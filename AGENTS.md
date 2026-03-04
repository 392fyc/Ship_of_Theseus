# AGENTS.md

> 面向 Codex、Cursor 及其他 AI 代理。与 `CLAUDE.md` 规则一致，此文件包含所有 Agent 需要的完整规则。

---

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

### 常用 KB 路径

```
03-AI-Context/Active-Context/current-session.md    — 会话状态
02-Development/Tasks/Phase1-Tasks.md               — 任务追踪
01-Game-Design/Core-Systems/battle-calculation.md   — 伤害公式
01-Game-Design/Characters/class-system.md           — 职业数据
01-Game-Design/Core-Systems/enemy-and-ai.md         — 敌人模板
02-Development/Decisions/                           — ADR 文件
```

---

## 会话协议

### 会话开始

1. 读取 `current-session.md`：
   ```
   obsidian_get_file_contents("03-AI-Context/Active-Context/current-session.md")
   ```
2. 从中识别当前 Phase 编号（如 M7 → Phase 1），读取对应任务文件：
   ```
   obsidian_get_file_contents("02-Development/Tasks/Phase{N}-Tasks.md")
   ```
3. 向用户展示：当前 Milestone、活跃任务、下一步、阻塞项
4. 根据任务类型建议读取相关设计文档

### 会话结束

1. 生成精简状态快照（≤100行，表格+列表，无叙述段落）
2. **全文替换** `current-session.md`（Read + Write，绝对路径）
3. **禁止** append（会导致维度爆炸）
4. 验证写入结果

---

## KB 写入决策树

### 追加到文件末尾
→ `obsidian_append_content(filepath, content)` — 始终安全

### 在特定标题下修改
- 标题为纯英文、无特殊字符 → `obsidian_patch_content` 安全
- 标题含中文/括号`()`/方括号`[]` → **不安全**，使用 Read + Edit 回退

### 替换整个文件
→ Read tool + Write tool（绝对路径）。Write 前**必须**先 Read。

### 创建新文件
→ Write tool（绝对路径），无需先 Read。

### 禁止的方法

| 方法 | 原因 |
|---|---|
| `obsidian_patch_content` 用于中文标题 | 静默失败或 `invalid-target` |
| `obsidian_patch_content` 用于含 `()` 标题 | `invalid-target` |
| PowerShell `Set-Content` / `Out-File` | UTF-8 BOM 问题 |
| `Write` 不先 `Read` | 工具拒绝操作 |
| `obsidian_append_content` 用于 session state | 无限增长 |

### KB 文档格式标准

- 标题**仅用英文**（Dashboard.md 除外）
- 不加 `> 中文标题` 副标题行
- 正文用英文
- 标题中避免 `()`、`[]`、中文字符

---

## 编码规范

### GDScript
- 类名 PascalCase，变量/函数 snake_case，常量 UPPER_SNAKE_CASE
- 信号 past_tense：`signal damage_dealt`, `signal unit_killed`
- GameAction模式：所有操作封装为可序列化Action
- class_name 与 autoload 同名 → 冲突，autoload 脚本**移除 class_name**
- Variant 类型推断不稳定 → **显式声明变量类型**

### 数据驱动
- 游戏内容 = JSON文件，代码只处理逻辑
- **禁止**在代码中硬编码数值，必须从JSON读取

---

## 已确认的错误模式

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

## 工作方法

### UI Playground 模式

涉及需要人工视觉审阅的工作，不直接实现，先建 Playground 供总控台判定后再应用。

- Playground 为独立文件，不污染主场景
- 每方案标注关键特征，方便对比选择
- 排布时机由总控台确认

---

## 参考

- `CLAUDE.md` — Claude Code 专用指令（含 skill 引用）
- `.claude/skills/` — Claude Code 专用 workflow skills

---

## Universal Agent Rules (from KB)

### Version Check
Any operation involving version numbers: WebSearch first, cross-verify 2+ sources, then reference.
Known versions (2026-03): Claude Opus 4.6 / Sonnet 4.6, GPT-5.3-Codex, Gemini 3.1 Pro, Godot 4.6

### Web Research Boundaries
L1 (precise): max 3 searches | L2 (survey): max 5 searches + 3 fetches, output comparison table | L3 (open): requires Main Agent approval + defined termination criteria

### Git Workflow
Branch naming: {agent}/{task-name}. No PR for personal work. Sub Agents create isolated branches/worktrees. Conflict resolution in neutral independent session only.
