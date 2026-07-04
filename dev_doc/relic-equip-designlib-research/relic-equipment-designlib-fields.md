---
title: 遗物/装备加入 SoT 设计库 — 字段规格研究
date: 2026-07-05
status: research_deliverable
authority: 研究材料 + grounded 方案，非设计裁决（结构级裁决属用户；软件实装属 Mercury）
visual_companion: relic-equipment-designlib-fields.html
lane: SoT main（研究 + 字段结论）→ 交 Mercury（设计库软件实装）
sources:
  - SoT-fyc-space/app/models.py（设计库 7 实体承载模式）
  - SoT-fyc-space/app/validation/godot_export.py（engine_json jsonschema + 派生列）
  - SoT-fyc-space/scripts/backfill_engine.py（Godot→设计库 只读回填管线）
  - Ship_of_Theseus/data/relics/（10）+ data/equipment/（8）
  - KB architecture-consensus-v2.md（L4/L5 定位，consensus_locked）
  - KB adr-2026-07-02-relic-canonical-rune-deprecated.md（ADR-010）
  - KB run-loop.md（奖励映射 + 来源模型）
  - KB D4-equipment-affix.md（装备词缀，stage2 提案未 locked）
---

# 遗物 / 装备加入 SoT 设计库 — 字段规格研究

> **一句话**：遗物（Relic）和装备（Equipment）可以照设计库现有 Skill / Talent 的承载模式加入——
> **叙述层字段**（名 / 描述 / 稀有度标注 / 生效时机文本 / 标签）在设计库直接维护，
> **引擎数值层 `engine_json`** 照 **Talent 的只读镜像模式**（Godot 权威 → Mercury 回填，设计库不手编）。
> 字段清单、jsonschema 草图、软件改动面已给出；**9 个结构级冲突需用户裁决**（稀有度词表统一、archetype 两分/三分、遗物是否绑职业等）。

> **三态标注贯穿全文**：**[已定]**=KB 正本 / 用户裁决；**[提案]**=方向建议待确认；**[占位]**=数字纯填坑随时可换。
> **数据流归属**：`Godot权威→镜像`（引擎数值，设计库只读）/ `设计库可编辑`（叙述层）/ `设计库自动派生`（派生列/时间戳）。

---

## 0. 本研究的边界（务必先读）

| 谁做什么 | 内容 |
|---|---|
| **本研究（SoT main）做** | 回 KB 真源核对 + 读设计库/引擎代码 + 业界做法研究 → 产出字段规格 + 数据流结论 + 软件改动面参考 |
| **本研究不做** | 不改设计库代码（软件实装归 Mercury）；不写 KB 正式规格（`relics-system.md`/`equipment.md` 属设计裁决，需用户先拍板）；不手编设计库 `engine_json` |
| **用户裁决** | 第 10 节的 9 个结构级冲突 |
| **Mercury 实装** | 第 9 节的设计库软件改动（建表 / 枚举 / API / 校验 / 模板 / 回填配置） |

---

## 1. 设计库现状：如何承载技能 / 天赋（遗物/装备的参照模板）

设计库（`SoT-fyc-space`，FastAPI + SQLModel + SQLite）现有 7 个实体：职业 / 标签 / 技能 / 天赋 / 规则 / 术语 / 评论。
**遗物、装备都不在其中**——这正是要新增的。Skill / Talent 的承载模式分三层：

| 层 | 谁维护 | 字段举例 | 说明 |
|---|---|---|---|
| **叙述层** | `设计库可编辑` | `name` / `description` / `damage_type`(中文枚举) / `rarity` / `trigger`(生效时机) / `effect` / `notes` / `tags` | 设计描述，走 CRUD 表单直接改（写门 `require_token`） |
| **引擎镜像层** | `Godot权威→镜像` | `engine_json`（完整 Godot 数值块 JSON 文本） | 引擎数值，独立 taxonomy（英文枚举 + 职业专属字段），jsonschema 校验 |
| **派生 / 元数据 / 状态** | `设计库自动派生` | `eng_*` 12 列 / `updated_at` / `status` / `shelf_state` / `trashed_at` | 派生列从 `engine_json` 自动拍平，供 SQL 查询/排序/离群初筛 |

### 1.1 ★关键发现：Skill 与 Talent 的 engine_json 模式不同

