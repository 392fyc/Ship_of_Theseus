# VA-5 通用行动资源栏实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 M/A/S 从地图单位周围迁移到技能栏正上方的独立横条，并通过现有战斗仪表盘刷新链实时同步。

**Architecture:** 新建只消费字典的 `ActionResourceBar`，由 `BottomDashboard` 创建、定位和控制可见性；`TacticalManager` 只增加结构化状态输出。最后从 `Unit._rebuild_status_icons()` 删除行动徽记分支，保留 Buff/Debuff 分支，避免 UI 和单位世界空间继续混合职责。

**Tech Stack:** Godot 4.6.3、GDScript、PowerShell、Git、GitHub CLI

**Spec:** `docs/superpowers/specs/2026-08-29-action-resource-bar-design.md`

## Milestone

**VA-5 阶段成果：** 战棋底层通用行动资源 M/A/S 在真实战斗中统一显示于技能栏正上方，并由现有战斗状态链实时驱动；地图单位只保留 Buff/Debuff 状态显示。

**完整完成条件：**

1. `ActionResourceBar`、仪表盘数据接入和地图徽记移除均完成，且不改变任何行动经济或职业资源规则。
2. 独立组件、仪表盘布局、真实移动、标准行动、迅捷技能、回合开始路径和 Buff 边界均有先红后绿的自动测试。
3. 当前全部 `tests/test_*.gd` 在 Godot 4.6.3 下全绿，候选分支经过独立任务审查和整分支终审。
4. 两张真实 `TacticalScene` 的 `1280×720` 原始截图生成并通过结构化视觉检查，随后由用户明确视觉通过。
5. 任务分支经受控入口发布，PR 已合并到 `develop`；最新 `develop` 上重新完成 Godot 导入、全量回归、聚焦核验和干净工作树检查。
6. GitHub issue #18 关闭，Mercury 兼容任务回执完整，且没有已知必需工作遗留。

## Global Constraints

- 工作分支固定为 `codex/issue-18-action-resource-bar`，起点固定为 `a54d00f11045234523393bb4c9ae4c0faa7dad1f`。
- 只实现 M/A/S；不得显示 R，不得通用化剑气、印记或遗物。
- 不改变 `movement_used`、`standard_used`、`swift_used` 的规则、消费或复位逻辑。
- 不新增第二套战斗 UI 刷新信号；只使用现有 `dashboard_state_changed` 链。
- `ActionResourceBar` 不得读取 `Unit`，只消费 `Dictionary`。
- 地图单位移除 M/A/S 后必须保留 Buff/Debuff 的现有 `StatusIcons`、`STATUS_BADGE_Y` 和样式行为。
- 所有生产改动必须先有会因缺少该行为而失败的真实测试，并明确观察失败，再写最小实现。
- 使用 Godot 4.6.3；新工作树运行测试前先执行一次无头编辑器导入以生成 `.godot` 缓存。
- 不直接提交或推送到 `develop`；发布必须使用 `scripts/codex/sot-publish.ps1`。

## File Map

| 文件 | 职责 |
|---|---|
| `scripts/ui/action_resource_bar.gd` | 三段行动资源横条、状态映射和暗黑哥特视觉 |
| `scripts/ui/bottom_dashboard.gd` | 创建资源栏、传入状态、定位在技能栏上方并参与避让 |
| `scripts/core/tactical_manager.gd` | 输出结构化 `action_resources` |
| `scripts/units/unit.gd` | 停止创建地图 M/A/S 标签，保留 Buff/Debuff |
| `tests/test_action_resource_bar.gd` | 独立组件状态和可辨识度回归 |
| `tests/test_action_resource_dashboard.gd` | 仪表盘数据合同、可见性、布局和避让回归 |
| `tests/test_action_resource_runtime.gd` | 真实场景刷新链、消费、复位和地图标签边界回归 |
| `tests/test_unit_map_token_visual.gd` | 正式棋子上的 Buff 标签保留与 M/A/S 缺席回归 |
| `tests/capture_action_resource_bar_tactical.gd` | 真实 `TacticalScene` 两态视觉证据捕获 |

## Pre-execution Checkpoint

主代理完成规格与计划自检后，先在当前任务工作树统一定义执行变量并补齐新工作树缓存：

