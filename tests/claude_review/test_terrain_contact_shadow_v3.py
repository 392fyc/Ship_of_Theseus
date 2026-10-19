from __future__ import annotations

import unittest

from terrain_contact_shadow_v3 import DiagnosticError, _captured_feet


# Exact geometry excerpt from wall@3.00,1.00 in the bound attempt-13 source
# capture. The original capture and semantic manifests remain untouched.
# capture-manifest.json SHA256:
# 855f6d4bff79b06a2a51e2fa7e229b498a2bf8fe5e4edcacb7f298393c9de4a5
# semantic-sidecar-manifest.json SHA256:
# 00bb49c6f7a49edcbe8eaabbf472f162436ae104da74d2bf391697a7c6baaa88
STABLE_ID = "wall@3.00,1.00"
CANVAS = [
    0.920000016689301,
    0.0,
    0.0,
    0.920000016689301,
    245.599990844727,
    161.440017700195,
]
CAPTURED_SIDE_PANEL = {
    "node_class": "Polygon2D",
    "node_name": "@Polygon2D@397",
    "relative_path": "0",
    "global_transform": [1.0, 0.0, 0.0, 1.0, 384.0, 128.0],
    "polygon": [
        [8.0, -12.7446479797363],
        [0.0, -17.0771656036377],
        [0.0, 8.0],
        [8.0, 12.0],
    ],
}
CAPTURED_MUD_BAND = {
    "node_class": "Polygon2D",
    "node_name": "@Polygon2D@398",
    "relative_path": "1",
    "global_transform": [1.0, 0.0, 0.0, 1.0, 384.0, 128.0],
    "polygon": [
        [8.0, 7.54596328735352],
        [0.0, 3.4861102104187],
        [0.0, 8.0],
        [8.0, 12.0],
    ],
}
CAPTURED_LEFT_SIDE_PANEL = {
    "node_class": "Polygon2D",
    "node_name": "@Polygon2D@404",
    "relative_path": "7",
    "global_transform": [1.0, 0.0, 0.0, 1.0, 384.0, 128.0],
    "polygon": [
        [0.0, -17.0771656036377],
        [-8.0, -9.0679988861084],
        [-8.0, 12.0],
        [0.0, 8.0],
    ],
}
CAPTURED_MASONRY_SEAM = {
    "node_class": "Line2D",
    "node_name": "@Line2D@399",
    "relative_path": "2",
    "width": 1.0,
    "global_transform": [1.0, 0.0, 0.0, 1.0, 384.0, 128.0],
    "points": [
        [8.0, 3.75178337097168],
        [0.0, -0.359055519104004],
    ],
}


def _wall_input(leaves: list[dict] | None = None, roles: list[str] | None = None):
    selected = leaves if leaves is not None else [
        CAPTURED_SIDE_PANEL.copy(),
        CAPTURED_MUD_BAND.copy(),
        CAPTURED_MASONRY_SEAM.copy(),
    ]
    selected_roles = roles if roles is not None else ["wall_side"] * len(selected)
    if len(selected_roles) != len(selected):
        raise ValueError("fixture roles and leaves must have the same length")
    return (
        {
            "instances": [{
                "stable_id": STABLE_ID,
                "color": "#010203",
                "parts": {"parts": [
                    {"role": role} for role in selected_roles
                ]},
            }],
        },
        {"frame": {"instance_tokens": [{
            "stable_id": STABLE_ID,
            "type": "wall",
            "draw_leaf_inputs": selected,
        }]}},
    )


