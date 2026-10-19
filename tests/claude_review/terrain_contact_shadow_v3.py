"""T4 v3 contact-shadow diagnostic for a bound capture, semantic manifest, and PNG set.

The CLI reads original-size PNGs only. It verifies every input byte digest against
its capture manifest and writes a portable JSON report without local paths.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path, PurePosixPath, PureWindowsPath
import sys
from typing import Any

import numpy as np
from PIL import Image

import claude_review_checks as checks
import terrain_readability_metrics as frozen


SAMPLE_STEP_PX = 0.5
OUTBOARD_PROBE_PX = 1.0
SHADOW_EDGE_RADIUS_PX = 2.0
MIN_SAMPLE_PIXELS = 20
MIN_EDGE_COVERAGE = 0.60
MAX_EDGE_GAP_PX = 1.0
LINE_FACE_BOUNDARY_TOLERANCE_PX = 1e-6
REQUIRED_IMAGE_ROLES = (
    "main",
    "contact_shadow",
    "exclusions",
    "grid",
    "ground",
    "ground_without_shadow",
    "instance_ids",
    "props",
)


class DiagnosticError(ValueError):
    """Raised when a capture cannot be measured without guessing."""


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_bytes().decode("utf-8-sig"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise DiagnosticError(f"cannot read JSON input {path.name}: {exc}") from exc
    if not isinstance(value, dict):
        raise DiagnosticError(f"JSON input {path.name} must contain an object")
    return value


def safe_capture_path(png_dir: Path, manifest_path: str) -> Path:
    normalized = manifest_path.replace("\\", "/")
    posix = PurePosixPath(normalized)
    windows = PureWindowsPath(normalized)
    if posix.is_absolute() or windows.is_absolute() or windows.drive:
        raise DiagnosticError("capture PNG paths must be relative to --png-dir")
    if any(part in ("", ".", "..") for part in posix.parts):
        raise DiagnosticError("capture PNG path contains an unsafe segment")
    return png_dir.joinpath(*posix.parts)


def _load_png(
    path: Path,
    role: str,
    expected_sha256: str,
    expected_size: tuple[int, int],
) -> tuple[np.ndarray, dict[str, str]]:
    if not path.is_file():
        raise DiagnosticError(f"missing PNG for role {role}: {path.name}")
    actual_sha = sha256_file(path)
    if not expected_sha256 or actual_sha != expected_sha256:
        raise DiagnosticError(f"PNG byte hash does not match capture manifest: {role}")
    with Image.open(path) as image:
        rgba = np.asarray(image.convert("RGBA"))
    width, height = expected_size
    if rgba.shape != (height, width, 4):
        raise DiagnosticError(
            f"PNG dimensions for {role} are {rgba.shape[1]}x{rgba.shape[0]}, "
            f"expected {width}x{height}"
        )
    return rgba, {
        "file": path.name,
        "bytes_sha256": actual_sha,
        "manifest_sha256": expected_sha256,
    }


def _hex_rgb(color: str) -> tuple[int, int, int]:
    raw = color.removeprefix("#")
    if len(raw) not in (6, 8):
        raise DiagnosticError(f"invalid instance color token: {color!r}")
    try:
        return tuple(int(raw[index:index + 2], 16) for index in (0, 2, 4))
    except ValueError as exc:
        raise DiagnosticError(f"invalid instance color token: {color!r}") from exc


def _affine(points: np.ndarray, transform: list[float]) -> np.ndarray:
    if len(transform) != 6:
        raise DiagnosticError("captured transform must have six values")
    if not np.isfinite(np.asarray(transform, dtype=np.float64)).all():
        raise DiagnosticError("captured transform contains non-finite values")
    points = np.asarray(points, dtype=np.float64)
    if not np.isfinite(points).all():
        raise DiagnosticError("captured geometry contains non-finite values")
    matrix = np.array(
        [[transform[0], transform[2]], [transform[1], transform[3]]],
        dtype=np.float64,
    )
    offset = np.array(transform[4:6], dtype=np.float64)
    return np.asarray(points, dtype=np.float64) @ matrix.T + offset


def _polygon_from_leaf(leaf: dict[str, Any], canvas: list[float]) -> np.ndarray:
    if leaf.get("node_class") != "Polygon2D":
        raise DiagnosticError("contact geometry must come from a captured Polygon2D")
    polygon = np.asarray(leaf.get("polygon"), dtype=np.float64)
    if polygon.ndim != 2 or polygon.shape[1] != 2 or len(polygon) < 3:
        raise DiagnosticError("captured polygon has invalid vertices")
    world = _affine(polygon, leaf.get("global_transform", []))
    return _affine(world, canvas)


def _cross_2d(first: np.ndarray, second: np.ndarray) -> float:
    return float(first[0] * second[1] - first[1] * second[0])


def _validate_wall_side_quad(polygon: np.ndarray, stable_id: str, leaf_index: int) -> None:
    if polygon.shape != (4, 2) or not np.isfinite(polygon).all():
        raise DiagnosticError(
            f"{stable_id} wall_side leaf {leaf_index} is not a finite four-vertex polygon"
        )
    edges = np.roll(polygon, -1, axis=0) - polygon
    lengths = np.linalg.norm(edges, axis=1)
    if np.any(lengths <= 1e-9):
        raise DiagnosticError(
            f"{stable_id} wall_side leaf {leaf_index} has a zero-length edge"
        )
    turns = np.asarray([
        _cross_2d(edges[index], edges[(index + 1) % 4])
        for index in range(4)
    ])
    if not (np.all(turns > 0.0) or np.all(turns < 0.0)):
        raise DiagnosticError(
            f"{stable_id} wall_side leaf {leaf_index} is not a convex quadrilateral"
        )


def _point_in_convex_polygon(point: np.ndarray, polygon: np.ndarray) -> bool:
    """Include the boundary within only captured-transform roundoff tolerance."""
    area_twice = sum(
        _cross_2d(polygon[index], polygon[(index + 1) % len(polygon)])
        for index in range(len(polygon))
    )
    if not math.isfinite(area_twice) or area_twice == 0.0:
        raise DiagnosticError("captured wall_side face has invalid area")
    winding = 1.0 if area_twice > 0.0 else -1.0
    for index, start in enumerate(polygon):
        edge = polygon[(index + 1) % len(polygon)] - start
        edge_length = float(np.linalg.norm(edge))
        if edge_length <= 1e-9:
            raise DiagnosticError("captured wall_side face has a zero-length edge")
        signed_distance = winding * _cross_2d(edge, point - start) / edge_length
        if signed_distance < -LINE_FACE_BOUNDARY_TOLERANCE_PX:
            return False
    return True


def _leaf_identity(leaf_index: int, leaf: dict[str, Any]) -> dict[str, Any]:
    return {
        "leaf_index": leaf_index,
        "node_name": leaf.get("node_name"),
        "relative_path": leaf.get("relative_path"),
    }


def _edge_key(a: np.ndarray, b: np.ndarray) -> tuple[tuple[float, float], tuple[float, float]]:
    first = (round(float(a[0]), 6), round(float(a[1]), 6))
    second = (round(float(b[0]), 6), round(float(b[1]), 6))
    return tuple(sorted((first, second)))  # type: ignore[return-value]


def _append_polygon_edge(
    segments: list[dict[str, Any]],
    seen: set[tuple[tuple[float, float], tuple[float, float]]],
    polygon: np.ndarray,
    start_index: int,
    end_index: int,
    source: str,
) -> bool:
    a = polygon[start_index]
    b = polygon[end_index]
    vector = b - a
    length = float(np.linalg.norm(vector))
    if length <= 1e-9:
        raise DiagnosticError("captured contact edge has zero length")
    key = _edge_key(a, b)
    if key in seen:
        return False
    seen.add(key)

    normal = np.array([-vector[1], vector[0]], dtype=np.float64) / length
    midpoint = (a + b) / 2.0
    center = polygon.mean(axis=0)
    if float(np.dot(normal, center - midpoint)) > 0:
        normal = -normal
    segments.append({
        "a": a,
        "b": b,
        "outward": normal,
        "length": length,
        "source": source,
    })
    return True


def _captured_feet(
    capture: dict[str, Any],
    semantic: dict[str, Any],
    canvas: list[float],
) -> tuple[list[dict[str, Any]], int]:
    capture_instances = {
        item["stable_id"]: item for item in capture.get("instances", [])
        if isinstance(item, dict) and item.get("stable_id")
    }
    feet: list[dict[str, Any]] = []
    duplicate_wall_edges = 0

    for record in semantic["frame"].get("instance_tokens", []):
        kind = record.get("type")
        if kind not in ("wall", "pillar"):
            continue
        stable_id = record.get("stable_id")
        if not stable_id or stable_id not in capture_instances:
            raise DiagnosticError("semantic contact instance is absent from capture")
        leaves = record.get("draw_leaf_inputs")
        if not isinstance(leaves, list) or not leaves:
            raise DiagnosticError(f"missing captured draw geometry for {stable_id}")

        segments: list[dict[str, Any]] = []
        seen: set[tuple[tuple[float, float], tuple[float, float]]] = set()
        source_roles: list[str] = []
        if kind == "pillar":
            parts = capture_instances[stable_id].get("parts", {}).get("parts", [])
            if len(parts) != len(leaves):
                raise DiagnosticError(
                    f"pillar leaf and captured part counts differ for {stable_id}"
                )
            base_indices = [
                index for index, part in enumerate(parts)
                if part.get("role") == "pillar_base"
            ]
            if len(base_indices) != 1:
                raise DiagnosticError(
                    f"expected one captured pillar_base part for {stable_id}"
                )
            polygon = _polygon_from_leaf(leaves[base_indices[0]], canvas)
            if len(polygon) != 6:
                raise DiagnosticError(
                    f"{stable_id} pillar base is not the captured six-vertex base"
                )
            for index in range(len(polygon)):
                _append_polygon_edge(
                    segments, seen, polygon, index, (index + 1) % len(polygon),
                    "captured_pillar_base_polygon",
                )
            source_roles.append("pillar_base")
        else:
            parts = capture_instances[stable_id].get("parts", {}).get("parts", [])
            if len(parts) != len(leaves):
                raise DiagnosticError(
                    f"wall leaf and captured part counts differ for {stable_id}"
                )
            side_faces: list[tuple[int, dict[str, Any], np.ndarray]] = []
            side_lines: list[tuple[int, dict[str, Any], np.ndarray]] = []
            for leaf_index, (part, leaf) in enumerate(zip(parts, leaves)):
                if part.get("role") != "wall_side":
                    continue
                node_class = leaf.get("node_class")
                if node_class == "Polygon2D":
                    polygon = _polygon_from_leaf(leaf, canvas)
                    if len(polygon) != 4:
                        raise DiagnosticError(
                            f"{stable_id} wall_side contact panel is not a four-vertex polygon"
                        )
                    _validate_wall_side_quad(polygon, stable_id, leaf_index)
                    side_faces.append((leaf_index, leaf, polygon))
                elif node_class == "Line2D":
                    width = leaf.get("width")
                    if not isinstance(width, (int, float)) or not math.isfinite(float(width)):
                        raise DiagnosticError(
                            f"{stable_id} wall_side Line2D leaf {leaf_index} has invalid width"
                        )
                    if float(width) != 1.0:
                        raise DiagnosticError(
                            f"{stable_id} wall_side Line2D leaf {leaf_index} is not the captured 1px seam"
                        )
                    points = np.asarray(leaf.get("points"), dtype=np.float64)
                    if points.ndim != 2 or points.shape[1] != 2 or len(points) < 2:
                        raise DiagnosticError(
                            f"{stable_id} wall_side Line2D leaf {leaf_index} has invalid centerline points"
                        )
                    centerline = _affine(points, leaf.get("global_transform", []))
                    centerline = _affine(centerline, canvas)
                    if np.any(np.linalg.norm(np.diff(centerline, axis=0), axis=1) <= 1e-9):
                        raise DiagnosticError(
                            f"{stable_id} wall_side Line2D leaf {leaf_index} has a zero-length segment"
                        )
                    side_lines.append((leaf_index, leaf, centerline))
                else:
                    raise DiagnosticError(
                        f"{stable_id} wall_side leaf {leaf_index} has unsupported node type: {node_class}"
                    )
            if not side_faces:
                raise DiagnosticError(
                    f"no captured Polygon2D wall_side bottom geometry found for {stable_id}"
                )
            for leaf_index, _, polygon in side_faces:
                if _append_polygon_edge(
                    segments, seen, polygon, 2, 3, "captured_wall_side_bottom_edge"
                ):
                    source_roles.append("wall_side")
                else:
                    duplicate_wall_edges += 1
            excluded_wall_side_lines: list[dict[str, Any]] = []
            for line_index, line_leaf, centerline in side_lines:
                matched_faces = [
                    (face_index, face_leaf, polygon)
                    for face_index, face_leaf, polygon in side_faces
                    if all(_point_in_convex_polygon(point, polygon) for point in centerline)
                ]
                if not matched_faces:
                    raise DiagnosticError(
                        f"{stable_id} wall_side Line2D leaf {line_index} has no captured four-vertex face containing its centerline"
                    )
                bottom_edge_groups: dict[
                    tuple[tuple[float, float], tuple[float, float]],
                    list[dict[str, Any]],
                ] = {}
                for face_index, face_leaf, polygon in matched_faces:
                    group_key = _edge_key(polygon[2], polygon[3])
                    bottom_edge_groups.setdefault(group_key, []).append(
                        _leaf_identity(face_index, face_leaf)
                    )
                if len(bottom_edge_groups) != 1:
                    raise DiagnosticError(
                        f"{stable_id} wall_side Line2D leaf {line_index} spans {len(bottom_edge_groups)} distinct physical bottom-edge groups"
                    )
                bottom_edge_key, bottom_edge_faces = next(iter(bottom_edge_groups.items()))
                excluded_wall_side_lines.append({
                    "line_leaf": _leaf_identity(line_index, line_leaf),
                    "width_px": float(line_leaf["width"]),
                    "centerline_points_px": centerline.tolist(),
                    "matched_side_face_leaves": bottom_edge_faces,
                    "physical_bottom_edge_group": {
                        "edge_key_px": [list(point) for point in bottom_edge_key],
                        "side_face_leaf_count": len(bottom_edge_faces),
                        "side_face_leaves": bottom_edge_faces,
                    },
                })
        if not segments:
            raise DiagnosticError(f"no actual bottom geometry found for {stable_id}")
        feet.append({
            "stable_id": stable_id,
            "type": kind,
            "color": _hex_rgb(capture_instances[stable_id].get("color", "")),
            "segments": segments,
            "source_roles": source_roles,
            "wall_side_polygon_leaf_count": len(side_faces) if kind == "wall" else 0,
            "excluded_wall_side_lines": (
                excluded_wall_side_lines if kind == "wall" else []
            ),
        })

    if not feet:
        raise DiagnosticError("capture contains no wall or pillar contact geometry")
    return feet, duplicate_wall_edges


def _cell_width_px(semantic: dict[str, Any], canvas: list[float]) -> tuple[float, float]:
    points: list[tuple[float, float, float, float]] = []
    for item in semantic["frame"].get("instance_tokens", []):
        if item.get("type") not in ("wall", "pillar"):
            continue
        logical = item.get("logical_position")
        transform = item.get("source_global_transform")
        if not isinstance(logical, list) or len(logical) < 2:
            continue
        if not isinstance(transform, list) or len(transform) != 6:
            continue
        points.append((
            float(logical[0]), float(logical[1]),
            float(transform[4]), float(transform[5]),
        ))
    if len(points) < 3:
        raise DiagnosticError("not enough captured instances to bind original cell scale")

    logical = np.asarray([[x, y, 1.0] for x, y, _, _ in points], dtype=np.float64)
    world = np.asarray([[wx, wy] for _, _, wx, wy in points], dtype=np.float64)
    affine, _, _, _ = np.linalg.lstsq(logical, world, rcond=None)
    residual = float(np.abs(logical @ affine - world).max())
    cell_vector = affine[0] - affine[1]
    screen_vector = _affine(np.asarray([cell_vector]), [*canvas[:4], 0.0, 0.0])[0]
    cell_width = float(np.linalg.norm(screen_vector))
    if not math.isfinite(cell_width) or cell_width <= 0:
        raise DiagnosticError("captured cell scale is invalid")
    return cell_width, residual


def equal_arc_length_samples(
    segments: list[dict[str, Any]],
    spacing_px: float = SAMPLE_STEP_PX,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Return segment points at equal arc spacing and exact per-sample arc weights."""
    if spacing_px <= 0:
        raise ValueError("spacing_px must be positive")
    point_rows: list[np.ndarray] = []
    normal_rows: list[np.ndarray] = []
    weight_rows: list[float] = []
    for segment in segments:
        a = np.asarray(segment["a"], dtype=np.float64)
        b = np.asarray(segment["b"], dtype=np.float64)
        length = float(np.linalg.norm(b - a))
        if length <= 1e-9:
            continue
        count = max(1, int(math.ceil(length / spacing_px)))
        t = (np.arange(count, dtype=np.float64) + 0.5) / count
        point_rows.append(a[None, :] + t[:, None] * (b - a)[None, :])
        normal_rows.append(
            np.repeat(np.asarray(segment["outward"], dtype=np.float64)[None, :], count, axis=0)
        )
        weight_rows.extend([length / count] * count)
    if not point_rows:
        return np.empty((0, 2)), np.empty((0, 2)), np.empty((0,))
    return (
        np.concatenate(point_rows, axis=0),
        np.concatenate(normal_rows, axis=0),
        np.asarray(weight_rows, dtype=np.float64),
    )


