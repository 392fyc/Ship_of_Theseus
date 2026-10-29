# 02 - 棋盘与地图系统(Grid and Map System)

> Back to [[game-design-doc|GDD]]

## 概览

方格棋盘,地图尺寸 ≤10×10。无高度(海拔)系统。战术深度由三层提供:**基础地形**、**特殊地形**、**建筑**。视野系统另用单独文档展开。

---

## 棋盘定义

每个格子由三层构成:

```
Cell:
  position: Vector2i
  terrain: TerrainType           # Layer 1: Base terrain (always present)
  special_terrain: SpecialTerrain | null  # Layer 2: Special terrain (stacked on base terrain)
  building: Building | null      # Layer 3: Building (overrides base terrain effects)
  occupant: Unit | null          # Unit currently standing on this cell

Grid:
  width: int (max 10)
  height: int (max 10)
  cells: Array[Array[Cell]]
```

### 三层效果叠加规则

| 场景 | 生效规则 |
|----------|------------|
| 仅基础地形 | 基础地形效果生效 |
| 基础地形 + 特殊地形 | 两者**叠加** |
| 基础地形 + 建筑 | 建筑效果生效,基础地形效果**被覆盖** |
| 基础地形 + 特殊地形 + 建筑 | 建筑效果生效(覆盖基础地形),Buff/Debuff 类特殊地形**可叠加**到建筑上;陷阱与传送门**不能**位于建筑上 |
| 建筑被摧毁后 | 建筑加成消失,基础地形效果**不恢复**(格子变为无效果的废墟 Ruins) |

---

## 基础地形

基础地形是地图的最底层;每个格子必须有一种基础地形类型。

| 地形 | 移动消耗 | 效果 | 可通行 |
|---------|-----------|--------|----------|
| PLAIN | 1 | 无 | ✅ |
| FOREST | 2 | +闪避(Evasion) | ✅ |
| MOUNTAIN | 2 | +DEF、+RES | ✅ |
| PEAK | - | - | ❌(任何单位) |
| WALL | - | - | ❌(特殊职业除外) |
| SHALLOW_WATER | 2 | Wet(特殊 Buff) | ✅ |
| DEEP_WATER | - | Wet(特殊 Buff) | ❌(特殊职业除外) |
| LAVA | 2 | Burn | ✅ |
| SWAMP | 3 | Poison | ✅ |

### 攻击线

攻击线不受地形阻挡(R4.3):远程攻击/技能只做射程检查,不做视线/路径阻挡检查;任何地形(含 PEAK)都不阻挡攻击。

### 基础地形附加效果说明

- **Wet**:特殊 Buff,具体效果在技能/效果系统中定义(可能影响雷系技能伤害、火系技能效果等)。
- **Burn**:进入/停留在熔岩上施加 Burn Debuff,遵循 01 中的 Buff/Debuff 时机规则。
- **Poison**:进入/停留在沼泽上施加 Poison Debuff。

---

## 特殊地形

特殊地形**叠加**在基础地形之上,不替换基础地形效果。

### 来源

- **地图预设**:部分特殊地形在地图数据中预先配置(如治疗地、传送门)。
- **技能生成**:部分特殊地形由单位技能在战斗中动态创建(如 Buff 区、Debuff 区、陷阱)。

### 触发条件

一般在**停留于格子上时**生效(移动过程中经过不触发,以简化路径计算与寻路逻辑)。

### 特殊地形分类

| 分类 | 触发方式 | 来源 | 阵营规则 |
|----------|---------------|--------|---------------|
| Buff 类 | 停留期间持续 | 地图预设 / 技能生成 | 默认:仅对施放者友方生效(特例:双方) |
| Debuff 类 | 停留期间持续 | 主要为技能生成 | 默认:仅对施放者敌方生效(特例:双方) |
| Trap 类(陷阱) | 停留时触发 | 主要为技能生成 | 仅对施放者敌方生效 |
| Teleporter(传送门) | 停留时触发传送 | 地图预设 | 影响所有单位 |

### 特殊地形示例

| 特殊地形 | 分类 | 效果 |
|----------------|----------|--------|
| 治疗地 Healing Ground | Buff | 停留期间每回合回复 HP |
| [技能生成的 Buff 区] | Buff | 由具体技能定义 |
| [技能生成的 Debuff 区] | Debuff | 由具体技能定义 |
| [技能生成的陷阱] | Trap | 停留时触发(伤害/减速/眩晕等) |
| 传送门 Teleporter | Teleport | 停留时传送到配对的传送门 |

### 特殊地形与建筑的交互

| 特殊地形分类 | 能否叠加到建筑上 |
|-------------------------|----------------------|
| Buff 类 | ✅ 可以 |
| Debuff 类 | ✅ 可以 |
| Trap 类(陷阱) | ❌ 不能 |
| Teleporter(传送门) | ❌ 不能 |

### 改变地形的技能

存在能改变基础地形与特殊地形的技能:
- 建筑格**不可被强制改变**,即使建筑已被摧毁也一样(废墟 Ruins 格同样不受改变地形类技能影响)。

---

## 建筑

建筑放置在棋盘上占据格子。

本节定义建筑在棋盘上及战斗中的**通用交互规则**。

