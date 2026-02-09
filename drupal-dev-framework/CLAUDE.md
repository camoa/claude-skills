# Drupal Dev Framework - Plugin Conventions

## Agents
- Frontmatter must include: name, description, capabilities, version, model
- Description starts with "Use when..." for auto-delegation
- Read-only agents must have `disallowedTools: Edit, Write`
- Agents that learn across sessions should have `memory: project`

## Skills
- Frontmatter must include: name, description, version
- Add `model:` matched to complexity (haiku for lookup, sonnet for balanced, opus for complex)
- Internal-only skills must have `user-invocable: false`
- Body uses imperative voice — instructions for Claude, not documentation
- Under 500 lines per SKILL.md

## Commands
- Frontmatter must include: description, allowed-tools
- Use `argument-hint:` for discoverability
- Restrict `allowed-tools` to minimum needed

## General
- Current state only — no historical narratives
- Replace outdated content, don't keep alongside new
- Every edit is a chance to prune irrelevant content
- Reference files instead of reproducing content