| 实体 | engine_json 可否库内手编 | 是否进写模型 | 校验 |
|---|---|---|---|
| **Skill** | **可手编**（`skills.html` textarea + `POST/PATCH`） | 进 `SkillIn/SkillPatch` | 写路径过 `GODOT_SKILL_SCHEMA` 校验（HTTP 400 拒非法） |
| **Talent** | **只读**（`talent_detail.html` 灰框展示「数值由 Godot 回填」） | **刻意不进** `TalentIn/TalentPatch` | 格式未冻结 → DEFER 原样保存不校验 |

**结论**：遗物/装备应照 **Talent 的只读模式**（守数据流纪律「设计库不手编 engine_json」），**不照 Skill 的可手编模式**。
Talent 的做法就是本研究声明的「只读镜像」纪律的正确范本。

### 1.2 engine_json 机制（4 个环节）

1. **校验**：`app/validation/godot_export.py` 的 `GODOT_SKILL_SCHEMA`（jsonschema Draft 2020-12）。必填 10 字段 + 核心枚举严格（catch 拼写）+ 顶层 `additionalProperties` 限标量（容职业专属字段 `qi_cost`/`mark_cost` 等）。fail-closed。
2. **派生列**：`derive_engine_columns()` 把通用标量字段拍平成 12 个 `eng_*` 列，安全降级不抛异常；数组（effects/tags）与职业专属字段不拍平、仍留 `engine_json`（避免 20+ 脆弱列）。
3. **导出**：`GET /api/export/godot` 三分区（合法 skills / 空 skipped / 非法 errors），fail-closed 不喂脏数据给引擎。
4. **回填**：`scripts/backfill_engine.py`，**配置驱动**、两段分离——
   - `snapshot`（仅开发机，有 Godot 仓）：读 Godot `data/skills/*.json` → 逐块校验 → 写镜像 `seed/engine_mirror.json`（随仓分发）。
   - `apply`（NAS/本地均可，只读镜像文件）：对每个设计库行 **update-only** 幂等灌 `engine_json` + 派生列；覆盖 stale、行缺失只报告不新建、非法块跳过。
   - `CLASS_MAP`（`swordsman→kensei`）是「Godot 扁平花名册 ↔ 设计库演化体系」的桥，扩职业=加一行。

---

## 2. SoT v0 遗物 / 装备数据现状（Godot 仓，已核）

### 2.1 遗物 `data/relics/`（10 件，全 [占位] 骨架）

字段：`id` / `name` / `rarity` / `category` / `slot_cost` / `effects[]`（声明式）/ `is_passive` / `description` / `_note`。

```json
// relic_iron_core.json（数值类）
{ "id":"relic_iron_core", "name":"铁芯", "rarity":"common", "category":"stat",
  "slot_cost":1, "effects":[{"type":"stat_flat","stat_key":"DEF","value":3}],
  "is_passive":true, "description":"防御力增加 3。" }
// relic_vampiric_fang.json（背水/流派类）
{ "id":"relic_vampiric_fang", "name":"吸血獠牙", "rarity":"epic", "category":"build",
  "slot_cost":1, "effects":[{"type":"lifesteal_pct","value":25}], "is_passive":true }
```

- **rarity 实际取值**：`common` / `epic` / `legendary`（三档在用；`rare` 也在 RewardDrop 词表）。
- **category 实际取值**：`economy` / `stat` / `build`（**三分法**——与 KB 的两原型冲突，见 §4/§10）。
- **effects 9 类**（全声明式、无执行器、全 [占位]）：`gold_gain_pct` / `exp_gain_pct` / `talent_point_bonus`（经济 3）、`stat_flat` / `crit_bonus` / `move_bonus` / `damage_reduction_pct`（数值 4）、`lifesteal_pct` / `low_hp_damage_bonus_pct`（背水/流派 3）。
- **slot_cost 恒 1** [占位]；**is_passive 恒 true**（主动/触发型遗物未设计）。

### 2.2 装备 `data/equipment/`（8 件，全 [占位] 骨架）

字段：`id` / `name` / `slot` / `tier` / `rarity` / `stats{}` / `description` / `_note`。

