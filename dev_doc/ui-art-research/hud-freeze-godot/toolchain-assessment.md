# 基础战斗 UI 素材工具流核验

核验日期：2026-09-24。当前定版剑和印记直接使用已批准的 Penpot 分层与同源状态图；下列工具用于后续新素材，不改动这批定版视觉。

| 工具 | 本机核验 | 工程判断 |
| --- | --- | --- |
| GPT Image 2.5 | 官方 Image API 明确支持 `gpt-image-2.5-sunburst` 和 `gpt-image-2.5-flare`。本会话可用的 `image_gen__imagegen` 接口只有提示词和参考图参数，没有模型选择或返回型号字段。本次没有生成图像，也不能把该接口的输出归属于某个确切型号。 | 新素材先生成完整且成立的物体，再做遮罩、填充与状态效果。需要指定 2.5 型号时，使用能显式设置并记录 `model` 的接口；保存提示词、尺寸、结果文件摘要和人工审查结论。 |
| BiRefNet | 官方仓库可读；本机 Python 环境没有 `torch`、`transformers`、`onnxruntime` 或 BiRefNet 包，项目目录下未发现安装仓。官方提供通用、抠图等权重和 ONNX 版本。 | 作为静态素材的轮廓与初始蒙版辅助，保留人工修边和与成品逐像素核对。逐帧静态分割不等于动画透明边缘稳定。 |
| CorridorKey | 官方仓库可读；本机没有可调用安装仓或命令，也没有 `ffmpeg`。本机 NVIDIA GeForce RTX 3070 Ti 为 8 GiB 显存，驱动报告 CUDA 13.2。官方说明新版本预期可在 6–8 GiB 显存运行，但本机尚无模型、样片和实测结果。 | 仅在有绿幕或蓝幕视频、粗略 AlphaHint 和动画交付需求时试用。先用短片核对帧间一致性、边缘、颜色、透明度及导入 Godot 后效果；不把单张抠图当成动画验收。GVM、VideoMaMa 的官方显存要求远高于本机配置，不列入首轮试用。 |
| GodotMaker | 官方仓库可读；本机未发现 `godotmaker-cli` 或独立工具仓。官方说明它主要生成 2D Godot 原型，当前像素画和 TileMap 自动流程仍有明确限制。 | 后续如试用，放在独立外部仓，锁定提交，只让小型适配层读取明确产物。任何进入 SoT 的代码仍要遵守 JSON 权威、可序列化 `GameAction`、独立工作树和现有验收流程。 |

本次远端 `HEAD` 记录（只读查询，未来试用前再核对）：GodotMaker `1d4702caa2ac5fdbe1b0139e1787691cb52ae290`，BiRefNet `ebcc0bc8ec7fe919cec829f2dea656b3078acddc`，CorridorKey `97e55a453060745bead1befd293f6e523c4b845c`。这些是候选锁定点，不表示已经安装或运行。

官方依据：[OpenAI 图像生成指南](https://developers.openai.com/api/docs/guides/image-generation)、[GodotMaker 仓库](https://github.com/RandallLiuXin/GodotMaker)、[BiRefNet 仓库](https://github.com/ZhengPeng7/BiRefNet)、[CorridorKey 仓库](https://github.com/nikopueringer/CorridorKey)。
