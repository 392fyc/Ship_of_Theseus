"""只校准测量，不生成或修改游戏素材；真实六组合批次仍须 Dot。"""
import unittest
import numpy as np
from terrain_readability_metrics import (
    lab, morph, rings, contour, planes, delta_e00, foliage, foliage_outline,
    contact_shadow, ground_stability, squint,
)


class TerrainMetricsTests(unittest.TestCase):
    def fixture(self):
        mask = np.zeros((80, 100), dtype=bool)
        mask[20:60, 30:70] = True
        lightness = np.where(mask, 60., 25.)
        return lightness, mask, np.zeros_like(mask)

    def test_lab_known_endpoints(self):
        converted = lab(np.array([[0, 0, 0], [255, 255, 255]], dtype=np.uint8))
        np.testing.assert_allclose(converted[:, 0], [0, 100], atol=.001)

    def test_contour_positive_and_camouflage_negative(self):
        lightness, mask, excluded = self.fixture()
        measured = contour(lightness, mask, excluded)
        self.assertEqual(measured['status'], 'PASS')
        self.assertEqual(measured['median_delta_l'], 35)
        self.assertEqual(measured['passing_share'], 1)
        lightness[mask] = 30
        self.assertEqual(contour(lightness, mask, excluded)['status'], 'FAIL')

    def test_global_median_does_not_hide_bad_perimeter(self):
        lightness, mask, excluded = self.fixture()
        lightness[20:40, 30:70] = 25
        measured = contour(lightness, mask, excluded)
        self.assertGreaterEqual(measured['median_delta_l'], 15)
        self.assertLess(measured['passing_share'], .8)
        self.assertEqual(measured['status'], 'FAIL')

    def test_excluded_edges_do_not_disappear_from_denominator(self):
        lightness, mask, excluded = self.fixture()
        excluded[:, :50] = True
        measured = contour(lightness, mask, excluded)
        self.assertEqual(measured['status'], 'NOT_TESTED')
        self.assertLess(measured['measurable_share'], .8)

    def test_tiny_clipped_and_empty_masks_are_not_passes(self):
        lightness, mask, excluded = self.fixture()
        for area in [np.s_[20:21, 30:33], np.s_[0:8, 30:40], np.s_[0:0, 0:0]]:
            mask[:] = False
            mask[area] = True
            self.assertEqual(contour(lightness, mask, excluded)['status'], 'NOT_TESTED')
        mask[:] = False
        mask[30:50, 30:50] = True
        excluded[:] = True
        self.assertEqual(contour(lightness, mask, excluded)['status'], 'NOT_TESTED')

    def test_disk_is_not_square_and_edges_do_not_wrap(self):
        mask = np.zeros((15, 15), dtype=bool)
        mask[7, 7] = True
        self.assertEqual(int(morph(mask, 2).sum()), 13)
        self.assertFalse(morph(mask, 2)[5, 5])
        mask[:] = False
        mask[0, 0] = True
        self.assertFalse(morph(mask, 2)[-1, -1])

    def test_walls_must_have_lit_top(self):
        a = lambda v: np.array([v, v])
        self.assertEqual(planes(a(40), a(30), a(28))['status'], 'PASS')
        self.assertEqual(planes(a(14.6), a(15.5), a(27.4))['status'], 'FAIL')
        self.assertEqual(planes(a(40), a(36), a(28))['status'], 'FAIL')
        self.assertEqual(planes(np.array([]), a(30), a(28))['status'], 'NOT_TESTED')

    def test_ciede2000_published_reference_cases(self):
        # Sharma/Wu/Dalal 作者补充数据第 1、7、10、11 行：含零彩度与色相分支。
        rows = [([50, 2.6772, -79.7751], [50, 0, -82.7485], 2.0425),
                ([50, 0, 0], [50, -1, 2], 2.3669),
                ([50, 2.49, -.001], [50, -2.49, .001], 7.1792),
                ([50, 2.49, -.001], [50, -2.49, .0011], 7.2195)]
        for a, b, expected in rows:
            self.assertAlmostEqual(delta_e00(a, b), expected, delta=.0001)
            self.assertAlmostEqual(delta_e00(b, a), expected, delta=.0001)

    def test_foliage_alternatives_require_lightness_floor(self):
        grass = np.array([[30., -10, 15]])
        lightness, mask, empty = self.fixture()
        outline_check = foliage_outline(lightness, mask, empty, empty)
        for canopy, expected in [([42, -10, 15], 'PASS'), ([38, 35, -20], 'PASS'),
                                 ([37, 35, -20], 'FAIL'), ([38, -10, 15], 'FAIL')]:
            self.assertEqual(foliage(np.array([canopy]), grass, outline_check=outline_check)['status'], expected)

    def test_foliage_outline_width_lightness_and_side(self):
        lightness, mask, outline = self.fixture()
        dark_side = np.zeros_like(mask)
        dark_side[:, :50] = True
        outline[20:60, 30] = True
        lightness[outline] = 12
        valid = foliage_outline(lightness, mask, outline, dark_side)
        self.assertEqual(valid['status'], 'PASS')
        canopy, grass = np.array([[50., 0, 0]]), np.array([[30., 0, 0]])
        self.assertEqual(foliage(canopy, grass, outline_check=valid)['status'], 'PASS')
        self.assertEqual(foliage(canopy, grass)['status'], 'NOT_TESTED')
        lightness[outline] = 13
        bright = foliage_outline(lightness, mask, outline, dark_side)
        self.assertEqual(bright['status'], 'FAIL')
        self.assertEqual(foliage(canopy, grass, outline_check=bright)['status'], 'FAIL')
        lightness[outline] = 10
        outline[20:60, 31] = True
        lightness[outline] = 10
        self.assertEqual(foliage_outline(lightness, mask, outline, dark_side)['status'], 'FAIL')
        outline[:] = False
        outline[20:60, 69] = True
        lightness[outline] = 10
        self.assertEqual(foliage_outline(lightness, mask, outline, dark_side)['status'], 'FAIL')

    def test_shadow_uses_same_pixel_subtraction_and_width(self):
        underlying = np.array([10., 40, 60])
        self.assertEqual(contact_shadow(underlying-10, underlying, 12, 30)['status'], 'PASS')
        self.assertEqual(contact_shadow(underlying-14, underlying, 12, 30)['status'], 'FAIL')
        self.assertEqual(contact_shadow(underlying-10, underlying, 18, 30)['status'], 'FAIL')

    def test_ground_change_cannot_buy_object_readability(self):
        a = np.array([10., 20, 30, 40])
        self.assertEqual(ground_stability(a+2, a+2, a, a)['status'], 'PASS')
        self.assertEqual(ground_stability(a+4, a, a, a)['status'], 'FAIL')
        self.assertEqual(ground_stability(a*1.1, a, a, a)['status'], 'FAIL')

    def test_nonfinite_samples_cannot_pass(self):
        with self.assertRaises(ValueError):
            planes(np.array([np.inf]), np.array([30]), np.array([20]))
        with self.assertRaises(ValueError):
            ground_stability(np.array([np.nan]), np.array([20]), np.array([20]), np.array([20]))

    def test_squint_native_size_and_contrast(self):
        rgb = np.full((720, 1280, 3), 40, dtype=np.uint8)
        mask = np.zeros((720, 1280), dtype=bool)
        mask[200:300, 500:600] = True
        rgb[mask] = 220
        excluded = np.zeros_like(mask)
        self.assertEqual(squint(rgb, mask, excluded)['status'], 'PASS')
        rgb[mask] = 45
        self.assertEqual(squint(rgb, mask, excluded)['status'], 'FAIL')
        self.assertEqual(squint(rgb[:100], mask[:100], excluded[:100])['status'], 'NOT_TESTED')


if __name__ == '__main__':
    unittest.main()
