# Skill Conventions

## Required Frontmatter
- `name` -- lowercase, hyphens only
- `description` -- starts with "Use when...", includes trigger phrases
- `version` -- semver

## Optional Frontmatter
- `model` -- sonnet for routing/analysis, opus for generation
- `user-invocable` -- false for skills only called by commands
- `context` -- fork for heavy operations

## Body
- Imperative voice -- instructions, not documentation
- Under 500 lines per SKILL.md
- Reference supporting files instead of inlining large content
- Reference external guides via WebFetch (discovery-first via llms.txt)
