# M2 运行时宿主合同

`HudM2RuntimeDashboard` 是正式 `TacticalScene` 的唯一底栏宿主。场景在 `$UILayer` 中创建一次该宿主，并以 `update_state(tactical_manager.get_dashboard_data())` 绑定状态；后续更新只重绑既有视图对象。

## 数据与显示边界

- `HudM2DashboardViewAdapter.build(state, icon_textures)` 是唯一载荷转换入口。人物、技能、行动资源和结束状态来自 `TacticalManager` 载荷。
- 正式图片映射由 `HudM2SkillIconCatalog` 从 `assets/ui/catalogs/hud_m2_skill_icons.json` 按真实 `skill_id` 解析。宿主每次应用当前技能清单后叠加调用方显式覆盖；未知技能保持缺图。宿主不读取 `p3-fixtures.json`，也不制造等级、资源、费用或库存数据。
- 装备与遗物统一保留通用空槽接口，不显示内容、类型轮廓或锁，也不产生槽位请求。有效武器载荷和对应图片不会改变当前空槽展示；原始载荷及战斗武器数据保留。药剂缺来源时仍为“暂无药剂信息”的不可用状态。职业资源按注册适用关系显示；只有 kensei 显示当前普通印记，myrmidon 保留真实剑气但隐藏印记，无资源单位不显示职业资源区。

## 输入与布局

- 宿主和组合背景使用 `MOUSE_FILTER_IGNORE`，五个可见区、行动条、人物检视卡和纯被动检视卡仍以各自控件的阻挡矩形接收输入。
- `get_content_top_y()` 与 `get_input_blocking_rects()` 返回当前全局 Canvas 坐标；没有可见内容时前者返回视口底边。
- 宿主关闭技能架数字键处理，使正式 `TacticalScene` 保有 1—4。鼠标技能与结束操作只有在当前玩家行动状态及可用性成立时才转发。
- `skills_visible` 决定是否绑定技能卡；敌方与无技能状态保留技能区外框。无结束操作时，结束区也保留外框，仅隐藏内部按钮与文字。
- 纯被动说明卡固定 260 宽、12px 字号和上下 12px 内边距；内容超过短说明时仅向上增加高度，短说明维持 104 高。

## 集成责任

正式 `TacticalScene` 将 `dashboard_state_changed` 连接到同一 M2 实例，并把保留的六个请求信号连接到现有 manager 请求方法。技能架自身关闭快捷键处理，数字键统一由场景按 `active_capable` 顺序分发，避免双发。

运行时测试与原生捕获直接读取 `scene._bottom_dashboard` 和正式 manager，不额外挂载宿主或隐藏旧栏。旧组件文件保留，但正式场景树不实例化它。

`DamageForecaster.get_visual_size()` 从面板与三角绘制常量返回完整视觉占用。场景保存最近的世界锚点；forecast 数据变化时更新内容和头顶数字，可见期间仅按相机、窗口与当前 M2 阻挡顶部重排位置，并保持 8 px 间距。
