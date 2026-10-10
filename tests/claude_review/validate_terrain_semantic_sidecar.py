"""Verify semantic sidecar provenance/alignment, then run frozen T2 and T3 metrics."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
from typing import Any

import numpy as np
from PIL import Image

import claude_review_checks as checks
import terrain_readability_metrics as metrics
import validate_terrain_readability_capture as v1
import validate_terrain_readability_capture_v4 as v4
import validate_terrain_readability_capture_v6 as frozen_v6


SIDECAR_SCHEMA = "terrain-semantic-sidecar/1"
SIDECAR_MANIFEST = "semantic-sidecar-manifest.json"
SIDECAR_SOURCE_FILES = (
    "tests/claude_review/capture_terrain_readability_v6_regions_semantic_sidecar.gd",
    "tests/claude_review/terrain_semantic_sidecar.gdshader",
    "tests/claude_review/validate_terrain_semantic_sidecar.py",
    "tests/claude_review/test_terrain_semantic_sidecar.py",
    "dev_doc/ui-art-research/terrain-readability/semantic-sidecar-task.md",
)
PART_CODES = {
    "wall_top": 1,
    "wall_side": 2,
    "pillar_top": 3,
    "pillar_side": 4,
    "pillar_base": 5,
    "wall_outline": 6,
    "tree_crown": 7,
    "tree_dark_side": 8,
    "tree_outline": 9,
    "whole_instance": 10,
    "unknown": 255,
}
UNKNOWN_PART_CODE = 255
T2_PARTS = {
    "wall": {"top": (PART_CODES["wall_top"],), "side": (PART_CODES["wall_side"],)},
    "pillar": {
        "top": (PART_CODES["pillar_top"],),
        "side": (PART_CODES["pillar_side"], PART_CODES["pillar_base"]),
    },
}
TREE_PART_CODES = {
    PART_CODES["tree_crown"], PART_CODES["tree_dark_side"], PART_CODES["tree_outline"]
}
REQUIRED_VISIBLE_KINDS = tuple(v1.KINDS)
SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")
HEX_RGB_RE = re.compile(r"#[0-9a-fA-F]{6}\Z")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def token_to_rgb(token: int) -> tuple[int, int, int]:
    if type(token) is not int or not 1 <= token <= 0xFFFFFF:
        raise ValueError("实例令牌必须是 1 到 0xFFFFFF 的整数")
    return (token >> 16, (token >> 8) & 255, token & 255)


def rgb_to_token(rgb: tuple[int, int, int] | np.ndarray) -> int:
    if len(rgb) != 3 or any(not isinstance(channel, (int, np.integer))
                             or isinstance(channel, (bool, np.bool_))
                             or not 0 <= int(channel) <= 255 for channel in rgb):
        raise ValueError("令牌 RGB 必须是三个无符号字节")
    return (int(rgb[0]) << 16) | (int(rgb[1]) << 8) | int(rgb[2])


def _valid_rgba(value: object) -> bool:
    return (isinstance(value, np.ndarray) and value.dtype == np.uint8
            and value.ndim == 3 and value.shape[2] == 4)


def validate_label_coverage_arrays(pair: np.ndarray, coverage: np.ndarray,
                                   instance_tokens: list[dict],
                                   props: np.ndarray | None = None) -> list[str]:
    """Validate raw RGBA8 semantic/coverage pixels without color-distance decoding."""
    errors: list[str] = []
    if not _valid_rgba(pair) or not _valid_rgba(coverage):
        return ["semantic_pair 与 semantic_coverage 必须是原始 RGBA8 数组"]
    if pair.shape != coverage.shape:
        return ["semantic_pair 与 semantic_coverage 原像素尺寸不一致"]
    if props is not None and (not _valid_rgba(props) or props.shape != pair.shape):
        return ["frozen props RGBA8 尺寸与 sidecar 不一致"]

    by_token: dict[int, dict] = {}
    by_stable_id: set[str] = set()
    for index, record in enumerate(instance_tokens):
        if not isinstance(record, dict):
            errors.append(f"实例令牌记录[{index}]格式无效")
            continue
        token, stable_id, token_rgb = record.get("token"), record.get("stable_id"), record.get("token_rgb")
        if type(token) is not int or not 1 <= token <= 0xFFFFFF:
            errors.append(f"实例令牌记录[{index}]超出 24 位非零范围")
            continue
        if not isinstance(stable_id, str) or not stable_id or stable_id in by_stable_id:
            errors.append(f"实例令牌记录[{index}] stable_id 缺失或重复")
        else:
            by_stable_id.add(stable_id)
        expected_rgb = list(token_to_rgb(token))
        if token_rgb != expected_rgb:
            errors.append(f"实例令牌记录[{index}] RGB 与 24 位令牌不一致")
        if token in by_token:
            errors.append(f"实例令牌 {token} 被多个对象共用")
        else:
            by_token[token] = record

    tokens = ((pair[..., 0].astype(np.uint32) << 16)
              | (pair[..., 1].astype(np.uint32) << 8)
              | pair[..., 2].astype(np.uint32))
    part = pair[..., 3]
    covered = coverage[..., 3] == 255
    labels_present = tokens != 0
    if np.any((tokens == 0) & (part != 0)):
        errors.append("背景 token=0 像素的部件码必须为 0")
    if np.any(labels_present & (part == 0)):
        errors.append("非零实例 token 必须带非零部件码")
    if not np.array_equal(labels_present, covered):
        errors.append("label token 与 coverage.A 覆盖标记在像素坐标上不一致")
    if np.any(covered & (coverage[..., 0] == 0)):
        errors.append("coverage.A 标记覆盖时 coverage.R 原始 alpha 不得为 0")
    if np.any((~covered) & np.any(coverage[..., :3] != 0, axis=2)):
        errors.append("coverage 标记为空的像素必须为零背景")
    if np.any((coverage[..., 3] != 0) & (coverage[..., 3] != 255)):
        errors.append("coverage.A 只能使用 0 或 255")
    known_codes = set(PART_CODES.values())
    invalid_codes = labels_present & ~np.isin(part, np.fromiter(known_codes, dtype=np.uint8))
    if invalid_codes.any():
        errors.append("semantic_pair 含未知或无效的部件码；禁止最近颜色归类")
    valid_token_mask = np.zeros(tokens.shape, dtype=bool)
    for token, record in by_token.items():
        token_mask = tokens == token
        valid_token_mask |= token_mask
        if record.get("type") == "unknown" and np.any(token_mask & (part != UNKNOWN_PART_CODE)):
            errors.append(f"未知实例 {record.get('stable_id')} 必须使用非零 unknown 部件码")
    if np.any(labels_present & ~valid_token_mask):
        errors.append("semantic_pair 含 manifest 未登记的 token；禁止按最近颜色猜测")
    if props is not None:
        prop_alpha = props[..., 3] > 127
        if np.any(prop_alpha & ~labels_present):
            errors.append("frozen props alpha>0.5 的像素未被语义 token 覆盖")
        if np.any(prop_alpha & ~covered):
            errors.append("frozen props alpha>0.5 的像素缺少独立 coverage 标记")
    return errors


def alpha_sample_masks(coverage: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Return the frozen >0.5 sample mask and the retained <0.98 uncertainty mask."""
    if not _valid_rgba(coverage):
        raise ValueError("coverage 必须是 RGBA8 数组")
    visible = (coverage[..., 3] == 255) & (coverage[..., 0] > 127)
    uncertain = visible & (coverage[..., 0].astype(np.float64) / 255.0 < 0.98)
    return visible, uncertain


def atlas_uv_to_region_local_uv(atlas_uv: tuple[float, float] | list[float],
                                atlas_size: tuple[int, int] | list[int],
                                atlas_region: tuple[float, float, float, float] | list[float]) -> tuple[float, float]:
    """Convert Godot AtlasTexture's atlas-space UV to the region-local category-map UV."""
    if len(atlas_uv) != 2 or len(atlas_size) != 2 or len(atlas_region) != 4:
        raise ValueError("Atlas UV、尺寸或 region 几何长度无效")
    u, v = map(float, atlas_uv)
    width, height = map(float, atlas_size)
    x, y, region_width, region_height = map(float, atlas_region)
    if (not all(math.isfinite(value) for value in (u, v, width, height, x, y, region_width, region_height))
            or width <= 0 or height <= 0 or region_width <= 0 or region_height <= 0):
        raise ValueError("Atlas UV 或 region 几何必须有限且非零")
    return ((u * width - x) / region_width,
            (v * height - y) / region_height)


