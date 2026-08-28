# 剑圣战棋棋子正式导入实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将已批准的剑圣 `clean_v2` 静态棋子原字节导入正式素材目录，并在真实 `TacticalScene` 中完成四方向、单双武器、脚底居中、纵向遮挡、血条和弹出信息避让。

**Architecture:** 正式 PNG 与独立 JSON 显示配置由 `DataLoader` 注册，`kensei` 职业数据只引用配置 ID。`MapTokenView: Sprite2D` 负责图集帧、中心点和过滤，`Unit` 负责玩法状态、HUD 与弹出文字锚点，`TacticalManager` 负责生成层和战斗文字消费；未绑定或加载失败的单位继续使用现有占位图。

**Tech Stack:** Godot 4.6.3、GDScript、JSON、PowerShell、Git、GitHub CLI

**Spec:** `docs/superpowers/specs/2026-08-28-kensei-map-token-production-integration-design.md`

## Global Constraints

- 只使用 SHA256 为 `e6f33324c52929769d4698ed75e969470ec45748788503f4637fcb3223dc5415` 的精确 PNG；正式副本不得裁切、缩放、重新编码或重新清理透明背景。
- 正式图集固定为 `1536×1024`、`4×2`、单帧 `384×512`，行顺序为单武器/双武器，列顺序为 `NW/NE/SW/SE`。
- 显示比例固定为 `0.15625`，过滤固定为 `Linear`，目标格固定为 `64×32`。
- 只有 `kensei` 绑定正式棋子；其他职业和敌人继续使用现有占位显示。
- 初始朝向缺省为 `SE`；多轴移动差值使用现有 Y 轴优先规则。
- 双武器显示只能复用现有 `Unit.is_dual_wielding()`，不得新增第二套双持判据。
- Buff/Debuff 与血条关联的样式及位置不在 VA-4 范围；后续专门的 UI/视觉设计裁决完成后才能生产化。既有通用状态显示保留其 `STATUS_BADGE_Y=-58` 基线，不作为本阶段视觉验收项。
- 初版不增加移动、攻击、受击或死亡动画。
- 不改变玩法数值、伤害公式、双持规则、技能位移朝向或 UI 总体设计。
- 正式运行时不得读取 `assets/prototype/visual_style/sample_manifest.json`。
- 使用 Godot 4.6.x；若版本不兼容，先升级再验证。
- 所有修改留在 `codex/va4-kensei-map-token` 工作树；不得直接提交或推送到受保护分支。

## File Map

| 文件 | 职责 |
|---|---|
| `assets/units/kensei/map_token_clean_v2.png` | 正式 PNG，必须与批准源文件字节相同 |
| `data/visual_profiles/kensei_map_token.json` | 图集、中心点、显示比例、头顶布局和正式准入合同 |
| `data/classes/kensei.json` | 只声明 `map_token_profile_id` |
| `assets/prototype/visual_style/sample_manifest.json` | 更新该精确文件的生产准入审计记录，不参与运行 |
| `scripts/data/data_loader.gd` | 注册 `visual_profiles` JSON 目录 |
| `scripts/units/map_token_view.gd` | 校验配置、加载纹理、选择帧、对齐人物中心点 |
| `scenes/tactical/Unit.tscn` | 同时容纳正式 `MapTokenView` 与占位 `AnimatedSprite2D` |
| `scripts/units/unit.gd` | 接入朝向、单双武器、HUD、弹出锚点、降级和死亡路径 |
| `scenes/tactical/TacticalScene.tscn` | 新增启用纵向排序的 `UnitLayer` |
| `scripts/core/tactical_manager.gd` | 在 `UnitLayer` 生成单位并消费最终战斗文字锚点 |
| `scripts/tactical/tactical_scene.gd` | 传入初始朝向并消费最终预估数字锚点 |
| `scripts/ui/damage_popup.gd` | 增加“不再二次偏移”的最终锚点 API，保留旧 API |
| `tests/test_kensei_map_token_asset.gd` | 正式素材、配置、准入和职业绑定合同 |
| `tests/test_map_token_view.gd` | 图集组件的八帧、中心点、过滤、布局和失败降级 |
| `tests/test_unit_map_token_visual.gd` | `Unit` 的朝向、单双武器、HUD、弹出锚点和死亡 |
| `tests/test_tactical_map_token_integration.gd` | 真实场景的生成层、格心、占位兼容和战斗文字 |
| `tests/capture_kensei_map_token_tactical.gd` | 实例化真实 `TacticalScene` 并批量保存视觉验收图 |

## Pre-execution Checkpoint

正式实施 Task 2 前，主代理先提交已通过自检与独立审查的计划文件：

```powershell
git add docs/superpowers/plans/2026-08-28-kensei-map-token-production-integration.md
git commit -m "docs: plan kensei map token integration"
git status --short
```

Expected: 计划提交成功，工作树清洁；后续 Task 6 的候选历史同时包含设计与计划提交。

---

### Task 2: 正式素材与配置合同

**Files:**
- Create: `assets/units/kensei/map_token_clean_v2.png`
- Create: `data/visual_profiles/kensei_map_token.json`
- Create: `tests/test_kensei_map_token_asset.gd`
- Modify: `assets/prototype/visual_style/sample_manifest.json`
- Modify: `data/classes/kensei.json`
- Modify: `scripts/data/data_loader.gd`

**Interfaces:**
- Consumes: 已批准源文件及规格中的 SHA256、八帧中心点和准入范围。
- Produces: `DataLoader.visual_profiles: Dictionary`；键 `kensei_map_token`；`kensei.map_token_profile_id == "kensei_map_token"`。

- [ ] **Step 1: 写正式素材合同失败测试**

创建 `tests/test_kensei_map_token_asset.gd`，使用现有 `SceneTree` 测试模式。测试必须包含这些精确常量与断言：

