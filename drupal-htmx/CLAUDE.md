# Drupal HTMX - Plugin Conventions

## Agents
- Frontmatter must include: name, description, version, model
- All agents are read-only analyzers — use `disallowedTools` to enforce
- Description starts with action phrases for auto-delegation

## Skills
- Frontmatter must include: name, description, version
- Add `model:` matched to complexity
- Body uses imperative voice — instructions, not documentation
- Under 500 lines per SKILL.md

## Commands
- Frontmatter must include: description, allowed-tools
- Use `argument-hint:` when command accepts arguments
- Restrict `allowed-tools` to minimum needed

## Online Dev-Guides
For Drupal domain context when analyzing or validating HTMX patterns, fetch the guide index:
- **Index:** `https://camoa.github.io/dev-guides/llms.txt`
- WebFetch the index to discover available topics, then fetch specific topic pages
- Likely relevant topics: forms, routing, js-development, render-api

## General
- Drupal 11.3+ HTMX patterns only — no legacy AJAX guidance
- Reference files instead of reproducing content
- Current state only — no historical narratives
