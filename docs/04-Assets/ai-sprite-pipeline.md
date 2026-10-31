# AI Sprite Animation Pipeline

> 本文 `<project-root>` 指本地配置中游戏主仓 `ship_root` 的父目录。共享资源保留在 `<project-root>/SoT/resource/`；不能从任务工作树的父目录推导该位置。

*Created: 2026-03-04 | Research by: AntiGravity (Gemini 3.1 Pro) | Finalized: 2026-03-04*

## Overview

Pipeline for generating GBA Fire Emblem style tactical RPG sprites using AI tools.
Target spec: side-view, non-chibi, 1:3~1:5 head ratio, 128px base reference image.

Units required: Swordmaster / Archer / Mage / Goblin Enemy
Animation states per unit: IDLE / WALK / RUN / ATTACK / HIT / DEFEATED

Decision status: AI pipeline confirmed viable (2026-03-04). HEROES 99 deferred.

---

## Production Pipeline

```
[Step 1] NanoBanana 2.0 (Gemini)
  Character prompt → HD illustration (high-res, magenta background)
        ↓
[Step 1.5] Pixel Conversion (FFmpeg)
  Nearest-neighbor downsampling → 128×128 pixel art PNG, transparent background
        ↓
[Step 2 — Optional] Minor manual edit of pixel art
        ↓
[Step 3] Personal Pixel Tool
  Reference image (128px) + animation state prompt + motion constraints
  → PNG frame sequence + GIF preview
        ↓
[Step 4] Review
  Pass → proceed to Godot
  Fail → return to Step 3 (adjust prompt or regenerate)
        ↓
[Step 5] Godot 4 AnimatedSprite2D
  Import PNG sequence, Nearest filter, SpriteFrames
```

Kling, Seedance as standalone tools: **not used in this pipeline.**

---

## Step 1 — NanoBanana 2.0 Reference Image

### Reference Image Anchor Rule

The reference image is the **rest-frame anchor** for all animation states.
Any body part not in a fully neutral, grounded position will be interpreted as an
animation target by the pixel tool, causing unwanted drift between frames.

Requirements for every reference image:
- **Feet**: both soles completely flat on the ground plane; no raised heel, no tiptoe, no mid-step
- **Arms**: relaxed at sides; no mid-gesture or dynamic positioning
- **Pose**: neutral idle stance — not an action or dynamic pose
- **Weight**: stable and evenly distributed; no unstable forward or backward lean

Validate all four points before proceeding to Step 1.5.

### Reference Image Prompt — Swordmaster (Female)

```
Single character only. One subject, centered horizontally in the frame.
Do not generate multiple poses, variants, or comparison layouts.
The image contains exactly one character and nothing else.

A young adult female swordmaster.
Pose: neutral idle battle stance, GBA tactical RPG side-view style.
Full body side profile facing right. Head turned toward the viewer.
Standing at ease — both feet flat on the ground, weight balanced. No action pose.

Weapon: one-handed longsword in right hand, arm relaxed at side, blade pointing downward.
Tip above foot level — blade does not touch the ground. Blade tapers to a fine point.

Costume referencing Fire Emblem Three Houses Swordmaster class:
form-fitting dark navy ornate long coat with gold decorative trim along hem and collar,
high mandarin collar, tapered sleeves, dark fitted trousers, knee-high boots.
No armor plates. Elegant and agile, not martial-heavy.

Hair: long vivid crimson-red hair.
Bangs: soft center-parted curtain fringe; short wispy strands rest gently on the forehead;
two or three loose strands fall naturally across the cheek facing the viewer.
Back hair: one long voluminous cascade sweeping behind to the back-left,
flowing freely with natural movement, reaching well below shoulder level.
Hair does not obscure the sword arm or coat silhouette.

Build: slim athletic adult female. Sharp defined facial features, mature expression.
Strict 1:4 head-to-body ratio. Non-chibi. Realistic adult female proportions.
Full body visible from crown to boot soles, filling 90% of frame height.

Art style: Japanese tactical RPG character concept art. Mature and refined —
sharply defined adult facial features, realistic eye proportions, no oversized anime eyes,
no chibi or cartoon exaggeration. Think character sheet from Fire Emblem Three Houses,
not a cartoon or anime illustration.
Flat color regions with clearly defined shadow bands. Bold black outline.
Minimal gradients — favor distinct color bands over soft blending.
Designed for downstream pixel art conversion; avoid texture noise and sub-pixel detail.

Background: perfectly flat solid uniform magenta (#FF00FF).
No ground shadow. No background elements. No vignette.
Output: high-resolution PNG.
```

### Unit Archetype Prompts (Other Units)

Use the same structure as above. Replace character description block only.
Always include the single-character constraint. Do not add pixel art constraints — pixelization is handled in Step 1.5.

