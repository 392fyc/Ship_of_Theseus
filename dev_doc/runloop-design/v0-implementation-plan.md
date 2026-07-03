# run-loop v0 最小门循环 —— 实装架构方案

> 状态：实装蓝图（2026-07-04 起草）。唯一设计真源 = `runloop-reward-map-proposal.md`（第三轮定稿，§7 v0 范围、§6 数据结构）+ KB `run-loop.md` / `enemy-and-ai.md`。
> 本文档不新增任何设计裁决，只把「已定设计 + 现有代码事实」翻译成工程落地方案。标注三态沿用真源：**[已定]**（用户裁决/KB 正本）/ **[提案]**（方向建议待确认）/ **[占位]**（数字纯填坑）。另加一类 **[工程]** = 主代理的实现选择（非设计裁决，用户可叫停）。

---

## 0. 现有代码关键事实（研读实测，带 file:line，实装以此为准）

**战斗生命周期**
- 主场景 = `res://scenes/tactical/TacticalScene.tscn`（`project.godot:19`），启动即进战斗，**全仓无场景流程管理器、`change_scene` 零调用**。
- 战斗结束信号 `battle_ended(result)`（`scripts/tactical/tactical_scene.gd:35`，发出于 `_end_battle()` `:383`，result = `"victory"`/`"defeat"`）**当前无任何订阅者** → run-loop 战后接管的天然挂载点。
- 战斗后目前只弹结果遮罩 + ReturnButton（`_on_return_pressed` `:386` = `reload_current_scene()`）→ run-loop 须接管/隐藏该按钮。
- 胜负判定在 `tactical_scene.gd:_check_battle_end()`（`:348-361`）：己方全灭=败 / 敌方全灭=胜，无其它胜利条件。
- 战斗开始硬编码：`_ready()`（`:78-132`）→ `initialize_battle("test_arena")`（`:91`，map_id 硬编码）→ 循环常量 `PLAYER_UNITS`（`:39`，仅剑圣）/ `ENEMY_UNITS`（`:47`，5 个 test_*）`spawn_unit` → `start_battle()`（`:127`）。
- `spawn_unit(class_id, pos, faction)`（`tactical_manager.gd:272-291`）先查 `DataLoader.classes` 再查 `DataLoader.enemies`，可复用喂任意敌人清单；**但无 spawn 后加成 hook**（词条/数值增强需新增）。
- `debug_harness_enabled`（`tactical_scene.gd:62`，`@export` 默认 **true**）→ 置 `debug_harness_active=true`，会让敌人 AI 不主动行动（`_do_enemy_turn` `:357` 门控）+ 木桩再生/复活。**正式 run-loop 战斗必须 `debug_harness_enabled=false`**，否则敌人不动。

**账本现状（全部需从零建或接线）**
- 金币：**完全不存在**（`scripts/**` 无 `gold`）。
- 经验/等级：UI 死占位（`bottom_dashboard.gd:374/386` 读 `state.get("level",1)`/`get("xp",0)` 默认值；`get_dashboard_data()` 根本不提供 level/xp 键）。
- `unit_stats.gd:78 level_up()`（概率成长+保底）实现完整但**无调用方，休眠**。

**数据/加载**
- `DataLoader`（`scripts/data/data_loader.gd`）= 唯一游戏 autoload，加载 8 目录（classes/skills/buffs/enemies/maps/relics/buildings/events），按 JSON `id` 建索引。**新增一类数据只需改 2 处**：`:3-10` 声明 dict + `load_all()` `:17-25` 加一行 `_load_directory`。
- `data/runloop/`、`data/waves/`、`data/terrain/` **未接入 DataLoader**（上一 session 冒烟测试自行读文件）。
- 空/缺目录：`data/waves/`（空）、`data/relics/`（空）、`data/affixes/`（不存在）、`data/equipment/`（不存在）。
- 「地图 + 波次 → 一场战斗」的数据驱动装配器**不存在**（地图 JSON 的 `wave_config` 字段无人消费）→ v0 必建件。

**架构惯例**
- `GameAction`（`scripts/core/game_action.gd`）= 单一 `RefCounted` 数据类 + 静态工厂/校验器，校验统一返回 `{ok:bool, reason:String}`；执行者是 `TacticalManager`；`action.data` 保持纯 JSON 可序列化（服务联机广播意图）。
- 信号过去时态（`unit_killed`/`battle_ended`/`turn_ended`）；UI 请求类用 `*_requested`。
- 显式类型声明无处不在（含 for 循环变量）；JSON 读取统一「显式转型 + 缺省值」`int(d.get("k", 0))`。
- headless `--script` 测试：可达脚本用 `preload` 而非 class_name；断言放 `_process` 首帧；避免引重全局 class_name（见 [[sot-godot-testing]]）。
- 调试功能门控模式：`debug_harness_active` 默认 false、仅测试场景置 true = 「纯加法、正式战斗 inert」的既定加法方式。