```powershell
$godot = 'D:\Download\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe'
$project = (git rev-parse --show-toplevel).Trim()
if (-not (Test-Path -LiteralPath (Join-Path $project '.godot\global_script_class_cache.cfg'))) {
	& $godot --headless --editor --path $project --quit
	if ($LASTEXITCODE -ne 0) { throw 'Godot import failed' }
}
git status --short
```

Expected: `$godot` 指向 Godot 4.6.3，`$project` 指向任务工作树；导入缓存存在，受版本控制文件无内容变化。

然后提交两份工程文档：

```powershell
git add docs/superpowers/specs/2026-08-29-action-resource-bar-design.md docs/superpowers/plans/2026-08-29-action-resource-bar.md
git commit -m "docs(ui): plan action resource bar migration" -m "Constraint: Keep class resources and relics out of VA-5`nConfidence: high`nScope-risk: narrow"
```

Expected: 文档提交成功，之后工作树清洁。

---

### Task 1: 独立行动资源栏组件

**Files:**
- Create: `scripts/ui/action_resource_bar.gd`
- Create: `tests/test_action_resource_bar.gd`

**Interfaces:**
- Consumes: `Dictionary`，字段为 `movement_used`、`standard_used`、`swift_used`。
- Produces: `class_name ActionResourceBar`；`func update_resources(resources: Dictionary) -> void`；稳定的 `_segments: Dictionary`，键为 `movement`、`standard`、`swift`。

- [ ] **Step 1: 写组件失败测试**

创建 `tests/test_action_resource_bar.gd`，沿用仓库 `SceneTree` 测试模式。测试必须直接加载真实脚本并验证这些行为：

```gdscript
const ActionResourceBarScript := preload("res://scripts/ui/action_resource_bar.gd")

func _run() -> void:
	var bar: PanelContainer = ActionResourceBarScript.new()
	root.add_child(bar)
	bar.update_resources({
		"movement_used": false,
		"standard_used": true,
		"swift_used": false,
	})
	_eq("资源顺序固定", bar._segments.keys(), ["movement", "standard", "swift"])
	var original_ids: Array[int] = []
	for resource_id: String in ["movement", "standard", "swift"]:
		original_ids.append((bar._segments[resource_id] as Object).get_instance_id())
	_check("M 可用", not bar._segments["movement"].spent)
	_check("A 已用", bar._segments["standard"].spent)
	_check("S 可用", not bar._segments["swift"].spent)
	_eq("M 标题", bar._segments["movement"].title_label.text, "M 移动")
	_eq("A 状态文字", bar._segments["standard"].state_label.text, "已用")
	_check("已用态有斜向缺口", bar._segments["standard"].glyph.spent)
	bar.update_resources({"movement_used": true, "standard_used": false, "swift_used": true})
	var updated_ids: Array[int] = []
	for resource_id: String in ["movement", "standard", "swift"]:
		updated_ids.append((bar._segments[resource_id] as Object).get_instance_id())
	_eq("重复更新不会重建段", updated_ids, original_ids)
	_check("第二次状态精确", bar._segments["movement"].spent and not bar._segments["standard"].spent and bar._segments["swift"].spent)
```

测试还必须断言三个段的最小尺寸都是 `Vector2(76.0, 30.0)`，外层不会自行读取或保存 `Unit`。

- [ ] **Step 2: 运行红灯**

```powershell
$godot = 'D:\Download\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe'
$project = (git rev-parse --show-toplevel).Trim()
& $godot --headless --path $project --script res://tests/test_action_resource_bar.gd
```

Expected: 非零退出；原因是 `action_resource_bar.gd` 尚不存在或 `ActionResourceBar` 尚未提供合同。

- [ ] **Step 3: 写最小组件实现**

创建 `scripts/ui/action_resource_bar.gd`。固定定义：

```gdscript
class_name ActionResourceBar
extends PanelContainer

const RESOURCE_DEFINITIONS: Array[Dictionary] = [
	{"id": "movement", "flag": "movement_used", "title": "M 移动", "accent": Color("#6FAED1")},
	{"id": "standard", "flag": "standard_used", "title": "A 行动", "accent": Color("#D17A50")},
	{"id": "swift", "flag": "swift_used", "title": "S 迅捷", "accent": Color("#D5BC59")},
]

var _segments: Dictionary = {}

func update_resources(resources: Dictionary) -> void:
	for definition: Dictionary in RESOURCE_DEFINITIONS:
		var resource_id: String = str(definition["id"])
		var flag: String = str(definition["flag"])
		(_segments[resource_id] as ResourceSegment).set_spent(bool(resources.get(flag, false)))
```

