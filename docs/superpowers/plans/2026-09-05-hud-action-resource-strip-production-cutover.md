# 正式行动资源条切换实施计划

> **执行要求：** 使用 `superpowers:subagent-driven-development` 按本计划执行。实现者与代码审查者、视觉审查者必须分离；实现者不得自行批准截图。

**目标：** 将冻结候选 `ActionResourceStrip` 作为唯一正式行动资源条接入 `BottomDashboard`，直接显示 1B 提供的六个真实字段，删除旧 `ActionResourceBar` 与三个过渡 HUD 键，并留下可复核的真实战斗截图。

**架构：** `TacticalManager` 继续只负责输出玩法状态；`BottomDashboard` 是严格的字典到 `HudActionResourceViewData` 适配门面；冻结候选场景只负责显示。生产门面从 `.tscn` 实例化唯一候选，验证完六字段后创建私有 ViewData，并负责显示门控、位置、鼠标遮挡和浮窗避让。候选场景、脚本、Theme 与 PNG 保持字节不变。

**技术栈：** Godot 4.6.3、GDScript、`SceneTree` 回归脚本、真实 `TacticalScene` 窗口捕获、PNG 与 JSON 视觉证据。

**规格：** `docs/superpowers/specs/2026-09-05-hud-action-resource-strip-production-cutover-design.md`

## 全局约束

- 起始提交固定为 `d2f53590b93774e2eecd944b74da2a56fcde957d`；它已完成 HUD-PROD-1B 并通过任务审查、整分支审查和控制器复验。
- 使用 `4.6.3.stable.official.7d41c59c4`。Godot 路径只能来自当前进程或被忽略的本地配置，不写入跟踪文件。
- 最终只创建一个本地提交；不推送、不建 PR、不合并、不发布。
- `action_resources` 在正式路径中只保留六个字段：`movement_remaining`、`movement_available`、`standard_capacity`、`standard_remaining`、`swift_capacity`、`swift_remaining`。
- 严格要求 `mode == "player"`、`show_actions == true`、整体 HUD 可见和六字段合法；任一条件不满足就立即隐藏资源条。
- 整数字段必须由 `typeof(value) == TYPE_INT` 验证，不能把布尔值、浮点数或字符串宽松转换成整数。
- 正式实例固定为 `274×40`，与技能栏水平中心一致，垂直净距精确为 6 像素；显示时计入 `get_content_top_y()`，隐藏时排除。
- 冻结资源条源场景的组合最小尺寸为 `274×46`，源 StyleBox 上下内容边距均为 5；正式门面使用 `duplicate()` 创建独立 StyleBox，只在实例上把上下内容边距覆盖为 2，使组合最小尺寸和实际尺寸均为 `274×40`。既有冻结 `bottom_hud_composition.tscn` 同样使用上下内容边距 2 的实例覆盖，维持批准高度 40；同一环境完成字体布局后，数字控件最小高 26、移动分区高 30、内部 Margin 高 36，因此源高度为 `36 + 5 + 5 = 46`，实例高度为 `36 + 2 + 2 = 40`。此覆盖已经通过审查，源 Theme、场景和 PNG 保持不变。
- 正式实例根设为 `MOUSE_FILTER_STOP`，但不修改候选源场景的 `MOUSE_FILTER_IGNORE`；全部候选 `Control` 保持 `FOCUS_NONE`。
- 禁止修改 `scripts/ui/hud/**`、`scenes/tactical/hud/**`、Theme、PNG、`test_hud_*`、生产 `TacticalScene`、`scripts/units/**`、`scripts/core/game_action.gd`、数据、存档、设计库、KB、Mercury 和三个既有跟踪修改。
- `tests/test_multi_action_resources.gd` 中的旧名称只是接口删除负向探针，不属于旧 HUD 合同，不修改该文件。
- 实现者先生成两张截图、写入“待独立审查”的证据记录并精确暂存，但不提交；控制器在同一候选上完成任务代码审查、整分支审查和视觉审查，合并全部发现后最多执行一次集中纠正。全部审查通过、视觉结论写回并经定向核对后，才创建唯一提交。

## 文件职责

