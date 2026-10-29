# Swordsman Talent Tree v2 — 整改指令

> Source: Main Agent 审计结果 `sw-talent-v2-audit-result.md`
> Date: 2026-03-15 | Executor: Claude Code (同一 session 或新 session)
> Priority: CRITICAL fixes first, then MODERATE, then documentation

---

## 审计背景

你的 v2 三版本产出（sw_onhit_v3 / sw_overwatch_v3 / sw_cycle_v3）已通过 Main Agent 批判性审查。设计层面质量高，但 JSON 实现层面存在系统性 bug。本指令要求你修复所有问题并补齐缺失文档。

完整审计报告见：`D:\ShipOfTheseus\ShipOfTheseus-KB\03-AI-Context\Handoffs\sw-talent-v2-audit-result.md`

---

## Part 1: 跨版本共性修复（三版本同步执行）

### Fix C1: 路径锚点 off-by-one [CRITICAL]

**问题**：三个版本的 BFS(sw_start → sw_adv_*) = 9，应为 10。共享区关键路径缺少 1 个节点。

**根因**：你未使用 Codex 基线（`sw_codex.json`）的共享区结构。Codex 的共享区有 20 个节点且关键路径恰好 10 跳。

**修复方法**：
1. 读取 `D:\ShipOfTheseus\Ship_of_Theseus\data\talent-tree\sw_codex.json` 的共享区（所有 `sw_*` 节点及其边）
2. 对比你三个版本的共享区，找出缺失的节点/边
3. 将缺失的节点补回——**不要随便插入 dummy 节点**，应该还原 Codex 基线的共享区拓扑
4. 三个版本使用**完全相同的共享区结构**（sw_* 节点和边应该是统一的）

**验证**：修复后对三个版本分别执行 BFS，确认：
- sw_adv_saint = 10
- sw_adv_cultivator = 10
- 任意 Lv15 _qual = 15
- 任意 Lv20 _qual = 20

### Fix C2: 剑仙 standard action 超限 [CRITICAL]

**问题**：SC 路径有 4 个 standard action（sc_B14 + sc_A16 + sc_A20_qual + sc_B20_qual），超出 ≤3 上限。

**修复方法**（三选一，按版本选择最合适的）：
- 将 `sc_A16` 改为 `action_cost: "swift"`（部署/准备类技能适合迅捷）
- 将 `sc_B14` 改为 `type: "skill_upgrade"`（作为 sc_B11 的升级，共用技能槽）
- 将 `sc_A16` 改为 `type: "passive"` 或 `type: "trait"`（如果描述实际上是被动效果）

**注意**：三个版本的 sc_A16 描述不同（A=on-hit 相关, B=overwatch 相关, C=resource 相关），每个版本应根据该版本的 sc_A16 具体描述选择最合适的修改方案。

**验证**：修复后每条路径 standard action ≤ 3（Lv11-20 范围内，不含深潜终局技）。

### Fix C3: cm_M11 标注 [MODERATE]

**修复**：在三个版本的 `cm_M11` 节点的 `notes` 字段中加入说明：
```json
"notes": "银蔷薇入口税节点，intentional dead end，提供属性收益但不连接后续路径"
```

### Fix C4: 硬编码绝对数值 [MODERATE]

**涉及节点**（三版本相同）：
| 节点 | 当前值 | 修复方向 |
|------|--------|---------|
| sw_R6 | RES+3 | → RES+base_res_bonus%（引用公式） |
| sw_hub8 | STR+3, DEF-1 | → ATK+atk_per_level%, DEF-def_trade% |
| sw_pre_magic9 | MAG+3 | → MAG+base_mag_bonus% |
| ss_A12 | SPD+2 | → SPD+spd_bonus%（或"小幅提升速度"） |
| ss_A19 | DEF-3 (debuff) | → DEF-debuff_def%（引用公式） |
| detour_sc_22 | MAG+2 | → MAG+detour_mag_bonus% |

**原则**：将绝对数值改为百分比加成，或改为描述性文字（"小幅/中幅/大幅"）+引用 balance table 的 key。具体数值应由运行时从 balance JSON 读取。

