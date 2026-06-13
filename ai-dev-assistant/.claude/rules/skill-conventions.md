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
- `model` — **`inherit` or `opus` only** (both 1M). A skill's `model:` is an inline current-turn override with no context isolation, so a sub-1M pin (`haiku`/`sonnet`) overflows when the skill activates from a large session (BUG-1; validator rule **S14**). For cheap deterministic work, delegate to a `scripts/*.sh` or a Task-dispatched `agents/*.md` instead — never pin `haiku`/`sonnet` on a skill.
- `user-invocable: false` — for internal skills only called by other skills/agents
- `allowed-tools` — restrict tool access when active
- `disallowed-tools` — kebab-case on skills (the agent form is camelCase `disallowedTools`; not interchangeable — validator rules **S15**/**A04**). Use on read-only readers, e.g. `disallowed-tools: Write, Edit`.

## Body Rules
- Imperative voice — instructions for Claude, not documentation
- Under 500 lines
- Use progressive disclosure — reference files for details
- Current state only — no historical narratives
- No v2.x backward compatibility warnings (migration is handled by task-folder-migrator)
