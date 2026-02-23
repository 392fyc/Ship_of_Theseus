# 11 - 城镇建设系统

> 返回 [总纲](./README.md)

## 概述

城镇建设是本游戏v1的核心差异化玩法。玩家在每个小关卡间的准备阶段，使用金币建造、升级和修复建筑。建筑分为两类：

- **功能建筑**：在准备阶段提供服务（商店、训练场等），不出现在战斗地图上
- **战场建筑**：放置在战斗地图上，在战斗中提供战术优势

所有建筑均可升级和扩建，使用统一货币（金币）。

---

## 功能建筑（准备阶段生效）

不出现在战斗地图上，在准备阶段为玩家提供服务。

| 建筑 | 功能 | 升级方向 |
|------|------|---------|
| 武器铺 | 购买/强化武器 | Lv1 基础武器 → Lv2 稀有武器 → Lv3 传说武器 |
| 防具铺 | 购买/强化防具 | Lv1 基础防具 → Lv2 稀有防具 → Lv3 传说防具 |
| 药剂铺 | 购买消耗品（回复/buff） | Lv1 基础药剂 → Lv2 高级药剂 → Lv3 稀有药剂 |
| 训练场 | 重置/更换/学习技能 | Lv1 更换技能 → Lv2 学习新技能 → Lv3 技能强化 |
| 酒馆 | 招募临时佣兵/获取情报 | （待定） |

---

## 战场建筑（战斗地图上生效）

### 建筑列表

#### 哨塔

| 属性 | 说明 |
|------|------|
| 类型 | 通用型（任何单位可占据） |
| 基础效果 | 占据者：命中率提升、视野提升、受到伤害轻微减少 |
| 联动伤害 | 占据者受到伤害时，哨塔也受到耐久损伤 |
| 摧毁后 | 失去建筑加成，格子变为废墟（不恢复基础地形效果） |
| 升级方向 | Lv1 → Lv2 加成提升 → Lv3 加成进一步提升 |

#### 要塞

| 属性 | 说明 |
|------|------|
| 类型 | 通用型 |
| 基础效果 | 占据者：命中率提升、视野提升、受到伤害**大幅**减少 |
| 联动伤害 | 占据者受到伤害时，要塞也受到耐久损伤 |
| 摧毁后 | 同哨塔 |
| 与哨塔区别 | 更高耐久、更强减伤，但建造/升级费用更高 |
| 升级方向 | Lv1 → Lv2 → Lv3 |

#### 拒马

| 属性 | 说明 |
|------|------|
| 类型 | 阻挡型（不可进入，不可占据） |
| 基础效果 | 阻挡所有单位通行 |
| 耐久 | 可以被攻击摧毁 |
| 摧毁后 | 格子变为废墟，可通行 |
| 升级方向 | Lv1 低耐久 → Lv2 中耐久 → Lv3 高耐久 |

#### 生命泉水

| 属性 | 说明 |
|------|------|
| 类型 | 范围型（不需占据，自动对范围内友军生效） |
| 基础效果 | **回合结束时**，为周围曼哈顿距离≤3的低生命值友军恢复一次HP |
| 能量系统 | 每次恢复消耗1点能量。关卡开始时拥有3/3点能量，每2回合恢复1点能量 |
| 升级方向 | Lv1 → Lv2 回复量提升/能量上限提升 → Lv3 进一步提升 |

*注意：生命泉水的回复触发在"回合结束"（非角色回合结束），每回合仅触发一次。*

#### 巨弩

| 属性 | 说明 |
|------|------|
| 类型 | 限制型（仅弓/弩职业可占据，其他单位可进入但不获得效果） |
| 基础效果 | 占据者：大幅提升射程，但最终伤害降低（数值直接扣减）且不可攻击近距离单位（最小射程限制） |
| 升级方向 | Lv1 → Lv2 伤害降低减少 → Lv3 射程进一步提升 |

#### 魔法塔

| 属性 | 说明 |
|------|------|
| 类型 | 限制型（仅魔法职业可占据，其他单位可进入但不获得效果） |
| 基础效果 | 占据者：略微提升射程，每回合结束时为占据者提供魔法恢复（如MP/技能冷却加速） |
| 升级方向 | Lv1 → Lv2 射程提升 → Lv3 魔法恢复增强 |

