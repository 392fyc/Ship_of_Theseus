"""R9 wrapper: preserve frozen V3 measurements and add fail-closed pixel gates."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image

import validate_terrain_acceptance_v3 as v3
import validate_terrain_semantic_sidecar as sidecar


SCHEMA = "terrain-pillar-readback/9"
CAPTURE_ENTRY = "res://tests/claude_review/capture_terrain_readability_r9.gd"
R9_SOURCE_PATHS = (
    "tests/claude_review/capture_terrain_readability_r9.gd",
    "tests/claude_review/validate_terrain_pillar_r9.py",
    "tests/claude_review/test_terrain_pillar_r9.py",
    "dev_doc/ui-art-research/terrain-readability/pillar-r9-task.md",
)
R9_CAPTURE_SCRIPT_CHAIN = (
    CAPTURE_ENTRY,
    "res://tests/claude_review/capture_terrain_readability_r7.gd",
    "res://tests/claude_review/capture_terrain_readability_r6.gd",
    "res://tests/claude_review/capture_terrain_readability_v6_atlas.gd",
    "res://tests/claude_review/capture_terrain_readability_v6_regions_semantic_sidecar.gd",
    "res://tests/claude_review/capture_terrain_readability_v6_regions.gd",
    "res://tests/claude_review/capture_terrain_readability_v6.gd",
    "res://tests/claude_review/capture_terrain_readability.gd",
)
O1_SCHEMA = "terrain-pillar-occlusion/1"
T6_MARGIN = 10.5
BODY_RGB_TOLERANCE = 2
BODY_ALPHA_TOLERANCE = 1


def _not_tested(reason: str, **details: Any) -> dict[str, Any]:
    return {"status": "NOT_TESTED", "reason": reason, **details}


def _read_bound_rgba(case_dir: Path, record: Any, label: str) -> np.ndarray:
    if not isinstance(record, dict):
        raise ValueError(f"{label} image record missing")
    relative = record.get("path")
    if not isinstance(relative, str) or not relative or Path(relative).is_absolute():
        raise ValueError(f"{label} image path missing or absolute")
    path = (case_dir / relative).resolve()
    if path.parent != case_dir.resolve() and case_dir.resolve() not in path.parents:
        raise ValueError(f"{label} image path escapes case directory")
    raw = path.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != record.get("sha256"):
        raise ValueError(f"{label} image SHA256 differs from its record")
    if record.get("bytes") not in (None, len(raw)):
        raise ValueError(f"{label} image byte count differs from its record")
    with Image.open(path) as image:
        image.load()
        if image.format != "PNG" or image.mode not in ("RGBA", "RGB"):
            raise ValueError(f"{label} is not a decoded PNG")
        rgba = np.asarray(image.convert("RGBA"), dtype=np.uint8)
    expected = record.get("image_size")
    if expected != [rgba.shape[1], rgba.shape[0]]:
        raise ValueError(f"{label} decoded size differs from its record")
    return rgba


def _main_image(case_dir: Path, capture: dict[str, Any]) -> np.ndarray:
    rows = capture.get("images")
    if not isinstance(rows, dict) or not isinstance(rows.get("main"), dict):
        raise ValueError("capture manifest has no bound main image")
    return _read_bound_rgba(case_dir, rows["main"], "main")


def _matrix(values: Any) -> np.ndarray:
    if not isinstance(values, list) or len(values) != 6:
        raise ValueError("transform must be a six-number Transform2D array")
    matrix = sidecar._source_transform_matrix(values)
    if matrix.shape != (3, 3) or not np.isfinite(matrix).all():
        raise ValueError("transform is not a finite 2D affine matrix")
    return matrix


def _point(matrix: np.ndarray, xy: Any) -> np.ndarray:
    values = np.asarray(xy, dtype=np.float64)
    if values.shape != (2,) or not np.isfinite(values).all():
        raise ValueError("Line2D point is missing or non-finite")
    mapped = matrix @ np.asarray([values[0], values[1], 1.0])
    return mapped[:2]


def _line_row_x(points: np.ndarray, y: float) -> float | None:
    """Return a vertical polyline's x at a native pixel-row center."""
    hits: list[float] = []
    for first, second in zip(points[:-1], points[1:], strict=True):
        low, high = sorted((float(first[1]), float(second[1])))
        if y < low or y > high:
            continue
        dy = float(second[1] - first[1])
        if abs(dy) < 1e-9:
            continue
        ratio = (y - float(first[1])) / dy
        hits.append(float(first[0] + ratio * (second[0] - first[0])))
    if not hits:
        return None
    return float(np.median(np.asarray(hits, dtype=np.float64)))


def _groove_points(leaf: dict[str, Any], viewport_matrix: np.ndarray) -> np.ndarray:
    points = leaf.get("points")
    if not isinstance(points, list) or len(points) < 2:
        raise ValueError("Line2D groove points missing")
    global_transform = _matrix(leaf.get("global_transform"))
    return np.asarray([_point(viewport_matrix @ global_transform, point) for point in points],
                      dtype=np.float64)


def _groove_width_px(leaf: dict[str, Any], viewport_matrix: np.ndarray) -> float:
    width = leaf.get("width")
    if not isinstance(width, (int, float)) or not math.isfinite(float(width)) or width <= 0:
        raise ValueError("Line2D groove width is missing or invalid")
    transform = viewport_matrix @ _matrix(leaf.get("global_transform"))
    # R9 grooves are authored as vertical Line2D strokes; their perpendicular
    # local axis is x. Apply the same recorded global and viewport transforms.
    scale = float(np.linalg.norm(transform[:2, 0]))
    if not math.isfinite(scale) or scale <= 0:
        raise ValueError("Line2D transformed stroke width is invalid")
    return float(width) * scale


def _point_segment_distance(point: np.ndarray, points: np.ndarray) -> float:
    distance = math.inf
    for first, second in zip(points[:-1], points[1:], strict=True):
        segment = second - first
        length_squared = float(np.dot(segment, segment))
        if length_squared <= 1e-12:
            candidate = float(np.linalg.norm(point - first))
        else:
            amount = float(np.clip(np.dot(point - first, segment) / length_squared, 0.0, 1.0))
            candidate = float(np.linalg.norm(point - (first + amount * segment)))
        distance = min(distance, candidate)
    return distance


