# Mage Talent Tree Design Brief

> Status: **DRAFT** — Awaiting Human + Design Agent collaboration
> Prerequisite: talent-tree-design.md (Swordsman reference), class-system.md (Mage spec)
> Target: P2-TALENT deliverable for M13

---

## 1. Class Identity Recap

| Field | Value |
|-------|-------|
| Core Role | Three elemental schools of magic, high damage + magical effects |
| Weapon | Magic weapons (staves/foci) |
| Stat Profile | High MAG; low HP/DEF/MOV |
| Starting Skills | Fireball, Frost |

---

## 3. Gauge System: Mana Resonance

Shared gauge concept across all Mage advancement paths, with element-specific behavior:

**Core Gauge: Mana Resonance**
- Type: Elemental attunement (0-100)
- Gain: +15 when casting a spell of matching element; +5 for any spell
- Decay: -10 per turn; casting off-element spell resets to 0

---

## 5. Shared Early Zone (Lv 1-10)

Budget: ~17 cost

Suggested progression:
- Lv 1: Arcane Initiation (start node, unlock Fireball)
- Lv 2-4: Basic passives (MAG boost, cast range, mana efficiency)
- Lv 5-7: Frost upgrade, elemental affinity preview (taste each element)
- Lv 8-9: Mana Resonance gauge introduction
- Lv 10: Advancement node — Fire / Wind / Lightning / Water (mutually exclusive)

---

## 6. Action Economy Integration

| Advancement | Typical Turn Pattern | Primary Resources |
|-------------|---------------------|-------------------|
| Early Mage | Move (position) → Standard (Fireball/Frost) | Standard primary |

---

## 8. Design Decisions Needing Human Input

1. **Mana Resonance numbers**: Gain/decay rates; should off-element casting reset completely?
2. **Cross-element builds**: Are they intended to be viable or intentionally suboptimal?

---

## 9. JSON Template Reference

Same schema as Swordsman/Archer:

```json
{
  "class_id": "mg_[tree_name]",
  "class_name": "法师 · [tree variant name]",
  "nodes": [
    {
      "id": "mg_start",
      "name": "奥术入门",
      "type": "trait",
      "cost": 1,
      "x": 0,
      "y": 0,
      "desc": "解锁初始技能「火球术」。激活法器专精。",
      "tags": "magic,start",
      "exclusive": "",
      "requires": ""
    }
  ],
  "edges": []
}
```

---

*Created: 2026-03-12 | Main Agent (Claude Code) | DRAFT — awaiting topology decision + Design Agent detail pass*
