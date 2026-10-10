"""Focused tests for exact semantic labels and frozen T2/T3 sample gates.

Synthetic arrays exercise validator logic only; they are not native capture or art evidence.
"""
from __future__ import annotations

import copy
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import numpy as np
from PIL import Image

import claude_review_checks as checks
import validate_terrain_semantic_sidecar as sidecar


ROOT = Path(__file__).resolve().parents[2]


def _rgba(height: int, width: int, rgb: tuple[int, int, int] = (0, 0, 0),
          alpha: int = 0) -> np.ndarray:
    image = np.zeros((height, width, 4), dtype=np.uint8)
    image[..., :3] = rgb
    image[..., 3] = alpha
    return image


def _png_bytes(array: np.ndarray) -> bytes:
    output = io.BytesIO()
    Image.fromarray(array).save(output, format="PNG")
    return output.getvalue()


def _binding_fixture(directory: Path) -> tuple[Path, dict, dict]:
    size = [4, 4]
    candidate = {"source_sha256": {}}
    case = {"map_size": [10, 10], "requested_resolution": size}
    main_viewport = {
        "size": size,
        "image_size": size,
        "texture_size": size,
        "canvas_transform": [1, 0, 0, 1, 0, 0],
        "final_transform": [1, 0, 0, 1, 0, 0],
        "visible_rect": [0, 0, 4, 4],
    }
    roles = ["main", "reconstruction", "props", "instance_ids", "part_ids", "ground",
             "ground_without_shadow", "ground_types", "grid", "exclusions",
             "contact_shadow", "tree_crown_union"]
    capture = {
        "candidate": candidate,
        "case": case,
        "images": {role: {} for role in roles},
        "viewports": {"main": main_viewport},
        "common_frame": {
            "frame_id": 7,
            "frames_drawn_before": 7,
            "frames_drawn_after": 7,
            "process_frames_before": 11,
            "process_frames_after": 11,
            "readback_awaits_between_images": False,
        },
    }
    capture_path = directory / "capture-manifest.json"
    capture_bytes = json.dumps(capture, sort_keys=True).encode("utf-8")
    capture_path.write_bytes(capture_bytes)

    image_records = {}
    for role in ("semantic_pair", "semantic_coverage"):
        relative = f"{role}.png"
        raw = _png_bytes(_rgba(4, 4))
        (directory / relative).write_bytes(raw)
        image_records[role] = {
            "role": role,
            "path": relative,
            "sha256": hashlib.sha256(raw).hexdigest(),
            "bytes": len(raw),
            "image_size": size,
            "frame_id": 7,
            "pixel_format": "RGBA8",
        }
    frame = {
        "frame_id": 7,
        "callback": "RenderingServer.frame_post_draw",
        "frames_drawn_before": 7,
        "frames_drawn_after": 7,
        "process_frames_before": 11,
        "process_frames_after": 11,
        "same_frame": True,
        "readback_awaits_between_images": False,
        "original_capture_image_count_unchanged": 12,
        "original_capture_roles_unchanged": sorted(roles),
        "window_size": size,
        "images": image_records,
        "viewports": {
            "main": main_viewport,
            "semantic_pair": copy.deepcopy(main_viewport),
            "semantic_coverage": copy.deepcopy(main_viewport),
        },
    }
    sidecar_manifest = {
        "schema_version": sidecar.SIDECAR_SCHEMA,
        "capture_manifest_path": "capture-manifest.json",
        "capture_manifest_sha256": hashlib.sha256(capture_bytes).hexdigest(),
        "capture_candidate": candidate,
        "candidate_source_sha256": {},
        "case": case,
        "frame": frame,
    }
    return capture_path, capture, sidecar_manifest


