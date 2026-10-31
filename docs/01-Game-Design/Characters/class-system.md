# 05 - 职业系统

> 正本：设计库规则表（生产 `/rules` 页）+ [[../rules-catalog|规则总目录]]；本章「属性档位标尺与剑士线标定」节为剑士线成长标定权威。

> 返回 [[./README.md|概览]]

## 概览

8 个基础职业，每个各有 2 条转职（Class Advancement）路线。职业决定基础属性、武器限制与初始技能。成长通过 **天赋树（Talent Tree）**（每局 Run 重置）+ **随机奖励**（装备 / 遗物 / 额外技能）实现，以此构建 build 多样性。

转职在 **Lv5** 触发——转职是等级事件，本身不消耗天赋点（详见 [[talent-tree|天赋树系统]]）；一旦选定，不可更改。下位职业的技能与天赋默认同时属于其上位职业；上位职业专属的技能与天赋仅属该上位职业（规则表 R2.4）。

---

## 职业数据结构（Class Data Structure）

```
Class:
  id: String
  name: String
  base_stats: UnitStats
  stat_growth: UnitStats            # Per-stat growth RATES（概率成长百分比；ADR-005 / 规则表 R2.2）
  innate_skills: Array[String]      # Starting skill IDs
  equip_types: Array[String]        # Equippable weapon/armor types
  class_tags: Array[String]         # Class tags (used for building occupation checks, etc.)
  move_type: "foot" | "armored" | "mounted"
  advancement: Array[AdvancedClass] # Class Advancement paths
```

---

## v1 测试职业 - 5

以下 5 个职业用于 v1 阶段，测试核心战斗数值与机制：

| 职业 | 测试覆盖范围 |
|-------|--------------|
| Soldier | 物理伤害、近战 / 远程混合、均衡属性基线 |
| Archer | 远程物理、暴击 / 命中、射程机制 |
| Mage | 魔法伤害、AOE、元素效果 |
| Knight | 物理防御、耐久、嘲讽机制 |
| Cleric | 治疗、纯粹伤害（pure）、辅助机制 |

*Myrmidon、Artificer、Hunter 将在 v1 核心机制验证后加入。*

---

## 全部职业 - 8 基础 + 16 进阶

### Myrmidon

| 属性 | 说明 |
|-----------|-------------|
| 核心定位 | 高机动近战；暴击 / 速度 / 闪避型；速度转化为出手顺序优势（R3.1） |
| 武器限制 | **仅剑（Swords only）** |
| 属性倾向 | 高命中、暴击、速度；防御偏弱，但擅长闪避（2026-10-28 用户裁决） |
| 初始技能 | 斩击 / 一闪 / 招架 / 居合 / 心眼（剑气资源引擎;拔刀与印记系统为剑圣转职专属,R2.4） |
| 攻击射程 | 近战（1 格） |

**转职路线**：

| 进阶职业 | 方向 | 核心变化 |
|----------------|-----------|--------------|
| **Kensei** | 物理专精 | 极致暴击与速度 |
| **Sword Immortal**（剑仙） | 物理 + 魔法混合 | 契约飞剑（远程混合攻击）；剑气槽（类 MP，与剑士线共享）；剑阵领域控场；后期成长强力 |

> **运行状态**：Ship 已有剑气、印记和剑士线技能的早期底座，但尚未实现当前设计库中的剑圣〔招架〕、新版〔心眼〕和本批回忆升级。设计事实以设计库为准，Ship 现有 JSON 只代表待迁移的运行事实；本阶段不据此反向修改设计。
>
> **剑士〔心眼〕是技能实体 `myrmidon_xinyan`**：每拥有 20 点剑气，暴击 +1；剑气每比 100 点少 40 点，速度 +1（现行文字以设计库为准）。剑士有斩击 / 一闪 / 招架 / 居合 / 心眼；剑圣对这五个技能各有同名条目（`kensei_*`），结算可以与剑士版不同（如〔招架〕），另有专属的拔刀。技能以“职业 + 技能”定位，见 [[00-rules/skill-design-principles|技能设计要点]] §7。
>
> **剑圣另有同名技能实体 `kensei_xinyan`**：每拥有 20 点剑气，暴击 +1；剑气每比 100 点少 40 点，速度 +1；每枚〔心〕、〔道〕、〔势〕分别使技巧、速度、力量提高 10%。这些加成由技能读取，印记资源本身不通用地提供属性。同名技能以 `class_id` 区分。当前回忆升级及未完成范围见 [[kensei-memory-upgrades|剑圣回忆升级]]。

