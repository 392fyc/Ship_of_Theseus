"""Validate V6 native-pixel-center mask alignment and retain every V5 capture gate."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess

import validate_terrain_readability_capture_v4 as v4
import validate_terrain_readability_capture_v5 as v5

V6_SCHEMA = "terrain-mask-capture/6"
V6_MASK_SCHEMA = "terrain-readability-mask-quantization-v6/1"
V6_MASK_ALGORITHM = "native-pixel-center-half-open-cell-alignment-v1"
V6_SOURCES = (
    "tests/claude_review/capture_terrain_readability_v6.gd",
    "tests/claude_review/validate_terrain_readability_capture_v6.py",
    "tests/claude_review/test_terrain_readability_capture_v6.py",
    "dev_doc/ui-art-research/terrain-readability/capture-v6-task.md",
)
AXIS_EPSILON = 1e-6
FLOAT_EPSILON = 1e-3


def _finite_vector(value: object, length: int) -> bool:
    return (isinstance(value, list) and len(value) == length
            and all(type(item) in (int, float) and math.isfinite(item) for item in value))


def _close_vectors(left: object, right: object, tolerance: float = FLOAT_EPSILON) -> bool:
    return (_finite_vector(left, len(right) if isinstance(right, list) else -1)
            and isinstance(right, list)
            and all(math.isclose(float(a), float(b), abs_tol=tolerance, rel_tol=0)
                    for a, b in zip(left, right)))


def _rect_intersection(rect: list[float], visible: list[float]) -> list[float]:
    x0 = max(rect[0], visible[0])
    y0 = max(rect[1], visible[1])
    x1 = min(rect[0] + rect[2], visible[0] + visible[2])
    y1 = min(rect[1] + rect[3], visible[1] + visible[3])
    return [x0, y0, max(0.0, x1 - x0), max(0.0, y1 - y0)]


def quantize_rect(rect: list[float], transform: list[float]) -> dict:
    """Return the cell envelope whose native pixel centers satisfy a half-open rect."""
    if not _finite_vector(rect, 4) or not _finite_vector(transform, 6):
        return {"status": "INVALID_INPUT"}
    x, y, width, height = map(float, rect)
    xx, xy, yx, yy, tx, ty = map(float, transform)
    if width <= 0 or height <= 0:
        return {
            "status": "CLIPPED_EMPTY",
            "native_nominal_bounds": [],
            "native_pixel_cell_bounds": [],
            "quantized_draw_rect": [0.0, 0.0, 0.0, 0.0],
        }
    if (xx <= 0 or yy <= 0 or abs(xy) > AXIS_EPSILON or abs(yx) > AXIS_EPSILON):
        return {"status": "UNSUPPORTED_FINAL_TRANSFORM"}

    corners = (
        (xx * px + yx * py + tx, xy * px + yy * py + ty)
        for px, py in ((x, y), (x + width, y), (x, y + height), (x + width, y + height))
    )
    mapped = list(corners)
    native_left = min(point[0] for point in mapped)
    native_top = min(point[1] for point in mapped)
    native_right = max(point[0] for point in mapped)
    native_bottom = max(point[1] for point in mapped)
    cell_left = math.ceil(native_left - 0.5)
    cell_top = math.ceil(native_top - 0.5)
    cell_right = math.ceil(native_right - 0.5)
    cell_bottom = math.ceil(native_bottom - 0.5)
    native_bounds = [native_left, native_top, native_right, native_bottom]
    cell_bounds = [cell_left, cell_top, cell_right, cell_bottom]
    if cell_right <= cell_left or cell_bottom <= cell_top:
        return {
            "status": "NO_NATIVE_PIXEL_CENTERS",
            "native_nominal_bounds": native_bounds,
            "native_pixel_cell_bounds": cell_bounds,
            "quantized_draw_rect": [0.0, 0.0, 0.0, 0.0],
        }
    draw_x = (cell_left - tx) / xx
    draw_y = (cell_top - ty) / yy
    draw_right = (cell_right - tx) / xx
    draw_bottom = (cell_bottom - ty) / yy
    return {
        "status": "QUANTIZED",
        "native_nominal_bounds": native_bounds,
        "native_pixel_cell_bounds": cell_bounds,
        "quantized_draw_rect": [draw_x, draw_y, draw_right - draw_x, draw_bottom - draw_y],
    }


def v6_source_errors(manifest: dict, source_root: Path) -> list[str]:
    errors: list[str] = []
    sources = manifest.get("sources", {})
    candidate = manifest.get("candidate", {})
    candidate_hashes = candidate.get("source_sha256", {}) if isinstance(candidate, dict) else {}
    if not isinstance(sources, dict):
        sources = {}
        errors.append("v6 sources 摘要格式无效")
    if not isinstance(candidate_hashes, dict):
        candidate_hashes = {}
        errors.append("v6 candidate.source_sha256 摘要格式无效")
    for relative in V6_SOURCES:
        digest = sources.get("res://" + relative)
        try:
            root = source_root.resolve()
            path = (root / relative).resolve()
            if not path.is_relative_to(root):
                raise ValueError("source path escapes the repository")
            actual = hashlib.sha256(path.read_bytes()).hexdigest()
            if digest != actual or candidate_hashes.get(relative) != actual:
                errors.append(f"v6 候选源码摘要与当前工作树不一致: {relative}")
        except (OSError, ValueError) as error:
            errors.append(f"v6 源码绑定无法读取 {relative}: {error}")
    return errors


def mask_quantization_errors(manifest: dict) -> list[str]:
    errors: list[str] = []
    exclusions = manifest.get("exclusions", {})
    if not isinstance(exclusions, dict):
        return ["v6 缺少 exclusions 遮罩记录"]
    quantization = exclusions.get("mask_draw_quantization", {})
    if not isinstance(quantization, dict):
        return ["v6 缺少遮罩量化记录"]
    if quantization.get("schema_version") != V6_MASK_SCHEMA:
        errors.append("v6 遮罩量化 schema 不匹配")
    if quantization.get("status") != "CAPTURED":
        errors.append("v6 遮罩量化状态不是 CAPTURED")
    if quantization.get("algorithm") != V6_MASK_ALGORITHM:
        errors.append("v6 遮罩量化算法标识不匹配")
    if quantization.get("pixel_center_rule") != (
            "Native pixel centers are index + 0.5; logical source rectangles are half-open; "
            "align only the native cells whose centers satisfy the original source rectangle."):
        errors.append("v6 遮罩量化没有声明冻结的像素中心和半开矩形规则")
    if quantization.get("source_bounds_are_unchanged") is not True:
        errors.append("v6 必须保留源 bounds 并仅修正绘制边界")
    if quantization.get("source_validator") != (
            "tests/claude_review/validate_terrain_readability_capture_v2.py::_bound_coverage"):
        errors.append("v6 没有引用冻结的像素中心覆盖规则来源")
    if quantization.get("bounds_coordinate_space") != (
            "main Window visible logical viewport before the viewport stretch transform"):
        errors.append("v6 遮罩量化逻辑坐标空间不匹配")
    if quantization.get("final_transform_source") != "viewports.main.final_transform":
        errors.append("v6 没有绑定主视口实际 final_transform")
    if quantization.get("transform_consistent_across_draw_calls") is not True:
        errors.append("v6 遮罩绘制期间 final_transform 不一致")

    viewports = manifest.get("viewports", {})
    main_viewport = viewports.get("main", {}) if isinstance(viewports, dict) else {}
    transform = main_viewport.get("final_transform", []) if isinstance(main_viewport, dict) else []
    if not _finite_vector(transform, 6):
        errors.append("v6 主视口缺少有效 final_transform")
        transform = []
    recorded_transform = quantization.get("final_transform", [])
    if transform and not _close_vectors(recorded_transform, transform):
        errors.append("v6 量化使用的 final_transform 与主视口实际记录不一致")

    records = quantization.get("records", [])
    if not isinstance(records, list) or not records:
        return errors + ["v6 缺少每次 exclusions mask 绘制的原始 bounds 记录"]
    if quantization.get("draw_call_count") != len(records):
        errors.append("v6 遮罩绘制记录数量与 draw_call_count 不一致")

    visible = main_viewport.get("visible_rect", []) if isinstance(main_viewport, dict) else []
    if not _finite_vector(visible, 4):
        errors.append("v6 主视口缺少有效 visible_rect")
        return errors

    expected: list[tuple[str, list[float]]] = []
    unit_records = exclusions.get("unit_screen_bounds", [])
    ui_records = exclusions.get("drawable_ui_control_bound_records", [])
    if isinstance(unit_records, list):
        for item in unit_records:
            rect = item.get("rect") if isinstance(item, dict) else None
            if _finite_vector(rect, 4):
                expected.append(("UnitConservativeBounds", list(map(float, rect))))
    if isinstance(ui_records, list):
        for item in ui_records:
            rect = item.get("rect") if isinstance(item, dict) else None
            if (_finite_vector(rect, 4) and float(rect[2]) > 0 and float(rect[3]) > 0):
                expected.append(("DrawableUIBounds", list(map(float, rect))))
    if len(expected) != len(records):
        errors.append("v6 原始遮罩绘制记录未一一对应既有单位/UI bounds")

    for index, record in enumerate(records):
        if not isinstance(record, dict):
            errors.append(f"v6 遮罩记录[{index}] 格式无效")
            continue
        if index >= len(expected):
            continue
        expected_node, expected_rect = expected[index]
        if record.get("node_name") != expected_node:
            errors.append(f"v6 遮罩记录[{index}] node_name 与源 bounds 类别不一致")
        nominal = record.get("nominal_rect")
        if not _close_vectors(nominal, expected_rect):
            errors.append(f"v6 遮罩记录[{index}] 改写了原始 nominal bounds")
        clipped = _rect_intersection(expected_rect, list(map(float, visible)))
        if not _close_vectors(record.get("logical_clipped_rect"), clipped):
            errors.append(f"v6 遮罩记录[{index}] logical clipping 与主视口边界不一致")
        if not _close_vectors(record.get("final_transform"), transform):
            errors.append(f"v6 遮罩记录[{index}] 没有保留实际原始 final_transform")
        expected_geometry = quantize_rect(clipped, list(map(float, transform)))
        for key in ("native_nominal_bounds", "native_pixel_cell_bounds", "quantized_draw_rect"):
            expected_value = expected_geometry.get(key, [])
            actual_value = record.get(key, [])
            if key == "native_pixel_cell_bounds":
                if actual_value != expected_value:
                    errors.append(f"v6 遮罩记录[{index}] native pixel-cell 边界重算不一致")
            elif not _close_vectors(actual_value, expected_value):
                errors.append(f"v6 遮罩记录[{index}] {key} 与实际 final_transform 重算不一致")
        if record.get("quantization_status") != expected_geometry.get("status"):
            errors.append(f"v6 遮罩记录[{index}] quantization_status 重算不一致")
        should_create = expected_geometry.get("status") == "QUANTIZED"
        if record.get("draw_created") is not should_create:
            errors.append(f"v6 遮罩记录[{index}] draw_created 与量化几何不一致")
        if expected_geometry.get("status") in ("UNSUPPORTED_FINAL_TRANSFORM", "NO_NATIVE_PIXEL_CENTERS"):
            errors.append(f"v6 遮罩记录[{index}] 没有可用的原生像素中心量化结果")
    return errors


def validate(manifest_path: Path, source_root: Path, expected_head: str,
             case_data: dict | None = None) -> dict:
    data = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    original_schema = v5.V5_SCHEMA
    v5.V5_SCHEMA = V6_SCHEMA
    try:
        result = v5.validate(manifest_path, source_root, expected_head, case_data)
    finally:
        v5.V5_SCHEMA = original_schema
    errors = list(result.get("errors", []))
    if data.get("schema_version") != V6_SCHEMA and "采集 schema 不匹配" not in errors:
        errors.append("采集 schema 不匹配")
    errors += mask_quantization_errors(data)
    errors += v6_source_errors(data, source_root)
    result["schema_version"] = data.get("schema_version")
    result["capture_preconditions"] = "PASS" if not errors else "FAIL"
    result["errors"] = errors
    result["measurement_status"] = "NOT_TESTED"
    result["art_acceptance"] = "NOT_TESTED"
    result["note"] = "v6 保留全部 v5/v4 像素与时序前置，仅为 exclusions overlay 记录并校验按冻结像素中心规则量化后的绘制边界；实际像素结果仍须由原生图像和冻结门槛验证。"
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifests", type=Path, nargs="+")
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    source_root = args.source_root.resolve()
    try:
        head = subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=source_root,
            capture_output=True, text=True, encoding="utf-8", timeout=15,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        parser.error(f"无法在源码工作树读取 Git HEAD: {error}")
    if head.returncode != 0 or head.stdout.strip() != args.candidate:
        parser.error("源码工作树 HEAD 与传入候选不同，或 Git HEAD 读取失败")
    case_data = json.loads((source_root / v4.V4_CASE_FILE).read_text(encoding="utf-8"))
    results: list[dict] = []
    for path in args.manifests:
        try:
            results.append(validate(path, source_root, args.candidate, case_data))
        except (OSError, ValueError, KeyError, TypeError) as error:
            results.append({"manifest": path.name, "capture_preconditions": "FAIL", "errors": [str(error)]})
    cases = [(tuple(result.get("case", {}).get("map_size", [])),
              tuple(result.get("case", {}).get("requested_resolution", []))) for result in results]
    expected = {(size, resolution) for size in v4.EXPECTED_MAP_SIZES
                for resolution in map(tuple, v4.EXPECTED_RESOLUTIONS)}
    complete = len(cases) == 6 and set(cases) == expected
    passed = complete and all(result.get("capture_preconditions") == "PASS" for result in results)
    output = {
        "schema_version": "terrain-capture-readback/6",
        "candidate_head": args.candidate,
        "six_case_coverage": complete,
        "capture_preconditions": "PASS" if passed else "FAIL",
        "measurement_status": "NOT_TESTED",
        "art_acceptance": "NOT_TESTED",
        "cases": results,
    }
    args.out.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "capture_preconditions": output["capture_preconditions"],
        "six_case_coverage": complete,
        "measurement_status": "NOT_TESTED",
        "art_acceptance": "NOT_TESTED",
    }, ensure_ascii=False))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
