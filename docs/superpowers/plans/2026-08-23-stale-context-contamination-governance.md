# 失效上下文泄漏与失效内容污染治理实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立只保留当前有效结论的轻量治理合同，清理三库已确认的失效内容污染，并用固定规模的语义样本验证新会话、handoff、设计数据和实现说明。

**Architecture:** 用户级规则负责跨会话普遍行为；Ship、设计库和 KB 只保存各自需要执行的局部合同。每个维护任务冻结文件和最多 12 个完整命题，仅允许一轮独立审查与一轮集中修正；历史内容统一进入 ADR、Research、明确归档区或 Git 历史，不进入默认读取链。

**Tech Stack:** Markdown、Python/pytest、PowerShell、Git worktree、GitHub CLI、SoT 设计库现有 API 与快照流程、Obsidian MCP。

**Spec:** `docs/superpowers/specs/2026-08-23-stale-context-contamination-governance.md`

## Global Constraints

- 每批最多处理 12 个完整命题；超过时立即停止并重新拆批。
- 每批只安排一名独立审查者，只允许一轮审查和一轮集中修正。
- 审查只检查：旧结论复活、历史混入现行内容、无关纠错回顾、当前约束丢失。
- 范围外发现只记录位置、类别和所需权威，不复制旧正文，不扩大当前任务。
- 设计库日常审计对象仅限“待审阅”“待优化”；草稿、待删除、已归档不审计也不参考。
- 锁定内容只在本规则造成可定位矛盾时按明确 ID 处理。
- 不改变玩法、运行逻辑、结构化字段含义或玩家已经确认的必要否定约束。
- 实现工作只在各仓独立 worktree 完成；用户级文件单独 readback，不进入项目 Git。
- 主代理会话不设置 token 预算。子任务使用本计划给出的规模、文件和时间上限收束。

---

### Task 1: 用户级与 Ship 项目入口

**Size / ceiling:** S，20 分钟，3 个文件，6 个命题。

**Files:**
- Modify: `C:/Users/392fy/.codex/AGENTS.md`
- Modify: `AGENTS.md`
- Test: `tests/codex/test_sot_project_layer.py`

**Interfaces:**
- Consumes: 用户已批准的五条全局生成规则。
- Produces: 所有新 Codex 会话可见的普遍规则；Ship 子代理可见的项目局部规则。

- [ ] **Step 1: 在 Ship 项目层测试中锁定局部合同**

在 `tests/codex/test_sot_project_layer.py` 增加：

```python
def test_project_contract_keeps_only_current_conclusions() -> None:
    agents = read_text(ROOT / "AGENTS.md")
    for marker in [
        "当前有效结论",
        "完整命题",
        "历史记录",
        "默认读取链",
        "范围外发现",
    ]:
        assert marker in agents
```

- [ ] **Step 2: 运行测试取得 RED**

Run: `python -m pytest -q tests/codex/test_sot_project_layer.py`

Expected: 新测试失败，原因是 Ship `AGENTS.md` 尚无这组标记；其余既有测试通过。

- [ ] **Step 3: 写入用户级普遍规则**

在用户维护区加入 `## 当前结论清晰度`，正文只包含：

```markdown
- 同一范围内，用户较晚的修正取代较早结论；后续输出以修正后的当前事实为准。
- 当前答复只保留完成本次目标所需的信息。已取代内容不得通过纠错回顾、对比说明或自我辩解重新进入输出。
- 持久化前按完整命题核对主体、断言、适用范围和当前依据，不以否定词扫描代替语义判断。
- 每句话应承担当前事实、必要约束、真实未决问题、证据或下一步之一。
- 历史过程只进入明确的历史载体，不进入现行产物或默认上下文。
```

- [ ] **Step 4: 写入 Ship 项目局部合同**

在项目 `AGENTS.md` 增加简短的 `## 产物清晰度`：

```markdown
- 现行设计、代码注释、handoff 和任务卡只保存当前有效结论、必要约束、真实未决问题、证据与下一步。
- 持久化审查以完整命题为单位；历史记录进入 ADR、Research、明确归档区或 Git 历史，并退出默认读取链。
- 范围外发现只登记位置、类别和所需权威，不扩展当前任务。
```

- [ ] **Step 5: GREEN、readback 与提交**

Run:

