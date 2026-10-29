# 10 - 网络架构(Network Architecture)

> Back to [[game-design-doc|GDD]]

## 概览

回合制速度轮转系统天然简化了多人联机设计:任一时刻只有 1 个单位行动,只需同步 1 名玩家的输入指令。整体架构基于 **GameAction 指令驱动设计**,单人与多人共享同一套游戏逻辑。

---

## 为什么回合制简化了多人联机

| 对比项 | 传统阵营回合制 | 轮转系统 - 本项目 |
|------|--------------|----------------|
| 并行操作 | 你方所有单位可在你方回合同时行动 | 任一时刻只有 1 个单位行动 |
| 同步难度 | 必须同步多名玩家的并行输入 | 只需同步当前行动者的输入 |
| 等待体验 | 阵营回合内所有玩家都能操作,但敌方回合时人人干等 | 每名玩家只在自己角色的回合到来时行动 |
| 多人模型 | 类似 RTS 的状态同步 | 类似回合制卡牌游戏 |

---

## GameAction 指令模型

所有游戏操作都封装为指令对象:

```
GameAction:
  actor_id: String          # Acting unit ID
  player_id: String         # Controlling player ID ("ai" = enemy AI)
  action_type: "move" | "skill" | "wait" | "item"
  move_target: Vector2i | null
  skill_id: String | null
  skill_target: Vector2i | null
  timestamp: int            # Action sequence number (for sync validation)
```

### 关键设计原则

**先做单人,但从一开始就用 GameAction 驱动所有逻辑。**

```gdscript
# Single-player mode — execute directly
func on_player_action(action: GameAction):
    game_state.apply(action)
    advance_turn()

# Multiplayer mode — execute after network transmission
func on_player_action(action: GameAction):
    network.broadcast(action)
    # After all clients receive it
    game_state.apply(action)   # Exactly the same logic
    advance_turn()
```

**这意味着多人联机只是在 GameAction 之上加了一层网络传输,无需重构任何游戏逻辑。**

---

## 同步流程

```
1. TurnManager calculates current actor → notifies all clients
   ↓
2. Determine the actor's owner:
   - Belongs to local player → enter action state, show movement/skill UI
   - Belongs to another player → display "Waiting for [player name] to act..."
   - Belongs to AI → compute AI decision locally (host responsible)
   ↓
3. Acting player submits GameAction
   ↓
4. GameAction is broadcast to all clients
   ↓
5. All clients execute GameAction with identical logic → consistent state
   ↓
6. Return to step 1
```

---

## 网络拓扑

### 推荐:Host-Client - 一名玩家作为 Host

- 1 名玩家充当 Host,负责权威游戏状态
- 其他玩家充当 Client,把指令发给 Host,Host 校验后广播
- 适合 1-4 人小规模,无需专用服务器

```
Player A (Host) ←→ Player B (Client)
     ↕
Player C (Client)
     ↕
Player D (Client)

Flow:
  Client sends GameAction → Host
  Host validates legality → broadcasts to all Clients
  All endpoints execute
```

### Godot 实现方向

- Godot 4 内置 `MultiplayerAPI` + `ENet`(局域网)
- 公网多人可选方案:Steam Networking / WebRTC / 简单中继服务器
- 初期阶段:用 ENet 做局域网多人原型

---

## 超时与掉线处理

```
Action Timeout:
  Each player has 60 seconds of action time
  Timeout → auto-execute "wait" (stay in place)
  3 consecutive timeouts → AI takes over that character

Disconnection Handling:
  Brief disconnect (<30 seconds) → pause and wait for reconnect
  Extended disconnect → AI takes over that character, other players continue
  Disconnected player reconnects → sync current state, restore control
```

---

## 多人联机特殊处理

### 奖励选择

战后三选一奖励,在多人联机下:
- 每名玩家为自己的角色独立选取奖励(推荐)
- 选择时限(30 秒)
- 超时则随机选取

### 商店与事件

- 所有玩家同时看到商店/事件
- 各自独立操作(买自己的物品)
- 共享金币还是独立金币?(待定 TBD)

### 中途掉线

- 掉线玩家的角色由 AI 接管
- 或由另一名玩家接管(投票决定)

---

## 需要同步的状态

```
Minimum Sync Set:
  - GameAction (command for each action)
  - Random number seed (ensures all clients produce identical random results)
  - Preparation Phase operations (shopping, etc.)
  - Reward selection results
  - Shop purchase operations

No Sync Needed (computed locally on each endpoint):
  - Damage calculation results (same input + same seed = same output)
  - AI decisions (Host computes then broadcasts as GameAction)
  - UI state
```

---

## 实现优先级

1. **Phase 1-5**:完全单人,但由 GameAction 驱动
2. **Phase 6**:
   - 局域网多人(Godot ENet)
   - 行动同步测试
   - 超时处理
3. **后续**:
   - 公网多人方案
   - 掉线与重连
   - 匹配系统(如有需要)

---

相关文档:
- [[turn-system|01 - 回合系统]] — 为什么轮转系统简化多人联机
- [[run-loop|08 - Run 循环]] — 多人联机时的奖励/商店流程