def _raster_indices(points: np.ndarray, width: int, height: int) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    x = np.floor(points[:, 0]).astype(np.int64)
    y = np.floor(points[:, 1]).astype(np.int64)
    in_bounds = (x >= 0) & (x < width) & (y >= 0) & (y < height)
    return x, y, in_bounds


def _classify_visible_edge(
    points: np.ndarray,
    outward_normals: np.ndarray,
    weights: np.ndarray,
    maps: dict[str, np.ndarray],
    own_color: tuple[int, int, int],
) -> tuple[np.ndarray, dict[str, dict[str, float | int]]]:
    """Test the ground-facing side, without reading contact_shadow."""
    height, width = maps["ground"].shape[:2]
    probe_points = points + outward_normals * OUTBOARD_PROBE_PX
    x, y, in_bounds = _raster_indices(probe_points, width, height)
    reason = np.full(len(points), "visible_ground_edge", dtype=object)
    reason[~in_bounds] = "outside_capture"

    inside = np.flatnonzero(in_bounds)
    if len(inside):
        ix, iy = x[inside], y[inside]
        props = maps["props"][iy, ix, 3] > 127
        exclusions = maps["exclusions"][iy, ix, 3] > 127
        grid = maps["grid"][iy, ix, 3] > 127
        ground_valid = (
            (maps["ground"][iy, ix, 3] > 250)
            & (maps["ground_without_shadow"][iy, ix, 3] > 250)
        )
        ids = maps["instance_ids"][iy, ix]
        id_valid = ids[:, 3] > 127
        same_owner = id_valid & np.all(ids[:, :3] == np.asarray(own_color), axis=1)

        for local, global_index in enumerate(inside):
            if props[local]:
                if same_owner[local]:
                    reason[global_index] = "owner_opaque_prop"
                elif id_valid[local]:
                    reason[global_index] = "other_opaque_prop"
                else:
                    reason[global_index] = "unattributed_opaque_prop"
            elif exclusions[local]:
                reason[global_index] = "ui_or_unit_exclusion"
            elif grid[local]:
                reason[global_index] = "grid"
            elif not ground_valid[local]:
                reason[global_index] = "missing_ground_pair"
    visible = reason == "visible_ground_edge"
    evidence: dict[str, dict[str, float | int]] = {}
    categories = (
        "visible_ground_edge",
        "owner_opaque_prop",
        "other_opaque_prop",
        "unattributed_opaque_prop",
        "ui_or_unit_exclusion",
        "grid",
        "missing_ground_pair",
        "outside_capture",
    )
    for category in categories:
        selected = reason == category
        evidence[category] = {
            "sample_count": int(selected.sum()),
            "arc_length_px": float(weights[selected].sum()),
        }
    return visible, evidence


