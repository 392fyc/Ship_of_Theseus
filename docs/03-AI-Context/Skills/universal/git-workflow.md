# Git Workflow Rules

## Branch Naming
Format: {agent}/{task-name}
Examples: cursor/pkg-e-battle-ui, codex/batch-json-gen, ag/parallel-task-xxx

## Personal Work
No PR required. Direct merge to feature branch after completion.

## Sub Agent Isolation
- Each Sub Agent task creates an independent branch or worktree
- Different Agents NEVER work on the same branch simultaneously
- Sub Agent notifies Main Agent on completion
- Main Agent decides merge timing

## Conflict Resolution Protocol
1. Use an independent, neutral session (NOT the conflicting agents)
2. Pull both branches into the neutral session
3. Perform neutral merge
4. Review the merge result
5. Merge to target branch
6. Clean up worktrees

## Branch Structure
```
develop
  +-- feature/phase1-impl
        +-- cursor/pkg-e-battle-ui
        +-- codex/batch-json-gen
        +-- ag/parallel-task-xxx
  +-- fix/conflict-resolution-xxx
```
