from __future__ import annotations

import unittest

import numpy as np

from terrain_contact_shadow_v2 import (
    _captured_feet,
    _classify_visible_edge,
    equal_arc_length_samples,
    evaluate_t4,
)


def _good_metric(
    distances: np.ndarray,
    visible_edge: float = 100.0,
    covered_edge: float = 80.0,
    cell_width: float = 30.0,
) -> dict:
    underlying = np.full(len(distances), 50.0)
    shadow = np.full(len(distances), 40.0)
    return evaluate_t4(
        shadow,
        underlying,
        distances,
        visible_edge,
        covered_edge,
        cell_width,
    )


class TerrainContactShadowV2Tests(unittest.TestCase):
    def test_pillar_geometry_is_selected_by_captured_base_role(self):
        side = {
            "node_class": "Polygon2D",
            "global_transform": [1.0, 0.0, 0.0, 1.0, 0.0, 0.0],
            "polygon": [[0, 0], [2, 0], [2, 2], [0, 2]],
        }
        base = {
            "node_class": "Polygon2D",
            "global_transform": [1.0, 0.0, 0.0, 1.0, 0.0, 0.0],
            "polygon": [[0, 0], [2, 0], [3, 1], [2, 2], [0, 2], [-1, 1]],
        }
        capture = {
            "instances": [{
                "stable_id": "pillar@0,0",
                "color": "#010203",
                "parts": {"parts": [
                    {"role": "pillar_side"},
                    {"role": "pillar_base"},
                ]},
            }],
        }
        semantic = {"frame": {"instance_tokens": [{
            "stable_id": "pillar@0,0",
            "type": "pillar",
            "draw_leaf_inputs": [side, base],
        }]}}

        feet, duplicate_edges = _captured_feet(
            capture, semantic, [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]
        )

        self.assertEqual(duplicate_edges, 0)
        self.assertEqual(len(feet[0]["segments"]), 6)
        self.assertEqual(feet[0]["segments"][0]["a"].tolist(), [0.0, 0.0])

    def test_positive_uses_p90_and_reports_max_outlier(self):
        distances = np.full(40, 0.9)
        distances[-1] = 40.0

        result = _good_metric(distances)

        self.assertEqual(result["status"], "PASS")
        self.assertAlmostEqual(result["frozen_metric"]["darkness_l"], 10.0)
        self.assertAlmostEqual(result["width_p90_px"], 0.9)
        self.assertEqual(result["width_max_px"], 40.0)
        self.assertAlmostEqual(result["visible_edge_coverage_ratio"], 0.8)

    def test_floating_shadow_fails_even_when_dark_and_narrow(self):
        distances = np.full(32, 1.01)

        result = _good_metric(distances)

        self.assertEqual(result["status"], "FAIL")
        self.assertFalse(result["checks"]["touches_bottom_edge_within_1px"])

    def test_small_shadow_blob_fails_independent_edge_coverage(self):
        distances = np.full(32, 0.5)

        result = _good_metric(distances, visible_edge=100.0, covered_edge=20.0)

        self.assertEqual(result["status"], "FAIL")
        self.assertAlmostEqual(result["visible_edge_coverage_ratio"], 0.2)
        self.assertFalse(
            result["checks"]["covers_at_least_60_percent_of_visible_bottom_edge"]
        )

    def test_fewer_than_20_shadow_pixels_is_not_tested(self):
        distances = np.full(19, 0.5)

        result = _good_metric(distances)

        self.assertEqual(result["status"], "NOT_TESTED")
        self.assertIsNone(result["frozen_metric"])
        self.assertEqual(result["sample_minimum"], 20)

    def test_p90_width_over_half_cell_fails(self):
        distances = np.full(40, 16.0)

        result = _good_metric(distances, cell_width=30.0)

        self.assertEqual(result["status"], "FAIL")
        self.assertEqual(result["width_p90_px"], 16.0)
        self.assertEqual(result["width_max_px"], 16.0)
        self.assertEqual(result["frozen_metric"]["status"], "FAIL")

    def test_arc_samples_are_equally_spaced_and_preserve_exact_length(self):
        segments = [
            {
                "a": np.array([0.0, 0.0]),
                "b": np.array([3.7, 0.0]),
                "outward": np.array([0.0, 1.0]),
            },
            {
                "a": np.array([0.0, 2.0]),
                "b": np.array([1.1, 2.0]),
                "outward": np.array([0.0, 1.0]),
            },
        ]

        points, normals, weights = equal_arc_length_samples(segments, 0.5)

        self.assertEqual(len(points), len(normals))
        self.assertTrue(np.allclose(normals[:, 1], 1.0))
        self.assertAlmostEqual(float(weights.sum()), 4.8)
        for first, second in zip(points[:7], points[1:8]):
            self.assertLessEqual(float(np.linalg.norm(second - first)), 0.5 + 1e-9)

    def test_opaque_props_grid_and_ui_are_excluded_from_edge_denominator(self):
        empty = np.zeros((8, 8, 4), dtype=np.uint8)
        maps = {
            "ground": empty.copy(),
            "ground_without_shadow": empty.copy(),
            "props": empty.copy(),
            "instance_ids": empty.copy(),
            "grid": empty.copy(),
            "exclusions": empty.copy(),
            "contact_shadow": empty.copy(),
        }
        maps["ground"][..., 3] = 255
        maps["ground_without_shadow"][..., 3] = 255
        owner = (0, 0, 1)
        other = (0, 0, 2)

        # All probes land on row 2. Four separate obstructions and one clear sample.
        maps["props"][2, 1, 3] = 255
        maps["instance_ids"][2, 1] = (*owner, 255)
        maps["props"][2, 2, 3] = 255
        maps["instance_ids"][2, 2] = (*other, 255)
        maps["exclusions"][2, 3, 3] = 255
        maps["grid"][2, 4, 3] = 255
        points = np.array([[1.5, 1.5], [2.5, 1.5], [3.5, 1.5], [4.5, 1.5], [5.5, 1.5]])
        normals = np.repeat([[0.0, 1.0]], len(points), axis=0)
        weights = np.full(len(points), 0.5)

        visible_a, evidence_a = _classify_visible_edge(points, normals, weights, maps, owner)
        maps["contact_shadow"][2, :, 3] = 255
        visible_b, evidence_b = _classify_visible_edge(points, normals, weights, maps, owner)

        self.assertTrue(np.array_equal(visible_a, visible_b))
        self.assertEqual(evidence_a, evidence_b)
        self.assertEqual(visible_a.tolist(), [False, False, False, False, True])
        self.assertEqual(evidence_a["owner_opaque_prop"]["sample_count"], 1)
        self.assertEqual(evidence_a["other_opaque_prop"]["sample_count"], 1)
        self.assertEqual(evidence_a["ui_or_unit_exclusion"]["sample_count"], 1)
        self.assertEqual(evidence_a["grid"]["sample_count"], 1)
        self.assertEqual(evidence_a["unattributed_opaque_prop"]["sample_count"], 0)
        self.assertEqual(evidence_a["missing_ground_pair"]["sample_count"], 0)
        self.assertEqual(evidence_a["outside_capture"]["sample_count"], 0)
        self.assertEqual(evidence_a["visible_ground_edge"]["arc_length_px"], 0.5)


if __name__ == "__main__":
    unittest.main()