```json
{ "id":"eq_wpn_iron_sword", "name":"铁剑", "slot":"weapon", "tier":1,
  "rarity":"common", "stats":{"STR":2} }
{ "id":"eq_arm_tower_shield", "name":"塔盾", "slot":"armor", "tier":2,
  "rarity":"epic", "stats":{"DEF":5,"max_hp":10} }
```

- **slot**：`weapon` / `armor`（两槽 [已定]）。
- **tier**：整数 `1` / `2`（品阶，与 rarity 是**两个维度**——见 §10）。
- **stats 键**：`STR` / `DEF` / `RES` / `max_hp` / `hit` 等（ADR-005 属性 + 派生量），值 flat 整数 [占位]。**未接引擎**（`run_manager.gd:412` 明注 equipment 未接 stats）。

### 2.3 消费点（GDScript）

- `reward_resolver.gd`：装备/遗物按品质权重（rarity 分桶）入 convoy / 角色槽。
- `run_state.gd`：`party` 每角色 `relics≤6`（`RELIC_SLOT_MAX=6`）+ `equipment{weapon,armor}`；`convoy` 大背包。
- **缺口**：`relics-system.md` / `equipment.md` KB 正式规格未落地；遗物/装备**效果执行器未建**（effects/stats 声明式占位）。

---

## 3. KB 真源定位（三态）

| 事实 | 状态 | 出处 |
|---|---|---|
| L4 装备 = 武器+防具**两槽**、**非 build-defining**、run-reset、随机捡到 | **[已定]** consensus_locked | architecture-consensus-v2.md:37 / run-loop.md:184 |
| L5 遗物 Relic = **6 槽/角色硬上限**、**build-defining**、经济类+流派类两 archetype、L1 起始赠 1 遗物 | **[已定]** consensus_locked | architecture-consensus-v2.md:38,173-177 |
| Relic 为正典、Rune 废案；数据层 `data/relics/`、`RewardDrop.kind="relic"`、无 `rune` | **[已定]** ADR-010 | adr-2026-07-02 |
| 遗物来源 = Relic door / shop / Events / Boss 特殊 Relic；池 **20+ 起**（用户预期下限） | **[已定]** 意图 / 规模 [占位] | run-loop.md:186 |
| 装备 = 渐进品阶、更高品阶替换、run-reset | **[已定]** | run-loop.md:184,196 |
| D4 装备词缀体系（9 武器+4 防具 type / 4 tier / 5 词缀大类 / 单词缀 ≤±15% 或 ≤1 触发 / 50 模板 / 装备+词缀 JSON schema 草案） | **[提案]** stage2，**从未转 locked** | D4-equipment-affix.md |
| 遗物 rarity tier 是否设计 / reroll / 获取 cost curve / 流派类遗物 vs 流派类 L2 节点冲突 | **[缺口]** D5 open question 未执行 | architecture-consensus-v2.md:190 |
| `relics-system.md`（Δ-2）/ `equipment.md`（Δ-3）正式规格 | **[缺口]** 从未落地 | architecture-consensus-v2.md:109-121 |
| 装备 4 槽 Demo（Main Hand / Off Hand 剑圣双持 / Armor / Accessory-TBD） | **[冲突]** 与两槽定稿不一致 | class-system.md:448-455 |

---

## 4. 业界研究提炼 + 对抗验证警示

三条业界研究（roguelite 遗物 / 战棋装备 / 数据 schema）各经对抗验证（game-critic）。三条 critic 判定均为 **Hold（有条件保留）**——基础字段层可采纳，但有以下**必须吸收的警示**：

