"""Validate v2 terrain capture preconditions; a pass is not an art approval."""
from __future__ import annotations

import argparse
import hashlib
from io import BytesIO
import json
import math
from pathlib import Path
import re
import subprocess

import numpy as np
from PIL import Image

import claude_review_checks as checks
import validate_terrain_readability_capture as v1

ROLES = v1.ROLES
RESOLUTIONS = v1.RESOLUTIONS
KINDS = v1.KINDS
V1_SCRIPT = "tests/claude_review/capture_terrain_readability.gd"
V2_SCRIPT = "tests/claude_review/capture_terrain_readability_v2.gd"
V2_SOURCES = (
    V1_SCRIPT,
    V2_SCRIPT,
    "tests/claude_review/validate_terrain_readability_capture_v2.py",
    "tests/claude_review/test_terrain_readability_capture_v2.py",
)
PORTRAIT_CAPTURE_GROUP = "portrait-hud"


def _pair(value: object, name: str) -> list[int] | None:
    if not isinstance(value, list) or len(value) != 2 or any(type(v) is not int for v in value):
        return None
    return value


def _finite_vector(value: object, length: int) -> bool:
    return (isinstance(value, list) and len(value) == length
            and all(type(v) in (int, float) and math.isfinite(v) for v in value))


def capture_state_errors(state: dict, map_size: list[int]) -> list[str]:
    errors: list[str] = []
    if state.get("headless_structure_only") is not False:
        errors.append("像素采集状态不能是 headless-only")
    if state.get("state_source") != "explicit capture override copied from the main validated session":
        errors.append("采集状态来源不是显式主会话状态复制")
    pointer = state.get("pointer", {})
    requested = pointer.get("requested_logical_position")
    actual = pointer.get("actual_logical_position")
    if not _finite_vector(requested, 2) or not _finite_vector(actual, 2):
        errors.append("缺少请求与实际逻辑鼠标坐标")
    if pointer.get("physical_input_used_as_state_authority") is not False:
        errors.append("采集状态不应依赖物理鼠标位置")
    if pointer.get("reconstruction_pointer_used") is not False:
        errors.append("重建视口不能依赖鼠标命中测试")
    for label, value in (("请求", pointer.get("requested_grid_cell")),
                         ("实际", pointer.get("actual_grid_cell"))):
        cell = _pair(value, label)
        if cell is None:
            errors.append(f"缺少{label}逻辑坐标对应的地形格")
        elif 0 <= cell[0] < map_size[0] and 0 <= cell[1] < map_size[1]:
            errors.append(f"{label}指针位置落在地形范围内")
    hover = state.get("hover", {})
    no_hover = [-1, -1]
    if hover.get("requested_cell") != no_hover or hover.get("main_cell") != no_hover or hover.get("reconstruction_cell") != no_hover:
        errors.append("主会话与重建会话没有使用同一个无悬停格")
    for key in ("main_tooltip", "reconstruction_tooltip"):
        tooltip = hover.get(key, {})
        if tooltip.get("available") is not True or tooltip.get("visible") is not False or tooltip.get("visible_in_tree") is not False:
            errors.append(f"{key} 未显式隐藏")
    if hover.get("main_gui_hovered_control_observation") != "":
        errors.append("窗口逻辑坐标仍命中 UI 控件")
    if hover.get("reconstruction_gui_hit_test_used") is not False:
        errors.append("重建会话不能以 SubViewport GUI 命中作为状态来源")
    context = state.get("unit_highlight_context", {})
    if context.get("hover_cell") != no_hover or context.get("copied_to_reconstruction") is not True:
        errors.append("单位/高亮上下文没有连同无悬停状态显式复制")
    units = context.get("units")
    highlights = context.get("highlights")
    if (not isinstance(units, list) or context.get("unit_count") != len(units)
            or not isinstance(highlights, list) or context.get("highlight_count") != len(highlights)):
        errors.append("单位或高亮上下文数量与记录不一致")
    props = state.get("prop_synchronization", {})
    if (props.get("includes_shrub_and_relief") is not True
            or props.get("property_order_copied_from_main") is not True
            or type(props.get("main_prop_count")) is not int
            or props.get("main_prop_count") <= 0
            or props.get("main_prop_count") != props.get("reconstruction_prop_count")):
        errors.append("完整 _props 清单、顺序或灌木/relief 状态没有同步")
    canvas = state.get("canvas_state_synchronization", {})
    if type(canvas.get("matched_canvas_items")) is not int or canvas.get("matched_canvas_items") <= 0:
        errors.append("没有同步 CanvasItem 动态状态")
    if (not str(canvas.get("terrain_branch", "")).startswith("independently generated from the same validated map")
            or type(canvas.get("terrain_draw_nodes_verified")) is not int
            or canvas.get("terrain_draw_nodes_verified") <= 0
            or type(canvas.get("copied_draw_payload_nodes")) is not int
            or canvas.get("copied_draw_payload_nodes") <= 0
            or type(canvas.get("sibling_index_class_matches")) is not int
            or canvas.get("sibling_index_class_matches") < 0
            or type(canvas.get("highlight_shapes_copied")) is not int
            or canvas.get("highlight_shapes_copied") < 0):
        errors.append("自动名兄弟节点、独立生成地形负载或动态高亮同步证据缺失")
    if canvas.get("independent_state_calculation_tested") is not False:
        errors.append("不能声称独立状态计算已经受测")
    freeze = state.get("freeze", {})
    if ("both formal TerrainBattleSession roots" not in freeze.get("scope", "")
            or type(freeze.get("main_frozen_nodes")) is not int
            or type(freeze.get("reconstruction_frozen_nodes")) is not int
            or freeze.get("main_frozen_nodes") <= 0
            or freeze.get("reconstruction_frozen_nodes") <= 0
            or freeze.get("total_frozen_nodes") != freeze.get("main_frozen_nodes") + freeze.get("reconstruction_frozen_nodes")):
        errors.append("会话递归冻结范围或覆盖数量不完整")
    return errors


