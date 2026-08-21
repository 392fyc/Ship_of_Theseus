from __future__ import annotations

import json
from pathlib import Path
import tomllib
import unittest


PROJECT_DIR = Path(__file__).resolve().parents[1]
CODEX_DIR = PROJECT_DIR.parent
TASK_CONTRACT_PATH = PROJECT_DIR / "mercury-task-contract.md"
AGENT_PATHS = {
    "developer": CODEX_DIR / "agents" / "mercury-dev.toml",
    "reviewer": CODEX_DIR / "agents" / "mercury-reviewer.toml",
    "acceptance": CODEX_DIR / "agents" / "mercury-acceptance.toml",
}


def load_agent_instructions(role: str) -> str:
    with AGENT_PATHS[role].open("rb") as stream:
        definition = tomllib.load(stream)
    return definition["developer_instructions"]


class MercuryContractConsistencyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.task_contract = TASK_CONTRACT_PATH.read_text(encoding="utf-8")
        cls.agent_instructions = {
            role: load_agent_instructions(role) for role in AGENT_PATHS
        }

    def test_every_role_binds_to_the_frozen_bundle_revision_and_digest(self) -> None:
        for role, instructions in self.agent_instructions.items():
            with self.subTest(role=role):
                self.assertIn("bundle_revision", instructions)
                self.assertIn("bundle_sha256", instructions)

    def test_developer_honors_the_repair_budget_and_reports_scope_discoveries(self) -> None:
        instructions = self.agent_instructions["developer"]
        self.assertIn("max_repair_rounds", instructions)
        self.assertIn("Do not adopt out-of-scope discoveries", instructions)
        self.assertIn("never start a second remediation round", instructions)

    def test_reviewer_emits_every_schema_finding_field_in_both_modes(self) -> None:
        instructions = self.agent_instructions["reviewer"]
        self.assertIn("initial", instructions)
        self.assertIn("remediation", instructions)

        schema = json.loads(
            (PROJECT_DIR / "review-result.schema.json").read_text(encoding="utf-8")
        )
        finding_fields = schema["properties"]["findings"]["items"]["required"]
        for field in finding_fields:
            with self.subTest(field=field):
                self.assertIn(f"`{field}`", instructions)

        self.assertIn("Only `blocking` findings change the verdict", instructions)

    def test_remediation_review_cannot_expand_ordinary_blocking_scope(self) -> None:
        instructions = self.agent_instructions["reviewer"]
        self.assertIn("RemediationChecklist", instructions)
        self.assertIn(
            "Do not add an ordinary `blocking` finding outside the checklist",
            instructions,
        )

    def test_acceptance_keeps_follow_up_findings_visible_but_non_failing(self) -> None:
        instructions = self.agent_instructions["acceptance"]
        self.assertIn("follow_up", instructions)
        self.assertIn("accepted_risk", instructions)
        self.assertIn("do not fail acceptance", instructions)

    def test_task_contract_declares_the_five_level_authority_order(self) -> None:
        contract = self.task_contract
        authority_order = [
            "project safety, single-writer, and destructive-operation contracts",
            "frozen ReviewBundle",
            "specification sections referenced by the ReviewBundle",
            "implementation receipt",
            "progress ledgers and historical decisions",
        ]
        positions = [contract.find(item) for item in authority_order]
        self.assertNotIn(-1, positions)
        self.assertEqual(positions, sorted(positions))

    def test_task_contract_schedules_focused_affected_and_full_verification(self) -> None:
        contract = self.task_contract
        self.assertIn("`focused` and `affected`", contract)
        self.assertIn("reproduction and directly affected", contract)
        self.assertIn("run `full` once", contract)

    def test_task_contract_ends_after_one_remediation_round(self) -> None:
        contract = self.task_contract
        self.assertIn("`max_repair_rounds` must equal `1`", contract)
        self.assertIn("split, redesign, or report", contract)

    def test_contracts_do_not_require_open_ended_repair_regressions(self) -> None:
        contracts = [self.task_contract, *self.agent_instructions.values()]
        forbidden_instructions = (
            "run full regression during every repair round",
            "continue up to five repair rounds",
        )
        for index, contract in enumerate(contracts):
            for forbidden in forbidden_instructions:
                with self.subTest(contract=index, forbidden=forbidden):
                    self.assertNotIn(forbidden, contract.lower())


if __name__ == "__main__":
    unittest.main()
