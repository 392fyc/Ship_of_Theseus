"""Offline synthetic controls for R9 groove and occlusion pixel rules."""
from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from unittest.mock import patch

import numpy as np
from PIL import Image

import validate_terrain_pillar_r9 as r9


TRANSFORM = [1, 0, 0, 1, 0, 0]


def _line(index: int, x: float, y_top: float = 2.0, y_bottom: float = 22.0,
          u: float | None = None, width: float = 1.0) -> dict:
    return {"node_name": f"R9Groove{index}", "node_class": "Line2D",
            "r9_groove_index": index, "r9_groove_u": (0.62 if index == 3 else index * 0.18)
            if u is None else u,
            "global_transform": TRANSFORM,
            "points": [[x + 0.5, y_top + 0.5], [x + 0.5, y_bottom + 0.5]],
            "width": width, "visible": True}


def _groove_pixels(center_gray: int, center_x: int = 11) -> tuple[np.ndarray, np.ndarray]:
    image = np.full((28, 32, 4), 128, dtype=np.uint8)
    image[..., 3] = 255
    image[3:23, center_x, :3] = center_gray
    owners = np.zeros((28, 32), dtype=np.uint32)
    owners[2:24, 5:27] = 7
    return image, owners


def _write_rgba(path: Path, image: np.ndarray) -> dict:
    Image.fromarray(image, mode="RGBA").save(path, format="PNG")
    raw = path.read_bytes()
    return {"path": path.name, "sha256": hashlib.sha256(raw).hexdigest(),
            "bytes": len(raw), "image_size": [image.shape[1], image.shape[0]],
            "role": path.stem, "mime_type": "image/png"}


