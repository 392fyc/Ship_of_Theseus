# GHV-7 内框安全净距证据

状态：GHV-7 布局修正与 GHV-8 代表图刷新均已通过独立复核，等待用户视觉审核。

## Milestone Tasks

1. 根因定位与固定几何批准：完成。
2. 测试先行的场景修正：完成。
3. 18 张截图刷新与主任务检查：完成。
4. 独立只读审查：完成。

## 根因与修正

外围框的可见边缘约占 6 像素。旧布局按组件原始边界放置子控件，人物、装备和血瓶仅内缩 8 像素，遗物网格上下仅内缩 6 像素，导致可见透明净距分别只剩约 2 像素和 0 像素。

当前统一按至少 10 像素原始内缩计算，使内框和外围框的可见边缘之间至少留出 4 像素透明区域。自动测试直接读取运行时 `Rect2`，覆盖人物画像、信息区、两件装备、血瓶、遗物网格和全部 8 个遗物槽。

## 测试证据

- RED：旧布局在新增几何合同下分别为人物 49/4、装备 16/8、遗物 48/12。
- GREEN：修正后分别为人物 53/0、装备 24/0、遗物 60/0，合计 137/0。
- 相关回归：22 个脚本，1210 项断言通过、0 项失败；没有 `SCRIPT ERROR` 或节点缺失输出。
- 独立复核：使用 Godot 4.6.3 重跑三个定向测试为 137/0、22 个相关脚本为 1210/0，并逐张检查四张代表性原图；完整度 100%，无阻塞项。

## 代表性审核文件

- 人物画像：`../../hud-ghv2-character-slice/evidence/hud_character_slice_1280x720.png`，SHA-256 `c627f03821bb3046ebe06a2c30412440a5bb1dfe84f437dd352522e0f69b70b7`。
- 装备、血瓶与遗物：`../../hud-ghv3-utility-slice/evidence/hud_utility_slice_1280x720.png`，SHA-256 `db77135c1fb3fc08eee77e0c3f937f633bd2dfa72402a42350ec4d17946e74b8`。
- 默认五技能完整底栏：`../../hud-ghv4-bottom-composition/evidence/hud_bottom_composition_5skills_1280x720.png`，SHA-256 `fc33d4bf4c9c078a5cb8cdbe89f44691269019de444ea18af8ef0f21ad0e7971`。
- 动态状态二：`../../hud-ghv5-bottom-dynamic-states/evidence/hud_bottom_dynamic_capacity_2_early_lock_1280x720.png`，SHA-256 `8460746fb04b4a6908bc30370e110d255e9e82ff90ccc9d85864581e4180d3bb`。

本批次共刷新人物 3 张、工具区 3 张、完整组合 9 张、动态状态 3 张，共 18 张。没有调用图像生成、外部 API 或购买素材。
