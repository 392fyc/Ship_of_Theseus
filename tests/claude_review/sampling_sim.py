"""缩小采样量化：按运行场景的真实显示高度，比较当前采样与面积滤波（等效 mipmap 或离线降采样）。

显示高度由代码推算（1280×720 基准；1920×1080、2560×1440 在项目拉伸下再乘 1.5、2）：
- 庭院演示镜头 `board_zoom × factor` = 1.36（battlefield_courtyard.gd:222）。
- 试战镜头按 terrain_battle_session.gd:99-106：10×10 为 0.92，25×25 为 0.418。
- 默认战斗 TacticalScene 未设置镜头缩放，按 1.0。
- 试战 `transition_preview=true`，跳过环境道具（courtyard_board_view.gd:530-531）：只有棋盘内森林树
  （缩放 0.91–1.02，:513）与残墙端碎石（缩放 0.35，:521），没有入口与树丛。
- 棋子单帧显示 60×80（scale 0.15625），源帧 384×512。

运行（仓库根目录）：
    uv run --no-project --python 3.13 --with numpy --with pillow python tests/claude_review/sampling_sim.py --out <仓库外目录>
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import artlib as al  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
B = ROOT / "assets/prototype/battlefield_courtyard"
BG = (16, 19, 26, 255)

# 名称, 文件, 源区域 (x, y, w, h), 运行过滤, [(场景说明, 720p 显示高度)]
CASES = [
    ("森林树 forest-tree-v2", B / "forest-tree-v2.png", (286, 33, 964, 950), "nearest",
     [("试战10×10 棋盘内树", 65.04 * 0.965 * 0.92), ("试战25×25 棋盘内树", 65.04 * 0.965 * 0.418),
      ("庭院树丛(1.75–2.01)", 65.04 * 1.88 * 1.36)]),
    ("碎石 low-rubble-v1", B / "low-rubble-v1.png", (426, 270, 690, 496), "nearest",
     [("试战10×10 残墙端", 37 * 0.35 * 0.92), ("试战25×25 残墙端", 37 * 0.35 * 0.418), ("庭院残墙端", 37 * 0.35 * 1.36)]),
    ("入口 courtyard-entry-v2", B / "courtyard-entry-v2.png", (35, 180, 1485, 745), "nearest",
     [("庭院入口(0.9)", 95.32 * 0.9 * 1.36)]),
    ("剑圣棋子 SW 帧", ROOT / "assets/units/kensei/map_token_clean_v2.png", (768, 0, 384, 512), "linear",
     [("默认战斗(镜头1.0)", 80.0), ("同规格用于试战10×10", 80 * 0.92), ("同规格用于试战25×25", 80 * 0.418)]),
]


def composite(a: np.ndarray) -> np.ndarray:
    im = Image.new("RGBA", (a.shape[1], a.shape[0]), BG)
    im.alpha_composite(Image.fromarray(a, "RGBA"))
    return np.asarray(im.convert("RGB"))


def mip_chain(src: np.ndarray) -> list[np.ndarray]:
    """按 2×2 盒式平均逐级生成 mip 链（预乘 alpha 后平均，避免透明边渗色）。"""
    levels = [src.astype(np.float64) / 255.0]
    cur = levels[0].copy()
    cur[..., :3] *= cur[..., 3:4]
    premul = [cur]
    while min(cur.shape[:2]) > 1:
        h, w = (cur.shape[0] // 2) * 2, (cur.shape[1] // 2) * 2
        c = cur[:h, :w]
        cur = (c[0::2, 0::2] + c[1::2, 0::2] + c[0::2, 1::2] + c[1::2, 1::2]) / 4.0
        premul.append(cur)
    out = []
    for p in premul:
        q = p.copy()
        a = q[..., 3:4]
        q[..., :3] = np.where(a > 0, q[..., :3] / np.maximum(a, 1e-9), 0)
        out.append(np.clip(q * 255 + 0.5, 0, 255).astype(np.uint8))
    return out


def bilinear_to(level: np.ndarray, oh: int, ow: int) -> np.ndarray:
    """在一级 mip 上按输出像素中心做 2×2 双线性采样，输出精确为 oh×ow。"""
    h, w = level.shape[:2]
    src = level.astype(np.float64)
    ys = (np.arange(oh) + 0.5) * h / oh - 0.5
    xs = (np.arange(ow) + 0.5) * w / ow - 0.5
    y0 = np.clip(np.floor(ys).astype(int), 0, h - 1)
    x0 = np.clip(np.floor(xs).astype(int), 0, w - 1)
    y1, x1 = np.clip(y0 + 1, 0, h - 1), np.clip(x0 + 1, 0, w - 1)
    fy = np.clip(ys - np.floor(ys), 0, 1)[:, None, None]
    fx = np.clip(xs - np.floor(xs), 0, 1)[None, :, None]
    top = src[y0][:, x0] * (1 - fx) + src[y0][:, x1] * fx
    bot = src[y1][:, x0] * (1 - fx) + src[y1][:, x1] * fx
    return top * (1 - fy) + bot * fy


def gpu_trilinear(src: np.ndarray, scale: float, bias: float = 0.0, chain: list[np.ndarray] | None = None) -> np.ndarray:
    """近似 GPU 的 LINEAR_WITH_MIPMAPS：LOD = log2(1/scale) + bias，在相邻两级上双线性采样到同一输出尺寸再线性混合。
    输出尺寸与 nearest/双线性模式一致（round(源尺寸 × scale)），便于逐像素比较。"""
    chain = chain or mip_chain(src)
    h, w = src.shape[:2]
    oh, ow = max(1, int(round(h * scale))), max(1, int(round(w * scale)))
    lod = max(0.0, np.log2(1.0 / scale) + bias)
    lo = min(int(np.floor(lod)), len(chain) - 1)
    hi = min(lo + 1, len(chain) - 1)
    t = lod - np.floor(lod) if hi != lo else 0.0
    out = bilinear_to(chain[lo], oh, ow) * (1 - t) + bilinear_to(chain[hi], oh, ow) * t
    return np.clip(out + 0.5, 0, 255).astype(np.uint8)


def sample(src: np.ndarray, scale: float, filt: str, chain: list[np.ndarray] | None = None) -> np.ndarray:
    if filt == "nearest":
        return al.nearest_scale(src, scale)
    if filt == "linear":
        return al.gpu_bilinear(src, scale)
    if filt.startswith("mip"):
        bias = float(filt.split(":", 1)[1]) if ":" in filt else 0.0
        return gpu_trilinear(src, scale, bias, chain)
    raise ValueError(filt)


def reference(src: np.ndarray, shape) -> np.ndarray:
    return np.asarray(Image.fromarray(src, "RGBA").resize((shape[1], shape[0]), Image.BOX))


def measure(src: np.ndarray, s: float, filt: str, chain) -> dict:
    """与面积滤波参考比较：平均 ΔE76；缩放 +2% 前后的差异（近似镜头缩放闪烁）。输出过小（高 < 20 像素）时抖动不定义。"""
    cur = sample(src, s, filt, chain)
    ref = reference(src, cur.shape)
    vc, vr = composite(cur), composite(ref)
    m = (cur[..., 3] > 0) | (ref[..., 3] > 0)
    de = float(np.linalg.norm(al.srgb_to_lab(vc) - al.srgb_to_lab(vr), axis=-1)[m].mean()) if m.any() else 0.0
    out = {"de76": round(de, 2), "jitter": None, "jitter_reference": None, "image": vc, "reference_image": vr}
    if cur.shape[0] >= 20:
        cur2 = sample(src, s * 1.02, filt, chain)
        ref2 = reference(src, cur2.shape)
        back = lambda a: np.asarray(Image.fromarray(composite(a)).resize((cur.shape[1], cur.shape[0]), Image.BOX))
        out["jitter"] = round(float(np.abs(back(cur2).astype(int) - vc.astype(int)).mean()), 2)
        out["jitter_reference"] = round(float(np.abs(back(ref2).astype(int) - vr.astype(int)).mean()), 2)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--master", action="append", default=[],
                    help="用母版替换源区域：<资产名前缀>=<母版 PNG>，母版应与源区域同比例（如 CR-01 的显示尺寸母版）")
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    masters = dict(m.split("=", 1) for m in args.master)
    rows, tiles = [], []
    for name, path, (x, y, w, h), filt, uses in CASES:
        src = np.asarray(Image.open(path).convert("RGBA"))[y : y + h, x : x + w]
        for prefix, mpath in masters.items():
            if name.startswith(prefix):
                src = np.asarray(Image.open(mpath).convert("RGBA"))
                h = src.shape[0]
        chain = mip_chain(src)
        for scene, dh720 in uses:
            for res, mult in (("1280×720", 1.0), ("2560×1440", 2.0)):
                dh = dh720 * mult
                s = min(1.0, dh / h)
                row = {"asset": name, "scene": scene, "resolution": res, "display_h_px": round(dh, 1),
                       "minification": round(h / dh, 1), "runtime_filter": filt}
                for label, mode in (("current", filt), ("mip", "mip"), ("mip_bias_-0.5", "mip:-0.5")):
                    r = measure(src, s, mode, chain)
                    row[label] = {k: v for k, v in r.items() if not k.endswith("image")}
                    if label == "current" and res == "1280×720":
                        tiles.append((f"{name} · {scene} · {dh:.0f}px", r["image"], r["reference_image"]))
                cur = row["current"]
                # 抖动判据只在缩小 ≥ 1.5 倍、输出高 ≥ 20 像素且参考抖动 ≥ 0.5 时成立；接近 1:1 时参考几乎不变，比值没有意义。
                jitter_valid = row["minification"] >= 1.5 and cur["jitter"] is not None and cur["jitter_reference"] >= 0.5
                row["jitter_criterion_applies"] = jitter_valid
                row["jitter_ratio_current"] = round(cur["jitter"] / cur["jitter_reference"], 1) if jitter_valid else None
                for label in ("mip", "mip_bias_-0.5"):
                    r = row[label]
                    ok_jitter = (not jitter_valid) or (r["jitter"] is not None and r["jitter"] <= 1.3 * cur["jitter_reference"])
                    row[f"{label}_meets_target"] = r["de76"] <= 4.0 and ok_jitter
                rows.append(row)
    (args.out / "sampling-sim.json").write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")
    # 对照图只用于看图；可复现的依据是 sampling-sim.json。系统没有中文字体时，标签可能无法显示中文。
    # 可用环境变量 CLAUDE_REVIEW_FONT 指定字体；否则依次尝试常见中文字体，都没有时退回默认字体。
    candidates = [os.environ.get("CLAUDE_REVIEW_FONT", ""), "msyh.ttc", "NotoSansCJK-Regular.ttc", "PingFang.ttc"]
    font = ImageFont.load_default()
    for name in candidates:
        if not name:
            continue
        try:
            font = ImageFont.truetype(name, 13)
            break
        except OSError:
            continue
    z = 3
    cw = max(t[1].shape[1] for t in tiles) * z
    ch = max(t[1].shape[0] for t in tiles) * z
    sheet = Image.new("RGB", (40 + 2 * cw, 30 + len(tiles) * (ch + 22)), (24, 24, 28))
    d = ImageDraw.Draw(sheet)
    d.text((10, 6), "左：当前运行采样（无 mipmap）  右：面积滤波（等效 mipmap）  3× nearest，仅诊断", fill=(220, 216, 206), font=font)
    for i, (label, c, r) in enumerate(tiles):
        y0 = 28 + i * (ch + 22)
        d.text((10, y0), label, fill=(170, 166, 158), font=font)
        sheet.paste(Image.fromarray(c).resize((c.shape[1] * z, c.shape[0] * z), Image.NEAREST), (10, y0 + 16))
        sheet.paste(Image.fromarray(r).resize((r.shape[1] * z, r.shape[0] * z), Image.NEAREST), (30 + cw, y0 + 16))
    sheet.save(args.out / "sampling-sim-sheet.png")
    sys.stdout.reconfigure(encoding="utf-8")
    print("资产 | 场景 | 分辨率 | 显示高 | 缩小倍数 | 过滤 | 当前 ΔE76 / 抖动 / 参考抖动 | mip ΔE76 / 抖动 / 达标 | mip −0.5 ΔE76 / 抖动 / 达标")
    for r in rows:
        c, m, mb = r["current"], r["mip"], r["mip_bias_-0.5"]
        print(f"{r['asset']} | {r['scene']} | {r['resolution']} | {r['display_h_px']} | {r['minification']} | {r['runtime_filter']} | "
              f"{c['de76']} / {c['jitter']} / {c['jitter_reference']} | {m['de76']} / {m['jitter']} / {r['mip_meets_target']} | "
              f"{mb['de76']} / {mb['jitter']} / {r['mip_bias_-0.5_meets_target']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