实现内部 `ResourceGlyph` 和 `ResourceSegment`：菱形由 `_draw()` 运行时绘制；`spent == true` 时绘制斜向缺口。段标题、`可用/已用` 状态文字、外壳和段样式全部按设计规格精确取色与尺寸。`_ready()` 只构建一次三段。

- [ ] **Step 4: 运行绿灯并做突变检查**

重跑 `test_action_resource_bar.gd`，Expected: exit 0。临时确认把 `standard_used` 映射成错误字段会使“A 已用”断言失败，然后恢复正确实现并再次通过。

- [ ] **Step 5: 提交**

```powershell
git add scripts/ui/action_resource_bar.gd tests/test_action_resource_bar.gd
git commit -m "feat(ui): add action resource bar component" -m "Constraint: Render only M/A/S from dictionary state`nConfidence: high`nScope-risk: narrow"
```

---

### Task 2: 仪表盘数据合同与布局接入

**Files:**
- Modify: `scripts/core/tactical_manager.gd`
- Modify: `scripts/ui/bottom_dashboard.gd`
- Create: `tests/test_action_resource_dashboard.gd`

**Interfaces:**
- Consumes: Task 1 的 `ActionResourceBar.update_resources(resources)`。
- Produces: `get_dashboard_data().action_resources`；`BottomDashboard._action_resource_bar`；技能栏上方 6 像素的响应式布局。

- [ ] **Step 1: 写数据、可见性和布局失败测试**

创建 `tests/test_action_resource_dashboard.gd`，实例化真实 `TacticalScene` 和真实 `BottomDashboard`。必须验证：

```gdscript
var data: Dictionary = tactical_manager.get_dashboard_data()
var resources: Dictionary = data.get("action_resources", {})
_eq("movement_used 透传", resources.get("movement_used"), current_unit.movement_used)
_eq("standard_used 透传", resources.get("standard_used"), current_unit.standard_used)
_eq("swift_used 透传", resources.get("swift_used"), current_unit.swift_used)

dashboard.size = Vector2(1280.0, 720.0)
dashboard.update_state(data.merged({"visible": true, "show_actions": true}, true))
_check("玩家操作态显示行动资源栏", dashboard._action_resource_bar.visible)
_check("资源栏与技能栏精确间隔 6 像素", is_equal_approx(dashboard._skill_bar.position.y - (dashboard._action_resource_bar.position.y + dashboard._action_resource_bar.size.y), 6.0))
_check("资源栏与技能栏水平中心一致", is_equal_approx(dashboard._action_resource_bar.position.x + dashboard._action_resource_bar.size.x * 0.5, dashboard._skill_bar.position.x + dashboard._skill_bar.size.x * 0.5))
var expected_top: float = dashboard.size.y
for control: Control in [dashboard._info_panel, dashboard._relic_panel, dashboard._action_shell, dashboard._skill_bar, dashboard._action_resource_bar]:
	if control.visible:
		expected_top = minf(expected_top, control.position.y)
_check("浮窗避让取全部可见底栏控件的最小 Y", is_equal_approx(dashboard.get_content_top_y(), expected_top))

for control: Control in [dashboard._info_panel, dashboard._relic_panel, dashboard._action_shell, dashboard._skill_bar]:
	control.visible = false
_check("只保留行动资源栏时仍参与避让", is_equal_approx(dashboard.get_content_top_y(), dashboard._action_resource_bar.position.y))

dashboard.update_state(data.merged({"visible": true, "mode": "enemy", "show_actions": false}, true))
_check("敌方信息态隐藏行动资源栏", not dashboard._action_resource_bar.visible)
```

另测 `action_resources` 缺失时即使 `show_actions == true` 也隐藏，避免显示猜测状态。

- [ ] **Step 2: 运行红灯**

运行 `test_action_resource_dashboard.gd`。Expected: 因 payload、控件和布局尚不存在而失败。

- [ ] **Step 3: 增加结构化 payload**

在 `TacticalManager.get_dashboard_data()` 的顶层字典增加：