| 警示 | 来源 | 已采纳到字段规格的做法 |
|---|---|---|
| **声明式 effects 数组「包打天下」被证伪**——Slay the Spire 每遗物是独立 Java 类、Hades 是过程式 Lua，JSON 只承载展示文本 | R3 critic | `effects[].type` 用**开放 string**（非闭枚举）= **脚本逃生舱口**：新机制 = 新 type + 新 GDScript 执行器，schema 不锁死 |
| **即时制 proc coefficient / 秒 duration 不可照搬**——战棋每回合每单位仅 1-2 次判定，样本量小两个数量级，套用会变「要么不触发要么单次巨量」 | R1 critic | trigger 若结构化，只用**回合制词表**（`on_turn_start`/`on_attack`/`on_kill`/`on_damage_taken`），**禁 proc coefficient / 秒 duration** |
| **业界对 build-defining 遗物侧覆盖不足**——取样偏动作 roguelite / 持久战役制战棋，缺回合制多角色队伍类先例（如 Into the Breach） | R1/R2 critic | 遗物字段结论**不搬装备侧「纯升级」思路**；触发/协同/叠加字段全列 [提案] 待裁决，不擅自定 |
| **「武器三角 SoT 已拒绝」是过度断言**——实为 park 候选未经用户裁决 | R2 critic | 本文一律标 [park 候选]，不写「已拒绝」 |
| **槽位模型（6 遗物槽 + 2 装备槽）已由用户裁决**，业界「shared pool 优于固定槽」建议不重开 | R3 critic | 槽位结构按 KB [已定]，不列为 open question |
| **稀有度/池权重解耦在 20+ 小池下可能过度设计** | R3 critic | 建议先用 `rarity` 分桶（`reward_resolver` 现状）跑通，独立 `pool_weight` 列为 [提案] 按需 |

---

## 5. ★遗物字段规格结论

> 图例：层 = 叙述层 / 引擎镜像层 / 派生列 / 元数据 / 状态；归属 = `Godot权威→镜像` / `设计库可编辑` / `设计库自动派生`。

### 5.1 核心字段（建议 v1 采纳）

| 字段 | 类型 | 层 | 归属 | 三态 | 说明 |
|---|---|---|---|---|---|
| `id` | str PK（`relic_*`） | 元数据 | 设计库可编辑 | **[已定]** | 稳定 join key；**无职业前缀**→ 库内外 id 一致、回填**无需**前缀映射（比 skill 简单） |
| `name` | str（中文名） | 叙述层 | 设计库可编辑 | **[已定]** | 导出/回填时作权威 name 注入 engine_json |
| `description` | str（中文描述） | 叙述层 | 设计库可编辑 | **[已定]** | ⚠含内嵌数字（如「20%」）与 engine_json 数值是两处表述，须人工随回填对齐 |
| `rarity` | enum 中文（普通/稀有/史诗/传奇） | 叙述层 | 设计库可编辑 | **[已定]** 维度 / 每件归类 [占位] | 复用现有 `Rarity` 枚举；与引擎英文 rarity 分离（两 taxonomy） |
| `archetype` | enum 中文（经济类/流派类）**[新增枚举]** | 叙述层 | 设计库可编辑 | **[已定]** 两原型 locked / 分类法 open | KB 定两原型；但引擎用三分（economy/stat/build）→ **§10 待裁决** |
| `trigger` | str（生效时机文本） | 叙述层 | 设计库可编辑 | **[已定]** | 自由文本，照 Talent/Skill 现模式；是否升级结构化 timing 枚举 = open |
| `notes` | str | 叙述层 | 设计库可编辑 | **[已定]** | 备注 |
| `engine_json` | str（Godot 引擎块**只读镜像**） | 引擎镜像层 | **Godot权威→镜像** | **[已定]** 纪律 / schema [提案] | ★照 **Talent 只读**（不进 `RelicIn/RelicPatch` 写模型）；Godot `data/relics` 格式未冻结→先 DEFER 不校验 |

### 5.2 派生列 / 状态 / 元数据（[提案] 按需，照 Talent 复用）

| 字段 | 层 | 归属 | 三态 | 说明 |
|---|---|---|---|---|
| `eng_rarity` / `eng_category` / `eng_slot_cost` / `eng_effect_count` | 派生列 | 设计库自动派生 | **[提案]** | 从 engine_json 拍平，供 SQL 过滤/离群初筛；仅在需查询时建。⚠`is_passive` 是 bool，`_as_int` 排除 bool，若需列须另写降级——建议先不拍平 |
| `tags` | 关联（新增 `relic_tag` 表） | 设计库可编辑 | **[提案]** | 复用 Tag 表；承载机制轴/流派轴筛选；遗物是 build-defining，标签价值高于装备 |
| `status`（草稿/待审阅/锁定/待优化） | 状态 | 设计库可编辑 | **[提案]** | 是否给遗物做审阅工作流待定 |
| `shelf_state` / `trashed_at` | 状态 | 设计库自动派生 | **[提案]** | 上架/回收站正交，照 Talent 软删 |
| `updated_at` / `updated_by` | 元数据 | 设计库自动派生 | **[提案]** | 自动时间戳 + CF Access 身份 |