**Archer**
```
A nimble archer in a green travelling cloak over a leather tunic, holding a longbow
vertically at their side, full body at three-quarter angle facing right, neutral idle pose.
Strict 1:4 head-to-body ratio, non-chibi. High-quality digital illustration, clean flat
cel-shading, bold black outline. Earth tones, practical travelling attire.
Background: flat solid magenta (#FF00FF). No shadows. Output: high-resolution PNG.
```

**Mage**
```
A spellcaster in voluminous dark purple robes with gold trim, holding a wooden staff topped
with a glowing crystal, full body at three-quarter angle facing right, neutral idle pose.
Strict 1:4 head-to-body ratio, non-chibi. High-quality digital illustration, clean flat
cel-shading, bold black outline. Mystical aura, dramatic drapery.
Background: flat solid magenta (#FF00FF). No shadows. Output: high-resolution PNG.
```

**Goblin Enemy**
```
A hunched aggressive green-skinned goblin wielding a rusted spiked club, full body at
three-quarter angle facing left (enemy unit), neutral idle pose.
Strict 1:3 head-to-body ratio, slightly exaggerated monstrous proportions, non-chibi.
High-quality digital illustration, clean flat cel-shading, bold black outline.
Jagged textures, tattered loincloth.
Background: flat solid magenta (#FF00FF). No shadows. Output: high-resolution PNG.
```

---

## Step 1.5 — Pixel Conversion (FFmpeg)

Convert the HD reference image to a 128×128 pixel art PNG with transparent background.

### FFmpeg Command

```bash
ffmpeg -i input_hd.png -vf "colorkey=0xFF00FF:0.05:0.0,scale=128:128:flags=neighbor" -c:v png output_128.png
```

| Parameter | Purpose |
|-----------|---------|
| `colorkey=0xFF00FF:0.05:0.0` | Remove magenta background, convert to transparency |
| `scale=128:128:flags=neighbor` | Nearest-neighbor downsampling to 128×128 |
| `-c:v png` | Output as lossless PNG |

### Output Check

Verify before passing to Personal Pixel Tool (Step 3):

| Check | Pass Condition |
|-------|---------------|
| Dimensions | 128×128 px |
| Background | Fully transparent; no magenta fringe remaining |
| Silhouette | Character outline clearly readable at pixel scale |
| Color count | Visually ≤16 distinct colors (FFmpeg does not auto-reduce palette) |

If color count exceeds 16 visually distinct colors, apply palette reduction:

```bash
pngquant --nofs --quality=80-100 16 output_128.png
```

### Naming Convention

```
{character}_reference_128.png
swordmaster_reference_128.png
```

---

## Step 3 — Personal Pixel Tool Prompt Architecture

The personal pixel tool accepts a reference image and a text prompt describing the animation state.
All prompts follow this 4-block structure:

```
[BLOCK 1 — Character Reference]
Using the provided reference image as the character identity source.
Maintain exact: costume design, color palette, hair style and color,
body proportions, and pixel art style. Do not alter any design elements.

[BLOCK 2 — Animation State]
Animation state: [STATE NAME]
[State-specific description — see Motion Constraints below]

[BLOCK 3 — Motion Constraints]
[Paste the relevant constraints block from the section below]

[BLOCK 4 — Style Lock]
GBA Fire Emblem battle sprite pixel art style.
Hard cel-shading, 3 tonal levels per region, bold black outlines.
Maximum 16 colors. No anti-aliasing, no gradients.
Flat solid magenta (#FF00FF) background throughout all frames.
No background elements. No ground shadow.
```

---

## Motion Constraints by State

### IDLE
```
Animation state: IDLE — looping breathing cycle.

Motion constraints:
- ONLY the chest and upper torso expand and contract subtly with each breath
- Feet remain completely planted and stationary throughout all frames
- Both arms remain stationary; no arm swing, no hand repositioning
- The sword does not rotate, swing, or shift position in any frame
- Hair does not sway or blow; it remains in a fixed, settled position
- Head does not tilt, turn, or bob
- The entire lower body from waist down is completely frozen across all frames
- Total range of motion is extremely minimal — one slow inhale and exhale cycle only
```

### WALK
```
Animation state: WALK — looping bipedal walk cycle.

Motion constraints:
- Natural alternating leg stride, feet clearly leaving and returning to ground plane
- Opposing arm swing: right arm forward when left leg forward, and vice versa
- Sword arm swing is minimal — sword remains pointing downward, no lateral drift
- Body does not bounce vertically; maintain consistent head height across all frames
- Hair flows naturally behind the body with momentum, no wild whipping
- Head remains level throughout; no bobbing
- Stride length is moderate — not a march, not a sneak
```

### RUN
```
Animation state: RUN — looping fast movement cycle.

Motion constraints:
- Aggressive alternating leg stride, knees raised higher than walk
- Body leans forward approximately 10-15 degrees from vertical
- Sword arm held close to body, sword angled back with momentum
- Non-sword arm pumps in opposition to legs
- Hair streams directly behind, horizontal with speed
- Head remains stable; no nodding
- No jumping — feet return to ground each stride
```