### Fix C5: action economy 表去重 [MODERATE]

**修复**：更新三个 rationale 文件的行动经济分配表，使其反映各版本的实际技能分配。尤其是 Version B 的架势切换应体现为额外 swift 用途。

---

## Part 2: 版本特有修复

### Fix A1: 深潜 gauge_extend 内轨违规 [MODERATE] — Version A only

将以下节点移至外轨：
- `ss_B16`: x 从 -200 改为 -400（或 -300）
- `ss_B18`: x 从 -200 改为 -400（或 -300）
- `sc_A19`: x 从 200 改为 400（或 300）

**注意**：移动坐标后检查视觉布局是否合理，避免与同层其他节点重叠。

### Fix B1: Overwatch 取舍瓦解 [CRITICAL/设计] — Version B only

**问题**：Overwatch 的核心设计是"放弃标准行动 → 进入待机状态"。但 Lv18+ 多个节点授予"使用技能后自动进入待机"，完全消除了核心取舍。

**修复方向**：
1. **保留取舍感**：将"自动进入待机"改为"使用技能后，下回合进入待机的触发阈值降低"或"技能后待机仅持续 1 次触发（而非完整待机）"
2. **分层设计**：
   - 基础待机（Lv8 sw_hub8 解锁）：放弃标准行动 → 完整待机（可触发多次）
   - 半待机（Lv18+ 解锁）：使用技能后 → 微待机（仅触发 1 次，伤害减半）
   - 这样高等级角色获得的是"行动 + 弱待机"而非"行动 + 完整待机"
3. **具体修改**：
   - `ss_A20_qual`: 改为"使用后进入半待机（仅 1 次触发，伤害 50%）"而非自动完整待机
   - `ss_B20_qual`: 同上
   - `cm_M20`: 改为"击杀后下回合待机触发伤害 +30%"（奖励待机质量而非免费待机）

### Fix B2: 深潜对角线 N→N+1 [MODERATE] — Version B only

**修复**：将对角线边调整为 N→N+2：
- `ss_B21 → sc_A23`：确认 y 差 = 160（2 级跳），如果是 80 则改为连接 Lv23 节点
- `sc_A21 → ss_B23`：同上

### Fix B3: 剑仙零 reaction [MODERATE] — Version B only

**修复**：在 SC 路径添加 1 个 reaction 节点。建议在 Lv15-17 区间添加一个飞剑拦截反应技能：
```json
{
  "id": "sc_M16",
  "name": "剑幕护身",
  "type": "active_skill",
  "action_cost": "reaction",
  "desc": "反应技能：当己方阵法范围内的友军受到攻击时，飞剑自动拦截，减免伤害"
}
```
注意全树 reaction 总数不超过 2。

### Fix C-1: 银蔷薇 Lv17-20 未隔离 [CRITICAL] — Version C only

**问题**：cm_M16 出边到 ss_B17/sc_A17，之后玩家可沿 B17→B18→B19→B20_qual 一路走到对侧终端。

**修复方法**（二选一）：
- **方案 A**（推荐）：cm_M16 的出边目标从 `ss_B17/sc_A17` 改为 `ss_B14/sc_A14`（降低桥出口等级，让跨系玩家从更早的位置重新开始攀爬）
- **方案 B**：在 ss_B18 和 sc_A18 添加 `exclusive: "adv_choice"` 限制，阻止非本系玩家继续前进（但这会引入 exclusive 滥用）

**验证**：修复后，从银蔷薇跨系到达对侧 Lv20 终端的 BFS 距离应 ≥ 从本系直接到达的距离 + 2。

### Fix C-2: 剑仙反囤积机制 [MODERATE] — Version C only

**修复**：在剑仙转职节点 `sw_adv_cultivator` 或早期 SC 节点中添加反囤积机制描述。建议：
- "剑元满值时，自然恢复停止且每回合溢出的剑元转化为 debuff（灵压过载：命中率 -5%/回合）"
- 或 "剑元 ≥80% 时，普攻回复效率减半（灵脉饱和）"

这确保剑仙玩家有动力及时消费资源，而非无限囤积等待最佳时机。

---

## Part 3: 文档补齐