### 5.3 提案候选字段（放 engine_json 内，待裁决）

| 字段 | 层 | 三态 | 说明 |
|---|---|---|---|
| `unique`（bool） | 引擎镜像 | **[提案]**（缺口） | KB 零规定；「每角色独立掉落×4」下「唯一」语义歧义（跨角色互斥 vs 单角色池内）→ §10 |
| `stackable`（none/count/upgrade） | 引擎镜像 | **[提案]**（缺口） | KB 零规定；取值与上限须裁决 |
| `pool_weight`（int） | 引擎镜像 | **[提案]** | 独立掉落权重；20+ 小池下建议先用 rarity 分桶 |

---

## 6. ★装备字段规格结论

### 6.1 核心字段（建议 v1 采纳）

| 字段 | 类型 | 层 | 归属 | 三态 | 说明 |
|---|---|---|---|---|---|
| `id` | str PK（`eq_wpn_*`/`eq_arm_*`） | 元数据 | 设计库可编辑 | **[已定]** | 无职业前缀，直接作回填对齐键 |
| `name` | str（中文名） | 叙述层 | 设计库可编辑 | **[已定]** | |
| `description` | str（中文描述） | 叙述层 | 设计库可编辑 | **[已定]** | |
| `slot` | enum 中文（武器/防具）**[新增枚举]** | 叙述层 | 设计库可编辑 | **[已定]** 两槽 | ⚠ accessory/off-hand（剑圣双持）4 槽 Demo 未收敛 → §10 |
| `rarity` | enum 中文（普通/稀有/史诗/传奇） | 叙述层 | 设计库可编辑 | **[已定]** 维度 / 归类 [占位] | 复用 `Rarity`；供 `reward_resolver` 品质加权抽取 |
| `notes` | str | 叙述层 | 设计库可编辑 | **[已定]** | |
| `engine_json` | str（Godot 引擎块**只读镜像**） | 引擎镜像层 | **Godot权威→镜像** | **[已定]** 纪律 / schema [提案] | ★照 Talent 只读；含 `slot`(en)/`tier`(int)/`rarity`(en)/`stats{}`；stats 现未接引擎 |

### 6.2 派生列 / 状态 / 元数据（[提案] 按需）

| 字段 | 层 | 三态 | 说明 |
|---|---|---|---|
| `eng_slot` / `eng_tier` / `eng_rarity` | 派生列 | **[提案]** | 供槽位/品阶/品质筛选排序 |
| `eng_stat_total` | 派生列 | **[提案]** | `sum(stats.values())` 粗功率镜像，供跨 tier 数值离群初筛；stats 键动态不宜逐键拍平（脆弱），仅派生一个聚合列 |
| `tags` / `status` / `shelf_state` / `trashed_at` / `updated_*` | 关联/状态/元数据 | **[提案]** | 照 Talent 复用；装备非 build-defining，标签需求弱于遗物 |

### 6.3 提案候选字段（放 engine_json 内，待裁决）

| 字段 | 三态 | 说明 |
|---|---|---|
| `affixes`（array） | **[提案]**（D4 未采纳） | D4 完整词缀体系从未 locked。⚠**澄清**：`data/affixes/` 目录是**敌人词条**系统（`af_`/`afs_` 前缀，run-loop 敌人分层），**与装备词缀无关**。是否引入 + 深度上限 → §10 |
| `requirements`（object：职业/等级限制） | **[提案]** | v0 无限制、KB 未规定；剑圣双持 off-hand 若保留会引入职业专属槽 → 与装备槽收敛绑定 |
| `tier` 归属 | **[已定]** 品阶方向 / 阈值 [占位] | tier 数值层在 engine_json（Godot 权威）；叙述层是否也暴露 tier 见 §10 品质维度对称问题 |

---

## 7. engine_json schema 草图

> 照 `godot_export.GODOT_SKILL_SCHEMA` 风格，对齐已核 `data/relics` / `data/equipment` 真实格式。
> **纪律**：只读镜像；Godot 格式未冻结 → 先 **DEFER 不校验**（照 Talent），待格式定稿再启用全路径 fail-closed 校验门。

