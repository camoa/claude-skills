# Command Conventions

## Required Frontmatter
- `description` — clear, concise action description
- `allowed-tools` — minimum needed tools

## Optional Frontmatter
- `argument-hint` — when command accepts arguments

## Body
- Step-by-step workflow with numbered steps
- Include error handling for missing prerequisites
- Wrap existing scripts — do not duplicate logic
- Agent team commands orchestrate AI debate workflows rather than wrapping scripts. They follow the same frontmatter conventions but contain team orchestration logic instead of script references.
