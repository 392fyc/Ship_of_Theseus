"""R6-0 T1 entry: frozen contour math, S2/S3 groups, exact native originals.

The group defines the outside of the object cluster. Each instance keeps its
own radius-2 inner ring, radius-4 neighbourhood and full four-edge perimeter.
Group diagnostics never replace an instance's FAIL or NOT_TESTED result.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np

import claude_review_checks as checks
import terrain_readability_metrics as metrics
import validate_terrain_semantic_sidecar as sidecar


SCHEMA = "terrain-contour-readback/1"
KINDS = ("wall", "pillar", "tree", "rubble")


def measure_contour(lightness: np.ndarray, own: np.ndarray,
                    group: np.ndarray, excluded: np.ndarray) -> dict:
    """Only constrain the frozen outer ring; never edit its perimeter weights."""
    if (group.dtype != bool or excluded.dtype != bool or own.dtype != bool
            or any(value.shape != own.shape for value in (group, excluded, lightness))):
        raise ValueError("T1 masks and lightness must have the same dimensions")
    if np.any(own & ~group):
        raise ValueError("instance mask is not contained in its group")
    group_outer = metrics.morph(group, 4) & ~group
    allowed = group_outer & ~excluded
    measured = metrics.contour(lightness, own, ~allowed)
    # This is exactly the ring that the frozen contour function sampled.
    own_outer = metrics.morph(own, 4) & ~own
    sampled_outer = own_outer & allowed
    inner = own & ~metrics.morph(own, 2, erode=True)
    inner_l = float(np.median(lightness[inner])) if inner.any() else None
    group_outer_l = float(np.median(lightness[allowed])) if allowed.any() else None
    group_complete = not (group[:4].any() or group[-4:].any()
                          or group[:, :4].any() or group[:, -4:].any())
    # S2/S3 share the complete group exterior for the global reference, while
    # the frozen local radius-4 test remains specific to this instance.
    local_global_gap = measured.get("median_delta_l")
    group_gap = abs(inner_l - group_outer_l) if inner_l is not None and group_outer_l is not None else None
    padded = np.pad(own, 1)
    neighbours = (padded[:-2, 1:-1].astype(int) + padded[2:, 1:-1]
                  + padded[1:-1, :-2] + padded[1:-1, 2:])
    perimeter = int(np.where(own, 4 - neighbours, 0).sum())
    measured.setdefault("perimeter_edges", perimeter)
    measured.setdefault("measurable_share", 0.0 if not sampled_outer.any() else None)
    measured.setdefault("passing_share", 0.0 if not sampled_outer.any() else None)
    measured["covered_perimeter_edges"] = (
        round(measured["measurable_share"] * perimeter)
        if measured["measurable_share"] is not None else None)
    measured["passing_perimeter_edges"] = (
        round(measured["passing_share"] * perimeter)
        if measured["passing_share"] is not None else None)
    if measured["status"] in ("PASS", "FAIL"):
        measured["status"] = ("PASS" if group_gap >= 15
                              and measured["passing_share"] >= .8 else "FAIL")
    if not group_complete:
        measured.update(status="NOT_TESTED", reason="组并集靠近图边，完整组外环不可观测")
        group_gap = None
    measured.update({
        "group_outer_pixels": int(group_outer.sum()),
        "instance_outer_candidate_pixels": int(own_outer.sum()),
        "instance_outer_inside_group_pixels": int((own_outer & group).sum()),
        "instance_outer_excluded_pixels": int((own_outer & group_outer & excluded).sum()),
        "instance_outer_sample_pixels": int(sampled_outer.sum()),
        "inner_median_l": inner_l,
        "group_outer_median_l": group_outer_l,
        "group_outer_complete": group_complete,
        "median_delta_l": group_gap,
        "instance_local_outer_median_delta_l_diagnostic": local_global_gap,
        "outer_median_l": float(np.median(lightness[sampled_outer]))
        if sampled_outer.any() else None,
        "perimeter_scope": "full visible instance four-neighbour edges",
        "reference_scope": "complete group exterior for global median; instance radius-4 for local shares",
        "excluded_edges_retained_in_denominator": True,
    })
    return measured


def measure_instances(capture: dict, images: dict, pair: np.ndarray,
                      coverage: np.ndarray, instance_tokens: list[dict]) -> dict:
    """Called only after provenance/alignment gates; synthetic arrays are testable."""
    lightness = checks.lab(images["main"][..., :3])[..., 0]
    visible, uncertain = sidecar.alpha_sample_masks(coverage)
    tokens = ((pair[..., 0].astype(np.uint32) << 16)
              | (pair[..., 1].astype(np.uint32) << 8)
              | pair[..., 2].astype(np.uint32))
    ui_units = images["exclusions"][..., 3] > 127
    grid = images["grid"][..., 3] > 127
    grouped: dict[str, dict] = {}
    for kind in ("wall", "tree"):
        grouped.update(sidecar._captured_connected_groups(
            capture, instance_tokens, pair, coverage, kind=kind,
            member_part_codes=sidecar.TREE_PART_CODES if kind == "tree" else None,
        ))
    records = {row["stable_id"]: row for row in instance_tokens
               if row.get("type") in KINDS}
    # Occluding HUD/units are not visible object geometry. Grid pixels do not
    # carve holes into geometry; the grid is excluded only from outside samples.
    masks = {key: (tokens == row["token"]) & visible & ~ui_units
             for key, row in records.items()}
    groups: dict[str, dict] = {}
    rows: list[dict] = []
    for stable_id in sorted(records):
        record = records[stable_id]
        info = grouped.get(stable_id, {})
        membership = info.get("measurement_group", {})
        members = membership.get("members", [stable_id])
        group_id = membership.get("group_id", stable_id)
        group = np.zeros(visible.shape, bool)
        for member in members:
            group |= masks[member]
        group_tokens = [records[member]["token"] for member in members]
        others = (coverage[..., 3] == 255) & ~np.isin(tokens, group_tokens)
        excluded = ui_units | grid | others
        result = measure_contour(lightness, masks[stable_id], group, excluded)
        if membership and membership.get("status") != "PASS":
            result = {**result, "status": "NOT_TESTED",
                      "reason": "captured group connectivity is incomplete"}
        result.update({"stable_id": stable_id, "type": record["type"],
                       "token": record["token"], "group_id": group_id,
                       "group_members": members,
                       "visible_pixels": int(masks[stable_id].sum()),
                       "uncertain_pixels_retained": int((masks[stable_id] & uncertain).sum()),
                       "all_instance_parts_included": True})
        rows.append(result)
        if group_id not in groups:
            diagnostic = measure_contour(lightness, group, group, excluded)
            diagnostic["perimeter_scope"] = "full visible group-union four-neighbour edges"
            groups[group_id] = {"group_id": group_id, "members": members,
                                "type": record["type"], "T1": diagnostic,
                                "diagnostic_only": True}
    summary = {kind: {status: sum(row["type"] == kind and row["status"] == status
                                 for row in rows)
                      for status in ("PASS", "FAIL", "NOT_TESTED")} for kind in KINDS}
    return {"instances": rows, "group_diagnostics": list(groups.values()),
            "summary": summary}


def validate(manifest_path: Path, source_root: Path, expected_head: str) -> dict:
    frozen = sidecar.validate_case(manifest_path, source_root, expected_head,
                                   measurement_version="v3")
    capture = json.loads(manifest_path.read_bytes())
    sidecar_path = manifest_path.parent / sidecar.SIDECAR_MANIFEST
    semantic = json.loads(sidecar_path.read_bytes())
    # Use the governing exact-byte PNG loaders; do not decode new labels or
    # accept precomputed notification/summary values as pixel evidence.
    errors, arrays = sidecar.validate_sidecar_binding(manifest_path, capture, semantic)
    images, image_errors = sidecar._load_capture_images(manifest_path, capture)
    errors += image_errors
    ready = (not errors and frozen["frozen_capture_preconditions"] == "PASS"
             and frozen["semantic_sidecar_preconditions"] == "PASS")
    if ready:
        measurement = measure_instances(capture, images, arrays["semantic_pair"],
                                        arrays["semantic_coverage"], semantic["frame"]["instance_tokens"])
    else:
        rows = [{"stable_id": row.get("stable_id"), "type": row.get("type"),
                 "status": "NOT_TESTED", "reason": "source, capture or alignment gate failed"}
                for row in semantic.get("frame", {}).get("instance_tokens", []) if row.get("type") in KINDS]
        measurement = {"instances": rows, "group_diagnostics": [],
                       "summary": {kind: {status: sum(row["type"] == kind and row["status"] == status
                                                      for row in rows)
                                          for status in ("PASS", "FAIL", "NOT_TESTED")}
                                   for kind in KINDS}}
    originals = [{"role": "capture-manifest", "bytes": manifest_path.stat().st_size,
                  "sha256": hashlib.sha256(manifest_path.read_bytes()).hexdigest()},
                 {"role": "semantic-sidecar-manifest", "bytes": sidecar_path.stat().st_size,
                  "sha256": hashlib.sha256(sidecar_path.read_bytes()).hexdigest()}]
    for origin in (capture, semantic.get("frame", {})):
        originals.extend({"role": role, "bytes": row.get("bytes"), "sha256": row.get("sha256")}
                         for role, row in origin.get("images", {}).items())
    for role, row in semantic.get("classification_maps", {}).items():
        originals.append({"role": "classification:" + role, "bytes": row.get("bytes"),
                          "sha256": row.get("sha256")})
    portrait = capture.get("portrait_companion", {}).get("image", {})
    if portrait:
        originals.append({"role": "portrait:C4", "bytes": portrait.get("bytes"),
                          "sha256": portrait.get("sha256")})
    return {"schema_version": SCHEMA, "candidate_head": expected_head,
            "case": capture.get("case"), "capture_preconditions": "PASS" if ready else "FAIL",
            "errors": errors, "original_inputs": originals,
            "measurement_code": {"path": "tests/claude_review/validate_terrain_contour_v1.py",
                                 "sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()},
            "rules": {"inner_radius_px": 2, "outer_radius_px": 4,
                      "median_delta_l_min": 15, "local_delta_l_min": 10,
                      "passing_perimeter_share_min": .8, "measurable_perimeter_share_min": .8,
                      "frozen_local_metric": "terrain_readability_metrics.contour",
                      "group_global_metric": "instance inner median vs complete group exterior median",
                      "groups": "unchanged S2/S3 captured adjacency and visible pixel contact",
                      "tree_group_topology": "existing codes 7/8/9 connectivity determines members",
                      "tree_group_outer_geometry": "full visible member tokens including branches and roots",
                      "tree_geometry": "full visible instance including branches and roots",
                      "outside_exclusions": ["other props", "grid", "HUD/units/exclusions"],
                      "contact_shadow_remains_visible": True,
                      "source_pngs_modified": False},
            "T1": measurement, "frozen_v3_case": frozen,
            "art_acceptance": "NOT_TESTED", "six_case_coverage": False}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    output = validate(args.manifest, args.source_root, args.candidate)
    args.out.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"capture_preconditions": output["capture_preconditions"],
                      "T1": output["T1"]["summary"]}, ensure_ascii=False))
    # Numerical FAIL is a valid measured baseline, not an execution failure.
    return 0 if output["capture_preconditions"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