| 路径 | 职责 |
| --- | --- |
| `scripts/core/tactical_manager.gd` | 只删除三个过渡 HUD 键 |
| `scripts/ui/bottom_dashboard.gd` | 实例化候选、严格适配六字段、门控、布局、输入和浮窗避让 |
| `scripts/ui/action_resource_bar.gd` | 删除旧实现 |
| `tests/test_action_resource_bar.gd` | 删除旧实现专用测试 |
| `tests/test_action_resource_strip_production_cutover.gd` | 新增正式门面、五态、异常输入、布局、命中与焦点回归 |
| `tests/test_action_resource_dashboard.gd` | 从旧三键和旧私有节点迁移到六字段与候选实例 |
| `tests/test_action_resource_runtime.gd` | 在真实攻击流程中检查候选 ViewData 和点阵状态 |
| `tests/capture_action_resource_bar_tactical.gd` | 写固定证据路径并捕获默认态、复杂部分消费态 |
| `tests/test_tactical_inject_smoke.gd` | 只运行，不修改 |
| 两张 `evidence/*.png` | 真实 `TacticalScene` 原始截图 |
| `evidence/visual-verdict.json` | 独立视觉审查结论与截图哈希 |
| 本规格与本计划 | 当前任务合同与可复现步骤 |

---

### Task 1：切换正式 ActionResourceStrip

**创建：**

- `tests/test_action_resource_strip_production_cutover.gd`
- `dev_doc/ui-art-research/hud-prod-1c-action-resource-cutover/evidence/action_resources_default_1280x720.png`
- `dev_doc/ui-art-research/hud-prod-1c-action-resource-cutover/evidence/action_resources_multi_point_1280x720.png`
- `dev_doc/ui-art-research/hud-prod-1c-action-resource-cutover/evidence/visual-verdict.json`

**修改：**

- `scripts/core/tactical_manager.gd:197-209`
- `scripts/ui/bottom_dashboard.gd:321-331,358-424,1061-1123`
- `tests/test_action_resource_dashboard.gd`
- `tests/test_action_resource_runtime.gd`
- `tests/capture_action_resource_bar_tactical.gd`
- `docs/superpowers/specs/2026-09-05-hud-action-resource-strip-production-cutover-design.md`
- `docs/superpowers/plans/2026-09-05-hud-action-resource-strip-production-cutover.md`

**删除：**

- `scripts/ui/action_resource_bar.gd`
- `tests/test_action_resource_bar.gd`

**只运行：**

- `tests/test_tactical_inject_smoke.gd`
- `tests/test_skillbar_v3_ui.gd`
- `tests/test_hud_action_resource_strip.gd`
- `tests/test_hud_bottom_composition.gd`
- `tests/test_hud_bottom_composition_gallery.gd`
- `tests/test_hud_bottom_dynamic_states_gallery.gd`
- `tests/test_hud_production_baseline_manifest.gd`

**接口：**

- `BottomDashboard._action_resource_strip`：从冻结 `.tscn` 实例化的唯一正式实例。
- `BottomDashboard.update_state(Dictionary)`、六个既有信号和 `get_content_top_y()`：对外合同不变。
- `HudActionResourceStrip.apply_view(HudActionResourceViewData)`：唯一显示输入；门面不传 `Unit`、管理器或完整字典。
- `TacticalManager.get_dashboard_data().action_resources`：只含六个真实字段。

- [x] **步骤 0：固定本地执行环境与起始状态**

实现者先在当前 PowerShell 进程中把由控制器提供或从被忽略本地配置解析出的 Godot 路径赋给 `$env:GODOT_EXE`，不得把本机路径写入跟踪文件。然后运行：

```powershell
$projectRoot = (git rev-parse --show-toplevel).Trim()
$taskBase = 'd2f53590b93774e2eecd944b74da2a56fcde957d'
$godot = $env:GODOT_EXE
if ([string]::IsNullOrWhiteSpace($projectRoot) -or -not (Test-Path -LiteralPath $projectRoot)) {
  throw '无法解析项目根'
}
if ([string]::IsNullOrWhiteSpace($godot) -or -not (Test-Path -LiteralPath $godot)) {
  throw 'GODOT_EXE 必须由当前进程或被忽略的本地配置提供'
}
if ((& $godot --version).Trim() -ne '4.6.3.stable.official.7d41c59c4') {
  throw 'Godot 版本不匹配'
}
if ((git rev-parse HEAD).Trim() -ne $taskBase) {
  throw 'HUD-PROD-1C 起始提交不匹配'
}
git status --short
```

