"""Focused v4 regressions for test spawns and frozen draw evidence."""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

import validate_terrain_readability_capture_v4 as validator
from validate_terrain_readability_capture_v4 import (
    REQUIRED_DRAW_ROLES,
    V4_SOURCES,
    case_file_errors,
    draw_refresh_errors,
    spawn_configuration_errors,
    target_coverage_errors,
)

CASE_FILE = Path(__file__).with_name("terrain_readability_capture_v4_cases.json")
DIGEST = "a" * 64


def _case_data() -> dict:
    return json.loads(CASE_FILE.read_text(encoding="utf-8"))


def _spawn_state() -> dict:
    expected = {"player": [9, 2], "enemy": [5, 9]}
    role_record = {
        "builder": "TerrainBattleSession.configure_map -> TerrainBattleDefinition.build",
        "original_formal_configuration_sha256": DIGEST,
        "actual_formal_configuration_sha256": "b" * 64,
        "applied_before_entering_tree": True,
        "changed_paths": ["enemy_units[0].position", "player_units[0].position"],
        "allowed_changed_paths": ["enemy_units[0].position", "player_units[0].position"],
        "all_other_fields_equal": True,
        "unit_counts_preserved": True,
        "class_ids_preserved": True,
        "position_fields_only": True,
        "desired_positions": expected,
        "actual_positions": expected,
    }
    main = {**role_record, "session_instance_id": 101}
    reconstruction = {**role_record, "session_instance_id": 202}
    reconstruction["actual_formal_configuration_sha256"] = "b" * 64
    return {
        "schema_version": "terrain-readability-spawn-state/1",
        "map_size": [10, 10],
        "case_file": "res://tests/claude_review/terrain_readability_capture_v4_cases.json",
        "case_file_sha256": "c" * 64,
        "expected_positions": expected,
        "main": main,
        "reconstruction": reconstruction,
        "positions_distinct": True,
        "positions_passable": True,
        "positions_avoid_prop_cells": True,
        "manager_positions_match_config": True,
        "units_visible": True,
        "highlights_visible": True,
    }


def _draw_state() -> tuple[dict, dict]:
    nodes = {
        role: {
            "queue_redraw_called": True,
            "visible_in_tree": True,
            "draw_input_sha256": DIGEST,
            "draw_events": [{
                "frames_drawn": 71,
                "draw_node_visible_in_tree": True,
                "time": 1.25,
                "draw_input_sha256": DIGEST,
                "terrain_configuration_sha256": DIGEST,
                "water_configuration_sha256": DIGEST,
                "profile_sha256": DIGEST,
                "material_inputs_sha256": DIGEST,
                "mesh_inputs_sha256": DIGEST,
            }],
        }
        for role in REQUIRED_DRAW_ROLES
    }
    state = {"terrain_v4_draw_refresh": {
        "request_method": "CanvasItem.queue_redraw",
        "status": "PASS",
        "headless_structure_only": False,
        "frame_post_draw_before_request": 70,
        "frame_post_draw_after_request": 71,
        "nodes": nodes,
    }}
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


def _coverage_state() -> dict:
    return {"terrain_v4_retained_sample_coverage": {
        "pillar@1.00,4.00": {
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
        },
        "rubble@3.12,2.08": {
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
        },
    }}


