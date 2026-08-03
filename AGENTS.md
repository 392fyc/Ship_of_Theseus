# AGENTS.md

> 面向 Codex CLI 及其他**外部** Sub Agent。
> **⚠ 工作模式（2026-06-16 起）**：默认在 Claude Code 内部用 subagent / agent team 执行（**含 GDScript 代码**）；**本文件仅在用户特殊声明派发外部工具时适用**。Task Bundle / `implementation_receipt` 模板已弃用（见文末）。

## Language

设计文档为中文（简体）。讨论设计、游戏机制、文档时用中文，除非用户切换为英文。

## Project

战棋RPG + Roguelite + 城镇建设, Godot 4.6 (GDScript), JSON驱动, GameAction指令架构。
KB 正本: Obsidian Vault `D:\ShipOfTheseus\ShipOfTheseus-KB\` (`obsidian_*` MCP)

## DO NOT — Security

- **禁止**在版本控制文件中硬编码 API Key / Secret。配置文件含密钥时必须加入 `.gitignore`（ref: ISSUE-SEC-001）

## DO NOT — GDScript

- class_name 与 autoload 同名 → autoload 脚本**移除 class_name**
- Variant 类型推断 → **显式声明变量类型**
- **禁止**在代码中硬编码数值，必须从JSON读取
- 信号命名: past_tense (`signal damage_dealt`)
- GameAction模式：所有操作封装为可序列化Action

## 游戏机制 — 查真源，不在本文件复述

规则正本 = 设计库规则表 `/api/rules`，共 23 条（R1.1–R1.10 / R2.1–R2.4 / R3.1–R3.4 / R4.1–R4.4 / R5.9）。
离线全量索引 = KB `01-Game-Design/rules-catalog.md`；逐字原文 = 设计库仓库 `snapshots/rules.json`。
改战斗 / 技能 / 伤害逻辑前必须回查真源，**禁止**凭本文件或凭记忆复述规则。

- 伤害怎么算、hybrid 怎么合、纯粹伤害是什么 → **R1.1**
- 命中 / 暴击怎么算，哪些属性参与 → **R1.2 / R1.3**
- 修正落在哪一层，取整与 clamp 的位置 → **R1.8**
- 一次效果对同一单位结算几次，会不会自己触发自己 → **R1.9 / R1.10**
- 技能消耗什么行动资源、什么时机能放 → **R3.2 / R3.3**
- 速度到底影响什么（有没有速度带来的追击） → **R3.1**
- 建筑受伤走不走伤害公式、摧毁后那格变成什么 → 规则表无此域，查 KB `01-Game-Design/Core-Systems/grid-and-map.md` §建筑耐久系统
- 受击方会不会自动反击 → 规则表无此域，查 KB `01-Game-Design/Core-Systems/battle-calculation.md` §反击系统

规则层没有列出的因素（例如距离）不要自行补进公式；要让它参与结算，必须由技能 / 天赋 / 遗物条目显式声明，并按 R1.8 落到指定的层。

## DO NOT — AI

- **禁止**用训练数据判断版本号。版本查询必须先搜索再作答

## Sub Agent Rules（仅外部工具，用户特殊声明派发时适用）

- Git 分支: `{agent}/{task-name}`，完成后通知 Main Agent；**不操作 `develop` / `main`**
- Sub Agent 只在指定写入范围内实现，不改 KB / registry

## Task Receipt（已弃用）

- **Task Bundle / `implementation_receipt` 模板已于 2026-06 弃用**——新工作模式默认在 Claude Code 内部用 subagent / team 执行，不再回填 receipt。`.claude/skills/sot-task-receipt/` 仅作历史参考保留。