### ATTACK
```
Animation state: ATTACK — single sword slash sequence, does not loop.

Motion constraints:
- One complete strike arc: windup → strike → follow-through
- Sword moves in a single clean horizontal or diagonal slash plane
- Body rotation does not exceed 45 degrees on windup
- Non-sword arm pulls back close to body during strike; does not flail outward
- Feet remain planted throughout all frames
- Head faces forward throughout; does not look away
- No secondary bounce or recovery step after follow-through
- Final frame returns to a stable ready stance
```

### HIT
```
Animation state: HIT — single recoil reaction, does not loop.

Motion constraints:
- Torso leans backward 20-30 degrees on impact frame
- Head snaps back briefly then returns
- Sword arm recoils with body but grip is maintained; sword does not drop
- Non-sword arm braces slightly outward, no excessive flailing
- Feet slide back no more than half a step; character does not fall
- Total animation: 3-4 frames — impact → peak recoil → recovery
- Final frame: character returns to stable stance
```

### DEFEATED
```
Animation state: DEFEATED — fall and collapse sequence, does not loop.

Motion constraints:
- Character topples toward the sword side (rightward fall)
- Body rotates from vertical to horizontal over the full sequence
- Sword arm falls with the body; sword slides to the ground
- No bounce on landing — final frame is completely still
- Hair drapes naturally at final rest position
- No dramatic spinning or tumbling — a single clean controlled fall
- Final frame: character fully horizontal, motionless, sword resting beside them
```

---

## Godot 4 Integration

1. Import PNG sequence into **AnimatedSprite2D** node via SpriteFrames resource panel
2. Texture filter: **Project Settings → Rendering → Textures → Default Texture Filter: Nearest**
3. Pivot point: **Bottom Center** (consistent with unit placement on grid cells)
4. Animation state names: `idle`, `walk`, `run`, `attack`, `hit`, `defeated`
5. Alpha transparency is pre-processed in the NanoBanana output — no shader needed

---

## Quality Assessment Checklist

| Criterion | Pass Condition |
|-----------|---------------|
| Head ratio | 1:3~1:5 visually confirmed, no chibi proportions |
| Loop seam (IDLE/WALK/RUN) | First frame ≈ last frame, no visible pop |
| Pixel stability | No boiling or geometry drift between frames |
| Silhouette clarity | Dark outline legible at game size, distinct unit identity |
| Color discipline | Visually ≤16 colors, no gradient banding |
| Background removal | Clean transparent background, no color fringing |
| Feet grounded in reference | Both soles flat on ground plane in reference image; no raised heel or tiptoe |
| Character consistency | Costume, hair, proportions identical to reference image |
| Motion scope | Only expected body parts move per state constraints |

---

## Decision Gate

After completing all 6 states for Swordmaster, evaluate before expanding to other units:

- All states pass checklist → proceed with AI pipeline for remaining units
- States with persistent issues → adjust motion constraints prompt and regenerate
- Fundamental quality failure → fall back to HEROES 99 purchase

HEROES 99 fallback: https://au-pixel.itch.io/heroes99 (paid commercial license)

---

## Verified Assets — Swordmaster

*Character: Female Swordmaster, red long hair, FE Three Houses Sword General style*
*Active reference image: `<project-root>/SoT/resource/Gemini_Generated_Image_z24sgbz24sgbz24s.png`*

| State | Status | File | Notes |
|-------|--------|------|-------|
| Reference v1 | ⚠️ | Gemini_Generated_Image_skai1vskai1vskai.png | Superseded — rear foot hover, sword too thin, left-hand grip |
| Reference v2 (128px) | ✅ | Gemini_Generated_Image_z24sgbz24sgbz24s.png | Current anchor — foot and sword corrected |
| IDLE | ✅ | rika_9512f411.png / .gif | 8 frames, human-edited, verified |
| WALK | ⬜ | — | Pending — unlock after IDLE stability confirmed (v2 prompts) |
| RUN | ⬜ | — | Pending |
| ATTACK | ⬜ | — | Pending |
| HIT | ⬜ | — | Pending |
| DEFEATED | ⬜ | — | Pending |

---

## Personal Pixel Tool — Pricing and Cost Planning

*Recorded: 2026-03-04*

### Pricing Tiers

| Tier | Price (RMB) | Uses | Unit Cost |
|------|-------------|------|-----------|
| A | ¥12 | 8 | ¥1.50 / use |
| B | ¥60 | 50 | ¥1.20 / use |
| C | ¥200 | 200 | ¥1.00 / use |

One use = one animation state for one unit (e.g. Swordmaster IDLE = 1 use).
Retries and re-generations each consume 1 use.

### Break-Even Points

