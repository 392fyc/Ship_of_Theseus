# ShipOfTheseus Knowledge Base Navigation

> This is the navigation hub for the Ship of Theseus knowledge base. Active memory lives in Mercury `.mercury/memory`; task, progress, and acceptance state live in GitHub/Git.

## Project Overview

- **Genre**: TRPG + Roguelite + Town Building
- **Engine**: Godot 4 (GDScript)
- **Scale**: Single-player / 1-4 player co-op multiplayer

## Directory Navigation

| Directory | Content | Primary AI |
|------|------|------------|
| [[01-Game-Design/]] | Qualitative game-design documents and navigation mirrors | Claude |
| [[02-Development/]] | ADRs, archived work records, and workflow references; not live task status | Claude / Cursor / Codex |
| [[00-rules/]] | Agent guidance and archived handoff records; not active memory | All AI |
| [[04-Assets/]] | Art and audio asset requirement lists | Codex / Gemini |
| [[05-Research/]] | Reference materials and research notes | Claude |
| [[90-archive/templates-legacy/]] | General templates | — |

## Quick Links

- **Current active memory** → Mercury `.mercury/memory`
- **Task, progress, and acceptance state** → GitHub/Git
- **AI handoff guide** → [[90-archive/legacy-index/AI-Handoff-Guide]]
- **Dashboard** → [[90-archive/legacy-index/Dashboard]]

## AI Session Protocol

**Every session must follow these steps:**

1. Read the current Mercury `.mercury/memory` anchor.
2. Read the relevant GitHub/Git task, branch, commit, and acceptance evidence.
3. Load only the authority documents and evidence links required for the current task.
4. Before handoff, keep only current confirmed conclusions, real open issues, next actions, and necessary evidence links.

**Document-Topic Quick Lookup:**

| Need to Know | Consult Authority |
|---------|---------|
| Current active memory | Mercury `.mercury/memory` |
| Task, progress, and acceptance state | GitHub/Git |
| Structured gameplay facts | SoT structured design library |
| Architecture decisions and research | KB `02-Development/Decisions/` and `05-Research/` |
| Damage formula / attribute calculation | `01-Game-Design/Core-Systems/battle-calculation.md` |
| Class data / attribute baselines | `01-Game-Design/Characters/class-system.md` |
| Enemy templates / AI behavior | `01-Game-Design/Core-Systems/enemy-and-ai.md` |
| Turn mechanics / action resources | `01-Game-Design/Core-Systems/turn-system.md` |
| Grid pathfinding / terrain | `01-Game-Design/Core-Systems/grid-and-map.md` |
| Multi-AI tool collaboration | `90-archive/legacy-index/AI-Handoff-Guide.md` |

## Design Doc Index

### Core Systems
- [[01-Game-Design/Core-Systems/turn-system|Turn System]]
- [[01-Game-Design/Core-Systems/grid-and-map|Grid and Map]]
- [[01-Game-Design/Core-Systems/battle-calculation|Battle Calculation]]
- [[01-Game-Design/Core-Systems/enemy-and-ai|Enemy and AI]]
- [[01-Game-Design/skills-and-range|Skills and Range]]

### Comprehensive Design
- [[01-Game-Design/game-design-doc|Game Design Document - GDD]]
- [[90-archive/notes-legacy/design-roadmap|Design Roadmap]]
- [[90-archive/ai-context-legacy/module-relations|Module Dependency Graph]]

### Characters
- [[01-Game-Design/Characters/class-system|Class System]]
- [[01-Game-Design/Characters/talent-tree|Talent Tree]]

### Progression
- [[01-Game-Design/Progression/run-loop|Run Loop]]

### Technical
- [[01-Game-Design/Technical/data-architecture|Data Architecture]]
- [[01-Game-Design/Technical/network|Network Architecture]]

### v2（独立隔离设计区）
> 当前设计处于 **v1 阶段**。根级 `v2/` 目录是独立的 v2 设计区，与 v1 完全隔离 —— v1 工作时不看 `v2/` 内容即自动隔离，其中文档不参与 v1 设计，也不进设计库设计书收录。

## 目录索引

| 文档 | 状态 | 说明 |
|---|---|---|
| [AI-Handoff-Guide.md](AI-Handoff-Guide.md) | 历史 | AI Tool Handoff Guide |
| [Dashboard.md](Dashboard.md) | 历史 | Dashboard.md |
