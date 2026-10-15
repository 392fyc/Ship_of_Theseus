"""R7 U1 over the native composite occupancy tokens; radii and thresholds stay frozen."""
from __future__ import annotations

from collections.abc import Iterable, Sequence

import numpy as np

import terrain_readability_metrics as frozen


def composite_occupancy(draw_masks: Sequence[np.ndarray], draw_alphas: Sequence[np.ndarray | float],
                        draw_tokens: Sequence[int], *,
                        shape: tuple[int, int] | None = None) -> np.ndarray:
    """Rebuild token ownership from already-rasterized draw leaves, in draw order.

    This helper performs only the approved alpha cut and ordering rule. Callers
    must rasterize each Sprite2D/Polygon2D/Line2D leaf using its recorded native
    transform, texture sampling, bounds, and effective alpha first. Alpha may be
    a normalized scalar/float array or an RGBA8 alpha-byte array.
    """
    if not (len(draw_masks) == len(draw_alphas) == len(draw_tokens)):
        raise ValueError("draw masks, alpha values, and tokens must have equal lengths")
    inferred_shape = shape
    for mask in draw_masks:
        if not isinstance(mask, np.ndarray) or mask.dtype != np.bool_ or mask.ndim != 2:
            raise ValueError("each draw mask must be a two-dimensional bool array")
        if inferred_shape is None:
            inferred_shape = mask.shape
        if mask.shape != inferred_shape:
            raise ValueError("draw masks must have one common image shape")
    if inferred_shape is None:
        raise ValueError("shape is required when the draw list is empty")
    occupancy = np.zeros(inferred_shape, dtype=np.uint32)
    for mask, alpha, token in zip(draw_masks, draw_alphas, draw_tokens, strict=True):
        if type(token) is not int or not 1 <= token <= 0xFFFFFF:
            raise ValueError("draw token must be a nonzero 24-bit integer")
        raw_alpha = np.asarray(alpha)
        alpha_values = (raw_alpha.astype(np.float64) / 255.0
                        if raw_alpha.dtype == np.uint8 else raw_alpha.astype(np.float64))
        if alpha_values.ndim == 0:
            if not np.isfinite(alpha_values) or not 0.0 <= float(alpha_values) <= 1.0:
                raise ValueError("draw alpha must be finite and within [0, 1]")
            writes = mask if float(alpha_values) > 0.5 else np.zeros(inferred_shape, dtype=bool)
        else:
            if alpha_values.shape != inferred_shape or not np.isfinite(alpha_values).all() \
                    or np.any((alpha_values < 0.0) | (alpha_values > 1.0)):
                raise ValueError("draw alpha arrays must match the image and stay within [0, 1]")
            writes = mask & (alpha_values > 0.5)
        occupancy[writes] = token
    return occupancy


def token_masks(occupancy_tokens: np.ndarray, own_token: int,
                group_tokens: Iterable[int]) -> tuple[np.ndarray, np.ndarray]:
    """Return visible owner and captured-group masks from final pass tokens."""
    if not isinstance(occupancy_tokens, np.ndarray) or occupancy_tokens.ndim != 2 \
            or occupancy_tokens.dtype.kind not in "ui":
        raise ValueError("occupancy tokens must be a two-dimensional integer array")
    if type(own_token) is not int or not 1 <= own_token <= 0xFFFFFF:
        raise ValueError("own token must be a nonzero 24-bit integer")
    token_set = tuple(sorted(set(group_tokens)))
    if own_token not in token_set or any(type(token) is not int or not 1 <= token <= 0xFFFFFF
                                         for token in token_set):
        raise ValueError("group tokens must be valid and include the own token")
    return occupancy_tokens == own_token, np.isin(occupancy_tokens, token_set)


def edge_weights(own: np.ndarray, group: np.ndarray) -> np.ndarray:
    """Count exposed four-neighbour edges on each owned pixel."""
    if own.dtype != bool or group.dtype != bool or own.shape != group.shape or own.ndim != 2:
        raise ValueError("instance/group must be equally sized bool masks")
    if np.any(own & ~group):
        raise ValueError("instance is not contained in group")
    padded = np.pad(group, 1)
    neighbours = (padded[:-2, 1:-1].astype(np.uint8) + padded[2:, 1:-1]
                  + padded[1:-1, :-2] + padded[1:-1, 2:])
    return np.where(own, 4 - neighbours, 0).astype(np.uint8)


def blocked_edge_weights(own: np.ndarray, group: np.ndarray,
                         blocked_pixels: np.ndarray) -> np.ndarray:
    """Count exposed edges touching a known other/unknown occluder pixel.

    The occluded edge remains part of the denominator. Same-token translucent
    source pixels are deliberately not supplied as blocked pixels; they can be
    excluded from samples without declaring every nearby edge unmeasurable.
    """
    if (own.dtype != bool or group.dtype != bool or blocked_pixels.dtype != bool
            or own.shape != group.shape or own.shape != blocked_pixels.shape or own.ndim != 2):
        raise ValueError("instance, group, and blocked masks must be equally sized bool arrays")
    if np.any(own & ~group):
        raise ValueError("instance is not contained in group")
    padded_group = np.pad(group, 1)
    padded_blocked = np.pad(blocked_pixels, 1)
    blocked_total = np.zeros(own.shape, dtype=np.uint8)
    shifts = ((slice(0, -2), slice(1, -1)), (slice(2, None), slice(1, -1)),
              (slice(1, -1), slice(0, -2)), (slice(1, -1), slice(2, None)))
    for ys, xs in shifts:
        neighbour_group = padded_group[ys, xs]
        boundary = own & ~neighbour_group
        neighbour_blocked = padded_blocked[ys, xs]
        blocked_total += boundary & (blocked_pixels | neighbour_blocked)
    return blocked_total