### Doc 1: iteration-log.md [HIGH]

**路径**：`D:\ShipOfTheseus\ShipOfTheseus-KB\05-Research\swordsman-talent-v2-research\iteration-log.md`

**内容要求**：
```markdown
# Swordsman Talent Tree v2 — 迭代日志

## Version A: On-Hit Engine
### R1 → R2 变更
- [具体修改项 + 原因]
### R2 → R3 变更
- [具体修改项 + 原因]
### R3 → R4 变更（本次整改）
- [Fix C1/C2/C4/A1 的具体修改]

## Version B: Overwatch/Stance
[同上结构]

## Version C: Resource Cycle
[同上结构]

## 跨版本共性修改
- [Fix C1-C5 的统一修改记录]
```

### Doc 2: v2-final-report.md [HIGH]

**路径**：`D:\ShipOfTheseus\ShipOfTheseus-KB\05-Research\swordsman-talent-v2-research\v2-final-report.md`

**内容要求**：
```markdown
# Swordsman Talent Tree v2 — 最终报告

## 1. 研究发现摘要
- Top-3 设计洞察（从 8 款游戏中提取）

## 2. 三版本对比矩阵
| 维度 | Version A | Version B | Version C |
|------|-----------|-----------|-----------|
| 核心机制 | ... | ... | ... |
| 普攻权重策略 | ... | ... | ... |
| 行动经济分布 | ... | ... | ... |
| 节点统计 | ... | ... | ... |
| 实现风险 | ... | ... | ... |

## 3. 推荐排序 + 理由
[C > A > B 的详细论证]

## 4. 新元素建议（如有）

## 5. 遗留问题
[需要 Main Agent 决策的设计分歧]
```

### Doc 3: 三版本 rationale 更新

更新各 rationale 文件，添加 R4（整改轮）记录，并修正 action economy 表使其反映各版本实际分配。

---

## 执行顺序

1. **先修共性 bug**（C1 → C2 → C4）— 三版本同步
2. **再修版本特有**（B1 → C-1 → B2 → B3 → A1 → C-2 → C3 → C5）
3. **最后补文档**（iteration-log → v2-final-report → rationale 更新）

## 验证清单

对每个版本执行以下检查，全部通过后方可提交：

- [ ] BFS(sw_start → sw_adv_saint) = 10
- [ ] BFS(sw_start → sw_adv_cultivator) = 10
- [ ] BFS(sw_start → 任意 Lv15 _qual) = 15
- [ ] BFS(sw_start → 任意 Lv20 _qual) = 20
- [ ] SC 路径 standard action ≤ 3（Lv11-20）
- [ ] cm_M11 有 notes 标注
- [ ] 零硬编码绝对数值（desc 中无 +N 形式的 flat stat）
- [ ] 零坐标碰撞
- [ ] 零孤儿节点
- [ ] 零重复 ID
- [ ] JSON 可加载（tools/talent-tree-editor.html）
- [ ] iteration-log.md 存在且内容完整
- [ ] v2-final-report.md 存在且内容完整
- [ ] 各版本 rationale 的 action economy 表已去重，反映实际分配

### 版本特有验证

**Version A**:
- [ ] gauge_extend 节点全部在外轨（|x| ≥ 300）

**Version B**:
- [ ] Overwatch 取舍在 Lv18-20 仍有意义（不存在"完整自动待机"）
- [ ] 深潜对角线为 N→N+2
- [ ] SC 路径有至少 1 个 reaction 技能
- [ ] 全树 reaction ≤ 2

**Version C**:
- [ ] 银蔷薇跨系到达对侧 Lv20 终端的 BFS ≥ 本系直达 + 2
- [ ] 剑仙有反囤积/溢出惩罚机制

---

## 提交要求

- 修改完成后 commit 到 `claude/sw-talent-v2-design` 分支
- Commit message: `design(P3-TALENT): v2 round-4 fixes per main agent audit`
- 向 Main Agent 汇报：修复项清单 + 每项的具体修改 + 验证结果

---

*Generated: 2026-03-15 | Main Agent audit → fix directive | Target: Claude Code session (P3-TALENT-V2)*