def viewport_errors_v2(viewports: dict, requested_size: list[int]) -> list[str]:
    """Keep raw PNG dimensions native while validating Window Texture's reported mapping."""
    errors: list[str] = []
    main = viewports.get("main", {})
    if not isinstance(main, dict):
        return ["缺少 Window 主视口记录"]
    main_transform = main.get("stretch_transform")
    main_scale = main.get("stretch_scale")
    if main.get("viewport_kind") != "Window" or main.get("window_size") != requested_size:
        errors.append("主视口未记录所请求的 Window 物理尺寸")
    if not _finite_vector(main_transform, 6) or not _finite_vector(main_scale, 2):
        errors.append("Window stretch transform 或 scale 缺失")
    elif any(v <= 0 for v in main_scale):
        errors.append("Window stretch scale 必须为正数")
    else:
        basis_scale = [math.hypot(main_transform[0], main_transform[1]),
                       math.hypot(main_transform[2], main_transform[3])]
        if not np.allclose(basis_scale, main_scale, atol=1e-6, rtol=0):
            errors.append("Window stretch scale 与 transform basis 不符")
        expected_window_report = [math.ceil(requested_size[i] * main_scale[i]) for i in range(2)]
        if main.get("texture_reported_size") != expected_window_report:
            errors.append("Window Texture reported size 不符合物理尺寸乘 stretch scale")
    for role in sorted(ROLES):
        viewport = viewports.get(role, {})
        if not isinstance(viewport, dict):
            errors.append(f"{role}: 缺少 viewport 记录")
            continue
        expected_report = (main.get("texture_reported_size") if role == "main" else requested_size)
        if viewport.get("size") != requested_size:
            errors.append(f"{role}: viewport physical size 不匹配")
        if viewport.get("texture_reported_size") != expected_report or viewport.get("texture_size") != expected_report:
            errors.append(f"{role}: Texture 报告尺寸与 viewport API 规则不符")
        if viewport.get("native_size") != requested_size or viewport.get("image_size") != requested_size:
            errors.append(f"{role}: Image raw native_size 必须等于请求尺寸")
        if role != "main" and (viewport.get("viewport_kind") != "SubViewport"
                                or viewport.get("window_size") != []):
            errors.append(f"{role}: 辅助视口应记录为 SubViewport")
        for field, length in (("canvas_transform", 6), ("final_transform", 6), ("visible_rect", 4),
                              ("stretch_transform", 6), ("stretch_scale", 2)):
            value = viewport.get(field)
            if not _finite_vector(value, length):
                errors.append(f"{role}: {field} 缺失或无效")
                continue
            if role != "main" and field in ("canvas_transform", "final_transform", "visible_rect"):
                reference = main.get(field)
                if _finite_vector(reference, length) and not np.allclose(value, reference, atol=1e-6, rtol=0):
                    errors.append(f"{role}: {field} 与主视口映射不一致")
    return errors