| Range of Uses Needed | Optimal Tier | Cost |
|----------------------|--------------|------|
| 1 – 8 | A × 1 | ¥12 |
| 9 – 16 | A × 2 | ¥24 |
| 17 – 24 | A × 3 | ¥36 |
| 25 – 50 | B × 1 | ¥60 |
| 51 – 100 | B × 2 | ¥120 |
| 101 – 150 | B × 3 | ¥180 |
| 151 – 200 | C × 1 | ¥200 (saves ¥40 vs B×4) |
| 201 – 250 | C × 1 + A × 1 | ¥212 |

Tier B becomes cheaper than Tier A from **25 uses onward**.
Tier C becomes cheaper than stacking Tier B from **151 uses onward**.

### Estimated Consumption by Scope

| Scope | Units | States | Base Uses | +25% Retry Buffer | Recommended Tier |
|-------|-------|--------|-----------|-------------------|-----------------|
| M7 Demo (1 unit) | 1 | 6 | 6 | ~8 | A × 1 (¥12) |
| M1.5 Full (4 units) | 4 | 6 | 24 | ~30 | B × 1 (¥60) |
| Phase 1 Complete (4 units + variants) | 6 | 6 | 36 | ~45 | B × 1 (¥60) |
| Phase 2 Expansion (10+ units) | 10 | 6 | 60 | ~75 | B × 2 (¥120) |
| Full Game Asset Library (20+ units) | 20 | 6 | 120 | ~150 | B × 3 or C × 1 (¥180–¥200) |

### Decision Rule

```
If estimated uses ≤ 24 with no retry margin  → Tier A (buy as needed)
If estimated uses 25–150                     → Tier B (standard choice)
If estimated uses 151+                       → Tier C (bulk discount)
```

---

## Swordmaster Prompt Stabilization v2 (2026-03-06)

Supersedes the v1 Regeneration Pack. Use these prompts for all Swordmaster generation.
Do not mix multiple state blocks in one generation request.

### Known Generation History

| Image | Status | Issues |
|-------|--------|--------|
| Gemini_Generated_Image_skai1vskai1vskai.png | ⚠️ Superseded | Rear foot hover → frame drift; left-hand grip; sword too thin |
| Gemini_Generated_Image_z24sgbz24sgbz24s.png | ✅ Active anchor | Foot and sword corrected |

NanoBanana 2 system limitation: iterative detail refinement is unreliable. Orientation flip
(back-to-viewer) occurs frequently when orientation constraints are under-specified. Prompts
must be complete in one pass — do not attempt fine detail edits in subsequent NanoBanana calls.

---

### Failure Tag System

| Tag | Scope | Failure Description | Detection Signal |
|-----|-------|---------------------|-----------------|
| `feet_not_grounded` | REF + ANIM | One or both feet hover, tip-toe, or lose ground contact | Visible gap under sole(s); heel raised |
| `weapon_shape_mutation` | REF + ANIM | Sword changes length, bends, tapers differently, or changes hand | Sword silhouette differs from reference |
| `idle_overmotion` | ANIM | Motion beyond chest breathing — arm swing, hip sway, head bob | Any non-chest region moves > 1–2px |
| `hair_boiling` | ANIM | Individual strands crawl, shimmer, or reshape per frame | Hair silhouette boundary changes between frames |
| `scale_drift` | ANIM | Character grows or shrinks between frames | Head-to-sole pixel height not constant |
| `pose_not_neutral` | REF | Reference shows dynamic / battle-tension pose instead of true neutral | Arms not at sides; weight shifted; foot raised |
| `outline_noise` | ANIM | Outline has pixel crawl, double-edge artifacts, or inconsistent width | Outline pixels shift or appear on new pixels |
| `silhouette_break` | REF + ANIM | Extremities cropped or hair/sword bleeds off canvas | Boot soles, sword tip, hair mass exits bounds |
| `orientation_flipped` | REF | Character generated back-to-viewer instead of side-profile facing right | Back of costume visible; face not visible; or character faces left |

`orientation_flipped` is a NanoBanana 2 system-level failure. It is not fixable via
animation-state prompt injection — requires reference regeneration with orientation override block.

---

### Global Stability Prefix v2

Paste this block before every state-specific block when using Personal Pixel Tool:

```text
Using the provided reference image as the sole identity anchor.
Keep exact: camera angle, facing direction, body proportions, costume silhouette,
hair design, sword design, palette, and pixel-art rendering style.
Do not redesign, simplify, or reinterpret the character.
Do not change zoom level or character scale between frames.
Character pixel height is identical in every frame — no zoom creep, no crop drift.
Do not crop the feet, sword tip, or hair mass in any frame; all must be within bounds.
Both boot soles remain in full contact with the ground plane in every frame.
Sword silhouette (length, taper, blade shape) is rigid and identical across all frames.
Hair is treated as one single mass — the silhouette boundary does not change between frames.
Outline is 1px bold black throughout; no anti-aliasing, no crawling, no double-pixel edges.
Preserve a clean readable silhouette in every frame.
Minimize frame-to-frame pixel jitter, outline boiling, and anatomy warping.
Full-body side-view battle sprite facing right in every frame.
Flat solid magenta (#FF00FF) background only.
```

