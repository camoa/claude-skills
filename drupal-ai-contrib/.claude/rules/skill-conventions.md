---
globs: skills/**
---

# Skill Conventions

## Required Frontmatter
- `name` — lowercase, hyphens only
- `description` — starts with "Use when...", includes literal trigger phrases
- `version` — semver

## Optional Frontmatter
- `model` — matched to complexity (sonnet for balanced tasks)
- `user-invocable: false` — umbrella + the six worker skills (invoked by command or
  routed to by the umbrella, never from the `/` menu)

## Body
- Imperative voice — instructions for Claude, not documentation
- Under 500 lines per SKILL.md; push detail into `references/`
- Cite dev-guides by slug; never embed guide content or fetch dev-guides URLs directly
- Every gate passes on a captured artifact, never on an assertion
