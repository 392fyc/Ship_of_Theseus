# 09 - Data Architecture

> Back to [[game-design-doc|GDD]]

## Overview

All game content (classes, skills, enemies, maps, relics, events) is defined in JSON data files; code only handles logic. This enables:
- Adding new content = adding JSON files, no code changes
- During vibe coding, AI can directly generate JSON data
- Balance adjustments only require changing values

---

## Data Directory Structure

```
data/
├── classes/
│   ├── soldier.json
│   ├── archer.json
│   ├── mage.json
│   ├── knight.json
│   └── cleric.json
├── skills/
│   ├── slash.json
│   ├── power_strike.json
│   ├── fireball.json
│   ├── ice_bolt.json
│   ├── heal.json
│   └── ...
├── enemies/
│   ├── goblin_melee.json
│   ├── goblin_archer.json
│   ├── goblin_shaman.json
│   ├── boss_goblin_king.json
│   └── ...
├── maps/
│   ├── forest_01.json
│   ├── forest_02.json
│   ├── cave_01.json
│   └── ...
├── relics/
│   ├── iron_amulet.json
│   ├── speed_boots.json
│   ├── vampiric_ring.json
│   └── ...
├── buildings/
│   ├── fountain.json
│   ├── watchtower.json
│   ├── weapon_shop.json
│   ├── barricade.json
│   └── ...
├── events/
│   ├── mysterious_altar.json
│   ├── wandering_merchant.json
│   └── ...
└── waves/
    ├── forest_01_waves.json
    └── ...
```

---

## JSON Schema Specification

### Skill

```json
{
  "id": "fireball",
  "name": "Fireball",
  "damage_type": "magical",
  "power": 120,
  "hit_bonus": 10,
  "range": { "type": "diamond", "min": 2, "max": 4 },
  "area": { "type": "diamond", "size": 1 },
  "cooldown": 2,
  "effects": [
    { "type": "burn", "chance": 30, "duration": 3, "value": 10 }
  ],
  "tags": ["magic", "fire", "aoe"],
  "description": "Hurl a fireball at the target, explosion radius 1 cell, chance to inflict Burn"
}
```

### Class

See [[class-system|05 - Class System]] for details.

### Enemy Template

See [[enemy-and-ai|06 - Enemy and AI]] for details.

### Map

```json
{
  "id": "forest_01",
  "name": "Forest Trail",
  "width": 8,
  "height": 8,
  "terrain": [
    [0,0,1,1,0,0,0,0],
    [0,0,1,0,0,2,0,0]
  ],
  "special_terrain": [
    { "type": "healing_ground", "position": [2, 5], "faction": "all" },
    { "type": "teleporter", "position": [0, 7], "pair_position": [7, 0] }
  ],
  "preset_buildings": [
    { "building_id": "watchtower", "position": [5, 3], "owner": "neutral" }
  ],
  "player_spawns": [[0,2],[0,3],[1,2],[1,3]],
  "player_build_zone": { "x_min": 0, "x_max": 2, "y_min": 0, "y_max": 7 },
  "wave_config": "forest_01_waves"
}
```

Base terrain numeric mapping: 0=PLAIN, 1=FOREST, 2=MOUNTAIN, 3=PEAK, 4=WALL, 5=SHALLOW_WATER, 6=DEEP_WATER, 7=LAVA, 8=SWAMP

### Relic

```json
{
  "id": "vampiric_ring",
  "name": "Vampiric Ring",
  "rarity": "uncommon",
  "effect": {
    "type": "heal_on_kill",
    "value": 10,
    "trigger": "on_kill"
  },
  "description": "Restore 10% max HP on kill"
}
```

### Event

