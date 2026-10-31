---
status: active
authority: delivery-policy
related_issue: https://github.com/392fyc/Ship_of_Theseus/issues/126
updated: 2026-10-31
---

# CI 与合并依据

## 现行做法

PR 的合并依据是 GitHub Actions 在该 PR 当前 HEAD 上的运行结果，不再用本地运行代替。用户 2026-10-31 将仓库暂时改为公开，并要求不再使用本地 CI（原话见 [Ship #126 的评论](https://github.com/392fyc/Ship_of_Theseus/issues/126#issuecomment-6542783606)）。

- `CI`（`.github/workflows/ci.yml`）在指向 `develop`、`main` 的 PR 和推送上运行：Godot 回归（`tools/ci/run_godot_tests.sh`，需要图形渲染的测试按 `godot_render_only_tests.txt` 跳过）与契约测试（`pytest tests/codex tests/claude_review/test_capture_config.py`）。
- `Mercury verify`（`.github/workflows/mercury-verify.yml`）由 Mercury 装载，核对 Mercury 受管文件；不手改受管文件。
- 合并前三项都满足：独立审查覆盖当前 HEAD；上面两个工作流在当前 HEAD 上通过；未解决的审查线程为 0。合并时用 `--match-head-commit` 锁定 HEAD。
- CI 失败时修代码或测试，不重跑到碰巧通过，也不把本地通过当成远端通过。需要图形渲染的测试在 CI 中显示为跳过；结构测试不代替画面审阅或用户视觉批准。

仓库改回私有、或 GitHub Actions 额度再次不足时，合并依据由用户重新裁决；在此之前不自行改回本地 CI。

## 本地运行

本地运行 Godot 回归或契约测试只用于开发时自查和定位失败，不作为合并依据。在 Windows 上运行的结果是 Windows 证据，不能写成 Linux runner 的结论。

## 工作流状态

`CI` 与 `Mercury verify` 曾因 2026-10 的 GitHub 额度问题被手动停用，已于 2026-10-31 重新启用（`gh workflow list --all` 回读为 `active`）。停用或恢复工作流只能按用户的明确指令进行，并回读状态；不修改账号账单、支出上限或分支保护。
