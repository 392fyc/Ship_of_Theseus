"""T1 integration tests; synthetic arrays are not runtime or art evidence."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import numpy as np

import terrain_readability_metrics as metrics
import validate_terrain_contour_v1 as contour


class ContourTests(unittest.TestCase):
    def fixture(self):
        own = np.zeros((100, 120), bool)
        own[30:70, 40:80] = True
        return np.where(own, 60., 25.), own, np.zeros_like(own)

    def test_singleton_reuses_frozen_math_and_thresholds(self):
        lightness, own, excluded = self.fixture()
        for value in (60., 30.):
            lightness[own] = value
            expected = metrics.contour(lightness, own, excluded)
            actual = contour.measure_contour(lightness, own, own, excluded)
            for key, result in expected.items():
                self.assertEqual(actual[key], result, key)

    def test_group_median_is_complete_exterior_not_instance_local_ring(self):
        lightness, own, excluded = self.fixture()
        own[:] = False
        own[40:60, 20:40] = True
        group = own.copy()
        group[40:60, 40:110] = True
        lightness[group] = 60
        outer = metrics.morph(group, 4) & ~group
        lightness[outer] = 5
        lightness[outer & metrics.morph(own, 4)] = 40
        actual = contour.measure_contour(lightness, own, group, excluded)
        inner = own & ~metrics.morph(own, 2, erode=True)
        self.assertEqual(actual['median_delta_l'],
                         abs(float(np.median(lightness[inner]) - np.median(lightness[outer]))))
        self.assertNotEqual(actual['median_delta_l'],
                            actual['instance_local_outer_median_delta_l_diagnostic'])

    def test_internal_seam_has_no_reference_but_keeps_instance_denominator(self):
        lightness, own, excluded = self.fixture()
        own[:] = False
        own[30:70, 70:80] = True
        group = own.copy()
        group[30:70, 80:110] = True
        lightness[group] = 60
        actual = contour.measure_contour(lightness, own, group, excluded)
        self.assertEqual(actual['perimeter_edges'], 100)
        self.assertGreater(actual['instance_outer_inside_group_pixels'], 0)
        self.assertLess(actual['measurable_share'], 1)
        self.assertEqual(actual['status'], 'NOT_TESTED')

    def test_excluded_edges_are_not_removed_to_buy_pass(self):
        lightness, own, excluded = self.fixture()
        excluded[:, :60] = True
        actual = contour.measure_contour(lightness, own, own, excluded)
        self.assertEqual(actual['perimeter_edges'], 160)
        self.assertEqual(actual['status'], 'NOT_TESTED')
        self.assertLess(actual['measurable_share'], .8)

    def test_no_reference_still_reports_zero_coverage_and_full_perimeter(self):
        lightness, own, excluded = self.fixture()
        excluded[:] = True
        actual = contour.measure_contour(lightness, own, own, excluded)
        self.assertEqual(actual['status'], 'NOT_TESTED')
        self.assertEqual(actual['perimeter_edges'], 160)
        self.assertEqual(actual['measurable_share'], 0)
        self.assertEqual(actual['passing_share'], 0)

    def test_empty_thin_and_clipped_geometry_do_not_pass(self):
        lightness, own, excluded = self.fixture()
        for area in (np.s_[0:5, 40:80], np.s_[40:41, 40:43], np.s_[0:0, 0:0]):
            mask = np.zeros_like(own)
            mask[area] = True
            self.assertEqual(contour.measure_contour(lightness, mask, mask, excluded)['status'],
                             'NOT_TESTED')

    def test_invalid_group_cannot_omit_own_geometry(self):
        lightness, own, excluded = self.fixture()
        with self.assertRaises(ValueError):
            contour.measure_contour(lightness, own, np.zeros_like(own), excluded)

    def test_clipped_group_cannot_supply_complete_global_reference(self):
        lightness, own, excluded = self.fixture()
        group = own.copy()
        group[30:70, 80:] = True
        actual = contour.measure_contour(lightness, own, group, excluded)
        self.assertEqual(actual['status'], 'NOT_TESTED')
        self.assertFalse(actual['group_outer_complete'])
        self.assertIsNone(actual['median_delta_l'])

    def test_blocked_preconditions_do_not_run_measurement(self):
        with tempfile.TemporaryDirectory() as td:
            folder = Path(td)
            manifest = folder/'capture-manifest.json'
            manifest.write_text(json.dumps({'images': {}}))
            (folder/'semantic-sidecar-manifest.json').write_text(json.dumps({
                'frame': {'instance_tokens': [{'stable_id': 'tree@0,0', 'type': 'tree', 'token': 1}]}}))
            with mock.patch.object(contour.sidecar, 'validate_case', return_value={
                'frozen_capture_preconditions': 'FAIL', 'semantic_sidecar_preconditions': 'FAIL'}), \
                 mock.patch.object(contour.sidecar, 'validate_sidecar_binding',
                                   return_value=(['original SHA mismatch'], {})), \
                 mock.patch.object(contour.sidecar, '_load_capture_images', return_value=({}, [])), \
                 mock.patch.object(contour, 'measure_instances') as measured:
                result = contour.validate(manifest, folder, 'f'*40)
            measured.assert_not_called()
            self.assertEqual(result['capture_preconditions'], 'FAIL')
            self.assertEqual(result['T1']['instances'][0]['status'], 'NOT_TESTED')

    def test_tree_group_includes_whole_token_not_only_crown(self):
        shape = (100, 120, 4)
        main = np.full(shape, 100, np.uint8)
        main[..., 3] = 255
        pair = np.zeros(shape, np.uint8)
        coverage = np.zeros_like(pair)
        own = np.zeros(shape[:2], bool)
        own[30:60, 35:60] = True
        own[60:70, 45:50] = True  # branches/root, part 255
        pair[own, 2] = 1
        pair[own, 3] = 255
        pair[30:60, 35:60, 3] = 7
        coverage[own, 0] = 255
        coverage[own, 3] = 255
        coverage[65:70, 45:50, 0] = 180  # uncertain alpha stays in the mask
        images = {'main': main, 'grid': np.zeros_like(main), 'exclusions': np.zeros_like(main)}
        records = [{'stable_id': 'tree@0,0', 'type': 'tree', 'token': 1}]
        capture = {'instances': [{'stable_id': 'tree@0,0', 'cell': [0, 0]}]}
        result = contour.measure_instances(capture, images, pair, coverage, records)
        row = result['instances'][0]
        self.assertEqual(row['visible_pixels'], int(own.sum()))
        self.assertEqual(row['uncertain_pixels_retained'], 25)
        self.assertEqual(row['perimeter_edges'], metrics.contour(np.full(shape[:2], 40.), own,
                                                               np.zeros(shape[:2], bool))['perimeter_edges'])


if __name__ == '__main__':
    unittest.main()
