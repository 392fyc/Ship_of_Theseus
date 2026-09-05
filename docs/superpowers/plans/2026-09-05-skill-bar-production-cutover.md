# HUD-PROD-1D：技能栏正式接入

状态：依据现行逐组件迁移路线与用户“通过指继续任务，自律”的指令制定并执行。

## 阶段成果与交付顺序

HUD-PROD-1 的阶段成果是把已经审核的 HUD 组件逐项接入真实战斗界面。所有必要区域完成数据适配、定向验证、独立复核、本地提交和用户视觉验收后，整个阶段才完成。

行动资源条及其图标修正已完成，并通过用户验收。当前 Task 仅接入技能栏；后续继续人物与装备、遗物、结束回合区域，最后进行整体组合核验。

本 Task 的完成路径为：实现生产适配 → 定向验证和真实截图 → 独立代码与视觉复核 → 精确本地提交 → 展示实机供用户验收。收到“通过”后自动进入下一项，不再询问是否继续。

## 起点与权威

- 分支：`codex/issue-18-action-resource-bar`。
- 起始 HEAD：`762e9cb9e7d6166d7134a42d6e72c0656dc6da7b`。
- 现行方法：`dev_doc/ui-art-research/godot-hud-asset-layer-methodology-2026-09-02.md`。
- 候选布局：`scenes/tactical/hud/skill_shelf.tscn`、`scenes/tactical/hud/skill_slot_button.tscn`，以及五／六／七技能候选证据。
- 正式行为来源：`scripts/ui/skill_bar.gd`、`scripts/ui/bottom_dashboard.gd`、`scripts/core/tactical_manager.gd`、`scripts/tactical/tactical_scene.gd`。
- `AGENTS.md`：保护已有改动，不混入规则修改，提交前独立复核。
- `.codex/project/mercury-task-contract.md`：一个 M 级主交付物、精确写入范围、三项验收；允许一次集中修正。

## 实现合同

### 兼容入口与组件复用

保留 `SkillBar` 类、`skill_selected(skill_id)`、`update_entries(entries, selected_skill_id)`、`set_expanded(expanded)`；保留 `BottomDashboard` 的六个信号、`update_state(Dictionary)` 和 `get_content_top_y()`。`set_expanded` 继续只控制技能栏在玩家行动阶段的可见性。

`SkillBar` 实例化冻结的技能架场景，使用其 `SlotsCenter/Slots` 布局接入点填充真实条目，不调用仅用于五至七项候选的 `apply_skills()`。不复制旧自绘技能槽，也不叠加两套可见技能栏。

新增生产技能槽继承冻结的 `skill_slot_button.tscn` 及其脚本，继续使用原有按钮激活、冷却和选中图层。新增职责仅为费用、首字占位和限宽 tooltip；不新增通用框架或显示数据模型。

### 真实信息和输入

- 没有已确认图标来源时，保留技能名首字作为运行时占位；完整技能名称在 tooltip 中提供，图标下方不显示名称。不得生成图标或让技能成为不可辨识的空框。
- 技能槽左下显示真实行动类型（M/A/S），右下通过职业中性的显示接口接收职业资源正数值费用，只显示数字；具体职业的资源来源由上层适配，通用 HUD 不直接读取 `qi_cost`、`mark_cost` 或职业 ID；两角可同时显示。印记不显示在费用角标中。纯被动两角隐藏，职业资源为零时右下留空；tooltip保留完整说明。此约定依据用户最新反馈，只改变显示适配。
- tooltip 保留名称、说明、被动标记与不可用原因，沿用约 248 px 内容宽度和自动换行。
- `available`、选中 ID、`cooldown` 分别映射可用、选中和剩余回合数，连续刷新不得留下旧条目。
- 前四个非被动技能显示与真实输入匹配的 `1—4`；纯被动不显示伪快捷键。不得把开发画廊的 `1/2/Q/E/R` 直接带入正式输入。
- 纯被动的可用信息与不可点击分开处理，不能仅因不可点击就把内容暗成资源不足状态。没有真实主动能力或次数来源时，不新增被动主动触发能力，不显示虚构次数。
- 保留输入字典，不为显示而回写上层数据。

### 职业资源费用显示接口

已解析的技能数据可提供 `resource_cost_display: {amount, resource_name}`。`TacticalManager._build_skill_entry()` 将其归一后放入技能 entry，`SkillBar` 只消费该中性字段：右下角标显示正整数，资源名称与费用进入 tooltip。纯被动的显示字段为空。

`amount` 接受整数或有限且为整数值的浮点数，输出为整数；这兼容 Godot 的 JSON 数字解析。正费用必须同时提供非空资源名称。零、负数、类型错误、缺字段等情况归一为空。显式空对象同样表示隐藏，不能回退到其他费用来源。

