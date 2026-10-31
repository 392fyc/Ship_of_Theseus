# Swordsman Talent Tree v2 — 多版本深度设计任务

> Executor: Claude Code (独立 session)
> Date: 2026-03-15 | Task ID: P3-TALENT-V2
> Branch: `claude/sw-talent-v2-design`

---

## 任务总览

基于三个 Sub Agent 的 v1 优化方案（已通过审计），以 **Codex 版本为基线**，设计 **至少 3 个差异化版本** 的剑士天赋树。每个版本经历 **至少 3 轮推导迭代**。如果研究过程中发现值得引入的新玩法元素，可额外创建研究分支版本（同样 3 轮推导）。

---

## 阶段一：研究（Research Phase）

### 1.1 战棋游戏天赋/技能树参考研究

使用 WebSearch 研究以下游戏的天赋/技能/职业系统设计，重点关注：

| 游戏 | 重点研究方向 |
|------|-------------|
| **XCOM 2 (War of the Chosen)** | 双路线技能树、行动经济（标准/自由动作）、Overwatch 反应系统、普通攻击与技能的权重关系 |
| **火焰纹章：风花雪月** | 技能等级系统、战技(Combat Arts)消耗与普通攻击的共存、骑士团加成、兵种转职分支 |
| **火焰纹章 Engage** | 纹章系统、技能继承、Bond Ring 被动加成层、武器三角回归的平衡 |
| **Dark Deity** | 6 职业分支、每个分支 4 等级被动、简洁明快的天赋树风格 |
| **Symphony of War** | 小队编制中的个体天赋、领袖技能与队员被动的组合、阵型影响 |
| **The Last Spell** | Roguelite 战棋中的随机天赋获取、每轮升级选择、高技能密度下普通攻击的设计 |
| **Into the Breach** | 极简行动经济（1 移动 + 1 攻击）、位移/推拉核心、反应式设计 |
| **Wildermyth** | 叙事驱动天赋解锁、变异系统、多元化成长路线 |

