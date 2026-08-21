from __future__ import annotations

import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


PROJECT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_DIR))

from validate_harness_bundle import bundle_digest, validate_bundle, validate_review


VALID_BUNDLE = {
    "schema_version": 1,
    "task_id": "example.task",
    "bundle_revision": 1,
    "target_head": "a" * 40,
    "primary_deliverable": "one bounded behavior",
    "change_kinds": ["harness_contract"],
    "acceptance_criteria": [
        {
            "id": "AC-1",
            "statement": "The bounded behavior is observable.",
            "paths": [".codex/project/example.json"],
            "cases": ["valid", "invalid"],
        }
    ],
    "allowed_write_paths": [".codex/project/example.json"],
    "forbidden_paths": ["data", "scripts"],
    "impact_cone": [".codex/project"],
    "test_policy": {
        "focused": ["python -m unittest focused"],
        "affected": ["python -m unittest affected"],
        "full": "python -m unittest discover",
        "full_triggers": ["dependency_change", "test_config_change"],
        "reuse_keys": [
            "candidate_head",
            "dependency_fingerprint",
            "test_config_fingerprint",
            "environment_fingerprint",
        ],
    },
    "max_repair_rounds": 1,
}


def valid_bundle() -> dict[str, object]:
    bundle = copy.deepcopy(VALID_BUNDLE)
    bundle["bundle_sha256"] = bundle_digest(bundle)
    return bundle


def finding(**overrides: object) -> dict[str, object]:
    result: dict[str, object] = {
        "id": "F-1",
        "criterion_id": None,
        "introduced_by_candidate": False,
        "in_scope": False,
        "severity": "minor",
        "category": "adjacent_risk",
        "disposition": "follow_up",
        "directly_caused_by_remediation": False,
        "evidence": "A bounded observation.",
        "correction": "Track in a later bounded task.",
    }
    result.update(overrides)
    return result


def valid_review(bundle: dict[str, object]) -> dict[str, object]:
    return {
        "schema_version": 1,
        "task_id": bundle["task_id"],
        "bundle_revision": bundle["bundle_revision"],
        "bundle_sha256": bundle["bundle_sha256"],
        "candidate_head": "b" * 40,
        "review_mode": "initial",
        "remediation_finding_ids": [],
        "findings": [finding()],
        "verdict": "pass",
    }


class BundleValidationTests(unittest.TestCase):
    def assert_invalid(self, bundle: dict[str, object], fragment: str) -> None:
        errors = validate_bundle(bundle)
        self.assertTrue(errors, "expected the bundle to be rejected")
        self.assertTrue(
            any(fragment in error for error in errors),
            f"expected an error containing {fragment!r}, got {errors!r}",
        )

    def test_valid_bundle_is_accepted(self) -> None:
        self.assertEqual(validate_bundle(valid_bundle()), [])

    def test_missing_or_duplicate_criterion_ids_are_rejected(self) -> None:
        missing = copy.deepcopy(VALID_BUNDLE)
        missing["acceptance_criteria"][0].pop("id")
        self.assert_invalid(missing, "criterion id")

        duplicate = copy.deepcopy(VALID_BUNDLE)
        duplicate["acceptance_criteria"].append(
            {
                "id": "AC-1",
                "statement": "A second criterion.",
                "paths": [".codex/project/other.json"],
                "cases": ["valid"],
            }
        )
        self.assert_invalid(duplicate, "duplicate criterion id")

    def test_empty_criterion_paths_or_cases_are_rejected(self) -> None:
        for field in ("paths", "cases"):
            with self.subTest(field=field):
                bundle = copy.deepcopy(VALID_BUNDLE)
                bundle["acceptance_criteria"][0][field] = []
                self.assert_invalid(bundle, field)

    def test_compatibility_key_cannot_name_multiple_deliverables(self) -> None:
        bundle = copy.deepcopy(VALID_BUNDLE)
        bundle["primary_deliverables"] = ["first", "second"]
        self.assert_invalid(bundle, "primary_deliverables")

    def test_two_high_risk_change_kinds_are_rejected(self) -> None:
        bundle = copy.deepcopy(VALID_BUNDLE)
        bundle["change_kinds"] = ["database_schema", "public_api"]
        self.assert_invalid(bundle, "high-risk")

    def test_exactly_one_repair_round_is_required(self) -> None:
        for rounds in (0, 2, True):
            with self.subTest(rounds=rounds):
                bundle = copy.deepcopy(VALID_BUNDLE)
                bundle["max_repair_rounds"] = rounds
                self.assert_invalid(bundle, "max_repair_rounds")

    def test_every_test_policy_field_is_required_and_non_empty(self) -> None:
        for field in ("focused", "affected", "full", "full_triggers", "reuse_keys"):
            with self.subTest(field=field):
                bundle = copy.deepcopy(VALID_BUNDLE)
                bundle["test_policy"].pop(field)
                self.assert_invalid(bundle, f"test_policy.{field}")

    def test_absolute_and_parent_traversal_paths_are_rejected(self) -> None:
        for unsafe_path in ("C:/private/file.json", "/etc/passwd", "../outside.json"):
            with self.subTest(path=unsafe_path):
                bundle = copy.deepcopy(VALID_BUNDLE)
                bundle["allowed_write_paths"] = [unsafe_path]
                self.assert_invalid(bundle, "safe repository-relative path")

    def test_stale_bundle_digest_is_rejected(self) -> None:
        bundle = valid_bundle()
        bundle["primary_deliverable"] = "changed after digesting"
        self.assert_invalid(bundle, "bundle_sha256")

    def test_unhashable_reuse_key_is_reported_instead_of_crashing(self) -> None:
        bundle = copy.deepcopy(VALID_BUNDLE)
        bundle["test_policy"]["reuse_keys"] = [
            {"unexpected": "object"},
            "dependency_fingerprint",
            "test_config_fingerprint",
            "environment_fingerprint",
        ]
        self.assert_invalid(bundle, "test_policy.reuse_keys")


class ReviewValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.bundle = valid_bundle()

    def assert_invalid(self, review: dict[str, object], fragment: str) -> None:
        errors = validate_review(review, self.bundle)
        self.assertTrue(errors, "expected the review to be rejected")
        self.assertTrue(
            any(fragment in error for error in errors),
            f"expected an error containing {fragment!r}, got {errors!r}",
        )

    def test_follow_up_only_review_with_pass_verdict_is_accepted(self) -> None:
        self.assertEqual(validate_review(valid_review(self.bundle), self.bundle), [])

    def test_minor_finding_cannot_be_blocking(self) -> None:
        review = valid_review(self.bundle)
        review["findings"] = [finding(disposition="blocking")]
        review["verdict"] = "needs_changes"
        self.assert_invalid(review, "minor")

    def test_non_blocking_categories_cannot_be_blocking(self) -> None:
        for category in (
            "existing_issue",
            "adjacent_risk",
            "maintainability",
            "test_enhancement",
        ):
            with self.subTest(category=category):
                review = valid_review(self.bundle)
                review["findings"] = [
                    finding(
                        severity="important",
                        category=category,
                        disposition="blocking",
                    )
                ]
                review["verdict"] = "needs_changes"
                self.assert_invalid(review, category)

    def test_ordinary_important_blocking_requires_a_frozen_criterion(self) -> None:
        review = valid_review(self.bundle)
        review["findings"] = [
            finding(
                severity="important",
                category="criterion_failure",
                disposition="blocking",
            )
        ]
        review["verdict"] = "needs_changes"
        self.assert_invalid(review, "criterion_id")

    def test_direct_candidate_defects_can_block_without_a_criterion(self) -> None:
        for category in ("public_regression", "security", "data_loss", "protected_scope"):
            with self.subTest(category=category):
                review = valid_review(self.bundle)
                review["findings"] = [
                    finding(
                        severity="important",
                        category=category,
                        disposition="blocking",
                        introduced_by_candidate=True,
                        in_scope=True,
                    )
                ]
                review["verdict"] = "needs_changes"
                self.assertEqual(validate_review(review, self.bundle), [])

    def test_needs_changes_matches_presence_of_blocking_findings(self) -> None:
        follow_up = valid_review(self.bundle)
        follow_up["verdict"] = "needs_changes"
        self.assert_invalid(follow_up, "verdict")

        blocking = valid_review(self.bundle)
        blocking["findings"] = [
            finding(
                criterion_id="AC-1",
                severity="important",
                category="criterion_failure",
                disposition="blocking",
                introduced_by_candidate=True,
                in_scope=True,
            )
        ]
        blocking["verdict"] = "pass"
        self.assert_invalid(blocking, "verdict")

    def test_bundle_revision_or_digest_mismatch_is_rejected(self) -> None:
        review = valid_review(self.bundle)
        review["bundle_revision"] = 2
        self.assert_invalid(review, "bundle_revision")

        review = valid_review(self.bundle)
        review["bundle_sha256"] = "0" * 64
        self.assert_invalid(review, "bundle_sha256")

    def test_duplicate_finding_ids_and_unknown_criteria_are_rejected(self) -> None:
        review = valid_review(self.bundle)
        review["findings"] = [finding(), finding()]
        self.assert_invalid(review, "duplicate finding id")

        review = valid_review(self.bundle)
        review["findings"] = [finding(criterion_id="AC-404")]
        self.assert_invalid(review, "criterion_id")

    def test_remediation_rejects_new_ordinary_blocking_finding(self) -> None:
        review = valid_review(self.bundle)
        review.update(
            {
                "review_mode": "remediation",
                "remediation_finding_ids": ["F-original"],
                "findings": [
                    finding(
                        id="F-new",
                        criterion_id="AC-1",
                        severity="important",
                        category="criterion_failure",
                        disposition="blocking",
                        introduced_by_candidate=True,
                        in_scope=True,
                    )
                ],
                "verdict": "needs_changes",
            }
        )
        self.assert_invalid(review, "remediation_finding_ids")

    def test_remediation_accepts_new_candidate_critical_caused_by_diff(self) -> None:
        review = valid_review(self.bundle)
        review.update(
            {
                "review_mode": "remediation",
                "remediation_finding_ids": ["F-original"],
                "findings": [
                    finding(
                        id="F-new",
                        severity="critical",
                        category="security",
                        disposition="blocking",
                        introduced_by_candidate=True,
                        in_scope=True,
                        directly_caused_by_remediation=True,
                    )
                ],
                "verdict": "needs_changes",
            }
        )
        self.assertEqual(validate_review(review, self.bundle), [])

    def test_unhashable_review_enum_value_is_reported_instead_of_crashing(self) -> None:
        for field in ("review_mode", "verdict"):
            with self.subTest(field=field):
                review = valid_review(self.bundle)
                review[field] = []
                self.assert_invalid(review, field)

        for field in ("criterion_id", "severity", "category", "disposition"):
            with self.subTest(field=field):
                review = valid_review(self.bundle)
                review["findings"][0][field] = []
                self.assert_invalid(review, field)


