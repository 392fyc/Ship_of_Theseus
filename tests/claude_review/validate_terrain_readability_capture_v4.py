"""Validate v4 terrain capture draw refresh and test-spawn evidence."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

V4_SCHEMA = "terrain-mask-capture/4"
V4_CASE_SCHEMA = "terrain-readability-capture-v4-cases/1"
V4_CASE_FILE = "tests/claude_review/terrain_readability_capture_v4_cases.json"
V4_SOURCES = (
    "tests/claude_review/capture_terrain_readability_v4.gd",
    "tests/claude_review/validate_terrain_readability_capture_v4.py",
    "tests/claude_review/test_terrain_readability_capture_v4.py",
    V4_CASE_FILE,
)
SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")
EXPECTED_RESOLUTIONS = [[1280, 720], [1920, 1080], [2560, 1440]]
EXPECTED_MAP_SIZES = {(10, 10), (25, 25)}
REQUIRED_DRAW_ROLES = {
    "main_board",
    "main_detail_layer",
    "reconstruction_board",
    "reconstruction_detail_layer",
}
RETAINED_SAMPLES = {"pillar@1.00,4.00", "rubble@3.12,2.08"}
CHANGED_POSITION_PATHS = ["enemy_units[0].position", "player_units[0].position"]


def _valid_digest(value: object) -> bool:
    return isinstance(value, str) and SHA256_RE.fullmatch(value) is not None


def _position(value: object) -> bool:
    return (isinstance(value, list) and len(value) == 2
            and all(type(component) is int for component in value))


def case_file_errors(data: dict) -> list[str]:
    errors: list[str] = []
    if data.get("schema_version") != V4_CASE_SCHEMA:
        errors.append("v4 用例 JSON schema 不匹配")
    if data.get("fixture") != "calibration_courtyard":
        errors.append("v4 用例没有绑定现有 courtyard 派生 fixture")
    if data.get("source_example") != "assets/prototype/battlefield_courtyard/terrain_examples.json#courtyard":
        errors.append("v4 用例 source courtyard 引用不匹配")
    override = data.get("capture_variant_override", {})
    if (override.get("cell_in_source_10x10") != [8, 7]
            or override.get("from") != "pillar"
            or override.get("to") != "ruined"
            or override.get("captured_instance_type") != "rubble"):
        errors.append("v4 用例未保留既有 8,7 派生与 rubble 分类")
    if data.get("resolutions") != EXPECTED_RESOLUTIONS:
        errors.append("v4 用例没有固定三档分辨率")
    cases = data.get("cases")
    indexed: dict[tuple[int, int], dict] = {}
    if not isinstance(cases, list):
        errors.append("v4 用例缺少地图尺寸安排列表")
        cases = []
    for case in cases:
        if not isinstance(case, dict):
            errors.append("v4 地图尺寸安排格式无效")
            continue
        size = case.get("map_size")
        if not _position(size) or size[0] != size[1]:
            errors.append("v4 地图尺寸必须是正方形整数边长")
            continue
        key = (size[0], size[1])
        if key in indexed:
            errors.append(f"v4 地图尺寸重复: {size}")
        indexed[key] = case
        player = case.get("player_unit_position")
        enemy = case.get("enemy_unit_position")
        for label, point in (("player", player), ("enemy", enemy)):
            if not _position(point):
                errors.append(f"{size[0]}x{size[1]} 缺少有效 {label} 出生格")
            elif not (0 <= point[0] < size[0] and 0 <= point[1] < size[1]):
                errors.append(f"{size[0]}x{size[1]} 的 {label} 出生格越界")
        if _position(player) and _position(enemy) and player == enemy:
            errors.append(f"{size[0]}x{size[1]} 的双方出生格重合")
    if set(indexed) != EXPECTED_MAP_SIZES:
        errors.append("v4 用例必须且只能覆盖 10x10 与 25x25")
    if [sample.get("stable_id") for sample in data.get("retained_sample_instances", [])
            if isinstance(sample, dict)] != ["pillar@1.00,4.00", "rubble@3.12,2.08"]:
        errors.append("v4 用例没有按原顺序保留石柱与碎石复测实例")
    contract = data.get("configuration_contract", {})
    if (contract.get("builder") != "TerrainBattleSession.configure_map -> TerrainBattleDefinition.build"
            or contract.get("apply_after_formal_build") is not True
            or contract.get("apply_before_entering_tree") is not True
            or contract.get("allowed_changed_paths") != CHANGED_POSITION_PATHS
            or contract.get("same_positions_for_all_resolutions_of_each_map_size") is not True
            or contract.get("unit_counts_classes_and_all_other_fields_preserved") is not True
            or contract.get("positions_must_be_distinct_passable_and_clear_of_prop_cells") is not True
            or contract.get("initial_fit_board_unchanged") is not True):
        errors.append("v4 用例位置覆写合同不完整")
    return errors


def spawn_configuration_errors(spawn: dict, case_data: dict,
                               expected_map_size: list[int]) -> list[str]:
    errors: list[str] = []
    if spawn.get("schema_version") != "terrain-readability-spawn-state/1":
        errors.append("v4 出生状态 schema 缺失")
    if spawn.get("map_size") != expected_map_size:
        errors.append("v4 出生状态地图尺寸与 manifest 不符")
    if spawn.get("case_file") != "res://" + V4_CASE_FILE:
        errors.append("v4 出生状态没有绑定版本化用例 JSON")
    if not _valid_digest(spawn.get("case_file_sha256")):
        errors.append("v4 出生状态缺少用例 JSON SHA256")
    expected = next((case for case in case_data.get("cases", [])
                     if isinstance(case, dict) and case.get("map_size") == expected_map_size), None)
    if expected is None:
        errors.append("v4 用例 JSON 没有对应地图尺寸")
        expected_positions = {}
    else:
        expected_positions = {
            "player": expected.get("player_unit_position"),
            "enemy": expected.get("enemy_unit_position"),
        }
    if spawn.get("expected_positions") != expected_positions:
        errors.append("v4 实际出生状态与版本化用例位置不符")
    for role in ("main", "reconstruction"):
        record = spawn.get(role, {})
        if not isinstance(record, dict):
            errors.append(f"v4 缺少 {role} 独立配置记录")
            continue
        for key in ("original_formal_configuration_sha256", "actual_formal_configuration_sha256"):
            if not _valid_digest(record.get(key)):
                errors.append(f"v4 {role} 缺少有效 {key}")
        if record.get("builder") != "TerrainBattleSession.configure_map -> TerrainBattleDefinition.build":
            errors.append(f"v4 {role} 没有使用正式 Definition.build")
        if record.get("applied_before_entering_tree") is not True:
            errors.append(f"v4 {role} 出生覆写没有在入树前应用")
        if record.get("changed_paths") != CHANGED_POSITION_PATHS:
            errors.append(f"v4 {role} 实际改动字段超出两个位置字段")
        if record.get("allowed_changed_paths") != CHANGED_POSITION_PATHS:
            errors.append(f"v4 {role} 允许改动字段记录不符")
        for flag in ("all_other_fields_equal", "unit_counts_preserved",
                     "class_ids_preserved", "position_fields_only"):
            if record.get(flag) is not True:
                errors.append(f"v4 {role} 未证明 {flag}")
        if record.get("desired_positions") != expected_positions:
            errors.append(f"v4 {role} desired_positions 与用例不符")
        actual = record.get("actual_positions", {})
        if actual != expected_positions:
            errors.append(f"v4 {role} 正式会话实际出生格与用例不符")
        if record.get("session_instance_id") is None:
            errors.append(f"v4 {role} 缺少独立正式 Session 实例标识")
    main = spawn.get("main", {})
    reconstruction = spawn.get("reconstruction", {})
    if main.get("session_instance_id") == reconstruction.get("session_instance_id"):
        errors.append("v4 main 与 reconstruction 共用了同一 Session 实例")
    if (main.get("original_formal_configuration_sha256")
            != reconstruction.get("original_formal_configuration_sha256")):
        errors.append("v4 两边正式 Definition.build 原始派生配置不同")
    if (main.get("actual_formal_configuration_sha256")
            != reconstruction.get("actual_formal_configuration_sha256")):
        errors.append("v4 两边独立正式配置在位置覆写后不同")
    for flag in ("positions_distinct", "positions_passable", "positions_avoid_prop_cells",
                 "manager_positions_match_config", "units_visible", "highlights_visible"):
        if spawn.get(flag) is not True:
            errors.append(f"v4 未证明实际出生与可见状态条件 {flag}")
    return errors


def draw_refresh_errors(state: dict, common_frame: dict | None = None) -> list[str]:
    errors: list[str] = []
    refresh = state.get("terrain_v4_draw_refresh", {})
    if not isinstance(refresh, dict):
        return ["v4 缺少冻结后的重绘诊断"]
    if refresh.get("request_method") != "CanvasItem.queue_redraw":
        errors.append("v4 没有记录 CanvasItem.queue_redraw 调用")
    nodes = refresh.get("nodes", {})
    if not isinstance(nodes, dict) or set(nodes) != REQUIRED_DRAW_ROLES:
        errors.append("v4 必须分别请求两边 BoardView 与 DetailLayer 重绘")
        nodes = {}
    for role in REQUIRED_DRAW_ROLES:
        node = nodes.get(role, {})
        if not isinstance(node, dict):
            errors.append(f"v4 缺少 {role} 重绘节点证据")
            continue
        if node.get("queue_redraw_called") is not True or node.get("visible_in_tree") is not True:
            errors.append(f"v4 {role} 没有记录实际可见节点的 queue_redraw 请求")
    if refresh.get("status") == "NOT_TESTED_HEADLESS":
        if refresh.get("headless_structure_only") is not True:
            errors.append("v4 headless 重绘状态标签不完整")
        if common_frame is not None:
            errors.append("headless 状态不得作为像素 capture manifest")
        return errors
    if refresh.get("status") != "PASS":
        errors.append("v4 冻结后真实重绘阶段没有通过")
    if refresh.get("headless_structure_only") is not False:
        errors.append("v4 像素采集不能标记为 headless")
    before = refresh.get("frame_post_draw_before_request")
    after = refresh.get("frame_post_draw_after_request")
    if type(before) is not int or type(after) is not int or after <= before:
        errors.append("v4 重绘请求前后缺少真实 frame_post_draw 帧推进证据")
    for role, node in nodes.items():
        events = node.get("draw_events", [])
        if not isinstance(events, list) or not events:
            errors.append(f"v4 {role} 没有实际 CanvasItem.draw 信号")
            continue
        for event in events:
            if (not isinstance(event, dict) or type(event.get("frames_drawn")) is not int
                    or type(before) is not int or type(after) is not int
                    or not before <= event["frames_drawn"] <= after):
                errors.append(f"v4 {role} draw 信号没有绑定到请求后的实际绘制帧")
            if not isinstance(event, dict):
                continue
            if event.get("draw_node_visible_in_tree") is not True:
                errors.append(f"v4 {role} draw 信号没有记录节点当时的可见状态")
            if type(event.get("time")) not in (int, float):
                errors.append(f"v4 {role} draw 信号缺少当时 BoardView._time")
            for key in ("draw_input_sha256", "terrain_configuration_sha256",
                        "water_configuration_sha256", "profile_sha256",
                        "material_inputs_sha256", "mesh_inputs_sha256"):
                if not _valid_digest(event.get(key)):
                    errors.append(f"v4 {role} draw 信号缺少当时输入摘要 {key}")
            if event.get("draw_input_sha256") != node.get("draw_input_sha256"):
                errors.append(f"v4 {role} draw 信号输入与实际 BoardView 状态快照不一致")
    if common_frame is not None:
        frame_id = common_frame.get("frame_id")
        binding = common_frame.get("terrain_v4_state_snapshot", {})
        if type(frame_id) is not int or frame_id <= 0:
            errors.append("v4 同帧图像缺少有效 frame_id")
        if binding.get("callback") != "RenderingServer.frame_post_draw":
            errors.append("v4 图像与状态没有绑定 RenderingServer.frame_post_draw")
        if binding.get("same_frame") is not True or binding.get("frame_id") != frame_id:
            errors.append("v4 图像与状态快照不是同一个 frame_post_draw")
        if binding.get("image_count") != 12 or binding.get("readback_awaits_between_images") is not False:
            errors.append("v4 12 图与状态必须来自同一个 frame_post_draw 且图间无 await")
        if binding.get("board_state_snapshot_captured") is not True:
            errors.append("v4 同帧快照缺少两边 BoardView 输入状态")
        if type(after) is int and after >= frame_id:
            errors.append("v4 重绘事件帧没有早于后续同帧图像采集")
    return errors


def target_coverage_errors(state: dict) -> list[str]:
    errors: list[str] = []
    coverage = state.get("terrain_v4_retained_sample_coverage", {})
    if not isinstance(coverage, dict) or set(coverage) != RETAINED_SAMPLES:
        return ["v4 必须保留两个既有石柱/碎石实例的覆盖状态"]
    for stable_id in RETAINED_SAMPLES:
        record = coverage[stable_id]
        if record.get("instance_retained") is not True:
            errors.append(f"v4 删除或漏记原样本分母: {stable_id}")
        if record.get("covered") is not False or record.get("range_covered") is not False:
            errors.append(f"v4 测试出生仍覆盖原样本或其正式范围: {stable_id}")
        if record.get("covered_source") != "CourtyardBoardView._process unit and hover bounds":
            errors.append(f"v4 {stable_id} 缺少实际单位/悬停覆盖来源")
        if record.get("range_covered_source") != "CourtyardBoardView._process actual HighlightLayer polygon centers":
            errors.append(f"v4 {stable_id} 缺少实际正式高亮范围来源")
        if record.get("alpha_mutated_by_v4") is not False:
            errors.append(f"v4 {stable_id} alpha 被采集器直接修改")
        if record.get("alpha_matches_source_state") is not True:
            errors.append(f"v4 {stable_id} 实际 alpha 与来源状态不一致")
        if record.get("alpha_matches_coverage_target") is not True:
            errors.append(f"v4 {stable_id} 实际 alpha 与正式覆盖条件结果不一致")
        for key in ("source_modulate_alpha", "actual_modulate_alpha", "target_alpha"):
            value = record.get(key)
            if type(value) not in (int, float) or not 0.0 <= float(value) <= 1.0:
                errors.append(f"v4 {stable_id} 缺少有效 {key}")
    return errors


def v4_source_errors(manifest: dict, source_root: Path) -> list[str]:
    errors: list[str] = []
    sources = manifest.get("sources", {})
    candidate_hashes = manifest.get("candidate", {}).get("source_sha256", {})
    for source in V4_SOURCES:
        resource = "res://" + source
        digest = sources.get(resource)
        if not _valid_digest(digest):
            errors.append(f"v4 源码绑定摘要缺失或格式无效: {resource}")
            continue
        try:
            root = source_root.resolve()
            path = (root / source).resolve()
            if not path.is_relative_to(root):
                raise ValueError("source path escapes the repository")
            actual = hashlib.sha256(path.read_bytes()).hexdigest()
            if actual != digest:
                errors.append(f"v4 源码绑定摘要不匹配: {resource}")
            if candidate_hashes.get(source) != actual:
                errors.append(f"v4 候选源码摘要缺失或不匹配: {source}")
        except (OSError, ValueError) as error:
            errors.append(f"v4 源码绑定无法读取 {resource}: {error}")
    return errors


def validate(manifest_path: Path, source_root: Path, expected_head: str,
             case_data: dict | None = None) -> dict:
    import validate_terrain_readability_capture_v3 as v3

    data = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    if case_data is None:
        case_data = json.loads((source_root / V4_CASE_FILE).read_text(encoding="utf-8-sig"))
    result = v3.validate(manifest_path, source_root, expected_head)
    errors = [error for error in result.get("errors", []) if error != "采集 schema 不匹配"]
    errors += case_file_errors(case_data)
    if data.get("schema_version") != V4_SCHEMA:
        errors.append("采集 schema 不匹配")
    case = data.get("case", {})
    map_size = case.get("map_size", [])
    capture_state = data.get("capture_state", {})
    spawn = capture_state.get("terrain_v4_spawn_configuration", {})
    errors += spawn_configuration_errors(spawn, case_data, map_size)
    errors += target_coverage_errors(capture_state)
    errors += draw_refresh_errors(capture_state, data.get("common_frame", {}))
    board_inputs = capture_state.get("terrain_v4_board_inputs", {})
    if set(board_inputs) != {"main", "reconstruction"}:
        errors.append("v4 缺少两边 BoardView 实际输入记录")
    for role in ("main", "reconstruction"):
        board = board_inputs.get(role, {})
        if not isinstance(board, dict):
            errors.append(f"v4 缺少 {role} BoardView 输入状态")
            continue
        for key in ("terrain_configuration_sha256", "water_configuration_sha256", "profile_sha256",
                    "material_inputs_sha256", "mesh_inputs_sha256", "draw_input_sha256"):
            if not _valid_digest(board.get(key)):
                errors.append(f"v4 {role} BoardView 缺少有效 {key}")
        time_value = board.get("time")
        if type(time_value) not in (int, float):
            errors.append(f"v4 {role} BoardView 没有记录实际 _time")
    errors += v4_source_errors(data, source_root)
    result["schema_version"] = data.get("schema_version")
    result["capture_preconditions"] = "PASS" if not errors else "FAIL"
    result["errors"] = errors
    result["measurement_status"] = "NOT_TESTED"
    result["art_acceptance"] = "NOT_TESTED"
    result["note"] = "v4 只验证采集状态与同帧前置；像素测量和美术接受仍未测试。"
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifests", type=Path, nargs="+")
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    source_root = args.source_root.resolve()
    local_head = subprocess.check_output(
        ["git", "-C", str(source_root), "rev-parse", "HEAD"], text=True
    ).strip()
    if local_head != args.candidate:
        parser.error("回读源码工作树 HEAD 与冻结候选不同")
    case_data = json.loads((source_root / V4_CASE_FILE).read_text(encoding="utf-8"))
    results: list[dict] = []
    for path in args.manifests:
        try:
            results.append(validate(path, source_root, args.candidate, case_data))
        except (OSError, ValueError, KeyError, TypeError) as error:
            results.append({"manifest": path.name, "capture_preconditions": "FAIL", "errors": [str(error)]})
    cases = [(tuple(result.get("case", {}).get("map_size", [])),
              tuple(result.get("case", {}).get("requested_resolution", []))) for result in results]
    expected = {(size, resolution) for size in EXPECTED_MAP_SIZES
                for resolution in map(tuple, EXPECTED_RESOLUTIONS)}
    complete = len(cases) == 6 and set(cases) == expected
    passed = complete and all(result.get("capture_preconditions") == "PASS" for result in results)
    output = {"schema_version": "terrain-capture-readback/4", "candidate_head": args.candidate,
              "six_case_coverage": complete, "capture_preconditions": "PASS" if passed else "FAIL",
              "measurement_status": "NOT_TESTED", "art_acceptance": "NOT_TESTED", "cases": results}
    args.out.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"capture_preconditions": output["capture_preconditions"],
                      "six_case_coverage": complete, "measurement_status": "NOT_TESTED",
                      "art_acceptance": "NOT_TESTED"}, ensure_ascii=False))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