def region_local_uv_to_texel(local_uv: tuple[float, float] | list[float],
                             map_size: tuple[int, int] | list[int]) -> tuple[int, int] | None:
    """Nearest, no-mipmap category map index for a normalized region-local UV."""
    if len(local_uv) != 2 or len(map_size) != 2:
        raise ValueError("region-local UV 或 map 尺寸长度无效")
    u, v = map(float, local_uv)
    width, height = map(int, map_size)
    if width <= 0 or height <= 0 or not math.isfinite(u) or not math.isfinite(v):
        raise ValueError("region map 尺寸或 UV 无效")
    if not 0 <= u < 1 or not 0 <= v < 1:
        return None
    return math.floor(u * width), math.floor(v * height)


def composite_semantic_samples(layers: list[dict]) -> tuple[np.ndarray, np.ndarray]:
    """Synthetic last-draw-wins contract used by focused tests; not a native pixel renderer."""
    label = np.zeros((1, 1, 4), dtype=np.uint8)
    coverage = np.zeros((1, 1, 4), dtype=np.uint8)
    for layer in layers:
        token = layer.get("token", 0)
        part_code = layer.get("part_code", 0)
        source_alpha = layer.get("source_alpha", 0)
        if type(source_alpha) is not int or not 0 <= source_alpha <= 255:
            raise ValueError("source_alpha 必须为字节")
        if source_alpha == 0:
            continue
        rgb = token_to_rgb(token)
        if type(part_code) is not int or not 1 <= part_code <= 255:
            raise ValueError("部件码必须为非零字节")
        label[0, 0] = (*rgb, part_code)
        coverage[0, 0] = (source_alpha, 0, 0, 255)
    return label, coverage


def _safe_relative(root: Path, value: object) -> Path:
    if not isinstance(value, str) or not value or "\\" in value:
        raise ValueError("制品路径必须是正斜杠相对路径")
    rel = Path(value)
    if rel.is_absolute() or ".." in rel.parts:
        raise ValueError("制品路径必须位于所属案例目录内")
    path = root / rel
    if not path.resolve().is_relative_to(root.resolve()):
        raise ValueError("制品路径越出所属案例目录")
    return path


def _read_rgba_png(path: Path, *, expected_size: list[int] | None = None,
                   expected_sha256: str | None = None,
                   expected_bytes: int | None = None) -> np.ndarray:
    raw = path.read_bytes()
    if expected_sha256 is not None and sha256_bytes(raw) != expected_sha256:
        raise ValueError(f"原 PNG SHA256 不一致: {path.name}")
    if expected_bytes is not None and len(raw) != expected_bytes:
        raise ValueError(f"原 PNG 字节数不一致: {path.name}")
    with Image.open(path) as image:
        if image.format != "PNG" or image.mode != "RGBA":
            raise ValueError(f"原 PNG 必须直接解码为 RGBA，不进行转换: {path.name}")
        if expected_size is not None and list(image.size) != expected_size:
            raise ValueError(f"PNG 原生尺寸不匹配: {path.name}")
        image.load()
        array = np.asarray(image, dtype=np.uint8).copy()
    if not _valid_rgba(array):
        raise ValueError(f"解码结果不是 RGBA8: {path.name}")
    return array


def validate_sidecar_binding(capture_manifest_path: Path, capture: dict,
                             sidecar: dict) -> tuple[list[str], dict[str, np.ndarray]]:
    errors: list[str] = []
    arrays: dict[str, np.ndarray] = {}
    if sidecar.get("schema_version") != SIDECAR_SCHEMA:
        errors.append("semantic sidecar schema 不匹配")
    try:
        capture_bytes = capture_manifest_path.read_bytes()
        capture_sha = sha256_bytes(capture_bytes)
    except OSError as error:
        return [f"capture-manifest 原字节无法读取: {error}"], arrays
    if sidecar.get("capture_manifest_path") != "capture-manifest.json":
        errors.append("sidecar 未绑定同目录 capture-manifest.json")
    if sidecar.get("capture_manifest_sha256") != capture_sha:
        errors.append("sidecar capture-manifest 原字节 SHA256 不匹配")
    candidate = capture.get("candidate", {})
    if sidecar.get("capture_candidate") != candidate:
        errors.append("sidecar candidate 与最终 capture-manifest candidate 不完全一致")
    if sidecar.get("candidate_source_sha256") != candidate.get("source_sha256"):
        errors.append("sidecar source 摘要未完整复制最终 candidate.source_sha256")
    if sidecar.get("case") != capture.get("case"):
        errors.append("sidecar case 与 capture-manifest 不一致")

    frame = sidecar.get("frame", {})
    common = capture.get("common_frame", {})
    if not isinstance(frame, dict) or not isinstance(common, dict):
        return errors + ["sidecar/capture common_frame 结构无效"], arrays
    if frame.get("callback") != "RenderingServer.frame_post_draw" or frame.get("same_frame") is not True:
        errors.append("sidecar 未记录同一次 frame_post_draw")
    if frame.get("readback_awaits_between_images") is not False:
        errors.append("sidecar 读取期间必须没有跨帧等待")
    if frame.get("original_capture_image_count_unchanged") != 12:
        errors.append("sidecar 没有保留冻结 12 图字典")
    if frame.get("original_capture_roles_unchanged") != sorted(capture.get("images", {}).keys()):
        errors.append("sidecar 原 12 个图像角色列表与 capture-manifest 不符")
    for key in ("frame_id", "frames_drawn_before", "frames_drawn_after",
                "process_frames_before", "process_frames_after"):
        if frame.get(key) != common.get(key):
            errors.append(f"sidecar {key} 与 frozen capture 同帧记录不一致")
    if frame.get("frame_id") != common.get("frame_id"):
        errors.append("sidecar frame_id 与原 12 图 frame_id 不一致")
    if common.get("readback_awaits_between_images") is not False:
        errors.append("frozen capture 原图读取记录不满足无等待约束")
    case = capture.get("case", {})
    size = case.get("requested_resolution") if isinstance(case, dict) else None
    image_records = frame.get("images", {})
    if not isinstance(size, list) or len(size) != 2:
        errors.append("capture-manifest 原生分辨率记录无效")
        size = None
    if not isinstance(image_records, dict) or set(image_records) != {"semantic_pair", "semantic_coverage"}:
        errors.append("sidecar 必须恰有 semantic_pair 与 semantic_coverage 两张图")
        image_records = {}
    paths: set[Path] = set()
    for role in ("semantic_pair", "semantic_coverage"):
        record = image_records.get(role)
        if not isinstance(record, dict):
            errors.append(f"sidecar 缺少 {role} 图像记录")
            continue
        if record.get("role") != role or record.get("frame_id") != frame.get("frame_id"):
            errors.append(f"{role} 图像角色或 frame_id 不匹配")
        if record.get("image_size") != size or record.get("pixel_format") != "RGBA8":
            errors.append(f"{role} 图像尺寸或 RGBA8 格式记录无效")
        try:
            path = _safe_relative(capture_manifest_path.parent, record.get("path"))
            if path in paths:
                raise ValueError("两个 sidecar 角色共用同一文件")
            paths.add(path)
            arrays[role] = _read_rgba_png(path, expected_size=size,
                                          expected_sha256=record.get("sha256"),
                                          expected_bytes=record.get("bytes"))
        except (OSError, ValueError) as error:
            errors.append(f"{role}: {error}")
    frame_tokens = frame.get("instance_tokens", [])
    tree_records = [record for record in frame_tokens
                    if isinstance(record, dict) and record.get("type") == "tree"] \
        if isinstance(frame_tokens, list) else []
    if isinstance(frame_tokens, list) and frame_tokens:
        stable_ids = [record.get("stable_id") for record in frame_tokens
                      if isinstance(record, dict)]
        source_orders = [record.get("source_order") for record in frame_tokens
                         if isinstance(record, dict)]
        if (len(stable_ids) != len(frame_tokens)
                or any(type(stable_id) is not str for stable_id in stable_ids)
                or len(set(stable_ids)) != len(stable_ids)
                or any(type(order) is not int for order in source_orders)
                or sorted(source_orders) != list(range(len(frame_tokens)))):
            errors.append("sidecar prop source_order 必须唯一并覆盖原始 _props 顺序")
        else:
            expected_draw_order = [record["stable_id"] for record in sorted(
                frame_tokens, key=lambda record: record["source_order"])]
            if frame.get("draw_order_stable_ids") != expected_draw_order:
                errors.append("sidecar draw_order_stable_ids 与原始 _props sibling 顺序不一致")
    elif frame_tokens:
        errors.append("sidecar instance_tokens 必须是数组，才能核对原始绘制顺序")
    classification_maps = sidecar.get("classification_maps", {})
    if tree_records:
        if not isinstance(classification_maps, dict) or set(classification_maps) != {"tree_regions"}:
            errors.append("tree 实例必须绑定唯一 semantic_tree_region_map 分类图")
        else:
            map_record = classification_maps.get("tree_regions", {})
            if not isinstance(map_record, dict) or map_record.get("pixel_format") != "RGBA8_CODE_ONLY":
                errors.append("tree 分类图记录格式无效")
            else:
                map_size = map_record.get("image_size")
                atlas_region = map_record.get("atlas_region")
                if (not isinstance(map_size, list) or len(map_size) != 2
                        or not isinstance(atlas_region, list) or len(atlas_region) != 4
                        or any(type(value) not in (int, float) or not math.isfinite(value)
                               for value in atlas_region)
                        or map_size != [round(atlas_region[2]), round(atlas_region[3])]):
                    errors.append("tree 分类图尺寸与 AtlasTexture region 不一致")
                try:
                    map_path = _safe_relative(capture_manifest_path.parent, map_record.get("path"))
                    if map_path in paths:
                        raise ValueError("类别图不能复用 semantic_pair/semantic_coverage 文件")
                    arrays["tree_classification_map"] = _read_rgba_png(
                        map_path, expected_size=map_size,
                        expected_sha256=map_record.get("sha256"),
                        expected_bytes=map_record.get("bytes"))
                except (OSError, ValueError) as error:
                    errors.append(f"tree classification map: {error}")
    elif classification_maps:
        errors.append("无 tree 实例时不应出现 tree 区域分类图")
    if not isinstance(arrays.get("semantic_pair"), np.ndarray) or not isinstance(arrays.get("semantic_coverage"), np.ndarray):
        return errors, arrays
    if arrays["semantic_pair"].shape != arrays["semantic_coverage"].shape:
        errors.append("sidecar 两张 RGBA 原图尺寸不一致")

    viewports = frame.get("viewports", {})
    capture_viewports = capture.get("viewports", {})
    main_viewport = capture_viewports.get("main", {}) if isinstance(capture_viewports, dict) else {}
    if not isinstance(viewports, dict) or set(viewports) != {"main", "semantic_pair", "semantic_coverage"}:
        errors.append("sidecar viewports 必须记录 main 与两张独立视口")
        viewports = {}
    if viewports.get("main") != main_viewport:
        errors.append("sidecar main viewport 记录与原 capture-manifest 不一致")
    for role in ("semantic_pair", "semantic_coverage"):
        record = viewports.get(role, {})
        if not isinstance(record, dict):
            errors.append(f"{role} viewport 记录无效")
            continue
        for field in ("size", "image_size", "texture_size"):
            if record.get(field) != size:
                errors.append(f"{role} viewport {field} 与原生图像尺寸不一致")
        for field in ("canvas_transform", "final_transform", "visible_rect"):
            if not _finite_array(record.get(field), 6 if field != "visible_rect" else 4):
                errors.append(f"{role} viewport {field} 缺失或无效")
                continue
            if not _close_array(record[field], main_viewport.get(field), 1e-6):
                errors.append(f"{role} viewport {field} 与 main 不一致；变换相同本身不代表像素配准")
    if frame.get("window_size") != size:
        errors.append("sidecar Window 尺寸与 capture 原生尺寸不一致")
    return errors, arrays


