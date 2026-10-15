"""R7 occupancy-backed U1 readback; frozen capture, T2/T3/C9 gates stay in force."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

import claude_review_checks as checks
import terrain_contour_v3 as contour
import validate_terrain_acceptance_v2 as v2
import validate_terrain_semantic_sidecar as sidecar


SCHEMA = "terrain-acceptance-readback/3"
KINDS = v2.KINDS
OCCUPANCY_SCHEMA = "terrain-composite-occupancy/1"
CONTROL_SCHEMA = "terrain-composite-occupancy-controls/1"
R7_SOURCE_PATHS = (
    "tests/claude_review/capture_terrain_readability_r7.gd",
    "tests/claude_review/terrain_composite_occupancy.gdshader",
    "tests/claude_review/terrain_contour_v3.py",
    "tests/claude_review/validate_terrain_acceptance_v3.py",
    "tests/claude_review/test_terrain_acceptance_v3.py",
)
NATIVE_CONTROL_SAMPLES = (
    ("N1_same_instance_alpha_0_48_seam", 6, 8, 101),
    ("N1_same_instance_alpha_0_48_seam", 16, 18, 101),
    ("N2_true_hole", 40, 8, 102),
    ("N2_true_hole", 50, 18, 0),
    ("N3_other_alpha_0_4_overlay", 76, 10, 103),
    ("N3_other_alpha_0_4_overlay", 92, 18, 103),
    ("N4_unknown_opaque_overlay", 110, 10, 104),
    ("N4_unknown_opaque_overlay", 126, 18, 199),
    ("N5_standalone_alpha_0_5", 152, 18, 0),
)
NATIVE_CONTROL_ALPHA = (1.0, 0.48, 1.0, 0.0, 1.0, 0.4, 1.0, 1.0, 0.5)


def _token_pixels(rgba: np.ndarray) -> np.ndarray:
    token = ((rgba[..., 0].astype(np.uint32) << 16)
             | (rgba[..., 1].astype(np.uint32) << 8)
             | rgba[..., 2].astype(np.uint32))
    return np.where(rgba[..., 3] == 255, token, 0).astype(np.uint32)


def occupancy_metadata_errors(capture: dict, semantic: dict) -> list[str]:
    """Validate mandatory R7 image/control metadata without opening their PNGs."""
    errors: list[str] = []
    candidate = capture.get("candidate", {})
    candidate_sources = candidate.get("source_sha256", {}) if isinstance(candidate, dict) else {}
    frame = semantic.get("frame", {}) if isinstance(semantic, dict) else {}
    common = capture.get("common_frame", {}) if isinstance(capture, dict) else {}
    occupancy = semantic.get("composite_occupancy") if isinstance(semantic, dict) else None
    controls = semantic.get("native_occupancy_controls") if isinstance(semantic, dict) else None
    if not isinstance(occupancy, dict):
        errors.append("缺少 composite_occupancy 原生占据图记录")
    if not isinstance(controls, dict):
        errors.append("缺少 native_occupancy_controls 同帧负例记录")
    if not isinstance(frame, dict) or not isinstance(common, dict):
        return errors + ["R7/capture common_frame 结构无效"]
    if frame.get("callback") != "RenderingServer.frame_post_draw" or frame.get("same_frame") is not True:
        errors.append("R7 sidecar 未绑定 frame_post_draw 同帧回读")
    for key in ("frame_id", "frames_drawn_before", "frames_drawn_after",
                "process_frames_before", "process_frames_after"):
        if frame.get(key) != common.get(key):
            errors.append(f"R7 sidecar {key} 与原始捕获同帧记录不一致")
    if frame.get("original_capture_image_count_unchanged") != 12:
        errors.append("R7 未保留原始 12 图读取集合")
    if not isinstance(candidate_sources, dict) or not candidate_sources:
        errors.append("capture candidate.source_sha256 缺失")
        candidate_sources = {}
    if not isinstance(occupancy, dict) or not isinstance(controls, dict):
        return errors

    if occupancy.get("schema_version") != OCCUPANCY_SCHEMA or occupancy.get("role") != "composite_occupancy":
        errors.append("composite_occupancy schema 或 role 无效")
    if controls.get("schema_version") != CONTROL_SCHEMA or controls.get("role") != "native_occupancy_controls":
        errors.append("native_occupancy_controls schema 或 role 无效")
    for label, record in (("composite_occupancy", occupancy), ("native_occupancy_controls", controls)):
        if record.get("callback") != "RenderingServer.frame_post_draw" or record.get("same_frame") is not True:
            errors.append(f"{label} 未声明 frame_post_draw 同帧回读")
        if record.get("frame_id") != frame.get("frame_id"):
            errors.append(f"{label} frame_id 与 semantic source-alpha 同帧不同")
        if record.get("candidate_source_sha256") != candidate_sources:
            errors.append(f"{label} 未绑定完整 candidate source 摘要")
        if record.get("capture_candidate_digest_sha256") != candidate.get("candidate_digest_sha256"):
            errors.append(f"{label} candidate digest 与 capture-manifest 不一致")
        image = record.get("image", {})
        if not isinstance(image, dict) or image.get("frame_id") != frame.get("frame_id"):
            errors.append(f"{label} 缺少相同 frame_id 的 PNG 原图记录")
        elif image.get("role") != label or image.get("mime_type") != "image/png" \
                or image.get("pixel_format") != "RGBA8":
            errors.append(f"{label} 原图 role、PNG 或 RGBA8 记录无效")
    if occupancy.get("effective_alpha_rule") != "discard when effective COLOR.a <= 0.5; write the instance token when COLOR.a > 0.5":
        errors.append("composite_occupancy alpha cutoff 记录不符合冻结口径")
    if occupancy.get("blend_mode") != "blend_disabled" or occupancy.get("last_qualifying_draw_owns_pixel") is not True:
        errors.append("composite_occupancy 未证明 blend_disabled 与最后合格绘制者语义")
    if occupancy.get("unknown_props_keep_nonzero_tokens") is not True:
        errors.append("composite_occupancy 未保留 unknown prop token")
    if occupancy.get("source_alpha_coverage_unchanged") is not True \
            or occupancy.get("source_alpha_uncertainty_unchanged") is not True:
        errors.append("R7 未声明旧 source-alpha / uncertainty 原样保留")
    expected_shader_path = "res://tests/claude_review/terrain_composite_occupancy.gdshader"
    if occupancy.get("shader_path") != expected_shader_path:
        errors.append("composite_occupancy 没有记录实际占据 shader 路径")
    shader_relative = expected_shader_path.removeprefix("res://")
    if occupancy.get("shader_source_sha256") != candidate_sources.get(shader_relative):
        errors.append("composite_occupancy shader 原字节摘要没有绑定 candidate source")
    bindings = occupancy.get("material_bindings")
    tokens = frame.get("instance_tokens", [])
    if not isinstance(bindings, list) or not isinstance(tokens, list):
        errors.append("composite_occupancy 缺少逐叶 material 绑定或实例来源记录")
    else:
        token_by_id = {row.get("stable_id"): row for row in tokens
                       if isinstance(row, dict) and isinstance(row.get("stable_id"), str)}
        expected_leaves: set[tuple[str, str]] = set()
        for row in token_by_id.values():
            signatures = row.get("draw_leaf_signatures", {})
            leaves = signatures.get("occupancy", []) if isinstance(signatures, dict) else []
            if not isinstance(leaves, list):
                errors.append("occupancy draw leaf signatures 格式无效")
                continue
            for leaf in leaves:
                if isinstance(leaf, dict) and isinstance(leaf.get("relative_path"), str):
                    expected_leaves.add((str(row["stable_id"]), leaf["relative_path"]))
                else:
                    errors.append("occupancy draw leaf signature 缺少相对路径")
        observed_leaves: set[tuple[str, str]] = set()
        shader_hashes: set[str] = set()
        for binding in bindings:
            if not isinstance(binding, dict):
                errors.append("occupancy material binding 格式无效")
                continue
            stable_id = binding.get("stable_id")
            relative_path = binding.get("relative_path")
            leaf_key = (stable_id, relative_path)
            if (binding.get("mode") != "occupancy"
                    or binding.get("canvas_valid") is not True
                    or binding.get("shader_material_bound") is not True
                    or binding.get("shader_declares_blend_disabled") is not True
                    or binding.get("use_parent_material") is not False):
                errors.append("occupancy draw leaf 没有绑定有效 blend_disabled material")
            if leaf_key in observed_leaves:
                errors.append("occupancy draw leaf material 绑定重复")
            observed_leaves.add(leaf_key)
            if leaf_key not in expected_leaves:
                errors.append("occupancy material binding 不对应任何已记录 draw leaf")
            instance = token_by_id.get(stable_id)
            rgb = binding.get("instance_token_rgb")
            declared_rgb = instance.get("token_rgb") if isinstance(instance, dict) else None
            if (not isinstance(rgb, list) or len(rgb) != 3 or not isinstance(declared_rgb, list)
                    or len(declared_rgb) != 3
                    or not np.allclose(rgb, np.asarray(declared_rgb, dtype=np.float64) / 255.0,
                                       atol=1e-6, rtol=0)):
                errors.append("occupancy material token RGB 与稳定实例 token 不一致")
            digest = binding.get("shader_code_sha256")
            if not isinstance(digest, str) or len(digest) != 64 \
                    or any(character not in "0123456789abcdef" for character in digest.lower()):
                errors.append("occupancy material 缺少 Shader.code SHA256")
            else:
                shader_hashes.add(digest.lower())
            if binding.get("effective_alpha_source") != "incoming CanvasItem COLOR.a after source texture/primitive alpha and inherited modulation":
                errors.append("occupancy material alpha 来源没有绑定原 draw leaf 输入")
        if observed_leaves != expected_leaves:
            errors.append("occupancy material 绑定没有逐一覆盖同一源层的 draw leaves")
        if len(shader_hashes) > 1:
            errors.append("occupancy draw leaves 实际绑定了多个 shader code")
    if controls.get("pass") is not True:
        errors.append("原生 N1-N5 occupancy 控制未通过")
    recorded_samples = controls.get("samples", [])
    if not isinstance(recorded_samples, list) or len(recorded_samples) != len(NATIVE_CONTROL_SAMPLES):
        errors.append("原生 N1-N5 occupancy 控制 alpha 样本记录不完整")
    else:
        for index, (sample, expected_alpha) in enumerate(zip(recorded_samples, NATIVE_CONTROL_ALPHA, strict=True)):
            polygon_alpha = sample.get("polygon_color_a")
            self_modulate_alpha = sample.get("self_modulate_a")
            effective_alpha = sample.get("effective_alpha_expected")
            valid_alpha_values = all(isinstance(value, (int, float)) and np.isfinite(value)
                                     for value in (polygon_alpha, self_modulate_alpha, effective_alpha))
            if (not valid_alpha_values or abs(float(polygon_alpha) - 1.0) > 1e-6
                    or abs(float(self_modulate_alpha) - expected_alpha) > 1e-6
                    or abs(float(effective_alpha) - expected_alpha) > 1e-6
                    or sample.get("effective_alpha_input") != "incoming COLOR.a from Polygon2D.color * CanvasItem.self_modulate"):
                errors.append(f"native {sample.get('case', index)} alpha 路径未以 self_modulate 精确保留")
    return errors


def _source_errors(capture: dict, source_root: Path) -> list[str]:
    errors: list[str] = []
    candidate = capture.get("candidate", {})
    hashes = candidate.get("source_sha256", {}) if isinstance(candidate, dict) else {}
    if not isinstance(hashes, dict):
        return ["capture candidate.source_sha256 不是对象"]
    manifest_sources = capture.get("sources", {})
    if not isinstance(manifest_sources, dict):
        manifest_sources = {}
        errors.append("capture manifest.sources 不是对象")
    config = capture.get("capture_config", {})
    if config.get("capture_entry_script") != "res://tests/claude_review/capture_terrain_readability_r7.gd":
        errors.append("capture config 没有指向 R7 capture entry")
    if config.get("composite_occupancy_shader") != "res://tests/claude_review/terrain_composite_occupancy.gdshader":
        errors.append("capture config 没有绑定 R7 occupancy shader")
    for relative in R7_SOURCE_PATHS:
        path = source_root / relative
        try:
            actual = hashlib.sha256(path.read_bytes()).hexdigest()
        except OSError:
            errors.append(f"R7 source 文件缺失：{relative}")
            continue
        if hashes.get(relative) != actual:
            errors.append(f"capture candidate 未绑定当前 R7 source：{relative}")
        if manifest_sources.get("res://" + relative) != actual:
            errors.append(f"capture manifest.sources 未绑定当前 R7 source：{relative}")
    return errors


def _viewport_errors(occupancy: dict, semantic_frame: dict, expected_size: list[int]) -> list[str]:
    errors: list[str] = []
    view = occupancy.get("viewport", {})
    viewports = semantic_frame.get("viewports", {})
    pair = viewports.get("semantic_pair", {}) if isinstance(viewports, dict) else {}
    if not isinstance(view, dict) or not isinstance(pair, dict):
        return ["occupancy/semantic_pair viewport 记录无效"]
    if view.get("image_size") != expected_size:
        errors.append("occupancy 原生 PNG 尺寸与 requested_resolution 不同")
    if view.get("image_size") != pair.get("image_size"):
        errors.append("occupancy 与 semantic_pair 原生像素尺寸不同")
    for key in ("size", "size_2d_override", "size_2d_override_stretch",
                "canvas_transform", "final_transform", "texture_size", "visible_rect"):
        left, right = view.get(key), pair.get(key)
        if isinstance(left, list) and isinstance(right, list):
            if len(left) != len(right) or not np.allclose(left, right, atol=0.001, rtol=0):
                errors.append(f"occupancy 与 semantic_pair {key} 不一致")
        elif left != right:
            errors.append(f"occupancy 与 semantic_pair {key} 不一致")
    return errors


def validate_occupancy_binding(manifest_path: Path, capture: dict, semantic: dict,
                               source_root: Path) -> tuple[list[str], dict[str, np.ndarray]]:
    errors = occupancy_metadata_errors(capture, semantic)
    errors += _source_errors(capture, source_root)
    arrays: dict[str, np.ndarray] = {}
    frame = semantic.get("frame", {}) if isinstance(semantic, dict) else {}
    if not isinstance(frame, dict):
        return errors + ["R7 semantic frame 结构无效"], arrays
    case = capture.get("case", {}) if isinstance(capture, dict) else {}
    requested_size = case.get("requested_resolution") if isinstance(case, dict) else None
    if not isinstance(requested_size, list) or len(requested_size) != 2:
        errors.append("capture requested_resolution 无效")
        return errors, arrays
    occupancy = semantic.get("composite_occupancy", {})
    controls = semantic.get("native_occupancy_controls", {})
    if not isinstance(occupancy, dict) or not isinstance(controls, dict):
        return errors + ["R7 occupancy 或原生控制记录缺失/格式无效"], arrays
    errors += _viewport_errors(occupancy, frame, requested_size)
    if controls.get("viewport", {}).get("image_size") != [176, 40]:
        errors.append("native N1-N5 control PNG 尺寸无效")

    forbidden_paths = {
        row.get("path") for row in frame.get("images", {}).values()
        if isinstance(row, dict)
    }
    seen_paths: set[Path] = set()
    for label, record, expected_size in (
            ("composite_occupancy", occupancy, requested_size),
            ("native_occupancy_controls", controls, [176, 40])):
        image_record = record.get("image", {})
        try:
            relative_name = image_record.get("path")
            if relative_name in forbidden_paths:
                raise ValueError("R7 图像复用了旧 sidecar PNG")
            path = sidecar._safe_relative(manifest_path.parent, relative_name)
            if path in seen_paths:
                raise ValueError("R7 occupancy/control 复用了同一 PNG")
            seen_paths.add(path)
            arrays[label] = sidecar._read_rgba_png(
                path, expected_size=expected_size,
                expected_sha256=image_record.get("sha256"),
                expected_bytes=image_record.get("bytes"))
        except (OSError, TypeError, ValueError) as error:
            errors.append(f"{label}: {error}")

    occupancy_pixels = arrays.get("composite_occupancy")
    if occupancy_pixels is not None:
        alpha = occupancy_pixels[..., 3]
        tokens = _token_pixels(occupancy_pixels)
        if np.any((alpha != 0) & (alpha != 255)):
            errors.append("occupancy 原图 alpha 只能为 0 或 255")
        if np.any((alpha == 0) & np.any(occupancy_pixels[..., :3] != 0, axis=2)):
            errors.append("occupancy 空背景 token 必须为零")
        if np.any((alpha == 255) & (tokens == 0)):
            errors.append("occupancy 非空像素必须含非零实例 token")
        declared = {row.get("token") for row in frame.get("instance_tokens", [])
                    if isinstance(row, dict) and type(row.get("token")) is int}
        observed = set(map(int, np.unique(tokens))) - {0}
        if not observed.issubset(declared):
            errors.append("occupancy 原图出现未声明的 prop token")

    controls_pixels = arrays.get("native_occupancy_controls")
    if controls_pixels is not None:
        if np.any((controls_pixels[..., 3] != 0) & (controls_pixels[..., 3] != 255)):
            errors.append("native occupancy control alpha 只能为 0 或 255")
        control_tokens = _token_pixels(controls_pixels)
        for case_id, x, y, expected_token in NATIVE_CONTROL_SAMPLES:
            observed = int(control_tokens[y, x])
            if observed != expected_token:
                errors.append(f"native {case_id} sample ({x},{y}) expected token {expected_token}, got {observed}")
        recorded = controls.get("samples", [])
        if not isinstance(recorded, list) or len(recorded) != len(NATIVE_CONTROL_SAMPLES):
            errors.append("native N1-N5 control sample record set is incomplete")
        else:
            for expected, actual in zip(NATIVE_CONTROL_SAMPLES, recorded, strict=True):
                case_id, x, y, token = expected
                if (actual.get("case") != case_id or actual.get("xy") != [x, y]
                        or actual.get("expected_token") != token
                        or actual.get("observed_token") != token or actual.get("matched") is not True):
                    errors.append(f"native {case_id} sample record does not match its fixed assertion")

    return errors, arrays


def contexts(capture: dict, images: dict, pair: np.ndarray, coverage: np.ndarray,
             occupancy_rgba: np.ndarray, records: list[dict]) -> list[dict]:
    _source_visible, uncertain = sidecar.alpha_sample_masks(coverage)
    source_tokens = ((pair[..., 0].astype(np.uint32) << 16)
                     | (pair[..., 1].astype(np.uint32) << 8) | pair[..., 2].astype(np.uint32))
    occupancy_tokens = _token_pixels(occupancy_rgba)
    ui_units = images["exclusions"][..., 3] > 127
    grid = images["grid"][..., 3] > 127
    grouped = {}
    for kind in ("wall", "tree"):
        grouped.update(sidecar._captured_connected_groups(
            capture, records, pair, coverage, kind=kind,
            member_part_codes=sidecar.TREE_PART_CODES if kind == "tree" else None))
    by_id = {r["stable_id"]: r for r in records if r.get("type") in KINDS}
    output = []
    source_drawn = coverage[..., 3] == 255
    low_source_alpha = source_drawn & (coverage[..., 0] <= 127)
    for key in sorted(by_id):
        record = by_id[key]
        info = grouped.get(key, {}).get("measurement_group", {})
        members = info.get("members", [key])
        member_tokens = [by_id[member]["token"] for member in members]
        own, group = contour.token_masks(occupancy_tokens, int(record["token"]), member_tokens)
        other_source_draw = source_drawn & (source_tokens != int(record["token"]))
        other_occupied = (occupancy_tokens != 0) & (occupancy_tokens != int(record["token"]))
        blocked = other_source_draw | other_occupied
        excluded = ui_units | grid | other_source_draw | other_occupied | low_source_alpha
        output.append({"record": record, "own": own, "group": group,
                       "group_id": info.get("group_id", key), "members": members,
                       "group_status": info.get("status", "PASS"),
                       "excluded": excluded, "blocked": blocked,
                       "uncertain_pixels": int((own & uncertain).sum()),
                       "same_instance_low_alpha_pixels_excluded": int(
                           (own & low_source_alpha & (source_tokens == int(record["token"]))).sum()),
                       "other_source_pixels_excluded": int((own & other_source_draw).sum())})
    return output


def measure(capture: dict, frozen_case: dict, images: dict, arrays: dict,
            semantic: dict) -> dict:
    pair, coverage = arrays["semantic_pair"], arrays["semantic_coverage"]
    occupancy = arrays["composite_occupancy"]
    records = semantic["frame"]["instance_tokens"]
    lightness = checks.lab(images["main"][..., :3])[..., 0]
    is_720 = images["main"].shape[:2] == (720, 1280)
    blurred = (checks.lab(np.asarray(Image.fromarray(images["main"][..., :3]).filter(
        ImageFilter.GaussianBlur(2))))[..., 0] if is_720 else None)
    output = []
    for context in contexts(capture, images, pair, coverage, occupancy, records):
        record = context["record"]
        t1 = contour.measure(lightness, context["own"], context["group"], context["excluded"],
                             blocked_pixels=context["blocked"])
        t6 = (contour.measure(blurred, context["own"], context["group"], context["excluded"],
                              blocked_pixels=context["blocked"], squint=True)
              if is_720 else {"status": "NOT_TESTED", "reason": "T6 requires native 1280x720"})
        if context["group_status"] != "PASS":
            for metric in (t1, t6):
                metric.update(status="NOT_TESTED", reason="captured group is incomplete")
        output.append({"stable_id": record["stable_id"], "type": record["type"],
                       "group_id": context["group_id"], "group_members": context["members"],
                       "uncertain_pixels_retained": context["uncertain_pixels"],
                       "same_instance_low_alpha_pixels_excluded": context["same_instance_low_alpha_pixels_excluded"],
                       "other_source_pixels_excluded": context["other_source_pixels_excluded"],
                       "T1": t1, "T6": t6,
                       "T1_required_for_acceptance": record["type"] != "tree",
                       "T6_required_for_acceptance": record["type"] != "tree" and is_720})
    c9_rows = v2.measure_c9(capture, images, pair, coverage, records)
    c9 = v2.c9_gate(c9_rows)
    t3_rows = frozen_case["T3_tree_instances"]
    all_t3 = bool(t3_rows) and all(row["T3"]["status"] == "PASS" for row in t3_rows)
    summary = {kind: {metric: {status: sum(row["type"] == kind and row[metric]["status"] == status
                                          for row in output)
                              for status in ("PASS", "FAIL", "NOT_TESTED")}
                      for metric in ("T1", "T6")} for kind in KINDS}
    return {"instances": output, "summary": summary, "C9_trees": c9_rows, "C9_gate": c9,
            "tree_numeric_gate": {"status": "PASS" if all_t3 and c9["status"] == "PASS" else "FAIL",
                                  "T3_all_declared_trees_pass": all_t3,
                                  "T1_T6_are_diagnostics": True,
                                  "visual_approval": "SEPARATE_REQUIRED_REVIEW"}}


def validate(manifest_path: Path, source_root: Path, expected_head: str) -> dict:
    source_root = source_root.resolve()
    old = v2.baseline.validate(manifest_path, source_root, expected_head)
    capture = json.loads(manifest_path.read_bytes())
    semantic_path = manifest_path.parent / sidecar.SIDECAR_MANIFEST
    errors: list[str] = []
    values: dict
    if old["capture_preconditions"] == "PASS":
        semantic = json.loads(semantic_path.read_bytes())
        side_errors, arrays = sidecar.validate_sidecar_binding(manifest_path, capture, semantic)
        images, image_errors = sidecar._load_capture_images(manifest_path, capture)
        occupancy_errors, occupancy_arrays = validate_occupancy_binding(
            manifest_path, capture, semantic, source_root)
        errors = side_errors + image_errors + occupancy_errors
        if errors:
            unavailable = {"status": "NOT_TESTED", "reason": "R7 occupancy provenance/alignment gate failed"}
            rows = [{"stable_id": row["stable_id"], "type": row["type"],
                     "T1": dict(unavailable), "T6": dict(unavailable),
                     "T1_required_for_acceptance": row["type"] != "tree",
                     "T6_required_for_acceptance": row["type"] != "tree"
                     and old.get("case", {}).get("requested_resolution") == [1280, 720]}
                    for row in old["T1"]["instances"]]
            c9_rows = [{"stable_id": row["stable_id"], **unavailable}
                       for row in rows if row["type"] == "tree"]
            values = {"instances": rows, "summary": {}, "C9_trees": c9_rows,
                      "C9_gate": {"status": "NOT_TESTED",
                                  "denominator_all_declared_trees": len(c9_rows)},
                      "tree_numeric_gate": {"status": "NOT_TESTED"}}
        else:
            arrays.update(occupancy_arrays)
            values = measure(capture, old["frozen_v3_case"], images, arrays, semantic)
    else:
        unavailable = {"status": "NOT_TESTED", "reason": "frozen source/capture/alignment gate failed"}
        rows = [{"stable_id": row["stable_id"], "type": row["type"],
                 "T1": dict(unavailable), "T6": dict(unavailable),
                 "T1_required_for_acceptance": row["type"] != "tree",
                 "T6_required_for_acceptance": row["type"] != "tree"
                 and old.get("case", {}).get("requested_resolution") == [1280, 720]}
                for row in old["T1"]["instances"]]
        c9_rows = [{"stable_id": row["stable_id"], **unavailable}
                   for row in rows if row["type"] == "tree"]
        values = {"instances": rows, "summary": {}, "C9_trees": c9_rows,
                  "C9_gate": {"status": "NOT_TESTED",
                              "denominator_all_declared_trees": len(c9_rows)},
                  "tree_numeric_gate": {"status": "NOT_TESTED"}}
        semantic = {}

    sources = []
    for relative in R7_SOURCE_PATHS:
        raw = (source_root / relative).read_bytes()
        sources.append({"path": relative, "bytes": len(raw),
                        "sha256": hashlib.sha256(raw).hexdigest()})
    capture_preconditions = "PASS" if old["capture_preconditions"] == "PASS" and not errors else "FAIL"
    return {"schema_version": SCHEMA, "candidate_head": expected_head,
            "capture_preconditions": capture_preconditions, "capture_errors": errors,
            "case": old.get("case"),
            "rules": {"U1": "new composite occupancy tokens; group-outside four-neighbour edges; touching external/unknown occlusion is unmeasurable and remains in denominator",
                      "sample_exclusions": "grid/UI, other instance or unknown source pixels, and source alpha <= 0.5; same-token alpha <= 0.5 excludes samples without blocking the whole adjacent edge",
                      "inner_radius_px": 2, "outer_radius_px": 4,
                      "local_min_delta_l": 10, "required_perimeter_share": 0.8,
                      "T1_median_delta_l": 15, "T6_median_delta_l": 10,
                      "tree_option": "A", "tree_T1_T6": "diagnostic_only",
                      "tree_gates": ["frozen T3", "C9", "independent visual review"],
                      "C9_model": v2.cvd.SOURCE, "C9_delta_e00_min": 10,
                      "C9_tree_fraction_min": 0.8,
                      "T2_T3_C9_thresholds_frozen": True,
                      "original_source_alpha_and_uncertainty_bytes_frozen": True,
                      "PNG_pixels_modified": False},
            "measurement_sources": sources, "measurements": values,
            "legacy_v1_baseline": old, "art_acceptance": "NOT_TESTED",
            "six_case_coverage": False}


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    result = validate(args.manifest, args.source_root, args.candidate)
    args.out.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"capture_preconditions": result["capture_preconditions"],
                      "summary": result["measurements"].get("summary", {}),
                      "C9": result["measurements"].get("C9_gate", {}),
                      "capture_errors": result["capture_errors"]}, ensure_ascii=False))
    return 0 if result["capture_preconditions"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
