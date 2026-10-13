from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CAPTURE_PATH = ROOT / "tests/claude_review/capture_terrain_readability_v6_atlas.gd"


class AtlasMaskSamplingContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = CAPTURE_PATH.read_text(encoding="utf-8")
        cls.builder = cls.source.split("func _make_annotated_texture", 1)[1].split("\n\nfunc ", 1)[0]
        cls.validator = cls.source.split("func _validate_annotated_region_clone", 1)[1].split("\n\nfunc ", 1)[0]

    def test_crown_mask_uses_full_atlas_and_source_atlas_properties(self) -> None:
        self.assertIn("Image.create(source_atlas_image.get_width(), source_atlas_image.get_height()", self.builder)
        self.assertIn("masked_atlas.atlas = ImageTexture.create_from_image(full_atlas_mask)", self.builder)
        self.assertIn("masked_atlas.region = source_atlas.region", self.builder)
        self.assertIn("masked_atlas.margin = source_atlas.margin", self.builder)
        self.assertIn("masked_atlas.filter_clip = source_atlas.filter_clip", self.builder)
        self.assertIn("_sha256_text(JSON.stringify(polygon_records))", self.builder)

    def test_entry_and_inheritance_chain_are_bound_for_capture_and_sidecar(self) -> None:
        expected_scripts = (
            "capture_terrain_readability_v6_atlas.gd",
            "capture_terrain_readability_v6_regions_semantic_sidecar.gd",
            "capture_terrain_readability_v6_regions.gd",
            "capture_terrain_readability_v6.gd",
            "capture_terrain_readability.gd",
        )
        for script_name in expected_scripts:
            self.assertIn(script_name, self.source)
        self.assertIn('capture_config["capture_entry_script"] = ATLAS_MASK_ENTRY_SCRIPT', self.source)
        self.assertIn('candidate["capture_entry_script"] = ATLAS_MASK_ENTRY_SCRIPT', self.source)
        self.assertIn('candidate["capture_script_inheritance"] = ATLAS_MASK_SCRIPT_CHAIN.duplicate()', self.source)
        self.assertIn("source_hashes[relative] = FileAccess.get_sha256(absolute)", self.source)

    def test_validator_checks_full_atlas_and_region_image_separately(self) -> None:
        self.assertIn("mask_atlas.region != source_atlas.region", self.validator)
        self.assertIn("mask_atlas.margin != source_atlas.margin", self.validator)
        self.assertIn("mask_atlas.filter_clip != source_atlas.filter_clip", self.validator)
        self.assertIn("mask_atlas_image.get_size()", self.validator)
        self.assertIn("var region_image: Image = mask_atlas.get_image()", self.validator)
        self.assertIn("region_image.get_size() != _atlas_region_rect(source_atlas.region).size", self.validator)
        self.assertIn('validation["nonzero_alpha_pixels_in_region_mask"] = alpha_pixels', self.validator)

    def test_diagnosed_pixels_keep_their_full_atlas_and_region_local_coordinates(self) -> None:
        atlas_size = (1536, 1024)
        atlas_region = (286, 33, 964, 950)
        observed = {(873, 319): 152, (874, 319): 44}
        mask = bytearray(atlas_size[0] * atlas_size[1])
        for (x, y), alpha in observed.items():
            mask[y * atlas_size[0] + x] = alpha

        region_x, region_y, region_width, region_height = atlas_region
        region_mask = bytearray(region_width * region_height)
        for (x, y), alpha in observed.items():
            local_x, local_y = x - region_x, y - region_y
            self.assertTrue(0 <= local_x < region_width and 0 <= local_y < region_height)
            region_mask[local_y * region_width + local_x] = mask[y * atlas_size[0] + x]

        self.assertEqual(len(mask), atlas_size[0] * atlas_size[1])
        self.assertEqual((region_width, region_height), (964, 950))
        self.assertEqual(region_mask[286 * region_width + 587], 152)
        self.assertEqual(region_mask[286 * region_width + 588], 44)
        self.assertEqual(mask[319 * atlas_size[0] + 873], 152)
        self.assertEqual(mask[319 * atlas_size[0] + 874], 44)


if __name__ == "__main__":
    unittest.main()