class GroovePixelTests(unittest.TestCase):
    def test_g1_measures_all_three_pillars_and_twelve_grooves(self) -> None:
        main = np.full((28, 88, 4), [128, 128, 128, 255], dtype=np.uint8)
        occupancy = np.zeros_like(main)
        token_rows = []
        for pillar_index in range(3):
            stable_id = f"pillar@{pillar_index},4.00"
            token = pillar_index + 7
            start_x = 4 + pillar_index * 27
            occupancy[1:25, start_x:start_x + 23] = [0, 0, token, 255]
            lines = []
            for groove_index, local_x in enumerate((5, 9, 13, 17), start=1):
                x = start_x + local_x
                center = 116 if groove_index == 3 else 110
                main[2:23, x, :3] = center
                lines.append(_line(groove_index, x))
            token_rows.append({"stable_id": stable_id, "type": "pillar", "token": token,
                               "draw_leaf_inputs": lines})
        semantic = {"frame": {
            "callback": "RenderingServer.frame_post_draw", "same_frame": True,
            "frame_id": 42, "original_capture_image_count_unchanged": 12,
            "viewports": {"main": {"image_size": [88, 28],
                                       "canvas_transform": TRANSFORM,
                                       "final_transform": TRANSFORM}},
            "instance_tokens": token_rows,
        }, "capture_candidate": {"candidate_digest_sha256": "candidate-digest"}}
        capture = {"common_frame": {"frame_id": 42},
                   "candidate": {"candidate_digest_sha256": "candidate-digest"}}
        with patch.object(r9, "_main_image", return_value=main), \
                patch.object(r9, "_occupancy_data", return_value=occupancy):
            result = r9.measure_g1(Path("unused/capture-manifest.json"), capture, semantic)
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(len(result["pillars"]), 3)
        self.assertEqual(sum(len(row["grooves"]) for row in result["pillars"]), 12)

    def test_outer_band_accepts_bounded_pure_pixel_contrast(self) -> None:
        image, owners = _groove_pixels(110)
        grooves = [_line(index, 7 + index * 4) for index in range(1, 5)]
        result = r9._sample_groove(grooves[0], grooves, image, owners, 7, np.eye(3))
        self.assertEqual(result["status"], "PASS")
        self.assertGreaterEqual(result["delta_L_star_median"], 6.0)
        self.assertLessEqual(result["delta_L_star_median"], 8.0)
        self.assertEqual(result["centerline_rows_measured"], 21)

    def test_core_slot_has_independent_four_lstar_floor(self) -> None:
        image, owners = _groove_pixels(116, center_x=19)
        grooves = [_line(index, 7 + index * 4) for index in range(1, 5)]
        result = r9._sample_groove(grooves[2], grooves, image, owners, 7, np.eye(3))
        self.assertEqual(result["groove_index"], 3)
        self.assertEqual(result["status"], "PASS")
        self.assertGreaterEqual(result["delta_L_star_median"], 4.0)

    def test_core_slot_below_four_lstar_fails(self) -> None:
        image, owners = _groove_pixels(118, center_x=19)
        grooves = [_line(index, 7 + index * 4) for index in range(1, 5)]
        result = r9._sample_groove(grooves[2], grooves, image, owners, 7, np.eye(3))
        self.assertEqual(result["status"], "FAIL")
        self.assertLess(result["delta_L_star_median"], 4.0)

    def test_other_groove_in_side_band_is_not_tested(self) -> None:
        image, owners = _groove_pixels(110)
        first = _line(1, 12)
        grooves = [first, _line(2, 14), _line(3, 20, u=0.62), _line(4, 24)]
        result = r9._sample_groove(first, grooves, image, owners, 7, np.eye(3))
        self.assertEqual(result["status"], "NOT_TESTED")
        self.assertIn("other_groove_2", result["excluded_rows"])

    def test_missing_or_misindexed_groove_input_is_rejected(self) -> None:
        semantic = {"frame": {"instance_tokens": [{"stable_id": "pillar@1.00,4.00",
                                                      "type": "pillar",
                                                      "draw_leaf_inputs": [_line(i, 6 + i * 5) for i in range(1, 4)]}]}}
        with self.assertRaisesRegex(ValueError, "exactly R9Groove1..4"):
            r9._groove_records(semantic, "pillar@1.00,4.00")
        bad = _line(3, 21, u=0.40)
        image, owners = _groove_pixels(110)
        grooves = [_line(1, 7), _line(2, 12), bad, _line(4, 24)]
        result = r9._sample_groove(bad, grooves, image, owners, 7, np.eye(3))
        self.assertEqual(result["status"], "NOT_TESTED")
        self.assertIn("u≈0.62", result["reason"])

    def test_normal_textured_pillar_pixels_remain_numeric_samples(self) -> None:
        image, owners = _groove_pixels(110)
        for y in range(3, 23):
            image[y, 9, :3] = 100 + (y * 7) % 25
            image[y, 10, :3] = 110 + (y * 3) % 18
            image[y, 11, :3] = 108 + y % 5
            image[y, 12, :3] = 132 - y % 5
            image[y, 13, :3] = 145 - (y * 5) % 22
        texture_leaf = {
            "node_name": "PillarStoneTexture",
            "node_class": "Polygon2D",
            "visible": True,
            "global_transform": TRANSFORM,
            "polygon": [[5, 2], [27, 2], [27, 24], [5, 24]],
            "texture": {"resource_path": "res://assets/pillar_stone.png"},
        }
        line_leaves = [_line(index, 7 + index * 4) for index in range(1, 5)]
        semantic = {"frame": {"instance_tokens": [{
            "stable_id": "pillar@1.00,4.00", "type": "pillar",
            "draw_leaf_inputs": [texture_leaf, *line_leaves],
        }]}}
        grooves = r9._groove_records(semantic, "pillar@1.00,4.00")
        result = r9._sample_groove(grooves[0], grooves, image, owners, 7, np.eye(3))
        self.assertIn(result["status"], {"PASS", "FAIL"})
        self.assertIsInstance(result["delta_L_star_median"], float)
        self.assertEqual(result["centerline_rows_measured"], 21)
        self.assertGreater(result["sideband_texture_spread_iqr_l_star"], 0.0)
        self.assertEqual(result["texture_policy"],
                         "actual same-token opaque main-image texture pixels remain in the row median; texture spread is diagnostic only")