```powershell
python -m pytest -q tests/codex/test_sot_project_layer.py
Select-String -LiteralPath C:\Users\392fy\.codex\AGENTS.md -Pattern 'Current-conclusion hygiene','完整命题','历史载体'
git diff --check
```

Expected: 项目层测试全绿；用户级三个标记各出现一次；Ship 只改 `AGENTS.md` 和测试。

Commit: `docs(harness): keep only current conclusions`

---

### Task 2: 设计库 canonical 瘦身与历史隔离

**Size / ceiling:** L，45 分钟，3 个文件，最多 12 个章节命题。

**Files:**
- Modify: `docs/mercury-sot-lane-management.md`
- Create: `docs/archive/mercury-sot-lane-management-history-2026-08-23.md`
- Create: `tests/test_mercury_lane_document.py`

**Interfaces:**
- Consumes: 当前 lane 权威、字段归属、回执、安全发布、§6.5 审计边界。
- Produces: 默认必读的精简 canonical；显式历史文件。

- [ ] **Step 1: 写 canonical 结构测试**

```python
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_mercury_lane_canonical_contains_only_current_contract() -> None:
    current = (ROOT / "docs/mercury-sot-lane-management.md").read_text(encoding="utf-8")
    history = (ROOT / "docs/archive/mercury-sot-lane-management-history-2026-08-23.md")
    for heading in [
        "权威与 lane 归属",
        "字段与目录边界",
        "协作与交付",
        "冲突检验",
        "内容审计的状态边界",
    ]:
        assert heading in current
    for stale_heading in ["在飞任务看板", "跨组收件箱", "即时连携：Agent Teams"]:
        assert stale_heading not in current
    assert history.is_file()
```

- [ ] **Step 2: 运行测试取得 RED**

Run: `.venv/Scripts/python.exe -m pytest -q tests/test_mercury_lane_document.py`

Expected: FAIL，原因是新结构和历史文件尚不存在。

- [ ] **Step 3: 隔离历史并重写当前入口**

把修改前全文保存到 `docs/archive/mercury-sot-lane-management-history-2026-08-23.md`，文件顶部标明：

```markdown
> 历史记录。仅供显式追溯，不属于 Mercury 或 SoT agent 的默认读取链，也不作为当前任务、流程或设计依据。
```

当前 canonical 收敛为以下五节：

1. `权威与 lane 归属`：结构化设计、运行实现、KB、GitHub/Git、Mercury 活跃记忆的单一权威。
2. `字段与目录边界`：保留当前目录分权、字段受众与导出边界；删除已退役字段和迁移经过。
3. `协作与交付`：只保留现行 worktree、单写、回执、受控发布和 PR 流程。
4. `冲突检验`：只保留当前可执行检查、提问候选集和工程状态纯指针规则。
5. `内容审计的状态边界`：原 §6.5 的现行六项规则原义不变，并加入“现行 artifact 不保存被否决正文，历史只给指针”。

- [ ] **Step 4: GREEN 与提交**

Run:

```powershell
.venv\Scripts\python.exe -m pytest -q tests/test_mercury_lane_document.py
git diff --check
git diff --name-only
```

Expected: 单文件测试通过；范围精确为三文件。

Commit: `docs(workflow): separate current lane contract from history`

---

### Task 3: KB handoff 默认链清理

**Size / ceiling:** M，35 分钟，4 个文件，最多 10 个命题。

**Files:**
- Modify: `00-Index/AI-Handoff-Guide.md`
- Modify: `00-Index/README.md`
- Modify: `03-AI-Context/Handoffs/handoff-template.md`
- Modify: `Templates/session-handoff.md`

**Interfaces:**
- Consumes: Mercury 活跃记忆与 GitHub/Git 的现行权威路由。
- Produces: 不携带完成过程和失效内容的 handoff 模板。

- [ ] **Step 1: 通过 Obsidian MCP 获取四份 document map 和版本**

对每个文件调用 `vault_get_document_map`，记录 `version`；随后只读取待改章节。若任一文件不存在或版本在 patch 前变化，停止本任务。

- [ ] **Step 2: 更新 handoff 合同**

四处共同使用以下当前性规则，只在 guide 完整陈述，模板中使用简短检查项：

```markdown
Handoff 只携带当前已确认结论、真实未决问题、下一步和必要证据链接。已被取代、否决、删除或已经完成的过程不进入起始指令；需要追溯时只链接 ADR、Research、明确归档记录或 Git 证据。
```

