"""Narrow v2 regression tests for explicit hover state and Window Texture sizing."""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import re
import tempfile
import unittest

import numpy as np
from PIL import Image

import claude_review_checks as checks
from validate_terrain_readability_capture_v2 import (
    KINDS, ROLES, capture_state_errors, exclusion_errors_v2, instance_coverage_errors,
    portrait_c4, viewport_errors_v2, _portrait_window_viewport_errors,
)


BOUNDS_SPACE = "main Window visible logical viewport before the viewport stretch transform"


def _valid_exclusion_fixture():
    requested = [4, 2]
    image = np.zeros((2, 4, 4), dtype=np.uint8)
    image[0, 0:3] = [255, 255, 255, 255]
    image[1, 3] = [255, 255, 255, 255]  # Extra alpha is permitted outside declared bounds.
    viewports = {"main": {
        "visible_rect": [0.0, 0.0, 4.0, 2.0],
        "final_transform": [1.0, 0.0, 0.0, 1.0, 0.0, 0.0],
        "native_size": requested,
        "image_size": requested,
    }}
    exclusions = {
        "status": "CAPTURED_WITH_CONSERVATIVE_CONTROL_BOUNDS",
        "bounds_coordinate_space": BOUNDS_SPACE,
        "excluded_background_controls": [{
            "relative_path": "TacticalScene/BattlefieldBackdrop/Ground",
            "class": "ColorRect", "canvas_layer": -1,
            "clipped_rect": [0.0, 0.0, 4.0, 2.0],
            "reason": "formal scene background, not HUD",
        }],
        "drawable_ui_control_bounds": 1,
        "drawable_ui_control_bound_records": [{
            "relative_path": "TacticalScene/Toolbar/Toggle",
            "class": "Button", "canvas_layer": 12,
            "rect": [0.0, 0.0, 2.0, 1.0],
            "clipped_rect": [0.0, 0.0, 2.0, 1.0],
            "area_logical_pixels": 2.0,
        }],
        "drawable_ui_bounds_union_logical_pixels": 2.0,
        "unit_count": 1,
        "unit_screen_bounds": [{"unit_id": "unit-a", "rect": [2.0, 0.0, 1.0, 1.0]}],
        "unit_screen_bounds_union_logical_pixels": 1.0,
        "mask_coverage_status": "CAPTURED",
        "mask_covered_pixels": 4,
        "mask_total_pixels": 8,
        "mask_covered_ratio": 0.5,
        "mask_entire_frame_opaque": False,
        "mask_native_image_size": requested,
    }
    return requested, image, exclusions, viewports


def _portrait_pixels(with_top_gap: bool = False) -> np.ndarray:
    panel = np.array([40, 55, 70, 255], dtype=np.uint8)
    brass = np.array([172, 147, 103, 255], dtype=np.uint8)
    frame_edge = np.array([68, 57, 51, 255], dtype=np.uint8)
    portrait = np.array([130, 35, 105, 255], dtype=np.uint8)
    image = np.empty((720, 1280, 4), dtype=np.uint8)
    image[:] = panel
    image[611:689, 46:114] = portrait
    image[609, 44:116] = brass
    image[690, 44:116] = brass
    image[610, 44:116] = frame_edge
    image[689, 44:116] = frame_edge
    image[609:691, 44] = brass
    image[609:691, 115] = brass
    image[609:691, 45] = frame_edge
    image[609:691, 114] = frame_edge
    if with_top_gap:
        image[611, 49:111] = panel
    return image


def _portrait_window_viewport(size: list[int], scale: list[float]) -> dict:
    expected_texture = [int(np.ceil(size[index] * scale[index])) for index in range(2)]
    transform = [scale[0], 0.0, 0.0, scale[1], 0.0, 0.0]
    return {
        "viewport_kind": "Window",
        "size": size,
        "window_size": size,
        "native_size": size,
        "image_size": size,
        "texture_reported_size": expected_texture,
        "texture_size": expected_texture,
        "stretch_scale": scale,
        "stretch_transform": transform,
        "canvas_transform": [1.0, 0.0, 0.0, 1.0, 0.0, 0.0],
        "final_transform": transform,
        "visible_rect": [0.0, 0.0, 1280.0, 720.0],
    }


