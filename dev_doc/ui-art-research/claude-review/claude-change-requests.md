# Claude 审查实施单（交 Codex 执行）

- 来源：[claude-review-report.md](claude-review-report.md)（发现 V-xx、产线 P-xx、裁决 D-x）
- 基准：`develop@1fdac59db52ebdade335a106732d2dde84234cbf`
- 证据：`evidence-2026-09-28/`（eNN，SHA256 见 `evidence-manifest.json`）
- 工具：
  - `tests/claude_review/claude_review_checks.py`（C1–C8，C6 未实现）
  - `capture_scene_native.gd`
  - `capture_run_flow_ui.gd`
  - `capture_battle_overlays.gd`
  - `sampling_sim.py`

## 通用约束（所有实施单都适用）

1. **不覆盖原字节。** 已批准文件保持原字节；派生文件另存，并记录父文件 SHA256、处理参数、输出 SHA256、像素尺寸、显示尺寸、过滤方式和用途。
2. **改动批准来源要走新批次。** 如果改动会让 `terrain-kit-approved.json`、`water-depth-approved.json`、HUD 批准记录或既有批次 protected-state 中的摘要失效，就建立新的审查批次和批准依据，旧记录保留历史身份。不得为了让旧测试通过而替换摘要或停用错误判据。
3. **新生成素材先放仓库外。** 用户逐个确认前，新生成素材只存放在仓库外的预览位置（KB 视觉裁决）。
4. **视觉证据必须来自真实配置。** 保留 `project.godot` 的拉伸设置，并使用与发行一致的渲染器（CR-02、D-5）；覆盖 1280×720、1920×1080、2560×1440 三档；局部图须能在同帧整屏中找回（C5），并记录源帧 SHA、区域与倍数。
5. **边界不变。** 基础剑士只有剑气、没有印记；不补写剑圣回忆技能；地图只能是正方形、边长 10–25；地形或技能规则的改动先读设计库。
6. **分开记录。** 实现者不自我批准，独立审查与用户视觉验收分别记录。

## 优先级与建议顺序

| 优先级 | 实施单 |
| --- | --- |
| P0 | CR-01 显示尺寸母版与 mipmap；CR-02 采集配置与发行一致 |
| P1 | CR-03 网格线；CR-04 试战外围；CR-05 大地图初始视角；CR-06 单位棋子与名牌；CR-07 基础剑士图标；CR-08 纹章显示；CR-09 行动顺序面板；CR-10 中文字体；CR-11 默认战斗地形渲染；CR-12 非战斗界面文本；CR-13 剑圣占位图标 |
| P2 | CR-14 行动资源图形；CR-15 不可用态；CR-16 被动槽；CR-17 HUD 框体高分辨率母版；CR-18 人物栏文字；CR-19 调试提示隔离；CR-20 石柱；CR-21 无网格态边界；CR-22 选门去 emoji；CR-23 三档分辨率；CR-24 头像贴合；CR-25 同帧记录；CR-26 Penpot 同步；CR-31 提示词风格条款；CR-34 最小动画反馈（仅登记）；CR-35 剑气流线与阈值色；CR-39 范围高亮配色与单次绘制；CR-40 伤害预测浮窗样式 |
| P3 | CR-27 水面外观；CR-28 工作台易用性；CR-29 证据目录 `.gdignore`；CR-30 旧素材与历史场景归档；CR-32 结束控件阶段提示；CR-33 装备空槽提示；CR-37 纹章回退图；CR-38 画廊显示现行棋子 |
| 已撤销 | CR-36（前提错误，见报告 V-42 与 §8.2） |

建议顺序：

1. 先做 CR-02 与 CR-23，让后续证据可信（其中渲染器一项需要 D-5）。
2. 再做 CR-01、CR-03、CR-06、CR-07。
3. 待用户裁决的 D-1 至 D-5 不阻断其余工作。

---

## CR-01 显示尺寸母版与 mipmap（P0，产线）

- **对应**：V-07、V-10、V-20、V-28、P-01、P-15

- **现象与影响**：大倍率缩小且没有 mipmap，金边、细线和枝叶高光碎成散点，镜头缩放和移动时闪烁（e08、e13、e15、e27）。

- **出错环节**：导入与运行组成。

- **为何放过**：没有任何检查比较"显示尺寸 / 源尺寸"。导入设置大多被 `.gitignore:3` 忽略，批准校验只覆盖庭院目录，而发行构建用 `git archive` 暂存，所以本机改动不会进入发布。

- **准确位置**：

| 素材 | 使用处 | 导入文件跟踪 | 缩小倍数（720p） |
| --- | --- | --- | --- |
| 棋子 `assets/units/kensei/map_token_clean_v2.png` | `scripts/units/map_token_view.gd:31`（LINEAR） | 否 | 默认战斗 0.156；同规格用于 25×25 试战时 0.065 |
| 纹章图集 `assets/ui/skins/hud_mark_crest/marks-filled-generated.png` | `scripts/ui/hud/m2/marks_panel.gd:7-16`（继承 Linear） | 否 | 0.089 |
| 头像 `assets/ui/portraits/*_generated.png` | `scenes/tactical/hud/m2/character_hud_panel.tscn:55`（`texture_filter = 2`） | 否 | 0.106 |
| 树、灌木、碎石、入口 `assets/prototype/battlefield_courtyard/{forest-tree-v2,shrub-v1,low-rubble-v1,courtyard-entry-v2}.png` | `scripts/ui/playground/courtyard_board_view.gd:658`（道具根节点 NEAREST） | 是 | 树：试战 0.061、庭院 0.175；碎石：试战 0.024；入口：庭院 0.157 |
| 墙面 `masonry-wall-v2.png` | `courtyard_board_view.gd:715`（NEAREST，repeat） | 是 | 按世界坐标铺贴：墙顶每世界单位 10 纹素（`:772`），墙面每单位 22.36 纹素（`:776`）；镜头 1.0 时每屏幕像素约采样 10 与 22 个纹素 |
| 水面 `water-surface-v5.png` 及棋盘绘制 | `courtyard_board_view.gd:69`（棋盘根节点 NEAREST，repeat） | 是 | 纵向：10×10 试战约 0.13，25×25 约 0.06，1440p 庭院约 0.39 |
| 地表材质 meadow、moss、stone、rock | `scripts/ui/terrain/terrain_blend.gdshader:9-12`（`filter_linear`） | 是 | 同上（rock 约 0.09） |

- **判断**：修改渲染与产线，美术本体保留。

