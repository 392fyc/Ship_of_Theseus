# Swordsman Talent Tree v2 — 平行审计结果

> Auditor: Claude Code Main Agent
> Date: 2026-03-15 | Task: P3-TALENT-V2 批判性审查
> Scope: sw_onhit_v3.json / sw_overwatch_v3.json / sw_cycle_v3.json + 全套研究文档

---

## 审计总评

**设计层面质量高**：研究扎实（8 款游戏全覆盖，引用具体机制）、三版本差异化明确、普攻权重策略创新。

**JSON 实现层面存在系统性 bug**：与 v1 时 AG/opencode 犯的错误完全一致，说明 v2 session 未以 Codex 基线的共享区结构为起点。

---

## 跨版本共性问题

| # | 问题 | 严重度 | 涉及版本 | 详情 |
|---|------|--------|---------|------|
| C1 | 路径锚点 off-by-one | CRITICAL | A/B/C 全部 | BFS(sw_start→sw_adv_*)=9（应为 10）。共享区关键路径只有 9 跳，缺少 1 个节点。Codex 基线是 10 跳 |
| C2 | 剑仙 standard action 超限 | CRITICAL | A/B/C 全部 | SC 路径有 4 个 standard（sc_B14 + sc_A16 + sc_A20_qual + sc_B20_qual），超出 ≤3 上限 |
| C3 | cm_M11 零出边死端 | MODERATE | A/B/C 全部 | 银蔷薇入口节点无出边，功能仅为属性税。可接受但需文档标注 |
| C4 | 硬编码绝对数值 | MODERATE | A/B/C 全部 | sw_R6(RES+3), sw_hub8(STR+3,DEF-1), sw_pre_magic9(MAG+3), ss_A12(SPD+2), ss_A19(DEF-3), detour_sc_22(MAG+2) 使用绝对值 |
| C5 | action economy 表跨版本复制粘贴 | MODERATE | A/B/C 全部 | 三版本 rationale 的行动经济表完全相同，Version B 的架势/迅捷分配应与 A/C 不同 |

## 版本特有问题

### Version A: On-Hit Engine

| # | 问题 | 严重度 | 详情 |
|---|------|--------|------|
| A1 | 深潜 gauge_extend 内轨违规 | MODERATE | ss_B16(x=-200), ss_B18(x=-200), sc_A19(x=200) 是 gauge_extend 但在内轨，应在外轨(\|x\|≥300) |
| A2 | on-hit 饱和度过高 | INFO | 76/87 节点(87%)提及 on-hit，版本内部差异化不足 |

### Version B: Overwatch/Stance

| # | 问题 | 严重度 | 详情 |
|---|------|--------|------|
| B1 | Overwatch 核心取舍被瓦解 | CRITICAL(设计) | Lv18+ 多个节点让"使用技能后自动进入待机"(ss_A20_qual, ss_B20_qual, sc_B14, sc_A16, cm_M20)，消灭了"放弃行动换待机"的核心决策 |
| B2 | 深潜对角线 N→N+1 | MODERATE | ss_B21→sc_A23 和 sc_A21→ss_B23 实际 dy=80(N+1)，规则要求 N→N+2(dy=160) |
| B3 | 剑仙零 reaction 技能 | MODERATE | 整条 SC 路径无反应技能，行动类型多样性不足 |
| B4 | Overwatch 饱和度过高 | INFO | 67/87 节点(77%)提及待机/架势 |

### Version C: Resource Cycle

| # | 问题 | 严重度 | 详情 |
|---|------|--------|------|
| C-1 | 银蔷薇 Lv17-20 未隔离 | CRITICAL | cm_M16 出边到 ss_B17/sc_A17 后可一路走到 Lv20 终端，违反"银蔷薇不覆盖 Lv18-20"设计裁决 |
| C-2 | 剑仙无反囤积机制 | MODERATE | 刀圣有剑意衰减(-5/回合)，剑仙的剑元可无限累积无惩罚 |

## 文档缺失

| 缺失文件 | 影响 |
|----------|------|
| iteration-log.md | 无跨版本 R1→R2→R3 变更追踪，迭代过程不可审计 |
| v2-final-report.md | 无最终推荐排序和理由文档，"C > A > B" 结论无正式记录 |

## 通过项

| 维度 | 结果 |
|------|------|
| 术语清洗 | ✅ 全部通过（无 ms_*/魔剑/magic_swordsman） |
| 坐标碰撞 | ✅ 零碰撞 |
| 孤儿/重复 ID | ✅ 零 |
| 深潜 detour 合规 | ✅ tag + 零出边 |
| Reaction 1-2 个 | ✅ 各 1 个(ss_M12) |
| 普攻权重覆盖 | ✅ 73-87% 节点涉及普攻增强 |
| 研究文档质量 | ✅ 8 款游戏全覆盖 |
| 三版本差异化 | ✅ 核心机制清晰区分 |

---

*Generated: 2026-03-15 | Main Agent*
