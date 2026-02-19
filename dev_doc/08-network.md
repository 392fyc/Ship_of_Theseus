# 08 - 联机架构

> 返回 [总纲](./README.md)

## 概述

回合+速度轮动制天然简化了联机设计：任何时刻只有1个单位行动，只需同步1个玩家的输入指令。整体架构基于 **GameAction指令驱动**，单机和联机共用同一套游戏逻辑。

---

## 为什么轮动制简化了联机

| 对比 | 传统阵营回合制 | 轮动制（本项目） |
|------|--------------|----------------|
| 并行操作 | 我方回合所有单位可同时操作 | 任何时刻只有1个单位行动 |
| 同步难度 | 需要同步多个玩家的并行输入 | 只需同步当前行动者的输入 |
| 等待体验 | 我方回合所有人可操作，但敌方回合全员等待 | 每人只在自己角色行动时操作 |
| 联机模型 | 类似RTS的状态同步 | 类似回合制卡牌游戏 |

---

## GameAction指令模型

所有游戏操作封装为指令对象：

```
GameAction:
  actor_id: String          # 行动单位ID
  player_id: String         # 控制玩家ID（"ai"=敌方AI）
  action_type: "move" | "skill" | "wait" | "item"
  move_target: Vector2i | null
  skill_id: String | null
  skill_target: Vector2i | null
  timestamp: int            # 行动序号（用于验证同步）
```

### 关键设计原则

**先做单机，但从一开始就用GameAction驱动所有逻辑。**

```gdscript
# 单机模式 — 直接执行
func on_player_action(action: GameAction):
    game_state.apply(action)
    advance_turn()

# 联机模式 — 网络传输后执行
func on_player_action(action: GameAction):
    network.broadcast(action)
    # 所有客户端收到后
    game_state.apply(action)   # 完全相同的逻辑
    advance_turn()
```

**这意味着联机只是给GameAction加了一层网络传输层，不需要重构游戏逻辑。**

---

## 同步流程

```
1. TurnManager 计算出当前行动者 → 通知所有客户端
   ↓
2. 判断行动者的owner:
   - 属于本地玩家 → 进入操作状态，显示移动/技能UI
   - 属于其他玩家 → 显示"等待 [玩家名] 行动..."
   - 属于AI → 本地计算AI决策（host负责）
   ↓
3. 行动玩家提交 GameAction
   ↓
4. GameAction 广播给所有客户端
   ↓
5. 所有客户端用相同逻辑执行 GameAction → 状态一致
   ↓
6. 回到步骤1
```

---

## 网络拓扑

### 推荐：Host-Client（一个玩家做主机）

- 1个玩家作为Host，负责游戏状态权威
- 其他玩家作为Client，发送指令给Host，Host验证后广播
- 适合1-4人小规模，不需要专用服务器

```
玩家A（Host）←→ 玩家B（Client）
     ↕               
玩家C（Client）  
     ↕
玩家D（Client）

流程:
  Client发送GameAction → Host
  Host验证合法性 → 广播给所有Client
  所有端执行
```

### Godot实现方向

- Godot 4 内置 `MultiplayerAPI` + `ENet`（局域网）
- 公网联机可选：Steam Networking / WebRTC / 简单relay服务器
- 初期用ENet做局域网联机原型即可

---

## 超时与断线处理

```
行动超时:
  每个玩家有60秒操作时间
  超时 → 自动执行"wait"（原地等待）
  连续3次超时 → AI接管该角色

断线处理:
  短暂断线（<30秒）→ 暂停等待重连
  长时间断线 → AI接管该角色，其他玩家继续
  断线玩家重连 → 同步当前状态，恢复控制
```

---

## 联机时的特殊处理

### 奖励选择

战斗结束后的奖励三选一，联机时：
- 每个玩家独立选择自己角色的奖励（推荐）
- 设置选择时间限制（30秒）
- 超时随机选择

### 商店/事件

- 所有玩家同时看到商店/事件
- 各自独立操作（购买自己的东西）
- 共享金币还是独立金币？（待定）

### Run中途退出

- 退出玩家的角色由AI接管
- 或由其他玩家接管（投票决定）

---

## 需要同步的状态

```
最小同步集:
  - GameAction（每次行动的指令）
  - 随机数种子（确保所有客户端的随机结果一致）
  - 准备阶段操作（城镇建设、购物等）
  - 奖励选择结果
  - 商店购买操作

不需要同步（各端本地计算）:
  - 伤害计算结果（基于相同输入+相同种子=相同输出）
  - AI决策（Host计算后作为GameAction广播）
  - UI状态
```

---

## 实现优先级

1. **Phase 1-5**：完全单机，但用GameAction驱动
2. **Phase 6**：
   - 局域网联机（Godot ENet）
   - 行动同步测试
   - 超时处理
3. **后续**：
   - 公网联机方案
   - 断线重连
   - 匹配系统（如果需要）

---

相关文档：
- [01-回合系统](./01-turn-system.md) — 轮动制为什么简化联机
- [07-Run循环](./07-run-loop.md) — 联机时的奖励/商店流程