删除对不存在的 `03-AI-Context/Active-Context/current-session.md` 的强制读取和写入。当前入口改为 Mercury `.mercury/memory`，任务与验收状态改为 GitHub/Git。

- [ ] **Step 3: 用 ifMatch 执行结构化 patch 并逐项回读**

每个文件只执行自身章节 patch；每次 patch 后调用 `vault_read` 回读。不得使用整文件覆盖。

- [ ] **Step 4: 聚焦验证与提交**

在 KB Git 根运行：

```powershell
$files = @(
  '00-Index/AI-Handoff-Guide.md',
  '00-Index/README.md',
  '03-AI-Context/Handoffs/handoff-template.md',
  'Templates/session-handoff.md'
)
$text = ($files | ForEach-Object { Get-Content -Raw -LiteralPath $_ }) -join "`n"
if ($text -match 'Active-Context/current-session\.md') { throw 'stale handoff entry remains' }
git diff --check
```

Expected: 旧入口无匹配；四文件均包含当前性规则或模板检查项。

Commit: `docs(handoff): carry only current conclusions`

---

### Task 4: 设计库当前天赋 notes 清理

**Size / ceiling:** M，35 分钟，4 个实体、4 个命题；生产写入前有一次 dry-run 确认门。

**Entities:**
- `kensei_jianqihuidang.notes`
- `kensei_jiaoren.notes`
- `kensei_lixing.notes`
- `kensei_wanxiangguiyi.notes`

**Interfaces:**
- Consumes: live API 当前实体、设计库审计状态边界、设计意图。
- Produces: 不含旧名称、改版经过和引擎接入状态的当前 notes。

- [ ] **Step 1: 读取 live API 并验证资格**

记录 `schema_version`、来源提交和规范化 SHA256。四个实体必须全部满足 `shelf_state=已上架` 且 `status` 为“待审阅”或“待优化”；任一不满足即从本批排除并报告，不用其他实体补位。

- [ ] **Step 2: 生成精确 dry-run**

目标 notes：

```json
{
  "kensei_jianqihuidang": "设计簇：双刀池（硬前置：二天一流）。主副呼应轴——主手的暴击回荡到副手，双刃同炽。",
  "kensei_jiaoren": "设计簇：双刀池（硬前置：二天一流；没有二天一流时本卡不出现）。生存补偿轴——对冲二天一流失去防具槽的代价。名取“交刃”：双刃交叉承刀。",
  "kensei_lixing": "印记池开启器：破除心、道、势各一的定式，构成交给天意。持有三枚印记时会形成随机组合，并与按构成或数量结算的效果联动。名取《庄子》“离形去知”：脱离形式，随心而行。",
  "kensei_wanxiangguiyi": "印记池倾泻轴：按本次消耗的印记构成强化一次攻击。名取“森罗万象”：万象聚于一手，归于一刀。没有改变印记构成的效果时，按心、道、势各一枚结算；构成发生变化时，以实际消耗的印记为准。数值仍待平衡阶段定稿。"
}
```

dry-run 只显示实体 ID、字段、旧值摘要和新值全文，不输出凭据。按 `sot-designlib` 合同向用户请求这一次生产写入确认。

- [ ] **Step 3: 写入、逐项 readback 和重新取摘要**

确认后使用既有 PATCH API。每写一条立即 GET 回读并做规范化比较；任一不一致停止剩余写入。

- [ ] **Step 4: 生成快照并提交**

使用设计库现有快照导出命令，不手改 `snapshots/`。验证四个 notes 与 live 一致，运行对应 snapshot/round-trip 聚焦测试和 `git diff --check`。

Commit: `data(talents): remove superseded design history from notes`

---

### Task 5: Ship 实体说明字段清理

**Size / ceiling:** M，30 分钟，4 个文件，最多 8 个命题。

**Files:**
- Modify: `data/talents/kensei_jianqihuidang.json`
- Modify: `data/talents/kensei_jiaoren.json`
- Modify: `data/talents/kensei_yanfan.json`
- Modify: `data/states/shuangchi.json`

**Interfaces:**
- Consumes: 当前 JSON 结构、当前设计库 effect/rules、当前运行字段。
- Produces: 只解释当前引擎合同的 `engine_note` / `_designlib_wording`。

- [ ] **Step 1: 写冻结断言脚本并取得 RED**

在任务执行命令中读取四个 JSON，断言以下历史标记不存在：`改版前`、`初版`、`任务书`、`此前 Wave`、`写反了方向`。首次运行应失败；脚本不提交为新框架。

- [ ] **Step 2: 最小改写说明字段**

- `kensei_jianqihuidang.engine_note`：只保留 `empower_next_offhand` 的两个子效果、命中后返气、一次消费和结构字段映射。
- `kensei_jiaoren.engine_note`：只保留共用招架减伤权威、未命中不扣气、每次攻击一次和当前已知的主副手事件边界；删除纠错经过。
- `kensei_jiaoren._designlib_wording`：改为“设计库 rules 使用规则表术语；引擎运行字段使用当前代码标识符，两者各自按所属权威维护。”
- `kensei_yanfan.engine_note`：只保留递减追加、`self_retriggerable=true`、沿用触发它的副手伤害规格和异常循环护栏。
- `shuangchi._engine_note`：只保留当前 predicate、`Unit.is_dual_wielding()` 和不可求值时拒绝注册的当前约束。

- [ ] **Step 3: JSON 与行为边界验证**

Run:

```powershell
$files = @(
  'data/talents/kensei_jianqihuidang.json',
  'data/talents/kensei_jiaoren.json',
  'data/talents/kensei_yanfan.json',
  'data/states/shuangchi.json'
)
foreach ($file in $files) { Get-Content -Raw -LiteralPath $file | ConvertFrom-Json | Out-Null }
$text = ($files | ForEach-Object { Get-Content -Raw -LiteralPath $_ }) -join "`n"
if ($text -match '改版前|初版|任务书|此前 Wave|写反了方向') { throw 'historical residue remains' }
git diff --check
```

人工 diff 核对只允许 JSON 说明字符串改变，结构化运行字段逐字不变。

Commit: `docs(data): keep engine notes on current behavior`

---

### Task 6: Ship 当前代码注释与测试说明清理

**Size / ceiling:** M，35 分钟，4 个文件，最多 12 个注释命题。

**Files:**
- Modify: `scripts/data/state_registry.gd`
- Modify: `scripts/data/talent_registry.gd`
- Modify: `scripts/core/tactical_manager.gd`
- Modify: `tests/test_talent_onhit.gd`

**Interfaces:**
- Consumes: 当前运行代码和当前测试断言。
- Produces: 只说明当前不变量的注释；运行代码和断言不变。

- [ ] **Step 1: 冻结非注释内容**

执行一个临时 PowerShell 检查：对三个 `.gd` 产品文件删除空行和以 `#` 开头的行后计算 SHA256；记录任务前摘要。测试文件同时记录所有 `_eq`、`_ok` 调用行的规范化摘要。

