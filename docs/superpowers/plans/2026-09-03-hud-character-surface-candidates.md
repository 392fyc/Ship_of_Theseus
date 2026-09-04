# 角色栏中性表面候选 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Milestone:** `GHA-2-CHARACTER-HUD-SURFACES`

**Goal:** 使用 Codex 内置图像生成能力，为已经通过结构验证的 `CharacterHudPanel` 与 `HudPortraitFrame` 各产出并接入一个正式材质候选，同时保持名称、等级、经验、HP、护盾、头像和所有填充为独立运行时内容。

**Architecture:** 两张图片分别只承担 226×108 角色栏外壳与 72×82 头像框外壳。两者通过 `StyleBoxTexture` 接入现有 Theme；任何文字、数值、头像、轨道、填充或状态都不得进入图片。原始候选、机械清理结果、项目资产、消费测试和三档截图分层保存，以便在不修改组件接口的情况下替换材质。

**Tech Stack:** Godot 4.6.3、GDScript、Theme、StyleBoxTexture、Codex 内置 `imagegen`、透明 PNG、SceneTree 测试、PNG 实机截图。

**Spec:** `dev_doc/ui-art-research/hud-ghv2-character-slice/minimum-asset-needs.md`

## Global Constraints

- 只处理角色栏中性外壳与头像框中性外壳；不生成头像、人物原画、技能、武器、数值条图片或整张 HUD。
- 使用当前 Codex 会话的内置 `imagegen`；不调用外部 API key，不购买素材。
- 以已通过的技能槽和行动资源条中性表面为同族风格锚点：略微精细的暗黑哥特像素质感、黑紫铁／石材、克制旧金、低装饰密度。
- 所有候选必须无文字、无数字、无字母、无头像、无职业徽记、无固定轨道、无固定填充、无发光状态和无场景背景。
- 外部背景和中心内容区必须是真实透明；机械清理只能处理透明、裁切、居中、目标尺寸和安全边，不新增装饰。
- 不修改三个受保护生产 HUD 脚本，不接入生产 `BottomDashboard`，不新增 mock 字段的生产来源。
- 候选接入后仍需用户最终视觉审核；本里程碑不提交、不发布。

## Milestone 完成条件

- 两类素材均由内置 `imagegen` 生成，提示、参考、运行标识和来源记录完整；
- 每类至少保留两个原始方向候选，选择依据明确；
- 清理后的 PNG 具有真实透明通道、中心内容区透明和 1 像素透明安全边；
- 角色栏 226×108 与头像框 72×82 均通过 `StyleBoxTexture` 使用对应候选；
- 文字、数值、头像、经验／HP／护盾轨道和填充仍由现有运行时节点与 Theme 表达；
- 普通、长名称、零护盾、满值和超大数值在三档截图中无边框挤压、裁切或内容污染；
- 新增测试、GHV-2、GHV-1／GHA-1 和两个生产回归通过，三个受保护生产脚本不变；
- 独立只读审查通过，候选回执明确仍待用户视觉审核、未提交、未发布。

---

### Task 1: 素材合同与失败消费测试

**Files:**
- Create: `dev_doc/ui-art-research/hud-gha2-character-surfaces/prompt-contract.md`
- Create: `dev_doc/ui-art-research/hud-gha2-character-surfaces/manifest.json`
- Create: `tests/test_hud_character_surface_skinning.gd`

- [x] **Step 1:** 写测试断言 `CharacterHudPanel/styles/panel` 与 `HudPortraitFrame/styles/panel` 为 `StyleBoxTexture`，分别指向两个最终资产路径。
- [x] **Step 2:** 同时断言动态 Label、三个 `ProgressBar`、头像纹理接口和 fallback 层仍存在且未进入图片。
- [x] **Step 3:** 运行测试并确认因当前仍是 `StyleBoxFlat` 且目标 PNG 不存在而 RED。
- [x] **Step 4:** 写提示合同和清单骨架，逐项记录用途、参考、禁止项、目标尺寸、消费者和生成模式。

### Task 2: 生成角色栏与头像框候选

**Files:**
- Create: `dev_doc/ui-art-research/hud-gha2-character-surfaces/raw/character-panel-surface-a.png`
- Create: `dev_doc/ui-art-research/hud-gha2-character-surfaces/raw/character-panel-surface-b.png`
- Create: `dev_doc/ui-art-research/hud-gha2-character-surfaces/raw/portrait-frame-surface-a.png`
- Create: `dev_doc/ui-art-research/hud-gha2-character-surfaces/raw/portrait-frame-surface-b.png`

