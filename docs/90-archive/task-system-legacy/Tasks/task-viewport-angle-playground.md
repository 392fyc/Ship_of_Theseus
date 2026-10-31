# Task: Viewport Angle Comparison Playground

- Status: Completed (2026-03-08)
- Agent: Cursor (Claude Opus 4.6 or GPT-5.4)
- Branch: `cursor/viewport-angle-playground`
- Priority: P0 (blocks Map Token art style decision)
- ADR ref: ADR-008

---

## Objective

Build a Godot Playground scene that displays the same 6x6 tactical grid in three visual styles side by side, using free tileset assets. Human controller will visually compare and select the map view angle for TacticalScene.

---

## Three Schemes to Present

### Scheme A - Pure Top-Down

- Camera looks straight down (no perspective tilt)
- Grid cells are perfect squares
- Terrain tiles viewed from directly above
- Unit tokens are circular or square icons centered in cells
- Reference: Advance Wars map editor, classic Roguelike

### Scheme B - Oblique 3/4 View

- Camera at roughly 30-45 degree elevated angle
- Grid cells are still square in code (64x64), but tile art is drawn with depth perspective
- Terrain shows front faces (grass has visible edges, trees have trunks)
- Unit tokens are small figures seen from a 3/4 elevated angle
- Reference: GBA Fire Emblem overworld, Wargroove, Into the Breach

### Scheme C - Isometric

- Diamond-shaped tile rendering (rotated 45 degrees)
- Tiles have clear height/depth illusion
- Unit tokens stand on diamond cells
- Reference: Final Fantasy Tactics, Tactics Ogre, Disgaea
- Note: This is for visual comparison only; if selected, grid math would need significant rework

---

## Free Assets to Use

Download and place in `res://assets/playground/viewport_test/`. These are for Playground comparison only, not production.

### For Scheme A - Top-Down

- Option 1: Simple colored rectangles (no external asset needed, programmatic)
- Option 2: RGS_Dev CC0 Top Down Tileset - https://rgsdev.itch.io/free-cc0-top-down-tileset-template-pixel-art

### For Scheme B - Oblique 3/4

- ansimuz Tiny Overworld (GBA FE style) - https://ansimuz.itch.io/tiny-overworld
- OR Pita RPG Overworld Tileset - https://pita.itch.io/rpg-overworld-tileset
- OR MalibuDarby World Map Tiles (FE-esque) - https://malibudarby.itch.io/world-map-tiles

### For Scheme C - Isometric

- The Outlander Free Isometric Tileset CC0 - https://the-outlander.itch.io/free-isometric-tileset-topdown-cc0-for-prototyping

### Unit Token Placeholder

- For all three schemes: 48x48 colored circle or square with faction color (blue = player, red = enemy), plus a single letter (S = Swordmaster, A = Archer). No sprite art needed.

---

## Playground Scene Spec

File: `res://scenes/playground/viewport_angle_playground.tscn`
Script: `res://scenes/playground/viewport_angle_playground.gd`

### Layout

```
+-------------------+-------------------+-------------------+
|                   |                   |                   |
|   SCHEME A        |   SCHEME B        |   SCHEME C        |
|   Top-Down        |   Oblique 3/4     |   Isometric       |
|                   |                   |                   |
|   [6x6 grid       |   [6x6 grid       |   [6x6 grid       |
|    with tiles     |    with tiles     |    with tiles     |
|    + 3 tokens]    |    + 3 tokens]    |    + 3 tokens]    |
|                   |                   |                   |
+-------------------+-------------------+-------------------+
     Label A             Label B             Label C
```

### Requirements

1. Three SubViewport or Camera2D regions side by side, each showing a 6x6 grid
2. Each grid has mixed terrain: grass (majority), forest (3-4 cells), mountain (1-2 cells), water (1-2 cells)
3. Terrain layout is identical across all three schemes (same logical map)
4. Place 3 unit token placeholders: 2 blue (player) at columns 1-2, 1 red (enemy) at column 5
5. Each scheme has a label at the bottom identifying it
6. Independent scene file - does NOT touch TacticalScene or any production code
7. Grid math for Scheme A and B uses standard 64x64 square cells
8. Grid math for Scheme C uses isometric projection (can be approximate for demo purposes)

### Terrain Color Fallback

If tileset download fails or license is unclear, use programmatic colored rectangles:

| Terrain | Color |
|---------|-------|
| Grass | #4a8c3f |
| Forest | #2d5a1e |
| Mountain | #8b7355 |
| Water | #3a7cbf |

---

## Acceptance Criteria

- [ ] Playground opens as independent scene in Godot editor
- [ ] Three schemes visible side by side with clear labels
- [ ] Same map layout across all three schemes
- [ ] Unit tokens visible and distinguishable by faction color
- [ ] No production code modified
- [ ] Free assets placed in playground-specific directory (easy to delete later)

---

## What This Decision Affects

After human controller selects a scheme:
1. Map Token art style and generation pipeline spec
2. Tile art direction for TacticalScene
3. Whether grid math needs changes (only if isometric is chosen)
4. Camera and viewport configuration for TacticalScene

---

*Created: 2026-03-07 | Main Agent dispatch*

---

## Completion Report

- **Date**: 2026-03-08
- **Branch**: `cursor/viewport-angle-playground`
- **Commit**: `5a144ad` - Add C-only viewport angle static mockup
- **Result**: Scheme C (Isometric) selected

### Delivered Files

- `scenes/playground/viewport_angle_static_mockup.gd`
- `scenes/playground/viewport_angle_static_mockup.tscn`
- `assets/prototype/viewport_angle/README.md`

### Verification

- Godot MCP: scene opened, run, and stopped successfully
- Human visual inspection: PASS
- No production code modified (scenes/battle/, scripts/core/, scripts/battle/ untouched)
- Known ignores: project.godot touched, .uid auto-generated files

### Selection Rationale

- C (Isometric) visual quality superior to B (Oblique 3/4)
- Better tactical readability, less unit occlusion
- Slight token float accepted; anchoring adjustable in production