def validate_tree_classification_map(sidecar: dict, instance_tokens: list[dict],
                                     arrays: dict[str, np.ndarray]) -> list[str]:
    errors: list[str] = []
    trees = [record for record in instance_tokens
             if isinstance(record, dict) and record.get("type") == "tree"]
    if not trees:
        return errors
    record = sidecar.get("classification_maps", {}).get("tree_regions", {})
    image = arrays.get("tree_classification_map")
    if not isinstance(record, dict) or not _valid_rgba(image):
        return ["tree 分类图原始 RGBA8 字节缺失"]
    expected_uv_mapping = {
        "uv_space": "Godot 4.6 CanvasItem UV is normalized over the original atlas texture used by AtlasTexture",
        "atlas_pixel": "UV * atlas_size",
        "region_local_uv": "(atlas_pixel - atlas_region.position) / atlas_region.size",
        "region_texel": "floor(region_local_uv * region_map_size); map texels represent source region pixel centers",
        "sampler": "filter_nearest, repeat_disable",
    }
    if record.get("status") != "READY" or record.get("atlas_uv_mapping") != expected_uv_mapping:
        errors.append("tree Atlas UV→region-local UV 映射记录不符合已核对的 nearest 路径")
    if record.get("map_has_mipmaps") is not False:
        errors.append("tree 分类图必须明确没有 mipmap")
    if record.get("coverage_samples_classification_map") is not False \
            or record.get("pair_samples_classification_map") is not True:
        errors.append("coverage 只能使用原 source alpha，类别图仅用于 semantic_pair")
    if record.get("source_alpha_sampler") != "original Sprite2D AtlasTexture TEXTURE through incoming COLOR.a":
        errors.append("tree source alpha 没有绑定原 Sprite2D AtlasTexture COLOR.a")
    if record.get("fallback_part_code") != UNKNOWN_PART_CODE:
        errors.append("tree 类别图缺少非零 unknown fallback")
    if record.get("map_rgb_role") != "R is a code byte normalized to 0..1; G/B are zero" \
            or record.get("map_alpha_role") != "255 marks a reviewed code texel; it is never used as source opacity":
        errors.append("tree 类别图通道与 alpha 来源语义记录无效")
    expected_data_sha = sha256_bytes(image.tobytes())
    if record.get("source_data_sha256") != expected_data_sha:
        errors.append("tree 类别图解码后 RGBA 原字节摘要不匹配")
    # PNG decoding already returns RGBA8 code bytes, not normalized channels.
    code = image[..., 0]
    alpha = image[..., 3]
    allowed = {0, PART_CODES["tree_crown"], PART_CODES["tree_dark_side"], PART_CODES["tree_outline"]}
    if np.any(~np.isin(code, np.fromiter(allowed, dtype=np.uint8))):
        errors.append("tree 类别图含非审查部件码")
    if np.any(image[..., 1:3] != 0) or not np.array_equal(alpha == 255, code != 0):
        errors.append("tree 类别图 RGB/A 标记字节无效")
    for tree in trees:
        inputs = tree.get("tree_region_inputs", {})
        if not isinstance(inputs, dict) or inputs.get("classification_map") != record:
            errors.append(f"tree {tree.get('stable_id')} 未绑定同一原字节分类图记录")
            continue
        if inputs.get("source_alpha_sampler") != "original Sprite2D AtlasTexture COLOR.a; source texture filter/repeat/mipmap remain unchanged" \
                or inputs.get("region_map_does_not_supply_alpha") is not True \
                or inputs.get("single_source_sprite_draw_preserves_order") is not True:
            errors.append(f"tree {tree.get('stable_id')} 未证明 source alpha 与绘制顺序保持原路径")
    return errors


def _finite_array(value: object, length: int) -> bool:
    return (isinstance(value, list) and len(value) == length
            and all(type(item) in (int, float) and math.isfinite(item) for item in value))


def _close_array(left: object, right: object, tolerance: float) -> bool:
    if not isinstance(left, list) or not isinstance(right, list) or len(left) != len(right):
        return False
    return all(type(a) in (int, float) and type(b) in (int, float)
               and math.isfinite(a) and math.isfinite(b) and abs(a - b) <= tolerance
               for a, b in zip(left, right))


def _rgb_from_hex(value: object) -> tuple[int, int, int] | None:
    if not isinstance(value, str) or HEX_RGB_RE.fullmatch(value) is None:
        return None
    return tuple(int(value[index:index + 2], 16) for index in (1, 3, 5))  # type: ignore[return-value]


