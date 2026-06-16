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

## DO NOT — 游戏机制

- 格挡和暴击 → **互斥**
- pure伤害格挡 → **无视**；pure暴击 → **固定1.5x，不受加成**
- hybrid → **phys_atk + mag_atk 同时生效**，武器倍率取平均
- 反击 → **不触发**连锁（**追击系统已移除**，R1.4 / 速度方案2）；area攻击 → **不触发**反击
- 建筑耐久 → **固定扣减**；建筑摧毁 → **变废墟**
- 距离 → **无衰减**
- ZOC → **不叠加**固定-2，仅从控制区离开时触发

## DO NOT — AI

- **禁止**用训练数据判断版本号。版本查询必须先搜索再作答

## Sub Agent Rules（仅外部工具，用户特殊声明派发时适用）

- Git 分支: `{agent}/{task-name}`，完成后通知 Main Agent；**不操作 `develop` / `main`**
- Sub Agent 只在指定写入范围内实现，不改 KB / registry

## Task Receipt（已弃用）

- **Task Bundle / `implementation_receipt` 模板已于 2026-06 弃用**——新工作模式默认在 Claude Code 内部用 subagent / team 执行，不再回填 receipt。`.claude/skills/sot-task-receipt/` 仅作历史参考保留。