```gdscript
extends SceneTree

const SOURCE_PATH := "res://assets/prototype/visual_style/samples/map_token_source_transparent_clean_v2.png"
const PRODUCTION_PATH := "res://assets/units/kensei/map_token_clean_v2.png"
const PROFILE_PATH := "res://data/visual_profiles/kensei_map_token.json"
const EXPECTED_SHA256 := "e6f33324c52929769d4698ed75e969470ec45748788503f4637fcb3223dc5415"
const EXPECTED_PIVOTS: Array[Vector2] = [
	Vector2(205.9, 397.0), Vector2(194.0, 398.5),
	Vector2(178.5, 408.5), Vector2(178.0, 407.5),
	Vector2(203.4, 350.0), Vector2(198.8, 347.5),
	Vector2(173.5, 365.5), Vector2(182.2, 364.0),
]

func _run() -> void:
	var production_exists := FileAccess.file_exists(PRODUCTION_PATH)
	_check("正式 PNG 存在", production_exists)
	_check("源文件 SHA 精确", FileAccess.get_sha256(SOURCE_PATH) == EXPECTED_SHA256)
	if not production_exists:
		_finish()
		return
	_check("正式文件 SHA 精确", FileAccess.get_sha256(PRODUCTION_PATH) == EXPECTED_SHA256)
	_check("源文件与正式文件字节一致", FileAccess.get_file_as_bytes(SOURCE_PATH) == FileAccess.get_file_as_bytes(PRODUCTION_PATH))
	var image := Image.new()
	_check("正式 PNG 可加载", image.load_png_from_buffer(FileAccess.get_file_as_bytes(PRODUCTION_PATH)) == OK)
	_check("正式 PNG 尺寸精确", Vector2i(image.get_width(), image.get_height()) == Vector2i(1536, 1024))
	_check("正式 PNG 为 RGBA8", image.get_format() == Image.FORMAT_RGBA8)
	_check("正式 PNG 含透明像素", image.detect_alpha() != Image.ALPHA_NONE)
	var union_top := INF
	for index: int in range(EXPECTED_PIVOTS.size()):
		var frame_rect := Rect2i((index % 4) * 384, floori(float(index) / 4.0) * 512, 384, 512)
		var used_rect := image.get_region(frame_rect).get_used_rect()
		union_top = minf(union_top, (float(used_rect.position.y) - EXPECTED_PIVOTS[index].y) * 0.15625)
	_check("八帧不透明联合上沿精确", is_equal_approx(union_top, -51.484375))
	var profile_exists := FileAccess.file_exists(PROFILE_PATH)
	_check("显示配置存在", profile_exists)
	if not profile_exists:
		_finish()
		return
	var parsed_profile: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	_check("显示配置是 JSON 对象", typeof(parsed_profile) == TYPE_DICTIONARY)
	if typeof(parsed_profile) != TYPE_DICTIONARY:
		_finish()
		return
	var profile := parsed_profile as Dictionary
	_check("配置 ID 精确", profile.get("id") == "kensei_map_token")
	_check("正式路径不引用 prototype", profile.get("texture_path") == PRODUCTION_PATH and not PRODUCTION_PATH.contains("/prototype/"))
	_check("配置 SHA 精确", profile.get("sha256") == EXPECTED_SHA256)
	_check("图集为 4×2", profile.get("frame_grid") == [4, 2])
	_check("单帧为 384×512", profile.get("source_frame_size") == [384, 512])
	_check("变体顺序精确", profile.get("variant_order") == ["single_weapon", "dual_weapon"])
	_check("方向顺序精确", profile.get("direction_order") == ["NW", "NE", "SW", "SE"])
	_check("八组中心点精确", _pivots_match(profile.get("frame_pivot", []), EXPECTED_PIVOTS))
	_check("显示比例精确", is_equal_approx(float(profile.get("display_scale")), 0.15625))
	_check("默认过滤为 Linear", profile.get("default_filter") == "linear")
	var admission := profile.get("production_admission", {}) as Dictionary
	_check("正式准入已批准", admission.get("status") == "approved")
	_check("正式准入只绑定 kensei", admission.get("class_ids", []) == ["kensei"])
	_check("头顶联合上沿精确", is_equal_approx(float(profile.get("overhead_layout", {}).get("opaque_union_top_y")), -51.484375))
	var loader: Node = load("res://scripts/data/data_loader.gd").new()
	loader.call("load_all")
	var loaded_profiles := loader.get("visual_profiles") as Dictionary
	var loaded_classes := loader.get("classes") as Dictionary
	_check("DataLoader 注册显示配置", loaded_profiles.get("kensei_map_token", {}).get("id") == "kensei_map_token")
	_check("剑圣绑定显示配置", loaded_classes.get("kensei", {}).get("map_token_profile_id") == "kensei_map_token")
	for class_id: Variant in loaded_classes.keys():
		if str(class_id) != "kensei":
			_check("其他职业未绑定正式棋子：%s" % class_id, not (loaded_classes[class_id] as Dictionary).has("map_token_profile_id"))
	loader.free()
	_finish()
```

测试辅助函数固定为：

```gdscript
var _pass := 0
var _fail := 0
var _ran := false

func _initialize() -> void:
	print("=== test_kensei_map_token_asset ===")

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true

func _check(label: String, condition: bool) -> void:
	if condition:
		_pass += 1
	else:
		_fail += 1
		push_error(label)

func _pivots_match(raw: Variant, expected: Array[Vector2]) -> bool:
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() != expected.size():
		return false
	for index: int in range(expected.size()):
		var pair: Variant = (raw as Array)[index]
		if typeof(pair) != TYPE_ARRAY or (pair as Array).size() != 2:
			return false
		var actual := Vector2(float((pair as Array)[0]), float((pair as Array)[1]))
		if not actual.is_equal_approx(expected[index]):
			return false
	return true

func _finish() -> void:
	print("--- %d pass / %d fail ---" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
```

- [ ] **Step 2: 运行测试确认按预期失败**

```powershell
$projectRoot = (git rev-parse --show-toplevel).Trim()
& $env:GODOT_EXE --headless --path $projectRoot --script res://tests/test_kensei_map_token_asset.gd
```

Expected: FAIL；至少报告正式 PNG、配置文件或 `DataLoader.visual_profiles` 不存在。

- [ ] **Step 3: 原字节复制正式 PNG 并核对哈希**

