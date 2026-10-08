"""TERRAIN-READABILITY-01 离线测量；输入证据完整性由批次采集器负责。

不读写素材。PASS 只表示传入数组的该项数值满足阈值，不是批次或美术批准。
测量定义见 dev_doc/ui-art-research/terrain-readability/measurement.md。
"""
from __future__ import annotations

import math
import numpy as np
from PIL import Image, ImageFilter
from claude_review_checks import lab


def result(passed: bool, **values) -> dict:
    return {"status": "PASS" if passed else "FAIL", **values}


def missing(reason: str, **values) -> dict:
    return {"status": "NOT_TESTED", "reason": reason, **values}


def finite(*values) -> None:
    if any(not np.isfinite(value).all() for value in values):
        raise ValueError("测量输入包含非有限值")


def morph(mask: np.ndarray, radius: int, *, erode: bool = False) -> np.ndarray:
    """欧氏圆盘，图外为 False；不使用循环回卷边界。"""
    h, w = mask.shape
    padded = np.pad(mask, radius, constant_values=False)
    output = np.full(mask.shape, erode, dtype=bool)
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            if dx * dx + dy * dy > radius * radius:
                continue
            shifted = padded[radius + dy:radius + dy + h, radius + dx:radius + dx + w]
            if erode:
                output &= shifted
            else:
                output |= shifted
    return output


