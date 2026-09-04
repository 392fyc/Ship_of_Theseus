# HUD 候选基线冻结设计

**状态：** 推荐路线与书面规格均已于 2026-09-05 获用户批准。

**日期：** 2026-09-05

**Milestone：** `HUD-PROD-1` 正式战斗 HUD 渐进接入

**当前 Task：** `HUD-PROD-1A-CANDIDATE-BASELINE-FREEZE`

## 1. 阶段成果

把已经通过逐轮审核的 Godot HUD 候选冻结为一个可复现、可审查的本地 Git 基线，为后续正式战斗 HUD 的叶子组件迁移提供唯一输入。

本 Task 只收录候选、修复候选证据、建立精确文件清单并创建本地提交。它不修改正式战斗 HUD，不推送远端，不创建 PR，也不把“进入 Git 基线”解释为正式发布或随游戏分发准入。

## 2. 当前事实

- 任务工作树为 `codex/issue-18-action-resource-bar`，起始 HEAD 为 `94e10f36757ad247dec0b779cd8859c5c02e61ea`。
- 当前 HUD 候选采用 Godot 4.6.3、声明式 `.tscn`、Theme、选择性图片和运行时图层。
- `GHV-10` 已把五技能设为开发画廊默认值，并于 2026-09-05 通过用户视觉审核；显式六技能和七技能仍受测试保护。
- 正式 `BottomDashboard`、`SkillBar` 和 `ActionResourceBar` 仍使用旧实现；本 Task 不触碰它们。
- 环境恢复审计时，工作树已有 3 个跟踪修改和数百个未跟踪文件；精确数量会随本 Task 新增规格和清单而变化，不作为合同字段。不能把整个工作树当成一个候选批次，也不能使用宽泛暂存命令。
- 后续正式迁移采用“保留 `BottomDashboard` 外部契约，逐个替换叶子组件”的路线；第一个迁移对象将是 `ActionResourceStrip`，但不属于本 Task。

## 3. 权威与边界

本 Task 受以下现行合同约束：

- `AGENTS.md`：只在任务分支工作，保护既有改动，现行产物不得混入已取代内容，提交前必须独立审查。
- `.codex/project/mercury-task-contract.md`：一个 Task 只有一个主交付物、最多三项验收条件，使用精确写入范围和新鲜验证。
- `dev_doc/ui-art-research/godot-hud-asset-layer-methodology-2026-09-02.md`：场景先行、Theme 驱动、图片按职责生成、动态文字和数值不得烘焙。
- `dev_doc/ui-art-research/hud-ghv10-default-five-skills/display-contract.md`：五技能是当前默认审核状态，六／七技能是显式兼容状态。

旧 `VA-6R` 原子资产计划与旧整图生产计划已经被 GHM-1 方法取代，不得恢复为执行依据。

## 4. 基线分层

基线清单必须逐文件记录 `path`、`sha256`、`hash_mode`、`category` 和 `role`。`category` 只允许 `runtime_candidate`、`verification_support`、`contract_evidence`、`provenance_archive` 四个值。目录规则只用于生成候选集合，最终 Git 暂存只使用清单中的精确路径。

### 4.1 运行候选 `runtime_candidate`

这些文件是后续正式迁移可以直接消费的候选实现：

- `assets/fonts/ibm_plex_mono/**`
- `assets/ui/skins/hud/*.png`
- `assets/ui/themes/hud_structure_prototype.tres`
- `scenes/tactical/hud/**`
- `scripts/ui/hud/**`

字体许可证和字体来源记录与对应运行文件一起进入清单。项目 `.gitignore` 全局排除所有 `*.import` 和 `*.uid`，因此 Godot 生成的导入侧文件与脚本 UID 文件不进入清单或提交；Godot 根据源文件和场景／Theme 中的消费设置重新生成这些辅助文件。清单不得包含 `.godot/imported/**` 等机器缓存。

### 4.2 验证支架 `verification_support`

这些文件不进入正式运行时，但用于证明候选结构、状态、布局和多分辨率行为：