```powershell
$projectRoot = (git rev-parse --show-toplevel).Trim()
$sourceAsset = Join-Path $projectRoot 'assets\prototype\visual_style\samples\map_token_source_transparent_clean_v2.png'
$productionDir = Join-Path $projectRoot 'assets\units\kensei'
$productionAsset = Join-Path $productionDir 'map_token_clean_v2.png'
New-Item -ItemType Directory -Path $productionDir -Force | Out-Null
Copy-Item -LiteralPath $sourceAsset -Destination $productionAsset
if ((Get-FileHash $sourceAsset -Algorithm SHA256).Hash -ne (Get-FileHash $productionAsset -Algorithm SHA256).Hash) {
	throw '正式 PNG 与批准源文件字节不一致'
}
```

- [ ] **Step 4: 新增精确显示配置**

创建 `data/visual_profiles/kensei_map_token.json`：

```json
{
  "id": "kensei_map_token",
  "asset_type": "map_token",
  "texture_path": "res://assets/units/kensei/map_token_clean_v2.png",
  "sha256": "e6f33324c52929769d4698ed75e969470ec45748788503f4637fcb3223dc5415",
  "source_size": [1536, 1024],
  "frame_grid": [4, 2],
  "source_frame_size": [384, 512],
  "variant_order": ["single_weapon", "dual_weapon"],
  "direction_order": ["NW", "NE", "SW", "SE"],
  "frame_pivot": [
    [205.9, 397.0], [194.0, 398.5], [178.5, 408.5], [178.0, 407.5],
    [203.4, 350.0], [198.8, 347.5], [173.5, 365.5], [182.2, 364.0]
  ],
  "display_scale": 0.15625,
  "tile_size": [64, 32],
  "default_filter": "linear",
  "overhead_layout": {
    "opaque_union_top_y": -51.484375,
    "health_bar_bottom_y": -58.0,
    "popup_anchor_y": -82.0
  },
  "production_admission": {
    "status": "approved",
    "class_ids": ["kensei"],
    "sha256": "e6f33324c52929769d4698ed75e969470ec45748788503f4637fcb3223dc5415",
    "basis": "2026-08-28 user approval for exact SHA256 and kensei binding"
  }
}
```

- [ ] **Step 5: 注册配置、绑定剑圣并更新审计记录**

在 `scripts/data/data_loader.gd` 增加：

```gdscript
var visual_profiles: Dictionary = {}
```

并在 `load_all()` 中增加：

```gdscript
_load_directory("res://data/visual_profiles/", visual_profiles)
```

在 `data/classes/kensei.json` 根对象增加：

```json
"map_token_profile_id": "kensei_map_token"
```

在原型清单对应 `runtime_candidate` 中保留原型准入来源，同时把生产字段更新为：

```json
"production_admission": "approved_exact_sha",
"production_bindings": ["kensei"],
"production_admission_basis": "2026-08-28 用户批准该精确 SHA256 文件原字节进入正式素材目录并仅绑定 kensei。"
```

- [ ] **Step 6: 运行聚焦测试并提交**

```powershell
$projectRoot = (git rev-parse --show-toplevel).Trim()
& $env:GODOT_EXE --headless --path $projectRoot --script res://tests/test_kensei_map_token_asset.gd
```

Expected: PASS，退出码 0。

```powershell
git add assets/units/kensei/map_token_clean_v2.png assets/prototype/visual_style/sample_manifest.json data/visual_profiles/kensei_map_token.json data/classes/kensei.json scripts/data/data_loader.gd tests/test_kensei_map_token_asset.gd
git commit -m "feat: admit kensei map token asset"
```

---

### Task 3A: 独立棋子显示组件

**Files:**
- Create: `scripts/units/map_token_view.gd`
- Create: `tests/test_map_token_view.gd`

**Interfaces:**
- Consumes: `DataLoader.visual_profiles[profile_id]` 字典。
- Produces: `configure(profile: Dictionary) -> bool`、`set_visual_state(facing: StringName, dual_wielding: bool) -> bool`、`is_configured() -> bool`、`get_facing() -> StringName`、`get_overhead_layout() -> Dictionary`。

- [ ] **Step 1: 写组件失败测试**

测试直接实例化脚本并加入测试根节点，断言：合法配置成功；纹理路径、哈希、`4×2`、八组中心点或必填布局缺失时返回 `false` 且节点不可见；省略 `status_badge_y` 仍可配置；八个状态的 `frame_coords`、`offset=-pivot`、`scale=(0.15625,0.15625)`、`centered=false` 和 `TEXTURE_FILTER_LINEAR` 精确。

```gdscript
var view: Sprite2D = load("res://scripts/units/map_token_view.gd").new()
root.add_child(view)
var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
	"res://data/visual_profiles/kensei_map_token.json"))
_check("合法配置成功", view.call("configure", profile))
_check("默认节点可见", view.visible)
_check("使用正式纹理", view.texture.resource_path == profile["texture_path"])
_check("图集为 4×2", view.hframes == 4 and view.vframes == 2)
_check("不按中心绘制", not view.centered)
_check("使用 Linear", view.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR)
for row: int in range(2):
	for column: int in range(4):
		var dual := row == 1
		var facing := StringName(["NW", "NE", "SW", "SE"][column])
		_check("状态可设置", view.call("set_visual_state", facing, dual))
		_check("帧坐标精确", view.frame_coords == Vector2i(column, row))
		var pivot_data: Array = profile["frame_pivot"][row * 4 + column]
		var pivot := Vector2(float(pivot_data[0]), float(pivot_data[1]))
		_check("人物中心点落在组件原点", (view.offset + pivot).distance_to(Vector2.ZERO) <= 0.001)
var invalid := profile.duplicate(true)
invalid["sha256"] = "0".repeat(64)
_check("格式合法但内容错误的哈希被拒绝", not view.call("configure", invalid) and not view.visible)
var out_of_bounds := profile.duplicate(true)
out_of_bounds["frame_pivot"][0] = [500.0, 397.0]
_check("越界人物中心点被拒绝", not view.call("configure", out_of_bounds) and not view.visible)
var non_finite := profile.duplicate(true)
non_finite["frame_pivot"][0] = [NAN, 397.0]
_check("非有限人物中心点被拒绝", not view.call("configure", non_finite) and not view.visible)
```

