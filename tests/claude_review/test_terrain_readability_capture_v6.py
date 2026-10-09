"""Focused checks for V6 mask edge alignment without rendering or changing source bounds."""
from __future__ import annotations

import copy
import hashlib
import json
import math
import os
from pathlib import Path
import unittest

import numpy as np
from PIL import Image

import validate_terrain_readability_capture_v2 as v2
import validate_terrain_readability_capture_v5 as v5
import validate_terrain_readability_capture_v6 as v6

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ROOT_CAUSE_SHA256 = "e67bfc20487d8e4275b75a0a1e00510947d7d917ea5955f5cd3eb8d5c4f22fb3"


def _mapped_aabb(rect: list[float], transform: list[float]) -> tuple[float, float, float, float]:
    x, y, width, height = map(float, rect)
    xx, xy, yx, yy, tx, ty = map(float, transform)
    points = [
        (xx * px + yx * py + tx, xy * px + yy * py + ty)
        for px, py in ((x, y), (x + width, y), (x, y + height), (x + width, y + height))
    ]
    return (min(point[0] for point in points), min(point[1] for point in points),
            max(point[0] for point in points), max(point[1] for point in points))


def _center_masks(rect: list[float], draw_rect: list[float], transform: list[float],
                  image_size: list[int]) -> tuple[tuple[int, int], np.ndarray, np.ndarray]:
    bounds = [_mapped_aabb(rect, transform), _mapped_aabb(draw_rect, transform)]
    left = max(0, math.floor(min(item[0] for item in bounds)))
    top = max(0, math.floor(min(item[1] for item in bounds)))
    right = min(image_size[0], math.ceil(max(item[2] for item in bounds)))
    bottom = min(image_size[1], math.ceil(max(item[3] for item in bounds)))
    xx, xy, yx, yy, tx, ty = map(float, transform)
    determinant = xx * yy - xy * yx
    px = np.arange(left, right, dtype=np.float64)[None, :] + 0.5
    py = np.arange(top, bottom, dtype=np.float64)[:, None] + 0.5
    dx, dy = px - tx, py - ty

    def inside(source_rect: list[float]) -> np.ndarray:
        x, y, width, height = map(float, source_rect)
        logical_x = (yy * dx - yx * dy) / determinant
        logical_y = (-xy * dx + xx * dy) / determinant
        return ((logical_x >= x) & (logical_x < x + width)
                & (logical_y >= y) & (logical_y < y + height))

    return (left, top), inside(rect), inside(draw_rect)


def _loaded_root_cause() -> tuple[dict, Path]:
    raw_path = os.environ.get("TERRAIN_V5_ROOT_CAUSE_JSON", "")
    if not raw_path:
        raise unittest.SkipTest("设置 TERRAIN_V5_ROOT_CAUSE_JSON 后运行仓外 V5 原件覆盖核对")
    path = Path(raw_path)
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != ROOT_CAUSE_SHA256:
        raise AssertionError("V5 exclusion root-cause JSON SHA-256 changed")
    return json.loads(raw.decode("utf-8-sig")), path.parent


def _expected_bounds(manifest: dict) -> list[list[float]]:
    exclusions = manifest["exclusions"]
    visible = manifest["viewports"]["main"]["visible_rect"]
    results: list[list[float]] = []
    for record in exclusions["unit_screen_bounds"]:
        clipped = v2._rect_intersection(list(map(float, record["rect"])), visible)
        if clipped[2] > 0 and clipped[3] > 0:
            results.append(clipped)
    for record in exclusions["drawable_ui_control_bound_records"]:
        clipped = list(map(float, record["clipped_rect"]))
        if clipped[2] > 0 and clipped[3] > 0:
            results.append(clipped)
    return results


def _strip_source_matches_manifest(strip: dict, manifest: dict) -> bool:
    exclusions = manifest["exclusions"]
    visible = manifest["viewports"]["main"]["visible_rect"]
    target = list(map(float, strip["logical_rect_used_by_validator"]))
    if strip["object_type"] == "unit":
        for record in exclusions["unit_screen_bounds"]:
            if record.get("unit_id") == strip["object_id"]:
                clipped = v2._rect_intersection(list(map(float, record["rect"])), visible)
                return np.allclose(clipped, target, atol=1e-3, rtol=0)
    else:
        for record in exclusions["drawable_ui_control_bound_records"]:
            if record.get("relative_path") == strip["object_id"]:
                return np.allclose(record.get("clipped_rect", []), target, atol=1e-3, rtol=0)
    return False