**词条挂载先例（心眼）**
- 心眼无独立 skill JSON，参数内联在 `data/classes/swordsman.json:38-48` 的 `sword_qi_config` block；`unit.gd:setup()`（`:100`）→ `_init_sword_qi_resource()`（`:712-726`）读进缓存字段；非剑圣无该 block → 直接 return，不影响其它职业。
- 生效两模型：**push**（写 `crit_bonus` 字段，`_apply_xinyan_passive` `:731-734`；`crit_bonus`/`crit_avoid_bonus` `:32/:34` 已注释为「来源无关加法钩子」）；**pull**（`get_effective_stat` `:252-261` 实时特判 SPD 阈值/印记属性）。
- `get_effective_stat`（`unit.gd:235`）是所有属性读取唯一入口，`damage_calculator` 全程走它 → 数值词条最干净的加/乘区。
- 敌我同一个 `setup()` / `UnitStats` / 读取链，差异仅在 JSON 内容 → **敌人 JSON 天然可带 `affixes` block**。
- `buffs` 系统（`BuffEffect`）= 有时限/可叠加/可驱散/每回合 tick/有图标；词条=永久内在特性，**不应走 BuffEffect**（与设计[已定]「词条≠buff/debuff」一致）。

---

## 1. v0 宿主架构 [工程]

三层分离，逻辑层脱离场景可 headless 单测：

```
RunManager (autoload, scripts/roguelite/run_manager.gd)
  持有 RunState：difficulty / act / stage / gold / 每角色 exp / 队伍 roster
                / Convoy / pity 计数 / 门历史 / 待发放奖励
  纯逻辑 API（无渲染依赖）：
    start_run(run_config, act_config)
    on_battle_resolved(result)      # 消费 battle_ended
    generate_door_group()           # 委托 DoorGenerator
    choose_door(index)              # 定下一关内容
    build_battle_plan()             # 委托 BattleAssembler → {map, player_roster, enemy_roster}
    settle_rewards(door_option)     # 委托 RewardResolver
    enter_prep() / confirm_departure()
    is_shop_prep() / is_run_over()

  子模块（RefCounted，纯逻辑，各自单测）：
    DoorGenerator   scripts/roguelite/door_generator.gd   # exp_door_generation 内核移植
    RewardResolver  scripts/roguelite/reward_resolver.gd  # 每角色独立掉落 + 固定金币经验
    BattleAssembler scripts/roguelite/battle_assembler.gd # (map_id, wave_id) → 敌人清单+词条
    RunState        scripts/roguelite/run_state.gd        # run 运行时状态数据类
```

**场景层 [工程]**：单一 run 宿主场景 `scenes/roguelite/RunScene.tscn` + `scripts/roguelite/run_scene.gd`，在其中 `add_child` 切换三个子视图：
- **战斗子视图** = 实例化 `TacticalScene`，实例化后**先设 `debug_harness_enabled=false` + 注入 battle_plan**，再 add_child；连 `battle_ended` → `RunManager.on_battle_resolved`。
- **门选择子视图** = `scenes/roguelite/DoorSelect.tscn`（2–3 扇门按钮 + 奖励图标 + 精英骷髅标 + 特殊词条预告）。
- **Prep 子视图** = `scenes/roguelite/PrepScene.tscn`（恢复 / 运输队 / 查看情报 / 确认出发；商店 Prep 多一个购物面板）。

选宿主 `add_child` 而非 `change_scene_to_packed` 的理由：run 状态已在 autoload 安全，但 `add_child` 能在战斗子场景 `_ready` **之前**设好 `debug_harness_enabled=false` 与注入数据，避开现有硬编码 `_ready` 流程；UI 先功能后美化，v0 子视图用最简 Control。

**改 `tactical_scene.gd` 支持注入模式 [工程]**（纯加法、门控，不破坏现有测试场景）：
- 新增 `@export var run_injected := false` + 注入数据字段（map_id / player_roster / enemy_roster）。
- `_ready()`：`if run_injected` → 走注入分支（用注入的 roster 替代 `PLAYER_UNITS`/`ENEMY_UNITS` 常量、用注入 map_id 替代 `"test_arena"`、`debug_harness_enabled` 由宿主设 false）；`else` → **完全保留现有硬编码行为**（剑圣手动测试/木桩/控制台不受影响）。
- 保证 8156c70 的木桩/控制台/forecast 回归全绿 = 注入分支的硬性验收线。

---

## 2. 词条挂载：方案 A（与心眼同构）[已定口径 → 工程落地]

