# HUD 中性表面候选 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 使用 Codex 内置图像生成能力，为 `SkillSlotButton` 与 `ActionResourceStrip` 各产出并接入一个正式材质候选，验证“图片只承担中性表面、状态继续由 Theme 与运行时图层表达”的 HUD 分层方法。

**Architecture:** 两类图片素材分别拥有唯一 Godot 消费者，并通过 `StyleBoxTexture` 接入现有组件；同一技能槽中性表面由 Theme 调色形成常态、悬停、按下和禁用状态，不复制状态图片。原始候选、清理后资产、接线测试和三档实机截图分开保存，以便替换图片而不改组件接口。

**Tech Stack:** Godot 4.6.3、GDScript、Theme、StyleBoxTexture、Codex 内置 `imagegen`、透明 PNG、SceneTree 测试、PNG 实机截图。

**Spec:** `dev_doc/ui-art-research/hud-ghv1-minimum-asset-needs.md`

## Global Constraints

- 本 Milestone 只处理技能槽中性外壳和行动资源条中性外壳；不生成技能图标、武器、装备、遗物、职业资源或整张 HUD。
- 使用 Codex 内置 `imagegen`；不调用外部 API key，不购买素材。
- 两类素材必须无文字、无数字、无图标、无冷却、选择、快捷键、次数、资源余量或其他运行时状态。
- 视觉方向沿用略微精细的暗黑哥特像素质感：黑紫底、克制旧金、低装饰密度；不得退化为粗颗粒像素或高亮塑料质感。
- 技能槽必须同时适配 64×64 与 58×58；行动资源条目标显示尺寸为 274×40。
- 冷却继续使用中央整数与 50% 透明近黑暗层；生成图片不得包含冷却效果。
- 生成结果先作为候选接入；不覆盖既有素材，不替换 `BottomDashboard` 生产接线。
- 当前会话采用连续执行；用户已明确本次修订不阻塞后续任务。

## Milestone 完成条件

- 两类素材均由内置 `imagegen` 生成，生成提示与来源记录完整；
- 清理后的 PNG 具有真实透明通道，中心内容区透明，且不含文字、图标或状态；
- `SkillSlotButton` 与 `ActionResourceStrip` 均通过 `StyleBoxTexture` 使用对应候选；
- 技能槽 58×58、64×64 和行动资源条 274×40 无边角拉伸、接缝、裁切或内容区污染；
- 现有快捷键、冷却数字、次数、选择、行动点和移动数值仍由运行时节点显示；
- 1280×720、1920×1080、2560×1440 三档截图可查看，并记录结构与材质差异；
- 相关自动测试通过，三个受保护生产脚本保持不变；
- 候选回执明确未提交、未发布及仍需独立审查的风险。

---

### Task 1: 素材合同与消费测试

**Files:**
- Create: `dev_doc/ui-art-research/hud-gha1-neutral-surfaces/prompt-contract.md`
- Create: `dev_doc/ui-art-research/hud-gha1-neutral-surfaces/manifest.json`
- Create: `tests/test_hud_surface_skinning.gd`

**Interfaces:**
- Produces: 两类素材的提示词、禁止项、原始候选路径、选中候选路径、最终资产路径与唯一消费者记录。
- Produces: SceneTree 测试，验证两个 Theme 表面均为 `StyleBoxTexture`、纹理可加载、状态图层仍独立存在。

- [x] **Step 1: 写入失败的 Theme 消费测试**

测试加载 `res://assets/ui/themes/hud_structure_prototype.tres`，断言 `SkillSlotButton/styles/normal` 与 `ActionResourceStrip/styles/panel` 为 `StyleBoxTexture`，纹理路径分别指向 `res://assets/ui/skins/hud/skill_slot_surface_v1.png` 与 `res://assets/ui/skins/hud/action_resource_strip_surface_v1.png`；同时实例化两个场景，确认 `%CooldownShade`、`%CooldownTurnsLabel`、`%StandardPips` 与 `%SwiftPips` 仍存在。

- [x] **Step 2: 运行测试并确认 RED**

Run:

```powershell
& $godot --path $project --script res://tests/test_hud_surface_skinning.gd
```

Expected: exit 1，因为 Theme 仍使用 `StyleBoxFlat`，两个正式候选路径尚不存在。

- [x] **Step 3: 写入提示合同与清单骨架**

`prompt-contract.md` 必须逐项写明用途、参考图、风格、透明背景、禁止文字／图标／状态和目标显示尺寸。`manifest.json` 的每一项固定包含 `asset_id`、`consumer`、`raw_candidates`、`selected_candidate`、`final_asset`、`generation_mode`、`prompt`、`alpha_verified`、`integration_verified`。

- [x] **Step 4: 校验合同文件**

运行 `ConvertFrom-Json` 校验清单，并用语义检查确认没有整张 HUD、技能图标、武器或运行时状态进入提示。

---

### Task 2: 生成并筛选技能槽中性表面

**Files:**
- Create: `dev_doc/ui-art-research/hud-gha1-neutral-surfaces/raw/skill-slot-surface-a.png`
- Create: `dev_doc/ui-art-research/hud-gha1-neutral-surfaces/raw/skill-slot-surface-b.png`
- Create: `assets/ui/skins/hud/skill_slot_surface_v1.png`
- Modify: `dev_doc/ui-art-research/hud-gha1-neutral-surfaces/manifest.json`

**Interfaces:**
- Consumes: `SkillSlotButton` 的 58×58／64×64 显示边界及现行材质参考。
- Produces: 透明中心、四边可安全缩放的方形中性外壳候选。

- [x] **Step 1: 使用内置 `imagegen` 生成 A 候选**

生成单个独立方形技能槽外壳，透明背景与透明中心，细像素暗黑哥特质感，黑紫铁／石材主体和克制旧金边角；无文字、无图标、无宝石焦点、无状态光效、无场景背景。

- [x] **Step 2: 使用内置 `imagegen` 生成 B 候选**

保持相同职责和约束，仅将边角语言改为更简洁的锻铁薄边与微弱旧金刻线，作为低装饰密度对照。

- [x] **Step 3: 检查并机械清理候选**

检查透明通道、中心透明、四边闭合和对称性；仅执行裁切透明外边、居中与无损 PNG 保存，不生成新的装饰内容。保留两个原始候选，选中结果另存为 `skill_slot_surface_v1.png`。

- [x] **Step 4: 原生尺寸检查**

在 64×64 与 58×58 下检查边角连续、中心不污染、像素细节不过粗；失败时只针对单一问题编辑候选，不改变视觉职责。

---

### Task 3: 生成并筛选行动资源条中性表面

**Files:**
- Create: `dev_doc/ui-art-research/hud-gha1-neutral-surfaces/raw/action-resource-strip-surface-a.png`
- Create: `dev_doc/ui-art-research/hud-gha1-neutral-surfaces/raw/action-resource-strip-surface-b.png`
- Create: `assets/ui/skins/hud/action_resource_strip_surface_v1.png`
- Modify: `dev_doc/ui-art-research/hud-gha1-neutral-surfaces/manifest.json`

**Interfaces:**
- Consumes: `ActionResourceStrip` 的 274×40 显示边界及现行材质参考。
- Produces: 透明中心、长条边缘可安全缩放的中性外壳候选；不包含足迹、数值、圆点、三角或分隔柱。

- [x] **Step 1: 使用内置 `imagegen` 生成 A 候选**

生成单个独立横向细框，透明背景与透明中心，材质语言与技能槽 A 一致；端部装饰必须克制，中央长边保持可重复、可缩放。

- [x] **Step 2: 使用内置 `imagegen` 生成 B 候选**

生成与技能槽 B 一致的低装饰密度横向细框；禁止中央徽记、文字、图形、资源点和分隔柱。

- [x] **Step 3: 检查并机械清理候选**

检查透明通道、中心透明、端部闭合和上下边连续；仅裁切透明外边、居中并无损保存，选中结果另存为 `action_resource_strip_surface_v1.png`。

- [x] **Step 4: 274×40 原生尺寸检查**

