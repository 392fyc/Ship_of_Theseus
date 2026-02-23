# AGENTS.md

面向 Codex 及其他 AI 代理的项目指南。内容与 CLAUDE.md 同步。

---

## Language

设计文档为中文（简体）。讨论设计、游戏机制、文档时用中文，除非用户切换为英文。

---

## 项目概述

战棋RPG + Roguelite + 城镇建设，Godot 4 (GDScript)。
支持单机1人 / 联机1-4人。当前阶段：设计文档 + 设计工具已完成，尚无游戏代码。

**核心差异化**：城镇建设融入战棋Roguelite，玩家在角色强化和建筑投资之间做经济抉择。

## 技术栈

| 层 | 技术 |
|---|---|
| 引擎 | Godot 4.x (GDScript) |
| 数据 | JSON驱动（游戏内容全JSON，代码只处理逻辑） |
| 联机 | Godot High-Level Multiplayer API, Host-Client |
| 架构 | GameAction指令驱动（联机广播同步） |

---

## 项目结构

```
project/
├── dev_doc/                       # 设计文档（开发参考）
│   ├── module-relations-agent.md  # ⭐ 模块依赖表（修改代码前必查）
│   ├── 01~12 模块文档
│   └── design-roadmap.md / game-design-doc.md
├── tools/                         # 设计工具（浏览器端 HTML 工具集）
│   ├── index.html                 # 工具导航页
│   ├── shared.js                  # 共享常量、公式、i18n（~1000行）
│   ├── talent-tree-editor.html    # ⭐ 天赋树编辑器（~3000行，勿直接读取）
│   ├── equipment-designer.html    # 装备设计器
│   ├── map-designer.html          # 地图设计器
│   └── damage-simulator.html      # 伤害模拟器
├── data/talent-tree/              # 天赋树编辑器输出（workspace数据）
├── scenes/                        # Godot场景（待建）
├── scripts/                       # GDScript代码（待建）
└── assets/                        # 美术资源（待建）
```

---

## 设计工具维护指南

### 核心原则：不要直接读取 HTML 文件

所有工具 HTML 文件体量大（天赋树编辑器 3000+ 行），直接读取会消耗大量上下文。
**修改工具时应使用搜索工具定位具体代码段后直接编辑**，不要通篇阅读。

### 天赋树编辑器（talent-tree-editor.html）

单文件 Canvas 图编辑器，关键模块：

| 模块 | 定位关键词 | 说明 |
|---|---|---|
| FSBridge | `const FSBridge` | 本地目录读写（File System Access API）、IndexedDB持久化 |
| computeShortestPaths | `function computeShortestPaths` | Dijkstra算法，自动计算节点最低等级 |
| getCachedPathData | `function getCachedPathData` | 路径计算缓存，每帧仅计算一次 |
| render | `function render()` | Canvas主绘制循环 |
| Undo/Redo | `function pushUndo` | JSON快照栈，突变前必须调用 pushUndo() |
| 侧边栏绑定 | `forEach(fid =>` | 属性面板输入绑定，focus时pushUndo |
| validateDAG | `function validateDAG` | DAG校验（重复ID/环/孤立节点/悬空边） |
| 路径分析 | `function updatePathAnalysis` | 最短路径高亮与花费分析 |
| 导入导出 | `function applyImportedJSON` | JSON导入（自动布局缺失坐标） |
| 搜索 | `searchQuery` | 节点名称/标签搜索与高亮 |

**节点数据格式**：
```json
{
  "class_id": "string", "class_name": "string",
  "nodes": [{
    "id": "string", "name": "string",
    "type": "passive|active_skill|trait|skill_upgrade|advancement|gauge_core|gauge_extend|stat_minor",
    "cost": 1, "x": 0, "y": 0,
    "desc": "", "notes": "", "tags": "", "exclusive": "", "requires": ""
  }],
  "edges": [{ "from": "node_id", "to": "node_id" }]
}
```

注意：节点无 `level` 字段，等级由 `computeShortestPaths()` 从起始节点路径花费自动计算。

### shared.js（共享模块）

| 内容 | 说明 |
|---|---|
| 游戏常量 | TERRAIN_TYPES, SPECIAL_TERRAIN_TYPES, BUILDING_TYPES, CLASS_DEFS 等 |
| I18N系统 | `I18N.t(key)`, `data-i18n` 属性, `createLangSwitcher()`, localStorage持久化 |
| 公式函数 | 伤害/命中/暴击计算器 |
| 工具函数 | toast, JSON导入导出, localStorage管理 |

添加 i18n 词条时：在 `shared.js` 的 `zh` 和 `en` 对象中同步添加。

---