def sidecar_source_errors(capture: dict, sidecar: dict, source_root: Path) -> list[str]:
    errors: list[str] = []
    candidate = capture.get("candidate", {})
    candidate_sources = candidate.get("source_sha256", {}) if isinstance(candidate, dict) else {}
    manifest_sources = capture.get("sources", {})
    side_sources = sidecar.get("candidate_source_sha256", {})
    if not isinstance(candidate_sources, dict) or not isinstance(manifest_sources, dict) or not isinstance(side_sources, dict):
        return ["candidate/source 摘要表格式无效"]
    for source in SIDECAR_SOURCE_FILES:
        try:
            actual = hashlib.sha256((source_root / source).read_bytes()).hexdigest()
        except OSError:
            errors.append(f"semantic sidecar 源码缺失: {source}")
            continue
        if candidate_sources.get(source) != actual or side_sources.get(source) != actual:
            errors.append(f"candidate.source_sha256 未绑定实际 sidecar 字节: {source}")
        if manifest_sources.get("res://" + source) != actual:
            errors.append(f"capture-manifest sources 未绑定 sidecar 字节: {source}")

    tree = capture.get("tree_semantic_input", {})
    input_hashes = sidecar.get("semantic_input_sha256", {})
    if not isinstance(tree, dict) or not isinstance(input_hashes, dict):
        return errors + ["tree semantic input/source hash 结构无效"]
    path_fields = {
        "author_annotation_path": "author_annotation_sha256",
        "independent_review_path": "independent_review_sha256",
        "base_crown_annotation_path": "base_crown_annotation_sha256",
        "texture_path": "texture_sha256",
    }
    actual_inputs: dict[str, str] = {}
    for path_field, digest_field in path_fields.items():
        resource_path = tree.get(path_field)
        expected_digest = tree.get(digest_field)
        if not isinstance(resource_path, str) or not resource_path.startswith("res://"):
            errors.append(f"tree semantic input {path_field} 缺失或不是 res:// 路径")
            continue
        relative = resource_path.removeprefix("res://")
        try:
            actual = hashlib.sha256(_safe_relative(source_root, relative).read_bytes()).hexdigest()
        except (OSError, ValueError):
            errors.append(f"tree semantic 输入文件无法读取: {relative}")
            continue
        actual_inputs[relative] = actual
        if expected_digest != actual or input_hashes.get(relative) != actual:
            errors.append(f"tree semantic 输入摘要与原文件不匹配: {relative}")
    scopes = tree.get("approved_scope", [])
    outline = tree.get("outline_semantics", {})
    if tree.get("status") not in ("APPROVED", "PARTIAL_APPROVAL"):
        errors.append("tree semantic author/review 记录不是已审查状态")
    if not isinstance(scopes, list) or "dark_side_geometry" not in scopes:
        errors.append("tree semantic 独审没有批准 dark_side_geometry")
    if not isinstance(outline, dict) or type(outline.get("present")) is not bool:
        errors.append("tree outline 必须有明确的 present 布尔语义")
    elif outline.get("present") is False:
        if "outline_absence" not in scopes or tree.get("effective_outline_status") != "absent_authoritatively":
            errors.append("outline 缺席没有独审批准；空数组不能代替明确缺席")
    elif outline.get("present") is True:
        if "outline_geometry" not in scopes or tree.get("effective_outline_status") != "captured":
            errors.append("outline present=true 时缺少有效独审几何")

    author_path = tree.get("author_annotation_path")
    review_path = tree.get("independent_review_path")
    try:
        author_value = json.loads(_safe_relative(source_root, str(author_path).removeprefix("res://")).read_text(encoding="utf-8"))
        review_value = json.loads(_safe_relative(source_root, str(review_path).removeprefix("res://")).read_text(encoding="utf-8"))
    except (OSError, ValueError, TypeError) as error:
        errors.append(f"tree semantic 原始输入 JSON 无法解析: {error}")
    else:
        if author_value.get("schema_version") != "terrain-readability-tree-semantics/1":
            errors.append("作者树语义 JSON schema 无效")
        if author_value.get("review_status") != "pending_author_review":
            errors.append("作者语义输入状态与批准边界不符")
        if review_value.get("schema_version") != "terrain-readability-tree-semantics-review/1" \
                or review_value.get("verdict") != "PASS":
            errors.append("tree semantic 独审报告不是绑定 PASS")
        if review_value.get("annotation_sha256") != tree.get("author_annotation_sha256") \
                or review_value.get("texture_sha256") != tree.get("texture_sha256") \
                or review_value.get("base_crown_annotation_sha256") != tree.get("base_crown_annotation_sha256"):
            errors.append("tree semantic 独审的 annotation/texture/crown 摘要不匹配")
        if review_value.get("approved_scope") != scopes:
            errors.append("tree semantic manifest scope 与独审 scope 不一致")
        if author_value.get("outline_semantics") != outline:
            errors.append("tree semantic outline 声明与作者输入不一致")
        if author_value.get("regions", {}).get("dark_side") == []:
            errors.append("树暗侧几何为空；不得把缺失区域当成已测")
    return errors


def pixel_alignment_report(capture: dict, images: dict[str, np.ndarray],
                           pair: np.ndarray, coverage: np.ndarray,
                           instance_tokens: list[dict]) -> dict:
    errors: list[str] = []
    props, legacy_ids, legacy_parts = (images.get(role) for role in ("props", "instance_ids", "part_ids"))
    if any(not _valid_rgba(image) for image in (props, legacy_ids, legacy_parts)):
        return {"status": "NOT_TESTED", "errors": ["缺少原始 props/instance_ids/part_ids RGBA 图像"],
                "opaque_instance_matches": 0, "opaque_part_matches": 0, "props_alpha_missing_labels": 0}
    if any(image.shape != pair.shape for image in (props, legacy_ids, legacy_parts)):
        return {"status": "FAIL", "errors": ["sidecar 与 frozen prop masks 尺寸不同"],
                "opaque_instance_matches": 0, "opaque_part_matches": 0, "props_alpha_missing_labels": 0}
    token_pixels = ((pair[..., 0].astype(np.uint32) << 16)
                    | (pair[..., 1].astype(np.uint32) << 8)
                    | pair[..., 2].astype(np.uint32))
    covered = coverage[..., 3] == 255
    prop_mask = props[..., 3] > 127
    missing_labels = int(np.count_nonzero(prop_mask & ((token_pixels == 0) | ~covered)))
    if missing_labels:
        errors.append("frozen props alpha>0.5 有未标注像素")

    semantic_by_stable = {str(record.get("stable_id")): record
                          for record in instance_tokens if isinstance(record, dict)}
    capture_instances = capture.get("instances", [])
    old_rgb_to_ids: dict[tuple[int, int, int], list[dict]] = {}
    for old in capture_instances if isinstance(capture_instances, list) else []:
        if not isinstance(old, dict):
            continue
        stable_id = old.get("stable_id")
        color = _rgb_from_hex(old.get("color"))
        if not isinstance(stable_id, str) or color is None:
            continue
        if stable_id not in semantic_by_stable:
            errors.append(f"legacy instance {stable_id} 没有 sidecar stable token")
            continue
        old_rgb_to_ids.setdefault(color, []).append(old)
    token_lookup = {int(record["token"]): record for record in instance_tokens
                    if isinstance(record, dict) and type(record.get("token")) is int}
    legacy_rgb = legacy_ids[..., :3]
    legacy_alpha = legacy_ids[..., 3]
    alpha_bytes = coverage[..., 0]
    exact_opaque = (legacy_alpha == 255) & (alpha_bytes == 255) & covered
    opaque_instance_matches = 0
    instance_matches_by_kind: dict[str, int] = {}
    instance_mismatches = 0
    for old_rgb, old_records in old_rgb_to_ids.items():
        old_color_pixels = exact_opaque & np.all(legacy_rgb == np.array(old_rgb, dtype=np.uint8), axis=2)
        if not old_color_pixels.any():
            continue
        if len(old_records) != 1:
            errors.append("legacy opaque ID 色值存在多实例别名，相关像素不作猜测")
            continue
        old = old_records[0]
        expected = semantic_by_stable[str(old["stable_id"])]
        expected_token = int(expected["token"])
        side_token_at = token_pixels[old_color_pixels]
        for observed_token in np.unique(side_token_at):
            observed_token_int = int(observed_token)
            record = token_lookup.get(observed_token_int)
            if record is None or record.get("type") == "unknown":
                # An unknown actual prop may correctly cover the legacy-only object.
                continue
            count = int(np.count_nonzero(side_token_at == observed_token_int))
            if observed_token_int != expected_token:
                instance_mismatches += count
            else:
                opaque_instance_matches += count
                kind = str(expected.get("type", ""))
                instance_matches_by_kind[kind] = instance_matches_by_kind.get(kind, 0) + count
    if instance_mismatches:
        errors.append(f"同坐标 exact opaque legacy instance ID 与 sidecar token 不一致: {instance_mismatches}")
    if opaque_instance_matches <= 0:
        errors.append("没有任何 exact opaque legacy ID 像素可证明 sidecar 的实际像素配准")
    for kind in ("tree", "wall"):
        if instance_matches_by_kind.get(kind, 0) <= 0:
            errors.append(f"没有 {kind} exact opaque ID 配准锚点，不能对该类别声称像素对齐")

    part_classes = capture.get("masks", {}).get("part_ids", {}).get("classes", {})
    old_part_rgb_to_code: dict[tuple[int, int, int], list[int]] = {}
    for name, metadata in part_classes.items() if isinstance(part_classes, dict) else []:
        if name not in PART_CODES or not isinstance(metadata, dict):
            continue
        color = _rgb_from_hex(metadata.get("color"))
        if color is not None:
            old_part_rgb_to_code.setdefault(color, []).append(PART_CODES[name])
    opaque_part_mask = (legacy_parts[..., 3] == 255) & covered & (alpha_bytes == 255)
    opaque_part_matches = 0
    part_mismatches = 0
    side_part = pair[..., 3]
    for old_rgb, part_codes in old_part_rgb_to_code.items():
        mask = opaque_part_mask & np.all(legacy_parts[..., :3] == np.array(old_rgb, dtype=np.uint8), axis=2)
        if not mask.any():
            continue
        if len(part_codes) != 1:
            errors.append("legacy opaque part 色值存在多类别别名，相关像素不作猜测")
            continue
        expected_code = part_codes[0]
        known_current = np.isin(token_pixels, np.fromiter(
            (token for token, item in token_lookup.items() if item.get("type") != "unknown"), dtype=np.uint32))
        comparable = mask & known_current
        if not comparable.any():
            continue
        actual_codes = side_part[comparable]
        opaque_part_matches += int(comparable.sum())
        part_mismatches += int(np.count_nonzero(actual_codes != expected_code))
    if part_mismatches:
        errors.append(f"同坐标 exact opaque legacy part 像素类别不一致: {part_mismatches}")

    result_status = "PASS" if not errors else "FAIL"
    return {
        "status": result_status,
        "errors": errors,
        "method": "exact RGBA pixel comparison only; old labels are compared only when an opaque observed byte color maps uniquely; no nearest-color decoding",
        "props_alpha_gt_0_5_pixels": int(prop_mask.sum()),
        "props_alpha_missing_labels": missing_labels,
        "opaque_instance_matches": opaque_instance_matches,
        "opaque_instance_mismatches": instance_mismatches,
        "opaque_instance_matches_by_kind": instance_matches_by_kind,
        "opaque_part_matches": opaque_part_matches,
        "opaque_part_mismatches": part_mismatches,
    }


