# 基础剑士图标资源包核验

## 结果

2026-09-26 使用 Godot 4.6.3 对 `b4e53d2a19456add57d24ab5090975f6e6cfe6aa` 的游戏项目完成资源导入，并通过临时 Windows Desktop 预设导出 ZIP 资源包。`scripts/codex/verify-myrmidon-export.ps1` 检查通过：

| 检查项 | 结果 |
| --- | --- |
| 技能图标目录 `assets/ui/catalogs/hud_m2_skill_icons.json` | 已进入包内，SHA-256 与仓库文件一致 |
| 心眼、斩击、一闪、招架、居合的运行图 | 五条 `.png.import` 映射及其非空 `.ctex` 纹理均在包内；本地运行图与定版清单的 SHA-256 一致 |
| 职业图标映射 | 目录中 `myrmidon` 的五项均指向对应正式运行图 |
| 开发源图、评审截图 | `dev_doc/` 整体未进入包内 |
| 其他开发资料 | `docs/` 与 `tests/` 未进入包内 |

本次资源包共 570 个条目，大小 9,782,311 字节，SHA-256 为 `fb0128b5d25ba922f6814239d54ce1e40a21b6583c12b1c6490e08dfe896e9af`。目录 JSON 的 SHA-256 为 `368c3e90f0168aec75fe68c0c823f5292d128d076be6eb2c3e33310121f5872b`。五张运行纹理的包内路径见[检查结果](export-audit.json)。资源包留在本机临时目录，不纳入 Git。

## 复核方法

仓库忽略 `export_presets.cfg`，因此本次在隔离工作树里建立临时审计预设，使用 `platform="Windows Desktop"`、`export_filter="all_resources"`、`include_filter="*.json"`、`exclude_filter="dev_doc/*,docs/*,tests/*"`。先用 Godot 的 `--headless --editor --import --quit` 导入资源，再以同一预设运行 `--headless --export-pack "Windows Desktop"` 生成 ZIP，最后执行：

```powershell
& scripts/codex/verify-myrmidon-export.ps1 -ArchivePath '<资源包 ZIP 的绝对路径>'
```

核验脚本读取[定版来源清单](source-manifest.json)，检查仓库与包内的目录、五张运行图摘要、导入映射、运行纹理以及开发资料排除情况。临时预设与导出的 ZIP 均不属于仓库交付文件。

## 范围

本记录证明上述五张运行图及目录进入了这次导出的资源包，且开发源图与评审截图没有进入该包。这次 ZIP 只有资源，不是可直接启动的 Windows 游戏；当时还没有可复用的 Windows 发行配置，包内有 `addons/godot_mcp/` 的 51 个条目。后续已完成[可启动 Windows 战斗 HUD 包验收](../hud-release-build/README.md)，在发行副本中排除了该插件。
