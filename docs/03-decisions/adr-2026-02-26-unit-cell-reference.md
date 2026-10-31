# ADR-003 - Unit and Cell Reference Relationship

- **Date**: 2026-02-26
- **Status**: Adopted
- **Decision Maker**: Design Agent (Claude)

---

## Background

In a tactical RPG system, Unit and Cell have a positional ownership relationship. Movement operations are frequent, BFS needs to quickly determine whether a cell is occupied, and the system must support "allies can pass through but not stop on" rules. Multiplayer synchronization requires serialization of position information.

### Constraints

1. **High-frequency BFS queries**: `is_occupied(pos)` is called on every BFS expansion; a 10x10 map BFS requires up to 100 calls
2. **High-frequency movement updates**: Each movement requires updating position references
3. **Ally pass-through rule**: Cells occupied by allies can be traversed but not stopped on; cells occupied by enemies are impassable
4. **Multiplayer serialization**: Unit positions must be included in GameAction and state synchronization
5. **ZOC determination**: Must quickly find enemy units on orthogonally adjacent cells

---

## Options

### Option A - Bidirectional Reference - Cell.occupant plus Unit.grid_position

- Cell holds `occupant: Unit` (the unit currently standing on it)
- Unit holds `grid_position: Vector2i` (current cell coordinates)
- Both sides are updated synchronously on movement

### Option B - Unidirectional - Unit Holds Position, Grid Provides Query

- Unit holds `grid_position: Vector2i`
- Grid provides `get_unit_at(pos)` by iterating all units to find a match
- Cell does not record occupant

### Option C - Unidirectional - Cell Holds Occupant, Query Unit via Cell

- Cell holds `occupant: Unit`
- Unit does not record position; must iterate Grid to find its own position
- Or Unit back-references Cell

---

## Selected Option - Option A - Bidirectional Reference

---

## Rationale

| Consideration | Option A (Selected) | Option B | Option C |
|---------|-------------|--------|--------|
| **is_occupied(pos)** | O(1) -- `cell.occupant != null` | O(n) -- iterate all Units to match position | O(1) -- same as A |
| **get_unit_position()** | O(1) -- `unit.grid_position` | O(1) -- same | O(n) -- must iterate Grid |
| **Movement update** | Must update 2 places (Cell + Unit) | Only update 1 place (Unit) | Must update 2 places (old Cell + new Cell) |
| **Consistency risk** | Medium -- bidirectional requires sync, but can be encapsulated in a single function | Low -- single source of truth | Medium -- same as A |
| **ZOC determination** | O(1) -- directly query adjacent Cell.occupant | O(n) -- must iterate units for each adjacent cell | O(1) -- same as A |
| **Multiplayer serialization** | Only need to serialize Unit.grid_position | Same | Must reverse-lookup from Cell |

**Decisive factors**:
1. BFS movement range calculation is a performance hotspot -- each expansion step must check 4 adjacent cells for occupation and enemy presence. Option B is O(n x 4 x expansion_steps) here, which is unacceptable (although n is small, this is avoidable waste)
2. ZOC determination requires checking 4 orthogonal neighbors for enemy units; bidirectional reference allows O(1) direct reads
3. Consistency risk is managed by encapsulating all updates in a `move_unit()` function, making it practically controllable
4. On a 10x10 map with <=20 units, the memory overhead of bidirectional references is negligible

---

## Implementation Spec

### Cell Data Structure

```
# Cell -- already contains three-layer terrain structure (established in ADR-001)
var position: Vector2i
var terrain: int               # Base terrain enum value
var special_terrain: Dictionary # or null
var building: Dictionary       # or null
var occupant: Unit             # Currently occupying unit (null = empty)
```

### Unit Position Field

```
# Unit.gd
var grid_position: Vector2i    # Current logical coordinates
```

### Grid Unified Movement Interface - Consistency Guarantee

```
# Grid.gd -- the only permitted entry point for modifying positions

func place_unit(unit: Unit, pos: Vector2i) -> void:
  ## Initial placement (battle start / summon)
  assert(is_in_bounds(pos))
  assert(get_cell(pos).occupant == null, "Target cell is already occupied")
  unit.grid_position = pos
  get_cell(pos).occupant = unit

func move_unit(unit: Unit, to: Vector2i) -> void:
  ## Movement (logical update before path animation)
  var from = unit.grid_position
  assert(is_in_bounds(to))
  assert(get_cell(to).occupant == null, "Target cell is already occupied")
  get_cell(from).occupant = null
  unit.grid_position = to
  get_cell(to).occupant = unit

func remove_unit(unit: Unit) -> void:
  ## Removal (death / retreat)
  var pos = unit.grid_position
  if is_in_bounds(pos) and get_cell(pos).occupant == unit:
    get_cell(pos).occupant = null
```

### Occupation Check in BFS

```
func is_passable(pos: Vector2i, moving_unit: Unit) -> bool:
  var cell = get_cell(pos)
  if cell == null:
    return false
  if not _terrain_is_passable(cell.terrain, moving_unit):
    return false
  if cell.occupant != null:
    if cell.occupant.faction == moving_unit.faction:
      return true   # Allies can pass through
    else:
      return false  # Enemies block
  return true

func is_stoppable(pos: Vector2i, moving_unit: Unit) -> bool:
  ## Whether the unit can stop here (BFS endpoint check)
  var cell = get_cell(pos)
  return is_passable(pos, moving_unit) and cell.occupant == null
```

### ZOC Determination

```
func is_in_enemy_zoc(pos: Vector2i, unit: Unit) -> bool:
  for dir in ORTHOGONAL_DIRS:
    var neighbor = pos + dir
    if is_in_bounds(neighbor):
      var occ = get_cell(neighbor).occupant  # O(1) direct read
      if occ != null and occ.faction != unit.faction:
        return true
  return false
```

### Serialization

```json
{
  "action": "MOVE",
  "unit_id": "player_warrior_01",
  "from": {"x": 2, "y": 3},
  "to": {"x": 4, "y": 5}
}
```

Serialization only transmits `unit_id` + coordinates. The receiving end uses the `move_unit()` function to automatically maintain bidirectional reference consistency.

---

## Consequences and Constraints

### Positive Consequences

- All high-frequency queries such as BFS, ZOC, and attack range are O(1)
- Code intent is clear: `cell.occupant` tells you who is standing here, `unit.grid_position` tells you where this unit is

### Negative Consequences

- Positions must be modified through `Grid.move_unit()` / `Grid.place_unit()`; direct assignment is prohibited
- Violating this constraint causes data inconsistency -- must be enforced through code review and assertions

### Constraints

- **Single entry point principle**: Any position change must go through `Grid.place_unit()` / `Grid.move_unit()` / `Grid.remove_unit()`
- Direct modification of `grid_position` or `occupant` inside Unit or Cell is prohibited
- GameAction handlers must call Grid interfaces and not manipulate references directly

---

*Related documents: [[01-Game-Design/Core-Systems/grid-and-map]] - ADR-001 (Grid coordinate system)*
