# CLAUDE.md

## Language

设计文档为中文（简体）。讨论设计、游戏机制、文档时用中文，除非用户切换为英文。

## Project

战棋RPG + Roguelite + 城镇建设, Godot 4.6 (GDScript), JSON驱动, GameAction指令架构。

## KB

正本: Obsidian Vault `D:\ShipOfTheseus\ShipOfTheseus-KB\` (`obsidian_*` MCP)
- `/sot-session-start` → 开始会话 | `/sot-session-end` → 结束会话 | `/sot-kb-write` → KB写入
- 游戏规则、公式、ADR、任务追踪 → 查 KB 与设计库规则表（见下「游戏机制」一节），不在此文件复述

## DO NOT — Security

- **禁止**在版本控制文件中硬编码 API Key / Secret。配置文件含密钥时必须加入 `.gitignore`，值使用环境变量引用（ref: ISSUE-SEC-001）

## DO NOT — GDScript

- class_name 与 autoload 同名 → autoload 脚本**移除 class_name**
- **内部类（`class Foo extends X:`）与某个全局 `class_name Foo` 同名** → `Parse Error: Class "Foo" hides a global script class`，**整个文件 parse 失败**。与上一条是两回事（那条是 autoload，这条是普通全局类）。抽出全局类时**记得删掉原文件里的同名内部类**——`skillbar_playground.gd` 就是抽出 `DamageForecaster` 时漏删，坏了两个月（2026-08-12 修，内部类改名 `_ForecastPanel`）
- Variant 类型推断 → **显式声明变量类型**
- **禁止**在代码中硬编码数值，必须从JSON读取

### 测试里不要这样判「脚本 parse 成功没有」

- **`load(脚本路径) != null` 不是 parse 判据**（2026-08-12 实测）：脚本 parse 失败时 `load()` **仍可能返回非 null**，且行为随调用时机与资源缓存状态而变（在 `_initialize` 里探测与在 `_process` 里探测结果不一样）。拿它当护栏会得到一条永远绿的假断言。
- **`packed.instantiate() != null` 更不行**：场景在附着脚本 parse 失败时照样实例化得出来——脚本变成 null、节点还在。`test_skillbar_playground_load.gd` 旧版就是只查这两条，于是上面那个 parse 错误坏了两个月而回归全绿。
- **可靠的是**：实例化后断言 `node.get_script() != null`（脚本真挂上了），再断言 `get_script().resource_path` 就是期望的那个（挂的是对的那一个）。
- 要一条真正等价于 `--check-only` 的，得在**回归脚本层面**对关键脚本各跑一次 `--check-only` 并断言退出码——那是测试基础设施改动，**尚未做**。

### 「升级」在本项目是两个意思，查证时别混

中文「升级」同时指两件**毫不相干**的事，扫全库时最容易在这里得出反的结论：

| 说的是 | 引擎里有没有 | 怎么查 |
|---|---|---|
| **角色升级**（Lv1→Lv5 成长、升级得天赋点） | **有** | `data/classes/myrmidon.json` 的转职成长说明、`data/relics/relic_mentor_tome.json`、`data/runloop/act1_config.json` |
| **技能升级链**（回忆天赋永久把某技能换成升级版；设计库 `Talent.upgrade_skill_id` ↔ `Skill.upgrade_of`，12 张在用） | **没有，零承载** | `grep -rni upgrade scripts/` → 零命中；`data/talents/` `data/skills/` 均无该字段 |

**查后者请用 `upgrade` 而不是「升级」**：用 `upgrade` 查是干净的（零命中）；用「升级」扫 `data/` 会撞上表第一行那三个文件的假阳性，看到 3 处命中很容易误判成「引擎已经有升级概念」。

引擎现有的 `slot_swap_trigger` / `slot_swap_target` / `slot_swap_provider` 是**局内动态替换**（印记满 3 → 招架换拔刀），**不是**技能升级链，两者别互相套用。

（2026-08-12 实测登记。这一栏是否要补承载字段尚未裁决，届时按 lane §2.2 先入字段归属表再写代码。）

## DO NOT — KB

- **禁止** PowerShell 写入 KB 文件（UTF-8 BOM 问题）
- **禁止** 对 current-session.md 使用 append（维度爆炸），始终全文替换
- KB 标题中**禁止**括号 `()`、方括号 `[]`、中文字符（导致 obsidian_patch_content 失败）

## DO NOT — AI

- **禁止**用训练数据判断版本号。版本查询必须先 WebSearch，交叉验证 2+ 来源

## 游戏机制 — 只给指针，不复述

规则正本 = **设计库规则表**（`/api/rules`，共 23 条：R1.1–R1.10 / R2.1–R2.4 / R3.1–R3.4 / R4.1–R4.4 / R5.9）。
离线可读的全量索引 = KB `01-Game-Design/rules-catalog.md`（每条一句话 + 展开文档链接）；逐字原文 = 设计库仓库 `snapshots/rules.json`。
按上文「KB」一节的约定，本文件**不复述规则内容**——写战斗 / 技能 / 伤害逻辑前回查真源，不要凭本文件或凭记忆作答。

最常问错的几处，直接给落点：

| 要确认什么 | 查这里 |
|---|---|
| 伤害怎么算、hybrid 怎么合、纯粹伤害是什么 | R1.1；展开见 KB `01-Game-Design/Core-Systems/battle-calculation.md` |
| 命中 / 暴击怎么算，哪些属性参与 | R1.2 / R1.3 |
| 某个修正该落在哪一层，什么时候取整、什么时候 clamp | R1.8 |
| 一次效果对同一单位结算几次，会不会自己触发自己 | R1.9 / R1.10 |
| 技能消耗什么行动资源、什么时机能放 | R3.2 / R3.3 |
| 速度到底影响什么（有没有速度带来的追击） | R3.1 |
| 建筑受伤走不走伤害公式，摧毁后那格变成什么 | 规则表无此域 → KB `01-Game-Design/Core-Systems/grid-and-map.md` §建筑耐久系统 |
| 受击方会不会自动反击 | 规则表无此域 → KB `01-Game-Design/Core-Systems/battle-calculation.md` §反击系统 |

R1.1 / R1.2 / R1.3 各自列全了本链的层与乘区。规则层没有列出的因素（例如距离）**不要自行补进公式**；要让某个因素参与结算，必须由技能 / 天赋 / 遗物条目显式声明，并按 R1.8 落到指定的层。

## Agent Constraints

> **工作模式（2026-06-16 用户定，覆盖旧约束）**：默认在 **Claude Code 内部**用 subagent / agent team 执行（**含 GDScript 代码**）；一般任务也派 subagent 防主窗口污染；**弃用 Task Bundle / implementation_receipt 模板**。

- **Main Agent = Claude Code**：设计 / KB / 调度 + **调度内部 subagent / team 执行**（含代码实现、代码库研究、大文件阅读）
- **外部工具（opencode / Codex CLI / AntiGravity）仅用户特殊声明时使用**——非默认路径
- Godot 编辑器交互 / Godot MCP → 仍由 opencode / Codex CLI / AntiGravity 连接（单客户端限制），Claude Code 不主动驱动编辑器
- Git 分支: `{agent}/{task-name}`，无 PR 个人作业，subagent 用隔离分支
- UI 视觉 → Playground 模式（独立文件，人工审阅后应用）
- GitHub Copilot CLI → **已废弃**，由 opencode 取代