class TerrainContactShadowV3GeometryTests(unittest.TestCase):
    def test_captured_side_and_internal_masonry_seam_keep_polygon_bottom_once(self):
        capture, semantic = _wall_input()

        feet, duplicate_edges = _captured_feet(capture, semantic, CANVAS)

        self.assertEqual(duplicate_edges, 1)
        self.assertEqual(len(feet[0]["segments"]), 1)
        self.assertEqual(feet[0]["wall_side_polygon_leaf_count"], 2)
        self.assertEqual(len(feet[0]["excluded_wall_side_lines"]), 1)
        seam = feet[0]["excluded_wall_side_lines"][0]
        self.assertEqual(seam["line_leaf"]["leaf_index"], 2)
        self.assertEqual(
            seam["matched_side_face_leaves"][0]["leaf_index"], 0
        )
        self.assertEqual(
            seam["physical_bottom_edge_group"]["side_face_leaf_count"], 1
        )
        self.assertEqual(seam["width_px"], 1.0)
        self.assertEqual(
            seam["centerline_points_px"],
            [
                [606.2399973869329, 282.65166060033414],
                [598.8799972534185, 278.8696887528574],
            ],
        )

    def test_multiple_faces_in_one_bottom_edge_group_are_accepted(self):
        seam = CAPTURED_MASONRY_SEAM.copy()
        seam["points"] = [[0.0, 8.0], [8.0, 12.0]]
        capture, semantic = _wall_input([
            CAPTURED_SIDE_PANEL.copy(),
            CAPTURED_MUD_BAND.copy(),
            seam,
        ])

        feet, _ = _captured_feet(capture, semantic, CANVAS)

        excluded_line = feet[0]["excluded_wall_side_lines"][0]
        self.assertEqual(
            [leaf["leaf_index"] for leaf in excluded_line["matched_side_face_leaves"]],
            [0, 1],
        )
        self.assertEqual(
            excluded_line["physical_bottom_edge_group"]["side_face_leaf_count"],
            2,
        )

    def test_line_on_shared_left_right_face_boundary_spanning_bottom_groups_is_rejected(self):
        ambiguous_line = CAPTURED_MASONRY_SEAM.copy()
        ambiguous_line["node_name"] = "@Line2D@ambiguous-inner-boundary"
        ambiguous_line["relative_path"] = "8"
        ambiguous_line["points"] = [[0.0, -4.0], [0.0, 0.0]]
        filler_leaves = []
        for index in range(1, 7):
            filler = CAPTURED_SIDE_PANEL.copy()
            filler["node_name"] = f"@ignored-wall-top-{index}"
            filler["relative_path"] = str(index)
            filler_leaves.append(filler)
        leaves = [
            CAPTURED_SIDE_PANEL.copy(),
            *filler_leaves,
            CAPTURED_LEFT_SIDE_PANEL.copy(),
            ambiguous_line,
        ]
        roles = ["wall_side", *(["wall_top"] * 6), "wall_side", "wall_side"]
        capture, semantic = _wall_input(leaves, roles)

        with self.assertRaisesRegex(
            DiagnosticError,
            "spans 2 distinct physical bottom-edge groups",
        ):
            _captured_feet(capture, semantic, CANVAS)

    def test_free_floating_wall_side_line_is_rejected(self):
        line = CAPTURED_MASONRY_SEAM.copy()
        line["points"] = [[100.0, 100.0], [101.0, 101.0]]
        capture, semantic = _wall_input([
            CAPTURED_SIDE_PANEL.copy(), line,
        ])

        with self.assertRaisesRegex(DiagnosticError, "has no captured four-vertex face"):
            _captured_feet(capture, semantic, CANVAS)

    def test_wall_side_line_with_an_unrecognized_width_is_rejected(self):
        line = CAPTURED_MASONRY_SEAM.copy()
        line["width"] = 2.0
        capture, semantic = _wall_input([
            CAPTURED_SIDE_PANEL.copy(), line,
        ])

        with self.assertRaisesRegex(DiagnosticError, "is not the captured 1px seam"):
            _captured_feet(capture, semantic, CANVAS)

    def test_line_without_a_polygon_face_is_rejected(self):
        capture, semantic = _wall_input([CAPTURED_MASONRY_SEAM.copy()])

        with self.assertRaisesRegex(DiagnosticError, "no captured Polygon2D wall_side bottom geometry"):
            _captured_feet(capture, semantic, CANVAS)

    def test_unknown_wall_side_node_type_is_rejected(self):
        unknown = CAPTURED_MASONRY_SEAM.copy()
        unknown["node_class"] = "CanvasItem"
        capture, semantic = _wall_input([
            CAPTURED_SIDE_PANEL.copy(), unknown,
        ])

        with self.assertRaisesRegex(DiagnosticError, "unsupported node type"):
            _captured_feet(capture, semantic, CANVAS)

    def test_invalid_four_point_wall_side_geometry_is_rejected(self):
        invalid = CAPTURED_SIDE_PANEL.copy()
        invalid["polygon"] = [
            [8.0, -12.7446479797363],
            [0.0, -17.0771656036377],
            [0.0, 8.0],
            [0.0, 8.0],
        ]
        capture, semantic = _wall_input([invalid])

        with self.assertRaisesRegex(DiagnosticError, "zero-length edge"):
            _captured_feet(capture, semantic, CANVAS)


if __name__ == "__main__":
    unittest.main()