class TerrainCaptureV6MaskTests(unittest.TestCase):
    def test_real_720_1080_1440_source_rects_keep_the_same_center_set(self):
        report, _ = _loaded_root_cause()
        cases = report["recomputed_cases"]
        relevant = [case for case in cases if case["requested_resolution"][1] in (720, 1080, 1440)]
        self.assertEqual(len(relevant), 6)
        high_resolution_strips = 0
        for case in relevant:
            mask_record = case["exclusion_mask"]
            mask_path = Path(mask_record["path"])
            mask_bytes = mask_path.read_bytes()
            self.assertEqual(len(mask_bytes), mask_record["bytes"])
            self.assertEqual(hashlib.sha256(mask_bytes).hexdigest(), mask_record["sha256"])
            manifest_record = case["manifest"]
            manifest_path = Path(manifest_record["path"])
            manifest_bytes = manifest_path.read_bytes()
            self.assertEqual(len(manifest_bytes), manifest_record["bytes"])
            self.assertEqual(hashlib.sha256(manifest_bytes).hexdigest(), manifest_record["sha256"])
            manifest = json.loads(manifest_bytes.decode("utf-8-sig"))
            transform = list(map(float, case["native_to_logical_mapping"]["final_transform"]))
            self.assertTrue(np.allclose(manifest["viewports"]["main"]["final_transform"], transform, atol=1e-6, rtol=0))
            alpha = np.asarray(Image.open(mask_path).convert("RGBA"), dtype=np.uint8)[..., 3]
            image_size = [alpha.shape[1], alpha.shape[0]]

            strips = case["missing_edge_strips"]
            if case["requested_resolution"][1] > 720:
                self.assertTrue(strips, case["case"])
                high_resolution_strips += len(strips)
            else:
                self.assertEqual(transform, [1.0, 0.0, 0.0, 1.0, 0.0, 0.0])
                for rect in _expected_bounds(manifest):
                    quantized = v6.quantize_rect(rect, transform)
                    self.assertEqual(quantized["status"], "QUANTIZED")
                    origin, source_centers, draw_centers = _center_masks(
                        rect, quantized["quantized_draw_rect"], transform, image_size
                    )
                    self.assertTrue(np.array_equal(source_centers, draw_centers))
                    before_required, before_missing = v2._bound_coverage(alpha, rect, transform)
                    self.assertGreater(before_required, 0)
                    self.assertEqual(before_missing, 0)
                    left, top = origin
                    actual = alpha[top:top + source_centers.shape[0], left:left + source_centers.shape[1]]
                    self.assertEqual(int(np.count_nonzero(source_centers & (actual <= 127))), 0)
            for strip in strips:
                rect = list(map(float, strip["logical_rect_used_by_validator"]))
                self.assertTrue(_strip_source_matches_manifest(strip, manifest), strip["object_id"])
                before_required, before_missing = v2._bound_coverage(alpha, rect, transform)
                self.assertEqual(before_missing, strip["uncovered_pixel_centers"], strip["object_id"])
                self.assertGreater(before_required, 0)
                quantized = v6.quantize_rect(rect, transform)
                self.assertEqual(quantized["status"], "QUANTIZED", strip["object_id"])
                origin, source_centers, draw_centers = _center_masks(
                    rect, quantized["quantized_draw_rect"], transform, image_size
                )
                self.assertTrue(np.array_equal(source_centers, draw_centers), strip["object_id"])
                left, top = origin
                after = alpha[top:top + source_centers.shape[0], left:left + source_centers.shape[1]].copy()
                after[draw_centers] = 255
                self.assertEqual(int(np.count_nonzero(source_centers & (after <= 127))), 0, strip["object_id"])
        self.assertGreaterEqual(high_resolution_strips, 10)

    def test_nonzero_translation_and_fractional_edges_preserve_exact_center_membership(self):
        rect = [10.2, 11.3, 20.4, 15.9]
        transform = [1.5, 0.0, 0.0, 2.0, 23.25, -17.75]
        result = v6.quantize_rect(rect, transform)
        self.assertEqual(result["status"], "QUANTIZED")
        origin, source_centers, draw_centers = _center_masks(
            rect, result["quantized_draw_rect"], transform, [256, 256]
        )
        self.assertTrue(np.array_equal(source_centers, draw_centers))
        self.assertNotEqual(result["quantized_draw_rect"], rect)

    def test_integer_720_mapping_does_not_add_or_drop_sample_centers(self):
        rect = [595.599975585938, 553.0, 88.7999877929688, 45.0]
        transform = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]
        result = v6.quantize_rect(rect, transform)
        self.assertEqual(result["status"], "QUANTIZED")
        self.assertEqual(result["native_pixel_cell_bounds"], [596, 553, 684, 598])
        _, source_centers, draw_centers = _center_masks(rect, result["quantized_draw_rect"], transform, [1280, 720])
        self.assertTrue(np.array_equal(source_centers, draw_centers))

    def test_unsupported_rotated_transform_fails_closed(self):
        result = v6.quantize_rect([10.0, 20.0, 30.0, 40.0], [0.0, 1.0, -1.0, 0.0, 50.0, 60.0])
        self.assertEqual(result["status"], "UNSUPPORTED_FINAL_TRANSFORM")

    def test_manifest_quantization_binds_original_bounds_transform_and_recomputed_cells(self):
        transform = [1.5, 0.0, 0.0, 1.5, 0.0, 0.0]
        visible = [0.0, 0.0, 1280.0, 720.0]
        bounds = [
            ("UnitConservativeBounds", [631.200012207031, 209.920013427734, 112.0, 168.00000000000003]),
            ("DrawableUIBounds", [595.599975585938, 553.0, 88.7999877929688, 45.0]),
        ]
        records = []
        for node_name, nominal in bounds:
            clipped = v2._rect_intersection(nominal, visible)
            geometry = v6.quantize_rect(clipped, transform)
            records.append({
                "node_name": node_name,
                "nominal_rect": nominal.copy(),
                "logical_clipped_rect": clipped,
                "final_transform": transform,
                **geometry,
                "quantization_status": geometry["status"],
                "draw_created": geometry["status"] == "QUANTIZED",
            })
        # The helper-only geometry record carries a private status key; manifests
        # publish just its stable, documented fields.
        for record in records:
            record.pop("status", None)
        manifest = {
            "viewports": {"main": {"visible_rect": visible, "final_transform": transform}},
            "exclusions": {
                "unit_screen_bounds": [{"unit_id": "myrmidon", "rect": bounds[0][1]}],
                "drawable_ui_control_bound_records": [{"rect": bounds[1][1]}],
                "mask_draw_quantization": {
                    "schema_version": v6.V6_MASK_SCHEMA,
                    "status": "CAPTURED",
                    "algorithm": v6.V6_MASK_ALGORITHM,
                    "pixel_center_rule": (
                        "Native pixel centers are index + 0.5; logical source rectangles are half-open; "
                        "align only the native cells whose centers satisfy the original source rectangle."
                    ),
                    "source_bounds_are_unchanged": True,
                    "source_validator": "tests/claude_review/validate_terrain_readability_capture_v2.py::_bound_coverage",
                    "bounds_coordinate_space": "main Window visible logical viewport before the viewport stretch transform",
                    "final_transform_source": "viewports.main.final_transform",
                    "final_transform": transform,
                    "transform_consistent_across_draw_calls": True,
                    "draw_call_count": len(records),
                    "records": records,
                },
            },
        }
        self.assertEqual(v6.mask_quantization_errors(manifest), [])
        tampered = copy.deepcopy(manifest)
        tampered["exclusions"]["mask_draw_quantization"]["records"][0]["nominal_rect"][0] += 0.25
        self.assertTrue(any("nominal bounds" in error for error in v6.mask_quantization_errors(tampered)))

    def test_all_four_v6_sources_are_bound_and_summary_tampering_fails(self):
        source_paths = tuple(dict.fromkeys((*v5.V5_SOURCES, *v6.V6_SOURCES)))
        hashes = {
            path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
            for path in source_paths
        }
        manifest = {
            "sources": {"res://" + path: digest for path, digest in hashes.items()},
            "candidate": {
                "source_sha256": hashes,
                "candidate_digest_sha256": hashlib.sha256(
                    json.dumps(hashes, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
                ).hexdigest(),
            },
        }
        self.assertEqual(v6.v6_source_errors(manifest, ROOT), [])
        self.assertEqual(v5.v5_source_errors(manifest, ROOT), [])
        bad_summary = copy.deepcopy(manifest)
        bad_summary["candidate"]["candidate_digest_sha256"] = "0" * 64
        self.assertTrue(any("candidate_digest_sha256" in error
                            for error in v5.v5_source_errors(bad_summary, ROOT)))
        tampered = copy.deepcopy(manifest)
        doc = v6.V6_SOURCES[-1]
        tampered["sources"]["res://" + doc] = "0" * 64
        self.assertTrue(any(doc in error for error in v6.v6_source_errors(tampered, ROOT)))
        recomputed_tamper = copy.deepcopy(manifest)
        recomputed_tamper["sources"]["res://" + doc] = "f" * 64
        recomputed_tamper["candidate"]["source_sha256"][doc] = "f" * 64
        self.assertTrue(any(doc in error for error in v6.v6_source_errors(recomputed_tamper, ROOT)))


if __name__ == "__main__":
    unittest.main()
