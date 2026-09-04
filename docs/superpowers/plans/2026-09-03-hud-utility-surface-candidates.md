# 实用 HUD 专用原子素材候选 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Milestone:** `GHA-3-UTILITY-HUD-SURFACES`

**Goal:** 使用当前 Codex 会话的内置图像生成能力，为 GHV-3 Gate 3 唯一保留的 32×32 血瓶按钮外壳、44×44 结束操作菱形框和 18×24 沙漏图形各产出并接入一个正式候选，不重新生成已经安全复用的面板／通用槽，也不生成任何内容图标。

**Architecture:** 三张图片各有一个原子职责。血瓶外壳通过 `StyleBoxTexture` 接入 `HudPotionButton32`；菱形框与沙漏作为 `EndTurnButton` 内两个独立 `TextureRect` 层接入，父 Button 统一承担可用、悬停、按下和禁用反馈。原始候选、机械清理文件、正式资产、消费测试和三档实机截图分开保存。

**Tech Stack:** Godot 4.6.3、GDScript、Button／TextureRect、Theme／StyleBoxTexture、Codex 内置 `imagegen`、透明 PNG、SceneTree 测试、PNG 实机截图。

**Spec:** `dev_doc/ui-art-research/hud-ghv3-utility-slice/minimum-asset-needs.md`

## Global Constraints

- 只处理三个 Gate 3 原子职责；不得生成武器、防具、血瓶内容、遗物内容、技能、职业资源或整段 HUD。
- 使用 Codex 内置 `imagegen`，每个候选单独调用；不使用外部 API key，不购买素材。
- 每类至少保留 A／B 两个原始候选，共至少六次首轮生成；运行标识和提示完整记录。
- 统一沿用已验收同族素材的略微精细暗黑哥特像素质感、黑紫金属／深色石材、克制旧金和低装饰密度。
- 三类最终 PNG 都需要真实透明背景和完整 1px 透明安全边；血瓶壳与菱形框中心必须透明。
- 血瓶壳不得包含瓶子、液体、次数、冷却、治疗量或文字；菱形框不得包含沙漏；沙漏不得包含菱形框。
- 结束按钮点击区保持 52×52，菱形框 44×44、沙漏 18×24，二者各边至少保留 5px 视觉空隙。
- 不修改受保护生产 HUD、TacticalManager、TacticalScene、RunState、RunManager 或玩法 JSON，不接入装备／血瓶／遗物生产数据。
- 候选需经独立只读审查，仍须用户最终视觉审核；本里程碑不提交、不发布。

## Milestone 完成条件

- 三类素材各有至少两个原始候选、内置生成运行标识、选择理由和可追溯来源；
- 三个选中资产满足目标尺寸、真实透明、安全边、职责纯度和原生尺寸可读性；
- 血瓶外壳通过一个中性图片和 Theme 调制覆盖常态、悬停、按下及禁用，不复制状态图片；
- 菱形框和沙漏分别由独立 `TextureRect` 消费，不合并整张结束按钮图片；
- 52×52 点击区、44×44 菱形、18×24 沙漏及至少 5px 四边空隙保持不变；
- 运行时图标接口、tooltip、按钮语义、双信号和禁用／隐藏行为保持通过；
- 1280×720、1920×1080、2560×1440 三档截图无裁切、混叠、过粗像素或职责污染；
- GHV-3、既有 HUD、生产回归和 `test_prep_flow.gd` 通过，8／6 边界与保护脚本不变；
- 独立审查通过，回执记录未提交、未发布和仍待用户视觉审核。

---

### Task 1: 提示合同、清单与失败消费测试

**Files:**
- Create: `dev_doc/ui-art-research/hud-gha3-utility-surfaces/prompt-contract.md`
- Create: `dev_doc/ui-art-research/hud-gha3-utility-surfaces/manifest.json`
- Create: `tests/test_hud_utility_surface_skinning.gd`

- [x] **Step 1:** 写失败测试，断言血瓶 Theme 使用目标 `StyleBoxTexture`，菱形与沙漏分别由指向目标 PNG 的 `TextureRect` 消费。
- [x] **Step 2:** 同时保护血瓶运行时内容接口、52×52 点击区、两层固定尺寸与空隙、结束双信号以及无烘焙文字。
- [x] **Step 3:** 运行测试并确认因三个目标 PNG 与接线尚不存在而 RED。
- [x] **Step 4:** 写清单骨架，固定六个原始候选、三个消费者、目标尺寸、禁止项、生成模式和运行标识字段。

### Task 2: 生成六个原始候选

**Files:**
- Create: `dev_doc/ui-art-research/hud-gha3-utility-surfaces/raw/potion-button-shell-a.png`
- Create: `dev_doc/ui-art-research/hud-gha3-utility-surfaces/raw/potion-button-shell-b.png`
- Create: `dev_doc/ui-art-research/hud-gha3-utility-surfaces/raw/end-action-diamond-frame-a.png`
- Create: `dev_doc/ui-art-research/hud-gha3-utility-surfaces/raw/end-action-diamond-frame-b.png`
- Create: `dev_doc/ui-art-research/hud-gha3-utility-surfaces/raw/end-action-hourglass-emblem-a.png`
- Create: `dev_doc/ui-art-research/hud-gha3-utility-surfaces/raw/end-action-hourglass-emblem-b.png`

