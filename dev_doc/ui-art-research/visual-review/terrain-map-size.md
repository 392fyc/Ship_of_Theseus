# 正方形地图尺寸

## 当前功能

地图仅支持正方形，边长为 10 至 25 的整数。默认 10×10；工作台右上只设置一个边长，点击“调整大小”生效。边长输入、导入、保存和正式试战使用同一范围。

- 扩大：保持原坐标的地形、铺石和外观变体，新格补平原。
- 缩小：保留左上原点开始的新方形区域，裁去其余地形及附属外观。
- 撤销：一次调整对应一步撤销，可恢复被裁掉的全部内容；再次应用相同边长不增加撤销记录。
- 加载与清空：加载文件同步边长显示，清空保留当前尺寸；原有 10×10 文件继续有效。
- 试战：按当前尺寸显示并操作正式棋盘；返回编辑后保留地图和撤销记录。

扩大只添加空地，不自动扩展原地图的建筑、道路或场景布局。25×25 的全图视野会缩小格子；正式试战仍可使用既有缩放、拖动和“居中”。

## 实现与边界

`TerrainCatalog.validate_map` 验证完整方形地图。接壤样图的 `validate_layout` 只用于小片段检查，作者入口均执行完整地图校验。

输入框采用 [Godot 4.6 SpinBox](https://docs.godotengine.org/en/4.6/classes/class_spinbox.html)，点击按钮时调用 `apply()` 提交正在编辑的文本。保存与加载保留铺石坐标顺序，避免 JSON 对象键排序导致往返数据顺序变化。

原 `terrain-kit-approved.json` 保持原样。Catalog 承担尺寸校验和视觉参数两种职责：尺寸校验按用户明确要求更新；数据路径和三个视觉函数仍与批准版本逐项比对，依据记录在 `terrain-catalog-visual-scope.json`。其他 27 项已批准来源继续执行整文件摘要检查。

## 验证入口

```powershell
./tests/run_terrain_runtime_validation.ps1 -GodotPath <Godot-4.6.3-console> -OutputDirectory <新的仓库外绝对目录>
```

专项覆盖真实边长按钮、10/25 边界与中间值、裁边撤销、扩大后边角绘制与取样、保存加载、拒绝矩形/越界/坏矩阵，以及 1280×720 和 1920×1080 下 25×25 的正式移动和返回编辑。统一入口同时运行原有地形与战斗回归。

本轮完成条件是上述功能与原有绘制通过新运行检查、原生画面检查和独立审查。结果及原始图见 `terrain-map-size-receipt.json` 与 `reviews/2026-09-27/terrain-map-size-v1/`。

最终运行批次 `final-v3` 的尺寸专项 79 项、正式试战 89 项、编辑往返 19 项、原工作台 28 项和地形库 166 项均通过，统一入口退出码为 0。原水岸、水深、邻接和战场回归继续通过；9 张固定地形图与批准版逐字节相同。

[10×10 工作台](reviews/2026-09-27/terrain-map-size-v1/map-size/map-size-10-editor-1280x720.png) · [25×25 工作台](reviews/2026-09-27/terrain-map-size-v1/map-size/map-size-25-editor-1280x720.png) · [1920 宽工作台](reviews/2026-09-27/terrain-map-size-v1/map-size/map-size-25-editor-1920x1080.png) · [25×25 正式试战](reviews/2026-09-27/terrain-map-size-v1/map-size/map-size-25-battle-1280x720.png)

证据清单逐项记录原始文件摘要。与既有证据完全相同的 40 张图通过 `stored_as` 引用原文件，其余文件逐字节归档，避免重复保存相同截图。
