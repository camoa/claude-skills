---
globs: agents/**
---

# Agent Conventions

## Required Frontmatter
- `name` — lowercase, hyphens only
- `description` — includes delegation triggers
- `version` — semver
- `model` — haiku, sonnet, or opus

## Optional Frontmatter
- `memory` — project for brand pattern learning
- `tools` — comma-separated allowlist
- `disallowedTools` — comma-separated denylist
- `hooks` — scoped lifecycle hooks

## Body
- Imperative voice: "Analyze...", "Extract...", "Return..."
- Read-only agents must not modify files
- Return findings to caller, don't write directly
