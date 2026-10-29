# Archer Talent Tree Design Brief

> Status: **DRAFT** — Awaiting Human + Design Agent collaboration
> Prerequisite: talent-tree-design.md (Swordsman reference), class-system.md (Archer spec)
> Target: P2-TALENT deliverable for M13

---

## 1. Class Identity Recap

| Field | Value |
|-------|-------|
| Core Role | Pure ranged physical damage dealer |
| Weapon | Bows (cannot melee by default) |
| Stat Profile | High CRIT, decent SPD/EVA; low DEF; average accuracy |
| Starting Skills | Shot, Aim (boost next attack accuracy + CRIT) |
| Advancement | **Sniper** (ultra-long range) vs **Elven Archer** (melee-capable + enchanted arrows) |

---

## 2. Bipolar Design

### Left Pole: Sniper — Stationary Precision

**Core Gauge: Focus**
- Type: Energy (0-100)
- Gain: +15 per turn spent without moving; +10 on crit; +5 on hit
- Decay: Movement resets Focus to 0; using Move Action skill resets to 0
- Threshold Effects:
  - 0-29: None
  - 30-59 "Steady Aim": HIT +10, CRIT +5
  - 60-89 "Dead Eye": HIT +10, CRIT +5, Range +1
  - 90-100 "Perfect Shot": All bonuses + unlock ultimate skill

**Faction 1: Overwatch Fortress Style**
- Tactical Role: Maximum range, area denial, reaction-based
- Core Mechanics: Extended range, Overwatch reaction (shoot enemies entering range), suppression debuff
- Action Pattern: Swift (set Overwatch) → Standard (long-range shot) → No movement
- Terminal Ability (Lv 20): Bullet Time — Reaction: shoot all enemies that move within range this turn

**Faction 2: Penetration Marksman Style**
- Tactical Role: High single-target burst, armor piercing
- Core Mechanics: Charged shots (skip turn for 2x damage next turn), armor penetration stacking, crit overflow → bleed
- Action Pattern: Swift (charge) → next turn Standard (empowered shot)
- Terminal Ability (Lv 20): Annihilation Arrow — Ignores 100% DEF, if kills, Focus fully refunded

### Right Pole: Elven Archer — Mobile Hybrid

**Core Gauge: Wind Essence**
- Type: Flow gauge (0-60)
- Gain: +8 on dodge; +5 per move action; +3 per ranged hit
- Spend: Consumed by enchanted arrow skills and evasion abilities
- Threshold: No passive thresholds; purely a spending resource
- Special: At 60, next dodge grants free Move Action (repositioning)

**Faction 3: Enchanted Arrow Style**
- Tactical Role: Debuff applicator, elemental variety
- Core Mechanics: Enchant arrows with elements (burn/slow/poison), multi-hit weaker shots, debuff amplification
- Action Pattern: Swift (enchant) → Standard (enchanted shot applying debuff) → Move (kite)
- Terminal Ability (Lv 20): Storm of Arrows — 3-hit area attack, each hit applies current enchantment

**Faction 4: Shadow Hunter Style**
- Tactical Role: Melee/ranged switch, assassination
- Core Mechanics: Melee unlocked, backstab bonus, stealth approach, close-range burst
- Action Pattern: Move Action (stealth approach) → Standard (backstab at melee range) → disengage
- Terminal Ability (Lv 20): Phantom Strike — Teleport to target, melee attack at 2.0x power, stealth after kill

### Central Axis: Wind Arrow Mastery

- Provides universal mobility buffs, accuracy/crit universals
- Bridge nodes connecting Sniper and Elven Archer paths
- Key nodes: Arrow Mastery (accuracy), Wind Step (MOV+1 for 1 turn after ranged kill), Keen Eye (VIS+1)

---

## 3. Shared Early Zone (Lv 1-10)

Budget: ~17 cost (matching Swordsman pattern)

Suggested progression:
- Lv 1: Archer Initiation (start node, unlock Shot)
- Lv 2-4: Basic passives (accuracy, crit, range familiarity)
- Lv 5-7: Aim upgrade, first active skill unlock
- Lv 8-9: Pre-advancement preparation (gauge introduction nodes)
- Lv 10: Advancement node — Sniper OR Elven Archer (mutually exclusive)

---

## 4. Action Economy Integration

| Advancement | Typical Turn Pattern | Primary Resources |
|-------------|---------------------|-------------------|
| Sniper | Swift (Overwatch/Charge) → Standard (precision shot) → NO move | Swift + Standard |
| Elven Archer | Swift (enchant) → Standard (shot) → Move Action (reposition) | All three |
| Early Archer | Move → Standard (Shot) → Aim if no move | Standard primary |

---

## 5. Design Decisions Needing Human Input

1. **Focus gauge numbers**: Are gain/decay rates appropriate? Should Focus persist across turns?
2. **Wind Essence gauge**: Cap 60 vs 100? Spending costs per enchant?
3. **Overwatch as Reaction**: Fits the action economy design but is complex — confirm scope for M13?
4. **Stealth mechanic**: Shadow Hunter uses stealth — does this require a new system or is it a buff?
5. **Melee unlock for Elven Archer**: At what advancement level? What weapon does melee use?

---

## 6. JSON Template Reference

Same schema as Swordsman (see `data/talent-tree/sw_starburst.json`):

```json
{
  "class_id": "ar_[tree_name]",
  "class_name": "弓箭手 · [tree variant name]",
  "nodes": [
    {
      "id": "ar_start",
      "name": "箭术入门",
      "type": "trait",
      "cost": 1,
      "x": 0,
      "y": 0,
      "desc": "解锁初始技能「射击」。激活弓类武器专精。",
      "tags": "bow,start",
      "exclusive": "",
      "requires": ""
    }
  ],
  "edges": [
    ["ar_start", "ar_l2_l"],
    ["ar_start", "ar_l2_m"],
    ["ar_start", "ar_l2_r"]
  ]
}
```

---

*Created: 2026-03-12 | Main Agent (Claude Code) | DRAFT — awaiting Design Agent detail pass*