记录三个既有跟踪修改和任务外未跟踪素材；它们全程不得暂存或改写。后续所有 Godot 命令统一使用 `$godot` 和 `$projectRoot`。

- [x] **步骤 1：新增确定失败的正式切换测试**

创建 `tests/test_action_resource_strip_production_cutover.gd`，沿用现有 `SceneTree` 的 `_check`、`_eq`、`_finish` 模式。先单独实例化正式 `scenes/tactical/bottom_dashboard.tscn`，在首次 `update_state()` 前验证构建状态；另行实例化真实 `TacticalScene` 验证生产数据链。测试先通过属性列表判断 `_action_resource_strip` 是否存在，再读取它，避免旧实现上出现测试脚本错误：

```gdscript
const STRIP_SCENE_PATH := "res://scenes/tactical/hud/action_resource_strip.tscn"

func _has_property(value: Object, property_name: String) -> bool:
    for property: Dictionary in value.get_property_list():
        if str(property.get("name", "")) == property_name:
            return true
    return false
```

测试组必须包括：

1. 单独实例化的正式门面有 `_action_resource_strip`，其 `scene_file_path` 精确等于冻结场景路径；递归统计该路径的实例数严格为 1。旧实现的退役由步骤 8 的删除与静态检查证明，新测试不重新写入旧接口名称。
2. 该尚未接收状态的正式实例初始隐藏、`mouse_filter == MOUSE_FILTER_STOP`；另行实例化冻结源场景并断言源根仍为 `MOUSE_FILTER_IGNORE`。等待布局后，精确断言源组合最小尺寸为 `274×46`、源 StyleBox 上下内容边距仍为 5；正式实例 StyleBox 与源不是同一对象、具有实例覆盖且上下内容边距为 2，组合最小尺寸和实际尺寸均为 `274×40`。另行实例化冻结组合场景，确认其中的资源条也用上下内容边距 2 的实例覆盖维持 `274×40`。
3. 深复制输入状态后调用 `update_state()`，输入字典保持相等；候选私有 `_view` 的六字段逐项等于输入。
4. 先送入有效状态令资源条可见，再逐项送入无效状态并断言立即隐藏：HUD 不可见、`mode` 为 `enemy` 或未知值、`show_actions=false`、资源对象缺失或不是字典、六字段逐个缺失、整数字段分别为浮点数／字符串／布尔值、可用状态不是布尔值、移动力为负、容量为 0 或 4、剩余量小于 0 或大于容量。
5. 以下五组状态逐组等待布局帧后验证；先保存 `expected_movement := maxi(0, current_unit.stats.mov)`。默认态使用真实单位默认容量，第 2 组通过正式消费入口关闭移动和耗尽标准点，第 3 至第 5 组必须对真实当前单位调用 `configure_action_resource_capacities()`、按需调用消费入口，再从 `TacticalManager.get_dashboard_data()` 取得正式载荷后交给门面。不得直接手写合法载荷来代替初始化入口和正式数据链。总尺寸始终为 `Vector2(274, 40)`，点数等于容量，`spent` 数组按 `index >= remaining` 得出：

```text
movement=expected_movement/available, standard=1/1, swift=1/1
movement=expected_movement/unavailable, standard=1/0, swift=1/1
movement=expected_movement/available, standard=2/1, swift=1/1
movement=expected_movement/available, standard=3/1, swift=1/1
movement=expected_movement/available, standard=1/1, swift=3/2，然后 swift=3/0
```

6. 三个分区节点均为 `PanelContainer`，`theme_type_variation == &"ActionResourceSegment"`，完整边框仍存在；移动失效只灰化足迹和数值，显示文本始终等于 `str(expected_movement)`，不得改写职业数据或单位移动力来凑固定测试值。
7. 资源条与 `_skill_bar` 中心一致，`skill_y - strip_bottom == 6`。隔离其他底栏面板，只保留位置更低的可见技能栏；显示态精确断言 `get_content_top_y() == strip.position.y`。再通过 `update_state()` 隐藏资源条，并重新隔离其他面板，按剩余可见控件计算预期顶边，断言其 Y 坐标大于资源条的 Y 坐标且 `get_content_top_y()` 精确等于此值；不能使用 `<=`。
8. 在独立正式门面实例下方建立全屏点击探针。对中心、左、右、上、下内缩 2 像素的五点，先隐藏资源条并等待现有显示动画结束，再逐点发送移动、按下和松开，确认探针每次恰好增加 1，以证明坐标和装置有效；再显示资源条并等待现有显示动画结束，清零计数并重复。每个事件都用 `root.push_input(event, true)` 明确采用根 Viewport 坐标。显示态逐点断言 `root.gui_get_hovered_control()` 是资源条或其后代、资源条子树连接的 `gui_input` 计数增加、底层探针计数不增加。
9. 递归检查资源条内所有 `Control.focus_mode == FOCUS_NONE`。