```json
{
  "id": "mysterious_altar",
  "title": "Mysterious Altar",
  "description": "You discover an altar emanating a faint glow...",
  "choices": [
    {
      "text": "Offer your vitality",
      "outcomes": [
        {
          "weight": 100,
          "effects": [
            { "type": "lose_hp_percent", "value": 20 },
            { "type": "gain_relic", "rarity": "rare" }
          ],
          "description": "You feel a wave of weakness, but obtained a powerful relic."
        }
      ]
    },
    {
      "text": "Touch the altar",
      "outcomes": [
        {
          "weight": 70,
          "effects": [{ "type": "gain_skill", "rarity": "uncommon" }],
          "description": "The altar's energy surges into your body, you learned a new skill."
        },
        {
          "weight": 30,
          "effects": [{ "type": "debuff", "debuff_id": "curse", "duration": 3 }],
          "description": "The altar releases a cursing power!"
        }
      ]
    },
    {
      "text": "Leave",
      "outcomes": [
        {
          "weight": 100,
          "effects": [],
          "description": "You cautiously walked away."
        }
      ]
    }
  ]
}
```

---

## Data Loader - Godot Implementation

```gdscript
# data_loader.gd — Auto-loads all JSON from data/ directory
class_name DataLoader

var skills: Dictionary = {}     # id -> SkillData
var classes: Dictionary = {}    # id -> ClassData
var enemies: Dictionary = {}    # id -> EnemyData
var relics: Dictionary = {}     # id -> RelicData
var buildings: Dictionary = {}  # id -> BuildingData
var maps: Dictionary = {}       # id -> MapData
var events: Dictionary = {}     # id -> EventData

func load_all():
    _load_directory("res://data/skills/", skills)
    _load_directory("res://data/classes/", classes)
    _load_directory("res://data/enemies/", enemies)
    # ...

func _load_directory(path: String, target: Dictionary):
    var dir = DirAccess.open(path)
    for file in dir.get_files():
        if file.ends_with(".json"):
            var data = _parse_json(path + file)
            target[data.id] = data
```

---

## Godot Project Directory Structure

```
project/
├── scenes/
│   ├── tactical/
│   │   ├── TacticalScene.tscn
│   │   ├── Unit.tscn
│   │   └── ui/
│   │       └── DamagePopup.tscn
│   ├── playground/
│   │   ├── viewport_angle_playground.tscn
│   │   └── viewport_angle_static_mockup.tscn
│   ├── roguelite/
│   │   ├── RunMap.tscn
│   │   ├── RewardScreen.tscn
│   │   └── ShopScreen.tscn
│   └── menus/
│       ├── MainMenu.tscn
│       └── CharacterSelect.tscn
├── scripts/
│   ├── core/
│   │   ├── grid.gd
│   │   ├── pathfinding.gd
│   │   ├── turn_manager.gd
│   │   ├── tactical_manager.gd
│   │   ├── damage_calculator.gd
│   │   └── game_action.gd
│   ├── units/
│   │   ├── unit.gd
│   │   ├── unit_stats.gd
│   │   └── skill_executor.gd
│   ├── ai/
│   │   └── enemy_ai.gd
│   ├── tactical/
│   │   └── tactical_scene.gd
│   ├── ui/
│   │   ├── damage_popup.gd
│   │   └── turn_order_bar.gd
│   ├── roguelite/
│   │   ├── run_manager.gd
│   │   ├── relic_system.gd
│   │   ├── town_manager.gd
│   │   ├── building_system.gd
│   │   └── reward_generator.gd
│   └── network/
│       └── network_manager.gd
├── data/
│   ├── classes/
│   ├── skills/
│   ├── enemies/
│   ├── maps/
│   ├── relics/
│   ├── buildings/
│   └── events/
└── assets/
    ├── sprites/
    ├── tilesets/
    ├── ui/
    └── audio/
```

---

Current playable prototype notes:
- Main runnable scene is `res://scenes/tactical/TacticalScene.tscn`
- ADR-008 renamed `BattleScene/BattleManager` to `TacticalScene/TacticalManager`
- Grid logic remains square internally; rendering uses isometric projection in `grid.gd`

Related documents:
- [[skills-and-range|04 - Skill and Range]] — Detailed field descriptions for skill JSON
- [[class-system|05 - Class System]] — Class JSON structure
- [[enemy-and-ai|06 - Enemy and AI]] — Enemy templates and wave configuration
- [[town-building|11 - Town Building]] — Building JSON structure