---

### Reference Prompt v2 (NanoBanana Step 1)

> **NanoBanana 2 orientation note**: This tool frequently generates back-to-viewer output
> when orientation is under-specified. The ORIENTATION block below uses layered, redundant
> constraints to force the correct result. Do not shorten or remove it.

```text
Single character only. One subject, centered horizontally in the frame.
Do not generate multiple poses, variants, or comparison layouts.
The image contains exactly one character and nothing else.

--- ORIENTATION (critical — read carefully) ---
The character is shown in full-body LEFT-to-RIGHT side profile view.
The character's RIGHT side faces the viewer. The LEFT side faces away.
The character's FACE is visible and directed toward the viewer.
The character's BACK is not visible. We are not looking at the character's back.
The character moves or would move toward the RIGHT side of the image.
Her RIGHT arm (sword arm) hangs along the near side — closest to the viewer.
Her LEFT arm is on the far side, partially behind her body.
This is a SIDE VIEW from the character's RIGHT side, NOT a rear view, NOT a front view.

A young adult female swordmaster.
Standing completely at ease in a neutral idle stance — NOT a dynamic or battle-ready pose.
Arms hang naturally at the character's sides with no tension or raised positioning.
Both feet are planted side-by-side on the ground plane.
Both boot soles are in full contact with the ground — no raised heel, no tiptoe,
no mid-step shift, no weight transferred to one foot only.
The soles of both boots must be visibly flat against the ground plane. Zero hovering.

Weapon: one-handed longsword in the character's RIGHT hand (near-side arm, closest to viewer).
Arm relaxed at side, blade pointing straight downward.
Sword tip is at knee height or slightly above; blade does not touch the ground.
Blade is broad with visible width and clear taper to a fine point — not wire-thin.
Sword has clear visual weight and a strong readable silhouette.
Sword shape is simple and clean. Do not add scabbard, second weapon, or extra accessories.

Costume referencing Fire Emblem Three Houses Swordmaster class:
form-fitting dark navy ornate long coat with gold decorative trim along hem and collar,
high mandarin collar, tapered sleeves, dark fitted trousers, knee-high boots.
No armor plates. Elegant and agile, not martial-heavy.

Hair: long vivid crimson-red hair.
Bangs: soft center-parted curtain fringe; short wispy strands rest gently on the forehead;
two or three loose strands fall naturally across the cheek facing the viewer.
Back hair: one long voluminous cascade sweeping behind to the character's left (away from viewer),
flowing freely with natural gravity, reaching well below shoulder level.
Hair does not obscure the sword arm or coat silhouette.
Hair rests in a settled, gravity-following position — not mid-motion, not wind-blown.

Build: slim athletic adult female. Sharp defined facial features, mature expression.
Strict 1:4 head-to-body ratio. Non-chibi. Realistic adult female proportions.
Full body visible from crown to boot soles, filling 90% of frame height.

Art style: Japanese tactical RPG character concept art. Mature and refined.
Sharply defined adult facial features, realistic eye proportions, no oversized anime eyes,
no chibi or cartoon exaggeration. Think character sheet from Fire Emblem Three Houses.
Flat color regions with clearly defined shadow bands. Bold black outline, 1px consistent width.
Minimal gradients — favor distinct color bands over soft blending.
No dithering, no texture noise, no anti-aliasing, no sub-pixel detail.
Designed for downstream pixel art conversion.

Background: perfectly flat solid uniform magenta (#FF00FF).
No ground shadow. No background elements. No vignette.
Output: high-resolution PNG.
```

#### Orientation Failure Recovery

If `orientation_flipped` occurs (back-to-viewer or leftward-facing output), regenerate with
these lines inserted immediately after the `--- ORIENTATION ---` block:

```text
CRITICAL OVERRIDE: The generated image must show the character facing toward the right edge
of the canvas. Her face must be visible. We see her chest and front, not her back.
Reject any output where the back of the costume is the dominant visible surface.
```

Do not attempt to fix orientation by requesting hair or background changes in the same pass.
NanoBanana 2 cannot reliably isolate orientation from other design elements.

---

### IDLE Prompt v2

```text
Animation state: IDLE — looping breathing cycle, 6–8 frames.

Motion requirements:
- Only the chest and upper torso rise and fall very slightly with each breath cycle
- Maximum displacement anywhere outside the chest region: 1–2px total
- Lower body from waist down is completely frozen across all frames
- Both boot soles remain on the exact same ground plane in every frame; no raising, no tiptoe
- Sword hand is fixed; sword angle, sword length, and sword silhouette do not change
- Hair silhouette is one rigid settled mass — individual strands do not move or shimmer
- Head height stays constant in every frame; no bobbing, no tilt, no turn
- No lateral drift of the full character between frames
- Outline pixels are stable between frames; no crawl, no shimmer, no new edge pixels
- All extremities (boot soles, sword tip, hair mass) remain within frame bounds
- Loop must return cleanly to frame 1 with no visible pop or positional jump
```

