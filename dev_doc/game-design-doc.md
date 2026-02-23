# 战棋Roguelite — 核心系统设计文档

## 项目概览

| 项目属性 | 决策 |
|---------|------|
| 类型 | 战棋RPG + Roguelite |
| 引擎 | Godot 4 (GDScript) |
| 网格 | 正方形网格（四方向/八方向） |
| 地图规模 | ≤10×10，敌人分批加入 |
| 回合制 | 速度轮动制（CTB/个体行动制） |
| 玩家人数 | 单机1人 / 联机1-4人 |
| 联机模式 | 每人控制1个角色，轮动操作 |
| 核心循环 | 杀戮尖塔式一次Run多关 |
| 画风 | GBA像素（初期跳过，先搭系统） |
| 开发方式 | Vibe Coding + AI素材生成 |

---

## 1. 回合系统（CTB - Charge Time Battle）

### 1.1 核心机制：速度轮动制

每个单位（含敌方）拥有一个 **行动值（CT: Charge Time）**，速度越高CT积攒越快，CT满时获得行动权。

```
每个Tick:
  for unit in all_units:
    unit.ct += unit.speed
  
  if any unit.ct >= CT_THRESHOLD (例如100):
    取CT最高者行动（同值时按优先级规则）
    行动后 CT 归零（或扣除阈值）
```

### 1.2 数据结构

```
Unit:
  id: String
  owner: PlayerID | "enemy"
  ct: int = 0
  speed: int          # 决定CT积攒速率
  ct_threshold: int = 100

TurnManager:
  units: Array[Unit]          # 所有存活单位
  action_queue: Array[Unit]   # 按CT排序的行动预览队列
  current_actor: Unit | null
```

### 1.3 行动预览

类似FFT的行动顺序预览条，让玩家看到接下来5-8个行动单位的顺序。这对战术决策至关重要——玩家需要知道"如果我不杀这个敌人，它下回合就会行动"。

### 1.4 联机适配

轮动制天然适合联机：
- 同一时刻只有一个单位行动
- 其他玩家等待时可以观察/规划
- 只需同步"谁在行动"和"行动指令"
- 可设置行动时间限制（如60秒）防止挂机

---

## 2. 网格与地图系统

### 2.1 网格定义

```
Grid:
  width: int (max 10)
  height: int (max 10)
  cells: Array[Array[Cell]]

Cell:
  position: Vector2i
  terrain: TerrainType
  elevation: int        # 高度层级（0-3）
  occupant: Unit | null
  effects: Array[CellEffect]  # 地形buff/陷阱等

TerrainType: enum
  PLAIN       # 平地：无特殊效果
  FOREST      # 树林：+闪避, 移动消耗+1
  MOUNTAIN    # 山地：+防御, 移动消耗+2
  WATER       # 水面：大多数职业不可通行
  WALL        # 墙壁：不可通行, 阻挡视线
  COVER       # 掩体：方向性防御加成
```

### 2.2 高低差系统

高度差影响：
- **攻击加成**：从高处往低处攻击有伤害/命中加成
- **攻击惩罚**：从低处往高处攻击有伤害/命中惩罚
- **射程变化**：远程攻击从高处可增加有效射程
- **移动消耗**：上坡消耗额外移动力，下坡可能减少

```
elevation_bonus(attacker, defender):
  diff = attacker.cell.elevation - defender.cell.elevation
  if diff > 0: return +damage_bonus_per_level * diff
  if diff < 0: return -damage_penalty_per_level * abs(diff)
  return 0
```

### 2.3 移动与寻路

- 使用 **A* 寻路**，移动消耗因地形而异
- 移动范围计算用 **BFS（广度优先搜索）** + 移动力
- 每个单位有 `move_points`，地形消耗不同点数

```
移动消耗表:
  PLAIN:    1
  FOREST:   2
  MOUNTAIN: 3
  上坡+1层: +1
  下坡:     0（不额外消耗）
```

---

## 3. 战斗系统

### 3.1 核心属性

```
UnitStats:
  hp: int             # 生命值
  max_hp: int
  attack: int         # 物理攻击
  magic: int          # 魔法攻击
  defense: int        # 物理防御
  resistance: int     # 魔法防御
  speed: int          # 影响CT和闪避
  move: int           # 移动力（格数）
  hit: int            # 命中率基础值
  evade: int          # 闪避率基础值
```

### 3.2 伤害公式

保持简单可调：

