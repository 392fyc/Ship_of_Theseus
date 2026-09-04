# HUD Godot Vertical Slices Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用两个真实 Godot 4.6 声明式组件验证已批准的 HUD 素材分层方法，并只根据实机证据形成下一批最小素材需求。

**Architecture:** `SkillSlotButton` 与 `ActionResourceStrip` 各自是可独立实例化的 `.tscn`；静态节点树、布局与占位皮肤由场景和 Theme 声明，脚本只接收有类型的显示数据、创建数量动态的行动点并发出交互信号。状态画廊同时实例化 5／6／7 技能和行动资源边界状态，在 720p、1080p、1440p 下生成实机证据；本 Milestone 不替换现有 `BottomDashboard` 生产接线，也不生成正式技能、装备或遗物图标。

**Tech Stack:** Godot 4.6.1、GDScript、Control／Container、Button、Theme 类型变体、StyleBoxFlat、SceneTree 测试、PNG 实机截图。

**Spec:** `dev_doc/ui-art-research/godot-hud-asset-layer-methodology-2026-09-02.md`

## Global Constraints

- 用户于 2026-09-02 通过现行方法；旧原子素材规格、合同和批量生产计划不得恢复。
- 本 Milestone 仅交付 `SkillSlotButton`、`ActionResourceStrip`、占位 Theme、状态画廊、测试和证据；不改 `scripts/ui/bottom_dashboard.gd`、`scripts/ui/skill_bar.gd`、`scripts/ui/action_resource_bar.gd` 或战斗规则。
- 不生成或嵌入正式技能图标；不购买素材；不调用外部图像 API key。
- `passive` 与 `active_capable` 是独立字段；`passive=true, active_capable=true` 必须可以触发。
- 技能槽不显示 `ACTIVE`、`PASSIVE` 或 `P` 类别标识；快捷键在 16×16 方形角标内水平、垂直居中。
- 行动资源不显示“可用”“已用”文字，不绘制分隔柱或耗尽斜杠。移动使用向上的足迹和纯数值；标准行动为绿色圆点；迅捷行动为橘黄色三角。
- 标准和迅捷行动只创建实际容量 1—3 的点，并在各自固定区域内居中；耗尽点保留同形并灰化。
- 结构样机使用 Theme 与引擎图形，不据此冻结正式材质；只有三档实机验证后才能写最小素材需求。
- 新生产方法不得依靠脚本逐个创建静态节点树；只有随容量变化的行动点允许动态创建。
- 执行方式沿用用户已批准的连续执行规则，在当前会话内逐 Task 推进，不另行请求实现细节确认。

## Milestone 完成条件

- 两个组件分别能独立加载、实例化，并且根节点与主要子节点由 `.tscn` 声明；
- 两套有类型显示数据覆盖边界值，组件不会保存战斗单位或玩法对象引用；
- 技能槽的点击、焦点、禁用、冷却、快捷键、次数和选择状态通过自动测试；
- 行动资源的容量 1／2／3、部分消耗、全部消耗、移动灰化、无文字／分隔柱／斜杠通过自动测试；
- 状态画廊在 1280×720、1920×1080、2560×1440 生成可查看 PNG，且没有裁切、重叠或超出安全画布；
- 根据纵向切片证据产出最小素材需求文档，明确“需要图片”“继续由 Theme 表达”“继续由运行时图层表达”；
- 独立审核与用户视觉审核属于明确 Gate；创建截图不等于 Milestone 自动完成。

---

### Task 1: 有类型显示数据与 `SkillSlotButton`

**Files:**
- Create: `scripts/ui/hud/skill_slot_view_data.gd`
- Create: `scripts/ui/hud/skill_slot_button.gd`
- Create: `scenes/tactical/hud/skill_slot_button.tscn`
- Create: `assets/ui/themes/hud_structure_prototype.tres`
- Create: `tests/test_hud_skill_slot_button.gd`