### 7.1 GODOT_RELIC_SCHEMA（草图）

```jsonc
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["rarity", "category", "slot_cost", "effects", "is_passive"],
  "properties": {
    "id": {"type": "string"},          // 可选；build_godot_relic 由行注入权威 id
    "name": {"type": "string"},        // 可选；注入权威 name
    "description": {"type": "string"},
    "rarity": {"enum": ["common", "rare", "epic", "legendary"]},  // 核心枚举严格；legendary 现悬空 [占位]
    "category": {"enum": ["economy", "stat", "build"]},           // ⚠ 三分法；改两原型待裁决
    "slot_cost": {"type": "integer", "minimum": 0},               // v0 恒 1 [占位]
    "is_passive": {"type": "boolean"},                            // v0 恒 true；主动遗物未设计
    "effects": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["type"],
        "properties": {
          "type": {"type": "string"},      // ★开放 string 非闭枚举 = 逃生舱口：新机制 = 新 type + 新执行器
          "value": {"type": "number"},
          "stat_key": {"type": "string"}   // 仅 stat_flat 携带（ADR-005 属性键）
        },
        "additionalProperties": {"type": ["integer", "number", "boolean", "string"]}
      }
    }
  },
  "additionalProperties": {"type": ["integer", "number", "boolean", "string"]}
}
// 提案（待裁决）可选顶层字段：
//   "unique": boolean / "stackable": {enum: ["none","count","upgrade"]}
//   "trigger": {enum: ["on_turn_start","on_attack","on_kill","on_damage_taken"]}（回合制词表，⚠禁 proc coefficient/秒 duration）
//   "pool_weight": integer
```

### 7.2 GODOT_EQUIPMENT_SCHEMA（草图）

```jsonc
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["slot", "tier", "rarity", "stats"],
  "properties": {
    "id": {"type": "string"}, "name": {"type": "string"}, "description": {"type": "string"},
    "slot": {"enum": ["weapon", "armor"]},                       // 两槽定稿；accessory/off-hand 待裁决
    "tier": {"type": "integer", "minimum": 1},                   // 品阶方向已定 / 阈值 [占位]
    "rarity": {"enum": ["common", "rare", "epic", "legendary"]}, // legendary 现悬空 [占位]
    "stats": {
      "type": "object",
      "propertyNames": {"enum": ["STR","MAG","DEX","DEF","RES","SPD","LCK","MOV","VIS","max_hp","hit"]},
      "additionalProperties": {"type": "integer"}               // 值 flat 整数 [占位]
    }
  },
  "additionalProperties": {"type": ["integer", "number", "boolean", "string"]}
}
// 提案（待裁决）：
//   "affixes": array（装备词缀，D4 未采纳；与敌人 data/affixes 词条无关）
//   "requirements": object（职业/等级限制）
```

---

## 8. 数据流（单向回填闭环）

```
        ┌─────────────────────────── 单一权威源 ───────────────────────────┐
        │  Godot 仓  data/relics/*.json  +  data/equipment/*.json           │
        │  （effects / stats / slot / tier / rarity / slot_cost / category  │
        │    / is_passive 全由引擎权威定）                                    │
        └───────────────┬──────────────────────────────────────────────────┘
                        │  ① snapshot（仅开发机，有 Godot 仓）
                        │     读 → 逐块 GODOT_RELIC/EQUIPMENT_SCHEMA 校验（fail-closed）
                        ▼
        seed/relic_mirror.json  +  equipment_mirror.json  （随仓分发的只读镜像快照）
                        │  ② apply（NAS/本地均可，无需 Godot 仓）
                        │     update-only 幂等灌 engine_json + eng_* 派生列
                        │     覆盖 stale / 行缺失只报 not_found 不新建 / 非法块跳过
                        ▼
   ┌───────────────────────────── 设计库 ─────────────────────────────┐
   │  relic 表 / equipment 表                                          │
   │  · engine_json = 只读镜像（照 Talent，不进写模型）★本方不手编       │
   │  · 叙述层（name/description/rarity 标注/archetype/slot/trigger/    │
   │    tag/status）= 设计库 CRUD 直接维护（写门 require_token）        │
   └──────────────────────────────────────────────────────────────────┘

★ 无「设计库 → Godot」数值写回路径：叙述若需引擎数值化，
  由 Godot 侧新建/更新 data/relics|equipment（引擎权威）后再回填，闭环单向。
★ 引擎层（英文 rarity/category/slot）与叙述层（中文 Rarity/archetype/slot）
  是两套独立 taxonomy，刻意分离、不互转不互校验（照 damage_type 中英分离先例）。
```

