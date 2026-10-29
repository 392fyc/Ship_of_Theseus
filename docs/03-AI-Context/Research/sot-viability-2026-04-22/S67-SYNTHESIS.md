---
session: S67
date: 2026-04-23
status: AWAITING_USER_DECISION
files_in_scope:
  - B3-strict-talent-tree-samples.md
  - R2-v2-analyst-viability.md
  - R3-v2-critic-failmodes.md
supersedes_partial:
  - B1.2-talent-roguelite-decoupling.md (Pattern A/C 部分)
  - B2.1-talent-modifier-patterns.md (Hades/MT 类比)
  - R2-analyst-viability.md (Tier 2 CAUTION 结论)
  - R3-critic-failmodes.md (Tier 2 MODIFY 结论)
---

# S67 Synthesis: SoT 天赋树概念重定义 + Tier 2 重评估

## 为什么重跑

S66 的 B1.2 / B2.1 / R2 / R3 用 Hades Mirror of Night + Monster Train Champion Spec 作为"小天赋树参考系"。用户指出**事实错误**：
- Hades Mirror = meta-buff 池（通用加强，不分化）
- Monster Train Champion = deckbuilder 卡牌路线

严格"天赋树"定义 = **节点图 + 分支依赖 + build 路线分化**。S67 强制以此定义重跑 B3 → R2-v2 → R3-v2。

## 硬事实汇总

### B3 样本数据（verified）

| 组合 | 样本数 |
|------|--------|
| 严格定义固定永久节点图天赋树 × roguelite | **0** |
| Talented 式 run-generated tree × roguelite | 1 (Talented) |
| Tactical roguelite (无永久天赋树) | 5+ |
| ARPG 天赋树 (非 roguelite) | 10+ |
| Roguelite + meta-buff 列表 (非节点图) | 20+ |

**SoT 设想组合（战棋 + 多职业 + 固定永久节点图天赋树 + roguelite + 4p co-op）行业真实参考系 = 0**

### 为何行业空白（反向理由）

1. 工程成本：8 职业 × 30-40 节点 = 240-320 永久节点
2. 设计成本：剑士 7 JSON 版本未收敛 → Tier 1 (600 节点) 推算 40+ 月
3. 玩家留存：Sunderfolk CCU 890 → 91（-90%），94% 好评说明留存是结构弱点
4. 市场验证：deckbuilder roguelite 已证赚钱，节点图 roguelite 无先例

## 5 路径最终对比

| 路径 | 描述 | Feasibility | Analyst Verdict | Critic Verdict |
|------|------|:-----------:|:---------------:|:--------------:|
| A | Tier 1 (75 × 8 = 600 节点) | 1/10 | STOP | STOP |
| B | Tier 2 (30-40 × 8 = 240-320 节点) | 3/10 | **STOP (升级)** | STOP |
| C | ARPG 式永久树 + 战棋 run + 轻量 Relic | 4/10 | INSUFFICIENT_DATA | (未独立 verdict) |
| **D** | Talented 式 run-generated tree + meta 库扩展 | 5/10 | **主选 (条件)** | MODIFY |
| **E** | STS 式 card/relic（放弃永久天赋树） | 7/10 | 备选 | **主选 (条件)** |

### Analyst vs Critic 分歧

- **Analyst** 推 Path D：设计成本可控 + 4p 兼容 + Talented 行业先例
- **Critic** 翻推 Path E：**剑士 7 JSON 未收敛根因 = 收敛标准缺失非规模问题** → 单张 card/relic 判断更原子化 → Path D 只是"设计逃逸路线"不解根因

### S66 保留的有效结论（未污染）

- ✅ 载体 A (小型战棋) 方向合理（Sunderfolk / ItB / 永铃回响）
- ✅ 载体 C (ARPG) 弃用（Wolcen 15 人团队崩溃）
- ✅ 4p co-op "一人独断"结构风险 → Day 1 约束（S67 细化：实为**信息不对称**非权力不对称）
- ✅ Sunderfolk 一年 CCU 衰减 90%（战棋 roguelite 长尾结构性弱点）
- ✅ 剑士 7 JSON 版本迭代成本
- ✅ Tier 1 (75 节点) STOP
- ✅ Town Building 去除后差异化缺口

### S66 被废除的结论

- ❌ B1.2 Pattern A (Hades) + Pattern C (Monster Train) —— 错误类比
- ❌ B2.1 修饰器 Pattern 中 Hades/MT 类比部分
- ❌ R2 Tier 2 CAUTION → 升级 **STOP**
- ❌ R3 Tier 2 MODIFY 的"小天赋树可行"论点 → 升级 **STOP**

## 3 个终极追问（用户必须在实现阶段前回答）

### Q-T1: 积累感前提

> **"run 结束后天赋节点全部消失，你能接受吗？"**

