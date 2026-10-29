# ADR-001 - Grid Coordinate System

- **Date**: 2026-02-26
- **Status**: Adopted
- **Decision Maker**: Design Agent (Claude)

---

## Background

In Godot 4, implementing a square grid tactical map of up to 10x10 requires determining the representation and storage method for grid coordinates. The coordinate system underpins the entire combat system -- BFS movement range, A* Pathfinding, Zone of Control (ZOC) checks, attack line checks, GameAction serialization (Multiplayer broadcast) -- making it a foundational Layer 1 architecture decision.

### Constraints

1. **Serialization**: GameActions must be serializable to JSON (Multiplayer broadcast sync)
2. **Neighbor Access**: BFS/A* requires efficient access to orthogonal 4-neighbors
3. **Map Scale**: Maximum 10x10, no hexagonal grid requirements
4. **Three-Layer Decoupling**: The Cell three-layer structure (base terrain / special terrain / building) must be decoupled from the coordinate system
5. **Data-Driven**: Map data is stored as JSON 2D arrays (`terrain: [[0,0,1,...],...]`)

---

## Options

### Option A - Vector2i Self-Managed 2D Array - col row

- Grid internally maintains `cells: Array[Array[Cell]]`, indexed by `cells[row][col]` or `cells[y][x]`
- Coordinates use Godot-native `Vector2i(x, y)` representation
- Completely bypasses TileMapLayer's coordinate system; TileMap is used only for rendering

### Option B - Rely on Godot TileMapLayer Built-in Coordinate System

- Directly use built-in APIs such as `TileMapLayer.local_to_map()` / `map_to_local()`
- Cell data is attached to TileMapLayer's tile data or custom data layers
- Coordinate conversion is managed by TileMapLayer

### Option C - Custom Resource Wrapping x y Integer Pair

- Define `GridCoord extends Resource`, encapsulating x/y integers
- Provide methods such as `neighbors()` / `distance_to()`
- Grid stores data as `Dictionary[GridCoord, Cell]`

---

## Selected Option - Option A - Vector2i Self-Managed 2D Array

---

## Rationale

| Consideration | Option A (Selected) | Option B | Option C |
|---------|-------------|--------|--------|
| **JSON Serialization** | `[x, y]` integer pair maps naturally to JSON array | TileMap coords need `map_to_local` conversion before serialization | Requires custom `to_dict()`/`from_dict()` |
| **Neighbor Access** | `Vector2i(0,1)` and other 4-directional offsets, O(1) direct indexing | Requires TileMap API conversion with extra call overhead | Same as A, but requires unboxing Resource |
| **Logic/Rendering Decoupling** | Fully decoupled -- Grid logic layer is independent from TileMap rendering layer | Coupled: logic depends on TileMap node existence | Decoupled but introduces extra Resource allocation |
| **Complexity** | Simple -- 2D array + Vector2i, Godot-native types | TileMap has extensive implicit behavior requiring study | Over-encapsulation -- a 10x10 map does not need custom types |
| **Performance** | Array direct indexing O(1), no issue for 100 cells | TileMap is optimized for large maps, overkill for small maps | Dictionary hash vs array indexing, no advantage |
| **Multiplayer Adaptation** | Vector2i -> `{"x": 3, "y": 5}` embeds directly into GameAction JSON | Must ensure Host/Client TileMap consistency | Same as A |

**Deciding Factors**:
1. A 10x10 square map is simple enough that TileMap's hexagonal/isometric/large-map optimization capabilities are not needed
2. Decoupling logic and rendering layers is key for long-term maintenance -- Grid logic should not depend on Godot scene nodes
3. `Vector2i` is a Godot-native value type with no GC pressure and good operator overloading

---

## Implementation Spec

### Grid Storage Structure

```
Grid:
  var width: int       # Read from map JSON
  var height: int      # Read from map JSON
  var cells: Array     # cells[y][x] = Cell, y=row, x=col

  func get_cell(pos: Vector2i) -> Cell:
    if is_in_bounds(pos):
      return cells[pos.y][pos.x]
    return null

  func is_in_bounds(pos: Vector2i) -> bool:
    return pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height
```

### Neighbor Access

```
const ORTHOGONAL_DIRS: Array[Vector2i] = [
  Vector2i(0, -1),  # Up
  Vector2i(0, 1),   # Down
  Vector2i(-1, 0),  # Left
  Vector2i(1, 0),   # Right
]

func get_neighbors(pos: Vector2i) -> Array[Vector2i]:
  var result: Array[Vector2i] = []
  for dir in ORTHOGONAL_DIRS:
    var neighbor = pos + dir
    if is_in_bounds(neighbor):
      result.append(neighbor)
  return result
```

### Coordinate Serialization - GameAction JSON

```json
{
  "action": "MOVE",
  "unit_id": "player_warrior_01",
  "from": {"x": 2, "y": 3},
  "to": {"x": 4, "y": 5},
  "path": [{"x": 2, "y": 3}, {"x": 3, "y": 3}, {"x": 4, "y": 3}, {"x": 4, "y": 4}, {"x": 4, "y": 5}]
}
```

### Coordinate Conventions

| Convention | Description |
|------|------|
| Origin | `(0, 0)` = Top-left corner |
| X-axis | Increases rightward (column) |
| Y-axis | Increases downward (row) |
| Storage | `cells[y][x]` (row-major, consistent with JSON terrain array) |
| Map JSON | `terrain[row][col]` = `terrain[y][x]` |

### TileMap Used Only for Rendering

```
# Rendering layer: maps logic coordinates to TileMap pixel coordinates
func logic_to_render(pos: Vector2i) -> Vector2:
  return Vector2(pos.x * CELL_SIZE + CELL_SIZE / 2, pos.y * CELL_SIZE + CELL_SIZE / 2)
```

---

## Consequences and Constraints

### Positive Consequences

- Grid logic can be unit tested independently of the scene tree
- Multiplayer sync only needs to transmit Vector2i integer pairs, with minimal bandwidth usage
- If a rendering approach change is needed in the future (e.g., custom rendering instead of TileMap), the logic layer requires zero modifications

### Negative Consequences

- TileMap's built-in features (auto-tiling, terrain painting) require manual bridging
- Logic coordinate to screen coordinate conversion functions must be implemented manually

### Constraints

- All systems (BFS/A*/ZOC/attack lines/GameAction) must uniformly use `Vector2i`; direct use of TileMap coordinates is prohibited
- Each Cell records its own position via a `Vector2i position` field, kept consistent with the Grid array index

---

*Related documents: [[01-Game-Design/Core-Systems/grid-and-map]] · [[01-Game-Design/Technical/data-architecture]]*