```
基础伤害 = attacker.attack - defender.defense  (物理)
         = attacker.magic - defender.resistance (魔法)

最终伤害 = 基础伤害
         × 技能倍率
         × 地形修正（高低差、掩体）
         × 暴击修正（暴击时×1.5）
         × 随机波动（0.9~1.1）

最低伤害 = 1（保底）
```

### 3.3 命中判定

```
命中率 = attacker.hit + 武器命中 - defender.evade - 地形闪避 - 高低差修正
暴击率 = attacker.crit - defender.crit_evade
```

### 3.4 武器与技能射程系统

这是你选择的核心机制之一。每个武器/技能有：

```
Skill:
  id: String
  name: String
  damage_type: "physical" | "magical" | "pure"
  power: int              # 技能倍率基础
  hit_bonus: int          # 命中修正
  range: RangePattern     # 射程模式
  area: AreaPattern       # 效果范围模式
  ct_cost: int            # 使用后额外CT延迟（重技能慢，轻技能快）
  cooldown: int           # 冷却回合数
  effects: Array[Effect]  # 附加效果（debuff等）

RangePattern:
  type: "diamond" | "line" | "cross" | "square" | "custom"
  min_range: int    # 最小射程（近战=1, 有些技能=2代表不能打邻接）
  max_range: int    # 最大射程

AreaPattern:
  type: "single" | "diamond" | "line" | "cross" | "square"
  size: int         # 范围大小
```

**射程示例（10×10网格上）：**
- 剑：range 1, area single（邻接单体）
- 弓：range 2-4, area single（远距单体，不能打邻接）
- 火球：range 3, area diamond(1)（3格内投射，爆炸范围1格菱形=5格）
- 治疗光环：range 0, area diamond(2)（以自身为中心，范围2的菱形）

### 3.5 CT消耗与技能权衡

轮动制的一个独特点：**强力技能会让你下次行动更慢**。

```
行动后CT处理:
  unit.ct = 0 - skill.ct_cost

  例如:
  - 普通攻击: ct_cost = 0  → CT归0，正常恢复
  - 重击:     ct_cost = 30 → CT变为-30，需要更久才到100
  - 快速斩:   ct_cost = -20 → CT变为20，比普通更快恢复
```

这让"什么时候用大招"成为核心战术决策。

---

## 4. 职业与Build系统

### 4.1 职业框架

Roguelite不需要像火纹那样的转职树，更适合**起始职业 + 技能获取**的模式：

```
Class:
  id: String
  name: String
  base_stats: UnitStats      # 基础属性
  stat_growth: UnitStats     # 每次升级成长率
  innate_skills: Array[Skill]  # 初始自带技能
  equip_types: Array[String]   # 可装备类型
  move_type: "foot" | "armored" | "flying" | "mounted"
```

**初始职业示例（4个基础，覆盖不同战术位）：**

| 职业 | 定位 | 移动 | 特点 |
|------|------|------|------|
| 战士 | 近战坦克 | 3格 | 高HP/防御, 嘲讽/护盾技能 |
| 弓手 | 远程输出 | 3格 | 长射程, 对空特效 |
| 法师 | 范围控制 | 2格 | AOE魔法, 低HP |
| 盗贼 | 机动刺杀 | 5格 | 高速度, 背刺加成, 低防 |

### 4.2 Build多样性来源（Roguelite层面）

每次Run中通过以下途径获取Build差异化：
- **技能获取**：战斗奖励/商店选择新技能装备到角色
- **遗物/被动**：全局增益（类杀戮尖塔遗物）
- **装备**：武器/防具影响属性和技能
- **技能槽位限制**：角色只能装备N个主动技能，迫使选择

```
UnitBuild:
  class: Class
  level: int
  equipped_skills: Array[Skill]  # 有限槽位（如4个）
  weapon: Weapon
  armor: Armor
  relics: Array[Relic]           # 被动遗物
```

---

## 5. 敌人与AI系统

### 5.1 AI行为模式

10×10的小地图 + 少量单位 = AI可以做得简单但有效。

```
AIBehavior: enum
  AGGRESSIVE   # 优先攻击最近/血最少的目标
  DEFENSIVE    # 守在某个区域，被接近才反击
  SUPPORT      # 优先治疗/Buff队友
  HIT_AND_RUN  # 攻击后尽量拉开距离
  BOSS         # 特殊行动模式（固定技能循环）

EnemyUnit extends Unit:
  ai_behavior: AIBehavior
  target_priority: "nearest" | "lowest_hp" | "highest_threat" | "specific_class"
```

