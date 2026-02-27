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

**会话开始**必读：`obsidian_get_file_contents("03-AI-Context/Active-Context/current-session.md")`
**会话结束**必写：更新 `current-session.md`（格式参考 `03-AI-Context/Handoffs/handoff-template.md`）

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

## 已确认的错误模式

> 此节仅收录模型**反复犯错后**经纠正确认的模式。新规则需经人工总控台批准后添加。

### Godot 4.6 兼容性
- class_name 与 autoload 同名 → 冲突，autoload 脚本**移除 class_name**
- Variant 类型推断不稳定 → **显式声明变量类型**

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
