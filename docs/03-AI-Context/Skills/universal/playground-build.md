# Playground Build Standard

## Purpose
Create independent visual proposal scenes for human review before applying to main scenes.

## Rules
- Each Playground is an independent scene file, never modifies main scenes
- Present A/B/C proposals with key feature annotations for comparison
- Label each proposal clearly with distinguishing characteristics
- Playground retention or cleanup is decided by human controller

## File Naming
playground_{feature}_{variant}.tscn
Example: playground_battle_ui_a.tscn, playground_terrain_b.tscn

## Workflow
1. Create independent Playground scene files
2. Implement 2-3 visual proposals per feature
3. Annotate key differences between proposals
4. Present to human controller for selection
5. Only apply selected proposal to main scene after approval