**Interfaces:**
- Produces: `HudSkillSlotViewData.new()` with typed fields `skill_id`, `icon_texture`, `hotkey_text`, `enabled`, `selected`, `cooldown_turns`, `charges`, `show_charges`, `passive`, `active_capable`, `tooltip_text`.
- Produces: `HudSkillSlotViewData.can_activate() -> bool`; this method ignores `passive` and evaluates identity, capability, enabled state and cooldown.
- Produces: `HudSkillSlotButton.apply_view(view: HudSkillSlotViewData) -> void` and `signal skill_activated(skill_id: String)`.
- Produces scene-owned nodes: `%IconRect`, `%CooldownShade`, `%CooldownTurnsLabel`, `%SelectedOverlay`, `%HotkeyBadge`, `%HotkeyText`, `%ChargeText`.

- [x] **Step 1: Write the failing behavior and structure test**

Create `tests/test_hud_skill_slot_button.gd` in the repository `SceneTree` test style. It must load `res://scenes/tactical/hud/skill_slot_button.tscn`, add the instance to `root`, wait one frame, and assert:

```gdscript
var passive_active := HudSkillSlotViewData.new()
passive_active.skill_id = "counter_stance"
passive_active.passive = true
passive_active.active_capable = true
passive_active.enabled = true
_check("可主动触发的被动技能可用", passive_active.can_activate())

var slot := scene.instantiate() as HudSkillSlotButton
root.add_child(slot)
slot.apply_view(passive_active)
slot.pressed.emit()
_eq("被动技能发出激活信号", activated_id, "counter_stance")
```

Also assert that the root is a `Button`, `theme_type_variation == &"SkillSlotButton"`, every named child exists with the expected Godot type, the hotkey label uses both center alignments, the badge minimum size is 16×16, the visible text tree contains neither `ACTIVE`, `PASSIVE` nor `P`, and disabled/cooldown/capability states suppress activation.

- [x] **Step 2: Run the new test and verify RED**

Run:

```powershell
& $godot --headless --path $project --script res://tests/test_hud_skill_slot_button.gd
```

Expected: exit 1 because the view-data script and scene do not exist.

- [x] **Step 3: Add the typed display object**

Implement `HudSkillSlotViewData extends RefCounted`. `can_activate()` must return:

```gdscript
return skill_id != "" and active_capable and enabled and cooldown_turns <= 0
```

技能冷却只使用整数剩余回合数；大于零时显示居中数字，以半透明近黑暗层压低亮度但保留图标辨识度，并禁用技能；归零时隐藏。不要增加比例进度条、玩法成本或单位引用。

- [x] **Step 4: Add the declarative scene and minimal component script**

The `.tscn` root is `Button`; its children are declared in the scene, not constructed in `_ready()`. Connect the root's built-in `pressed` signal inside the script. `apply_view()` updates node properties and root `disabled`; it never changes the node tree.

Use a project resource `hud_structure_prototype.tres` with a `SkillSlotButton` variation based on `Button`. Supply `normal`, `hover`, `pressed`, `disabled` and `focus` `StyleBoxFlat` states. These are structure placeholders, not approved production material.

- [x] **Step 5: Run focused test and relevant existing regression**

Run:

```powershell
& $godot --headless --path $project --script res://tests/test_hud_skill_slot_button.gd
& $godot --headless --path $project --script res://tests/test_skillbar_v3_ui.gd
```

Expected: both exit 0. Existing `skill_bar.gd` is unchanged, so this Task proves the new component without silently replacing production behavior.

---

### Task 2: `ActionResourceStrip` 与动态点组

**Files:**
- Create: `scripts/ui/hud/action_resource_view_data.gd`
- Create: `scripts/ui/hud/action_resource_glyph.gd`
- Create: `scripts/ui/hud/action_resource_strip.gd`
- Create: `scenes/tactical/hud/action_resource_strip.tscn`
- Create: `tests/test_hud_action_resource_strip.gd`

