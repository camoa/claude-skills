---
paths:
  - "agents/**"
---

# Agent Conventions

## Required Frontmatter
- `name` — kebab-case, matches filename
- `description` — starts with "Use when..." for auto-delegation
- `capabilities` — array of capability keywords
- `version` — semantic version
- `model` — haiku (lookup), sonnet (balanced), opus (complex reasoning)

## Optional Frontmatter
- `memory: project` — for agents that learn across sessions
- `disallowedTools` — restrict tools (e.g., `Edit, Write` for read-only agents)
- `skills` — preload skills into agent context
- `hooks` — scoped hooks that run only when this agent is active

## Body Structure
1. Purpose section — what the agent does
2. When to Invoke — trigger conditions
3. Process — numbered steps
4. Output Format — expected output structure
5. Human Control Points — where developer decides