def _distances_to_segments(points: np.ndarray, segments: list[dict[str, Any]]) -> np.ndarray:
    if len(points) == 0:
        return np.empty((0,), dtype=np.float64)
    result = np.full(len(points), np.inf, dtype=np.float64)
    for segment in segments:
        a = np.asarray(segment["a"], dtype=np.float64)
        b = np.asarray(segment["b"], dtype=np.float64)
        vector = b - a
        denom = float(vector @ vector)
        if denom <= 1e-18:
            continue
        t = np.clip(((points - a) @ vector) / denom, 0.0, 1.0)
        nearest = a[None, :] + t[:, None] * vector[None, :]
        result = np.minimum(result, np.linalg.norm(points - nearest, axis=1))
    return result


def _within_radius(points: np.ndarray, targets: np.ndarray, radius: float) -> np.ndarray:
    if len(points) == 0 or len(targets) == 0:
        return np.zeros(len(points), dtype=bool)
    result = np.zeros(len(points), dtype=bool)
    radius_sq = radius * radius
    for start in range(0, len(points), 256):
        batch = points[start:start + 256]
        delta = batch[:, None, :] - targets[None, :, :]
        result[start:start + len(batch)] = np.any(
            np.einsum("ijk,ijk->ij", delta, delta) <= radius_sq,
            axis=1,
        )
    return result