**Interfaces:**
- Produces: `HudActionResourceViewData` fields `movement_remaining`, `movement_available`, `standard_capacity`, `standard_remaining`, `swift_capacity`, `swift_remaining`.
- Produces: `HudActionResourceViewData.normalize() -> void`; capacities clamp to 1—3 and remaining values clamp to their capacities; movement remaining never drops below zero.
- Produces: `HudActionResourceStrip.apply_view(view: HudActionResourceViewData) -> void`.
- Produces scene-owned nodes: `%MovementCluster`, `%FootprintGlyph`, `%MovementValue`, `%StandardZone`, `%StandardPips`, `%SwiftZone`, `%SwiftPips`.
- Produces: `HudActionResourceGlyph.configure(kind: Kind, spent: bool) -> void` where `Kind` is `FOOTPRINT`, `STANDARD`, or `SWIFT`.

- [x] **Step 1: Write the failing resource structure test**

Create `tests/test_hud_action_resource_strip.gd`. It must instantiate the real scene and assert:

```gdscript
view.standard_capacity = 3
view.standard_remaining = 2
view.swift_capacity = 2
view.swift_remaining = 0
strip.apply_view(view)
_eq("标准行动只创建实际容量", strip.get_standard_pips().size(), 3)
_eq("迅捷行动只创建实际容量", strip.get_swift_pips().size(), 2)
_eq("标准行动部分消耗", _spent_states(strip.get_standard_pips()), [false, false, true])
_eq("迅捷行动全部消耗", _spent_states(strip.get_swift_pips()), [true, true])
```

Also assert the three fixed semantic regions exist in an `HBoxContainer`, `StandardPips` and `SwiftPips` use centered alignment, visible labels contain only the numeric movement value, no node name contains `Divider`, no visible text is `可用` or `已用`, spent glyphs keep the same kind and use the shared gray color, and the glyph implementation contains no slash-state property.

- [x] **Step 2: Run the new test and verify RED**

Run the focused test. Expected: exit 1 because the new scripts and scene do not exist.

- [x] **Step 3: Implement typed normalization and lightweight glyph drawing**

`normalize()` clamps values. `HudActionResourceGlyph._draw()` draws an upward footprint for `FOOTPRINT`, a filled circle for `STANDARD`, and an upright triangle for `SWIFT`. It chooses active or spent color before drawing; it must not call a second draw operation to add a slash over spent glyphs.

- [x] **Step 4: Implement the declarative strip**

Declare the shell, margin, main row and three semantic regions in the `.tscn`. The script may clear and recreate only the capacity-dependent pip children of `%StandardPips` and `%SwiftPips`. It updates movement text and colors without rebuilding static nodes.

- [x] **Step 5: Run focused tests**

Run `test_hud_action_resource_strip.gd` and the existing `test_action_resource_bar.gd`. The new focused test must pass. The old production test must also stay green because GHV-1 does not replace `scripts/ui/action_resource_bar.gd`.

---

### Task 3: 状态画廊与 5／6／7 布局

**Files:**
- Create: `scripts/ui/playground/hud_vertical_slice_gallery.gd`
- Create: `scenes/dev/hud_vertical_slice_gallery.tscn`
- Create: `tests/test_hud_vertical_slice_gallery.gd`

**Interfaces:**
- Consumes: both new PackedScenes and typed view-data classes.
- Produces: gallery boards named `SkillCount5`, `SkillCount6`, `SkillCount7`, `ActionCapacity1`, `ActionCapacity2`, `ActionCapacity3`, `ActionMovementDisabled`.
- Produces: `set_reference_size(size: Vector2i) -> void` for deterministic resolution checks.

- [x] **Step 1: Write the failing gallery test**

The test loads the real gallery scene, verifies its script is attached, and for each skill board asserts exact count, fixed 476×108 shelf size, centered children, and no clipping. It verifies all action boards expose the expected capacity and state.

- [x] **Step 2: Run and verify RED**

Expected: exit 1 because the gallery does not exist.

- [x] **Step 3: Implement the gallery**

The `.tscn` declares the viewport-safe root, title labels and board containers. The gallery script only instantiates repeated component scenes and supplies display data. Five and six skills use 64×64 slots; seven skills use the smallest size that fits inside the same 476×108 shelf, recorded by the test rather than promoted to a production Theme variation.