```gdscript
"action_resources": {
	"movement_used": info_unit.movement_used,
	"standard_used": info_unit.standard_used,
	"swift_used": info_unit.swift_used,
},
```

不删除现有 `status_text`，不修改行动规则。

- [ ] **Step 4: 接入 BottomDashboard**

在 `bottom_dashboard.gd`：

```gdscript
const ActionResourceBarScript: GDScript = preload("res://scripts/ui/action_resource_bar.gd")
const ACTION_RESOURCE_GAP_Y: float = 6.0
var _action_resource_bar: Control = null
```

`_build_ui()` 在创建 `_skill_bar` 后创建一次资源栏。`update_state()` 提取 `action_resources`，调用 `update_resources()`，仅在 `show_actions` 且字典非空时显示。`_layout_dashboard()` 先布局技能栏，再把资源栏水平中心对齐，并令：

```gdscript
var resource_y: float = skill_y - resource_sz.y - ACTION_RESOURCE_GAP_Y
```

`get_content_top_y()` 的枚举加入 `_action_resource_bar`。所有空引用防护同步覆盖该控件。

- [ ] **Step 5: 运行聚焦回归**

运行：

```powershell
$godot = 'D:\Download\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe'
$project = (git rev-parse --show-toplevel).Trim()
& $godot --headless --path $project --script res://tests/test_action_resource_dashboard.gd
& $godot --headless --path $project --script res://tests/test_skillbar_v3_ui.gd
& $godot --headless --path $project --script res://tests/test_swordsman_skillbar.gd
```

Expected: 三项退出码均为 0；剑气、印记和技能栏原有断言不变。

- [ ] **Step 6: 提交**

```powershell
git add scripts/core/tactical_manager.gd scripts/ui/bottom_dashboard.gd tests/test_action_resource_dashboard.gd
git commit -m "feat(ui): wire action resources into battle dashboard" -m "Constraint: Reuse dashboard_state_changed refresh path`nConfidence: high`nScope-risk: moderate"
```

---

### Task 3: 移除地图行动徽记并验证实时刷新

**Files:**
- Modify: `scripts/units/unit.gd`
- Modify: `tests/test_unit_map_token_visual.gd`
- Create: `tests/test_action_resource_runtime.gd`

**Interfaces:**
- Consumes: Task 2 的 payload 和底栏控件。
- Produces: 地图 `StatusIcons` 只含 Buff/Debuff；真实场景的消费与复位状态同步证明。

- [ ] **Step 1: 写地图边界失败测试**

在 `test_unit_map_token_visual.gd` 中，在添加 Buff 前取得 `StatusIcons`，断言其子节点中没有文本恰为 `M`、`A`、`S`。依次调用三个 `consume_*_resource()` 和 `refresh_status_icons()` 后重复断言；添加真实 Buff 后仍能通过 `_find_status_label()` 找到它且 Y 等于 `Unit.STATUS_BADGE_Y`。

- [ ] **Step 2: 写真实刷新链失败测试**

创建 `tests/test_action_resource_runtime.gd`，实例化真实 `TacticalScene`，取得 `tactical_manager`、当前玩家单位和 `bottom_dashboard`。测试连接到真实 `dashboard_state_changed` 以记录事件次数，但不得主动调用 `_emit_dashboard_state_changed()`。每个状态变化必须通过生产入口触发：

