# CR-10 中文字体打包候选

## 范围与当前实现

该候选为 Godot 普通主题、M2 HUD 主题和直接自绘文字提供随包字体回退。原有拉丁字族与 IBM Plex Mono 数字字族继续作为主字体；CJK、符号和 emoji 只在主字体缺少相应字形时参与回退。系统字体回退已在字体导入默认值、随包字体和运行时字体链中关闭。

默认主题通过 `SoTFontSetup` 将 ThemeDB 原默认字体副本设为普通主题字体并挂接包内回退链。M2 的 CJK/符号/emoji 字体资源使用独立 MSDF 缓存，以适配既有 `Control.scale`。冻结剑气面板只绘制数字，仍使用原 Source Sans Pro Semibold 栅格字形和度量，不挂中文回退。M2 数值标签使用 IBM Plex Mono 主字族及中文回退。

字符、图标用途和界面结构保持原有配置。Noto Emoji 子集是单色矢量轮廓，所需 emoji 不再依赖本机 emoji 字体；这两处 emoji 的最终外观仍须通过实际画面审查。CR-18 样式改版与 CR-22 图标改版不属于本候选。

## 字体来源与许可

本轮补充 Medium（500）与 Bold（700），与 Regular 使用同一个固定上游提交和同一份 OFL 许可证。`LICENSE.txt` 保留上游原始字节；每个新增字重在 `source.json` 中分别绑定该许可证摘要。正文使用 **Medium**，对应既有拉丁 Semibold；标题使用 **Bold**，Regular 保留作对照。用户已授权 Codex 在图上选定正文；选择依据是 `../runs/2026-10-07-cr10-weight/` 的 Windows 三档对照。生成清单中的 `weight_candidate`/`not_approved` 仅记录生成阶段，实际视觉裁决与独立审查另见运行记录。

每个字体目录内的 `source.json` 记录固定上游提交、源字体 URL、源 SHA-256、生成子集 SHA-256、字节数与字体工具版本；`LICENSE.txt` 保留上游 SIL Open Font License 1.1 文本。目录内的 `.gitattributes` 禁用换行转换，使许可证、清单和字体在 Windows 检出后保持这些精确字节。

| 包内字体 | 固定来源 | 原件 SHA-256 | 子集 SHA-256 | 子集字节数 | 许可证 SHA-256 |
| --- | --- | --- | --- | ---: | --- |
| `NotoSansCJKsc-Regular-subset.otf` | `notofonts/noto-cjk` `Sans2.004`, `523d033d6cb47f4a80c58a35753646f5c3608a78` | `2c76254f6fc379fddfce0a7e84fb5385bb135d3e399294f6eeb6680d0365b74b` | `241e7ebc37926a6a893771a8d0f2f375e385b44d9e8d400553402968a111531b` | 3,408,020 | `6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2` |
| `NotoSansCJKsc-Medium-subset.otf` | 同一 `Sans2.004` 提交 | `ca094f6b0001fb048ca39ddd797a0cdb0179e1e55c6561e111c49c3e6a61d7b7` | `668e9acbda2f004f5145f14c19d3bb3fac0dc2a6506dab78fe87a76e7ce7f101` | 3,409,012 | 同上 |
| `NotoSansCJKsc-Bold-subset.otf` | 同一 `Sans2.004` 提交 | `b5f0d1a190a7f9b43c310a8850630af12553df32c4c050543f9059732d9b4c0a` | `78aeec072742f4aa8feebb4ab845d59e76b15ded3bccdfb6da0a11115abba8a4` | 3,497,576 | 同上 |
| `NotoSansSymbols2-Regular-subset.ttf` | `notofonts/noto-fonts`, `ffebf8c1ee449e544955a7e813c54f9b73848eac` | `630846d528dbe4c4981370a4d0a9475a1fd1491a129bb411f8e157cdb5de13c6` | `e3fba50bf66cf9f4475629b2840f27df8b0a6bde04743007c6e263ebbcba2bce` | 6,664 | `0dab92d0544f7b233403f14b84a663bdbfa746982eda629e7f4f9ffe1b036feb` |
| `NotoSansSymbols-Regular-subset.ttf` | `notofonts/noto-fonts`, `ffebf8c1ee449e544955a7e813c54f9b73848eac` | `8f02f31959bbdf6061547a188248e13f84dc5fdd940326ec494675f453f072bb` | `029bbe8952f5e1270dbfcbf6f29fa43e2b8158a5b87e4fc80d695fefa7d1cd6f` | 6,508 | 同上 |
| `NotoEmoji-Regular-400-subset.ttf` | `google/fonts`, `8b0a1d0f5983c89bc2b93f1b5fb55f9e252744b5`, `wght=400` | `de6c18832938afc99caf132b39d6a30a19bac7f2e812e28db2535b4608d27551` | `2e1a067b485a7a8f8b8459405d712ab0465f1cb2de971b928471d815d20dbe90` | 2,812 | `500bb1ccf43df7bbb522112f9133a52b16e1c35e809632f5d8609b179152de5b` |