- [x] **Step 1:** 使用内置 `imagegen` 单独生成血瓶壳 A／B，只改变边角装饰密度。
- [x] **Step 2:** 单独生成菱形框 A／B，只改变锻铁与旧金层次，不生成沙漏。
- [x] **Step 3:** 单独生成沙漏 A／B，只改变轮廓简洁度，不生成外框。
- [x] **Step 4:** 逐张检查文字、内容图标、合并职责、背景、粗大像素和状态污染；必要编辑每次只修一个客观缺陷。

### Task 3: 机械清理与三个目标资产

**Files:**
- Reuse: `dev_doc/ui-art-research/hud-gha1-neutral-surfaces/clean_neutral_checkerboard.gd`
- Create: `assets/ui/skins/hud/potion_button_shell_v1.png`
- Create: `assets/ui/skins/hud/end_action_diamond_frame_v1.png`
- Create: `assets/ui/skins/hud/end_action_hourglass_emblem_v1.png`
- Modify: `dev_doc/ui-art-research/hud-gha3-utility-surfaces/manifest.json`

- [x] **Step 1:** 只执行透明提取、裁切、居中、目标尺寸派生和 1px 安全边，不新增装饰。
- [x] **Step 2:** 验证目标尺寸、外部 alpha、必要中心 alpha、可见边框／图形和 SHA256。
- [x] **Step 3:** 在 32×32、44×44 与 18×24 原生尺寸比较 A／B，按职责纯度和可读性选择。
- [x] **Step 4:** 验证菱形边缘不会接触 52×52 点击区，沙漏不会接触 44×44 菱形边缘。

### Task 4: Theme／场景接入与组件回归

**Files:**
- Modify: `assets/ui/themes/hud_structure_prototype.tres`
- Modify: `scenes/tactical/hud/end_turn_button.tscn`
- Delete if no longer consumed: `scripts/ui/hud/end_turn_frame.gd`
- Delete if no longer consumed: `scripts/ui/hud/end_turn_emblem.gd`
- Test: `tests/test_hud_utility_surface_skinning.gd`
- Test: `tests/test_hud_slot_button.gd`
- Test: `tests/test_hud_end_turn_control.gd`

- [x] **Step 1:** 将血瓶常态、悬停、按下和禁用切换为同一血瓶壳的 `StyleBoxTexture` 与 Theme 调制。
- [x] **Step 2:** 将菱形框和沙漏改为两个独立 `TextureRect`，保持原节点名、位置、尺寸和鼠标穿透。
- [x] **Step 3:** 移除不再被消费的占位绘制脚本，避免图片与自绘重叠；不得改动信号语义。
- [x] **Step 4:** 运行消费测试、血瓶／通用槽、结束按钮和 GHV-3 画廊回归。

### Task 5: 三档证据、完整回归与独立审查

**Files:**
- Modify: `dev_doc/ui-art-research/hud-ghv3-utility-slice/evidence/hud_utility_slice_1280x720.png`
- Modify: `dev_doc/ui-art-research/hud-ghv3-utility-slice/evidence/hud_utility_slice_1920x1080.png`
- Modify: `dev_doc/ui-art-research/hud-ghv3-utility-slice/evidence/hud_utility_slice_2560x1440.png`
- Create: `dev_doc/ui-art-research/hud-gha3-utility-surfaces/visual-verdict.json`
- Create: `dev_doc/ui-art-research/hud-gha3-utility-surfaces/candidate-receipt.json`

- [x] **Step 1:** 重新生成三档窗口截图，检查三个原子素材、禁用灰化、边缘空隙和原生尺寸可读性。
- [x] **Step 2:** 运行新增测试、GHV-3、GHV-2、GHV-1／既有素材测试、生产回归与 `test_prep_flow.gd`。
- [x] **Step 3:** 校验清单／回执 JSON、PNG 尺寸／alpha／哈希、路径卫生、`git diff --check` 和保护脚本。
- [x] **Step 4:** 由独立只读审查者核对六次内置生成来源、原子职责、运行证据、8／6 边界和范围；审查结论为 PASS，完整度 1.0，无阻断项。

## Self-review

- Scope containment: 只有 Gate 3 明确保留的三个原子职责进入生成，已安全复用的面板与通用槽不重复生成。
- Atomicity: 血瓶壳、菱形框、沙漏各有唯一消费者；结束按钮不合并为整图。
- Runtime separation: 血瓶内容、按钮状态、tooltip、结束语义和信号继续由运行时节点表达。
- User authority: 不购买素材、不使用外部 API key；候选仍需用户最终视觉审核。