- [ ] **Step 2: 运行测试确认失败**

Run: `& $env:GODOT_EXE --headless --path (git rev-parse --show-toplevel).Trim() --script res://tests/test_map_token_view.gd`

Expected: FAIL，脚本不存在或接口未定义。

- [ ] **Step 3: 实现最小 `MapTokenView`**

核心结构固定为：

```gdscript
extends Sprite2D

const DIRECTIONS: Array[StringName] = [&"NW", &"NE", &"SW", &"SE"]
const EXPECTED_GRID := Vector2i(4, 2)
const EXPECTED_FRAME_SIZE := Vector2i(384, 512)

var _configured := false
var _profile: Dictionary = {}
var _facing: StringName = &"SE"

func configure(profile: Dictionary) -> bool:
	_reset()
	if not _validate_profile(profile):
		return false
	var texture_path := str(profile["texture_path"])
	if not FileAccess.file_exists(texture_path):
		push_error("[MapTokenView] Texture missing: %s" % texture_path)
		return false
	if FileAccess.get_sha256(texture_path) != str(profile["sha256"]):
		push_error("[MapTokenView] Texture SHA256 mismatch: %s" % texture_path)
		return false
	texture = load(texture_path) as Texture2D
	if texture == null:
		push_error("[MapTokenView] Texture load failed: %s" % texture_path)
		return false
	hframes = 4
	vframes = 2
	centered = false
	var display_scale := float(profile["display_scale"])
	scale = Vector2(display_scale, display_scale)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_profile = profile.duplicate(true)
	_configured = true
	visible = true
	return set_visual_state(&"SE", false)

func set_visual_state(facing: StringName, dual_wielding: bool) -> bool:
	if not _configured or not DIRECTIONS.has(facing):
		return false
	_facing = facing
	var column := DIRECTIONS.find(facing)
	var row := 1 if dual_wielding else 0
	frame_coords = Vector2i(column, row)
	var raw_pivot: Array = _profile["frame_pivot"][row * 4 + column]
	offset = -Vector2(float(raw_pivot[0]), float(raw_pivot[1]))
	return true

func is_configured() -> bool:
	return _configured

func get_facing() -> StringName:
	return _facing

func get_overhead_layout() -> Dictionary:
	return _profile.get("overhead_layout", {}).duplicate(true) if _configured else {}

func _validate_profile(profile: Dictionary) -> bool:
	if str(profile.get("texture_path", "")).contains("/prototype/"):
		return false
	if profile.get("frame_grid", []) != [4, 2] or profile.get("source_frame_size", []) != [384, 512]:
		return false
	if profile.get("variant_order", []) != ["single_weapon", "dual_weapon"]:
		return false
	if profile.get("direction_order", []) != ["NW", "NE", "SW", "SE"]:
		return false
	var pivots: Variant = profile.get("frame_pivot", null)
	if typeof(pivots) != TYPE_ARRAY or (pivots as Array).size() != 8:
		return false
	for pivot: Variant in pivots as Array:
		if typeof(pivot) != TYPE_ARRAY or (pivot as Array).size() != 2:
			return false
		if not [TYPE_INT, TYPE_FLOAT].has(typeof((pivot as Array)[0])) or not [TYPE_INT, TYPE_FLOAT].has(typeof((pivot as Array)[1])):
			return false
		var pivot_x := float((pivot as Array)[0])
		var pivot_y := float((pivot as Array)[1])
		if not is_finite(pivot_x) or not is_finite(pivot_y):
			return false
		if pivot_x < 0.0 or pivot_x >= 384.0 or pivot_y < 0.0 or pivot_y >= 512.0:
			return false
	if not is_equal_approx(float(profile.get("display_scale", 0.0)), 0.15625):
		return false
	if str(profile.get("default_filter", "")) != "linear":
		return false
	var sha256 := str(profile.get("sha256", ""))
	if sha256.length() != 64:
		return false
	var layout: Variant = profile.get("overhead_layout", null)
	if typeof(layout) != TYPE_DICTIONARY:
		return false
	for key: String in ["opaque_union_top_y", "health_bar_bottom_y", "popup_anchor_y"]:
		if not [TYPE_INT, TYPE_FLOAT].has(typeof((layout as Dictionary).get(key, null))):
			return false
	return true

func _reset() -> void:
	texture = null
	visible = false
	_configured = false
	_profile = {}
	_facing = &"SE"
```

测试另建 `profile.duplicate(true)`，分别删除 `texture_path`、改坏 SHA、改变图集、删除中心点和删除布局字段；每次都必须返回 `false` 且保持不可见。

- [ ] **Step 4: 运行测试并提交**

Run: `& $env:GODOT_EXE --headless --path (git rev-parse --show-toplevel).Trim() --script res://tests/test_map_token_view.gd`

Expected: PASS，退出码 0。

```powershell
git add scripts/units/map_token_view.gd tests/test_map_token_view.gd
git commit -m "feat: add static map token view"
```

---

### Task 3B: `Unit` 显示状态、HUD 与死亡接入

**Files:**
- Modify: `scenes/tactical/Unit.tscn`
- Modify: `scripts/units/unit.gd`
- Create: `tests/test_unit_map_token_visual.gd`

**Interfaces:**
- Consumes: `MapTokenView` 的五个公开接口和 `DataLoader.visual_profiles`。
- Produces: `setup(class_data: Dictionary, initial_facing: StringName = &"SE")`、`set_facing(direction: StringName) -> bool`、`get_facing() -> StringName`、`refresh_map_token_visual() -> void`、`has_runtime_map_token() -> bool`、`get_combat_text_anchor_world(fallback_offset_y: float) -> Vector2`。

- [ ] **Step 1: 写 `Unit` 失败测试**

创建测试并分别实例化剑圣、普通占位单位和坏配置剑圣。必须断言：

