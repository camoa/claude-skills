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

## Online Dev-Guides — Proactive Usage
**ALWAYS consult dev-guides before making Drupal development decisions** unless the relevant guide was already loaded in this session.
- Use the `dev-guides-navigator` skill for topic discovery, caching, and disambiguation
- Do NOT fetch `llms.txt` or dev-guides URLs directly — invoke the navigator skill instead
- The `guide-integrator` and `guide-loader` skills delegate to the navigator
- **Phase 1 (Research):** Load guides for the task's Drupal domain (forms, entities, plugins, etc.)
- **Phase 2 (Design):** Load guides for architecture decisions (services, routing, caching, config)
- **Phase 3 (Implementation):** Load guides for security, SDC, JS patterns before writing code
- If a guide was loaded earlier in the session, do not re-fetch — use the cached content

## General
- Current state only — no historical narratives
- Replace outdated content, don't keep alongside new
- Every edit is a chance to prune irrelevant content
- Reference files instead of reproducing content
