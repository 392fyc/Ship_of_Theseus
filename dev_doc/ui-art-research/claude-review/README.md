# Claude 全量美术、UI/UX 与素材产线审查

## 任务和权限

本次由外部 Claude 独立审查截至 2026-09-27 已有的全部美术、UI/UX 和用于生成、处理、导出、接入与验收素材的产线。用户已通过当前成果的人类审查并授权先提交合并，再进入本审查阶段。

用户明确授权 Claude 对已完成素材内容调整、删减或推翻重来，也可修订对应制作与验收流程。此前的“定版”“冻结”描述是当前基线及历史批准依据，不能限制本次视觉审查权限。需要 Codex 修改或重新生成素材时，Claude 应提供可访问的材质或式样参考、应提取的特征、替换范围、运行尺寸和验收判据。

本次阶段成果是完整的独立审查及可以直接实施的修订要求。完成条件：全部范围有结论；每个问题有实际证据和位置；产线有可复验性与已知错误拦截能力的检查；拟重做内容有参考与验收要求；直接修改另有变更清单和运行证据。不能仅列审美形容词或复述现有回执。

### 持续约束

- 基础剑士仅有剑气，没有印记系统。剑圣具有剑气和心、道、势印记；回忆天赋仍在设计中，不能补写其未定版技能机制。
- 地图只支持正方形，边长 10—25；已有地形相邻效果应可复用，编辑与正式试战保持一致。不合场景逻辑的组合可以按现行目录拒绝。
- 审查视觉或信息表达时可以重做风格、构图、图标、头像、边框、环境和产线；涉及玩法数值、技能含义、地形规则时先读取设计库，不从图像推导新玩法。
- 主仓有用户改动，实施应使用核对过的独立任务树。读项目 `AGENTS.md`、`CLAUDE.md`，跨仓先解析 roots 并读取目标合同；不要覆盖主仓、设计库、KB 或 Mercury 的既有改动。
- 审查意见、实现验证、用户验收分别记录。新的美术成果需要真实引擎证据；以往自动测试通过不证明审美正确。

## 建议审查顺序

1. 核对交接中的 Git 版本和当前场景，读取下列来源清单，直接查看现行原画、实机整屏及实际尺寸。
2. 通览整体视觉语言、角色与环境的风格关系、信息层级和操作反馈，再逐项检查图标语义、字体、头像、地形接壤及动态遮挡。
3. 从原始输入到 Godot 输出逐段追踪产线，区分生成、裁切、透明边界、导入、布局、着色与采集责任。
4. 用同一检查检查正确样例和旧错误反例，验证问题能否被拒绝。核对整屏与细节来自同一帧。
5. 输出审查报告和按优先级排列的实施任务；需要重做的项附参考。可在独立任务树直接改动用户授权范围，记录改动和验证。

## 现行资产与界面索引

所有路径均相对游戏仓根。某个目录包含多个候选时，优先沿当前资源引用和来源清单定位，不能只选文件名最大的版本。