def _write_portrait_fixture(root: Path, with_top_gap: bool = False):
    capture_dir = root / "captures"
    capture_dir.mkdir(parents=True)
    source_root = root / "source"
    texture_path = source_root / "assets" / "ui" / "portraits" / "unit.png"
    texture_path.parent.mkdir(parents=True)
    texture_path.write_bytes(b"fixture texture source bytes")
    companion_path = capture_dir / "portrait-hud.png"
    Image.fromarray(_portrait_pixels(with_top_gap)).save(companion_path, format="PNG")
    raw = companion_path.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    size = [1280, 720]
    frame_id = 44
    c8_capture = {
        "file": companion_path.name,
        "sha256": digest,
        "image_size": size,
        "capture_group": "portrait-hud",
        "role": "portrait_hud",
        "frame_id": frame_id,
        "capture_kind": "viewport",
    }
    image_record = {
        "role": "portrait_hud",
        "capture_group": "portrait-hud",
        "path": companion_path.name,
        "sha256": digest,
        "bytes": len(raw),
        "mime_type": "image/png",
        "pixel_format": "RGBA8",
        "image_size": size,
        "frame_id": frame_id,
    }
    fit = {"fit_zoom": 0.92}
    candidate = {"head": "fixture-head", "candidate_digest_sha256": "fixture-candidate"}
    common_frame = {
        "callback": "RenderingServer.frame_post_draw",
        "frame_id": frame_id,
        "frames_drawn_before": frame_id,
        "frames_drawn_after": frame_id,
        "process_frames_before": 44,
        "process_frames_after": 44,
        "same_callback": True,
        "readback_awaits_between_images": False,
        "capture_group": "portrait-hud",
        "image_count": 1,
        "image_roles": ["portrait_hud"],
    }
    companion = {
        "schema_version": "terrain-portrait-companion/1",
        "case_name": "10x10_1280x720",
        "capture_group": "portrait-hud",
        "state": "formal_selected_unit_before_measurement_cancel",
        "selected_unit": "unit-a",
        "portrait_visible": True,
        "portrait_texture_path": "res://assets/ui/portraits/unit.png",
        "portrait_texture_sha256": hashlib.sha256(texture_path.read_bytes()).hexdigest(),
        "portrait_frame_native_rect": [44.0, 609.0, 72.0, 82.0],
        "candidate": candidate,
        "initial_fit": fit,
        "formal_configuration_sha256": "formal-config-sha",
        "viewport": _portrait_window_viewport(size, [1.0, 1.0]),
        "image": image_record,
        "common_frame": common_frame,
        "c8_capture": c8_capture,
    }
    data = {
        "case": {"name": "10x10_1280x720", "requested_resolution": size, "initial_fit": fit},
        "candidate": candidate,
        "common_frame": {"frame_id": 45},
        "capture_state": {"terrain_v4_spawn_configuration": {"main": {
            "actual_formal_configuration_sha256": "formal-config-sha",
        }}},
        "images": {"main": {"path": "main.png"}},
        "portrait_companion": companion,
        "captures": [c8_capture],
    }
    manifest_path = capture_dir / "capture-manifest.json"
    manifest_path.write_text(json.dumps(data), encoding="utf-8")
    return manifest_path, data, source_root, companion_path


def _replace_c8(data, **changes):
    capture = dict(data["portrait_companion"]["c8_capture"])
    capture.update(changes)
    data["portrait_companion"]["c8_capture"] = capture
    data["captures"] = [capture]