---

### WALK Prompt v2

```text
Animation state: WALK — looping controlled walk cycle, 8 frames.

Motion requirements:
- Moderate alternating step cycle with clear foot contact and lift phases
- Character advances through leg motion only; camera framing and scale stay fixed
- Head height stays nearly constant; avoid bounce
- Sword remains in right hand, pointing generally downward throughout the loop
- Sword arm swing is subtle and shorter than the off-hand swing
- Hair follows body motion with gentle delayed sway only
- No foot sliding on contact frames
- Final frame transitions cleanly back to frame 1
```

### RUN Prompt v2

```text
Animation state: RUN — looping forward run cycle, 6–8 frames.

Motion requirements:
- Stronger stride than WALK with a slight forward lean
- Feet still make believable ground contact; do not turn into a jump loop
- Head stays stable relative to the torso; no nodding
- Sword remains close to the body and trails slightly backward with momentum
- Sword shape stays rigid; no bending, no length change
- Free arm pumps naturally in opposition to the legs
- Hair streams backward but remains readable as one stable mass
- No camera shake, no zoom shift, no silhouette distortion
```

### ATTACK Prompt v2

```text
Animation state: ATTACK — single non-looping sword slash, 5–6 frames.

Motion requirements:
- Sequence is windup -> strike -> follow-through -> stable ready frame
- Use one clean slash arc only; no combo, no extra second strike
- Feet stay planted; no step-in and no hop
- Torso rotates only as needed to support the slash
- Sword remains a rigid one-handed longsword in the right hand throughout
- Off-hand stays controlled near the torso; no wide flaring
- Head keeps facing forward toward the enemy side
- Final frame settles into a balanced combat-ready stance
```

### HIT Prompt v2

```text
Animation state: HIT — single recoil reaction, 3–4 frames, non-looping.

Motion requirements:
- Impact causes a brief backward recoil through the torso and shoulders
- Sword arm recoils with the body but the grip stays secure
- Feet may slide slightly but no more than half a step
- Character must not spin, kneel, or fall down
- Hair reacts briefly, then settles immediately
- No exaggerated smear or squash-and-stretch
- Final frame returns to an upright stable stance
```

### DEFEATED Prompt v2

```text
Animation state: DEFEATED — single collapse sequence, 5–6 frames, non-looping.

Motion requirements:
- Character loses balance and collapses cleanly toward the sword side
- Body rotation is controlled and readable from standing to grounded
- Sword stays in hand during the fall, then rests naturally beside the body
- No bounce on impact and no extra recovery motion
- Hair follows gravity and settles into the final pose
- Final frame is fully motionless and clearly readable
- Keep the full body visible until the last frame
```

---

### Failure Prompt Fix Table

Identify the tag(s) in the failed generation. Inject the fix string at the END of the state
prompt block, on its own line. Apply only the fix(es) for observed tags.
**Rule: Do not retry without a prompt delta. Each credit spend requires a changed prompt.**

| Tag | Inject This Fix String |
|-----|------------------------|
| `feet_not_grounded` | `Feet fix: both boot soles are flat on the ground plane in every single frame. No raised heel, no tiptoe, no mid-step positioning.` |
| `weapon_shape_mutation` | `Sword fix: blade length, taper, and full silhouette are pixel-for-pixel identical in every frame. Blade does not bend, does not grow, does not shrink.` |
| `idle_overmotion` | `Motion fix: only chest pixels move. Every other region including arms, hands, legs, feet, and head is completely frozen. Total non-chest displacement must not exceed 2px anywhere.` |
| `hair_boiling` | `Hair fix: treat hair as one single rigid mass. The outer boundary of the hair silhouette must not change between frames. Individual strands do not move, shimmer, or reorganize.` |
| `scale_drift` | `Scale fix: character total pixel height from crown to boot sole is identical in every frame. No zoom change, no framing shift, no partial crop.` |
| `pose_not_neutral` | `Pose fix: this is a static neutral stance. Arms hang at sides. Both feet planted equally. No combat tension, no weight shift. (Apply to reference regeneration, not animation.)` |
| `outline_noise` | `Outline fix: the black outline is exactly 1px wide with no anti-aliasing. Outline pixels do not shift or appear on new locations between frames. No double-edges, no fuzz.` |
| `silhouette_break` | `Frame fix: all extremities — boot soles, sword tip, and complete hair mass — must be fully inside the frame bounds in every single frame. Do not crop any body part.` |
| `orientation_flipped` | *(Reference-only — apply orientation override block in Reference Prompt v2 section. Not fixable via animation prompt injection. Regenerate reference.)* |