- Path D 不可妥协前提
- 若答"不能完全接受" → Path D 实现将功能蔓延 → 最终向 A/B 收敛
- **诊断**: 剑士 7 JSON 版本未收敛 + 换设计轴（非换规模）= 隐形锚点可能是"看到节点被点亮"的视觉反馈
- **决策含义**:
  - YES → Path D 可行
  - NO → Path E 成主选，但需回答 Q-T3
  - 模糊 → **项目可行性重评**，非路径选择问题

### Q-T2: 4p 共同语言

> **"当 4 名玩家在 run 中途各自持有完全不同的随机天赋树时，战术讨论的共同语言是什么？"**

- Sunderfolk 共同语言 = 固定技能名
- Deep Rock Galactic 共同语言 = 固定角色职责
- Path D 中 4 玩家 × 随机树 = **无稳定共同语言**
- 原型阶段必须解决，不是发布阶段
- **决策含义**:
  - 可设计共同语言机制 → Path D 实现门槛提升但可行
  - 无解 → Path D 降为 STOP，Path E 为唯一主选

### Q-T3: Card UI 预览流失

> **"如果 SoT 的 Steam 页面截图里有 card UI，你的目标用户会 wishlist 还是滑走？"**

- **Jake Solomon (Midnight Suns 创意总监)**: *"I was naive about what people would think when they saw the mechanic was cards."*
- Midnight Suns: Metacritic 83 / Take-Two CEO 定性 commercial flop
- 战棋玩家（XCOM / 战锤受众）类型身份认同**不含** card game
- **决策含义**:
  - 接受 Midnight Suns 教训 → Path E 需美术"去卡牌化"包装（技能印记 / 战术手册）
  - 不信 card UI 是硬伤 → 商业风险自担
  - 担忧 card UI → Path E 降为 STOP，**无主选路径**，项目需重评

## 路径-问题决策矩阵

| 问题\答案 | YES | NO | 模糊 |
|----------|-----|-----|------|
| Q-T1 积累感能放弃 | → Q-T2 | → Q-T3 | 重评项目 |
| Q-T2 4p 共同语言可设计 | Path D ✅ | Path E 主选 | 原型验证 |
| Q-T3 card UI 可去卡牌化 | Path E ✅ | 无主选 | 重评项目 |

## 下一步行动建议

### 立即行动（不等用户）
- [x] S67 调研 B3 + R2-v2 + R3-v2 落盘
- [x] S67 synthesis 文档（本文）
- [ ] NAS 备份本目录到 `/share/homes/392fyc/kb/sot-viability-2026-04-22/`（S67 末或 S68 初择一）

### 等用户决策后
**如用户答 Q-T1 = YES**:
- 进入 Path D 条件性实施
- 必要前置：4p 原型验证（4 人各自随机树，30 min 战术讨论质量测量）
- 原型不过 → 降 STOP，fallback 到 Path E

**如用户答 Q-T1 = NO**:
- Path E 成主选
- 必要前置：Q-T3 答案（card UI 美术策略 or 放弃项目）

**如用户答 Q-T1 = 模糊**:
- 暂停路径决策
- 诊断剑士 7 JSON 未收敛根因：规模问题 vs 收敛标准问题
- Critic 建议用户提供**至少 1 节点的完整设计历史**以诊断（在 7 版本中追踪某个节点的变化）

### 不建议的下一步
- ❌ 在未回答 Q-T1 前进入任何 Path 实现
- ❌ 继续 Tier 2 探索（已 STOP）
- ❌ 假设"我的 card 实现更好"绕过 Midnight Suns 教训
- ❌ 假设"随机 4p 树"的协调问题可在发布阶段解决

## 信度声明

- **B3 样本**：信度 3/5（Reddit + Steam + GDC 搜索非穷尽）
- **R2-v2 analysis**：信度 3/5（Path C/D 4p 兼容 INSUFFICIENT_DATA）
- **R3-v2 critique**：信度 3/5（战棋 × roguelite × 4p 交叉样本稀缺；Sunderfolk 仅证市场天花板低）
- **综合**：**行业空白 + Tier 2 STOP 结论高信度**；**Path D vs E 主选之争低信度**（依赖用户回答 Q-T1）

## Cross-Reference

- Mercury agent 定义：`.claude/agents/game-{researcher,analyst,critic}.md`
- Mercury session memory: `~/.claude/projects/D--Mercury-Mercury/memory/session-handoff.md` (S66→S67)
- SoT 当前设计 KB: `01-Game-Design/game-design-doc.md`, `Progression/run-loop.md`, `Characters/talent-tree-design.md`
- SoT 剑士 JSON: `data/talent-tree/sw_*.json` (7 版本)
- SoT 法师 JSON: `data/talent-tree/mg_pentagram.json`
