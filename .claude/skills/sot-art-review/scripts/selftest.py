"""审核脚本自检：用已知答案的数据验证色差、网格、棋盘格、缩放均匀性与采样函数。

    uv run --no-project --python 3.13 --with numpy --with pillow python selftest.py
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import artlib as al  # noqa: E402

failures: list[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    print(("PASS " if ok else "FAIL ") + name + (f"  {detail}" if detail else ""))
    if not ok:
        failures.append(name)


# 1. CIEDE2000：Sharma, Wu & Dalal (2005) 测试数据中的三组
pairs = [
    ((50.0, 2.6772, -79.7751), (50.0, 0.0, -82.7485), 2.0425),
    ((50.0, 3.1571, -77.2803), (50.0, 0.0, -82.7485), 2.8615),
    ((50.0, 2.5, 0.0), (73.0, 25.0, -18.0), 27.1492),
]
for i, (l1, l2, expect) in enumerate(pairs):
    got = float(al.ciede2000(np.array(l1), np.array(l2)))
    check(f"ciede2000 pair {i + 1}", abs(got - expect) < 1e-3, f"got={got:.4f} expect={expect}")

# 2. sRGB→Lab：纯白 L*=100，纯黑 L*=0
lab = al.srgb_to_lab(np.array([[255, 255, 255], [0, 0, 0]]))
check("lab white/black", abs(lab[0, 0] - 100) < 0.05 and abs(lab[1, 0]) < 0.05, str(lab.round(2).tolist()))

# 3. 像素网格：随机 40×30 像素画按 3 倍 nearest 放大，应检出 k=3
rng = np.random.default_rng(7)
base = rng.integers(0, 255, size=(30, 40, 3), dtype=np.uint8)
up = np.repeat(np.repeat(base, 3, axis=0), 3, axis=1)
rgba = np.dstack([up, np.full(up.shape[:2], 255, np.uint8)])
g = al.pixel_grid(rgba, al.srgb_to_lab(rgba[..., :3]))
check("grid k=3", g["x"]["k"] == 3 and g["y"]["k"] == 3 and g["x"]["confidence"] > 0.9, str(g["x"]))

# 4. 无网格噪声图：置信度应很低
noise = rng.integers(0, 255, size=(120, 160, 3), dtype=np.uint8)
rgba_n = np.dstack([noise, np.full(noise.shape[:2], 255, np.uint8)])
g2 = al.pixel_grid(rgba_n, al.srgb_to_lab(noise))
check("grid none on noise", g2["x"]["confidence"] < 0.2, str(g2["x"]))

# 5. 缩放均匀性：1 像素美术网格在 1.5× 不均匀，2 像素网格在 1.5×/2× 均匀
check("evenness 1px@1.5 uneven", not al.scale_evenness(1, 0, 1.5)["even"])
check("evenness 2px@1.5 even", al.scale_evenness(2, 0, 1.5)["even"], str(al.scale_evenness(2, 0, 1.5)))
check("evenness 2px@2.0 even", al.scale_evenness(2, 0, 2.0)["even"])

# 6. 假棋盘格：8 像素边长的两档浅灰
yy, xx = np.mgrid[0:128, 0:128]
cb = np.where(((yy // 8 + xx // 8) % 2)[..., None] == 0, 255, 204).astype(np.uint8).repeat(3, axis=2)
ck = al.checker_pattern(cb, np.ones(cb.shape[:2], bool))
check("checker detect", ck["suspect"] and ck["dominant_run"] in (7, 8, 9), str(ck))
flat = np.full((128, 128, 3), 30, np.uint8)
check("checker none on flat", not al.checker_pattern(flat, np.ones((128, 128), bool))["suspect"])

# 7. 采样函数形状与 nearest 等价性
img = np.dstack([up, np.full(up.shape[:2], 255, np.uint8)])
check("nearest 2x shape", al.nearest_scale(img, 2.0).shape[:2] == (180, 240))
check("gpu bilinear shape", al.gpu_bilinear(img, 0.5).shape[:2] == (45, 60))

# 8. 对称：左右镜像图差异为 0
half = rng.integers(0, 255, size=(20, 10, 3), dtype=np.uint8)
sym_img = np.concatenate([half, half[:, ::-1]], axis=1)
sym_rgba = np.dstack([sym_img, np.full(sym_img.shape[:2], 255, np.uint8)])
s = al.symmetry(sym_rgba, al.srgb_to_lab(sym_img), "x")
check("symmetry x", s["alpha_mismatch"] == 0 and s["color_mismatch"] == 0, str(s))

print(f"\n{len(failures)} failure(s)")
sys.exit(1 if failures else 0)
