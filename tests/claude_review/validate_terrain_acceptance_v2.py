"""User-approved U1 boundaries and tree option A; frozen source gates first."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

import claude_review_checks as checks
import terrain_contour_v2 as contour
import terrain_cvd_machado as cvd
import terrain_readability_metrics as metrics
import validate_terrain_contour_v1 as baseline
import validate_terrain_semantic_sidecar as sidecar


SCHEMA = "terrain-acceptance-readback/2"
KINDS = baseline.KINDS


def c9_gate(rows: list[dict]) -> dict:
    total = len(rows)
    passed = sum(row.get("status") == "PASS" for row in rows)
    missing = sum(row.get("status") == "NOT_TESTED" for row in rows)
    return {"status": ("PASS" if passed / total >= .8 else "FAIL") if total else "NOT_TESTED",
            "passed": passed, "failed": total-passed-missing, "not_tested": missing,
            "denominator_all_declared_trees": total,
            "passing_fraction": passed/total if total else None,
            "required_fraction": .8, "required_delta_e00_each_mode": 10,
            "requires_both_modes_per_tree": True}


def contexts(capture: dict, images: dict, pair: np.ndarray, coverage: np.ndarray,
             records: list[dict]) -> list[dict]:
    visible, uncertain = sidecar.alpha_sample_masks(coverage)
    tokens = ((pair[..., 0].astype(np.uint32) << 16)
              | (pair[..., 1].astype(np.uint32) << 8) | pair[..., 2].astype(np.uint32))
    ui_units = images["exclusions"][..., 3] > 127
    grid = images["grid"][..., 3] > 127
    grouped = {}
    for kind in ("wall", "tree"):
        grouped.update(sidecar._captured_connected_groups(
            capture, records, pair, coverage, kind=kind,
            member_part_codes=sidecar.TREE_PART_CODES if kind == "tree" else None))
    by_id = {r["stable_id"]: r for r in records if r.get("type") in KINDS}
    masks = {key: (tokens == r["token"]) & visible & ~ui_units for key, r in by_id.items()}
    output = []
    for key in sorted(by_id):
        info = grouped.get(key, {}).get("measurement_group", {})
        members = info.get("members", [key])
        group = np.zeros(visible.shape, bool)
        for member in members:
            group |= masks[member]
        group_tokens = [by_id[member]["token"] for member in members]
        others = (coverage[..., 3] == 255) & ~np.isin(tokens, group_tokens)
        output.append({"record": by_id[key], "own": masks[key], "group": group,
                       "group_id": info.get("group_id", key), "members": members,
                       "group_status": info.get("status", "PASS"),
                       "excluded": ui_units | grid | others,
                       "uncertain_pixels": int((masks[key] & uncertain).sum())})
    return output


def measure_c9(capture: dict, images: dict, pair: np.ndarray, coverage: np.ndarray,
               records: list[dict]) -> list[dict]:
    """Reuse frozen S3/S5 reference masks; simulate pixels before Lab medians."""
    blocked, block_errors = sidecar._blocking_mask(images)
    object_blocked, object_errors = sidecar._blocking_mask(images, ground_samples=False)
    palette, water, palette_errors = sidecar._tree_reference_palette_v3(capture)
    groups = sidecar._captured_connected_groups(
        capture, records, pair, coverage, kind="tree", member_part_codes=sidecar.TREE_PART_CODES,
        object_blocked=object_blocked)
    visible, uncertain = sidecar.alpha_sample_masks(coverage)
    tokens = ((pair[..., 0].astype(np.uint32) << 16)
              | (pair[..., 1].astype(np.uint32) << 8) | pair[..., 2].astype(np.uint32))
    output = []
    for record in sorted((r for r in records if r.get("type") == "tree"),
                         key=lambda r: r["stable_id"]):
        key = record["stable_id"]
        crown = ((tokens == record["token"]) & visible & ~object_blocked
                 & np.isin(pair[..., 3], tuple(sidecar.TREE_PART_CODES)))
        group_info = groups[key]
        ring_source = group_info["measurement_group_mask"]
        outer = metrics.morph(ring_source, 4) & ~ring_source
        grass, categories, excluded_water = sidecar._v3_reference_samples(
            outer, images["ground_types"], images["ground"], coverage,
            blocked, palette, water)
        row = {"stable_id": key, "group_id": group_info["measurement_group"]["group_id"],
               "crown_part_codes": sorted(sidecar.TREE_PART_CODES),
               "crown_pixels": int(crown.sum()), "reference_pixels": int(grass.sum()),
               "reference_categories": categories, "water_pixels_excluded": excluded_water,
               "uncertain_crown_pixels_retained": int((crown & uncertain).sum()),
               "reference_scope": "frozen S3 crown union exterior with v3 S5 grass/environment reference",
               "severity": 1.0, "modes": {}}
        if (block_errors or object_errors or palette_errors
                or group_info["measurement_group_status"] != "PASS"
                or not crown.any() or not grass.any()):
            row.update(status="NOT_TESTED", reason="C9 source/group or crown/reference samples unavailable")
        else:
            crown_rgb, reference_rgb = images["main"][crown, :3], images["main"][grass, :3]
            row["normal_delta_e00_diagnostic"] = metrics.delta_e00(
                np.median(checks.lab(crown_rgb), axis=0), np.median(checks.lab(reference_rgb), axis=0))
            for mode in cvd.MATRICES:
                a = np.median(checks.lab(cvd.simulate(crown_rgb, mode)), axis=0)
                b = np.median(checks.lab(cvd.simulate(reference_rgb, mode)), axis=0)
                delta = metrics.delta_e00(a, b)
                row["modes"][mode] = {"delta_e00": delta,
                                      "status": "PASS" if delta >= 10 else "FAIL"}
            row["status"] = "PASS" if all(x["status"] == "PASS" for x in row["modes"].values()) else "FAIL"
        output.append(row)
    return output


def measure(capture: dict, frozen_case: dict, images: dict, arrays: dict,
            semantic: dict) -> dict:
    pair, coverage = arrays["semantic_pair"], arrays["semantic_coverage"]
    records = semantic["frame"]["instance_tokens"]
    main = images["main"]
    lightness = checks.lab(main[..., :3])[..., 0]
    is_720 = main.shape[:2] == (720, 1280)
    blurred = (checks.lab(np.asarray(Image.fromarray(main[..., :3]).filter(
        ImageFilter.GaussianBlur(2))))[..., 0] if is_720 else None)
    output = []
    for context in contexts(capture, images, pair, coverage, records):
        record = context["record"]
        t1 = contour.measure(lightness, context["own"], context["group"], context["excluded"])
        t6 = (contour.measure(blurred, context["own"], context["group"], context["excluded"], squint=True)
              if is_720 else {"status": "NOT_TESTED", "reason": "T6 requires native 1280x720"})
        if context["group_status"] != "PASS":
            for metric in (t1, t6):
                metric.update(status="NOT_TESTED", reason="captured group is incomplete")
        output.append({"stable_id": record["stable_id"], "type": record["type"],
                       "group_id": context["group_id"], "group_members": context["members"],
                       "uncertain_pixels_retained": context["uncertain_pixels"],
                       "T1": t1, "T6": t6,
                       "T1_required_for_acceptance": record["type"] != "tree",
                       "T6_required_for_acceptance": record["type"] != "tree" and is_720})
    c9_rows = measure_c9(capture, images, pair, coverage, records)
    c9 = c9_gate(c9_rows)
    t3_rows = frozen_case["T3_tree_instances"]
    all_t3 = bool(t3_rows) and all(row["T3"]["status"] == "PASS" for row in t3_rows)
    summary = {kind: {metric: {status: sum(row["type"] == kind and row[metric]["status"] == status
                                          for row in output)
                              for status in ("PASS", "FAIL", "NOT_TESTED")}
                      for metric in ("T1", "T6")} for kind in KINDS}
    return {"instances": output, "summary": summary, "C9_trees": c9_rows, "C9_gate": c9,
            "tree_numeric_gate": {"status": "PASS" if all_t3 and c9["status"] == "PASS" else "FAIL",
                                  "T3_all_declared_trees_pass": all_t3,
                                  "T1_T6_are_diagnostics": True,
                                  "visual_approval": "SEPARATE_REQUIRED_REVIEW"}}


def validate(manifest_path: Path, source_root: Path, expected_head: str) -> dict:
    old = baseline.validate(manifest_path, source_root, expected_head)
    if old["capture_preconditions"] == "PASS":
        capture = json.loads(manifest_path.read_bytes())
        semantic = json.loads((manifest_path.parent/sidecar.SIDECAR_MANIFEST).read_bytes())
        errors, arrays = sidecar.validate_sidecar_binding(manifest_path, capture, semantic)
        images, image_errors = sidecar._load_capture_images(manifest_path, capture)
        if errors or image_errors:
            raise ValueError("input changed after frozen provenance readback")
        values = measure(capture, old["frozen_v3_case"], images, arrays, semantic)
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
    sources = []
    for name in ("terrain_contour_v2.py", "terrain_cvd_machado.py", "validate_terrain_acceptance_v2.py"):
        raw = (Path(__file__).parent/name).read_bytes()
        sources.append({"path": "tests/claude_review/"+name, "bytes": len(raw),
                        "sha256": hashlib.sha256(raw).hexdigest()})
    return {"schema_version": SCHEMA, "candidate_head": expected_head,
            "capture_preconditions": old["capture_preconditions"], "case": old["case"],
            "rules": {"U1": "group-outside edges only; excluded outside edges retained",
                      "tree_option": "A", "tree_T1_T6": "diagnostic_only",
                      "tree_gates": ["frozen T3", "C9", "independent visual review"],
                      "C9_model": "Machado 2009 severity 1.0",
                      "C9_source": cvd.SOURCE, "C9_delta_e00_min": 10, "C9_tree_fraction_min": .8,
                      "C9_pipeline": "decode sRGB; linear matrix; clip linear RGB; encode float sRGB; Lab; median; CIEDE2000",
                      "PNG_pixels_modified": False},
            "measurement_sources": sources, "measurements": values,
            "legacy_v1_baseline": old, "art_acceptance": "NOT_TESTED", "six_case_coverage": False}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    output = validate(args.manifest, args.source_root, args.candidate)
    args.out.write_text(json.dumps(output, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(json.dumps({"capture_preconditions": output["capture_preconditions"],
                      "summary": output["measurements"]["summary"],
                      "C9": output["measurements"]["C9_gate"]}, ensure_ascii=False))
    return 0 if output["capture_preconditions"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
