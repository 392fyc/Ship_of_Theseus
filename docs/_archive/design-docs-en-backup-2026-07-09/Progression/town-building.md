# 11 - Town Building System

> Back to [Overview](./README.md)

## Overview

Town Building is the economy and shop system floor of this game's v1; the core differentiator is the talent tree architecture (see [[01-Game-Design/Characters/talent-tree-design|Talent Tree Design Theory]]). During the Preparation Phase between each sub-stage, players use Gold to construct, upgrade, and repair Buildings. Buildings are divided into two categories:

- **Functional Buildings**: Provide services during the Preparation Phase (shops, training grounds, etc.), do not appear on the battle map
- **Battlefield Buildings**: Placed on the battle map, provide tactical advantages during combat

All Buildings can be upgraded and expanded using a unified currency (Gold).

---

## Functional Buildings - Active During Preparation Phase

Do not appear on the battle map; provide services to players during the Preparation Phase.

| Building | Function | Upgrade Path |
|------|------|---------|
| Weapon Shop | Buy/enhance weapons | Lv1 Basic Weapons → Lv2 Rare Weapons → Lv3 Legendary Weapons |
| Armor Shop | Buy/enhance armor | Lv1 Basic Armor → Lv2 Rare Armor → Lv3 Legendary Armor |
| Potion Shop | Buy consumables (recovery/buff) | Lv1 Basic Potions → Lv2 Advanced Potions → Lv3 Rare Potions |
| Training Ground | Reset/swap/learn skills | Lv1 Swap Skills → Lv2 Learn New Skills → Lv3 Skill Enhancement |
| Tavern | Recruit temporary mercenaries/gather intel | (TBD) |

---

## Battlefield Buildings - Active on Battle Map

### Building List

#### Watchtower

| Attribute | Description |
|------|------|
| Type | Universal (any unit can occupy) |
| Base Effect | Occupant: increased hit rate, increased vision, slightly reduced damage taken |
| Linked Damage | When the occupant takes damage, the Watchtower also takes Durability damage |
| When Destroyed | Loses building bonuses, tile becomes Ruins (does not revert to base terrain effects) |
| Upgrade Path | Lv1 → Lv2 increased bonuses → Lv3 further increased bonuses |

#### Fortress

| Attribute | Description |
|------|------|
| Type | Universal |
| Base Effect | Occupant: increased hit rate, increased vision, **greatly** reduced damage taken |
| Linked Damage | When the occupant takes damage, the Fortress also takes Durability damage |
| When Destroyed | Same as Watchtower |
| Difference from Watchtower | Higher Durability, stronger damage reduction, but higher construction/upgrade cost |
| Upgrade Path | Lv1 → Lv2 → Lv3 |

#### Barricade

| Attribute | Description |
|------|------|
| Type | Blocking (cannot enter, cannot occupy) |
| Base Effect | Blocks all unit movement |
| Durability | Can be attacked and destroyed |
| When Destroyed | Tile becomes Ruins, passable |
| Upgrade Path | Lv1 Low Durability → Lv2 Medium Durability → Lv3 High Durability |

#### Life Fountain

| Attribute | Description |
|------|------|
| Type | Area (does not require occupation, automatically affects allied units in range) |
| Base Effect | **At round end**, restores HP once to allied units with low health within Manhattan distance ≤ 3 |
| Energy System | Each heal consumes 1 energy. Starts the stage with 3/3 energy, regenerates 1 energy every 2 rounds |
| Upgrade Path | Lv1 → Lv2 increased heal amount / increased energy cap → Lv3 further increased |

*Note: Life Fountain healing triggers at "round end" (not character turn end), triggers only once per round.*

#### Ballista

| Attribute | Description |
|------|------|
| Type | Restricted (only bow/crossbow classes can occupy; other units can enter but do not gain effects) |
| Base Effect | Occupant: greatly increased range, but final damage reduced (flat subtraction) and cannot attack close-range units (minimum range restriction) |
| Upgrade Path | Lv1 → Lv2 damage reduction penalty decreased → Lv3 range further increased |

#### Magic Tower

| Attribute | Description |
|------|------|
| Type | Restricted (only magic classes can occupy; other units can enter but do not gain effects) |
| Base Effect | Occupant: slightly increased range, at each round end provides magic recovery to the occupant (e.g., MP / skill cooldown acceleration) |
| Upgrade Path | Lv1 → Lv2 range increased → Lv3 magic recovery enhanced |

*The above describes base effects. Buildings may gain additional functions through upgrades or class/skill effects.*

---

## General Building Rules

### Construction and Placement

- **Construction Timing**: During the Preparation Phase between each sub-stage
- **Resources**: Uses Gold uniformly, shared with shopping
- **Placement Range Restricted**: Can only be placed in the designated area on the player's side of the map (defined by the map's `player_build_zone`)
- Cannot be placed on tiles with existing buildings, impassable terrain, or tiles occupied by units
- Battlefield Buildings persist in subsequent battles after placement

### Occupation Mechanics

```
When a unit moves onto a building tile:
  if building is Universal:
    automatically occupy, gain building effects
  elif building is Restricted:
    if unit meets conditions (e.g., bow/crossbow class):
      automatically occupy, gain building effects
    else:
      only stays, does not gain building effects
  leaving the building tile → automatically release occupation
```