测试不得调用候选 `normalize()` 代替门面验证，也不得复制候选节点树。

- [x] **步骤 2：先迁移现有生产链测试和捕获脚本**

在生产代码变更前完成以下测试改写：

- `test_action_resource_dashboard.gd`：确认 `TacticalManager` 的资源字典只有六个真实字段；确认正式实例来自冻结场景；删除三个旧键的透传与缺失字段断言，改为六字段逐个缺失和非法类型／范围门控。
- `test_action_resource_runtime.gd`：沿用起始提交中的真实流程：回合开始、真实移动、两次 `GameAction` 普通攻击、新回合、真实迅捷技能、最终回合重置。每次行为前后只监听并比较 `dashboard_state_changed` 计数，禁止主动扣点或主动调用 `_refresh_dashboard()` 来替代流程；容量通过初始化入口配置。将节点读取迁移为 `_action_resource_strip`，每一步精确核对 Unit 剩余量、私有 `_view` 六字段、标准与迅捷点阵、移动数值和足迹灰化，并确认地图人物没有 M/A/S。
- `capture_action_resource_bar_tactical.gd`：改为 `_action_resource_strip` 和 ViewData／点阵验证；复杂态调用 `configure_action_resource_capacities(3, 3)`，消费移动、两个标准点和一个迅捷点，得到标准 `3/1`、迅捷 `3/2`、移动不可用。

捕获脚本使用固定项目内目录，不创建时间戳批次：

```gdscript
const CAPTURE_ROOT := "res://dev_doc/ui-art-research/hud-prod-1c-action-resource-cutover/evidence/"
const CAPTURE_NAMES := [
    "action_resources_default_1280x720.png",
    "action_resources_multi_point_1280x720.png",
]
```

保存前使用 `ProjectSettings.globalize_path(CAPTURE_ROOT)` 建目录；每次保存后重新 `Image.load_from_file()`，断言尺寸为 `1280×720`。捕获前还要断言资源条为 `274×40`、间距为 6、点阵状态正确且地图人物没有 M/A/S 徽标。

- [x] **步骤 3：运行 RED 并记录真实缺失行为**

分别运行：

```powershell
& $godot --headless --path $projectRoot --script res://tests/test_action_resource_strip_production_cutover.gd
& $godot --headless --path $projectRoot --script res://tests/test_action_resource_dashboard.gd
& $godot --headless --path $projectRoot --script res://tests/test_action_resource_runtime.gd
```

预期旧生产代码下：

- 新测试因正式门面没有 `_action_resource_strip` 而退出非零；
- 仪表盘测试因正式载荷仍含三个旧键、门面仍使用旧组件而退出非零；
- 真实流程测试因候选实例不存在而退出非零。

语法、场景加载或夹具错误不算 RED。只修测试直到失败来自缺失生产行为。

- [x] **步骤 4：把 TacticalManager 载荷收敛为六字段**

在 `get_dashboard_data()` 的 `action_resources` 中只删除：

```gdscript
"movement_used": info_unit.movement_used,
"standard_used": info_unit.standard_remaining == 0,
"swift_used": info_unit.swift_remaining == 0,
```

不得改动六个真实字段、其他仪表盘字段、回合流程或 `Unit`。

- [x] **步骤 5：在 BottomDashboard 实现严格门面适配**

预加载冻结场景与 ViewData：

```gdscript
const ActionResourceStripScene: PackedScene = preload(
    "res://scenes/tactical/hud/action_resource_strip.tscn")
const ActionResourceViewDataScript: GDScript = preload(
    "res://scripts/ui/hud/action_resource_view_data.gd")

var _action_resource_strip: Control = null
```

构建时只实例化一次：

