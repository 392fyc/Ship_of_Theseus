# 底栏装备／遗物／结束回合 Godot 纵向切片 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Milestone:** `GHV-3-UTILITY-HUD-VERTICAL-SLICE`

**Goal:** 在不修改生产 `BottomDashboard`、装备／遗物玩法规则和现有刷新链的前提下，用真实 Godot 4.6.3 组件完成装备栏、固定血瓶按钮、8 格遗物视觉网格和结束回合／结束移动双语义按钮的结构纵向切片，并形成下一批最小素材需求。

**Architecture:** 建立独立的 `HudSlotButton`、`PotionButton`、`EquipmentHudPanel`、`RelicGrid`、`EndTurnButton` 与 `EndTurnControl` 场景。静态层级和固定几何由 `.tscn`、Container 与 Theme 声明；脚本只接收有类型显示数据、更新既有节点和发出语义信号。装备、遗物、血瓶内容在本期全部明确为 `mock-only`；遗物场景的 8 个槽只证明已批准的视觉布局，不改变当前玩法的 6 槽上限。结束回合组件保留现有 `end_turn` 与 `end_move` 两套真实语义。

**Tech Stack:** Godot 4.6.3、GDScript、Control／Container／Button、Theme 类型变体、RefCounted 显示数据、SceneTree 测试、PNG 实机截图。

**Specs:**

- `dev_doc/skillbar-design/bottom-dashboard-combined-visual-design-spec.md`
- `dev_doc/ui-art-research/godot-hud-asset-layer-methodology-2026-09-02.md`

## Global Constraints

- 不修改 `scripts/ui/bottom_dashboard.gd`、`scripts/ui/skill_bar.gd`、`scripts/ui/action_resource_bar.gd`、`TacticalManager`、`TacticalScene`、`RunState`、`RunManager` 或玩法 JSON。
- 装备、遗物和血瓶尚未进入战斗 HUD 刷新链；其 `content_id`、图标、tooltip 与占用状态只用于明确标注的画廊 mock，不伪装成生产接线。
- 视觉布局固定为 8 个遗物槽，但当前玩法仍由 `RunState.RELIC_SLOT_MAX = 6` 控制。本里程碑不得把 8 写成玩法容量，不得修改 6 槽拦截规则。
- 血瓶只冻结为全职业通用、装备栏内部右上角的独立 32×32 按钮；不新增次数、补充、冷却、治疗量或商店药水映射。
- 结束按钮必须保留 `end_turn` 与 `end_move` 两种 action kind，并分别发出 `end_turn_requested` 与 `end_move_requested`；不得只保留其中一个。
- 正式界面不显示 `EQUIPMENT`、`WPN`、`ARM`、`RELIC`、`END` 等审核文字；说明文字不参与几何计算。
- 本里程碑不生成或导入武器、防具、血瓶、遗物图标，也不使用已取代的旧批量面板、槽位或结束按钮候选。
- 先用 Theme 和引擎绘制证明结构；只有 Gate 3 后才能决定图片职责。用户已允许连续执行，但图片候选仍需最终视觉审核。

## 固定几何

- 装备栏：128×108。武器槽 52×52，位置 x=8、y=48；防具槽 52×52，位置 x=68、y=48；血瓶按钮 32×32，位置 x=88、y=8。
- 遗物栏：278×108。内部视觉网格 254×96，位置 x=12、y=6；2 行×4 列共 8 个 44×44 正方形槽，横向间距 26、纵向间距 8。
- 结束区：76×108。52×52 正方形按钮位于 x=12、y=28；内部菱形框与沙漏图形分层，菱形略大于沙漏且边缘不接触。

## Milestone 完成条件

