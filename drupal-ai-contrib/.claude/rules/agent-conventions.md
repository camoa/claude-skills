---
globs: agents/**
---

# Agent Conventions

## Required Frontmatter
- `name` — lowercase, hyphens only
- `description` — includes delegation triggers ("Use proactively when...")
- `version` — semver
- `model` — haiku, sonnet, or opus matched to task complexity

## Tool Restriction
- The agent tool allowlist field is `tools` — NOT `allowed-tools` (silently ignored
  on agents, leaving the agent with all tools).
- All three agents are read-only — also declare `disallowedTools: Edit, Write`.

## Body
- Imperative voice: "Verify...", "Review...", "Fetch...".
- Fresh context, no session narrative — an agent must not inherit the builder's claims.
- Return findings to the caller as a structured verdict; never modify files.
