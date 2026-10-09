"""Validate v5 frozen-redraw sequencing and retain v4 terrain capture gates."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

import validate_terrain_readability_capture_v4 as v4

V5_SCHEMA = "terrain-mask-capture/5"
V5_DIAGNOSTIC_SCHEMA = "terrain-readability-capture-v5-state-diagnostic/1"
V5_DRAW_ROLE_ORDER = (
    "main_board",
    "main_detail_layer",
    "reconstruction_board",
    "reconstruction_detail_layer",
)
V5_SOURCES = (
    "tests/claude_review/capture_terrain_readability_v5.gd",
    "tests/claude_review/validate_terrain_readability_capture_v5.py",
    "tests/claude_review/test_terrain_readability_capture_v5.py",
    "dev_doc/ui-art-research/terrain-readability/capture-v5-task.md",
)
V5_REQUIRED_PREDICATES = {
    "all_signals_seen",
    "draw_sequence_aligned",
    "frame_post_draw_seen_for_sequence",
    "counter_advanced_at_process_boundary",
    "input_summaries_match",
    "process_boundary_after_render_return",
}
V5_INPUT_KEYS = (
    "time",
    "draw_input_sha256",
    "terrain_configuration_sha256",
    "water_configuration_sha256",
    "profile_sha256",
    "material_inputs_sha256",
    "mesh_inputs_sha256",
)
V5_THREAD_MODELS = {"main_thread", "render_or_worker_thread"}
V5_DRAW_PHASES = {
    "before_frame_pre_draw",
    "after_frame_pre_draw",
    "after_frame_post_draw",
}
SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")


def _valid_digest(value: object) -> bool:
    return isinstance(value, str) and SHA256_RE.fullmatch(value) is not None


def _valid_sequence(value: object) -> bool:
    return type(value) is int and value > 0


def _valid_ordinal(value: object) -> bool:
    return type(value) is int and value > 0


def _input_summary(value: object) -> dict:
    if not isinstance(value, dict):
        return {}
    return {key: value.get(key) for key in V5_INPUT_KEYS}


def _expected_summary(board: object) -> dict:
    if not isinstance(board, dict):
        return {}
    return {key: board.get(key) for key in V5_INPUT_KEYS}


def _draw_render_associations(state: dict) -> list[dict]:
    """Associate deferred draws with a later pre/post pair and return boundary."""
    refresh = state.get("terrain_v4_draw_refresh", {})
    observation = state.get("terrain_v5_draw_observation", {})
    nodes = refresh.get("nodes", {}) if isinstance(refresh, dict) else {}
    if not isinstance(nodes, dict) or not isinstance(observation, dict):
        return []
    request_id = observation.get("capture_request_id")
    if type(request_id) is not int or request_id <= 0:
        return []
    role_events: dict[str, list[dict]] = {}
    for role in v4.REQUIRED_DRAW_ROLES:
        node = nodes.get(role, {}) if isinstance(nodes, dict) else {}
        events = node.get("draw_events", []) if isinstance(node, dict) else []
        role_events[role] = [event for event in events if isinstance(event, dict)] if isinstance(events, list) else []
    pre_events = observation.get("frame_pre_draw_events", [])
    post_events = observation.get("frame_post_draw_events", [])
    boundaries = observation.get("process_frame_boundaries", [])
    pre_events = [event for event in pre_events if isinstance(event, dict)] if isinstance(pre_events, list) else []
    post_events = [event for event in post_events if isinstance(event, dict)] if isinstance(post_events, list) else []
    boundaries = [event for event in boundaries if isinstance(event, dict)] if isinstance(boundaries, list) else []
    associations: list[dict] = []
    for pre in pre_events:
        if pre.get("capture_request_id") != request_id or pre.get("phase") != "frame_pre_draw":
            continue
        sequence = pre.get("render_sequence")
        pre_ordinal = pre.get("event_ordinal")
        if not _valid_sequence(sequence) or not _valid_ordinal(pre_ordinal):
            continue
        draw_ordinals_by_role: dict[str, list[int]] = {}
        complete = True
        for role in v4.REQUIRED_DRAW_ROLES:
            ordinals = sorted(
                event["event_ordinal"] for event in role_events[role]
                if event.get("capture_request_id") == request_id
                and event.get("phase") == "before_frame_pre_draw"
                and _valid_ordinal(event.get("event_ordinal"))
                and event["event_ordinal"] < pre_ordinal
            )
            draw_ordinals_by_role[role] = ordinals
            complete = complete and bool(ordinals)
        if not complete:
            continue
        for post in post_events:
            post_ordinal = post.get("event_ordinal")
            if (post.get("capture_request_id") != request_id
                    or post.get("phase") != "frame_post_draw"
                    or post.get("render_sequence") != sequence
                    or not _valid_ordinal(post_ordinal)
                    or post_ordinal <= pre_ordinal):
                continue
            matching_boundaries = [
                boundary for boundary in boundaries
                if boundary.get("capture_request_id") == request_id
                and boundary.get("phase") == "process_frame_after_render_return"
                and _valid_ordinal(boundary.get("event_ordinal"))
                and boundary["event_ordinal"] > post_ordinal
                and type(boundary.get("latest_completed_render_sequence")) is int
                and boundary["latest_completed_render_sequence"] >= sequence
            ]
            base = {
                "capture_request_id": request_id,
                "render_sequence": sequence,
                "draw_event_ordinals_by_role": draw_ordinals_by_role,
                "frame_pre_draw_event_ordinal": pre_ordinal,
                "frame_post_draw_event_ordinal": post_ordinal,
            }
            if not matching_boundaries:
                associations.append({
                    **base,
                    "process_boundary_event_ordinal": 0,
                    "process_boundary_index": 0,
                    "process_boundary_frames_drawn": -1,
                    "latest_completed_render_sequence": 0,
                })
            else:
                for boundary in matching_boundaries:
                    associations.append({
                        **base,
                        "process_boundary_event_ordinal": boundary["event_ordinal"],
                        "process_boundary_index": boundary.get("boundary_index", 0),
                        "process_boundary_frames_drawn": boundary.get("frames_drawn_after_return", -1),
                        "latest_completed_render_sequence": boundary.get("latest_completed_render_sequence", 0),
                    })
    return associations


def draw_observation_errors(state: dict, common_frame: dict | None = None) -> list[str]:
    """Check raw event order from deferred draw through render return."""
    errors: list[str] = []
    refresh = state.get("terrain_v4_draw_refresh", {})
    observation = state.get("terrain_v5_draw_observation", {})
    if not isinstance(refresh, dict):
        return ["v5 缺少继承的四节点重绘请求记录"]
    if not isinstance(observation, dict):
        return ["v5 缺少 frame_pre_draw/process_frame 观察记录"]
    nodes = refresh.get("nodes", {})
    if not isinstance(nodes, dict) or set(nodes) != v4.REQUIRED_DRAW_ROLES:
        return ["v5 必须记录全部四个 BoardView/DetailLayer 节点"]
    for role in v4.REQUIRED_DRAW_ROLES:
        node = nodes[role]
        if not isinstance(node, dict):
            errors.append(f"v5 缺少 {role} 节点记录")
            continue
        if node.get("queue_redraw_called") is not True:
            errors.append(f"v5 {role} 没有记录一次 queue_redraw 请求")
        if node.get("visible_in_tree") is not True:
            errors.append(f"v5 {role} 请求重绘时不可见")
    if observation.get("schema_version") != "terrain-readability-draw-observation-v5/1":
        errors.append("v5 重绘观察 schema 不匹配")
    if observation.get("status") == "NOT_TESTED_HEADLESS":
        if observation.get("headless_structure_only") is not True:
            errors.append("v5 headless 状态必须明确标为结构检查")
        if refresh.get("status") != "NOT_TESTED_HEADLESS" or refresh.get("headless_structure_only") is not True:
            errors.append("v5 headless 状态不得声称实际 draw 回调通过")
        if common_frame is not None:
            errors.append("v5 headless 结构状态不能作为像素 capture manifest")
        return errors

    errors += v4.draw_refresh_errors(state, common_frame)
    if observation.get("status") != "PASS":
        errors.append("v5 有限观察窗口未达到全部重绘谓词")
    if observation.get("headless_structure_only") is not False:
        errors.append("v5 原生绘制观察不能标记为 headless")
    request_id = observation.get("capture_request_id")
    if type(request_id) is not int or request_id <= 0:
        errors.append("v5 缺少有效 capture_request_id")

    pre_events = observation.get("frame_pre_draw_events", [])
    post_events = observation.get("frame_post_draw_events", [])
    boundaries = observation.get("process_frame_boundaries", [])
    if not isinstance(pre_events, list) or not pre_events:
        errors.append("v5 缺少实际 frame_pre_draw 序号")
        pre_events = []
    if not isinstance(post_events, list) or not post_events:
        errors.append("v5 缺少实际 frame_post_draw 序号")
        post_events = []
    if not isinstance(boundaries, list) or not boundaries:
        errors.append("v5 缺少有限 process_frame 返回边界")
        boundaries = []
    max_boundaries = observation.get("max_process_frame_boundaries")
    if type(max_boundaries) is not int or max_boundaries != 3:
        errors.append("v5 观察边界必须明确限制为三个 process_frame")
    if len(boundaries) > 3:
        errors.append("v5 超出三个 process_frame 的有限观察边界")
    if observation.get("observed_process_frame_boundaries") != len(boundaries):
        errors.append("v5 观察边界数量与记录不一致")

    event_ordinals: list[int] = []
    for event_list, expected_phase, label in (
        (pre_events, "frame_pre_draw", "frame_pre_draw"),
        (post_events, "frame_post_draw", "frame_post_draw"),
        (boundaries, "process_frame_after_render_return", "process_frame"),
    ):
        for event in event_list:
            if not isinstance(event, dict):
                errors.append(f"v5 {label} 事件格式无效")
                continue
            ordinal = event.get("event_ordinal")
            if not _valid_ordinal(ordinal):
                errors.append(f"v5 {label} 事件缺少有效全局 event_ordinal")
            else:
                event_ordinals.append(ordinal)
            if event.get("phase") != expected_phase:
                errors.append(f"v5 {label} 事件 phase 与实际回调阶段不符")
            if event.get("capture_request_id") != request_id:
                errors.append(f"v5 {label} 事件跨 capture_request_id")
            if label == "process_frame":
                if type(event.get("process_frame")) is not int or type(event.get("frames_drawn_after_return")) is not int:
                    errors.append("v5 process_frame 边界没有记录返回后的帧计数")
                completed = event.get("latest_completed_render_sequence")
                if type(completed) is not int or completed < 0:
                    errors.append("v5 process_frame 边界没有记录已完成渲染序号")
            else:
                if not _valid_sequence(event.get("render_sequence")):
                    errors.append("v5 frame_pre_draw/frame_post_draw 缺少有效本地渲染序号")
                if type(event.get("frames_drawn_at_callback")) is not int:
                    errors.append("v5 渲染信号没有记录回调时的 Engine 帧计数")
                if type(event.get("process_frame")) is not int:
                    errors.append("v5 渲染信号没有记录 process_frame 序号")
            if event.get("callback_thread_model") not in V5_THREAD_MODELS:
                errors.append(f"v5 {label} 事件没有记录线程模型")

    draw_events_by_role: dict[str, list[dict]] = {}
    for role in v4.REQUIRED_DRAW_ROLES:
        node = nodes.get(role, {})
        raw_events = node.get("draw_events", []) if isinstance(node, dict) else []
        raw_events = raw_events if isinstance(raw_events, list) else []
        draw_events_by_role[role] = []
        for event in raw_events:
            if not isinstance(event, dict):
                errors.append(f"v5 {role} draw 事件格式无效")
                continue
            draw_events_by_role[role].append(event)
            ordinal = event.get("event_ordinal")
            if not _valid_ordinal(ordinal):
                errors.append(f"v5 {role} draw 事件缺少有效全局 event_ordinal")
            else:
                event_ordinals.append(ordinal)
            if event.get("capture_request_id") != request_id:
                errors.append(f"v5 {role} draw 事件跨 capture_request_id")
            if event.get("phase") not in V5_DRAW_PHASES:
                errors.append(f"v5 {role} draw 事件没有保留原始 phase")
            if "render_sequence" in event:
                errors.append(f"v5 {role} draw 事件不得伪造尚未发生的 render_sequence")
            if type(event.get("frames_drawn_at_callback")) is not int:
                errors.append(f"v5 {role} draw 事件没有记录回调时的 Engine 帧计数")
            if type(event.get("process_frame")) is not int:
                errors.append(f"v5 {role} draw 事件没有记录 process_frame 序号")
            if event.get("callback_thread_model") not in V5_THREAD_MODELS:
                errors.append(f"v5 {role} draw 回调没有记录线程模型")
    if len(event_ordinals) != len(set(event_ordinals)):
        errors.append("v5 全局 event_ordinal 重复")

    request_events_by_role = {
        role: [event for event in draw_events_by_role[role]
               if event.get("capture_request_id") == request_id]
        for role in v4.REQUIRED_DRAW_ROLES
    }
    all_signals_seen = all(request_events_by_role[role] for role in v4.REQUIRED_DRAW_ROLES)
    computed_associations = _draw_render_associations(state)
    recorded_associations = observation.get("draw_render_associations", [])
    if not isinstance(recorded_associations, list) or recorded_associations != computed_associations:
        errors.append("v5 draw→后续 pre→post→返回边界关联与原始事件序号不一致")
    aligned_sequences = {item["render_sequence"] for item in computed_associations}
    matched_sequence = observation.get("matched_render_sequence")
    sequence_aligned = _valid_sequence(matched_sequence) and matched_sequence in aligned_sequences
    if not all_signals_seen:
        errors.append("v5 并非四个目标都发出实际 CanvasItem.draw")
    if not aligned_sequences:
        errors.append("v5 四个 deferred draw 没有按 ordinal 绑定到后续 pre_draw/post_draw")
    if not sequence_aligned:
        errors.append("v5 matched_render_sequence 没有完整四节点与后续 post_draw 证据")

    request_count = observation.get("request_frames_drawn")
    if type(request_count) is not int:
        errors.append("v5 缺少请求前 Engine.get_frames_drawn()")
        request_count = -1
    matched_sequence_associations = [
        item for item in computed_associations
        if sequence_aligned and item["render_sequence"] == matched_sequence
    ]
    matched_associations = [
        item for item in matched_sequence_associations
        if item["process_boundary_event_ordinal"] > item["frame_post_draw_event_ordinal"]
    ]
    process_boundary_after_render = bool(matched_associations)
    counter_advanced = any(
        type(item.get("process_boundary_frames_drawn")) is int
        and item["process_boundary_frames_drawn"] > request_count
        and item.get("latest_completed_render_sequence", 0) >= matched_sequence
        for item in matched_associations
    )
    if not counter_advanced:
        errors.append("v5 在渲染返回后的 process_frame 边界没有观察到 Engine 帧计数前进")
    if not process_boundary_after_render:
        errors.append("v5 process_frame 边界没有按 ordinal 关联到已完成的 frame_post_draw")

    board_inputs = state.get("terrain_v4_board_inputs", {})
    input_summaries_match = True
    side_by_role = {
        "main_board": "main",
        "main_detail_layer": "main",
        "reconstruction_board": "reconstruction",
        "reconstruction_detail_layer": "reconstruction",
    }
    for role in v4.REQUIRED_DRAW_ROLES:
        node = nodes.get(role, {})
        if not isinstance(node, dict):
            input_summaries_match = False
            continue
        side = side_by_role[role]
        expected = _expected_summary(board_inputs.get(side, {}) if isinstance(board_inputs, dict) else {})
        node_summary = _input_summary(node.get("input_summary"))
        if node.get("side") != side or node_summary != expected or not expected:
            input_summaries_match = False
            errors.append(f"v5 {role} 实际输入摘要未绑定对应 BoardView")
        for event in request_events_by_role[role]:
            event_summary = _input_summary(event.get("input_summary"))
            if event_summary != expected or event.get("input_summary") != node.get("input_summary"):
                input_summaries_match = False
                errors.append(f"v5 {role} draw 输入与对应 BoardView 实际输入不一致")
            for key in V5_INPUT_KEYS[1:]:
                if not _valid_digest(event_summary.get(key)):
                    input_summaries_match = False
                    errors.append(f"v5 {role} draw 输入摘要缺少有效 {key}")
                    break
            if type(event_summary.get("time")) not in (int, float):
                input_summaries_match = False
                errors.append(f"v5 {role} draw 输入摘要缺少实际 _time")
    if not input_summaries_match:
        errors.append("v5 实际输入摘要没有与重绘请求前的对应 BoardView 输入相等")

    computed = {
        "all_signals_seen": all_signals_seen,
        "draw_sequence_aligned": bool(sequence_aligned),
        "frame_post_draw_seen_for_sequence": bool(sequence_aligned and matched_sequence_associations),
        "counter_advanced_at_process_boundary": counter_advanced,
        "input_summaries_match": input_summaries_match,
        "process_boundary_after_render_return": process_boundary_after_render,
    }
    predicates = observation.get("predicates", {})
    if not isinstance(predicates, dict) or set(predicates) != V5_REQUIRED_PREDICATES:
        errors.append("v5 没有分别记录全部六个独立重绘谓词")
    else:
        for name, actual in computed.items():
            if predicates.get(name) is not actual:
                errors.append(f"v5 独立谓词与实际序号/输入/计数证据不符: {name}")
    return errors

def diagnostic_errors(diagnostic: dict) -> list[str]:
    """Ensure a failed run preserves its active case independently of successes."""
    errors: list[str] = []
    if diagnostic.get("schema_version") != V5_DIAGNOSTIC_SCHEMA:
        errors.append("v5 失败诊断 schema 不匹配")
    cases = diagnostic.get("cases", [])
    if not isinstance(cases, list):
        errors.append("v5 成功用例列表格式无效")
        cases = []
    if diagnostic.get("case_count") != len(cases):
        errors.append("v5 已完成用例计数与成功列表不一致")
    if diagnostic.get("run_status") != "FAIL":
        errors.append("v5 失败诊断整体 run_status 必须为 FAIL")
    if diagnostic.get("active_case_status") != "FAIL":
        errors.append("v5 整体失败诊断的 active_case_status 必须为 FAIL")
    active = diagnostic.get("active_case")
    if not isinstance(active, dict) or diagnostic.get("active_case_persisted") is not True:
        errors.append("v5 失败退出没有持久化独立 active_case")
        return errors
    if active.get("case_status") != "FAIL":
        errors.append("v5 整体失败诊断不能把 READY active_case 当作失败证据")
    failure_reason = diagnostic.get("failure_reason")
    if not isinstance(failure_reason, str) or not failure_reason.strip():
        errors.append("v5 失败诊断没有保存失败原因")
    if active.get("failure_reason") != failure_reason:
        errors.append("v5 active_case 失败原因与整体诊断不一致")
    map_size = active.get("map_size")
    resolution = active.get("resolution")
    if (not isinstance(map_size, list) or len(map_size) != 2
            or any(type(value) is not int for value in map_size)
            or map_size[0] != map_size[1] or map_size[0] not in {10, 25}):
        errors.append("v5 失败 active_case 缺少有效地图尺寸")
    if resolution not in [[1280, 720], [1920, 1080], [2560, 1440]]:
        errors.append("v5 失败 active_case 缺少有效采集分辨率")
    nodes = active.get("nodes", {})
    if not isinstance(nodes, dict) or set(nodes) != v4.REQUIRED_DRAW_ROLES:
        errors.append("v5 失败 active_case 必须保留全部四个目标节点")
        nodes = {}
    observed = active.get("observed_draw_callbacks", {})
    if not isinstance(observed, dict) or set(observed) != v4.REQUIRED_DRAW_ROLES:
        errors.append("v5 失败 active_case 必须保留每个目标已出现的回调列表")
        observed = {}
    missing = []
    for role in V5_DRAW_ROLE_ORDER:
        node = nodes.get(role, {})
        node_events = node.get("draw_events", []) if isinstance(node, dict) else []
        callbacks = observed.get(role, [])
        if not isinstance(callbacks, list):
            errors.append(f"v5 active_case {role} 回调列表格式无效")
            callbacks = []
        if callbacks != node_events:
            errors.append(f"v5 active_case {role} 回调列表与节点记录不一致")
        if not node_events:
            missing.append(role)
    raw_observation = active.get("draw_observation", {})
    if not isinstance(raw_observation, dict):
        errors.append("v5 失败 active_case 没有保存原始 draw_observation")
        raw_observation = {}
    raw_event_ordinals: list[int] = []
    raw_request_id = raw_observation.get("capture_request_id", 0)
    for key in ("frame_pre_draw_events", "frame_post_draw_events",
                "process_frame_boundaries", "draw_render_associations"):
        if not isinstance(raw_observation.get(key), list):
            errors.append(f"v5 active_case 原始观察缺少列表 {key}")
    for role in V5_DRAW_ROLE_ORDER:
        node = nodes.get(role, {})
        events = node.get("draw_events", []) if isinstance(node, dict) else []
        if not isinstance(events, list):
            events = []
        for event in events:
            if not isinstance(event, dict):
                continue
            ordinal = event.get("event_ordinal")
            if not _valid_ordinal(ordinal):
                errors.append(f"v5 active_case {role} 原始 draw 事件缺少 ordinal")
            else:
                raw_event_ordinals.append(ordinal)
            if event.get("phase") not in V5_DRAW_PHASES:
                errors.append(f"v5 active_case {role} 原始 draw 事件没有保留 phase")
            if event.get("capture_request_id") != raw_request_id:
                errors.append(f"v5 active_case {role} 原始 draw 事件请求编号不一致")
            if "render_sequence" in event:
                errors.append(f"v5 active_case {role} 原始 draw 事件伪造 render_sequence")
    for key, phase in (("frame_pre_draw_events", "frame_pre_draw"),
                       ("frame_post_draw_events", "frame_post_draw"),
                       ("process_frame_boundaries", "process_frame_after_render_return")):
        events = raw_observation.get(key, [])
        if not isinstance(events, list):
            events = []
        for event in events:
            if not isinstance(event, dict):
                errors.append(f"v5 active_case 原始 {key} 事件格式无效")
                continue
            ordinal = event.get("event_ordinal")
            if not _valid_ordinal(ordinal):
                errors.append(f"v5 active_case 原始 {key} 事件缺少 ordinal")
            else:
                raw_event_ordinals.append(ordinal)
            if event.get("phase") != phase or event.get("capture_request_id") != raw_request_id:
                errors.append(f"v5 active_case 原始 {key} phase/request 编号不一致")
    if len(raw_event_ordinals) != len(set(raw_event_ordinals)):
        errors.append("v5 active_case 原始事件 ordinal 重复")
    if active.get("missing_nodes") != missing:
        errors.append("v5 active_case 缺失节点列表与实际回调不一致")
    predicates = active.get("failure_predicates", {})
    if not isinstance(predicates, dict) or set(predicates) != V5_REQUIRED_PREDICATES:
        errors.append("v5 失败 active_case 没有分别保存六个独立谓词")
    elif any(type(predicates[name]) is not bool for name in V5_REQUIRED_PREDICATES):
        errors.append("v5 失败 active_case 谓词必须逐项保留 true/false")
    return errors


def v5_source_errors(manifest: dict, source_root: Path) -> list[str]:
    errors: list[str] = []
    sources = manifest.get("sources", {})
    candidate = manifest.get("candidate", {})
    if not isinstance(sources, dict):
        sources = {}
        errors.append("v5 sources 摘要格式无效")
    if not isinstance(candidate, dict):
        candidate = {}
        errors.append("v5 candidate 摘要格式无效")
    candidate_hashes = candidate.get("source_sha256", {})
    if not isinstance(candidate_hashes, dict):
        candidate_hashes = {}
        errors.append("v5 candidate.source_sha256 摘要格式无效")
    candidate_digest = candidate.get("candidate_digest_sha256")
    digest_payload = json.dumps(candidate_hashes, ensure_ascii=False, separators=(",", ":"))
    actual_candidate_digest = hashlib.sha256(digest_payload.encode("utf-8")).hexdigest()
    if not _valid_digest(candidate_digest) or candidate_digest != actual_candidate_digest:
        errors.append("v5 candidate_digest_sha256 与完整 source_sha256 摘要不一致")
    for source in V5_SOURCES:
        digest = sources.get("res://" + source)
        if not _valid_digest(digest):
            errors.append(f"v5 源码绑定摘要缺失或格式无效: {source}")
            continue
        try:
            root = source_root.resolve()
            path = (root / source).resolve()
            if not path.is_relative_to(root):
                raise ValueError("source path escapes the repository")
            actual = hashlib.sha256(path.read_bytes()).hexdigest()
            if actual != digest or candidate_hashes.get(source) != actual:
                errors.append(f"v5 候选源码摘要与当前工作树不一致: {source}")
        except (OSError, ValueError) as error:
            errors.append(f"v5 源码绑定无法读取 {source}: {error}")
    return errors


def validate(manifest_path: Path, source_root: Path, expected_head: str,
             case_data: dict | None = None) -> dict:
    data = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    if case_data is None:
        case_data = json.loads((source_root / v4.V4_CASE_FILE).read_text(encoding="utf-8-sig"))
    result = v4.validate(manifest_path, source_root, expected_head, case_data)
    errors = [error for error in result.get("errors", []) if error != "采集 schema 不匹配"]
    if data.get("schema_version") != V5_SCHEMA:
        errors.append("采集 schema 不匹配")
    state = data.get("capture_state", {})
    errors += draw_observation_errors(state, data.get("common_frame", {}))
    errors += v5_source_errors(data, source_root)
    result["schema_version"] = data.get("schema_version")
    result["capture_preconditions"] = "PASS" if not errors else "FAIL"
    result["errors"] = errors
    result["measurement_status"] = "NOT_TESTED"
    result["art_acceptance"] = "NOT_TESTED"
    result["note"] = "v5 只验证冻结后 draw 序号与渲染返回边界；像素测量和美术接受仍未测试。"
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifests", type=Path, nargs="+")
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--candidate", required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    source_root = args.source_root.resolve()
    try:
        head = subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=source_root,
            capture_output=True, text=True, encoding="utf-8", timeout=15,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        parser.error(f"无法在源码工作树读取 Git HEAD: {error}")
    if head.returncode != 0 or head.stdout.strip() != args.candidate:
        parser.error("源码工作树 HEAD 与传入候选不同，或 Git HEAD 读取失败")
    case_data = json.loads((source_root / v4.V4_CASE_FILE).read_text(encoding="utf-8"))
    results: list[dict] = []
    for path in args.manifests:
        try:
            results.append(validate(path, source_root, args.candidate, case_data))
        except (OSError, ValueError, KeyError, TypeError) as error:
            results.append({"manifest": path.name, "capture_preconditions": "FAIL", "errors": [str(error)]})
    cases = [(tuple(result.get("case", {}).get("map_size", [])),
              tuple(result.get("case", {}).get("requested_resolution", []))) for result in results]
    expected = {(size, resolution) for size in v4.EXPECTED_MAP_SIZES
                for resolution in map(tuple, v4.EXPECTED_RESOLUTIONS)}
    complete = len(cases) == 6 and set(cases) == expected
    passed = complete and all(result.get("capture_preconditions") == "PASS" for result in results)
    output = {
        "schema_version": "terrain-capture-readback/5",
        "candidate_head": args.candidate,
        "six_case_coverage": complete,
        "capture_preconditions": "PASS" if passed else "FAIL",
        "measurement_status": "NOT_TESTED",
        "art_acceptance": "NOT_TESTED",
        "cases": results,
    }
    args.out.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "capture_preconditions": output["capture_preconditions"],
        "six_case_coverage": complete,
        "measurement_status": "NOT_TESTED",
        "art_acceptance": "NOT_TESTED",
    }, ensure_ascii=False))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