---

### Mercenary

| 属性 | 说明 |
|-----------|-------------|
| 核心定位 | 全能均衡型物理战士，可近战 / 远程 |
| 武器限制 | **除魔法武器外全部可用**（剑 / 斧 / 枪 / 弓 / 弩等） |
| 属性倾向 | 除魔法外各项均衡，无明显短板 |
| 初始技能 | Power Strike、Throw（远程物理单体） |
| 攻击射程 | 取决于所装备武器 |

**转职路线**：

| 进阶职业 | 方向 | 核心变化 |
|----------------|-----------|--------------|
| **Champion** | 单体作战强化 | 全属性进一步提升；单挑作战能力强化 |
| **Tactician** | 光环辅助 | 获得增益光环，为自身与周围友军提供属性加成 |

---

### Archer

| 属性 | 说明 |
|-----------|-------------|
| 核心定位 | 纯远程物理输出 |
| 武器限制 | **弓（Bows）** |
| 属性倾向 | 高暴击，速度与闪避尚可；防御低；命中平庸（需天赋树 / 技能补足） |
| 初始技能 | Shot、Aim（大幅提升下次攻击的命中与暴击） |
| 攻击射程 | 远程（**无法近战**） |

**转职路线**：

| 进阶职业 | 方向 | 核心变化 |
|----------------|-----------|--------------|
| **Sniper** | 超远射程 / 高伤害 | 射程由技能 / 天赋 / 遗物声明（R1.7）；高伤害输出 |
| **Elven Archer** | 可近战 / 附魔箭 / 闪避 | 解锁近战能力；箭矢附魔减益；高闪避可抗打 |

---

### Artificer

| 属性 | 说明 |
|-----------|-------------|
| 核心定位 | 建筑操作 / 战场控制，非直接战斗型 |
| 武器限制 | （待定 TBD） |
| 属性倾向 | 个人战斗能力弱；核心价值在战场控制 |
| 初始技能 | Repair（恢复建筑耐久 Building Durability）、Temporary Enhancement（为建筑添加临时效果） |
| 特殊能力 | 可在战斗中修复建筑并为战斗建筑添加临时效果 |

**转职路线**：

| 进阶职业 | 方向 | 核心变化 |
|----------------|-----------|--------------|
| **Engineer** | 建筑强化 / 收益 | 进一步强化战斗建筑；可建造临时收益建筑（金币 / 经验 / 随机装备） |
| **Inventor** | 机甲召唤 / 前线作战 | 可建造特殊战斗建筑：机甲；用天赋与附加效果强化机甲进行前线作战 |

---

### Mage

| 属性 | 说明 |
|-----------|-------------|
| 核心定位 | 三系元素魔法（火 / 冰 / 风），高伤害 + 魔法效果 |
| 武器限制 | **魔法武器（Magic weapons）**（法杖 / 魔法媒介等） |
| 属性倾向 | 高魔法攻击；低 HP / 物理防御 / 移动力 |
| 初始技能 | Fireball、Frost |
| 攻击射程 | 可近战可远程（取决于技能） |

**元素系统 - 三源互斥**：

Mage 天赋树包含 3 个元素起源节点（火 / 冰 / 风）。解锁一个起源会**锁死**另外两个（互斥）。每个元素有各自的能量槽、技能组与战术定位。

| 元素 | 战术定位 | 能量槽 |
|---------|-------------------|-------|
| **火（Fire）** | AOE 爆发、灼烧 DOT、持续高温 | Hellfire（能量 0-100） |
| **冰（Ice）** | 控制、减速 / 冰冻、区域封锁 | Frost（能量 0-100） |
| **风（Air）** | 机动、速度操控、连锁打击 | Gale（能量 0-100） |

**转职路线 - 两个方向**：

| 进阶职业 | 方向 | 核心变化 |
|----------------|-----------|--------------|
| **Grand Sage**（大贤者） | 多元素掌控 | 解除元素互斥——解锁第二个元素起源。更广但更浅；可混用两套元素套件 |
| **Element Sage**（X之贤者） | 单元素极致 | 永久锁定所选元素。更深度专精；解锁该元素的终极层能力 |

