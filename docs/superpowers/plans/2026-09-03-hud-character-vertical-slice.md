# 角色栏 Godot 纵向切片 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Milestone:** `GHV-2-CHARACTER-HUD-VERTICAL-SLICE`

**Goal:** 在不修改现有生产 HUD 和玩法规则的前提下，以真实 Godot 4.6.3 组件证明角色栏的职业名／玩家名、等级／经验、HP／护盾、头像接口和动态数值条可以由声明式场景与有类型显示数据表达，并形成下一批最小图片需求。

**Architecture:** `CharacterHudPanel.tscn` 固定为 226×108，并组合可复用的 `HudValueMeter.tscn`。静态节点、三组等距布局、轨道与文字层在 `.tscn`／Theme 中声明；脚本只接收 `RefCounted` 显示数据、计算受限显示比例和绑定文本／头像。当前生产只真实提供职业名、HP 和 HP 上限；玩家名、等级、经验、护盾与头像在画廊中使用明确 mock，不伪装成已接通的生产事实。

**Tech Stack:** Godot 4.6.3、GDScript、Control／Container、ProgressBar、Theme 类型变体、RefCounted 显示数据、SceneTree 测试、PNG 实机截图。

## Global Constraints

- 不修改 `scripts/ui/bottom_dashboard.gd`、`scripts/ui/skill_bar.gd`、`scripts/ui/action_resource_bar.gd`、`TacticalManager`、`TacticalScene`、`Unit` 或玩法 JSON。
- 不新增或推断等级、经验、护盾、玩家名、头像的玩法来源；这些字段在本里程碑只验证显示合同。
- 不生成头像、头像框、面板、数值条轨道或填充图片；先用 Theme 和运行时控件完成 Gate 2。
- 职业名在前、玩家自定义名称在后，属于真实运行时字段；长名称必须单行截断并保留完整 tooltip。
- 等级与经验为一组；HP 与护盾位于一个共同外框中的两条独立填充条。所有数值由运行时 Label 显示，禁止图片占位。
- 数值显示使用统一的高对比描边字体样式；普通值与长值都不得溢出或遮挡填充条。
- 角色栏外框 226×108；右列三组高度 18／20／28，组间距均为 8，上下边距均为 13。
- 本里程碑只交付角色栏纵向切片、极值画廊、三档截图、Gate 3 素材判定和独立审查，不接入生产 `BottomDashboard`。

## Milestone 完成条件

- `HudValueMeter` 与 `CharacterHudPanel` 均为可独立实例化的声明式 `.tscn`，静态子节点不由脚本动态创建；
- 有类型显示数据不持有 `Unit`、`RunState`、`GameAction` 或其他玩法对象；
- 经验、HP、护盾的当前值、最大值、比例和文字由运行时输入产生，非法最大值安全归零；
- HP 与护盾共享外框但保持独立填充与数值；等级／经验与名称／职业组的间距相等；
- 普通值、零护盾、满值、超大数值、长职业名和长玩家名均无溢出、裁切或重叠；
- 1280×720、1920×1080、2560×1440 三档实机截图可查看；
- 下一批图片需求只保留有唯一消费者且 Theme 不足以表达的职责；
- 相关自动测试通过，三个受保护生产脚本相对基线不变；
- 独立只读审查通过，候选仍明确等待用户视觉审核；不提交、不发布。

---

### Task 1: 显示合同与失败测试

**Files:**
- Create: `dev_doc/ui-art-research/hud-ghv2-character-slice/display-contract.md`
- Create: `scripts/ui/hud/value_meter_view_data.gd`
- Create: `scripts/ui/hud/character_hud_view_data.gd`
- Create: `tests/test_hud_value_meter.gd`
- Create: `tests/test_hud_character_panel.gd`

- [x] **Step 1:** 记录生产已接通字段与 mock-only 字段，明确唯一生产刷新链和受保护接口。
- [x] **Step 2:** 定义只含显示值的两个 `RefCounted` 类型；比例只读并限制到 0—1。
- [x] **Step 3:** 先写场景、节点、尺寸、数据绑定、极值与对象隔离测试。
- [x] **Step 4:** 运行两个测试并确认因场景／脚本尚不存在而 RED。

### Task 2: `HudValueMeter` 声明式组件

**Files:**
- Create: `scripts/ui/hud/value_meter.gd`
- Create: `scenes/tactical/hud/value_meter.tscn`
- Modify: `assets/ui/themes/hud_structure_prototype.tres`
- Test: `tests/test_hud_value_meter.gd`

