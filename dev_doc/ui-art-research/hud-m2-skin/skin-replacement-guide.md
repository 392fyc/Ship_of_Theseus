# M2 HUD 样式替换

默认入口是 `assets/ui/themes/hud_m2.tres`。当前默认采用用户通过的 FE-FRAME-R1 黑紫织纹与旧黄铜边框，材质由 Penpot 原生导出 PNG、Godot StyleBoxTexture 和共享框样式资源组合；外观资源与人物、技能、职业费用和输入逻辑分别维护。完整底框保留固定五区、共享分隔和圆滑两肩。

## 替换整套主题

先复制默认 Theme 为自己的 `.tres`，在 Godot Theme 编辑器中修改样式。修改现有默认文件会更新所有使用默认皮肤的 M2 HUD；使用单独的 Theme 可以保留多套外观。

运行时给组合或 `HudM2RuntimeDashboard` 设置同一接口：

```gdscript
var new_skin: Theme = load("res://assets/ui/themes/my_hud_skin.tres") as Theme
dashboard.set_skin_theme(new_skin)

# 回到项目默认样式。
dashboard.set_skin_theme(null)
```

`get_skin_theme()` 返回当前主题。切换在原有控件上发生，后续新增的技能槽和行动点继承当前主题。HUD 的固定布局、焦点、载荷和信号无需随素材变化重写。

## 主要样式入口

| Theme 类型 / 名称 | 覆盖范围 |
| --- | --- |
| `HudM2SharedFrame / panel` | 含行动资源抬升区域的完整共享底框。 |
| `HudM2SharedFrame / collapsed` | 无行动资源时的底栏框。 |
| `HudM2SlotFrame / panel` | 主动技能与通用占用槽的外框。 |
| `HudM2EmptySlotFrame / panel`、`HudM2RelicFrame / panel` | 52px装备空槽与40px遗物空槽；显示状态不耦合职业。 |
| `HudM2Panel / panel` | 人物/技能浮卡和独立组件的面板框；完整组合的五区使用共享框。 |
| `HudM2PotionFrame / panel` | 血瓶入口框。 |
| `HudM2InfoBorder / panel` | 人物信息的可替换入口；默认透明，让常驻信息与整体底栏统一。 |
| `HudPortraitFrame / panel`、`HudM2PortraitBackground / panel` | 头像外框和背景。 |
| `HudM2ExperienceTrack / panel`、`HudM2ExperienceFill / panel` | 经验槽与填充。 |
| `HudM2SurvivalTrack / panel`、`HudM2HpFill / panel`、`HudM2ShieldFill / panel` | 生命与护盾槽。 |
| `HudM2PassiveContour`、`HudM2PassiveShadow`、`HudM2PassiveBottom`、`HudM2PassiveRight`、`HudM2PassiveInner` | 纯被动的内凹轮廓和明暗边，名称均为 `panel`。 |
| `HudM2EndFrame / panel` | 结束行动框。 |
| `HudM2Selection / panel`、`HudM2PortraitFocus / panel` | 选中和焦点状态。 |

其他颜色、字体、角标底板、禁用和冷却样式继续使用同一 Theme 中的语义类型。行动类型颜色与灰色状态轮廓、HP/SH 的含义应保留；费用接口始终为右下纯数字，不随职业更换皮肤结构。

结束按钮的沙漏可由 `HudM2 / icons / end_emblem` 替换；未设置图片时使用原生线条。其颜色来自 `HudM2 / colors / end_emblem`。

## 接入新边框贴图

在相应 Theme 类型的样式项中，将 StyleBoxFlat 换成 StyleBoxTexture，指定新纹理。可以替换同一材质族的多个语义槽框。现有空槽铜边更暗，纯被动使用独立的内凹边纹理。

配置时区分两类边距：

- **纹理分割边距**决定九宫格中哪些边角保持尺寸，按新素材的边缘厚度设置。
- **内容边距**决定内容可用空间。沿用当前角色对应值，避免贴图换好后，图标、文字和按钮的最小尺寸发生变化。

普通槽四边内容边距为 6px，血瓶为 5px，人物信息与共享框为 0。头像纹理向上扩展 2px 保留获批装饰，图像锚点保持不动；被动轮廓纹理向四边扩展 2px，`draw_center=false` 让上层轮廓不盖住技能图像。场景中的图标和文字锚点保持固定。完整 HUD 会让子组件继承根 Theme；单独使用子场景时仍有默认 Theme，如需继承外部父主题，在加入树前将该实例的 `theme` 设为 `null`。

技能槽会显示为 64px 或 56px，装备为 52px，遗物为 40px，血瓶为 32px。新纹理应在这些尺寸下保持清晰，并给当前内容留出完整空间。纯被动仍使用内凹样式，不能只靠灰化区分。

共享框的 `panel` 资源绘制范围是逻辑坐标 `(32,550,1216,154)`，`collapsed` 是 `(32,596,1216,108)`。共享样式的 `material_texture` 接收整块纯材质贴图；设为 `null` 时采用 `background_color`、`border_color`、`border_width` 的原生后备绘制。也可以整体替换成相应 StyleBoxTexture，但贴图必须保留行动区两侧的透明空间和共享分隔位置。不得在共享贴图烘焙槽框、图像、文字或数字，0—7个技能由动态槽位独立绘制。整体 UI 按同一比例缩放，内部内容锚点固定。输入区域按布局几何维护，不能由新贴图随意扩大。

## 验证与来源

接入新素材后，应检查默认、悬停、焦点、冷却、不可用、纯被动、人物卡、0—7 技能与三档分辨率，并执行换肤/切回验证。定向入口为 `tests/test_hud_m2_skin_theme.gd`；原生入口为 `tests/capture_hud_m2_skin_theme.gd`，当前材质额外传入 `-- --capture-hud-m2-fe-import`，输出到 `dev_doc/ui-art-research/hud-m2-fe-import/evidence`。

当前素材来源及摘要在 `assets/ui/skins/hud_m2_fe/material-manifest.json`；本次实现证据位于 `../hud-m2-fe-import/evidence/`，最终验收状态以本任务独立审查和回执为准。本目录 `evidence/` 保存先前换肤接口的历史证据。用于验证 StyleBoxTexture 的彩色纹理属于测试夹具，不作为正式美术素材。

接口依据：[Godot Theme](https://docs.godotengine.org/en/4.6/classes/class_theme.html)、[StyleBoxFlat](https://docs.godotengine.org/en/4.6/classes/class_styleboxflat.html)、[StyleBoxTexture](https://docs.godotengine.org/en/4.6/classes/class_styleboxtexture.html)。