---

## 9. 设计库软件改动面（供 Mercury 参考，本方不实装）

| 环节 | 改动 |
|---|---|
| **建表** `models.py` | 新增 `class Relic` + `class Equipment`（照 Skill/Talent）。★两表**省略 `class_id` 与 `game_class` 关系**（遗物全局掉落池、装备非职业锁）——待用户确认（§10）。新增 `relic_tag` / `equipment_tag` 关联表 + `Tag.relics`/`Tag.equipment` 反向关系。engine_json 照 Talent 只读。 |
| **枚举** | 复用：`Rarity` / `TalentStatus` / `ShelfState`。新建：`RelicArchetype`(经济类/流派类，[提案] 两分 vs 三分)、`EquipSlot`(武器/防具，[已定])。可选：`RelicStackRule`([提案])。遗物/装备**均不设 `DamageType`**（遗物是 effects 修饰、装备是纯 stats）。 |
| **API** | 新建 `api/relics.py` + `api/equipment.py`，各照 `talents.py` 五路由（list/get/create/patch/delete）。写路由挂 `require_token`；DELETE 照 Talent 软删。★engine_json **不进 In/Patch 写模型，仅 Out 只读暴露**。 |
| **校验** | 新建 `validation/relic_export.py` + `equipment_export.py`（照 `godot_export.py`）。但按纪律 engine_json 是只读镜像且格式未冻结 → **先 DEFER**（不校验、不进写模型），待 Godot 定稿再补 fail-closed 校验门。 |
| **模板** | `relics.html` + `equipment.html`（照 `skills.html`）。★engine_json 照 `talent_detail.html` 做**只读展示灰框**，不做可编辑 textarea。 |
| **回填** | `backfill_engine.py` 参数化实体类型（skill/relic/equipment 各自 schema/目标表/镜像文件），或复制 `backfill_relic.py`/`backfill_equipment.py`。★遗物/装备 id **无职业前缀 → 无需 `_design_skill_id` 前缀替换**（比 skill 简单）。`db.py` 启动迁移登记新表/新列/索引/派生列回填（否则 NAS `codex.db` 运行时 `no such column`）。 |

---

## 10. ★需用户裁决的结构级问题（附 grounded 推荐）

> 参数级数字一律 [占位] 自行推进；下列**结构级**冲突属设计裁决，需用户拍板。每条给出我的 grounded 推荐（带真源出处）。