def source_errors_v2(manifest: dict, source_root: Path, expected_head: str) -> list[str]:
    errors = v1.source_errors(manifest, source_root, expected_head)
    sources = manifest.get("sources", {})
    candidate_hashes = manifest.get("candidate", {}).get("source_sha256", {})
    for source in V2_SOURCES:
        resource = "res://" + source
        if resource not in sources:
            errors.append(f"源码绑定缺少 {resource}")
            continue
        if not re.fullmatch(r"[0-9a-f]{64}", str(sources[resource])):
            errors.append(f"源码摘要格式无效: {resource}")
        try:
            path = v1.safe_child(source_root, source)
            if v1.sha256(path) != sources[resource]:
                errors.append(f"源码绑定摘要不匹配: {resource}")
        except (OSError, ValueError) as error:
            errors.append(f"源码绑定无法读取 {resource}: {error}")
    for source in (V1_SCRIPT, V2_SCRIPT):
        digest = candidate_hashes.get(source)
        try:
            if not re.fullmatch(r"[0-9a-f]{64}", str(digest)) or v1.sha256(v1.safe_child(source_root, source)) != digest:
                errors.append(f"候选源码摘要缺少或不匹配: {source}")
        except (OSError, ValueError):
            errors.append(f"候选源码无法读取: {source}")
    return errors


def _rect_intersection(rect: list[float], visible: list[float]) -> list[float]:
    x0 = max(rect[0], visible[0])
    y0 = max(rect[1], visible[1])
    x1 = min(rect[0] + rect[2], visible[0] + visible[2])
    y1 = min(rect[1] + rect[3], visible[1] + visible[3])
    return [x0, y0, max(0.0, x1 - x0), max(0.0, y1 - y0)]


def _bound_coverage(alpha: np.ndarray, rect: list[float], transform: list[float]) -> tuple[int, int]:
    """Count native pixel centers inside a logical half-open rect and those lacking alpha."""
    x, y, rect_width, rect_height = map(float, rect)
    if rect_width <= 0 or rect_height <= 0:
        return 0, 0
    xx, xy, yx, yy, tx, ty = map(float, transform)
    determinant = xx * yy - xy * yx
    if not math.isfinite(determinant) or abs(determinant) <= 1e-12:
        return 0, 0

    corners = (
        (x, y), (x + rect_width, y),
        (x, y + rect_height), (x + rect_width, y + rect_height),
    )
    mapped = [(xx * px + yx * py + tx, xy * px + yy * py + ty) for px, py in corners]
    image_height, image_width = alpha.shape
    left = max(0, math.floor(min(point[0] for point in mapped)))
    top = max(0, math.floor(min(point[1] for point in mapped)))
    right = min(image_width, math.ceil(max(point[0] for point in mapped)))
    bottom = min(image_height, math.ceil(max(point[1] for point in mapped)))
    if right <= left or bottom <= top:
        return 0, 0

    pixel_x = np.arange(left, right, dtype=np.float64)[None, :] + 0.5
    pixel_y = np.arange(top, bottom, dtype=np.float64)[:, None] + 0.5
    dx, dy = pixel_x - tx, pixel_y - ty
    logical_x = (yy * dx - yx * dy) / determinant
    logical_y = (-xy * dx + xx * dy) / determinant
    inside = ((logical_x >= x) & (logical_x < x + rect_width)
              & (logical_y >= y) & (logical_y < y + rect_height))
    required = int(np.count_nonzero(inside))
    missing = int(np.count_nonzero(inside & (alpha[top:bottom, left:right] <= 127)))
    return required, missing


def _bounds_coverage_errors(alpha: np.ndarray, bounds: list[list[float]], transform: list[float], label: str) -> list[str]:
    errors: list[str] = []
    required_total = 0
    missing_total = 0
    for index, rect in enumerate(bounds):
        required, missing = _bound_coverage(alpha, rect, transform)
        if required == 0:
            errors.append(f"{label} bounds[{index}] 没有映射到任何原生像素中心")
        required_total += required
        missing_total += missing
    if required_total == 0:
        errors.append(f"exclusions PNG 没有覆盖任何 {label} bounds 原生像素中心")
    elif missing_total:
        errors.append(f"exclusions alpha 未覆盖 {label} bounds 内 {missing_total} 个原生像素中心")
    return errors


