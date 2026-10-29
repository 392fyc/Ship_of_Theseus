# Task: Scene Rename + Isometric Grid Refactor

- Status: Ready for dispatch
- Agent: Cursor (Claude Opus 4.6 or GPT-5.4)
- Branch: `cursor/isometric-refactor`
- Priority: P0 (blocks all subsequent TacticalScene work)
- ADR ref: ADR-008
- Depends on: Viewport Angle Playground completed (Isometric selected)

---

## Objective

Rename BattleScene/BattleManager to TacticalScene/TacticalManager, and convert the grid rendering + input system from top-down square to isometric diamond projection. Logical grid remains square 64x64 internally.

---

## Phase 1 - Rename

Mechanical find-and-replace. No logic changes.

### File Renames

| Old Path | New Path |
|----------|----------|
| `scenes/battle/BattleScene.tscn` | `scenes/tactical/TacticalScene.tscn` |
| `scripts/battle/battle_scene.gd` | `scripts/tactical/tactical_scene.gd` |
| `scripts/core/battle_manager.gd` | `scripts/core/tactical_manager.gd` |

### Symbol Renames

| Old | New | Files Affected |
|-----|-----|----------------|
| `class_name BattleManager` | `class_name TacticalManager` | tactical_manager.gd |
| `BattleManager` (type refs) | `TacticalManager` | enemy_ai.gd, tactical_scene.gd |
| `BattleScene` (node name in tscn) | `TacticalScene` | TacticalScene.tscn |
| `BattleManager` (node name in tscn) | `TacticalManager` | TacticalScene.tscn |
| `[BattleManager]` (print tags) | `[TacticalManager]` | tactical_manager.gd |
| `[BattleScene]` (print tags) | `[TacticalScene]` | tactical_scene.gd |

### Files to check for references

- `scripts/core/enemy_ai.gd`
- `scenes/playground/playground_battle_ui.gd` (may reference BattleManager)
- `project.godot` (autoload entries if any)

### Verification after Phase 1

- Game launches without errors
- Scene tree shows TacticalScene > TacticalManager hierarchy
- Turn system and combat still function (same square grid, just renamed)

---

## Phase 2 - Isometric Grid Math

Change grid_to_world and world_to_grid in `grid.gd` to use isometric projection.

### grid.gd Changes

Current:
```gdscript
const CELL_SIZE := Vector2i(64, 64)

func grid_to_world(pos: Vector2i) -> Vector2:
    return Vector2(pos.x * CELL_SIZE.x + CELL_SIZE.x / 2.0,
                   pos.y * CELL_SIZE.y + CELL_SIZE.y / 2.0)

func world_to_grid(world_pos: Vector2) -> Vector2i:
    return Vector2i(int(world_pos.x) / CELL_SIZE.x,
                    int(world_pos.y) / CELL_SIZE.y)
```

New (isometric):
```gdscript
const CELL_SIZE := Vector2i(64, 64)
const TILE_WIDTH := 64    # diamond width
const TILE_HEIGHT := 32   # diamond height (half of width for standard 2:1 iso)

# Offset to keep the map in positive screen space
var _iso_offset := Vector2.ZERO

func set_iso_offset(map_width: int, _map_height: int) -> void:
    _iso_offset = Vector2(float(map_width) * TILE_WIDTH / 2.0, 64.0)

func grid_to_world(pos: Vector2i) -> Vector2:
    var sx: float = (pos.x - pos.y) * TILE_WIDTH / 2.0 + _iso_offset.x
    var sy: float = (pos.x + pos.y) * TILE_HEIGHT / 2.0 + _iso_offset.y
    return Vector2(sx, sy)

func world_to_grid(world_pos: Vector2) -> Vector2i:
    var wx: float = world_pos.x - _iso_offset.x
    var wy: float = world_pos.y - _iso_offset.y
    var gx: float = (wx / (TILE_WIDTH / 2.0) + wy / (TILE_HEIGHT / 2.0)) / 2.0
    var gy: float = (wy / (TILE_HEIGHT / 2.0) - wx / (TILE_WIDTH / 2.0)) / 2.0
    return Vector2i(roundi(gx), roundi(gy))
```

Call `set_iso_offset(width, height)` at end of `initialize()`.

### Key constants

- TILE_WIDTH = 64 (horizontal diamond span)
- TILE_HEIGHT = 32 (vertical diamond span, 2:1 ratio is standard isometric)
- These are rendering constants; logical CELL_SIZE stays 64x64 for pathfinding/range calculations

---

## Phase 3 - Isometric Terrain Rendering

Replace ColorRect-based rendering in tactical_manager.gd with _draw() based diamond polygons.

### Current approach (to replace)

`_render_terrain()` creates ColorRect nodes per cell with square positioning.

### New approach

TacticalManager (or a dedicated TerrainRenderer child node) uses `_draw()` to paint:

For each cell at grid position (gx, gy):
1. Get screen center via `grid.grid_to_world(Vector2i(gx, gy))`
2. Draw diamond top-face polygon:
   ```
   top    = center + Vector2(0, -TILE_HEIGHT/2)
   right  = center + Vector2(TILE_WIDTH/2, 0)
   bottom = center + Vector2(0, TILE_HEIGHT/2)
   left   = center + Vector2(-TILE_WIDTH/2, 0)
   ```
3. Draw with terrain color
4. Draw diamond outline with `Color(0.0, 0.0, 0.0, 0.25)`
5. Optional: draw terrain label at center

### Rendering order

Draw cells in order: row by row, left to right (back to front for correct overlap if tiles have height).

### Terrain colors

Keep existing TERRAIN_COLORS dictionary unchanged.

---

## Phase 4 - Isometric Highlights

Replace ColorRect + ReferenceRect based highlights with diamond polygon rendering.

### Current approach (to replace)

`_add_highlight()` creates ColorRect + ReferenceRect per cell.

### New approach

Highlight layer uses `_draw()` or adds Polygon2D children:

Option A - Polygon2D children (easier to add/remove dynamically):
```gdscript
func _add_highlight(cell_pos: Vector2i, fill_color: Color, border_color: Color) -> void:
    var center := grid.grid_to_world(cell_pos)
    var points := _diamond_points(center)

    var poly := Polygon2D.new()
    poly.polygon = points
    poly.color = fill_color
    poly.mouse_filter = Control.MOUSE_FILTER_IGNORE  # not needed for Node2D
    highlight_layer.add_child(poly)

    # Border via Line2D
    var line := Line2D.new()
    line.points = points + PackedVector2Array([points[0]])  # close the loop
    line.width = HIGHLIGHT_BORDER_WIDTH
    line.default_color = border_color
    highlight_layer.add_child(line)

func _diamond_points(center: Vector2) -> PackedVector2Array:
    return PackedVector2Array([
        center + Vector2(0, -TILE_HEIGHT / 2.0),
        center + Vector2(TILE_WIDTH / 2.0, 0),
        center + Vector2(0, TILE_HEIGHT / 2.0),
        center + Vector2(-TILE_WIDTH / 2.0, 0),
    ])
```

`_clear_highlights()` remains the same (queue_free all children).

---

## Phase 5 - Input Click Detection

### Current approach

`_unhandled_input` gets mouse position → `world_to_grid()` → handle click.

### New approach

Same flow, but `world_to_grid()` now uses inverse isometric math (already updated in Phase 2). Should work automatically.

### Edge case

Mouse clicks near diamond edges may map to adjacent cells. The rounding in `world_to_grid` handles this, but verify with manual testing.

---

## Phase 6 - Unit Positioning

### Current approach

`spawn_unit()` calls `grid.grid_to_world(spawn_pos)` to set `unit.position`.
`unit.move_to()` calls `grid.grid_to_world()` for movement animation target.

### Expected behavior

Since `grid_to_world()` is updated in Phase 2, unit positioning should automatically use isometric coordinates. Verify:

- Units spawn at correct diamond centers
- Movement animation follows isometric path
- HP bars and popups appear above unit position correctly

### HP Bar offset

Current HP bar offset is `offset_top = -44.0` in Unit.tscn. May need adjustment since isometric tiles are shorter (32px vs 64px height).

---

## Files Modified Summary

| File | Changes |
|------|---------|
| `scripts/core/grid.gd` | Add TILE_WIDTH/TILE_HEIGHT, isometric grid_to_world/world_to_grid, set_iso_offset |
| `scripts/core/tactical_manager.gd` (renamed) | Rename class, isometric terrain rendering, isometric highlights |
| `scripts/tactical/tactical_scene.gd` (renamed) | Rename references |
| `scenes/tactical/TacticalScene.tscn` (renamed) | Rename nodes, update script paths |
| `scripts/core/enemy_ai.gd` | Update BattleManager → TacticalManager references |
| `scenes/playground/playground_battle_ui.gd` | Update any BattleManager/BattleScene references |
| `scenes/battle/Unit.tscn` | Possibly move to scenes/tactical/Unit.tscn; adjust HP bar offset |

---

## Acceptance Criteria

- [ ] No files or classes named BattleScene or BattleManager remain
- [ ] Game launches with TacticalScene as main scene
- [ ] Grid renders as isometric diamond tiles
- [ ] Terrain colors and labels display correctly on diamonds
- [ ] Move/attack highlight shows diamond shapes
- [ ] Click detection works on isometric grid (click diamond → correct cell)
- [ ] Units spawn at correct isometric positions
- [ ] Unit movement animates along isometric coordinates
- [ ] Enemy AI turn still functions
- [ ] DamagePopup appears at correct positions
- [ ] HP bars display above units correctly
- [ ] No GDScript errors in output console

---

*Created: 2026-03-08 | Main Agent dispatch*
