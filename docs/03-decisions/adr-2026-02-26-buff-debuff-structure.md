# ADR-002: Buff/Debuff Data Structure

- **Date**: 2026-02-26
- **Status**: Adopted
- **Decision Maker**: Design Agent (Claude)

---

## Background

Units need to maintain a Buff/Debuff list for timing-based triggers in the turn system (effects trigger at Unit Turn Start; duration decrements at Unit Turn End). The Buff system spans multiple subsystems including combat calculations (stat modifiers), terrain effects (burn/poison/wet), skill-applied effects, and Gauge interval effects.

### Constraints - from turn-system.md

1. **Trigger Timing**: Effect trigger = Unit Turn Start; duration decrement = Unit Turn End
2. **Application Timing**: Application = immediate effect (stats are affected as soon as the buff is applied)
3. **Stacking Logic**: Must support same buff_id override (refresh duration) or independent instances (stacking layers)
4. **Multiplayer Serialization**: Must serialize entire Unit state (including all Buffs) for multiplayer sync
5. **Iteration Efficiency**: TurnManager must iterate all Buffs on a Unit at the start and end of each turn

---

## Options

### Option A: `Array[Resource]` - Each Buff as Resource Subclass

```
class BuffEffect extends Resource:
  var buff_id: String
  var duration: int
  var value: float
  ...

Unit.buffs: Array[BuffEffect]
```

### Option B: `Array[Dictionary]` - Each Buff as Plain Dictionary

```
Unit.buffs: Array[Dictionary]
# Each element: {"id": "burn", "duration": 3, "value": 10, ...}
```

### Option C: `Dictionary[String, Array]` - key=buff_id, value=Instance List

```
Unit.buffs: Dictionary
# {"burn": [instance1, instance2], "shield": [instance1]}
```

---

## Selected Option: Option A - `Array[BuffEffect]` Resource Subclass

---

## Rationale

| Consideration | Option A (Selected) | Option B | Option C |
|---------|-------------|--------|--------|
| **Type Safety** | Editor autocomplete; field typos caught at compile time | String keys unchecked; errors only at runtime | Same as B (values are still Dictionary or Resource) |
| **Logic Encapsulation** | Buff has built-in `tick()` / `apply()` / `remove()` methods | Logic scattered across TurnManager and other externals | Grouping by id aids lookup, but logic encapsulation is equally difficult |
| **Serialization** | Resource natively supports custom `to_dict()` export | Naturally JSON-friendly | Key-value structure serialization is slightly cumbersome |
| **Iteration** | Simple Array iteration, O(n) | Same as A | Requires double-layer iteration (outer keys + inner Array) |
| **Stacking Check** | `has_buff(id)` iterates Array to find, O(n) acceptable | Same as A | O(1) direct key lookup, fastest dedup |
| **Godot Compatibility** | Resource is Godot's recommended data container, integrates well with the editor | Dictionary has no editor support | Mixed structure, complex to maintain |

**Decisive Factors**:
1. Buff logic is complex (different trigger/effect/stacking rules); encapsulating in Resource methods is more maintainable than external switch-case
2. On a 10x10 map with at most ~20 units, each typically having <=5 Buffs, performance is not a bottleneck
3. Option C's O(1) dedup advantage is meaningless at this scale, and it adds iteration complexity

---

## Implementation Spec

### BuffEffect Field Definition

```
class BuffEffect extends Resource:
  # === Identification ===
  var buff_id: String          # Unique identifier, e.g. "burn", "shield", "sword_qi_surge"
  var display_name: String     # Display name, e.g. "Burn", "Shield"
  var icon: String             # Icon resource path (for UI)

  # === Timing ===
  var duration: int            # Remaining turns (-1 = permanent, until manually removed)
  var max_duration: int        # Initial total turns (used by UI to display progress)

  # === Effect ===
  var effect_type: String      # "stat_mod" | "dot" | "hot" | "shield" | "control" | "special"
  var stat_key: String         # When effect_type="stat_mod", the stat key to modify (e.g. "atk", "def")
  var value: float             # Effect value (positive=buff, negative=debuff)
  var is_percentage: bool      # true=percentage modifier, false=flat value modifier

  # === Trigger ===
  var trigger: String          # "turn_start" | "turn_end" | "on_hit" | "on_attacked" | "permanent"
  var source_unit_id: String   # Applier's ID (for faction checks, effect attribution)

  # === Stacking Rules ===
  var stackable: bool          # true=can stack new instances (e.g. Sharp Wound up to 3 layers)
  var max_stacks: int          # Max stack count (effective when stackable=true, 0=unlimited)
  var refresh_on_reapply: bool # Whether to refresh duration on reapplication (effective when stackable=false)
```