def exclusion_errors_v2(exclusions: dict, images: dict, requested_size: list[int], viewports: dict) -> list[str]:
    """Require alpha at every declared UI/unit bound pixel center after the recorded native transform."""
    errors: list[str] = []
    if exclusions.get("status") not in ("COMPLETE", "CAPTURED_WITH_CONSERVATIVE_CONTROL_BOUNDS"):
        errors.append("单位、HUD 或网格排除掩膜仍不完整")
    background = exclusions.get("excluded_background_controls")
    expected_background = "TacticalScene/BattlefieldBackdrop/Ground"
    if not isinstance(background, list) or len(background) != 1:
        errors.append("必须保留唯一已核实的全屏 BattlefieldBackdrop/Ground 背景例外记录")
    else:
        record = background[0]
        if (record.get("relative_path") != expected_background or record.get("class") != "ColorRect"
                or record.get("canvas_layer") != -1
                or record.get("reason") != "formal scene background, not HUD"):
            errors.append("全屏排除项没有绑定正式 BattlefieldBackdrop/Ground 背景角色")
        rect = record.get("clipped_rect")
        main_visible = viewports.get("main", {}).get("visible_rect", [])
        if (not _finite_vector(rect, 4) or not _finite_vector(main_visible, 4)
                or not np.allclose(rect, main_visible, atol=1e-3, rtol=0)):
            errors.append("背景例外 bounds 未覆盖并准确记录主视口可见区域")

    main_viewport = viewports.get("main", {})
    bounds_space = "main Window visible logical viewport before the viewport stretch transform"
    if exclusions.get("bounds_coordinate_space") != bounds_space:
        errors.append("UI/单位 bounds 坐标空间缺失或与采集声明不符")
    visible = main_viewport.get("visible_rect", []) if isinstance(main_viewport, dict) else []
    final_transform = main_viewport.get("final_transform", []) if isinstance(main_viewport, dict) else []
    if not _finite_vector(visible, 4) or visible[2] <= 0 or visible[3] <= 0:
        errors.append("UI/单位 bounds 缺少有效主视口逻辑 visible_rect")
    if not _finite_vector(final_transform, 6):
        errors.append("UI/单位 bounds 缺少逻辑坐标到原生像素的 final_transform")

    bounds = exclusions.get("drawable_ui_control_bound_records")
    count = exclusions.get("drawable_ui_control_bounds")
    ui_rects: list[list[float]] = []
    if (not isinstance(bounds, list) or type(count) is not int or count <= 0
            or len(bounds) != count):
        errors.append("实际可绘制 UI bounds 清单缺失或数量不一致")
    else:
        for index, bound in enumerate(bounds):
            bound_area = bound.get("area_logical_pixels") if isinstance(bound, dict) else None
            if (not isinstance(bound, dict) or not isinstance(bound.get("relative_path"), str)
                    or not bound.get("relative_path")
                    or not _finite_vector(bound.get("rect"), 4)
                    or not _finite_vector(bound.get("clipped_rect"), 4)
                    or type(bound_area) not in (int, float) or not math.isfinite(bound_area)
                    or bound["rect"][2] < 0 or bound["rect"][3] < 0
                    or bound["clipped_rect"][2] < 0 or bound["clipped_rect"][3] < 0):
                errors.append("可绘制 UI bounds 含无效路径或非有限坐标")
                break
            rect = list(map(float, bound["rect"]))
            clipped = list(map(float, bound["clipped_rect"]))
            if _finite_vector(visible, 4):
                expected_clipped = _rect_intersection(rect, visible)
                if expected_clipped[2] > 0 and expected_clipped[3] > 0:
                    if not np.allclose(clipped, expected_clipped, atol=1e-3, rtol=0):
                        errors.append(f"UI bounds[{index}] clipped_rect 与逻辑可见区域交集不符")
                    elif not math.isclose(float(bound_area), clipped[2] * clipped[3], abs_tol=1e-3, rel_tol=1e-6):
                        errors.append(f"UI bounds[{index}] 面积记录与 clipped_rect 不符")
                    else:
                        ui_rects.append(clipped)
                elif clipped[2] > 0 and clipped[3] > 0:
                    errors.append(f"UI bounds[{index}] 在主视口外却声明了可见 clipped_rect")
            elif clipped[2] > 0 and clipped[3] > 0:
                ui_rects.append(clipped)
    union_area = exclusions.get("drawable_ui_bounds_union_logical_pixels")
    if (not _finite_vector(visible, 4) or type(union_area) not in (int, float)
            or not math.isfinite(union_area) or union_area <= 0
            or union_area >= visible[2] * visible[3]):
        errors.append("UI bounds 并集面积缺失、无效或覆盖完整主视口")
    unit_bounds = exclusions.get("unit_screen_bounds")
    unit_union = exclusions.get("unit_screen_bounds_union_logical_pixels")
    unit_rects: list[list[float]] = []
    if (not isinstance(unit_bounds, list) or len(unit_bounds) == 0
            or type(exclusions.get("unit_count")) is not int or exclusions.get("unit_count") != len(unit_bounds)
            or type(unit_union) not in (int, float) or not math.isfinite(unit_union)
            or unit_union <= 0):
        errors.append("单位保守 bounds 清单或覆盖面积缺失")
    else:
        for index, bound in enumerate(unit_bounds):
            if (not isinstance(bound, dict) or not isinstance(bound.get("unit_id"), str)
                    or not bound.get("unit_id") or not _finite_vector(bound.get("rect"), 4)
                    or bound["rect"][2] <= 0 or bound["rect"][3] <= 0):
                errors.append("单位保守 bounds 含无效 ID 或矩形")
                continue
            rect = list(map(float, bound["rect"]))
            if _finite_vector(visible, 4):
                clipped = _rect_intersection(rect, visible)
                if clipped[2] > 0 and clipped[3] > 0:
                    unit_rects.append(clipped)
            else:
                unit_rects.append(rect)

    excluded = images.get("exclusions")
    coverage = exclusions
    native_size = _pair(requested_size, "requested native size")
    if native_size is None:
        errors.append("请求原生尺寸无效")
        return errors
    total = native_size[0] * native_size[1]
    if excluded is None:
        errors.append("缺少 exclusions 原始 PNG")
    else:
        if (not isinstance(excluded, np.ndarray) or excluded.ndim != 3
                or excluded.shape[2] < 4 or excluded.shape[:2] != (native_size[1], native_size[0])):
            errors.append("exclusions 原始 PNG 像素尺寸或 RGBA 通道无效")
            return errors
        alpha_pixels = excluded[..., 3] > 127
        covered = int(np.count_nonzero(alpha_pixels))
        if (coverage.get("mask_coverage_status") != "CAPTURED"
                or coverage.get("mask_total_pixels") != total
                or coverage.get("mask_covered_pixels") != covered
                or coverage.get("mask_native_image_size") != requested_size):
            errors.append("exclusions alpha 覆盖记录与原始 PNG 不一致")
        ratio = coverage.get("mask_covered_ratio")
        if (type(ratio) not in (int, float) or not math.isfinite(ratio)
                or not math.isclose(ratio, covered / max(1, total), abs_tol=1e-9, rel_tol=0)):
            errors.append("exclusions alpha 覆盖比例记录不一致")
        if covered == total or coverage.get("mask_entire_frame_opaque") is not False:
            errors.append("exclusions 掩膜覆盖整张画面，实例可见性不可测")
        if (isinstance(main_viewport, dict)
                and (main_viewport.get("native_size") != native_size
                     or main_viewport.get("image_size") != native_size)):
            errors.append("主视口记录的 Image 原生尺寸与 exclusions PNG 不一致")
        if (ui_rects and _finite_vector(final_transform, 6)
                and _finite_vector(visible, 4)):
            errors += _bounds_coverage_errors(excluded[..., 3], ui_rects, final_transform, "UI")
        elif not ui_rects:
            errors.append("缺少可验证的 UI clipped bounds 范围")
        if (unit_rects and _finite_vector(final_transform, 6)
                and _finite_vector(visible, 4)):
            errors += _bounds_coverage_errors(excluded[..., 3], unit_rects, final_transform, "单位")
        elif not unit_rects:
            errors.append("缺少可验证的单位保守 bounds 范围")
    return errors