def _groove_records(semantic: dict[str, Any], stable_id: str) -> list[dict[str, Any]]:
    rows = semantic.get("frame", {}).get("instance_tokens", [])
    if not isinstance(rows, list):
        raise ValueError("semantic instance token inventory missing")
    instance = next((row for row in rows if isinstance(row, dict)
                     and row.get("stable_id") == stable_id), None)
    if instance is None or instance.get("type") != "pillar":
        raise ValueError(f"actual pillar instance {stable_id!r} missing")
    leaves = instance.get("draw_leaf_inputs")
    if not isinstance(leaves, list):
        raise ValueError("pillar draw_leaf_inputs missing")
    grooves: list[dict[str, Any]] = []
    for leaf in leaves:
        if not isinstance(leaf, dict):
            continue
        if not str(leaf.get("node_name", "")).startswith("R9Groove"):
            continue
        index = leaf.get("r9_groove_index")
        u = leaf.get("r9_groove_u", leaf.get("u"))
        if leaf.get("node_class") != "Line2D" or type(index) is not int \
                or not isinstance(u, (int, float)) or not math.isfinite(float(u)):
            raise ValueError("R9 groove leaf lacks Line2D index/u metadata")
        normalized = dict(leaf)
        normalized["r9_groove_u"] = float(u)
        grooves.append(normalized)
    indexes = [int(row["r9_groove_index"]) for row in grooves]
    if len(grooves) != 4 or sorted(indexes) != [1, 2, 3, 4]:
        raise ValueError("exactly R9Groove1..4 with unique metadata indexes are required")
    return sorted(grooves, key=lambda row: int(row["r9_groove_index"]))


def _occupancy_data(case_dir: Path, semantic: dict[str, Any]) -> np.ndarray:
    record = semantic.get("composite_occupancy", {}).get("image")
    return _read_bound_rgba(case_dir, record, "composite_occupancy")


def _owner_map(occupancy: np.ndarray) -> np.ndarray:
    rgb = occupancy[..., :3].astype(np.uint32)
    token = (rgb[..., 0] << 16) | (rgb[..., 1] << 8) | rgb[..., 2]
    return np.where(occupancy[..., 3] == 255, token, 0).astype(np.uint32)


def _srgb_lstar(rgb: np.ndarray) -> np.ndarray:
    srgb = rgb.astype(np.float64) / 255.0
    linear = np.where(srgb <= 0.04045, srgb / 12.92,
                      ((srgb + 0.055) / 1.055) ** 2.4)
    y = linear @ np.asarray([0.2126, 0.7152, 0.0722], dtype=np.float64)
    return np.where(y > 0.008856, 116.0 * np.cbrt(y) - 16.0, 903.3 * y)


def _sample_groove(groove: dict[str, Any], all_grooves: list[dict[str, Any]],
                   image: np.ndarray, owners: np.ndarray, token: int,
                   viewport_matrix: np.ndarray) -> dict[str, Any]:
    index = int(groove["r9_groove_index"])
    u = float(groove["r9_groove_u"])
    points = _groove_points(groove, viewport_matrix)
    span_x = float(np.ptp(points[:, 0]))
    span_y = float(np.ptp(points[:, 1]))
    if span_y < 3 or span_y < span_x * 2:
        return _not_tested("groove is not a sufficiently vertical Line2D for same-row side bands",
                           groove_index=index, u=u, transformed_points=points.tolist())
    if index == 3 and abs(u - 0.62) > 0.02:
        return _not_tested("third groove metadata is not u≈0.62", groove_index=index, u=u)
    height, width = owners.shape
    y_start = max(0, int(math.ceil(float(points[:, 1].min()) - 0.5)))
    y_end = min(height - 1, int(math.floor(float(points[:, 1].max()) - 0.5)))
    own_lightness = _srgb_lstar(image[..., :3])
    excluded: dict[str, int] = {}
    deltas: list[float] = []
    center_pixels: list[list[int]] = []
    line_width_px = _groove_width_px(groove, viewport_matrix)
    other_rows: list[tuple[int, np.ndarray, float]] = []
    for other in all_grooves:
        if other is groove:
            continue
        other_index = int(other["r9_groove_index"])
        try:
            other_points = _groove_points(other, viewport_matrix)
            other_width_px = _groove_width_px(other, viewport_matrix)
            other_rows.append((other_index, other_points, other_width_px))
        except (TypeError, ValueError):
            excluded["other_groove_transform_missing"] = excluded.get("other_groove_transform_missing", 0) + 1

    for y in range(y_start, y_end + 1):
        center_x = _line_row_x(points, y + 0.5)
        if center_x is None:
            excluded["no_centerline_at_row"] = excluded.get("no_centerline_at_row", 0) + 1
            continue
        x = int(math.floor(center_x))
        band_x = [x - 2, x - 1, x + 1, x + 2]
        if x < 0 or x >= width or min(band_x) < 0 or max(band_x) >= width:
            excluded["outside_image"] = excluded.get("outside_image", 0) + 1
            continue
        contamination = False
        for other_index, other_points, other_width_px in other_rows:
            # 对实际候选像素中心计算到另一条变换后线段的距离；仅当中心
            # 命中其半线宽内才排除，避免按槽间距阈值误删整列。
            if any(_point_segment_distance(np.asarray([sample_x + 0.5, y + 0.5]), other_points)
                   <= other_width_px * 0.5 for sample_x in [x, *band_x]):
                excluded["other_groove_%d" % other_index] = excluded.get("other_groove_%d" % other_index, 0) + 1
                contamination = True
                break
        if contamination:
            continue
        sample_x = [x, *band_x]
        if any(int(owners[y, sample]) != token for sample in sample_x):
            kinds = [int(owners[y, sample]) for sample in sample_x]
            reason = "non_pillar_or_occluded_owner" if any(owner not in (0, token) for owner in kinds) \
                else "pillar_surface_or_empty_pixel_missing"
            excluded[reason] = excluded.get(reason, 0) + 1
            continue
        if any(int(image[y, sample, 3]) != 255 for sample in sample_x):
            excluded["non_opaque_pixel"] = excluded.get("non_opaque_pixel", 0) + 1
            continue
        center_l = float(own_lightness[y, x])
        side_l = float(np.median(own_lightness[y, band_x]))
        deltas.append(side_l - center_l)
        center_pixels.append([x, y])

    if not deltas:
        return _not_tested("no uncontaminated opaque pillar rows remain for this groove",
                           groove_index=index, u=u, excluded_rows=excluded,
                           valid_rows=0,
                           transformed_points=points.tolist())
    contrast = float(np.median(np.asarray(deltas, dtype=np.float64)))
    sampled_side_l = np.asarray([
        own_lightness[y, [x - 2, x - 1, x + 1, x + 2]] for x, y in center_pixels
    ], dtype=np.float64).reshape(-1)
    sideband_iqr = float(np.percentile(sampled_side_l, 75) - np.percentile(sampled_side_l, 25))
    required = "6.0 <= delta_L* <= 8.0" if index != 3 else "delta_L* >= 4.0"
    passed = (6.0 <= contrast <= 8.0) if index != 3 else contrast >= 4.0
    status = "PASS" if passed else "FAIL"
    return {"status": status, "groove_index": index, "u": u,
            "delta_L_star_median": contrast, "required": required,
            "centerline_rows_measured": len(deltas), "centerline_rows_excluded": excluded,
            "sideband_texture_spread_iqr_l_star": sideband_iqr,
            "transformed_line_width_px": line_width_px,
            "centerline_sample_pixels_first_last": [center_pixels[0], center_pixels[-1]],
            "side_band_offsets_px": [-2, -1, 1, 2], "side_reference": "median of the four actual same-row pillar pixels",
            "center_reference": "actual RGBA8 main-image pixel nearest the transformed Line2D centerline",
            "raster_basis": "Line2D local points and stroke width -> leaf global_transform -> viewport canvas_transform -> final_transform -> native pixel centers",
            "texture_policy": "actual same-token opaque main-image texture pixels remain in the row median; texture spread is diagnostic only"}