### 5.2 AI决策流程（简化版）

```
AI行动:
  1. 计算所有可能的 (移动目标格, 攻击目标, 使用技能) 组合
  2. 对每个组合评分:
     score = 预期伤害 × 权重
           + 击杀奖励（能击杀额外加分）
           + 位置评分（背对敌人扣分，占据有利地形加分）
           - 风险惩罚（移动到危险位置扣分）
  3. 选择最高分组合执行
```

### 5.3 分批入场

```
WaveConfig:
  waves: Array[Wave]

Wave:
  trigger: WaveTrigger
  enemies: Array[EnemySpawn]

WaveTrigger:
  type: "turn" | "enemy_count" | "hp_threshold"
  value: int   # 第N回合 / 剩余敌人≤N / Boss血量≤N%

EnemySpawn:
  unit_template: String  # 引用敌人模板ID
  position: Vector2i     # 入场位置
  delay: int             # 入场后的CT初始值
```

---

## 6. Roguelite循环：一次Run的结构

### 6.1 Run流程

```
一次Run:
  ┌─ 选择起始角色（单机选1-4个，联机各选1个）
  │
  ├─ [关卡1] 战斗 → 奖励选择（技能/遗物/回复 三选一）
  ├─ [关卡2] 战斗 → 奖励选择
  ├─ [事件] 随机事件（商店/休息/特殊遭遇）
  ├─ [关卡3] 战斗 → 奖励选择
  ├─ [关卡4] 精英战 → 高级奖励
  ├─ [事件] 随机事件
  ├─ [关卡5] Boss战
  │
  ├─ 进入下一幕（难度提升）...
  │
  └─ 最终Boss → Run结束
```

### 6.2 地图选择（杀戮尖塔式路径）

```
RunMap:
  floors: Array[Floor]

Floor:
  nodes: Array[MapNode]
  connections: Array[Connection]  # 节点间的路径

MapNode:
  type: "battle" | "elite" | "boss" | "shop" | "rest" | "event" | "treasure"
  difficulty: int
  preview: String  # 简要预览信息（如"3个近战敌人"）
```

### 6.3 Meta进度（Run间的持久升级）

```
MetaProgress:
  currency: int                  # 死亡/通关获得的永久货币
  unlocked_classes: Array[String]
  unlocked_relics: Array[String] # 解锁后才会出现在Run中
  upgrades: Dict[String, int]    # 永久升级（如+5%初始HP）
```

---

## 7. 联机架构

### 7.1 为什么轮动制简化了联机

传统战棋联机的难点是"我方回合所有单位都能操作"时的并行问题。轮动制下：
- **任何时刻只有1个单位行动** → 只需要同步1个玩家的输入
- 其他玩家处于"观战等待"状态
- 类似于回合制卡牌游戏的联机模型

### 7.2 指令同步模型

```
GameAction:
  actor_id: String        # 行动单位
  player_id: String       # 控制玩家
  action_type: "move" | "skill" | "wait" | "item"
  move_target: Vector2i | null
  skill_id: String | null
  skill_target: Vector2i | null

同步流程:
  1. TurnManager确定当前行动者 → 通知所有客户端
  2. 对应玩家客户端进入操作状态，其他客户端等待
  3. 玩家提交GameAction → 广播给所有客户端
  4. 所有客户端本地执行同一GameAction → 状态一致
  5. 回到步骤1
```

### 7.3 初期设计原则

- **先做单机，但所有游戏逻辑通过GameAction驱动**
- 单机时GameAction直接本地执行
- 联机时GameAction通过网络发送后再执行
- 这样联机只是给GameAction加一层网络传输，不需要重构游戏逻辑

```
# 单机模式
func execute_action(action: GameAction):
  game_state.apply(action)

# 联机模式（未来）
func execute_action(action: GameAction):
  network.broadcast(action)  # 发送给所有客户端
  # 收到确认后
  game_state.apply(action)   # 同一套逻辑
```

---

## 8. 数据驱动架构

### 8.1 所有内容用数据文件定义

```
/data
  /classes
    warrior.json
    archer.json
    mage.json
    rogue.json
  /skills
    slash.json
    power_strike.json
    fireball.json
    heal.json
  /enemies
    goblin.json
    skeleton_archer.json
    boss_dragon.json
  /maps
    forest_01.json
    cave_02.json
  /relics
    iron_shield.json
    speed_boots.json
  /events
    merchant.json
    mysterious_shrine.json
```

### 8.2 示例：技能数据

