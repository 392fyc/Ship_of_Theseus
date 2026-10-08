"""Narrow v2 regression tests for explicit hover state and Window Texture sizing."""
from __future__ import annotations

import copy
import unittest

import numpy as np

from validate_terrain_readability_capture_v2 import (
    KINDS, ROLES, capture_state_errors, exclusion_errors_v2, instance_coverage_errors,
    viewport_errors_v2,
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


if __name__ == "__main__":
    unittest.main()
