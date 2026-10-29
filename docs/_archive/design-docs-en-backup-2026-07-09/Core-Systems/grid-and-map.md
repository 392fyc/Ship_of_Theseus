# 02 - Grid and Map System

> Back to [[game-design-doc|GDD]]

## Overview

Square grid, map size ≤10×10. No elevation system. Tactical depth is provided through three layers: **base terrain**, **special terrain**, and **buildings**. The vision system will be covered in a separate document.

---

## Grid Definition

Each cell consists of three layers:

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

### Three-Layer Effect Stacking Rules

| Scenario | Active Rule |
|----------|------------|
| Base terrain only | Base terrain effects apply |
| Base terrain + Special terrain | Both **stack** |
| Base terrain + Building | Building effects apply, base terrain effects **overridden** |
| Base terrain + Special terrain + Building | Building effects apply (override base terrain), Buff/Debuff special terrain **can stack** onto building; traps and teleporters **cannot** be on buildings |
| After building destroyed | Building bonuses lost, base terrain effects **not restored** (cell becomes effectless Ruins) |

---

## Base Terrain

Base terrain is the bottom layer of the map; every cell must have one base terrain type.

| Terrain | Move Cost | Effect | Passable | Blocks Attack Line |
|---------|-----------|--------|----------|--------------------|
| PLAIN | 1 | None | ✅ | ❌ |
| FOREST | 2 | +Evasion | ✅ | ❌ |
| MOUNTAIN | 2 | +DEF, +RES | ✅ | ❌ |
| PEAK | - | - | ❌ (any unit) | ✅ Blocks ranged attack lines |
| WALL | - | - | ❌ (except special classes) | ❌ |
| SHALLOW_WATER | 2 | Wet (special Buff) | ✅ | ❌ |
| DEEP_WATER | - | Wet (special Buff) | ❌ (except special classes) | ❌ |
| LAVA | 2 | Burn | ✅ | ❌ |
| SWAMP | 3 | Poison | ✅ | ❌ |

### Peaks and Attack Lines

Peak (PEAK) is the only base terrain that blocks attack lines. When ranged attacks/skills check range, the line-of-sight path from attacker to target must be checked for peak cells. If a peak exists on the path, the target cannot be attacked.

```
Attack line check:
  Draw a line from attacker to target
  If the path passes through a PEAK cell → attack blocked, target not selectable
  Other terrain (including WALL) does not block attack lines
```

*The specific algorithm for attack line checking (Bresenham/ray casting) will be determined during implementation.*

### Base Terrain Additional Effect Notes

- **Wet**: Special Buff, specific effects will be defined in the skill/effect system (may affect lightning skill damage, fire skill effects, etc.)
- **Burn**: Entering/standing on lava applies a Burn Debuff, following Buff/Debuff timing rules from 01
- **Poison**: Entering/standing on swamp applies a Poison Debuff

---

## Special Terrain

Special terrain **stacks** on top of base terrain, does not replace base terrain effects.

### Sources

- **Map preset**: Some special terrain is pre-configured in map data (e.g., Healing Ground, Teleporter)
- **Skill-generated**: Some special terrain is dynamically created by unit skills during battle (e.g., Buff zones, Debuff zones, Traps)

### Activation Conditions

Generally, effects apply **when standing on the cell** (passing through during movement does not trigger, to simplify path calculation and pathfinding logic).

### Special Terrain Categories

| Category | Trigger Method | Source | Faction Rules |
|----------|---------------|--------|---------------|
| Buff type | Persistent while standing | Map preset / Skill-generated | Default: friendly to caster only (special cases: both sides) |
| Debuff type | Persistent while standing | Primarily skill-generated | Default: hostile to caster only (special cases: both sides) |
| Trap type | Triggered on standing | Primarily skill-generated | Hostile to caster only |
| Teleporter | Triggers teleport on standing | Map preset | Affects all units |

### Special Terrain Examples

| Special Terrain | Category | Effect |
|----------------|----------|--------|
| Healing Ground | Buff | Restores HP each turn while standing |
| [Skill-generated Buff zone] | Buff | Defined by specific skill |
| [Skill-generated Debuff zone] | Debuff | Defined by specific skill |
| [Skill-generated Trap] | Trap | Triggered on standing (damage/slow/stun, etc.) |
| Teleporter | Teleport | Teleports to paired teleporter on standing |

