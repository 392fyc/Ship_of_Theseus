---
issue_id: "ISSUE-SEC-001"
title: "opencode.json OBSIDIAN_API_KEY leaked to git history"
priority: "Sev-0"
status: "resolved"
resolved: "2026-03-16"
created: "2026-03-16"
reporter: "human"
assignee: "human"
related_commit: "52d9295"
fix_commit: "d4b1ae5"
tags: [security, credential-leak]
---

# ISSUE-SEC-001 — opencode.json API Key Leak

## Summary

Commit `52d9295` (2026-03-14) added `opencode.json` containing a hardcoded `OBSIDIAN_API_KEY` in plaintext. The commit was pushed to `origin/develop`, exposing the key in remote git history.

## Impact

| Item | Detail |
|------|--------|
| Leaked secret | `OBSIDIAN_API_KEY` (Obsidian Local REST API) |
| Scope | Local REST API on `localhost:27123` — low remote risk, but key is in public/shared git history |
| Exposure window | 2026-03-14 ~ 2026-03-16 (2 days) |
| Affected branch | `origin/develop` |

## Root Cause

- `opencode.json` was not included in `.gitignore` (only `.mcp.json` was listed)
- API key was hardcoded directly in config instead of using environment variable reference

## Remediation Steps

| Step | Status | Detail |
|------|--------|--------|
| 1. Remove from git tracking | ✅ done | `git rm --cached opencode.json` (commit `d4b1ae5`) |
| 2. Add to `.gitignore` | ✅ done | `.gitignore` updated (commit `d4b1ae5`) |
| 3. Replace with env var | ✅ done | `"${OBSIDIAN_API_KEY}"` placeholder in local file |
| 4. Rotate API key | ✅ done | New key generated and applied (2026-03-16) |
| 5. Update all agents | ✅ done | `.mcp.json` + `opencode.json` updated with new key |
| 6. Purge git history | ✅ done | `git filter-repo --replace-text` → old key replaced with `***REMOVED***`, force pushed to origin |
| 7. Verify no other secrets | ✅ done | `.mcp.json` never committed; no other secrets found |
| 8. Cleanup branches | ✅ done | 3 merged codex branches deleted (local + remote) |

## Prevention

- `.gitignore` rule added for `opencode.json`
- All agent config files containing secrets must use `${ENV_VAR}` references, never hardcoded values
- Future: add pre-commit hook to detect high-entropy strings in staged files

## Notes

- Risk is partially mitigated by the fact that Obsidian Local REST API binds to `localhost` only — remote exploitation requires local network access
- Key rotation is still mandatory as the key is in remote git history