#### Secondary Escalation (same tag fails after first fix)

If a tag persists after the first fix is applied, add the secondary escalation string on a new
line. If it recurs a third time, stop and flag to human operator before spending another credit.

| Tag | Secondary Escalation |
|-----|----------------------|
| `feet_not_grounded` | `Absolute ground lock: draw an invisible floor line and pin both feet to it. Feet never move upward even 1px.` |
| `weapon_shape_mutation` | `Sword identity lock: copy the exact sword shape from the reference image as if tracing it — same pixel count, same length, same taper angle.` |
| `idle_overmotion` | `Near-static mandate: treat this as a near-still image with only a subtle brightness pulse in the chest region. No animation elsewhere.` |
| `hair_boiling` | `Hair static lock: do not animate the hair at all. Hair is 100% frozen across all frames.` |
| `scale_drift` | `Pixel ruler lock: place an invisible ruler alongside the character; the crown and boot sole must touch the same ruler marks in every frame.` |

---

### Go / No-Go Gate

**Condition to unlock WALK / RUN / ATTACK / HIT / DEFEATED:**

A generation batch passes if ALL of the following are true across all frames:

| # | Check | Pass Threshold |
|---|-------|----------------|
| 1 | `feet_not_grounded` | Zero — both soles grounded in every frame |
| 2 | `weapon_shape_mutation` | Zero — sword silhouette identical across all frames |
| 3 | `idle_overmotion` | Zero — only chest region displaces; all other regions frozen |
| 4 | `hair_boiling` | ≤ 1 minor pixel tick — no strand shimmer, mass boundary stable |
| 5 | `scale_drift` | Zero — head height constant across all frames |
| 6 | `pose_not_neutral` | Zero — reference image check; arms at sides, both soles flat |
| 7 | `outline_noise` | ≤ 1 isolated pixel per frame — no systematic crawl |
| 8 | `silhouette_break` | Zero — all extremities in frame in all frames |

**To reach GO:** IDLE must achieve PASS on **2 independent generation runs** (not 1).
One lucky pass is not sufficient — confirm the prompt is stable.

**Budget guard:** Each retry must include a prompt delta (at least one fix injection applied).
Do not spend a credit regenerating with identical prompt. If 3 attempts fail on the same tag
after fix injection, flag to human operator — do not auto-escalate to WALK.

---

### Current Execution Order

1. Confirm reference image `Gemini_Generated_Image_z24sgbz24sgbz24s.png` is in `<project-root>/SoT/resource/`
2. Run IDLE using `Global Stability Prefix v2 + IDLE Prompt v2`
3. Review IDLE output against Go/No-Go gate (8 checks)
4. If FAIL: identify tag(s), inject fix string(s), regenerate — do not skip prompt delta
5. Once IDLE achieves 2× independent PASS, unlock WALK generation
6. Continue in order: WALK → RUN → ATTACK → HIT → DEFEATED


---

## Session Findings (2026-03-07) — Prompt Stabilization v2 Test

### NanoBanana 2 Operational Rules (Confirmed)

| Control Type | Text Prompt Only | Reference Image + Text |
|-------------|-----------------|----------------------|
| Character details (costume, hair, accessories) | ✅ Reliable | ✅ Reliable |
| Orientation (facing direction) | ❌ Unreliable — frequent back-to-viewer output | ✅ Reliable |
| Composition (single view vs multi-view sheet) | ❌ Unreliable — detailed prompts trigger character sheet mode | ✅ Reliable |
| Fine detail edits (iterative refinement) | ❌ Unreliable — reinterprets whole character | N/A |

**Rule: NanoBanana 2 composition and orientation must be controlled via reference image. Text prompts control design details only.**

Workflow for new characters:
1. Simple prompt first (minimal detail) to get correct single-view composition
2. If still multi-view, provide any existing side-view reference image as composition anchor
3. Once correct composition obtained, use it as reference + full detail prompt for final generation

### Progressive Asset Generation — Reference Library

Build a per-attribute reference image library. When a specific attribute fails in generation,
provide the relevant reference image rather than adding text overrides.

| Attribute | Reference Image Purpose | Source |
|-----------|------------------------|--------|
| Facing / stance | Lock orientation and weight distribution | First successful side-view generation |
| Hairstyle | Lock hair volume, length, flow direction | Dedicated hair-focused generation |
| Weapon | Lock blade width, length, grip style | Dedicated weapon-focused generation |
| Costume | Lock coat silhouette, trim pattern, color | Reference or official FE3H art |