```gdscript
_action_resource_strip = ActionResourceStripScene.instantiate() as Control
add_child(_action_resource_strip)
var strip_style: StyleBoxTexture = _action_resource_strip.get_theme_stylebox(&"panel") as StyleBoxTexture
if strip_style != null:
    var compact_strip_style: StyleBoxTexture = strip_style.duplicate() as StyleBoxTexture
    compact_strip_style.content_margin_top = 2.0
    compact_strip_style.content_margin_bottom = 2.0
    _action_resource_strip.add_theme_stylebox_override(&"panel", compact_strip_style)
_action_resource_strip.visible = false
_action_resource_strip.mouse_filter = Control.MOUSE_FILTER_STOP
```

该实例覆盖沿用冻结组合场景已经采用的内容边距与批准高度，只复制样式对象，不改变源共享资源。正式切换测试同时验证源与实例的边距、对象身份、组合最小尺寸和实际尺寸。

删除 `ActionResourceBarScript`、`_action_resource_bar` 和其 `.new()` 路径。用小型私有函数完成严格校验；不得 `int()` 或 `bool()` 宽松转换。合法条件为：

```text
typeof(movement_remaining) == TYPE_INT and movement_remaining >= 0
typeof(movement_available) == TYPE_BOOL
typeof(standard_capacity) == TYPE_INT and 1 <= standard_capacity <= 3
typeof(standard_remaining) == TYPE_INT and 0 <= standard_remaining <= standard_capacity
typeof(swift_capacity) == TYPE_INT and 1 <= swift_capacity <= 3
typeof(swift_remaining) == TYPE_INT and 0 <= swift_remaining <= swift_capacity
```

`_update_action_resources()` 必须先隐藏资源条，再检查：整体 `visible`、`str(state.get("mode", "")) == "player"`、`show_actions` 和合法载荷。通过后创建新的 ViewData，逐字段赋值，再调用：

```gdscript
_action_resource_strip.call("apply_view", view)
_action_resource_strip.visible = true
```

不得把原输入字典或共享 ViewData 传入候选。

布局将旧变量替换为新实例，保持总尺寸和间距：

```gdscript
var resource_size := _action_resource_strip.get_combined_minimum_size()
_action_resource_strip.size = resource_size
var resource_x := skill_x + skill_sz.x * 0.5 - resource_size.x * 0.5
var resource_y := skill_y - resource_size.y - ACTION_RESOURCE_GAP_Y
_action_resource_strip.position = Vector2(resource_x, resource_y)
```

`get_content_top_y()` 的可见控件列表也只使用 `_action_resource_strip`。

- [x] **步骤 6：删除旧实现及全部活动引用**

删除 `scripts/ui/action_resource_bar.gd` 和只验证旧文字、斜杠、`_segments` 的 `tests/test_action_resource_bar.gd`。不要创建新旧双实现开关或兼容别名。

- [x] **步骤 7：运行自动 GREEN 套件**

集中修正后的两项定向测试由实现者重新运行，完整十项套件与编辑器导入由控制器在修正后重新执行。本轮十项均退出 0、无测试失败；导入退出 0 且脚本类注册完成，范围外 `addons/godot_mcp` 插件报端口占用与日志接口错误，已记录于忽略目录的实施报告，未修改插件。

逐个独立运行：

```powershell
$tests = @(
  'test_action_resource_strip_production_cutover.gd',
  'test_action_resource_dashboard.gd',
  'test_action_resource_runtime.gd',
  'test_tactical_inject_smoke.gd',
  'test_skillbar_v3_ui.gd',
  'test_hud_action_resource_strip.gd',
  'test_hud_bottom_composition.gd',
  'test_hud_bottom_composition_gallery.gd',
  'test_hud_bottom_dynamic_states_gallery.gd',
  'test_hud_production_baseline_manifest.gd'
)
foreach ($test in $tests) {
  & $godot --headless --path $projectRoot --script "res://tests/$test"
  if ($LASTEXITCODE -ne 0) { throw "Failed: $test" }
}
```

再运行：

```powershell
& $godot --headless --editor --path $projectRoot --quit
```

预期全部退出 0；manifest 必须仍为 218 项、2687/0，SHA-256 为 `584B1C9648BDF68396F37623DBD9BFDF268CB0F32574FC34F35FEE011D2E0956`。

- [x] **步骤 8：验证删除边界和冻结候选未变**