class SchemaContractTests(unittest.TestCase):
    def test_bundle_schema_is_closed_and_requires_contract_fields(self) -> None:
        schema = json.loads((PROJECT_DIR / "task-bundle.schema.json").read_text("utf-8"))
        self.assertFalse(schema["additionalProperties"])
        self.assertEqual(
            set(schema["required"]),
            {
                "schema_version",
                "task_id",
                "bundle_revision",
                "target_head",
                "primary_deliverable",
                "change_kinds",
                "acceptance_criteria",
                "allowed_write_paths",
                "forbidden_paths",
                "impact_cone",
                "test_policy",
                "max_repair_rounds",
                "bundle_sha256",
            },
        )
        criterion = schema["properties"]["acceptance_criteria"]["items"]
        self.assertFalse(criterion["additionalProperties"])
        self.assertEqual(set(criterion["required"]), {"id", "statement", "paths", "cases"})
        self.assertEqual(criterion["properties"]["paths"]["minItems"], 1)
        self.assertEqual(criterion["properties"]["cases"]["minItems"], 1)
        self.assertFalse(schema["properties"]["test_policy"]["additionalProperties"])

    def test_review_schema_is_closed_and_enumerates_finding_values(self) -> None:
        schema = json.loads((PROJECT_DIR / "review-result.schema.json").read_text("utf-8"))
        self.assertFalse(schema["additionalProperties"])
        self.assertEqual(
            set(schema["required"]),
            {
                "schema_version",
                "task_id",
                "bundle_revision",
                "bundle_sha256",
                "candidate_head",
                "review_mode",
                "remediation_finding_ids",
                "findings",
                "verdict",
            },
        )
        finding_schema = schema["properties"]["findings"]["items"]
        self.assertFalse(finding_schema["additionalProperties"])
        self.assertEqual(
            set(finding_schema["required"]),
            {
                "id",
                "criterion_id",
                "introduced_by_candidate",
                "in_scope",
                "severity",
                "category",
                "disposition",
                "directly_caused_by_remediation",
                "evidence",
                "correction",
            },
        )
        self.assertEqual(
            set(finding_schema["properties"]["severity"]["enum"]),
            {"critical", "important", "minor"},
        )
        self.assertEqual(
            set(finding_schema["properties"]["disposition"]["enum"]),
            {"blocking", "follow_up", "accepted_risk"},
        )


class CliTests(unittest.TestCase):
    def run_cli(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(PROJECT_DIR / "validate_harness_bundle.py"), *args],
            capture_output=True,
            check=False,
            text=True,
        )

    def test_cli_accepts_valid_bundle_and_review(self) -> None:
        bundle = valid_bundle()
        review = valid_review(bundle)
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            bundle_path = root / "bundle.json"
            review_path = root / "review.json"
            bundle_path.write_text(json.dumps(bundle), encoding="utf-8")
            review_path.write_text(json.dumps(review), encoding="utf-8")

            bundle_result = self.run_cli("bundle", str(bundle_path))
            review_result = self.run_cli("review", str(bundle_path), str(review_path))

        self.assertEqual(bundle_result.returncode, 0, bundle_result.stderr)
        self.assertEqual(review_result.returncode, 0, review_result.stderr)

    def test_cli_returns_two_and_concise_stderr_for_invalid_input(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            malformed_path = root / "malformed.json"
            malformed_path.write_text("{", encoding="utf-8")

            malformed_result = self.run_cli("bundle", str(malformed_path))
            missing_result = self.run_cli("bundle", str(root / "missing.json"))

        self.assertEqual(malformed_result.returncode, 2)
        self.assertTrue(malformed_result.stderr.strip())
        self.assertNotIn("Traceback", malformed_result.stderr)
        self.assertEqual(missing_result.returncode, 2)
        self.assertTrue(missing_result.stderr.strip())
        self.assertNotIn("Traceback", missing_result.stderr)


if __name__ == "__main__":
    unittest.main()
