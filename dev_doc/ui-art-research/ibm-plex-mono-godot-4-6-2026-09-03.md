# IBM Plex Mono 数值 HUD 候选研究（Godot 4.6）

## 结论

`IBM Plex Mono SemiBold` 可以作为 SoT 底部 HUD 数值的免费候选，不涉及素材购买。候选使用静态 TTF、传统栅格化和实时 Label 排版；不使用变量字体、MSDF、烘焙文字或图像化数值。

字体采用 SIL Open Font License 1.1。该许可允许字体随商业游戏嵌入和再分发，但不得单独销售字体；发行副本需要保留版权声明与完整许可文本。若未来对子集或字体文件本身做修改，修改版不得继续使用保留名称 `Plex`，除非取得 IBM 书面许可。本记录是工程合规摘要，不构成法律意见。

## 已核实来源

- 官方版本：`@ibm/plex-mono@2.5.0`，字体版本 `IBM PLEX MONO V2.5`，字体版本标记日期 2026-04-21，对应短提交 `2f9ba1b`；GitHub Release 实际发布时间为 `2026-06-11T19:24:51Z`。
- 静态 SemiBold TTF：`packages/plex-mono/fonts/complete/ttf/IBMPlexMono-SemiBold.ttf`。
- 同目录许可证：`packages/plex-mono/fonts/complete/ttf/license.txt`。
- 官方发行资产：`ibm-plex-mono.zip`。
- 官方公布的 ZIP SHA-256：`6d23f01257663d8cc49a0d64c22ced630b79e0e2a0ac08a0da86e9a38bbc481c`。
- 保留字体名：`Plex`。

来源：

- [IBM Plex Mono 2.5.0 官方发布页](https://github.com/IBM/plex/releases/tag/%40ibm%2Fplex-mono%402.5.0)
- [官方 TTF 文件页](https://github.com/IBM/plex/blob/%40ibm/plex-mono%402.5.0/packages/plex-mono/fonts/complete/ttf/IBMPlexMono-SemiBold.ttf)
- [同版本许可证原文](https://github.com/IBM/plex/blob/%40ibm%2Fplex-mono%402.5.0/packages/plex-mono/fonts/complete/ttf/license.txt)
- [IBM 字体许可说明](https://www.ibm.com/design/language/typography/typeface/#open-source-licenses)
- [Godot 4.6：Using Fonts](https://docs.godotengine.org/en/4.6/tutorials/ui/gui_using_fonts.html)
- [Godot 4.6：FontFile](https://docs.godotengine.org/en/4.6/classes/class_fontfile.html)
- [Godot 4.6：Theme](https://docs.godotengine.org/en/4.6/classes/class_theme.html)

## Godot 候选配置

- 使用静态 `IBMPlexMono-SemiBold.ttf`，字重 600。
- `multichannel_signed_distance_field = false`，保留传统栅格化与小字号 hinting。
- 首轮使用灰度抗锯齿；先比较 `Light` 与 `Full` hinting。
- 比较 `Auto`、`Disabled`、`One Quarter` 三种子像素定位；不预先断言哪一种在实际游戏画面上最佳。
- 1:1 HUD 不开启 mipmap；Label 和父级 Control 保持 `scale = (1, 1)`。
- 普通数值 8px；长度达到 13 字符的 `999999/999999` 使用 7px 回退。
- 字体只服务拉丁数字和斜杠；中文身份栏继续使用现有字体链，本任务不引入 CJK 字体。

## 可读性风险

7px／8px 已经进入对 hinting、像素对齐和窗口缩放很敏感的范围。等宽字体能够避免数值更新引发水平抖动，但不能自动保证内部空间清晰。验收不能只检查“没有裁切”，还必须检查：

- `0/6/8/9` 的内部空间能够区分；
- `1/7` 不混淆；
- `/` 连续且不过细；
- `999999/999999` 在既定轨道中右对齐、无溢出；
- 数值变化时基线和右边界不跳动；
- 暗色 HUD、亮色棋盘和高噪声背景上均可读。

## 最小导入与记录

仅导入：

1. `IBMPlexMono-SemiBold.ttf`；
2. 原样许可文本；
3. 来源版本、发行 URL、官方 ZIP SHA-256、取得日期；
4. 下载后实测的 ZIP、TTF 和许可文本 SHA-256。

不导入其他字重、斜体、Web 字体、变量字体或源码包。字体先进入开发画廊候选，不直接成为正式 HUD 字体；只有用户视觉确认后才写入现行 Theme 合同。
