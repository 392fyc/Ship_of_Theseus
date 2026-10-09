# 地形可读性采集 v5：冻结重绘时序与失败留证

## 当前阶段与边界

TERRAIN-READABILITY-01 的像素基线前置仍未完成，地形问题、美术接受与 Milestone 均未完成。TASK50 原件完整。本候选不改写 v1–v4 或 TASK50 的证据，不创建 PR。

本次只新增 v5 采集子类、对应验证器与回归测试、本任务记录。v5 继承 v4 的正式场景入口、独立出生用例 JSON、道具、镜头、阈值、12 张同帧图、完整 RGBA、C4/C8、实际排除规则、alpha 条件与每类至少 3 个可见实例门槛。两项既有石柱/碎石样本继续保留，采集器不直接修改其实例 alpha。源码摘要必须绑定这四个新增文件的实际字节。

## 已确认依据

v3 TASK48 的历史结果记录了 925 个完整 RGBA 样本都落在水面、props 为 0，石柱与碎石各有 2 个可见样本；这些不是 TASK50 或 v5 的本次测量。v4 新增正式会话出生位置用例与 draw 观测；其先前六组 headless 结构检查和 Python 检查通过，但发生在本轮时序修订之前，不作为最终候选证据。

新的原生先行 TASK50 单组运行在 `_v4_request_frozen_redraw` 失败，退出码为 1，生成 0 张 PNG、0 个 manifest。失败具体落在哪个 draw/counter 子条件仍为 UNKNOWN，未运行冻结版 validator。v4 的旧诊断只含 `cases=[]`，因为成功用例追加前失败，writer 没有保存活跃失败用例。不能把 v3 TASK48 的 925 个样本或 v4 的 headless 结果引用为 TASK50/v5 的测量。

Godot 4.6.3 的真实调用顺序允许 deferred `CanvasItem.draw` 早于 `RenderingServer.frame_pre_draw`。因此 v5 在每个实际回调发生时保存单调全局 `event_ordinal`、`capture_request_id` 与原始 `phase`；draw 事件只保留自己的 ordinal/phase，不预填或伪造 `render_sequence`。验证器依据原始顺序确认四个 draw 事件先于同一后续 pre，再到匹配 post，最后到渲染返回后的 `process_frame` 边界。post 回调中的帧计数可能仍为旧值；只有关联边界的 Engine 计数推进才满足计数谓词。

## v5 观察合同

1. 对 main/reconstruction 两边的 BoardView 与 DetailLayer 各调用一次 `queue_redraw()`，记录请求前输入摘要、实际回调输入摘要、可见状态和回调线程模型。
2. 四个实际 deferred `CanvasItem.draw` 回调记录全局 ordinal、原始 phase 与请求编号。它们必须发生在同一后续 `frame_pre_draw` 之前；该实际 pre 序号必须与后续匹配的 `frame_post_draw` 一致。不得将 render sequence 回填到更早的 draw 事件。
3. 最多观察三个 `process_frame` 返回边界。边界必须晚于匹配 post ordinal，并确认完整渲染序号已完成；计数只在边界读取，且须高于请求前 `Engine.get_frames_drawn()`。未满足时为 FAIL；headless 只能记录 NOT_TESTED。
4. 分别保存 `all_signals_seen`、`draw_sequence_aligned`、`frame_post_draw_seen_for_sequence`、`counter_advanced_at_process_boundary`、`input_summaries_match` 与 `process_boundary_after_render_return`。验证器从原始事件重新计算 draw→pre→post→boundary 关联，并拒绝 ordinal 重复、请求编号跨越、错误 pre/post 序号或摘要不匹配。
5. 外部诊断保留已完成用例列表，并始终单独写入 `active_case`。任一继承 `_abort` 都先设置失败状态与原因、保存当前 active case 和已有原始 draw/pre/post/边界事件，再调用外部 writer，最后进入基类清理；成功用例是否已追加不影响失败状态优先级或 active case 留存。失败记录包括四个节点、已出现的原始回调与事件、缺失节点及独立谓词；尚未构建或已释放的节点通过有效性检查安全记录。
6. manifest 仍须通过继承的 v4 完整像素前置。结构检查、源码检查或 draw 信号通过不能替代 12 图完整 RGBA 与实际像素测量。

## 验收与下一步

- Python 回归覆盖真实 deferred draw→pre→post→返回边界正例，以及缺失 draw、错误 pre/post 序号、跨请求事件、返回边界计数未推进、输入摘要不匹配、成功用例列表非空后继承 abort、失败 active case 原始事件保存和四文件源码摘要篡改。
- 本轮最终源码修改后不启动 Godot 或输入设备。此前 v4 headless 结构运行使用过相同出生用例 JSON（SHA-256 `514bfd3bd12ddcbbb70615578921023f1444c3c8f23337f36926fe1b59e2d7bd`）并覆盖 10×10、25×25 × 1280×720、1920×1080、2560×1440；它发生在本轮代码修改前，只能作为历史检查记录，不能作为当前候选的最终 headless 证据。此前输出中 draw 状态 `NOT_TESTED_HEADLESS`，不代表原生 draw 或像素验收通过。
- 后续原生运行必须给继承的 v3 路由诊断和 v5 活跃用例诊断传入互不相同的绝对仓外路径：`--v3-diagnostic=<独立绝对外部路径>/v3-diagnostic.json` 与 `--v5-diagnostic=<另一独立绝对外部路径>/v5-diagnostic.json`。PNG/manifest 输出也必须位于仓库外。
- Main 取得第五文件独立源码审查并冻结候选后，再创建新原生请求。新请求只先运行 10×10/720p；全部严格前置通过后才运行其余五组，每组一次。前置失败则保留原件并停止。
- TASK50 原件消费与关闭、独立源码/原件审查、用户视觉验收、实际登记和 lane 收尾由 Main 按既定流程完成。当前候选不推送、不建 PR，也不宣告 Milestone 完成。