def instance_coverage_errors(instance_counts: dict, visible_counts: dict) -> list[str]:
    return [f"{kind}: 少于三个实例或少于三个可见实例" for kind in KINDS
            if instance_counts.get(kind, 0) < 3 or visible_counts.get(kind, 0) < 3]


def _portrait_window_viewport_errors(viewport: object, size: list[int]) -> list[str]:
    """Apply the existing v2 main-Window texture mapping rule to the companion."""
    if not isinstance(viewport, dict):
        return ["C4 伴随画面缺少原生 Window viewport 记录"]
    errors: list[str] = []
    if (viewport.get("viewport_kind") != "Window" or viewport.get("window_size") != size
            or viewport.get("size") != size):
        errors.append("C4 伴随 viewport 未记录所请求的 Window 物理尺寸")
    scale = viewport.get("stretch_scale")
    transform = viewport.get("stretch_transform")
    if not _finite_vector(scale, 2) or not _finite_vector(transform, 6) or any(value <= 0 for value in scale or []):
        errors.append("C4 伴随 Window stretch transform/scale 缺失或无效")
    else:
        basis_scale = [math.hypot(transform[0], transform[1]), math.hypot(transform[2], transform[3])]
        if not np.allclose(basis_scale, scale, atol=1e-6, rtol=0):
            errors.append("C4 伴随 Window stretch scale 与 transform basis 不符")
        expected_texture_size = [math.ceil(size[i] * scale[i]) for i in range(2)]
        if (viewport.get("texture_reported_size") != expected_texture_size
                or viewport.get("texture_size") != expected_texture_size):
            errors.append("C4 伴随 Window Texture 尺寸不符合物理尺寸乘 stretch scale")
    if viewport.get("native_size") != size or viewport.get("image_size") != size:
        errors.append("C4 伴随原始 Image native_size/image_size 必须等于请求尺寸")
    for field, length in (("canvas_transform", 6), ("final_transform", 6), ("visible_rect", 4)):
        if not _finite_vector(viewport.get(field), length):
            errors.append(f"C4 伴随 Window {field} 缺失或无效")
    return errors