*以上为基础效果描述。建筑可能通过升级或职业/技能效果获得额外功能。*

---

## 建筑通用规则

### 建造与放置

- **建造时机**：每个小关卡间的准备阶段
- **资源**：统一使用金币，与购物共享
- **放置范围受限**：只能放置在地图玩家侧的指定区域内（由地图`player_build_zone`定义）
- 不可放置在已有建筑、不可通行地形、或被单位占据的格子上
- 战场建筑放置后在后续战斗中持续存在

### 占据机制

```
当单位移动到建筑格上:
  if 建筑为通用型:
    自动占据，获得建筑效果
  elif 建筑为限制型:
    if 单位满足条件（如弓/弩职业）:
      自动占据，获得建筑效果
    else:
      仅停留，不获得建筑效果
  离开建筑格 → 自动解除占据
```

不需要专门的"占据"操作。

### 升级系统

每个建筑可从Lv1升级到Lv3（暂定）。升级在准备阶段进行，消耗金币。

```
Building:
  id: String
  name: String
  type: "functional" | "battlefield"
  subtype: "universal" | "restricted" | "blocking" | "area"  # 通用/限制/阻挡/范围
  level: int              # 1-3
  max_level: int          # 3
  build_cost: Array[int]  # [Lv1建造, Lv2升级, Lv3升级]
  repair_cost_per_point: int  # 每点耐久的修复费用
  effects_per_level: Array[BuildingEffect]
  position: Vector2i | null   # 战场建筑的地图位置
```

### 扩建

除了升级已有建筑，玩家也可以建造新的建筑：
- 可能存在建筑数量上限（功能建筑/战场建筑各有上限），防止后期过于强势
- 部分高级建筑可能需要Meta进度解锁后才出现在建造列表

---

## 建筑耐久系统

### 核心规则

建筑使用**耐久值**系统，**不使用常规伤害公式**。受到攻击时，根据攻击的**属性类型和攻击方式**扣减**固定点数**耐久。

```
BuildingDurability:
  current: int
  max: int
  damage_cost: Dict[String, int]  # 各伤害类型组合对应的固定耐久扣减值
```

耐久扣减可按属性类型（physical/magical/holy/hybrid）和攻击方式（melee/ranged/area）两轴组合查表，或简化为单轴。具体结构待平衡时确定。

**设计意图**：
- 高伤害单位不能轻松秒杀建筑
- 低伤害职业也不会被建筑完全挡住
- 所有人面对建筑的拆除速度相对一致
- 可通过两轴组合微调（如攻城类特殊技能扣减更多）

*具体各伤害类型对应的扣减数值待平衡时确定。*

### 耐久参考值

| 建筑 | 耐久（暂定） |
|------|------------|
| 哨塔 | 8 |
| 要塞 | 15 |
| 拒马 | 5 / 8 / 12 (Lv1/2/3) |
| 生命泉水 | 6 |
| 巨弩 | 6 |
| 魔法塔 | 6 |

*数值待平衡。*

### 联动伤害（哨塔/要塞）

```
当占据哨塔/要塞的单位受到攻击:
  1. 计算对单位的伤害（含建筑提供的减伤效果）
  2. 建筑按攻击的伤害类型扣减对应固定点数耐久
  → 单位受伤和建筑损耗同时发生
```

### 建筑摧毁

- 耐久降至0 → 建筑被摧毁
- 格子变为**废墟**：无任何效果，可通行
- 废墟格不恢复原基础地形效果
- 废墟格不可被地形改变技能影响

### 建筑修复

- **时机**：准备阶段
- **费用**：按缺失耐久 × 每点修复费用计算
- 修复后耐久恢复至满值
- 完全被摧毁的建筑也可修复（从废墟恢复）

---

## 所有权规则

| 建筑来源 | 效果对象 |
|---------|---------|
| 玩家建造 | 仅对玩家方生效 |
| 地图预设 | 对双方生效（中立建筑） |

*注意：地图预设的中立建筑可以被双方单位占据使用。*

---

## 城镇建设的策略深度

