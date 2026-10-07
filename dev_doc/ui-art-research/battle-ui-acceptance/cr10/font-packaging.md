# CR-10 中文字体打包候选

## 范围与当前实现

该候选为 Godot 普通主题、M2 HUD 主题和直接自绘文字提供随包字体回退。原有拉丁字族与 IBM Plex Mono 数字字族继续作为主字体；CJK、符号和 emoji 只在主字体缺少相应字形时参与回退。系统字体回退已在字体导入默认值、随包字体和运行时字体链中关闭。

默认主题通过 `SoTFontSetup` 将 ThemeDB 原默认字体副本设为普通主题字体并挂接包内回退链。M2 的 CJK/符号/emoji 字体资源使用独立 MSDF 缓存，以适配既有 `Control.scale`。冻结剑气面板只绘制数字，仍使用原 Source Sans Pro Semibold 栅格字形和度量，不挂中文回退。M2 数值标签使用 IBM Plex Mono 主字族及中文回退。

字符、图标用途和界面结构保持原有配置。Noto Emoji 子集是单色矢量轮廓，所需 emoji 不再依赖本机 emoji 字体；这两处 emoji 的最终外观仍须通过实际画面审查。CR-18 样式改版与 CR-22 图标改版不属于本候选。

## 字体来源与许可

每个字体目录内的 `source.json` 记录固定上游提交、源字体 URL、源 SHA-256、生成子集 SHA-256、字节数与字体工具版本；`LICENSE.txt` 保留上游 SIL Open Font License 1.1 文本。目录内的 `.gitattributes` 禁用换行转换，使许可证、清单和字体在 Windows 检出后保持这些精确字节。

| 包内字体 | 固定来源 | 原件 SHA-256 | 子集 SHA-256 | 子集字节数 | 许可证 SHA-256 |
| --- | --- | --- | --- | ---: | --- |
| `NotoSansCJKsc-Regular-subset.otf` | `notofonts/noto-cjk` `Sans2.004`, `523d033d6cb47f4a80c58a35753646f5c3608a78` | `2c76254f6fc379fddfce0a7e84fb5385bb135d3e399294f6eeb6680d0365b74b` | `241e7ebc37926a6a893771a8d0f2f375e385b44d9e8d400553402968a111531b` | 3,408,020 | `6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2` |
| `NotoSansSymbols2-Regular-subset.ttf` | `notofonts/noto-fonts`, `ffebf8c1ee449e544955a7e813c54f9b73848eac` | `630846d528dbe4c4981370a4d0a9475a1fd1491a129bb411f8e157cdb5de13c6` | `e3fba50bf66cf9f4475629b2840f27df8b0a6bde04743007c6e263ebbcba2bce` | 6,664 | `0dab92d0544f7b233403f14b84a663bdbfa746982eda629e7f4f9ffe1b036feb` |
| `NotoSansSymbols-Regular-subset.ttf` | `notofonts/noto-fonts`, `ffebf8c1ee449e544955a7e813c54f9b73848eac` | `8f02f31959bbdf6061547a188248e13f84dc5fdd940326ec494675f453f072bb` | `029bbe8952f5e1270dbfcbf6f29fa43e2b8158a5b87e4fc80d695fefa7d1cd6f` | 6,508 | 同上 |
| `NotoEmoji-Regular-400-subset.ttf` | `google/fonts`, `8b0a1d0f5983c89bc2b93f1b5fb55f9e252744b5`, `wght=400` | `de6c18832938afc99caf132b39d6a30a19bac7f2e812e28db2535b4608d27551` | `2e1a067b485a7a8f8b8459405d712ab0465f1cb2de971b928471d815d20dbe90` | 2,812 | `500bb1ccf43df7bbb522112f9133a52b16e1c35e809632f5d8609b179152de5b` |

保留字体名称、版权和许可元数据。各上游清单均记录没有 Reserved Font Name 声明。上游完整字体不进入仓库；仓库只包含生成子集、来源清单和许可证。

## 覆盖与确定性重建

`tests/claude_review/build_cr10_font_subset.py` 固定上游原件 SHA-256 和 `fontTools 4.66.1`。生成前先验证所有原件和许可证摘要，并验证 CJK、Symbols2、Symbols1、Emoji 的联合 cmap 能覆盖完整需求；任一缺字都会终止生成。随后为每份子集固定 Unicode 输入、表顺序和可变字体实例，并重复构建比较摘要。

需求集包括完整 GB2312 编码字符集 7,445 个码点，以及当前游戏数据、场景、脚本、资源和项目配置字符串中提取的码点；并集共 7,476 个不同码点。CJK 子集覆盖 7,460 个码点，其中包含全部 GB2312 码点；Symbols2 覆盖 12 个码点，Symbols1 覆盖 2 个码点，Emoji 覆盖 2 个码点。运行时检查验证主题和自绘使用的完整回退链覆盖整个并集。

在 PowerShell 中设置 `CR10_FONT_SOURCE_DIR` 指向四份已按来源 SHA 核验的上游原件所在目录，然后运行：

```powershell
$fontSourceRoot = $env:CR10_FONT_SOURCE_DIR
& python tests/claude_review/build_cr10_font_subset.py `
  --source-font (Join-Path $fontSourceRoot 'NotoSansCJKsc-Regular.otf') `
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

运行检查还会输出 `CR10_TEXT_METRICS`，用于核对 ThemeDB/M2 的真实混合字符串度量。例如本候选 Godot 4.6.3 size 9 的普通 ThemeDB 字体链 ascent/descent/height 为 `14/6/20`，其 primary-only 为 `10/3/13`；M2 默认文本链为 `13.5/5.813/18.75`，primary-only 为 `9.75/2.813/12.563`。检查记录“命中 100%”“暴击 25%”“必定生效”的 `get_string_size`。这些 API 度量变化需要纳入三档实际分辨率画面复核；运行覆盖通过不代表字形外观或排版已获美术验收。

`scripts/codex/build-windows-release.ps1` 现核验三组字体及许可证清单与 SHA-256；编辑器导入后检查完整 `.import` 参数为 `allow_system_fallback=false`，并对 Windows PCK 中每个字体 `.import` 映射检查其指向的 `.fontdata` 唯一且非空。脚本将三份许可证复制到发行包 `licenses/` 并比对摘要。真实 PCK 的 FontFile/ThemeDB 字体链属性由 `cr10_font_runtime_check.gd` 在 `--main-pack` 模式下复核。当前候选尚未运行真实 Windows 发行构建；该步骤由主代理在独立审查和提交后执行。三档画面、Windows 实机显示及字体形状仍是待验收条件。