> 详细的能量槽设计见 mage-talent-tree-design-brief；法师三元素槽的总览见 [[talent-tree|天赋树系统]] §计量槽系统。

---

### Knight

| 属性 | 说明 |
|-----------|-------------|
| 核心定位 | 物理防御核心，嘲讽 / 耐久专家 |
| 武器限制 | 近战武器 + **可装备盾牌**（盾牌可携带偏减伤向的特殊效果） |
| 属性倾向 | 高 HP / 物理防御；低速度 / 魔法防御 |
| 初始技能 | Shield Bash、Provoke（嘲讽周围敌人） |
| 天赋互斥 | 骑乘（高机动）vs 重甲 + 盾（高防御），二选一——不能同时选 |

**转职路线**：

| 进阶职业 | 方向 | 核心变化 |
|----------------|-----------|--------------|
| **Paladin** | 魔法防御 / 治疗 / 增益 | 弥补魔法防御短板；获得友军治疗与增益能力 |
| **Heavy Knight** | 极致物理防御 / 嘲讽 / 反伤 | 物理抗性进一步提升；主动吸引敌方攻击；被击中时反伤敌人 |

---

### Hunter

| 属性 | 说明 |
|-----------|-------------|
| 核心定位 | 近战 / 远程混合，灵活应对 |
| 武器限制 | **弓 + 近战武器** |
| 属性倾向 | 高闪避 / 魔法抗性；速度尚可；攻击 / 防御平庸 |
| 初始技能 | Shot、Close Slash |
| 攻击射程 | 可近战可远程 |

**转职路线**：

| 进阶职业 | 方向 | 核心变化 |
|----------------|-----------|--------------|
| **Beast Master** | 宠物协同 | 获得专属宠物；指挥宠物进行协同攻击 |
| **Survivalist** | 陷阱 / 闪避 / 魔法抗性 | 布置陷阱限制敌人；高闪避 + 魔法抗性以牵制特定敌人 |

---

### Priest

| 属性 | 说明 |
|-----------|-------------|
| 核心定位 | 治疗核心，基础魔法攻击 |
| 武器限制 | **法杖（Staves）** |
| 属性倾向 | 高魔法防御 / 状态抗性；低物理攻击 / 物理防御；魔法攻击平庸 |
| 初始技能 | Heal、Holy Bolt（纯粹伤害 pure，单体） |
| 攻击射程 | 主要远程 |

**转职路线**：

| 进阶职业 | 方向 | 核心变化 |
|----------------|-----------|--------------|
| **High Priest** | AOE 治疗 + 次级伤害 | AOE 治疗与伤害；特殊机制允许每回合同时输出伤害与治疗 |
| **Zealot** | 放弃治疗 / 纯粹伤害 | 放弃治疗能力；获得无视防御的纯粹伤害（pure），稳定高效输出 |

---

## Build 构成（Build Composition）

一个角色的 build 由以下要素构成：

```
UnitBuild:
  class: Class                     # Base class
  advanced_class: AdvancedClass | null  # Post-advancement class (null if not advanced)
  level: int                       # Current level
  talent_tree: TalentTreeState     # Talent Tree state (reset each Run)
  active_skills: Array[Skill]      # Active skill slots (talent unlocks + random acquisition)
  passive_effects: Array[Passive]  # Passive effects (unlocked via Talent Tree)
  weapon: Weapon                   # Weapon
  armor: Armor                     # Armor
  relics: Array[Relic]             # Relics (Roguelite random acquisition)
```

### Build 多样性来源

| 来源 | 类型 | 说明 |
|--------|------|-------------|
| 天赋树（Talent Tree） | 可控 | 每局 Run 重置，玩家自选路线。提供被动特性、核心技能、转职 |
| 随机技能奖励 | 半随机 | 战斗奖励 / 商店提供额外技能，扩展可用技能池 |
| 装备 | 半随机 | 武器 / 护甲两槽，影响属性与特殊效果 |
| 遗物（Relics） | 随机 | Roguelite 核心随机要素，提供独特被动效果 |

**天赋树 = 骨架**（决定角色方向与转职），**随机要素 = 血肉**（在骨架之上填充具体 build）。