def evaluate_t4(
    shadow_l: np.ndarray,
    underlying_l: np.ndarray,
    edge_distances_px: np.ndarray,
    visible_edge_length_px: float,
    shadow_covered_edge_length_px: float,
    cell_width_px: float,
) -> dict[str, Any]:
    """Apply frozen darkness/width rules and adopted contact/coverage safeguards."""
    shadow_l = np.asarray(shadow_l, dtype=np.float64)
    underlying_l = np.asarray(underlying_l, dtype=np.float64)
    distances = np.asarray(edge_distances_px, dtype=np.float64)
    if shadow_l.ndim != 1 or underlying_l.ndim != 1 or distances.ndim != 1:
        raise ValueError("T4 inputs must be one-dimensional sample arrays")
    if shadow_l.shape != underlying_l.shape or shadow_l.shape != distances.shape:
        raise ValueError("T4 sample arrays must describe the same pixels")
    if (
        not np.isfinite(shadow_l).all()
        or not np.isfinite(underlying_l).all()
        or not np.isfinite(distances).all()
        or not math.isfinite(visible_edge_length_px)
        or not math.isfinite(shadow_covered_edge_length_px)
        or not math.isfinite(cell_width_px)
    ):
        raise ValueError("T4 inputs must be finite")
    if visible_edge_length_px < 0 or shadow_covered_edge_length_px < 0:
        raise ValueError("edge lengths cannot be negative")
    if shadow_covered_edge_length_px > visible_edge_length_px + 1e-6:
        raise ValueError("covered edge length cannot exceed visible edge length")
    if np.any(distances < 0) or cell_width_px <= 0:
        raise ValueError("distances must be nonnegative and cell width positive")

    sample_count = int(len(distances))
    width_p90 = float(np.percentile(distances, 90)) if sample_count else None
    width_max = float(distances.max()) if sample_count else None
    minimum_distance = float(distances.min()) if sample_count else None
    coverage = (
        float(shadow_covered_edge_length_px / visible_edge_length_px)
        if visible_edge_length_px > 0 else None
    )
    result: dict[str, Any] = {
        "status": "NOT_TESTED",
        "sample_count": sample_count,
        "sample_minimum": MIN_SAMPLE_PIXELS,
        "width_p90_px": width_p90,
        "width_max_px": width_max,
        "minimum_shadow_to_edge_distance_px": minimum_distance,
        "visible_bottom_edge_length_px": float(visible_edge_length_px),
        "shadow_covered_visible_edge_length_px": float(shadow_covered_edge_length_px),
        "visible_edge_coverage_ratio": coverage,
        "cell_width_px": float(cell_width_px),
        "frozen_metric": None,
        "checks": None,
    }
    if sample_count < MIN_SAMPLE_PIXELS:
        result["reason"] = "fewer than 20 eligible same-frame shadow pixels"
        return result
    if visible_edge_length_px <= 0:
        result["reason"] = "no visible bottom-edge arc remains after occlusion filtering"
        return result
    assert width_p90 is not None and minimum_distance is not None and coverage is not None

    frozen_result = frozen.contact_shadow(
        shadow_l, underlying_l, width_p90, cell_width_px
    )
    checks_result = {
        "frozen_darkness_and_p90_width": frozen_result["status"],
        "touches_bottom_edge_within_1px": minimum_distance <= MAX_EDGE_GAP_PX,
        "covers_at_least_60_percent_of_visible_bottom_edge": coverage >= MIN_EDGE_COVERAGE,
    }
    overall = (
        frozen_result["status"] == "PASS"
        and checks_result["touches_bottom_edge_within_1px"]
        and checks_result["covers_at_least_60_percent_of_visible_bottom_edge"]
    )
    result.update({
        "status": "PASS" if overall else "FAIL",
        "frozen_metric": frozen_result,
        "checks": checks_result,
    })
    return result


