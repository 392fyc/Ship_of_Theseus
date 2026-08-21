from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
from typing import Any


HIGH_RISK_CHANGE_KINDS = {
    "database_schema",
    "data_migration",
    "public_api",
    "deployment",
    "cross_repository_write",
}
NON_BLOCKING_CATEGORIES = {
    "existing_issue",
    "adjacent_risk",
    "maintainability",
    "test_enhancement",
}
DIRECT_BLOCKING_CATEGORIES = {
    "public_regression",
    "security",
    "data_loss",
    "protected_scope",
}

REQUIRED_REUSE_KEYS = {
    "candidate_head",
    "dependency_fingerprint",
    "test_config_fingerprint",
    "environment_fingerprint",
}
SEVERITIES = {"critical", "important", "minor"}
CATEGORIES = {
    "criterion_failure",
    "public_regression",
    "security",
    "data_loss",
    "protected_scope",
    "existing_issue",
    "adjacent_risk",
    "maintainability",
    "test_enhancement",
    "evidence_invalidated",
}
DISPOSITIONS = {"blocking", "follow_up", "accepted_risk"}
REVIEW_MODES = {"initial", "remediation"}
VERDICTS = {"pass", "needs_changes", "blocked"}

BUNDLE_FIELDS = {
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
}
CRITERION_FIELDS = {"id", "statement", "paths", "cases"}
TEST_POLICY_FIELDS = {"focused", "affected", "full", "full_triggers", "reuse_keys"}
REVIEW_FIELDS = {
    "schema_version",
    "task_id",
    "bundle_revision",
    "bundle_sha256",
    "candidate_head",
    "review_mode",
    "remediation_finding_ids",
    "checks_performed",
    "findings",
    "residual_risks",
    "verdict",
}
FINDING_FIELDS = {
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
}
SHA1_PATTERN = re.compile(r"^[0-9a-fA-F]{40}$")
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
WINDOWS_DRIVE_PREFIX_PATTERN = re.compile(r"^[A-Za-z]:")