- `scenes/dev/hud_*.tscn`
- `scripts/ui/playground/diamond_board_stress.gd`
- `scripts/ui/playground/hud_*.gd`
- `tests/test_hud_*.gd`
- `tests/capture_hud_*.gd`

验证支架可以引用 mock 内容，但不得被正式 `TacticalScene`、正式资源加载器或 `project.godot` 消费。

### 4.3 现行合同与证据 `contract_evidence`

这些文件解释候选的来源、用户裁决、独立审查与当前适用范围：

- `dev_doc/ui-art-research/godot-hud-asset-layer-methodology-2026-09-02.md`
- `dev_doc/ui-art-research/ibm-plex-mono-godot-4-6-2026-09-03.md`
- `dev_doc/ui-art-research/penpot-hud-r1-method-reset/**`
- `dev_doc/ui-art-research/hud-gha1-neutral-surfaces/**`
- `dev_doc/ui-art-research/hud-gha2-character-surfaces/**`
- `dev_doc/ui-art-research/hud-gha3-utility-surfaces/**`，但排除 `raw/hourglass-a-gallery-1280x720.png`
- `dev_doc/ui-art-research/hud-gha4-numeric-font/**`
- `dev_doc/ui-art-research/hud-gha5-numeric-font-theme-integration/**`
- `dev_doc/ui-art-research/hud-ghv1-candidate-receipt.json`
- `dev_doc/ui-art-research/hud-ghv1-minimum-asset-needs.md`
- `dev_doc/ui-art-research/hud-ghv1-vertical-slice-evidence/**`
- `dev_doc/ui-art-research/hud-ghv2-character-slice/**`
- `dev_doc/ui-art-research/hud-ghv3-utility-slice/**`
- `dev_doc/ui-art-research/hud-ghv4-bottom-composition/**`
- `dev_doc/ui-art-research/hud-ghv5-bottom-dynamic-states/**`
- `dev_doc/ui-art-research/hud-ghv6-action-resource-segments/**`
- `dev_doc/ui-art-research/hud-ghv7-frame-safe-insets/**`
- `dev_doc/ui-art-research/hud-ghv9-typography-scale/**`
- `dev_doc/ui-art-research/hud-ghv10-default-five-skills/**`
- `docs/superpowers/plans/2026-09-02-hud-godot-vertical-slices.md`
- `docs/superpowers/plans/2026-09-03-hud-*.md`
- `docs/superpowers/plans/2026-09-04-hud-*.md`
- 本规格、后续实现计划与基线验证测试。

上述文件进入 Git 只是保存候选及其可复现证据。文件自身已有的“等待用户审核”或“候选”状态不得因本 Task 被批量改写为生产准入。

### 4.4 来源存档 `provenance_archive`

GHA-1 与 GHA-2 的现行来源记录仍引用旧材质方向图。为避免产生悬空来源，只保留它们已引用的精确方向图：

- `dev_doc/ui-art-research/hud-r1-material-sample-v1/hud-r1-material-direction-v1.png`

该图片只能在 manifest 中标记为 `provenance_archive`，其 `role` 必须明确写为“GHA-1／GHA-2 生成来源存档”。它不得成为生产素材、现行视觉候选、Godot 资源或默认阅读入口。旧目录 README 仍包含已经失效的“现行下一步”，不进入基线。

### 4.5 任务前已有修改

三个已跟踪修改都早于本 Task。即使其中部分内容与旧路线取代有关，本 Task 也不得把它们暂存或提交。它们全部按第 5 节排除并保持原样；现行路线由本规格直接引用 GHM-1，不依赖提交这些既有差异来成立。

## 5. 明确排除

以下内容不得进入本次基线清单或提交：

