"""回读地形同帧采集原件。通过只表示采集前置成立，不批准素材。"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

import numpy as np
from PIL import Image

import claude_review_checks as checks

ROLES = {"main", "reconstruction", "props", "instance_ids", "part_ids", "ground",
         "ground_without_shadow", "grid", "contact_shadow", "exclusions", "ground_types",
         "tree_crown_union"}
RESOLUTIONS = {(1280, 720), (1920, 1080), (2560, 1440)}
KINDS = ("tree", "wall", "pillar", "rubble")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def safe_child(root: Path, name: str) -> Path:
    if not isinstance(name, str) or not name or "\\" in name:
        raise ValueError("制品路径必须为正斜杠相对路径")
    path = root / name
    if Path(name).is_absolute() or ".." in Path(name).parts or not path.resolve().is_relative_to(root.resolve()):
        raise ValueError("制品路径超出指定目录")
    return path


def frame_errors(frame: dict) -> list[str]:
    errors = []
    if frame.get("callback") != "RenderingServer.frame_post_draw" or frame.get("same_callback") is not True:
        errors.append("没有同一次 frame_post_draw 记录")
    if frame.get("readback_awaits_between_images") is not False:
        errors.append("读取图像期间没有排除跨帧等待")
    for before, after in (("frames_drawn_before", "frames_drawn_after"),
                          ("process_frames_before", "process_frames_after")):
        if type(frame.get(before)) is not int or frame[before] < 0 or frame.get(before) != frame.get(after):
            errors.append(f"帧记录缺失或变化：{before}/{after}")
    if type(frame.get("frame_id")) is not int or frame.get("frame_id") != frame.get("frames_drawn_before"):
        errors.append("图像帧号没有对应当前绘制帧")
    return errors


def read_images(root: Path, records: dict, size: list[int], frame_id: int) -> tuple[dict, list[str]]:
    arrays, errors, names = {}, [], set()
    for role in sorted(ROLES | set(records)):
        rec = records.get(role)
        try:
            if not isinstance(rec, dict):
                raise ValueError("缺失图像记录")
            path = safe_child(root, rec.get("path"))
            if path in names:
                raise ValueError("不同角色共用一个图像文件")
            names.add(path)
            if not re.fullmatch(r"[0-9a-f]{64}", str(rec.get("sha256", ""))) or sha256(path) != rec["sha256"]:
                raise ValueError("原文件 SHA256 不一致")
            if rec.get("bytes") is not None and path.stat().st_size != rec["bytes"]:
                raise ValueError("原文件字节数不一致")
            with Image.open(path) as image:
                if image.format != "PNG" or list(image.size) != size or rec.get("image_size") != size:
                    raise ValueError("原 PNG 与记录的原生尺寸不一致")
                arrays[role] = np.asarray(image.convert("RGBA"))
            if rec.get("frame_id") != frame_id or rec.get("role", role) != role:
                raise ValueError("图像角色或同帧编号不一致")
        except (OSError, ValueError, TypeError) as error:
            errors.append(f"{role}: {error}")
    return arrays, errors


def reconstruction_check(images: dict) -> dict:
    if not {"main", "reconstruction", "props"}.issubset(images):
        return {"status": "NOT_TESTED", "reason": "对照原件不完整"}
    main, rebuilt, props = (images[key] for key in ("main", "reconstruction", "props"))
    if main.shape != rebuilt.shape or main.shape != props.shape:
        return {"status": "FAIL", "reason": "对照尺寸不一致"}
    changed = np.any(main != rebuilt, axis=2)
    prop_pixels = props[..., 3] > 127
    count = int(prop_pixels.sum())
    return {"status": "PASS" if count and not changed.any() else "FAIL",
            "scope": "完整正式画面与独立重建原件的 RGBA 逐像素相等",
            "pixels": int(changed.size), "mismatch_pixels": int(changed.sum()),
            "prop_pixels": count, "prop_mismatch_pixels": int((changed & prop_pixels).sum())}


def segmentation_check(images: dict, colors: set[str]) -> dict:
    if not {"props", "instance_ids"}.issubset(images):
        return {"status": "NOT_TESTED", "reason": "缺少道具 alpha 或实例 ID 原图"}
    props, identifiers = images["props"], images["instance_ids"]
    if props.shape != identifiers.shape:
        return {"status": "FAIL", "reason": "道具和实例 ID 尺寸不同"}
    silhouette, mask = props[..., 3] > 127, identifiers[..., 3] > 127
    mismatch = int(np.count_nonzero(silhouette != mask))
    known = np.zeros(mask.shape, dtype=bool)
    for color in colors:
        rgb = np.array([int(color[i:i+2], 16) for i in (1, 3, 5)])
        known |= np.all(identifiers[..., :3] == rgb, axis=2) & mask
    return {"status": "PASS" if silhouette.any() and mismatch == 0 and known.any() else "FAIL",
            "alpha_threshold": "> 0.5", "silhouette_pixels": int(silhouette.sum()),
            "alpha_mask_mismatch_pixels": mismatch,
            "unknown_mixed_color_pixels": int((mask & ~known).sum()),
            "note": "未知颜色不可分配给最近 ID；测量时排除，边界覆盖按原周长保留。"}


def source_errors(manifest: dict, source_root: Path, expected_head: str) -> list[str]:
    errors = []
    candidate = manifest.get("candidate", {})
    if not re.fullmatch(r"[0-9a-f]{40}", expected_head) or candidate.get("head") != expected_head:
        errors.append("候选提交不是请求冻结的完整 SHA")
    if candidate.get("dirty") is not False:
        errors.append("候选没有证明工作树干净")
    for section in ("sources", "materials"):
        bindings = manifest.get(section)
        if not isinstance(bindings, dict) or not bindings:
            errors.append(f"缺少 {section} 来源摘要")
            continue
        for name, digest in bindings.items():
            try:
                name = name.removeprefix("res://")
                path = safe_child(source_root, name)
                if not re.fullmatch(r"[0-9a-f]{64}", str(digest)) or sha256(path) != digest:
                    raise ValueError("来源摘要不匹配")
            except (OSError, ValueError, AttributeError) as error:
                errors.append(f"{section}/{name}: {error}")
    required = {"res://project.godot", "res://tests/claude_review/capture_terrain_readability.gd",
                "res://scripts/ui/playground/courtyard_board_view.gd"}
    if not required.issubset(manifest.get("sources", {})):
        errors.append("缺少项目、采集入口或正式地形代码绑定")
    return errors


def viewport_errors(viewports: dict, size: list[int]) -> list[str]:
    """比较实际映射，而非只验证矩阵格式；辅助层必须与 main 同坐标。"""
    errors = []
    main = viewports.get("main", {})
    for role in ROLES:
        viewport = viewports.get(role, {})
        if viewport.get("texture_size") != size or viewport.get("image_size") != size:
            errors.append(f"{role}: Texture/Image 尺寸记录不匹配")
        for field, length in (("canvas_transform", 6), ("final_transform", 6), ("visible_rect", 4)):
            matrix, reference = viewport.get(field, []), main.get(field, [])
            valid = lambda values: (isinstance(values, list) and len(values) == length
                                    and all(type(v) in (int, float) and np.isfinite(v) for v in values))
            if not valid(matrix) or not valid(reference):
                errors.append(f"{role}: 缺少有效 {field}")
            elif not np.allclose(matrix, reference, atol=1e-6, rtol=0):
                errors.append(f"{role}: {field} 与主视口不一致")
    return errors


def validate(manifest_path: Path, source_root: Path, expected_head: str) -> dict:
    data = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    errors = []
    if data.get("schema_version") != "terrain-mask-capture/1":
        errors.append("采集 schema 不匹配")
    case, frame = data.get("case", {}), data.get("common_frame", {})
    size, map_size = case.get("requested_resolution", []), case.get("map_size", [])
    if tuple(size) not in RESOLUTIONS or case.get("window_size") != size:
        errors.append("不是三档原生窗口尺寸之一")
    if map_size not in ([10, 10], [25, 25]):
        errors.append("不是 10×10 或 25×25 正方形地图")
    if not case.get("initial_fit"):
        errors.append("缺少初始 fit 相机记录")
    errors += frame_errors(frame) + source_errors(data, source_root, expected_head)
    images, image_errors = read_images(manifest_path.parent, data.get("images", {}), size, frame.get("frame_id"))
    errors += image_errors
    errors += viewport_errors(data.get("viewports", {}), size)
    counts = {kind: 0 for kind in KINDS}
    visible_counts = counts.copy()
    ids, colors = set(), set()
    id_image = images.get("instance_ids")
    excluded = images.get("exclusions")
    for instance in data.get("instances", []):
        sid, color = instance.get("stable_id"), instance.get("color", "")
        if not sid or sid in ids or color in colors or not re.fullmatch(r"#[0-9a-fA-F]{6}", color):
            errors.append("实例 ID 或颜色缺失、重复或无效")
            continue
        ids.add(sid)
        colors.add(color)
        kind = instance.get("type")
        if kind not in counts:
            continue
        counts[kind] += 1
        if id_image is not None:
            rgb = np.array([int(color[i:i+2], 16) for i in (1, 3, 5)])
            visible = np.all(id_image[..., :3] == rgb, axis=2) & (id_image[..., 3] > 127)
            if excluded is not None:
                visible &= excluded[..., 3] <= 127
            visible_counts[kind] += int(visible.any())
    for kind in KINDS:
        if counts[kind] < 3 or visible_counts[kind] < 3:
            errors.append(f"{kind}: 少于三个实例或少于三个可见实例")
    alignment = reconstruction_check(images)
    if alignment["status"] != "PASS":
        errors.append("重建画面尚未与正式原图完全对齐")
    segmentation = segmentation_check(images, colors)
    if segmentation["status"] != "PASS":
        errors.append("实例掩膜与实际道具 alpha 轮廓不一致")
    c4 = checks.c4_file(safe_child(manifest_path.parent, data["images"]["main"]["path"])) if "main" in images else {"pass": False, "reason": "缺少主图"}
    # 使用项目现行 C8，不复制其拉伸/渲染器判定。
    previous_root = checks.ROOT
    try:
        checks.ROOT = source_root
        c8 = checks.c8_manifest(manifest_path)
        c8_source = checks.c8_script(source_root / "tests/claude_review/capture_terrain_readability.gd")
    finally:
        checks.ROOT = previous_root
    if not c4.get("pass") or not c8.get("pass") or not c8_source.get("pass"):
        errors.append("C4 或 C8 未通过")
    if data.get("exclusions", {}).get("status") not in ("COMPLETE", "CAPTURED_WITH_CONSERVATIVE_CONTROL_BOUNDS"):
        errors.append("单位、HUD 或网格排除掩膜仍不完整")
    return {"manifest": manifest_path.name, "case": case,
            "capture_preconditions": "PASS" if not errors else "FAIL", "errors": errors,
            "instance_counts": counts, "visible_instance_counts": visible_counts,
            "reconstruction": alignment, "segmentation": segmentation,
            "C4": c4, "C8": c8, "C8_source": c8_source,
            "measurement_status": "NOT_TESTED", "art_acceptance": "NOT_TESTED",
            "note": "采集前置通过后，另行测量真实 T1–T6、负例校准与原图审查；不从文件完整推导美术通过。"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifests", type=Path, nargs="+")
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    local_head = subprocess.check_output(["git", "-C", str(args.source_root), "rev-parse", "HEAD"], text=True).strip()
    if local_head != args.candidate:
        parser.error("回读源码工作树 HEAD 与冻结候选不同")
    results = []
    for path in args.manifests:
        try:
            results.append(validate(path, args.source_root, args.candidate))
        except (OSError, ValueError, KeyError, TypeError) as error:
            results.append({"manifest": path.name, "capture_preconditions": "FAIL", "errors": [str(error)]})
    cases = [(tuple(r.get("case", {}).get("map_size", [])), tuple(r.get("case", {}).get("requested_resolution", []))) for r in results]
    required = {(size, res) for size in ((10, 10), (25, 25)) for res in RESOLUTIONS}
    complete = len(cases) == 6 and set(cases) == required
    valid = complete and all(r["capture_preconditions"] == "PASS" for r in results)
    output = {"schema_version": "terrain-capture-readback/1", "candidate_head": args.candidate,
              "six_case_coverage": complete, "capture_preconditions": "PASS" if valid else "FAIL",
              "art_acceptance": "NOT_TESTED", "cases": results}
    args.out.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"capture_preconditions": output["capture_preconditions"], "six_case_coverage": complete, "art_acceptance": "NOT_TESTED"}, ensure_ascii=False))
    return 0 if valid else 1


if __name__ == "__main__":
    raise SystemExit(main())
