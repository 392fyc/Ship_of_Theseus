# Swordsman Engine — Runtime Verification (2026-06-21)

> 剑圣底座（剑气 / 印记 / 心眼 资源引擎 + 5 基础技能）的运行时验证记录。
> 代码已实装并通过 Godot headless 回归（112 断言全过）。本文为该次验证的单一事实源，
> 用于补充 / 纠正 [[battle-calculation]] 与 [[class-system]] 中标注「待同步」的相关条目。
> 设计裁决「招架 ≠ 格挡」（不复活 ADR-005 已移除的格挡子系统）仍然有效。

## Scope and Result

- **验证方式 = Godot 4.6.1 headless `--script` 回归套件**（不是 MCP；MCP 无鼠标，无法驱动鼠标点击的战斗流程，详见测试方法论）。
- `tests/test_swordsman_resources.gd`（81 断言：unit.gd / damage_calculator.gd / JSON 数据层）
- `tests/test_swordsman_integration.gd`（31 断言：tactical_manager 运行时接线 + 合成棋盘 ZOC + 仪表盘）
- 合计 **112 断言全过**，退出码 0。
- 提交（分支 `claude/p0-pursuit-lck-cleanup`）：`7f538c8` / `96b2d82` / `72af223` / `500a6d9` / `b1ba6b2` / `63631d3`。

## Implemented Mechanics (verified)

| 机制 | 行为 | 代码位置 |
|------|------|----------|
| 剑气 sword_qi | 整数 0–`qi_max`（=10），`set_sword_qi` 钳制；非剑圣 `_qi_max==0` 职业隔离 | unit.gd |
| 印记 marks | 心 / 道 / 势 三离散布尔；`gain_random_mark` 随机得未持有印记，`spend_marks(n)` 按量扣 | unit.gd |
| 心眼 — 暴击 | 每点剑气 +`crit_per_qi`(=1)% 暴击，经 `crit_bonus` 加项注入暴击率 | unit.gd / damage_calculator.gd |
| 心眼 — 速度 | 剑气 ≥ `speed_threshold`(=7) 时速度 +`speed_bonus`(=1)，`get_effective_stat` 实时计算 | unit.gd |
| 印记属性 | 持「心」→DEX+2 / 「道」→LCK+2 / 「势」→STR+2（`mark_*_bonus`，占位待调） | unit.gd |
| 槽位替换 | 满 `mark_max` 印记时招架槽显示为拔刀（**数据驱动**：读技能 JSON 的 `slot_swap_trigger`/`slot_swap_target`，不再硬编码技能 ID） | unit.gd / tactical_manager.gd |
| 技能资源接线 | 施放扣气（`qi_cost`）/ 命中产气（`qi_gain_on_hit`）/ 击杀返气（`qi_gain_on_kill`）/ cd-1（`ki_on_kill_cd_reduction`）/ 命中得印记（`mark_gain`）/ 按量扣印记（`mark_cost`→`spend_marks`） | tactical_manager.gd |
| 可用性门槛 | 剑气不足 / 印记不足时技能不可用并给原因 | tactical_manager._build_skill_entry |

## Data-Driven Config Surface (全部在 JSON，无硬编码)

`swordsman.json` 的 `sword_qi_config`：
`qi_max=10, qi_initial=0, mark_max=3, crit_per_qi=1, speed_threshold=7, speed_bonus=1, mark_dex_bonus=2, mark_lck_bonus=2, mark_str_bonus=2`（数值均为占位，待手感调）。

5 个技能 JSON 的资源字段：

| 技能 | qi_cost | 产气 | 印记 | 必中必暴 | 暴击/其它 |
|------|--------|------|------|---------|-----------|
| 斩击 zhanji | 0 | 命中 +1 | — | — | power 100 |
| 一闪 yishan | 1 | — | — | — | power 50，直线区域 |
| 招架 zhaojia | 1 | — | — | — | `slot_swap_trigger=marks_full`、`slot_swap_target=swordsman_badao`，迅捷架势 |
| 居合 juhe | 6 | 击杀 +3 | 命中 +1 | 必中 + 必暴 | power 300，击杀 `ki_on_kill_cd_reduction=1` |
| 拔刀 badao | 2 | — | 需 3 / 消耗 3（`spend_marks`） | — | power 180，`crit_damage_bonus=1.5`（暴击 3.0x），`slot_swap_provider=true` |

## Combat Formula Clarifications (verified in code，对应 battle-calculation.md 同步)

- **命中下限 = 1%**（不是旧文档写的 20%）。判定 `clamp((命中−回避)/100, 0.01, 1.0)`，1% 仅兜底，正常对局命中预期 60–70+。
- **暴击倍率初始 1.5x，是初始值不是上限**（用户 2026-06-21 澄清）。暴击倍率可经 `crit_damage_bonus`（加法叠加到 1.5）提高：拔刀 `crit_damage_bonus=1.5` → 该次暴击倍率 1.5+1.5 = **3.0x**（暴击伤害翻倍至 300%）；「暴击伤害 +20%」类天赋 = `crit_damage_bonus=0.2` → 1.7x。
- **纯粹伤害不参与暴击判定**（R1.1 / R1.3）：既不做暴击判定，也不适用任何暴击倍率或 `crit_damage_bonus`。
- **心眼剑气暴击加项已实装**（旧文档标「尚未实装、代码无剑气字段」已作废）。
- ZOC 移动惩罚 `ZOC_MOVE_PENALTY=1`（-2 降为 -1），仅离开敌方控制区一次性触发、不随相邻敌人数叠加，功能性已验证。

## Side Fix (本次实测附带修复)

底部仪表盘主属性面板 STR/MAG/DEX/SPD/DEF/RES/LCK/MOV **恒显 0**（`get_dashboard_data` 从未输出 `stats` 键）。已修：输出 `stats`（基础值）+ `stats_delta`（生效−基础），显示为「基础值 + 括号加成」，如剑圣持印记 `DEX 9 (+2)`、剑气≥7 `SPD 8 (+1)`。

## Open / Manual (MCP / headless 测不了，需编辑器内人工)

视觉 / 动画 / 颜色、鼠标驱动的完整施放链路、多回合手感与占位数值调校 → 见 `tests/剑圣手动测试清单.md`。

## Corrections Flagged in Canon Docs

- **battle-calculation.md**：命中下限 20 → 1；心眼剑气暴击已实装；`crit_damage_bonus` 字段 + 拔刀 3.0x 例。
- **class-system.md**：剑圣启动技能为 斩击 / 一闪 / 招架 / 居合 / 拔刀（非旧 Slash / Evasion Slash）；「追击受益者」表述随追击系统移除作废，速度第二效果改为出手顺序。

---

*Last updated: 2026-06-21 | Runtime verification | Claude Code (Opus 4.8) — 内部 subagent 工作模式*
