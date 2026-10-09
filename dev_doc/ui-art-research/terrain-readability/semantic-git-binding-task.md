# 树语义输入的 Git 原字节绑定修正

## 目标与范围

本任务使树语义作者输入和独立审查绑定到冻结候选的实际 Git 原字节，并在与云端一致的 LF 检出环境验证输入门。任务基线为 `9ff48a1d138cad708a4b05f4afa98e0a4f0af52d`。

写入仅限 `terrain_readability_tree_semantics.json`、`terrain_readability_tree_semantics_review.json` 和本任务说明。作者输入继续保持 `pending_author_review`；独立审查者读取修正后的精确输入并单独填写审查。语义区域、原图、冻结树冠、V1–V6、采集器、地图、相机和指标阈值保持原字节。

## 来源与验证

冻结树冠 `tests/claude_review/terrain_readability_crown_regions.json` 的 Git 文件是 7140 字节、LF 行尾，SHA256 为 `915256344f2674c8ade4fbd6dab47f182d7859453f8cc3b6022cdcc3eab26a27`。输入门对同一次读取的原始字节计算摘要；调用方必须使用这个精确来源，不能跳过校验或现场转换冻结文件。

本任务工作树创建时通过进程级 `core.autocrlf=false` 保持 Git 原字节；不修改共享 Git 配置。独审需核对作者区域未变、基础树冠与 Git blob 精确一致、审查范围和当前输入摘要一致。随后运行已有 40 项无窗口结构检查及 C8 源码检查。提交后的三个文件须与受审字节一致。

## 结果边界

本任务只修复输入绑定，完整 T3、旧墙和旧树的数值负例、语义图逐像素配准、云端采集和素材验收分别执行。TASK52 原件消费、独审、签名回执和实际关闭仍是下一云端任务的开始条件。保持既有两道门、API 测试分工和发布约束；不推送、不建 PR。
