"""Reachable U1 negative cases for composite occupancy and occlusion accounting."""
from __future__ import annotations

import unittest
import hashlib
import re
import tempfile
from pathlib import Path

import numpy as np

import terrain_contour_v3 as contour
import validate_terrain_acceptance_v3 as acceptance

ROOT = Path(__file__).resolve().parents[2]


def _rect(shape: tuple[int, int], x0: int, y0: int, x1: int, y1: int) -> np.ndarray:
    mask = np.zeros(shape, dtype=bool)
    mask[y0:y1, x0:x1] = True
    return mask


class CompositeOccupancyNegativeTests(unittest.TestCase):
    def test_n1_same_instance_alpha_048_seam_keeps_body_and_only_outer_perimeter(self):
        body = _rect((48, 48), 12, 12, 36, 36)
        seam = _rect((48, 48), 18, 22, 30, 26)
        occupancy = contour.composite_occupancy([body, seam], [1.0, 0.48], [11, 11])
        self.assertTrue(np.array_equal(occupancy == 11, body))
        self.assertEqual(int(contour.edge_weights(occupancy == 11, occupancy == 11).sum()), 96)
        excluded = seam.copy()
        lightness = np.full(body.shape, 60.0)
        lightness[body] = 35.0
        result = contour.measure(lightness, occupancy == 11, occupancy == 11, excluded)
        self.assertEqual(result["perimeter_edges"], 96)
        self.assertEqual(result["status"], "PASS")

    def test_n2_true_hole_remains_empty_and_its_boundary_stays_in_perimeter(self):
        body = _rect((48, 48), 8, 8, 40, 40)
        hole = _rect((48, 48), 20, 20, 28, 28)
        body &= ~hole
        occupancy = contour.composite_occupancy([body], [1.0], [21])
        own, group = contour.token_masks(occupancy, 21, [21])
        self.assertFalse(own[23, 23])
        self.assertEqual(int(contour.edge_weights(own, group).sum()), 160)

    def test_n3_other_alpha_04_keeps_owner_but_blocks_touching_edges_and_samples(self):
        shape = (48, 48)
        body = _rect(shape, 12, 12, 36, 36)
        overlay = _rect(shape, 34, 12, 36, 36)
        occupancy = contour.composite_occupancy([body, overlay], [1.0, 0.4], [31, 32])
        own, group = contour.token_masks(occupancy, 31, [31])
        self.assertTrue(np.all(own[12:36, 34:36]))
        lightness = np.full(shape, 60.0)
        lightness[own] = 35.0
        result = contour.measure(lightness, own, group, overlay, blocked_pixels=overlay)
        self.assertEqual(result["perimeter_edges"], 96)
        self.assertGreaterEqual(result["occluded_perimeter_edges"], 24)
        self.assertLessEqual(result["locally_eligible_perimeter_edges"], 72)
        self.assertEqual(result["other_or_unknown_touching_edges_retained"], True)

    def test_n4_opaque_unknown_owns_overlap_and_neighbour_edges_are_unmeasurable(self):
        shape = (48, 48)
        body = _rect(shape, 12, 12, 36, 36)
        unknown = _rect(shape, 32, 12, 36, 36)
        occupancy = contour.composite_occupancy([body, unknown], [1.0, 1.0], [41, 255])
        own, group = contour.token_masks(occupancy, 41, [41])
        self.assertTrue(np.all(occupancy[12:36, 32:36] == 255))
        self.assertFalse(own[20, 34])
        result = contour.measure(np.full(shape, 50.0), own, group, unknown,
                                 blocked_pixels=unknown | (occupancy == 255))
        self.assertEqual(result["perimeter_edges"], 88)
        self.assertGreaterEqual(result["occluded_perimeter_edges"], 24)

    def test_n5_standalone_alpha_half_draw_does_not_occupy(self):
        faint = _rect((40, 40), 10, 10, 30, 30)
        occupancy = contour.composite_occupancy([faint], [0.5], [51])
        self.assertEqual(int(np.count_nonzero(occupancy)), 0)
        own, group = contour.token_masks(occupancy, 51, [51])
        result = contour.measure(np.full(faint.shape, 50.0), own, group,
                                 np.zeros(faint.shape, dtype=bool))
        self.assertEqual(result["status"], "NOT_TESTED")
        self.assertEqual(result["reason_category"], "empty_instance")

    def test_composite_occupancy_applies_strict_cutoff_to_rgba8_alpha_bytes(self):
        mask = np.ones((2, 2), dtype=bool)
        alpha = np.array([[127, 128], [127, 128]], dtype=np.uint8)
        occupancy = contour.composite_occupancy([mask], [alpha], [61])
        self.assertTrue(np.array_equal(occupancy, np.array([[0, 61], [0, 61]], dtype=np.uint32)))

    def test_v3_metadata_gate_rejects_missing_occupancy_instead_of_using_legacy_mask(self):
        capture = {"candidate": {"source_sha256": {}}, "common_frame": {"frame_id": 8}}
        semantic = {"frame": {"frame_id": 8}}
        errors = acceptance.occupancy_metadata_errors(capture, semantic)
        self.assertTrue(any("composite_occupancy" in error for error in errors))
        self.assertTrue(any("native_occupancy_controls" in error for error in errors))

    def test_v3_png_binding_fails_closed_on_missing_occupancy_records(self):
        capture = {"candidate": {"source_sha256": {}},
                   "case": {"requested_resolution": [48, 48]}}
        semantic = {"frame": {"viewports": {"semantic_pair": {}}}}
        with tempfile.TemporaryDirectory() as folder:
            manifest = Path(folder) / "capture-manifest.json"
            errors, arrays = acceptance.validate_occupancy_binding(
                manifest, capture, semantic, ROOT)
        self.assertTrue(errors)
        self.assertEqual(arrays, {})

    def test_v3_metadata_gate_binds_occupancy_sources_and_frame_to_capture(self):
        capture_source = (ROOT / acceptance.R7_SOURCE_PATHS[0]).read_text(encoding="utf-8")
        controls_record = re.search(r'_r7_controls_record = \{(.*?)\n\t\}',
                                    capture_source, re.S)
        self.assertIsNotNone(controls_record)
        controls_role = re.search(r'"role": "([^"]+)"', controls_record.group(1))
        self.assertIsNotNone(controls_role)
        sources = {relative: hashlib.sha256((ROOT / relative).read_bytes()).hexdigest()
                   for relative in acceptance.R7_SOURCE_PATHS}
        common = {"frame_id": 8, "frames_drawn_before": 8, "frames_drawn_after": 8,
                  "process_frames_before": 12, "process_frames_after": 12}
        capture = {"candidate": {"source_sha256": sources,
                                  "candidate_digest_sha256": "a" * 64},
                   "common_frame": common}
        frame = {"callback": "RenderingServer.frame_post_draw", "same_frame": True,
                 "original_capture_image_count_unchanged": 12, **common}
        token_record = {"stable_id": "fixture-instance", "token": 11,
                        "token_rgb": [0, 0, 11],
                        "draw_leaf_signatures": {"occupancy": [{"relative_path": "0"}]}}
        sample_records = [
            {"case": case_id, "xy": [x, y], "expected_token": token,
             "observed_token": token, "matched": True, "polygon_color_a": 1.0,
             "self_modulate_a": alpha, "effective_alpha_expected": alpha,
             "effective_alpha_input": "incoming COLOR.a from Polygon2D.color * CanvasItem.self_modulate"}
            for (case_id, x, y, token), alpha in zip(
                acceptance.NATIVE_CONTROL_SAMPLES, acceptance.NATIVE_CONTROL_ALPHA, strict=True)]
        base_record = {"callback": "RenderingServer.frame_post_draw", "frame_id": 8,
                       "same_frame": True, "candidate_source_sha256": sources,
                       "capture_candidate_digest_sha256": "a" * 64,
                       "image": {"frame_id": 8, "mime_type": "image/png",
                                 "pixel_format": "RGBA8", "role": "composite_occupancy"}}
        material_binding = {"mode": "occupancy", "stable_id": "fixture-instance",
                            "relative_path": "0", "canvas_valid": True,
                            "shader_material_bound": True,
                            "shader_declares_blend_disabled": True,
                            "use_parent_material": False,
                            "instance_token_rgb": [0.0, 0.0, 11 / 255],
                            "shader_code_sha256": "c" * 64,
                            "effective_alpha_source": "incoming CanvasItem COLOR.a after source texture/primitive alpha and inherited modulation"}
        semantic = {"frame": frame,
                    "composite_occupancy": {
                        **base_record, "schema_version": acceptance.OCCUPANCY_SCHEMA,
                        "role": "composite_occupancy",
                        "effective_alpha_rule": "discard when effective COLOR.a <= 0.5; write the instance token when COLOR.a > 0.5",
                        "blend_mode": "blend_disabled", "last_qualifying_draw_owns_pixel": True,
                        "unknown_props_keep_nonzero_tokens": True,
                        "source_alpha_coverage_unchanged": True,
                        "source_alpha_uncertainty_unchanged": True,
                        "shader_path": "res://tests/claude_review/terrain_composite_occupancy.gdshader",
                        "shader_source_sha256": sources["tests/claude_review/terrain_composite_occupancy.gdshader"],
                        "material_bindings": [material_binding]},
                    "native_occupancy_controls": {
                        **base_record, "schema_version": acceptance.CONTROL_SCHEMA,
                        "role": controls_role.group(1), "pass": True,
                        "samples": sample_records,
                        "image": {**base_record["image"], "role": "native_occupancy_controls"}}}
        semantic["frame"]["instance_tokens"] = [token_record]
        self.assertEqual(acceptance.occupancy_metadata_errors(capture, semantic), [])
        semantic["native_occupancy_controls"]["role"] = "composite_occupancy_controls"
        self.assertIn("native_occupancy_controls schema 或 role 无效",
                      acceptance.occupancy_metadata_errors(capture, semantic))
        semantic["native_occupancy_controls"]["role"] = controls_role.group(1)
        semantic["native_occupancy_controls"]["frame_id"] = 9
        self.assertTrue(any("native_occupancy_controls frame_id" in error
                            for error in acceptance.occupancy_metadata_errors(capture, semantic)))

    def test_v3_metadata_rejects_occupancy_material_mode_or_token_drift(self):
        sources = {relative: hashlib.sha256((ROOT / relative).read_bytes()).hexdigest()
                   for relative in acceptance.R7_SOURCE_PATHS}
        common = {"frame_id": 8, "frames_drawn_before": 8, "frames_drawn_after": 8,
                  "process_frames_before": 12, "process_frames_after": 12}
        candidate = {"source_sha256": sources, "candidate_digest_sha256": "a" * 64}
        capture = {"candidate": candidate, "common_frame": common}
        token_record = {"stable_id": "fixture-instance", "token": 11,
                        "token_rgb": [0, 0, 11],
                        "draw_leaf_signatures": {"occupancy": [{"relative_path": "0"}]}}
        binding = {"mode": "pair", "stable_id": "fixture-instance", "relative_path": "0",
                   "canvas_valid": True, "shader_material_bound": True,
                   "shader_declares_blend_disabled": True, "use_parent_material": False,
                   "instance_token_rgb": [0.0, 0.0, 10 / 255],
                   "shader_code_sha256": "c" * 64,
                   "effective_alpha_source": "incoming CanvasItem COLOR.a after source texture/primitive alpha and inherited modulation"}
        occupancy = {"schema_version": acceptance.OCCUPANCY_SCHEMA,
                     "role": "composite_occupancy", "callback": "RenderingServer.frame_post_draw",
                     "same_frame": True, "frame_id": 8, "candidate_source_sha256": sources,
                     "capture_candidate_digest_sha256": "a" * 64,
                     "image": {"frame_id": 8, "role": "composite_occupancy",
                               "mime_type": "image/png", "pixel_format": "RGBA8"},
                     "effective_alpha_rule": "discard when effective COLOR.a <= 0.5; write the instance token when COLOR.a > 0.5",
                     "blend_mode": "blend_disabled", "last_qualifying_draw_owns_pixel": True,
                     "unknown_props_keep_nonzero_tokens": True,
                     "source_alpha_coverage_unchanged": True,
                     "source_alpha_uncertainty_unchanged": True,
                     "shader_path": "res://tests/claude_review/terrain_composite_occupancy.gdshader",
                     "shader_source_sha256": sources["tests/claude_review/terrain_composite_occupancy.gdshader"],
                     "material_bindings": [binding]}
        controls = {"schema_version": acceptance.CONTROL_SCHEMA,
                    "role": "native_occupancy_controls", "callback": "RenderingServer.frame_post_draw",
                    "same_frame": True, "frame_id": 8, "candidate_source_sha256": sources,
                    "capture_candidate_digest_sha256": "a" * 64, "pass": True,
                    "image": {"frame_id": 8, "role": "native_occupancy_controls",
                              "mime_type": "image/png", "pixel_format": "RGBA8"}}
        frame = {"callback": "RenderingServer.frame_post_draw", "same_frame": True,
                 "original_capture_image_count_unchanged": 12, **common,
                 "instance_tokens": [token_record]}
        semantic = {"frame": frame, "composite_occupancy": occupancy,
                    "native_occupancy_controls": controls}
        errors = acceptance.occupancy_metadata_errors(capture, semantic)
        self.assertTrue(any("有效 blend_disabled material" in error for error in errors))
        self.assertTrue(any("token RGB" in error for error in errors))

    def test_v3_source_gate_requires_candidate_and_manifest_bindings(self):
        hashes = {relative: hashlib.sha256((ROOT / relative).read_bytes()).hexdigest()
                  for relative in acceptance.R7_SOURCE_PATHS}
        capture = {"candidate": {"source_sha256": hashes},
                   "capture_config": {
                       "capture_entry_script": "res://tests/claude_review/capture_terrain_readability_r7.gd",
                       "composite_occupancy_shader": "res://tests/claude_review/terrain_composite_occupancy.gdshader"}}
        missing_manifest_errors = acceptance._source_errors(capture, ROOT)
        self.assertEqual(len(missing_manifest_errors), len(hashes))
        capture["sources"] = {"res://" + relative: digest
                              for relative, digest in hashes.items()}
        self.assertEqual(acceptance._source_errors(capture, ROOT), [])

    def test_v3_png_readback_fails_closed_when_new_original_images_are_missing(self):
        sources = {relative: hashlib.sha256((ROOT / relative).read_bytes()).hexdigest()
                   for relative in acceptance.R7_SOURCE_PATHS}
        candidate = {"source_sha256": sources, "candidate_digest_sha256": "b" * 64}
        capture = {"candidate": candidate,
                   "capture_config": {"capture_entry_script": "res://tests/claude_review/capture_terrain_readability_r7.gd",
                                      "composite_occupancy_shader": "res://tests/claude_review/terrain_composite_occupancy.gdshader"},
                   "case": {"requested_resolution": [48, 48]}}
        viewport = {"image_size": [48, 48], "size": [48, 48],
                    "size_2d_override": [48, 48], "size_2d_override_stretch": True,
                    "canvas_transform": [1, 0, 0, 1, 0, 0],
                    "final_transform": [1, 0, 0, 1, 0, 0],
                    "texture_size": [48, 48], "visible_rect": [0, 0, 48, 48]}
        controls_viewport = {**viewport, "image_size": [176, 40]}
        common = {"frame_id": 8, "frames_drawn_before": 8, "frames_drawn_after": 8,
                  "process_frames_before": 12, "process_frames_after": 12}
        frame = {"callback": "RenderingServer.frame_post_draw", "same_frame": True,
                 "original_capture_image_count_unchanged": 12, **common,
                 "viewports": {"semantic_pair": viewport}, "images": {}, "instance_tokens": []}
        capture["common_frame"] = common
        base = {"callback": "RenderingServer.frame_post_draw", "frame_id": 8,
                "same_frame": True, "candidate_source_sha256": sources,
                "capture_candidate_digest_sha256": "b" * 64,
                "image": {"mime_type": "image/png", "pixel_format": "RGBA8",
                          "sha256": "0" * 64, "bytes": 1, "frame_id": 8}}
        occupancy = {**base, "schema_version": acceptance.OCCUPANCY_SCHEMA,
                     "role": "composite_occupancy", "viewport": viewport,
                     "image": {**base["image"], "role": "composite_occupancy",
                               "path": "missing_occupancy.png", "image_size": [48, 48]},
                     "effective_alpha_rule": "discard when effective COLOR.a <= 0.5; write the instance token when COLOR.a > 0.5",
                     "blend_mode": "blend_disabled", "last_qualifying_draw_owns_pixel": True,
                     "unknown_props_keep_nonzero_tokens": True,
                     "source_alpha_coverage_unchanged": True,
                     "source_alpha_uncertainty_unchanged": True}
        controls = {**base, "schema_version": acceptance.CONTROL_SCHEMA,
                    "role": "native_occupancy_controls", "viewport": controls_viewport,
                    "image": {**base["image"], "role": "native_occupancy_controls",
                              "path": "missing_controls.png", "image_size": [176, 40]},
                    "pass": True, "samples": []}
        semantic = {"frame": frame, "composite_occupancy": occupancy,
                    "native_occupancy_controls": controls}
        with tempfile.TemporaryDirectory() as folder:
            manifest = Path(folder) / "capture-manifest.json"
            errors, arrays = acceptance.validate_occupancy_binding(manifest, capture, semantic, ROOT)
        self.assertTrue(any("composite_occupancy" in error for error in errors))
        self.assertTrue(any("native_occupancy_controls" in error for error in errors))
        self.assertEqual(arrays, {})


if __name__ == "__main__":
    unittest.main()
