---
paths:
  - "commands/**"
---

# Command Conventions

## Required Frontmatter
- `description` — what the command does, concise
- `allowed-tools` — restrict to minimum needed

## Optional Frontmatter
- `argument-hint` — shown during autocomplete (e.g., `<task-name>`)

## Body Rules
- Clear instructions for what Claude should do when command is invoked
- Support `$ARGUMENTS` for user-provided arguments
- Reference skills/agents for complex workflows rather than inlining logic
