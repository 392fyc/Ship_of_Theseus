# 战斗 HUD 的 Windows 包验收

## 本次结果

2026-09-26 从游戏仓提交 `d05e58e9999fa3fece03ee51fbea290469b3145c` 的运行文件构建了 Windows x86_64 包，使用 Godot `4.6.3.stable.official.7d41c59c4` 和[官方 4.6.3 导出模板](https://github.com/godotengine/godot-builds/releases/tag/4.6.3-stable)。模板包的 SHA-256 为 `3fbe2c0e2dec9d537ab9ec97bcf8da91dcf23357fc51f67092dd068d839290a8`。

交付 ZIP 包含 `ShipOfTheseus.exe`、`ShipOfTheseus.pck` 和四份许可说明，大小 46,734,133 字节，SHA-256 为 `6c73783d9880221080935fcb657cfd1a93fa36340164565f575382dcf30fe324`。许可说明涵盖 Godot 引擎及界面使用的 IBM Plex Mono、Source Sans Pro 字体；Godot 的[官方许可页](https://godotengine.org/license/)说明了发行时保留引擎许可与版权信息的要求。本机从该 ZIP **重新解压后**启动游戏，运行 120 帧并以退出码 0 结束；导入、导出和启动日志没有脚本错误。完整摘要见[构建结果](evidence/build-result.json)。ZIP 留在本机输出目录，不提交到游戏仓。

发行副本采用仓库内的[Windows 预设模板](../../../release/windows-export-preset.cfg.in)和[构建脚本](../../../scripts/codex/build-windows-release.ps1)。脚本从当前提交提取运行所需的 `project.godot`、`assets/`、`data/`、`scenes/`、`scripts/`，在独立副本中关闭战斗调试界面并移除 Godot MCP 的自动加载、编辑器配置和插件文件，不改开发工作树的配置。导出的资源包中 `addons/godot_mcp/`、`dev_doc/`、`docs/` 和 `tests/` 均为 0 个条目。

五张基础剑士图标的目录映射、导入映射和运行纹理再次通过[包内检查](evidence/icon-audit.json)。从**解压后的 Windows 程序**捕获的 [1280×720 画面](evidence/windows-package-1280-normalized.png)显示人物栏、技能栏、行动资源、剑气槽及三枚纹章；左上角的开发调试提示已移除。画面文件的 SHA-256 为 `2641d6f81e4b7cef9e05d3984fce9d8ed94902cd3deac4883a2c6fb724b3ac7d`。

## 重建

先取得上方官方导出模板包，并准备相同版本的 Godot 控制台程序。使用新的、位于仓库外的输出目录运行：

```powershell
& scripts/codex/build-windows-release.ps1 `
  -GodotPath '<Godot 4.6.3 控制台程序的绝对路径>' `
  -TemplateArchivePath '<官方导出模板包的绝对路径>' `
  -OutputDirectory '<新的输出目录绝对路径>' `
  -CaptureVisual
```

脚本核对官方模板摘要，生成发行副本和可执行包，检查五张图标与开发资料的纳入范围，并从压缩包解压启动。Godot 的[导出说明](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_projects.html)区分了可运行导出包与仅包含资源的 ZIP；本次验收的是前者。

## 当前边界

当前项目的主场景仍是 `TacticalScene` 测试战斗，因此这个包用于**基础战斗 HUD 的可启动体验与验收**，不表示完整 Roguelite 游戏内容已经完成。启动日志另有一条提示：`data/buildings/` 目前只有 `.gitkeep`，导出后空目录不存在；它未阻止战斗场景启动。本次没有进行异机兼容性或代码签名验收。
