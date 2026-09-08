# 职业资源显示接入

RESOURCE-INTEGRATION-R1 将已批准 A 方案接入 M2，并由正式 `TacticalScene` 直接创建唯一 `HudM2RuntimeDashboard`。逻辑画布为 1280×720，职业区为 `[32,540,366,56]`，五区和行动锚点保持既有几何。

`TacticalManager.get_dashboard_data()` 在原有库存字段之外提供 `class_resource_display`：`class_id` 来自当前显示单位的 `unit_id`，印记容量、剑气分档比例来自该单位解析后的运行字段。低段判断保持 `current * 100 <= maximum * pct`，上段严格大于；显示层不更改资源获取、消费、上限或属性效果。

`HudM2DashboardViewAdapter` 输出 `class_resources`，通过 `HudM2ClassResourceHost` 选择资源子视图。当前 `sword` 子视图读取精确 current/max，使用连续比例填充；十等分只属于皮肤刻度。合法资源独立于玩家能否行动和人物悬停存在。数值缺失、非整数、非有限值或无资源哨兵不生成显示库存，缺阈值只隐藏分档提示。

`assets/ui/catalogs/hud_m2_class_resource_profiles.json` 只保存设计库的注册适用关系：myrmidon、kensei、sword_immortal 均有剑气，只有 kensei 显示印记。来源为 SoT-fyc-space 提交 `3a71ade3cac109dbdda8a90d0e47f04232f83b9f` 的 `snapshots/resources.json`，完整规范化 SHA256 为 `526d654f5b1d2490e2f9674a7486e7cc0547c5ca10d7d86c4128bab97813a0da`。未知职业有合法运行 qi 时以 `runtime_qi_only` 来源继续显示数值，印记隐藏。

普通印记按心、道、势的种类顺序紧凑排列，右侧保留空槽。当前输入是种类布尔状态；`instance_id` 和 `special_marker` 保持空值。重复印记、获取顺序及纳刀印尚无运行实体来源，需要独立玩法任务提供真实状态后再接入，不能从数量或布尔字典推断。

`assets/ui/layouts/hud_m2_class_resource.tres` 保存 A 显示坐标。`HudM2SharedFrame` 的 `panel`、`collapsed`、`panel_resources`、`collapsed_resources` 对应行动与职业区的四种可见组合。新增两个整框材质和 `mark-slot.png` 来自同一获批 Penpot 材质，来源节点与 PNG 散列见资源皮肤目录的 `source-manifest.json`。绘制、命中和全局矩形采样使用同一外轮廓，两凸起之间的空白及资源肩角透传。

`set_skin_theme(Theme)` 同时替换框、印记、文字和剑气语义颜色；`null` 恢复默认 Theme。新增配色、字号与印记 StyleBox 均在 `HudM2ClassResource` 主题类型下。材质变更不重建技能槽或清除焦点，动态数值和文字不烘入 PNG。

`HudM2PopupPlacement.place_above()` 处理逻辑矩形避让，人物卡留 14 px，技能卡留 8 px。A 人物卡底边为 y=526；与资源横向相交的最左技能说明底边为 y=532。卡片按文本高度向上增长。普通技能和纯被动的鼠标/焦点说明均使用受控 `InspectionPanel`，`tooltip_text` 保留文本兼容访问，`_get_tooltip()` 返回空以关闭默认弹窗。实际鼠标经过触发区和浮卡间的竖向过渡区域时保持检视，离开过渡区域后关闭。纯被动激活条件仍由既有 `can_activate()` 拒绝。

资源和所有实际可见说明卡由 `get_input_blocking_rects()` 汇总到全局坐标，`get_content_top_y()` 消费同一清单。人物卡中不放第二份资源，装备及八个遗物槽继续保持预留空槽。

T1 定向验证脚本为 `test_hud_m2_class_resources.gd`、`test_hud_m2_dashboard_view_adapter.gd`、`test_hud_m2_character_hover.gd`、`test_hud_m2_runtime_dashboard.gd` 和 `test_hud_m2_skin_theme.gd`。新鲜命令、结果和候选散列保存在本任务回执；实现者不作独立批准。

