---
globs: skills/**
---

# Skill Conventions

## Required Frontmatter
- `name` — lowercase, hyphens only
- `description` — starts with "Use when...", includes literal trigger phrases
- `version` — semver

## Optional Frontmatter
- `model` — use `inherit` on inline skills. A skill's `model:` is a current-turn
  override with no context isolation, so pinning a sub-1M tier (`sonnet`/`haiku`)
  overflows when the skill activates from a large conversation (validator S14). Pin a
  specific tier only on a Task-dispatched agent (fresh context), never on a SKILL.md.
- `disallowed-tools` (kebab-case on skills — distinct from the agent `disallowedTools`
  camelCase field) — declare `Edit, Write` on read-only worker skills that only dispatch
  agents, run gate commands, or read status and never mutate contribution files.
- `user-invocable: false` — umbrella + the six worker skills (invoked by command or
  routed to by the umbrella, never from the `/` menu)

## Body
- Imperative voice — instructions for Claude, not documentation
- Under 500 lines per SKILL.md; push detail into `references/`
- Cite dev-guides by slug; never embed guide content or fetch dev-guides URLs directly
- Every gate passes on a captured artifact, never on an assertion
