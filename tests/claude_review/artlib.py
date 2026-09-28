"""SoT 美术审核脚本的公共函数（numpy + Pillow）。

运行方式统一为：
    uv run --no-project --python 3.13 --with numpy --with pillow python <脚本> ...
所有函数只读取输入文件，不修改任何源文件。
"""
from __future__ import annotations

import hashlib
from pathlib import Path

import numpy as np
from PIL import Image

# ---------------------------------------------------------------- 文件与载入


def sha256_file(path: str | Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_rgba(path: str | Path) -> tuple[np.ndarray, dict]:
    """返回 HxWx4 uint8 数组与原始格式信息（原始 mode 用于判断是否真有 alpha）。"""
    im = Image.open(path)
    info = {
        "mode": im.mode,
        "size": [im.width, im.height],
        "format": im.format,
        "has_alpha_channel": im.mode in ("RGBA", "LA", "PA") or "transparency" in im.info,
    }
    rgba = np.asarray(im.convert("RGBA"), dtype=np.uint8)
    return rgba, info


# ---------------------------------------------------------------- 色彩空间


def srgb_to_lab(rgb: np.ndarray) -> np.ndarray:
    """sRGB(0-255) → CIE Lab（D65）。输入形状 (...,3)。"""
    c = rgb.astype(np.float64) / 255.0
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    m = np.array(
        [
            [0.4124564, 0.3575761, 0.1804375],
            [0.2126729, 0.7151522, 0.0721750],
            [0.0193339, 0.1191920, 0.9503041],
        ]
    )
    xyz = lin @ m.T
    t = xyz / np.array([0.95047, 1.0, 1.08883])
    eps, kappa = 216 / 24389, 24389 / 27
    f = np.where(t > eps, np.cbrt(t), (kappa * t + 16) / 116)
    lab_l = 116 * f[..., 1] - 16
    lab_a = 500 * (f[..., 0] - f[..., 1])
    lab_b = 200 * (f[..., 1] - f[..., 2])
    return np.stack([lab_l, lab_a, lab_b], axis=-1)


def ciede2000(lab1: np.ndarray, lab2: np.ndarray) -> np.ndarray:
    """向量化 CIEDE2000 色差，输入可广播的 (...,3) Lab 数组。"""
    l1, a1, b1 = lab1[..., 0], lab1[..., 1], lab1[..., 2]
    l2, a2, b2 = lab2[..., 0], lab2[..., 1], lab2[..., 2]
    c1 = np.hypot(a1, b1)
    c2 = np.hypot(a2, b2)
    cbar = (c1 + c2) / 2
    g = 0.5 * (1 - np.sqrt(cbar**7 / (cbar**7 + 25.0**7)))
    a1p = (1 + g) * a1
    a2p = (1 + g) * a2
    c1p = np.hypot(a1p, b1)
    c2p = np.hypot(a2p, b2)
    h1p = np.degrees(np.arctan2(b1, a1p)) % 360
    h2p = np.degrees(np.arctan2(b2, a2p)) % 360
    zero_c = (c1p * c2p) == 0
    dlp = l2 - l1
    dcp = c2p - c1p
    dhp = h2p - h1p
    dhp = np.where(dhp > 180, dhp - 360, dhp)
    dhp = np.where(dhp < -180, dhp + 360, dhp)
    dhp = np.where(zero_c, 0, dhp)
    dhp_big = 2 * np.sqrt(c1p * c2p) * np.sin(np.radians(dhp / 2))
    lbarp = (l1 + l2) / 2
    cbarp = (c1p + c2p) / 2
    hsum = h1p + h2p
    hbarp = np.where(
        np.abs(h1p - h2p) <= 180,
        hsum / 2,
        np.where(hsum < 360, (hsum + 360) / 2, (hsum - 360) / 2),
    )
    hbarp = np.where(zero_c, hsum, hbarp)
    t = (
        1
        - 0.17 * np.cos(np.radians(hbarp - 30))
        + 0.24 * np.cos(np.radians(2 * hbarp))
        + 0.32 * np.cos(np.radians(3 * hbarp + 6))
        - 0.20 * np.cos(np.radians(4 * hbarp - 63))
    )
    dtheta = 30 * np.exp(-(((hbarp - 275) / 25) ** 2))
    rc = 2 * np.sqrt(cbarp**7 / (cbarp**7 + 25.0**7))
    sl = 1 + (0.015 * (lbarp - 50) ** 2) / np.sqrt(20 + (lbarp - 50) ** 2)
    sc = 1 + 0.045 * cbarp
    sh = 1 + 0.015 * cbarp * t
    rt = -np.sin(np.radians(2 * dtheta)) * rc
    return np.sqrt(
        (dlp / sl) ** 2 + (dcp / sc) ** 2 + (dhp_big / sh) ** 2 + rt * (dcp / sc) * (dhp_big / sh)
    )


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    v = value.strip().lstrip("#")
    return int(v[0:2], 16), int(v[2:4], 16), int(v[4:6], 16)


def rgb_to_hex(rgb) -> str:
    return "#{:02X}{:02X}{:02X}".format(*[int(x) for x in rgb])


# ---------------------------------------------------------------- 邻域工具


def neighbor_any(mask: np.ndarray) -> np.ndarray:
    """4 邻域中任一像素为 True 时为 True（不含自身）。"""
    out = np.zeros_like(mask)
    out[1:, :] |= mask[:-1, :]
    out[:-1, :] |= mask[1:, :]
    out[:, 1:] |= mask[:, :-1]
    out[:, :-1] |= mask[:, 1:]
    return out


# ---------------------------------------------------------------- 透明通道


def alpha_profile(rgba: np.ndarray) -> dict:
    a = rgba[..., 3]
    total = a.size
    zero = int((a == 0).sum())
    full = int((a == 255).sum())
    semi = total - zero - full
    visible = total - zero
    return {
        "transparent_ratio": round(zero / total, 4),
        "opaque_ratio": round(full / total, 4),
        "semi_ratio_of_visible": round(semi / visible, 4) if visible else 0.0,
        "binary_alpha": semi == 0,
        "fully_opaque": zero == 0 and semi == 0,
    }


def hidden_rgb_profile(rgba: np.ndarray, lab: np.ndarray) -> dict:
    """统计 alpha=0 区域残留的 RGB。浅色残留在 Linear 过滤、mipmap 或忽略 alpha 的工具中会显形。"""
    t = rgba[..., 3] == 0
    n = int(t.sum())
    if n == 0:
        return {"transparent_pixels": 0}
    l_star = lab[..., 0][t]
    light = float((l_star > 70).mean())
    return {
        "transparent_pixels": n,
        "light_rgb_share": round(light, 4),
        "mean_rgb": [int(x) for x in rgba[..., :3][t].mean(axis=0)],
        "checker_like": bool(checker_pattern(rgba[..., :3], t)["suspect"]),
    }


def edge_fringe(rgba: np.ndarray, lab: np.ndarray) -> dict:
    """比较贴近透明区的外圈像素与内一圈像素的明度，检测白边、浅色光晕与半透明白雾。"""
    a = rgba[..., 3]
    visible = a > 0
    edge = visible & neighbor_any(a == 0)
    inner = visible & ~edge & neighbor_any(edge)
    if edge.sum() == 0 or inner.sum() == 0:
        return {"edge_pixels": int(edge.sum())}
    l_star = lab[..., 0]
    chroma = np.hypot(lab[..., 1], lab[..., 2])
    semi = visible & (a < 255)
    near_white = (l_star > 85) & (chroma < 12)
    return {
        "edge_pixels": int(edge.sum()),
        "edge_mean_L": round(float(l_star[edge].mean()), 2),
        "inner_mean_L": round(float(l_star[inner].mean()), 2),
        "edge_minus_inner_L": round(float(l_star[edge].mean() - l_star[inner].mean()), 2),
        "edge_near_white_share": round(float(near_white[edge].mean()), 4),
        "semi_light_share": round(float((semi & (l_star > 80) & (chroma < 15)).sum() / max(semi.sum(), 1)), 4),
    }


def checker_pattern(rgb: np.ndarray, region: np.ndarray, min_share: float = 0.03) -> dict:
    """检测区域内是否存在“假透明”棋盘格：两档浅中性灰按固定边长交替。"""
    n_region = int(region.sum())
    if n_region == 0:
        return {"suspect": False}
    lab = srgb_to_lab(rgb)
    l_star = lab[..., 0]
    chroma = np.hypot(lab[..., 1], lab[..., 2])
    neutral = region & (chroma < 6) & (l_star > 70)
    share = neutral.sum() / n_region
    if share < min_share:
        return {"suspect": False, "neutral_light_share": round(float(share), 4)}
    vals = l_star[neutral]
    mid = float(np.median(vals))
    hi = neutral & (l_star > mid + 1.5)
    lo = neutral & (l_star < mid - 1.5)
    if hi.sum() < 50 or lo.sum() < 50:
        return {"suspect": False, "neutral_light_share": round(float(share), 4)}
    # 沿行统计高/低两档的游程长度，棋盘格会集中在同一边长
    runs = []
    rows = np.nonzero((hi | lo).any(axis=1))[0]
    for y in rows[:: max(1, len(rows) // 200)]:
        line = np.where(hi[y], 1, np.where(lo[y], -1, 0))
        start = 0
        for x in range(1, len(line) + 1):
            if x == len(line) or line[x] != line[start]:
                if line[start] != 0:
                    runs.append(x - start)
                start = x
    if not runs:
        return {"suspect": False, "neutral_light_share": round(float(share), 4)}
    runs = np.array(runs)
    vals_, counts = np.unique(runs[runs >= 4], return_counts=True)
    if len(vals_) == 0:
        return {"suspect": False, "neutral_light_share": round(float(share), 4)}
    top = int(vals_[counts.argmax()])
    near_top = float(((runs >= top - 1) & (runs <= top + 1)).sum() / len(runs))
    return {
        "suspect": near_top > 0.45 and top >= 4,
        "neutral_light_share": round(float(share), 4),
        "dominant_run": top,
        "dominant_run_share": round(near_top, 3),
    }


# ---------------------------------------------------------------- 像素网格与密度


def _axis_grid(edge_counts: np.ndarray, kmax: int) -> dict | None:
    total = edge_counts.sum()
    if total <= 0:
        return None
    base = edge_counts.mean()
    scores = {}
    for k in range(2, kmax + 1):
        means = np.array([edge_counts[p::k].mean() if len(edge_counts[p::k]) else 0 for p in range(k)])
        score = means.max() / (base + 1e-9)
        conf = (score - 1) / (k - 1)
        scores[k] = (float(max(0.0, min(1.0, conf))), int(means.argmax()))
    strong = [k for k, (c, _) in scores.items() if c >= 0.8]
    k_best = max(strong) if strong else max(scores, key=lambda kk: scores[kk][0])
    return {
        "k": k_best,
        "confidence": round(scores[k_best][0], 3),
        "phase": scores[k_best][1],
        "top": sorted(((kk, round(v[0], 3)) for kk, v in scores.items()), key=lambda t: -t[1])[:4],
    }


def pixel_grid(rgba: np.ndarray, lab: np.ndarray, kmax: int = 16, edge_de: float = 6.0) -> dict:
    """估计“美术像素”边长：真正按 k 倍 nearest 放大的像素画，颜色边界只落在固定相位的 k 倍位置。

    confidence 接近 1 表示存在严格网格；0.35 以下表示没有一致网格（涂抹质感、AI 伪像素或经过插值缩放）。
    """
    vis = rgba[..., 3] >= 128
    dx = np.linalg.norm(lab[:, 1:] - lab[:, :-1], axis=-1)
    dy = np.linalg.norm(lab[1:, :] - lab[:-1, :], axis=-1)
    ex = ((dx > edge_de) & vis[:, 1:] & vis[:, :-1]).sum(axis=0).astype(float)
    ey = ((dy > edge_de) & vis[1:, :] & vis[:-1, :]).sum(axis=1).astype(float)
    return {"x": _axis_grid(ex, kmax), "y": _axis_grid(ey, kmax)}


def scale_evenness(art_pixel: int, phase: int, scale: float, length: int = 512) -> dict:
    """给定美术像素边长与屏幕缩放倍率，计算 nearest 采样后每个美术像素占用的屏幕像素宽度集合。

    宽度集合只有一个值为“均匀”；出现 {1,2} 等多值即会产生粗细不一的线条与闪烁。
    """
    out_len = int(length * scale)
    src = np.floor((np.arange(out_len) + 0.5) / scale).astype(int)
    block = (src - phase) // art_pixel
    _, widths = np.unique(block, return_counts=True)
    widths = widths[1:-1] if len(widths) > 2 else widths
    ws = sorted({int(w) for w in widths})
    return {"scale": scale, "art_pixel": art_pixel, "widths": ws, "even": len(ws) == 1}


# ---------------------------------------------------------------- 调色与明度


def palette_extract(rgba: np.ndarray, n: int = 16, max_pixels: int = 250_000) -> list[dict]:
    """对可见像素做中位切分量化，返回按占比排序的主色。"""
    vis = rgba[..., 3] >= 128
    px = rgba[..., :3][vis]
    if len(px) == 0:
        return []
    if len(px) > max_pixels:
        idx = np.linspace(0, len(px) - 1, max_pixels).astype(int)
        px = px[idx]
    strip = Image.fromarray(px.reshape(1, -1, 3), "RGB")
    q = strip.quantize(colors=n, method=Image.Quantize.MEDIANCUT)
    pal = np.array(q.getpalette()[: 3 * n]).reshape(-1, 3)
    counts = np.bincount(np.asarray(q).ravel(), minlength=n)
    order = np.argsort(-counts)
    total = counts.sum()
    out = []
    for i in order:
        if counts[i] == 0:
            continue
        lab = srgb_to_lab(pal[i].reshape(1, 3))[0]
        out.append(
            {
                "hex": rgb_to_hex(pal[i]),
                "share": round(float(counts[i] / total), 4),
                "L": round(float(lab[0]), 1),
                "C": round(float(np.hypot(lab[1], lab[2])), 1),
                "h": round(float(np.degrees(np.arctan2(lab[2], lab[1])) % 360), 1),
            }
        )
    return out


def palette_adherence(lab_pixels: np.ndarray, ref_hex: list[str], threshold: float = 6.0) -> dict:
    """可见像素到参考色板最近色的 CIEDE2000 距离分布。"""
    if len(lab_pixels) == 0 or not ref_hex:
        return {}
    ref = srgb_to_lab(np.array([hex_to_rgb(h) for h in ref_hex], dtype=np.float64).reshape(-1, 3))
    best = np.full(len(lab_pixels), np.inf)
    for r in ref:
        best = np.minimum(best, ciede2000(lab_pixels, r.reshape(1, 3)))
    return {
        "within_threshold_share": round(float((best <= threshold).mean()), 4),
        "threshold": threshold,
        "mean_delta_e00": round(float(best.mean()), 2),
        "p90_delta_e00": round(float(np.percentile(best, 90)), 2),
    }


def value_profile(lab: np.ndarray, rgba: np.ndarray) -> dict:
    vis = rgba[..., 3] >= 128
    if vis.sum() == 0:
        return {}
    l_star = lab[..., 0][vis]
    chroma = np.hypot(lab[..., 1], lab[..., 2])[vis]
    return {
        "L_mean": round(float(l_star.mean()), 2),
        "L_p05": round(float(np.percentile(l_star, 5)), 2),
        "L_p50": round(float(np.percentile(l_star, 50)), 2),
        "L_p95": round(float(np.percentile(l_star, 95)), 2),
        "C_mean": round(float(chroma.mean()), 2),
        "C_p95": round(float(np.percentile(chroma, 95)), 2),
    }


def unique_colors(rgba: np.ndarray) -> int:
    vis = rgba[..., 3] >= 128
    px = rgba[..., :3][vis].astype(np.uint32)
    if len(px) == 0:
        return 0
    packed = (px[:, 0] << 16) | (px[:, 1] << 8) | px[:, 2]
    return int(len(np.unique(packed)))


def symmetry(rgba: np.ndarray, lab: np.ndarray, axis: str = "x", de: float = 8.0) -> dict:
    """镜像对称差异：axis=x 为左右镜像，axis=y 为上下镜像。只比较两侧至少一侧可见的像素。"""
    flip = (lambda arr: arr[:, ::-1]) if axis == "x" else (lambda arr: arr[::-1, :])
    a = rgba[..., 3] >= 128
    af = flip(a)
    union = a | af
    if union.sum() == 0:
        return {}
    alpha_mismatch = float((a ^ af)[union].mean())
    both = a & af
    d = np.linalg.norm(lab - flip(lab), axis=-1)
    color_mismatch = float((d[both] > de).mean()) if both.sum() else 0.0
    return {"axis": axis, "alpha_mismatch": round(alpha_mismatch, 4), "color_mismatch": round(color_mismatch, 4)}


# ---------------------------------------------------------------- 采样模拟


def gpu_bilinear(rgba: np.ndarray, scale: float, premultiplied: bool = False) -> np.ndarray:
    """模拟 GPU 无 mipmap 的双线性采样（每个输出像素只取 2×2 纹素）。

    Pillow 的 BILINEAR 缩小会自动扩大采样核，与游戏内无 mipmap 采样不同；需要评估游戏内缩小后的锯齿、
    细节丢失与边缘颜色渗出时使用本函数。
    """
    h, w = rgba.shape[:2]
    oh, ow = max(1, int(round(h * scale))), max(1, int(round(w * scale)))
    src = rgba.astype(np.float64) / 255.0
    if premultiplied:
        src[..., :3] *= src[..., 3:4]
    ys = (np.arange(oh) + 0.5) / scale - 0.5
    xs = (np.arange(ow) + 0.5) / scale - 0.5
    y0 = np.clip(np.floor(ys).astype(int), 0, h - 1)
    x0 = np.clip(np.floor(xs).astype(int), 0, w - 1)
    y1 = np.clip(y0 + 1, 0, h - 1)
    x1 = np.clip(x0 + 1, 0, w - 1)
    fy = np.clip(ys - np.floor(ys), 0, 1)[:, None, None]
    fx = np.clip(xs - np.floor(xs), 0, 1)[None, :, None]
    top = src[y0][:, x0] * (1 - fx) + src[y0][:, x1] * fx
    bot = src[y1][:, x0] * (1 - fx) + src[y1][:, x1] * fx
    out = top * (1 - fy) + bot * fy
    if premultiplied:
        a = out[..., 3:4]
        out[..., :3] = np.where(a > 0, out[..., :3] / np.maximum(a, 1e-9), 0)
    return np.clip(out * 255 + 0.5, 0, 255).astype(np.uint8)


def nearest_scale(rgba: np.ndarray, scale: float) -> np.ndarray:
    """与 Godot nearest 过滤一致的点采样缩放（取输出像素中心对应的源像素）。"""
    h, w = rgba.shape[:2]
    oh, ow = max(1, int(h * scale)), max(1, int(w * scale))
    ys = np.clip(np.floor((np.arange(oh) + 0.5) / scale).astype(int), 0, h - 1)
    xs = np.clip(np.floor((np.arange(ow) + 0.5) / scale).astype(int), 0, w - 1)
    return rgba[ys][:, xs]
