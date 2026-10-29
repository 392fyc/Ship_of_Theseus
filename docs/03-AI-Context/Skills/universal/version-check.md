# Version Check Rule

## Scope
All agents in the SOT ecosystem: Claude Code, Cursor, Codex CLI, AntiGravity.

## Rule
Any operation involving version numbers must follow this sequence:
1. WebSearch for the latest version first
2. Cross-verify with at least 2 independent sources or the official page
3. Only then may the version be referenced in subsequent work

## Applies To
- AI model versions (Claude, GPT, Gemini, etc.)
- Game engine versions (Godot, Unity, Unreal)
- SDK and library versions
- Plugin and addon versions

## Known Current Versions (as of 2026-03)
- Claude: Opus 4.6, Sonnet 4.6
- OpenAI: GPT-5.3-Codex
- Google: Gemini 3.1 Pro
- Godot: 4.6

## Anti-Pattern
NEVER rely on training data to determine version numbers. Search results from a single source also require cross-verification.
