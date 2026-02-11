# Code Quality Tools - Plugin Conventions

## Skills
- Frontmatter must include: name, description, version, model
- Description starts with "Use when..." and includes trigger phrases
- Body uses imperative voice — instructions, not documentation
- Under 500 lines per SKILL.md

## Commands
- Frontmatter must include: description, allowed-tools
- Use `argument-hint:` when command accepts arguments
- Restrict `allowed-tools` to minimum needed
- Commands wrap existing scripts — no logic duplication
- Agent team commands orchestrate debate workflows — these are a new category alongside script wrappers

## General
- Reference files instead of reproducing content
- Current state only — no historical narratives
- Scripts handle Drupal (DDEV) and Next.js (npm) detection