def _portrait_image_errors(root: Path, record: object, size: list[int], frame_id: int,
                           terrain_images: dict) -> tuple[Path | None, list[str]]:
    errors: list[str] = []
    if not isinstance(record, dict):
        return None, ["C4 伴随画面缺少 portrait_hud 图像记录"]
    if record.get("role") != "portrait_hud":
        errors.append("C4 伴随 PNG 角色必须是 portrait_hud")
    if record.get("capture_group") != PORTRAIT_CAPTURE_GROUP:
        errors.append("C4 伴随 PNG 未使用独立 portrait-hud 采集组")
    if record.get("mime_type") != "image/png" or record.get("pixel_format") != "RGBA8":
        errors.append("C4 伴随 PNG 格式记录必须是 image/png 和 RGBA8")
    if record.get("image_size") != size:
        errors.append("C4 伴随 PNG 记录尺寸与请求原生尺寸不一致")
    if type(record.get("frame_id")) is not int or record.get("frame_id") != frame_id:
        errors.append("C4 伴随 PNG 角色或帧号与独立 frame_post_draw 不一致")
    byte_count = record.get("bytes")
    if type(byte_count) is not int or byte_count <= 0:
        errors.append("C4 伴随 PNG 缺少原文件字节数")
    digest = record.get("sha256")
    if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
        errors.append("C4 伴随 PNG 缺少有效原文件 SHA256")
    try:
        path = v1.safe_child(root, record.get("path"))
        terrain_paths = {
            v1.safe_child(root, terrain_record.get("path")).resolve()
            for terrain_record in terrain_images.values()
            if isinstance(terrain_record, dict) and isinstance(terrain_record.get("path"), str)
        }
        if path.resolve() in terrain_paths:
            errors.append("C4 伴随 PNG 不能复用 12 张地形同帧图像中的文件")
        raw = path.read_bytes()
        if type(byte_count) is int and len(raw) != byte_count:
            errors.append("C4 伴随 PNG 原文件字节数不一致")
        if isinstance(digest, str) and re.fullmatch(r"[0-9a-f]{64}", digest) and hashlib.sha256(raw).hexdigest() != digest:
            errors.append("C4 伴随 PNG 原文件 SHA256 不一致")
        try:
            with Image.open(BytesIO(raw)) as image:
                image.load()
                if image.format != "PNG":
                    errors.append("C4 伴随原文件格式不是 PNG")
                if list(image.size) != size:
                    errors.append("C4 伴随原 PNG 原生尺寸不一致")
                if image.mode != "RGBA":
                    errors.append("C4 伴随原 PNG 像素格式不是 RGBA8")
        except (OSError, ValueError) as error:
            errors.append(f"C4 伴随 PNG 无法解码: {error}")
        return path, errors
    except (OSError, ValueError, TypeError) as error:
        errors.append(f"C4 伴随 PNG 路径或原文件无效: {error}")
        return None, errors


