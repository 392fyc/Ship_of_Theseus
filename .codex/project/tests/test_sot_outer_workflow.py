import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".codex/project/workflows/sot-outer.yml"
CLI = ("uvx", "--from", "specify-cli==1.0.1", "specify")


def run_specify(*args: str, cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [*CLI, "workflow", *args],
        cwd=cwd,
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        check=False,
    )


def initialize_project(project: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            *CLI,
            "init",
            "--here",
            "--force",
            "--non-interactive",
            "--ignore-agent-tools",
        ],
        cwd=project,
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        check=False,
    )


class SotOuterWorkflowTests(unittest.TestCase):
    def test_workflow_add_rejects_invalid_enum_inputs_and_resumes(self) -> None:
        self.assertTrue(WORKFLOW.is_file())

        with tempfile.TemporaryDirectory() as temporary_directory:
            project = Path(temporary_directory)
            workflow_copy = project / "sot-outer.yml"
            shutil.copy2(WORKFLOW, workflow_copy)

            initialized = initialize_project(project)
            self.assertEqual(initialized.returncode, 0, initialized.stderr)

            installed = run_specify("add", "--dev", str(workflow_copy), cwd=project)
            self.assertEqual(installed.returncode, 0, installed.stdout + installed.stderr)

            for invalid_input in (
                "authority=invalid",
                "task_size=XL",
                "approval=maybe",
            ):
                rejected = run_specify("run", "sot-outer", "--input", invalid_input, "--json", cwd=project)
                self.assertNotEqual(rejected.returncode, 0, rejected.stdout + rejected.stderr)

            paused = run_specify(
                "run",
                "sot-outer",
                "--input",
                "authority=ship",
                "--input",
                "task_size=S",
                "--input",
                "approval=reject",
                "--json",
                cwd=project,
            )
            self.assertEqual(paused.returncode, 0, paused.stderr)
            paused_result = json.loads(paused.stdout)
            self.assertEqual(paused_result["status"], "paused")
            self.assertTrue((project / ".specify/workflows/runs").is_dir())

            resumed = run_specify(
                "resume",
                paused_result["run_id"],
                "--input",
                "approval=approve",
                "--json",
                cwd=project,
            )
            self.assertEqual(resumed.returncode, 0, resumed.stderr)
            self.assertEqual(json.loads(resumed.stdout)["status"], "completed")

    def test_gitignore_ignores_workflow_run_state(self) -> None:
        self.assertIn(".specify/workflows/runs/", (ROOT / ".gitignore").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