def measure_g1(manifest_path: Path, capture: dict[str, Any], semantic: dict[str, Any]) -> dict[str, Any]:
    case_dir = manifest_path.parent
    try:
        main = _main_image(case_dir, capture)
        occupancy = _occupancy_data(case_dir, semantic)
        if main.shape != occupancy.shape:
            raise ValueError("static main and composite occupancy images have different sizes")
        frame = semantic.get("frame", {})
        common = capture.get("common_frame", {})
        if frame.get("callback") != "RenderingServer.frame_post_draw" \
                or frame.get("same_frame") is not True \
                or frame.get("frame_id") != common.get("frame_id"):
            raise ValueError("static main is not bound to the same frame_post_draw as sidecar")
        if frame.get("original_capture_image_count_unchanged") != 12:
            raise ValueError("R9 requires the frozen 12-image base capture")
        same_candidate = capture.get("candidate", {}).get("candidate_digest_sha256") \
            == semantic.get("capture_candidate", {}).get("candidate_digest_sha256")
        if not same_candidate:
            raise ValueError("static main and semantic sidecar candidate digests differ")
        view = frame.get("viewports", {}).get("main")
        if not isinstance(view, dict) or view.get("image_size") != [main.shape[1], main.shape[0]]:
            raise ValueError("sidecar main viewport does not match native main image")
        viewport_matrix = _matrix(view.get("final_transform")) @ _matrix(view.get("canvas_transform"))
        token_rows = frame.get("instance_tokens", [])
        owner_map = _owner_map(occupancy)
        pillars = [row for row in token_rows if isinstance(row, dict) and row.get("type") == "pillar"]
        if len(pillars) != 3:
            raise ValueError(f"expected all three pillar instances in the sidecar, found {len(pillars)}")
        pillar_results: list[dict[str, Any]] = []
        all_grooves: list[dict[str, Any]] = []
        for pillar in sorted(pillars, key=lambda row: str(row.get("stable_id", ""))):
            stable_id = str(pillar.get("stable_id", ""))
            token = int(pillar.get("token", 0))
            if not stable_id or token <= 0 or token > 0xFFFFFF:
                raise ValueError("pillar stable id or token is invalid")
            grooves = _groove_records(semantic, stable_id)
            groove_results = [_sample_groove(row, grooves, main, owner_map, token, viewport_matrix)
                              for row in grooves]
            all_grooves.extend(groove_results)
            instance_status = "PASS" if all(row["status"] == "PASS" for row in groove_results) else (
                "FAIL" if any(row["status"] == "FAIL" for row in groove_results) else "NOT_TESTED")
            pillar_results.append({"stable_id": stable_id, "token": token,
                                   "status": instance_status, "grooves": groove_results})
        if all(row["status"] == "PASS" for row in pillar_results):
            status = "PASS"
        elif any(row["status"] == "FAIL" for row in pillar_results):
            status = "FAIL"
        else:
            status = "NOT_TESTED"
        return {"status": status, "pillars": pillar_results,
                "static_main_frame_id": common["frame_id"], "same_frame": True,
                "same_candidate_digest": same_candidate,
                "grooves": all_grooves,
                "notes": ["source metadata identifies groove identity only; source color is never used to infer a pass",
                          "non-pillar/empty/transparent or another-groove-hit rows are excluded with counted reasons",
                          "normal same-token opaque pillar texture remains in the actual pixel samples; texture spread is diagnostic only"]}
    except (OSError, KeyError, TypeError, ValueError, IndexError) as error:
        return _not_tested(str(error), pillars=[], grooves=[])


def measure_pillar_side_iqr(manifest_path: Path, capture: dict[str, Any],
                            semantic: dict[str, Any]) -> dict[str, Any]:
    """Measure original-main-image L* spread over the highest pillar's effective side pixels."""
    try:
        case_dir = manifest_path.parent
        main = _main_image(case_dir, capture)
        frame = semantic.get("frame", {})
        image_records = frame.get("images", {}) if isinstance(frame, dict) else {}
        pair = _read_bound_rgba(case_dir, image_records.get("semantic_pair"), "semantic_pair")
        coverage = _read_bound_rgba(case_dir, image_records.get("semantic_coverage"), "semantic_coverage")
        occupancy = _occupancy_data(case_dir, semantic)
        if not (main.shape == pair.shape == coverage.shape == occupancy.shape):
            raise ValueError("main/semantic/occupancy dimensions differ for pillar-side IQR")
        pair_token = ((pair[..., 0].astype(np.uint32) << 16)
                      | (pair[..., 1].astype(np.uint32) << 8)
                      | pair[..., 2].astype(np.uint32))
        owner = _owner_map(occupancy)
        side_code = int(sidecar.PART_CODES["pillar_side"])
        pillars = [row for row in frame.get("instance_tokens", []) if isinstance(row, dict)
                   and row.get("type") == "pillar"]
        if len(pillars) != 3:
            raise ValueError(f"expected all three pillar instances for side IQR, found {len(pillars)}")
        lightness = _srgb_lstar(main[..., :3])
        pillar_results: list[dict[str, Any]] = []
        for pillar in sorted(pillars, key=lambda row: str(row.get("stable_id", ""))):
            token = int(pillar.get("token", 0))
            stable_id = str(pillar.get("stable_id", ""))
            if not stable_id or token <= 0 or token > 0xFFFFFF:
                raise ValueError("pillar stable id or token is invalid for side IQR")
            effective_side = (pair_token == token) & (pair[..., 3] == side_code) \
                & (coverage[..., 3] > 127) & (owner == token)
            count = int(effective_side.sum())
            if count == 0:
                pillar_results.append(_not_tested(
                    "no effective pillar_side pixels remain after alpha/owner checks",
                    stable_id=stable_id, token=token))
                continue
            values = lightness[effective_side]
            q25, q75 = np.percentile(values, [25, 75])
            iqr = float(q75 - q25)
            pillar_results.append({"status": "PASS" if iqr >= 5.0 else "FAIL",
                                   "stable_id": stable_id, "token": token,
                                   "effective_pillar_side_pixels": count,
                                   "l_star_q25": float(q25), "l_star_q75": float(q75),
                                   "l_star_iqr": iqr, "required_minimum_iqr_l_star": 5.0})
        status = "PASS" if all(row.get("status") == "PASS" for row in pillar_results) else (
            "FAIL" if any(row.get("status") == "FAIL" for row in pillar_results) else "NOT_TESTED")
        return {"status": status, "pillars": pillar_results,
                "pixel_source": "original RGBA8 main image; semantic_pair pillar_side code; semantic_coverage alpha >127/255; same-token R7 composite occupancy",
                "legacy_T2_formula_unchanged": True}
    except (OSError, KeyError, TypeError, ValueError, IndexError) as error:
        return _not_tested(str(error))