**研究输出**：写入 `D:\ShipOfTheseus\ShipOfTheseus-KB\05-Research\swordsman-talent-v2-research\` 目录：
- `tactical-rpg-skill-systems-survey.md` — 各游戏系统的核心设计模式总结
- `attack-action-weight-analysis.md` — 各游戏如何保持"普通攻击"在技能丰富环境下的竞争力
- `action-economy-comparison.md` — 行动经济设计对比（标准/迅捷/反应/自由）

### 1.2 本项目核心系统重读

必须完整阅读以下文件，确保设计不偏离核心系统：

| 文件 | 路径 | 关注点 |
|------|------|--------|
| 天赋树深潜规则 | `D:\ShipOfTheseus\ShipOfTheseus-KB\01-Game-Design\Characters\talent-tree-deep-dive-rules.md` | 深潜区拓扑、量谱、阵营 |
| 天赋树设计哲学 | `D:\ShipOfTheseus\ShipOfTheseus-KB\01-Game-Design\Characters\talent-tree-design.md` | 五线谱布局、桥税、锚点 |
| 天赋树系统规格 | `D:\ShipOfTheseus\ShipOfTheseus-KB\01-Game-Design\Characters\talent-tree.md` | 量谱定义、暴击无上限、节点类型 |
| 职业系统 | `D:\ShipOfTheseus\ShipOfTheseus-KB\01-Game-Design\Characters\class-system.md` | 剑士属性、转职路线、反击/追击 |
| 战斗计算 | `D:\ShipOfTheseus\ShipOfTheseus-KB\01-Game-Design\Core-Systems\battle-calculation.md` | 伤害/命中/暴击公式 |
| 回合系统 | `D:\ShipOfTheseus\ShipOfTheseus-KB\01-Game-Design\Core-Systems\turn-system.md` | 行动经济：移动/标准/迅捷/反应/自由 |
| 技能与射程 | `D:\ShipOfTheseus\ShipOfTheseus-KB\01-Game-Design\skills-and-range.md` | 技能数据结构、action_cost |
| 原始优化 Prompt | `D:\ShipOfTheseus\ShipOfTheseus-KB\03-AI-Context\Handoffs\swordsman-talent-tree-optimization-prompt.md` | 7 个已知问题、设计约束、质量清单 |

### 1.3 三方案对比分析

阅读三个 Agent 的 JSON 文件，提取各自优势和不足：

| 文件 | 来源 |
|------|------|
| `D:\ShipOfTheseus\Ship_of_Theseus\data\talent-tree\sw_codex.json` | Codex CLI (R2) — **基线** |
| `D:\ShipOfTheseus\Ship_of_Theseus\data\talent-tree\sw_antigravity.json` | AntiGravity (R3) |
| `D:\ShipOfTheseus\Ship_of_Theseus\data\talent-tree\sw_opencode.json` | opencode (R2) |

**输出**：`D:\ShipOfTheseus\ShipOfTheseus-KB\05-Research\swordsman-talent-v2-research\three-agent-comparison.md`

---

## 阶段二：设计文档（Design Doc Phase）

基于研究成果，撰写核心设计文档：

**输出**：`D:\ShipOfTheseus\ShipOfTheseus-KB\05-Research\swordsman-talent-v2-research\v2-design-philosophy.md`

内容必须覆盖：

### 2.1 普通攻击权重提升策略

这是本次设计的 **核心新增要求**。传统战棋中普通攻击在大量技能面前容易沦为"没技能可用时的下位替代"。v2 天赋树必须通过节点设计让普通攻击保持竞争力：

可能的方向（研究后确定）：
- **On-hit 被动链**：普通攻击触发被动效果（量谱生成、debuff 附加、追击触发），使普通攻击成为"引擎启动器"
- **攻击强化节点**：直接提升普通攻击的伤害/命中/暴击，使其数值上不被技能碾压
- **资源经济**：技能消耗资源（剑意/剑元），普通攻击回复资源，形成"普攻充能→技能释放"的循环
- **Overwatch/待机攻击**：将普通攻击延伸为反应式待机射击（参考 XCOM），让不使用技能的回合也有战术价值
- **连击/追击系统**：普通攻击可触发追击（参考火纹），使攻击收益 > 单次伤害

### 2.2 行动经济设计框架

按 action_cost 类型规划每个版本的技能分配：

| 行动类型 | 预算上限 | 设计原则 |
|----------|---------|---------|
| **standard** (标准) | 每路径 ≤3 | 核心输出/控制技能，与普通攻击竞争同一个行动槽 |
| **swift** (迅捷) | 每路径 1-2 | 增益/位移/准备类，不与标准行动竞争 |
| **move** (移动) | 每路径 0-1 | 特殊位移技能，替代普通移动 |
| **reaction** (反应) | 全树 1-2 | 被动触发式主动技能，回合外行动 |
| **free** (自由) | 全树 0-1 | 极稀有，不消耗行动资源 |

### 2.3 转职分支特色定义

| 分支 | 核心身份 | 量谱 | 战术定位 | 普攻角色 |
|------|---------|------|---------|---------|
| **刀圣 (Blade Master)** | 高速近战、居合爆发 | 剑意 (Sword Intent) | 单体击杀、反击压制 | 普攻生成剑意，是爆发循环的启动器 |
| **剑仙 (Sword Cultivator)** | 飞剑遥控、阵法控场 | 剑元 (Sword Essence) | 范围控制、阵地战 | 普攻通过飞剑进行，触发阵法效果 |
| **银蔷薇 (Silver Rose)** | 中轴桥接 | 无专属量谱 | 跨系多面手 | 中轴节点增强普攻的泛用性 |

---

## 阶段三：三版本天赋树设计 + 迭代

### 版本命名规则

`sw_{版本特点缩写}_v{版本号}.json`

例如：`sw_onhit_v1.json`、`sw_overwatch_v2.json`、`sw_combo_v3.json`

### 三个版本的核心差异方向（研究后可调整）

| 版本 | 核心特点 | 普攻权重策略 | 参考游戏 |
|------|---------|-------------|---------|
| **Version A: On-Hit Engine** | 普攻作为被动链引擎，每次普攻触发 on-hit 效果叠加 | 普攻 = 被动引擎启动器，不打普攻就没有被动收益 | The Last Spell, 暗黑破坏神 |
| **Version B: Overwatch/Stance** | 引入待机/架势系统，不使用技能的回合进入 Overwatch 状态 | 普攻 = Overwatch 的自动触发手段，主动放弃技能换取反应控场 | XCOM, Into the Breach |
| **Version C: Resource Cycle** | 强化资源循环——普攻回复资源、技能消耗资源 | 普攻 = 唯一稳定资源回复手段，不普攻就没资源放技能 | 火焰纹章 (战技耐久), 风花雪月 |

### 每版本迭代流程（3 轮）

**Round 1 — 骨架**：
- 定义所有节点 ID、名称、类型、位置、依赖
- 确保五线谱布局、层级锚点（Lv10/15/20/22-25）
- 确保银蔷薇间歇桥结构
- 输出 JSON + 简要设计说明

**Round 2 — 审计**：
- 路径锚点验证（BFS 计算）
- 行动经济审计（standard ≤3/路径、reaction 1-2/全树）
- 普攻权重审计：每条路径是否有足够节点让普攻保持竞争力？
- 技能描述完善：效果、数值（百分比/公式引用，不硬编码）
- 深潜合规检查

**Round 3 — 打磨**：
- 对比三版本，确保差异化足够明显
- 叙事/文案一致性检查（术语、世界观）
- 边缘情况：纯普攻 build 是否可行？纯技能 build 是否可行？混合 build？
- 最终 JSON 输出 + 完整 rationale

### 额外研究分支（如适用）

如果研究阶段发现新玩法元素值得引入（例如：变异/契约系统、队友联动天赋、地形交互天赋等），可创建第 4+ 个版本作为研究分支。同样经历 3 轮迭代。命名加 `_exp` 后缀（experimental）。

---

## 硬性约束（继承自原始 Prompt）

1. **All node cost = 1**
2. **不硬编码战斗数值** — 使用百分比/倍率/公式引用
3. **暴击率无上限** — 不设计基于暴击率上限的节点
4. **格挡与暴击互斥**
5. **pure 伤害无视格挡；pure 暴击 = 固定 1.5x**
6. **hybrid = phys_atk + mag_atk 同时生效**
7. **反击/追击不连锁**
8. **范围攻击不触发反击**
9. **ZOC 不叠加，固定 -2**
10. **距离无衰减**
11. **银蔷薇 = 间歇可穿越桥**：cm_M13 + cm_M16 有横向出边，cm_M20 死端，不覆盖 Lv18-20
12. **Reaction 技能全树 1-2 个**
13. **路径锚点**：Lv10=转职, Lv15=小门槛, Lv20=大门槛, Lv22-25=终极

---

## 输出文件结构

```
D:\ShipOfTheseus\ShipOfTheseus-KB\05-Research\swordsman-talent-v2-research\
├── tactical-rpg-skill-systems-survey.md      # 阶段一研究
├── attack-action-weight-analysis.md          # 阶段一研究
├── action-economy-comparison.md              # 阶段一研究
├── three-agent-comparison.md                 # 阶段一对比
├── v2-design-philosophy.md                   # 阶段二设计文档
└── iteration-log.md                          # 迭代过程记录

