"""Narrow v3 regressions for actual manager hover state and independent highlights."""
from __future__ import annotations

import copy
import unittest

from validate_terrain_readability_capture_v3 import (
    independent_highlight_errors,
    manager_hover_normalization_errors,
)


def _valid_hover_normalization() -> dict:
    return {
        "input_method": "TacticalManager.handle_pointer_hover",
        "target_grid_cell": [-1, -1],
        "target_is_invalid_in_both_grids": True,
        "target_world_position": [0.0, -24.0],
        "main_viewport_position": [641.0, 351.0],
        "reconstruction_viewport_position": [641.0, 351.0],
        "before": {
            "main": {"has_hover": False, "hover_cell": [4, 3], "hover_cell_valid": True},
            "reconstruction": {"has_hover": True, "hover_cell": [4, 3], "hover_cell_valid": True},
        },
        "after": {
            "main": {"has_hover": False, "hover_cell": [4, 3], "hover_cell_valid": True},
            "reconstruction": {"has_hover": False, "hover_cell": [4, 3], "hover_cell_valid": True},
        },
        "deferred_frees_waited": True,
        "normalized": True,
    }


def _valid_highlight_comparison() -> dict:
    digest = "a" * 64
    return {
        "independently_generated": True,
        "strict_sibling_order_and_class": True,
        "main_sibling_classes": ["Polygon2D", "Line2D"],
        "reconstruction_sibling_classes": ["Polygon2D", "Line2D"],
        "sibling_classes_match": True,
        "main_payload_sha256": digest,
        "reconstruction_payload_sha256": digest,
        "payload_equal": True,
        "copied_to_reconstruction": False,
        "main_nodes_compared": 5,
        "reconstruction_nodes_compared": 5,
        "main_draw_payload_nodes_compared": 4,
        "reconstruction_draw_payload_nodes_compared": 4,
        "deferred_frees_waited": True,
    }


class TerrainCaptureV3StateTests(unittest.TestCase):
    def test_actual_hover_normalization_records_both_manager_states(self):
        self.assertEqual(manager_hover_normalization_errors({
            "manager_hover_normalization": _valid_hover_normalization(),
        }), [])

    def test_hover_normalization_rejects_a_manager_that_still_has_hover(self):
        state = _valid_hover_normalization()
        state["after"]["reconstruction"]["has_hover"] = True
        errors = manager_hover_normalization_errors({"manager_hover_normalization": state})
        self.assertTrue(any("仍有悬停" in error for error in errors))

    def test_independent_highlight_payload_requires_equal_siblings_and_no_copy(self):
        self.assertEqual(independent_highlight_errors({
            "independent_highlight_payload": _valid_highlight_comparison(),
        }), [])

    def test_independent_highlight_payload_rejects_mismatch_or_copied_state(self):
        comparison = copy.deepcopy(_valid_highlight_comparison())
        comparison["reconstruction_payload_sha256"] = "b" * 64
        comparison["payload_equal"] = False
        comparison["copied_to_reconstruction"] = True
        errors = independent_highlight_errors({"independent_highlight_payload": comparison})
        self.assertTrue(any("不相等" in error for error in errors))
        self.assertTrue(any("不能复制" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