Store reference images in `<project-root>/SoT/resource/reference-library\` by attribute.

### Resolution Decision

Sprite resolution changed from 128x128 to **256x256**.

| Factor | 128x128 | 256x256 |
|--------|---------|---------|
| AI generation noise ratio | High — coarse pixels | Low — cleaner detail |
| Outline stability | 1px outline = large ratio | More stable outlines |
| Weapon readability | Sword ~2-3px wide | Sword ~5-6px wide |
| Downstream compatibility | Can upscale with nearest | Can downscale to 128 anytime |
| Godot performance | Negligible | Negligible |

FFmpeg Step 1.5 command updated: `scale=256:256:flags=neighbor`

### Personal Pixel Tool — Parameter Reference

#### Tool Settings per State

| State | Low Noise | High Noise | Frames | Palette | Background RGB |
|-------|-----------|------------|--------|---------|---------------|
| IDLE | 0.5 | 0.3 | 12 | 24 | 255, 0, 255 |
| WALK | 0.9 | 0.8 | 12 | 24 | 255, 0, 255 |
| RUN | 1.1 | 1.0 | 12 | 24 | 255, 0, 255 |
| ATTACK | 1.1 | 1.0 | 16 | 24 | 255, 0, 255 |
| HIT | 0.8 | 0.7 | 12 | 24 | 255, 0, 255 |
| DEFEATED | 1.0 | 0.9 | 16 | 24 | 255, 0, 255 |

Noise range: 0–2 (step 0.1). Frame options: 8/10/12/14/16 (even only).
Palette range: 8–64 (color count).

**Parameter principles:**
- Low noise > High noise (always) — allow texture variation, suppress structural drift
- Less motion → lower noise (IDLE lowest, ATTACK/RUN highest)
- Higher frame count → smaller per-frame delta → better AI consistency
- 24 palette balances pixel style with 256x256 detail needs (16 too few, 32 starts gradient bleed)

#### Additional Tool Features

- **Middle frame pin**: Set a specific image as the midpoint frame — forces animation to return to a known pose
- **End frame pin**: Set a specific image as the final frame — ensures clean loop closure
- For IDLE: set both middle and end frame to the reference image for maximum stability

#### Streamlined Prompt Format

The tool responds best to comma-separated descriptive phrases matching its native prompt style.
Do NOT include in prompt (handled by tool UI): frame count, background color, palette setting.

Native IDLE example from tool:
```
side-view, 2D game character standing in place, breathing motion,
body sways up-and-down slightly, chest and shoulders rising and falling,
head bob synchronized with breathing.
```

Adapted IDLE prompt (tested and verified):
```
side-view, 2D pixel art game character standing in place, very subtle breathing motion only,
chest rises and falls very slightly, all other body parts remain completely still and frozen,
feet planted flat on ground throughout, sword held still at right side pointing down with
no movement, hair stays settled in fixed position, head stays level at constant height,
character stays centered with no lateral drift, consistent character size across all frames,
clean stable 1px black outline, smooth loop back to first frame.
```

### Swordmaster IDLE — Test Result

**Configuration:** Low noise 0.5 / High noise 0.3 / 12 frames / Palette 24 / 256x256
**Reference image:** NanoBanana 2 output using z24sgb as reference
**Output:** `rika_fa8c464f.gif` / `rika_fa8c464f.png` (12-frame sprite sheet)

**Human operator Go/No-Go result: ✅ PASS (Run 1 of 2)**

| # | Check | Result | Human Assessment |
|---|-------|--------|-----------------|
| 1 | feet_not_grounded | ✅ | No offset detected |
| 2 | weapon_shape_mutation | ✅ | No deformation |
| 3 | idle_overmotion | ✅ | Only hair and clothing move, limbs still |
| 4 | hair_boiling | ✅ | Hair movement is natural wind-blown effect |
| 5 | scale_drift | ✅ | No size change |
| 6 | pose_not_neutral | — | Reference check, skipped |
| 7 | outline_noise | ✅ | No issues reported |
| 8 | silhouette_break | ✅ | Full body in frame |

**Known minor issue:** Background gradually brightens across frames. Not a character issue.
Needs investigation for FFmpeg colorkey impact. Low priority.

### Go/No-Go Process Correction

**Critical learning: AI cannot reliably judge animation quality from static sprite sheet images.**
Frame-to-frame differences in a sprite sheet may represent intended animation, not failures.

Corrected process:
1. Human operator reviews the **animated GIF** (not the sprite sheet PNG)
2. Human identifies failure tags by visual inspection of the animation
3. AI role is limited to: mapping identified tags to fix strings, tracking prompt deltas, enforcing budget rules
4. AI does NOT make Go/No-Go judgments on animation quality

### Open Architecture Question — Escalate to Main Agent

**Question:** How do 256x256 side-view battle sprites integrate with the game engine?

| Scene | Unresolved |
|-------|-----------|
| Map movement | 256px on grid cell requires extreme downscale; side-view may not suit top-down/isometric map |
| Battle scene | Primary intended use; needs camera/viewport scale definition |
| Character display | May need separate portrait or half-body assets |

**Decision needed:** Whether map scene uses same sprites (scaled), separate chibi set, or icon tokens.
This affects total asset pipeline scope and should be decided before expanding to more units.
