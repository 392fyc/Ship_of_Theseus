"""Tests for the multi-lane controlled tooling.

Everything runs against temporary fixture repositories. SOT_* and inherited
GIT_* variables are removed from the child environment, and roots always point
into the temporary directory.
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts" / "codex"
SCRIPT_NAMES = ["sot-sync.ps1", "sot-memory.ps1", "sot-worktree.ps1", "sot-publish.ps1"]
IDENTITY = {
    "GIT_AUTHOR_NAME": "SoT Test",
    "GIT_AUTHOR_EMAIL": "sot-test@example.invalid",
    "GIT_COMMITTER_NAME": "SoT Test",
    "GIT_COMMITTER_EMAIL": "sot-test@example.invalid",
}

pytestmark = pytest.mark.skipif(shutil.which("pwsh") is None, reason="PowerShell 7 is required")


def clean_env(extra: dict[str, str] | None = None) -> dict[str, str]:
    env = {
        key: value
        for key, value in os.environ.items()
        if not key.startswith("SOT_")
        and key not in ("GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_INDEX_FILE")
    }
    env.update(IDENTITY)
    env.update({"GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1"})
    env.update(extra or {})
    return env


def run(command, cwd, *, check=True, env=None) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        [str(part) for part in command],
        cwd=cwd,
        env=clean_env(env),
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


def git(cwd, *args, check=True) -> str:
    return run(["git", *args], cwd, check=check).stdout.strip()


def ps(script: str, cwd, *args, check=True, env=None) -> subprocess.CompletedProcess[str]:
    return run(["pwsh", "-NoProfile", "-File", script, *args], cwd, check=check, env=env)


def commit_file(repo: Path, name: str, content: str, message: str) -> None:
    (repo / name).parent.mkdir(parents=True, exist_ok=True)
    (repo / name).write_text(content, encoding="utf-8", newline="\n")
    git(repo, "add", name)
    git(repo, "commit", "-q", "-m", message)


def make_repo(base: Path, name: str, default_branch: str, *, scripts: bool) -> tuple[Path, Path]:
    """Create <base>/<name> with a bare origin that already holds the default branch."""
    origin = base / f"{name}-origin.git"
    repo = base / name
    origin.mkdir()
    repo.mkdir()
    git(origin, "init", "-q", "--bare", f"--initial-branch={default_branch}")
    git(repo, "init", "-q", f"--initial-branch={default_branch}")
    git(repo, "config", "core.autocrlf", "false")
    git(repo, "remote", "add", "origin", str(origin))
    (repo / ".gitignore").write_text(".codex/project/sot-roots.local.toml\n/.worktrees/\n", encoding="utf-8")
    git(repo, "add", ".gitignore")
    commit_file(repo, "base.txt", "base\n", "base")
    if scripts:
        dest = repo / "scripts" / "codex"
        dest.mkdir(parents=True)
        for script in SCRIPT_NAMES:
            shutil.copy2(SCRIPTS / script, dest / script)
        git(repo, "add", "scripts")
        git(repo, "commit", "-q", "-m", "install scripts")
    git(repo, "push", "-q", "origin", default_branch)
    git(repo, "fetch", "-q", "origin")
    git(repo, "remote", "set-head", "origin", default_branch)
    return repo, origin


@pytest.fixture
def sandbox():
    with tempfile.TemporaryDirectory() as raw:
        yield Path(raw).resolve()


def script_of(repo: Path, name: str) -> str:
    return str(repo / "scripts" / "codex" / name)


def add_task(repo: Path, task: str, branch: str, group: Path | None = None) -> Path:
    group = group or repo / ".worktrees"
    group.mkdir(parents=True, exist_ok=True)
    path = group / task
    git(repo, "worktree", "add", "-q", "-b", branch, str(path))
    return path


def write_roots(path: Path, **roots: Path) -> Path:
    lines = ["[roots]"]
    lines += [f"{key} = '{value.as_posix()}'" for key, value in roots.items()]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    return path


# --------------------------------------------------------------------------- sot-worktree


def full_roots_file(sandbox: Path, ship: Path, designlib: Path, kb: Path) -> Path:
    path = sandbox / "roots.toml"
    path.write_text(
        "[roots]\n"
        f"ship_root = '{ship.as_posix()}'\n"
        f"designlib_root = '{designlib.as_posix()}'\n"
        f"kb_root = '{kb.as_posix()}'\n"
        "[worktrees]\n"
        f"ship_root = '{(ship / ".worktrees").as_posix()}'\n"
        f"designlib_root = '{(designlib / ".worktrees").as_posix()}'\n"
        f"kb_root = '{(kb / ".worktrees").as_posix()}'\n",
        encoding="utf-8",
        newline="\n",
    )
    return path


@pytest.fixture
def trio(sandbox):
    ship, _ = make_repo(sandbox, "Ship_of_Theseus", "develop", scripts=True)
    designlib, _ = make_repo(sandbox, "SoT-fyc-space", "master", scripts=False)
    kb, _ = make_repo(sandbox, "ShipOfTheseus-KB", "main", scripts=False)
    return ship, designlib, kb


def test_ignore_environment_reads_only_the_roots_file(sandbox, trio) -> None:
    ship, designlib, kb = trio
    task = add_task(ship, "grouped", "task/grouped")
    roots = full_roots_file(sandbox, ship, designlib, kb)
    script = script_of(ship, "sot-worktree.ps1")
    other_group = sandbox / "elsewhere" / "Ship_of_Theseus"

    ignored = ps(
        script, ship, "-Action", "List", "-Repository", "ship", "-RootsFile", roots, "-IgnoreEnvironment",
        env={"SOT_SHIP_WORKTREE_ROOT": str(other_group), "SOT_SHIP_ROOT": str(sandbox / "missing")},
    )
    rows = json.loads(ignored.stdout)
    assert [row["grouped"] for row in rows if Path(row["path"]) == task] == [True]
    assert "override" not in ignored.stderr.lower()

    # Without -IgnoreEnvironment the environment wins and a warning names the variable.
    overridden = ps(
        script, ship, "-Action", "List", "-Repository", "ship", "-RootsFile", roots,
        env={"SOT_SHIP_WORKTREE_ROOT": str(other_group)},
    )
    rows = json.loads(overridden.stdout)
    assert [row["grouped"] for row in rows if Path(row["path"]) == task] == [False]
    assert "SOT_SHIP_WORKTREE_ROOT" in overridden.stderr
    assert str(other_group) not in overridden.stderr


def test_create_dry_run_writes_nothing_and_reports_the_plan(sandbox, trio) -> None:
    ship, designlib, kb = trio
    roots = full_roots_file(sandbox, ship, designlib, kb)
    script = script_of(ship, "sot-worktree.ps1")
    branches_before = git(ship, "for-each-ref", "refs/heads")

    result = ps(
        script, ship, "-Action", "Create", "-Repository", "ship", "-Task", "planned",
        "-Branch", "task/planned", "-BaseRef", "refs/remotes/origin/develop",
        "-RootsFile", roots, "-IgnoreEnvironment", "-DryRun",
    )
    plan = json.loads(result.stdout)
    assert plan["status"] == "dry-run"
    assert Path(plan["path"]) == ship / ".worktrees" / "planned"
    assert plan["branch"] == "task/planned"
    assert plan["base_commit"] == git(ship, "rev-parse", "refs/remotes/origin/develop")
    assert f"ship_root = '{ship.as_posix()}'" in plan["local_roots_content"]
    assert not (ship / ".worktrees").exists()
    assert git(ship, "for-each-ref", "refs/heads") == branches_before
    assert "planned" not in git(ship, "worktree", "list")

    real = ps(
        script, ship, "-Action", "Create", "-Repository", "ship", "-Task", "planned",
        "-Branch", "task/planned", "-BaseRef", "refs/remotes/origin/develop",
        "-RootsFile", roots, "-IgnoreEnvironment",
    )
    assert json.loads(real.stdout)
    assert (ship / ".worktrees" / "planned" / ".codex" / "project" / "sot-roots.local.toml").is_file()


def test_create_dry_run_still_validates(sandbox, trio) -> None:
    ship, designlib, kb = trio
    roots = full_roots_file(sandbox, ship, designlib, kb)
    result = ps(
        script_of(ship, "sot-worktree.ps1"), ship, "-Action", "Create", "-Repository", "ship",
        "-Task", "bad", "-Branch", "develop", "-BaseRef", "refs/remotes/origin/develop",
        "-RootsFile", roots, "-IgnoreEnvironment", "-DryRun", check=False,
    )
    assert result.returncode != 0
    assert not (ship / ".worktrees").exists()


def test_create_rejects_a_group_outside_the_repository(sandbox, trio) -> None:
    ship, designlib, kb = trio
    roots = full_roots_file(sandbox, ship, designlib, kb)
    text = roots.read_text(encoding="utf-8").replace(
        (ship / ".worktrees").as_posix(), (sandbox / "worktrees" / ship.name).as_posix()
    )
    roots.write_text(text, encoding="utf-8", newline="\n")
    result = ps(
        script_of(ship, "sot-worktree.ps1"), ship, "-Action", "Create", "-Repository", "ship",
        "-Task", "outside", "-Branch", "task/outside", "-BaseRef", "refs/remotes/origin/develop",
        "-RootsFile", roots, "-IgnoreEnvironment", "-DryRun", check=False,
    )
    assert result.returncode != 0 and ".worktrees" in (result.stdout + result.stderr)


def test_create_requires_the_group_to_be_ignored(sandbox, trio) -> None:
    ship, designlib, kb = trio
    (ship / ".gitignore").write_text(".codex/project/sot-roots.local.toml\n", encoding="utf-8")
    roots = full_roots_file(sandbox, ship, designlib, kb)
    result = ps(
        script_of(ship, "sot-worktree.ps1"), ship, "-Action", "Create", "-Repository", "ship",
        "-Task", "unignored", "-Branch", "task/unignored", "-BaseRef", "refs/remotes/origin/develop",
        "-RootsFile", roots, "-IgnoreEnvironment", "-DryRun", check=False,
    )
    assert result.returncode != 0 and "git-ignore" in (result.stdout + result.stderr)


def test_create_keeps_task_trees_out_of_a_godot_project(sandbox, trio) -> None:
    ship, designlib, kb = trio
    commit_file(ship, "project.godot", "config_version=5\n", "godot project")
    roots = full_roots_file(sandbox, ship, designlib, kb)
    ps(
        script_of(ship, "sot-worktree.ps1"), ship, "-Action", "Create", "-Repository", "ship",
        "-Task", "godot", "-Branch", "task/godot", "-BaseRef", "HEAD",
        "-RootsFile", roots, "-IgnoreEnvironment",
    )
    assert (ship / ".worktrees" / ".gdignore").is_file()
    assert (ship / ".worktrees" / "godot" / "project.godot").is_file()
    assert git(ship, "status", "--porcelain") == ""


# --------------------------------------------------------------------------- sot-sync


def sync(repo_script_owner: Path, cwd: Path, *args, check=True):
    return ps(script_of(repo_script_owner, "sot-sync.ps1"), cwd, *args, "-IgnoreEnvironment", check=check)


def advance_origin(repo: Path, branch: str, name: str, content: str) -> None:
    """Push a new commit to origin/<branch> from a scratch clone, keeping repo untouched."""
    origin = git(repo, "remote", "get-url", "origin")
    scratch = repo.parent / f"scratch-{name}"
    git(repo.parent, "clone", "-q", "--branch", branch, origin, str(scratch))
    git(scratch, "config", "core.autocrlf", "false")
    commit_file(scratch, name, content, f"upstream {name}")
    git(scratch, "push", "-q", "origin", branch)


def test_sync_merges_origin_base_into_task_branch(sandbox, trio) -> None:
    ship, _, _ = trio
    task = add_task(ship, "t1", "task/t1")
    commit_file(task, "mine.txt", "mine\n", "mine")
    up_to_date = json.loads(sync(ship, task).stdout)
    assert up_to_date["status"] == "up-to-date"

    advance_origin(ship, "develop", "theirs.txt", "theirs\n")
    preview = json.loads(sync(ship, task, "-DryRun").stdout)
    assert preview["status"] == "dry-run"
    assert (preview["ahead"], preview["behind"], preview["predicted"]) == (1, 1, "clean")
    assert not (task / "theirs.txt").exists()

    merged = json.loads(sync(ship, task).stdout)
    assert merged["status"] == "merged"
    assert (task / "theirs.txt").is_file() and (task / "mine.txt").is_file()
    assert len(git(task, "rev-list", "--parents", "-n1", "HEAD").split()) == 3  # a real merge commit


def test_sync_refuses_main_worktree_protected_branch_and_detached_head(sandbox, trio) -> None:
    ship, _, _ = trio
    refused = sync(ship, ship, check=False)
    assert refused.returncode != 0 and "main worktree" in (refused.stdout + refused.stderr).lower()

    task = add_task(ship, "t2", "task/t2")
    git(task, "checkout", "-q", "--detach")
    detached = sync(ship, task, check=False)
    assert detached.returncode != 0 and "detached" in (detached.stdout + detached.stderr).lower()

    protected = add_task(ship, "t3", "master")
    refused = sync(ship, protected, check=False)
    assert refused.returncode != 0 and "protected" in (refused.stdout + refused.stderr).lower()


def test_sync_refuses_dirty_tree_and_dry_run_reports_it(sandbox, trio) -> None:
    ship, _, _ = trio
    task = add_task(ship, "t4", "task/t4")
    (task / "base.txt").write_text("dirty\n", encoding="utf-8")
    refused = sync(ship, task, check=False)
    assert refused.returncode != 0 and "not clean" in (refused.stdout + refused.stderr).lower()

    report = sync(ship, task, "-DryRun", check=False)
    assert report.returncode != 0
    data = json.loads(report.stdout)
    assert data["clean"] is False and data["dirty_files"]


def test_sync_conflict_is_reported_and_abort_restores_the_branch(sandbox, trio) -> None:
    ship, _, _ = trio
    task = add_task(ship, "t5", "task/t5")
    commit_file(task, "base.txt", "mine\n", "mine edits base")
    advance_origin(ship, "develop", "base.txt", "theirs\n")
    head_before = git(task, "rev-parse", "HEAD")

    preview = json.loads(sync(ship, task, "-DryRun").stdout)
    assert preview["predicted"] == "conflict" and preview["conflict_files"] == ["base.txt"]

    conflict = sync(ship, task, check=False)
    assert conflict.returncode == 2
    data = json.loads(conflict.stdout)
    assert data["status"] == "conflict" and data["conflict_files"] == ["base.txt"]
    assert (task / ".git").exists() and git(task, "rev-parse", "-q", "--verify", "MERGE_HEAD")

    again = sync(ship, task, check=False)
    assert again.returncode != 0 and "in progress" in (again.stdout + again.stderr).lower()

    aborted = json.loads(sync(ship, task, "-Abort").stdout)
    assert aborted["status"] == "aborted"
    assert git(task, "rev-parse", "HEAD") == head_before
    assert git(task, "status", "--porcelain") == ""

    nothing = sync(ship, task, "-Abort", check=False)
    assert nothing.returncode != 0 and "no merge" in (nothing.stdout + nothing.stderr).lower()


def test_sync_resolves_designlib_default_branch_and_authorizes_by_roots(sandbox, trio) -> None:
    ship, designlib, kb = trio
    task = add_task(designlib, "dl", "task/dl")
    roots = write_roots(sandbox / "roots.toml", designlib_root=designlib)
    script = script_of(ship, "sot-sync.ps1")
    advance_origin(designlib, "master", "dl-new.txt", "x\n")
    merged = json.loads(ps(script, task, "-RootsFile", roots, "-IgnoreEnvironment").stdout)
    assert merged["status"] == "merged" and merged["base"] == "origin/master"

    # Not configured: refused as a foreign repository.
    unauthorized = ps(script, task, "-RootsFile", sandbox / "none.toml", "-IgnoreEnvironment", check=False)
    assert unauthorized.returncode != 0 and "authorized" in (unauthorized.stdout + unauthorized.stderr).lower()


def test_sync_allows_kb_fixed_vault_on_a_task_branch_only(sandbox, trio) -> None:
    ship, _, kb = trio
    roots = write_roots(sandbox / "roots.toml", kb_root=kb)
    script = script_of(ship, "sot-sync.ps1")
    on_default = ps(script, kb, "-RootsFile", roots, "-IgnoreEnvironment", check=False)
    assert on_default.returncode != 0 and "protected" in (on_default.stdout + on_default.stderr).lower()

    git(kb, "checkout", "-q", "-b", "task/kb-note")
    advance_origin(kb, "main", "kb-new.txt", "x\n")
    merged = json.loads(ps(script, kb, "-RootsFile", roots, "-IgnoreEnvironment").stdout)
    assert merged["status"] == "merged" and merged["repository"] == "kb"


def test_sync_requires_explicit_base_when_default_cannot_be_resolved(sandbox, trio) -> None:
    ship, designlib, _ = trio
    task = add_task(designlib, "nobase", "task/nobase")
    git(designlib, "remote", "set-url", "origin", str(sandbox / "gone.git"))
    git(designlib, "remote", "set-head", "origin", "-d")
    roots = write_roots(sandbox / "roots.toml", designlib_root=designlib)
    result = ps(script_of(ship, "sot-sync.ps1"), task, "-RootsFile", roots, "-IgnoreEnvironment", check=False)
    assert result.returncode != 0 and "-basebranch" in (result.stdout + result.stderr).lower()


# --------------------------------------------------------------------------- sot-memory


def memory_setup(sandbox: Path, trio):
    ship, _, _ = trio
    task = add_task(ship, "mem", "task/mem")
    memory = ship / ".sot" / "memory"
    bucket = "D--Fixture-Bucket"
    (memory / "projects" / bucket).mkdir(parents=True)
    return ship, task, memory, bucket


def memory(task: Path, *args, check=True, env=None):
    return ps(script_of(task, "sot-memory.ps1"), task, *args, "-IgnoreEnvironment", check=check, env=env)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_memory_default_root_and_bucket_come_from_the_primary_worktree(sandbox, trio) -> None:
    ship, task, mem, _ = memory_setup(sandbox, trio)
    result = json.loads(memory(task, "-Action", "Status").stdout)
    assert Path(result["memory_root"]) == mem
    assert result["memory_root_source"] == "primary-worktree"
    posix = ship.as_posix()
    if len(posix) > 2 and posix[1] == ":":
        expected = posix[0].upper() + "--" + "-".join(part for part in posix[3:].split("/") if part)
    else:
        expected = "-" + "-".join(part for part in posix.split("/") if part)
    assert result["bucket"] == expected and result["bucket"] != "-".join(task.parts[-2:])


def test_memory_root_resolution_order(sandbox, trio) -> None:
    ship, task, mem, bucket = memory_setup(sandbox, trio)
    configured = sandbox / "configured-memory"
    configured.mkdir()
    roots = sandbox / "roots.toml"
    roots.write_text(f"[roots]\nmemory_root = '{configured.as_posix()}'\n", encoding="utf-8")
    script = script_of(task, "sot-memory.ps1")
    args = ["-Action", "Status", "-Bucket", bucket, "-RootsFile", roots]
    from_file = json.loads(ps(script, task, *args, "-IgnoreEnvironment").stdout)
    assert Path(from_file["memory_root"]) == configured and from_file["memory_root_source"] == "roots.memory_root"

    environment = sandbox / "env-memory"
    environment.mkdir()
    from_env = ps(script, task, *args, env={"SOT_MEMORY_ROOT": str(environment)})
    assert Path(json.loads(from_env.stdout)["memory_root"]) == environment
    assert "SOT_MEMORY_ROOT" in from_env.stderr

    missing = ps(script, task, "-Action", "Status", "-Bucket", bucket, "-RootsFile", sandbox / "none.toml",
                 "-IgnoreEnvironment", env={"SOT_MEMORY_ROOT": str(sandbox / "absent")}, check=True)
    assert Path(json.loads(missing.stdout)["memory_root"]) == mem  # the variable was ignored


def test_memory_record_and_verify_cycle(sandbox, trio) -> None:
    _, task, mem, bucket = memory_setup(sandbox, trio)
    target = mem / "projects" / bucket / "notes" / "MEMORY.md"
    target.parent.mkdir()
    target.write_text("v1\n", encoding="utf-8")
    args = ["-Bucket", bucket]

    unrecorded = json.loads(memory(task, "-Action", "Verify", "-Path", "notes/MEMORY.md", *args).stdout)
    assert unrecorded["result"] == "unrecorded"

    # An unrelated row and a malformed row must survive byte for byte.
    other = '{"project_bucket":"Other","relative_path":"x.md","sha256":"00","size_bytes":1}'
    (mem / "index.jsonl").write_bytes((other + "\nnot json\n").encode("utf-8"))
    added = json.loads(memory(task, "-Action", "Record", "-Path", "notes/MEMORY.md", *args).stdout)
    assert added["result"] == "added" and added["sha256"] == sha(target)
    raw = (mem / "index.jsonl").read_bytes()
    assert raw.startswith((other + "\nnot json\n").encode()) and b"\r" not in raw and not raw.startswith(b"\xef\xbb\xbf")
    row = json.loads(raw.decode().splitlines()[2])
    assert row == {"project_bucket": bucket, "relative_path": "notes/MEMORY.md", "sha256": sha(target), "size_bytes": target.stat().st_size}
    assert list(row) == ["project_bucket", "relative_path", "sha256", "size_bytes"]

    assert json.loads(memory(task, "-Action", "Verify", "-Path", "notes/MEMORY.md", *args).stdout)["result"] == "match"

    old_hash = sha(target)
    target.write_text("v2 changed\n", encoding="utf-8")
    mismatch = memory(task, "-Action", "Verify", "-Path", "notes/MEMORY.md", *args, check=False)
    assert mismatch.returncode == 1 and json.loads(mismatch.stdout)["result"] == "mismatch"
    status = memory(task, "-Action", "Status", *args, check=False)
    assert status.returncode == 1 and json.loads(status.stdout)["problems"] == 1

    updated = json.loads(memory(task, "-Action", "Record", "-Path", "notes/MEMORY.md", "-ExpectedSha256", old_hash, *args).stdout)
    assert updated["result"] == "updated"
    lines = (mem / "index.jsonl").read_text(encoding="utf-8").splitlines()
    assert len(lines) == 3 and lines[0] == other and lines[1] == "not json"
    assert json.loads(lines[2])["sha256"] == sha(target)
    assert not list(mem.glob("index.jsonl.*"))  # no temp or lock leftovers

    target.unlink()
    missing = memory(task, "-Action", "Verify", "-Path", "notes/MEMORY.md", *args, check=False)
    assert missing.returncode == 2 and json.loads(missing.stdout)["result"] == "missing"


def test_memory_record_rejects_stale_expected_hash(sandbox, trio) -> None:
    _, task, mem, bucket = memory_setup(sandbox, trio)
    target = mem / "projects" / bucket / "a.md"
    target.write_text("one\n", encoding="utf-8")
    memory(task, "-Action", "Record", "-Path", "a.md", "-Bucket", bucket)
    stale = sha(target)
    target.write_text("two (other agent)\n", encoding="utf-8")
    memory(task, "-Action", "Record", "-Path", "a.md", "-Bucket", bucket)
    index_before = (mem / "index.jsonl").read_bytes()

    target.write_text("three (me)\n", encoding="utf-8")
    refused = memory(task, "-Action", "Record", "-Path", "a.md", "-ExpectedSha256", stale, "-Bucket", bucket, check=False)
    assert refused.returncode != 0 and "concurrent" in (refused.stdout + refused.stderr).lower()
    assert (mem / "index.jsonl").read_bytes() == index_before

    no_row = memory(task, "-Action", "Record", "-Path", "a.md", "-ExpectedSha256", "0" * 64, "-Bucket", bucket, check=False)
    assert no_row.returncode != 0
    assert memory(task, "-Action", "Record", "-Path", "missing.md", "-Bucket", bucket, check=False).returncode != 0


@pytest.mark.parametrize(
    "bad_path",
    ["../outside.md", "notes/../../outside.md", "..\\outside.md", "/etc/passwd", "C:/Windows/x", "C:x", "a//b.md", "./a.md", ""],
)
def test_memory_rejects_paths_that_escape_the_bucket(sandbox, trio, bad_path) -> None:
    _, task, mem, bucket = memory_setup(sandbox, trio)
    (mem / "outside.md").write_text("outside\n", encoding="utf-8")
    for action in ("Verify", "Record"):
        result = memory(task, "-Action", action, "-Path", bad_path, "-Bucket", bucket, check=False)
        assert result.returncode != 0
    assert not (mem / "index.jsonl").exists()


def test_memory_rejects_reparse_points_and_bad_bucket(sandbox, trio) -> None:
    _, task, mem, bucket = memory_setup(sandbox, trio)
    outside = sandbox / "outside-dir"
    outside.mkdir()
    (outside / "secret.md").write_text("secret\n", encoding="utf-8")
    link = mem / "projects" / bucket / "link"
    try:
        os.symlink(outside, link, target_is_directory=True)
    except (OSError, NotImplementedError):
        if sys.platform == "win32":
            made = subprocess.run(["cmd", "/c", "mklink", "/J", str(link), str(outside)], capture_output=True)
            if made.returncode != 0:
                pytest.skip("cannot create a link in this environment")
        else:
            pytest.skip("cannot create a link in this environment")
    result = memory(task, "-Action", "Record", "-Path", "link/secret.md", "-Bucket", bucket, check=False)
    assert result.returncode != 0 and "reparse" in (result.stdout + result.stderr).lower()
    assert not (mem / "index.jsonl").exists()
    for bucket_name in ("..", "a/b", "a\\b"):
        assert memory(task, "-Action", "Status", "-Bucket", bucket_name, check=False).returncode != 0


def test_memory_reports_missing_memory_root(sandbox, trio) -> None:
    ship, _, _ = trio
    task = add_task(ship, "nomem", "task/nomem")
    result = memory(task, "-Action", "Status", "-Bucket", "b", check=False)
    assert result.returncode != 0 and "missing" in (result.stdout + result.stderr).lower()
    assert not (ship / ".sot").exists()


# --------------------------------------------------------------------------- sot-publish stacked detection


def isolated_path(directory: Path) -> dict[str, str]:
    """PATH holding only the fake gh directory plus the git and pwsh directories."""
    path = os.pathsep.join(
        [str(directory), str(Path(shutil.which("git")).parent), str(Path(shutil.which("pwsh")).parent)]
    )
    found = shutil.which("gh", path=path)
    if (directory / "gh.cmd").exists() or (directory / "gh").exists():
        assert found is not None and Path(found).parent == directory, "the fake gh must shadow any real gh"
    else:
        assert found is None, "a real gh is reachable"
    return {"PATH": path}


def fake_gh(directory: Path, payload: object | None, exit_code: int = 0) -> dict[str, str]:
    directory.mkdir(parents=True, exist_ok=True)
    data = directory / "gh.json"
    data.write_text(json.dumps(payload if payload is not None else []), encoding="utf-8")
    if os.name == "nt":
        (directory / "gh.cmd").write_text(
            f'@echo off\r\nif {exit_code} NEQ 0 exit /b {exit_code}\r\ntype "{data}"\r\n', encoding="utf-8"
        )
    else:
        script = directory / "gh"
        script.write_text(f'#!/bin/sh\n[ {exit_code} -ne 0 ] && exit {exit_code}\ncat "{data}"\n', encoding="utf-8")
        script.chmod(0o755)
    return isolated_path(directory)


def stacked_setup(sandbox: Path, trio):
    ship, _, _ = trio
    git(ship, "checkout", "-q", "-b", "lane/a/1")
    commit_file(ship, "a.txt", "a\n", "lane a")
    git(ship, "push", "-q", "origin", "lane/a/1")
    git(ship, "checkout", "-q", "-b", "lane/b/1")
    commit_file(ship, "b.txt", "b\n", "lane b")
    prs = [{"number": 46, "headRefName": "lane/a/1", "baseRefName": "develop"}]
    return ship, prs


def publish(ship: Path, env: dict[str, str], *args, check=True):
    return ps(script_of(ship, "sot-publish.ps1"), ship, "-DryRun", *args, check=check, env=env)


def test_publish_refuses_stacking_without_declaration(sandbox, trio) -> None:
    ship, prs = stacked_setup(sandbox, trio)
    env = fake_gh(sandbox / "bin", prs)
    refused = publish(ship, env, check=False)
    text = refused.stdout + refused.stderr
    assert refused.returncode != 0 and "#46" in text and "-StackedOn" in text

    allowed = publish(ship, env, "-StackedOn", "lane/a/1")
    assert "#46" in allowed.stdout and "merge after" in allowed.stdout
    assert "lane/b/1" in allowed.stdout


def test_publish_stacking_is_not_flagged_for_independent_or_merged_heads(sandbox, trio) -> None:
    ship, prs = stacked_setup(sandbox, trio)
    env = fake_gh(sandbox / "bin", prs)

    # The PR head itself is not stacked on itself.
    git(ship, "checkout", "-q", "lane/a/1")
    assert "#46" not in publish(ship, env).stdout

    # A branch cut from the protected base does not contain the PR head.
    git(ship, "checkout", "-q", "-b", "lane/c/1", "origin/develop")
    commit_file(ship, "c.txt", "c\n", "lane c")
    assert "stacked" not in (publish(ship, env).stdout).lower()

    # Once the PR head is part of the protected base, it no longer counts.
    git(ship, "checkout", "-q", "lane/b/1")
    git(ship, "push", "-q", "origin", "lane/a/1:develop")
    git(ship, "fetch", "-q", "origin")
    assert "stacked" not in publish(ship, env).stdout.lower()


def test_publish_continues_with_a_warning_when_gh_is_unusable(sandbox, trio) -> None:
    ship, prs = stacked_setup(sandbox, trio)
    failing = publish(ship, fake_gh(sandbox / "bin-fail", prs, exit_code=1))
    assert failing.returncode == 0 and "skipped the stacked pull request check" in failing.stderr
    assert "Dry-run" in failing.stdout

    no_gh_path = sandbox / "empty-bin"
    no_gh_path.mkdir()
    missing = publish(ship, isolated_path(no_gh_path))
    assert missing.returncode == 0 and "gh is not available" in missing.stderr


# --------------------------------------------------------------------------- review follow-ups


def default_bucket(ship: Path) -> str:
    posix = ship.as_posix()
    if len(posix) > 2 and posix[1] == ":":
        return posix[0].upper() + "--" + "-".join(part for part in posix[3:].split("/") if part)
    return "-" + "-".join(part for part in posix.split("/") if part)


def make_link(link: Path, target: Path) -> None:
    try:
        os.symlink(target, link, target_is_directory=True)
    except (OSError, NotImplementedError):
        if sys.platform == "win32":
            made = subprocess.run(["cmd", "/c", "mklink", "/J", str(link), str(target)], capture_output=True)
            if made.returncode == 0:
                return
        pytest.skip("cannot create a link in this environment")


def test_memory_uses_the_real_projects_layout(sandbox, trio) -> None:
    ship, task, mem, _ = memory_setup(sandbox, trio)
    bucket = default_bucket(ship)
    source = sandbox / "lanes.md"
    source.write_bytes(b"# lanes\n")

    created = json.loads(memory(task, "-Action", "Write", "-Path", "LANES.md", "-SourceFile", source, "-CreateNew").stdout)
    assert created["bucket"] == bucket
    target = mem / "projects" / bucket / "LANES.md"
    assert target.read_bytes() == b"# lanes\n"
    assert not (mem / bucket).exists()
    row = json.loads((mem / "index.jsonl").read_text(encoding="utf-8").splitlines()[0])
    assert (row["project_bucket"], row["relative_path"]) == (bucket, "LANES.md")

    verified = json.loads(memory(task, "-Action", "Verify", "-Path", "LANES.md").stdout)
    assert verified["result"] == "match"
    h0 = sha(target)
    source.write_bytes(b"# lanes v2\n")
    written = json.loads(memory(task, "-Action", "Write", "-Path", "LANES.md", "-SourceFile", source, "-ExpectedSha256", h0).stdout)
    assert written["result"] == "written"
    assert json.loads(memory(task, "-Action", "Status").stdout)["problems"] == 0


def test_memory_ignores_non_object_index_lines(sandbox, trio) -> None:
    _, task, mem, bucket = memory_setup(sandbox, trio)
    (mem / "index.jsonl").write_bytes(b'[1,2]\n5\nnull\n"text"\n')
    result = json.loads(memory(task, "-Action", "Verify", "-Path", "a.md", "-Bucket", bucket, check=False).stdout)
    assert result["result"] == "missing"
    assert json.loads(memory(task, "-Action", "Status", "-Bucket", bucket).stdout)["entries"] == []


@pytest.mark.skipif(sys.platform != "win32", reason="Windows path rules")
@pytest.mark.parametrize(
    "bad_path", ["CON", "nul.txt", "dir/COM1.md", "lpt9", "a:b.md", "dir/a:stream", "trail./x.md", "trail /x.md"]
)
def test_memory_rejects_windows_reserved_and_invalid_segments(sandbox, trio, bad_path) -> None:
    _, task, mem, bucket = memory_setup(sandbox, trio)
    source = sandbox / "s"
    source.write_bytes(b"x")
    assert memory(task, "-Action", "Verify", "-Path", bad_path, "-Bucket", bucket, check=False).returncode != 0
    write = memory(task, "-Action", "Write", "-Path", bad_path, "-SourceFile", source, "-CreateNew", "-Bucket", bucket, check=False)
    assert write.returncode != 0 and not (mem / "index.jsonl").exists()


def test_memory_write_refuses_reparse_points_before_touching_anything(sandbox, trio) -> None:
    _, task, mem, bucket = memory_setup(sandbox, trio)
    outside = sandbox / "outside-dir"
    outside.mkdir()
    make_link(mem / "projects" / bucket / "link", outside)
    source = sandbox / "s"
    source.write_bytes(b"x")
    for sub in ("link/new.md", "link/deeper/new.md"):
        result = memory(task, "-Action", "Write", "-Path", sub, "-SourceFile", source, "-CreateNew", "-Bucket", bucket, check=False)
        assert result.returncode != 0 and "reparse" in (result.stdout + result.stderr).lower()
    assert list(outside.iterdir()) == [] and not (mem / "index.jsonl").exists()


@pytest.mark.skipif(sys.platform != "win32", reason="relies on Windows sharing semantics")
def test_memory_write_reports_a_stale_index_when_the_index_cannot_be_replaced(sandbox, trio) -> None:
    _, task, mem, bucket = memory_setup(sandbox, trio)
    (mem / "index.jsonl").write_bytes(b"")
    source = sandbox / "s"
    source.write_bytes(b"content\n")
    with open(mem / "index.jsonl", "rb"):  # a reader without delete sharing blocks the atomic swap
        result = memory(task, "-Action", "Write", "-Path", "f.md", "-SourceFile", source, "-CreateNew", "-Bucket", bucket, check=False)
    assert result.returncode == 3
    data = json.loads(result.stdout)
    target = mem / "projects" / bucket / "f.md"
    assert data["status"] == "written-index-stale" and data["sha256"] == sha(target)
    assert not list(mem.glob("index.jsonl.*"))
    fixed = json.loads(memory(task, "-Action", "Record", "-Path", "f.md", "-Bucket", bucket).stdout)
    assert fixed["result"] == "added"


def test_publish_detects_a_lower_pr_that_advanced_after_this_branch_was_cut(sandbox, trio) -> None:
    ship, prs = stacked_setup(sandbox, trio)
    env = fake_gh(sandbox / "bin", prs)
    # The lower PR gets a new commit after lane/b/1 was cut: its head is no longer an ancestor of HEAD.
    origin = git(ship, "remote", "get-url", "origin")
    scratch = sandbox / "scratch-lower"
    git(sandbox, "clone", "-q", "--branch", "lane/a/1", origin, str(scratch))
    git(scratch, "config", "core.autocrlf", "false")
    commit_file(scratch, "a2.txt", "more\n", "lower advanced")
    git(scratch, "push", "-q", "origin", "lane/a/1")
    refused = publish(ship, env, check=False)
    assert refused.returncode != 0 and "#46" in refused.stdout + refused.stderr
    allowed = publish(ship, env, "-StackedOn", "lane/a/1")
    assert "#46" in allowed.stdout


def test_sync_refuses_designlib_main_worktree_and_kb_linked_worktree(sandbox, trio) -> None:
    ship, designlib, kb = trio
    roots = sandbox / "roots.toml"
    roots.write_text(
        f"[roots]\ndesignlib_root = '{designlib.as_posix()}'\nkb_root = '{kb.as_posix()}'\n", encoding="utf-8"
    )
    script = script_of(ship, "sot-sync.ps1")
    main = ps(script, designlib, "-RootsFile", roots, "-IgnoreEnvironment", check=False)
    assert main.returncode != 0 and "main worktree" in (main.stdout + main.stderr).lower()

    linked = add_task(kb, "kb-linked", "task/kb-linked")
    refused = ps(script, linked, "-RootsFile", roots, "-IgnoreEnvironment", check=False)
    assert refused.returncode != 0 and "fixed kb vault" in (refused.stdout + refused.stderr).lower()


def test_sync_authorizes_through_environment_and_warns_on_override(sandbox, trio) -> None:
    ship, designlib, _ = trio
    task = add_task(designlib, "env", "task/env")
    script = script_of(ship, "sot-sync.ps1")
    advance_origin(designlib, "master", "env-new.txt", "x\n")
    # No roots file at all: the environment variable alone authorizes the designlib checkout.
    merged = ps(script, task, "-RootsFile", sandbox / "none.toml", env={"SOT_DESIGNLIB_ROOT": str(designlib)})
    assert json.loads(merged.stdout)["status"] == "merged"
    assert "SOT_DESIGNLIB_ROOT" in merged.stderr  # explicit -RootsFile overridden by the environment

    quiet = ps(script, task, env={"SOT_DESIGNLIB_ROOT": str(designlib)})
    assert "WARNING" not in quiet.stderr  # default roots file path: not an explicit override


def test_sync_ignores_unrelated_invalid_configured_roots(sandbox, trio) -> None:
    ship, designlib, _ = trio
    task = add_task(ship, "robust", "task/robust")
    roots = sandbox / "roots.toml"
    missing = (sandbox / "does-not-exist").as_posix()
    roots.write_text(f"[roots]\ndesignlib_root = '{missing}'\nkb_root = '{sandbox.as_posix()}'\n", encoding="utf-8")
    result = ps(script_of(ship, "sot-sync.ps1"), task, "-RootsFile", roots, "-IgnoreEnvironment")
    assert json.loads(result.stdout)["status"] == "up-to-date"


def test_create_dry_run_fails_when_the_branch_already_exists(sandbox, trio) -> None:
    ship, designlib, kb = trio
    roots = full_roots_file(sandbox, ship, designlib, kb)
    git(ship, "branch", "task/taken", "origin/develop")
    result = ps(
        script_of(ship, "sot-worktree.ps1"), ship, "-Action", "Create", "-Repository", "ship", "-Task", "x",
        "-Branch", "task/taken", "-BaseRef", "refs/remotes/origin/develop", "-RootsFile", roots,
        "-IgnoreEnvironment", "-DryRun", check=False,
    )
    assert result.returncode != 0 and "already exists" in (result.stdout + result.stderr)
