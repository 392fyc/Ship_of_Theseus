# CLAUDE.md

## Language

设计文档为中文（简体）。讨论设计、游戏机制、文档时用中文，除非用户切换为英文。

## Project

战棋RPG + Roguelite + 城镇建设, Godot 4.6 (GDScript), JSON驱动, GameAction指令架构。

## KB

正本: Obsidian Vault `D:\ShipOfTheseus\ShipOfTheseus-KB\` (`obsidian_*` MCP)
- `/sot-session-start` → 开始会话 | `/sot-session-end` → 结束会话 | `/sot-kb-write` → KB写入
- 游戏规则、公式、ADR、任务追踪 → 查 KB，不在此文件复述

## DO NOT — GDScript

- class_name 与 autoload 同名 → autoload 脚本**移除 class_name**
- Variant 类型推断 → **显式声明变量类型**
- **禁止**在代码中硬编码数值，必须从JSON读取

## DO NOT — KB

- **禁止** PowerShell 写入 KB 文件（UTF-8 BOM 问题）
- **禁止** 对 current-session.md 使用 append（维度爆炸），始终全文替换
- KB 标题中**禁止**括号 `()`、方括号 `[]`、中文字符（导致 obsidian_patch_content 失败）

## DO NOT — AI

- **禁止**用训练数据判断版本号。版本查询必须先 WebSearch，交叉验证 2+ 来源

## DO NOT — 游戏机制

- 格挡和暴击 → **互斥**
- pure伤害格挡 → **无视**；pure暴击 → **固定1.5x，不受加成**
- hybrid → **phys_atk + mag_atk 同时生效**，武器倍率取平均
- 反击/追击 → **不触发**连锁；area攻击 → **不触发**反击
- 建筑耐久 → **固定扣减**；建筑摧毁 → **变废墟**
- 距离 → **无衰减**
- ZOC → **不叠加**固定-2，仅从控制区离开时触发

## Agent Constraints

- **Main Agent = Claude Code**：设计 / KB / 调度。**禁止**自行创建 Sub Agent（禁止 Task tool 派内部 agent）
- "递交 Sub Agent" = 外部工具（GitHub Copilot CLI / Codex CLI / AntiGravity），输出规格交用户转递
- Godot MCP → **GitHub Copilot CLI / Codex CLI / AntiGravity 连接**，Claude Code 不主动使用
- 大文件阅读 / 代码库研究 → 委托 Codex CLI 或 AntiGravity，**禁止** Claude 消耗 token
- Git 分支: `{agent}/{task-name}`，无 PR 个人作业，Sub Agent 隔离分支
- UI 视觉 → Playground 模式（独立文件，人工审阅后应用）