def _exact_palette_mask(image: np.ndarray, rgb: tuple[int, int, int] | None) -> np.ndarray:
    if rgb is None:
        return np.zeros(image.shape[:2], dtype=bool)
    return (image[..., 3] > 127) & np.all(image[..., :3] == np.array(rgb, dtype=np.uint8), axis=2)


def _blocking_mask(images: dict[str, np.ndarray]) -> tuple[np.ndarray, list[str]]:
    reasons: list[str] = []
    shape = images["main"].shape[:2]
    blocked = np.zeros(shape, dtype=bool)
    for role, label in (("exclusions", "units/HUD/exclusions"),
                        ("grid", "grid"), ("contact_shadow", "contact shadow")):
        image = images.get(role)
        if not _valid_rgba(image) or image.shape[:2] != shape:
            reasons.append(f"missing or size-mismatched {label} mask")
            continue
        blocked |= image[..., 3] > 127
    ground = images.get("ground")
    ground_without_shadow = images.get("ground_without_shadow")
    if not _valid_rgba(ground) or not _valid_rgba(ground_without_shadow) \
            or ground.shape != ground_without_shadow.shape or ground.shape[:2] != shape:
        reasons.append("missing or size-mismatched same-pixel shadow control layers")
    else:
        blocked |= np.any(ground != ground_without_shadow, axis=2)
    return blocked, reasons


def _ground_palette(manifest: dict) -> tuple[tuple[int, int, int] | None,
                                             set[tuple[int, int, int]], list[str]]:
    errors: list[str] = []
    classes = manifest.get("masks", {}).get("ground_types", {}).get("classes", {})
    if not isinstance(classes, dict):
        return None, set(), ["frozen ground_types palette is missing"]
    paving: tuple[int, int, int] | None = None
    grass: set[tuple[int, int, int]] = set()
    for name, value in classes.items():
        if not isinstance(value, dict):
            continue
        color = _rgb_from_hex(value.get("color"))
        if color is None:
            continue
        semantic = str(value.get("semantic", "")).lower()
        if name == "paving":
            paving = color
        if "grass" in semantic or "forest" in semantic:
            grass.add(color)
    if paving is None:
        errors.append("frozen ground_types has no paving class")
    if not grass:
        errors.append("frozen ground_types has no declared grass/forest class")
    return paving, grass, errors


def _not_tested(reason: str, **values: Any) -> dict:
    return metrics.missing(reason, **values)


def measure_t2_instances(manifest: dict, images: dict[str, np.ndarray],
                         pair: np.ndarray, coverage: np.ndarray,
                         instance_tokens: list[dict], blocked: np.ndarray) -> dict:
    main = images["main"]
    main_lab = checks.lab(main[..., :3])
    ground_types = images.get("ground_types")
    paving_rgb, _grass, palette_errors = _ground_palette(manifest)
    output: dict[str, list[dict]] = {"wall": [], "pillar": []}
    if palette_errors or not _valid_rgba(ground_types):
        reason = "; ".join(palette_errors) if palette_errors else "ground_types RGBA image is missing"
        for instance in instance_tokens:
            kind = instance.get("type")
            if kind in output:
                output[kind].append({"stable_id": instance.get("stable_id"),
                                     "status": "NOT_TESTED", "reason": reason,
                                     "top_pixels": 0, "side_pixels": 0, "paving_pixels": 0})
        return output
    paving_pixels_all = _exact_palette_mask(ground_types, paving_rgb)
    visible_alpha, uncertain_alpha = alpha_sample_masks(coverage)
    tokens = ((pair[..., 0].astype(np.uint32) << 16)
              | (pair[..., 1].astype(np.uint32) << 8)
              | pair[..., 2].astype(np.uint32))
    for instance in instance_tokens:
        kind = instance.get("type")
        if kind not in T2_PARTS:
            continue
        token = int(instance["token"])
        own_mask = (tokens == token) & visible_alpha & ~blocked
        top_mask = own_mask & np.isin(pair[..., 3], T2_PARTS[kind]["top"])
        side_mask = own_mask & np.isin(pair[..., 3], T2_PARTS[kind]["side"])
        outer_ring = metrics.morph(own_mask, 4) & ~own_mask
        adjacent_paving = outer_ring & paving_pixels_all & (coverage[..., 3] == 0) & ~blocked
        counts = {
            "top_pixels": int(top_mask.sum()),
            "side_pixels": int(side_mask.sum()),
            "paving_pixels": int(adjacent_paving.sum()),
            "alpha_uncertain_top_pixels": int((top_mask & uncertain_alpha).sum()),
            "alpha_uncertain_side_pixels": int((side_mask & uncertain_alpha).sum()),
            "alpha_uncertain_samples_included": True,
            "alpha_threshold_for_samples": ">127/255",
            "uncertain_if_alpha_below": 0.98,
        }
        if not counts["top_pixels"] or not counts["side_pixels"] or not counts["paving_pixels"]:
            result = _not_tested("top, side, or unoccluded radius-4 adjacent paving sample is empty", **counts)
        else:
            result = metrics.planes(main_lab[top_mask, 0], main_lab[side_mask, 0], main_lab[adjacent_paving, 0])
            result.update(counts)
        result["stable_id"] = instance.get("stable_id")
        result["type"] = kind
        result["token"] = token
        result["top_part_codes"] = list(T2_PARTS[kind]["top"])
        result["side_part_codes"] = list(T2_PARTS[kind]["side"])
        output[kind].append(result)
    return output


def _tree_semantic_measurement_gate(manifest: dict, sidecar: dict) -> list[str]:
    errors: list[str] = []
    tree = manifest.get("tree_semantic_input", {})
    if not isinstance(tree, dict):
        return ["capture-manifest tree semantic input is missing"]
    scopes = tree.get("approved_scope", [])
    if not isinstance(scopes, list) or "dark_side_geometry" not in scopes:
        errors.append("dark_side_geometry is not independently approved")
    if tree.get("status") not in ("APPROVED", "PARTIAL_APPROVAL"):
        errors.append("author/reviewer tree semantic inputs are not approved")
    if not tree.get("author_annotation_sha256") or not tree.get("independent_review_sha256"):
        errors.append("author/reviewer exact-byte hashes are missing")
    outline = tree.get("outline_semantics", {})
    if not isinstance(outline, dict) or type(outline.get("present")) is not bool:
        errors.append("outline semantics are not explicit")
    elif outline.get("present") is False:
        if "outline_absence" not in scopes or tree.get("effective_outline_status") != "absent_authoritatively":
            errors.append("empty outline data is not an independently approved absence")
    elif outline.get("present") is True:
        if "outline_geometry" not in scopes or tree.get("effective_outline_status") != "captured":
            errors.append("present outline has no validated reviewed geometry")
    if sidecar.get("tree_semantic_input") != tree:
        errors.append("sidecar tree semantic inputs do not exactly match the final capture manifest")
    return errors