同样是 Archer 转 Sniper，在不同 Run 中因获得不同遗物与技能，可形成截然不同的玩法。

### Build 中的行动资源规划

选择技能时，需考虑**行动资源分配**（见 [[turn-system|回合系统]]）。每回合通常有 1 次移动机会，并把标准行动点与迅捷行动点恢复到各自容量；两类行动点默认容量均为 1，允许由明确效果提高到 3。同类型技能仍争夺对应资源：

- 默认容量下，携带多个 \[Standard Action\] 技能仍需争夺 1 点标准行动点；容量提高后可在同回合支付多次
- 默认容量下，携带多个 \[Swift Action\] 技能仍需争夺 1 点迅捷行动点；容量提高后可在同回合支付多次
- \[Reaction Action\] 技能不消耗主动资源，是 build 深度的重要来源
- **健康的 build** 应在不同行动类型间均衡分布技能，而非把一切集中在 \[Standard Action\]

---

## Roguelite 原型（Archetype）映射

以下原型可通过不同的职业 + 天赋 + 随机要素组合实现：

| 原型 | 典型职业 | 核心机制 | 行动资源侧重 |
|-----------|----------------|----------------|----------------------|
| 单回合爆发伤害 | Kensei、Element Sage（火）、Zealot | 高倍率技能 / 蓄力 / 高冷却 | Swift Action buff 后接 Standard Action |
| 额外行动 | Myrmidon、Soldier | 特殊天赋 / 遗物在单回合内给予多次行动 | Standard Action x2（再行动） |
| 辅助增益机器 | Grand Sage、Tactician、High Priest | 增益友军以提升各乘区 | Swift Action buff 后接 Standard Action buff |
| 战略控制 | Engineer、Inventor、Survivalist | 建筑 / 陷阱 / 召唤物控场 | Move Action + Standard Action |
| 远程火炮 | Sniper | 超远射程，安全输出 | Swift Action 瞄准后接 Standard Action |
| 打了就跑 | Elven Archer、Hunter、Soldier | 攻击后移动，游击式作战 | Move Action + 基础攻击 |
| 防御 / 反伤 | Heavy Knight | 高防御 + 嘲讽 + 反伤 | Swift Action 防御 + Reaction Action |
| DOT / 减益 | Elven Archer、Element Sage（火 / 冰） | 附魔箭 / 灼烧 DOT / 冰冻控制 / 持续伤害 | Standard Action + Swift Action 附魔 |

---

## 升级与成长

角色在一局 Run 的战斗中获得经验并升级：

```
Level-up:
  each growable stat: if random() < growth_rate[stat] → stat += 1   # 概率成长 + pity 保底（ADR-005 / 规则表 R2.2）
  Gain talent points (used to unlock nodes in the Talent Tree)
```

- 预期一局(Run)结束时人物等级 **25-30**（3 幕 × 8 关模型）
- LCK / MOV 为固定属性，不随升级成长；其余七项（HP/STR/MAG/DEX/SPD/DEF/RES）按成长率概率成长
- stat_growth 可在转职后改变（进阶职业有自己的成长率）

### 属性档位标尺与剑士线标定

成长率档位**固定单值**（规则表 R2.3 唯一换算）：**C=40% / B=50% / A=60% / S=75%**；SS 不设更高单次率——每次升级以 S（75%）仅判定一次：成功 +2，失败保底 +1（期望 +1.75、每级恒 ≥+1，不参与 pity 计数）。不设弃轴档，最低档 = C。

| 属性 | 剑士 | 剑圣 | 剑仙 | 备注 |
|---|---|---|---|---|
| DEX | A（60%） | **S（75%）** | A（60%） | 全表唯一提至 S 档的属性 |
| HP | B（50%） | B（50%） | B（50%） | |
| STR | B（50%） | **A（60%）** | **A（60%）** | 剑圣 STR 于 2026-08-03 由 B 提至 A |
| DEF | B（50%） | B（50%） | B（50%） | |
| MAG | C（40%） | C（40%） | **A（60%）** | 剑仙走物理 + 魔法混合，MAG 与 STR 同档 |
| RES | C（40%） | C（40%） | **B（50%）** | 不设弃轴，最低 C |
| SPD | B（50%） | A（60%） | B（50%） | |
| LCK / MOV | 固定 | 固定 | 固定 | 不成长 |

