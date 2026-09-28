"""Claude 审查新增的素材与证据检查，并用正例与既有错例校准每项检查。

C1 满幅图标不透明；C2 长剑长度代理；C3 图标组色彩区分度（只作盲测预筛）；C4 头像四边贴合（同帧像素）；
C5 局部图内容可在整屏中找回；C6 网格覆盖层（未实现，见 CR-03）；C7 缩小倍率与 mipmap（导入、跟踪、使用处三项）；
C8 采集配置与运行配置（脚本静态规则 + 采集清单记录的拉伸与渲染器）。
每项检查都附正例与反例；只有正例通过、反例被拒绝，该检查才可用于验收。
检查结论只证明其覆盖的具体缺陷，不代替原尺寸、整屏与动态的人工看图。

运行（仓库根目录）：
    uv run --no-project --python 3.13 --with numpy --with pillow python tests/claude_review/claude_review_checks.py \
        --references <第 5 号交接包 references 目录> --hud-capture <含 available-1280.png、mixed-1280.png 的仓库外目录> \
        [--native-1920 <项目拉伸 1920 整屏>] [--manifests <capture_scene_native 清单> ...] --json <仓库外输出 json>
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SLOT_BG = (18, 14, 22)  # 技能槽底色近似值，仅用于合成显示


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rgba(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGBA"))


def lab(rgb: np.ndarray) -> np.ndarray:
    c = rgb.astype(np.float64) / 255.0
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    m = np.array([[0.4124564, 0.3575761, 0.1804375], [0.2126729, 0.7151522, 0.0721750], [0.0193339, 0.1191920, 0.9503041]])
    t = (lin @ m.T) / np.array([0.95047, 1.0, 1.08883])
    f = np.where(t > 216 / 24389, np.cbrt(t), (24389 / 27 * t + 16) / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], axis=-1)


def display(path: Path, size: int) -> np.ndarray:
    """按显示尺寸做面积降采样后合成到槽底色，近似玩家在 52 像素槽内看到的内容。"""
    im = Image.open(path).convert("RGBA").resize((size, size), Image.BOX)
    base = Image.new("RGBA", im.size, SLOT_BG + (255,))
    base.alpha_composite(im)
    return np.asarray(base.convert("RGB"))


# ---------------------------------------------------------------- C1 满幅图标不透明


def c1_icon_opacity(path: Path) -> dict:
    """满幅技能图标应在槽内完整不透明；羽化或整体半透明会让槽底透出、各图标轮廓不一。"""
    a = rgba(path)[..., 3].astype(float)
    semi = float((a < 250).mean())
    return {"file": path.name, "sha256": sha256(path), "alpha_below_250_share": round(semi, 4),
            "alpha_mean": round(float(a.mean()) / 255, 4), "pass": semi <= 0.005}


# ---------------------------------------------------------------- C2 长剑长度代理


def _shift_min_max(a: np.ndarray, r: int, op) -> np.ndarray:
    pad = np.pad(a, r, mode="edge")
    out = None
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            s = pad[r + dy : r + dy + a.shape[0], r + dx : r + dx + a.shape[1]]
            out = s if out is None else op(out, s)
    return out


def _components(mask: np.ndarray) -> list[list[tuple[int, int]]]:
    seen = np.zeros_like(mask)
    h, w = mask.shape
    found = []
    for y0 in range(h):
        for x0 in range(w):
            if not mask[y0, x0] or seen[y0, x0]:
                continue
            stack, pts = [(y0, x0)], []
            seen[y0, x0] = True
            while stack:
                y, x = stack.pop()
                pts.append((y, x))
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        ny, nx = y + dy, x + dx
                        if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            stack.append((ny, nx))
            found.append(pts)
    return found


def c2_blade_extent(path: Path, size: int = 52) -> dict:
    """在 52 像素显示下用白顶帽提取比周围更亮的细长低饱和结构（剑身），取主轴最长的连通区域，
    测量其长度占图标宽度的比例。长剑语义要求 ≥ 0.75；短刀、匕首式剑身会低于该值。"""
    rgb = display(path, size)
    lb = lab(rgb)
    lum = lb[..., 0]
    chroma = np.hypot(lb[..., 1], lb[..., 2])
    opening = _shift_min_max(_shift_min_max(lum, 3, np.minimum), 3, np.maximum)
    tophat = lum - opening
    mask = (tophat > 8) & (chroma < 30)
    best_extent, best_px = 0.0, 0
    for pts in _components(mask):
        if len(pts) < 4:
            continue
        p = np.array(pts, dtype=float)
        p -= p.mean(axis=0)
        _, vecs = np.linalg.eigh(np.cov(p.T))
        proj = p @ vecs[:, -1]
        extent = float(proj.max() - proj.min() + 1)
        if extent > best_extent:
            best_extent, best_px = extent, len(pts)
    return {"file": path.name, "sha256": sha256(path), "extent_ratio": round(best_extent / size, 3),
            "component_px": best_px, "pass": best_extent / size >= 0.75}


# ---------------------------------------------------------------- C3 图标组色彩区分度


def c3_set_color_spread(paths: list[Path]) -> dict:
    """统计每枚图标在 52 像素显示下的主色调与平均色；色调全集中在同一窄带时只能靠轮廓区分，需人工盲测。"""
    rows = []
    for p in paths:
        lb = lab(display(p, 52)).reshape(-1, 3)
        c = np.hypot(lb[:, 1], lb[:, 2])
        sat = lb[c > 12]
        hue = float(np.degrees(np.arctan2(sat[:, 2].mean(), sat[:, 1].mean())) % 360) if len(sat) else None
        rows.append({"file": p.name, "mean_L": round(float(lb[:, 0].mean()), 1), "chromatic_share": round(float((c > 12).mean()), 3),
                     "dominant_hue_deg": round(hue, 1) if hue is not None else None})
    hues = [r["dominant_hue_deg"] for r in rows if r["dominant_hue_deg"] is not None]
    span = 0.0
    if len(hues) > 1:
        ordered = sorted(hues)
        gaps = [ordered[i + 1] - ordered[i] for i in range(len(ordered) - 1)] + [360 - ordered[-1] + ordered[0]]
        span = 360 - max(gaps)
    return {"icons": rows, "hue_span_deg": round(span, 1), "needs_blind_semantic_review": span < 45}


# ---------------------------------------------------------------- C4 头像四边贴合（像素）


PORTRAIT_FRAME_1280 = (43, 608, 74, 84)  # 与 tests/capture_hud_final_acceptance.gd 的比较区域一致


def _brass(line: np.ndarray) -> bool:
    """黄铜边框线（受光面或压暗面）：整行平均为暖色、明度中高。实测 1280 下受光面约 (172,147,103)，压暗面约 (85,65,48)。"""
    r, g, b = line[..., 0].mean(), line[..., 1].mean(), line[..., 2].mean()
    return r > 60 and g > 40 and r - b > 20


def _frame_edge(line: np.ndarray) -> bool:
    """黄铜线内侧的暗棕描边，属于画框本身。实测约 (68,57,51)；头像边缘行因红发与深色服装，平均 G 远低于 40。"""
    r, g = line[..., 0].mean(), line[..., 1].mean()
    return r > 45 and g > 40


def c4_portrait_edges(img: np.ndarray, name: str, frame_rect_1280=PORTRAIT_FRAME_1280) -> dict:
    """在同一整屏中检查头像框四边：先在预期位置附近找到黄铜边框线，再数紧贴其内侧、整行（列）都是面板底色的行数。

    画框区域按项目拉伸的缩放系数 s=min(宽/1280, 高/720) 从 1280 基准换算；由于先定位黄铜线，换算取整不会造成误判。
    """
    h_img, w_img = img.shape[:2]
    s = min(w_img / 1280, h_img / 720)
    x, y, w, h = (int(round(v * s)) for v in frame_rect_1280)
    inset = max(4, int(round(6 * s)))
    panel = img[y + h // 2, x - int(round(6 * s))]  # 画框外侧面板底色
    search = int(round(4 * s)) + 2

    def line_at(side: str, k: int) -> np.ndarray:
        if side == "top":
            return img[y + k, x + inset : x + w - inset]
        if side == "bottom":
            return img[y + h - 1 - k, x + inset : x + w - inset]
        if side == "left":
            return img[y + inset : y + h - inset, x + k]
        return img[y + inset : y + h - inset, x + w - 1 - k]

    report, border = {}, {}
    for side in ("top", "bottom", "left", "right"):
        ks = [k for k in range(-search, search + 1) if _brass(line_at(side, k))]
        if not ks:
            report[side], border[side] = None, None
            continue
        last = max(ks)  # 最靠内的一条黄铜线
        k = last + 1
        while k < last + search * 2 and _frame_edge(line_at(side, k)) and not _brass(line_at(side, k)):
            k += 1  # 跳过画框内侧暗棕描边
        # 在遇到头像内容行（平均 R 明显高于 B；面板底色则是 B > R）之前，底色占比 ≥ 0.5 的行都算作缝，
        # 这样 1.5×/2× 下被混合成半像素的缝也会计入。
        gap = 0
        while k < last + 1 + search * 3:
            line = line_at(side, k)
            if float((np.abs(line - panel).max(axis=-1) <= 10).mean()) >= 0.5:
                gap += 1
            elif line[..., 0].mean() - line[..., 2].mean() > 15:
                break
            else:
                break
            k += 1
        report[side], border[side] = gap, last
    ok = all(v == 0 for v in report.values())
    return {"capture": name, "scale": round(s, 3), "panel_colour_rows": report, "brass_offset": border, "pass": ok}


def c4_file(capture: Path) -> dict:
    out = c4_portrait_edges(np.asarray(Image.open(capture).convert("RGB")).astype(int), capture.name)
    out["sha256"] = sha256(capture)
    return out


def c4_positive_fixture(capture: Path) -> dict:
    """正例：把头像第一条内容行复制到顶部底色缝上，代表“四边贴合”的修正结果。"""
    img = np.asarray(Image.open(capture).convert("RGB")).astype(int).copy()
    x, y, w, h = PORTRAIT_FRAME_1280
    img[611, x + 4 : x + w - 4] = img[612, x + 4 : x + w - 4]
    return c4_portrait_edges(img, capture.name + " + 顶缝修正（合成正例）")


# ---------------------------------------------------------------- C5 局部图与整屏同帧


def c5_detail_from_frame(frame: Path, detail: Path | np.ndarray, scale: int = 4) -> dict:
    """局部放大图的内容必须能在声称的整屏中按 nearest 逐像素找回。

    这证明细节画面确实存在于该整屏中，可以作为它的细节证据；它不能区分内容完全相同的两个不同帧，
    因此采集清单仍须记录源帧 SHA256、区域与倍数（CR-25）。
    """
    f = np.asarray(Image.open(frame).convert("RGB")).astype(np.int16)
    d = (np.asarray(Image.open(detail).convert("RGB")) if isinstance(detail, Path) else detail).astype(np.int16)
    detail_name = detail.name if isinstance(detail, Path) else "内存中的合成细节"
    small = d[scale // 2 :: scale, scale // 2 :: scale]
    sh, sw = small.shape[:2]
    best = (1e9, None)
    probe = small[sh // 2, sw // 2]
    ys, xs = np.nonzero((np.abs(f - probe).max(axis=-1) == 0))
    for yy, xx in zip(ys, xs):
        oy, ox = yy - sh // 2, xx - sw // 2
        if oy < 0 or ox < 0 or oy + sh > f.shape[0] or ox + sw > f.shape[1]:
            continue
        err = float(np.abs(f[oy : oy + sh, ox : ox + sw] - small).mean())
        if err < best[0]:
            best = (err, (int(ox), int(oy)))
            if err == 0:
                break
    return {"frame": frame.name, "detail": detail_name, "best_mean_abs_error": round(best[0], 3) if best[1] else None,
            "probe_found": best[1] is not None, "offset": best[1], "pass": best[0] == 0.0}


def c5_state_mismatch_detail(src_frame: Path, box=(500, 548, 820, 600), scale: int = 4) -> np.ndarray:
    """反例素材：从“部分消耗”整屏裁出行动条并放大，拿去对照“全部可用”整屏。两帧布局相同、状态不同。"""
    crop = Image.open(src_frame).convert("RGB").crop(box)
    return np.asarray(crop.resize((crop.width * scale, crop.height * scale), Image.NEAREST))


# ---------------------------------------------------------------- C7 缩小倍率与 mipmap


# CanvasItem.TextureFilter：0 继承、1 NEAREST、2 LINEAR、3 NEAREST_WITH_MIPMAPS、4 LINEAR_WITH_MIPMAPS、5/6 对应各向异性版本
CANVAS_FILTER_NAMES = {"PARENT_NODE": 0, "NEAREST": 1, "LINEAR": 2, "NEAREST_WITH_MIPMAPS": 3, "LINEAR_WITH_MIPMAPS": 4,
                       "NEAREST_WITH_MIPMAPS_ANISOTROPIC": 5, "LINEAR_WITH_MIPMAPS_ANISOTROPIC": 6}
# 项目设置 rendering/textures/canvas_textures/default_texture_filter：0 Nearest、1 Linear、2 Linear Mipmap、3 Nearest Mipmap
PROJECT_FILTER_MIPMAP = {2, 3}


def _strip_comment(line: str, marker: str) -> str:
    return line.split(marker, 1)[0]


def project_default_filter(project_text: str) -> int:
    m = re.search(r"^textures/canvas_textures/default_texture_filter=(\d+)", project_text, re.M)
    return int(m.group(1)) if m else 1


def importer_defaults_mipmaps(project_text: str) -> bool:
    sec = re.search(r"^\[importer_defaults\](.*?)(?=^\[|\Z)", project_text, re.M | re.S)
    return bool(sec and re.search(r'texture\s*=\s*\{[^}]*"mipmaps/generate"\s*:\s*true', sec.group(1), re.S))


def usage_filter(spec: dict, files: dict, project_text: str) -> dict:
    """按资产精确定位使用处并解析过滤方式；注释不参与判定；没有显式设置时沿父级继承到项目默认值。"""
    kind, text = spec["kind"], files.get(spec["file"])
    if text is None:
        return {"resolved": None, "samples_mipmaps": False, "detail": "使用处文件不存在"}
    value, detail = None, ""
    if kind == "gd":
        lines = text.splitlines()
        start = 0
        if spec.get("block"):
            idx = [i for i, ln in enumerate(lines) if spec["block"] in _strip_comment(ln, "#")]
            if not idx:
                return {"resolved": None, "samples_mipmaps": False, "detail": "找不到定位语句"}
            start = idx[0]
        for ln in lines[start : start + spec.get("window", len(lines))]:
            code = _strip_comment(ln, "#")
            if re.search(spec["pattern"], code):
                m = re.search(r"TEXTURE_FILTER_([A-Z_]+)", code) or re.search(r"=\s*(\d+)\s*$", code)
                value = CANVAS_FILTER_NAMES.get(m.group(1), None) if m and not m.group(1).isdigit() else (int(m.group(1)) if m else None)
                detail = code.strip()
                break
        if value is None and spec.get("inherit_if_absent"):
            value = 0
    elif kind == "tscn":
        block = re.search(r'\[node name="%s"[^\]]*\](.*?)(?=^\[|\Z)' % re.escape(spec["node"]), text, re.M | re.S)
        if block is None:
            return {"resolved": None, "samples_mipmaps": False, "detail": "找不到节点"}
        m = re.search(r"^texture_filter = (\d+)", block.group(1), re.M)
        value = int(m.group(1)) if m else 0
        detail = f'节点 {spec["node"]} texture_filter = {value}'
    elif kind == "shader":
        for ln in text.splitlines():
            code = _strip_comment(ln, "//")
            if re.search(spec["pattern"], code):
                hints = code.split(":", 1)[1] if ":" in code else ""
                mip = bool(re.search(r"filter_(nearest|linear)_mipmap", hints))
                return {"resolved": "shader:" + hints.strip().rstrip(";"), "samples_mipmaps": mip, "detail": code.strip()}
        return {"resolved": None, "samples_mipmaps": False, "detail": "找不到 uniform"}
    if value == 0:
        pd = project_default_filter(project_text)
        return {"resolved": f"继承 → 项目默认 {pd}", "samples_mipmaps": pd in PROJECT_FILTER_MIPMAP, "detail": detail or "未显式设置"}
    if value is None:
        return {"resolved": None, "samples_mipmaps": False, "detail": "未找到过滤设置"}
    return {"resolved": value, "samples_mipmaps": value in (3, 4, 5, 6), "detail": detail}


def c7_rule(scale: float, import_text: str | None, import_tracked: bool, usage: dict, project_text: str) -> dict:
    """缩小到 0.5 倍以下时，必须同时满足：导入生成 mipmap；导入设置能进入发布（.import 已跟踪，或未跟踪但
    project.godot 的 [importer_defaults] 让全新导入生成 mipmap）；使用处的实际过滤方式采样 mipmap。"""
    if scale >= 0.5:
        return {"display_over_source": round(scale, 3), "needs_mipmaps": False, "pass": True}
    local_mip = bool(import_text and re.search(r"^mipmaps/generate=true", import_text, re.M))
    defaults_mip = importer_defaults_mipmaps(project_text)
    persisted = (import_tracked and local_mip) or (not import_tracked and defaults_mip)
    reasons = []
    if import_text is None and not defaults_mip:
        reasons.append("缺少 .import 文件，且没有 importer_defaults")
    elif not persisted:
        reasons.append("能进入发布的导入设置没有生成 mipmap" if import_tracked or defaults_mip else ".import 未跟踪且没有 importer_defaults，修改不会进入发布")
    if not usage.get("samples_mipmaps"):
        reasons.append(f"使用处过滤方式不采样 mipmap（{usage.get('resolved')}）")
    return {"display_over_source": round(scale, 3), "needs_mipmaps": True, "import_tracked": import_tracked,
            "local_import_mipmaps": local_mip, "importer_defaults_mipmaps": defaults_mip,
            "usage": usage, "reasons": reasons, "pass": not reasons}


def _git_tracked(rel: str) -> bool:
    import subprocess
    r = subprocess.run(["git", "-C", str(ROOT), "ls-files", "--error-unmatch", rel], capture_output=True)
    return r.returncode == 0


BOARD = "scripts/ui/playground/courtyard_board_view.gd"
PROPS = {"kind": "gd", "file": BOARD, "block": 'root.name = "CourtyardProp"', "window": 4, "pattern": r"root\.texture_filter\s*="}
WALLS = {"kind": "gd", "file": BOARD, "block": 'root.name = "CourtyardWall"', "window": 5, "pattern": r"root\.texture_filter\s*="}
BOARD_ROOT = {"kind": "gd", "file": BOARD, "pattern": r"^\ttexture_filter\s*="}
SHADER = "scripts/ui/terrain/terrain_blend.gdshader"
# 显示倍率 = 屏幕像素 / 纹素，取主要用法中的最差轴向（推算依据见报告 §3.1 与 CR-01）
C7_CASES = [
    ("assets/units/kensei/map_token_clean_v2.png", 80 / 512, {"kind": "gd", "file": "scripts/units/map_token_view.gd", "pattern": r"^\s*texture_filter\s*="}),
    ("assets/ui/skins/hud_mark_crest/marks-filled-generated.png", 52 / 586,
     {"kind": "gd", "file": "scripts/ui/hud/m2/marks_panel.gd", "pattern": r"glyph\.texture_filter\s*=", "inherit_if_absent": True}),
    ("assets/ui/portraits/kensei_hud_portrait_generated.png", 78 / 735, {"kind": "tscn", "file": "scenes/tactical/hud/m2/character_hud_panel.tscn", "node": "PortraitContent"}),
    ("assets/ui/portraits/myrmidon_hud_portrait_generated.png", 78 / 735, {"kind": "tscn", "file": "scenes/tactical/hud/m2/character_hud_panel.tscn", "node": "PortraitContent"}),
    ("assets/prototype/battlefield_courtyard/forest-tree-v2.png", 57.7 / 950, PROPS),
    ("assets/prototype/battlefield_courtyard/shrub-v1.png", 41.6 / 700, PROPS),
    ("assets/prototype/battlefield_courtyard/low-rubble-v1.png", 11.9 / 496, PROPS),
    ("assets/prototype/battlefield_courtyard/courtyard-entry-v2.png", 116.7 / 745, PROPS),
    ("assets/prototype/battlefield_courtyard/masonry-wall-v2.png", 0.92 / 22.36, WALLS),
    ("assets/prototype/battlefield_courtyard/water-surface-v5.png", 0.92 / 6.93, BOARD_ROOT),
    ("assets/prototype/battlefield_courtyard/meadow-ground-v2.png", 0.92 / 6.93, {"kind": "shader", "file": SHADER, "pattern": r"uniform sampler2D meadow"}),
    ("assets/prototype/battlefield_courtyard/moss-ground-v1.png", 0.92 / 6.93, {"kind": "shader", "file": SHADER, "pattern": r"uniform sampler2D moss"}),
    ("assets/prototype/battlefield_courtyard/stone-ground-v1.png", 0.92 / 6.93, {"kind": "shader", "file": SHADER, "pattern": r"uniform sampler2D paving"}),
    ("assets/prototype/battlefield_courtyard/natural-rock-v1.png", 0.92 / 10.1, {"kind": "shader", "file": SHADER, "pattern": r"uniform sampler2D rock"}),
    ("assets/ui/skills/myrmidon/zhanji.png", 52 / 104, {"kind": "tscn", "file": "scenes/tactical/hud/m2/skill_slot_button.tscn", "node": "Icon"}),
    ("assets/ui/skins/hud_m2_fe/shared-frame.png", 1.0, {"kind": "gd", "file": "scripts/ui/hud/m2/shared_frame_style.gd", "pattern": r"texture_filter"}),
]


def _read_files(paths) -> dict:
    out = {}
    for p in paths:
        fp = ROOT / p
        out[p] = fp.read_text(encoding="utf-8") if fp.exists() else None
    return out


def c7_minification(rel: str, scale: float, spec: dict, files: dict, project_text: str) -> dict:
    imp_path = ROOT / (rel + ".import")
    import_text = imp_path.read_text(encoding="utf-8") if imp_path.exists() else None
    out = c7_rule(scale, import_text, _git_tracked(rel + ".import"), usage_filter(spec, files, project_text), project_text)
    out.update({"file": rel, "usage_spec": {k: v for k, v in spec.items() if k != "pattern"}})
    return out


def c7_calibration(files: dict, project_text: str) -> dict:
    """用真实文件做内存改写来校准：正确修法必须通过，只改注释、只改一处或整数值写法等错误修法必须被拒绝。"""
    token_view = "scripts/units/map_token_view.gd"
    tscn = "scenes/tactical/hud/m2/character_hud_panel.tscn"
    token_spec = C7_CASES[0][2]
    portrait_spec = C7_CASES[2][2]
    imp_ok = "[params]\nmipmaps/generate=true\n"
    fixed_token = dict(files, **{token_view: files[token_view].replace("TEXTURE_FILTER_LINEAR", "TEXTURE_FILTER_LINEAR_WITH_MIPMAPS")})
    comment_only = dict(files, **{token_view: files[token_view] + "\n# texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS\n"})
    portrait_int4 = dict(files, **{tscn: re.sub(r'(\[node name="PortraitContent".*?\ntexture_filter = )2', r"\g<1>4", files[tscn], flags=re.S)})
    walls_only = dict(files, **{BOARD: re.sub(r'(root\.name = "CourtyardWall"(?:.*\n){1,4}?\s*root\.texture_filter = CanvasItem\.TEXTURE_FILTER_)NEAREST',
                                              r"\g<1>LINEAR_WITH_MIPMAPS", files[BOARD])})
    defaults_project = project_text + '\n[importer_defaults]\n\ntexture={\n"mipmaps/generate": true\n}\n'
    shader_fixed = dict(files, **{SHADER: files[SHADER].replace("uniform sampler2D meadow : source_color, filter_linear,", "uniform sampler2D meadow : source_color, filter_linear_mipmap,")})
    cases = {
        "正例：棋子改为 LINEAR_WITH_MIPMAPS，导入已跟踪且开 mipmap": c7_rule(0.156, imp_ok, True, usage_filter(token_spec, fixed_token, project_text), project_text),
        "反例：只在注释里写 LINEAR_WITH_MIPMAPS": c7_rule(0.156, imp_ok, True, usage_filter(token_spec, comment_only, project_text), project_text),
        "正例：头像场景以整数 4 保存": c7_rule(0.106, imp_ok, True, usage_filter(portrait_spec, portrait_int4, project_text), project_text),
        "反例：头像场景仍为整数 2": c7_rule(0.106, imp_ok, True, usage_filter(portrait_spec, files, project_text), project_text),
        "反例：只改墙体，道具仍为 NEAREST": c7_rule(0.061, imp_ok, True, usage_filter(PROPS, walls_only, project_text), project_text),
        "正例：墙体改为 LINEAR_WITH_MIPMAPS": c7_rule(0.041, imp_ok, True, usage_filter(WALLS, walls_only, project_text), project_text),
        "正例：.import 未跟踪但 importer_defaults 开 mipmap": c7_rule(0.156, None, False, usage_filter(token_spec, fixed_token, defaults_project), defaults_project),
        "反例：.import 未跟踪且没有 importer_defaults": c7_rule(0.156, imp_ok, False, usage_filter(token_spec, fixed_token, project_text), project_text),
        "正例：着色器改为 filter_linear_mipmap": c7_rule(0.133, imp_ok, True, usage_filter(C7_CASES[10][2], shader_fixed, project_text), project_text),
        "反例：着色器仍为 filter_linear": c7_rule(0.133, imp_ok, True, usage_filter(C7_CASES[10][2], files, project_text), project_text),
        "正例：显示倍率 ≥ 0.5 不需要 mipmap": c7_rule(0.5, None, False, {}, project_text),
    }
    ok = all(v["pass"] for k, v in cases.items() if k.startswith("正例")) and not any(v["pass"] for k, v in cases.items() if k.startswith("反例"))
    return {"cases": cases, "calibration_ok": ok}


# ---------------------------------------------------------------- C8 采集配置与运行配置


def _doc_header(text: str) -> str:
    """仅接受首次声明之前的文件头；允许 extends 位于注释前后。"""
    lines = []
    for ln in text.splitlines():
        stripped = ln.strip()
        if stripped.startswith("##"):
            lines.append(stripped)
        elif not stripped or stripped.startswith("#") or stripped.startswith("extends "):
            continue
        else:
            break
    return "\n".join(lines)


def c8_rule(text: str) -> dict:
    """在函数体顶层（一级缩进）无条件关闭项目拉伸、又没有在 `##` 文件头声明“不代表运行配置”的采集脚本不合格。
    嵌套在条件分支内的关闭（二级及以上缩进）视为可选对照模式，由其采集清单记录的实际参数判定。"""
    unconditional, conditional = [], []
    for i, ln in enumerate(text.splitlines(), 1):
        code = ln.split("#", 1)[0]
        if re.search(r"content_scale_mode\s*=\s*Window\.CONTENT_SCALE_MODE_DISABLED", code):
            depth = len(ln) - len(ln.lstrip("\t"))
            (unconditional if depth <= 1 else conditional).append(i)
    declared = "不代表运行配置" in _doc_header(text)
    return {"unconditional_disable_lines": unconditional, "conditional_disable_lines": conditional,
            "declared_not_runtime": declared, "pass": not unconditional or declared}


def c8_script(script: Path) -> dict:
    out = c8_rule(script.read_text(encoding="utf-8"))
    out["script"] = str(script.relative_to(ROOT)).replace("\\", "/")
    return out


def c8_manifest(manifest: Path) -> dict:
    """验证采集配置和图片身份；接受原生采集清单及统一伴随清单。"""
    project = (ROOT / "project.godot").read_text(encoding="utf-8")
    m = re.search(r'^renderer/rendering_method="([^"]+)"', project, re.M)
    project_renderer = m.group(1) if m else "forward_plus"
    sm = re.search(r'^window/stretch/mode="([^"]+)"', project, re.M)
    stretch = sm.group(1) if sm else "disabled"
    expected_mode = {"disabled": 0, "canvas_items": 1, "viewport": 2}.get(stretch)
    vw = re.search(r"^window/size/viewport_width=(\d+)", project, re.M)
    vh = re.search(r"^window/size/viewport_height=(\d+)", project, re.M)
    expected_size = [int(vw.group(1)) if vw else 1152, int(vh.group(1)) if vh else 648]
    bad = []
    data = {}
    try:
        data = json.loads(manifest.read_text(encoding="utf-8-sig"))
        if not isinstance(data, dict):
            raise ValueError("清单根必须为对象")
    except (OSError, ValueError) as error:
        return {"manifest": manifest.name, "pass": False, "mismatches": [str(error)]}
    if data.get("runtime_evidence") is False:
        bad.append("固定像素诊断清单不能作为运行视觉验收证据")
    if data.get("renderer") != project_renderer:
        bad.append(f"渲染器 {data.get('renderer')} ≠ 项目默认 {project_renderer}")
    if data.get("project_stretch_mode") != stretch:
        bad.append("缺少或不匹配项目拉伸模式")
    captures = data.get("captures")
    if not isinstance(captures, list) or not captures:
        bad.append("采集记录必须为非空数组")
        captures = []
    names, viewport_count = set(), 0

    def finite_number(value):
        return type(value) in (int, float) and math.isfinite(value)

    def positive_pair(value):
        return isinstance(value, list) and len(value) == 2 and all(finite_number(v) and v > 0 for v in value)

    def image_file(name, digest):
        if not isinstance(name, str) or not name or Path(name).is_absolute() or ".." in Path(name).parts:
            raise ValueError("图片路径必须为清单目录下的相对路径")
        path = manifest.parent / name
        if not path.resolve().is_relative_to(manifest.parent.resolve()):
            raise ValueError("图片路径超出清单目录")
        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
            raise ValueError("缺少有效SHA256")
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError("图片SHA256不匹配")
        with Image.open(path) as image:
            return list(image.size)

    for cap in captures:
        if not isinstance(cap, dict):
            bad.append("采集项必须为对象")
            continue
        name = cap.get("file")
        try:
            size = image_file(name, cap.get("sha256"))
            if name in names:
                raise ValueError("重复图片记录")
            names.add(name)
            if not positive_pair(cap.get("image_size")) or cap.get("image_size") != size:
                raise ValueError("记录尺寸与图片实际尺寸不同")
            if type(cap.get("content_scale_mode")) is not int or cap.get("content_scale_mode") != expected_mode or (expected_mode and cap.get("content_scale_size") != expected_size):
                raise ValueError("拉伸参数与项目不同")
            if cap.get("renderer", data.get("renderer")) != project_renderer or cap.get("project_stretch_mode", stretch) != stretch:
                raise ValueError("单张采集配置与项目不同")
            window, visible = cap.get("window_size"), cap.get("visible_rect")
            if not positive_pair(window) or not isinstance(visible, list) or len(visible) not in (2, 4) or not all(finite_number(v) for v in visible) or not positive_pair(visible[-2:]):
                raise ValueError("缺少有效窗口或可见区域尺寸")
            kind = cap.get("capture_kind", "viewport")
            if kind == "viewport":
                viewport_count += 1
                if size != (expected_size if expected_mode == 2 else window):
                    raise ValueError("整屏尺寸与实际视口配置不符")
            elif kind == "derived_detail":
                source_size = image_file(cap.get("source_file"), cap.get("source_sha256"))
                region = cap.get("source_region")
                scale = cap.get("scale")
                if (not isinstance(region, list) or len(region) != 4 or not all(finite_number(v) for v in region)
                        or not positive_pair(region[-2:]) or not finite_number(scale) or scale <= 0):
                    raise ValueError("派生细节缺少有效母帧区域或放大参数")
                if region[0] < 0 or region[1] < 0 or region[0] + region[2] > source_size[0] or region[1] + region[3] > source_size[1]:
                    raise ValueError("派生区域超出母帧")
            else:
                raise ValueError("未知采集类型")
        except (OSError, ValueError, TypeError) as error:
            bad.append(f"{name}：{error}")
    if not viewport_count:
        bad.append("清单没有有效整屏采集记录")
    return {"manifest": manifest.name, "project_renderer": project_renderer, "renderer": data.get("renderer"),
            "capture_count": len(captures), "mismatches": bad, "pass": not bad}


def c8_scripts() -> list[dict]:
    """包含已修复的采集脚本，避免仅检查仍有禁用语句的脚本。"""
    paths = sorted((ROOT / "tests").rglob("*.gd")) + sorted((ROOT / "dev_doc").rglob("capture_*.gd"))
    return [c8_script(p) for p in paths if any(token in p.read_text(encoding="utf-8")
            for token in ("save_png", "CONTENT_SCALE_MODE_DISABLED", "CaptureMetadata"))]


def c8_calibration() -> dict:
    """用三个合成脚本校准：声明过的关闭可通过；注释里写了关键字但无条件关闭仍拒绝；嵌套在条件分支的关闭交给清单判定。"""
    declared = "## 仅用于固定像素几何的单元测试，不代表运行配置。\nextends SceneTree\nfunc _run() -> void:\n\troot.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED\n"
    comment_trick = "extends SceneTree\n# 这里 stretch == \"disabled\"\nfunc _run() -> void:\n\troot.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED\n"
    conditional = "extends SceneTree\nfunc _run() -> void:\n\tif _mode == \"legacy\":\n\t\troot.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED\n"
    cases = {"正例：文件头已声明": c8_rule(declared), "反例：注释含关键字但无条件关闭": c8_rule(comment_trick),
             "正例：条件分支内的对照模式": c8_rule(conditional)}
    ok = cases["正例：文件头已声明"]["pass"] and cases["正例：条件分支内的对照模式"]["pass"] and not cases["反例：注释含关键字但无条件关闭"]["pass"]
    return {"cases": cases, "calibration_ok": ok}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--references", type=Path)
    ap.add_argument("--c8-only", action="store_true", help="仅运行采集配置检查；必须提供实际清单")
    ap.add_argument("--hud-capture", type=Path, help="含 available-1280.png、mixed-1280.png 的仓库外目录")
    ap.add_argument("--native-1920", type=Path, help="capture_scene_native.gd 保留项目拉伸的 1920×1080 整屏")
    ap.add_argument("--manifests", type=Path, nargs="*", help="capture_scene_native.gd 生成的采集清单")
    ap.add_argument("--json", type=Path, required=True)
    args = ap.parse_args()
    if args.c8_only:
        if not args.manifests:
            ap.error("--c8-only 必须提供 --manifests")
        result = {"scripts": c8_scripts(), "manifests": [c8_manifest(p) for p in args.manifests],
                  "calibration": c8_calibration()}
        result["pass"] = bool(result["scripts"]) and result["calibration"]["calibration_ok"] and all(
            item["pass"] for item in result["scripts"] + result["manifests"])
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps({"pass": result["pass"], "scripts": len(result["scripts"]), "manifests": len(result["manifests"])}, ensure_ascii=False))
        return 0 if result["pass"] else 1
    if not args.references or not args.hud_capture:
        ap.error("完整检查必须提供 --references 和 --hud-capture")
    icons = ROOT / "assets/ui/skills/myrmidon"
    src = ROOT / "dev_doc/ui-art-research/myrmidon-skill-icons/candidate-v3"
    ev = ROOT / "dev_doc/ui-art-research"
    out: dict = {"repository_head_note": "以运行时工作树文件为准", "checks": {}}

    c1 = {n: c1_icon_opacity(icons / f"{n}.png") for n in ("juhe", "xinyan", "yishan", "zhanji", "zhaojia")}
    out["checks"]["C1_icon_opacity"] = {"cases": c1, "calibration": {
        "positive_juhe_passes": c1["juhe"]["pass"], "negative_yishan_rejected": not c1["yishan"]["pass"]}}

    c2_pos = c2_blade_extent(src / "juhe-source.png")
    c2_neg = c2_blade_extent(args.references / "juhe-before-length-correction.png")
    out["checks"]["C2_long_blade_extent"] = {"positive_final_juhe": c2_pos, "negative_before_length_correction": c2_neg,
                                             "calibration_ok": c2_pos["pass"] and not c2_neg["pass"]}

    current = [src / f"{n}-source.png" for n in ("xinyan", "zhanji", "yishan", "zhaojia", "juhe")]
    out["checks"]["C3_icon_set_color_spread"] = c3_set_color_spread(current)

    hud = args.hud_capture
    out["checks"]["C4_portrait_edges"] = {
        "negative_claude_capture_1280": c4_file(hud / "available-1280.png"),
        "negative_codex_evidence_1280": c4_file(ev / "hud-final-acceptance/evidence/available-1280.png"),
        "positive_fixture_gap_filled": c4_positive_fixture(hud / "available-1280.png"),
    }
    if args.native_1920 and args.native_1920.exists():
        out["checks"]["C4_portrait_edges"]["project_stretch_1920"] = c4_file(args.native_1920)
    c4 = out["checks"]["C4_portrait_edges"]
    c4["calibration_ok"] = c4["positive_fixture_gap_filled"]["pass"] and not c4["negative_claude_capture_1280"]["pass"]

    pairs = [
        (ev / "hud-myrmidon-portrait/candidate/combat-1280.png", ev / "hud-myrmidon-portrait/candidate/portrait-detail-4x.png"),
        (ev / "hud-myrmidon-portrait/candidate/combat-1280.png", ev / "hud-myrmidon-portrait/candidate/end-turn-detail-4x.png"),
        (ev / "hud-character-panel-portrait/candidate/hover-1280.png", ev / "hud-character-panel-portrait/candidate/portrait-detail-4x.png"),
        (ev / "hud-character-panel-portrait/candidate/hover-1280-generated.png", ev / "hud-character-panel-portrait/candidate/portrait-detail-4x-generated.png"),
    ]
    c5 = [c5_detail_from_frame(f, d) for f, d in pairs if f.exists() and d.exists()]
    # 反例 1：重生成版头像细节配给原画版整屏（内容不存在于该帧）
    neg_pair = c5_detail_from_frame(pairs[2][0], pairs[3][1])
    # 反例 2：同一布局、不同状态——“部分消耗”行动条细节对照“全部可用”整屏（探针存在，内容不同）
    neg_state = c5_detail_from_frame(hud / "available-1280.png", c5_state_mismatch_detail(hud / "mixed-1280.png"))
    out["checks"]["C5_detail_in_frame"] = {"cases": c5, "negative_mismatched_pair": neg_pair, "negative_state_mismatch": neg_state,
                                           "calibration_ok": all(r["pass"] for r in c5) and not neg_pair["pass"] and not neg_state["pass"]}

    out["checks"]["C6_grid_overlay"] = {"status": "未实现", "note": "网格覆盖层渲染检查（顶点与边中点亮度），按 CR-03 验收第 1 条由实施方加入。"}

    project_text = (ROOT / "project.godot").read_text(encoding="utf-8")
    files = _read_files({spec["file"] for _, _, spec in C7_CASES})
    out["checks"]["C7_minification"] = {
        "cases": [c7_minification(rel, scale, spec, files, project_text) for rel, scale, spec in C7_CASES],
        "calibration": c7_calibration(files, project_text),
    }

    capture_scripts = c8_scripts()
    manifests = [c8_manifest(p) for p in sorted(args.manifests)] if args.manifests else []
    out["checks"]["C8_capture_config"] = {"scripts": capture_scripts, "manifests": manifests, "calibration": c8_calibration()}

    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
