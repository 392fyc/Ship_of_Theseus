# 09 - 数据架构(Data Architecture)

> Back to [[game-design-doc|GDD]]

## 概览

所有游戏内容(职业、技能、敌人、地图、遗物、事件)都在 JSON 数据文件里定义;代码只处理逻辑。这样带来的好处:
- 添加新内容 = 添加 JSON 文件,无需改代码
- 在 vibe coding 过程中,AI 可以直接生成 JSON 数据
- 平衡调整只需改数值

---

## 数据目录结构

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

## JSON Schema 规范

### 技能(Skill)

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

### 职业(Class)

详见 [[class-system|05 - 职业系统]]。

### 敌人模板(Enemy Template)

详见 [[enemy-and-ai|07 - 敌人与 AI]]。

### 地图(Map)

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

基础地形数字映射:0=PLAIN、1=FOREST、2=MOUNTAIN、3=PEAK、4=WALL、5=SHALLOW_WATER、6=DEEP_WATER、7=LAVA、8=SWAMP

### 遗物(Relic)

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

### 事件(Event)

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

## 数据加载器 - Godot 实现

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

## Godot 工程目录结构

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

当前可玩原型说明:
- 主可运行场景是 `res://scenes/tactical/TacticalScene.tscn`
- 场景与管理器命名为 `TacticalScene`/`TacticalManager`
- 棋盘逻辑内部仍为方格;渲染在 `grid.gd` 中使用等距投影

相关文档:
- [[skills-and-range|04 - 技能与射程]] — 技能 JSON 的字段详解
- [[class-system|05 - 职业系统]] — 职业 JSON 结构
- [[enemy-and-ai|07 - 敌人与 AI]] — 敌人模板与波次配置
