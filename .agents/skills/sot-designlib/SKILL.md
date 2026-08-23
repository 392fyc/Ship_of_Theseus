---
name: sot-designlib
description: "Read and safely modify the SoT structured design authority through its existing API or repository snapshot, with portable root resolution and verifiable receipts."
---

# SoT 设计库 lane

设计库 `SoT-fyc-space` 保存天赋、技能、规则、装备、遗物等**结构化玩法目标事实**；`Ship_of_Theseus` 保存**当前可执行实现事实**。数据流以设计库到游戏仓的消费方向为准，不从引擎侧反向裁决设计库内容。

## 1. 定位目标与加载合同

按以下顺序解析设计库根目录：

1. 环境变量 `SOT_DESIGNLIB_ROOT`。
2. 当前游戏仓中被忽略的 `.codex/project/sot-roots.local.toml` 内 `[roots].designlib_root`。
3. 两者都不存在时停止，并请求配置；不得猜测本机路径。

任何跨仓写入前必须：

1. 读取目标仓 `AGENTS.md`（若存在）。
2. 读取 canonical 合同 `docs/mercury-sot-lane-management.md`。
3. 获取目标仓当前 HEAD。
4. 在回执中记录 `target_head` 与 `contract_summary`。

代码修改只在设计库的独立 worktree 中进行，不在受保护主工作树中提交。

## 2. 读取现有来源

优先使用任务指定的现有来源，不建立第二套服务：

- 现有 API：`/api/talents`、`/api/skills`、`/api/equipment`、`/api/relics`、`/api/rules`、`/api/tags`、`/api/classes`、`/api/resources`、`/api/states`、`/api/judgments`。
- 仓库快照：`snapshots/` 下由设计库既有流程生成的版本控制文件。

需要全量读取时沿用端点现有查询参数：talents、equipment、relics 使用 `include_shelved=true`，skills 使用 `include_upgrades=true`。连接信息与鉴权只从受保护运行时配置取得，不在命令、日志或回执中回显。

内容审计必须遵守 canonical 合同 §6.5 的状态边界：先排除 `shelf_state`，再筛选 `status`；日常审计对象仅限“待审阅”和“待优化”。“草稿”、“待删除”（回收站）和“已归档”不得审计或作为参考；“锁定”只可作为参考。只有导入新规则改变适用依据，或其他流程发现有证据的具体矛盾时，才可按明确 ID 重新审计相关锁定内容，不得重开全部锁定内容。字段缺失或出现未知值时不得静默纳入。该边界适用于主代理、子代理、审查者和只读审计；使用 `include_shelved=true` 取得全量数据不代表扩大了审计集合。

每次读取都要记录：

- `schema_version`：响应或快照声明的版本；来源没有声明时写 `unversioned`，不得编造。
- `source_snapshot_or_commit`：快照相对路径及其提交，或 API 对应的来源提交/版本标识。
- `normalized_sha256`：把完整响应按键排序、UTF-8 编码并使用紧凑 JSON 规范化后计算 SHA256。

报告只给记录数量、字段类别与摘要，不输出凭据或受保护内容。

## 3. 生产数据写入

生产写入必须满足全部条件：

1. 用户或任务明确授权修改对应的设计事实。
2. 先生成 dry-run 计划，列出实体 id、字段、预期旧值摘要和新值摘要。
3. dry-run 经确认后才调用现有写接口。
4. 每一条写入后立即 readback，并与计划中的规范化结果比较；任一不一致立即停止。
5. 重新读取受影响集合，更新 `schema_version`、`source_snapshot_or_commit` 与 `normalized_sha256`。

批量操作不得触及任务范围外、已归档或待删除记录。不得新建第二套数据导出服务、反向引擎镜像字段或生产数据回灌工程；只消费现有 API 与仓库快照。

## 4. 设计库代码修改

- 遵守 canonical 的单写范围和目标仓 `AGENTS.md`。
- 在目标 worktree 中修改并运行目标仓既有测试与检查命令。
- 应用行为变更必须使用设计库既有部署流程；部署权限或配置缺失时明确报告阻断，不猜测运行时细节。
- 发布任务分支时，在目标仓 worktree 中调用当前 Ship 工作根的 `scripts/codex/sot-publish.ps1`。目标仓无需提供同名脚本；不得误报发布阻断，也不得改用原始 `git push`。
- 交付时记录目标分支、提交、验证命令、受保护 dirty 和未完成风险；实现者不得自行批准。

## 5. 禁止事项

- 不在版本控制内容中保存本机路径、主机、密钥位置、token、端口、容器名或部署密码。
- 不手改 `snapshots/`；生产数据变更后只运行设计库既有快照生成流程。
- 不把游戏仓的当前实现状态写成设计库的目标设计裁决。
- 不新增平行数据平台、反向镜像层或自动迁移体系。