- [x] **Step 1:** 以 `Control + ProgressBar + Label` 声明静态层级，脚本只实现 `apply_view()`。
- [x] **Step 2:** 为经验、HP、护盾建立 Theme 类型变体；轨道／填充仍为引擎 StyleBox，不使用图片。
- [x] **Step 3:** 验证 0、部分、满值、超过上限、最大值为 0 与超长数值文本。
- [x] **Step 4:** 运行 `test_hud_value_meter.gd` 并确认 GREEN。

### Task 3: `CharacterHudPanel` 声明式组件

**Files:**
- Create: `scripts/ui/hud/character_hud_panel.gd`
- Create: `scenes/tactical/hud/character_hud_panel.tscn`
- Modify: `assets/ui/themes/hud_structure_prototype.tres`
- Test: `tests/test_hud_character_panel.gd`

- [x] **Step 1:** 声明头像区、名称组、等级／经验组、HP／护盾共同外框和三个 `HudValueMeter` 实例。
- [x] **Step 2:** 实现 `apply_view()`；头像缺失时只使用显式 fallback 字符，不读取 Unit。
- [x] **Step 3:** 验证 226×108、18／20／28 三组、两个 8 像素间距、长名称 tooltip、零护盾和数值更新。
- [x] **Step 4:** 运行 `test_hud_character_panel.gd` 并确认 GREEN。

### Task 4: 极值画廊与三档实机截图

**Files:**
- Create: `scripts/ui/playground/hud_character_vertical_slice_gallery.gd`
- Create: `scenes/dev/hud_character_vertical_slice_gallery.tscn`
- Create: `tests/test_hud_character_vertical_slice_gallery.gd`
- Create: `tests/capture_hud_character_vertical_slice_gallery.gd`
- Create: `dev_doc/ui-art-research/hud-ghv2-character-slice/evidence/README.md`
- Create: `dev_doc/ui-art-research/hud-ghv2-character-slice/evidence/visual-verdict.json`
- Create: `dev_doc/ui-art-research/hud-ghv2-character-slice/evidence/hud_character_slice_1280x720.png`
- Create: `dev_doc/ui-art-research/hud-ghv2-character-slice/evidence/hud_character_slice_1920x1080.png`
- Create: `dev_doc/ui-art-research/hud-ghv2-character-slice/evidence/hud_character_slice_2560x1440.png`

- [x] **Step 1:** 建立普通、长名称、零护盾、满值与超大数值五类状态板，明确 mock-only 字段。
- [x] **Step 2:** 自动验证所有状态板在安全画布内，内部字段不越出 226×108。
- [x] **Step 3:** 生成三档窗口截图并逐张检查文字基线、截断、填充、共同外框与等距关系。
- [x] **Step 4:** 写入结构视觉判定；实现者不自我批准最终美术。

### Task 5: Gate 3 最小素材判定、回归与独立审查

**Files:**
- Create: `dev_doc/ui-art-research/hud-ghv2-character-slice/minimum-asset-needs.md`
- Create: `dev_doc/ui-art-research/hud-ghv2-character-slice/candidate-receipt.json`

- [x] **Step 1:** 对角色面板、头像框、经验轨道、HP／护盾轨道、填充、文字和头像内容逐项应用 Gate 3 五问。
- [x] **Step 2:** 只将 Theme 无法达到正式质感且拥有唯一消费者的职责列为下一批图片候选；动态填充、数值和头像内容不得混入皮肤图片。
- [x] **Step 3:** 运行新增测试、现有 GHV-1／GHA-1 测试、两个生产回归、JSON、截图尺寸、受保护脚本与 `git diff --check`。
- [x] **Step 4:** 由独立只读审查者核对规格、运行证据和范围；修正客观缺陷后记录最终审查结论。

## Self-review

- Scope containment: 不接生产刷新链，不生成图片，不新增玩法数据，只验证角色栏显示职责。
- Data truth: 当前 production 只接通职业名、HP、HP 上限；其余字段在画廊中明确标为 mock。
- Layout truth: 角色栏固定 226×108，三个字段组和间距来自已通过布局，不把说明文字计入几何。
- Method continuity: 继续执行 Gate 0—3 的 Godot 场景先行方法，不恢复已取代的 Penpot／PNG 批量原子合同。
