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

## Online Dev-Guides
For Drupal-specific patterns when explaining violations or suggesting fixes, fetch the guide index:
- **Index:** `https://camoa.github.io/dev-guides/llms.txt`
- WebFetch the index to discover available topics, then fetch specific topic pages
- Likely relevant topics: solid-principles, dry-principles, security, testing, tdd, js-development, github-actions

## General
- Reference files instead of reproducing content
- Current state only — no historical narratives
- Scripts handle Drupal (DDEV) and Next.js (npm) detection