def _rect_xywh(value: Any, width: int, height: int) -> tuple[slice, slice]:
    if not isinstance(value, list) or len(value) != 4:
        raise ValueError("body_rect must be [x,y,width,height]")
    rect = np.asarray(value, dtype=np.float64)
    if not np.isfinite(rect).all() or rect[2] <= 0 or rect[3] <= 0:
        raise ValueError("body_rect is empty or non-finite")
    x0 = max(0, int(math.floor(rect[0])))
    y0 = max(0, int(math.floor(rect[1])))
    x1 = min(width, int(math.ceil(rect[0] + rect[2])))
    y1 = min(height, int(math.ceil(rect[1] + rect[3])))
    if x1 <= x0 or y1 <= y0:
        raise ValueError("body_rect is outside the viewport")
    return slice(y0, y1), slice(x0, x1)


def _unit_contribution(visible: np.ndarray, hidden: np.ndarray,
                       body_rect: Any) -> tuple[int, int, np.ndarray]:
    if visible.shape != hidden.shape:
        raise ValueError("paired O1 images have different dimensions")
    sy, sx = _rect_xywh(body_rect, visible.shape[1], visible.shape[0])
    left = visible[sy, sx].astype(np.int16)
    right = hidden[sy, sx].astype(np.int16)
    rgb_delta = np.max(np.abs(left[..., :3] - right[..., :3]), axis=2)
    alpha_delta = np.abs(left[..., 3] - right[..., 3])
    contributed = (rgb_delta > BODY_RGB_TOLERANCE) | (alpha_delta > BODY_ALPHA_TOLERANCE)
    return int(contributed.sum()), int(contributed.size), contributed


