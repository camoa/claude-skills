---
globs: commands/**
---

# Command Conventions

## Required Frontmatter
- `description` — clear action description with literal trigger phrases
- `allowed-tools` — minimum the backing worker skill needs

## Optional Frontmatter
- `argument-hint` — when the command accepts arguments

## Body
- Thin entry point: validate arguments, invoke the backing worker skill via the Skill
  tool, present the result. No procedure logic in the command body.
- Include error handling for missing prerequisites — point the contributor at the
  gap, never refuse to run (the arc is detect-driven, not a forced sequence).
