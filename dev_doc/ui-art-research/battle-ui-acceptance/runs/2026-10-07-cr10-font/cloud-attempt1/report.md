# CR-10 云端字体验收记录

## 当前结论

云端九张正式场景原图的可见中文、全角标点、拉丁字母和数字观察通过。整套检查集仍为 **FAIL**：九图均复现 CR-24 头像顶边底色缝。整体 UI、CR-10 和 P0/CR-01 Milestone 均未完成。

候选提交 `21a77b91818fe0b71f5d9fbe684cc942250db0e2`，tree `682dd3579db930b4331f99b173b101cd984cce3c`。本轮是 `courtyard` 10×10 进入正式 `TacticalScene`，使用 Compatibility 与项目原有 `canvas_items` 拉伸。基础剑士印记隐藏。测试使用脚本鼠标事件，不覆盖真实云端鼠标的 G4 再入用例。

## 原件与逐项核验

本地主动读取实际配对 YC 原生会话的 RESULT 引用，核对 106/106 份原件（42,967,521 字节）、127/127 个原字节分片、7 个分片映射及 18 个空文件。三张大 PNG 由完整原字节重构；未缩放、重编码、修图或重跑 Godot。引用和逐文件 SHA256 见 `evidence-references.json`，原件留在仓库外证据根和私有 Page。

| 项目 | 结果 | 依据 |
| --- | --- | --- |
| 658 个冻结 Git blob 与执行前后来源 | PASS | `source-binding-verification.json` |
| 冷启动串行导入、字体覆盖和无系统回退运行检查 | PASS | 原始命令、日志；运行 `failed=0` |
| 三种状态×三档分辨率，共 9 PNG/9 JSON | PASS | `capture-states.json`；同一次 `frame_post_draw` |
| Window、Image 和原 PNG 原生尺寸 | PASS | 1280×720、1920×1080、2560×1440 |
| 可见 Label 的字体链关闭系统回退 | PASS | 三种状态分别 32、33、50 个 Label；Button 与自绘节点由运行检查和原图观察覆盖 |
| 云端可见字形、标点、混排和裁切 | PASS，限可见云端内容 | 九图独立观察原件 |
| C8 采集配置 | PASS | 冻结实现云端与本地全返回 |
| C4 头像贴合 | FAIL（CR-24） | 本地九次返回与云端原始返回完全一致；顶缝 1、2、2 行，其余三边 0 |
| Windows 字体像素外观、独立 GPU、音频、性能 | NOT_TESTED / local_required | 云端软件渲染无法替代 |
| 两个单色 emoji 的实际外观 | NOT_TESTED | 九图未展示；字形覆盖通过不等于外观验收 |

原始 `same-frame-validation.json` 的 `all_pass=false` 保留。它额外要求 Texture API 尺寸等于 PNG；签名任务与冻结采集器要求记录四种尺寸，并检查 Window/Image/PNG 一致及同帧。高分辨率 Texture API 返回 2880×1620、5120×2880，原生图片仍为 1920×1080、2560×1440。原始 `dimensions-adjudication.json` 一并保留；本记录不把 API 数值差异推断成已证实的故障原因。

## 交付状态与剩余工作

独立消费记录审查已通过；签名 RECEIPT（seq28）已发送且 Page 原字节回读一致。YC 已验签并关闭本次往返，execution_count=1。7205 字节 CLOSE_ACK 原件及引用已与实际配对原生根的完整输出核对一致，见 `verified-closure.json`。关闭只完成证据往返。最终关闭记录的独立增量复核通过，见 `final-close-review.json`；独立审查没有把关闭状态扩展为 Windows 外观、整体 UI 或用户视觉验收通过。已有 Windows 包、许可证和实际 PCK 字体消费技术核验通过，详见上级目录的 Windows 核验记录；它不验收 Windows 像素外观。

CR-24、CR-40 新增位置避让和 TERRAIN-READABILITY-01 尚未修复；本轮未修改这些生产代码、素材或玩法，未实施 CR-11。树木、墙壁、碎石与地板难区分的问题仍存在。

本轮记录只作本地提交，不推送、不创建 PR。独立审查与用户视觉验收分别记录。
