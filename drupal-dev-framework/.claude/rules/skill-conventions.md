---
paths:
  - "skills/**"
---

# Skill Conventions

## Required Frontmatter
- `name` — kebab-case, matches directory name
- `description` — starts with "Use when...", max 1024 chars, third person
- `version` — semantic version

## Optional Frontmatter
- `model` — haiku (lookup/loading), sonnet (balanced), opus (complex design)
- `user-invocable: false` — for internal skills only called by other skills/agents
- `allowed-tools` — restrict tool access when active

## Body Rules
- Imperative voice — instructions for Claude, not documentation
- Under 500 lines
- Use progressive disclosure — reference files for details
- Current state only — no historical narratives
- No v2.x backward compatibility warnings (migration is handled by task-folder-migrator)