- [ ] **Step 2: 删除历史叙述并改成当前不变量**

- `state_registry.gd`：保留“条件状态每次读取时求值”“special Buff 需要消费方”“不可求值条件拒绝注册”；删除旧先例、替代路线和补丁史。
- `talent_registry.gd`：保留状态可求值、条件模型和当前字段边界；删除 Wave 任务书争议。
- `tactical_manager.gd`：本批只处理剑气回荡及相邻防御侧注释；保留“副手实际命中后返气”的当前理由，删除对旧卡面的依赖。目标模式的 legacy fallback 属兼容路径，另登记范围外位置，不在本批改动。
- `test_talent_onhit.gd`：测试名称和注释只描述当前预期；删除“改版前”“新旧分水岭”“任务书说错”等过程语句，断言不变。

- [ ] **Step 3: 验证无运行改动**

重新计算 Step 1 摘要，要求完全一致。再运行项目可用的 GDScript 静态解析或现有 `test_talent_onhit.gd` 入口；本机没有 Godot console 时，记录环境限制，但非注释摘要一致性必须通过。

Run: `git diff --check`

Commit: `docs(engine): remove superseded history from comments`

---

### Task 7: KB 现行设计文档清理

**Size / ceiling:** M，40 分钟，4 个文件，最多 12 个命题。

**Files:**
- Modify: `01-Game-Design/Characters/kensei-slash-memory-upgrades.md`
- Modify: `01-Game-Design/Characters/talent-tree.md`
- Modify: `01-Game-Design/game-design-doc.md`
- Modify: `03-AI-Context/content-design-general.md`