```gdscript
var packed := load("res://scenes/tactical/Unit.tscn") as PackedScene
var kensei: Unit = packed.instantiate()
kensei.faction = "player"
root.add_child(kensei)
kensei.setup(DataLoader.classes["kensei"], &"SE")
var token_view := kensei.get_node("MapTokenView") as Sprite2D
var placeholder_sprite := kensei.get_node("Sprite") as AnimatedSprite2D
var health_bar := kensei.get_node("HealthBar") as ProgressBar
_check("剑圣启用正式棋子", kensei.has_runtime_map_token())
_check("正式棋子显示且占位隐藏", token_view.visible and not placeholder_sprite.visible)
_check("初始方向 SE", kensei.get_facing() == &"SE")
_check("正式棋子不使用阵营染色", token_view.self_modulate == Color.WHITE)
_check("占位职业文字不存在", kensei.get_node_or_null("UnitLabel") == null)
_check("血条底边为 -58", is_equal_approx(health_bar.position.y + health_bar.size.y, -58.0))
_check("通用状态图标保留既有基线锚点", status_label != null and is_equal_approx(status_label.position.y, Unit.STATUS_BADGE_Y))
_check("实际文字锚点为 -82", kensei.get_combat_text_anchor_world(-50.0).is_equal_approx(kensei.global_position + Vector2(0, -82)))
kensei.equip_offhand("wpn_swordsman_starter")
_check("装副手切到双武器行", token_view.frame_coords.y == 1)
kensei.unequip_offhand()
_check("卸副手切回单武器行", token_view.frame_coords.y == 0)
kensei.call("_set_walk_direction", Vector2i(1, -1))
_check("多轴移动 Y 优先为 NE", kensei.get_facing() == &"NE")
```

占位单位断言 `Sprite.visible=true`、`MapTokenView.visible=false`、阵营染色与 `get_combat_text_anchor_world(-50.0)` 的旧 `-50` 偏移保持。坏配置使用复制的 `class_data` 和不存在的 `map_token_profile_id`，必须生成成功并降级占位。死亡测试对正式棋子造成致死伤害，等待一帧后断言节点已释放，不能等待不存在的动画。

- [ ] **Step 2: 运行测试确认失败**

Run: `& $env:GODOT_EXE --headless --path (git rev-parse --show-toplevel).Trim() --script res://tests/test_unit_map_token_visual.gd`

Expected: FAIL；`MapTokenView` 节点或新接口不存在。

- [ ] **Step 3: 在 `Unit.tscn` 增加正式显示节点**

增加 `map_token_view.gd` 外部资源和默认隐藏节点：

```gdscript
[node name="MapTokenView" type="Sprite2D" parent="."]
visible = false
script = ExtResource("map_token_view_script")
```

保留原 `Sprite: AnimatedSprite2D`、血条和状态节点，确保降级路径不重建场景。

- [ ] **Step 4: 在 `Unit` 中接入显示配置与 HUD**

实现以下状态与方法：

```gdscript
@onready var map_token_view: Sprite2D = $MapTokenView
var _facing: StringName = &"SE"
var _map_token_active := false
var _map_token_layout: Dictionary = {}

func setup(class_data: Dictionary, initial_facing: StringName = &"SE") -> void:
	# 保留现有属性、技能和资源初始化顺序。
	var valid_directions: Array[StringName] = [&"NW", &"NE", &"SW", &"SE"]
	_facing = initial_facing if valid_directions.has(initial_facing) else &"SE"
	# 在现有 stats/resource 初始化完成后：
	_map_token_active = _try_apply_map_token_visual(class_data)
	_apply_visuals()
	_rebuild_status_icons()
	_emit_buffs_changed()

func _try_apply_map_token_visual(class_data: Dictionary) -> bool:
	var profile_id := str(class_data.get("map_token_profile_id", ""))
	if profile_id == "":
		return false
	var profile: Dictionary = DataLoader.visual_profiles.get(profile_id, {})
	if profile.is_empty() or not bool(map_token_view.call("configure", profile)):
		push_error("[Unit] Map token profile unavailable for %s: %s" % [unit_id, profile_id])
		return false
	_map_token_layout = map_token_view.call("get_overhead_layout") as Dictionary
	_map_token_active = true
	refresh_map_token_visual()
	return true

func set_facing(direction: StringName) -> bool:
	if not [&"NW", &"NE", &"SW", &"SE"].has(direction):
		return false
	_facing = direction
	refresh_map_token_visual()
	return true

func get_facing() -> StringName:
	return _facing

func refresh_map_token_visual() -> void:
	if _map_token_active:
		map_token_view.call("set_visual_state", _facing, is_dual_wielding())

func has_runtime_map_token() -> bool:
	return _map_token_active

func get_combat_text_anchor_world(fallback_offset_y: float) -> Vector2:
	var offset_y := float(_map_token_layout.get("popup_anchor_y", fallback_offset_y)) if _map_token_active else fallback_offset_y
	return global_position + Vector2(0.0, offset_y)
```

在 `_apply_visuals()` 中使用以下分支；现有血条样式创建逻辑继续执行：

```gdscript
if _map_token_active:
	sprite.visible = false
	map_token_view.visible = true
	map_token_view.self_modulate = Color.WHITE
	var health_bottom := float(_map_token_layout["health_bar_bottom_y"])
	health_bar.position.y = health_bottom - health_bar.size.y
else:
	sprite.visible = true
	map_token_view.visible = false
	sprite.self_modulate = FACTION_COLORS.get(faction, Color.WHITE)
	sprite.scale = UNIT_ICON_SCALE
```

`_hp_label` 创建后始终复制 `health_bar.position` 与 `health_bar.size`。只有占位分支创建 `UnitLabel`。`equip_offhand()`、`unequip_offhand()` 写字段后调用 `refresh_map_token_visual()`。

`_rebuild_status_icons()` 保留既有 Buff/Debuff 状态标签创建和 `STATUS_BADGE_Y=-58` 基线；不要移动 `StatusIcons` 父节点，否则会与子标签的 Y 坐标重复叠加。行动资源徽记继续使用 `ACTION_BADGE_Y`。

- [ ] **Step 5: 固定移动朝向与安全死亡路径**

`_set_walk_direction()` 先按 Y 轴优先计算 `NW/NE/SW/SE` 并调用 `set_facing()`；只有占位模式继续播放原 walk 动画。`move_to()` 结束后只有占位模式调用 `sprite.play("idle")`，正式棋子保持最后方向。

