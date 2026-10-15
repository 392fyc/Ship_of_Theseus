"""U1: measure each instance only on the captured group's outside boundary.

Known same-group seams are not contour edges. Unknown/occluded outside edges
remain in the denominator. Radii and numerical thresholds are unchanged.
"""
from __future__ import annotations

import numpy as np

import terrain_readability_metrics as frozen


def edge_weights(own: np.ndarray, group: np.ndarray) -> np.ndarray:
    if own.dtype != bool or group.dtype != bool or own.shape != group.shape or own.ndim != 2:
        raise ValueError("instance/group must be equally sized bool masks")
    if np.any(own & ~group):
        raise ValueError("instance is not contained in group")
    padded = np.pad(group, 1)
    neighbours = (padded[:-2, 1:-1].astype(int) + padded[2:, 1:-1]
                  + padded[1:-1, :-2] + padded[1:-1, 2:])
    return np.where(own, 4 - neighbours, 0)


def measure(lightness: np.ndarray, own: np.ndarray, group: np.ndarray,
            excluded: np.ndarray, *, squint: bool = False) -> dict:
    if (lightness.shape != own.shape or excluded.shape != own.shape
            or excluded.dtype != bool or not np.isfinite(lightness).all()):
        raise ValueError("lightness/exclusion dimensions or values are invalid")
    weights = edge_weights(own, group)
    full_perimeter = int(edge_weights(own, own).sum())
    perimeter = int(weights.sum())
    inner = own & ~frozen.morph(own, 2, erode=True)
    outer = frozen.morph(group, 4) & ~group & ~excluded
    inner_l = float(np.median(lightness[inner])) if inner.any() else None
    outer_l = float(np.median(lightness[outer])) if outer.any() else None
    gap = abs(inner_l - outer_l) if inner_l is not None and outer_l is not None else None
    stats = {"median_delta_l": gap, "inner_median_l": inner_l,
             "group_outer_median_l": outer_l,
             "perimeter_edges": perimeter, "full_instance_perimeter_edges": full_perimeter,
             "same_group_seam_edges_removed": full_perimeter - perimeter,
             "inner_pixels": int(inner.sum()), "group_outer_sample_pixels": int(outer.sum()),
             "covered_perimeter_edges": None, "passing_perimeter_edges": None,
             "measurable_share": None, "passing_share": None,
             "perimeter_scope": "instance edges with neighbour outside captured group",
             "unknown_excluded_edges_retained": True,
             "inner_radius_px": 2, "outer_radius_px": 4,
             "metric": "T6" if squint else "T1",
             "sigma_px": 2 if squint else None}

    def missing(reason: str, category: str) -> dict:
        return {"status": "NOT_TESTED", "reason": reason, "reason_category": category, **stats}

    if not own.any():
        return missing("实例可见掩膜为空", "empty_instance")
    if group[:4].any() or group[-4:].any() or group[:, :4].any() or group[:, -4:].any():
        stats["median_delta_l"] = None
        return missing("完整组外环在画布边缘不可观测", "group_clipped")
    if not frozen.morph(own, 2, erode=True).any():
        return missing("实例没有足够的2像素内核", "no_interior_core")
    if not perimeter:
        return missing("实例没有暴露在组外的轮廓边", "no_exposed_group_boundary")
    if not outer.any():
        stats.update(covered_perimeter_edges=0, passing_perimeter_edges=0,
                     measurable_share=0., passing_share=0.)
        return missing("完整组外环没有有效样本", "no_group_exterior")
    covered = passing = 0
    yy, xx = np.mgrid[-4:5, -4:5]
    disk = xx * xx + yy * yy <= 16
    for y, x in np.argwhere(weights > 0):
        cut = np.s_[y-4:y+5, x-4:x+5]
        a, b = inner[cut] & disk, outer[cut] & disk
        if not a.any() or not b.any():
            continue
        weight = int(weights[y, x])
        covered += weight
        local_gap = abs(float(np.median(lightness[cut][a]) - np.median(lightness[cut][b])))
        if local_gap >= 10:
            passing += weight
    stats.update(covered_perimeter_edges=covered, passing_perimeter_edges=passing,
                 measurable_share=covered/perimeter, passing_share=passing/perimeter)
    if covered/perimeter < .8:
        return missing("可测组外轮廓不足80%", "insufficient_coverage")
    passed = gap >= (10 if squint else 15) and (squint or passing/perimeter >= .8)
    return {"status": "PASS" if passed else "FAIL", **stats}