```gdscript
var _dashboard_signal_count: int = 0

func _on_dashboard_state_changed() -> void:
	_dashboard_signal_count += 1

func _test_runtime_paths(tactical_manager: TacticalManager, unit: Unit, enemy: Unit) -> void:
	tactical_manager.dashboard_state_changed.connect(_on_dashboard_state_changed)

	# 回合开始：由 TurnManager 的真实信号触发 TacticalManager._on_turn_started，
	# 该路径调用 reset_turn_state() 和 _prepare_player_turn()。
	unit.consume_movement_resource()
	unit.consume_standard_resource()
	unit.consume_swift_resource()
	var before_turn_start: int = _dashboard_signal_count
	tactical_manager.turn_manager.current_unit = unit
	tactical_manager.turn_manager.turn_started.emit(unit)
	await process_frame
	_check("回合开始自动发出仪表盘刷新", _dashboard_signal_count > before_turn_start)
	_check("回合开始三项可用", _bar_matches(false, false, false))

	# 移动：调用真实 _execute_move()，完成移动后由 _complete_move_phase() 自动发信号。
	var move_target: Vector2i = _find_empty_neighbor(tactical_manager, unit.grid_position)
	var before_move: int = _dashboard_signal_count
	await tactical_manager._execute_move(unit, move_target)
	await process_frame
	_check("移动完成自动发出仪表盘刷新", _dashboard_signal_count > before_move)
	_check("移动后仅 M 已用", _bar_matches(true, false, false))

	# 标准行动：通过真实 GameAction 和 _execute_attack_from_input()；目标使用高血木桩，
	# 保证行动结束后仍能读取资源状态。
	var attack: GameAction = GameAction.make_attack(unit, enemy)
	attack.data.merge(tactical_manager._build_basic_attack_action_data(unit, enemy), true)
	var before_attack: int = _dashboard_signal_count
	tactical_manager._execute_attack_from_input(attack)
	await process_frame
	_check("标准行动自动发出仪表盘刷新", _dashboard_signal_count > before_attack)
	_check("标准行动后 M/A 已用", _bar_matches(true, true, false))

	# 独立新回合后，经真实技能构造和 _execute_skill_from_input() 使用迅捷技能招架。
	tactical_manager.turn_manager.turn_started.emit(unit)
	await process_frame
	tactical_manager._selected_skill_id = "swordsman_zhaojia"
	var swift_action: GameAction = tactical_manager._build_skill_action(unit, unit.grid_position, unit)
	var before_swift: int = _dashboard_signal_count
	tactical_manager._execute_skill_from_input(swift_action)
	await process_frame
	_check("迅捷技能自动发出仪表盘刷新", _dashboard_signal_count > before_swift)
	_check("迅捷技能后仅 S 已用", _bar_matches(false, false, true))
```

测试必须使用现有测试辅助方式把攻击者与木桩放在相邻有效格，并显式检查 `move_target` 与 `swift_action` 有效。最后再次通过 `turn_started.emit(unit)` 验证三项恢复；每一步同时断言单位 `StatusIcons` 不含 M/A/S。

- [ ] **Step 3: 运行红灯**

运行 `test_unit_map_token_visual.gd` 和 `test_action_resource_runtime.gd`。Expected: 前者因仍有地图 M/A/S 失败；后者至少证明当前资源栏刷新或地图边界尚未满足完整合同。

- [ ] **Step 4: 删除世界空间行动徽记**

从 `Unit` 删除 `ACTION_BADGE_Y` 和 `_rebuild_status_icons()` 中的 `action_badges` 数组及循环。保留清空旧节点、Buff/Debuff 构建、`STATUS_BADGE_STEP`、`STATUS_BADGE_Y` 与 `_make_badge()`；不得修改 Buff/Debuff 颜色或位置。

- [ ] **Step 5: 运行聚焦回归并提交**

运行：

```powershell
$godot = 'D:\Download\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe'
$project = (git rev-parse --show-toplevel).Trim()
& $godot --headless --path $project --script res://tests/test_unit_map_token_visual.gd
& $godot --headless --path $project --script res://tests/test_action_resource_runtime.gd
& $godot --headless --path $project --script res://tests/test_action_cost_free.gd
```

Expected: 三项退出码均为 0。

```powershell
git add scripts/units/unit.gd tests/test_unit_map_token_visual.gd tests/test_action_resource_runtime.gd
git commit -m "fix(ui): remove action badges from map units" -m "Constraint: Preserve Buff and Debuff status rendering`nConfidence: high`nScope-risk: narrow"
```

---

### Task 4: 真实战斗画面与全量回归

**Files:**
- Create: `tests/capture_action_resource_bar_tactical.gd`

**Interfaces:**
- Consumes: 完整 VA-5 候选实现。
- Produces: 两张 `1280×720` PNG 绝对路径和完整 `tests/test_*.gd` 回归证据。

- [ ] **Step 1: 写捕获脚本**

脚本必须要求 `--capture-action-resources` 参数，并在 `DisplayServer.get_name().to_lower() == "headless"` 时立即退出 1。窗口模式实例化真实 `TacticalScene`，保存：

```gdscript
const CAPTURE_NAMES := [
	"action_resources_all_available.png",
	"action_resources_mixed_spent.png",
]
```