def portrait_c4(manifest_path: Path, data: dict, source_root: Path) -> dict:
    """Check C4 on its real HUD frame, independently of the terrain masks."""
    companion = data.get("portrait_companion")
    if companion is None:
        semantic_entry = "res://tests/claude_review/capture_terrain_readability_v6_regions_semantic_sidecar.gd"
        if semantic_entry in data.get("sources", {}):
            return {"pass": False, "errors": ["新版语义采集缺少必需的 C4 头像伴随画面"],
                    "source": "portrait_companion"}
        return checks.c4_file(v1.safe_child(manifest_path.parent, data["images"]["main"]["path"]))
    errors: list[str] = []
    try:
        if companion.get("schema_version") != "terrain-portrait-companion/1":
            errors.append("C4 伴随画面 schema 无效")
        case = data["case"]
        size = case["requested_resolution"]
        frame = companion["common_frame"]
        errors += v1.frame_errors(frame)
        terrain_frame = data.get("common_frame", {}).get("frame_id")
        frame_id = frame.get("frame_id")
        if type(terrain_frame) is not int or type(frame_id) is not int or frame_id >= terrain_frame:
            errors.append("C4 伴随画面必须在取消选择之前独立采集")
        if (companion.get("case_name") != case["name"]
                or companion.get("candidate") != data["candidate"]
                or companion.get("initial_fit") != case["initial_fit"]):
            errors.append("C4 伴随画面的用例、候选或相机不匹配")
        if (companion.get("capture_group") != PORTRAIT_CAPTURE_GROUP
                or frame.get("capture_group") != PORTRAIT_CAPTURE_GROUP
                or frame.get("image_count") != 1
                or frame.get("image_roles") != ["portrait_hud"]
                or companion.get("capture_group") == case["name"]):
            errors.append("C4 伴随帧没有与 12 张地形图像的同帧组明确分开")
        spawn = data["capture_state"]["terrain_v4_spawn_configuration"]["main"]
        if companion.get("formal_configuration_sha256") != spawn["actual_formal_configuration_sha256"]:
            errors.append("C4 伴随画面的正式地图配置不匹配")
        if (companion.get("state") != "formal_selected_unit_before_measurement_cancel"
                or companion.get("portrait_visible") is not True
                or not isinstance(companion.get("selected_unit"), str)
                or not companion["selected_unit"].strip()):
            errors.append("C4 伴随画面没有已选单位的可见头像")
        texture = companion["portrait_texture_path"]
        if not texture.startswith("res://") or hashlib.sha256(v1.safe_child(
                source_root, texture.removeprefix("res://")).read_bytes()).hexdigest() != companion["portrait_texture_sha256"]:
            errors.append("C4 头像纹理原件不匹配")
        scale = min(size[0] / 1280, size[1] / 720)
        # The actual HUD frame is inset one native pixel from C4's unchanged
        # search rectangle: the algorithm rect has a one-pixel margin on each edge.
        algorithm_rect = checks.PORTRAIT_FRAME_1280
        expected = [(algorithm_rect[0] + 1) * scale, (algorithm_rect[1] + 1) * scale,
                    (algorithm_rect[2] - 2) * scale, (algorithm_rect[3] - 2) * scale]
        rect = companion.get("portrait_frame_native_rect")
        if not _finite_vector(rect, 4) or not np.allclose(rect, expected, atol=.01, rtol=0):
            errors.append("C4 采集到的原生头像框没有对应 C4 算法搜索区域内缩一像素的正式边框")
        image = companion["image"]
        image_path, image_errors = _portrait_image_errors(
            manifest_path.parent, image, size, frame_id, data.get("images", {}))
        errors += image_errors
        view = companion["viewport"]
        errors += _portrait_window_viewport_errors(view, size)
        c8_capture = companion.get("c8_capture")
        captures = data.get("captures")
        if not isinstance(c8_capture, dict) or not isinstance(captures, list) or c8_capture not in captures:
            errors.append("C4 伴随画面未纳入 C8")
        elif isinstance(image, dict):
            if (c8_capture.get("file") != image.get("path")
                    or c8_capture.get("sha256") != image.get("sha256")
                    or c8_capture.get("image_size") != image.get("image_size")
                    or c8_capture.get("capture_group") != PORTRAIT_CAPTURE_GROUP
                    or c8_capture.get("role") != "portrait_hud"
                    or c8_capture.get("frame_id") != frame_id
                    or c8_capture.get("capture_kind") != "viewport"):
                errors.append("C8 伴随记录没有绑定同一 portrait_hud PNG、帧号和独立采集组")
            elif image_path is not None and c8_capture.get("file") != image_path.name:
                errors.append("C8 伴随记录路径与经过受控路径解析的 PNG 文件不一致")
        if errors:
            return {"pass": False, "errors": errors, "source": "portrait_companion"}
        assert image_path is not None
        result = checks.c4_file(image_path)
        return dict(result, source="portrait_companion", frame_id=frame_id)
    except (KeyError, TypeError, ValueError, OSError, AttributeError) as error:
        return {"pass": False, "errors": [f"C4 伴随画面记录无效: {error}"], "source": "portrait_companion"}


