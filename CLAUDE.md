# CLAUDE.md

## Language

设计文档为中文（简体）。讨论设计、游戏机制、文档时用中文，除非用户切换为英文。

---

## 项目概述

战棋RPG + Roguelite + 城镇建设，Godot 4.6 (GDScript)。
支持单机1人 / 联机1-4人。

| 层 | 技术 |
|---|---|
| 引擎 | Godot 4.6 (GDScript) |
| 数据 | JSON驱动（游戏内容全JSON，代码只处理逻辑） |
| 联机 | Godot High-Level Multiplayer API, Host-Client |
| 架构 | GameAction指令驱动（联机广播同步） |

---

## 知识库（唯一正本）

设计文档正本：Obsidian Vault `D:\ShipOfTheseus\ShipOfTheseus-KB\`
- 通过 MCP 工具（`obsidian_*`）访问，任何工作目录均可用
- `dev_doc/` 已归档不再更新
- 游戏规则、伤害公式、设计决策 → 查 KB，不在此文件复述

**会话开始**：使用 `/sot-session-start` skill（或手动执行 `obsidian_get_file_contents("03-AI-Context/Active-Context/current-session.md")`）
**会话结束**：使用 `/sot-session-end` skill（或手动更新 `current-session.md`，Read + Write，≤100行）
**KB 写入**：使用 `/sot-kb-write` skill 选择最可靠的写入方法

---

## 编码规范

### GDScript
- 类名 PascalCase，变量/函数 snake_case，常量 UPPER_SNAKE_CASE
- 信号 past_tense：`signal damage_dealt`, `signal unit_killed`
- GameAction模式：所有操作封装为可序列化Action

### 数据驱动
- 游戏内容 = JSON文件，代码只处理逻辑
- **禁止**在代码中硬编码数值，必须从JSON读取

---

## 工作方法

### UI Playground 模式

**适用场景**：涉及需要人工视觉审阅的工作，不直接实现，先建 Playground 供总控台判定后再应用。

| 适用 | 不适用 |
|------|--------|
| 游戏内 UI 样式（HUD / 面板 / 弹窗 / 对话框）| 纯逻辑/数据层实现（无需视觉审阅）|
| 素材视觉风格（角色/地形/特效，需人眼判断）| 已有明确设计结论的工作 |
| 颜色方案、字体、布局间距等视觉参数 | |
| 「哪种更合适」类视觉选择 | |

**流程**：
1. Cursor 构建**独立** Playground 文件（不影响主场景），呈现 A/B/C 多方案
2. 人工总控台在 Playground 中观察并选定
3. 选定后方可将方案应用至正式场景

**原则**：
- Playground 为独立文件，不污染主场景
- 每方案标注关键特征，方便对比选择
- Playground 保留/清理由总控台决定
- **排布时机**：可在任务中合适区间安排，无需立即执行，等待总控台确认再开始

---

## ADR 索引

| ADR | 标题 | 文件 |
|-----|------|------|
| ADR-001 | Grid Coordinate System | adr-2026-02-26-grid-coordinate-system.md |
| ADR-002 | Buff/Debuff Structure | adr-2026-02-26-buff-debuff-structure.md |
| ADR-003 | Unit-Cell Bidirectional Reference | adr-2026-02-26-unit-cell-reference.md |
| ADR-004 | Four Damage Types | adr-2026-02-27-damage-type-redesign.md |
| ADR-005 | Attribute System v1 | adr-2026-02-27-attribute-system-v1.md |
| ADR-007 | Multi-Agent Toolchain Optimization | adr-2026-03-03-multi-agent-toolchain.md |

---

## 已确认的错误模式

> 此节仅收录模型**反复犯错后**经纠正确认的模式。新规则需经人工总控台批准后添加。

### Godot 4.6 兼容性
- class_name 与 autoload 同名 → 冲突，autoload 脚本**移除 class_name**
- Variant 类型推断不稳定 → **显式声明变量类型**

### KB 写入标准
- KB 文档全英文（标题 + 正文），Dashboard.md 除外
- 标题仅用英文，不加 `> 中文标题` 副标题行
- 标题中避免括号 `()`、方括号 `[]`、中文字符（会导致 obsidian_patch_content 失败）
- KB 写入方法选择 → 使用 `/sot-kb-write` skill 的决策树
- **禁止**用 PowerShell 写入 KB 文件（UTF-8 BOM 问题）
- **禁止**对 current-session.md 使用 append（会导致维度爆炸），始终全文替换

### AI 工具查询
- **禁止用训练数据判断 AI 模型版本**。涉及模型版本号时，必须先 WebSearch 再作答

### 游戏机制陷阱
- 格挡和暴击同时生效 → **互斥**
- pure伤害触发格挡 → **无视**；pure暴击倍率受加成 → **固定1.5x，不受加成**
- hybrid使用单一atk → **phys_atk + mag_atk 同时生效**，武器倍率取平均
- 反击触发反击 → **不触发**，也不触发追击
- 追击触发追击或反击 → **不触发**
- area攻击触发反击 → **不触发**
- 建筑耐久用伤害公式 → **固定扣减**
- 建筑摧毁恢复地形效果 → **变废墟**
- 距离影响伤害/命中 → **无衰减**
- 多个敌方ZOC叠加 → **不叠加**，固定-2
- 向敌人方向移动触发ZOC → **不触发**，仅从控制区离开时触发

---

## Universal Agent Rules

### Version Check
Any operation involving version numbers must follow this sequence:
1. WebSearch for the latest version first
2. Cross-verify with at least 2 independent sources or official documentation
3. Only then may the version be referenced in subsequent work

Applies to: AI models, game engines, SDKs, libraries, plugins.

Known versions (as of 2026-03): Claude Opus 4.6, Sonnet 4.6 | OpenAI GPT-5.3-Codex | Google Gemini 3.1 Pro | Godot 4.6

### Web Research Boundaries

**L1 Precise Query** (max 3 searches): Clear target, stop on find. Examples: Godot 4.6 API, version confirmation.

**L2 Directed Survey** (max 5 searches + 3 fetches): Clear scope with structured comparison table deliverable. Examples: asset search, solution comparison.

**L3 Open Research**: Broad scope requiring Main Agent approval, defined deliverable format, and termination criteria before execution.

### Git Workflow

Branch naming: `{agent}/{task-name}`. Examples: `cursor/pkg-e-battle-ui`, `codex/batch-json-gen`, `ag/parallel-task-xxx`

**Personal work**: No PR required. Direct merge to feature branch after completion.

**Sub Agent isolation**: Each task creates independent branch/worktree. Different agents never work on same branch. Sub Agent notifies Main Agent on completion.

**Conflict resolution**: Use neutral independent session, pull both branches, perform merge, review, then merge to target.

### Agent Task Matrix

| Task | Agent | Note |
|------|-------|------|
| GDScript implementation | Cursor | Primary development agent |
| Godot editor / debug | Cursor | Godot MCP exclusive — single client only |
| Playground proposals | Cursor | Visual proposals in Godot |
| Batch JSON / data gen | Codex CLI | GPT-5.3-Codex, sandbox safe |
| Codebase research | Codex CLI or AntiGravity | Do NOT use Claude for large file research |
| Asset creation (sprite/animation/music) | AntiGravity (Gemini 3.1 Pro) | Gemini multimodal + web plugins |
| Design / KB / orchestration | Claude Code | Main Agent only — no self-spawning Sub Agents |

**Sub Agent dispatch rule**: When the user says "dispatch to Sub Agent", this means instructing external tools (Cursor, Codex CLI, AntiGravity) — NOT spawning Claude internal agents via Task tool.
