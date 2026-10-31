# 08 - Network Architecture

> Back to [[game-design-doc|GDD]]

## Overview

The turn-based speed rotation system naturally simplifies multiplayer design: at any given moment only 1 unit acts, requiring only 1 player's input commands to be synced. The overall architecture is based on **GameAction command-driven design**, where single-player and multiplayer share the same game logic.

---

## Why Turn-Based Simplifies Multiplayer

| Comparison | Traditional Faction Turn-Based | Rotation System - This Project |
|------|--------------|----------------|
| Parallel Operations | All units on your side can act simultaneously during your turn | Only 1 unit acts at any given moment |
| Sync Difficulty | Must sync multiple players' parallel inputs | Only need to sync the current actor's input |
| Waiting Experience | All players can act during their faction's turn, but everyone waits during the enemy turn | Each player only acts when their character's turn comes |
| Multiplayer Model | Similar to RTS state synchronization | Similar to turn-based card games |

---

## GameAction Command Model

All game operations are encapsulated as command objects:

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

### Key Design Principle

**Build single-player first, but drive all logic with GameAction from the start.**

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

**This means multiplayer only adds a network transport layer on top of GameAction, no game logic restructuring needed.**

---

## Sync Flow

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

## Network Topology

### Recommended: Host-Client - One Player as Host

- 1 player serves as Host, responsible for authoritative game state
- Other players serve as Clients, sending commands to Host, Host validates then broadcasts
- Suitable for 1-4 player small scale, no dedicated server needed

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

### Godot Implementation Direction

- Godot 4 built-in `MultiplayerAPI` + `ENet` (LAN)
- Public network multiplayer options: Steam Networking / WebRTC / simple relay server
- Initial phase: use ENet for LAN multiplayer prototype

---

## Timeout and Disconnection Handling

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

## Special Multiplayer Handling

### Reward Selection

Post-battle pick-one-of-three rewards, in multiplayer:
- Each player independently selects rewards for their own character (recommended)
- Selection time limit (30 seconds)
- Timeout results in random selection

### Shop and Events

- All players see the shop/event simultaneously
- Each operates independently (buying their own items)
- Shared gold vs. independent gold? (TBD)

### Mid-Run Disconnection

- Disconnected player's character is taken over by AI
- Or taken over by another player (decided by vote)

---

## State That Needs Syncing

```
Minimum Sync Set:
  - GameAction (command for each action)
  - Random number seed (ensures all clients produce identical random results)
  - Preparation Phase operations (town building, shopping, etc.)
  - Reward selection results
  - Shop purchase operations

No Sync Needed (computed locally on each endpoint):
  - Damage calculation results (same input + same seed = same output)
  - AI decisions (Host computes then broadcasts as GameAction)
  - UI state
```

---

## Implementation Priority

1. **Phase 1-5**: Fully single-player, but driven by GameAction
2. **Phase 6**:
   - LAN multiplayer (Godot ENet)
   - Action sync testing
   - Timeout handling
3. **Later**:
   - Public network multiplayer solution
   - Disconnection and reconnection
   - Matchmaking system (if needed)

---

Related documents:
- [[turn-system|01 - Turn System]] — Why rotation system simplifies multiplayer
- [[run-loop|07 - Run Loop]] — Reward/shop flow during multiplayer