def _o1_group_errors(record: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if record.get("same_frame") is not True or record.get("callback") != "RenderingServer.frame_post_draw":
        errors.append("O1 four-state group lacks same-frame callback evidence")
    if record.get("setup_status") != "PASS":
        errors.append("O1 setup status is not PASS")
    states = record.get("states", {})
    if not isinstance(states, dict) or set(states) != {"A", "B", "C", "D"}:
        return errors + ["O1 A/B/C/D state set is incomplete"]
    frame_ids = {row.get("frame_id") for row in states.values() if isinstance(row, dict)}
    frames_before = {row.get("frames_drawn_before") for row in states.values() if isinstance(row, dict)}
    frames_after = {row.get("frames_drawn_after") for row in states.values() if isinstance(row, dict)}
    process_before = {row.get("process_frames_before") for row in states.values() if isinstance(row, dict)}
    process_after = {row.get("process_frames_after") for row in states.values() if isinstance(row, dict)}
    if len(frame_ids) != 1 or frame_ids != {record.get("frame_id")}: 
        errors.append("O1 A/B/C/D frame ids differ")
    if not (len(frames_before) == len(frames_after) == len(process_before) == len(process_after) == 1
            and frames_before == frames_after == frame_ids and process_before == process_after):
        errors.append("O1 image readbacks crossed the same-frame/process boundary")
    expected_visibility = {"A": (True, True), "B": (False, True),
                           "C": (True, False), "D": (False, False)}
    expected_cell = [0, 3]
    for role, (pillar_visible, unit_visible) in expected_visibility.items():
        row = states.get(role, {})
        if not isinstance(row, dict):
            errors.append(f"O1 state {role} is invalid")
            continue
        if row.get("role") != role or row.get("callback") != "RenderingServer.frame_post_draw" \
                or row.get("same_frame") is not True:
            errors.append(f"O1 state {role} is not a frame_post_draw readback")
        if row.get("pillar_visible") is not pillar_visible or row.get("unit_visible") is not unit_visible:
            errors.append(f"O1 state {role} visibility controls do not match A/B/C/D design")
        if row.get("requested_hover_cell") != expected_cell or row.get("requested_unit_cell") != expected_cell \
                or row.get("hover_cell") != expected_cell or row.get("unit_cell") != expected_cell \
                or row.get("has_hover_cell") is not True:
            errors.append(f"O1 state {role} actual/requested Unit or hover cell differs from the approved cell")
        view = row.get("viewport", {})
        if not isinstance(view, dict) or view.get("image_size") != record.get("image_size"):
            errors.append(f"O1 state {role} viewport size differs")
        if row.get("window_size") != record.get("window_size"):
            errors.append(f"O1 state {role} window size differs")
    def same_transform(left: Any, right: Any) -> bool:
        try:
            a, b = np.asarray(left, dtype=np.float64), np.asarray(right, dtype=np.float64)
            return a.shape == b.shape == (6,) and np.isfinite(a).all() and np.isfinite(b).all() \
                and bool(np.allclose(a, b, atol=0.001, rtol=0))
        except (TypeError, ValueError):
            return False

    viewport_rows = [states[role].get("viewport", {}) if isinstance(states[role], dict) else {}
                     for role in "ABCD"]
    transforms = [view.get("canvas_transform") if isinstance(view, dict) else None
                  for view in viewport_rows]
    finals = [view.get("final_transform") if isinstance(view, dict) else None
              for view in viewport_rows]
    if any(not same_transform(value, transforms[0]) for value in transforms[1:]):
        errors.append("O1 viewports do not share canvas transforms within 0.001 px")
    if any(not same_transform(value, finals[0]) for value in finals[1:]):
        errors.append("O1 viewports do not share final transforms within 0.001 px")
    viewport_ids = [states[role].get("viewport_instance_id") if isinstance(states[role], dict) else None
                    for role in "ABCD"]
    image_paths = [states[role].get("image", {}).get("path")
                   if isinstance(states[role], dict) and isinstance(states[role].get("image", {}), dict)
                   else None for role in "ABCD"]
    if any(type(value) is not int for value in viewport_ids) or len(set(viewport_ids)) != 4:
        errors.append("O1 state records do not identify four independent viewports")
    if any(not isinstance(value, str) or not value for value in image_paths) or len(set(image_paths)) != 4:
        errors.append("O1 state records do not identify four separate pixel images")
    body_rects = [states[role].get("body_rect") if isinstance(states[role], dict) else None
                  for role in "ABCD"]
    if any(value != body_rects[0] for value in body_rects[1:]) or body_rects[0] != record.get("body_rect"):
        errors.append("O1 body rectangles differ across the four actual source states")
    if record.get("unit_cell") != expected_cell or record.get("hover_cell") != expected_cell:
        errors.append("O1 group does not bind the actual Unit and hover to the approved cell")
    if len({states[role].get("window_id") if isinstance(states[role], dict) else None
            for role in "ABCD"}) != 1:
        errors.append("O1 states do not identify the same host window")
    if any(not isinstance(states[role].get("pillar_alpha"), (int, float))
           or not math.isfinite(float(states[role]["pillar_alpha"]))
           for role in "ABCD" if isinstance(states[role], dict)) \
            or any(not isinstance(states[role], dict) for role in "ABCD"):
        errors.append("O1 actual per-state pillar alpha readback is missing")
    return errors


def o1_ratio_status(with_pillar: int, without_pillar: int) -> tuple[str, float | None, str]:
    if with_pillar < 0 or without_pillar <= 0:
        return "NOT_TESTED", None, "same-frame no-pillar Unit contribution denominator is empty"
    ratio = with_pillar / without_pillar
    if with_pillar > without_pillar:
        return "FAIL", ratio, "pillar-present contribution exceeds same-frame no-pillar contribution"
    if ratio >= 0.60:
        return "PASS", ratio, "actual Unit contribution remains at least 60% of same-frame no-pillar control"
    return "FAIL", ratio, "actual Unit contribution is below 60% of same-frame no-pillar control"


def _load_o1_images(manifest_path: Path, record: dict[str, Any]) -> dict[str, np.ndarray]:
    images: dict[str, np.ndarray] = {}
    for role in ("A", "B", "C", "D"):
        row = record.get("states", {}).get(role)
        if not isinstance(row, dict):
            raise ValueError(f"O1 state {role} record missing")
        if row.get("role") != role or row.get("callback") != "RenderingServer.frame_post_draw" \
                or row.get("same_frame") is not True:
            raise ValueError(f"O1 state {role} is not a frame_post_draw readback")
        images[role] = _read_bound_rgba(manifest_path.parent, row.get("image"), f"O1 {role}")
    return images


def measure_o1(manifest_path: Path, capture: dict[str, Any]) -> dict[str, Any]:
    sidecar_path = manifest_path.parent / sidecar.SIDECAR_MANIFEST
    o1_path = manifest_path.parent / "r9-o1.json"
    if not o1_path.is_file():
        return _not_tested("r9-o1.json is missing")
    try:
        raw = o1_path.read_bytes()
        record = json.loads(raw)
        if not isinstance(record, dict) or record.get("schema_version") != O1_SCHEMA:
            raise ValueError("O1 schema is invalid")
        if record.get("setup_status") != "PASS":
            return _not_tested(str(record.get("setup_reason") or "O1 capture setup is incomplete"))
        if record.get("capture_manifest_sha256") != hashlib.sha256(manifest_path.read_bytes()).hexdigest():
            raise ValueError("O1 is not bound to the exact static capture-manifest bytes")
        if record.get("semantic_sidecar_sha256") != hashlib.sha256(sidecar_path.read_bytes()).hexdigest():
            raise ValueError("O1 is not bound to the exact semantic-sidecar bytes")
        if record.get("candidate_digest_sha256") != capture.get("candidate", {}).get("candidate_digest_sha256"):
            raise ValueError("O1 candidate digest differs from the static capture")
        group_errors = _o1_group_errors(record)
        if group_errors:
            raise ValueError("; ".join(group_errors))
        states = record["states"]
        images = _load_o1_images(manifest_path, record)
        if any(image.shape != images["A"].shape for image in images.values()):
            raise ValueError("O1 image pixel dimensions differ")
        body_rect = record.get("body_rect")
        with_pillar, denominator, mask_a = _unit_contribution(images["A"], images["C"], body_rect)
        without_pillar, no_pillar_denominator, mask_b = _unit_contribution(images["B"], images["D"], body_rect)
        if denominator != no_pillar_denominator or denominator <= 0 or without_pillar <= 0:
            raise ValueError("O1 actual Unit body contribution denominator is empty or inconsistent")
        status, ratio, reason = o1_ratio_status(with_pillar, without_pillar)
        pillar_alpha = record.get("pillar_alpha")
        if not isinstance(pillar_alpha, (int, float)) or not math.isfinite(float(pillar_alpha)) \
                or record.get("pillar_alpha_input") != "actual pillar CanvasItem.modulate.a after TerrainBattleSession._update_board_visibility_context and CourtyardBoardView._process":
            return _not_tested("actual production pillar alpha readback is missing or lacks visibility-context provenance",
                               contribution={"with_pillar_pixels": with_pillar,
                                             "without_pillar_pixels": without_pillar,
                                             "body_denominator_pixels": denominator,
                                             "ratio": ratio})
        if float(pillar_alpha) >= 0.99:
            status = "FAIL"
            reason = "actual pillar alpha did not enter the faded visibility state"
        overlay = record.get("overlays", {})
        required_overlay_keys = ("name", "hp", "forecast", "unit_overhead_forecast")
        overlays_ready = all(isinstance(overlay.get(key), dict)
                             and overlay[key].get("text")
                             and isinstance(overlay[key].get("rect"), list)
                             and len(overlay[key]["rect"]) == 4
                             and overlay[key].get("visible") is True
                             and isinstance(overlay[key].get("canvas_layer"), int)
                             and overlay[key].get("text_complete") is True
                             for key in required_overlay_keys)
        forecast = overlay.get("forecast", {}) if isinstance(overlay, dict) else {}
        forecast_ready = forecast.get("has_matching_official_value") is True
        if not overlays_ready or not forecast_ready:
            return _not_tested("actual Unit name/HP/forecast node rect, visible overhead number, or official forecast value is missing",
                               contribution={"with_pillar_pixels": with_pillar,
                                             "without_pillar_pixels": without_pillar,
                                             "body_denominator_pixels": denominator,
                                             "ratio": ratio}, overlays=overlay)
        sidecar_path = manifest_path.parent / sidecar.SIDECAR_MANIFEST
        semantic = json.loads(sidecar_path.read_bytes())
        token_rows = semantic.get("frame", {}).get("instance_tokens", [])
        pillar_rows = [row for row in token_rows if isinstance(row, dict)
                       and row.get("stable_id") == record.get("pillar_stable_id")
                       and row.get("type") == "pillar"]
        if len(pillar_rows) != 1:
            return _not_tested("static sidecar cannot identify the actual pillar token for overlay intersection",
                               contribution={"with_pillar_pixels": with_pillar,
                                             "without_pillar_pixels": without_pillar,
                                             "body_denominator_pixels": denominator,
                                             "ratio": ratio}, overlays=overlay)
        occupancy = _occupancy_data(manifest_path.parent, semantic)
        owner = _owner_map(occupancy)
        if occupancy.shape != images["A"].shape:
            return _not_tested("static occupancy image and O1 viewport dimensions differ")
        pillar_mask = owner == int(pillar_rows[0]["token"])
        pillar_canvas_layer = record.get("pillar_canvas_layer")
        if type(pillar_canvas_layer) is not int:
            return _not_tested("actual pillar canvas-layer ordering is missing")
        overlay_records: dict[str, Any] = {}
        for key in required_overlay_keys:
            row = dict(overlay[key])
            if not _rect_inside_image(row["rect"], images["A"].shape[1], images["A"].shape[0]):
                return _not_tested(f"{key} rectangle is outside the native O1 image", overlays=overlay)
            sy, sx = _rect_xywh(row["rect"], images["A"].shape[1], images["A"].shape[0])
            overlap = int(np.count_nonzero(pillar_mask[sy, sx]))
            above = int(row["canvas_layer"]) > pillar_canvas_layer
            row["pillar_opaque_pixel_intersection"] = overlap
            row["readability_basis"] = "actual visible production node and measured text fits its recorded control; an overlapping rectangle has no rendered text-pixel comparison"
            row["layer_above_pillar"] = above
            if overlap:
                row["status"] = "NOT_TESTED"
                row["reason"] = (f"{key} overlaps {overlap} opaque pillar pixels; actual rendered text-pixel visibility "
                                  "has no comparison evidence")
                if status == "PASS":
                    status = "NOT_TESTED"
                    reason = row["reason"]
            overlay_records[key] = row
        return {"status": status, "reason": reason,
                "unit_visible_body_contribution_pixels": with_pillar,
                "same_frame_no_pillar_unit_contribution_pixels": without_pillar,
                "body_rect_denominator_pixels": denominator,
                "body_contribution_ratio": ratio, "required_ratio": 0.60,
                "rgb_tolerance_per_channel": BODY_RGB_TOLERANCE,
                "alpha_tolerance": BODY_ALPHA_TOLERANCE,
                "body_pixel_definition": "within Unit.get_overhead_body_rect_screen; A-C and B-D per-pixel RGBA8 difference, RGB max-channel >2 or alpha >1 counts actual Unit contribution",
                "same_frame": True, "frame_id": record["frame_id"],
                "state_images": {role: states[role]["image"] for role in "ABCD"},
                "overlays": overlay_records,
                "pillar_stable_id": record.get("pillar_stable_id"),
                "pillar_canvas_layer": pillar_canvas_layer,
                "pillar_alpha": record.get("pillar_alpha"),
                "pillar_alpha_input": record.get("pillar_alpha_input"),
                "forecast_path": record.get("forecast_path"),
                "limitations": ["The unit contribution ratio is computed from controlled actual-frame image differences, not from isolated alpha or RGB mismatch against a single control.",
                                "The official custom-drawn DamageForecaster panel and the separately rendered Unit-overhead damage Label are both recorded and tested."]}
    except (OSError, KeyError, TypeError, ValueError, IndexError) as error:
        return _not_tested(str(error))


def measure_t6_margin(legacy: dict[str, Any]) -> dict[str, Any]:
    measurements = legacy.get("measurements", {})
    rows = measurements.get("instances", []) if isinstance(measurements, dict) else []
    inspected: list[dict[str, Any]] = []
    unresolved = 0
    failures = 0
    for row in rows:
        if not isinstance(row, dict) or row.get("type") != "pillar":
            continue
        t6 = row.get("T6", {})
        legacy_status = t6.get("status") if isinstance(t6, dict) else None
        delta = t6.get("median_delta_l") if isinstance(t6, dict) else None
        valid_delta = isinstance(delta, (int, float)) and math.isfinite(float(delta))
        if legacy_status not in {"PASS", "FAIL"} or not valid_delta:
            unresolved += 1
            if legacy_status == "NOT_TESTED":
                unresolved_reason = (t6.get("reason") if isinstance(t6, dict) else None) \
                    or "legacy T6 geometry or provenance is NOT_TESTED"
            elif legacy_status not in {"PASS", "FAIL"}:
                unresolved_reason = "legacy T6 status does not establish a measured result"
            else:
                unresolved_reason = "finite legacy T6 median_delta_l is missing or invalid"
            inspected_row = {"stable_id": row.get("stable_id"), "status": "NOT_TESTED",
                             "legacy_T6_status": legacy_status,
                             "reason": unresolved_reason}
            if valid_delta:
                inspected_row["legacy_T6_median_delta_l"] = float(delta)
            inspected.append(inspected_row)
            continue
        margin = float(delta) - 10.0
        passed = float(delta) >= T6_MARGIN
        failures += int(not passed)
        inspected.append({"stable_id": row.get("stable_id"), "status": "PASS" if passed else "FAIL",
                          "legacy_T6_status": legacy_status,
                          "legacy_T6_median_delta_l": float(delta),
                          "distance_from_legacy_threshold_10": margin,
                          "distance_from_r9_target_10_5": float(delta) - T6_MARGIN,
                          "required_minimum": T6_MARGIN})
    status = "NOT_TESTED" if not inspected or unresolved else ("FAIL" if failures else "PASS")
    return {"status": status, "quality_target": "R9 margin target: T6 median_delta_l >= 10.5",
            "legacy_T6_threshold_unchanged": 10,
            "legacy_T6_status_and_value_unchanged": True,
            "inspected_instances": inspected}


def _rect_inside_image(value: Any, width: int, height: int) -> bool:
    if not isinstance(value, list) or len(value) != 4:
        return False
    rect = np.asarray(value, dtype=np.float64)
    return bool(np.isfinite(rect).all() and rect[2] > 0 and rect[3] > 0
                and rect[0] >= 0 and rect[1] >= 0
                and rect[0] + rect[2] <= width and rect[1] + rect[3] <= height)


def _r9_source_errors(capture: dict[str, Any], source_root: Path) -> list[str]:
    config = capture.get("capture_config", {})
    if not isinstance(config, dict):
        config = {}
    candidate = capture.get("candidate", {})
    if not isinstance(candidate, dict):
        candidate = {}
    hashes = candidate.get("source_sha256", {})
    sources = capture.get("sources", {})
    errors: list[str] = []
    if config.get("capture_entry_script") != CAPTURE_ENTRY:
        errors.append("capture config does not identify the R9 capture entry")
    if config.get("capture_script_inheritance") != list(R9_CAPTURE_SCRIPT_CHAIN):
        errors.append("capture config inheritance chain is not R9 -> R7 -> frozen R6 base")
    if not isinstance(hashes, dict):
        hashes = {}
        errors.append("candidate source_sha256 is not an object")
    if not isinstance(sources, dict):
        sources = {}
        errors.append("capture manifest sources are not an object")
    if candidate.get("capture_entry_script") != CAPTURE_ENTRY:
        errors.append("candidate does not identify the R9 capture entry")
    if candidate.get("capture_script_inheritance") != list(R9_CAPTURE_SCRIPT_CHAIN):
        errors.append("candidate inheritance chain differs from the R9 capture config")
    if config.get("composite_occupancy_shader") != "res://tests/claude_review/terrain_composite_occupancy.gdshader":
        errors.append("capture config does not bind the frozen R7 occupancy shader")
    for relative in (*v3.R7_SOURCE_PATHS, *R9_SOURCE_PATHS):
        path = source_root / relative
        try:
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
        except OSError:
            errors.append(f"capture source file missing: {relative}")
            continue
        if hashes.get(relative) != digest:
            errors.append(f"candidate does not bind current capture source: {relative}")
        if sources.get("res://" + relative) != digest:
            errors.append(f"capture manifest sources do not bind current file: {relative}")
    capture_script = source_root / "tests/claude_review/capture_terrain_readability_r9.gd"
    try:
        script_text = capture_script.read_text(encoding="utf-8")
    except OSError:
        script_text = ""
    if re.search(r"\.modulate(?:\.a)?\s*=|\.set\(\s*['\"]modulate", script_text):
        errors.append("R9 capture directly writes a pillar/unit modulation instead of reading the production fade")
    return errors


def _validate_r9_occupancy_binding(manifest_path: Path, capture: dict[str, Any],
                                   semantic: dict[str, Any], source_root: Path
                                   ) -> tuple[list[str], dict[str, np.ndarray]]:
    """Apply V3 occupancy checks while replacing only its R7-entry equality gate."""
    errors = v3.occupancy_metadata_errors(capture, semantic)
    errors.extend(_r9_source_errors(capture, source_root))
    arrays: dict[str, np.ndarray] = {}
    frame = semantic.get("frame", {}) if isinstance(semantic, dict) else {}
    if not isinstance(frame, dict):
        return errors + ["R7 semantic frame structure is invalid"], arrays
    case = capture.get("case", {}) if isinstance(capture, dict) else {}
    requested_size = case.get("requested_resolution") if isinstance(case, dict) else None
    if not isinstance(requested_size, list) or len(requested_size) != 2:
        return errors + ["capture requested_resolution is invalid"], arrays
    occupancy = semantic.get("composite_occupancy", {})
    controls = semantic.get("native_occupancy_controls", {})
    if not isinstance(occupancy, dict) or not isinstance(controls, dict):
        return errors + ["R7 occupancy or native controls are missing/invalid"], arrays
    errors.extend(v3._viewport_errors(occupancy, frame, requested_size))
    if controls.get("viewport", {}).get("image_size") != [176, 40]:
        errors.append("native N1-N5 control PNG size is invalid")
    forbidden_paths = {row.get("path") for row in frame.get("images", {}).values()
                       if isinstance(row, dict)}
    seen_paths: set[Path] = set()
    for label, record, expected_size in (
            ("composite_occupancy", occupancy, requested_size),
            ("native_occupancy_controls", controls, [176, 40])):
        image_record = record.get("image", {})
        try:
            relative_name = image_record.get("path")
            if relative_name in forbidden_paths:
                raise ValueError("R7 image reuses a frozen semantic PNG")
            path = sidecar._safe_relative(manifest_path.parent, relative_name)
            if path in seen_paths:
                raise ValueError("R7 occupancy/control images reuse one PNG")
            seen_paths.add(path)
            arrays[label] = sidecar._read_rgba_png(
                path, expected_size=expected_size,
                expected_sha256=image_record.get("sha256"),
                expected_bytes=image_record.get("bytes"))
        except (OSError, TypeError, ValueError) as error:
            errors.append(f"{label}: {error}")
    occupancy_pixels = arrays.get("composite_occupancy")
    if occupancy_pixels is not None:
        alpha = occupancy_pixels[..., 3]
        tokens = v3._token_pixels(occupancy_pixels)
        if np.any((alpha != 0) & (alpha != 255)):
            errors.append("R7 occupancy alpha has a value other than 0 or 255")
        if np.any((alpha == 0) & np.any(occupancy_pixels[..., :3] != 0, axis=2)):
            errors.append("R7 empty occupancy background token is nonzero")
        if np.any((alpha == 255) & (tokens == 0)):
            errors.append("R7 occupied pixel has a zero instance token")
        declared = {row.get("token") for row in frame.get("instance_tokens", [])
                    if isinstance(row, dict) and type(row.get("token")) is int}
        observed = set(map(int, np.unique(tokens))) - {0}
        if not observed.issubset(declared):
            errors.append("R7 occupancy image contains an undeclared token")
    controls_pixels = arrays.get("native_occupancy_controls")
    if controls_pixels is not None:
        if np.any((controls_pixels[..., 3] != 0) & (controls_pixels[..., 3] != 255)):
            errors.append("native occupancy control alpha has a value other than 0 or 255")
        control_tokens = v3._token_pixels(controls_pixels)
        for case_id, x, y, expected_token in v3.NATIVE_CONTROL_SAMPLES:
            observed = int(control_tokens[y, x])
            if observed != expected_token:
                errors.append(f"native {case_id} sample ({x},{y}) expected {expected_token}, got {observed}")
    return errors, arrays


def _legacy_v3_result(manifest_path: Path, source_root: Path,
                      expected_head: str) -> dict[str, Any]:
    """Keep the frozen V3 output schema/measurements, with R9's entry gate."""
    source_root = source_root.resolve()
    old = v3.v2.baseline.validate(manifest_path, source_root, expected_head)
    capture = json.loads(manifest_path.read_bytes())
    semantic_path = manifest_path.parent / sidecar.SIDECAR_MANIFEST
    errors: list[str] = []
    if old["capture_preconditions"] == "PASS":
        semantic = json.loads(semantic_path.read_bytes())
        side_errors, arrays = sidecar.validate_sidecar_binding(manifest_path, capture, semantic)
        images, image_errors = sidecar._load_capture_images(manifest_path, capture)
        occupancy_errors, occupancy_arrays = _validate_r9_occupancy_binding(
            manifest_path, capture, semantic, source_root)
        errors = side_errors + image_errors + occupancy_errors
        if errors:
            unavailable = {"status": "NOT_TESTED", "reason": "R7 occupancy provenance/alignment gate failed"}
            rows = [{"stable_id": row["stable_id"], "type": row["type"],
                     "T1": dict(unavailable), "T6": dict(unavailable),
                     "T1_required_for_acceptance": row["type"] != "tree",
                     "T6_required_for_acceptance": row["type"] != "tree"
                     and old.get("case", {}).get("requested_resolution") == [1280, 720]}
                    for row in old["T1"]["instances"]]
            c9_rows = [{"stable_id": row["stable_id"], **unavailable}
                       for row in rows if row["type"] == "tree"]
            values = {"instances": rows, "summary": {}, "C9_trees": c9_rows,
                      "C9_gate": {"status": "NOT_TESTED",
                                  "denominator_all_declared_trees": len(c9_rows)},
                      "tree_numeric_gate": {"status": "NOT_TESTED"}}
        else:
            arrays.update(occupancy_arrays)
            values = v3.measure(capture, old["frozen_v3_case"], images, arrays, semantic)
    else:
        unavailable = {"status": "NOT_TESTED", "reason": "frozen source/capture/alignment gate failed"}
        rows = [{"stable_id": row["stable_id"], "type": row["type"],
                 "T1": dict(unavailable), "T6": dict(unavailable),
                 "T1_required_for_acceptance": row["type"] != "tree",
                 "T6_required_for_acceptance": row["type"] != "tree"
                 and old.get("case", {}).get("requested_resolution") == [1280, 720]}
                for row in old["T1"]["instances"]]
        c9_rows = [{"stable_id": row["stable_id"], **unavailable}
                   for row in rows if row["type"] == "tree"]
        values = {"instances": rows, "summary": {}, "C9_trees": c9_rows,
                  "C9_gate": {"status": "NOT_TESTED",
                              "denominator_all_declared_trees": len(c9_rows)},
                  "tree_numeric_gate": {"status": "NOT_TESTED"}}
        semantic = {}
    sources = []
    for relative in v3.R7_SOURCE_PATHS:
        raw = (source_root / relative).read_bytes()
        sources.append({"path": relative, "bytes": len(raw),
                        "sha256": hashlib.sha256(raw).hexdigest()})
    capture_preconditions = "PASS" if old["capture_preconditions"] == "PASS" and not errors else "FAIL"
    return {"schema_version": v3.SCHEMA, "candidate_head": expected_head,
            "capture_preconditions": capture_preconditions, "capture_errors": errors,
            "case": old.get("case"),
            "rules": {"U1": "new composite occupancy tokens; group-outside four-neighbour edges; touching external/unknown occlusion is unmeasurable and remains in denominator",
                      "sample_exclusions": "grid/UI, other instance or unknown source pixels, and source alpha <= 0.5; same-token alpha <= 0.5 excludes samples without blocking the whole adjacent edge",
                      "inner_radius_px": 2, "outer_radius_px": 4,
                      "local_min_delta_l": 10, "required_perimeter_share": 0.8,
                      "T1_median_delta_l": 15, "T6_median_delta_l": 10,
                      "tree_option": "A", "tree_T1_T6": "diagnostic_only",
                      "tree_gates": ["frozen T3", "C9", "independent visual review"],
                      "C9_model": v3.v2.cvd.SOURCE, "C9_delta_e00_min": 10,
                      "C9_tree_fraction_min": 0.8,
                      "T2_T3_C9_thresholds_frozen": True,
                      "original_source_alpha_and_uncertainty_bytes_frozen": True,
                      "PNG_pixels_modified": False},
            "measurement_sources": sources, "measurements": values,
            "legacy_v1_baseline": old, "art_acceptance": "NOT_TESTED",
            "six_case_coverage": False}


def validate(manifest_path: Path, source_root: Path, expected_head: str) -> dict[str, Any]:
    legacy = _legacy_v3_result(manifest_path, source_root, expected_head)

    capture: dict[str, Any] = {}
    semantic: dict[str, Any] = {}
    g1 = _not_tested("R9 legacy capture prerequisites failed")
    side_iqr = _not_tested("R9 legacy capture prerequisites failed")
    if legacy.get("capture_preconditions") == "PASS":
        try:
            capture = json.loads(manifest_path.read_bytes())
            semantic_path = manifest_path.parent / sidecar.SIDECAR_MANIFEST
            semantic = json.loads(semantic_path.read_bytes())
            g1 = measure_g1(manifest_path, capture, semantic)
            side_iqr = measure_pillar_side_iqr(manifest_path, capture, semantic)
        except (OSError, json.JSONDecodeError) as error:
            g1 = _not_tested(f"R9 semantic sidecar could not be read: {error}")
    else:
        try:
            capture = json.loads(manifest_path.read_bytes())
        except (OSError, json.JSONDecodeError):
            capture = {}
    o1 = measure_o1(manifest_path, capture) if capture else _not_tested("capture manifest could not be read")
    t6_margin = measure_t6_margin(legacy)
    r9_gate = "PASS" if all(row.get("status") == "PASS" for row in (g1, side_iqr, o1, t6_margin)) else (
        "FAIL" if any(row.get("status") == "FAIL" for row in (g1, side_iqr, o1, t6_margin)) else "NOT_TESTED")
    r9_sources = []
    for relative in R9_SOURCE_PATHS:
        path = source_root / relative
        try:
            raw = path.read_bytes()
        except OSError:
            r9_sources.append({"path": relative, "status": "MISSING"})
        else:
            r9_sources.append({"path": relative, "bytes": len(raw),
                               "sha256": hashlib.sha256(raw).hexdigest()})
    legacy["r9"] = {"schema_version": SCHEMA, "capture_entry_script": CAPTURE_ENTRY,
                    "supplemental_gate": r9_gate, "G1": g1,
                    "pillar_side_iqr": side_iqr, "O1": o1,
                    "T6_margin": t6_margin,
                    "measurement_sources": r9_sources,
                    "legacy_v3_result_retained": True,
                    "thresholds": {"G1_outer_delta_L_star": [6.0, 8.0],
                                   "G1_core_third_groove_delta_L_star_min": 4.0,
                                   "O1_minimum_visible_body_ratio": 0.60,
                                   "T6_legacy_threshold_unchanged": 10,
                                   "T6_R9_margin_target": T6_MARGIN,
                                   "pillar_side_iqr_l_star_minimum": 5.0}}
    return legacy


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    result = validate(args.manifest, args.source_root, args.candidate)
    args.out.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    r9 = result.get("r9", {})
    print(json.dumps({"capture_preconditions": result.get("capture_preconditions"),
                      "legacy_summary": result.get("measurements", {}).get("summary", {}),
                      "legacy_C9": result.get("measurements", {}).get("C9_gate", {}),
                      "r9_gate": r9.get("supplemental_gate"),
                      "G1": r9.get("G1", {}).get("status"),
                      "O1": r9.get("O1", {}).get("status"),
                      "T6_margin": r9.get("T6_margin", {}).get("status"),
                      "capture_errors": result.get("capture_errors", [])}, ensure_ascii=False))
    # Preserve V3's CLI contract: this code is a source/capture precondition
    # failure. Domain measurements remain explicit in JSON without stopping
    # the runner before the independent follow-up command.
    return 0 if result.get("capture_preconditions") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
