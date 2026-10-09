"""Focused regressions for v5 redraw timing, source binding, and failure diagnostics."""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import unittest

import validate_terrain_readability_capture_v4 as v4
import validate_terrain_readability_capture_v5 as v5

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
DIGEST = "a" * 64
ROLES = v4.REQUIRED_DRAW_ROLES


def _summary(time_value: float = 1.25) -> dict:
    return {
        "time": time_value,
        "draw_input_sha256": DIGEST,
        "terrain_configuration_sha256": "b" * 64,
        "water_configuration_sha256": "c" * 64,
        "profile_sha256": "d" * 64,
        "material_inputs_sha256": "e" * 64,
        "mesh_inputs_sha256": "f" * 64,
    }


def _state() -> tuple[dict, dict]:
    request_id = 1
    board_inputs = {"main": _summary(), "reconstruction": _summary()}
    nodes = {}
    side_by_role = {
        "main_board": "main",
        "main_detail_layer": "main",
        "reconstruction_board": "reconstruction",
        "reconstruction_detail_layer": "reconstruction",
    }
    for ordinal, role in enumerate(ROLES, start=1):
        side = side_by_role[role]
        summary = copy.deepcopy(board_inputs[side])
        nodes[role] = {
            "side": side,
            "visible_in_tree": True,
            "queue_redraw_called": True,
            "draw_input_sha256": DIGEST,
            "input_summary": summary,
            "draw_events": [{
                "capture_request_id": request_id,
                "event_ordinal": ordinal,
                "phase": "before_frame_pre_draw",
                "frames_drawn": 70,
                "frames_drawn_at_callback": 70,
                "process_frame": 20,
                "callback_thread_model": "main_thread",
                "draw_node_visible_in_tree": True,
                "input_summary": copy.deepcopy(summary),
                "time": 1.25,
                **{key: summary[key] for key in v5.V5_INPUT_KEYS[1:]},
            }],
        }
    predicates = {
        "all_signals_seen": True,
        "draw_sequence_aligned": True,
        "frame_post_draw_seen_for_sequence": True,
        "counter_advanced_at_process_boundary": True,
        "input_summaries_match": True,
        "process_boundary_after_render_return": True,
    }
    observation = {
        "schema_version": "terrain-readability-draw-observation-v5/1",
        "status": "PASS",
        "capture_request_id": request_id,
        "headless_structure_only": False,
        "request_frames_drawn": 70,
        "request_process_frame": 20,
        "max_process_frame_boundaries": 3,
        "observed_process_frame_boundaries": 1,
        "matched_render_sequence": 1,
        "frame_pre_draw_events": [{
            "capture_request_id": request_id,
            "event_ordinal": 5,
            "phase": "frame_pre_draw",
            "render_sequence": 1,
            "frames_drawn_at_callback": 70,
            "process_frame": 20,
            "callback_thread_model": "main_thread",
        }],
        "frame_post_draw_events": [{
            "capture_request_id": request_id,
            "event_ordinal": 6,
            "phase": "frame_post_draw",
            "render_sequence": 1,
            "frames_drawn_at_callback": 70,
            "process_frame": 20,
            "callback_thread_model": "main_thread",
        }],
        "process_frame_boundaries": [{
            "capture_request_id": request_id,
            "event_ordinal": 7,
            "phase": "process_frame_after_render_return",
            "boundary_index": 1,
            "process_frame": 21,
            "frames_drawn_after_return": 71,
            "latest_completed_render_sequence": 1,
            "callback_thread_model": "main_thread",
        }],
        "predicates": predicates,
    }
    state = {
        "terrain_v4_board_inputs": board_inputs,
        "terrain_v4_draw_refresh": {
            "request_method": "CanvasItem.queue_redraw",
            "status": "PASS",
            "headless_structure_only": False,
            "frame_post_draw_before_request": 70,
            "frame_post_draw_after_request": 71,
            "nodes": nodes,
        },
        "terrain_v5_draw_observation": observation,
    }
    observation["draw_render_associations"] = v5._draw_render_associations(state)
    common_frame = {
        "frame_id": 80,
        "terrain_v4_state_snapshot": {
            "callback": "RenderingServer.frame_post_draw",
            "same_frame": True,
            "frame_id": 80,
            "image_count": 12,
            "readback_awaits_between_images": False,
            "board_state_snapshot_captured": True,
        },
    }
    return state, common_frame