设计[已定]「词条=类似人物被动的技能、非 buff/debuff」→ 工程上唯一自洽路径 = 沿用心眼的「内联/引用 config → 缓存字段 → get_effective_stat/时机钩子」，**不走 BuffEffect**。

- **数据**：`data/affixes/base/*.json` 与 `data/affixes/special/*.json`，DataLoader 加载合并进 `affixes` dict（加载器加 2 处，两子目录各一行或递归）。单个 affix schema：
  ```jsonc
  { "id": "af_...", "name": "...", "pool": "base"|"special",
    "type": "stat_flat"|"stat_pct"|"on_hit"|"on_kill"|"on_turn_start"|"on_counter"|...,
    "params": { ... },              // 数值全在此，禁代码硬编码
    "is_passive": true, "description": "..." }
  ```
- **单位挂载**：`unit.gd:setup()` 末尾加 `_init_affixes(class_data)` —— 读单位/波次注入的 `affixes:[id]` 列表进缓存字段（照 `_init_sword_qi_resource`）；无 affixes 的单位直接 return。
- **数值类词条**：`stat_flat`/`stat_pct` 在 `get_effective_stat` 末尾追加分发分支，或写 `crit_bonus`/`crit_avoid_bonus` 已有钩子。
- **触发类词条**：集中到单一分发器 `_apply_affixes(timing, attacker, defender, action_data)`，挂在 `_apply_sword_qi_on_hit`（`tactical_manager.gd:2346`）旁 / `_on_turn_started`（`:310`）。
- **头目「数值增强」[占位 乘区值]**：新开具名乘区 `affix_multiplier`（`damage_calculator` 的 `action_data`，与 `relic_multiplier` 并列），避免与遗物/技能乘区语义混淆；或对波次注入的头目直接 scale `base_stats`。v0 二选一按最简，标 [工程]。
- **可见性**：`special_affix` 门上可见（DoorOption.preview 带其 id/name/描述）；`base_affixes` 进房前不可见、[提案] 战斗内点选可读——v0 先做「特殊可见」（选门循环验证所需），基础点选可读留 [提案] 后置。

---

## 3. 波次数据层：`data/waves/*.json` [工程，真源已隐含]

真源 `DoorGenConfig.battle_pools = {normal:[waveId], elite:[waveId]}`、`DoorOption.battle = {map_id, enemy_config}` 已隐含波次数据文件存在（`enemy_config` = wave id）。建：

```jsonc
// data/waves/wave_act1_normal_01.json
{ "id": "wave_act1_normal_01",
  "enemies": [
    { "class_id": "goblin_melee", "spawn_pos": [x,y], "tier": "normal" },
    { "class_id": "goblin_melee", "spawn_pos": [x,y], "tier": "lesser_elite",
      "affixes": ["af_..."] }               // 小精英 1–3 基础词条
  ] }
// data/waves/wave_act1_elite_01.json （精英房替身头目）
{ "id": "...", "enemies": [
    { "class_id": "...", "spawn_pos": [x,y], "tier": "elite_chief",
      "affixes": ["af_...","af_...","af_..."],   // 3–5 基础
      "special_affix": "afs_...",                // +1 特殊（门上可见）
      "stat_scale": 1.35 } ] }                    // [占位] 数值增强
```

`BattleAssembler.build(map_id, wave_id, player_roster)` → 读 wave + map，产 `{player_units:[{class_id,pos}], enemy_units:[{class_id,pos,affixes,special_affix,stat_scale}]}` 喂 `tactical_scene` 注入分支 → `spawn_unit` + `_init_affixes`。

act1_config 现有 6 个悬空波次 id（3 normal + 2 elite + 1 boss）+ 事件里 `wave_event_mine_ambush` → 全部建对应文件（含 spawn_pos，占位坐标按各地图 8×8 布局）。

**玩家队伍 roster [占位]**：v0 先固定一个 4 人预设（或沿用现有职业数据里可用职业），存 RunManager；正式版接存档。

---

## 4. 数据层新建/扩展清单（任务 #3）

| 目录/文件 | 内容 | 数量 | 标注 |
|---|---|---|---|
| `data/affixes/base/*.json` | 基础词条（被动技能）：反击强化/先手部署/受治疗减半/拆建筑/控制区扩大方向 | 5 个左右 | [占位] |
| `data/affixes/special/*.json` | 特殊词条（房间签名级） | 1–2 个 | [占位] |
| `data/waves/*.json` | 6 波次（3 normal + 2 elite + 1 boss）+ 1 事件伏击 | 7 | [工程] spawn_pos [占位] |
| `data/relics/*.json` | 简单遗物条目（经济类 + 数值类方向） | 8–12 | [占位] |
| `data/equipment/*.json` | 武器/防具各几件（L4 两槽渐进） | 各 3–4 | [占位] |
| DataLoader 扩展 | 加载 affixes(两池)/waves/equipment(+relics 已有钩子) | 改 2+ 处 | [工程] |
| `run_config.json` / `act1_config.json` | 已存在，v0 沿用；如需补字段（如 boss.special_affix 引用）随实装补 | — | 沿用 |
| 冒烟测试扩展 | `test_runloop_data_smoke.gd` 把「enemy_config 只查非空」升级为 wave 文件存在性校验；新增 affixes/relics/equipment schema 校验段 | — | 回归护栏 |

