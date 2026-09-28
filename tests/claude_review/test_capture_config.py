"""C8 的正反例校准：配置、空批次、真实图片身份与派生图边界。"""
import copy
import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from PIL import Image
import claude_review_checks as checks


class CaptureConfigTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        Image.new('RGB', (128, 72), 'navy').save(self.root / 'frame.png')
        self.manifest = self.root / 'capture-metadata.json'
        self.good = {
            'renderer': 'forward_plus', 'project_stretch_mode': 'canvas_items',
            'captures': [{'file': 'frame.png', 'sha256': hashlib.sha256((self.root / 'frame.png').read_bytes()).hexdigest(),
                          'image_size': [128, 72], 'window_size': [128, 72],
                          'content_scale_mode': 1, 'content_scale_size': [1280, 720],
                          'visible_rect': [0, 0, 1280, 720], 'capture_kind': 'viewport'}],
        }
        self.old_root = checks.ROOT
        self.project = self.root / 'project'
        self.project.mkdir()
        (self.project / 'project.godot').write_text('[display]\nwindow/stretch/mode="canvas_items"\nwindow/size/viewport_width=1280\nwindow/size/viewport_height=720\n', encoding='utf-8')
        checks.ROOT = self.project

    def tearDown(self):
        checks.ROOT = self.old_root
        self.temp.cleanup()

    def verify(self, data):
        self.manifest.write_text(json.dumps(data), encoding='utf-8')
        return checks.c8_manifest(self.manifest)['pass']

    def test_valid_frame_and_legacy_visible_size(self):
        self.assertTrue(self.verify(self.good))
        self.good['captures'][0]['visible_rect'] = [1280, 720]
        self.assertTrue(self.verify(self.good))

    def test_missing_or_empty_captures(self):
        for captures in (None, [], {}, ['frame.png']):
            data = dict(self.good, captures=captures)
            self.assertFalse(self.verify(data))

    def test_diagnostics_are_not_runtime_evidence(self):
        self.good["runtime_evidence"] = False
        self.assertFalse(self.verify(self.good))

    def test_renderer_mismatch(self):
        self.good['renderer'] = 'gl_compatibility'
        self.assertFalse(self.verify(self.good))

    def test_disabled_stretch_or_missing_project_mode(self):
        data = copy.deepcopy(self.good)
        data['captures'][0]['content_scale_mode'] = 0
        self.assertFalse(self.verify(data))
        del self.good['project_stretch_mode']
        self.assertFalse(self.verify(self.good))

    def test_boolean_is_not_a_stretch_enum(self):
        self.good["captures"][0]["content_scale_mode"] = True
        self.assertFalse(self.verify(self.good))

    def test_missing_capture_fields(self):
        for field in ('window_size', 'content_scale_size', 'image_size', 'visible_rect', 'sha256'):
            data = copy.deepcopy(self.good)
            del data['captures'][0][field]
            self.assertFalse(self.verify(data), field)

    def test_wrong_size_and_replaced_image(self):
        data = copy.deepcopy(self.good)
        data['captures'][0]['image_size'] = [1920, 1080]
        self.assertFalse(self.verify(data))
        Image.new('RGB', (128, 72), 'red').save(self.root / 'frame.png')
        self.assertFalse(self.verify(self.good))

    def test_duplicate_or_escape_path(self):
        data = copy.deepcopy(self.good)
        data['captures'].append(copy.deepcopy(data['captures'][0]))
        self.assertFalse(self.verify(data))
        self.good['captures'][0]['file'] = '../frame.png'
        self.assertFalse(self.verify(self.good))

    def test_derived_detail_requires_source_and_full_frame(self):
        Image.new('RGB', (32, 32), 'navy').save(self.root / 'detail.png')
        detail = dict(self.good['captures'][0], file='detail.png',
                      sha256=hashlib.sha256((self.root / 'detail.png').read_bytes()).hexdigest(),
                      image_size=[32, 32], capture_kind='derived_detail', source_file='frame.png',
                      source_sha256=self.good['captures'][0]['sha256'], source_region=[0, 0, 8, 8], scale=4)
        self.good['captures'].append(detail)
        self.assertTrue(self.verify(self.good))
        del detail['source_sha256']
        self.assertFalse(self.verify(self.good))
        self.good['captures'] = [detail]
        self.assertFalse(self.verify(self.good))

    def test_invalid_rect_coordinates_and_scale(self):
        for rect in (['bad', None, 1280, 720], [float('nan'), 0, 1280, 720], [0, 0, float('inf'), 720]):
            data = copy.deepcopy(self.good)
            data['captures'][0]['visible_rect'] = rect
            self.assertFalse(self.verify(data))
        detail = dict(self.good['captures'][0], capture_kind='derived_detail', source_file='frame.png',
                      source_sha256=self.good['captures'][0]['sha256'], source_region=[0, 0, 128, 72], scale=1)
        Image.open(self.root / 'frame.png').save(self.root / 'detail.png')
        detail['file'] = 'detail.png'
        for region, scale in ((['bad', None, 8, 8], 4), ([0, 0, 8, 8], -4),
                              ([0, 0, 8, 8], float('inf')), ([127, 0, 8, 8], 4)):
            data = copy.deepcopy(self.good)
            data['captures'].append(dict(detail, source_region=region, scale=scale))
            self.assertFalse(self.verify(data))

    def test_late_comment_does_not_exempt_runtime_capture(self):
        script = 'extends SceneTree\nfunc _run():\n\t## 不代表运行配置\n\troot.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED\n'
        self.assertFalse(checks.c8_rule(script)['pass'])

    def test_static_calibration(self):
        self.assertTrue(checks.c8_calibration()['calibration_ok'])


if __name__ == '__main__':
    unittest.main()