- **参考与应提取特征**：
  - [Godot：Importing images](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html)——mipmap 用于 2D 缩小显示；负的 mipmap 偏置可以换取锐度。
  - [Godot：CanvasItem](https://docs.godotengine.org/en/stable/classes/class_canvasitem.html)——`LINEAR`、`NEAREST` 不采样 mipmap；`*_WITH_MIPMAPS` 会采样。
  - `texture_mipmap_bias` 只在 Forward+ 和 Mobile 下生效，Compatibility 下恒为 0。所以偏置实验只能在 Forward+ 下做；若 D-5 选 Compatibility，棋子与碎石必须另做母版（报告 §3.1：偏置 0 时这 6 个档位 ΔE 仍 > 4）。

- **尺寸与透明/重复约束**：显示尺寸母版的高度取现有各用法在 2560×1440 下的最大显示高度，更小的显示由 mipmap 覆盖。

  | 素材 | 母版尺寸（像素） | 依据 |
  | --- | --- | --- |
  | 棋子单帧 | 高 160、宽 120 | 默认战斗 1440p |
  | 树 | 高 356、宽 361 | 庭院树丛最大缩放 2.01 |
  | 灌木 | 高 84、宽 126 | — |
  | 碎石 | 高 36、宽 50 | — |
  | 入口 | 高 234、宽 466 | — |
  | 纹章 | 116×104、100×104、92×104 | — |
  | 头像 | 140×156 | — |
  | 技能图标 | 104×104 | 现有 |

  - 透明素材保持 `process/fix_alpha_border=true`。
  - 地表、水、墙保持 repeat，只加 mipmap，不做母版（1440p 庭院下接近 1:1）。

- **做法**：先在引擎中并排三种候选：
  - **A**：原图开 mipmap，使用处改为 `*_WITH_MIPMAPS` 或 `filter_linear_mipmap`，偏置取 0、−0.5、−1.0（只在 Forward+ 下可见差别）。
  - **B**：按上表制作 Lanczos 母版，可轻度锐化，并开启 mipmap。
  - **C**：A 与 B 结合。

  持久化：为用到的 `.png.import` 增加 `.gitignore` 例外并提交，或在 `project.godot` 的 `[importer_defaults]` 中设定默认值再逐文件覆盖。使用处的过滤方式同时修改。

- **验收**：
  1. C7 全部通过（C7 不解析节点父链，过滤须设在使用节点本身，或先补父链解析，见报告 §7）：显示尺寸 / 源尺寸 < 0.5 的素材，能进入发布的导入设置（已跟踪的 `.import`，或 `importer_defaults`）生成 mipmap，且使用处的过滤方式（`.gd` 赋值、`.tscn` 节点属性、着色器提示，或继承到的项目默认值）采样 mipmap；显示倍率 ≥ 0.5 的素材不要求 mipmap。
  2. 用发行渲染器采集 A、B、C 三档分辨率的并排整屏，覆盖默认战斗、10×10 与 25×25 试战、庭院，并附棋子四方向、纹章 8 状态和头像的同帧局部。
  3. 用 `sampling_sim.py` 按所选方案对应的模式复测（`mip` 或 `mip:-0.5`；做了母版的素材用 `--master 前缀=母版路径`）：`sampling-sim.json` 的 20 个档位都要满足 ΔE76 ≤ 4；抖动判据适用的档位还要满足抖动 ≤ 参考 × 1.3。
  4. 若采用偏置：在 Forward+ 下用受控测试图（例如高频棋盘格按 0.1 倍显示）分别采集偏置 0 与 −0.5，确认引擎内确有差别；否则不得以离线模拟的 `mip:-0.5` 结果验收。
  5. 构建产物中能读到新的导入参数。
  6. 用户在引擎中选定方案。

- **未知与所需裁决**：锐利还是平滑由用户在 A、B、C 并排图上裁决；渲染器依 D-5。障碍物现在是 nearest 的"脆"质感，改为 linear 族会改变已批准外观，需要用户确认。

---

## CR-02 采集配置与发行一致（P0，产线）

- **对应**：P-03、P-15、D-5

- **现象与影响**：视觉证据与玩家实际看到的画面不一致（e03 对 e04），而且所有验证都用 Compatibility，发行却是 Forward+。

- **出错环节**：采集脚本与验证入口。

- **为何放过**：没有检查比较采集配置与 `project.godot` 和发行构建；HUD 自带的缩放系数掩盖了拉伸差异。

- **准确位置**：以下 21 个脚本设置了 `root.content_scale_mode = CONTENT_SCALE_MODE_DISABLED`。
  - `tests/` 下 19 个：
    - `capture_courtyard_visual_review.gd`
    - `capture_hud_character_panel.gd`
    - `test_courtyard_terrain_adjacency.gd`
    - `test_courtyard_water_visual_contract.gd`
    - `test_courtyard_water_depth_continuity.gd`
    - `capture_courtyard_material_intake.gd`
    - `capture_battlefield_environment_motion.gd`
    - `capture_hud_freeze.gd`
    - `capture_hud_final_acceptance.gd`
    - `capture_hud_crest_candidate.gd`
    - `test_hud_m2_runtime_dashboard.gd`
    - `capture_hud_number_candidate.gd`
    - `test_battlefield_courtyard.gd`
    - `test_myrmidon_skill_icons.gd`
    - `test_terrain_battle_runtime.gd`
    - `test_terrain_map_size.gd`
    - `test_terrain_kit.gd`
    - `test_terrain_painter_battle_flow.gd`
    - `test_terrain_painter.gd`
  - `dev_doc/ui-art-research/` 下 2 个：
    - `hud-myrmidon-portrait/capture_review.gd:15`
    - `myrmidon-skill-icons/capture_candidate.gd:15`
  - 验证入口 `tests/run_*_validation.ps1` 传入 `--rendering-method gl_compatibility`；发行构建 `scripts/codex/build-windows-release.ps1` 用项目默认的 Forward+（`project.godot:20`）。

- **证据**：e03、e04。Forward+ 与 Compatibility 的对照见报告 §3.2 和 e33。

- **判断**：修改。

- **参考与应提取特征**：
  - `tests/claude_review/capture_scene_native.gd`：默认保留项目拉伸；关闭拉伸只作为条件分支中的对照模式；清单记录 `content_scale_mode`、`content_scale_size`、`visible_rect` 与渲染器。

- **尺寸与透明/重复约束**：视觉证据以 1280×720 为基准，覆盖三档分辨率。

- **做法**：
  1. 产出视觉证据的采集脚本保留项目拉伸，只设置窗口尺寸。
  2. 确实需要固定像素几何的单元测试可以继续关闭拉伸，但须在 `##` 文件头写明"不代表运行配置"，其截图不得作为视觉验收证据。
  3. 验证入口与发行构建使用同一渲染器（依 D-5）。
  4. 每份采集清单记录拉伸与渲染器，并加入 C8。

- **旧错例**：
  - `capture_hud_final_acceptance.gd` 的 1920 截图（e03）里 `Turn Order` 位于屏幕中部，而实际拉伸下它贴右边缘。
  - C8 已拒绝 21 个现行脚本，以及"注释含关键字但无条件关闭"的合成反例。

- **验收**：
  1. C8 对全部视觉证据脚本通过。
  2. 采集清单中的渲染器与发行一致。
  3. 重新生成的 HUD、庭院、试战证据与 `capture_scene_native.gd --stretch=project` 的布局一致。

- **未知与所需裁决**：D-5，目标渲染器是 Forward+ 还是显式 Compatibility。

---

## CR-03 网格线每条只画一次（P1）

- **对应**：V-25、P-08

- **现象与影响**：半透明线在交点叠加出亮星，水面上最明显，干扰读格和观感（e16、e18）。

- **准确位置**：`scripts/ui/playground/courtyard_board_view.gd:218`（每格绘制闭合菱形）与 `:220`（外框）；线色 `assets/prototype/battlefield_courtyard/visual_profile.json` 中的 `grid_color = "c9c8b45c"`。

- **证据**：e16、e18。

- **判断**：修改。

- **参考与应提取特征**：沿用现有线色与线宽的视觉分量，只改变绘制方式。

- **尺寸与透明/重复约束**：线宽在三档分辨率下保持现有观感，大约为基准 0.55 世界单位乘以镜头缩放；交点与边中点的不透明度必须一致。

- **做法（推荐第一种）**：
  1. **着色器网格**：在棋盘表面按格坐标的小数部分计算到最近格线的距离，用 `smoothstep` 得到线宽。每个像素只着色一次。
  2. **按线族绘制**：沿两个方向各画 N+1 条贯通长线，改用不透明线色，或在交点补偿 alpha。

- **旧错例**：现行实现。实施后它应被 C6 拒绝。

- **验收**：
  1. 实现 C6：在纯色底和水面上渲染 10×10 网格，采样全部顶点与边中点的 L*，二者之差 ≤ 2。
  2. 现行实现作为错例被拒绝。
  3. 三档分辨率整屏中看不到亮星。
  4. `courtyard_board_view.gd` 属于批准来源，需要建立新批次。

- **未知与所需裁决**：无。

---

## CR-04 试战外围：消除世界边缘，补外围环境（P1）

- **对应**：V-26

- **现象与影响**：外围只有单一草土，画面空旷（e19）；25×25 时视口四角露出深色背景（e21）。

- **准确位置**：
  - `scripts/ui/terrain/terrain_surface.gd:8`（`padding := 32`，菱形）
  - `scripts/tactical/terrain_battle_session.gd:99-106`（镜头）
  - `scripts/ui/playground/courtyard_board_view.gd:420`（`_draw_channel_extension`，可以作为向外延伸的范例）

- **证据**：e19、e21。

- **判断**：修改。

- **参考与应提取特征**：
  - 本项目庭院三布局的外围组织（e16、e17）：
    - 边缘地形向场外延续；
    - 树丛与残垣围合；
    - 外围不喧宾夺主。
  - 方法依据：`visual-review/README.md` 中引用的 Tiled Terrain 与 Unexplored 2 的分层地图实践。

- **尺寸与透明/重复约束**：
  - 外围地表沿用 `terrain_blend.gdshader` 的世界坐标 UV 与重复周期，不另做新贴图。
  - 装饰物使用现有树、灌木、碎石素材，按 CR-01 的母版与 mipmap 规定。

- **做法**：
  1. **消除世界边缘**：按最小缩放和视口计算外延范围，或者用屏幕空间的无限地表层（背景四边形使用世界坐标 UV）。
  2. **外围装饰**：由棋盘边缘的地形类型向外延伸若干格；用地图内容的哈希作种子，确定性地散布树木与残垣，不得侵入棋盘。
  3. **框出战场**：棋盘外 3 格起逐渐压暗，L* 下降不少于 15%。

- **验收**：
  1. 10×10、17×17、25×25 在三档分辨率、最小缩放下，屏幕四角 16×16 像素内没有背景色像素（自动检查）。
  2. 外围不遮挡棋盘格，也没有与内部无空间关系的物件（人工看图）。
  3. 建立新批次。

- **未知与所需裁决**：无。装饰的疏密与风格在新批次中由用户视觉验收。

---

## CR-05 大地图初始视角的可读下限（P1）

- **对应**：V-27

- **现象与影响**：25×25 初始缩放约 0.418，每格约 27 像素，单位与数字不可读（e20）。

- **准确位置**：`scripts/tactical/terrain_battle_session.gd:99-106`。

- **证据**：e20、e21。

- **判断**：修改。

- **参考与应提取特征**：沿用现有拖动、滚轮缩放和"居中"交互。

- **尺寸与透明/重复约束**：1280×720 下初始格宽 ≥ 48 像素（缩放 ≥ 0.75）。

- **做法**：
  - 初始缩放取 `max(适配全图的缩放, 可读缩放)`，镜头对准当前行动单位或出生区域。

- **验收**：
  1. 25×25 在 1280×720 下初始格宽 ≥ 48 像素，单位 ≥ 40 像素，血量数字 ≥ 11 像素。
  2. 现有滚轮缩放仍能缩到看见整张地图。
  3. `tests/test_terrain_map_size.gd` 的预期按新规则明确更新，不能删除断言。

- **未知与所需裁决**：是否另加一键"全图"切换属于新交互，需要用户决定；本单不要求。

---

## CR-06 单位地图棋子与名牌血条（P1，新制作）

- **对应**：V-19、V-21、P-11

- **现象与影响**：
  - 基础剑士、枪兵及全部敌人都是文字方块（e17、e19）。
  - 占位血条宽于棋子，压住后排单位头部（e13、e14）。

- **准确位置**：
  - `scripts/units/unit.gd:698,713`（`_hp_label`、`_unit_label`）
  - `scripts/units/map_token_view.gd`
  - `data/visual_profiles/`
  - `data/classes/*.json`

- **证据**：e13、e14、e17、e19。

- **判断**：缺失，需要新制作；名牌与血条重做。

- **范围（按顺序）**：
  1. 基础剑士：单武器，NW/NE/SW/SE 四方向。
  2. `test_lancer`。
  3. RunScene 首战出现的敌我单位。

- **参考与应提取特征**：
  - 身份：`assets/ui/portraits/myrmidon_hud_portrait_generated.png`
  - 画风与比例：`assets/units/kensei/map_token_clean_v2.png`，提取：
    - 身高约占帧高的 70%
    - 左上受光
    - 黑紫与旧金的配色比例
    - 1–2 像素的金属高光簇
    - 剑与手的真实握持
  - 服装配色：基础剑士技能图标

- **尺寸与透明/重复约束**：
  - 沿用 `data/visual_profiles/kensei_map_token.json` 的合同：
    - 源帧 384×512，透明背景；
    - 逐帧脚部 pivot：横向取人体解剖中轴，纵向取双脚接地点中点；
    - 局部显示 60×80。
  - 按 CR-01 另出单帧母版，高 160、宽 120。
  - 武器必须读成长剑，不能像匕首；可以用 C2 的思路预筛：剑身长度 ≥ 身高的 0.6。
  - 透明清理必须附带可重跑的脚本与参数。
  - 名牌与血条：
    - 宽度 ≤ 棋子宽度（720p 约 40 像素），高 4 像素；
    - 用阵营色描边区分敌我；
    - 与后排单位头部重叠时降低不透明度或偏移；
    - 绘制在单独的 UI 层。

- **旧错例**：旧预览板 `map_token_preview_final_v2` 外轮廓约 34% 为近白像素（`anchor-audit-token.json`），新棋子的清理结果应达到 clean_v2 的 0%。

- **验收**：
  1. 三档分辨率的试战与庭院整屏中没有文字方块单位。
  2. 分步盲测：独立审查者在 1280 下能区分敌我和单位类型。
  3. pivot 落在格心。
  4. 自动检查：血条矩形不与其他单位的头部矩形相交。
  5. 运动序列中无闪烁（C7）。
  6. 外轮廓近白像素占比与 clean_v2 相当（`art_audit.py` 的 `edge_fringe`）。

- **未知与所需裁决**：
  - 敌方单位的外观设定若涉及叙事或设计，按 KB 与设计库现行记录执行，没有记录的项需要用户裁决。
  - 血量数字是否默认隐藏、只在悬停或选中时显示，会改变信息可见性，需要用户裁决；裁决前保持现有显示方式。

---

## CR-07 基础剑士五枚技能图标（P1）

- **对应**：V-04、P-02、P-06

- **现象与影响**：
  - 四枚图标羽化、半透明，轮廓不统一。
  - 色相跨度只有 11.7°。
  - 盲测中一闪不可辨，居合只有中等把握（e09、e10）。

- **准确位置**：
  - 运行图：`assets/ui/skills/myrmidon/{xinyan,zhanji,yishan,zhaojia,juhe}.png`
  - 派生：`dev_doc/ui-art-research/myrmidon-skill-icons/build_icons.gd:19`
  - 源图：`candidate-v3/*-source.png`

- **证据**：e09、e10、e11、`blind-test-reviewer-report.json`、`claude-review-checks.json`（C1、C2、C3）。

- **判断**：五枚都修改处理方式；一闪重做；居合修订构图；斩击、招架、心眼保留主体设计。

- **参考与应提取特征**：
  - 斩击 `zhanji-source.png`：盲测高把握。提取其大块对比、单一亮弧、主体占画面 80%。
  - 招架 `zhaojia-source.png`：提取其单一亮接触点。
  - 色相分工（本审查提议，待 D-4）：VA-6 规格 `dev_doc/skillbar-design/bottom-dashboard-combined-visual-design-spec.md:52` 只定义了绛红、黯紫、冷钢蓝三种语义色（色板未冻结，见 `:59`），下面把它们分配到技能类型是本审查的提议：
    - 攻击：绛红
    - 位移：冷钢蓝 `#708493`，亮阶 `#9FB2BF`
    - 防御：旧黄铜
    - 被动：黯紫点缀

- **尺寸与透明/重复约束**：
  - 满幅方形，alpha 恒为 255；运行显示 52×52，按 CR-01 另出 104×104 母版。
  - 背景统一为图标族暗底：四枚源图边缘环带实测中位色约为 `#130000`–`#170201`（心眼因发色偏红，不参与取样）。
  - 需要边缘压暗时，五枚共用同一张设计好的暗角遮罩。

- **做法**：
  1. **全部五枚**：`build_icons.gd` 先合成到统一底色，再缩放，必要时套用共用遮罩；C1 全部通过。
  2. **一闪（重做）**：52 像素下要有清楚的人形轮廓，外加单一方向、穿过敌人剪影的直线轨迹。人形占画面高度 ≥ 45%；52 像素下人形 L* ≥ 45，背景 L* ≤ 15；轨迹用冷钢蓝系。
  3. **居合（修订）**：剑身在 52 像素下至少 3 像素粗；加上左侧刀鞘口与半出鞘的剑身作为出鞘线索（"拔刀"是剑圣技能 `swordsman_badao` 的名称，基础剑士图标不要借用这个语义）；保持单一直线；C2 ≥ 0.75。
  4. **心眼（可选，P3）**：保留眼部主题，去掉与头像相同的发型与面罩。

- **旧错例**：
  - 修正前的居合 `juhe-before-length-correction.png` 在 C2 中得 0.54，被拒。
  - 历史对照组的旧斩击与居合，在盲测中被判为中度混淆。

- **验收**：
  1. C1、C2、C3 通过（C3 色相跨度 ≥ 45°）。
  2. 换一位没看过本轮图片的独立审查者做分步盲测：先只给图片描述主体和动作，再给技能表匹配。五枚都要达到高把握。
  3. 三档分辨率下可用、不可用、选中、冷却四种状态的整屏与同帧局部。
  4. 用户视觉验收。

- **未知与所需裁决**：色相分工依赖 D-4；技能含义以设计库为准，不从图标推定。

---

## CR-08 纹章显示与空心态（P1）

- **对应**：V-07

- **现象与影响**：持有态金边碎成点；空心态描边断续（e07、e08）。

- **准确位置**：
  - `scripts/ui/hud/m2/marks_panel.gd:7-16`（区域与目标矩形）
  - `assets/ui/shaders/hud_mark_hollow.gdshader:7`（`reach = TEXTURE_PIXEL_SIZE * 14.0`）

- **证据**：e07、e08。

- **判断**：保留设计，修改渲染。

- **参考与应提取特征**：[FINAL FANTASY XIV 武士职业指南](https://na.finalfantasyxiv.com/jobguide/samurai/)展示了三个独立资源位的"已获得与未获得"表达，只作状态表达方式的研究，不复制图形。

- **尺寸与透明/重复约束**：
  - 显示 58×52、50×52、46×52；母版 116×104、100×104、92×104，透明背景，开启 mipmap。
  - 空心描边在 720p 下 2 像素宽。

- **做法**：
  - 空心态二选一：用母版预渲染描边贴图；或者着色器改为屏幕空间宽度（`reach = 2 像素 / 显示缩放`，换算成 UV），并在母版上采样。
  - 持有态为彩色珐琅、空心态为灰色描边，这一语义不变。

- **验收**：
  1. 三档分辨率下 000–111 八种状态的整屏与同帧局部。
  2. 每个纹章的空心描边掩膜连通分量 ≤ 2。
  3. 持有态金边与面积滤波参考的 ΔE76 ≤ 3（e08 的对照方法）。
  4. 现行实现作为错例被拒绝。

- **未知与所需裁决**：无。

---

## CR-09 行动顺序面板重做（P1）

- **对应**：V-14

- **现象与影响**：英文开发样式，不在 M2 视觉语言内（e01、e04）。

- **准确位置**：`scripts/ui/turn_order_bar.gd:48`（`Turn Order`）、`:137`（`Init %d`），以及 `M✓ A✓ S✓` 字段。

- **证据**：e01、e04。

- **判断**：重做。

- **参考与应提取特征**：
  - M2 主题共享框体的材质：暗紫底加细黄铜边。
  - 行动资源符号与 CR-14 统一。

- **尺寸与透明/重复约束**：
  - 锚定右上角，随项目拉伸缩放。
  - 720p 下文字 ≥ 12 像素；单位缩略图约 24×24。

- **做法**：
  - 标题改为"行动顺序"。
  - 每项包含：单位小头像或棋子缩略图（没有时用职业符号），名称，带图标的先攻值。
  - 剩余行动用 CR-14 的符号。
  - 当前单位用黄铜框高亮。

- **验收**：
  1. 三档分辨率（项目拉伸）下没有英文字段。
  2. 颜色与材质在 M2 色板内。
  3. 行动顺序的现有功能测试通过。

- **未知与所需裁决**：无。

---

## CR-10 打包中文字体（P1）

- **对应**：V-23，缺口 G07

- **现象与影响**：中文依赖系统回退，不同机器上字形不同。

- **准确位置**：
  - `scripts/ui/hud/m2/hud_font_setup.gd`（`allow_system_fallback = true`；默认字族来自 `ThemeDB.fallback_font`）
  - `assets/ui/themes/hud_m2_fonts.tres`

- **证据**：代码。

- **判断**：修改。

- **参考与应提取特征**：
  - Noto Sans CJK SC（或 Google Fonts 的 Noto Sans SC）采用 SIL OFL 1.1，未声明保留字体名，子集化后无需改名。[许可原文](https://github.com/notofonts/noto-cjk/blob/main/Sans/LICENSE)
  - 思源黑体声明了保留字体名 `Source`，派生子集必须改名。[许可原文](https://github.com/adobe-fonts/source-han-sans/blob/release/LICENSE.txt)

- **尺寸与透明/重复约束**：
  - 子集范围：GB2312 常用字加游戏全部字符串。
  - 按现有字体目录的格式记录 `source.json`、`LICENSE.txt` 和 SHA256。

- **做法**：
  - 设为 HUD 与默认主题的中文字族。
  - 发行配置关闭系统回退。

- **验收**：
  1. 关闭系统回退后，三档分辨率整屏中的中文全部正常显示。
  2. 字体与许可在发行包内。

- **未知与所需裁决**：字重（Regular、Medium 或 Bold）按 CR-18 的字号层级确定，无需另行裁决。

---

## CR-11 默认战斗与 RunScene 统一走地形渲染（P1）

- **对应**：V-32、V-02

- **现象与影响**：主场景与 Run 循环的战斗显示亮绿占位菱形（e01、e14）。

- **准确位置**：`DataLoader.maps` 的旧地图数据与旧战术网格渲染；地形渲染入口为 `TerrainCatalog.validate_map` → `Grid.initialize` → `CourtyardBoardView.configure`（见 `visual-review/terrain-kit.md` 的"技术消费约定"）。

- **证据**：e01、e14。

- **判断**：修改。

- **参考与应提取特征**：正式试战已经证明了这条渲染路径（e19）。

- **尺寸与透明/重复约束**：地图仍只能是正方形、边长 10–25。旧地图不满足时，需要先确认是否属于测试夹具。

- **做法**：
  - 把旧地图转换为地形目录格式，并通过合法性检查。
  - 暂时无法转换时，标为开发夹具，不出现在玩家流程中。

- **验收**：
  1. RunScene 首战与默认战斗在三档分辨率下使用地形库渲染。
  2. 战斗与注入回归通过。
  3. 默认战斗统一镜头逻辑后，1280 下棋盘可见像素与 HUD 组件的最近间距不小于现在的约 7.3 像素，也不与 HUD 重叠（报告 V-42）。

- **未知与所需裁决**：旧地图若不是正方形或尺寸不在 10–25，转换方式涉及地图规格，需要先读设计库并由用户裁决。

---

## CR-12 非战斗界面文本清理（P1）

- **对应**：V-36

- **现象与影响**：备战、运输队、商店、事件选项、事件结果与结束面板直接显示内部 ID 和开发备注（e25、e30、e31）。

- **准确位置**：`scripts/roguelite/run_scene.gd`，涉及以下构建函数：

  - `_show_prep`、`_build_intel_section`、`_build_convoy_panel`、`_build_shop_section`（备战、运输队、商店）
  - `_show_event_choices`、`_show_event_outcome`（事件）
  - `_show_end_panel`（结束面板）

  已确认的具体位置：
  - `scripts/roguelite/run_manager.gd:269`：事件结果日志写入"[占位] 获得 run buff：……（执行器待建，未生效）"。
  - `run_scene.gd:204`：备战标题"备战 (Prep) — 下一关：stage N"。
  - `run_scene.gd:332`：运输队成员行直接显示 `class_id`。

- **证据**：e25、e30、e31。商店界面本次没有采集到画面，上述商店条目只来自代码阅读，实施后须补采。

- **判断**：先清理文本（本单）；整套视觉在 UI 组件库完成后重做（CR-22 同类）。

- **参考与应提取特征**：沿用 M2 字号层级与色板。

- **尺寸与透明/重复约束**：720p 下正文 ≥ 12 像素。

- **做法**：
  - 内部 ID 改为数据中的显示名。
  - 开发标签（`[提案]`、`[占位]`、"执行器待建，未生效"等）只在调试构建中显示。
  - 面向玩家的规则说明（如恢复比例）按设计库现行记录表述，不从界面文案推定规则。
  - 英文 `stage`、`RUN` 改为中文。

- **验收**：
  1. 玩家可见文本中检索不到 `[占位]`、`[提案]`、英文 ID 与英文阶段词。
  2. 六种界面整屏看图，包括本次未采集的商店。

- **未知与所需裁决**：显示名缺失的数据项需要内容方补充。

---

## CR-13 剑圣占位技能图标处置（P1）

- **对应**：V-05，裁决 D-3

- **现象与影响**：开发占位图的来源与分发权未核实（G02），构造与基础剑士不一致，2× 下发糊（e28）。

- **准确位置**：`assets/prototype/hud_m2/skill-*.png`；`assets/ui/catalogs/hud_m2_skill_icons.json` 的剑圣映射。

- **证据**：e05、e28；交接 `files.md`。

- **判断**：删除（替换）。

- **参考与应提取特征**：沿用 CR-07 的构造：不透明方形、图标族底色。

- **尺寸与透明/重复约束**：52×52 显示，104×104 母版，alpha 恒为 255。

- **做法**：按 D-3 用中性占位替换（通用符号，明确的"未定"状态，不表达未定版技能含义）；旧文件退出发行包。

- **验收**：
  1. 导出包检查中不再出现 G02 文件。
  2. 剑圣 HUD 三档整屏。

- **未知与所需裁决**：D-3。

---

## CR-14 行动资源图形（P2）

- **对应**：V-08、V-03，裁决 D-4

- **现象与影响**：几何图元加离色板的薄荷绿（e05、e06）。

- **准确位置**：
  - `scripts/ui/hud/m2/action_resource_glyph.gd`
  - `assets/ui/themes/hud_m2.tres:913-914`（`standard = #54B789`，`swift = #D49A51`）
  - `scenes/tactical/hud/m2/action_resource_strip.tscn:8`（行动条 274×40）

- **证据**：e05、e06。

- **判断**：布局保留，图形重做。

- **参考与应提取特征**：纹章的"黄铜边加珐琅"材质语言，简化为小符号。

- **尺寸与透明/重复约束**：
  - 保持行动条 274×40 与各区现有字形控件的尺寸，每类最多 3 点。
  - 程序绘制保持矢量；如果改用位图，按 2× 显示尺寸制作并开启 mipmap。

- **做法**（颜色分工是本审查的提议，待 D-4；VA-6 规格 `:52` 只定义了绛红、黯紫、冷钢蓝三种语义色）：
  - 移动：保留脚印，冷钢蓝 `#708493`，亮阶 `#9FB2BF`。
  - 标准行动：圆形珐琅，旧黄铜亮面 `#C9A25A`。
  - 迅捷行动：菱形或三角珐琅，冷骨白 `#D8D0C2`（中性色；与标准行动靠明度和形状区分）。
  - 已用：只留边框，填充 `#4A4450`。

- **验收**：
  1. 有彩色（移动、标准行动）与色板基色同色相（色相差 ≤ 6°），只在明度或彩度上不同；中性色（迅捷行动、已用）以彩度 C* ≤ 12 为准，不按色相判定。移动、标准行动、已用三个提议色已实测：与冷钢蓝、旧黄铜、炭紫黑的色相差分别为 3.8°、4.0°、5.1°。
  2. 红绿色弱模拟下三态可以靠形状区分。
  3. 在真实操作流程中采集可用、部分消耗、全部消耗三态。

- **未知与所需裁决**：D-4。

---

## CR-15 技能不可用态（P2）

- **对应**：V-06、V-06b、P-13

- **现象与影响**：不可用图标压暗到接近全黑（e20、e21）；全消耗画面是用直接修改资源的方式采集的，不代表实际流程。

- **准确位置**：
  - `scripts/ui/hud/m2/skill_slot_button.gd:57`（`_unavailable_shade`）
  - `scripts/ui/hud/m2/dashboard_view_adapter.gd:127`（`enabled`）
  - `tests/capture_hud_final_acceptance.gd`（`consume_*` 调用）

- **证据**：e06、e20、e21。

- **判断**：修改；V-06b 需要复核。

- **参考与应提取特征**：保留轮廓与主色，用去饱和与遮挡纹理表达不可用。

- **尺寸与透明/重复约束**：遮罩覆盖 52×52 内容区，不改变槽尺寸。

- **做法**：
  - 不可用：去饱和 80%，明度约 60%，叠加细斜线或锁形符号。原因继续放在提示中。
  - 复核：先实际使用技能消耗行动，再截图。

- **验收**：
  1. 盲测中不可用图标的可辨识度不低于可用态一个等级。
  2. 用真实流程重拍 V-06b 并给出结论。

- **未知与所需裁决**：无。

---

## CR-16 被动技能槽尺寸（P2）

- **对应**：V-09，裁决 D-2

- **现象与影响**：规格要求被动槽"略小"，实际与主动槽等大。

- **准确位置**：`scenes/tactical/hud/m2/skill_slot_button.tscn:8`；`assets/ui/skins/hud_m2_fe/slot-passive.png`（64×64）。

- **证据**：KB 默认分支第 57 行；VA-6 规格。

- **判断**：需裁决。

- **参考与应提取特征**：主动槽的框体语言保持一致。

- **尺寸与透明/重复约束**：建议 56×56 或 52×52，与主动槽底边对齐；框体按 CR-17 出母版。

- **做法**：按 D-2 执行，并同步 Penpot 与布局资源（CR-26）；快捷键角标与可触发状态的合同不变。若保留等大，把裁决写入 KB，并改正 VA-6 与 skillbar 规格中的描述。

- **验收**：三档整屏；Penpot 与 Godot 的几何一致。

- **未知与所需裁决**：D-2。

---

## CR-17 HUD 框体高分辨率母版（P2）

- **对应**：V-16、P-12

- **现象与影响**：1× 纹理在 2560×1440 下放大后发软（e28）；材质表现弱于纹章与头像（e01）。

- **准确位置**：`assets/ui/skins/hud_m2_fe/*.png`（9 张）；`scripts/ui/hud/m2/shared_frame_style.gd`。

- **证据**：e01、e28、`hud-frame-audit.json`。

- **判断**：修改。

- **参考与应提取特征**：
  - 已批准 UI 锚点 `assets/prototype/visual_style/samples/ui_preview_final_v3.png`：45° 断角母题、两色黄铜线、宝石铆钉。
  - 装饰不得压过人物（VA-6 规格）。

- **尺寸与透明/重复约束**：
  - 2× 导出（例：共享框 2432×308），开启 mipmap。
  - NinePatch 边距为偶数，最小、标准、最大尺寸下没有接缝。
  - 透明区域保持真实透明。

- **做法（二选一，先做小规模验证）**：
  - **(a)** 从 Penpot 以 2× 重新导出。
  - **(b)** SVG 加 DPITexture：Godot 4.6 中 SVG 是唯一能导入为 DPITexture、按当前过采样倍率在运行时重新栅格化的格式（[导入说明](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html)）。需要验证 ThorVG 的渲染结果和 StyleBoxTexture 的用法。
  - 材质增强按 D-1：保持左上受光、右下压暗；黄铜线在 1× 下用 1 像素亮边加 1 像素暗边。

- **验收**：
  1. 2560 下框线的边缘过渡 ≤ 1.5 像素。
  2. 1280 下与现有批准外观一致，或经用户重新批准。
  3. NinePatch 在三种尺寸下没有接缝。

- **未知与所需裁决**：材质是否增强依 D-1。

---

## CR-18 人物栏文字层级（P2）

- **对应**：V-11、V-24

- **现象与影响**：英文缩写与中文混用；8 像素标签难读；没有数据时仍显示破折号占位（e05、e12）。

- **准确位置**：`scenes/tactical/hud/m2/character_hud_panel.tscn`；`assets/ui/themes/hud_m2.tres` 中人物栏的字号覆盖。

- **证据**：e05、e12。

- **判断**：修改。

- **参考与应提取特征**：属性悬浮卡的中文标签写法（e02）。

- **尺寸与透明/重复约束**：720p 下最小字号 11–12 像素；数字继续用 IBM Plex Mono。

- **做法**：
  - `HP`、`SH`、`XP`、`Lv.` 改为中文标签（生命、护盾、经验、等级）或小图标。
  - 没有数据的行隐藏。

- **验收**：三档整屏；字号层级与悬浮卡一致。

- **未知与所需裁决**：无。

---

## CR-19 调试提示与开发面板的发布隔离（P2）

- **对应**：V-15

- **现象与影响**：调试提示常驻主战斗画面。

- **准确位置**：`scripts/tactical/tactical_scene.gd:542`（`DEBUG_HINT_TEXT`）。

- **证据**：e01。

- **判断**：修改。

- **参考与应提取特征**：无。

- **尺寸与透明/重复约束**：无。

- **做法**：只在 `OS.is_debug_build()` 或显式开发开关打开时显示。庭院与工作台的场景切换按钮保持为开发工具。

- **验收**：导出包运行截图中没有调试提示。

- **未知与所需裁决**：无。

---

## CR-20 石柱的明度与材质（P2）

- **对应**：V-30

- **现象与影响**：在试战缩放下，石柱是几乎没有材质的黑色长方体（e18）。

- **准确位置**：`scripts/ui/playground/courtyard_board_view.gd` 的墙体与石柱绘制（`:715` 起），使用 `masonry-wall-v2.png`。

- **证据**：e18。

- **判断**：修改。

- **参考与应提取特征**：同一画面中残墙立面的明度与磨损（e18 右上）。

- **尺寸与透明/重复约束**：沿用 masonry 材质与 repeat，不新增贴图。

- **做法**：石柱立面 L* 提高约 12；顶面加左上受光的亮边；边角加磨损。

- **验收**：10×10 与 25×25 三档整屏下石柱可辨认为石材；建立新批次。

- **未知与所需裁决**：无。

---

## CR-21 无网格态的可战区域提示（P2）

- **对应**：V-33

- **现象与影响**：关闭网格后，可战区域与外围环境分不开（e17）。

- **准确位置**：`courtyard_board_view.gd:219-221`（外框线）。`:219` 的注释写明"边界仅在格线模式显示，不把环境切成有装饰边框的菱形底板"，即现行行为是有意设计。

- **证据**：e17。

- **判断**：需裁决（建议采纳）。

- **参考与应提取特征**：与 CR-04 的外围压暗共用。

- **尺寸与透明/重复约束**：1 像素、低不透明度的外轮廓，或棋盘外轻度压暗。

- **做法**：关闭网格时保留很弱的边界提示，不做装饰性边框，以符合现行设计意图。

- **验收**：荒草中庭无网格态下能分辨可战区域边界；e17 作为错例被拒绝。

- **未知与所需裁决**：现行设计有意在无网格态不显示边界。是否改为保留极弱提示，由用户决定（报告 V-33）。

---

## CR-22 选门界面去 emoji（P2）

- **对应**：V-35

- **现象与影响**：emoji 字形随平台变化，风格也与游戏冲突（e24）。

- **准确位置**：
  - `scripts/roguelite/door_select.gd:20-27`（`REWARD_LABELS`，其中 `:26` 为"☠ Boss"）
  - `door_select.gd:80`（精英房说明行"💀 精英房"）

- **证据**：e24。

- **判断**：先去 emoji；整套选门界面在 UI 组件库完成后重做。

- **参考与应提取特征**：沿用 CR-07 的图标构造做奖励类型图标。

- **尺寸与透明/重复约束**：按钮沿用 `DOOR_BUTTON_MIN_SIZE`（190×128）。

- **做法**：改为纯文字标签。

- **验收**：整屏；不含 emoji 字符。

- **未知与所需裁决**：无。

---

## CR-23 三档分辨率验收（P2，产线）

- **对应**：P-12

- **现象与影响**：验证批次只含两档，1× 纹理在 2× 下发软这类问题不会被采集到。

- **出错环节**：验证入口的分辨率列表。

- **为何放过**：入口只采 1280 与 1920 两档。

- **准确位置**：`tests/run_terrain_runtime_validation.ps1`、`tests/run_courtyard_visual_validation.ps1` 及各采集脚本中的尺寸列表。

- **证据**：e28。

- **判断**：修改。

- **参考与应提取特征**：KB 视觉裁决要求 720p、1080p、1440p 三档。

- **尺寸与透明/重复约束**：2560×1440；本机显示器已支持。

- **做法**：所有视觉批次加入 2560×1440，与 CR-02 同时实施。

- **旧错例**：e28 在新入口中应被采集到。

- **验收**：验证入口输出包含三档。

- **未知与所需裁决**：无。

---

## CR-24 头像贴合（P2）

- **对应**：V-10、P-04

- **现象与影响**：头像顶边与黄铜内边之间有面板底色缝（1280 下 1 行，1920 下 2 行）（e12、e32）。

- **准确位置**：
  - `scenes/tactical/hud/m2/character_hud_panel.tscn:51`（`PortraitContent` 顶边）
  - `assets/ui/themes/hud_m2.tres:650-661`（`FE_Portrait`；`:656` 为 `expand_margin_top = 2.0`）
  - `tests/test_hud_m2_runtime_dashboard.gd:75`（顶边容差 +3）

- **证据**：e12、e32，C4。

- **判断**：修改。

- **参考与应提取特征**：其余三边已经贴合，按其贴合方式处理顶边。

- **尺寸与透明/重复约束**：头像显示 70×78，画框控件 72×82，外框 72×84。

- **做法**：调整 `PortraitContent` 的位置或尺寸，或 StyleBox 的扩边；把 `:75` 的节点矩形检查换成 C4 的同帧像素检查。

- **旧错例**：现行 1280 与 1920 画面被 C4 拒绝（已验证），合成的修正图通过。

- **验收**：C4 在三档分辨率下通过。

- **未知与所需裁决**：无。

---

## CR-25 局部图与整屏的同帧记录（P2，产线）

- **对应**：P-05

- **现象与影响**：局部图与整屏的对应只靠人工记录。

- **出错环节**：采集清单。

- **为何放过**：清单不记录局部图的来源帧。

- **准确位置**：各 `capture-manifest.json` 与 `archive-manifest.json`。

- **证据**：C5。

- **判断**：修改。

- **参考与应提取特征**：本审查 `evidence-manifest.json` 的"裁切区域与倍数"写法。

- **尺寸与透明/重复约束**：无。

- **做法**：清单为每张局部图记录源帧文件与 SHA256、裁切区域、倍数和插值方式；验证入口用 C5 复算。

- **旧错例**：C5 的两个反例：重生成版细节配原画版整屏；"部分消耗"行动条细节配"全部可用"整屏。

- **验收**：现有 4 组细节通过，两个反例被拒绝。

- **未知与所需裁决**：无。

---

## CR-26 Penpot 与 Godot 的几何同步（P2，产线）

- **对应**：P-09，缺口 G06

- **现象与影响**：Godot 在定版后改了头像、图标、纹章尺寸和沙漏，Penpot 未同步。

- **出错环节**：设计源与运行事实之间没有同步规则。

- **为何放过**：没有对账步骤。

- **准确位置**：`dev_doc/ui-art-research/penpot/2026-09-24-hud/manifest.json`；Penpot 文件 `New File 1` 的页面 `HUD R1 · 基础 UI 材质与布局修订`。

- **证据**：revision 189、215 与实时 221 的差异；交接 `penpot.json`。

- **判断**：修改。

- **参考与应提取特征**：无。

- **尺寸与透明/重复约束**：以 1280×720 为基准记录矩形。

- **做法**：以 Godot 场景为运行事实、Penpot 为设计源；每次改动后更新 Penpot 并保存命名版本，在清单中记录几何差异；先对当前做一次对账。

- **验收**：对账表列出每个组件在两边的矩形，差异为 0 或有明确的裁决记录。

- **未知与所需裁决**：唯一权威的选择如与本建议不同，需要用户确认。

---

## CR-27 水面外观（P3）

- **对应**：V-29

- **现象与影响**：青色与暖土的色相冲突；接壤样例中像平铺色块；涟漪是规整圆圈（e16、e18、e22）。

- **准确位置**：`courtyard_board_view.gd:318`（`_draw_water_surface`）、`:491`（`_draw_ripple`）；`visual_profile.json` 的水色参数。

- **证据**：e16、e18、e22；报告 §3.4 的测量。

- **判断**：保留连续水深机制与函数，修改外观局部。

- **参考与应提取特征**：地形锚点的低彩度（平均 C* 约 5.2）。

- **尺寸与透明/重复约束**：`water-surface-v5.png` 的重复周期不变。

- **做法**：浅水色调向冷钢蓝系靠拢，或把浅水着色的彩度降低约 25%；涟漪改为长短不一的断续短弧，不透明度 ≤ 25%。

- **验收**：水岸、水深全部检查继续通过（正例与错例结果不变）；三档整屏；用户视觉验收；建立新批次。

- **未知与所需裁决**：水面色调的方向由用户在对照图上裁决。

---

## CR-28 工作台易用性（P3）

- **对应**：V-34

- **现象与影响**：地形只有文字按钮；选中态弱；720p 下左栏需要滚动（e23）。

- **准确位置**：`scripts/ui/playground/terrain_painter.gd`；`scenes/playground/terrain_painter.tscn`。

- **证据**：e23。

- **判断**：保留功能，修改易用性。

- **参考与应提取特征**：各地形实际材质的小色块。

- **尺寸与透明/重复约束**：色块约 24×24，取自运行材质。

- **做法**：地形按钮加材质色块；选中态用高对比描边；左栏分组折叠或改为两列。

- **验收**：1280 整屏；`tests/test_terrain_painter.gd` 通过。

- **未知与所需裁决**：无。

---

## CR-29 证据目录 `.gdignore`（P3，产线）

- **对应**：P-10

- **现象与影响**：`dev_doc/ui-art-research/hud-*` 下的 55 张证据图会被本机导入，只增加导入耗时和缓存（导入文件被 `.gitignore` 忽略，不会进入提交）。

- **出错环节**：目录约定。

- **为何放过**：没有要求证据目录加 `.gdignore`。

- **准确位置**：`dev_doc/ui-art-research/hud-*`。

- **证据**：目录清点结果。

- **判断**：修改。

- **参考与应提取特征**：`visual-review/`、`penpot/` 与本审查证据目录已有 `.gdignore`。

- **尺寸与透明/重复约束**：无。

- **做法**：为这些目录加 `.gdignore`。

- **旧错例**：无。

- **验收**：恢复模式导入后不再为这些目录生成导入缓存；导出包内容不变。

- **未知与所需裁决**：无。

---

## CR-30 旧素材与历史场景归档（P3）

- **对应**：V-39、V-40、V-46

- **现象与影响**：非运行素材放在运行目录里，容易被误用。

- **准确位置**：
  - `assets/ui/skins/hud/`（7 张）
  - `assets/ui/themes/hud_structure_prototype.tres`
  - `scenes/tactical/hud/`（非 m2 旧场景簇）
  - `scripts/ui/hud/skill_shelf.gd`
  - 历史水面候选 `water-surface-v3/v4`、`natural-water-v2`、`shallow-water-v1`
  - 历史 UI 探索与工具场景 `scenes/playground/dashboard_variant_a/b/c`、`playground_battle_ui`、`viewport_angle_playground`、`viewport_angle_static_mockup`、`terrain_highlight_playground`、`map_token_runtime_playground`，以及 `scenes/dev/skillbar_playground.tscn`

- **证据**：本报告的引用检索。

- **判断**：归档。

- **参考与应提取特征**：无。

- **尺寸与透明/重复约束**：无。

- **前置依赖（旧 HUD 不能直接归档）**：现行 M2 仍继承或预加载旧 HUD 脚本，必须先解除：
  - `extends`：`scripts/ui/hud/m2/` 下的 `bottom_hud_composition`、`character_hud_view_data`、`end_turn_control`、`potion_button`、`skill_shelf`、`skill_slot_button`、`skill_slot_view_data`、`slot_button`、`slot_view_data` 都继承 `scripts/ui/hud/` 同名脚本。
  - `preload`：`m2/dashboard_view_adapter.gd:10-13` 与 `m2/action_resource_strip.gd:4` 预加载旧的 view data 脚本。
  - `ext_resource`：`scenes/tactical/hud/m2/equipment_hud_panel.tscn:3` 与 `m2/relic_grid.tscn:3` 直接使用 `scripts/ui/hud/` 下的旧脚本。
  - 旧 `scripts/ui/hud/skill_shelf.gd:6` 又预加载旧场景 `scenes/tactical/hud/skill_slot_button.tscn`，该场景 `:4` 引用 `hud_structure_prototype.tres`，所以 M2 间接依赖旧场景、旧主题与旧皮肤。

  解除方式：把被继承的行为并入 M2 脚本（或移到中性的共享目录并改名），逐个替换引用并跑全量回归，然后才归档剩余旧文件。

- **做法**：
  - 完成前置依赖后，确认没有测试依赖，再移到带 `.gdignore` 的归档或反例目录，保留 SHA 记录与用途说明。
  - `scripts/ui/hud/skill_shelf.gd` 的摘要被多个既有批次的 protected-state 记录，归档时建立新批次。

- **验收**：
  1. 在 `scripts/`、`scenes/`、`assets/ui/themes/` 中检索以下路径字面量（覆盖 `extends`、`preload`、`load` 与 `ext_resource`），现行文件中都没有命中：`res://scripts/ui/hud/` 下直接的 `.gd`（不含 `m2/`）、`res://scenes/tactical/hud/` 下直接的 `.tscn`（不含 `m2/`）、`hud_structure_prototype`、`skins/hud/`。
  2. 全量回归通过；运行目录中不再有非运行素材。

- **未知与所需裁决**：历史 UI 探索场景是否保留在仓库里，由用户决定。

---

## CR-31 生成提示词的共用风格条款（P2，产线，待 D-1）

- **对应**：P-07、V-01

- **现象与影响**：图标、纹章、头像的提示词写 `no pixel art` 或 `painterly`，地形写 `pixel-cluster`，彼此矛盾，也与 KB 裁决矛盾。

- **出错环节**：生成。

- **为何放过**：没有共用的风格条款。

- **准确位置**：
  - `assets/ui/skins/hud_mark_crest/source-manifest.json`
  - `dev_doc/ui-art-research/hud-character-panel-portrait/generation-prompt.md`
  - `dev_doc/ui-art-research/hud-myrmidon-portrait/generation-prompt.md`
  - `assets/prototype/battlefield_courtyard/source-manifest.json`
  - 图标提示词只在第 5 号交接包 `generation.md/json`

- **证据**：以上原文。

- **判断**：修改。

- **参考与应提取特征**：D-1 的裁决结果。

- **尺寸与透明/重复约束**：显示尺寸条款须写明 52 像素下的主体占比、明度对比、单一焦点高光与线条最小粗细。

- **做法**：D-1 裁决后，在 KB 记录带版本号的"风格条款"（色板与语义、光照方向、笔触与像素簇尺度、禁止项）和"显示尺寸条款"；每次生成都引用条款版本号；图标提示词原文补进仓库内的来源清单。

- **旧错例**：V-01 列出的提示词，按新条款会被判为不一致。

- **验收**：新生成记录都带条款版本号。

- **未知与所需裁决**：D-1。

---

## CR-32 结束控件阶段提示（P3）

- **对应**：V-13

- **现象与影响**：结束移动与结束回合只靠文字区分。

- **准确位置**：`scripts/ui/hud/m2/end_turn_control.gd:16-17`。

- **证据**：e01、e20。

- **判断**：保留沙漏，小修改。

- **参考与应提取特征**：沙漏上下两个三角的现有造型。

- **尺寸与透明/重复约束**：不改变控件尺寸与对称性。

- **做法**：用沙漏上半与下半的填充状态，或一个角标，区分两个阶段。

- **验收**：两个阶段的整屏不看文字也能区分。

- **未知与所需裁决**：无。

---

## CR-33 装备空槽提示（P3）

- **对应**：V-12

- **现象与影响**：三个空槽的用途不可辨。

- **准确位置**：`scenes/tactical/hud/m2/equipment_hud_panel.tscn`、`slot_button.tscn`、`potion_button.tscn`。

- **证据**：e01。

- **判断**：修改。

- **参考与应提取特征**：低对比的武器、防具、药水剪影。

- **尺寸与透明/重复约束**：剪影位于 40×40 与 32×32 的内图区，透明背景，按 2× 出图。

- **做法**：放入类型剪影；32 像素药水槽与两个 52 像素槽对齐排布。

- **验收**：1280 整屏中不看提示也能分辨三个槽的用途。

- **未知与所需裁决**：无。

---

## CR-34 最小动画反馈（P2，仅登记）

- **对应**：V-22

- **现象与影响**：单位只有位移，没有待机、受击、攻击反馈。

- **准确位置**：`scenes/tactical/Unit.tscn`（`PlaceholderTexture2D`）；`scripts/units/unit.gd`。

- **证据**：代码。

- **判断**：缺失，仅登记。

- **参考与应提取特征**：用现有静态棋子，以程序方式实现。

- **尺寸与透明/重复约束**：待机起伏 1–2 像素；受击闪白不超过 2 帧。

- **做法**：待机呼吸、受击闪白、攻击前冲。

- **验收**：运动采集中可见，且不产生闪烁（C7）。

- **未知与所需裁决**：是否排期由用户决定，本单不自动扩大制作范围。

---

## CR-35 剑气流线与阈值色（P2）

- **对应**：V-41、V-03

- **现象与影响**：流线不随剑气比例变化，剑气为 1 时也铺满整把剑；低段青色与高段粉红都不在色板内，在 51 突变（e29）。

- **准确位置**：
  - `scripts/ui/hud/m2/sword_resource_panel.gd:20-35`（`:35` 完整绘制流线）
  - `assets/ui/skins/hud_freeze/sword-{energy,flow}-{low,high}.png`

- **证据**：e26、e29。

- **判断**：保留剑体、裁切能量层和数字的设计；修改流线与配色。

- **参考与应提取特征**：绛红承担人物与物理攻击（VA-6 规格 `:52`）；VFX 拥有最高瞬时亮度。

- **尺寸与透明/重复约束**：沿用现有剑气面板的目标矩形。

- **做法**：
  - 流线与能量层按同一比例裁切，或按比例淡入。
  - 低段与高段改为同一色相族的明度递进，例如暗绛红到亮余烬色，而不是换一个色相。

- **验收**：
  1. 剑气 0、1、50、51、100 五档整屏。
  2. 剑气为 1 时流线长度不超过能量层。
  3. 色相差 ≤ 6°（同色相族）。
  4. 低段与高段仍然可以区分：两段在 720p 同帧整屏中的平均 L* 相差 ≥ 15，或在段落边界有清楚的形状变化；不能因为统一色相而让玩家看不出已越过阈值。

- **未知与所需裁决**：阈值与段落数量是设计库中的资源规则，保持不变；只改表现。

---

## CR-36 默认战斗镜头避让 HUD（已撤销）

- **对应**：V-42
- **撤销原因**：前提错误。`scripts/tactical/tactical_scene.gd:523` 已有避让 HUD 的镜头偏移 `(0, 130)`；棋盘与"心"纹章可见像素最近相距约 7.3 像素（1280），并不重叠。间距偏小的问题已作为 CR-11 的一条验收写入，不单独实施。

---

## CR-37 纹章回退图同源化（P3）

- **对应**：V-44

- **现象与影响**：回退图是旧的 Penpot 八状态线稿；一旦触发回退，画面风格突变（e34）。

- **准确位置**：
  - 回退绘制：`scripts/ui/hud/m2/marks_panel.gd:72-77`（图集未启用时按主题图标 `marks_<状态>` 绘制；说明见 `:4`）
  - 主题映射：`assets/ui/themes/hud_m2.tres:12-19`
  - 图片：`assets/ui/skins/hud_freeze/marks-000…111.png`

- **证据**：e34。

- **判断**：修改。

- **参考与应提取特征**：现行纹章图集。

- **尺寸与透明/重复约束**：278×56，透明背景。

- **做法**：用现行图集按 CR-08 离线渲染 8 张回退图替换旧线稿；回退时在日志中给出明确告警。

- **验收**：人为让图集加载失败，回退画面与正常画面风格一致。

- **未知与所需裁决**：无。

---

## CR-38 画廊显示现行棋子（P3）

- **对应**：V-45

- **现象与影响**：风格样例画廊展示旧预览板，而不是现行的 clean_v2（e35）。

- **准确位置**：`scripts/ui/playground/visual_style_playground.gd`；`assets/prototype/visual_style/sample_manifest.json` 的 `map_token` 样本。

- **证据**：e35、`anchor-audit-token.json`。

- **判断**：保留设计，修改局部。

- **参考与应提取特征**：`runtime_candidate`（clean_v2）的现有清单字段。

- **尺寸与透明/重复约束**：沿用画廊容器尺寸。

- **做法**：画廊增加现行棋子视图，或把旧预览板标为"历史批准样例"。

- **验收**：画廊整屏中能看到现行棋子。

- **未知与所需裁决**：无。

---

## CR-39 范围高亮配色与单次绘制（P2）

- **对应**：V-48

- **现象与影响**：移动范围亮蓝、攻击范围橙红、悬停亮黄、支援亮绿（支援只有代码依据，本次没有采集画面），全部是高饱和原色，不在色板语义内，在暗色地形与 HUD 中最抢眼；每格单独描边，相邻格共用的边画两遍，交界处更亮（e01、e37）。

- **准确位置**：
  - 颜色：`scripts/core/tactical_manager.gd:693-709`
  - 逐格绘制：`tactical_manager.gd:721-734`（每格一个 `Polygon2D` 加一条闭合 `Line2D`）

- **证据**：e01、e37。

- **判断**：修改。

- **参考与应提取特征**：
  - 色板语义（本审查提议，待 D-4 一并裁决）：移动沿用冷钢蓝 `#708493` 与亮阶 `#9FB2BF`；攻击用绛红族；支援或治疗需要单独的非红色，由 D-4 一并决定；悬停与选中用旧黄铜亮面。
  - 结构参考 CR-03：按区域外轮廓与内部共享边分别绘制，每条边只画一次。

- **尺寸与透明/重复约束**：填充不透明度 ≤ 0.30，保证地形仍可读；外轮廓 2 像素、内部格线 1 像素（720p）。

- **做法**：
  - 颜色从主题或数据读取，不在 `tactical_manager.gd` 中硬编码。
  - 把一组格子合并为一个多边形集合，只描区域外轮廓；需要显示内部格线时，每条共享边只画一次。

- **验收**：
  1. 移动、攻击、支援、悬停四态在 1280 与 1920 的同帧整屏中都能区分，并在红绿色弱模拟下仍能靠明度或描边区分。
  2. 范围内相邻格交界处的亮度不高于外轮廓（C6 的思路：边中点亮度不因重复绘制而升高）。
  3. 暗色地形（积水花园、荒草中庭）上仍能看清范围边界。

- **未知与所需裁决**：支援类高亮色依赖 D-4。

---

## CR-40 伤害预测浮窗样式（P2）

- **对应**：V-50

- **现象与影响**：浮窗是脚本自绘面板，黄铜边透明度只有 0.55，画面上读作灰边，与技能提示和 M2 面板不像一套；标题 10 像素，生命、目标名、命中、暴击 9 像素，720p 下偏小；面板高 104 像素而内容止于约 70 像素（e37）。

- **准确位置**：
  - `scripts/ui/damage_forecaster.gd:21-33`（尺寸与颜色）、`:137-180`（文字绘制与字号）
  - 宿主：`scripts/tactical/tactical_scene.gd:300-308`、`:363`

- **证据**：e37、e36（技能提示作为同屏对照）。

- **判断**：修改；信息结构保留。

- **参考与应提取特征**：技能提示卡片（`skill_bar.gd:87-100`）的暗紫底与黄铜细边；M2 人物栏的字号层级。

- **尺寸与透明/重复约束**：
  - 720p 下所有文字 ≥ 11 像素，伤害数值保持最大字号。
  - 面板高度按内容计算，底部留白不超过上下内边距。
  - 边框与底色取自主题，与技能提示一致。

- **做法**：改为读取主题样式，或至少与技能提示共用同一组颜色常量；字号按上面的约束调整；面板高度随内容变化。

- **验收**：
  1. 默认战斗与试战中，攻击、治疗、命中 0% 三种预测的 1280 与 1920 同帧整屏与局部。
  2. 浮窗与技能提示同屏时，边框与底色一致。
  3. 浮窗不遮挡目标单位本身与头顶数字。

- **未知与所需裁决**：无。

---

## 参考资料

**官方与作者一手资料：**

- [Godot：Importing images](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html)：mipmap、Fix Alpha Border、DPITexture
- [Godot：CanvasItem](https://docs.godotengine.org/en/stable/classes/class_canvasitem.html)：TextureFilter 各模式
- [Godot：Multiple resolutions](https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html)：像素美术建议 viewport 拉伸加整数缩放（D-1 选项 b）
- [Godot：StyleBoxTexture](https://docs.godotengine.org/en/stable/classes/class_styleboxtexture.html)：九宫格边距与轴向拉伸
- [FINAL FANTASY XIV 武士职业指南](https://na.finalfantasyxiv.com/jobguide/samurai/)：三资源位的状态表达，仅供研究
- [Noto CJK 许可](https://github.com/notofonts/noto-cjk/blob/main/Sans/LICENSE)
- [思源黑体许可](https://github.com/adobe-fonts/source-han-sans/blob/release/LICENSE.txt)
- Pedro Medeiros（Saint11）：[Consistency](https://saint11.art/blog/consistency/)、[Scaling Pixel Art](https://saint11.art/blog/scaling/)

**内部锚点（按 `sample_manifest.json` 与各来源清单的 SHA 绑定）：**

- `assets/prototype/visual_style/samples/ui_preview_final_v3.png`
- `assets/units/kensei/map_token_clean_v2.png`
- `assets/ui/portraits/*_generated.png`
- `dev_doc/ui-art-research/myrmidon-skill-icons/candidate-v3/zhanji-source.png`
- `assets/prototype/visual_style/samples/terrain_preview_final.png`（地形彩度与明度基准，平均 C* 约 5.2）