### Special Terrain and Building Interaction

| Special Terrain Category | Can Stack on Building |
|-------------------------|----------------------|
| Buff type | ✅ Yes |
| Debuff type | ✅ Yes |
| Trap type | ❌ No |
| Teleporter | ❌ No |

### Terrain-Altering Skills

Skills exist that can change base terrain and special terrain:
- Building cells **cannot be forcibly changed**, even if the building has been destroyed (Ruins cells also cannot be affected by terrain-altering skills)

---

## Buildings

Buildings are placed on the grid occupying cells. For detailed building lists, construction/upgrade/repair rules, see → [[town-building|11 - Town Building]].

This section defines the **general interaction rules** for buildings on the grid and in battle.

### Ownership and Effective Range

| Building Source | Effect Target |
|----------------|---------------|
| Player-built buildings | Player side only |
| Map preset buildings | Both sides |

### Occupation Mechanics

Buildings have two interaction modes:

| Interaction Mode | Description | Example |
|-----------------|-------------|---------|
| Universal | Any unit can enter and automatically gain effects | Watchtower, Fortress |
| Restricted | Eligible units automatically occupy and gain effects when standing; ineligible units can enter but only count as standing, no building effects | Ballista (archer/crossbow classes), Magic Tower (magic classes) |

- **Occupation = Standing**: Eligible units automatically occupy by standing on the building cell
- No dedicated "occupy" action needed
- Leaving the building cell automatically releases occupation

### Building Durability System

Buildings use **durability** instead of HP. When attacked, a fixed number of durability points are deducted based on **damage type** (does not use the normal damage formula).

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

**Design Intent**: Prevents high-damage units from easily destroying buildings, while low-damage classes are also not stuck against buildings. Demolition speed is relatively consistent for all units.

### Building Destruction

- Building is destroyed when durability reaches 0
- After destruction, the cell becomes **Ruins**: loses building bonuses, base terrain effects are **not restored**
- Ruins cells are passable, no special effects
- Buildings can be **repaired** during preparation phase for gold (see 11 - Town Building)

### Building Link When Occupant Takes Damage

Some buildings (Watchtower, Fortress) also take durability damage when the occupying unit is damaged:

```
When occupant is attacked:
  1. First resolve damage to unit (including building damage reduction effects)
  2. Building deducts fixed durability points based on attack's damage type
```

---

## Movement and Pathfinding

### Movement Range Calculation - BFS

```
func get_movable_cells(unit: Unit) -> Array[Vector2i]:
  BFS from unit.position
  Each step deducts corresponding terrain move cost
  Cells with total cost ≤ unit.move_points are reachable
  Impassable cells excluded (PEAK / WALL / DEEP_WATER / Barricade, etc., special class exceptions)
  Enemy-occupied cells are impassable
  Friendly-occupied cells can be traversed but not stopped on
```

### Path Calculation - A*

After selecting a destination, A* pathfinding calculates the actual movement path.

### Pathfinding Simplification Notes

Trap-type special terrain **does not affect pathfinding calculation** — paths will not automatically avoid traps. This is an intentional simplification to avoid complex path planning causing difficulty for players and AI.

### Zone of Control - ZOC（已全面删除）

> **ZOC（控制区）机制已全面删除（2026-07-06 用户裁决）**：减移动力设定不便玩家计算移动力，
> 小棋盘下累赘且增加设计负担。原 ZOC 定义、移动惩罚、寻路交互、抗性/免疫预留全部作废；
> 敌人词条 `af_zone_expand`（控制区扩大）随之作废。Godot 侧代码移除由 SoT 组另行执行。

---

## Map Data Format

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

**Base terrain numeric mapping**:

| Value | Terrain |
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

Related documents:
- [[town-building|11 - Town Building]] — Building list, construction/upgrade/repair rules
- [[battle-calculation|03 - Battle Calculation]] — Specific terrain combat modifier values
- [[skills-and-range|04 - Skill and Range]] — Attack line checking, skill-generated special terrain
- [[enemy-and-ai|06 - Enemy and AI]] — AI pathfinding and terrain evaluation
- Vision System — To be created in a separate document