def measure_t3_trees(manifest: dict, sidecar: dict, images: dict[str, np.ndarray],
                     pair: np.ndarray, coverage: np.ndarray,
                     instance_tokens: list[dict], blocked: np.ndarray) -> list[dict]:
    main = images["main"]
    main_lab = checks.lab(main[..., :3])
    ground_types = images.get("ground_types")
    crown_union = images.get("tree_crown_union")
    _paving, grass_palette, palette_errors = _ground_palette(manifest)
    semantic_gate_errors = _tree_semantic_measurement_gate(manifest, sidecar)
    if not _valid_rgba(ground_types) or not _valid_rgba(crown_union):
        palette_errors.append("frozen ground_types or tree_crown_union RGBA image is missing")
    tree_union = crown_union[..., 3] > 127 if _valid_rgba(crown_union) else None
    tree_palette_pixels = np.zeros(main.shape[:2], dtype=bool)
    if _valid_rgba(ground_types):
        for rgb in grass_palette:
            tree_palette_pixels |= _exact_palette_mask(ground_types, rgb)
    tokens = ((pair[..., 0].astype(np.uint32) << 16)
              | (pair[..., 1].astype(np.uint32) << 8)
              | pair[..., 2].astype(np.uint32))
    visible_alpha, uncertain_alpha = alpha_sample_masks(coverage)
    tree_records = [record for record in instance_tokens if record.get("type") == "tree"]
    all_tree_tokens = {int(record["token"]) for record in tree_records if type(record.get("token")) is int}
    any_tree_token = np.isin(tokens, np.fromiter(all_tree_tokens, dtype=np.uint32)) if all_tree_tokens else np.zeros(tokens.shape, bool)
    any_non_tree_prop = (coverage[..., 3] == 255) & ~any_tree_token
    crown_expected_visible = (tree_union & ~blocked & ~any_non_tree_prop) if tree_union is not None else np.zeros(tokens.shape, bool)
    semantic_tree_regions = any_tree_token & np.isin(pair[..., 3], np.fromiter(TREE_PART_CODES, dtype=np.uint8)) & visible_alpha
    tree_unknown = any_tree_token & (pair[..., 3] == UNKNOWN_PART_CODE) & visible_alpha
    crown_xor = crown_expected_visible ^ semantic_tree_regions
    crown_alignment = {
        "status": "PASS" if not crown_xor.any() and not tree_unknown.any() else "FAIL",
        "expected_visible_crown_pixels": int(crown_expected_visible.sum()),
        "sidecar_reviewed_crown_pixels": int(semantic_tree_regions.sum()),
        "union_mismatch_pixels": int(crown_xor.sum()),
        "unclassified_tree_pixels_alpha_gt_0_5": int(tree_unknown.sum()),
        "basis": "same-coordinate exact comparison with frozen tree_crown_union alpha; no transform-only alignment claim",
    }
    output: list[dict] = []
    for instance in tree_records:
        token = int(instance["token"])
        own_visible = (tokens == token) & visible_alpha & ~blocked
        crown = own_visible & np.isin(pair[..., 3], tuple(TREE_PART_CODES))
        dark_side = own_visible & (pair[..., 3] == PART_CODES["tree_dark_side"])
        outline = own_visible & (pair[..., 3] == PART_CODES["tree_outline"])
        unknown = own_visible & (pair[..., 3] == UNKNOWN_PART_CODE)
        outside_ring = metrics.morph(crown, 4) & ~crown
        grass = outside_ring & tree_palette_pixels & (coverage[..., 3] == 0) & ~blocked
        uncertain_crown = int((crown & uncertain_alpha).sum())
        outline_semantics = manifest.get("tree_semantic_input", {}).get("outline_semantics", {})
        if isinstance(outline_semantics, dict) and outline_semantics.get("present") is False:
            outline_status = "absent_authoritatively"
        elif outline.any():
            outline_status = "captured"
        else:
            outline_status = "NOT_TESTED"
        counts = {
            "crown_pixels": int(crown.sum()),
            "dark_side_pixels": int(dark_side.sum()),
            "outline_pixels": int(outline.sum()),
            "outer_grass_pixels": int(grass.sum()),
            "alpha_uncertain_crown_pixels": uncertain_crown,
            "alpha_uncertain_dark_side_pixels": int((dark_side & uncertain_alpha).sum()),
            "alpha_uncertain_samples_included": True,
            "alpha_threshold_for_samples": ">127/255",
            "uncertain_if_alpha_below": 0.98,
            "unclassified_tree_pixels_alpha_gt_0_5": int(unknown.sum()),
            "tree_crown_alignment": crown_alignment,
            "outline_status": outline_status,
        }
        reasons = list(semantic_gate_errors) + list(palette_errors)
        if crown_alignment["status"] != "PASS":
            reasons.append("sidecar tree regions do not exactly cover the visible frozen crown geometry")
        if not counts["crown_pixels"] or not counts["dark_side_pixels"] or not counts["outer_grass_pixels"]:
            reasons.append("crown, dark-side, or unoccluded radius-4 outer grass sample is empty")
        if unknown.any():
            reasons.append("visible tree pixels alpha>0.5 remain unclassified")
        if outline_status == "NOT_TESTED":
            reasons.append("outline absence/presence is not independently resolved")
        if reasons:
            outline_result = _not_tested("; ".join(dict.fromkeys(reasons)), **counts)
            foliage_result = _not_tested("T3 source/geometry/sample gate is incomplete", **counts)
        else:
            outline_result = metrics.foliage_outline(
                main_lab[..., 0], crown, outline, dark_side,
            )
            foliage_result = metrics.foliage(
                main_lab[crown], main_lab[grass], outline_check=outline_result,
            )
            outline_result.update(counts)
            foliage_result.update(counts)
        output.append({
            "stable_id": instance.get("stable_id"),
            "token": token,
            "outline_check": outline_result,
            "T3": foliage_result,
        })
    return output


def visible_instance_counts(pair: np.ndarray, coverage: np.ndarray,
                            instance_tokens: list[dict], blocked: np.ndarray) -> dict[str, dict]:
    tokens = ((pair[..., 0].astype(np.uint32) << 16)
              | (pair[..., 1].astype(np.uint32) << 8)
              | pair[..., 2].astype(np.uint32))
    visible_alpha, _uncertain = alpha_sample_masks(coverage)
    counts: dict[str, dict] = {}
    for kind in REQUIRED_VISIBLE_KINDS:
        records = [record for record in instance_tokens if record.get("type") == kind]
        visible_records = []
        for record in records:
            token = int(record["token"])
            pixels = int(np.count_nonzero((tokens == token) & visible_alpha & ~blocked))
            if pixels:
                visible_records.append({"stable_id": record.get("stable_id"), "pixels": pixels})
        counts[kind] = {"instances": len(records), "visible_instances": len(visible_records),
                        "required_visible_instances": 3, "records": visible_records,
                        "status": "PASS" if len(records) >= 3 and len(visible_records) >= 3 else "FAIL"}
    return counts


def _load_capture_images(manifest_path: Path, capture: dict) -> tuple[dict[str, np.ndarray], list[str]]:
    errors: list[str] = []
    records = capture.get("images", {})
    size = capture.get("case", {}).get("requested_resolution", [])
    arrays: dict[str, np.ndarray] = {}
    if not isinstance(records, dict):
        return {}, ["frozen images 元数据无效"]
    for role, record in records.items():
        if not isinstance(record, dict):
            errors.append(f"frozen {role} 图像元数据无效")
            continue
        try:
            path = _safe_relative(manifest_path.parent, record.get("path"))
            arrays[role] = _read_rgba_png(path, expected_size=size,
                                          expected_sha256=record.get("sha256"),
                                          expected_bytes=record.get("bytes"))
        except (OSError, ValueError) as error:
            errors.append(f"frozen {role}: {error}")
    return arrays, errors