class CaptureStateV2Tests(unittest.TestCase):
    def test_two_visible_pillars_still_fail_the_three_instance_gate(self):
        instances = {kind: 3 for kind in KINDS}
        visible = {kind: 3 for kind in KINDS}
        visible["pillar"] = 2
        self.assertEqual(instance_coverage_errors(instances, visible), [
            "pillar: 少于三个实例或少于三个可见实例",
        ])

    def test_no_hover_state_requires_matching_sessions_and_hidden_tooltips(self):
        state = {
            "headless_structure_only": False,
            "state_source": "explicit capture override copied from the main validated session",
            "pointer": {
                "requested_logical_position": [1272.0, 712.0],
                "actual_logical_position": [1272.0, 712.0],
                "requested_grid_cell": [-1, 28],
                "actual_grid_cell": [-1, 28],
                "physical_input_used_as_state_authority": False,
                "reconstruction_pointer_used": False,
            },
            "hover": {
                "requested_cell": [-1, -1],
                "main_cell": [-1, -1],
                "reconstruction_cell": [-1, -1],
                "main_tooltip": {"available": True, "visible": False, "visible_in_tree": False},
                "reconstruction_tooltip": {"available": True, "visible": False, "visible_in_tree": False},
                "main_gui_hovered_control_observation": "",
                "reconstruction_gui_hit_test_used": False,
            },
            "unit_highlight_context": {
                "hover_cell": [-1, -1], "unit_count": 0, "units": [],
                "highlight_count": 0, "highlights": [], "copied_to_reconstruction": True,
            },
            "prop_synchronization": {
                "includes_shrub_and_relief": True, "property_order_copied_from_main": True,
                "main_prop_count": 12, "reconstruction_prop_count": 12,
            },
            "canvas_state_synchronization": {
                "matched_canvas_items": 24, "independent_state_calculation_tested": False,
                "terrain_branch": "independently generated from the same validated map; draw payload equality checked before runtime CanvasItem state sync",
                "terrain_draw_nodes_verified": 40, "sibling_index_class_matches": 4,
                "highlight_shapes_copied": 2, "copied_draw_payload_nodes": 12,
            },
            "freeze": {
                "scope": "all descendants of both formal TerrainBattleSession roots before mask-pass construction",
                "main_frozen_nodes": 10, "reconstruction_frozen_nodes": 10, "total_frozen_nodes": 20,
            },
        }
        self.assertEqual(capture_state_errors(state, [10, 10]), [])

        mismatched = copy.deepcopy(state)
        mismatched["hover"]["reconstruction_cell"] = [3, 4]
        mismatched["hover"]["reconstruction_tooltip"]["visible"] = True
        errors = capture_state_errors(mismatched, [10, 10])
        self.assertTrue(any("无悬停格" in error for error in errors))
        self.assertTrue(any("reconstruction_tooltip" in error for error in errors))

    def test_exclusion_bounds_keep_hud_measurable_and_reject_full_frame_mask(self):
        requested, image, exclusions, viewports = _valid_exclusion_fixture()
        self.assertEqual(exclusion_errors_v2(exclusions, {"exclusions": image}, requested, viewports), [])

        all_white = image.copy()
        all_white[..., 3] = 255
        full_frame = copy.deepcopy(exclusions)
        full_frame.update({
            "mask_covered_pixels": 8,
            "mask_covered_ratio": 1.0,
            "mask_entire_frame_opaque": True,
        })
        errors = exclusion_errors_v2(full_frame, {"exclusions": all_white}, requested, viewports)
        self.assertTrue(any("覆盖整张画面" in error for error in errors))

        wrong_role = copy.deepcopy(exclusions)
        wrong_role["excluded_background_controls"][0]["relative_path"] = "TacticalScene/UILayer/Panel"
        errors = exclusion_errors_v2(wrong_role, {"exclusions": image}, requested, viewports)
        self.assertTrue(any("背景角色" in error for error in errors))

    def test_exclusion_bounds_reject_transparent_mask(self):
        requested, image, exclusions, viewports = _valid_exclusion_fixture()
        image[..., 3] = 0
        exclusions.update({"mask_covered_pixels": 0, "mask_covered_ratio": 0.0})
        errors = exclusion_errors_v2(exclusions, {"exclusions": image}, requested, viewports)
        self.assertTrue(any("UI bounds 内" in error for error in errors))
        self.assertTrue(any("单位 bounds 内" in error for error in errors))

    def test_exclusion_bounds_reject_alpha_only_outside_declared_ranges(self):
        requested, image, exclusions, viewports = _valid_exclusion_fixture()
        image[..., 3] = 0
        image[1, 3] = [255, 255, 255, 255]
        exclusions.update({"mask_covered_pixels": 1, "mask_covered_ratio": 0.125})
        errors = exclusion_errors_v2(exclusions, {"exclusions": image}, requested, viewports)
        self.assertTrue(any("UI bounds 内" in error for error in errors))
        self.assertTrue(any("单位 bounds 内" in error for error in errors))

    def test_exclusion_bounds_reject_missing_ui_or_unit_ranges(self):
        requested, image, exclusions, viewports = _valid_exclusion_fixture()
        missing_ui = copy.deepcopy(exclusions)
        missing_ui["drawable_ui_control_bounds"] = 0
        missing_ui["drawable_ui_control_bound_records"] = []
        missing_ui["drawable_ui_bounds_union_logical_pixels"] = 0.0
        errors = exclusion_errors_v2(missing_ui, {"exclusions": image}, requested, viewports)
        self.assertTrue(any("UI bounds" in error for error in errors))

        missing_units = copy.deepcopy(exclusions)
        missing_units["unit_count"] = 0
        missing_units["unit_screen_bounds"] = []
        missing_units["unit_screen_bounds_union_logical_pixels"] = 0.0
        errors = exclusion_errors_v2(missing_units, {"exclusions": image}, requested, viewports)
        self.assertTrue(any("单位保守 bounds 清单" in error for error in errors))

    def test_exclusion_bounds_map_to_native_pixel_centers(self):
        requested = [6, 3]
        image = np.zeros((3, 6, 4), dtype=np.uint8)
        image[0, 0:4] = [255, 255, 255, 255]
        image[1, 2] = [255, 255, 255, 128]  # Logical y=1 boundary; outside the half-open bound.
        exclusions = {
            "status": "CAPTURED_WITH_CONSERVATIVE_CONTROL_BOUNDS",
            "bounds_coordinate_space": BOUNDS_SPACE,
            "excluded_background_controls": [{
                "relative_path": "TacticalScene/BattlefieldBackdrop/Ground",
                "class": "ColorRect", "canvas_layer": -1,
                "clipped_rect": [0.0, 0.0, 4.0, 2.0],
                "reason": "formal scene background, not HUD",
            }],
            "drawable_ui_control_bounds": 1,
            "drawable_ui_control_bound_records": [{
                "relative_path": "TacticalScene/Toolbar/Toggle",
                "class": "Button", "canvas_layer": 12,
                "rect": [0.0, 0.0, 2.0, 1.0],
                "clipped_rect": [0.0, 0.0, 2.0, 1.0],
                "area_logical_pixels": 2.0,
            }],
            "drawable_ui_bounds_union_logical_pixels": 2.0,
            "unit_count": 1,
            "unit_screen_bounds": [{"unit_id": "unit-a", "rect": [2.0, 0.0, 1.0, 1.0]}],
            "unit_screen_bounds_union_logical_pixels": 1.0,
            "mask_coverage_status": "CAPTURED",
            "mask_covered_pixels": 5,
            "mask_total_pixels": 18,
            "mask_covered_ratio": 5 / 18,
            "mask_entire_frame_opaque": False,
            "mask_native_image_size": requested,
        }
        viewports = {"main": {
            "visible_rect": [0.0, 0.0, 4.0, 2.0],
            "final_transform": [1.5, 0.0, 0.0, 1.5, 0.0, 0.0],
            "native_size": requested,
            "image_size": requested,
        }}
        self.assertEqual(exclusion_errors_v2(exclusions, {"exclusions": image}, requested, viewports), [])

    def test_window_texture_reported_size_is_distinct_from_raw_png_size(self):
        requested = [1920, 1080]
        reference = {
            "size": requested,
            "image_size": requested,
            "native_size": requested,
            "texture_size": requested,
            "texture_reported_size": requested,
            "canvas_transform": [1.0, 0.0, 0.0, 1.0, 20.0, 30.0],
            "final_transform": [1.0, 0.0, 0.0, 1.0, 0.0, 0.0],
            "visible_rect": [0.0, 0.0, 1280.0, 720.0],
            "stretch_transform": [1.5, 0.0, 0.0, 1.5, 0.0, 0.0],
            "stretch_scale": [1.5, 1.5],
            "window_size": [],
            "viewport_kind": "SubViewport",
        }
        viewports = {role: copy.deepcopy(reference) for role in ROLES}
        for role in ROLES - {"main"}:
            viewports[role]["viewport_kind"] = "SubViewport"
        main = viewports["main"]
        main["viewport_kind"] = "Window"
        main["window_size"] = requested
        main["texture_size"] = [2880, 1620]
        main["texture_reported_size"] = [2880, 1620]

        self.assertEqual(viewport_errors_v2(viewports, requested), [])

        wrong_texture = copy.deepcopy(viewports)
        wrong_texture["main"]["texture_reported_size"] = requested
        wrong_texture["main"]["texture_size"] = requested
        self.assertTrue(any("Window Texture" in error for error in viewport_errors_v2(wrong_texture, requested)))

        resized_native = copy.deepcopy(viewports)
        resized_native["main"]["native_size"] = [2880, 1620]
        self.assertTrue(any("native_size" in error for error in viewport_errors_v2(resized_native, requested)))

        wrong_subviewport = copy.deepcopy(viewports)
        wrong_subviewport["reconstruction"]["texture_reported_size"] = [2880, 1620]
        wrong_subviewport["reconstruction"]["texture_size"] = [2880, 1620]
        self.assertTrue(any("Texture 报告尺寸" in error for error in viewport_errors_v2(wrong_subviewport, requested)))


