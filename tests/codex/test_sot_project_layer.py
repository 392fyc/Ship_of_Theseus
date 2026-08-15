from __future__ import annotations

import re
import json
import shutil
import subprocess
import tempfile
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PUBLISH_SCRIPT = ROOT / "scripts" / "codex" / "sot-publish.ps1"


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def run(command: list[str], cwd: Path, *, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        command,
        cwd=cwd,
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        check=False,
    )
    if check and result.returncode != 0:
        raise AssertionError(
            f"command failed ({result.returncode}): {command}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return result


def init_repository(path: Path, branch: str) -> None:
    run(["git", "init", f"--initial-branch={branch}"], path)
    (path / "fixture.txt").write_text("fixture\n", encoding="utf-8")
    run(["git", "add", "fixture.txt"], path)
    run(
        [
            "git",
            "-c",
            "user.name=SoT Test",
            "-c",
            "user.email=sot-test@example.invalid",
            "commit",
            "-m",
            "fixture",
        ],
        path,
    )


def install_publish_script(repository: Path) -> Path:
    destination = repository / "scripts" / "codex" / "sot-publish.ps1"
    destination.parent.mkdir(parents=True)
    shutil.copy2(PUBLISH_SCRIPT, destination)
    run(["git", "add", "scripts/codex/sot-publish.ps1"], repository)
    run(
        [
            "git",
            "-c",
            "user.name=SoT Test",
            "-c",
            "user.email=sot-test@example.invalid",
            "commit",
            "-m",
            "install publish fixture",
        ],
        repository,
    )
    return destination


def test_codex_project_layer_is_discoverable_and_keeps_ownership_boundaries() -> None:
    agent_paths = sorted((ROOT / ".codex" / "agents").glob("*.toml"))
    rule_paths = sorted((ROOT / ".codex" / "rules").glob("*.rules"))
    skill_paths = sorted((ROOT / ".agents" / "skills").glob("sot-*/SKILL.md"))

    assert [path.name for path in agent_paths] == [
        "mercury-acceptance.toml",
        "mercury-dev.toml",
        "mercury-reviewer.toml",
        "sot-designlib.toml",
        "sot-kb.toml",
    ]
    assert [path.name for path in rule_paths] == [
        "mercury-git-safety.rules",
        "sot-protected-branches.rules",
    ]
    assert len(skill_paths) == 5

    for path in agent_paths:
        parsed = tomllib.loads(read_text(path))
        assert {"name", "description", "developer_instructions"} <= parsed.keys()
        assert "model" not in parsed


def test_project_config_and_lane_agents_encode_cross_repository_receipts() -> None:
    config = tomllib.loads(read_text(ROOT / ".codex" / "config.toml"))
    assert config["web_search"] == "live"
    assert "hooks" not in config
    instructions = config["developer_instructions"].lower()
    for required in ["protected", "agents.md", "canonical", "target head", "contract summary"]:
        assert required in instructions

    designlib = tomllib.loads(read_text(ROOT / ".codex" / "agents" / "sot-designlib.toml"))
    assert designlib["name"] == "sot-designlib"
    design_instructions = designlib["developer_instructions"].lower()
    for required in [
        ".agents/skills/sot-designlib/skill.md",
        "schema_version",
        "source_snapshot_or_commit",
        "sha256",
        "dry-run",
        "write",
        "readback",
        "target worktree",
    ]:
        assert required in design_instructions
    for forbidden in ["engine_json", "export endpoint", "backfill"]:
        assert forbidden in design_instructions

    kb = tomllib.loads(read_text(ROOT / ".codex" / "agents" / "sot-kb.toml"))
    assert kb["name"] == "sot-kb"
    kb_instructions = kb["developer_instructions"].lower()
    for required in [
        ".agents/skills/sot-kb-write/skill.md",
        "narrative",
        "qualitative",
        "user decision",
        "adr",
        "research",
        "work record",
        "not the authority for tasks",
        "not the authority for active memory",
    ]:
        assert required in kb_instructions


def test_routing_and_root_configuration_keep_the_five_authorities_distinct() -> None:
    routing = read_text(ROOT / ".codex" / "project" / "sot-authority-routing.md").lower()
    for required in [
        "structured gameplay",
        "current executable behavior",
        "narrative",
        "github/git",
        ".mercury/memory",
    ]:
        assert required in routing

    roots_path = ROOT / ".codex" / "project" / "sot-roots.example.toml"
    roots = tomllib.loads(read_text(roots_path))
    assert roots == {
        "roots": {
            "mercury_root": "<path-to-mercury>",
            "designlib_root": "<path-to-design-library>",
            "kb_root": "<path-to-kb-repository>",
        }
    }
    assert ".codex/project/sot-roots.local.toml" in read_text(ROOT / ".gitignore")
    assert not (ROOT / ".codex" / "project" / "sot-roots.local.toml").exists()


def test_project_owned_files_do_not_embed_machine_state_or_runtime_credentials() -> None:
    paths = [
        ROOT / ".codex" / "config.toml",
        ROOT / ".codex" / "agents" / "sot-designlib.toml",
        ROOT / ".codex" / "agents" / "sot-kb.toml",
        ROOT / ".codex" / "project" / "sot-authority-routing.md",
        ROOT / ".codex" / "project" / "sot-roots.example.toml",
        ROOT / ".codex" / "rules" / "sot-protected-branches.rules",
        PUBLISH_SCRIPT,
    ]
    combined = "\n".join(read_text(path) for path in paths)
    assert not re.search(r"(?i)(?:[a-z]:[\\/]|192\.168\.|localhost|127\.0\.0\.1|:[0-9]{2,5}\b)", combined)
    assert not re.search(r"(?i)(?:api[_-]?key|api[_-]?token|secret|private[_-]?key)\s*=", combined)
    assert ".codex/hooks.json" not in combined
    assert "hooks =" not in combined


def test_sot_rules_forbid_selecting_each_protected_branch() -> None:
    rules = read_text(ROOT / ".codex" / "rules" / "sot-protected-branches.rules")
    for command in ("switch", "checkout"):
        for branch in ("develop", "main", "master"):
            expected = f'pattern = ["git", "{command}", "{branch}"]'
            assert expected in rules
    for command, option in (("switch", "-c"), ("switch", "-C"), ("checkout", "-b"), ("checkout", "-B")):
        for branch in ("develop", "main", "master"):
            expected = f'pattern = ["git", "{command}", "{option}", "{branch}"]'
            assert expected in rules
    assert rules.count('decision = "forbidden"') == 18


def test_sot_rules_reject_force_create_forms_in_execpolicy() -> None:
    codex = shutil.which("codex")
    if codex is None:
        return
    rule_args = [
        codex,
        "execpolicy",
        "check",
        "--rules",
        str(ROOT / ".codex" / "rules" / "mercury-git-safety.rules"),
        "--rules",
        str(ROOT / ".codex" / "rules" / "sot-protected-branches.rules"),
    ]
    for command in (
        ["git", "switch", "-C", "main"],
        ["git", "checkout", "-B", "master"],
        ["git", "push", "origin", "HEAD"],
    ):
        result = run(rule_args + command, ROOT)
        assert json.loads(result.stdout)["decision"] == "forbidden"


def test_publish_pushes_only_the_current_task_branch_to_the_same_origin_branch() -> None:
    with tempfile.TemporaryDirectory() as temp_dir:
        temp = Path(temp_dir)
        origin = temp / "origin.git"
        repo = temp / "repo"
        origin.mkdir()
        repo.mkdir()
        run(["git", "init", "--bare"], origin)
        init_repository(repo, "codex/fixture-publish")
        run(["git", "remote", "add", "origin", str(origin)], repo)
        fixture_script = install_publish_script(repo)

        result = run(
            ["pwsh", "-NoProfile", "-File", str(fixture_script)],
            repo,
        )
        assert "codex/fixture-publish" in result.stdout
        assert str(origin) not in result.stdout
        local_head = run(["git", "rev-parse", "HEAD"], repo).stdout.strip()
        remote_head = run(
            ["git", "--git-dir", str(origin), "rev-parse", "refs/heads/codex/fixture-publish"],
            temp,
        ).stdout.strip()
        assert remote_head == local_head
        branches = run(
            ["git", "--git-dir", str(origin), "for-each-ref", "--format=%(refname:short)", "refs/heads"],
            temp,
        ).stdout.splitlines()
        assert branches == ["codex/fixture-publish"]


def test_publish_rejects_protected_branches() -> None:
    with tempfile.TemporaryDirectory() as temp_dir:
        repo = Path(temp_dir)
        init_repository(repo, "main")
        fixture_script = install_publish_script(repo)
        protected = run(
            ["pwsh", "-NoProfile", "-File", str(fixture_script)],
            repo,
            check=False,
        )
        assert protected.returncode != 0
        assert "protected" in (protected.stdout + protected.stderr).lower()


def test_publish_exposes_no_user_supplied_refspec_parameter() -> None:
    command = (
        f"$command = Get-Command -Name '{PUBLISH_SCRIPT}'; "
        "if ($command.Parameters.ContainsKey('Refspec')) { exit 1 }"
    )
    result = run(["pwsh", "-NoProfile", "-Command", command], ROOT, check=False)
    assert result.returncode == 0


def test_publish_rejects_a_dirty_working_tree() -> None:
    with tempfile.TemporaryDirectory() as temp_dir:
        temp = Path(temp_dir)
        origin = temp / "origin.git"
        repo = temp / "repo"
        origin.mkdir()
        repo.mkdir()
        run(["git", "init", "--bare"], origin)
        init_repository(repo, "codex/fixture-dirty")
        run(["git", "remote", "add", "origin", str(origin)], repo)
        fixture_script = install_publish_script(repo)
        (repo / "fixture.txt").write_text("dirty\n", encoding="utf-8")
        result = run(
            ["pwsh", "-NoProfile", "-File", str(fixture_script), "-DryRun"],
            repo,
            check=False,
        )
        assert result.returncode != 0
        assert "not clean" in (result.stdout + result.stderr).lower()


def test_publish_rejects_invocation_from_another_repository() -> None:
    with tempfile.TemporaryDirectory() as temp_dir:
        repo = Path(temp_dir)
        init_repository(repo, "codex/foreign-repository")
        result = run(
            ["pwsh", "-NoProfile", "-File", str(PUBLISH_SCRIPT), "-DryRun"],
            repo,
            check=False,
        )
        assert result.returncode != 0
        assert "controlled entrypoint" in (result.stdout + result.stderr).lower()