- 六个组件均为可独立加载的声明式 `.tscn`；静态节点不由脚本动态创建；
- 有类型显示数据不持有 `Unit`、`RunState`、`GameAction`、`TacticalManager` 或 `BottomDashboard`；
- 装备栏、血瓶、遗物网格与结束区符合上述固定几何，所有正方形控件保持正方形；
- 8 个遗物槽只作为视觉槽壳存在，文档、字段和测试均不宣称玩法容量为 8，现有 6 槽玩法测试保持通过；
- 空槽、mock 占用、不可用、焦点与按下状态的运行时职责清楚；具体内容图标不进入结构皮肤；
- 结束按钮在 `end_turn` 与 `end_move` 下分别发出正确信号，禁用或隐藏时不触发；无 `END` 烘焙文字；
- 1280×720、1920×1080、2560×1440 三档截图可查看，组件无裁切、重叠或安全边界越界；
- Gate 3 只保留拥有明确消费者且 Theme／现有同族表面不足的图片职责；
- 新增测试、既有 HUD 测试、生产回归和 `test_prep_flow.gd` 通过，受保护脚本不变；
- 独立只读审查通过；候选仍明确等待用户视觉审核，不提交、不发布。

---

### Task 1: 显示合同、有类型数据与失败测试

**Files:**
- Create: `dev_doc/ui-art-research/hud-ghv3-utility-slice/display-contract.md`
- Create: `scripts/ui/hud/slot_view_data.gd`
- Create: `scripts/ui/hud/potion_view_data.gd`
- Create: `scripts/ui/hud/end_turn_view_data.gd`
- Create: `tests/test_hud_slot_button.gd`
- Create: `tests/test_hud_equipment_panel.gd`
- Create: `tests/test_hud_relic_grid.gd`
- Create: `tests/test_hud_end_turn_control.gd`

- [x] **Step 1:** 记录生产事实、mock-only 字段、8 格视觉布局与 6 格玩法容量的边界，以及结束回合双信号合同。
- [x] **Step 2:** 定义纯显示 `RefCounted` 数据；不得加入血瓶次数／冷却或遗物玩法容量字段。
- [x] **Step 3:** 先写场景、节点、固定几何、运行时绑定、信号和玩法隔离测试。
- [x] **Step 4:** 运行四个测试并确认因组件场景尚不存在而 RED。

### Task 2: 通用槽与独立血瓶按钮

**Files:**
- Create: `scripts/ui/hud/slot_button.gd`
- Create: `scripts/ui/hud/potion_button.gd`
- Create: `scenes/tactical/hud/slot_button.tscn`
- Create: `scenes/tactical/hud/potion_button.tscn`
- Modify: `assets/ui/themes/hud_structure_prototype.tres`

- [x] **Step 1:** 声明 `HudSlotButton` 的 Button 根、IconRect 与焦点／状态层；脚本只实现显示绑定和无玩法含义的槽位按下信号。
- [x] **Step 2:** 声明独立 `PotionButton`，保留图标接口、tooltip、enabled 和 `potion_requested`；不显示次数、冷却或补给状态。
- [x] **Step 3:** 为 52×52、44×44 与 32×32 建立 Theme 占位变体，文字和内容图标均不烘焙。
- [x] **Step 4:** 运行 `test_hud_slot_button.gd` 并确认 GREEN。

### Task 3: `EquipmentHudPanel`

**Files:**
- Create: `scripts/ui/hud/equipment_hud_panel.gd`
- Create: `scenes/tactical/hud/equipment_hud_panel.tscn`
- Test: `tests/test_hud_equipment_panel.gd`

- [x] **Step 1:** 在 128×108 声明两个 52×52 槽和右上 32×32 血瓶按钮，位置严格遵循固定几何。
- [x] **Step 2:** 组件只把 mock 显示数据转交子组件；不读取 `RunState.equipment` 或商店 `potions`。
- [x] **Step 3:** 验证空槽、占用 mock、不可用和血瓶按钮接口，正式可见树不出现审核文字。
- [x] **Step 4:** 运行 `test_hud_equipment_panel.gd` 并确认 GREEN。

### Task 4: `RelicGrid` 的 8 格视觉布局

**Files:**
- Create: `scripts/ui/hud/relic_grid.gd`
- Create: `scenes/tactical/hud/relic_grid.tscn`
- Test: `tests/test_hud_relic_grid.gd`

