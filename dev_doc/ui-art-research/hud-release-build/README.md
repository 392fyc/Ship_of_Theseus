# 基础战斗 HUD 的 Windows 体验包

## 基础剑士版

2026-09-26 从游戏仓提交 `23570b334d67f678ecaa6f69a6bf03c79f7e1948` 构建了独立的基础剑士 Windows x86_64 体验包 `ShipOfTheseus-MyrmidonHUD-Windows-x86_64.zip`。包大小为 46,734,068 字节，SHA-256 为 `dd0af9d230748aa0ba608f3555ed015897dea81b6123f44d8a5279ae3d5d8c5a`。构建使用 Godot `4.6.3.stable.official.7d41c59c4` 和[官方 4.6.3 导出模板](https://github.com/godotengine/godot-builds/releases/tag/4.6.3-stable)，模板包 SHA-256 为 `3fbe2c0e2dec9d537ab9ec97bcf8da91dcf23357fc51f67092dd068d839290a8`。

构建只在发行副本中把测试战斗的玩家设为基础剑士，仓库默认战斗场景不变。发行副本的专项检查确认：基础剑士剑气上限为 100，印记容量为 0，印记面板隐藏，技能说明不描述印记，五个技能栏图标指向 `assets/ui/skills/myrmidon/`。共享技能命中也无法给基础剑士添加印记。从 ZIP 解压后启动程序，实际进入剑士回合，运行 120 帧后以退出码 0 结束。详见[构建结果](evidence/myrmidon-build-result.json)与[包内图标检查](evidence/myrmidon-icon-audit.json)。

从**解压后的 Windows 程序**截取的[1280×720 画面](evidence/myrmidon-package-1280.png)显示五枚剑士图标和剑气槽，右侧没有印记面板。开场剑气为 0；剑气填充到 65 的界面可见[设计验收画面](../myrmidon-skill-icons/candidate-v3/action-1280.png)。发行画面文件的 SHA-256 为 `5b2730a0fb256b933ee621c95d883728f58e7063c2f7dfc4902dbec1468038f5`。

发行 ZIP 包含 `ShipOfTheseus.exe`、`ShipOfTheseus.pck` 和 Godot、IBM Plex Mono、Source Sans Pro 的许可说明。导出的资源包不包含 Godot MCP、开发文档和测试文件。ZIP 留在仓库外的本机输出目录，不提交到游戏仓。

## 剑圣版

此前从提交 `d05e58e9999fa3fece03ee51fbea290469b3145c` 构建了 `ShipOfTheseus-Windows-x86_64.zip`。这一版启动的是剑圣，画面包含剑气和三枚印记，技能栏显示剑圣当前的原型图标。包大小为 46,734,133 字节，SHA-256 为 `6c73783d9880221080935fcb657cfd1a93fa36340164565f575382dcf30fe324`。原始[构建结果](evidence/build-result.json)、[包内图标检查](evidence/icon-audit.json)和[运行画面](evidence/windows-package-1280-normalized.png)保留用于分别核对。包内图标检查只证明五张基础剑士图标随资源进入包，不表示剑圣技能栏使用这些图标。

## 重建基础剑士版

准备相同版本的 Godot 控制台程序和官方导出模板包，使用新的、位于仓库外的输出目录运行：

```powershell
& scripts/codex/build-windows-release.ps1 `
  -GodotPath '<Godot 4.6.3 控制台程序的绝对路径>' `
  -TemplateArchivePath '<官方导出模板包的绝对路径>' `
  -OutputDirectory '<新的输出目录绝对路径>' `
  -PreviewClass myrmidon `
  -CaptureVisual
```

不指定 `-PreviewClass` 时仍构建剑圣版。构建脚本从当前提交提取运行文件，使用仓库内的[Windows 导出预设模板](../../../release/windows-export-preset.cfg.in)，清理发行副本中的调试配置，再检查导出资源、解压启动与运行画面。Godot 的[导出说明](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_projects.html)区分了可运行导出包与仅包含资源的 ZIP；这里验收的是前者。

## 当前边界

项目主场景仍是 `TacticalScene` 测试战斗，因此这些包用于基础战斗 HUD 的体验与验收，不代表完整游戏内容。基础剑士的人物栏目前使用通用占位头像，剑圣人物栏另有正式头像。此处未进行异机兼容性或代码签名验收。
