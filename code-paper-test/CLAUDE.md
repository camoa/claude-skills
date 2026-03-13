# Code Paper Test - Plugin Conventions

## What This Plugin Tests

- **Code** — PHP, JavaScript, Python, etc. (trace execution with concrete values)
- **Skills** — SKILL.md files (trace instructions through Claude)
- **Commands** — Command .md files (verify orchestration logic)
- **Agents** — Agent definitions (verify spawn configs, coordination)
- **Configs** — YAML, JSON, services files (verify values match code expectations)

## Skills
- Frontmatter must include: name, description, version, model, allowed-tools, user-invocable
- Description starts with "Use when..." and includes multiple trigger phrases covering synonyms
- Description must be pushy — include "Use proactively" and "MUST" enforcement where appropriate
- Body uses imperative voice — instructions, not documentation
- Under 500 lines per SKILL.md

## Commands
- Frontmatter must include: description, allowed-tools
- Use `argument-hint:` when command accepts arguments
- Agent team commands orchestrate AI debate workflows rather than wrapping scripts
- Agent spawns should include `maxTurns` (cost control) and `isolation: worktree` (independence)

## General
- Reference files instead of reproducing content
- Current state only — no historical narratives
- Language-agnostic examples preferred (PHP shown as primary)
- Skill/config testing uses instruction tracing, not code tracing — see `references/skill-and-config-testing.md`