剑圣 STR 由 B 提至 A、剑仙一列七项首次标定，均为 2026-08-03 用户裁决 [已定]。剑仙此前在设计库中属性档位为空白，本表为其首次成文标定。

Σ成长率（剑圣）= 3.75 → 每级平均 +3.75 属性点，升级全空概率约 0.36%（另有 pity 保底）；Σ成长率（剑仙）= 3.80 → 每级平均 +3.80 属性点，升级全空概率约 0.40%。各属性初始值均为占位待定。引擎侧剑圣数值在 `data/classes/kensei.json`（成长率 DEX 75 / HP 50 / **STR 60** / DEF 50 / SPD 60 / MAG 40 / RES 40，其中 STR 按 2026-08-03 裁决由 50 提至 60）。原先文件名与 `id` 为 `swordsman`、内容却是剑圣的错配，已于 2026-08-03 由提交 `2b5128c` 解决：职业 `id` 改为 `kensei`，剑士另建为 `data/classes/myrmidon.json`。上方「职业数据文件示例」按剑士列书写。

---

## 属性基线 - 1 级（Attribute Baseline - Level 1）

*以下是对齐 ADR-005 的 1 级基线，用于表达职业定位。数值仍待原型校准。当前可玩原型使用 Soldier/Archer/Mage/Knight/Cleric 作为其 5 个演示职业。*

| 属性 | Myrmidon | Mercenary | Archer | Artificer | Mage | Knight | Hunter | Cleric | 成长 |
|-----------|-----------|-----------|--------|-----------|------|--------|--------|--------|--------|
| HP | 90 | 100 | 75 | 80 | 65 | 120 | 85 | 70 | Yes |
| STR | 14 | 13 | 16 | 8 | 5 | 12 | 13 | 5 | Yes |
| MAG | 5 | 3 | 3 | 8 | 20 | 3 | 5 | 15 | Yes |
| DEX | 12 | 8 | 11 | 6 | 7 | 5 | 9 | 6 | Yes |
| SPD | 12 | 8 | 10 | 6 | 7 | 6 | 10 | 7 | Yes |
| LCK | 5 | 5 | 5 | 8 | 10 | 8 | 10 | 12 | No（固定） |
| DEF | 7 | 9 | 5 | 6 | 4 | 14 | 6 | 4 | Yes |
| RES | 5 | 6 | 5 | 7 | 10 | 5 | 9 | 12 | Yes |
| MOV | 3 | 3 | 3 | 3 | 2 | 3 | 4 | 2 | No |

**设计理据**：
- **Myrmidon**：高 SPD/DEX，暴击导向，DEF/RES 平庸，STR 适中
- **Mercenary / 当前原型 Soldier 位**：均衡 STR/DEX/DEF，无短板但也无极值
- **Archer**：高 STR/DEX，SPD 适中，DEF 低
- **Artificer**：直接战斗弱，较高 RES/LCK 以在前线建筑操作中生存
- **Mage**：极高 MAG，最低 HP/DEF，最低 MOV
- **Knight**：最高 HP/DEF，低 SPD/RES
- **Hunter**：高 SPD/RES，近战 / 远程混合
- **Cleric**：最高 RES/LCK，物理属性弱

---

## 反击系统（Counter-attack System）

任何单位不因受到攻击而进行反击，不存在反击类结算。受击方的对抗手段由反应类（Reaction）天赋 / 技能 / 遗物在各自条目内自行定义（反应动作不消耗主动资源，R3.2/R3.3）。

---

## 职业数据文件示例（Class Data File Example）

```json
{
  "id": "swordsman",
  "name": "Myrmidon",
  "base_stats": {
    "HP": 90, "STR": 14, "MAG": 5,
    "DEF": 7, "RES": 5,
    "DEX": 12, "SPD": 12, "LCK": 5,
    "MOV": 3
  },
  "growth_rates": {
    "HP": 50, "STR": 50, "MAG": 40,
    "DEF": 50, "RES": 40,
    "DEX": 60, "SPD": 50
  },
  "innate_skills": ["slash", "evasion_slash"],
  "equip_types": ["sword"],
  "class_tags": ["melee", "sword"],
  "move_type": "foot",
  "advancement": [
    {
      "id": "sword_saint",
      "name": "Kensei",
      "talent_node_id": "swordsman_adv_a",
      "growth_rates_override": {
        "STR": 60, "DEX": 75, "SPD": 60
      },
      "unlocked_tags": ["critical_master", "speed_chain"]
    },
    {
      "id": "sword_cultivator",
      "name": "Sword Immortal",
      "talent_node_id": "swordsman_adv_b",
      "growth_rates_override": {
        "STR": 60, "MAG": 60, "RES": 50
      },
      "unlocked_tags": ["hybrid_damage", "sword_essence"]
    }
  ]
}
```