class T6MarginTests(unittest.TestCase):
    def test_legacy_fail_with_finite_value_is_measured_against_r9_margin(self) -> None:
        legacy = {"measurements": {"instances": [{"stable_id": "pillar@1.00,4.00", "type": "pillar",
                                                    "T6": {"status": "FAIL", "median_delta_l": 9.8}}]}}
        result = r9.measure_t6_margin(legacy)
        row = result["inspected_instances"][0]
        self.assertEqual(result["status"], "FAIL")
        self.assertEqual(row["status"], "FAIL")
        self.assertEqual(row["legacy_T6_status"], "FAIL")
        self.assertEqual(row["legacy_T6_median_delta_l"], 9.8)
        self.assertAlmostEqual(row["distance_from_legacy_threshold_10"], -0.2)
        self.assertAlmostEqual(row["distance_from_r9_target_10_5"], -0.7)

    def test_missing_value_and_legacy_geometry_not_tested_remain_not_tested(self) -> None:
        legacy = {"measurements": {"instances": [
            {"stable_id": "pillar@1.00,4.00", "type": "pillar", "T6": {"status": "FAIL"}},
            {"stable_id": "pillar@2.00,4.00", "type": "pillar",
             "T6": {"status": "NOT_TESTED", "median_delta_l": 11.0,
                    "reason": "captured group is incomplete"}},
        ]}}
        result = r9.measure_t6_margin(legacy)
        self.assertEqual(result["status"], "NOT_TESTED")
        missing, unmeasured = result["inspected_instances"]
        self.assertEqual(missing["status"], "NOT_TESTED")
        self.assertNotIn("legacy_T6_median_delta_l", missing)
        self.assertEqual(unmeasured["status"], "NOT_TESTED")
        self.assertEqual(unmeasured["legacy_T6_median_delta_l"], 11.0)
        self.assertEqual(unmeasured["reason"], "captured group is incomplete")


