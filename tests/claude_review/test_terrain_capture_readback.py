"""只测试采集证据拒绝条件，合成 PNG 不作为 Godot 或美术证据。"""
import copy
from pathlib import Path
import tempfile
import unittest

import numpy as np
from PIL import Image

from validate_terrain_readability_capture import (
    ROLES, frame_errors, read_images, reconstruction_check, safe_child, sha256, segmentation_check,
    viewport_errors,
)


class ReadbackTests(unittest.TestCase):
    def test_reject_cross_frame_or_missing_identity(self):
        frame = {"callback": "RenderingServer.frame_post_draw", "same_callback": True,
                 "readback_awaits_between_images": False, "frame_id": 7,
                 "frames_drawn_before": 7, "frames_drawn_after": 7,
                 "process_frames_before": 9, "process_frames_after": 9}
        self.assertEqual(frame_errors(frame), [])
        for change in ({"frames_drawn_after": 8}, {"process_frames_after": 10},
                       {"readback_awaits_between_images": True}, {"frame_id": 6},
                       {"frames_drawn_before": None}):
            with self.subTest(change=change):
                self.assertTrue(frame_errors(frame | change))

    def test_original_hash_dimensions_and_frame_are_checked(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            records = {}
            for role in ROLES:
                path = root / f"{role}.png"
                Image.new("RGBA", (8, 8), (50, 100, 150, 255)).save(path)
                records[role] = {"role": role, "path": path.name, "sha256": sha256(path),
                                 "image_size": [8, 8], "frame_id": 4}
            self.assertEqual(read_images(root, records, [8, 8], 4)[1], [])
            altered = copy.deepcopy(records)
            altered["main"]["frame_id"] = 3
            self.assertTrue(read_images(root, altered, [8, 8], 4)[1])
            altered = copy.deepcopy(records)
            altered["main"]["sha256"] = "0" * 64
            self.assertTrue(read_images(root, altered, [8, 8], 4)[1])
            self.assertTrue(read_images(root, records, [16, 16], 4)[1])
            (root / "main.png").unlink()
            self.assertTrue(read_images(root, records, [8, 8], 4)[1])

    def test_reconstruction_must_match_formal_pixels(self):
        main = np.full((8, 8, 4), 255, dtype=np.uint8)
        images = {"main": main, "reconstruction": main.copy(), "props": main.copy()}
        self.assertEqual(reconstruction_check(images)["status"], "PASS")
        images["reconstruction"][4, 4, 0] = 0
        result = reconstruction_check(images)
        self.assertEqual(result["status"], "FAIL")
        self.assertEqual(result["mismatch_pixels"], 1)
        images["reconstruction"] = main.copy()
        images["props"][..., 3] = 0
        self.assertEqual(reconstruction_check(images)["status"], "FAIL")

    def test_missing_required_mask_and_duplicate_reference_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "one.png"
            Image.new("RGBA", (8, 8), "white").save(path)
            one = {"path": path.name, "sha256": sha256(path), "image_size": [8, 8], "frame_id": 4}
            errors = read_images(root, {"main": one, "props": one}, [8, 8], 4)[1]
            self.assertTrue(any("不同角色共用" in e for e in errors))
            self.assertTrue(any("缺失图像" in e for e in errors))

    def test_shifted_segmentation_cannot_pass_with_same_frame_number(self):
        props = np.zeros((8, 8, 4), dtype=np.uint8)
        props[2:5, 2:5] = (255, 255, 255, 253)
        ids = props.copy()
        ids[2:5, 2:5, :3] = (255, 0, 0)
        images = {"props": props, "instance_ids": ids}
        self.assertEqual(segmentation_check(images, {"#FF0000"})["status"], "PASS")
        images["instance_ids"] = np.roll(ids, 1, axis=1)
        self.assertEqual(segmentation_check(images, {"#FF0000"})["status"], "FAIL")

    def test_finite_but_misaligned_viewport_is_rejected(self):
        reference = {"texture_size": [1280, 720], "image_size": [1280, 720],
                     "canvas_transform": [1, 0, 0, 1, 30, 40],
                     "final_transform": [1, 0, 0, 1, 0, 0], "visible_rect": [0, 0, 1280, 720]}
        viewports = {role: copy.deepcopy(reference) for role in ROLES}
        self.assertEqual(viewport_errors(viewports, [1280, 720]), [])
        for field, slot in (("canvas_transform", 4), ("final_transform", 0), ("visible_rect", 2)):
            modified = copy.deepcopy(viewports)
            modified["part_ids"][field][slot] += 1
            self.assertTrue(viewport_errors(modified, [1280, 720]))

    def test_outside_original_reference_is_rejected(self):
        root = Path(tempfile.gettempdir()) / "terrain-readback-test"
        for path in ("../other.png", "/other.png", "a/../../other.png", "a\\..\\other.png"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                safe_child(root, path)


if __name__ == "__main__":
    unittest.main()
