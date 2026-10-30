---
status: active
authority: delivery-policy
related_issue: https://github.com/392fyc/Ship_of_Theseus/issues/109
updated: 2026-10-30
---

# CI 与本地验证

## 2026 年 10 月的临时安排

用户于 2026-10-30 明确要求：“当前 Github 超限了，本月暂时只本地跑 CI，通过即可合并。下个月重开 github actions CI。”本节适用至 2026-10-31，2026-11-01 起恢复远端 CI。该安排不增加任务范围或合并授权；未被授权的任务仍按项目规则处理。

本月暂停 `CI` 和 `Mercury verify` 两个自动验证工作流，避免每次推送反复触发额度不足的运行；不修改工作流源码、账号账单、支出上限或分支保护。恢复时只重新启用这两个工作流，并回读其状态；用户后续明确暂停的指令优先。

## 本地等价检查

在任务工作树中按当前 `.github/workflows/ci.yml` 的检查内容执行：

- 使用相同版本 Godot，运行 `tools/ci/run_godot_tests.sh`，沿用资源导入、单测试超时及 `godot_render_only_tests.txt` 的排除范围。
- 使用 Python 3.12 运行 `python -B -m pytest -q tests/codex tests/claude_review/test_capture_config.py`。
- Mercury 安装变化从已发布的来源提交运行 `tools/mercury.py check`，核对锁文件及受管内容；不手改受管文件。自动更新分支另按 `tools/mercury_update.py verify` 检查，普通任务分支不能把其“不适用”输出算成实际安装验证。

记录执行环境、源码提交或候选差异、命令、退出码、通过/失败/跳过项和私有日志位置。Windows 本地运行是 Windows 证据，不声称已经执行 Linux GitHub runner。图形渲染测试未执行时仍标为跳过；结构测试不代替画面或用户视觉批准。

上述本地检查全部通过、独立审查绑定当前候选，并满足现有权限和合并规则后，可以按用户授权合并。本地通过不改写先前 GitHub 失败检查的事实，也不向 GitHub伪造成功状态。

提交使用已发布 Mercury `git-safe` pack 安装的受控入口；发布仍沿用项目的 `scripts/codex/sot-publish.ps1`。临时 CI 安排不放宽分支权限、暂存范围或独立审查要求。

## 恢复远端 CI

恢复目标为 2026-11-01。通过 GitHub 支持的工作流启用入口恢复 `CI`、`Mercury verify`，并回读 `active` 状态；后续提交按原有触发器运行。不自动提高额度、不改账单，也不为证明启用成功而重复发起旧提交的付费任务。若权限或账号状态仍不允许执行，如实报告。