def _wall_fixture() -> tuple[dict, dict[str, np.ndarray], np.ndarray, np.ndarray,
                              list[dict], np.ndarray]:
    height = width = 64
    token = 0x123456
    pair = _rgba(height, width)
    coverage = _rgba(height, width)
    top = np.s_[20:30, 20:28]
    side = np.s_[20:30, 28:38]
    rgb = sidecar.token_to_rgb(token)
    pair[top][..., :3] = rgb
    pair[top][..., 3] = sidecar.PART_CODES["wall_top"]
    pair[side][..., :3] = rgb
    pair[side][..., 3] = sidecar.PART_CODES["wall_side"]
    coverage[top][..., 0] = np.resize(np.array([242, 245], dtype=np.uint8), pair[top][..., 0].shape)
    coverage[side][..., 0] = 245
    coverage[top][..., 3] = 255
    coverage[side][..., 3] = 255

    main = _rgba(height, width, (125, 125, 125), 255)
    main[top] = (220, 220, 220, 255)
    main[side] = (70, 70, 70, 255)
    ground_types = _rgba(height, width, (0, 0, 0), 255)
    paving = (120, 120, 120)
    ground_types[..., :3] = paving
    images = {"main": main, "ground_types": ground_types}
    manifest = {"masks": {"ground_types": {"classes": {
        "paving": {"color": "#787878", "semantic": "paving"},
        "grass": {"color": "#28a028", "semantic": "grass"},
    }}}}
    instances = [{"stable_id": "wall-a", "token": token,
                  "token_rgb": list(rgb), "type": "wall"}]
    blocked = np.zeros((height, width), dtype=bool)
    return manifest, images, pair, coverage, instances, blocked


def _tree_fixture() -> tuple[dict, dict, dict[str, np.ndarray], np.ndarray, np.ndarray,
                              list[dict], np.ndarray]:
    height = width = 64
    token = 0x654321
    pair = _rgba(height, width)
    coverage = _rgba(height, width)
    crown = np.s_[20:40, 20:40]
    dark_side = np.s_[20:40, 30:40]
    rgb = sidecar.token_to_rgb(token)
    pair[crown][..., :3] = rgb
    pair[crown][..., 3] = sidecar.PART_CODES["tree_crown"]
    pair[dark_side][..., 3] = sidecar.PART_CODES["tree_dark_side"]
    coverage[crown][..., 0] = 242
    coverage[dark_side][..., 0] = 245
    coverage[crown][..., 3] = 255
    coverage[dark_side][..., 3] = 255

    main = _rgba(height, width, (100, 170, 50), 255)
    main[crown] = (30, 130, 30, 255)
    ground_types = _rgba(height, width, (0, 0, 0), 255)
    ground_types[..., :3] = (100, 170, 50)
    tree_union = _rgba(height, width)
    tree_union[crown] = (255, 255, 255, 255)
    tree_input = {
        "status": "APPROVED",
        "approved_scope": ["dark_side_geometry", "outline_absence"],
        "author_annotation_sha256": "a" * 64,
        "independent_review_sha256": "b" * 64,
        "base_crown_annotation_sha256": "c" * 64,
        "outline_semantics": {"present": False, "reason": "reviewed explicit absence"},
        "effective_outline_status": "absent_authoritatively",
    }
    manifest = {
        "masks": {"ground_types": {"classes": {
            "paving": {"color": "#787878", "semantic": "paving"},
            "grass": {"color": "#64aa32", "semantic": "grass"},
        }}},
        "tree_semantic_input": tree_input,
    }
    sidecar_manifest = {"tree_semantic_input": copy.deepcopy(tree_input)}
    images = {"main": main, "ground_types": ground_types, "tree_crown_union": tree_union}
    instances = [{"stable_id": "tree-a", "token": token,
                  "token_rgb": list(rgb), "type": "tree"}]
    blocked = np.zeros((height, width), dtype=bool)
    return manifest, sidecar_manifest, images, pair, coverage, instances, blocked