D:\ShipOfTheseus\Ship_of_Theseus\data\talent-tree\
├── sw_onhit_v3.json                          # Version A 最终版
├── sw_overwatch_v3.json                      # Version B 最终版
├── sw_cycle_v3.json                          # Version C 最终版
├── sw_{exp}_v3.json                          # 研究分支（如有）
├── sw_onhit_rationale.md                     # Version A 设计说明
├── sw_overwatch_rationale.md                 # Version B 设计说明
├── sw_cycle_rationale.md                     # Version C 设计说明
└── sw_{exp}_rationale.md                     # 研究分支说明（如有）
```

---

## 汇报要求

任务完成后，向 Main Agent 提交结构化汇报：

1. **研究发现摘要**：从参考游戏中提取的 top-3 设计洞察
2. **三版本对比矩阵**：核心差异、普攻权重策略、行动经济分布、节点统计
3. **每版本的迭代变更日志**：R1→R2→R3 的关键修改
4. **推荐排序**：哪个版本最适合本项目，理由
5. **新元素建议**（如有）：研究分支的价值评估
6. **遗留问题**：需要 Main Agent 决策的设计分歧

---

## 工具使用指南

- **WebSearch**: 用于阶段一战棋游戏研究，必须交叉验证 2+ 来源
- **Read**: 读取 KB 文档和现有 JSON
- **Write**: 写入研究文档和 JSON 文件
- **Edit**: 迭代修改 JSON 和文档
- **Agent tool (Sub Agents)**: **本次任务特许使用**。可以派发 Sub Agent 处理以下类型的子任务：
  - 并行研究不同游戏的技能系统（阶段一）
  - 并行生成多版本天赋树骨架 JSON（阶段三 Round 1）
  - 并行执行 BFS 路径验证 / 行动经济审计（阶段三 Round 2）
  - 并行打磨不同版本的文案和边缘情况检查（阶段三 Round 3）
  - Sub Agent 仅限辅助研究和验证，**最终设计决策和文件写入由主 session 执行**
  - Sub Agent 不得直接写入 KB 文件或修改 Git 状态

---

## 关键提醒

- 你是 Claude Code Main Agent 的独立 session，拥有本次任务的完整设计决策权
- **本次特许使用 Sub Agents**（Agent tool），但最终交付物由你亲自写入
- 遵守 CLAUDE.md 所有约束
- 设计文档用中文（简体）
- JSON 中的 desc 用中文
- 版本查询必须先 WebSearch
- 每轮迭代的 JSON 必须可被 `tools/talent-tree-editor.html` 加载验证
- 普通攻击权重是本次任务的 **第一优先级设计目标**

---

*Generated: 2026-03-15 | Claude Code Main Agent | For: Claude Code independent session*