保留字体名称、版权和许可元数据。各上游清单均记录没有 Reserved Font Name 声明。上游完整字体不进入仓库；仓库只包含生成子集、来源清单和许可证。

## 覆盖与确定性重建

`tests/claude_review/build_cr10_font_subset.py` 固定上游原件 SHA-256 和 `fontTools 4.66.1`。生成前先验证所有原件和许可证摘要，并验证 CJK、Symbols2、Symbols1、Emoji 的联合 cmap 能覆盖完整需求；任一缺字都会终止生成。随后为每份子集固定 Unicode 输入、表顺序和可变字体实例，并重复构建比较摘要。

需求集包括完整 GB2312 编码字符集 7,445 个码点，以及当前游戏数据、场景、脚本、资源和项目配置字符串中提取的码点；并集共 7,476 个不同码点。CJK 子集覆盖 7,460 个码点，其中包含全部 GB2312 码点；Symbols2 覆盖 12 个码点，Symbols1 覆盖 2 个码点，Emoji 覆盖 2 个码点。运行时检查验证主题和自绘使用的完整回退链覆盖整个并集。

在 PowerShell 中设置 `CR10_FONT_SOURCE_DIR` 指向六份已按来源 SHA 核验的上游原件所在目录，然后运行：

```powershell
$fontSourceRoot = $env:CR10_FONT_SOURCE_DIR
& python tests/claude_review/build_cr10_font_subset.py `
  --source-font (Join-Path $fontSourceRoot 'NotoSansCJKsc-Regular.otf') `
  --medium-source-font (Join-Path $fontSourceRoot 'NotoSansCJKsc-Medium.otf') `
  --bold-source-font (Join-Path $fontSourceRoot 'NotoSansCJKsc-Bold.otf') `
  --symbols2-source-font (Join-Path $fontSourceRoot 'NotoSansSymbols2-Regular.ttf') `
  --symbols-source-font (Join-Path $fontSourceRoot 'NotoSansSymbols-Regular.ttf') `
  --emoji-source-font (Join-Path $fontSourceRoot 'NotoEmoji-variable.ttf')
```

本候选生成结果：`gb2312=7445`、`game_strings=1232`、`unique=7476`、`symbol_fonts=2`、`emoji_glyphs=2`、`deterministic=true`。CJK 子集为 3,408,020 字节，摘要为 `241e7ebc37926a6a893771a8d0f2f375e385b44d9e8d400553402968a111531b`；Emoji 静态实例为 2,812 字节，摘要为 `2e1a067b485a7a8f8b8459405d712ab0465f1cb2de971b928471d815d20dbe90`。详细符号分配与全部 Unicode 清单见各目录 `source.json`。

## 运行时与发行检查

用 Godot 4.6.3 控制台版运行字体覆盖检查：

```powershell
godot --headless --path . --script res://tests/claude_review/cr10_font_runtime_check.gd
```

检查实际普通 `Label.get_theme_font("font")`、M2 默认文本、IBM Plex Mono 数值标签、冻结数字以及各导入 `FontFile`。检查项覆盖包内字体联合字形、系统回退关闭、回退顺序、资源循环、原 Latin 字形保留及冻结数字原度量。冻结 Source Sans Pro 32px 指标仍为 ascent 32、descent 9、height 41，`100` 宽度为 49，与原始字体一致。

