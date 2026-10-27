"""审核联系表：同一素材放在多种底色、灰度和游戏内缩放模拟下并排查看。

为什么需要：Claude 的图片查看会忽略 alpha，直接显示透明区底下残留的 RGB；只有合成到已知底色上才能看到真实外观。
品红底暴露白边与抗锯齿残留，白底暴露暗边，灰度列用于检查明度层级。

用法示例：
    uv run --no-project --python 3.13 --with numpy --with pillow python contact_sheet.py \
        --bgs checker,black,white,magenta,scene --gray --fit 320 --out sheet.png a.png b.png
    # 游戏内显示模拟：nearest 1.5×（1080p 画布缩放）或无 mipmap 双线性 0.15625×（棋子）
    ... --sim nearest:1.5 --sim gpu_bilinear:0.15625 --native --crop 0,0,384,512 token.png
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import artlib as al  # noqa: E402

BG = {
    "black": (0, 0, 0),
    "white": (255, 255, 255),
    "magenta": (255, 0, 255),
    "gray": (128, 128, 128),
}
LABEL_BG = (24, 24, 28)
LABEL_FG = (230, 226, 216)


def load_font(size: int) -> ImageFont.ImageFont:
    for cand in ("C:/Windows/Fonts/msyh.ttc", "C:/Windows/Fonts/simhei.ttf", "C:/Windows/Fonts/arial.ttf"):
        try:
            return ImageFont.truetype(cand, size)
        except OSError:
            continue
    return ImageFont.load_default()


def background(name: str, w: int, h: int, scene_rgb: tuple[int, int, int]) -> Image.Image:
    if name == "checker":
        yy, xx = np.mgrid[0:h, 0:w]
        v = np.where(((yy // 8 + xx // 8) % 2) == 0, 58, 90).astype(np.uint8)
        return Image.fromarray(np.dstack([v, v, v, np.full_like(v, 255)]), "RGBA")
    rgb = scene_rgb if name == "scene" else BG[name]
    return Image.new("RGBA", (w, h), rgb + (255,))


def to_gray(im: Image.Image) -> Image.Image:
    """按 CIE L* 生成灰度，而不是简单平均，便于比较明度层级。"""
    arr = np.asarray(im.convert("RGBA"))
    l_star = al.srgb_to_lab(arr[..., :3])[..., 0]
    # L* → sRGB 灰度（中性灰的 L* 反变换）
    y = np.where(l_star > 8, ((l_star + 16) / 116) ** 3, l_star / (24389 / 27))
    s = np.where(y <= 0.0031308, 12.92 * y, 1.055 * np.power(np.clip(y, 0, 1), 1 / 2.4) - 0.055)
    g = np.clip(s * 255 + 0.5, 0, 255).astype(np.uint8)
    return Image.fromarray(np.dstack([g, g, g, arr[..., 3]]), "RGBA")


def apply_sim(arr: np.ndarray, sims: list[str]) -> tuple[np.ndarray, list[str]]:
    notes = []
    for s in sims:
        kind, _, factor = s.partition(":")
        f = float(factor)
        if kind == "nearest":
            arr = al.nearest_scale(arr, f)
        elif kind == "gpu_bilinear":
            arr = al.gpu_bilinear(arr, f)
        elif kind == "gpu_bilinear_premul":
            arr = al.gpu_bilinear(arr, f, premultiplied=True)
        else:
            raise SystemExit(f"未知模拟方式：{kind}")
        notes.append(f"{kind}×{f:g}")
    return arr, notes


def fit_tile(im: Image.Image, fit: int, native: bool) -> tuple[Image.Image, str]:
    if native:
        return im, "1:1"
    w, h = im.size
    longer = max(w, h)
    if longer <= fit:
        k = max(1, fit // longer)
        return im.resize((w * k, h * k), Image.NEAREST), f"nearest {k}×"
    r = fit / longer
    return im.resize((max(1, int(w * r)), max(1, int(h * r))), Image.LANCZOS), f"缩略 {r:.3f}×（重采样，仅看整体）"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="+", type=Path)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--bgs", default="checker,black,white,magenta,scene")
    ap.add_argument("--scene-color", default="#10131A", help="游戏战场暗底色，默认接近当前实机背景")
    ap.add_argument("--gray", action="store_true", help="追加 L* 灰度列（叠在 scene 底上）")
    ap.add_argument("--fit", type=int, default=320)
    ap.add_argument("--native", action="store_true", help="不缩放，逐像素 1:1")
    ap.add_argument("--crop", type=lambda s: [int(v) for v in s.split(",")], help="x,y,w,h")
    ap.add_argument("--sim", action="append", default=[], help="nearest:1.5 / gpu_bilinear:0.15625，可重复")
    args = ap.parse_args()

    scene_rgb = al.hex_to_rgb(args.scene_color)
    bgs = [b.strip() for b in args.bgs.split(",") if b.strip()]
    font = load_font(14)
    rows = []
    for path in args.files:
        arr, _info = al.load_rgba(path)
        if args.crop:
            x, y, w, h = args.crop
            arr = arr[y : y + h, x : x + w]
        arr, notes = apply_sim(arr, args.sim)
        im = Image.fromarray(arr, "RGBA")
        tiles = []
        scale_note = ""
        for b in bgs:
            t, scale_note = fit_tile(im, args.fit, args.native)
            base = background(b, t.width, t.height, scene_rgb)
            base.alpha_composite(t)
            tiles.append((b, base))
        if args.gray:
            t, _ = fit_tile(to_gray(im), args.fit, args.native)
            base = background("scene", t.width, t.height, scene_rgb)
            base.alpha_composite(t)
            tiles.append(("L* 灰度", base))
        label = f"{path.name}  {arr.shape[1]}×{arr.shape[0]}  sha {al.sha256_file(path)[:12]}  {scale_note}"
        if notes:
            label += "  模拟：" + " → ".join(notes)
        if args.crop:
            label += f"  裁切 {args.crop}"
        rows.append((label, tiles))

    pad, label_h = 8, 24
    col_w = max(t.width for _, tiles in rows for _, t in tiles)
    row_h = [max(t.height for _, t in tiles) for _, tiles in rows]
    ncol = max(len(tiles) for _, tiles in rows)
    width = pad + ncol * (col_w + pad)
    height = pad + sum(label_h * 2 + h + pad for h in row_h)
    sheet = Image.new("RGBA", (max(width, 640), height), LABEL_BG + (255,))
    draw = ImageDraw.Draw(sheet)
    y = pad
    for (label, tiles), h in zip(rows, row_h):
        draw.text((pad, y), label, fill=LABEL_FG, font=font)
        y += label_h
        for i, (name, t) in enumerate(tiles):
            x = pad + i * (col_w + pad)
            draw.text((x, y), name, fill=(170, 166, 158), font=font)
            sheet.alpha_composite(t, (x, y + label_h))
        y += label_h + h + pad
    args.out.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(args.out)
    print(f"写入 {args.out}  {sheet.width}×{sheet.height}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
