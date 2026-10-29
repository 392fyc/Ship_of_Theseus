# ADR-008: Three-Layer Unit Asset Architecture and Scene Naming

- Status: Approved
- Date: 2026-03-07
- Context: Define the three-layer visual asset system (Map Token / Battle Sprite / Portrait) for unit representation across game scenes, and establish naming conventions for tactical vs combat scenes

---

## Decision Summary

Adopt a three-layer unit asset architecture: **Map Token** (isometric grid), **Battle Sprite** (side-view cutin), and **Portrait** (UI display). Rename the grid-based scene from BattleScene to TacticalScene and introduce CombatScene for side-view battle cutins.

---

## Scene Naming

| Old Name | New Name | Responsibility |
|----------|----------|----------------|
| BattleScene | **TacticalScene** | Grid map: unit movement, turn management, skill targeting, terrain, highlights |
| BattleManager | **TacticalManager** | Manages TacticalScene logic: units, turns, highlights, grid state |
| *(new)* | **CombatScene** | Side-view battle cutin: plays ATTACK / HIT / DEFEATED animations when units engage |

### Flow

```
TacticalScene (isometric grid map)
  --> Unit A attacks Unit B
  --> CombatScene launched (side-view cutin)
  --> Animations play: attacker ATTACK, defender HIT or DEFEATED
  --> CombatScene closes
  --> TacticalScene resumes turn
```

---

## Three-Layer Asset Architecture

### Layer 1 - Map Token

| Field | Spec |
|-------|------|
| Purpose | Unit representation on the tactical grid map |
| Resolution | 48x48 px (on 64x64 logical grid cells) |
| View angle | Isometric (decided 2026-03-08 via Playground) |
| Animation states | IDLE (breathing/bob loop), WALK (4 directional) |
| Non-animated effects | ATTACK: position displacement + weapon swing VFX; HIT: flash white/red + slight knockback; DEFEATED: fade out or collapse via Tween |
| M7 placeholder | Colored rectangles with faction tint (current implementation) |

### Layer 2 - Battle Sprite

| Field | Spec |
|-------|------|
| Purpose | Side-view animated combat cutin in CombatScene |
| Resolution | 256x256 px |
| View angle | Side-view (facing right for player, left for enemy) |
| Animation states | ATTACK, HIT, DEFEATED only |
| Pipeline | NanoBanana 2 reference image + Personal Pixel Tool animation (existing pipeline) |
| Note | No IDLE or WALK states needed for battle sprites |

### Layer 3 - Portrait

| Field | Spec |
|-------|------|
| Purpose | UI panels, status bars, turn order display |
| Source | Cropped from NanoBanana 2 Step 1 HD reference image |
| Format | Static image or IDLE GIF |
| View angle | Front or 3/4 view (inherits from NB2 reference) |
| Note | No dialogue system planned for current milestone; simple display only |

---

## Animation State Matrix

| State | Map Token | Battle Sprite | Method |
|-------|-----------|---------------|--------|
| IDLE | Sprite animation (loop) | Not needed | AnimatedSprite2D |
| WALK | Sprite animation (4-dir) | Not needed | AnimatedSprite2D |
| ATTACK | Tween displacement + VFX | Sprite animation | Token: Tween; Battle: SpriteFrames |
| HIT | Flash shader + knockback | Sprite animation | Token: ShaderMaterial; Battle: SpriteFrames |
| DEFEATED | Tween fade/collapse | Sprite animation | Token: Tween; Battle: SpriteFrames |

---

## Grid and Camera Context

| Parameter | Value |
|-----------|-------|
| Grid CELL_SIZE | 64x64 px logical (unchanged, ADR-001) |
| Map Token size | 48x48 px (fits within cell with margin) |
| Map view angle | **Isometric** (decided 2026-03-08) |
| Isometric projection | `screen_x = (grid_x - grid_y) * tile_w/2`, `screen_y = (grid_x + grid_y) * tile_h/2` |
| Grid math impact | `grid_to_world` / `world_to_grid` need isometric conversion; logical grid remains square |
| Token anchoring | Bottom-center anchor; slight float above tile surface is acceptable |
| Tile rendering | Diamond top-face + left/right side-faces for depth; side-faces darken 20%/40% |
| CombatScene viewport | Separate viewport or overlay, scale TBD |

### Isometric Decision Rationale

Decided via Playground visual comparison (commit `5a144ad` on `cursor/viewport-angle-playground`).

- Scheme B (Oblique 3/4) and Scheme C (Isometric) were both prototyped
- C was selected for superior visual quality and better tactical readability
- Isometric view reduces unit occlusion vs oblique
- Slight token float above tile surface accepted as trade-off for clean anchoring
- Grid logic remains square internally; only rendering transforms to isometric

---

## Impact on Existing Pipeline

| Item | Impact |
|------|--------|
| NB2 battle sprite pipeline | Reduced scope: only ATTACK / HIT / DEFEATED (was 6 states) |
| NB2 reference image (Step 1) | Dual use: portrait source + animation anchor |
| Map Token pipeline | New - needs definition after view angle is decided |
| Unit.tscn | Existing placeholder animations (idle, walk_4dir, hurt, death) align with Map Token layer |
| BattleScene.tscn rename | Rename to TacticalScene.tscn, script to tactical_scene.gd |
| BattleManager rename | Rename to TacticalManager, script to tactical_manager.gd |
| CombatScene.tscn | New scene, to be designed |

---

## Open Items

1. ~~**Map view angle**~~: **Resolved** — Isometric selected (2026-03-08)
2. **Grid math refactor**: `grid_to_world` / `world_to_grid` need isometric projection; `Grid.CELL_SIZE` remains 64x64 logical
3. **CombatScene camera/viewport**: Layout, scaling, background treatment — design next
4. **Map Token art pipeline**: Isometric token generation spec needed
5. **Isometric tile art**: Diamond tiles with terrain depth — generation pipeline TBD

---

*Approved: 2026-03-07 | Three-layer architecture and naming confirmed by human controller*
*Updated: 2026-03-08 | Isometric view angle selected via Playground comparison*
