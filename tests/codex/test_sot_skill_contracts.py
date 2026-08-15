from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SKILL_DIR = ROOT / ".agents" / "skills"

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
        ]:
            assert bad not in text, f"{path}: found forbidden token '{bad}'"

    kb = read_text(SKILL_PATHS["sot-kb-write"])
    for required in [
        "mcp__obsidian__vault_read",
        "mcp__obsidian__vault_write",
        "mcp__obsidian__vault_append",
        "mcp__obsidian__vault_get_document_map",
        "mcp__obsidian__vault_patch",
        "mcp__obsidian__search_simple",
    ]:
        assert required in kb, f"sot-kb-write missing required native tool {required}"

    session_start = read_text(SKILL_PATHS["sot-session-start"])
    assert ".mercury\\memory" in session_start or ".mercury/memory" in session_start
    assert "index.jsonl" in session_start
    assert "MEMORY.md" in session_start and "session-checkpoint.md" in session_start

    session_end = read_text(SKILL_PATHS["sot-session-end"])
    assert "projects\\<project-bucket>\\session-checkpoint.md" in session_end
    assert "memory\\session-checkpoint.md" not in session_end
    assert "~/.Codex/projects/<project>/memory/project_session{N}_handoff.md" in session_end
    assert "user" in session_end.lower()
    assert "handoff" in session_end.lower()
    assert "manual" in session_end.lower()
    assert "PreCompact" in session_end or "precompact" in session_end

    task_receipt = read_text(SKILL_PATHS["sot-task-receipt"])
    for key in [
        "objective",
        "status",
        "changed_files",
        "verification",
        "commit",
        "push",
        "residual_risks",
        "protected_dirty",
    ]:
        assert key in task_receipt, f"sot-task-receipt missing required field key '{key}'"
