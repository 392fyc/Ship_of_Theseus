# Batch Data Generation Standards

> ⚠️ **DEPRECATED** — This file documents an early pure-JSON-file generation flow and is no longer a valid standard (marked 2026-08-03; registered as entry D-5 in `02-Development/doc-drift-ledger.md`). Its attribute enumeration predates R2.1: the current model is nine attributes — seven growth attributes (HP / STR / MAG / DEX / SPD / DEF / RES) plus two fixed ones (LCK / MOV), with VIS removed — so the names below (`phys_atk`, `mag_atk`, `def_attr`, `mag_def`, `evade`, and the `"CRT" / "HIT" / "EVA"` JSON keys) match no current data file. Batch data generation now follows the design library interfaces rather than this document. The per-agent skill-document directory this file sits in is itself obsolete: since 2026-06-16 the work is carried out by subagents inside Claude Code. Do not modify or follow this file; for the attribute model use `01-Game-Design/rules-catalog.md` (R2.1).

## JSON Schema
All game data JSON must follow the schemas defined in data-architecture.md in the KB.

## Attribute Naming (FE Style)
- hp, phys_atk, mag_atk, def_attr, mag_def, speed, move, crit, hit, evade
- JSON keys use uppercase: "HP", "STR", "MAG", "DEF", "RES", "SPD", "MOV", "CRT", "HIT", "EVA"

## Growth Rates Format
Each class JSON must include growth_rates object with same attribute keys, values 0.0-1.0.

## Validation Requirements
- Validate generated JSON against schema before output
- Ensure all required fields are present
- Cross-reference with existing data files for consistency