def measure(lightness: np.ndarray, own: np.ndarray, group: np.ndarray,
            sample_excluded: np.ndarray, *, blocked_pixels: np.ndarray | None = None,
            squint: bool = False) -> dict:
    """Measure frozen U1 edges using occupancy masks and per-edge occlusion.

    ``sample_excluded`` removes pixels from inner and outer lightness samples.
    ``blocked_pixels`` additionally makes each touching outer edge unmeasurable;
    those edge counts stay in ``perimeter_edges`` and in every share denominator.
    """
    if blocked_pixels is None:
        blocked_pixels = np.zeros(own.shape, dtype=bool)
    if (lightness.shape != own.shape or sample_excluded.shape != own.shape
            or sample_excluded.dtype != bool or blocked_pixels.shape != own.shape
            or blocked_pixels.dtype != bool or not np.isfinite(lightness).all()):
        raise ValueError("lightness/exclusion/blocked dimensions or values are invalid")
    weights = edge_weights(own, group)
    total_perimeter = int(weights.sum())
    blocked_weights = blocked_edge_weights(own, group, blocked_pixels)
    occluded_edges = int(blocked_weights.sum())
    eligible_weights = weights.astype(np.int16) - blocked_weights.astype(np.int16)
    eligible_weights = np.maximum(eligible_weights, 0)
    full_perimeter = int(edge_weights(own, own).sum())
    inner = own & ~frozen.morph(own, 2, erode=True) & ~sample_excluded
    outer = frozen.morph(group, 4) & ~group & ~sample_excluded
    inner_l = float(np.median(lightness[inner])) if inner.any() else None
    outer_l = float(np.median(lightness[outer])) if outer.any() else None
    gap = abs(inner_l - outer_l) if inner_l is not None and outer_l is not None else None
    stats = {"median_delta_l": gap, "inner_median_l": inner_l,
             "group_outer_median_l": outer_l,
             "perimeter_edges": total_perimeter,
             "full_instance_perimeter_edges": full_perimeter,
             "same_group_seam_edges_removed": full_perimeter - total_perimeter,
             "occluded_perimeter_edges": occluded_edges,
             "locally_eligible_perimeter_edges": total_perimeter - occluded_edges,
             "inner_pixels": int(inner.sum()), "group_outer_sample_pixels": int(outer.sum()),
             "covered_perimeter_edges": None, "passing_perimeter_edges": None,
             "measurable_share": None, "passing_share": None,
             "perimeter_scope": "occupancy-token instance edges with neighbour outside captured occupancy group",
             "unknown_excluded_edges_retained": True,
             "other_or_unknown_touching_edges_retained": True,
             "inner_radius_px": 2, "outer_radius_px": 4,
             "metric": "T6" if squint else "T1",
             "sigma_px": 2 if squint else None}

    def missing(reason: str, category: str) -> dict:
        return {"status": "NOT_TESTED", "reason": reason, "reason_category": category, **stats}

    if not own.any():
        return missing("实例占据掩膜为空", "empty_instance")
    if group[:4].any() or group[-4:].any() or group[:, :4].any() or group[:, -4:].any():
        stats["median_delta_l"] = None
        return missing("完整组外环在画布边缘不可观测", "group_clipped")
    if not frozen.morph(own, 2, erode=True).any():
        return missing("实例没有足够的2像素内核", "no_interior_core")
    if not total_perimeter:
        return missing("实例没有暴露在组外的轮廓边", "no_exposed_group_boundary")
    if not outer.any():
        stats.update(covered_perimeter_edges=0, passing_perimeter_edges=0,
                     measurable_share=0.0, passing_share=0.0)
        return missing("完整组外环没有有效样本", "no_group_exterior")
    covered = passing = 0
    yy, xx = np.mgrid[-4:5, -4:5]
    disk = xx * xx + yy * yy <= 16
    for y, x in np.argwhere(eligible_weights > 0):
        cut = np.s_[y-4:y+5, x-4:x+5]
        a, b = inner[cut] & disk, outer[cut] & disk
        if not a.any() or not b.any():
            continue
        weight = int(eligible_weights[y, x])
        covered += weight
        local_gap = abs(float(np.median(lightness[cut][a]) - np.median(lightness[cut][b])))
        if local_gap >= 10:
            passing += weight
    measurable_share = covered / total_perimeter
    stats.update(covered_perimeter_edges=covered, passing_perimeter_edges=passing,
                 measurable_share=measurable_share, passing_share=passing/total_perimeter)
    if measurable_share < 0.8:
        return missing("可测组外轮廓不足80%", "insufficient_coverage")
    passed = gap >= (10 if squint else 15) and (squint or passing/total_perimeter >= 0.8)
    return {"status": "PASS" if passed else "FAIL", **stats}