| 范围 | 当前运行入口、素材或配置 | 证据和来源 |
| --- | --- | --- |
| 正式战斗整体、五区布局、角色/装备/技能/遗物/结束行动 | `scenes/tactical/TacticalScene.tscn`；`scenes/tactical/hud/m2/bottom_hud_composition.tscn`；`scripts/ui/hud/m2/runtime_dashboard.gd`；`assets/ui/themes/hud_m2.tres` | `dev_doc/ui-art-research/hud-final-acceptance/README.md` 及 `evidence/`；最新基础剑士头像与沙漏见下方专项目录 |
| HUD 材质、边框和行动资源 | `assets/ui/skins/hud_m2_fe/`；`scripts/ui/hud/m2/action_resource_glyph.gd` | 该素材目录的 `material-manifest.json`；`hud-final-acceptance/evidence/capture-manifest.json` 中常态、混合消耗、全消耗及悬停状态 |
| 剑气槽、32 像素数字与阈值状态 | `assets/ui/skins/hud_freeze/`；`scripts/ui/hud/m2/sword_resource_panel.gd`；`assets/ui/layouts/hud_m2_class_resource.tres`；`assets/ui/catalogs/hud_m2_class_resource_profiles.json` | `hud_freeze/source-manifest.json`；`dev_doc/ui-art-research/hud-freeze-godot/`；正式整屏见前两行 |
| 剑圣心、道、势纹章、空心及持有态 | `assets/ui/skins/hud_mark_crest/`；`scripts/ui/hud/m2/marks_panel.gd`；`assets/ui/shaders/hud_mark_hollow.gdshader` | `hud_mark_crest/source-manifest.json`；52 像素高纹章已包含放大约 20% 的版本；缺图时回退到 `hud_freeze/marks-000…111.png` |
| 属性悬浮卡与头像框 | `scripts/ui/hud/m2/` 中角色面板与属性卡；正式 M2 组合 | `dev_doc/ui-art-research/hud-character-panel-portrait/`；属性卡在头像悬停或聚焦时显示，位于人物栏上方并避开剑气槽 |
| 剑圣头像 | `assets/ui/portraits/kensei_hud_portrait_generated.png` 与 `kensei_hud_portrait.tres` | `assets/ui/portraits/source-manifest.json`；`hud-character-panel-portrait/generation-prompt.md`；当前为重新生成版，旧裁切候选在 `candidate/` |
| 基础剑士头像及对称沙漏 | `assets/ui/portraits/myrmidon_hud_portrait_generated.png` 与 `myrmidon_hud_portrait.tres`；当前 HUD 结束行动按钮 | `assets/ui/portraits/myrmidon-source-manifest.json`；`dev_doc/ui-art-research/hud-myrmidon-portrait/generation-prompt.md`、`candidate/README.md`；当前发布证据也见 `hud-release-build/evidence/myrmidon-package-1280.png` |
| 基础剑士五枚技能图标 | `assets/ui/skills/myrmidon/{xinyan,zhanji,yishan,zhaojia,juhe}.png`；`assets/ui/catalogs/hud_m2_skill_icons.json` 的 myrmidon 项 | `dev_doc/ui-art-research/myrmidon-skill-icons/source-manifest.json`；同目录 `build_icons.gd`、`capture_candidate.gd`、`export-audit.md`、`export-audit.json`。104×104 素材在栏中按 52×52 显示 |
| 角色原画与整体风格参考 | `assets/prototype/visual_style/samples/portrait_preview_final.png`；同目录 UI、地图棋子、地形和 VFX 样例 | `assets/prototype/visual_style/README.md`、`sample_manifest.json`。参考原画与当前运行头像有不同职责 |
| 剑圣地图棋子 | `assets/units/kensei/map_token_clean_v2.png`；`data/visual_profiles/kensei_map_token.json`；`data/classes/kensei.json`；`scripts/units/map_token_view.gd` | `tests/test_kensei_map_token_asset.gd`；`tests/capture_kensei_map_token_tactical.gd`。4×2 图集按朝向和单双武器切换；当前为静态棋子帧 |
| 单位运动和占位动画 | `scenes/tactical/Unit.tscn`；`scripts/units/unit.gd` | 位置移动使用 tween；AnimatedSprite2D 各状态仍使用 PlaceholderTexture2D，不能称为已制作角色动画 |
| 字体与中文排版 | `assets/fonts/source_sans_pro/`；`assets/fonts/ibm_plex_mono/`；`assets/ui/themes/hud_m2_fonts.tres`；`scripts/ui/hud/m2/hud_font_setup.gd` | 字体目录中的 `source.json` 和许可证；普通文字允许系统 fallback，中文外观尚未完全固定 |
| 九类地形与可复用接壤 | `assets/prototype/battlefield_courtyard/terrain_catalog.json`；`scripts/ui/terrain/terrain_catalog.gd`、`terrain_surface.gd`、`terrain_blend.gdshader` | `visual-review/terrain-kit.md`；`terrain-kit-approved.json`；32 种合法异类组合、四种含对角的排除组合 |
| 水域、地表、入口、树木、残垣、墙柱山峰 | `assets/prototype/battlefield_courtyard/visual_profile.json`、`source-manifest.json`、`terrain-kit-sources.json`；当前 PNG；`scripts/ui/playground/courtyard_board_view.gd` | 同素材目录的 `water-depth-approved.json`；`visual-review/reviews/2026-09-27/terrain-kit-v1/`、`water-depth-v6/`；来源清单的 active 状态需与代码实际引用共同核对 |
| 整体包裹的庭院环境与三场景 | `scenes/playground/battlefield_courtyard.tscn`；`scripts/ui/playground/battlefield_courtyard.gd`；`courtyard_layouts.json` | `visual-review/reviews/2026-09-27/terrain-map-size-v1/` 中整屏证据，部分图片经 archive-manifest 引用此前同摘要文件 |
| 地形创作工作台、地图尺寸、正式试战与返回 | `scenes/playground/terrain_painter.tscn`；`scripts/ui/playground/terrain_painter.gd`；`scripts/tactical/terrain_battle_session.gd`；`scripts/ui/terrain/terrain_battle_definition.gd`；`data/battlefields/terrain_workshop_test.json` | `visual-review/terrain-runtime-integration.md`、`terrain-map-size.md`；`reviews/2026-09-27/terrain-map-size-v1/`。当前示例在 `terrain_examples.json`，10—25 边长编辑图和战斗图覆盖两种分辨率 |