只有技能数据没有声明该字段时，上层才从当前真实 `qi_cost` 构造剑气显示数据。`mark_cost`、`requires_marks` 和旧 `cost_text` 均不参与角标构造。现有印记相关说明、资源可用性检查和扣费行为保持。

此接口用于一个职业资源费用角标。其他职业可从其真实来源提供相同显示数据；本次通过明确标注的非剑气测试夹具验证接入路径，不新增其他职业玩法配置、资源容器、扣费系统或多资源组合显示规则。

费用按用户确认的最多三位数范围显示，保持现有字体、字号、描边和固定角标布局；用三位数费用验证56/64槽边界。该显示约定不在本次代码中新增玩法上限或截断。完整资源名与金额在 tooltip 中提供。

### 数量与布局

- 0—7 个真实条目时外框固定 `476×108`；0 条显示既有空提示。
- 1—6 条使用 `64×64` 方槽；7 条及以上使用 `56×56` 方槽；横向间距始终为 8 px。
- 超过 7 条时外框宽度为 `56×数量 + 8×(数量−1) + 36`，延续原栏按真实内容加宽的能力，不补假槽、不截断条目、不改变技能上限；不扩展分页或滚动交互。
- 方槽在 108 px 高度内垂直居中，保持已批准的尺寸与位置；槽下不设置名称行。
- 新尺寸交给现有 `BottomDashboard` 定位。行动资源条保持 `274×40`，与技能栏中线对齐并保持 6 px 净距；浮窗继续使用 `get_content_top_y()` 避让。

## 精确写入范围

产品代码与场景：

- 修改 `scripts/ui/skill_bar.gd`。
- 修改 `scripts/core/tactical_manager.gd` 的技能与被动 entry 显示字段及相邻归一函数。
- 新增 `scripts/ui/production/skill_slot.gd`。
- 新增 `scenes/tactical/production/skill_slot.tscn`。

验证与交付：

- 新增 `tests/test_skill_bar_production_cutover.gd`。
- 新增 `tests/capture_skill_bar_production_tactical.gd`。
- 新增 `dev_doc/ui-art-research/hud-prod-1d-skill-bar-cutover/evidence/` 中的本次原始截图、捕获元数据和独立视觉回执。
- 本计划与 `.superpowers/sdd/2026-09-05-hud-skill-bar-production-cutover/` 中的忽略工作记录。

`.uid`、`.import` 和 `.godot` 是被忽略的引擎副产物，不强制加入 Git。冻结的 `scripts/ui/hud`、`scenes/tactical/hud`、Theme、素材和基线清单保持原状；人物与装备、遗物、结束回合、技能规则和真实键位注册不在当前 Task 修改。不得夹带三个用户 dirty 文档和其他未跟踪文件。不推送、创建 PR 或合并。

## 三项验收条件

1. **生产接入和信息完整：** 真实技能仅使用一套候选按钮结构；公开合同保留，名称、费用、tooltip、冷却、选中、禁用和纯被动状态完整，输入载荷不被修改。
2. **数量、输入和布局正确：** 0、1、4、5、6、7、8 条及连续切换不丢项；鼠标和真实 `1—4` 输入指向相同技能，禁用／冷却／纯被动不会误触发；资源条几何、净距和浮窗避让保持。
3. **证据与交付完成：** 定向测试通过，真实战斗默认、选中、冷却或资源不足与 tooltip 状态的原始截图经独立复核；精确本地提交后展示用户验收。默认态补充 1920×1080、2560×1440；合成数量仅用于明确标注的测试夹具，不冒充角色配置。

## 定向验证

运行新增 `test_skill_bar_production_cutover.gd`，以及既有 `test_swordsman_skillbar.gd`、`test_skillbar_v3_ui.gd`、`test_tactical_inject_smoke.gd`、`test_action_resource_strip_production_cutover.gd`、`test_hud_skill_slot_button.gd`、`test_hud_skill_shelf.gd`。

新测试至少覆盖真实鼠标输入穿过槽按钮到 `BottomDashboard.skill_selected`、禁用与纯被动拦截、冷却和选中刷新、槽位替换、数量和显示门控、原输入字典不变。若生产适配影响其他现有公开接口，补跑命名的直接依赖；没有规则或公共框架变更时不运行全套测试。

本次比较冻结路径和清单的起点／结束 SHA256，不重写冻结清单以迎合新生产文件。捕获使用真实 `TacticalScene`，保存未经拼贴的 PNG，并记录分辨率、技能 ID、状态、技能架与资源条尺寸和净距。