class TerrainSemanticSidecarTests(unittest.TestCase):
    def _classification_errors(self, codes: list[int]) -> list[str]:
        image = _rgba(1, len(codes))
        image[0, :, 0] = codes
        image[0, :, 3] = np.where(image[0, :, 0] != 0, 255, 0)
        raw = _png_bytes(image)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "tree-regions.png"
            path.write_bytes(raw)
            decoded = sidecar._read_rgba_png(
                path, expected_size=[len(codes), 1],
                expected_sha256=hashlib.sha256(raw).hexdigest(),
                expected_bytes=len(raw))
        np.testing.assert_array_equal(decoded, image)
        record = {
            "status": "READY",
            "atlas_uv_mapping": {
                "uv_space": "Godot 4.6 CanvasItem UV is normalized over the original atlas texture used by AtlasTexture",
                "atlas_pixel": "UV * atlas_size",
                "region_local_uv": "(atlas_pixel - atlas_region.position) / atlas_region.size",
                "region_texel": "floor(region_local_uv * region_map_size); map texels represent source region pixel centers",
                "sampler": "filter_nearest, repeat_disable",
            },
            "map_has_mipmaps": False,
            "coverage_samples_classification_map": False,
            "pair_samples_classification_map": True,
            "source_alpha_sampler": "original Sprite2D AtlasTexture TEXTURE through incoming COLOR.a",
            "fallback_part_code": 255,
            "map_rgb_role": "R is a code byte normalized to 0..1; G/B are zero",
            "map_alpha_role": "255 marks a reviewed code texel; it is never used as source opacity",
            "source_data_sha256": hashlib.sha256(decoded.tobytes()).hexdigest(),
        }
        tree = {"type": "tree", "stable_id": "tree-a", "tree_region_inputs": {
            "classification_map": record,
            "source_alpha_sampler": "original Sprite2D AtlasTexture COLOR.a; source texture filter/repeat/mipmap remain unchanged",
            "region_map_does_not_supply_alpha": True,
            "single_source_sprite_draw_preserves_order": True,
        }}
        return sidecar.validate_tree_classification_map(
            {"classification_maps": {"tree_regions": record}}, [tree],
            {"tree_classification_map": decoded})

    def test_tree_classification_preserves_decoded_rgba8_code_bytes(self):
        self.assertEqual(self._classification_errors([0, 7, 8, 9]), [])

    def test_tree_classification_rejects_unreviewed_and_wrapped_code_bytes(self):
        for code in (1, 6, 10, 11, 247, 248, 249, 255):
            with self.subTest(code=code):
                errors = self._classification_errors([0, code])
                self.assertIn("tree 类别图含非审查部件码", errors)

    def test_token_bytes_round_trip_and_duplicate_tokens_fail(self):
        for token in (1, 0x123456, 0xFFFFFF):
            self.assertEqual(sidecar.rgb_to_token(sidecar.token_to_rgb(token)), token)
        pair, coverage = _rgba(1, 1), _rgba(1, 1)
        first = {"stable_id": "wall-a", "token": 1, "token_rgb": [0, 0, 1], "type": "wall"}
        duplicate = {"stable_id": "tree-a", "token": 1, "token_rgb": [0, 0, 1], "type": "tree"}
        errors = sidecar.validate_label_coverage_arrays(pair, coverage, [first, duplicate])
        self.assertTrue(any("多个对象共用" in error for error in errors))

    def test_zero_alpha_keeps_prior_label_and_unknown_nonzero_alpha_occludes(self):
        pair, coverage = sidecar.composite_semantic_samples([
            {"token": 1, "part_code": sidecar.PART_CODES["wall_top"], "source_alpha": 255},
            {"token": 2, "part_code": sidecar.PART_CODES["unknown"], "source_alpha": 0},
        ])
        self.assertEqual(sidecar.rgb_to_token(pair[0, 0, :3]), 1)
        pair, coverage = sidecar.composite_semantic_samples([
            {"token": 1, "part_code": sidecar.PART_CODES["wall_top"], "source_alpha": 255},
            {"token": 2, "part_code": sidecar.PART_CODES["unknown"], "source_alpha": 242},
        ])
        self.assertEqual(sidecar.rgb_to_token(pair[0, 0, :3]), 2)
        self.assertEqual(int(pair[0, 0, 3]), 255)
        self.assertEqual(coverage[0, 0].tolist(), [242, 0, 0, 255])
        records = [
            {"stable_id": "wall-a", "token": 1, "token_rgb": [0, 0, 1], "type": "wall"},
            {"stable_id": "unknown-a", "token": 2, "token_rgb": [0, 0, 2], "type": "unknown"},
        ]
        props = _rgba(1, 1)
        props[0, 0] = (0, 0, 0, 242)
        self.assertEqual(sidecar.validate_label_coverage_arrays(pair, coverage, records, props), [])

    def test_atlas_uv_mapping_handles_reviewed_nonzero_region_offset_and_pixel_centers(self):
        atlas_size = (2048, 1024)
        atlas_region = (286, 33, 964, 950)
        source_texel = (455, 115)
        atlas_uv = ((atlas_region[0] + source_texel[0] + 0.5) / atlas_size[0],
                    (atlas_region[1] + source_texel[1] + 0.5) / atlas_size[1])
        local_uv = sidecar.atlas_uv_to_region_local_uv(atlas_uv, atlas_size, atlas_region)
        self.assertAlmostEqual(local_uv[0], (source_texel[0] + 0.5) / atlas_region[2])
        self.assertAlmostEqual(local_uv[1], (source_texel[1] + 0.5) / atlas_region[3])
        self.assertEqual(sidecar.region_local_uv_to_texel(local_uv, atlas_region[2:]), source_texel)

        region_start_uv = sidecar.atlas_uv_to_region_local_uv(
            (atlas_region[0] / atlas_size[0], atlas_region[1] / atlas_size[1]),
            atlas_size, atlas_region)
        region_end_uv = sidecar.atlas_uv_to_region_local_uv(
            ((atlas_region[0] + atlas_region[2]) / atlas_size[0],
             (atlas_region[1] + atlas_region[3]) / atlas_size[1]),
            atlas_size, atlas_region)
        self.assertEqual(sidecar.region_local_uv_to_texel(region_start_uv, atlas_region[2:]), (0, 0))
        self.assertIsNone(sidecar.region_local_uv_to_texel(region_end_uv, atlas_region[2:]))

    def test_tree_shader_keeps_original_alpha_and_single_sprite_draw(self):
        shader_path = ROOT / "tests/claude_review/terrain_semantic_sidecar.gdshader"
        capture_path = ROOT / "tests/claude_review/capture_terrain_readability_v6_regions_semantic_sidecar.gd"
        shader = shader_path.read_text(encoding="utf-8")
        capture_source = capture_path.read_text(encoding="utf-8")
        map_sampler = "uniform sampler2D semantic_region_map : filter_nearest, repeat_disable;"
        self.assertIn(map_sampler, shader)
        self.assertIn("float effective_source_alpha = COLOR.a;", shader)
        self.assertLess(shader.index("effective_source_alpha <= 0.0"),
                        shader.index("if (coverage_output)"))
        self.assertLess(shader.index("if (coverage_output)"),
                        shader.index("texture(semantic_region_map, region_local_uv)"))
        self.assertIn("COLOR = vec4(effective_source_alpha, 0.0, 0.0, 1.0);", shader)
        self.assertIn("Image.create(local_size.x, local_size.y, false, Image.FORMAT_RGBA8)", capture_source)
        self.assertIn("classification.has_mipmaps()", capture_source)
        self.assertNotIn("_semantic_tree_classification_texture.has_mipmaps()", capture_source)
        self.assertIn("Vector2(float(x) + 0.5, float(y) + 0.5)", capture_source)
        self.assertIn("_semantic_point_in_polygon_set(source_point, crown_polygons)", capture_source)
        self.assertIn("_semantic_point_in_polygon_set(source_point, dark_polygons)", capture_source)
        self.assertIn("copy_sprite.material as ShaderMaterial", capture_source)
        self.assertIn('"draw_order_stable_ids": _semantic_sidecar_draw_order_stable_ids()', capture_source)
        self.assertIn("sort_custom(func(a: Node2D, b: Node2D)", capture_source)
        self.assertIn('get("source_order", -1)', capture_source)
        self.assertNotIn("_make_annotated_texture", capture_source)
        self.assertNotIn("_semantic_runtime_source_for_record", capture_source)

        tree_draw_method = capture_source.split("func _semantic_apply_tree_classification_map", 1)[1].split(
            "func _semantic_ensure_tree_classification_map", 1)[0]
        self.assertNotIn("add_child", tree_draw_method)
        self.assertNotIn("Sprite2D.new()", tree_draw_method)

    def test_wall_t2_uses_alpha_095_096_and_keeps_uncertainty_visible(self):
        manifest, images, pair, coverage, instances, blocked = _wall_fixture()
        visible, uncertain = sidecar.alpha_sample_masks(coverage)
        self.assertGreater(int(np.count_nonzero(visible)), 0)
        self.assertTrue(np.all(visible[20:30, 20:38]))
        self.assertTrue(np.all(uncertain[20:30, 20:38]))
        rows = sidecar.measure_t2_instances(manifest, images, pair, coverage, instances, blocked)["wall"]
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["status"], "PASS")
        self.assertGreater(rows[0]["top_pixels"], 0)
        self.assertGreater(rows[0]["side_pixels"], 0)
        self.assertGreater(rows[0]["paving_pixels"], 0)
        self.assertGreater(rows[0]["alpha_uncertain_top_pixels"], 0)
        self.assertGreater(rows[0]["alpha_uncertain_side_pixels"], 0)
        self.assertTrue(rows[0]["alpha_uncertain_samples_included"])
        self.assertIn("top_l", rows[0])
        self.assertIn("side_l", rows[0])
        self.assertIn("paving_l", rows[0])

    def test_tree_t3_includes_dark_side_in_crown_and_calls_both_frozen_metrics(self):
        manifest, sidecar_manifest, images, pair, coverage, instances, blocked = _tree_fixture()
        rows = sidecar.measure_t3_trees(manifest, sidecar_manifest, images, pair,
                                        coverage, instances, blocked)
        self.assertEqual(len(rows), 1)
        row = rows[0]
        self.assertEqual(row["outline_check"]["status"], "PASS")
        self.assertEqual(row["outline_check"]["outline_present"], False)
        self.assertEqual(row["T3"]["status"], "PASS")
        self.assertEqual(row["T3"]["crown_pixels"], 400)
        self.assertEqual(row["T3"]["dark_side_pixels"], 200)
        self.assertEqual(row["T3"]["alpha_uncertain_crown_pixels"], 400)
        self.assertGreater(row["T3"]["outer_grass_pixels"], 0)
        self.assertIn("delta_l", row["T3"])
        self.assertIn("delta_e00", row["T3"])

    def test_empty_outline_is_not_absence_without_approved_scope(self):
        manifest, sidecar_manifest, images, pair, coverage, instances, blocked = _tree_fixture()
        tree = manifest["tree_semantic_input"]
        tree["approved_scope"] = ["dark_side_geometry"]
        tree["effective_outline_status"] = "NOT_TESTED"
        sidecar_manifest["tree_semantic_input"] = copy.deepcopy(tree)
        row = sidecar.measure_t3_trees(manifest, sidecar_manifest, images, pair,
                                       coverage, instances, blocked)[0]
        self.assertEqual(row["outline_check"]["status"], "NOT_TESTED")
        self.assertEqual(row["T3"]["status"], "NOT_TESTED")
        self.assertIn("empty outline data is not an independently approved absence",
                      row["outline_check"]["reason"])

    def test_binding_rejects_frame_size_and_exact_png_hash_mismatches(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            capture_path, capture, sidecar_manifest = _binding_fixture(directory)
            errors, arrays = sidecar.validate_sidecar_binding(capture_path, capture, sidecar_manifest)
            self.assertEqual(errors, [])
            self.assertEqual(arrays["semantic_pair"].shape, (4, 4, 4))

            changed_frame = copy.deepcopy(sidecar_manifest)
            changed_frame["frame"]["frame_id"] = 8
            errors, _ = sidecar.validate_sidecar_binding(capture_path, capture, changed_frame)
            self.assertTrue(any("frame_id" in error for error in errors))

            changed_size = copy.deepcopy(sidecar_manifest)
            changed_size["frame"]["images"]["semantic_pair"]["image_size"] = [5, 4]
            errors, _ = sidecar.validate_sidecar_binding(capture_path, capture, changed_size)
            self.assertTrue(any("尺寸" in error or "原生尺寸" in error for error in errors))

            (directory / "semantic_pair.png").write_bytes(_png_bytes(_rgba(4, 4, (1, 2, 3), 255)))
            errors, _ = sidecar.validate_sidecar_binding(capture_path, capture, sidecar_manifest)
            self.assertTrue(any("SHA256 不一致" in error for error in errors))

            (directory / "semantic_pair.png").write_bytes(_png_bytes(_rgba(4, 4)))
            ordered = copy.deepcopy(sidecar_manifest)
            ordered["frame"]["instance_tokens"] = [
                {"stable_id": "later", "type": "wall", "source_order": 1},
                {"stable_id": "first", "type": "unknown", "source_order": 0},
            ]
            ordered["frame"]["draw_order_stable_ids"] = ["first", "later"]
            errors, _ = sidecar.validate_sidecar_binding(capture_path, capture, ordered)
            self.assertEqual(errors, [])
            ordered["frame"]["draw_order_stable_ids"] = ["later", "first"]
            errors, _ = sidecar.validate_sidecar_binding(capture_path, capture, ordered)
            self.assertTrue(any("draw_order_stable_ids" in error for error in errors))

    def test_alignment_requires_exact_unique_wall_and_tree_pixel_anchors(self):
        props, legacy_ids, legacy_parts = _rgba(2, 2), _rgba(2, 2), _rgba(2, 2)
        pair, coverage = _rgba(2, 2), _rgba(2, 2)
        wall_rgb, tree_rgb = (1, 2, 3), (4, 5, 6)
        wall_token, tree_token = 1, 2
        for y, x, old_rgb, token, part_code, old_part_rgb in (
            (0, 0, wall_rgb, wall_token, sidecar.PART_CODES["wall_top"], (20, 30, 40)),
            (1, 1, tree_rgb, tree_token, sidecar.PART_CODES["tree_crown"], (50, 60, 70)),
        ):
            props[y, x] = (0, 0, 0, 255)
            legacy_ids[y, x] = (*old_rgb, 255)
            legacy_parts[y, x] = (*old_part_rgb, 255)
            pair[y, x] = (*sidecar.token_to_rgb(token), part_code)
            coverage[y, x] = (255, 0, 0, 255)
        capture = {
            "instances": [
                {"stable_id": "wall-a", "color": "#010203"},
                {"stable_id": "tree-a", "color": "#040506"},
            ],
            "masks": {"part_ids": {"classes": {
                "wall_top": {"color": "#141e28"},
                "tree_crown": {"color": "#323c46"},
            }}},
        }
        records = [
            {"stable_id": "wall-a", "token": 1, "token_rgb": [0, 0, 1], "type": "wall"},
            {"stable_id": "tree-a", "token": 2, "token_rgb": [0, 0, 2], "type": "tree"},
        ]
        images = {"props": props, "instance_ids": legacy_ids, "part_ids": legacy_parts}
        report = sidecar.pixel_alignment_report(capture, images, pair, coverage, records)
        self.assertEqual(report["status"], "PASS")
        self.assertEqual(report["opaque_instance_matches_by_kind"], {"wall": 1, "tree": 1})
        pair[0, 0, 0] = 9
        report = sidecar.pixel_alignment_report(capture, images, pair, coverage, records)
        self.assertEqual(report["status"], "FAIL")

    def test_negative_control_requires_complete_numeric_metric_failure(self):
        rows = [
            {"status": "FAIL", "top_pixels": 8, "side_pixels": 9, "paving_pixels": 10,
             "top_l": 30.0, "side_l": 29.0, "paving_l": 25.0},
            {"status": "FAIL"},
        ]
        report = sidecar._negative_control(rows, batch_ready=True)
        self.assertEqual(report["status"], "ESTABLISHED")
        self.assertEqual(report["measured_failures"], 1)
        self.assertEqual(report["not_tested_rows"], 1)
        tree_row = {"outline_check": {"status": "PASS", "outline_pixels": 0},
                    "T3": {"status": "FAIL", "crown_pixels": 20, "dark_side_pixels": 5,
                           "outer_grass_pixels": 40, "delta_l": 4.0, "delta_e00": 6.0}}
        self.assertEqual(sidecar._negative_control([tree_row], batch_ready=True)["status"],
                         "ESTABLISHED")
        self.assertEqual(sidecar._negative_control(rows, batch_ready=False)["status"], "NOT_TESTED")

    @staticmethod
    def _wall_metric(status: str = "FAIL") -> dict:
        return {"status": status, "top_pixels": 8, "side_pixels": 9,
                "paving_pixels": 10, "top_l": 30.0, "side_l": 29.0,
                "paving_l": 25.0}

    @staticmethod
    def _tree_metric(status: str = "FAIL") -> dict:
        return {
            "outline_check": {"status": "PASS", "outline_pixels": 0},
            "T3": {"status": status, "crown_pixels": 20, "dark_side_pixels": 5,
                   "outer_grass_pixels": 40, "delta_l": 4.0, "delta_e00": 6.0},
        }

    @staticmethod
    def _case_result(map_size: int, resolution: tuple[int, int], *,
                     frozen: str = "PASS", semantic: str = "PASS",
                     wall: list[dict] | None = None,
                     trees: list[dict] | None = None) -> dict:
        return {
            "case": {"map_size": [map_size, map_size],
                     "requested_resolution": list(resolution)},
            "frozen_capture_preconditions": frozen,
            "semantic_sidecar_preconditions": semantic,
            "T2_wall_instances": list(wall or []),
            "T2_pillar_instances": [],
            "T3_tree_instances": list(trees or []),
            "measurement_status": "MEASURED_WHERE_READY" if frozen == "PASS" and semantic == "PASS" else "NOT_TESTED",
            "art_acceptance": "NOT_TESTED",
        }

    def test_pilot_numeric_wall_and_tree_failures_open_material_review_gate(self):
        pilot = self._case_result(10, (1280, 720),
                                  wall=[self._wall_metric()],
                                  trees=[self._tree_metric()])
        gate = sidecar._pilot_gate(pilot)
        self.assertEqual(gate["preconditions"], "PASS")
        self.assertEqual(gate["remaining_five_capture_action"], "CONTINUE")
        self.assertEqual(gate["negative_controls"]["old_wall_T2"]["status"], "ESTABLISHED")
        self.assertEqual(gate["negative_controls"]["old_tree_complete_T3"]["status"], "ESTABLISHED")
        self.assertEqual(gate["negative_controls"]["old_wall_T2"]["rows_with_numeric_metric_evidence"], 1)
        self.assertEqual(gate["material_gate"], "OPEN_FOR_MATERIAL_ITERATION_REVIEW")

    def test_pilot_prerequisites_pass_with_invalid_or_missing_failures_continues_closed(self):
        pilot = self._case_result(10, (1280, 720),
                                  wall=[{"status": "FAIL"}],
                                  trees=[self._tree_metric("PASS")])
        gate = sidecar._pilot_gate(pilot)
        self.assertEqual(gate["preconditions"], "PASS")
        self.assertEqual(gate["remaining_five_capture_action"], "CONTINUE")
        self.assertEqual(gate["negative_controls"]["old_wall_T2"]["status"], "NOT_TESTED")
        self.assertEqual(gate["negative_controls"]["old_tree_complete_T3"]["status"], "NOT_ESTABLISHED")
        self.assertEqual(gate["material_gate"], "CLOSED")
        missing = sidecar._pilot_gate(self._case_result(10, (1280, 720)))
        self.assertEqual(missing["remaining_five_capture_action"], "CONTINUE")
        self.assertEqual(missing["material_gate"], "CLOSED")

    def test_pilot_phase_reads_one_case_and_returns_continue_when_only_negative_gate_is_closed(self):
        pilot = self._case_result(10, (1280, 720), trees=[self._tree_metric("PASS")])
        with mock.patch.object(sidecar, "validate_case", return_value=pilot):
            output = sidecar.validate_pilot([Path("pilot/capture-manifest.json")], ROOT, "candidate")
        self.assertEqual(output["phase"], "pilot")
        self.assertEqual(output["pilot_10x10_720p"]["preconditions"], "PASS")
        self.assertEqual(output["pilot_10x10_720p"]["remaining_five_capture_action"], "CONTINUE")
        self.assertEqual(output["material_gate"], "CLOSED")
        self.assertEqual(output["cases"][0]["T3_tree_instances"][0]["T3"]["status"], "PASS")
        self.assertEqual(sidecar.validation_exit_code("pilot", output), 0)

    def test_pilot_prerequisite_failure_stops_even_if_rows_claim_numeric_failures(self):
        pilot = self._case_result(10, (1280, 720), frozen="FAIL",
                                  wall=[self._wall_metric()], trees=[self._tree_metric()])
        gate = sidecar._pilot_gate(pilot)
        output = {"pilot_10x10_720p": gate}
        self.assertEqual(gate["remaining_five_capture_action"], "STOP")
        self.assertEqual(gate["material_gate"], "CLOSED")
        self.assertEqual(sidecar.validation_exit_code("pilot", output), 1)

    def test_batch_full_gate_is_independent_from_pilot_material_gate(self):
        cases = [(10, (1280, 720))]
        cases.extend((10, resolution) for resolution in ((1920, 1080), (2560, 1440)))
        cases.extend((25, resolution) for resolution in ((1280, 720), (1920, 1080), (2560, 1440)))
        results = [self._case_result(size, resolution,
                                     wall=[self._wall_metric()] if index == 0 else [],
                                     trees=[self._tree_metric()] if index == 0 else [],
                                     frozen="PASS" if index == 0 else "FAIL",
                                     semantic="PASS" if index == 0 else "FAIL")
                   for index, (size, resolution) in enumerate(cases)]
        manifests = [Path(f"capture-{index}.json") for index in range(6)]
        with mock.patch.object(sidecar, "validate_case", side_effect=results):
            output = sidecar.validate_batch(manifests, ROOT, "candidate")
        self.assertTrue(output["six_case_coverage"])
        self.assertEqual(output["batch_final_gate"], "FAIL_OR_INCOMPLETE")
        self.assertEqual(output["pilot_10x10_720p"]["remaining_five_capture_action"], "CONTINUE")
        self.assertEqual(output["material_gate"], "OPEN_FOR_MATERIAL_ITERATION_REVIEW")
        self.assertEqual(output["negative_controls"]["old_wall_T2"]["rows_reported"], 1)
        self.assertEqual(output["negative_controls"]["old_tree_complete_T3"]["rows_reported"], 1)
        self.assertEqual(sidecar.validation_exit_code("batch", output), 1)

    def test_native_capture_guard_is_before_inherited_case_loop(self):
        source = (ROOT / sidecar.SIDECAR_SOURCE_FILES[0]).read_text(encoding="utf-8")
        run_source = source[source.index("func _run() -> void:"):source.index("func _create_capture_passes(")]
        self.assertIn("if _headless_check:", run_source)
        self.assertLess(run_source.index("if _map_sizes.size() != 1 or _resolutions.size() != 1:"),
                        run_source.index("await super._run()", run_source.index("if _map_sizes.size() != 1")))

    def test_c8_reports_capture_script_as_non_runtime_configuration(self):
        source = ROOT / sidecar.SIDECAR_SOURCE_FILES[0]
        result = checks.c8_script(source)
        self.assertTrue(result["pass"], result)


if __name__ == "__main__":
    unittest.main()