### 归属与生效范围

| 建筑来源 | 效果对象 |
|----------------|---------------|
| 玩家建造的建筑 | 仅玩家一方 |
| 地图预设建筑 | 双方 |

### 占据机制

建筑有两种交互模式:

| 交互模式 | 说明 | 例子 |
|-----------------|-------------|---------|
| 通用(Universal) | 任何单位都可进入并自动获得效果 | 哨塔、要塞 |
| 限定(Restricted) | 符合条件的单位停留时自动占据并获得效果;不符合条件的单位可进入但仅算停留,无建筑效果 | 弩台(弓/弩系职业)、魔法塔(法系职业) |

- **占据 = 停留**:符合条件的单位停留在建筑格上即自动占据。
- 无需专门的「占据」动作。
- 离开建筑格自动解除占据。

### 建筑耐久系统

建筑使用**耐久(durability)**而非 HP。受攻击时,按**伤害类型**扣减固定点数的耐久(不走常规伤害公式)。

```
BuildingDurability:
  current: int
  max: int
  damage_cost: Dict[String, int]  # Fixed durability deduction per damage type combination

Example (specific values TBD):
  physical: 1 point
  magical: 2 points
  siege: 3 points    # Siege-type skills
  ...
```

**设计意图**:防止高伤害单位轻易摧毁建筑,同时低伤害职业也不会被建筑卡死。所有单位的拆除速度相对一致。

### 建筑摧毁

- 耐久降至 0 时建筑被摧毁。
- 摧毁后,格子变为**废墟 Ruins**:失去建筑加成,基础地形效果**不恢复**。
- 废墟格可通行,无特殊效果。

### 占据者受伤时的建筑联动

部分建筑(哨塔、要塞)在占据单位受伤时也会受到耐久损伤:

```
When occupant is attacked:
  1. First resolve damage to unit (including building damage reduction effects)
  2. Building deducts fixed durability points based on attack's damage type
```

---

## 移动与寻路

### 移动范围计算 - BFS

```
func get_movable_cells(unit: Unit) -> Array[Vector2i]:
  BFS from unit.position
  Each step deducts corresponding terrain move cost
  Cells with total cost ≤ unit.move_points are reachable
  Impassable cells excluded (PEAK / WALL / DEEP_WATER / Barricade, etc., special class exceptions)
  Enemy-occupied cells are impassable
  Friendly-occupied cells can be traversed but not stopped on
```

### 路径计算 - A*

选定目的地后,A* 寻路计算实际移动路径。

### 寻路简化说明

Trap 类特殊地形**不影响寻路计算**——路径不会自动避开陷阱。这是刻意的简化,避免复杂的路径规划给玩家和 AI 造成困难。

### 已删除的机制与移动设计约束

- **控制区(ZOC)与格挡已于 2026-07-06 完全删除**(用户裁决):移动力不再受敌方控制区影响,伤害流程中没有格挡。此前 2026-06-21「ZOC 移动惩罚从 −2 降为 −1、暂定观察」的决定随之作废。剑圣的**招架**是独立机制,不属于格挡,不受此删除影响。
- **移动惩罚类设计须保守**(长期约束,与 ZOC 存废无关):棋盘不做超大、移动力不给高,任何「移动惩罚 / 移动消耗」类设计都要保守。改这类数值前,先算最坏情况:低移动力单位在高消耗地形上是否仍能行动。

---

## 地图数据格式

```json
{
  "id": "forest_01",
  "name": "Forest Trail",
  "width": 8,
  "height": 8,
  "terrain": [
    [0,0,1,1,0,0,0,0],
    [0,0,1,0,0,2,0,0],
    [0,0,0,0,3,0,0,0],
    [0,0,0,0,0,0,5,5],
    [0,0,7,0,0,0,0,0],
    [0,0,0,0,0,0,0,0],
    [0,0,0,0,0,0,0,0],
    [0,0,0,0,0,1,1,0]
  ],
  "special_terrain": [
    { "type": "healing_ground", "position": [2, 5], "faction": "all" },
    { "type": "teleporter", "position": [0, 7], "pair_position": [7, 0] }
  ],
  "preset_buildings": [
    { "building_id": "watchtower", "position": [5, 3], "owner": "neutral" }
  ],
  "player_spawns": [[0,2], [0,3], [1,2], [1,3]],
  "player_build_zone": { "x_min": 0, "x_max": 2, "y_min": 0, "y_max": 7 },
  "wave_config": "forest_01_waves"
}
```

**基础地形数值映射**:

| 数值 | 地形 |
|-------|---------|
| 0 | PLAIN |
| 1 | FOREST |
| 2 | MOUNTAIN |
| 3 | PEAK |
| 4 | WALL |
| 5 | SHALLOW_WATER |
| 6 | DEEP_WATER |
| 7 | LAVA |
| 8 | SWAMP |

---

相关文档:
- [[battle-calculation|03 - 战斗计算]] — 具体地形战斗修正数值
- [[skills-and-range|04 - 技能与射程]] — 射程计算、技能生成的特殊地形
- [[enemy-and-ai|07 - 敌人与 AI]] — AI 寻路与地形评估
- 视野系统 — 另用单独文档创建