class PortraitCompanionV2Tests(unittest.TestCase):
    def test_valid_companion_uses_its_single_real_png_and_unchanged_c4_rule(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            manifest, data, source_root, png_path = _write_portrait_fixture(Path(temp_dir))
            result = portrait_c4(manifest, data, source_root)
            self.assertTrue(result["pass"], result)
            self.assertEqual(result["source"], "portrait_companion")
            self.assertEqual(result["frame_id"], 44)
            self.assertEqual(result["sha256"], hashlib.sha256(png_path.read_bytes()).hexdigest())

    def test_companion_rejects_wrong_image_frame_role_or_c8_binding(self):
        mutations = (
            ("wrong image frame", lambda data: data["portrait_companion"]["image"].update(frame_id=43), "帧号"),
            ("wrong image role", lambda data: data["portrait_companion"]["image"].update(role="main"), "角色"),
            ("wrong C8 hash", lambda data: _replace_c8(data, sha256="f" * 64), "C8"),
        )
        for label, mutate, expected in mutations:
            with self.subTest(label=label), tempfile.TemporaryDirectory() as temp_dir:
                manifest, data, source_root, _ = _write_portrait_fixture(Path(temp_dir))
                mutate(data)
                result = portrait_c4(manifest, data, source_root)
                self.assertFalse(result["pass"], result)
                self.assertTrue(any(expected in error for error in result.get("errors", [])), result)

    def test_companion_rejects_corrupt_png_bytes(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            manifest, data, source_root, png_path = _write_portrait_fixture(Path(temp_dir))
            png_path.write_bytes(b"corrupt PNG bytes")
            result = portrait_c4(manifest, data, source_root)
            self.assertFalse(result["pass"], result)
            self.assertTrue(any("字节数" in error or "SHA256" in error or "解码" in error
                                for error in result.get("errors", [])), result)

    def test_companion_keeps_the_existing_c4_gap_threshold(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            manifest, data, source_root, _ = _write_portrait_fixture(Path(temp_dir), with_top_gap=True)
            result = portrait_c4(manifest, data, source_root)
            self.assertFalse(result["pass"], result)
            self.assertEqual(result["panel_colour_rows"]["top"], 1)

    def test_manifest_without_companion_keeps_legacy_main_image_behavior(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            pixels = Image.fromarray(_portrait_pixels())
            main_path = root / "main.png"
            pixels.save(main_path, format="PNG")
            result = portrait_c4(root / "capture-manifest.json", {
                "images": {"main": {"path": "main.png"}},
            }, root)
            self.assertTrue(result["pass"], result)

    def test_semantic_manifest_without_companion_rejects_a_passing_main_image(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            Image.fromarray(_portrait_pixels()).save(root / "main.png", format="PNG")
            result = portrait_c4(root / "capture-manifest.json", {
                "images": {"main": {"path": "main.png"}},
                "sources": {"res://tests/claude_review/capture_terrain_readability_v6_regions_semantic_sidecar.gd": {}},
            }, root)
            self.assertFalse(result["pass"], result)
            self.assertEqual(result["source"], "portrait_companion")
            self.assertTrue(any("缺少" in error for error in result["errors"]), result)

    def test_gdscript_captures_a_distinct_frame_and_rejects_missing_portrait_nodes(self):
        repository = Path(__file__).resolve().parents[2]
        script = (repository / "tests/claude_review/capture_terrain_readability_v6_regions_semantic_sidecar.gd").read_text(encoding="utf-8")
        capture_state = script.split("func _establish_frozen_capture_state() -> bool:", 1)[1].split(
            "func _semantic_capture_portrait_companion() -> bool:", 1)[0]
        self.assertLess(capture_state.index("await _semantic_capture_portrait_companion()"),
                        capture_state.index('cancel.action = "ui_cancel"'))
        for node in ("BottomRow", "CharacterHudPanel", "PortraitContent", "PortraitFrame"):
            self.assertIn(f'get_node_or_null("{node}")', script)
        self.assertIn('"image_roles": ["portrait_hud"]', script)
        self.assertIn('c8_capture["role"] = "portrait_hud"', script)
        self.assertIn('c8_capture["frame_id"] = drawn_before', script)
        self.assertIn('window.get_final_transform() * border.get_global_transform_with_canvas()', script)

    def test_c4_search_rect_contains_the_real_formal_hud_frame_by_one_pixel(self):
        repository = Path(__file__).resolve().parents[2]
        bottom_path = repository / "scenes/tactical/hud/m2/bottom_hud_composition.tscn"
        portrait_path = repository / "scenes/tactical/hud/m2/character_hud_panel.tscn"

        def node_offsets(path: Path, name: str) -> dict[str, float]:
            source = path.read_text(encoding="utf-8")
            match = re.search(rf'^\[node name="{re.escape(name)}"[^\]]*\](.*?)(?=^\[node|\Z)',
                              source, re.M | re.S)
            if match is None:
                self.fail(f"missing TSCN node {name} in {path.name}")
            return {
                axis: float(re.search(rf"^{attribute} = ([0-9.]+)$", match.group(1), re.M).group(1))
                for axis, attribute in (("left", "offset_left"), ("top", "offset_top"),
                                        ("right", "offset_right"), ("bottom", "offset_bottom"))
            }

        row = node_offsets(bottom_path, "BottomRow")
        frame = node_offsets(portrait_path, "PortraitFrame")
        actual = (row["left"] + frame["left"], row["top"] + frame["top"],
                  frame["right"] - frame["left"], frame["bottom"] - frame["top"])
        algorithm = checks.PORTRAIT_FRAME_1280
        self.assertEqual(actual, (44.0, 609.0, 72.0, 82.0))
        self.assertEqual(actual, (algorithm[0] + 1, algorithm[1] + 1,
                                  algorithm[2] - 2, algorithm[3] - 2))

    def test_portrait_window_texture_mapping_accepts_all_three_project_stretch_sizes(self):
        cases = (([1280, 720], [1.0, 1.0]), ([1920, 1080], [1.5, 1.5]),
                 ([2560, 1440], [2.0, 2.0]))
        for size, scale in cases:
            with self.subTest(size=size):
                viewport = _portrait_window_viewport(size, scale)
                self.assertEqual(_portrait_window_viewport_errors(viewport, size), [])
                wrong_texture = copy.deepcopy(viewport)
                wrong_texture["texture_size"] = size
                wrong_texture["texture_reported_size"] = size
                if scale != [1.0, 1.0]:
                    self.assertTrue(any("Texture 尺寸" in error for error in
                                        _portrait_window_viewport_errors(wrong_texture, size)))


if __name__ == "__main__":
    unittest.main()