- [x] **Step 1:** 以当前同族素材为参考，分别生成低装饰薄框 A 与略强化角部层次 B 的 226×108 角色栏外壳候选。
- [x] **Step 2:** 以同一材质语言分别生成与角色栏 A／B 配对的 72×82 头像框候选。
- [x] **Step 3:** 逐张检查是否误生文字、头像、徽记、轨道、固定填充、粗大像素或烘焙场景背景。
- [x] **Step 4:** 只针对单一客观缺陷做编辑；保留全部原始候选并记录内置生成运行标识。

### Task 3: 机械清理与目标资产

**Files:**
- Reuse: `dev_doc/ui-art-research/hud-gha1-neutral-surfaces/clean_neutral_checkerboard.gd`
- Create: `assets/ui/skins/hud/character_panel_surface_v1.png`
- Create: `assets/ui/skins/hud/portrait_frame_surface_v1.png`
- Modify: `dev_doc/ui-art-research/hud-gha2-character-surfaces/manifest.json`

- [x] **Step 1:** 对候选执行真实透明提取、透明外边裁切和居中，不改变装饰内容。
- [x] **Step 2:** 派生 226×108 与 72×82 目标文件，并保留 1 像素透明安全边。
- [x] **Step 3:** 验证外部与中心 alpha、目标尺寸、SHA256 和候选来源。
- [x] **Step 4:** 在原生尺寸检查四角、长边、头像窗口和中心内容区；从每类选择一个候选。

### Task 4: Theme 接入与组件回归

**Files:**
- Modify: `assets/ui/themes/hud_structure_prototype.tres`
- Modify: `tests/test_hud_character_surface_skinning.gd`
- Test: `tests/test_hud_character_panel.gd`
- Test: `tests/test_hud_value_meter.gd`
- Test: `tests/test_hud_character_vertical_slice_gallery.gd`

- [x] **Step 1:** 将角色栏外壳切换为引用 `character_panel_surface_v1.png` 的 `StyleBoxTexture`。
- [x] **Step 2:** 将头像框切换为引用 `portrait_frame_surface_v1.png` 的 `StyleBoxTexture`。
- [x] **Step 3:** 设定经原生尺寸验证的纹理边距；不得用图片边距补偿组件布局。
- [x] **Step 4:** 运行消费测试与三个 GHV-2 回归并确认 GREEN。

### Task 5: 三档证据、完整回归与独立审查

**Files:**
- Modify: `dev_doc/ui-art-research/hud-ghv2-character-slice/evidence/hud_character_slice_1280x720.png`
- Modify: `dev_doc/ui-art-research/hud-ghv2-character-slice/evidence/hud_character_slice_1920x1080.png`
- Modify: `dev_doc/ui-art-research/hud-ghv2-character-slice/evidence/hud_character_slice_2560x1440.png`
- Create: `dev_doc/ui-art-research/hud-gha2-character-surfaces/visual-verdict.json`
- Create: `dev_doc/ui-art-research/hud-gha2-character-surfaces/candidate-receipt.json`

- [x] **Step 1:** 重新生成三档窗口截图，逐张检查边框挤压、透明中心、头像窗口、名称截断、六位数值和两条生存轨道。
- [x] **Step 2:** 运行新增测试、GHV-2 三项、GHV-1／GHA-1 四项与两个生产回归。
- [x] **Step 3:** 校验清单／回执 JSON、PNG 尺寸与 alpha、路径卫生、`git diff --check` 和受保护脚本。
- [x] **Step 4:** 由独立只读审查者核对生成来源、图片职责、运行证据和范围；客观缺陷修正后记录最终结论。

## Self-review

- Scope containment: 只有两个 Gate 3 已判定的外壳职责进入图片生成；动态内容与生产接线均排除。
- Atomicity: 角色栏与头像框各有唯一消费者，外壳图片不承担内部组件布局。
- Method continuity: 复用 GHA-1 已验证的同族风格、透明机械清理和运行时分层，不恢复整张 HUD 生成。
- User authority: 不购买素材；生成结果仍明确等待用户最终视觉审核。
