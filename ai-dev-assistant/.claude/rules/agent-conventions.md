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

## Agent Frontmatter Limitations
- `hooks`, `mcpServers`, and `permissionMode` in agent frontmatter are **not supported** when agents are invoked as sub-agents via the Agent SDK or spawned programmatically. These fields only take effect when the agent runs as the top-level session.
- `architecture-validator` currently uses `hooks: PreToolUse` in frontmatter — this works for interactive sessions but will be silently ignored if the agent is ever invoked as a sub-agent. The `disallowedTools: Edit, Write` field remains the reliable write-block mechanism.

## Body Structure
1. Purpose section — what the agent does
2. When to Invoke — trigger conditions
3. Process — numbered steps
4. Output Format — expected output structure
5. Human Control Points — where developer decides