def analyze(
    capture_path: Path,
    semantic_path: Path,
    png_dir: Path,
) -> dict[str, Any]:
    capture = read_json(capture_path)
    semantic = read_json(semantic_path)
    capture_sha = sha256_bytes(capture_path.read_bytes())
    semantic_sha = sha256_bytes(semantic_path.read_bytes())

    frame = semantic.get("frame")
    if not isinstance(frame, dict):
        raise DiagnosticError("semantic manifest is missing frame geometry")
    if semantic.get("capture_manifest_sha256") != capture_sha:
        raise DiagnosticError("semantic manifest is not bound to these capture-manifest bytes")
    frame_id = frame.get("frame_id")
    image_metadata = capture.get("images")
    viewport = capture.get("viewports", {}).get("main")
    if not isinstance(image_metadata, dict) or not isinstance(viewport, dict):
        raise DiagnosticError("capture manifest lacks image or main viewport metadata")
    image_size = viewport.get("image_size")
    if not isinstance(image_size, list) or len(image_size) != 2:
        raise DiagnosticError("capture manifest lacks original main image size")
    expected_size = (int(image_size[0]), int(image_size[1]))

    maps: dict[str, np.ndarray] = {}
    png_hashes: dict[str, dict[str, str]] = {}
    for role in REQUIRED_IMAGE_ROLES:
        entry = image_metadata.get(role)
        if not isinstance(entry, dict):
            raise DiagnosticError(f"capture manifest lacks required PNG role {role}")
        if str(entry.get("frame_id")) != str(frame_id):
            raise DiagnosticError(f"PNG role {role} is not from semantic frame {frame_id}")
        if entry.get("image_size") != list(expected_size):
            raise DiagnosticError(f"PNG role {role} does not retain the main capture size")
        path = safe_capture_path(png_dir, str(entry.get("path", "")))
        rgba, binding = _load_png(
            path, role, str(entry.get("sha256", "")), expected_size
        )
        maps[role] = rgba
        png_hashes[role] = binding

    main_capture = next(
        (row for row in capture.get("captures", []) if row.get("role") == "main"),
        None,
    )
    if not isinstance(main_capture, dict):
        raise DiagnosticError("capture manifest lacks the main screenshot binding")
    if (
        main_capture.get("sha256") != png_hashes["main"]["bytes_sha256"]
        or main_capture.get("file") != png_hashes["main"]["file"]
    ):
        raise DiagnosticError("main screenshot metadata disagrees with PNG bytes")

    canvas = viewport.get("canvas_transform")
    if not isinstance(canvas, list) or len(canvas) != 6:
        raise DiagnosticError("main viewport lacks its captured canvas transform")
    feet, duplicate_wall_edges = _captured_feet(capture, semantic, canvas)
    cell_width, cell_residual = _cell_width_px(semantic, canvas)
    if cell_residual > 1e-5:
        raise DiagnosticError(
            f"captured cell transform fit residual is too large: {cell_residual}"
        )

    alpha = {name: image[..., 3] for name, image in maps.items()}
    eligible = (
        (alpha["contact_shadow"] > 127)
        & (alpha["ground"] > 250)
        & (alpha["ground_without_shadow"] > 250)
        & (alpha["props"] <= 127)
        & (alpha["exclusions"] <= 127)
        & (alpha["grid"] <= 127)
    )
    ys, xs = np.where(eligible)
    shadow_points = np.column_stack((xs + 0.5, ys + 0.5)).astype(np.float64)
    all_distances = np.stack([
        _distances_to_segments(shadow_points, foot["segments"])
        for foot in feet
    ], axis=0)
    owner = np.argmin(all_distances, axis=0) if len(shadow_points) else np.empty(0, dtype=int)

    ground_l = checks.lab(maps["ground"][..., :3])[..., 0]
    underlying_l = checks.lab(maps["ground_without_shadow"][..., :3])[..., 0]
    rows: list[dict[str, Any]] = []

    for index, foot in enumerate(feet):
        edge_points, normals, edge_weights = equal_arc_length_samples(foot["segments"])
        visible, occlusion = _classify_visible_edge(
            edge_points, normals, edge_weights, maps, foot["color"]
        )
        visible_points = edge_points[visible]
        visible_weights = edge_weights[visible]
        visible_length = float(visible_weights.sum())

        owned_indices = np.flatnonzero(owner == index)
        owned_shadow_points = shadow_points[owned_indices]
        owned_distances = all_distances[index, owned_indices]
        if len(visible_points) and len(owned_shadow_points):
            covered = _within_radius(
                visible_points, owned_shadow_points, SHADOW_EDGE_RADIUS_PX
            )
            covered_length = float(visible_weights[covered].sum())
        else:
            covered_length = 0.0

        ys_i, xs_i = ys[owned_indices], xs[owned_indices]
        shadow_l = ground_l[ys_i, xs_i]
        underlying_l_samples = underlying_l[ys_i, xs_i]
        result = evaluate_t4(
            shadow_l,
            underlying_l_samples,
            owned_distances,
            visible_length,
            covered_length,
            cell_width,
        )
        result.update({
            "stable_id": foot["stable_id"],
            "type": foot["type"],
            "geometry": (
                "captured pillar_base Polygon2D perimeter"
                if foot["type"] == "pillar"
                else "unique captured wall_side bottom edges"
            ),
            "geometry_segment_count": len(foot["segments"]),
            "edge_sampling_spacing_px": SAMPLE_STEP_PX,
            "outboard_ground_probe_px": OUTBOARD_PROBE_PX,
            "shadow_neighbourhood_radius_px": SHADOW_EDGE_RADIUS_PX,
            "wall_side_polygon_leaf_count": foot["wall_side_polygon_leaf_count"],
            "excluded_wall_side_lines": foot["excluded_wall_side_lines"],
            "visible_edge_occlusion_evidence": occlusion,
        })
        rows.append(result)

    summary = {
        status: sum(1 for row in rows if row["status"] == status)
        for status in ("PASS", "FAIL", "NOT_TESTED")
    }
    source_commit = capture.get("candidate", {}).get("head")
    semantic_commit = semantic.get("capture_candidate", {}).get("head")
    if semantic_commit and source_commit and semantic_commit != source_commit:
        raise DiagnosticError("semantic and capture candidate commits differ")

    return {
        "schema": "sot-t4-contact-shadow-diagnostic/3",
        "diagnostic_origin": {
            "kind": "offline_derived_from_bound_original_capture",
            "is_cloud_command6_result": False,
            "scope_note": "离线派生诊断；它不是原云端 command6 结果。",
        },
        "evidence_scope": {
            "kind": "offline_derived_single_capture_measurement",
            "candidate_commit": source_commit,
            "case": capture.get("case", {}).get("name"),
            "fixture": capture.get("case", {}).get("fixture", {}).get("name"),
            "frame_id": frame_id,
            "scope_note": "离线单组测量仅适用于该捕获，不代表整体验收，也不是原云端 command6 结果。",
        },
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "candidate": {

            "commit": source_commit,
            "semantic_candidate_commit": semantic_commit,
            "source_sha256": semantic.get("candidate_source_sha256"),
        },
        "capture": {
            "case": capture.get("case"),
            "semantic_case": semantic.get("case"),
            "frame_id": frame_id,
            "size_px": [expected_size[0], expected_size[1]],
            "renderer": capture.get("renderer"),
            "same_frame_ground_pair": True,
        },
        "input_hashes": {
            "capture_manifest": {
                "file": capture_path.name,
                "bytes_sha256": capture_sha,
            },
            "semantic_manifest": {
                "file": semantic_path.name,
                "bytes_sha256": semantic_sha,
                "bound_capture_manifest_sha256": semantic.get("capture_manifest_sha256"),
                "semantic_input_sha256": semantic.get("semantic_input_sha256"),
            },
            "png_files": png_hashes,
            "measurement_sources": {
                "tool": {
                    "file": Path(__file__).name,
                    "bytes_sha256": sha256_file(Path(__file__)),
                },
                "frozen_metric": {
                    "file": Path(frozen.__file__).name,
                    "bytes_sha256": sha256_file(Path(frozen.__file__)),
                },
                "srgb_to_lab": {
                    "file": Path(checks.__file__).name,
                    "bytes_sha256": sha256_file(Path(checks.__file__)),
                },
            },
        },
        "method": {
            "frozen_formula": "terrain_readability_metrics.contact_shadow",
            "darkness_rule_lstar": [8, 12],
            "width_rule": "p90 Euclidean distance to captured bottom geometry <= half captured cell width; maximum is also reported",
            "touch_rule": "minimum eligible shadow-pixel-centre distance to bottom geometry <= 1px",
            "coverage_rule": "at least 0.60 of independently measured visible bottom-edge arc has an eligible shadow sample within 2px",
            "sample_rule": "fewer than 20 eligible same-frame shadow pixels is NOT_TESTED",
            "shadow_samples": "contact_shadow alpha>127, ground and ground_without_shadow alpha>250, props alpha<=127, grid alpha<=127, exclusions alpha<=127",
            "edge_denominator": "captured geometry sampled every <=0.5px by equal arc length; visible ground-facing side is tested 1px outboard against same-frame props, grid, exclusions, ground and ground_without_shadow; contact_shadow is never used to create denominator",
            "geometry": "pillar: unchanged six-vertex Polygon2D matched by captured pillar_base role; wall contact edges: unique bottom edges (vertices 2 to 3) from captured convex four-vertex wall_side Polygon2D faces only",
            "wall_side_line_exclusion": "only captured wall_side Line2D leaves with width exactly 1.0px and every transformed centerline vertex inside/on at least one captured wall_side quadrilateral are excluded from contact geometry; each line and matched face leaf identity are reported; unmatched lines and unknown wall_side node types are errors",
            "line_face_boundary_tolerance_px": LINE_FACE_BOUNDARY_TOLERANCE_PX,
            "coordinate_scale": "original capture pixels; captured Polygon2D global transform followed by captured main canvas transform; no image resize",
            "ui_exclusion_source": "capture exclusions PNG; manifest purpose records unit silhouettes and conservative drawable UI bounds",
            "props_occlusion_source": "same-frame props PNG alpha>0.5; instance_ids PNG attributes opaque owner/other tokens",
        },
        "geometry_audit": {
            "cell_width_px": cell_width,
            "cell_affine_fit_max_error_world_px": cell_residual,
            "edge_sample_spacing_px": SAMPLE_STEP_PX,
            "outboard_probe_px": OUTBOARD_PROBE_PX,
            "duplicate_wall_edges_removed": duplicate_wall_edges,
            "matched_wall_side_lines_excluded_from_contact_edges": sum(
                len(foot["excluded_wall_side_lines"]) for foot in feet
            ),
            "perimeter_not_derived_from_shadow_samples": True,
        },
        "summary": summary,
        "rows": rows,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--capture", "--capture-manifest", dest="capture", required=True,
        help="capture-manifest.json for the image set",
    )
    parser.add_argument(
        "--semantic", "--semantic-manifest", dest="semantic", required=True,
        help="semantic-sidecar-manifest.json bound to the capture manifest",
    )
    parser.add_argument(
        "--png-dir", required=True,
        help="directory containing the relative PNG paths named by the capture manifest",
    )
    parser.add_argument("--output", required=True, help="output JSON diagnostic path")
    args = parser.parse_args()

    if not sys.dont_write_bytecode:
        parser.error("run this command with python -B to avoid writing pycache")

    try:
        result = analyze(Path(args.capture), Path(args.semantic), Path(args.png_dir))
    except (DiagnosticError, OSError, ValueError, KeyError, TypeError, IndexError) as exc:
        parser.error(str(exc))

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False))
        handle.write("\n")
    print(json.dumps({
        "output": output.name,
        "candidate_commit": result["candidate"]["commit"],
        "is_cloud_command6_result": result["diagnostic_origin"]["is_cloud_command6_result"],
        "frame_id": result["capture"]["frame_id"],
        "summary": result["summary"],
        "rows": [
            {
                "stable_id": row["stable_id"],
                "status": row["status"],
                "sample_count": row["sample_count"],
                "darkness_l": (
                    row["frozen_metric"].get("darkness_l")
                    if row["frozen_metric"] else None
                ),
                "width_p90_px": row["width_p90_px"],
                "width_max_px": row["width_max_px"],
                "minimum_shadow_to_edge_distance_px": row[
                    "minimum_shadow_to_edge_distance_px"
                ],
                "visible_edge_coverage_ratio": row["visible_edge_coverage_ratio"],
            }
            for row in result["rows"]
        ],
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