- `dev_doc/skillbar-design/bottom-dashboard-combined-visual-design-spec.md`
- `dev_doc/skillbar-design/hud-r1-atomic-asset-contract.json`
- `dev_doc/ui-art-research/hud-r1-material-sample-matrix.md`
- `dev_doc/ui-art-research/hud-r1-atomic-atoms-v1/**`
- `dev_doc/ui-art-research/hud-r1-component-sources-v1/**`
- 除第 4.4 节一个精确文件外的 `dev_doc/ui-art-research/hud-r1-material-sample-v1/**`
- `dev_doc/ui-art-research/penpot-hud-r1-review-v3/**`
- `dev_doc/ui-art-research/hud-ghv8-numeric-readability/**`
- `dev_doc/ui-art-research/hud-gha3-utility-surfaces/raw/hourglass-a-gallery-1280x720.png`
- `docs/superpowers/plans/2026-08-29-bottom-dashboard-combined-visual-production.md`
- `docs/superpowers/plans/2026-08-31-bottom-dashboard-atomic-asset-system.md`
- `docs/superpowers/specs/2026-08-31-bottom-dashboard-atomic-asset-architecture.md`
- `*.import`
- `*.uid`
- `.godot/**`、`__pycache__/**`、临时捕获目录和工具缓存。

这些文件不删除、不移动、不覆盖。它们保持当前工作树状态，不参与本次暂存和提交。

## 6. 受保护正式路径

以下路径相对起始 HEAD 必须保持不变：

- `project.godot`
- `scenes/tactical/TacticalScene.tscn`
- `scenes/tactical/bottom_dashboard.tscn`
- `scripts/tactical/tactical_scene.gd`
- `scripts/core/tactical_manager.gd`
- `scripts/ui/bottom_dashboard.gd`
- `scripts/ui/skill_bar.gd`
- `scripts/ui/action_resource_bar.gd`
- `scripts/units/**`
- `data/**`
- 设计库、KB 与 Mercury 仓库。

## 7. 基线清单

新增 `dev_doc/ui-art-research/hud-production-baseline-v1/manifest.json`，结构固定为：

```json
{
  "schema_version": 1,
  "baseline_id": "hud-godot-candidate-v1",
  "admission_kind": "development_candidate_baseline",
  "target_head_before": "94e10f36757ad247dec0b779cd8859c5c02e61ea",
  "production_admission": false,
  "publication": false,
  "files": [
    {
      "path": "repository/relative/path",
      "sha256": "64 lowercase hexadecimal characters",
      "hash_mode": "binary or text_lf",
      "category": "runtime_candidate",
      "role": "one concise current responsibility"
    }
  ]
}
```

`files` 按路径升序排列。清单不收录自身，避免自引用哈希。每个路径只能出现一次；不存在、重复、位于排除范围、类别非法或哈希不一致都属于验证失败。

`hash_mode=binary` 直接计算原始字节 SHA-256，适用于 PNG、TTF 等二进制文件。`hash_mode=text_lf` 在计算前把 CRLF 与单独 CR 统一为 LF，再按 UTF-8 字节计算，适用于 Markdown、JSON、GDScript、场景和 Theme 文本。这样清单不受 Windows `core.autocrlf` 或其他检出平台换行差异影响。

本规格、实现计划和基线验证测试在内容固定后进入 manifest。`manifest.json` 因自引用而不列入自身。Task 完成后的最终 Mercury 兼容回执只在提交后返回到当前会话，不作为本次单一基线提交的文件，因此能够记录真实 `candidate_head`，也不会形成“回执包含自身提交哈希”的循环。

配套测试 `tests/test_hud_production_baseline_manifest.gd` 对 `binary` 使用 `FileAccess.get_sha256()`，对 `text_lf` 使用 `HashingContext` 计算规范化 UTF-8 字节的 SHA-256。测试同时保证：

- 所有路径均为仓库相对路径，不包含盘符、反斜杠或 `..`；
- 所有路径均未被 `git check-ignore --no-index` 判定为忽略，且不得以 `.import` 或 `.uid` 结尾；
- `runtime_candidate` 不位于 `scenes/dev`、`scripts/ui/playground`、`tests` 或 `dev_doc`；
- `verification_support` 只位于 `scenes/dev`、`scripts/ui/playground` 或 `tests`；
- `contract_evidence` 只位于 `dev_doc` 或 `docs/superpowers`；
- `provenance_archive` 只允许第 4.4 节列出的精确 PNG；
- 正式受保护路径不在清单中；
- `production_admission` 与 `publication` 均为 `false`。

