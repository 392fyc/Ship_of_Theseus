"""SoT 素材机械审计：文件身份、透明通道、边缘污染、假棋盘格、像素网格、色板、明度、对称与缩放均匀性。

用法示例：
    uv run --no-project --python 3.13 --with numpy --with pillow python art_audit.py \
        --profile ui --ref-palette ../references/palette-anchor.json --json out.json --md out.md a.png b.png

只读取输入；机械结论只是证据，不能替代原生尺寸下的人工视觉审查。
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import artlib as al  # noqa: E402

# 类型预期来自 Ship 的 sample_manifest.json v3 与 KB 视觉裁决；阈值是初版经验值，按审核记录再校准。
PROFILES = {
    "ui": {"alpha_required": True, "crisp": True, "filter": "nearest", "grid_expected": True},
    "icon": {"alpha_required": True, "crisp": True, "filter": "nearest", "grid_expected": True},
    "terrain": {"alpha_required": True, "crisp": True, "filter": "nearest", "grid_expected": True},
    "vfx": {"alpha_required": True, "crisp": True, "filter": "nearest", "grid_expected": False},
    "vfx_glow": {"alpha_required": True, "crisp": False, "filter": "linear", "grid_expected": False},
    "portrait": {"alpha_required": True, "crisp": False, "filter": "nearest", "grid_expected": False},
    "portrait_crop": {"alpha_required": False, "crisp": False, "filter": "linear", "grid_expected": False},
    "map_token": {"alpha_required": True, "crisp": False, "filter": "linear", "grid_expected": False},
    "capture": {"alpha_required": False, "crisp": False, "filter": "n/a", "grid_expected": False},
    "generic": {"alpha_required": False, "crisp": False, "filter": "n/a", "grid_expected": False},
}

SCREEN_SCALES = (1.5, 2.0)  # 以 1280×720 为基准：1920×1080 = 1.5×，2560×1440 = 2×


def flag(level: str, code: str, message: str) -> dict:
    return {"level": level, "code": code, "message": message}


def audit_file(path: Path, profile_name: str, ref_palette: list[str] | None, args) -> dict:
    profile = PROFILES[profile_name]
    rgba, info = al.load_rgba(path)
    lab = al.srgb_to_lab(rgba[..., :3])
    report: dict = {
        "file": str(path).replace("\\", "/"),
        "sha256": al.sha256_file(path),
        "bytes": path.stat().st_size,
        "pixel_size": info["size"],
        "mode": info["mode"],
        "profile": profile_name,
    }
    flags: list[dict] = []

    # ---- 透明通道
    ap = al.alpha_profile(rgba)
    report["alpha"] = ap
    if profile["alpha_required"] and (not info["has_alpha_channel"] or ap["fully_opaque"]):
        flags.append(flag("FAIL", "alpha.missing", "该类型要求真实透明通道，但文件没有 alpha 或完全不透明。"))
    if profile["crisp"] and ap["semi_ratio_of_visible"] > 0.005:
        flags.append(
            flag(
                "WARN",
                "alpha.semi",
                f"可见像素中 {ap['semi_ratio_of_visible']:.1%} 为半透明；nearest 像素件通常应为二值 alpha，"
                "需确认是否为抗锯齿导出、柔边残留或应拆出的光晕层。",
            )
        )

    # ---- alpha=0 残留 RGB
    if ap["transparent_ratio"] > 0:
        hr = al.hidden_rgb_profile(rgba, lab)
        report["hidden_rgb"] = hr
        if hr.get("checker_like"):
            flags.append(
                flag(
                    "INFO",
                    "hidden.checker",
                    "透明区底下残留棋盘格 RGB：来源图曾把“透明”画成棋盘格，清理只改了 alpha。忽略 alpha 的查看器会显示棋盘格；"
                    "Linear 过滤或 mipmap 时依赖 Godot 的 Fix Alpha Border 防止浅色渗边，导入设置需保持开启。",
                )
            )
        elif hr.get("light_rgb_share", 0) > 0.2 and profile["filter"] == "linear":
            flags.append(flag("WARN", "hidden.light", "Linear 过滤素材的透明区残留大量浅色 RGB，缩放时可能渗出浅色边。"))

    # ---- 边缘污染
    if ap["transparent_ratio"] > 0:
        ef = al.edge_fringe(rgba, lab)
        report["edge_fringe"] = ef
        if ef.get("edge_near_white_share", 0) > 0.15 and ef.get("edge_minus_inner_L", 0) > 12:
            flags.append(
                flag("WARN", "edge.white_fringe", "外轮廓一圈明显偏白偏亮，疑似白底抠图残边；需在深色与品红底上目检。")
            )
        if ef.get("semi_light_share", 0) > 0.3:
            flags.append(flag("WARN", "edge.semi_white", "半透明像素中浅中性色占比高，疑似白色半透明雾边。"))

    # ---- 可见区假棋盘格
    vis = rgba[..., 3] >= 128
    ck = al.checker_pattern(rgba[..., :3], vis)
    report["visible_checker"] = ck
    if ck.get("suspect"):
        flags.append(flag("FAIL", "visible.checker", "可见区域出现规则的浅灰棋盘格，疑似把透明背景画进了像素。"))

    # ---- 像素网格
    grid = al.pixel_grid(rgba, lab)
    report["pixel_grid"] = grid
    gx, gy = grid.get("x"), grid.get("y")
    if profile["grid_expected"] and gx and gy:
        conf = min(gx["confidence"], gy["confidence"])
        if conf < 0.35:
            flags.append(
                flag(
                    "WARN",
                    "grid.none",
                    f"未检测到一致的美术像素网格（x={gx['k']}@{gx['confidence']}, y={gy['k']}@{gy['confidence']}）；"
                    "像素化素材可能是插值缩放或 AI 伪像素，需在原生尺寸比较与其他素材的像素密度。",
                )
            )
        elif gx["k"] != gy["k"]:
            flags.append(flag("WARN", "grid.anisotropic", f"横纵美术像素边长不同（x={gx['k']}, y={gy['k']}），疑似非等比缩放。"))
        # 屏幕缩放均匀性：只在素材按 1:1 显示时成立
        if args.display_scale == 1.0 and conf >= 0.35:
            k = gx["k"] if gx["k"] == gy["k"] else min(gx["k"], gy["k"])
            evenness = [al.scale_evenness(k, gx["phase"], s) for s in SCREEN_SCALES]
            report["screen_scale_evenness"] = evenness
            uneven = [e for e in evenness if not e["even"]]
            if uneven:
                flags.append(
                    flag(
                        "WARN",
                        "scale.uneven",
                        "按 1280×720 基准 1:1 显示时，"
                        + "、".join(f"{e['scale']}× 下美术像素宽度为 {e['widths']}" for e in uneven)
                        + "，nearest 下会出现粗细不一的线条。",
                    )
                )
    if args.display_scale != 1.0:
        k_eff = None
        if gx and gx["confidence"] >= 0.35:
            k_eff = round(gx["k"] * args.display_scale, 3)
        report["display"] = {"display_scale": args.display_scale, "effective_art_pixel_at_base": k_eff}

    # ---- 色彩与明度
    report["unique_colors"] = al.unique_colors(rgba)
    report["value"] = al.value_profile(lab, rgba)
    report["palette_top"] = al.palette_extract(rgba, n=args.palette_size)
    if ref_palette:
        px = lab[vis]
        if len(px) > 200_000:
            px = px[np.linspace(0, len(px) - 1, 200_000).astype(int)]
        adh = al.palette_adherence(px, ref_palette, threshold=args.de_threshold)
        report["palette_adherence"] = adh
        if adh and adh["within_threshold_share"] < 0.6:
            flags.append(
                flag(
                    "WARN",
                    "palette.drift",
                    f"只有 {adh['within_threshold_share']:.0%} 的可见像素落在参考色板 ΔE00≤{args.de_threshold} 内，"
                    f"平均 ΔE00={adh['mean_delta_e00']}；需确认是否偏离锚点配色。",
                )
            )

    # ---- 对称
    for axis in args.symmetry:
        sym = al.symmetry(rgba, lab, axis=axis)
        report.setdefault("symmetry", []).append(sym)
        if sym and (sym["alpha_mismatch"] > 0.03 or sym["color_mismatch"] > 0.08):
            flags.append(
                flag(
                    "WARN",
                    f"symmetry.{axis}",
                    f"{'左右' if axis == 'x' else '上下'}镜像差异：轮廓 {sym['alpha_mismatch']:.1%}，颜色 {sym['color_mismatch']:.1%}。",
                )
            )

    # ---- 尺寸约束
    w, h = info["size"]
    if args.expect_size and [w, h] != args.expect_size:
        flags.append(flag("FAIL", "size.mismatch", f"像素尺寸 {w}×{h} 与预期 {args.expect_size[0]}×{args.expect_size[1]} 不符。"))
    if profile["crisp"] and (w % 2 or h % 2) and args.even_required:
        flags.append(flag("WARN", "size.odd", f"尺寸 {w}×{h} 含奇数边，1.5× 缩放下无法与 2 像素美术网格对齐。"))

    report["flags"] = flags
    return report


def to_markdown(reports: list[dict]) -> str:
    lines = [
        "| 文件 | 尺寸 | SHA256 前 12 位 | alpha | 半透明 | 网格 x/y | 色数 | L* p5/p50/p95 | 标记 |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for r in reports:
        a = r["alpha"]
        g = r["pixel_grid"]
        gx = f"{g['x']['k']}@{g['x']['confidence']}" if g.get("x") else "-"
        gy = f"{g['y']['k']}@{g['y']['confidence']}" if g.get("y") else "-"
        v = r.get("value", {})
        flags = ", ".join(f"{f['level']}:{f['code']}" for f in r["flags"]) or "无"
        lines.append(
            f"| {Path(r['file']).name} | {r['pixel_size'][0]}×{r['pixel_size'][1]} | {r['sha256'][:12]} | "
            f"{'二值' if a['binary_alpha'] else '含半透明'}/{a['transparent_ratio']:.0%} 透明 | {a['semi_ratio_of_visible']:.2%} | "
            f"{gx} / {gy} | {r['unique_colors']} | {v.get('L_p05', '-')}/{v.get('L_p50', '-')}/{v.get('L_p95', '-')} | {flags} |"
        )
    detail = []
    for r in reports:
        if not r["flags"]:
            continue
        detail.append(f"\n**{Path(r['file']).name}**")
        for f in r["flags"]:
            detail.append(f"- {f['level']} `{f['code']}`：{f['message']}")
    return "\n".join(lines + detail) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="+", type=Path)
    ap.add_argument("--profile", default="generic", choices=sorted(PROFILES))
    ap.add_argument("--ref-palette", type=Path, help="JSON：十六进制色数组，或 {\"colors\": [...]}")
    ap.add_argument("--de-threshold", type=float, default=6.0)
    ap.add_argument("--palette-size", type=int, default=16)
    ap.add_argument("--symmetry", default="", help="x、y 或 xy")
    ap.add_argument("--display-scale", type=float, default=1.0, help="素材在 1280×720 基准下的显示缩放")
    ap.add_argument("--expect-size", type=lambda s: [int(v) for v in s.lower().split("x")], default=None)
    ap.add_argument("--even-required", action="store_true", help="像素件要求偶数边长")
    ap.add_argument("--json", type=Path)
    ap.add_argument("--md", type=Path)
    args = ap.parse_args()
    args.symmetry = [c for c in args.symmetry if c in "xy"]

    ref = None
    if args.ref_palette:
        data = json.loads(args.ref_palette.read_text(encoding="utf-8"))
        ref = data["colors"] if isinstance(data, dict) else data
        ref = [c["hex"] if isinstance(c, dict) else c for c in ref]

    files: list[Path] = []
    for f in args.files:
        files.extend(sorted(f.glob("*.png")) if f.is_dir() else [f])
    reports = [audit_file(f, args.profile, ref, args) for f in files]
    md = to_markdown(reports)
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(reports, ensure_ascii=False, indent=2), encoding="utf-8")
    if args.md:
        args.md.parent.mkdir(parents=True, exist_ok=True)
        args.md.write_text(md, encoding="utf-8")
    sys.stdout.reconfigure(encoding="utf-8")
    print(md)
    return 1 if any(f["level"] == "FAIL" for r in reports for f in r["flags"]) else 0


if __name__ == "__main__":
    raise SystemExit(main())
