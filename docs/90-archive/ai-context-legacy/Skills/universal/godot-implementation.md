# GDScript Implementation Standards

## Naming Conventions
- Class names: PascalCase
- Variables and functions: snake_case
- Constants: UPPER_SNAKE_CASE
- Signals: past tense (signal damage_dealt, signal unit_killed)

## Architecture Pattern
- GameAction pattern: all operations encapsulated as serializable Actions
- Data-driven: game content = JSON files, code handles logic only
- NEVER hardcode numeric values in code, must read from JSON

## Known Error Patterns
- class_name conflicts with autoload: remove class_name from autoload scripts
- Variant type inference unstable: always declare variable types explicitly
- Reserved words: use str_attr/def_attr as variable names, JSON keys stay "STR"/"DEF"
- DamageCalculator: only calculate and return values, never call take_damage()
- BattleManager API: initialize_battle() then start_battle(), do not rely on _ready()

## Context7 Rule
When uncertain about Godot 4.6 API usage, query official docs via Context7. Never guess based on training data.