def validate(manifest_path: Path, source_root: Path, expected_head: str) -> dict:
    data = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    errors: list[str] = []
    if data.get("schema_version") != "terrain-mask-capture/2":
        errors.append("采集 schema 不匹配")
    case, frame = data.get("case", {}), data.get("common_frame", {})
    size, map_size = case.get("requested_resolution", []), case.get("map_size", [])
    if tuple(size) not in RESOLUTIONS or case.get("window_size") != size:
        errors.append("不是三档原生 Window 尺寸之一")
    if map_size not in ([10, 10], [25, 25]):
        errors.append("不是 10×10 或 25×25 正方形地图")
    if not case.get("initial_fit"):
        errors.append("缺少初始 fit 相机记录")
    errors += v1.frame_errors(frame)
    errors += source_errors_v2(data, source_root, expected_head)
    errors += capture_state_errors(data.get("capture_state", {}), map_size)
    images, image_errors = v1.read_images(manifest_path.parent, data.get("images", {}), size,
                                          frame.get("frame_id"))
    errors += image_errors
    errors += viewport_errors_v2(data.get("viewports", {}), size)
    counts = {kind: 0 for kind in KINDS}
    visible_counts = counts.copy()
    ids: set[str] = set()
    colors: set[str] = set()
    id_image = images.get("instance_ids")
    excluded = images.get("exclusions")
    for instance in data.get("instances", []):
        sid, color = instance.get("stable_id"), instance.get("color", "")
        if not sid or sid in ids or color in colors or not re.fullmatch(r"#[0-9a-fA-F]{6}", color):
            errors.append("实例 ID 或颜色缺失、重复或无效")
            continue
        ids.add(sid)
        colors.add(color)
        kind = instance.get("type")
        if kind not in counts:
            continue
        counts[kind] += 1
        if id_image is not None:
            rgb = np.array([int(color[i:i + 2], 16) for i in (1, 3, 5)])
            visible = np.all(id_image[..., :3] == rgb, axis=2) & (id_image[..., 3] > 127)
            if excluded is not None:
                visible &= excluded[..., 3] <= 127
            visible_counts[kind] += int(visible.any())
    errors += instance_coverage_errors(counts, visible_counts)
    alignment = v1.reconstruction_check(images)
    if alignment["status"] != "PASS":
        errors.append("重建画面尚未与正式原图完全对齐")
    segmentation = v1.segmentation_check(images, colors)
    if segmentation["status"] != "PASS":
        errors.append("实例掩膜与实际道具 alpha 轮廓不一致")
    previous_root = checks.ROOT
    try:
        checks.ROOT = source_root
        c4 = portrait_c4(manifest_path, data, source_root) if "main" in images else {"pass": False, "reason": "缺少主图"}
        c8 = checks.c8_manifest(manifest_path)
        c8_v1 = checks.c8_script(v1.safe_child(source_root, V1_SCRIPT))
        c8_v2 = checks.c8_script(v1.safe_child(source_root, V2_SCRIPT))
    finally:
        checks.ROOT = previous_root
    if not c4.get("pass") or not c8.get("pass") or not c8_v1.get("pass") or not c8_v2.get("pass"):
        errors.append("C4 或 C8 未通过")
    errors += exclusion_errors_v2(data.get("exclusions", {}), images, size, data.get("viewports", {}))
    return {"manifest": manifest_path.name, "case": case,
            "capture_preconditions": "PASS" if not errors else "FAIL", "errors": errors,
            "instance_counts": counts, "visible_instance_counts": visible_counts,
            "reconstruction": alignment, "segmentation": segmentation,
            "C4": c4, "C8": c8, "C8_source_v1": c8_v1, "C8_source_v2": c8_v2,
            "measurement_status": "NOT_TESTED", "art_acceptance": "NOT_TESTED",
            "note": "采集前置通过后，仍需独立测量和原图审查；素材验收状态保持 NOT_TESTED。"}


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
    results = []
    for path in args.manifests:
        try:
            results.append(validate(path, args.source_root, args.candidate))
        except (OSError, ValueError, KeyError, TypeError) as error:
            results.append({"manifest": path.name, "capture_preconditions": "FAIL", "errors": [str(error)]})
    cases = [(tuple(result.get("case", {}).get("map_size", [])),
              tuple(result.get("case", {}).get("requested_resolution", []))) for result in results]
    required = {(size, resolution) for size in ((10, 10), (25, 25)) for resolution in RESOLUTIONS}
    complete = len(cases) == 6 and set(cases) == required
    valid = complete and all(result["capture_preconditions"] == "PASS" for result in results)
    output = {"schema_version": "terrain-capture-readback/2", "candidate_head": args.candidate,
              "six_case_coverage": complete, "capture_preconditions": "PASS" if valid else "FAIL",
              "art_acceptance": "NOT_TESTED", "cases": results}
    args.out.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"capture_preconditions": output["capture_preconditions"],
                      "six_case_coverage": complete, "art_acceptance": "NOT_TESTED"}, ensure_ascii=False))
    return 0 if valid else 1


if __name__ == "__main__":
    raise SystemExit(main())
