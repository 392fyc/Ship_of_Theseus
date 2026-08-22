from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SKILL_DIR = ROOT / ".agents" / "skills"
AGENTS_PATH = ROOT / "AGENTS.md"

SKILL_PATHS = {
    "sot-designlib": SKILL_DIR / "sot-designlib" / "SKILL.md",
    "sot-kb-write": SKILL_DIR / "sot-kb-write" / "SKILL.md",
    "sot-session-start": SKILL_DIR / "sot-session-start" / "SKILL.md",
    "sot-session-end": SKILL_DIR / "sot-session-end" / "SKILL.md",
    "sot-task-receipt": SKILL_DIR / "sot-task-receipt" / "SKILL.md",
}


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def parse_frontmatter(text: str) -> str:
    match = re.match(r"(?s)\A---\n(.*?)\n---\n", text)
    assert match, "frontmatter block missing"
    return match.group(1)


def parse_name(frontmatter: str) -> str:
    match = re.search(r"^\s*name:\s*(.+?)\s*$", frontmatter, flags=re.M)
    assert match, "frontmatter name missing"
    return match.group(1).strip().strip('\"')


def test_sot_skill_contracts_static():
    discovered = sorted(ROOT.glob("**/sot-*/SKILL.md"))
    assert discovered == sorted(SKILL_PATHS.values()), (
        "sot-* skill procedures must have exactly one canonical body under .agents/skills"
    )

    for name, path in SKILL_PATHS.items():
        assert path.exists(), f"missing skill file: {path}"
        text = read_text(path)
        frontmatter = parse_frontmatter(text)
        parsed_name = parse_name(frontmatter)
        assert parsed_name == name, f"{path.name}: name should be {name}, got {parsed_name}"

        # 通用禁用项
        for bad in [
            "obsidian_get_file_contents",
            "obsidian_append_content",
            "obsidian_patch_content",
            "${CLAUDE_PLUGIN_ROOT}",
            "~/.claude",
            ".claude/skills",
            ".claude\\skills",
        ]:
            assert bad not in text, f"{path}: found forbidden token '{bad}'"

        assert not re.search(
            r"(?i)(?<![A-Za-z0-9_])[A-Z]:[\\/]", text
        ), f"{path}: contains a machine-specific Windows absolute path"


def test_agents_is_codex_native_and_routes_each_authority():
    text = read_text(AGENTS_PATH)
    for forbidden in [
        "默认在 Claude Code",
        "仅外部工具",
        "仅在用户特殊声明派发外部工具时适用",
        "obsidian_get_file_contents",
        "obsidian_append_content",
        "obsidian_patch_content",
        ".claude/skills",
        ".claude\\skills",
        "已弃用",
    ]:
        assert forbidden not in text, f"AGENTS.md contains stale authority: {forbidden}"
    assert not re.search(
        r"(?i)(?<![A-Za-z0-9_])[A-Z]:[\\/]", text
    ), "AGENTS.md contains a machine-specific Windows absolute path"

    for required in [
        "Codex",
        "SoT-fyc-space",
        "结构化玩法",
        "当前可执行",
        "叙事",
        "定性设计",
        "用户裁决",
        "ADR",
        "GitHub/Git",
        "Mercury",
        ".mercury/memory",
    ]:
        assert required in text, f"AGENTS.md missing authority routing term: {required}"


def test_agents_distinguishes_task_completion_from_milestone_completion():
    text = read_text(AGENTS_PATH)

    for required in [
        "Milestone",
        "Task",
        "Subtask",
        "完成 Task 不等于完成 Milestone",
        "已知且未阻塞",
        "自动继续",
        "无需再次确认",
        "不得自行增加新的 Task",
    ]:
        assert required in text, f"AGENTS.md missing progression contract: {required}"

    assert "全部必需 Task" in text
    assert "没有已知的必需工作遗留" in text


def test_designlib_contract_uses_portable_roots_and_current_one_way_model():
    text = read_text(SKILL_PATHS["sot-designlib"])
    for required in [
        "SOT_DESIGNLIB_ROOT",
        ".codex/project/sot-roots.local.toml",
        "/api/talents",
        "/api/skills",
        "/api/equipment",
        "/api/relics",
        "/api/rules",
        "snapshots/",
        "schema_version",
        "source_snapshot_or_commit",
        "normalized_sha256",
        "dry-run",
        "readback",
        "worktree",
        "结构化玩法目标事实",
        "当前可执行实现事实",
    ]:
        assert required in text, f"sot-designlib missing contract term: {required}"

    for retired in [
        "engine_json",
        "/api/export/",
        "backfill_engine",
        "回填管线",
        "export platform",
    ]:
        assert retired not in text, f"sot-designlib retains retired contract: {retired}"


def test_kb_contract_is_safe_and_records_cross_repo_context():
    kb = read_text(SKILL_PATHS["sot-kb-write"])
    for required in [
        "mcp__obsidian__vault_read",
        "mcp__obsidian__vault_write",
        "mcp__obsidian__vault_append",
        "mcp__obsidian__vault_get_document_map",
        "mcp__obsidian__vault_patch",
        "mcp__obsidian__search_simple",
        "01-Game-Design/rules-catalog.md",
        "SOT_KB_ROOT",
        "[roots].kb_root",
        "target_head",
        "contract_summary",
        "叙事",
        "定性设计",
        "用户裁决",
        "ADR",
        "研究",
        "工作记录",
    ]:
        assert required in kb, f"sot-kb-write missing required contract term {required}"
    assert "任务与验收" in kb and "活跃记忆" in kb
    assert "不得执行跨仓写入" in kb
    assert "已存在的文档禁止使用 `mcp__obsidian__vault_write`" in kb
    assert "没有 `ifMatch`" in kb


def test_session_skills_use_logical_mercury_memory_and_manual_handoff_only():
    session_start = read_text(SKILL_PATHS["sot-session-start"])
    assert "MERCURY_ROOT" in session_start
    assert "[roots].mercury_root" in session_start
    assert ".codex/project/sot-roots.local.toml" in session_start
    assert ".mercury/memory" in session_start
    assert "index.jsonl" in session_start
    assert "MEMORY.md" in session_start and "session-checkpoint.md" in session_start

    session_end = read_text(SKILL_PATHS["sot-session-end"])
    assert "MERCURY_ROOT" in session_end
    assert "[roots].mercury_root" in session_end
    assert ".codex/project/sot-roots.local.toml" in session_end
    assert ".mercury/memory/projects/<project-bucket>/session-checkpoint.md" in session_end
    assert ".mercury/memory/projects/<project-bucket>/" in session_end
    assert "~/.Codex" not in session_end
    assert "user" in session_end.lower()
    assert "handoff" in session_end.lower()
    assert "manual" in session_end.lower()
    assert "不得自动" in session_end


def test_task_receipt_records_cross_repository_evidence_without_self_approval():
    task_receipt = read_text(SKILL_PATHS["sot-task-receipt"])
    for key in [
        "task_id",
        "status",
        "target_repository",
        "target_branch",
        "target_head_before",
        "candidate_head",
        "changed_files",
        "verification",
        "criteria_evidence",
        "residual_risks",
        "protected_state",
        "escalation_reason",
        "target_head",
        "contract_summary",
        "source_schema_version",
        "source_snapshot_or_commit",
        "normalized_digest",
    ]:
        assert key in task_receipt, f"sot-task-receipt missing required field key '{key}'"
    assert "completed | blocked | failed" in task_receipt
    assert "不得自行" in task_receipt and "批准" in task_receipt