---

## 装备系统 - Demo（Equipment System - Demo）

### 槽位结构（Slot Structure）

| 槽位 | 说明 | 通用 |
|------|-------------|-----------|
| 主手（双手武器） | 剑 / 弓 / 魔导书 | Yes - 每职业限用对应武器 |
| 副手 | **Kensei「二天一流」天赋开启**（失去防具槽、换副手武器槽），装备第二把武器 | No - Kensei 专属 |
| 护甲 | 提供防御 / HP / 抗性 | Yes |

> **通用槽位共两个：武器 + 护甲**（2026-08-09 用户裁决，与 run-loop 两槽定稿一致）。原先此表还有一行「饰品（各类效果，通用）」，其效果一直是 TBD、从未细化，现**作废**。副手不是第三个通用槽，它是 Kensei 的**职业专属特例**，不进通用槽位枚举。

> 武器参数框架见规则 R1.7：`weapon_might` / `weapon_hit` / `weapon_crit` 三项是武器的全部基础参数，武器不区分伤害类型、也不管理射程；射程归技能、天赋、遗物。各职业可装备的武器范围由专门条款规定。

### 双持 - Kensei 专属（Dual Wielding - Kensei Exclusive）

- **开启方式**：转职后通过 Kensei 天赋「二天一流」失去防具槽，并获得副手武器槽；双刀池其余天赋以它为硬前置。
- **状态边界**：〔双持〕表示角色当前确实同时装备主手与副手武器。它本身不提供额外加成，只作为其他效果的生效条件；装备条件失效时立即退出。因为它记录的是装备事实，不应被状态免疫抹除。
- **副手特效边界**：「二刀开刃」只让副手武器特效中能够按比例折算的部分生效；无法折算的离散部分不生效。仍可生效的部分沿用原特效的触发概率、触发时机、作用对象和每次触发次数，并禁止无明确说明的自循环或互相循环。
- **多人环境**：副手追加按命中的每个目标分别结算，并不沿用主手的溅射衰减。双刀在范围场景中收益显著，是已接受的构筑取向。
- **核心收益**：来自交刃、剑气回荡、燕返等双刀天赋形成的攻防循环，而不是单纯叠加两把武器的面板。
- **权威边界**：具体伤害、概率、资源数值、触发结构和 State 关系以设计库当前记录为准；本节只保存职业构筑意图和定性边界。

### 装备加成参考 - 按关卡进度（Equipment Bonus Reference - By Stage Progress）

| 阶段 | 武器 ATK 加成 | 护甲 DEF 加成 |
|-------|------------------|-----------------|
| 第 1 幕（stages 1-8） | +2~4 | +1~2 |
| 第 2 幕（stages 9-16） | +5~8 | +3~5 |
| 第 3 幕（stages 17-23） | +9~14 | +5~8 |
| 终局（stage 24 = 第 3 幕 Boss） | +12~18 | +7~10 |

> 关卡区间按现行 3 幕 × 8 关 = 24 关对齐；四档的**数值区间沿用原参考值、未重新标定** [占位]。

---

## 未来扩展 - 预留（Future Extensions - Reserved）

- **Astrologer**：将在引入昼夜系统时加入，随昼夜变化获得不同的技能效果
- **更多转职分支**：现有职业未来可能获得第 3、第 4 条转职路线
- **跨职业技能**：遗物 / 特殊事件可能允许获取其他职业的技能

---

相关文档：
- [[../Core-Systems/battle-calculation|战斗计算]] — 属性如何参与伤害 / 命中公式
- [[../skills-and-range|技能与射程]] — 技能定义与伤害类型
- [[talent-tree|天赋树系统]] — 天赋卡池、计量槽、等级与转职节奏
- [[../Progression/run-loop|Run 循环]] — 技能 / 遗物获取路径
