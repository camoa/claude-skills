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
- `tools` — comma-separated allowlist
- `disallowedTools` — comma-separated denylist

## Body
- Imperative voice: "Analyze...", "Scan...", "Validate..."
- Read-only agents must not modify files
- Return findings to caller, don't write directly