| # | 结构级问题 | grounded 推荐 |
|---|---|---|
| **Q1** | **遗物是否绑职业？** | **推荐：全局掉落池，不绑职业**（省 `class_id`）。KB「每角色独立掉落」指各角色独立**持有槽**，遗物本身任意角色可持。设计库现有实体全有 class_id，遗物是首个全局实体。 |
| **Q2** | **遗物 archetype 分类法采几分？** 引擎用**三分**（economy/stat/build），KB 定**两原型**（经济类/流派类）。 | **推荐：需统一为一套 canonical**。倾向把 `stat` 归入相应原型（纯属性→经济类语义 or 独立），或把三分正式写进 KB。此冲突不解决，叙述层 archetype 与引擎 category 会长期错位。 |
| **Q3** | **稀有度词表统一**。四套未收敛：引擎 `common/rare/epic/legendary`、run-loop RewardDrop、D4 `Common/Uncommon/Rare/Unique`、D5 `Common/Rare/Mythic`。 | **推荐：定一套 canonical**（叙述层中文 + 引擎层英文各自命名 + 对齐映射）。倾向以**引擎现值** `common/rare/epic/legendary` 为准（v0 已用），把 D4/D5 的其他命名归档。 |
| **Q4** | **遗物 unique / stackable 规则**是否设计、如何取值？KB 零规定。且「每角色独立掉落×4」下「唯一」语义歧义（跨 4 角色互斥 vs 单角色池内互斥）。 | **推荐：v1 先不做**（KB 无要求）；若做，先明确「唯一」的作用域。属引擎抽取逻辑 → 放 engine_json。 |
| **Q5** | **遗物是否升级为结构化 `trigger_timing` 枚举**（还是维持自由文本 trigger）？v0 遗物全 `is_passive:true`，是否设计主动/触发型遗物？ | **推荐：v1 维持自由文本 trigger**；若引入触发型，只用回合制词表（`on_turn_start`/`on_attack`/`on_kill`/`on_damage_taken`），**禁即时制 proc coefficient**（R1 critic）。 |
| **Q6** | **装备是否引入 affix/词缀维度？** D4 提案（5 大类/单词缀≤±15%或≤1 触发/4 tier/50 模板）从未 locked；引擎现只有 `stats{}`。 | **推荐：v1 维持纯 stats 加值**（不引入 affix）。装备非 build-defining，纯品阶替换够用；affix 是显著复杂度，等玩法验证需要再引入。 |
| **Q7** | **装备槽收敛**。两槽（武器+防具，run-loop 定稿）vs class-system 4 槽 Demo（含 off-hand 剑圣双持 / accessory-TBD）。 | **推荐：以两槽定稿为准**（更晚、更权威）；剑圣双持若保留，作为**职业专属特例**单独处理，不进通用 EquipSlot 枚举。需用户确认 class-system 4 槽 Demo 是否作废。 |
| **Q8** | **遗物/装备品质维度是否对称？** 现状遗物只 `rarity`、装备 `rarity`+`tier` 两维。 | **推荐：保持非对称**（遗物按稀有度、装备按品阶+稀有度）——契合「装备渐进品阶替换 vs 遗物按稀有度构筑」的不同定位。或统一，需裁决。 |
| **Q9** | **遗物掉落权重模型**：每遗物独立 `pool_weight` vs「rarity 即权重」简单模型？ | **推荐：先用 rarity 分桶**（`reward_resolver` 现状）跑通；20+ 小池下独立 pool_weight 可能过度设计（R3 critic）。 |

---

## 11. 占位清单（所有 [占位] 数字）

- 遗物 `rarity` 每件归类（common/rare/epic/legendary）— 每件 `_note` 标 rarity 待调
- 遗物 `slot_cost` 全为 1 — 槽位经济学未设计（relics-system.md 缺口）
- 遗物 `effects[].value` 全部数值：`gold_gain_pct 20` / `lifesteal_pct 25` / `low_hp_damage_bonus_pct 40` / `stat_flat DEF+3` / `LCK+4` / `crit_bonus 10` / `move_bonus 1` / `talent_point_bonus 1` / `exp_gain_pct 15` / `damage_reduction_pct 15` — 纯填坑待调（9 类效果均无执行器）
- 遗物初始池规模 — run-loop.md:186「20+ 起」为已定意图、确切规模占位；引擎现仅 10 件骨架
- 遗物保底 N=3（按出现计数） — run-loop.md:137,417（1000 幕模拟示偏紧待调）
- 装备 `tier` 阈值与数值锚点（class-system Early +2~4 … Endgame +12~18） — 品阶方向已定、数值待调
- 装备 `rarity` 每件归类 — 用于品质加权抽取
- 装备 `stats` 数值（`{STR:2}` / `{DEF:4,RES:1}` / `{DEF:5,max_hp:10}` 等） — 声明式、未接引擎
- 门奖励品质权重 / 商店定价 / Boss 包 forced_rarity — act1_config.json
- **legendary 稀有度池悬空**：`data/relics/` 与 `data/equipment/` 均无 legendary 条目，但 Boss `forced_rarity` + 商店定价引用 legendary → 抽取会回退 — 需补 legendary 池或明确该档暂空
- （若采纳）遗物 `pool_weight` / `stackable` 计数上限 / 装备 `affix` 词缀数值 — 占位

---

*研究方法：内部深读（设计库承载模式 / SoT v0 数据 / KB 真源）+ 业界研究（roguelite 遗物 / 战棋装备 / 数据 schema，各经 game-critic 对抗验证）→ 综合。10 agent，约 60 万 token。主代理独立核对 KB 真源（architecture-consensus-v2 / ADR-010 / D4 / run-loop）后定稿。*
