# 图像生成技能小型研究

## 目标

在不使用外部 API key、不读取 Codex 会话日志、继续由 Codex 内置图像生成能力执行的前提下，评估可用于优化 Ship of Theseus 统一视觉素材链的技能。

## 结论

保留当前系统 `imagegen` 作为唯一生成执行器。若后续需要加强提示拆解和风格检索，可在用户确认后选择性安装 `gpt-image-2-style-library`；其他候选暂不安装。

| 候选 | 结论 | 主要依据 |
|---|---|---|
| Codex 系统 `imagegen` | 保留为唯一执行层 | 使用 Codex 内置图像生成能力，不需要外部 API key；支持引用图、透明图、非破坏版本和逐项迭代。SoT 仍需自行维护棋子朝向、脚底锚点、格内尺度和文件准入合同。[官方技能](https://github.com/openai/codex/blob/main/codex-rs/skills/src/assets/samples/imagegen/SKILL.md)；[Apache-2.0 许可证](https://github.com/openai/codex/blob/main/LICENSE)。 |
| `gpt-image-2-style-library` | 推荐作为可选提示与风格检索层 | 技能本体只读取本地参考库并整理提示，不负责生成；MIT 许可。它没有专门的像素战棋或菱形棋盘模板，不能替代 SoT 视觉合同。[技能说明](https://github.com/freestylefly/awesome-gpt-image-2/blob/main/agents/skills/gpt-image-2-style-library/SKILL.md)；[风格索引](https://github.com/freestylefly/awesome-gpt-image-2/blob/main/agents/skills/gpt-image-2-style-library/references/style-library.md)；[许可证](https://github.com/freestylefly/awesome-gpt-image-2/blob/main/LICENSE)。 |
| `agent-sprite-forge / generate2dsprite` | 不原样安装，后续只参考几何与验收方法 | 固定脚底锚点、身体尺度、武器包围盒偏移和身体/特效分层规则对战棋棋子有价值；默认粗像素、16-bit、饱和配色和特定怪物收集风格与本项目方向冲突。[项目说明](https://github.com/0x0funky/agent-sprite-forge)；[提示规则](https://github.com/0x0funky/agent-sprite-forge/blob/main/skills/generate2dsprite/references/prompt-rules.md)；[许可证](https://github.com/0x0funky/agent-sprite-forge/blob/main/LICENSE)。 |
| `generating-dot-assets` | 不推荐安装 | 默认像素化和颜色压缩容易再次造成像素过粗；故障恢复流程会搜索 `$CODEX_HOME/sessions` 下的会话记录，不符合本项目的最小暴露原则。[技能说明](https://github.com/abagames/agentic-gamedev-skills/blob/main/.agents/skills/generating-dot-assets/SKILL.md)；[恢复说明](https://github.com/abagames/agentic-gamedev-skills/blob/main/.agents/skills/generating-dot-assets/references/imagegen-cli-recovery.md)；[许可证](https://github.com/abagames/agentic-gamedev-skills/blob/main/LICENSE)。 |

## 建议的两层流程

1. 提示与风格层：SoT 已通过的视觉规则和参考素材始终是权威；可选风格库只负责检索模板、拆分构图、材质和限制，并记录所选模板。
2. 生成与验收层：只调用系统 `imagegen` 的内置模式，随后执行项目已有的本地机械清理、文件身份记录和质量检查。棋子、地形与特效可以选择性吸收脚底锚点、主体尺度和分层方法，但不得继承不符合项目定位的默认美术提示。

## 使用权和安全边界

- 不启用网站登录、Supabase、第三方 API 或外部 API key。
- 不允许命令行回退绕过 Codex 内置会话生成。
- `awesome-gpt-image-2` 仓库虽为 MIT，但仓库明确声明收录的第三方案例和图片不保证可商用；项目只可借鉴抽象提示结构，不得直接把案例图片或完整社区提示当作素材来源。[免责声明](https://github.com/freestylefly/awesome-gpt-image-2#disclaimer)。
- 本次研究没有安装技能、调用图像生成或消耗生成额度。实际提升幅度需要在后续正式素材批次中用少量对照候选验证。