def _o1_fixture(root: Path, with_count: int = 12) -> tuple[Path, dict]:
    background = np.full((16, 16, 4), [20, 20, 20, 255], dtype=np.uint8)
    base_unit_mask = np.zeros((16, 16), dtype=bool)
    base_unit_mask[4:8, 4:9] = True  # 20 source-Unit pixels within the reported body rectangle.
    pillar_mask = np.zeros((16, 16), dtype=bool)
    pillar_mask[4:8, 4:6] = True   # Eight pixels are hidden in the pillar-present control.
    a = background.copy()
    b = background.copy()
    c = background.copy()
    d = background.copy()
    c[pillar_mask, :3] = 90
    a[pillar_mask, :3] = 90
    visible_positions = np.argwhere(base_unit_mask & ~pillar_mask)
    for y, x in visible_positions[:with_count]:
        a[y, x, :3] = 200
    b[base_unit_mask, :3] = 200
    arrays = {"A": a, "B": b, "C": c, "D": d}
    state_records = {}
    for role, image in arrays.items():
        image_record = _write_rgba(root / f"o1_{role}.png", image)
        state_records[role] = {"role": role, "callback": "RenderingServer.frame_post_draw",
                               "same_frame": True, "frame_id": 42,
                               "frames_drawn_before": 42, "frames_drawn_after": 42,
                               "process_frames_before": 108, "process_frames_after": 108,
                               "window_id": 0, "window_size": [16, 16],
                               "viewport_name": f"o1_{role}",
                               "viewport_instance_id": ord(role),
                               "requested_unit_cell": [0, 3], "requested_hover_cell": [0, 3],
                               "has_hover_cell": True, "body_rect": [4, 4, 8, 8],
                               "pillar_alpha": 0.18,
                               "pillar_visible": role in ("A", "C"),
                               "unit_visible": role in ("A", "B"),
                               "unit_cell": [0, 3], "hover_cell": [0, 3],
                               "viewport": {"image_size": [16, 16],
                                            "canvas_transform": TRANSFORM,
                                            "final_transform": TRANSFORM},
                               "image": image_record}
    record = {"schema_version": r9.O1_SCHEMA,
              "candidate_digest_sha256": "candidate-digest",
              "capture_manifest_sha256": "",
              "semantic_sidecar_sha256": "",
              "callback": "RenderingServer.frame_post_draw", "same_frame": True,
              "setup_status": "PASS",
              "frame_id": 42, "image_size": [16, 16],
              "window_size": [16, 16],
              "unit_cell": [0, 3], "hover_cell": [0, 3],
              "body_rect": [4, 4, 8, 8],
              "pillar_stable_id": "pillar@1.00,4.00", "pillar_canvas_layer": 0,
              "pillar_alpha": 0.18,
              "pillar_alpha_input": "actual pillar CanvasItem.modulate.a after TerrainBattleSession._update_board_visibility_context and CourtyardBoardView._process",
              "forecast_path": "TacticalManager.request_end_move -> request_attack_targeting -> handle_pointer_hover -> TacticalScene._update_damage_forecaster",
              "overlays": {
                  "name": {"text": "木桩", "visible": True, "rect": [10, 1, 5, 2], "canvas_layer": 10, "text_complete": True},
                  "hp": {"text": "20 / 20", "visible": True, "rect": [10, 3, 5, 2], "canvas_layer": 10, "text_complete": True},
                  "forecast": {"text": "物理 · 4", "visible": True, "rect": [10, 1, 5, 8], "canvas_layer": 6,
                               "text_complete": True, "has_matching_official_value": True},
                  "unit_overhead_forecast": {"text": "4", "visible": True, "rect": [10, 5, 5, 2],
                                             "canvas_layer": 10, "text_complete": True},
              }, "states": state_records}
    manifest_path = root / "capture-manifest.json"
    capture = {"candidate": {"candidate_digest_sha256": "candidate-digest"}}
    manifest_bytes = json.dumps(capture).encode()
    manifest_path.write_bytes(manifest_bytes)
    sidecar_path = root / "semantic-sidecar-manifest.json"
    token_image = np.zeros((16, 16, 4), dtype=np.uint8)
    token_image[pillar_mask] = [0, 0, 1, 255]
    token_record = _write_rgba(root / "occupancy.png", token_image)
    semantic = {"frame": {"instance_tokens": [{"stable_id": "pillar@1.00,4.00",
                                                  "type": "pillar", "token": 1}]},
                "composite_occupancy": {"image": token_record}}
    sidecar_path.write_text(json.dumps(semantic), encoding="utf-8")
    record["capture_manifest_sha256"] = hashlib.sha256(manifest_bytes).hexdigest()
    record["semantic_sidecar_sha256"] = hashlib.sha256(sidecar_path.read_bytes()).hexdigest()
    (root / "r9-o1.json").write_text(json.dumps(record), encoding="utf-8")
    return manifest_path, capture


