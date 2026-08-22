# Spec Kit 外层采用方案

**状态：** 技术验证通过、尚未正式启用

**目标：** 把 Spec Kit 限定为可替换的运行控制层，并保持 Mercury、`AGENTS.md` 与 `sot-*` Skills 在没有 Spec Kit 时仍可独立工作。当前仓库中的 workflow 与专属测试只证明技术可行性，不表示日常任务已经切换到该流程。

## 一、采用结论

采用前必须遵守“一条规则一个拥有者”：同一任务事实、裁决或状态只在一个系统中定义，其他系统只传递引用或结果，不复制规则。

- Spec Kit 只拥有暂停、恢复、人工批准和 workflow 运行状态。
- Mercury 独占权威路由、任务拆分、代理边界、验证范围、独立审查和任务回执。
- `AGENTS.md` 只拥有进入仓库后始终生效的长期规则，例如权威入口、安全、分支和跨仓前置条件。
- `sot-*` Skills 只拥有对应领域的操作流程，不读取或复制 Spec Kit 的状态规则。
- Git/GitHub 继续拥有提交、任务范围和验收证据；三库继续各自拥有业务事实。

因此禁止建立第二份 task card、第二套审查流程、第二种回执或第二个任务状态机。Spec Kit 不解释 Mercury 合同，Mercury 也不复制 workflow 的暂停与恢复状态。

## 二、职责边界

### Spec Kit

Spec Kit 可以：

- 运行一个已获准的最小 workflow；
- 保存一次运行的状态；
- 在人工批准点暂停，并在取得批准后恢复。

Spec Kit 不可以：

- 决定目标仓、业务权威、任务规模或拆分方式；
- 生成或修改 Mercury task card、代理指令、验证范围、审查结论或回执；
- 保存或修改玩法、叙事、设计库、KB 或引擎业务事实；
- 建立自动修复循环、路径矩阵、验收 schema 或多轮审查状态机。

### Mercury

Mercury 是唯一任务编排者，负责：

- 确定唯一权威和目标仓；
- 将工作拆成一个主要交付物，并声明允许写入范围与停止条件；
- 决定主代理与子代理边界；
- 指定聚焦验证、安排独立审查并生成唯一任务回执；
- 在范围、风险或规模发生变化时停止并向用户升级，而不是让 workflow 自动扩张。

Mercury 可以选择使用 Spec Kit 保存外层运行状态，但其裁决不依赖 Spec Kit 文档或运行目录。

## 三、速度与 token 纪律

- S 级任务默认绕过 Spec Kit，由 Mercury 直接下发并完成；只有用户明确要求暂停、恢复或批准点时才使用 workflow。
- M/L 级任务也只有在确实需要可恢复的外层运行状态时才进入 Spec Kit；任务规模本身不构成启用理由。
- 主会话不设置 token 预算。子代理只接收完成当前交付物所需的简短 task card，不接收整份 Spec Kit 方案、workflow 历史或旧运行记录。
- 子代理不得读取 Spec Kit 文档、历史或 `.specify` 运行状态；需要的信息由 Mercury 在 task card 中一次性给出。
- 不以补充测试、重复审查或重写回执为理由扩大任务或无限消耗 token。证据不足时回到 Mercury，由其决定停止、拆分或升级。

## 四、最小运行方式

正式启用后，Spec Kit 外层最多表达以下状态变化：

1. Mercury 已完成路由和任务卡下发。
2. workflow 运行，或在人工批准点暂停。
3. 人工批准后恢复运行。
4. Mercury 接收执行结果，负责验证、独立审查和唯一回执。

workflow 不实现 `specify → plan → tasks → implement` 的第二套任务链，也不直接调用或约束 Codex 子代理。任何 task card、review、receipt 和执行状态机都只能有一个拥有者。

## 五、技术验证范围

当前验证固定使用 `uvx --from specify-cli==1.0.1 specify`，不安装或修改用户级工具。验证只确认：

- 本地 `sot-outer.yml` 能校验、安装和运行；
- 无效枚举输入被拒绝；
- 人工拒绝会暂停，批准后可恢复；
- 运行状态只进入 `.specify/workflows/runs/`；
- 核心 `AGENTS.md`、Mercury agents/contract 和 `sot-*` Skills 不引用 `sot-outer` 或 `.specify/workflows`。

这些结果只构成技术验证，不构成正式启用。正式启用、任务阈值调整和用户级 CLI 安装必须另行裁决。

## 六、完整切除边界

Spec Kit 必须能够作为一个整体切除。完整切除包含它拥有的全部表面，而不是只删除 workflow：

1. 用户级 Spec Kit CLI（仅在未来正式安装后适用）；
2. `.codex/project/workflows/sot-outer.yml`；
3. Spec Kit 专属测试；
4. `.gitignore` 中只服务于 Spec Kit 运行目录的规则；
5. `.specify/workflows/` 下的 runtime 与运行状态。

切除后不得修改 `AGENTS.md`、Mercury agents、Mercury task contract、`sot-*` Skills、设计库、KB 或玩法代码。Codex 必须仍能从仓库根读取原有规则，并由 Mercury 完成路由、拆分、代理边界、验证、审查和回执。

如果切除需要保留兼容 schema、迁移脚本、旧角色、第二测试矩阵或任何桥接状态机，则说明 Spec Kit 已侵入核心宿主，方案不成立。

## 七、正式启用门槛

正式启用需要另立任务并取得用户批准。该任务至少要确认：

- 是否安装固定版本 CLI；
- 是否接受新增的日常运行开销；
- 暂停、恢复、批准和运行状态确实需要跨会话保存；
- 完整切除边界仍成立。

在此之前，S/M/L 任务都继续以 Mercury 合同为唯一任务入口；S 级尤其保持默认直达执行。