def _failure_diagnostic() -> dict:
    nodes = {role: {"draw_events": []} for role in ROLES}
    callbacks = {role: [] for role in ROLES}
    predicates = {name: False for name in v5.V5_REQUIRED_PREDICATES}
    return {
        "schema_version": v5.V5_DIAGNOSTIC_SCHEMA,
        "run_status": "FAIL",
        "failure_reason": "bounded_render_observation failed",
        "active_case_status": "FAIL",
        "case_count": 0,
        "cases": [],
        "active_case_persisted": True,
        "active_case": {
            "case_index": 1,
            "case_status": "FAIL",
            "failure_stage": "bounded_render_observation",
            "failure_reason": "bounded_render_observation failed",
            "map_size": [10, 10],
            "resolution": [1280, 720],
            "nodes": nodes,
            "observed_draw_callbacks": callbacks,
            "missing_nodes": list(v5.V5_DRAW_ROLE_ORDER),
            "draw_observation": {
                "schema_version": "terrain-readability-draw-observation-v5/1",
                "status": "FAIL",
                "capture_request_id": 1,
                "frame_pre_draw_events": [],
                "frame_post_draw_events": [],
                "process_frame_boundaries": [],
                "draw_render_associations": [],
            },
            "failure_predicates": predicates,
        },
    }


def _coverage_record() -> dict:
    return {
        "instance_retained": True,
        "covered": False,
        "range_covered": False,
        "covered_source": "CourtyardBoardView._process unit and hover bounds",
        "range_covered_source": "CourtyardBoardView._process actual HighlightLayer polygon centers",
        "source_modulate_alpha": 1.0,
        "actual_modulate_alpha": 1.0,
        "target_alpha": 1.0,
        "alpha_matches_source_state": True,
        "alpha_matches_coverage_target": True,
        "alpha_mutated_by_v4": False,
    }