```powershell
function Assert-NoRgHit {
  param([string]$Pattern, [string[]]$Paths, [switch]$Fixed)
  $rgArgs = @('-n')
  if ($Fixed) { $rgArgs += '-F' }
  $rgArgs += $Pattern
  $rgArgs += $Paths
  $hits = & rg @rgArgs
  $code = $LASTEXITCODE
  if ($code -eq 0) {
    $hits
    throw "发现已退役引用：$Pattern"
  }
  if ($code -gt 1) { throw "rg 执行失败：$Pattern" }
}

Assert-NoRgHit 'ActionResourceBarScript|ActionResourceBar|_action_resource_bar|_segments' @('scripts', 'scenes', 'tests')
Assert-NoRgHit '"(movement_used|standard_used|swift_used)"' @('scripts/core/tactical_manager.gd', 'scripts/ui/bottom_dashboard.gd', 'tests/test_action_resource_dashboard.gd', 'tests/test_action_resource_runtime.gd', 'tests/capture_action_resource_bar_tactical.gd', 'tests/test_action_resource_strip_production_cutover.gd')
Assert-NoRgHit 'res://scripts/ui/action_resource_bar.gd' @('scripts', 'scenes', 'tests') -Fixed

$protectedPaths = @(
  'scripts/ui/hud',
  'scenes/tactical/hud',
  'assets/ui/themes/hud_structure_prototype.tres',
  'assets/ui/skins/hud/action_resource_strip_surface_v1.png',
  'tests/test_hud_action_resource_strip.gd',
  'tests/test_hud_bottom_composition.gd',
  'tests/test_hud_bottom_composition_gallery.gd',
  'tests/test_hud_bottom_dynamic_states_gallery.gd',
  'tests/test_hud_production_baseline_manifest.gd',
  'scripts/tactical/tactical_scene.gd',
  'scenes/tactical/TacticalScene.tscn',
  'scenes/tactical/bottom_dashboard.tscn',
  'scripts/units',
  'scripts/core/game_action.gd',
  'data'
)
& git diff --exit-code $taskBase -- @protectedPaths
if ($LASTEXITCODE -ne 0) { throw '受保护跟踪文件发生变化' }
$untrackedProtected = & git ls-files --others --exclude-standard -- @protectedPaths
if ($LASTEXITCODE -ne 0) { throw '无法检查受保护未跟踪文件' }
if ($untrackedProtected) { throw "受保护路径出现未跟踪文件：`n$untrackedProtected" }
git diff --check
if ($LASTEXITCODE -ne 0) { throw '任务差异存在空白错误' }
```

三个引用检查均应以 `rg` 的“无命中”退出码 1 结束；退出码 0 是旧引用残留，大于 1 是命令错误，两者都失败。`movement_used` 作为 `Unit` 运行字段可在未列入第二条的运行测试或捕获状态构造中出现，但不得再成为带引号的 HUD 键。跟踪与未跟踪两类冻结路径差异都必须为空。

- [x] **步骤 9：用真实 TacticalScene 生成两张固定截图**

```powershell
if ((& $godot --version).Trim() -ne '4.6.3.stable.official.7d41c59c4') {
  throw 'Godot 版本不匹配'
}
& $godot --windowed --single-window --resolution 1280x720 --position 64,64 `
  --path $projectRoot --script res://tests/capture_action_resource_bar_tactical.gd `
  -- --capture-action-resources