前置内容依赖（真源 §7）：`relics-system.md` / `equipment.md` 两 KB 缺口 → v0 用最小池数据文件 + `_note` 简注代替，正式版前补（记入迭代清单，不阻塞 v0）。

---

## 5. 任务 → §7 八项映射与依赖顺序

| 任务 | §7 项 | 依赖 | 产物 |
|---|---|---|---|
| #3 数据层 | 数据基座 | — | affixes/waves/relics/equipment + DataLoader + 冒烟扩展 |
| #4 门生成器 | §7.3 | #3 | `door_generator.gd` + headless 回归（约束扫描+保底按出现） |
| #5 run 骨架 | §7.1/7.7 | #3 | `run_manager.gd`/`run_state.gd`/`reward_resolver.gd` + 8 关状态机 + 替身 Boss + 金币/经验账本 + 接线 `level_up()` |
| #9 敌阶词条 | §7.6 | #3 | `_init_affixes`/`_apply_affixes`/affix_multiplier + `battle_assembler.gd` + headless 回归 |
| #6 门流程 | §7.2 | #4,#5 | RunScene 宿主 + DoorSelect UI + tactical_scene 注入模式 + battle_ended 接线 |
| #8 Prep | §7.5 | #5 | PrepScene（恢复/运输队/情报/出发）+ Convoy |
| #7 固定商店 | §7.4 | #8 | 商店面板嵌入两个固定 Prep（幕中[占位第4关后]+Boss前） |
| #10 奖励结算 | §7.7 | #5 | 每角色独立掉落 + 每图固定金币经验（reward_resolver 内） |
| #11 集成验证 | §7.8 | 全部 | 整轮 headless 模拟 + 全量回归 + 手动测试清单 + 记忆/KB 同步 |

每个子系统落地即写 headless 回归（照 `test_runloop_data_smoke.gd` 模式）。逻辑层（RunManager/DoorGenerator/RewardResolver/BattleAssembler）优先纯逻辑单测；场景/UI 层走手动测试清单（headless 无渲染无鼠标）。

---

## 6. [提案]/[占位]/[工程] 决策台账（实装时保持标注）

**[工程]（主代理定，用户可叫停）**
1. 宿主架构 = RunManager autoload + 纯逻辑子模块 + RunScene 宿主 add_child 子视图。
2. 词条 = 方案 A（内联/引用 config → 缓存字段 → get_effective_stat/`_apply_affixes` 分发器），不走 BuffEffect。
3. 改 `tactical_scene.gd` 加注入模式（`run_injected` 门控），保留现有硬编码行为不变。
4. 波次数据层 `data/waves/*.json`（真源已隐含 waveId 引用）。
5. 头目数值增强用具名 `affix_multiplier` 乘区或 base_stats scale。
6. `same_offer_types_distinct` 做成可配置开关（默认读数据 true），避免 [提案] 被硬编码固化。

**[提案]（照真源带入、保持标注，不阻塞）**：恢复按角色拒绝/出发确认提示/拒绝不另给奖励/低血触发条目需求；幕进度条；基础词条战斗内点选可读；经验共享 vs 按角色独立（v0 先按角色独立，与独立掉落一致）。

**[占位]（数字填坑，随时可调）**：门权重/精英房权重/保底 N=3/恢复量 50%/固定金币 40 经验 30/Boss 包/幕中商店第 4 关后/词条池条目数/wave spawn 坐标/头目 stat_scale/玩家 roster。

---

## 7. 勿误用（真源纪律）

- 唯一实装真源 = `runloop-reward-map-proposal.md` 第三轮定稿；`research-raw-2026-07-02.json` 是第一轮调研**归档**（含作废的分支地图/线性方案），勿当现行设计。
- 已废弃勿复活：线性 MapGraph、商店门（含「回当前进度重选门」语义）、A/B/C 三案、锚点 1/5/7、恢复随幕递减、特性=buff/debuff 口径。
- `exp_door_generation.gd` 头部警告块：商店重掷逻辑=死代码勿据此实装商店、保底为旧「按选中」语义须改「按出现」、脚本是起点参考非实装规格。
- 已闭合裁决不重开（门数下限 2、商店固定插入、保底按出现、词条≠buff、Relic 正典 ADR-010）。