No dedicated "occupy" action is needed.

### Upgrade System

Each Building can be upgraded from Lv1 to Lv3 (tentative). Upgrades are performed during the Preparation Phase and cost Gold.

```
Building:
  id: String
  name: String
  type: "functional" | "battlefield"
  subtype: "universal" | "restricted" | "blocking" | "area"  # Universal/Restricted/Blocking/Area
  level: int              # 1-3
  max_level: int          # 3
  build_cost: Array[int]  # [Lv1 build, Lv2 upgrade, Lv3 upgrade]
  repair_cost_per_point: int  # Repair cost per Durability point
  effects_per_level: Array[BuildingEffect]
  position: Vector2i | null   # Map position for Battlefield Buildings
```

### Expansion

In addition to upgrading existing Buildings, players can also construct new Buildings:
- There may be a Building count limit (separate limits for Functional Buildings and Battlefield Buildings) to prevent becoming overpowered in later stages
- Some advanced Buildings may require Meta progression unlocks before appearing in the build list

---

## Building Durability System

### Core Rules

Buildings use a **Durability** system and **do not use standard damage formulas**. When attacked, a **fixed number of points** of Durability is deducted based on the attack's **element type and attack method**.

```
BuildingDurability:
  current: int
  max: int
  damage_cost: Dict[String, int]  # Fixed Durability deduction per damage type combination
```

Durability deduction can be looked up via a two-axis table of element type (physical/magical/holy/hybrid) and attack method (melee/ranged/area), or simplified to a single axis. The exact structure will be determined during balancing.

**Design Intent**:
- High-damage units cannot easily one-shot Buildings
- Low-damage classes are not completely blocked by Buildings
- All units demolish Buildings at a relatively consistent speed
- Fine-tuning is possible via two-axis combinations (e.g., siege-type special skills deduct more)

*The specific deduction values for each damage type will be determined during balancing.*

### Durability Reference Values

| Building | Durability - Tentative |
|------|------------|
| Watchtower | 8 |
| Fortress | 15 |
| Barricade | 5 / 8 / 12 (Lv1/2/3) |
| Life Fountain | 6 |
| Ballista | 6 |
| Magic Tower | 6 |

*Values pending balance.*

### Linked Damage - Watchtower and Fortress

```
When a unit occupying a Watchtower/Fortress is attacked:
  1. Calculate damage to the unit (including damage reduction from the building)
  2. The building deducts fixed Durability points based on the attack's damage type
  → Unit damage and building wear occur simultaneously
```

### Building Destruction

- Durability drops to 0 → Building is destroyed
- Tile becomes **Ruins**: no effects, passable
- Ruins tiles do not revert to original base terrain effects
- Ruins tiles cannot be affected by terrain-altering skills

### Building Repair

- **Timing**: Preparation Phase
- **Cost**: Calculated as missing Durability × repair cost per point
- Durability is restored to full after repair
- Completely destroyed Buildings can also be repaired (restored from Ruins)

---

## Ownership Rules

| Building Source | Effect Target |
|---------|---------|
| Player-built | Only affects the player's side |
| Map preset | Affects both sides (neutral building) |

*Note: Map-preset neutral Buildings can be occupied and used by units from both sides.*

---

## Strategic Depth of Town Building

Core dilemma: **Should Gold be spent on equipment/potions to strengthen characters, or invested in Buildings for long-term returns?**

- **Short-term investment**: Buy weapons to directly increase damage
- **Long-term investment**: Build a Weapon Shop so better weapons are available at every subsequent Preparation Phase
- **Battlefield investment**: Build Watchtowers/Fortresses to gain tactical advantages in every battle
- **Repair costs**: Battlefield Buildings may be damaged during combat, requiring additional Gold to repair
- **Building choices**: Ballista/Magic Tower have class restrictions and require synergy with team composition

---

## Data Structures

### Building Definition - JSON

```json
{
  "id": "watchtower",
  "name": "Watchtower",
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
  "description": "Occupant gains hit rate, vision bonuses and slight damage reduction. When the occupant takes damage, the Watchtower also loses Durability."
}
```

```json
{
  "id": "ballista",
  "name": "Ballista",
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
  "description": "Only bow/crossbow classes can occupy. Greatly increases range, but final damage is reduced and cannot attack close-range targets."
}
```

```json
{
  "id": "life_fountain",
  "name": "Life Fountain",
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
  "description": "At round end, restores HP to allied units with low health within distance ≤ 3. Each heal costs 1 energy, regenerates 1 energy every 2 rounds."
}
```

### Town State During a Run

```
TownState:
  gold: int
  buildings: Array[BuildingInstance]

BuildingInstance:
  building_id: String
  level: int
  position: Vector2i | null     # Battlefield Building position
  current_durability: int | null  # Battlefield Building current Durability
  current_energy: int | null      # Energy-type Building (e.g., fountain) current energy
```

---

Related documents:
- [[02-grid-and-map|02 - Grid and Map]] — Three-layer stacking rules, occupation mechanics in the grid
- [[03-battle-calculation|03 - Battle Calculation]] — Building modifiers on damage/hit rate
- [[07-run-loop|07 - Run Loop]] — Town Building and repair flow during the Preparation Phase
- [[09-data-architecture|09 - Data Architecture]] — Building JSON data structures