对于 `text_lf`，测试读取文本、规范化换行后计算 SHA-256；对于 `binary`，使用 `FileAccess.get_sha256()`。任何其他 `hash_mode` 都失败。

## 8. 证据修复

后续截图刷新改变了共享证据文件的 SHA-256。本 Task 只更新引用，不重新生成图片或改变视觉内容。

必须修复：

- GHV-4 的九张组合图哈希及默认五技能说明；
- GHV-5 的三张动态图哈希及五快捷键说明；
- GHV-6 的四张共享图哈希；
- GHV-7 的角色、组合与动态图哈希；
- GHA-5 的三张共享图哈希。

GHV-8 整体排除，不修复其历史哈希。GHA-1／GHA-2 的旧方向图引用由第 4.4 节的来源存档保留，不改写为新的视觉权威。

## 9. 提交策略

本 Task 只允许创建一个本地候选基线提交。暂存流程必须从通过验证的 manifest 读取精确路径，再额外加入 `manifest.json`。形成精确暂存候选后，独立 reviewer 先审查暂存内容；审查通过才能提交。禁止：

- `git add .`
- `git add -A`
- 按整个 `dev_doc`、`docs`、`assets`、`scenes`、`scripts` 或 `tests` 目录暂存
- stash、reset、checkout 丢弃、清理未跟踪文件
- push、PR、合并或保护分支写入。

审查者返回通过结论后，不再修改暂存内容，直接创建本地提交。提交完成后，把审查时的 index tree 与 `HEAD^{tree}` 比较，并用 `git show --name-status --stat HEAD` 复核路径集合；这一步只证明提交与已审候选字节一致，不代替提交前独立审查。被排除文件继续留在工作树不等于 Task 失败；最终会话回执必须明确它们未进入提交，并记录完整 `candidate_head`。

## 10. 验证与审查

Task 完成条件只有三项：

1. manifest 中每个文件存在、哈希正确、分类合法，且提交内容与允许集合双向一致。
2. 全部 HUD 组件、画廊和正式保护回归通过；证据文档不再引用已被当前候选覆盖的旧哈希。
3. 独立审查在提交前确认正式战斗与玩法路径未变、旧路线未被恢复、暂存候选未包含排除文件；提交后完整提交与已审候选字节一致。

验证至少包括：

- `tests/test_hud_production_baseline_manifest.gd`
- 全部 `tests/test_hud_*.gd`
- `tests/test_skillbar_v3_ui.gd`
- `tests/test_action_resource_bar.gd`
- `tests/test_action_resource_dashboard.gd`
- `tests/test_action_resource_runtime.gd`
- `tests/test_tactical_inject_smoke.gd`
- 12 张 GHV-10 组合／动态图的存在性、尺寸和 SHA-256 检查
- `git diff --check`
- 受保护路径相对起始 HEAD 的限定比较
- 独立 reviewer 对任务卡、manifest、精确暂存候选和验证输出的只读审查；提交后只执行 index tree 与完整提交的一致性核验。

## 11. 失败与回退

- manifest 验证失败时不允许暂存或提交，先修正清单或当前范围内的证据引用。
- 任何受保护路径出现差异时停止 Task；不通过自动回退命令处理。
- 发现某个候选缺少来源、许可证或当前合同引用时，将它从 manifest 移除并报告，不补造依据。
- 提交前审查失败时，只允许一轮集中修正并重新形成暂存候选；提交后字节一致性失败则停止并报告，不改写历史。

## 12. 后续入口

本 Task 通过后，`HUD-PROD-1B` 才可把 `ActionResourceStrip` 接入真实 `BottomDashboard`。后续 Task 继续保留 `BottomDashboard.update_state(Dictionary)`、`get_content_top_y()` 和六个既有信号；多行动点玩法、职业资源 HUD、装备／遗物业务逻辑及完整组合替换均需各自任务卡，不从基线冻结 Task 推导。