上述 `visual-review/` 和 `hud-*` 简写目录均位于 `dev_doc/ui-art-research/`。

### 非战斗界面、样例与尚未制作的部分

| 范围 | 实际位置 | 当前身份与审查边界 |
| --- | --- | --- |
| 门选、奖励与事件提示 | `scenes/roguelite/DoorSelect.tscn`；`scripts/roguelite/door_select.gd` | 可运行的 v0 文字和按钮界面；奖励使用 emoji，可审查理解顺序与状态表达，尚无完整美术皮肤 |
| 准备、运输队、装备交换、商店、事件选项与结果 | `scripts/roguelite/run_scene.gd`；`scripts/roguelite/run_manager.gd` | 动态建立的文字、按钮和列表界面；装备效果仍有占位逻辑。检查入口为 `tests/test_run_scene_ui.gd`、`test_event_resolver.gd`、`test_run_scene_flow.gd` |
| 风格样例画廊、VFX 参考 | `scenes/playground/visual_style_playground.tscn`；`scripts/ui/playground/visual_style_playground.gd`；`assets/prototype/visual_style/sample_manifest.json` | 五类参考；VFX 为 `samples/vfx_preview_clean.png` 单张审查图，未发现生产 VFX 图集或动画库 |
| 历史 UI 探索 | `scenes/playground/dashboard_variant_a.tscn`、`dashboard_variant_b.tscn`、`dashboard_variant_c.tscn`、`playground_battle_ui.tscn`；`scenes/dev/skillbar_playground.tscn` | 可用于追查设计取舍，不是当前正式 M2 场景 |

尚未找到标题主菜单、城镇、招募、独立背包、天赋选择或技能升级的专用场景；当前主场景直接进入战斗。它们标记为未实施范围，不要把缺失画面当成已有成果来审批，也不要为完成此次现有成果审查而自动扩展制作这些界面。

## 产线检查清单

