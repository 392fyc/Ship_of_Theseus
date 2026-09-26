# 基础剑士头像与结束回合沙漏：视觉确认记录

本候选从游戏仓提交 `b96a07c3aee954474d2ac6d82500b14d9efd0c0a` 构建。用户于 2026-09-26 确认基础剑士头像的形象、裁切与贴边效果，以及沙漏上下比例与三角形对称性。素材清单中的 `visual_status` 为 `user_approved`。正式 Windows 包从批准后的提交另行构建并记录。

## Godot 界面检查

[1280×720 整屏](combat-1280.png)使用真实剑士战斗场景，把剑气设为 65 以检查填充效果。[头像四倍细节](portrait-detail-4x.png)用于核对 70×78 像素画框内缘；[沙漏四倍细节](end-turn-detail-4x.png)用于核对上下三角形的比例与对称性。头像接入只作用于基础剑士，剑圣仍读取原有头像。

## Windows 候选包检查

独立候选 ZIP 名为 `ShipOfTheseus-MyrmidonHUD-Windows-x86_64.zip`，大小 48,563,246 字节，SHA-256 为 `ef7e76991948f494d3d15a13c277929e2f7594144eb7ea51613b0f04638fccb4`。[构建结果](windows-build-result.json)与[包内图标检查](windows-icon-audit.json)均通过。候选 ZIP 解压后的程序运行 120 帧，以退出码 0 结束，日志进入“剑士”回合。[程序截图](windows-package-1280.png)显示新头像、对称沙漏、五枚基础剑士技能图标及剑气槽，未显示印记面板。程序截图 SHA-256 为 `eb731ecb6cbe41217ae0130d56bd324ae6d7e9f206ca9af257b2aad105e6eb38`。

本候选包及构建中间文件留在仓库外的本机输出目录，只有截图和摘要进入本目录。正式发行记录仍见[基础战斗 HUD 的 Windows 体验包](../../hud-release-build/README.md)。
