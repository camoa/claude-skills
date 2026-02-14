# Command Conventions

## Required Frontmatter
- `description` -- clear, concise action description
- `allowed-tools` -- minimum needed tools

## Optional Frontmatter
- `argument-hint` -- when command accepts arguments
- `model` -- override model for this command

## Body
- Step-by-step workflow with numbered steps
- Use AskUserQuestion for interactive choices
- Include error handling for missing prerequisites
- Reference skills via Skill tool, not inline duplication