class TerrainCaptureV4StateTests(unittest.TestCase):
    def test_versioned_case_file_has_fixed_valid_arrangements(self):
        self.assertEqual(case_file_errors(_case_data()), [])

    def test_case_file_rejects_reused_or_out_of_bounds_spawn(self):
        data = copy.deepcopy(_case_data())
        data["cases"][0]["enemy_unit_position"] = data["cases"][0]["player_unit_position"]
        self.assertTrue(any("重合" in error for error in case_file_errors(data)))
        data = copy.deepcopy(_case_data())
        data["cases"][0]["player_unit_position"] = [10, 0]
        self.assertTrue(any("越界" in error for error in case_file_errors(data)))

    def test_formal_spawn_state_proves_only_the_two_positions_changed(self):
        data = _case_data()
        self.assertEqual(spawn_configuration_errors(_spawn_state(), data, [10, 10]), [])

    def test_formal_spawn_state_rejects_any_unrelated_configuration_change(self):
        data = _case_data()
        state = _spawn_state()
        state["main"]["changed_paths"] = ["player_units[0].class_id"]
        state["main"]["all_other_fields_equal"] = False
        errors = spawn_configuration_errors(state, data, [10, 10])
        self.assertTrue(any("实际改动字段" in error for error in errors))
        self.assertTrue(any("all_other_fields_equal" in error for error in errors))

    def test_frozen_draw_refresh_requires_real_signals_and_same_post_draw_frame(self):
        state, common_frame = _draw_state()
        self.assertEqual(draw_refresh_errors(state, common_frame), [])

    def test_frozen_draw_refresh_rejects_missing_signal_and_wrong_frame_binding(self):
        state, common_frame = _draw_state()
        state["terrain_v4_draw_refresh"]["nodes"]["main_board"]["draw_events"] = []
        common_frame["terrain_v4_state_snapshot"]["frame_id"] = 79
        errors = draw_refresh_errors(state, common_frame)
        self.assertTrue(any("没有实际 CanvasItem.draw 信号" in error for error in errors))
        self.assertTrue(any("不是同一个 frame_post_draw" in error for error in errors))

    def test_headless_redraw_is_recorded_without_claiming_a_real_draw(self):
        state, _ = _draw_state()
        refresh = state["terrain_v4_draw_refresh"]
        refresh["status"] = "NOT_TESTED_HEADLESS"
        refresh["headless_structure_only"] = True
        self.assertEqual(draw_refresh_errors(state), [])

    def test_draw_signal_must_bind_live_input_to_requested_board_snapshot(self):
        state, common_frame = _draw_state()
        event = state["terrain_v4_draw_refresh"]["nodes"]["main_board"]["draw_events"][0]
        event["draw_input_sha256"] = "d" * 64
        errors = draw_refresh_errors(state, common_frame)
        self.assertTrue(any("实际 BoardView 状态快照不一致" in error for error in errors))

    def test_retained_sample_coverage_preserves_alpha_and_rejects_range_overlap(self):
        state = _coverage_state()
        self.assertEqual(target_coverage_errors(state), [])
        state["terrain_v4_retained_sample_coverage"]["rubble@3.12,2.08"]["range_covered"] = True
        errors = target_coverage_errors(state)
        self.assertTrue(any("覆盖原样本" in error for error in errors))

    def test_retained_sample_coverage_rejects_alpha_changed_from_source_or_target(self):
        state = _coverage_state()
        pillar = state["terrain_v4_retained_sample_coverage"]["pillar@1.00,4.00"]
        pillar["actual_modulate_alpha"] = 0.32
        pillar["alpha_matches_source_state"] = False
        pillar["alpha_matches_coverage_target"] = False
        errors = target_coverage_errors(state)
        self.assertTrue(any("alpha 与来源状态不一致" in error for error in errors))
        self.assertTrue(any("alpha 与正式覆盖条件结果不一致" in error for error in errors))

    def test_validate_three_argument_entry_loads_versioned_case_file(self):
        source_root = Path(__file__).resolve().parents[2]
        source_hashes = {
            relative: hashlib.sha256((source_root / relative).read_bytes()).hexdigest()
            for relative in V4_SOURCES
        }
        manifest = {
            "schema_version": "terrain-mask-capture/4",
            "case": {"map_size": [10, 10], "requested_resolution": [1280, 720]},
            "capture_state": {},
            "common_frame": {},
            "sources": {"res://" + path: digest for path, digest in source_hashes.items()},
            "candidate": {"source_sha256": source_hashes},
        }
        stub_v3 = types.ModuleType("validate_terrain_readability_capture_v3")
        stub_v3.validate = lambda *_args: {"errors": []}
        with tempfile.TemporaryDirectory() as directory:
            manifest_path = Path(directory) / "manifest.json"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            with patch.dict(sys.modules, {"validate_terrain_readability_capture_v3": stub_v3}):
                result = validator.validate(manifest_path, source_root, "test-head")
        self.assertEqual(result["schema_version"], "terrain-mask-capture/4")
        self.assertFalse(any("v4 用例 JSON schema" in error for error in result["errors"]))


if __name__ == "__main__":
    unittest.main()
