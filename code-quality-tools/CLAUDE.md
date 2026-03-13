# Code Quality Tools - Plugin Conventions

## Capabilities

- **Automated audits** — 22 operations across Drupal (10 security layers) and Next.js (7 security layers)
- **Code review** — Rubric-scored assessment with quality gate (/50 scale, PASS/FAIL)
- **Security debate** — 3-agent team: Defender + Red Team + Compliance (isolated worktrees)
- **Architecture debate** — 3-agent team: Pragmatist + Purist + Maintainer (isolated worktrees)
- **Cross-audit synthesis** — Correlate findings across tools into prioritized action plan

## Skills
- Frontmatter must include: name, description, version, model, allowed-tools, user-invocable
- Description starts with "Use when..." and includes multiple trigger phrases covering synonyms
- Description must be pushy — include "Use proactively" and enforcement where appropriate
- Body uses imperative voice — instructions, not documentation
- Under 500 lines per SKILL.md

## Commands
- Frontmatter must include: description, allowed-tools
- Use `argument-hint:` when command accepts arguments
- Restrict `allowed-tools` to minimum needed
- Commands wrap existing scripts — no logic duplication
- Agent team commands include `maxTurns` (cost control) and `isolation: worktree` (independence)
- Agent team commands orchestrate debate workflows with quality gate enforcement

## Online Dev-Guides
For Drupal-specific patterns when explaining violations or suggesting fixes, fetch the guide index:
- **Index:** `https://camoa.github.io/dev-guides/llms.txt`
- WebFetch the index to discover available topics, then fetch specific topic pages
- Likely relevant topics: solid-principles, dry-principles, security, testing, tdd, js-development, github-actions

## General
- Reference files instead of reproducing content
- Current state only — no historical narratives
- Scripts handle Drupal (DDEV) and Next.js (npm) detection
