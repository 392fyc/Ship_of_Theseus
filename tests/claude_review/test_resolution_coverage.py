import json
from pathlib import Path
import tempfile
import unittest

from resolution_coverage import REQUIRED, check_manifest


class ResolutionCoverageTests(unittest.TestCase):
    def check(self, records, **extra):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "manifest.json"
            path.write_text(json.dumps({"captures": records, **extra}), encoding="utf-8")
            return check_manifest(path)["pass"]

    def records(self, group="idle"):
        return [{"file": f"{group}-{w}.png", "capture_group": group,
                 "window_size": [w, h], "image_size": [w, h], "capture_kind": "viewport"}
                for w, h in sorted(REQUIRED)]

    def test_complete_states(self):
        self.assertTrue(self.check(self.records() + self.records("hover")))

    def test_incomplete_state_not_hidden_by_other_state(self):
        self.assertFalse(self.check(self.records() + self.records("hover")[:2]))

    def test_repeated_size_does_not_replace_missing_size(self):
        self.assertFalse(self.check(self.records()[:2] * 2))

    def test_detail_does_not_fill_missing_viewport(self):
        records = self.records()
        records[-1]["capture_kind"] = "derived_detail"
        self.assertFalse(self.check(records))

    def test_scaled_file_is_not_native_resolution(self):
        records = self.records()
        records[-1]["image_size"] = [1280, 720]
        self.assertFalse(self.check(records))

    def test_group_required(self):
        records = self.records()
        del records[0]["capture_group"]
        self.assertFalse(self.check(records))

    def test_diagnostic_rejected(self):
        self.assertFalse(self.check(self.records(), runtime_evidence=False))

    def test_empty_rejected(self):
        self.assertFalse(self.check([]))


if __name__ == "__main__":
    unittest.main()
