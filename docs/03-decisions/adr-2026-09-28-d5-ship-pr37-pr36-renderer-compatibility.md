# ADR：D-5 发行与验证统一使用 Compatibility

## 状态

用户于 2026-09-28 裁决。本文记录渲染器选择及其理由。实现事实由 Ship 仓维护；任务进度与验收证据由 GitHub/Git 维护；结构化玩法事实仍以设计库为准。

## 适用范围

本裁决适用于项目发行设置、运行画面采集和相关验证工具。它只确定渲染器选择，不新增玩法规则，也不代替其他待裁决事项。

## 裁决

1. 所有发行构建和验证入口统一使用 `Compatibility` 渲染器；`project.godot` 明确配置 `gl_compatibility`。C8 据此判定。
2. 先完成 CR-02 的独立审查并合并，合并后回读核验，再进入 CR-23。各项当前完成状态仍由 GitHub/Git 记录。
3. CR-01 按偏置恒为 `0` 执行；mip 模式下仍不达标的剑圣棋子与碎石另做显示尺寸母版（方案 B 或 C），验收使用 `tests/claude_review/sampling_sim.py` 的 mip 模式；不做偏置实验。锐利/平滑由用户在引擎内 A/B/C 并排图选择。
4. 已批准历史素材的身份与造型批准继续有效。此前关闭拉伸的整屏画面须按 CR-02 重新采集。其他历史证据按其来源、用途和渲染条件逐项判断，不自动视为本次 Compatibility 运行验收证据。
5. D-1 至 D-4 仍待用户裁决。

## 理由

- 在 Ship `develop@6641a054e190ed731775f731466f749cea7eaf9c` 上核对的生产场景与脚本没有 3D 节点或 GPUParticles 用法；两个 `.gdshader` 文件均为 `canvas_item`。这与当前 2D 游戏需求相符。
- 当时仓内现有发行脚本仅覆盖 Windows。该现状支持沿用现有发行与验证链，不构成未来平台范围承诺。
- Godot 4.6 官方文档指出，Compatibility 支持最广的硬件范围，并适用于 2D 游戏。
- 延续既有验证链，同时保留已批准素材的身份，能继续使用已确认的视觉方向；运行画面仍按新的 CR-02 条件采集和核验。

## 依据与关联

- 代码核对快照：Ship `develop@6641a054e190ed731775f731466f749cea7eaf9c`。
- [Ship PR #37：CR-02 Compatibility 与运行画面采集](https://github.com/392fyc/Ship_of_Theseus/pull/37)。
- [Ship PR #36：美术与 UI/UX 独立审查交付](https://github.com/392fyc/Ship_of_Theseus/pull/36)。
- [Godot 4.6 渲染器说明](https://docs.godotengine.org/en/4.6/tutorials/rendering/renderers.html)。
- 视觉素材身份与既有批准见 [[../04-Assets/visual-style-decisions|视觉素材现行裁决]]。

## 权威边界

本文保存用户的渲染器裁决与理由。CR-02、CR-23、CR-01 的实施状态和验收结果以 GitHub/Git 与 Ship 仓的新证据为准；本文不将 PR 当前状态写作裁决依据，也不表示任何实现或里程碑已经完成。