**Interfaces:**
- Consumes: 设计库当前结构化事实、已批准审计边界、现行内容设计规则。
- Produces: 只陈述当前设计意图和真实未决问题的 KB 现行文档。

- [ ] **Step 1: 取得四份 document map、版本与目标章节**

使用 Obsidian MCP；只读取计划列出的章节。写前再次核对设计库 live/snapshot 当前名称和字段，不复制完整结构化数据。

- [ ] **Step 2: 清理现行设计内容**

- `kensei-slash-memory-upgrades.md`：删除“进入删除的旧方案”和“已排除的探索方向”；全文统一使用当前技能名；删除已漂移的完整数值表，只保留成长性、命中不受必中延长、发动条件等设计依据，并指向设计库技能实体。
- `talent-tree.md`：删除旧点数表和旧候选数字；真实未决项只写问题本身；移除已脱节工具和已作废槽位的墓碑提醒。
- `game-design-doc.md`：删除已脱节编辑器警告，只描述当前卡池入口。
- `content-design-general.md`：日常审计对象改为待审阅/待优化；草稿、已归档、待删除不参考；锁定只按新规则或具体矛盾的明确 ID 重审。删除被否决提案示例，保留当前正面原则。

- [ ] **Step 3: ifMatch patch、回读和聚焦验证**

逐文件 patch 与回读。随后在 KB Git 根运行：

```powershell
$current = @(
  '01-Game-Design/Characters/kensei-slash-memory-upgrades.md',
  '01-Game-Design/Characters/talent-tree.md',
  '01-Game-Design/game-design-doc.md',
  '03-AI-Context/content-design-general.md'
)
$text = ($current | ForEach-Object { Get-Content -Raw -LiteralPath $_ }) -join "`n"
if ($text -match '进入删除的旧方案|已排除的探索方向|草稿条目仅供参考|固定拓扑树时代') { throw 'current/history mixture remains' }
git diff --check
```

必要否定约束由独立审查者逐句核对，禁止按上述词表以外的否定词自动删除。

Commit: `docs(design): separate current decisions from history`

---

### Task 8: 六样本验收、PR 与里程碑收口

**Size / ceiling:** M，30 分钟；不新增产品文件；一名独立验收者。

**Files:**
- Verify: 用户级 `C:/Users/392fy/.codex/AGENTS.md`
- Verify: Ship、设计库、KB 各任务提交及工作树
- Verify: Spec 与本计划

**Interfaces:**
- Consumes: Task 1–7 候选提交和生产 readback。
- Produces: 一份结构化验收回执、三个仓库 PR/合并证据、下一里程碑入口。

- [ ] **Step 1: 冻结验收包**

只包含：规格、计划、Task 1–7 changed files、各自测试/回读证据和六个样本。验收者不得读取未改动的全库内容，除非是 changed artifact 直接引用的当前权威。

- [ ] **Step 2: 运行六个语义样本**

逐项返回 PASS/FAIL：

1. 后续方案取代先前方案，现行产物只含后续方案。
2. 三个无关轮次后仍只使用当前结论。
3. 无关任务不回顾旧纠错。
4. 当前禁止性规则继续生效，但不复制到无关产物。
5. ADR 保存历史，玩家数据和现行设计不保存历史。
6. handoff 和子代理输入只携带当前结论与真实未决项。

- [ ] **Step 3: 独立验收**

验收只检查四类语义失败和以下工程证据：范围、测试、readback、快照、Git clean、秘密扫描类别结果。最多返回 12 个 finding；超过即判“拆分不足”并停止，不继续展开。

- [ ] **Step 4: 单轮集中修正**

只处理验收 finding；使用原检查集复核。不得添加相邻优化、第二审查者或新测试体系。

- [ ] **Step 5: 发布、PR、合并与核对**

Ship 与设计库使用 `scripts/codex/sot-publish.ps1` 先 dry-run 后发布；KB 使用其现有安全发布路径。分别创建 PR：Ship→`develop`，设计库→`master`，KB→其当前受保护默认分支。核对 merge commit、远端默认分支和开放 PR 数量。

- [ ] **Step 6: 里程碑回执**

回执必须区分：各 Task 完成、整个治理里程碑完成、未进入本里程碑的范围外候选。下一步恢复“首批回忆/其他非独特天赋设计内容”里程碑，不重新开启本治理审计。
