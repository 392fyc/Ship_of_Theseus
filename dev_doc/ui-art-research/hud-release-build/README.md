# 基础战斗 HUD 的 Windows 体验包

## 基础剑士版

2026-09-26 从游戏仓提交 `f2c74650c242c7df3731f0a90fc14236af7264dd` 构建了独立的基础剑士 Windows x86_64 体验包 `ShipOfTheseus-MyrmidonHUD-Windows-x86_64.zip`。包大小为 48,563,342 字节，SHA-256 为 `2f94282d427f4f32cc5ebb8e253028db8c627bf670586542ad9f4ec60e6e5ab7`。构建使用 Godot `4.6.3.stable.official.7d41c59c4` 和[官方 4.6.3 导出模板](https://github.com/godotengine/godot-builds/releases/tag/4.6.3-stable)，模板包 SHA-256 为 `3fbe2c0e2dec9d537ab9ec97bcf8da91dcf23357fc51f67092dd068d839290a8`。

构建只在发行副本中把测试战斗的玩家设为基础剑士，仓库默认战斗场景不变。发行副本的专项检查确认：基础剑士剑气上限为 100，印记容量为 0，印记面板隐藏，技能说明不描述印记，五个技能栏图标指向 `assets/ui/skills/myrmidon/`。共享技能命中也无法给基础剑士添加印记。从 ZIP 解压后启动程序，实际进入剑士回合，运行 120 帧后以退出码 0 结束。详见[构建结果](evidence/myrmidon-build-result.json)与[包内图标检查](evidence/myrmidon-icon-audit.json)。

从**解压后的 Windows 程序**截取的[1280×720 画面](evidence/myrmidon-package-1280.png)显示五枚剑士图标、剑气槽、正式剑士头像和上下对称的结束回合沙漏，右侧没有印记面板。开场剑气为 0；剑气填充到 65 时的画面和头像、沙漏四倍细节见[视觉确认记录](../hud-myrmidon-portrait/candidate/README.md)。用户已确认头像的形象、裁切与贴边效果，以及沙漏上下比例与三角形对称性。发行画面文件的 SHA-256 为 `eb731ecb6cbe41217ae0130d56bd324ae6d7e9f206ca9af257b2aad105e6eb38`。

发行 ZIP 包含 `ShipOfTheseus.exe`、`ShipOfTheseus.pck` 和 Godot、IBM Plex Mono、Source Sans Pro 的许可说明。导出的资源包不包含 Godot MCP、开发文档和测试文件。ZIP 留在仓库外的本机输出目录，不提交到游戏仓。

## 剑圣版

此前从提交 `d05e58e9999fa3fece03ee51fbea290469b3145c` 构建了 `ShipOfTheseus-Windows-x86_64.zip`。这一版启动的是剑圣，画面包含剑气和三枚印记，技能栏显示剑圣当前的原型图标；它尚未包含本次沙漏修订。包大小为 46,734,133 字节，SHA-256 为 `6c73783d9880221080935fcb657cfd1a93fa36340164565f575382dcf30fe324`。原始[构建结果](evidence/build-result.json)、[包内图标检查](evidence/icon-audit.json)和[运行画面](evidence/windows-package-1280-normalized.png)保留用于分别核对。包内图标检查只证明五张基础剑士图标随资源进入包，不表示剑圣技能栏使用这些图标。

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

项目主场景仍是 `TacticalScene` 测试战斗，因此这些包用于基础战斗 HUD 的体验与验收，不代表完整游戏内容。基础剑士与剑圣都已有各自的人物栏头像；剑圣旧包仍是当时的画面。此处未进行异机兼容性或代码签名验收。