## 设计文档查阅规则

**修改游戏代码前**必须：
1. 查 `dev_doc/module-relations-agent.md` 确认影响范围
2. 读对应模块设计文档了解规则
3. 检查 depended_by 列表确认联动修改

### 文档状态

- **已稳定**：01-turn, 02-grid, 03-battle, 05-class, 11-town（非用户要求不改）
- **待核查**：04-skills, 06-enemy, 07-run, 08-network, 09-data, 10-milestones
- **待建**：12-talent-tree（方向已定，文档未完善）、视野系统

### 系统分层
```
Layer 4 (Meta层):   07-Run循环  ←→  11-城镇建设
Layer 3 (角色层):   05-职业系统  ←→  06-敌人与AI  ←→ 12-天赋树
Layer 2 (战斗层):   01-回合  →  04-技能  →  03-伤害计算
Layer 1 (基础层):   02-网格与地图
Layer 0 (数据层):   09-数据架构
叠加层:             08-联机架构（不改变游戏逻辑）
```

---

## 核心游戏规则

### 回合系统 (→ dev_doc/01)

- 速度轮动：按speed降序，相同按先制优先级(0/+1/+2)
- 同速：低难度玩家先，最高难度敌人先
- Buff时机：触发=回合开始，扣减=回合结束，施加=立即生效

### 网格与地图 (→ dev_doc/02)

- 正方形 ≤10×10，三层结构（基础地形/特殊地形/建筑）
- 基础地形枚举: PLAIN=0~SWAMP=8
- 仅PEAK阻挡远程攻击线，WALL不阻挡
- 建筑摧毁→废墟，不恢复基础地形效果

### 伤害计算 (→ dev_doc/03)

```
最终伤害 = 基础伤害 × 技能倍率 × 特殊地形修正 × 暴击修正 × 格挡修正 × 最终伤害增减
基础伤害 = 攻击力 × 武器威力 - 防御力 × 护甲抵抗  (最低0)
命中率 = hit + weapon.hit + skill_bonus - evade - terrain_evade (20%~100%)
暴击率 = (crit + weapon.crit + skill_bonus - crit_evade) × 抵抗率 (0%~50%, 1.5x)
```
格挡：固定（不成长），70%减免，**与暴击互斥**

### 伤害类型双轴

| 属性类型 | 防御 | 暴击/格挡 |
|---|---|---|
| physical | 物防×护甲 | Yes |
| magical | 魔防×魔抗 | Yes |
| holy | 无视防御 | No |
| hybrid | 取低者 | Yes |

攻击方式：`melee`(1格) / `ranged`(>1格) / `area`(AOE)

### 结算顺序（必须严格遵守）

```
1. 命中(20%~100%) → miss跳到结束
2. 格挡 → 成功=0.3修正, 跳过暴击
3. 暴击(0%~50%) → 仅格挡失败时判定
4. 计算伤害 → 5. 应用伤害 → 6. 命中后附加效果 → 7. 伤害后附加效果
8. 反击(attack_type!=area, 存活, 射程可达, 未控制) → 走1-7, 不触发反击/追击
9. 追击((atk.speed-def.speed)×10%, 0%~100%, 需原始命中) → 走1-7, 不触发反击/追击
```

### 反击 / 追击 / 职业 / 建筑 / Meta

- **反击**：普通攻击（完整结算），不触发二次反击，不触发追击
- **追击**：`(attacker.speed - defender.speed) × 10%`，全职业通用，剑士系深度特化
- **职业**：8基础+16转职，speed/move/block/vision不成长，转职通过天赋树节点
- **建筑耐久**：不用伤害公式，按攻击类型固定扣减
- **Meta原则**：横向解锁（选择多样性），禁止纵向数值强化

---

## 编码规范

### GDScript
- 类名 PascalCase，变量/函数 snake_case，常量 UPPER_SNAKE_CASE
- 信号 past_tense：`signal damage_dealt`, `signal unit_killed`
- GameAction模式：所有操作封装为可序列化Action

### 数据驱动
- 游戏内容 = JSON文件，代码只处理逻辑
- **禁止**在代码中硬编码数值，必须从JSON读取
- speed/move/vision/block 不出现在 stat_growth 中

### 常见陷阱

- 格挡和暴击同时生效 → **互斥**
- holy伤害触发暴击/格挡 → **无视**
- 反击触发反击 → **不触发**，也不触发追击
- 追击触发追击或反击 → **不触发**
- area攻击触发反击 → **不触发**
- 建筑耐久用伤害公式 → **固定扣减**
- 建筑摧毁恢复地形效果 → **变废墟**
- 距离影响伤害/命中 → **无衰减**