- [x] **Step 4: Run focused and parse checks**

Run the gallery test and:

```powershell
& $godot --headless --editor --path $project --quit
```

Expected: exit 0 with no parse or scene load errors.

---

### Task 4: 三档实机截图与视觉检查

**Files:**
- Create: `tests/capture_hud_vertical_slice_gallery.gd`
- Create: `dev_doc/ui-art-research/hud-ghv1-vertical-slice-evidence/README.md`
- Create: generated PNG files under `dev_doc/ui-art-research/hud-ghv1-vertical-slice-evidence/`

**Interfaces:**
- Consumes: `scenes/dev/hud_vertical_slice_gallery.tscn`.
- Produces: `hud_vertical_slice_1280x720.png`, `hud_vertical_slice_1920x1080.png`, `hud_vertical_slice_2560x1440.png`.

- [x] **Step 1: Write capture validation before capture implementation**

The capture script must refuse headless mode, require `--capture-hud-vertical-slices`, set each requested window size, wait for layout and `RenderingServer.frame_post_draw`, assert the image dimensions, then save PNG. It must exit 1 if any board lies outside its viewport-safe root.

- [x] **Step 2: Run in headless mode and verify intentional RED**

Run with `--headless` and the capture argument. Expected: exit 1 with `HUD_VERTICAL_SLICE_CAPTURE_UNSUPPORTED_HEADLESS`.

- [x] **Step 3: Run windowed capture**

Use Godot 4.6.1 console executable. Expected: three PNG files at exact requested dimensions and exit 0.

- [x] **Step 4: Inspect all three images**

Check: no `ACTIVE`／`PASSIVE`／`P` marker, no action-state words, no divider posts, no spent slash, hotkeys centered, all action points inside their fixed zones, and all 5／6／7 layouts inside the same shelf frame. Record observations and any failed state in the evidence README.

---

### Task 5: Gate 3 最小素材需求

**Files:**
- Create: `dev_doc/ui-art-research/hud-ghv1-minimum-asset-needs.md`
- Modify only if proven necessary: `dev_doc/skillbar-design/hud-r1-atomic-asset-contract.json`

**Interfaces:**
- Consumes: tests, three screenshots, scene trees and placeholder Theme.
- Produces: a three-way decision table with `需要图片`、`继续由 Theme 表达`、`继续由运行时图层表达`.

- [x] **Step 1: Inventory actual consumers**

For every visible responsibility in the two slices, record the exact node or Theme type consuming it. Any item without a unique consumer is rejected from the image list.

- [x] **Step 2: Apply Gate 3 questions**

Decide whether the placeholder Theme is insufficient for the approved dark gothic refined-pixel material, whether a texture must stretch, whether it changes with content, and whether it changes at runtime. Record NinePatch and filtering only as candidates until visual assets exist.

- [x] **Step 3: Run document and contract checks**

Validate JSON if modified, run `git diff --check`, and search the new needs document for forbidden premature commitments: fixed generated filenames without a consumer, baked text/numbers, a global filter rule, or bulk production authorization.

- [x] **Step 4: Submit the evidence Gate**

Open the methodology, evidence README, three screenshots and minimum-needs document for user review. This is the end of GHV-1; do not start image generation until the user accepts the Gate 3 result.

## Self-review

- Spec coverage: Tasks 1—4 cover typed data, declarative scenes, Theme, runtime layers, 5／6／7 skills, action capacities and three resolutions; Task 5 covers the post-slice asset decision.
- Scope containment: existing production HUD scripts and gameplay rules are explicitly excluded.
- Type consistency: both components consume dedicated `RefCounted` view-data classes; gallery and tests use the same class and method names.
- Placeholder scan: no unfinished implementation decision is delegated to a later worker; visual material itself is intentionally a tested placeholder because formal material production is outside this Milestone.
- Execution mode: inline continuous execution, as previously authorized by the user.