正式技能图片由 `assets/ui/catalogs/hud_m2_skill_icons.json` 按真实 `skill_id` 映射到既有获批图片。runtime 每次从当前技能清单重新解析，再叠加显式测试覆盖，因此切换清单不会保留旧纹理，未知技能继续使用缺图表现。主/被动、可用性和数字键角标仍完全读取 manager 的 `is_passive`、`active_capable` 与 `available`。

正式入口、注入入口、停止战斗与再入场都消费场景自身的唯一 M2 实例。预测器使用包含下方三角的完整尺寸，并在可见期间随相机、窗口和人物/技能检视卡位置实时避让；内容及头顶数字只在 manager 的 forecast 更新时重建。

## T3 原生捕获

`tests/capture_hud_m2_resource_integration.gd` 只在收到 `--capture-hud-m2-resource-integration` 时执行捕获。无此参数时立即以成功状态退出，便于 Main 做脚本加载检查；捕获参数与 headless 同时出现时会失败，因为完整 PNG 必须来自实际窗口 viewport。

三张 `real-player-normal-*` 从 `application/run/main_scene` 直接实例化，保持场景默认 `run_injected=false` 和默认战斗配置，只调整原生窗口尺寸与鼠标位置；完成后释放该场景。其余交互矩阵另行实例化同一正式场景，并通过 `TacticalScene` 既有注入入口生成一个玩家剑圣、一个无职业资源敌人和一个剑圣敌人。两类正式图都只读取场景自身的 `_bottom_dashboard`。鼠标和按键通过 viewport 输入进入正式处理链；主图不调用 `set_icon_textures()` 或 `update_state()`，也不直接修改 Unit。人物检视、最长真实纯被动说明、敌方检视和返回玩家记录实际事件步骤与最终 manager 载荷。敌方剑圣只用于观察“有资源、无玩家行动”的正式检视状态，配置原因写入相应 case。

展示边界在正式场景释放后使用独立 `HudM2RuntimeDashboard`，并明确标为 `data_kind=display_boundary_fixture`。B01—B21 覆盖剑气 0、1、满值、阈值等号与上方、动态上限，myrmidon 仅剑气，kensei 0—3 个普通印记，无资源，0/7 技能，3 点行动容量，以及资源/行动四种外框组合。B17 从每个迅捷图形的 `get_swift_points()` 读取实际三个绘制点，记录三条边长和面积，并核对三边相等且面积非零；控件盒尺寸不作为三角比例。夹具只表达当前普通布尔印记；重复印记、获取顺序、离形重复和纳刀印不列为运行能力。

运行前由 Main 生成 `.omc/ui-m2/resource-integration-r1/source-candidate.json`，字段为 `candidate_sha256`、`head` 和 `files[{path,sha256}]`。脚本在捕获开始和结束按工作区原始字节复核每项 SHA256；当前候选捕获还要求清单 HEAD 等于实时 `git HEAD`。`--post-commit` 将输出改到 `evidence/post-commit/`，实时记录新提交 HEAD，同时继续要求源码文件与冻结候选散列一致。

Main 使用以下命令执行。脚本会在布局、载荷、宿主身份和节点矩形连续两帧一致后，从 `root.get_texture().get_image()` 保存完整物理尺寸 PNG；1920×1080 和 2560×1440 不通过逻辑画布放大伪造。每张全图另从同一 `Image` 保存连接局部，并在 `native-capture.json` 中记录父图散列和物理裁剪矩形。

```powershell
& $hudGodot --path . --script res://tests/capture_hud_m2_resource_integration.gd -- --capture-hud-m2-resource-integration
& $hudGodot --path . --script res://tests/capture_hud_m2_resource_integration.gd -- --capture-hud-m2-resource-integration --post-commit
```

`native-capture.json` 顶层记录引擎版本、DisplayServer、引擎参数与 `OS.get_cmdline_user_args()` 提供的捕获参数、场景路径、候选与实时 HEAD、所选 A 画布来源、`case_count`、逐 case `passed`/`failed` 和结果。当前矩阵应为 36 个 case，通过数与失败数只按这些 case 计算；启动或候选错误另记 `run_failure_count`。每个 case 包含真实宿主 instance ID、逻辑到 viewport 的变换、实际节点矩形、前提、动作、原始载荷及摘要、可观察断言、PNG 物理尺寸和 SHA256。失败以非零状态退出，已存在证据不会因清理操作被删除。
