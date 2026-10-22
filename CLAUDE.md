@AGENTS.md

# Ship of Theseus 的 Claude Code 入口

本文件只补充 Claude Code 宿主差异；项目规则、权威划分、安全要求、Git 发布和工作树约束以导入的 AGENTS.md 为准。开始工作前仍需读取当前任务目标、验收标准、允许写入路径和目标仓合同。

## 模型与角色

- Ship 主会话使用最新 Opus：从游戏仓根目录启动时使用 claude --model opus，也可在会话中选择 /model opus。Markdown 指令不能替当前会话设置主模型。
- 用户级代理文件使用 Claude Code 的 YAML frontmatter。执行与研究角色使用 model: sonnet；独立审查与盲验收使用 model: opus。别名由 Claude Code 按当前登录的官方提供方映射到推荐版本，不固定模型 ID。
- 简单、顺序任务由主会话直接完成。只有独立工作流可并行、需要隔离上下文或任务合同要求独立审查时，才使用对应子代理。

## 根目录解析

- Ship 根目录依次从 SOT_SHIP_ROOT、用户级本地 roots 文件 ~/.claude/mercury-roots.local.json 的 roots.ship_root、以及当前 Ship 仓被忽略的 .codex/project/sot-roots.local.toml 的 [roots].ship_root 解析。设计库与固定 KB vault 分别优先使用 SOT_DESIGNLIB_ROOT、SOT_KB_ROOT，再从可信用户级 roots 提供项或已解析的 Ship 本地 roots 文件读取明确配置的值。活跃记忆根按 AGENTS.md「活跃记忆根」一节解析。
- 任务工作树目录组优先使用各自的 SOT_*_WORKTREE_ROOT 环境变量，再读取本地 roots 文件的 [worktrees]。未解析出明确根目录时停止并说明缺少哪项配置；禁止从父目录、兄弟目录或相似路径猜测。
- 本机 roots 配置可保存绝对路径与本地运行参数；这些本机值和凭据不得写入版本控制、分享包、聊天或回执。

## SoT 专项规则

- 结构化玩法目标事实归 SoT-fyc-space 设计库；当前可执行行为归 Ship 游戏仓；叙事、定性设计、用户裁决、ADR 与研究归 KB；任务状态归 GitHub/Git；活跃会话锚点归配置的活跃记忆根（见 AGENTS.md）。
- 设计库和游戏代码工作使用已解析游戏根中的 scripts/codex/sot-worktree.ps1 管理任务工作树，并从已解析工作根调用 scripts/codex/sot-publish.ps1 发布。不得直接向受保护分支推送。
- KB 始终使用唯一固定 Obsidian vault；任务隔离通过该 vault 的 Git 任务分支完成。禁止另开任务 vault、切换 MCP endpoint、绕过分支占用或丢弃改动。写前确认 vault、目标分支与工作区状态，MCP 写入使用版本条件，写后立即回读。
- 生产设计数据写入必须有明确授权，先 dry-run，逐条写入后 readback，再读取受影响集合并记录 schema、来源版本与规范化摘要。
- 实现、审查和验收职责分离。需要交付回执时使用 sot-task-receipt 技能，并提供本次执行的证据；不得把自评当成独立批准。

## 从设计库或 KB 直接启动

SoT 与 Mercury agents 和 skills 安装在 Claude 用户级目录，可从不同仓库启动时复用。用户级只读 SessionStart hook 从 SOT_SHIP_ROOT 或用户级本地 roots 文件的 roots.ship_root 解析 Ship 根，并提供 Ship AGENTS.md 路径；会话必须读取该文件正文。若 hook 未提供路径，则显式解析 Ship 根并读取 AGENTS.md；缺少明确根时停止询问，不从相邻仓库推断。Ship 的项目级 CLAUDE.md 不会因另一仓库位于相邻目录而自动生效。

## 配置来源

