# 09 - 数据架构

> 返回 [总纲](./README.md)

## 概述

所有游戏内容（职业、技能、敌人、地图、遗物、事件）均用JSON数据文件定义，代码只处理逻辑。这使得：
- 添加新内容 = 新增JSON文件，不改代码
- Vibe coding时AI可以直接生成JSON数据
- 平衡调整只需改数值

---

## 数据目录结构

```
data/
├── classes/
│   ├── warrior.json
│   ├── archer.json
│   ├── mage.json
│   └── rogue.json
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

### 技能（Skill）

```json
{
  "id": "fireball",
  "name": "火球术",
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
  "description": "向目标投掷火球，爆炸范围1格，有几率附加燃烧"
}
```

### 职业（Class）

→ 详见 [05-职业系统](./05-class-system.md)

### 敌人模板（Enemy）

→ 详见 [06-敌人与AI](./06-enemy-and-ai.md)

### 地图（Map）

```json
{
  "id": "forest_01",
  "name": "密林小径",
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

基础地形映射：0=PLAIN, 1=FOREST, 2=MOUNTAIN, 3=PEAK, 4=WALL, 5=SHALLOW_WATER, 6=DEEP_WATER, 7=LAVA, 8=SWAMP

### 遗物（Relic）

```json
{
  "id": "vampiric_ring",
  "name": "吸血戒指",
  "rarity": "uncommon",
  "effect": {
    "type": "heal_on_kill",
    "value": 10,
    "trigger": "on_kill"
  },
  "description": "击杀敌人时回复10%最大HP"
}
```

### 事件（Event）

```json
{
  "id": "mysterious_altar",
  "title": "神秘祭坛",
  "description": "你发现一座散发微光的祭坛...",
  "choices": [
    {
      "text": "献上生命力",
      "outcomes": [
        {
          "weight": 100,
          "effects": [
            { "type": "lose_hp_percent", "value": 20 },
            { "type": "gain_relic", "rarity": "rare" }
          ],
          "description": "你感到一阵虚弱，但获得了一件强力遗物。"
        }
      ]
    },
    {
      "text": "触碰祭坛",
      "outcomes": [
        {
          "weight": 70,
          "effects": [{ "type": "gain_skill", "rarity": "uncommon" }],
          "description": "祭坛的能量涌入体内，你学会了新技能。"
        },
        {
          "weight": 30,
          "effects": [{ "type": "debuff", "debuff_id": "curse", "duration": 3 }],
          "description": "祭坛释放出诅咒之力！"
        }
      ]
    },
    {
      "text": "离开",
      "outcomes": [
        {
          "weight": 100,
          "effects": [],
          "description": "你谨慎地离开了。"
        }
      ]
    }
  ]
}
```

---

## 数据加载器（Godot实现方向）

```gdscript
# data_loader.gd — 自动加载data/目录下所有JSON
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

## Godot项目目录结构

```
project/
├── scenes/
│   ├── battle/
│   │   ├── BattleScene.tscn
│   │   ├── Grid.tscn
│   │   ├── Unit.tscn
│   │   └── ui/
│   │       ├── TurnOrderBar.tscn
│   │       ├── ActionMenu.tscn
│   │       └── DamagePopup.tscn
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
│   │   ├── battle_manager.gd
│   │   ├── damage_calculator.gd
│   │   └── game_action.gd
│   ├── units/
│   │   ├── unit.gd
│   │   ├── unit_stats.gd
│   │   └── skill_executor.gd
│   ├── ai/
│   │   └── enemy_ai.gd
│   ├── data/
│   │   └── data_loader.gd
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

相关文档：
- [04-技能与射程](./04-skills-and-range.md) — 技能JSON的详细字段说明
- [05-职业系统](./05-class-system.md) — 职业JSON结构
- [06-敌人与AI](./06-enemy-and-ai.md) — 敌人模板和波次配置
- [11-城镇建设](./11-town-building.md) — 建筑JSON结构
