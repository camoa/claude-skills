---
paths:
  - "commands/**"
---

# Command Conventions

## Required Frontmatter
- `description` — clear, concise action description
- `allowed-tools` — minimum needed tools

## Optional Frontmatter
- `argument-hint` — when command accepts arguments

## Body
- Step-by-step workflow with numbered steps
- Include error handling for missing prerequisites
- Agent team commands contain team orchestration logic