if ($LASTEXITCODE -ne 0) { throw '行动资源条窗口捕获失败' }
```

确认两张文件存在、均为 `1280×720`，并记录各自 SHA-256。默认图显示容量 `1/1` 全可用；复杂图显示移动灰化、标准 `3/1`、迅捷 `3/2`。不得出现“可用／已用”、斜杠或 M/A/S。

- [x] **步骤 10：创建待审证据并精确暂存，不提交**

实现者创建初始 `visual-verdict.json`，只记录真实 `task_id`、状态 `pending_independent_visual_review`、两张截图的完整项目相对路径、`1280x720` 尺寸和各自 64 位 SHA-256；`checks` 保持空数组，并明确独立视觉审查尚未发生。该状态不是自我批准。

只暂存本 Task 允许路径，包括删除项、两张截图、待审视觉记录、本规格与本计划：

```powershell
git add -A -- scripts/core/tactical_manager.gd scripts/ui/bottom_dashboard.gd scripts/ui/action_resource_bar.gd tests/test_action_resource_bar.gd tests/test_action_resource_strip_production_cutover.gd tests/test_action_resource_dashboard.gd tests/test_action_resource_runtime.gd tests/capture_action_resource_bar_tactical.gd dev_doc/ui-art-research/hud-prod-1c-action-resource-cutover/evidence/action_resources_default_1280x720.png dev_doc/ui-art-research/hud-prod-1c-action-resource-cutover/evidence/action_resources_multi_point_1280x720.png dev_doc/ui-art-research/hud-prod-1c-action-resource-cutover/evidence/visual-verdict.json docs/superpowers/specs/2026-09-05-hud-action-resource-strip-production-cutover-design.md docs/superpowers/plans/2026-09-05-hud-action-resource-strip-production-cutover.md
git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw '暂存差异存在空白错误' }
git diff --cached --name-status
```

把暂存路径与任务允许清单逐项比对；三个既有跟踪修改和其他未跟踪素材不得进入索引。实现者写阶段报告并返回 `READY_FOR_INDEPENDENT_REVIEW`，报告 RED、逐项 GREEN、静态删除、冻结路径、manifest、窗口命令、两图尺寸与 SHA、节点实测尺寸及 6 像素净距。此时 HEAD 必须仍为 `$taskBase`。

- [ ] **步骤 11：提交前完成三路独立审查，并共享一次纠正额度**

控制器在同一暂存候选上安排三路相互独立的只读审查：

1. 任务审查者读取规格、计划、实施报告、`git diff --cached --name-status` 与 `git diff --cached -U10`，核对逐文件规格和代码质量；它把“视觉结论尚待独立审查”视为预期中间状态。
2. 整分支审查者读取相同暂存差异，检查跨文件数据链、删除边界、冻结路径、对外合同和回退风险。
3. 视觉审查者使用 `visual-verdict` 技能读取两张原始截图，至少判断：资源条可见且不遮挡棋盘主体；足迹与数字、绿色圆点、橘黄色三角清楚；消费态仅灰化；三个同款完整类边框和整体边框存在；274×40 比例与 6 像素间距可信；无旧文字、斜杠或 M/A/S。

三个审查结果全部返回后再合并发现。若存在任何真实代码问题或视觉失败，原实现者只能执行一次集中纠正，必须同时处理三路发现、重跑受影响测试并重新暂存；修正影响显示时重新捕获两张图。原审查者只对各自发现和修正差异做定向复核。该一次集中纠正是本 Task 的共享总额度，不能在视觉和代码审查中各自再开一轮；仍有承重问题时才构成明确阻塞。

- [ ] **步骤 12：写回独立视觉结论并在提交前定向核对**

三路审查均通过后，控制器把视觉审查者标识、逐项结论和残余风险交回原实现者。实现者只更新 `visual-verdict.json`：状态改为 `independent_visual_pass_pending_user_confirmation`，写入真实审查者标识、逐项 `checks` 和“仍待用户确认”的非阻断限制；截图路径、尺寸与 SHA 必须保持与已审原图一致。重新暂存该文件。

视觉审查者对 `visual-verdict.json` 与原审查输出做一次只读定向核对；这不是新的纠正轮。然后控制器确认：

```powershell
git diff --cached --check
if ($LASTEXITCODE -ne 0) { throw '最终暂存差异存在空白错误' }
git diff --cached --name-status
if ((git rev-parse HEAD).Trim() -ne $taskBase) { throw '审查前出现了意外提交' }
```

未通过独立代码、整分支、视觉和证据核对中的任一项，都不得提交。

- [ ] **步骤 13：创建唯一提交并做提交后完整性核验**

全部提交前审查通过后，原实现者创建唯一提交：

```powershell
git commit -m "feat(ui): cut over production action resource strip"
if ((git rev-list --count "$taskBase..HEAD").Trim() -ne '1') {
  throw 'HUD-PROD-1C 必须只有一个提交'
}
git diff --check $taskBase..HEAD
git status --short
```

完成实施报告，补入独立三路审查结论、证据核对、最终提交哈希和保护文件状态。控制器再确认提交树与获批暂存路径一致，不重新修改实现。

技术和独立审查均通过后，把两张原始截图在当前会话中直接显示给用户确认。用户确认前，本 Task 状态为“技术与独立视觉通过，待用户确认”，不得宣称 HUD-PROD-1C 或整个 HUD-PROD-1 Milestone 完成。
