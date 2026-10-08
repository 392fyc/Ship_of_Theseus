"""Validate v3 terrain capture preconditions while reusing the frozen v2 checks."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess

import claude_review_checks as checks
import validate_terrain_readability_capture_v2 as v2

V3_SCHEMA = "terrain-mask-capture/3"
V3_SOURCES = (
    "tests/claude_review/capture_terrain_readability_v3.gd",
    "tests/claude_review/validate_terrain_readability_capture_v3.py",
    "tests/claude_review/test_terrain_readability_capture_v3.py",
    "tests/claude_review/test_terrain_capture_input_routing_v3.gd",
)
SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")


def manager_hover_normalization_errors(state: dict) -> list[str]:
    errors: list[str] = []
    normalization = state.get("manager_hover_normalization", {})
    if normalization.get("input_method") != "TacticalManager.handle_pointer_hover":
        errors.append("v3 悬停归一化没有使用两个正式 TacticalManager 的既有接口")
    if normalization.get("target_grid_cell") != [-1, -1] or normalization.get("target_is_invalid_in_both_grids") is not True:
        errors.append("v3 未将同一无效棋盘格位置应用到两个正式管理器")
    for key in ("target_world_position", "main_viewport_position", "reconstruction_viewport_position"):
        value = normalization.get(key)
        if (not isinstance(value, list) or len(value) != 2
                or any(type(component) not in (int, float) for component in value)):
            errors.append(f"v3 缺少有效的 {key}")
    for phase in ("before", "after"):
        managers = normalization.get(phase, {})
        for role in ("main", "reconstruction"):
            record = managers.get(role, {})
            cell = record.get("hover_cell")
            if (type(record.get("has_hover")) is not bool or not isinstance(cell, list)
                    or len(cell) != 2 or any(type(part) is not int for part in cell)):
                errors.append(f"v3 缺少归一化{phase}的实际 {role} 管理器悬停状态")
    after = normalization.get("after", {})
    if after.get("main", {}).get("has_hover") is not False or after.get("reconstruction", {}).get("has_hover") is not False:
        errors.append("v3 归一化后两个实际管理器仍有悬停")
    if normalization.get("deferred_frees_waited") is not True or normalization.get("normalized") is not True:
        errors.append("v3 未等待延后释放完成或未记录归一化结果")
    return errors


def independent_highlight_errors(canvas: dict) -> list[str]:
    errors: list[str] = []
    comparison = canvas.get("independent_highlight_payload", {})
    if comparison.get("independently_generated") is not True:
        errors.append("v3 高亮没有证明由两个会话独立生成")
    if comparison.get("strict_sibling_order_and_class") is not True or comparison.get("sibling_classes_match") is not True:
        errors.append("v3 没有匹配独立高亮的兄弟顺序和节点类型")
    main_classes = comparison.get("main_sibling_classes")
    reconstruction_classes = comparison.get("reconstruction_sibling_classes")
    if (not isinstance(main_classes, list) or not isinstance(reconstruction_classes, list)
            or main_classes != reconstruction_classes):
        errors.append("v3 独立高亮兄弟类型顺序缺失或不同")
    main_hash = comparison.get("main_payload_sha256")
    reconstruction_hash = comparison.get("reconstruction_payload_sha256")
    if (not isinstance(main_hash, str) or not SHA256_RE.fullmatch(main_hash)
            or not isinstance(reconstruction_hash, str) or not SHA256_RE.fullmatch(reconstruction_hash)
            or main_hash != reconstruction_hash or comparison.get("payload_equal") is not True):
        errors.append("v3 独立高亮完整绘制状态摘要不相等")
    for key in ("main_nodes_compared", "reconstruction_nodes_compared"):
        if type(comparison.get(key)) is not int or comparison[key] <= 0:
            errors.append(f"v3 高亮没有比较有效的 {key}")
    for key in ("main_draw_payload_nodes_compared", "reconstruction_draw_payload_nodes_compared"):
        if type(comparison.get(key)) is not int or comparison[key] < 0:
            errors.append(f"v3 高亮缺少有效的 {key}")
    if comparison.get("main_nodes_compared") != comparison.get("reconstruction_nodes_compared"):
        errors.append("v3 独立高亮比较的节点数量不同")
    if comparison.get("main_draw_payload_nodes_compared") != comparison.get("reconstruction_draw_payload_nodes_compared"):
        errors.append("v3 独立高亮比较的绘制节点数量不同")
    if comparison.get("copied_to_reconstruction") is not False:
        errors.append("v3 不能复制主会话高亮来制造一致")
    if comparison.get("deferred_frees_waited") is not True:
        errors.append("v3 高亮比较前没有等待延后释放完成")
    return errors


def source_errors_v3(manifest: dict, source_root: Path) -> list[str]:
    errors: list[str] = []
    sources = manifest.get("sources", {})
    candidate_hashes = manifest.get("candidate", {}).get("source_sha256", {})
    for source in V3_SOURCES:
        resource = "res://" + source
        digest = sources.get(resource)
        if not isinstance(digest, str) or not SHA256_RE.fullmatch(digest):
            errors.append(f"v3 源码绑定摘要缺失或格式无效: {resource}")
            continue
        try:
            path = v2.v1.safe_child(source_root, source)
            actual = v2.v1.sha256(path)
            if actual != digest:
                errors.append(f"v3 源码绑定摘要不匹配: {resource}")
            if candidate_hashes.get(source) != actual:
                errors.append(f"v3 候选源码摘要缺失或不匹配: {source}")
        except (OSError, ValueError) as error:
            errors.append(f"v3 源码绑定无法读取 {resource}: {error}")
    return errors


def validate(manifest_path: Path, source_root: Path, expected_head: str) -> dict:
    data = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    result = v2.validate(manifest_path, source_root, expected_head)
    errors = [error for error in result.get("errors", []) if error != "采集 schema 不匹配"]
    if data.get("schema_version") != V3_SCHEMA:
        errors.append("采集 schema 不匹配")
    state = data.get("capture_state", {})
    errors += manager_hover_normalization_errors(state)
    canvas = state.get("canvas_state_synchronization", {})
    errors += independent_highlight_errors(canvas)
    errors += source_errors_v3(data, source_root)
    previous_root = checks.ROOT
    try:
        checks.ROOT = source_root
        c8_v3 = checks.c8_script(v2.v1.safe_child(source_root, V3_SOURCES[0]))
    finally:
        checks.ROOT = previous_root
    if not c8_v3.get("pass"):
        errors.append("v3 采集脚本未通过现行 C8 检查")
    result["schema_version"] = data.get("schema_version")
    result["capture_preconditions"] = "PASS" if not errors else "FAIL"
    result["errors"] = errors
    result["C8_source_v3"] = c8_v3
    result["measurement_status"] = "NOT_TESTED"
    result["art_acceptance"] = "NOT_TESTED"
    result["note"] = "v3 仅验证采集前置；真实像素、布局与素材仍须独立验收。"
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifests", type=Path, nargs="+")
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    local_head = subprocess.check_output(["git", "-C", str(args.source_root), "rev-parse", "HEAD"], text=True).strip()
    if local_head != args.candidate:
        parser.error("回读源码工作树 HEAD 与冻结候选不同")
    results: list[dict] = []
    for path in args.manifests:
        try:
            results.append(validate(path, args.source_root, args.candidate))
        except (OSError, ValueError, KeyError, TypeError) as error:
            results.append({"manifest": path.name, "capture_preconditions": "FAIL", "errors": [str(error)]})
    cases = [(tuple(result.get("case", {}).get("map_size", [])),
              tuple(result.get("case", {}).get("requested_resolution", []))) for result in results]
    required = {(size, resolution) for size in ((10, 10), (25, 25)) for resolution in v2.RESOLUTIONS}
    complete = len(cases) == 6 and set(cases) == required
    passed = complete and all(result.get("capture_preconditions") == "PASS" for result in results)
    output = {"schema_version": "terrain-capture-readback/3", "candidate_head": args.candidate,
              "six_case_coverage": complete, "capture_preconditions": "PASS" if passed else "FAIL",
              "art_acceptance": "NOT_TESTED", "cases": results}
    args.out.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"capture_preconditions": output["capture_preconditions"],
                      "six_case_coverage": complete, "art_acceptance": "NOT_TESTED"}, ensure_ascii=False))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