class OcclusionImageTests(unittest.TestCase):
    def test_exact_sixty_percent_contribution_passes(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            manifest, capture = _o1_fixture(Path(temp), with_count=12)
            result = r9.measure_o1(manifest, capture)
            self.assertEqual(result["status"], "PASS")
            self.assertEqual(result["unit_visible_body_contribution_pixels"], 12)
            self.assertEqual(result["same_frame_no_pillar_unit_contribution_pixels"], 20)
            self.assertAlmostEqual(result["body_contribution_ratio"], 0.60)

    def test_below_sixty_percent_contribution_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            manifest, capture = _o1_fixture(Path(temp), with_count=11)
            result = r9.measure_o1(manifest, capture)
            self.assertEqual(result["status"], "FAIL")
            self.assertAlmostEqual(result["body_contribution_ratio"], 0.55)

    def test_overlapping_text_rect_without_pixel_evidence_is_not_tested(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            manifest, capture = _o1_fixture(Path(temp), with_count=12)
            path = Path(temp) / "r9-o1.json"
            record = json.loads(path.read_text(encoding="utf-8"))
            # The fixture images contain no rendered text pixels. Geometry and
            # a higher CanvasLayer cannot prove text remains readable here.
            record["overlays"]["name"]["rect"] = [4, 4, 2, 2]
            path.write_text(json.dumps(record), encoding="utf-8")
            result = r9.measure_o1(manifest, capture)
            self.assertEqual(result["body_contribution_ratio"], 0.60)
            self.assertEqual(result["status"], "NOT_TESTED")
            self.assertEqual(result["overlays"]["name"]["status"], "NOT_TESTED")
            self.assertGreater(result["overlays"]["name"]["pillar_opaque_pixel_intersection"], 0)
            self.assertTrue(result["overlays"]["name"]["layer_above_pillar"])
            self.assertTrue(record["overlays"]["name"]["text_complete"])
            self.assertIn("text-pixel visibility", result["overlays"]["name"]["reason"])

    def test_different_frame_or_transform_is_not_tested(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            manifest, capture = _o1_fixture(Path(temp))
            path = Path(temp) / "r9-o1.json"
            record = json.loads(path.read_text(encoding="utf-8"))
            record["states"]["D"]["frame_id"] = 43
            path.write_text(json.dumps(record), encoding="utf-8")
            result = r9.measure_o1(manifest, capture)
            self.assertEqual(result["status"], "NOT_TESTED")
            self.assertIn("frame ids differ", result["reason"])

        with tempfile.TemporaryDirectory() as temp:
            manifest, capture = _o1_fixture(Path(temp))
            path = Path(temp) / "r9-o1.json"
            record = json.loads(path.read_text(encoding="utf-8"))
            record["states"]["D"]["viewport"]["canvas_transform"] = [1, 0, 0, 1, 1, 0]
            path.write_text(json.dumps(record), encoding="utf-8")
            result = r9.measure_o1(manifest, capture)
            self.assertEqual(result["status"], "NOT_TESTED")
            self.assertIn("canvas transforms", result["reason"])

    def test_missing_o1_record_never_defaults_to_pass(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            manifest = Path(temp) / "capture-manifest.json"
            manifest.write_text("{}", encoding="utf-8")
            result = r9.measure_o1(manifest, {})
            self.assertEqual(result["status"], "NOT_TESTED")
            self.assertIn("missing", result["reason"])


class CliExitContractTests(unittest.TestCase):
    def test_domain_failure_keeps_zero_precondition_exit_for_runner_continuation(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest = root / "capture-manifest.json"
            manifest.write_text("{}", encoding="utf-8")
            output = root / "report.json"
            expected = {"capture_preconditions": "PASS",
                        "measurements": {"summary": {}, "C9_gate": {}},
                        "r9": {"supplemental_gate": "FAIL",
                               "G1": {"status": "FAIL"}, "O1": {"status": "PASS"},
                               "T6_margin": {"status": "PASS"}}}
            argv = ["validate_terrain_pillar_r9.py", str(manifest), "--source-root", temp,
                    "--candidate", "head", "--out", str(output)]
            with patch.object(r9, "validate", return_value=expected), patch.object(sys, "argv", argv):
                with redirect_stdout(StringIO()):
                    code = r9.main()
            self.assertEqual(code, 0)
            report = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(report["r9"]["G1"]["status"], "FAIL")
            self.assertEqual(report["r9"]["supplemental_gate"], "FAIL")

    def test_capture_precondition_failure_returns_nonzero(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest = root / "capture-manifest.json"
            manifest.write_text("{}", encoding="utf-8")
            output = root / "report.json"
            expected = {"capture_preconditions": "FAIL", "capture_errors": ["source hash mismatch"],
                        "measurements": {"summary": {}, "C9_gate": {}},
                        "r9": {"supplemental_gate": "NOT_TESTED", "G1": {"status": "NOT_TESTED"},
                               "O1": {"status": "NOT_TESTED"}, "T6_margin": {"status": "NOT_TESTED"}}}
            argv = ["validate_terrain_pillar_r9.py", str(manifest), "--source-root", temp,
                    "--candidate", "head", "--out", str(output)]
            with patch.object(r9, "validate", return_value=expected), patch.object(sys, "argv", argv):
                with redirect_stdout(StringIO()):
                    code = r9.main()
            self.assertEqual(code, 1)
            report = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(report["capture_preconditions"], "FAIL")


if __name__ == "__main__":
    unittest.main()
