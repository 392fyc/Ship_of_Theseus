"""NinePatch / StyleBoxTexture 拉伸检查：按 Godot 的九宫格语义在多个尺寸下渲染，并量化边条是否适合拉伸。

Godot 行为（StyleBoxTexture / NinePatchRect）：四角原样绘制；上下边条只沿横向变化，左右边条只沿纵向变化；
axis_stretch 为 STRETCH 时拉伸，TILE 时重复，TILE_FIT 时重复并微调到整数次。

用法示例：
    uv run --no-project --python 3.13 --with numpy --with pillow python nineslice_check.py \
        --margins 12,12,12,12 --sizes 64x48,200x64,640x160 --mode stretch --scale 2 --out ns.png panel.png
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import artlib as al  # noqa: E402


def resize_axis(strip: np.ndarray, length: int, axis: int, mode: str) -> np.ndarray:
    n = strip.shape[axis]
    if length <= 0:
        shape = list(strip.shape)
        shape[axis] = 0
        return np.zeros(shape, strip.dtype)
    if n == 0:
        raise ValueError("边条长度为 0，边距配置无效")
    if mode == "stretch":
        idx = np.clip(np.floor((np.arange(length) + 0.5) * n / length).astype(int), 0, n - 1)
    elif mode == "tile":
        idx = np.arange(length) % n
    elif mode == "tile_fit":
        reps = max(1, round(length / n))
        idx = np.clip(np.floor((np.arange(length) + 0.5) * (n * reps) / length).astype(int) % n, 0, n - 1)
    else:
        raise ValueError(mode)
    return np.take(strip, idx, axis=axis)


def render(src: np.ndarray, margins: tuple[int, int, int, int], size: tuple[int, int], mode: str) -> np.ndarray:
    l, t, r, b = margins
    h, w = src.shape[:2]
    ow, oh = size
    cw, ch = ow - l - r, oh - t - b
    if cw < 0 or ch < 0:
        raise ValueError(f"目标尺寸 {ow}×{oh} 小于边距之和")
    top = np.concatenate([src[:t, :l], resize_axis(src[:t, l : w - r], cw, 1, mode), src[:t, w - r :]], axis=1)
    mid_l = resize_axis(src[t : h - b, :l], ch, 0, mode)
    mid_c = resize_axis(resize_axis(src[t : h - b, l : w - r], cw, 1, mode), ch, 0, mode)
    mid_r = resize_axis(src[t : h - b, w - r :], ch, 0, mode)
    mid = np.concatenate([mid_l, mid_c, mid_r], axis=1)
    bot = np.concatenate([src[h - b :, :l], resize_axis(src[h - b :, l : w - r], cw, 1, mode), src[h - b :, w - r :]], axis=1)
    return np.concatenate([top, mid, bot], axis=0)


def strip_variation(strip: np.ndarray, axis: int) -> dict:
    """沿拉伸方向的相邻像素色差。均一边条接近 0；有花纹的边条拉伸会变形，应改用 tile 或简化花纹。"""
    if strip.size == 0 or strip.shape[axis] < 2:
        return {"mean_de76": 0.0, "period": None}
    lab = al.srgb_to_lab(strip[..., :3])
    alpha = strip[..., 3].astype(float) / 255
    lab = lab * alpha[..., None]  # 透明像素按黑色参与比较，避免残留 RGB 干扰
    d = np.linalg.norm(np.diff(lab, axis=axis), axis=-1)
    prof = lab.mean(axis=1 - axis) if axis in (0, 1) else lab
    # 周期：沿拉伸方向的剖面自相关
    series = np.linalg.norm(prof - prof.mean(axis=0), axis=-1)
    n = len(series)
    period = None
    if n >= 8 and series.std() > 1e-6:
        s = series - series.mean()
        ac = np.correlate(s, s, mode="full")[n - 1 :] / (s.var() * np.arange(n, 0, -1))
        cand = [(k, ac[k]) for k in range(2, n // 2) if ac[k] > 0.8]
        period = int(cand[0][0]) if cand else None
    return {"mean_de76": round(float(d.mean()), 3), "period": period}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("file", type=Path)
    ap.add_argument("--margins", required=True, type=lambda s: tuple(int(v) for v in s.split(",")), help="L,T,R,B")
    ap.add_argument("--sizes", required=True, help="逗号分隔的 WxH，覆盖最小、标准、最大")
    ap.add_argument("--mode", default="stretch", choices=["stretch", "tile", "tile_fit"])
    ap.add_argument("--scale", type=int, default=2, help="输出图 nearest 放大倍数（诊断用，最多 2×）")
    ap.add_argument("--scene-color", default="#10131A")
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--json", type=Path)
    args = ap.parse_args()

    src, _ = al.load_rgba(args.file)
    l, t, r, b = args.margins
    h, w = src.shape[:2]
    if l + r >= w or t + b >= h:
        raise SystemExit(f"边距 {args.margins} 超出源图 {w}×{h}")
    sizes = [tuple(int(v) for v in s.lower().split("x")) for s in args.sizes.split(",")]

    metrics = {
        "file": args.file.name,
        "sha256": al.sha256_file(args.file),
        "source_size": [w, h],
        "margins_LTRB": list(args.margins),
        "mode": args.mode,
        "strips": {
            "top": strip_variation(src[:t, l : w - r], 1),
            "bottom": strip_variation(src[h - b :, l : w - r], 1),
            "left": strip_variation(src[t : h - b, :l], 0),
            "right": strip_variation(src[t : h - b, w - r :], 0),
            "center_x": strip_variation(src[t : h - b, l : w - r], 1),
            "center_y": strip_variation(src[t : h - b, l : w - r], 0),
        },
        "warnings": [],
    }
    if args.mode == "stretch":
        for name, m in metrics["strips"].items():
            if m["mean_de76"] > 2.5:
                hint = f"，检测到约 {m['period']} 像素周期，可改用 tile/tile_fit" if m["period"] else ""
                metrics["warnings"].append(f"{name} 边条沿拉伸方向不均一（ΔE76 均值 {m['mean_de76']}），stretch 会拉长花纹{hint}。")
    for v, name in ((l, "L"), (t, "T"), (r, "R"), (b, "B")):
        if v % 2:
            metrics["warnings"].append(f"边距 {name}={v} 为奇数，1.5× 画布缩放下角部与边条交界会出现 1/2 像素交替。")

    scene = al.hex_to_rgb(args.scene_color)
    font = ImageFont.load_default()
    renders = []
    for sz in sizes:
        out = render(src, args.margins, sz, args.mode)
        im = Image.fromarray(out, "RGBA")
        im = im.resize((im.width * args.scale, im.height * args.scale), Image.NEAREST)
        renders.append((sz, im))
    guide = Image.fromarray(src, "RGBA").resize((w * args.scale, h * args.scale), Image.NEAREST)
    gd = ImageDraw.Draw(guide)
    s = args.scale
    for x in (l * s, (w - r) * s):
        gd.line([(x, 0), (x, h * s)], fill=(0, 255, 255, 255))
    for y in (t * s, (h - b) * s):
        gd.line([(0, y), (w * s, y)], fill=(0, 255, 255, 255))

    pad = 12
    total_w = max([guide.width] + [im.width for _, im in renders]) + pad * 2
    total_h = pad + guide.height + 20 + sum(im.height + 20 + pad for _, im in renders) + pad
    sheet = Image.new("RGBA", (total_w, total_h), scene + (255,))
    d = ImageDraw.Draw(sheet)
    y = pad
    d.text((pad, y), f"source {w}x{h} margins {args.margins} (cyan guides) x{s}", fill=(220, 220, 210), font=font)
    sheet.alpha_composite(guide, (pad, y + 14))
    y += 14 + guide.height + pad
    for sz, im in renders:
        d.text((pad, y), f"{sz[0]}x{sz[1]} {args.mode} x{s}", fill=(220, 220, 210), font=font)
        sheet.alpha_composite(im, (pad, y + 14))
        y += 14 + im.height + pad
    args.out.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(args.out)
    if args.json:
        args.json.write_text(json.dumps(metrics, ensure_ascii=False, indent=2), encoding="utf-8")
    sys.stdout.reconfigure(encoding="utf-8")
    print(json.dumps(metrics, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