def validate_case(capture_manifest_path: Path, source_root: Path,
                  expected_head: str, case_data: dict | None = None) -> dict:
    """Frozen V6/V5 checks run first; T2/T3 run only after all semantic gates pass."""
    capture = json.loads(capture_manifest_path.read_text(encoding="utf-8-sig"))
    if case_data is None:
        case_data = json.loads((source_root / v4.V4_CASE_FILE).read_text(encoding="utf-8-sig"))
    frozen = frozen_v6.validate(capture_manifest_path, source_root, expected_head, case_data)
    frozen_errors = list(frozen.get("errors", []))
    sidecar_path = capture_manifest_path.parent / SIDECAR_MANIFEST
    sidecar_errors: list[str] = []
    sidecar: dict = {}
    arrays: dict[str, np.ndarray] = {}
    try:
        sidecar = json.loads(sidecar_path.read_text(encoding="utf-8-sig"))
        sidecar_errors, arrays = validate_sidecar_binding(capture_manifest_path, capture, sidecar)
        sidecar_errors += sidecar_source_errors(capture, sidecar, source_root)
    except (OSError, ValueError, TypeError) as error:
        sidecar_errors.append(f"semantic sidecar manifest 无法读取: {error}")
    instance_tokens = sidecar.get("frame", {}).get("instance_tokens", []) if isinstance(sidecar, dict) else []
    if isinstance(sidecar, dict):
        sidecar_errors += validate_tree_classification_map(sidecar, instance_tokens, arrays)
    if arrays.get("semantic_pair") is not None and arrays.get("semantic_coverage") is not None:
        props = None
        try:
            props_path = _safe_relative(capture_manifest_path.parent,
                                        capture.get("images", {}).get("props", {}).get("path"))
            props = _read_rgba_png(props_path,
                                   expected_size=capture.get("case", {}).get("requested_resolution"),
                                   expected_sha256=capture.get("images", {}).get("props", {}).get("sha256"),
                                   expected_bytes=capture.get("images", {}).get("props", {}).get("bytes"))
        except (OSError, ValueError, TypeError) as error:
            sidecar_errors.append(f"frozen props 原像素无法读取: {error}")
        sidecar_errors += validate_label_coverage_arrays(arrays["semantic_pair"],
                                                         arrays["semantic_coverage"],
                                                         instance_tokens, props)
    else:
        sidecar_errors.append("sidecar 两张原始像素图未能成对读回")
    capture_images, image_errors = _load_capture_images(capture_manifest_path, capture)
    sidecar_errors += image_errors
    if arrays.get("semantic_pair") is not None and arrays.get("semantic_coverage") is not None \
            and not image_errors:
        alignment = pixel_alignment_report(capture, capture_images,
                                           arrays["semantic_pair"], arrays["semantic_coverage"],
                                           instance_tokens)
    else:
        alignment = {"status": "NOT_TESTED", "errors": ["alignment 的 frozen/source 图像不完整"]}
    sidecar_errors += alignment.get("errors", []) if alignment.get("status") == "FAIL" else []
    blocked = np.zeros(arrays["semantic_pair"].shape[:2], dtype=bool) if arrays.get("semantic_pair") is not None else np.zeros((0, 0), bool)
    blocking_errors: list[str] = []
    if capture_images and arrays.get("semantic_pair") is not None:
        blocked, blocking_errors = _blocking_mask(capture_images)
    sidecar_errors += blocking_errors
    sidecar_visible = visible_instance_counts(arrays["semantic_pair"], arrays["semantic_coverage"],
                                              instance_tokens, blocked) if arrays.get("semantic_pair") is not None \
        and arrays.get("semantic_coverage") is not None and blocked.shape == arrays["semantic_pair"].shape[:2] else {}
    visible_errors = [f"sidecar {kind} visible instances {record.get('visible_instances', 0)} < 3"
                      for kind, record in sidecar_visible.items() if record.get("status") != "PASS"]
    sidecar_errors += visible_errors
    semantic_alignment = "PASS" if not sidecar_errors and alignment.get("status") == "PASS" else "FAIL"
    ready = frozen.get("capture_preconditions") == "PASS" and semantic_alignment == "PASS"
    t2: dict[str, list[dict]] = {"wall": [], "pillar": []}
    t3: list[dict] = []
    if ready:
        t2 = measure_t2_instances(capture, capture_images, arrays["semantic_pair"],
                                  arrays["semantic_coverage"], instance_tokens, blocked)
        t3 = measure_t3_trees(capture, sidecar, capture_images, arrays["semantic_pair"],
                              arrays["semantic_coverage"], instance_tokens, blocked)
    else:
        reason = "冻结 V6/V5 或 sidecar provenance/alignment/visible-instance gate 未通过"
        for instance in instance_tokens if isinstance(instance_tokens, list) else []:
            kind = instance.get("type") if isinstance(instance, dict) else ""
            record = {"stable_id": instance.get("stable_id"), "status": "NOT_TESTED", "reason": reason}
            if kind in t2:
                t2[kind].append(record)
            elif kind == "tree":
                t3.append({"stable_id": instance.get("stable_id"),
                           "T3": _not_tested(reason), "outline_check": _not_tested(reason)})
    case = capture.get("case", {})
    return {
        "manifest": capture_manifest_path.name,
        "case": case,
        "frozen_capture_preconditions": frozen.get("capture_preconditions", "FAIL"),
        "frozen_capture_errors": frozen_errors,
        "semantic_sidecar_preconditions": semantic_alignment,
        "semantic_sidecar_errors": sidecar_errors,
        "pixel_alignment": alignment,
        "visible_instances": sidecar_visible,
        "T2_wall_instances": t2["wall"],
        "T2_pillar_instances": t2["pillar"],
        "T3_tree_instances": t3,
        "measurement_status": "MEASURED_WHERE_READY" if ready else "NOT_TESTED",
        "art_acceptance": "NOT_TESTED",
    }


def _batch_case_set(results: list[dict]) -> tuple[bool, set[tuple[tuple[int, ...], tuple[int, ...]]]]:
    cases: set[tuple[tuple[int, ...], tuple[int, ...]]] = set()
    for result in results:
        case = result.get("case", {})
        cases.add((tuple(case.get("map_size", [])), tuple(case.get("requested_resolution", []))))
    expected = {(size, resolution) for size in ((10, 10), (25, 25))
                for resolution in map(tuple, v1.RESOLUTIONS)}
    return len(results) == 6 and cases == expected, cases


def _numeric_metric(value: object) -> bool:
    return type(value) in (int, float) and math.isfinite(value)


def _negative_control_metric(row: dict) -> tuple[str, bool]:
    """Only numeric, non-empty frozen-metric outputs may establish a negative control."""
    t3 = row.get("T3")
    if isinstance(t3, dict):
        outline = row.get("outline_check", {})
        complete = (
            isinstance(outline, dict)
            and outline.get("status") in ("PASS", "FAIL")
            and all(type(t3.get(key)) is int and t3[key] > 0
                    for key in ("crown_pixels", "dark_side_pixels", "outer_grass_pixels"))
            and _numeric_metric(t3.get("delta_l"))
            and _numeric_metric(t3.get("delta_e00"))
            and _numeric_metric(outline.get("outline_pixels"))
        )
        status = str(t3.get("status", "NOT_TESTED"))
        return (status if complete and status in ("PASS", "FAIL") else "NOT_TESTED", complete)
    complete = (
        all(type(row.get(key)) is int and row[key] > 0
            for key in ("top_pixels", "side_pixels", "paving_pixels"))
        and all(_numeric_metric(row.get(key)) for key in ("top_l", "side_l", "paving_l"))
    )
    status = str(row.get("status", "NOT_TESTED"))
    return (status if complete and status in ("PASS", "FAIL") else "NOT_TESTED", complete)


def _negative_control(rows: list[dict], *, batch_ready: bool) -> dict:
    """Evaluate rows only when their own capture prerequisites are complete."""
    measured = [_negative_control_metric(row) for row in rows]
    statuses = [status for status, _complete in measured]
    failed = statuses.count("FAIL")
    passed = statuses.count("PASS")
    not_tested = statuses.count("NOT_TESTED")
    if not batch_ready or not rows:
        state = "NOT_TESTED"
    elif failed:
        state = "ESTABLISHED"
    elif not_tested:
        state = "NOT_TESTED"
    else:
        state = "NOT_ESTABLISHED"
    return {"status": state, "measured_failures": failed, "measured_passes": passed,
            "not_tested_rows": not_tested, "rows_reported": len(rows),
            "rows_with_numeric_metric_evidence": sum(complete for _status, complete in measured),
            "requires_actual_numeric_metric_FAIL": True,
            "reason": ("batch preconditions are incomplete" if not batch_ready else
                       ("no instances were reported" if not rows else None))}


