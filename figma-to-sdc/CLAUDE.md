# Figma to SDC - Plugin Conventions

## Skills
- Frontmatter must include: name, description, version, model
- Description starts with action phrase for auto-delegation
- Body uses imperative voice — instructions, not documentation
- Under 500 lines per SKILL.md

## Commands
- Frontmatter must include: description, allowed-tools
- Use `argument-hint:` when command accepts arguments
- Restrict `allowed-tools` to minimum needed

## General
- Reference files instead of reproducing content
- Current state only — no historical narratives
- Figma MCP server required for extraction — validate availability early