| 环节 | 可定位入口 | 独立审查重点 |
| --- | --- | --- |
| 视觉方向与参考 | `assets/prototype/visual_style/`，各项 source-manifest，头像 generation-prompt | 参考是否对应当前角色、材质和使用尺度；是否能约束色域、笔触、光照、形体与细节密度 |
| 图像生成 | 头像、印记、技能及地形的来源清单和生成提示 | 单次生成职责、参考摘要、透明边缘、重复性、烘焙光影；保存的结果可复用，未记录可核实模型版本或种子，不能逐次精确重放生成 |
| 裁切、清理和派生 | 头像 `.tres` 裁切；技能 `build_icons.gd`；地图棋子母图及正式图 | 头像四边贴合、脸部结构、实际尺寸语义；技能缩放后是否仍能区分；棋子 alpha 清理目前缺少仓内可重放脚本 |
| 设计画布与材质导出 | Penpot 归档、`verify.py`、`verify-cloud.js`，HUD 材质清单 | 云端与本地以及后续 Godot 改动是否一致；素材导出 revision 189 与整体画布 revision 215 的关系需核对 |
| Godot 导入和运行组成 | `.png.import`、主题、AtlasTexture、布局资源、渲染脚本与 shader | 过滤、裁切、透明、缩放、状态共用、实际引用；不能把已有 PNG 等同于运行中已接入 |
| 素材入库与相邻关系 | `tests/capture_courtyard_material_intake.gd`；地形 catalog、visual_profile、blend shader | 单张、3×3 重复、实际尺度；相邻两类、转角、交会、窄道、端头、连续水深、场内外延伸；不得用亮线掩盖硬接缝 |
| 交互与动态 | HUD 捕获、地形工作台与 battle_flow 测试、`tests/capture_battlefield_environment_motion.gd` | 悬停不换框、状态反馈、可达性、缩放拖动、遮挡淡化与恢复、编辑往返；静态图不能证明动态正确 |
| 固定采集与错误拒绝 | `visual-review/README.md`；water-visual-contract.json、water-depth-continuity-contract.json；`tests/run_courtyard_visual_validation.ps1` | 正例和旧错例是否用同一判据；是否实际看图；规则是否只检查实现自己定义的结果；已知错误包括水岸高亮、中心突然变浅、河岸错位、墙体无空间依据 |
| 整体回归与发布 | `tests/run_terrain_kit_validation.ps1`、`tests/run_terrain_runtime_validation.ps1`；`scripts/codex/verify-myrmidon-export.ps1`、`build-windows-release.ps1`；`release/windows-export-preset.cfg.in` | 原生图与整屏一致、两种分辨率、资源真正在包内且被运行场景引用；历史包不能证明当前提交 |

### 可运行的主要入口

使用 Godot 4.6.3，代码实际以 `gl_compatibility` 采集。启动 `scenes/playground/terrain_painter.tscn` 可编辑地图并试战；`scenes/playground/battlefield_courtyard.tscn` 查看庭院环境；`scenes/tactical/TacticalScene.tscn` 查看默认战斗。先导入项目再运行脚本。

```powershell
& $GodotPath --headless --path $ProjectPath --editor --recovery-mode --import --quit
& $GodotPath --path $ProjectPath --rendering-method gl_compatibility res://scenes/playground/terrain_painter.tscn
& "$ProjectPath/tests/run_terrain_runtime_validation.ps1" -GodotPath $GodotPath -OutputDirectory $NewExternalOutput
```

脚本要求新的仓库外输出目录。完整地形验证先核对当前批准来源；若 Claude 有意重做视觉，应保留旧批准记录，创建新的审查批次与批准依据，并修订对应测试预期。不能为了让旧测试通过而偷偷替换摘要或停用错误判据。

自动导入使用 Godot 已提供的恢复模式，避免已有编辑器与新副本的 MCP 插件争用本机连接。常规第二次导入曾触发插件连接占用和该插件的错误日志接口问题；该项属于编辑器插件环境，未修改插件或用户正在运行的编辑器。恢复模式导入和普通游戏运行分别验证，不能据此声明 MCP 插件问题已修复。

HUD 重采：`tests/capture_hud_final_acceptance.gd`。棋子重采：`tests/capture_kensei_map_token_tactical.gd`。专项脚本的参数及输出以文件头和相邻 README 为准；采集输出的 `user://` 路径不是仓库文件。

## 当前证据与历史资料的界线