def _source_manifest() -> dict:
    hashes = {
        source: hashlib.sha256((ROOT / source).read_bytes()).hexdigest()
        for source in v5.V5_SOURCES
    }
    digest = hashlib.sha256(
        json.dumps(hashes, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    return {
        "sources": {"res://" + source: value for source, value in hashes.items()},
        "candidate": {"source_sha256": hashes, "candidate_digest_sha256": digest},
    }


class TerrainCaptureV5ObservationTests(unittest.TestCase):
    def test_v4_case_file_still_covers_two_sizes_and_three_fixed_resolutions(self):
        case_data = json.loads((HERE / v4.V4_CASE_FILE.split("/")[-1]).read_text(encoding="utf-8"))
        self.assertEqual(v4.case_file_errors(case_data), [])
        self.assertEqual(
            {tuple(case["map_size"]) for case in case_data["cases"]},
            v4.EXPECTED_MAP_SIZES,
        )
        self.assertEqual(case_data["resolutions"], v4.EXPECTED_RESOLUTIONS)
        source = (HERE / "capture_terrain_readability_v5.gd").read_text(encoding="utf-8")
        self.assertIn('extends "res://tests/claude_review/capture_terrain_readability_v4.gd"', source)
        self.assertNotIn("terrain_readability_capture_v5_cases.json", source)

    def test_real_deferred_draws_before_pre_draw_associate_through_return_boundary(self):
        state, common_frame = _state()
        observation = state["terrain_v5_draw_observation"]
        first_draw = state["terrain_v4_draw_refresh"]["nodes"]["main_board"]["draw_events"][0]
        post_event = observation["frame_post_draw_events"][0]
        self.assertEqual(first_draw["phase"], "before_frame_pre_draw")
        self.assertLess(first_draw["event_ordinal"], observation["frame_pre_draw_events"][0]["event_ordinal"])
        self.assertNotIn("render_sequence", first_draw)
        self.assertEqual(post_event["frames_drawn_at_callback"], 70)
        self.assertEqual(observation["request_frames_drawn"], 70)
        self.assertEqual(observation["process_frame_boundaries"][0]["frames_drawn_after_return"], 71)
        self.assertEqual(v5.draw_observation_errors(state, common_frame), [])

    def test_return_boundary_must_advance_counter_after_post_draw(self):
        state, common_frame = _state()
        observation = state["terrain_v5_draw_observation"]
        observation["process_frame_boundaries"][0]["frames_drawn_after_return"] = 70
        observation["predicates"]["counter_advanced_at_process_boundary"] = False
        observation["status"] = "FAIL"
        state["terrain_v4_draw_refresh"]["status"] = "FAIL"
        state["terrain_v4_draw_refresh"]["frame_post_draw_after_request"] = 70
        observation["draw_render_associations"] = v5._draw_render_associations(state)
        errors = v5.draw_observation_errors(state, common_frame)
        self.assertTrue(any("返回后的 process_frame 边界" in error for error in errors))

    def test_missing_draw_callback_fails_and_remains_unassociated(self):
        state, common_frame = _state()
        observation = state["terrain_v5_draw_observation"]
        state["terrain_v4_draw_refresh"]["nodes"]["main_detail_layer"]["draw_events"] = []
        observation["predicates"]["all_signals_seen"] = False
        observation["predicates"]["draw_sequence_aligned"] = False
        observation["predicates"]["frame_post_draw_seen_for_sequence"] = False
        observation["predicates"]["counter_advanced_at_process_boundary"] = False
        observation["predicates"]["process_boundary_after_render_return"] = False
        observation["matched_render_sequence"] = -1
        observation["status"] = "FAIL"
        state["terrain_v4_draw_refresh"]["status"] = "FAIL"
        observation["draw_render_associations"] = v5._draw_render_associations(state)
        errors = v5.draw_observation_errors(state, common_frame)
        self.assertTrue(any("main_detail_layer" in error for error in errors))
        self.assertTrue(any("没有按 ordinal" in error for error in errors))

    def test_wrong_pre_post_sequence_cannot_complete_deferred_draw_chain(self):
        state, common_frame = _state()
        observation = state["terrain_v5_draw_observation"]
        observation["frame_post_draw_events"][0]["render_sequence"] = 6
        observation["predicates"]["draw_sequence_aligned"] = False
        observation["predicates"]["frame_post_draw_seen_for_sequence"] = False
        observation["predicates"]["counter_advanced_at_process_boundary"] = False
        observation["predicates"]["process_boundary_after_render_return"] = False
        observation["matched_render_sequence"] = -1
        observation["status"] = "FAIL"
        state["terrain_v4_draw_refresh"]["status"] = "FAIL"
        observation["draw_render_associations"] = v5._draw_render_associations(state)
        errors = v5.draw_observation_errors(state, common_frame)
        self.assertTrue(any("没有按 ordinal" in error for error in errors))

    def test_callbacks_from_another_capture_request_cannot_be_combined(self):
        state, common_frame = _state()
        observation = state["terrain_v5_draw_observation"]
        event = state["terrain_v4_draw_refresh"]["nodes"]["reconstruction_detail_layer"]["draw_events"][0]
        event["capture_request_id"] = 2
        observation["predicates"]["all_signals_seen"] = False
        observation["predicates"]["draw_sequence_aligned"] = False
        observation["predicates"]["frame_post_draw_seen_for_sequence"] = False
        observation["predicates"]["counter_advanced_at_process_boundary"] = False
        observation["predicates"]["process_boundary_after_render_return"] = False
        observation["matched_render_sequence"] = -1
        observation["status"] = "FAIL"
        state["terrain_v4_draw_refresh"]["status"] = "FAIL"
        observation["draw_render_associations"] = v5._draw_render_associations(state)
        errors = v5.draw_observation_errors(state, common_frame)
        self.assertTrue(any("跨 capture_request_id" in error for error in errors))
        self.assertTrue(any("没有按 ordinal" in error for error in errors))

    def test_actual_input_summary_must_match_each_requested_board(self):
        state, common_frame = _state()
        event = state["terrain_v4_draw_refresh"]["nodes"]["main_board"]["draw_events"][0]
        event["input_summary"]["water_configuration_sha256"] = "9" * 64
        errors = v5.draw_observation_errors(state, common_frame)
        self.assertTrue(any("输入" in error and "不一致" in error for error in errors))

    def test_failed_active_case_is_required_even_when_success_case_list_is_empty(self):
        diagnostic = _failure_diagnostic()
        self.assertEqual(v5.diagnostic_errors(diagnostic), [])
        diagnostic.pop("active_case")
        errors = v5.diagnostic_errors(diagnostic)
        self.assertTrue(any("active_case" in error for error in errors))

    def test_later_abort_overrides_ready_case_after_completed_case_was_recorded(self):
        diagnostic = _failure_diagnostic()
        diagnostic["case_count"] = 1
        diagnostic["cases"] = [{"case_index": 1, "case_status": "STATE_READY"}]
        diagnostic["active_case"]["case_index"] = 2
        diagnostic["active_case"]["draw_observation"]["capture_request_id"] = 2
        draw_event = {
            "capture_request_id": 2,
            "event_ordinal": 40,
            "phase": "before_frame_pre_draw",
            "frames_drawn_at_callback": 70,
            "process_frame": 20,
        }
        diagnostic["active_case"]["nodes"]["main_board"]["draw_events"] = [draw_event]
        diagnostic["active_case"]["observed_draw_callbacks"]["main_board"] = [copy.deepcopy(draw_event)]
        diagnostic["active_case"]["missing_nodes"] = [
            role for role in v5.V5_DRAW_ROLE_ORDER if role != "main_board"
        ]
        diagnostic["active_case"]["draw_observation"]["frame_pre_draw_events"] = [{
            "capture_request_id": 2,
            "event_ordinal": 41,
            "phase": "frame_pre_draw",
        }]
        diagnostic["active_case"]["draw_observation"]["frame_post_draw_events"] = [{
            "capture_request_id": 2,
            "event_ordinal": 42,
            "phase": "frame_post_draw",
        }]
        diagnostic["active_case"]["draw_observation"]["process_frame_boundaries"] = [{
            "capture_request_id": 2,
            "event_ordinal": 43,
            "phase": "process_frame_after_render_return",
        }]
        self.assertEqual(v5.diagnostic_errors(diagnostic), [])

        invalid = copy.deepcopy(diagnostic)
        invalid["active_case_status"] = "STATE_READY"
        invalid["active_case"]["case_status"] = "STATE_READY"
        errors = v5.diagnostic_errors(invalid)
        self.assertTrue(any("active_case_status" in error for error in errors))
        self.assertTrue(any("READY active_case" in error for error in errors))

        source = (HERE / "capture_terrain_readability_v5.gd").read_text(encoding="utf-8")
        abort_body = source.split("func _abort(message: String) -> void:", 1)[1].split("\n\n", 1)[0]
        self.assertLess(abort_body.index("_failed = true"), abort_body.index("_v4_write_external_diagnostic()"))
        self.assertLess(abort_body.index("_v4_write_external_diagnostic()"), abort_body.index("super._abort(message)"))
        active_record = source.split("func _v5_active_case_record() -> Dictionary:", 1)[1]
        self.assertLess(active_record.index("if _failed or _v4_draw_refresh.get(\"status\", \"\") == \"FAIL\":"),
                        active_record.index("elif _v4_case_diagnostics.size() >= _v5_active_case_index"))

    def test_failed_active_case_retains_original_draw_phase_and_ordinal(self):
        diagnostic = _failure_diagnostic()
        active = diagnostic["active_case"]
        event = {
            "capture_request_id": 1,
            "event_ordinal": 9,
            "phase": "before_frame_pre_draw",
            "frames_drawn_at_callback": 70,
            "process_frame": 20,
        }
        active["nodes"]["main_board"]["draw_events"] = [event]
        active["observed_draw_callbacks"]["main_board"] = [copy.deepcopy(event)]
        active["missing_nodes"] = [role for role in v5.V5_DRAW_ROLE_ORDER if role != "main_board"]
        self.assertEqual(v5.diagnostic_errors(diagnostic), [])
        del active["nodes"]["main_board"]["draw_events"][0]["phase"]
        errors = v5.diagnostic_errors(diagnostic)
        self.assertTrue(any("保留 phase" in error for error in errors))

    def test_all_four_v5_sources_are_bound_to_bytes_and_summary_tampering_fails(self):
        self.assertEqual(len(v5.V5_SOURCES), 4)
        task_doc = "dev_doc/ui-art-research/terrain-readability/capture-v5-task.md"
        self.assertIn(task_doc, v5.V5_SOURCES)
        source = (HERE / "capture_terrain_readability_v5.gd").read_text(encoding="utf-8")
        self.assertIn('"res://' + task_doc + '"', source)
        manifest = _source_manifest()
        self.assertEqual(v5.v5_source_errors(manifest, ROOT), [])

        tampered_digest = copy.deepcopy(manifest)
        tampered_digest["candidate"]["candidate_digest_sha256"] = "0" * 64
        self.assertTrue(any(
            "candidate_digest_sha256" in error
            for error in v5.v5_source_errors(tampered_digest, ROOT)
        ))

        tampered_source = copy.deepcopy(manifest)
        fake_digest = "9" * 64
        tampered_source["sources"]["res://" + task_doc] = fake_digest
        tampered_source["candidate"]["source_sha256"][task_doc] = fake_digest
        hashes = tampered_source["candidate"]["source_sha256"]
        tampered_source["candidate"]["candidate_digest_sha256"] = hashlib.sha256(
            json.dumps(hashes, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        ).hexdigest()
        self.assertTrue(any(
            task_doc in error and "不一致" in error
            for error in v5.v5_source_errors(tampered_source, ROOT)
        ))

    def test_retained_samples_keep_original_alpha_state(self):
        coverage = {
            "pillar@1.00,4.00": _coverage_record(),
            "rubble@3.12,2.08": _coverage_record(),
        }
        self.assertEqual(v4.target_coverage_errors({"terrain_v4_retained_sample_coverage": coverage}), [])
        source = (HERE / "capture_terrain_readability_v5.gd").read_text(encoding="utf-8")
        self.assertNotRegex(source, r"\bmodulate\s*\.\s*a\s*=")


if __name__ == "__main__":
    unittest.main()