.codex/agents/*.toml 仍是 Codex 的源配置。用户级 Mercury 代理是从三个 TOML 角色说明只读派生的独立 Claude 文件，不由 Mercury 的 TOML 同步器生成；原 TOML 与同步锁保持原样。SoT 代理和六个技能依据当前 Ship 源文件派生，旧 Claude 技能不作为来源。代理与技能安装在 Claude 用户级目录，Ship 根 CLAUDE.md 保持项目级。本配置不包含 MCP endpoint、密钥或其他凭据。

## 领域经验与查证指针

以下是实装与查证中踩过的坑和规则落点，不重复 AGENTS.md 已有约束。

### DO NOT — GDScript

- class_name 与 autoload 同名 → autoload 脚本**移除 class_name**
- **内部类（`class Foo extends X:`）与某个全局 `class_name Foo` 同名** → `Parse Error: Class "Foo" hides a global script class`，**整个文件 parse 失败**。与上一条是两回事（那条是 autoload，这条是普通全局类）。抽出全局类时**记得删掉原文件里的同名内部类**——`skillbar_playground.gd` 就是抽出 `DamageForecaster` 时漏删，坏了两个月（2026-08-12 修，内部类改名 `_ForecastPanel`）
- Variant 类型推断 → **显式声明变量类型**
- **禁止**在代码中硬编码数值，必须从JSON读取

#### 测试里不要这样判「脚本 parse 成功没有」

- **`load(脚本路径) != null` 不是 parse 判据**（2026-08-12 实测）：脚本 parse 失败时 `load()` **仍可能返回非 null**，且行为随调用时机与资源缓存状态而变（在 `_initialize` 里探测与在 `_process` 里探测结果不一样）。拿它当护栏会得到一条永远绿的假断言。
- **`packed.instantiate() != null` 更不行**：场景在附着脚本 parse 失败时照样实例化得出来——脚本变成 null、节点还在。`test_skillbar_playground_load.gd` 旧版就是只查这两条，于是上面那个 parse 错误坏了两个月而回归全绿。
- **可靠的是**：实例化后断言 `node.get_script() != null`（脚本真挂上了），再断言 `get_script().resource_path` 就是期望的那个（挂的是对的那一个）。
- 要一条真正等价于 `--check-only` 的，得在**回归脚本层面**对关键脚本各跑一次 `--check-only` 并断言退出码——那是测试基础设施改动，**尚未做**。

#### 「升级」在本项目是两个意思，查证时别混

中文「升级」同时指两件**毫不相干**的事，扫全库时最容易在这里得出反的结论：

| 说的是 | 引擎里有没有 | 怎么查 |
|---|---|---|
| **角色升级**（Lv1→Lv5 成长、升级得天赋点） | **有** | `data/classes/myrmidon.json` 的转职成长说明、`data/relics/relic_mentor_tome.json`、`data/runloop/act1_config.json` |
| **技能升级链**（回忆天赋永久把某技能换成升级版；设计库 `Talent.upgrade_skill_id` ↔ `Skill.upgrade_of`，12 张在用） | **没有，零承载** | `grep -rni upgrade scripts/` → 零命中；`data/talents/` `data/skills/` 均无该字段 |

**查后者请用 `upgrade` 而不是「升级」**：用 `upgrade` 查是干净的（零命中）；用「升级」扫 `data/` 会撞上表第一行那三个文件的假阳性，看到 3 处命中很容易误判成「引擎已经有升级概念」。

引擎现有的 `slot_swap_trigger` / `slot_swap_target` / `slot_swap_provider` 是**局内动态替换**（印记满 3 → 招架换拔刀），**不是**技能升级链，两者别互相套用。

（2026-08-12 实测登记。这一栏是否要补承载字段尚未裁决，届时按 lane §2.2 先入字段归属表再写代码。）

### DO NOT — KB

- **禁止** PowerShell 写入 KB 文件（UTF-8 BOM 问题）
- **禁止** 对 current-session.md 使用 append（维度爆炸），始终全文替换
- KB 标题中**禁止**括号 `()`、方括号 `[]`、中文字符（导致 obsidian_patch_content 失败）

### DO NOT — AI

- **禁止**用训练数据判断版本号。版本查询必须先 WebSearch，交叉验证 2+ 来源

### 游戏机制 — 只给指针，不复述

规则正本 = **设计库规则表**（`/api/rules`，共 23 条：R1.1–R1.10 / R2.1–R2.4 / R3.1–R3.4 / R4.1–R4.4 / R5.9）。
离线可读的全量索引 = KB `01-Game-Design/rules-catalog.md`（每条一句话 + 展开文档链接）；逐字原文 = 设计库仓库 `snapshots/rules.json`。
按 AGENTS.md「权威路由」与「玩法事实核对」，本文件**不复述规则内容**——写战斗 / 技能 / 伤害逻辑前回查真源，不要凭本文件或凭记忆作答。

最常问错的几处，直接给落点：

| 要确认什么 | 查这里 |
|---|---|
| 伤害怎么算、hybrid 怎么合、纯粹伤害是什么 | R1.1；展开见 KB `01-Game-Design/Core-Systems/battle-calculation.md` |
| 命中 / 暴击怎么算，哪些属性参与 | R1.2 / R1.3 |
| 某个修正该落在哪一层，什么时候取整、什么时候 clamp | R1.8 |
| 一次效果对同一单位结算几次，会不会自己触发自己 | R1.9 / R1.10 |
| 技能消耗什么行动资源、什么时机能放 | R3.2 / R3.3 |
| 速度到底影响什么（有没有速度带来的追击） | R3.1 |
| 建筑受伤走不走伤害公式，摧毁后那格变成什么 | 规则表无此域 → KB `01-Game-Design/Core-Systems/grid-and-map.md` §建筑耐久系统 |
| 受击方会不会自动反击 | 规则表无此域 → KB `01-Game-Design/Core-Systems/battle-calculation.md` §反击系统 |

R1.1 / R1.2 / R1.3 各自列全了本链的层与乘区。规则层没有列出的因素（例如距离）**不要自行补进公式**；要让某个因素参与结算，必须由技能 / 天赋 / 遗物条目显式声明，并按 R1.8 落到指定的层。