```json
{
  "id": "fireball",
  "name": "火球术",
  "damage_type": "magical",
  "power": 120,
  "hit_bonus": 10,
  "range": { "type": "diamond", "min": 2, "max": 4 },
  "area": { "type": "diamond", "size": 1 },
  "ct_cost": 25,
  "cooldown": 2,
  "effects": [
    { "type": "burn", "chance": 30, "duration": 3, "damage_per_tick": 10 }
  ],
  "description": "向目标投掷火球，爆炸范围1格，有几率附加燃烧"
}
```

### 8.3 好处

- 添加新职业/技能/敌人 = 新增JSON文件，不改代码
- Vibe coding时AI可以直接生成JSON数据
- 平衡调整只需改数值，不需要碰代码逻辑

---

## 9. 开发里程碑

### Phase 1: 网格原型（1-2周）
- [ ] Godot项目搭建 + TileMap网格
- [ ] 单位在网格上放置和显示（色块即可）
- [ ] 点击选择单位，显示移动范围（BFS）
- [ ] 点击目标格移动单位（A*寻路）
- [ ] 基础地形显示（不同颜色代表不同地形）

### Phase 2: 回合与战斗（2-3周）
- [ ] CT轮动系统实现
- [ ] 行动顺序预览UI
- [ ] 基础攻击（单体近战）
- [ ] 伤害公式 + 命中判定
- [ ] 单位死亡/移除
- [ ] 胜负判定（全灭）

### Phase 3: 技能与射程（2-3周）
- [ ] 技能数据加载（JSON）
- [ ] 射程显示（不同pattern）
- [ ] AOE范围预览和执行
- [ ] CT消耗权衡
- [ ] 2-3个技能实装测试

### Phase 4: 职业与AI（2-3周）
- [ ] 职业数据加载
- [ ] 4个基础职业实装
- [ ] 敌方AI基础版（评分系统）
- [ ] 敌人分批入场
- [ ] 完整一场战斗可玩

### Phase 5: Roguelite框架（3-4周）
- [ ] Run流程管理器
- [ ] 路径选择地图
- [ ] 战斗奖励（技能/遗物选择）
- [ ] 商店/休息事件
- [ ] Meta进度存储
- [ ] 完整一次Run可玩

### Phase 6: 联机（4-6周）
- [ ] GameAction网络序列化
- [ ] P2P连接（Godot高层API或Steam）
- [ ] 行动同步
- [ ] 等待/超时处理
- [ ] 联机角色选择
- [ ] 联机测试与调试

---

## 10. Godot项目结构建议

```
project/
├── scenes/
│   ├── battle/
│   │   ├── BattleScene.tscn      # 战斗主场景
│   │   ├── Grid.tscn              # 网格系统
│   │   ├── Unit.tscn              # 单位场景
│   │   └── UI/
│   │       ├── TurnOrderBar.tscn  # 行动顺序条
│   │       ├── ActionMenu.tscn    # 行动菜单
│   │       └── DamagePopup.tscn   # 伤害数字
│   ├── roguelite/
│   │   ├── RunMap.tscn            # 路径选择
│   │   ├── RewardScreen.tscn      # 奖励选择
│   │   └── ShopScreen.tscn        # 商店
│   └── menus/
│       ├── MainMenu.tscn
│       └── CharacterSelect.tscn
├── scripts/
│   ├── core/
│   │   ├── grid.gd                # 网格逻辑
│   │   ├── pathfinding.gd         # 寻路
│   │   ├── turn_manager.gd        # 回合管理
│   │   ├── battle_manager.gd      # 战斗流程
│   │   ├── damage_calculator.gd   # 伤害计算
│   │   └── game_action.gd         # 行动指令定义
│   ├── units/
│   │   ├── unit.gd                # 单位基类
│   │   ├── unit_stats.gd          # 属性系统
│   │   └── skill_executor.gd      # 技能执行
│   ├── ai/
│   │   └── enemy_ai.gd            # AI决策
│   ├── roguelite/
│   │   ├── run_manager.gd         # Run流程
│   │   ├── relic_system.gd        # 遗物系统
│   │   └── reward_generator.gd    # 奖励生成
│   └── network/
│       └── network_manager.gd     # 联机管理（后期）
├── data/
│   ├── classes/
│   ├── skills/
│   ├── enemies/
│   ├── maps/
│   └── relics/
└── assets/
    ├── sprites/    # 后期替换
    ├── tilesets/
    ├── ui/
    └── audio/
```