`_on_death()` 固定为：正式棋子直接 `queue_free()`；占位 SpriteFrames 存在非循环 `death` 动画时才播放并等待，否则直接释放。

- [ ] **Step 6: 运行聚焦与双持回归后提交**

```powershell
$projectRoot = (git rev-parse --show-toplevel).Trim()
& $env:GODOT_EXE --headless --path $projectRoot --script res://tests/test_unit_map_token_visual.gd
if ($LASTEXITCODE -ne 0) { throw 'test_unit_map_token_visual failed' }
& $env:GODOT_EXE --headless --path $projectRoot --script res://tests/test_state_registry.gd
if ($LASTEXITCODE -ne 0) { throw 'test_state_registry failed' }
```

```powershell
git add scenes/tactical/Unit.tscn scripts/units/unit.gd tests/test_unit_map_token_visual.gd
git commit -m "feat: integrate map token with unit state"
```

---

### Task 4: 真实战棋场景、纵向排序与战斗文字

**Files:**
- Modify: `scenes/tactical/TacticalScene.tscn`
- Modify: `scripts/core/tactical_manager.gd`
- Modify: `scripts/tactical/tactical_scene.gd`
- Modify: `scripts/ui/damage_popup.gd`
- Modify: `tests/test_damage_popup.gd`
- Create: `tests/test_tactical_map_token_integration.gd`

**Interfaces:**
- Consumes: `Unit.setup(..., initial_facing)` 与 `Unit.get_combat_text_anchor_world(fallback_offset_y)`。
- Produces: `TacticalManager.spawn_unit(class_id, spawn_pos, faction, initial_facing = &"SE")`；`DamagePopup.spawn_at_anchor(...)`；`DamagePopup.spawn_miss_at_anchor(...)`。

- [ ] **Step 1: 先扩充战斗文字失败测试**

在 `tests/test_damage_popup.gd` 增加最终锚点 API 断言：

```gdscript
var parent := Node2D.new()
root.add_child(parent)
var anchor := Vector2(120, 80)
var legacy_origin := DamagePopup._compute_origin(anchor, "12", "sword", 16, 0, true)
var final_origin := DamagePopup._compute_origin(anchor, "12", "sword", 16, 0, false)
_check("旧 API 保留向上 50 像素", is_equal_approx(legacy_origin.y, anchor.y - 50.0))
_check("最终锚点 API 不再减 50", is_equal_approx(final_origin.y, anchor.y))
```

创建 `tests/test_tactical_map_token_integration.gd`，在 `add_child` 前设置真实 `TacticalScene` 的注入模式：一个 `kensei`、一个未绑定正式棋子的敌人。断言：`UnitLayer.y_sort_enabled=true`；所有单位父节点为 `UnitLayer`；剑圣正式显示、敌人占位；两个根位置等于 `grid.grid_to_world()`；`PopupLayer.z_index` 高于单位层；旧三参数 `spawn_unit()` 仍可用；显式 `NW` 初始朝向生效；预估目标 `world` 等于 `get_combat_text_anchor_world(-30.0)`。

预估锚点断言按现有正式接口准备状态，不通过界面点击：

```gdscript
tm.current_unit = kensei
tm.input_state = 4 # InputState.ATTACK_TARGETING
tm._attack_cells = [enemy.grid_position]
var forecast: Dictionary = tm._build_attack_forecast_for_hover(enemy.grid_position)
var targets: Array = forecast.get("targets", [])
_check("普攻预估返回一个目标", targets.size() == 1)
if targets.size() == 1:
	var target_data := targets[0] as Dictionary
	var actual_world: Vector2 = target_data["world"]
	_check("预估 world 使用最终锚点", actual_world.is_equal_approx(
		enemy.get_combat_text_anchor_world(-30.0)))
```

- [ ] **Step 2: 运行两个测试确认失败**

```powershell
$projectRoot = (git rev-parse --show-toplevel).Trim()
& $env:GODOT_EXE --headless --path $projectRoot --script res://tests/test_damage_popup.gd
& $env:GODOT_EXE --headless --path $projectRoot --script res://tests/test_tactical_map_token_integration.gd
```

Expected: FAIL；最终锚点 API、`UnitLayer` 或四参数生成接口不存在。

- [ ] **Step 3: 增加 `UnitLayer` 并保持生成兼容**

在 `TacticalScene.tscn` 的 `HighlightLayer` 与 `PopupLayer` 之间增加：

```gdscript
[node name="UnitLayer" type="Node2D" parent="TacticalManager"]
y_sort_enabled = true
```

`TacticalManager` 增加 `$UnitLayer` 引用，把生成接口改为：

```gdscript
func spawn_unit(class_id: String, spawn_pos: Vector2i,
		faction: String, initial_facing: StringName = &"SE") -> Unit:
	# 保留现有 class/enemy 查找。
	var unit: Unit = preload("res://scenes/tactical/Unit.tscn").instantiate()
	unit.faction = faction
	unit_layer.add_child(unit)
	unit.setup(class_data, initial_facing)
	unit.position = grid.grid_to_world(spawn_pos)
	# 保留 place_unit、units、调试位置和信号连接。
```

不要给单位设置递增 `z_index`；纵向排序依赖脚底根节点 Y，`PopupLayer` 保持 `z_index=50`。

- [ ] **Step 4: 传递初始朝向**

默认 `PLAYER_UNITS` 中剑圣配置增加 `"facing": &"SE"`。默认生成、注入玩家、注入敌人和调试复活路径均使用：

```gdscript
var facing := StringName(str(cfg.get("facing", "SE")))
tactical_manager.spawn_unit(str(cfg.get("class_id", "")), pos, faction, facing)
```

旧测试和实验保留三参数调用，由缺省参数兼容。

- [ ] **Step 5: 增加最终锚点战斗文字 API**

在 `damage_popup.gd` 增加：

