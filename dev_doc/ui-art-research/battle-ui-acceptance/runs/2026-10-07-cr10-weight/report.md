# CR-10 字重与行高追加修正结果

## 当前结论

本轮追加修正的实现、Windows 字体外观独立验收与发行包检查均通过。实施提交为 `b0e1ca919c4bcfa3aa16fb87872f9aa986e376ff`，分支为 `codex/ui-ux/cr10-chinese-font`。按用户明确委托，Codex 在三档原尺寸对照上选定 **Medium 正文、Bold 标题**。用户整体视觉批准状态单独记为 `not_recorded`；本记录不代替该批准，也不宣布基础战斗 UI 或原 P0/CR-01 Milestone 完成。

## 改动与验证

|验收项|结果|证据|
|---|---|---|
|固定来源、确定性生成、覆盖和许可证|PASS|`font-source-independent-review.json`；Regular 原件保持，新增 Medium、Bold 与同一上游提交和许可证绑定。|
|正文与标题字重|PASS，受托选择 Medium/Bold|`weight-selection.json`；Windows 三档左右对照，Medium 与现有拉丁 Semibold 更协调，Bold 保留标题层级。|
|三档同帧图像与真实字重|PASS|`frame-and-source-verification.json`；24 张整屏、24 份状态、66 张精确局部；逐图验证实际字体数据 SHA256。|
|Windows 外观、行高和文字边距|独立 PASS|`windows-visual-independent-review.json`；五种组件文字完整，外层边框余量均达到 720p/1080p/1440p 的 2/3/4px 要求。|
|批准布局、字号与剑气数字|PASS|`presentation-independent-review.json`；面板坐标和尺寸、字号保留，冻结数字仍无中文回退，度量保持。|
|运行回归|PASS|独立字体运行检查 failed=0；既有 HUD dashboard 117 通过；技能操作 175 通过。|
|Windows 发行包|PASS|`windows-package-verification.json`；真实 PCK 的字体导入与字体链检查、7 份许可文件、包内启动检查通过。未发布。|
|C8 采集配置|PASS|`c8-raw-output.json`。|
|C4 头像贴合|FAIL，仍属 CR-24|`c4-raw-output.json`；24 张均有顶边缝，三档为 1/2/2 行，其余边缘为 0。本轮没有修复头像。|

### 五个组件的最小文字外框余量

|原生分辨率|人物栏|Turn Order|技能提示|属性卡|伤害预测|要求|
|---|---:|---:|---:|---:|---:|---:|
|1280×720|12|7|13|4|7|≥2px|
|1920×1080|18|10|19|6|11|≥3px|
|2560×1440|25|13|25|9|14|≥4px|

数值来自独立审查的原图像素检查，阈值法有约 1px 的栅格边界误差，完整方法和限制见审查 JSON。Turn Order 内部职业色块没有描边；文字到其填色边缘的 1/2/1px 作为范围外观察保留，不当作外层面板边框。

## 采集与来源

批次为 `<仓库外证据根>/windows-attempt4`，逐文件 SHA256 见 `evidence-manifest.json`。使用 Godot 4.6.3、Windows 显示服务、NVIDIA GeForce RTX 3070 Ti 和 Compatibility，正式 `courtyard` 10×10 进入 `TacticalScene`。基础剑士无印记；只在测试副本中把一个既有敌方出生点移至合法相邻格以展开预测文字。

窗口在屏幕外且 `no_focus`，没有系统鼠标移动；内部输入展开界面。该批只验字体像素和布局，不验物理鼠标、音频或性能。原 PNG 与 Window 尺寸一致；Viewport、Texture API 和 Image 的实际尺寸分别保留，未把不同 API 的数值混为一谈。

采集前冻结逐文件源字节，采集后核对未变；`committed-candidate-binding.json` 将 20 项实施文件与提交绑定。字体和来源清单字节完全相同；部分文本仅存在 Git 规定的换行归一化。三个独立审查分别负责字体来源、呈现与采集代码、Windows 原图外观；实现者未自行批准。

发行包依据同一实施提交构建。包内无窗口启动检查仍进入既有 8×8 `test_arena`，只用于包完整性，不能作为地图约束验收或 CR-11 已完成的依据。本次三档视觉批次使用合法 10×10 场景。

## 当前边界与剩余事项

- CR-06 的头顶伤害/血量及相邻名牌遮挡、CR-40 的避让要求已另行登记，行为未修复。
- G4 v2 候选早于 CR-10，其截图不评价本轮字体；G4 原始证据补取另行记录。
- CR-24 与 TERRAIN-READABILITY-01 均未修复；独立 GPU、音频、性能专项尚未完成。
- 用户整体视觉批准、发布与合并均未记录；按指令仅保留本地提交。

Task 的候选交付和 Milestone 状态分开记录，结构化结果见 `task-receipt.json`。