- 最后尺寸与正式试战统一批次是 `visual-review/reviews/2026-09-27/terrain-map-size-v1/`；读取 `archive-manifest.json` 的 `stored_as` 定位原图。5 张地图尺寸图在该目录的 `map-size/` 中。
- 发布前新检出复验在 `visual-review/reviews/2026-09-27/release-clean-checkout/`：46 项来源和 85 项原证据核对通过，首次导入及完整五阶段运行通过。`verification-summary.json` 同时记录一次自动点击失败及测试派发调整；自动交互验证使用合成事件，不能宣称物理设备验收。
- `terrain-kit-v1` 是地形外观批准批次；`water-depth-v6` 是连续水深的批准依据。历史失败样例应作为反例检查流程，不作为当前截图。
- `candidate-receipt.json` 和旧来源中的未发布、未批准状态是其生成时记录。当前集成身份看 `visual-review/release-2026-09-27.md` 和 GitHub 合并记录。
- `assets/ui/skins/hud/`、`hud_structure_prototype.tres`、早期 HTML 布局及 moodboard 属于旧原型；当前 M2 引用 `hud_m2_fe`。
- `assets/prototype/hud_m2/skill-*.png` 仍被剑圣默认图标目录使用，来源记录为 `development_placeholder`，分发权未核实。它们在审查范围内，不能称为正式批准图标。
- `dev_doc/ui-art-research/hud-release-build/` 的 Windows 包证据来自过去的 HUD 提交，未包含当前地形工作台；本次应运行合并后的源码。
- 原型 README 中关于“棋子尚未接入 Unit”的早期描述与当前正式剑圣引用不一致，当前运行事实以 `data/classes/kensei.json`、视觉配置和 Unit 代码为准。

## Penpot 外部对象

| 项 | 已知身份和状态 |
| --- | --- |
| 服务、文件 | `https://design.penpot.app`；`New File 1`；`c828d3cf-7d4e-8145-8008-8f0919f9073c` |
| 页面 | `HUD R1 · 基础 UI 材质与布局修订`；`8086b853-2801-807d-8008-985af17836c7` |
| 主画板 | `SPLIT-PIXEL-R1 · 左剑右素材印记 · 65 · 111`；`8086b853-2801-807d-8008-9cc915f221e9`；页面坐标 `[0,38900,1280,720]` |
| 纹章状态板 | `7537319b-8c1a-8048-8008-a08a60c059ca`；本轮未单独实时核验 |
| 历史版本 | 2026-09-24 revision 215，命名版本“ SoT HUD 定版 2026-09-24 · 左剑右印记”；不把此修订号当作实时当前版本 |
| 本轮读取 | 2026-09-27 23:26（Asia/Tokyo），Penpot MCP 只读返回上述文件、页面、主板身份与几何一致；未重导完整画布、未检查实时版本或全部子节点 |
| 本地完整依据 | `dev_doc/ui-art-research/penpot/2026-09-24-hud/{manifest.json,README.md,verify.py,verify-cloud.js,evidence/,previews/,source/}`；主要画布为 `previews/main-native.png` |

画布以 1280×720 为基准，局部坐标为主板左上角原点：人物 `[32,596,226,108]`、装备 `[266,596,128,108]`、技能 `[402,596,476,108]`、遗物 `[886,596,278,108]`、结束行动 `[1172,596,76,108]`；行动资源 `[503,550,274,40]`、横剑 `[32,520,366,56]`、剑圣纹章 `[886,520,278,56]`。它们是现行参考值，允许本次审查重设。

Godot 在画布定版后新增或调整了头像、图标、纹章大小、行动条和沙漏，不能假定云端与当前 Godot 完全同步。Claude 接手时重新核对连接和目标身份；连接不可用时可以继续本地审查，云端修改则等待恢复。不要把当前活动页自动当成目标。

## Claude 交回的内容

1. **审查总表**：每类标记保留、修改、删除、重做或证据不足；写清问题、截图与区域、素材路径、对应运行脚本，以及对玩家理解或操作的影响。
2. **修改任务单**：优先级、准确替换范围、可保留项、参考图或官方/作者来源链接、应提取的形状/材质/光照特征、实际显示尺寸、透明和重复要求、禁止特征、验收状态和复验入口。每项使 Codex 能直接执行。
3. **产线改进表**：现有错误发生在哪一段、现有检查为何放过、要改变什么、用哪个已知错例证明新检查有效、仍需人判断什么。
4. **直接修改回执**：若已修改，列文件、原因、来源与许可、运行证据、残余问题，独立任务分支与提交；不能只交替换后的单张图片。

报告可保存为本目录下的 `claude-review-report.md`；给 Codex 的实施单可用 `claude-change-requests.md`。审查未发生之前不得预先填写通过结论。