```gdscript
static func spawn_at_anchor(parent: Node, anchor_world: Vector2, amount: int,
		damage_type: String, is_crit: bool, segment_index: int = 0) -> void:
	var parts := compose(amount, damage_type, is_crit)
	_create(parent, anchor_world, parts.text, parts.shape, parts.color, parts.size, segment_index, false)

static func spawn_miss_at_anchor(parent: Node, anchor_world: Vector2,
		segment_index: int = 0) -> void:
	_create(parent, anchor_world, "MISS", "none", COLOR_MISS, MISS_SIZE, segment_index, false)

static func _compute_origin(world_pos: Vector2, text: String, shape: String,
		font_size: int, segment_index: int, apply_legacy_offset: bool) -> Vector2:
	var glyph_width := (GLYPH_SIZE + GLYPH_GAP) if shape != "none" else 0.0
	var total_width := glyph_width + float(text.length()) * float(font_size) * 0.62
	var segment_offset := Vector2(SEGMENT_DX, -SEGMENT_DY) * float(segment_index)
	var legacy_y := -50.0 if apply_legacy_offset else 0.0
	return Vector2(world_pos.x - total_width * 0.5, world_pos.y + legacy_y) + segment_offset
```

给 `_create()` 增加 `apply_legacy_offset: bool = true` 并使用 `_compute_origin()`；旧 `spawn()`、`spawn_miss()` 和 `spawn_heal()` 继续传 `true`，新 API 传 `false`。不得改变现有文本构成、动画、暴击或多段偏移。

主手和副手的伤害/MISS 调用改用新 API，并把 `defender.get_combat_text_anchor_world(-50.0)` 作为最终坐标。

- [ ] **Step 6: 统一预估数字的最终锚点**

普攻和技能预估目标字典中的 `world` 改为目标单位的 `get_combat_text_anchor_world(-30.0)`。`TacticalScene._spawn_forecast_head_nodes()` 直接把该 `world` 转成屏幕坐标，不再额外减 `HEAD_NUMBER_OFFSET_Y`；预测面板继续使用悬停格中心，不得改动。

删除不再被任何路径使用的 `HEAD_NUMBER_OFFSET_Y` 常量，避免后续实现再次叠加旧偏移。

- [ ] **Step 7: 运行聚焦与受影响测试后提交**

```powershell
$projectRoot = (git rev-parse --show-toplevel).Trim()
$tests = @(
	'test_damage_popup.gd',
	'test_tactical_map_token_integration.gd',
	'test_tactical_inject_smoke.gd',
	'test_harness_load.gd',
	'test_harness_regression.gd',
	'test_harness_dummies.gd',
	'test_support_displacement.gd',
	'test_swordsman_skillbar.gd',
	'test_talent_carrier.gd'
)
foreach ($test in $tests) {
	& $env:GODOT_EXE --headless --path $projectRoot --script "res://tests/$test"
	if ($LASTEXITCODE -ne 0) { throw "$test failed with $LASTEXITCODE" }
}
```

```powershell
git add scenes/tactical/TacticalScene.tscn scripts/core/tactical_manager.gd scripts/tactical/tactical_scene.gd scripts/ui/damage_popup.gd tests/test_damage_popup.gd tests/test_tactical_map_token_integration.gd
git commit -m "feat: integrate map token into tactical scene"
```

---

### Task 5: 实机截图、全量回归与独立审查

**Files:**
- Create: `tests/capture_kensei_map_token_tactical.gd`

**Interfaces:**
- Consumes: 真实 `TacticalScene`、正式 `Unit`、`MapTokenView` 与战斗文字最终锚点。
- Produces: `user://visual_style_playground/kensei_map_token_tactical/<batch>/` 下的三组 PNG 及控制台绝对路径。

- [ ] **Step 1: 编写真实场景捕获脚本**

脚本必须实例化 `res://scenes/tactical/TacticalScene.tscn`，在加入根节点前设置 `run_injected=true`、`debug_harness_enabled=false` 和注入清单；不得复制 playground 的棋子绘制逻辑。捕获计划固定为：

```gdscript
const CAPTURE_ROOT := "user://visual_style_playground/kensei_map_token_tactical/"
const CAPTURE_NAMES := [
	"kensei_single_four_directions.png",
	"kensei_dual_four_directions.png",
	"kensei_occlusion_hud_popup.png",
]
```

第一张布置四名单武器剑圣并分别调用 `set_facing(NW/NE/SW/SE)`；第二张给四名剑圣 `equip_offhand("wpn_swordsman_starter")`；第三张把两名单位放在相邻 Y 深度，核验纵向遮挡、血条和通过 `DamagePopup.spawn_at_anchor()` 显示的一组伤害文字。既有行动反馈可存在，但不作为本次视觉验收项。每张截图前等待两个 `process_frame` 和一次 `RenderingServer.frame_post_draw`，从真实根 viewport 取图，验证为 `1280×720` 后保存。每次成功打印 `KENSEI_TACTICAL_CAPTURED=<absolute path>`，结束打印 `KENSEI_TACTICAL_CAPTURE_DIR=<absolute directory>`；任何失败以退出码 1 结束。

- [ ] **Step 2: 验证 Godot 版本并运行捕获**

```powershell
if (-not (Test-Path -LiteralPath $env:GODOT_EXE)) { throw 'GODOT_EXE 未指向 Godot console' }
$godotVersion = (& $env:GODOT_EXE --version).Trim()
if ($godotVersion -notmatch '^4\.6(\.|$)') { throw "VA-4 requires Godot 4.6.x, current: $godotVersion" }
$projectRoot = (git rev-parse --show-toplevel).Trim()
# headless 是快速验证“不支持捕获”的路径，必须立即以 1 退出，不能等待绘制信号。
& $env:GODOT_EXE --headless --path $projectRoot --script res://tests/capture_kensei_map_token_tactical.gd -- --capture-all
if ($LASTEXITCODE -ne 1) { throw 'Headless TacticalScene capture must fail fast with exit 1' }
# Windows 真实视觉证据使用同一 Godot console 的窗口渲染模式。
& $env:GODOT_EXE --path $projectRoot --script res://tests/capture_kensei_map_token_tactical.gd -- --capture-all
if ($LASTEXITCODE -ne 0) { throw 'Windowed TacticalScene capture failed' }
```