- [x] **Step 1:** 以 `GridContainer(columns=4)` 声明 8 个 44×44 槽，网格尺寸和间距严格符合固定几何。
- [x] **Step 2:** 允许画廊逐槽注入 mock 显示数据，但 API 不暴露或改变玩法容量常量。
- [x] **Step 3:** 测试明确断言“8 是视觉槽壳数量，不是生产玩法容量”，并静态保护 `RunState.RELIC_SLOT_MAX = 6`。
- [x] **Step 4:** 运行 `test_hud_relic_grid.gd` 与 `test_prep_flow.gd` 并确认 GREEN。

### Task 5: `EndTurnButton` 与双语义结束区

**Files:**
- Create: `scripts/ui/hud/end_turn_frame.gd`
- Create: `scripts/ui/hud/end_turn_emblem.gd`
- Create: `scripts/ui/hud/end_turn_button.gd`
- Create: `scripts/ui/hud/end_turn_control.gd`
- Create: `scenes/tactical/hud/end_turn_button.tscn`
- Create: `scenes/tactical/hud/end_turn_control.tscn`
- Test: `tests/test_hud_end_turn_control.gd`

- [x] **Step 1:** 声明 52×52 Button、独立菱形框层与居中沙漏层；不显示 `END` 或其他文字。
- [x] **Step 2:** 引擎占位绘制中让菱形明显大于沙漏并保留可测空隙；两层保持独立，便于 Gate 3 替换。
- [x] **Step 3:** `apply_view()` 只绑定 action kind、visible、enabled 和 tooltip；按下时分别发出 `end_turn_requested` 或 `end_move_requested`。
- [x] **Step 4:** 运行 `test_hud_end_turn_control.gd` 与 `test_skillbar_v3_ui.gd` 并确认 GREEN。

### Task 6: 状态画廊、三档证据、Gate 3 与独立审查

**Files:**
- Create: `scripts/ui/playground/hud_utility_vertical_slice_gallery.gd`
- Create: `scenes/dev/hud_utility_vertical_slice_gallery.tscn`
- Create: `tests/test_hud_utility_vertical_slice_gallery.gd`
- Create: `tests/capture_hud_utility_vertical_slice_gallery.gd`
- Create: `dev_doc/ui-art-research/hud-ghv3-utility-slice/evidence/README.md`
- Create: `dev_doc/ui-art-research/hud-ghv3-utility-slice/evidence/visual-verdict.json`
- Create: `dev_doc/ui-art-research/hud-ghv3-utility-slice/minimum-asset-needs.md`
- Create: `dev_doc/ui-art-research/hud-ghv3-utility-slice/candidate-receipt.json`

- [x] **Step 1:** 建立空装备、mock 占用、禁用、8 格空遗物、局部 mock 遗物、结束回合、结束移动与禁用结束按钮状态板。
- [x] **Step 2:** 自动验证固定几何、正方形、运行时层、信号和所有状态板位于安全画布内。
- [x] **Step 3:** 生成并逐张检查 1280×720、1920×1080、2560×1440 三档实机截图。
- [x] **Step 4:** 对面板、通用槽、血瓶壳体、结束菱形框、沙漏图形和内容图标逐项执行 Gate 3；先测试现有同族表面能否安全复用。
- [x] **Step 5:** 运行新增、既有 HUD、生产回归、`test_prep_flow.gd`、JSON、截图、保护脚本和差异检查。
- [x] **Step 6:** 由独立只读审查者核对规格、6／8 边界、运行证据和范围；修正客观缺陷后记录最终结论。

## Self-review

- Data truth: 装备／遗物／血瓶内容全部标为 mock；只有结束按钮双语义拥有现有生产事实。
- Capacity truth: 8 格只属于视觉网格，当前玩法上限 6 保持受保护。
- Component boundaries: 通用槽、血瓶、装备面板、遗物网格、结束按钮与结束区职责分开；技能专用组件不被错误复用。
- Asset method: Gate 2 先用 Theme／引擎图形，Gate 3 才决定能否复用现有表面或生成最小新图片。
- Scope containment: 不接生产 HUD，不修改玩法规则，不导入旧批量候选或具体内容图标。