第一张先 `reset_action_resources()` 并刷新；第二张调用 `consume_movement_resource()`、`consume_standard_resource()`，保持 S 可用并刷新。保存前必须断言：资源栏可见、位于技能栏上方、三个段状态分别为 `false/false/false` 与 `true/true/false`、地图单位无 M/A/S。每张都等待两次 `process_frame` 和一次 `RenderingServer.frame_post_draw`，从根 Viewport 取图并精确检查 `1280×720`。

- [ ] **Step 2: 验证捕获合同**

先用 `--headless` 运行并确认快速退出 1；再用同一 Godot 4.6.3 控制台窗口模式运行：

```powershell
$godot = 'D:\Download\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe'
$project = (git rev-parse --show-toplevel).Trim()
& $godot --headless --path $project --script res://tests/capture_action_resource_bar_tactical.gd -- --capture-action-resources
if ($LASTEXITCODE -ne 1) { throw 'Headless capture must fail fast with exit 1' }
& $godot --path $project --script res://tests/capture_action_resource_bar_tactical.gd -- --capture-action-resources
if ($LASTEXITCODE -ne 0) { throw 'Windowed capture failed' }
```

Expected: exit 0，输出批次绝对目录，两张 PNG 都存在且尺寸为 `1280×720`。

- [ ] **Step 3: 运行全部标准回归**

顺序执行当前全部 `tests/test_*.gd`，逐项记录文件名、退出码和失败尾部：

```powershell
$godot = 'D:\Download\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe'
$project = (git rev-parse --show-toplevel).Trim()
$tests = Get-ChildItem -LiteralPath (Join-Path $project 'tests') -Filter 'test_*.gd' -File | Sort-Object Name
$failures = @()
foreach ($case in $tests) {
	$output = & $godot --headless --path $project --script "res://tests/$($case.Name)" 2>&1
	if ($LASTEXITCODE -ne 0) {
		$failures += $case.Name
		Write-Output "FAIL $($case.Name)"
		$output | Select-Object -Last 30
	}
}
Write-Output "FULL_REGRESSION total=$($tests.Count) failed=$($failures.Count)"
if ($failures.Count -gt 0) { throw "Failed tests: $($failures -join ', ')" }
```

Expected: 所有既有与新增测试退出码均为 0。

- [ ] **Step 4: 静态检查和提交**

运行 `git diff --check`、`git status --short`，确认只出现本 Task 的捕获脚本；提交：

```powershell
git add tests/capture_action_resource_bar_tactical.gd
git commit -m "test(ui): capture action resource bar in tactical scene" -m "Constraint: Use real TacticalScene at 1280x720`nConfidence: high`nScope-risk: narrow"
```

---

### Task 5: 独立终审与用户视觉验收

**Files:** 无生产写入；修复仅在审查确认的当前范围内进行。

- [ ] **Step 1:** 对起点 `a54d00f` 到候选 HEAD 生成完整审查包，由未参与实现的独立审查者核对规格符合性和代码质量。
- [ ] **Step 2:** 若有 Critical/Important 问题，交给独立修复者做一次合并修复并复审；不得由主代理或审查者直接修改。
- [ ] **Step 3:** 使用结构化视觉审查检查两张原始 PNG 的位置、状态差异、遮挡和整体质感。
- [ ] **Step 4:** 在当前会话中直接展示两张本地 PNG，请用户完成最终视觉裁决。用户未通过前，Milestone 仍处于验收阶段。

---

### Task 6: 受控发布、合并与合并后核验

**Files:** Git/GitHub 集成状态；不新增功能范围。

- [ ] **Step 1:** 用户视觉通过后，先从任务工作树调用 `scripts/codex/sot-publish.ps1 -DryRun` 验证分支、工作树和授权仓库；通过后再调用同一脚本正式发布，不使用原始 `git push`。
- [ ] **Step 2:** 创建指向 `develop` 的 PR，等待独立审查通过并合并；创建 PR 不等于 Task 完成。
- [ ] **Step 3:** 在最新 `develop` 上重新执行 Godot 导入、全部 `tests/test_*.gd`、两项行动资源聚焦测试和 `git status`。
- [ ] **Step 4:** 关闭 issue #18，返回 `sot-task-receipt` 结构化回执；只有合并后验证全绿且无必需遗留时才宣布 VA-5 完成。
