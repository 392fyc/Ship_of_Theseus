from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parents[2]
KB = ROOT / "docs"
KB_CHECK = ROOT / ".mercury" / "packs" / "kb" / "scripts" / "kb_check.py"
# 入口文件、项目技能、角色来源与仓内导航页里写到的 KB 路径必须真实存在；生成的角色文件由安装器从来源同步。
ENTRY_FILES = [ROOT / "AGENTS.md", ROOT / "CLAUDE.md", ROOT / "README.md", ROOT / "dev_doc" / "README.md"]
ENTRY_GLOBS = [
    ".agents/skills/*/SKILL.md",
    ".claude/skills/*/SKILL.md",
    ".mercury/local/roles/*.md",
    ".codex/project/*.md",
]
# 仓库根相对的写法，例如 `docs/00-rules/design-rules-index.md`。
KB_PATH = re.compile(r"(?<![\w.-])(?<![\w.-]/)docs/[\w./-]+?\.md\b")
# Markdown 相对链接，例如 [工作树](../../../docs/02-Development/worktree-lifecycle.md)。
MD_LINK = re.compile(r"(?<!!)\]\(<?([^)\s>]+)>?(?:\s+\"[^\"]*\")?\)")
# 其他仓库自己的 docs/ 路径（例如设计库的跨仓合同），不在本 KB 中。
FOREIGN = {"docs/mercury-sot-lane-management.md"}


def entry_files() -> list[Path]:
    files = list(ENTRY_FILES)
    for pattern in ENTRY_GLOBS:
        files.extend(sorted(ROOT.glob(pattern)))
    return files


def test_kb_check_passes() -> None:
    result = subprocess.run(
        [sys.executable, "-B", str(KB_CHECK), str(KB)],
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    assert result.returncode == 0, result.stdout + result.stderr


def test_kb_root_has_only_entry_readme() -> None:
    documents = sorted(p.name for p in KB.glob("*.md"))
    assert documents == ["README.md"]


def test_entry_files_point_to_existing_kb_documents() -> None:
    missing = []
    for path in entry_files():
        text = path.read_text(encoding="utf-8")
        where = path.relative_to(ROOT).as_posix()
        for match in KB_PATH.findall(text):
            if match not in FOREIGN and not (ROOT / match).is_file():
                missing.append(f"{where}: {match}")
        for target in MD_LINK.findall(text):
            if re.match(r"^[a-z][a-z0-9+.-]*:", target, re.I) or target.startswith("#"):
                continue
            resolved = (path.parent / unquote(target.split("#", 1)[0])).resolve()
            if (resolved == KB or KB in resolved.parents) and not resolved.exists():
                missing.append(f"{where}: {target}")
    assert not missing, "\n".join(missing)