Expected: headless 打印“不支持捕获”标记并立即以退出码 1 结束；窗口模式生成三张 PNG，并打印绝对目录。

- [ ] **Step 3: 在会话中检查并提交视觉证据给用户**

用本地图片查看工具逐张检查原始 `1280×720` 文件，并在会话中直接显示三张图片；同时提供控制台打印的绝对目录。检查：八个状态、脚底格心、单双武器、相邻遮挡、血条和伤害数字。用户只裁决视觉结果；实现细节不再次询问。

- [ ] **Step 4: 运行全部标准回归**

```powershell
$projectRoot = (git rev-parse --show-toplevel).Trim()
$testFiles = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tests') -Filter 'test_*.gd' -File | Sort-Object Name
foreach ($testFile in $testFiles) {
	$resourcePath = "res://tests/$($testFile.Name)"
	& $env:GODOT_EXE --headless --path $projectRoot --script $resourcePath
	if ($LASTEXITCODE -ne 0) { throw "$resourcePath failed with $LASTEXITCODE" }
}
```

Expected: 所有 `tests/test_*.gd` 退出码均为 0。

- [ ] **Step 5: 运行静态检查并提交捕获脚本**

Run: `git diff --check`

Expected: 无输出，退出码 0。

```powershell
git add tests/capture_kensei_map_token_tactical.gd
git commit -m "test: capture kensei tactical visuals"
```

- [ ] **Step 6: 独立审查**

向独立审查者提供：规格、实施计划、从规格提交后的精确候选 diff、聚焦测试输出、全量回归输出和三张截图。审查者只核对完成条件、代码质量、降级路径和范围；实现者不得自我批准。发现按同一检查集集中修正后重跑受影响测试与全量回归。

---

### Task 6: 发布、PR、合并与合并后核验

**Files:**
- No new files unless审查要求修复本 Milestone 内缺陷。

**Interfaces:**
- Consumes: 工作树清洁、全部提交、独立审查通过、用户视觉验收通过。
- Produces: 已合并 PR、`develop` 上的合并后测试证据和 Milestone 完成回执。

- [ ] **Step 1: 检查候选状态**

```powershell
git status --short
git log --oneline develop..HEAD
git diff --check develop...HEAD
```

Expected: 工作树清洁；提交包含设计、计划、三个实现交付和捕获验证；差异检查通过。

- [ ] **Step 2: 使用受控入口发布分支**

```powershell
& ./scripts/codex/sot-publish.ps1 -DryRun
& ./scripts/codex/sot-publish.ps1
```

Expected: `codex/va4-kensei-map-token` 以同名分支发布到 `origin`。

- [ ] **Step 3: 创建或更新 PR**

```powershell
$captureRoot = Join-Path $env:APPDATA 'Godot\app_userdata\ShipOfTheseus\visual_style_playground\kensei_map_token_tactical'
$captureDir = Get-ChildItem -LiteralPath $captureRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($null -eq $captureDir) { throw '未找到 VA-4 实机截图批次' }
$captureBatch = $captureDir.Name
$prBody = @"
## Milestone
VA-4：剑圣正式战棋棋子进入真实 TacticalScene。

## Asset identity
SHA256: e6f33324c52929769d4698ed75e969470ec45748788503f4637fcb3223dc5415
Binding: kensei only

## Verification
- Godot 4.6.x focused tests: test_kensei_map_token_asset, test_map_token_view, test_unit_map_token_visual, test_tactical_map_token_integration passed
- Full tests/test_*.gd regression: passed
- Independent review: passed
- User visual acceptance: passed
- Screenshot batch: $captureBatch
- Screenshot files: kensei_single_four_directions.png, kensei_dual_four_directions.png, kensei_occlusion_hud_popup.png
"@
gh pr create --base develop --head codex/va4-kensei-map-token --title "feat: integrate kensei map token" --body $prBody
```

若 PR 已存在则使用相同正文运行 `gh pr edit --body $prBody`。

- [ ] **Step 4: 完成 PR 审查与合并**

```powershell
$prUrl = gh pr view --json url --jq .url
gh pr checks --watch
gh pr merge --merge
```

Expected: 必要检查通过，PR 以 merge commit 合并。记录 `$prUrl` 与 `gh pr view $prUrl --json mergeCommit --jq .mergeCommit.oid`。PR 创建不等于 Task 或 Milestone 完成。

- [ ] **Step 5: 在最新 `develop` 上做合并后核验**

在新的只读/核验工作树取得最新 `origin/develop`，重新运行：

```powershell
git fetch origin develop
$repositoryParent = Split-Path -Parent (git rev-parse --show-toplevel).Trim()
$postMergeRoot = Join-Path $repositoryParent 'va4-post-merge-verify'
if (Test-Path -LiteralPath $postMergeRoot) { throw "核验目录已存在：$postMergeRoot" }
git worktree add --detach $postMergeRoot origin/develop
$postMergeTests = @(
	'res://tests/test_kensei_map_token_asset.gd',
	'res://tests/test_unit_map_token_visual.gd',
	'res://tests/test_tactical_map_token_integration.gd'
)
foreach ($testScript in $postMergeTests) {
	& $env:GODOT_EXE --headless --path $postMergeRoot --script $testScript
	if ($LASTEXITCODE -ne 0) { throw "$testScript failed after merge with $LASTEXITCODE" }
}
$productionAsset = Join-Path $postMergeRoot 'assets\units\kensei\map_token_clean_v2.png'
if ((Get-FileHash $productionAsset -Algorithm SHA256).Hash.ToLowerInvariant() -ne 'e6f33324c52929769d4698ed75e969470ec45748788503f4637fcb3223dc5415') {
	throw '合并后正式素材 SHA256 不一致'
}
```

并重新核对正式 PNG SHA256。Expected: 三项测试退出码 0，SHA256 精确一致。

- [ ] **Step 6: 返回 Milestone 回执**

使用 `sot-task-receipt` 报告：分支和提交、改变文件、素材/KB 来源证据、Godot 版本、聚焦与全量测试、三张截图、独立审查、PR/merge commit、合并后核验。只有所有完成条件均满足时才把 `Milestone VA-4` 标记完成。