核心抉择：**金币是用来买装备/药剂强化角色，还是投资建筑获得长期收益？**

- **短期投入**：买武器直接提升伤害
- **长期投入**：建造武器铺，后续每个准备阶段都能买到更好的武器
- **战场投入**：建造哨塔/要塞，每场战斗都能获得战术优势
- **修复成本**：战场建筑可能在战斗中被损坏，需要额外金币修复
- **建筑选择**：巨弩/魔法塔有职业限制，需要配合队伍构成

---

## 数据结构

### 建筑定义（JSON）

```json
{
  "id": "watchtower",
  "name": "哨塔",
  "type": "battlefield",
  "subtype": "universal",
  "max_level": 3,
  "build_cost": [40, 80, 150],
  "repair_cost_per_point": 5,
  "restrict_class_tags": [],
  "durability_per_level": [8, 10, 13],
  "damage_cost": {
    "physical": 1,
    "magical": 2,
    "siege": 3
  },
  "linked_damage": true,
  "effects_per_level": [
    { "hit_bonus": 5, "damage_reduction_percent": 10, "vision_bonus": 1 },
    { "hit_bonus": 10, "damage_reduction_percent": 15, "vision_bonus": 1 },
    { "hit_bonus": 15, "damage_reduction_percent": 20, "vision_bonus": 2 }
  ],
  "placement_zone": "player_side",
  "description": "占据者获得命中、视野提升和轻微减伤。占据者受伤时哨塔也损耗耐久。"
}
```

```json
{
  "id": "ballista",
  "name": "巨弩",
  "type": "battlefield",
  "subtype": "restricted",
  "max_level": 3,
  "build_cost": [60, 120, 200],
  "repair_cost_per_point": 8,
  "restrict_class_tags": ["bow", "crossbow"],
  "durability_per_level": [6, 8, 10],
  "damage_cost": {
    "physical": 1,
    "magical": 2,
    "siege": 3
  },
  "linked_damage": false,
  "effects_per_level": [
    { "range_bonus": 3, "damage_penalty": -20, "min_range": 3 },
    { "range_bonus": 3, "damage_penalty": -15, "min_range": 3 },
    { "range_bonus": 4, "damage_penalty": -10, "min_range": 3 }
  ],
  "placement_zone": "player_side",
  "description": "仅弓/弩职业可占据。大幅提升射程，但最终伤害降低且不可攻击近距离目标。"
}
```

```json
{
  "id": "life_fountain",
  "name": "生命泉水",
  "type": "battlefield",
  "subtype": "area",
  "max_level": 3,
  "build_cost": [50, 100, 180],
  "repair_cost_per_point": 6,
  "restrict_class_tags": [],
  "durability_per_level": [6, 8, 10],
  "damage_cost": {
    "physical": 1,
    "magical": 2,
    "siege": 3
  },
  "linked_damage": false,
  "effects_per_level": [
    { "heal_amount": 10, "range": 3, "energy_max": 3, "energy_regen_interval": 2 },
    { "heal_amount": 15, "range": 3, "energy_max": 4, "energy_regen_interval": 2 },
    { "heal_amount": 20, "range": 4, "energy_max": 5, "energy_regen_interval": 2 }
  ],
  "trigger_timing": "round_end",
  "placement_zone": "player_side",
  "description": "回合结束时，为周围距离≤3的低生命值友军恢复HP。每次消耗1能量，每2回合恢复1能量。"
}
```

### Run中的城镇状态

```
TownState:
  gold: int
  buildings: Array[BuildingInstance]

BuildingInstance:
  building_id: String
  level: int
  position: Vector2i | null     # 战场建筑的位置
  current_durability: int | null  # 战场建筑的当前耐久
  current_energy: int | null      # 能量型建筑（如泉水）的当前能量
```

---

相关文档：
- [02-网格与地图](./02-grid-and-map.md) — 三层叠加规则、占据机制在网格中的表现
- [03-战斗计算](./03-battle-calculation.md) — 建筑修正对伤害/命中的影响
- [07-Run循环](./07-run-loop.md) — 准备阶段的城镇建设和修复流程
- [09-数据架构](./09-data-architecture.md) — 建筑JSON数据结构
