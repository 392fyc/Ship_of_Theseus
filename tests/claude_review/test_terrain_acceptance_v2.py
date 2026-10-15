"""Approved U1/C9 checks on synthetic arrays; not runtime visual approval."""
from pathlib import Path
import unittest
from unittest import mock

import numpy as np

import terrain_contour_v2 as contour
import terrain_cvd_machado as cvd
import validate_terrain_acceptance_v2 as acceptance
import validate_terrain_contour_v1 as previous


class ApprovedRulesTests(unittest.TestCase):
    def fixture(self):
        own = np.zeros((100, 120), bool)
        own[30:70, 40:80] = True
        return np.where(own, 60., 25.), own, np.zeros_like(own)

    def test_singleton_preserves_previous_numeric_thresholds(self):
        lightness, own, excluded = self.fixture()
        for value in (60., 30.):
            lightness[own] = value
            old = previous.measure_contour(lightness, own, own, excluded)
            new = contour.measure(lightness, own, own, excluded)
            for key in ('status', 'median_delta_l', 'perimeter_edges', 'measurable_share', 'passing_share'):
                self.assertEqual(new[key], old[key], key)

    def test_known_group_seam_removed_but_no_outside_edge_removed(self):
        lightness, own, excluded = self.fixture()
        group = own.copy()
        group[30:70, 80:100] = True
        lightness[group] = 60
        measured = contour.measure(lightness, own, group, excluded)
        self.assertEqual(measured['full_instance_perimeter_edges'], 160)
        self.assertEqual(measured['perimeter_edges'], 120)
        self.assertEqual(measured['same_group_seam_edges_removed'], 40)
        self.assertEqual(measured['status'], 'PASS')
        self.assertEqual(measured['measurable_share'], 1)

    def test_unknown_occlusion_keeps_outside_edges_in_denominator(self):
        lightness, own, excluded = self.fixture()
        group = own.copy()
        group[30:70, 80:100] = True
        lightness[group] = 60
        excluded[:, :55] = True
        measured = contour.measure(lightness, own, group, excluded)
        self.assertEqual(measured['perimeter_edges'], 120)
        self.assertEqual(measured['status'], 'NOT_TESTED')
        self.assertLess(measured['measurable_share'], .8)

    def test_enclosed_member_is_not_a_pass(self):
        lightness, own, excluded = self.fixture()
        group = np.zeros_like(own)
        group[20:80, 30:90] = True
        measured = contour.measure(lightness, own, group, excluded)
        self.assertEqual(measured['perimeter_edges'], 0)
        self.assertEqual(measured['status'], 'NOT_TESTED')
        self.assertEqual(measured['reason_category'], 'no_exposed_group_boundary')

    def test_geometry_and_empty_reference_fail_closed(self):
        lightness, own, excluded = self.fixture()
        group = own.copy()
        group[30:70, 80:] = True
        self.assertEqual(contour.measure(lightness, own, group, excluded)['status'], 'NOT_TESTED')
        excluded[:] = True
        self.assertEqual(contour.measure(lightness, own, own, excluded)['measurable_share'], 0)
        own[:] = False
        own[40:41, 30:50] = True
        self.assertEqual(contour.measure(lightness, own, own, excluded)['reason_category'], 'no_interior_core')

    def test_t6_retains_its_own_global_ten_threshold(self):
        lightness, own, excluded = self.fixture()
        lightness[own] = 38
        self.assertEqual(contour.measure(lightness, own, own, excluded)['status'], 'FAIL')
        self.assertEqual(contour.measure(lightness, own, own, excluded, squint=True)['status'], 'PASS')

    def test_c9_counts_all_trees_and_eighty_percent(self):
        rows = [{'status': 'PASS'}]*9 + [{'status': 'FAIL'}]*2 + [{'status': 'NOT_TESTED'}]
        self.assertEqual(acceptance.c9_gate(rows)['status'], 'FAIL')
        rows[9] = {'status': 'PASS'}
        measured = acceptance.c9_gate(rows)
        self.assertEqual(measured['status'], 'PASS')
        self.assertEqual(measured['denominator_all_declared_trees'], 12)
        self.assertEqual(measured['not_tested'], 1)
        self.assertEqual(acceptance.c9_gate([])['status'], 'NOT_TESTED')

    def test_neutral_srgb_is_neutral_in_both_models(self):
        pixels = np.array([[0., 0., 0.], [128., 128., 128.], [255., 255., 255.]])
        for mode in cvd.MATRICES:
            np.testing.assert_allclose(cvd.simulate(pixels, mode), pixels, atol=.001)

    def test_matrix_operates_in_linear_not_encoded_rgb(self):
        red = np.array([[255, 0, 0]], np.uint8)
        original = red.copy()
        transformed = cvd.simulate(red, 'protanopia')[0]
        self.assertTrue(100 < transformed[0] < 120)
        self.assertTrue(90 < transformed[1] < 100)
        self.assertEqual(transformed[2], 0)
        self.assertEqual(transformed.dtype, np.float64)
        np.testing.assert_array_equal(red, original)
        with self.assertRaises(ValueError):
            cvd.simulate(np.array([[np.nan, 0, 0]]), 'protanopia')

    def test_failed_frozen_source_never_runs_new_measurements(self):
        old = {'capture_preconditions': 'FAIL', 'case': {'requested_resolution': [1280, 720]},
               'T1': {'instances': [{'stable_id': 'tree@0,0', 'type': 'tree'}]}}
        with mock.patch.object(acceptance.baseline, 'validate', return_value=old), \
             mock.patch.object(acceptance, 'measure') as measured:
            result = acceptance.validate(Path('not-read.json'), Path('.'), 'f'*40)
        measured.assert_not_called()
        self.assertEqual(result['measurements']['instances'][0]['T1']['status'], 'NOT_TESTED')
        self.assertFalse(result['measurements']['instances'][0]['T1_required_for_acceptance'])
        self.assertEqual(result['measurements']['C9_gate']['status'], 'NOT_TESTED')

    def test_c9_requires_both_modes_and_keeps_uncertain_crown_samples(self):
        h, w = 60, 80
        own = np.zeros((h, w), bool)
        own[20:40, 30:50] = True
        ground = np.full((h, w, 4), 40, np.uint8)
        ground[..., 3] = 255
        main = ground.copy()
        main[own, :3] = 220
        empty = np.zeros_like(main)
        ground_types = np.zeros_like(main)
        ground_types[..., :3] = [1, 1, 1]
        ground_types[..., 3] = 255
        pair, coverage = empty.copy(), empty.copy()
        pair[own, 2] = 1
        pair[own, 3] = 7
        pair[20:30, 30:50, 3] = 8
        coverage[own, 0] = 180
        coverage[own, 3] = 255
        images = {'main': main, 'ground': ground, 'ground_without_shadow': ground.copy(),
                  'ground_types': ground_types, 'exclusions': empty, 'grid': empty,
                  'contact_shadow': empty}
        records = [{'stable_id': 'tree@0,0', 'type': 'tree', 'token': 1}]
        capture = {'instances': [{'stable_id': 'tree@0,0', 'cell': [0, 0]}],
                   'masks': {'ground_types': {'classes': {'plain': {'color': '#010101', 'semantic': 'plain'}}}}}
        first = acceptance.measure_c9(capture, images, pair, coverage, records)[0]
        self.assertEqual(first['status'], 'PASS')
        self.assertEqual(first['crown_pixels'], 400)
        self.assertEqual(first['uncertain_crown_pixels_retained'], 400)
        original_simulate = cvd.simulate
        def one_mode_loses_contrast(rgb, mode):
            return np.full(rgb.shape, 128., np.float64) if mode == 'deuteranopia' else original_simulate(rgb, mode)
        with mock.patch.object(cvd, 'simulate', side_effect=one_mode_loses_contrast):
            second = acceptance.measure_c9(capture, images, pair, coverage, records)[0]
        self.assertEqual(second['modes']['protanopia']['status'], 'PASS')
        self.assertEqual(second['modes']['deuteranopia']['status'], 'FAIL')
        self.assertEqual(second['status'], 'FAIL')


if __name__ == '__main__':
    unittest.main()
