# 地形同帧基线：首轮材料失败原件消费

## 当前结论

本记录只完成 TASK42 首轮材料失败原件的消费。任务处理计数为 1，Godot 进程为 0；材料一致性为 FAIL，六组原生像素与 T1–T6 均为 NOT_TESTED。TERRAIN-READABILITY-01 未修复，基础战斗 UI 与 P0/CR-01 Milestone 未完成。

固定采集候选为 `d4d53d1934e631ccc17940a1b19d1a68561ec722`，tree 为 `5d3ff01073cd43ee95239f47217fc23b14d9dab8`。首轮 request 为 `451714b0-d241-4c13-b0a3-1be35c7273fe`，task 为 `0c554586-1350-49a8-b07d-33bf5a672f9f`，attempt1/seq42。

## 失败与实际执行范围

原签名正文的 archive_sha256 为 65 位，绑定清单的正确摘要为 64 位；原信封保持不动。YC 在固定协议的身份、授权及登记前置核验后唯一领取，仅登记材料失败，实际同代账本为 failed/count1。没有拼装归档、导入、检出游戏、采集 PNG 或计算美术指标。

Main 核对了 YC 原根明确采用的失败 RESULT、完整映射及账本失败证据。42 份证据原件共 632,830 字节，13 份传输文件的字节数与 SHA256 全部一致；35 份容器原件均按原字节还原。原 claim 回包为 running/count1，failed 回包与 Main 实际查询均为 failed/count1，绑定同一个材料失败证据摘要。服务计数表示任务处理领取次数，不能当作游戏进程数。

完整引用、大小和摘要见 original-consumption-index.json。大原始报告保留在私有 Page 和仓库外证据根，版本化文件只保存精确映射，不复制云端或本机绝对路径。RESULT 在创建时记录 root adoption pending，之后由 YC 原根明确采用；本记录采用后者的真实聊天证据。旧 20159 字节 RESULT 是未采用草稿，采用原件为 21042 字节。

## 消费与后续边界

签名 RECEIPT43 仅记录首轮失败原件已消费，不要求 failed 转为 closed，也不重新领取首轮。原 FAIL/NOT_TESTED 保持。允许同 task_id 的新 request、nonce 与 attempt2；修正请求的执行记录另存 dot-attempt2，不把首轮变为 PASS。

35 份执行材料及候选未改变。manifest(1).json 是浏览器文件名别名，其真实身份、字节和摘要与 manifest.json 一致。完整归档只在 Main 本地按原字节核验；本首轮云端未拼装，云端完整归档核验为 NOT_TESTED。

本 Task 仅新增当前运行记录，不修改冻结工具、生产代码、素材、玩法或旧记录。没有推送、PR、用户视觉批准或素材修复结论。