def _pilot_gate(pilot: dict | None) -> dict:
    expected_map = (10, 10)
    expected_resolution = (1280, 720)
    case = pilot.get("case", {}) if isinstance(pilot, dict) else {}
    is_pilot_case = (tuple(case.get("map_size", [])) == expected_map
                     and tuple(case.get("requested_resolution", [])) == expected_resolution)
    preconditions_pass = bool(
        is_pilot_case
        and pilot.get("frozen_capture_preconditions") == "PASS"
        and pilot.get("semantic_sidecar_preconditions") == "PASS"
    ) if isinstance(pilot, dict) else False
    wall_rows = pilot.get("T2_wall_instances", []) if isinstance(pilot, dict) else []
    pillar_rows = pilot.get("T2_pillar_instances", []) if isinstance(pilot, dict) else []
    tree_rows = pilot.get("T3_tree_instances", []) if isinstance(pilot, dict) else []
    wall_negative = _negative_control(wall_rows, batch_ready=preconditions_pass)
    pillar_negative = _negative_control(pillar_rows, batch_ready=preconditions_pass)
    tree_negative = _negative_control(tree_rows, batch_ready=preconditions_pass)
    material_gate = (
        "OPEN_FOR_MATERIAL_ITERATION_REVIEW"
        if preconditions_pass
        and wall_negative["status"] == "ESTABLISHED"
        and tree_negative["status"] == "ESTABLISHED"
        else "CLOSED"
    )
    reason = None
    if pilot is None:
        reason = "10x10/1280x720 pilot case is missing"
    elif not is_pilot_case:
        reason = "the supplied single case is not 10x10/1280x720"
    elif not preconditions_pass:
        reason = "pilot frozen capture or semantic sidecar preconditions did not PASS"
    return {
        "preconditions": "PASS" if preconditions_pass else "FAIL_OR_MISSING",
        "precondition_components": {
            "case_is_10x10_1280x720": is_pilot_case,
            "frozen_capture": pilot.get("frozen_capture_preconditions", "MISSING") if isinstance(pilot, dict) else "MISSING",
            "semantic_sidecar": pilot.get("semantic_sidecar_preconditions", "MISSING") if isinstance(pilot, dict) else "MISSING",
        },
        "precondition_reason": reason,
        "remaining_five_capture_action": "CONTINUE" if preconditions_pass else "STOP",
        "negative_controls": {
            "old_wall_T2": wall_negative,
            "old_pillar_T2": pillar_negative,
            "old_tree_complete_T3": tree_negative,
            "scope": "This 10x10/1280x720 pilot only; rows are not combined across cases.",
        },
        "material_gate": material_gate,
    }


def validate_pilot(manifest_paths: list[Path], source_root: Path,
                   expected_head: str) -> dict:
    """Read exactly one pilot; pilot prerequisites decide STOP/CONTINUE."""
    pilot: dict | None = None
    errors: list[str] = []
    if len(manifest_paths) != 1:
        errors.append("pilot phase requires exactly one capture-manifest.json")
    else:
        try:
            case_data = json.loads((source_root / v4.V4_CASE_FILE).read_text(encoding="utf-8-sig"))
            pilot = validate_case(manifest_paths[0], source_root, expected_head, case_data)
        except (OSError, ValueError, KeyError, TypeError, IndexError) as error:
            errors.append(str(error))
            pilot = {
                "manifest": manifest_paths[0].name,
                "case": {},
                "frozen_capture_preconditions": "FAIL",
                "semantic_sidecar_preconditions": "FAIL",
                "frozen_capture_errors": [str(error)],
                "semantic_sidecar_errors": [str(error)],
                "T2_wall_instances": [],
                "T2_pillar_instances": [],
                "T3_tree_instances": [],
                "measurement_status": "NOT_TESTED",
                "art_acceptance": "NOT_TESTED",
            }
    gate = _pilot_gate(pilot)
    output = {
        "schema_version": "terrain-semantic-sidecar-readback/1",
        "phase": "pilot",
        "candidate_head": expected_head,
        "six_case_coverage": False,
        "batch_frozen_and_semantic_preconditions": "NOT_RUN_IN_PILOT_PHASE",
        "batch_final_gate": "NOT_RUN_IN_PILOT_PHASE",
        "cases": [pilot] if pilot is not None else [],
        "pilot_10x10_720p": gate,
        "negative_controls": gate["negative_controls"],
        "material_gate": gate["material_gate"],
        "pilot_validation_errors": errors,
        "T1_T4_T5_T6": "NOT_TESTED_BY_SEMANTIC_SIDECAR_VALIDATOR",
        "measurement_status": pilot.get("measurement_status", "NOT_TESTED") if pilot else "NOT_TESTED",
        "art_acceptance": "NOT_TESTED",
        "note": "Pilot exit status is determined only by the single 10x10/1280x720 frozen and semantic prerequisites. A passing pilot continues even when either numeric negative control is missing or not FAIL; in that case material_gate remains CLOSED. No other capture or art acceptance is implied.",
    }
    return output


def validate_batch(manifest_paths: list[Path], source_root: Path,
                   expected_head: str) -> dict:
    case_data = json.loads((source_root / v4.V4_CASE_FILE).read_text(encoding="utf-8-sig"))
    results: list[dict] = []
    for path in manifest_paths:
        try:
            results.append(validate_case(path, source_root, expected_head, case_data))
        except (OSError, ValueError, KeyError, TypeError, IndexError) as error:
            results.append({"manifest": path.name, "case": {},
                            "frozen_capture_preconditions": "FAIL",
                            "semantic_sidecar_preconditions": "FAIL",
                            "semantic_sidecar_errors": [str(error)],
                            "measurement_status": "NOT_TESTED", "art_acceptance": "NOT_TESTED"})
    complete, observed_cases = _batch_case_set(results)
    all_ready = complete and all(result.get("frozen_capture_preconditions") == "PASS"
                                 and result.get("semantic_sidecar_preconditions") == "PASS"
                                 for result in results)
    pilot = next((result for result in results
                  if tuple(result.get("case", {}).get("map_size", [])) == (10, 10)
                  and tuple(result.get("case", {}).get("requested_resolution", [])) == (1280, 720)), None)
    pilot_gate = _pilot_gate(pilot)
    pilot_negative_controls = pilot_gate["negative_controls"]
    output = {
        "schema_version": "terrain-semantic-sidecar-readback/1",
        "phase": "batch",
        "candidate_head": expected_head,
        "six_case_coverage": complete,
        "observed_cases": [
            {"map_size": list(map_size), "resolution": list(resolution)}
            for map_size, resolution in sorted(observed_cases)
        ],
        "pilot_10x10_720p": pilot_gate,
        "batch_frozen_and_semantic_preconditions": "PASS" if all_ready else "FAIL_OR_INCOMPLETE",
        "batch_final_gate": "PASS" if complete and all_ready else "FAIL_OR_INCOMPLETE",
        "cases": results,
        "negative_controls": pilot_negative_controls,
        "material_gate": pilot_gate["material_gate"],
        "T1_T4_T5_T6": "NOT_TESTED_BY_SEMANTIC_SIDECAR_VALIDATOR",
        "measurement_status": "T2_T3_MEASURED_WHERE_READY" if any(
            result.get("measurement_status") == "MEASURED_WHERE_READY" for result in results
        ) else "NOT_TESTED",
        "art_acceptance": "NOT_TESTED",
        "note": "Metrics come only from main-image pixels at exact same coordinates; full RGBA/candidate/C4/C8 and sidecar pixel-alignment gates precede measurement. A .98 uncertainty flag never removes an alpha>0.5 sample. The material iteration gate uses only the pilot rows; the six-case final gate is separate. No T1-T6 or art-acceptance completion is implied.",
    }
    return output


def validation_exit_code(phase: str, output: dict) -> int:
    if phase == "pilot":
        return 0 if output.get("pilot_10x10_720p", {}).get("preconditions") == "PASS" else 1
    return 0 if output.get("six_case_coverage") \
        and output.get("batch_final_gate") == "PASS" else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifests", type=Path, nargs="+")
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--phase", choices=("pilot", "batch"), default="batch")
    args = parser.parse_args()
    source_root = args.source_root.resolve()
    try:
        head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=source_root,
                              capture_output=True, text=True, encoding="utf-8",
                              timeout=15, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        parser.error(f"无法读取源码工作树 Git HEAD: {error}")
    if head.returncode != 0 or head.stdout.strip() != args.candidate:
        parser.error("源码工作树 HEAD 与传入 candidate 不一致")
    try:
        output = (validate_pilot(args.manifests, source_root, args.candidate)
                  if args.phase == "pilot"
                  else validate_batch(args.manifests, source_root, args.candidate))
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.error(f"无法构建 semantic sidecar 报告: {error}")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "phase": output["phase"],
        "six_case_coverage": output["six_case_coverage"],
        "pilot_10x10_720p": output["pilot_10x10_720p"]["preconditions"],
        "pilot_action": output["pilot_10x10_720p"]["remaining_five_capture_action"],
        "batch_preconditions": output["batch_frozen_and_semantic_preconditions"],
        "wall_negative": output["negative_controls"]["old_wall_T2"]["status"],
        "tree_negative": output["negative_controls"]["old_tree_complete_T3"]["status"],
        "material_gate": output["material_gate"],
        "art_acceptance": output["art_acceptance"],
    }, ensure_ascii=False))
    return validation_exit_code(args.phase, output)


if __name__ == "__main__":
    raise SystemExit(main())
