#!/usr/bin/env python3
"""从原 v3 RGB 颜色选区确定性派生 v3b；区域图只用于冻结区域统计。

从仓库根运行示例：
  python scripts/art/build_forest_tree_v3b.py --region-map <TASK112>/semantic_tree_region_map.png

脚本使用冻结的 claude_review_checks.lab 作 sRGB/D65 Lab 输入转换；反变换按相同 D65 矩阵实现。它只生成树图，不进行 Godot 导入或运行验收。
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE_REL = Path("assets/prototype/battlefield_courtyard/forest-tree-v3.png")
OUTPUT_REL = Path("assets/prototype/battlefield_courtyard/forest-tree-v3b.png")
EXPECTED_PARENT_SHA256 = "616f54a6816f026d0154c390460ea4b90fdf3ddcbc8b782dcf295feffbf0be52"
EXPECTED_LAB_HELPER_CANONICAL_SHA256 = "c2c387df4bf4212fdc80f386233ff4e0b66768417ef69730f62079bc44a0f14a"
ATLAS_REGION = (286, 33, 964, 950)  # x, y, width, height
R4_GAIN = np.array([1.088777, 1.281212, 0.602625], dtype=np.float64)
CANOPY_L_KNEE = 50.0
CANOPY_L_SLOPE = 0.45
CANOPY_C_KNEE = 45.0
CANOPY_C_SLOPE = 0.25
WOOD_L_PERCENTILES = (2.0, 50.0, 98.0)
WOOD_L_PERCENTILE_TARGETS = (26.0, 30.0, 31.5)
WOOD_L_SOFT_TAIL = 0.15
WOOD_C_MAX = 19.2
WOOD_H_RANGE = (63.0, 82.0)
WOOD_HUE_FADE_IN = (10.0, 24.0)
WOOD_HUE_FADE_OUT = (76.0, 92.0)
WOOD_RED_GREEN_FADE = (2.0, 15.0)
WOOD_LOW_CHROMA_HUE_CONFIDENCE = (2.0, 12.0)
WOOD_LOW_CHROMA_NEUTRAL_LIKELIHOOD = 0.7
WOOD_ALPHA_FADE = (4.0, 64.0)

# Exact sRGB/D65 XYZ matrix and reference white used by claude_review_checks.lab.
RGB_TO_XYZ = np.array([
    [0.4124564, 0.3575761, 0.1804375],
    [0.2126729, 0.7151522, 0.0721750],
    [0.0193339, 0.1191920, 0.9503041],
], dtype=np.float64)
XYZ_TO_RGB = np.linalg.inv(RGB_TO_XYZ)
WHITE = np.array([0.95047, 1.0, 1.08883], dtype=np.float64)
DELTA = 6.0 / 29.0


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def smoothstep(low: float, high: float, values: np.ndarray) -> np.ndarray:
    t = np.clip((values - low) / (high - low), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def smooth_percentile_lightness(values: np.ndarray, knots: np.ndarray,
                                targets: np.ndarray) -> np.ndarray:
    """Monotone cubic through percentile anchors with smooth, non-flat tails."""
    x0, x1, x2 = (float(x) for x in knots)
    y0, y1, y2 = (float(y) for y in targets)
    slope0 = (y1 - y0) / (x1 - x0)
    slope1 = (y2 - y1) / (x2 - x1)
    slope_mid = 2.0 * slope0 * slope1 / (slope0 + slope1)
    result = np.empty_like(values, dtype=np.float64)
    low = values < x0
    high = values > x2
    middle = ~(low | high)
    low_scale = WOOD_L_SOFT_TAIL / slope0
    high_scale = WOOD_L_SOFT_TAIL / slope1
    result[low] = y0 - WOOD_L_SOFT_TAIL * (1.0 - np.exp((values[low] - x0) / low_scale))
    result[high] = y2 + WOOD_L_SOFT_TAIL * (1.0 - np.exp(-(values[high] - x2) / high_scale))
    left = middle & (values <= x1)
    right = middle & (values > x1)
    for mask, xa, xb, ya, yb, ma, mb in (
        (left, x0, x1, y0, y1, slope0, slope_mid),
        (right, x1, x2, y1, y2, slope_mid, slope1),
    ):
        span = xb - xa
        t = np.clip((values[mask] - xa) / span, 0.0, 1.0)
        t2, t3 = t * t, t * t * t
        h00 = 2.0 * t3 - 3.0 * t2 + 1.0
        h10 = t3 - 2.0 * t2 + t
        h01 = -2.0 * t3 + 3.0 * t2
        h11 = t3 - t2
        result[mask] = h00 * ya + h10 * span * ma + h01 * yb + h11 * span * mb
    return result


def srgb_lab_function():
    helper = ROOT / "tests" / "claude_review" / "claude_review_checks.py"
    # Only this Python helper is canonicalized, because core.autocrlf may make
    # the local checkout CRLF while the reviewed Git blob is LF. Input images
    # and region-map evidence continue to use their exact original bytes.
    helper_bytes = helper.read_bytes().replace(b"\r\n", b"\n")
    helper_sha = sha256(helper_bytes)
    if helper_sha != EXPECTED_LAB_HELPER_CANONICAL_SHA256:
        raise SystemExit(f"冻结 Lab 转换辅助文件 canonical-LF SHA256 不符：{helper_sha}")
    sys.path.insert(0, str(helper.parent))
    from claude_review_checks import lab  # frozen project measurement conversion
    return lab


def lab_to_linear_rgb(lab: np.ndarray) -> np.ndarray:
    l_star, a_star, b_star = np.moveaxis(lab.astype(np.float64), -1, 0)
    fy = (l_star + 16.0) / 116.0
    fx = fy + a_star / 500.0
    fz = fy - b_star / 200.0
    f = np.stack([fx, fy, fz], axis=-1)
    xyz_ratio = np.where(f > DELTA, f ** 3, 3.0 * DELTA ** 2 * (f - 4.0 / 29.0))
    xyz = xyz_ratio * WHITE
    return xyz @ XYZ_TO_RGB.T


def lab_to_srgb(lab: np.ndarray) -> tuple[np.ndarray, int, float]:
    """Keep Lab hue/lightness and reduce chroma only for out-of-gamut colors."""
    target = lab.astype(np.float64, copy=True)
    linear = lab_to_linear_rgb(target)
    out = np.any((linear < -1e-10) | (linear > 1.0 + 1e-10), axis=-1)
    count = int(out.sum())
    max_c_reduction = 0.0
    if count:
        l_star = target[..., 0][out]
        a_star = target[..., 1][out]
        b_star = target[..., 2][out]
        chroma = np.hypot(a_star, b_star)
        hue = np.arctan2(b_star, a_star)
        low = np.zeros_like(chroma)
        high = chroma.copy()
        for _ in range(24):
            mid = (low + high) * 0.5
            probe = np.stack([l_star, mid * np.cos(hue), mid * np.sin(hue)], axis=-1)
            probe_linear = lab_to_linear_rgb(probe)
            valid = np.all((probe_linear >= -1e-10) & (probe_linear <= 1.0 + 1e-10), axis=-1)
            low = np.where(valid, mid, low)
            high = np.where(valid, high, mid)
        max_c_reduction = float(np.max(chroma - low))
        target[..., 1][out] = low * np.cos(hue)
        target[..., 2][out] = low * np.sin(hue)
        linear = lab_to_linear_rgb(target)
    if np.any((linear < -1e-8) | (linear > 1.0 + 1e-8)):
        raise ValueError("色域映射后仍存在超出 sRGB 色域的颜色")
    linear = np.clip(linear, 0.0, 1.0)
    srgb = np.where(
        linear <= 0.0031308,
        12.92 * linear,
        1.055 * np.power(np.maximum(linear, 0.0), 1.0 / 2.4) - 0.055,
    )
    return np.rint(srgb * 255.0).astype(np.uint8), count, max_c_reduction


def summarize(lab: np.ndarray) -> dict:
    l_star = lab[..., 0]
    chroma = np.hypot(lab[..., 1], lab[..., 2])
    hue = (np.degrees(np.arctan2(lab[..., 2], lab[..., 1])) + 360.0) % 360.0
    return {
        "pixels": int(l_star.size),
        "L_min": float(np.min(l_star)),
        "L_percentiles_5_50_95_max": [float(x) for x in np.percentile(l_star, [5, 50, 95, 100])],
        "C_min": float(np.min(chroma)),
        "C_percentiles_50_95_max": [float(x) for x in np.percentile(chroma, [50, 95, 100])],
        "hue_min_max": [float(np.min(hue)), float(np.max(hue))],
        "hue_percentiles_5_50_95": [float(x) for x in np.percentile(hue, [5, 50, 95])],
        "L_gt_55_and_C_gt_50_share": float(np.mean((l_star > 55.0) & (chroma > 50.0))),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--region-map", type=Path, required=True,
                        help="TASK112 semantic_tree_region_map.png，964x950 RGBA")
    parser.add_argument("--source", type=Path, default=ROOT / SOURCE_REL)
    parser.add_argument("--output", type=Path, default=ROOT / OUTPUT_REL)
    parser.add_argument("--replace", action="store_true",
                        help="允许覆盖现有派生输出")
    args = parser.parse_args()

    source_bytes = args.source.read_bytes()
    source_sha = sha256(source_bytes)
    if source_sha != EXPECTED_PARENT_SHA256:
        raise SystemExit(f"父图 SHA256 不符：{source_sha}")
    source = np.asarray(Image.open(args.source).convert("RGBA"))
    region_map = np.asarray(Image.open(args.region_map).convert("RGBA"))
    x, y, width, height = ATLAS_REGION
    if source.shape != (1024, 1536, 4):
        raise SystemExit(f"父图尺寸不符：{source.shape[1]}x{source.shape[0]}")
    if region_map.shape != (height, width, 4):
        raise SystemExit(f"语义图尺寸不符：{region_map.shape[1]}x{region_map.shape[0]}")
    if args.output.exists() and not args.replace:
        raise SystemExit("派生输出已存在；确认替换后添加 --replace")

    map_codes = region_map[..., 0]
    map_alpha = region_map[..., 3]
    if not set(np.unique(map_codes).tolist()).issubset({0, 7, 8}):
        raise SystemExit("语义图红通道只能包含未分类 0、树冠 7、暗侧 8")
    if not set(np.unique(map_alpha).tolist()).issubset({0, 255}):
        raise SystemExit("语义图 alpha 必须是二值区域覆盖")
    if np.any((map_codes != 0) != (map_alpha != 0)):
        raise SystemExit("语义图类别码与 alpha 覆盖不一致")

    original = source[y:y + height, x:x + width]
    visible = original[..., 3] >= 4
    canopy = visible & (map_codes == 7)
    dark_side = visible & (map_codes == 8)
    crown_mask = canopy | dark_side
    if not canopy.any() or not dark_side.any():
        raise SystemExit("审查树冠或暗侧区域为空")

    lab_fn = srgb_lab_function()
    original_rgb = original[..., :3]
    original_float = original_rgb.astype(np.float64)
    source_lab = lab_fn(original_rgb.reshape(-1, 3)).reshape(height, width, 3)
    source_chroma = np.hypot(source_lab[..., 1], source_lab[..., 2])
    source_hue = (np.degrees(np.arctan2(source_lab[..., 2], source_lab[..., 1])) + 360.0) % 360.0
    red_over_green = original_float[..., 0] - original_float[..., 1]
    red_green_score = smoothstep(*WOOD_RED_GREEN_FADE, red_over_green)
    warm_hue_score = (
        smoothstep(*WOOD_HUE_FADE_IN, source_hue)
        * (1.0 - smoothstep(*WOOD_HUE_FADE_OUT, source_hue))
    )
    hue_confidence = smoothstep(*WOOD_LOW_CHROMA_HUE_CONFIDENCE, source_chroma)
    # Neutral/low-chroma pixels are not rejected solely because hue is noisy;
    # the independent original-R-minus-G score still has to support wood.
    hue_likelihood = (
        hue_confidence * warm_hue_score
        + (1.0 - hue_confidence) * WOOD_LOW_CHROMA_NEUTRAL_LIKELIHOOD
    )
    alpha_score = smoothstep(*WOOD_ALPHA_FADE, original[..., 3].astype(np.float64))
    wood_weight = red_green_score * hue_likelihood * alpha_score
    wood_weight *= visible
    wood_candidates = visible & (wood_weight >= 0.10)
    wood_core = visible & (wood_weight >= 0.85) & (original[..., 3] >= 128)
    if int(wood_core.sum()) < 100:
        raise SystemExit("原始颜色选区中的高置信木质样本过少")

    tinted = np.rint(np.clip(original_float * R4_GAIN, 0.0, 255.0)).astype(np.uint8)
    tinted_lab = lab_fn(tinted.reshape(-1, 3)).reshape(height, width, 3)
    output = source.copy()
    changed_rgb = np.zeros(visible.shape, dtype=bool)
    gamut_pixels = {"foliage_base": 0, "wood_blend": 0}
    max_gamut_c_reduction = {"foliage_base": 0.0, "wood_blend": 0.0}

    # Apply the foliage soft knee to visible atlas pixels, including code-0
    # leaf edges. Semantic codes remain measurement labels, not material masks.
    base_lab = tinted_lab.copy()
    base_l = base_lab[..., 0].copy()
    base_lab[..., 0] = np.where(base_l > CANOPY_L_KNEE,
                                CANOPY_L_KNEE + (base_l - CANOPY_L_KNEE) * CANOPY_L_SLOPE,
                                base_l)
    base_c = np.hypot(base_lab[..., 1], base_lab[..., 2])
    compressed_c = np.where(base_c > CANOPY_C_KNEE,
                            CANOPY_C_KNEE + (base_c - CANOPY_C_KNEE) * CANOPY_C_SLOPE,
                            base_c)
    scale = np.divide(compressed_c, base_c, out=np.ones_like(compressed_c), where=base_c > 0.0)
    base_lab[..., 1] *= scale
    base_lab[..., 2] *= scale
    base_rgb, gamut_pixels["foliage_base"], max_gamut_c_reduction["foliage_base"] = lab_to_srgb(base_lab[visible])
    crop = output[y:y + height, x:x + width]
    crop[..., :3][visible] = base_rgb

    wood_l_percentiles = np.percentile(tinted_lab[..., 0][wood_core], WOOD_L_PERCENTILES)
    wood_l_low, wood_l_mid, wood_l_high = (float(x) for x in wood_l_percentiles)
    if min(wood_l_mid - wood_l_low, wood_l_high - wood_l_mid) < 1e-6:
        raise SystemExit("木质样本的 L* 分布过窄，不能进行平滑映射")
    source_l = tinted_lab[..., 0]
    mapped_l = smooth_percentile_lightness(
        source_l,
        np.asarray([wood_l_low, wood_l_mid, wood_l_high], dtype=np.float64),
        np.asarray(WOOD_L_PERCENTILE_TARGETS, dtype=np.float64),
    )
    tinted_c = np.hypot(tinted_lab[..., 1], tinted_lab[..., 2])
    wood_c = np.minimum(tinted_c, WOOD_C_MAX)
    wood_hue = np.clip(source_hue, *WOOD_H_RANGE)
    wood_target_lab = np.stack([
        mapped_l,
        wood_c * np.cos(np.radians(wood_hue)),
        wood_c * np.sin(np.radians(wood_hue)),
    ], axis=-1)
    wood_mask = wood_candidates
    # Re-map the continuous color/alpha score smoothly so high-confidence
    # trunk pixels reach the wood target while uncertain leaf edges stay soft.
    wood_blend_weight = smoothstep(0.05, 0.85, wood_weight)
    blend_weight = wood_blend_weight[wood_mask, None]
    blended_lab = base_lab[wood_mask] * (1.0 - blend_weight) + wood_target_lab[wood_mask] * blend_weight
    wood_rgb, gamut_pixels["wood_blend"], max_gamut_c_reduction["wood_blend"] = lab_to_srgb(blended_lab)
    crop[..., :3][wood_mask] = wood_rgb
    changed_rgb[visible] = np.any(crop[..., :3][visible] != original_rgb[visible], axis=1)

    if not np.array_equal(source[..., 3], output[..., 3]):
        raise SystemExit("内部错误：alpha 发生改变")
    output_buffer = io.BytesIO()
    Image.fromarray(output, mode="RGBA").save(output_buffer, format="PNG", optimize=False, compress_level=9)
    output_bytes = output_buffer.getvalue()
    reread = np.asarray(Image.open(io.BytesIO(output_bytes)).convert("RGBA"))
    if not np.array_equal(source[..., 3], reread[..., 3]):
        raise SystemExit("PNG 回读后 alpha 与父图不一致")

    outside_atlas = np.ones(source.shape[:2], dtype=bool)
    outside_atlas[y:y + height, x:x + width] = False
    if not np.array_equal(source[outside_atlas], reread[outside_atlas]):
        raise SystemExit("atlas 区域外像素发生变化")
    if not np.array_equal(source[..., :3][source[..., 3] < 4], reread[..., :3][source[..., 3] < 4]):
        raise SystemExit("alpha < 4 的 RGB 像素发生变化")

    canopy_out = lab_fn(reread[y:y + height, x:x + width, :3][canopy])
    dark_side_out = lab_fn(reread[y:y + height, x:x + width, :3][dark_side])
    crown_union_out = lab_fn(reread[y:y + height, x:x + width, :3][crown_mask])
    wood_final_core_mask = wood_core
    wood_out = lab_fn(reread[y:y + height, x:x + width, :3][wood_final_core_mask])
    canopy_summary = summarize(canopy_out)
    dark_side_summary = summarize(dark_side_out)
    crown_union_summary = summarize(crown_union_out)
    wood_summary = summarize(wood_out)
    wood_chroma_out = np.hypot(wood_out[:, 1], wood_out[:, 2])
    wood_hue_defined = wood_chroma_out > 2.0
    wood_hue_out = (np.degrees(np.arctan2(wood_out[:, 2], wood_out[:, 1])) + 360.0) % 360.0
    if np.any(wood_hue_defined):
        wood_hue_summary = {
            "pixels": int(wood_hue_defined.sum()),
            "hue_min_max": [float(np.min(wood_hue_out[wood_hue_defined])),
                            float(np.max(wood_hue_out[wood_hue_defined]))],
            "hue_percentiles_5_50_95": [float(x) for x in np.percentile(wood_hue_out[wood_hue_defined], [5, 50, 95])],
        }
    else:
        wood_hue_summary = {"pixels": 0, "hue_min_max": None, "hue_percentiles_5_50_95": None}
    wood_hue_undefined_count = int((~wood_hue_defined).sum())
    # Keep undefined low-chroma hue out of the hue report and guard. L/C guards
    # still apply to every high-confidence wood-core pixel.
    wood_summary.pop("hue_min_max")
    wood_summary.pop("hue_percentiles_5_50_95")
    canopy_l = canopy_summary["L_percentiles_5_50_95_max"]
    canopy_c = canopy_summary["C_percentiles_50_95_max"]
    if not (canopy_l[2] <= 60.0 and canopy_l[3] <= 72.0 and canopy_c[1] <= 52.0
            and canopy_summary["L_gt_55_and_C_gt_50_share"] <= 0.08 and canopy_l[1] >= 33.0):
        raise SystemExit("树冠输出没有满足 R5 冠部目标")
    if dark_side_summary["L_percentiles_5_50_95_max"][1] >= canopy_l[1]:
        raise SystemExit("树冠暗侧中位明度未低于树冠中位明度")
    if not (wood_summary["L_min"] >= 20.0 and wood_summary["L_percentiles_5_50_95_max"][3] <= 32.0
            and wood_summary["C_percentiles_50_95_max"][2] <= 20.0
            and wood_hue_summary["pixels"] > 0
            and wood_hue_summary["hue_min_max"][0] >= 60.0
            and wood_hue_summary["hue_min_max"][1] <= 85.0):
        raise SystemExit("高置信枝干/根选区输出超出 R5 木质目标：" + json.dumps({
            "wood_L_C": wood_summary,
            "defined_hue_C_gt_2": wood_hue_summary,
            "undefined_hue_C_le_2_count": wood_hue_undefined_count,
        }, ensure_ascii=False))
    output_bytes_path = args.output
    output_bytes_path.parent.mkdir(parents=True, exist_ok=True)
    output_bytes_path.write_bytes(output_bytes)
    report = {
        "schema": "sot-tree-r5-derivation-run/1",
        "parent_sha256": source_sha,
        "region_map_sha256": sha256(args.region_map.read_bytes()),
        "region_map_size": [width, height],
        "atlas_region": list(ATLAS_REGION),
        "lab_helper_canonical_lf_sha256": EXPECTED_LAB_HELPER_CANONICAL_SHA256,
        "r4_gain_baked_in_srgb_channel_space": [float(x) for x in R4_GAIN],
        "foliage_curve": {"L_if_gt_50": f"50 + (L - 50) * {CANOPY_L_SLOPE:g}", "C_if_gt_45": f"45 + (C - 45) * {CANOPY_C_SLOPE:g}", "applied_to": "all visible atlas pixels so unclassified leaf edges remain foliage"},
        "wood_color_selection": {"rgb_source": "original v3 before R4 gain", "red_minus_green_fade": list(WOOD_RED_GREEN_FADE), "warm_hue_fade_in": list(WOOD_HUE_FADE_IN), "warm_hue_fade_out": list(WOOD_HUE_FADE_OUT), "low_chroma_hue_confidence_ramp": list(WOOD_LOW_CHROMA_HUE_CONFIDENCE), "low_chroma_neutral_likelihood": WOOD_LOW_CHROMA_NEUTRAL_LIKELIHOOD, "alpha_weight_fade": list(WOOD_ALPHA_FADE), "semantic_region_map_used_as_material_classifier": False},
        "wood_curve": {"hue_target": list(WOOD_H_RANGE), "chroma_max_before_rounding": WOOD_C_MAX, "lightness_percentiles_of_high_confidence_core": list(WOOD_L_PERCENTILES), "lightness_quantiles_source": [wood_l_low, wood_l_mid, wood_l_high], "lightness_target_at_quantiles": list(WOOD_L_PERCENTILE_TARGETS), "lightness_mapping": "monotone cubic Hermite through percentile anchors with exponential soft tails; no hard clamp", "tail_asymptote_offset": WOOD_L_SOFT_TAIL, "blend_weight_remap": "smoothstep(0.05, 0.85, wood_weight)"},
        "classification_codes_for_reporting_only": {"canopy": 7, "dark_side": 8, "not_used_for_wood_selection": 0},
        "region_pixel_counts": {"canopy": int(canopy.sum()), "dark_side": int(dark_side.sum()), "wood_candidates_weight_ge_0_10": int(wood_candidates.sum()), "wood_core_weight_ge_0_85_alpha_ge_128": int(wood_core.sum()), "wood_weighted_by_reporting_code": {str(code): int((wood_candidates & (map_codes == code)).sum()) for code in (0, 7, 8)}, "visible_alpha_ge_4_total": int(visible.sum()), "alpha_lt_4_unchanged": int((original[..., 3] < 4).sum())},
        "gamut_fit": {"pixels_by_region": gamut_pixels, "maximum_C_reduction_by_region": max_gamut_c_reduction},
        "canopy_after": canopy_summary,
        "dark_side_after": dark_side_summary,
        "crown_union_after": crown_union_summary,
        "wood_after": wood_summary,
        "wood_hue_defined_C_gt_2": wood_hue_summary,
        "wood_hue_undefined_C_le_2_count": wood_hue_undefined_count,
        "alpha_pixelwise_equal": bool(np.array_equal(source[..., 3], reread[..., 3])),
        "alpha_sha256_parent": sha256(source[..., 3].tobytes()),
        "alpha_sha256_output": sha256(reread[..., 3].tobytes()),
        "changed_rgb_pixels_in_atlas_region": int(changed_rgb.sum()),
        "output_sha256": sha256(output_bytes),
        "output_bytes": len(output_bytes),
    }
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())