运行检查输出 `CR10_TEXT_METRICS`。本轮 size 9 的普通主题链为 ascent/descent/height `11/3/14`（primary-only `10/3/13`）；M2 正文链为 `10.5/2.813/13.125`（primary-only `9.75/2.813/12.563`）。size 12 的技能提示正文与标题高度均为 `17.5`。实际 API 的 ascent、descent 与 height 分别记录，不能假定其舍入结果总能相加。

行高修正只规范独立补充符号字体副本的缓存 ascent/descent，以相应 CJK 主字体为参照。普通栅格缓存覆盖当前 8、9、10、11、12、13、14、16、20 号字；M2 MSDF 使用字体自身的固定缓存尺寸（48），然后由 Godot 缩放。原 CJK、拉丁字体数据、水平字距与冻结 32 号字均不改。字段行为参见 [Godot FontFile 缓存度量](https://docs.godotengine.org/en/4.6/classes/class_fontfile.html#class-fontfile-method-set-cache-ascent)。

技能提示使用 RichTextLabel 的 normal/bold 字体分开绘制首行和正文，原始提示内容、对外 `get_inspection_text()`、批准宽度、字号、内边距与定位公式保持。标题字重用于技能标题、属性卡标题、Turn Order 标题及预测标题。

`scripts/codex/build-windows-release.ps1` 现核验三组字体及许可证清单与 SHA-256；编辑器导入后检查完整 `.import` 参数为 `allow_system_fallback=false`，并对 Windows PCK 中每个字体 `.import` 映射检查其指向的 `.fontdata` 唯一且非空。脚本将三份许可证复制到发行包 `licenses/` 并比对摘要。真实 PCK 的 FontFile/ThemeDB 字体链属性由 `cr10_font_runtime_check.gd` 在 `--main-pack` 模式下复核。候选 `b0e1ca919c4bcfa3aa16fb87872f9aa986e376ff` 已完成包含三种 CJK 字重的真实 Windows 无窗口发行构建、许可证打包与 PCK 字体链检查；原件摘要、范围及已有警告见 `../runs/2026-10-07-cr10-weight/windows-package-verification.json`。三档 Windows 画面、受托字重选择与用户视觉验收分别记录，发行检查不替代它们。

## 首次导入与制作设置

自动加载脚本在运行树入口加载正文及补充符号字体，避免在首次导入前解析期预加载字体。`project.godot` 设置 `editor/import/use_multiple_threads=false`，让资源导入使用串行路径；这会增加潜在导入耗时，不改变运行渲染器或玩法。全新无 `.godot` 缓存的导入、字体运行与 10×10 正式场景绑定已分别通过 Main 和独立审查者检查。

此前的首次解析失败和并行导入原生崩溃日志保留在仓库外证据中，摘要记入本轮运行记录。串行导入成功不构成原生崩溃根因已经查明的证据。字段语义以 [Godot 4.6 ProjectSettings](https://docs.godotengine.org/en/4.6/classes/class_projectsettings.html#class-projectsettings-property-editor-import-use-multiple-threads) 和 [4.6.3 导入源码](https://github.com/godotengine/godot/blob/4.6.3-stable/editor/file_system/editor_file_system.cpp#L3064-L3078) 为依据。


## Windows 对照与验收边界

`tests/claude_review/run_cr10_windows_weights.ps1` 在仓库外冻结逐文件源字节，复用正式 `courtyard` 10×10 试战及项目拉伸。`capture_cr10_windows_weights.gd` 在场景已持有主题后设置 Regular/Medium，并逐图核对真实字体数据 SHA256；同次 `frame_post_draw` 后保存整屏、状态与精确局部。标题始终为 Bold，冻结剑气数字不挂 CJK 回退。

采集使用 Windows 原生显示服务和本机 Compatibility GPU，窗口不获得焦点并置于屏幕外，内部 `Viewport.push_input` 展开文字。该批不是物理鼠标交互、音频或性能验收。原 PNG 尺寸与 Window 尺寸一致；Viewport、Texture API 和 Image 尺寸分别记录，未把 Texture API 数值当作 PNG 像素尺寸。

CR-10 完成条件：字形一致、正文图上选定、三档五个面板中文字不裁切且距边框至少 2/3/4 像素、Windows 外观验收。独立审查、Codex 受托字重选择、用户视觉批准分别记录。C4 与 C8 同轮执行；头像贴合 CR-24 的失败不因本轮字体结果改变。