def bundle_digest(bundle: dict[str, object]) -> str:
    """Return the canonical SHA256 for a bundle without its digest field."""
    canonical_bundle = dict(bundle)
    canonical_bundle.pop("bundle_sha256", None)
    payload = json.dumps(
        canonical_bundle,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _is_non_empty_string(value: object) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _is_strict_integer(value: object) -> bool:
    return type(value) is int


def _safe_repository_path(value: object) -> bool:
    if not _is_non_empty_string(value):
        return False
    path = value.replace("\\", "/")
    if path.startswith("/") or WINDOWS_DRIVE_PREFIX_PATTERN.match(value):
        return False
    return ".." not in path.split("/") and "\x00" not in path


def _validate_string_list(
    value: object,
    field: str,
    errors: list[str],
    *,
    paths: bool = False,
) -> None:
    if not isinstance(value, list) or not value:
        errors.append(f"{field} must be a non-empty list")
        return
    if any(not _is_non_empty_string(item) for item in value):
        errors.append(f"{field} must contain non-empty strings")
    if len(value) != len(set(item for item in value if isinstance(item, str))):
        errors.append(f"{field} must not contain duplicates")
    if paths and any(not _safe_repository_path(item) for item in value):
        errors.append(f"{field} must contain only safe repository-relative paths")


def _unexpected_fields(value: dict[str, object], allowed: set[str], owner: str) -> list[str]:
    return [f"{owner} has unexpected field {field}" for field in sorted(set(value) - allowed)]


def validate_bundle(bundle: dict[str, object]) -> list[str]:
    """Return contract errors for a ReviewBundle, or an empty list when valid."""
    if not isinstance(bundle, dict):
        return ["bundle must be a JSON object"]

    errors: list[str] = []
    errors.extend(_unexpected_fields(bundle, BUNDLE_FIELDS, "bundle"))

    compatibility_deliverables = bundle.get("primary_deliverables")
    if isinstance(compatibility_deliverables, list) and len(compatibility_deliverables) > 1:
        errors.append("primary_deliverables cannot contain multiple deliverables")

    for field in sorted(BUNDLE_FIELDS - set(bundle)):
        errors.append(f"bundle is missing required field {field}")

    if bundle.get("schema_version") != 1 or not _is_strict_integer(bundle.get("schema_version")):
        errors.append("schema_version must be integer 1")
    if not _is_non_empty_string(bundle.get("task_id")):
        errors.append("task_id must be a non-empty string")
    revision = bundle.get("bundle_revision")
    if not _is_strict_integer(revision) or revision < 1:
        errors.append("bundle_revision must be a positive integer")
    target_head = bundle.get("target_head")
    if not isinstance(target_head, str) or not SHA1_PATTERN.fullmatch(target_head):
        errors.append("target_head must be a 40-character hexadecimal commit")
    if not _is_non_empty_string(bundle.get("primary_deliverable")):
        errors.append("primary_deliverable must name one bounded deliverable")

    change_kinds = bundle.get("change_kinds")
    _validate_string_list(change_kinds, "change_kinds", errors)
    if isinstance(change_kinds, list):
        high_risk = {
            item for item in change_kinds if isinstance(item, str) and item in HIGH_RISK_CHANGE_KINDS
        }
        if len(high_risk) > 1:
            errors.append("change_kinds contains more than one high-risk change kind")

    criteria = bundle.get("acceptance_criteria")
    criterion_ids: set[str] = set()
    if not isinstance(criteria, list) or not criteria:
        errors.append("acceptance_criteria must be a non-empty list")
    else:
        for index, criterion in enumerate(criteria):
            owner = f"acceptance_criteria[{index}]"
            if not isinstance(criterion, dict):
                errors.append(f"{owner} must be an object")
                continue
            errors.extend(_unexpected_fields(criterion, CRITERION_FIELDS, owner))
            for field in sorted(CRITERION_FIELDS - set(criterion)):
                errors.append(f"{owner} is missing required field {field}")
            criterion_id = criterion.get("id")
            if not _is_non_empty_string(criterion_id):
                errors.append(f"{owner} criterion id must be a non-empty string")
            elif criterion_id in criterion_ids:
                errors.append(f"duplicate criterion id {criterion_id}")
            else:
                criterion_ids.add(criterion_id)
            if not _is_non_empty_string(criterion.get("statement")):
                errors.append(f"{owner}.statement must be a non-empty string")
            _validate_string_list(criterion.get("paths"), f"{owner}.paths", errors, paths=True)
            _validate_string_list(criterion.get("cases"), f"{owner}.cases", errors)

    for field in ("allowed_write_paths", "forbidden_paths", "impact_cone"):
        _validate_string_list(bundle.get(field), field, errors, paths=True)

    policy = bundle.get("test_policy")
    if not isinstance(policy, dict):
        errors.append("test_policy must be an object")
    else:
        errors.extend(_unexpected_fields(policy, TEST_POLICY_FIELDS, "test_policy"))
        for field in sorted(TEST_POLICY_FIELDS - set(policy)):
            errors.append(f"test_policy.{field} is required")
        _validate_string_list(policy.get("focused"), "test_policy.focused", errors)
        _validate_string_list(policy.get("affected"), "test_policy.affected", errors)
        if not _is_non_empty_string(policy.get("full")):
            errors.append("test_policy.full must be a non-empty command")
        _validate_string_list(policy.get("full_triggers"), "test_policy.full_triggers", errors)
        reuse_keys = policy.get("reuse_keys")
        _validate_string_list(reuse_keys, "test_policy.reuse_keys", errors)
        if isinstance(reuse_keys, list) and (
            len(reuse_keys) != len(REQUIRED_REUSE_KEYS)
            or any(not isinstance(item, str) for item in reuse_keys)
            or {item for item in reuse_keys if isinstance(item, str)} != REQUIRED_REUSE_KEYS
        ):
            errors.append("test_policy.reuse_keys must contain the four required reuse keys")

    repair_rounds = bundle.get("max_repair_rounds")
    if not _is_strict_integer(repair_rounds) or repair_rounds != 1:
        errors.append("max_repair_rounds must equal integer 1")

    supplied_digest = bundle.get("bundle_sha256")
    if "bundle_sha256" in bundle:
        if not isinstance(supplied_digest, str) or not SHA256_PATTERN.fullmatch(supplied_digest):
            errors.append("bundle_sha256 must be a lowercase 64-character SHA256")
        else:
            try:
                expected_digest = bundle_digest(bundle)
            except (TypeError, ValueError):
                errors.append("bundle cannot be encoded as canonical JSON")
            else:
                if supplied_digest != expected_digest:
                    errors.append("bundle_sha256 does not match the bundle digest")

    return errors


def validate_review(review: dict[str, object], bundle: dict[str, object]) -> list[str]:
    """Return binding and finding errors for a ReviewResult."""
    bundle_errors = validate_bundle(bundle)
    if bundle_errors:
        return [f"bundle: {error}" for error in bundle_errors]
    if not isinstance(review, dict):
        return ["review must be a JSON object"]

    errors: list[str] = []
    errors.extend(_unexpected_fields(review, REVIEW_FIELDS, "review"))
    for field in sorted(REVIEW_FIELDS - set(review)):
        errors.append(f"review is missing required field {field}")

    if review.get("schema_version") != 1 or not _is_strict_integer(review.get("schema_version")):
        errors.append("review schema_version must be integer 1")
    if review.get("task_id") != bundle.get("task_id"):
        errors.append("review task_id does not match the bundle")
    review_revision = review.get("bundle_revision")
    if not _is_strict_integer(review_revision) or review_revision != bundle.get("bundle_revision"):
        errors.append("review bundle_revision does not match the bundle")
    expected_digest = bundle["bundle_sha256"]
    if review.get("bundle_sha256") != expected_digest:
        errors.append("review bundle_sha256 does not match the bundle")
    candidate_head = review.get("candidate_head")
    if not isinstance(candidate_head, str) or not SHA1_PATTERN.fullmatch(candidate_head):
        errors.append("candidate_head must be a 40-character hexadecimal commit")

    review_mode = review.get("review_mode")
    if not isinstance(review_mode, str) or review_mode not in REVIEW_MODES:
        errors.append("review_mode must be initial or remediation")
    remediation_ids = review.get("remediation_finding_ids")
    if not isinstance(remediation_ids, list):
        errors.append("remediation_finding_ids must be a list")
        remediation_id_set: set[str] = set()
    else:
        remediation_id_set = {
            item for item in remediation_ids if isinstance(item, str) and item.strip()
        }
        if len(remediation_id_set) != len(remediation_ids):
            errors.append("remediation_finding_ids must contain unique non-empty strings")
        if review_mode == "initial" and remediation_ids:
            errors.append("initial review remediation_finding_ids must be empty")

    _validate_string_list(review.get("checks_performed"), "checks_performed", errors)
    residual_risks = review.get("residual_risks")
    if not isinstance(residual_risks, list):
        errors.append("residual_risks must be a list")
    else:
        if any(not _is_non_empty_string(item) for item in residual_risks):
            errors.append("residual_risks must contain non-empty strings")
        if len(residual_risks) != len(
            set(item for item in residual_risks if isinstance(item, str))
        ):
            errors.append("residual_risks must not contain duplicates")

    criteria = bundle.get("acceptance_criteria", [])
    criterion_ids = {
        criterion["id"]
        for criterion in criteria
        if isinstance(criterion, dict) and isinstance(criterion.get("id"), str)
    }
    findings = review.get("findings")
    finding_ids: set[str] = set()
    blocking_findings = 0
    if not isinstance(findings, list):
        errors.append("findings must be a list")
        findings = []

    for index, item in enumerate(findings):
        owner = f"findings[{index}]"
        if not isinstance(item, dict):
            errors.append(f"{owner} must be an object")
            continue
        errors.extend(_unexpected_fields(item, FINDING_FIELDS, owner))
        for field in sorted(FINDING_FIELDS - set(item)):
            errors.append(f"{owner} is missing required field {field}")

        finding_id = item.get("id")
        if not _is_non_empty_string(finding_id):
            errors.append(f"{owner} finding id must be a non-empty string")
        elif finding_id in finding_ids:
            errors.append(f"duplicate finding id {finding_id}")
        else:
            finding_ids.add(finding_id)

        criterion_id = item.get("criterion_id")
        if criterion_id is not None and (
            not isinstance(criterion_id, str) or criterion_id not in criterion_ids
        ):
            errors.append(f"{owner}.criterion_id does not reference a frozen criterion")
        for field in ("introduced_by_candidate", "in_scope", "directly_caused_by_remediation"):
            if type(item.get(field)) is not bool:
                errors.append(f"{owner}.{field} must be a boolean")

        severity = item.get("severity")
        category = item.get("category")
        disposition = item.get("disposition")
        if not isinstance(severity, str) or severity not in SEVERITIES:
            errors.append(f"{owner}.severity is invalid")
        if not isinstance(category, str) or category not in CATEGORIES:
            errors.append(f"{owner}.category is invalid")
        if not isinstance(disposition, str) or disposition not in DISPOSITIONS:
            errors.append(f"{owner}.disposition is invalid")
        for field in ("evidence", "correction"):
            if not _is_non_empty_string(item.get(field)):
                errors.append(f"{owner}.{field} must be a non-empty string")

        if disposition != "blocking":
            continue
        blocking_findings += 1
        if severity == "minor":
            errors.append(f"{owner}: minor findings cannot be blocking")
        if isinstance(category, str) and category in NON_BLOCKING_CATEGORIES:
            errors.append(f"{owner}: {category} findings cannot be blocking")

        direct_candidate_defect = (
            isinstance(category, str)
            and category in DIRECT_BLOCKING_CATEGORIES
            and item.get("introduced_by_candidate") is True
        )
        frozen_criterion_failure = (
            isinstance(criterion_id, str) and criterion_id in criterion_ids
        )
        if not frozen_criterion_failure and not direct_candidate_defect:
            errors.append(
                f"{owner}.criterion_id is required unless a direct candidate defect permits blocking"
            )

        finding_is_in_remediation = (
            isinstance(finding_id, str) and finding_id in remediation_id_set
        )
        if review_mode == "remediation" and not finding_is_in_remediation:
            remediation_exception = (
                severity == "critical"
                and item.get("introduced_by_candidate") is True
                and (
                    item.get("in_scope") is True
                    or category == "protected_scope"
                )
                and item.get("directly_caused_by_remediation") is True
            )
            if not remediation_exception:
                errors.append(
                    f"{owner}.id is not in remediation_finding_ids and is not a remediation-caused critical"
                )

    verdict = review.get("verdict")
    if not isinstance(verdict, str) or verdict not in VERDICTS:
        errors.append("verdict is invalid")
    expected_verdict = "needs_changes" if blocking_findings else "pass"
    if isinstance(verdict, str) and verdict in VERDICTS and verdict != expected_verdict:
        errors.append(f"verdict must be {expected_verdict} for the reported findings")

    return errors


def _load_json(path_text: str) -> dict[str, object]:
    path = Path(path_text)
    try:
        value: Any = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ValueError(f"{path}: {error}") from error
    if not isinstance(value, dict):
        raise ValueError(f"{path}: top-level JSON value must be an object")
    return value


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Validate Mercury harness records")
    subparsers = parser.add_subparsers(dest="command", required=True)
    bundle_parser = subparsers.add_parser("bundle", help="validate a ReviewBundle")
    bundle_parser.add_argument("path")
    review_parser = subparsers.add_parser("review", help="validate a bound ReviewResult")
    review_parser.add_argument("bundle_path")
    review_parser.add_argument("review_path")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    try:
        if args.command == "bundle":
            errors = validate_bundle(_load_json(args.path))
        else:
            bundle = _load_json(args.bundle_path)
            review = _load_json(args.review_path)
            errors = validate_review(review, bundle)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 2

    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