def rings(mask: np.ndarray, exclude: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    return mask & ~morph(mask, 2, erode=True), morph(mask, 4) & ~mask & ~exclude


def contour(lightness: np.ndarray, mask: np.ndarray, exclude: np.ndarray) -> dict:
    """T1。mask/exclude 为原图尺寸 bool 数组；被排除周长不计为已通过。"""
    if lightness.shape != mask.shape or mask.shape != exclude.shape:
        raise ValueError("图像与掩膜尺寸不一致")
    if mask.dtype != bool or exclude.dtype != bool or not np.isfinite(lightness).all():
        raise ValueError("掩膜必须为 bool，明度必须为有限值")
    if not mask.any():
        return missing("实例掩膜为空")
    if mask[:4].any() or mask[-4:].any() or mask[:, :4].any() or mask[:, -4:].any():
        return missing("实例靠近图边，完整外环不可观测")
    if not morph(mask, 2, erode=True).any():
        return missing("实例没有足够的 2 像素内核")
    inner, outer = rings(mask, exclude)
    if not inner.any() or not outer.any():
        return missing("内环或有效外环为空")
    gap = abs(float(np.median(lightness[inner]) - np.median(lightness[outer])))
    padded = np.pad(mask, 1)
    neighbours = (padded[:-2, 1:-1].astype(int) + padded[2:, 1:-1]
                  + padded[1:-1, :-2] + padded[1:-1, 2:])
    weights = np.where(mask, 4 - neighbours, 0)
    perimeter = int(weights.sum())
    covered = passing = 0
    yy, xx = np.mgrid[-4:5, -4:5]
    disk = xx * xx + yy * yy <= 16
    for y, x in np.argwhere(weights > 0):
        cut = np.s_[y-4:y+5, x-4:x+5]
        a, b = inner[cut] & disk, outer[cut] & disk
        if not a.any() or not b.any():
            continue
        weight = int(weights[y, x])
        covered += weight
        local_gap = abs(float(np.median(lightness[cut][a]) - np.median(lightness[cut][b])))
        if local_gap >= 10:
            passing += weight
    stats = dict(median_delta_l=gap, perimeter_edges=perimeter,
                 measurable_share=covered/perimeter, passing_share=passing/perimeter,
                 inner_pixels=int(inner.sum()), outer_pixels=int(outer.sum()))
    if covered/perimeter < .8:
        return missing("可测轮廓不足 80%", **stats)
    return result(gap >= 15 and passing/perimeter >= .8, **stats)


def planes(top: np.ndarray, side: np.ndarray, paving: np.ndarray) -> dict:
    """T2，三个参数为对应区域的 L* 像素值。"""
    finite(top, side, paving)
    if any(x.size == 0 for x in (top, side, paving)):
        return missing("顶面、侧面或铺地分类缺失")
    t, s, p = (float(np.median(x)) for x in (top, side, paving))
    return result(t >= p + 10 and s <= t - 8, top_l=t, side_l=s, paving_l=p)


def delta_e00(first: np.ndarray, second: np.ndarray) -> float:
    """Sharma/Wu/Dalal 2005 公式，kL=kC=kH=1；不复制其 MATLAB 代码。"""
    finite(first, second)
    l1, a1, b1 = map(float, first)
    l2, a2, b2 = map(float, second)
    cbar = (math.hypot(a1, b1) + math.hypot(a2, b2)) / 2
    g = .5 * (1 - math.sqrt(cbar**7 / (cbar**7 + 25**7)))
    a1, a2 = a1 * (1 + g), a2 * (1 + g)
    c1, c2 = math.hypot(a1, b1), math.hypot(a2, b2)
    h1 = math.degrees(math.atan2(b1, a1)) % 360 if c1 else 0
    h2 = math.degrees(math.atan2(b2, a2)) % 360 if c2 else 0
    dh = h2 - h1
    if c1 * c2 == 0:
        dh = 0
    elif dh > 180:
        dh -= 360
    elif dh < -180:
        dh += 360
    dl, dc = l2 - l1, c2 - c1
    dh_term = 2 * math.sqrt(c1 * c2) * math.sin(math.radians(dh/2))
    lm, cm = (l1 + l2)/2, (c1 + c2)/2
    hm = (h1 + h2)/2
    if c1 * c2 == 0:
        hm = h1 + h2
    elif abs(h1 - h2) > 180:
        hm += 180 if h1 + h2 < 360 else -180
    cos = lambda deg: math.cos(math.radians(deg))
    t = 1 - .17*cos(hm-30) + .24*cos(2*hm) + .32*cos(3*hm+6) - .20*cos(4*hm-63)
    sl = 1 + .015*(lm-50)**2 / math.sqrt(20+(lm-50)**2)
    sc, sh = 1 + .045*cm, 1 + .015*cm*t
    rt = -2*math.sqrt(cm**7/(cm**7+25**7))*math.sin(math.radians(60*math.exp(-((hm-275)/25)**2)))
    return math.sqrt((dl/sl)**2 + (dc/sc)**2 + (dh_term/sh)**2 + rt*(dc/sc)*(dh_term/sh))


def foliage_outline(lightness: np.ndarray, canopy_mask: np.ndarray,
                    outline_mask: np.ndarray, dark_side_mask: np.ndarray) -> dict:
    """T3 可选暗侧轮廓：最终树冠可见掩膜内的一像素边界，L*≤12。

    三个分类掩膜须来自采集器，不能由像素明暗反推。空 outline_mask 明确表示未画轮廓。
    """
    finite(lightness)
    if any(m.shape != lightness.shape or m.dtype != bool
           for m in (canopy_mask, outline_mask, dark_side_mask)):
        raise ValueError("轮廓分类掩膜必须为同尺寸 bool 数组")
    if not canopy_mask.any():
        return missing("树冠实例为空")
    if not outline_mask.any():
        return result(True, outline_pixels=0, outline_present=False)
    boundary = canopy_mask & ~morph(canopy_mask, 1, erode=True)
    wider = int((outline_mask & ~boundary).sum())
    wrong_side = int((outline_mask & ~dark_side_mask).sum())
    brightest = float(lightness[outline_mask].max())
    return result(wider == 0 and wrong_side == 0 and brightest <= 12,
                  outline_pixels=int(outline_mask.sum()), outline_present=True,
                  pixels_outside_one_pixel_boundary=wider,
                  pixels_outside_dark_side=wrong_side, maximum_outline_l=brightest)


def foliage(canopy_lab: np.ndarray, grass_lab: np.ndarray, *, outline_check: dict | None = None) -> dict:
    """T3，N×3 Lab 对比与 foliage_outline 的检查结果必须共同通过。"""
    finite(canopy_lab, grass_lab)
    if canopy_lab.ndim != 2 or grass_lab.ndim != 2 or canopy_lab.shape[1] != 3 or grass_lab.shape[1] != 3:
        raise ValueError("树冠和草地必须为 N×3 Lab 样本")
    if canopy_lab.size == 0 or grass_lab.size == 0:
        return missing("树冠或草地样本缺失")
    a, b = np.median(canopy_lab, axis=0), np.median(grass_lab, axis=0)
    dl, de = abs(float(a[0]-b[0])), delta_e00(a, b)
    contrast_pass = dl >= 12 or (dl >= 8 and de >= 15)
    values = dict(delta_l=dl, delta_e00=de, contrast_pass=contrast_pass, outline_check=outline_check)
    if outline_check is None or outline_check.get("status") == "NOT_TESTED":
        return missing("未完成暗侧轮廓检查", **values)
    if outline_check.get("status") not in ("PASS", "FAIL"):
        raise ValueError("不是 foliage_outline 的检查结果")
    return result(contrast_pass and outline_check["status"] == "PASS", **values)


def contact_shadow(shadow_l: np.ndarray, underlying_l: np.ndarray,
                   width: float, cell_width: float) -> dict:
    """T4，阴影和无阴影地面同像素逐点对照；宽度由采集掩膜测量。"""
    finite(shadow_l, underlying_l, width, cell_width)
    if shadow_l.shape != underlying_l.shape:
        raise ValueError("阴影与地面样本不对应")
    if not shadow_l.size or width <= 0 or cell_width <= 0:
        return missing("接触阴影或宽度证据缺失")
    darkness = float(np.median(underlying_l.astype(float) - shadow_l))
    return result(8 <= darkness <= 12 and width <= cell_width/2,
                  darkness_l=darkness, width_px=width, cell_width_px=cell_width)


def ground_stability(paving: np.ndarray, grass: np.ndarray,
                     baseline_paving: np.ndarray, baseline_grass: np.ndarray) -> dict:
    """T5 数值部分；调用方须保证当前/基线使用相同掩膜。"""
    finite(paving, grass, baseline_paving, baseline_grass)
    if paving.shape != baseline_paving.shape or grass.shape != baseline_grass.shape:
        raise ValueError("地面基线不是同一组样本")
    if not paving.size or not grass.size:
        return missing("地面基线样本缺失")
    iqr = lambda a: float(np.percentile(a, 75) - np.percentile(a, 25))
    pshift = float(paving.mean() - baseline_paving.mean())
    gshift = float(grass.mean() - baseline_grass.mean())
    spread, base_spread = iqr(paving), iqr(baseline_paving)
    return result(spread <= base_spread + 1e-9 and abs(pshift) <= 3 and abs(gshift) <= 3,
                  paving_iqr=spread, baseline_paving_iqr=base_spread,
                  paving_mean_shift=pshift, grass_mean_shift=gshift)


def squint(rgb: np.ndarray, mask: np.ndarray, exclude: np.ndarray) -> dict:
    """T6，只接受原始 720p RGB；Pillow GaussianBlur 的 radius 为标准差。"""
    if rgb.shape != (720, 1280, 3) or rgb.dtype != np.uint8:
        return missing("T6 需要原始 1280×720 RGB uint8 图像")
    lightness = lab(np.asarray(Image.fromarray(rgb).filter(ImageFilter.GaussianBlur(2))))[..., 0]
    check = contour(lightness, mask, exclude)
    if check["status"] == "NOT_TESTED":
        return check
    return result(check["median_delta_l"] >= 10,
                  median_delta_l=check["median_delta_l"], sigma_px=2)