确认两端不被拉扁、长边没有重复接缝、中心内容区不被装饰占用。

---

### Task 4: Theme 接入与组件回归

**Files:**
- Modify: `assets/ui/themes/hud_structure_prototype.tres`
- Modify: `tests/test_hud_surface_skinning.gd`
- Test: `tests/test_hud_skill_slot_button.gd`
- Test: `tests/test_hud_action_resource_strip.gd`
- Test: `tests/test_hud_vertical_slice_gallery.gd`

**Interfaces:**
- Consumes: 两个清理后的透明 PNG。
- Produces: 技能槽与行动资源条的 `StyleBoxTexture` Theme 接线；状态调色与运行时覆盖层保持独立。

- [x] **Step 1: 为技能槽接入共用中性表面**

将技能槽各 Button 状态切换为引用同一 `skill_slot_surface_v1.png` 的 `StyleBoxTexture`，使用 Theme 调色和覆盖反馈区分常态、悬停、按下和禁用；不得复制图片。

- [x] **Step 2: 为行动资源条接入中性表面**

将 `ActionResourceStrip/styles/panel` 切换为引用 `action_resource_strip_surface_v1.png` 的 `StyleBoxTexture`；内部足迹、数值和行动点不进入图片。

- [x] **Step 3: 运行消费测试并确认 GREEN**

运行 `test_hud_surface_skinning.gd`，预期所有素材路径、StyleBox 类型和运行时节点断言通过。

- [x] **Step 4: 运行三个组件回归**

运行技能槽、行动资源条与状态画廊测试，预期全部退出 0。

---

### Task 5: 三档截图、视觉记录与候选回执

**Files:**
- Modify: `dev_doc/ui-art-research/hud-ghv1-vertical-slice-evidence/hud_vertical_slice_1280x720.png`
- Modify: `dev_doc/ui-art-research/hud-ghv1-vertical-slice-evidence/hud_vertical_slice_1920x1080.png`
- Modify: `dev_doc/ui-art-research/hud-ghv1-vertical-slice-evidence/hud_vertical_slice_2560x1440.png`
- Create: `dev_doc/ui-art-research/hud-gha1-neutral-surfaces/visual-verdict.json`
- Create: `dev_doc/ui-art-research/hud-gha1-neutral-surfaces/candidate-receipt.json`

**Interfaces:**
- Consumes: 接入素材后的真实组件画廊。
- Produces: 三档实机证据、视觉差异、测试证据、跨仓状态与剩余风险。

- [x] **Step 1: 重新生成三档窗口截图**

运行现有 `capture_hud_vertical_slice_gallery.gd -- --capture-hud-vertical-slices`，验证 PNG 精确尺寸。

- [x] **Step 2: 检查材质与运行时图层**

检查 58×58／64×64 技能槽和 274×40 行动资源条的边缘、透明中心、冷却数字、50% 透明近黑暗层、快捷键、次数、足迹和行动点；记录可见缺陷，不自行把候选表述为用户最终批准。

- [x] **Step 3: 运行完整相关回归与静态检查**

运行 `test_hud_surface_skinning.gd`、GHV-1 三项测试及两个既有生产回归；校验两个新 JSON、`git diff --check` 和三个受保护生产脚本。

- [x] **Step 4: 写入候选回执**

回执记录生成模式为 Codex 内置 `imagegen`、四个原始候选、两个选中资产、Godot 接线证据、测试计数、截图尺寸、未提交／未发布状态与独立审查风险。

## Self-review

- Spec coverage: 两个且仅两个 Gate 3 图片职责均有生成、清理、接入、原生尺寸验证和截图任务。
- Scope containment: 技能图标、武器、装备、遗物、职业资源、生产 `BottomDashboard` 接线和玩法规则均不在范围内。
- Type consistency: 最终资产路径与消费测试、Theme 接线及清单字段完全一致。
- Placeholder scan: 所有候选名、最终路径、消费者、尺寸和禁止项均已确定；视觉候选本身是本 Milestone 的实际产物，不是未定义占位。
- Execution mode: 用户已选择当前会话内连续执行；不创建外部 API 或需要用户购买的路径。
