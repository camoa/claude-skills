# Brand Content Design - Plugin Conventions

## Agents
- Frontmatter must include: name, description, version, model
- Description starts with action phrases for auto-delegation
- Read-only agents must have `disallowedTools: Edit, Write, Bash`
- Agents that learn brand patterns across sessions should have `memory: project`

## Skills
- Frontmatter must include: name, description, version
- Add `model:` matched to complexity (sonnet for routing, opus for creative/artistic)
- Internal skills called only by commands should have `user-invocable: false`
- Body uses imperative voice — instructions for Claude, not documentation
- Under 500 lines per SKILL.md

## Commands
- Frontmatter must include: description, allowed-tools
- Use `argument-hint:` when command accepts arguments
- Restrict `allowed-tools` to minimum needed
- Interactive commands use AskUserQuestion for user input

## General
- Accessibility (WCAG AA) is mandatory — never skip contrast validation
- Three-layer philosophy: brand → content type → template
- Current state only — no historical narratives
- Reference files instead of reproducing content