### Stacking Rules

| Scenario | stackable | refresh | Behavior |
|------|-----------|---------|------|
| Burn (override type) | false | true | Reapplication refreshes duration, does not stack damage |
| Sharp Wound (stacking type) | true | false | Each hit adds a new instance, up to max_stacks layers |
| Shield (independent type) | true | false | Shields from different sources exist independently |
| Silence (unique type) | false | false | New application ignored if already present |

### Unit-Side Interface

```
# Buff management in Unit.gd

var buffs: Array[BuffEffect] = []

func add_buff(buff: BuffEffect) -> void:
  # Stacking logic
  var existing = get_buff(buff.buff_id)
  if existing:
    if not buff.stackable:
      if buff.refresh_on_reapply:
        existing.duration = existing.max_duration
      return  # Do not stack
    else:
      var count = count_buff_stacks(buff.buff_id)
      if buff.max_stacks > 0 and count >= buff.max_stacks:
        return  # Cap reached
  buffs.append(buff)
  _apply_immediate(buff)  # Apply immediately

func remove_buff(buff: BuffEffect) -> void:
  _unapply(buff)
  buffs.erase(buff)

func get_buff(id: String) -> BuffEffect:
  for b in buffs:
    if b.buff_id == id:
      return b
  return null

func count_buff_stacks(id: String) -> int:
  var count = 0
  for b in buffs:
    if b.buff_id == id:
      count += 1
  return count

func has_buff(id: String) -> bool:
  return get_buff(id) != null
```

### TurnManager Integration

```
# Unit Turn Start
func on_unit_turn_start(unit: Unit):
  for buff in unit.buffs.duplicate():  # duplicate to prevent modification during iteration
    if buff.trigger == "turn_start":
      _execute_buff_effect(unit, buff)  # DOT damage, regeneration, etc.

# Unit Turn End
func on_unit_turn_end(unit: Unit):
  for buff in unit.buffs.duplicate():
    if buff.duration > 0:
      buff.duration -= 1
    if buff.duration == 0:
      unit.remove_buff(buff)
```

### Serialization - Multiplayer Sync

```json
{
  "unit_id": "player_warrior_01",
  "buffs": [
    {
      "buff_id": "burn",
      "duration": 2,
      "max_duration": 3,
      "effect_type": "dot",
      "value": 10,
      "trigger": "turn_start",
      "source_unit_id": "enemy_shaman_01",
      "stackable": false,
      "refresh_on_reapply": true
    }
  ]
}
```

---

## Consequences and Constraints

### Positive Consequences

- Buff logic is cohesive; adding new Buff types only requires extending `effect_type` without changing iteration code
- Resources can be preset as templates in the editor (e.g. `burn_template.tres`), facilitating data-driven design
- Type safety reduces runtime errors

### Negative Consequences

- Compared to the Dictionary approach, requires defining a Resource class (slightly more initial code)
- Querying by buff_id requires iterating the Array (O(n)), but n <= 10 is entirely acceptable

### Constraints

- All Buff data must be carried through `BuffEffect` Resources; raw Dictionaries are prohibited
- Gauge is not a Buff -- Gauges have their own independent data structure and trigger logic, and do not go through the Buff system
- Terrain Debuffs (burn/poison) create standard `BuffEffect` instances when applied, following the same pipeline as skill-applied Buffs

---

*Related documents: [[01-Game-Design/Core-Systems/turn-system]] · [[01-Game-Design/Characters/talent-tree]]*
