# Drupal HTMX Plugin

[![Listed on ClaudePluginHub](https://www.claudepluginhub.com/badge/camoa-drupal-htmx-drupal-htmx)](https://www.claudepluginhub.com/plugins/camoa-drupal-htmx-drupal-htmx?ref=badge)

HTMX development guidance and AJAX-to-HTMX migration tools for Drupal 11.3+.

> **Not using Claude Code?** See the marketplace [PORTABILITY.md](../PORTABILITY.md) — skills work in Cursor, Codex CLI, Copilot, Gemini CLI, Cline, and more.

## Features

- **Analyze** existing AJAX patterns for migration opportunities
- **Migrate** AJAX to HTMX with guided step-by-step instructions
- **Recommend** HTMX patterns for new development
- **Validate** HTMX implementations against best practices

## Installation

```bash
/plugin marketplace add camoa/claude-skills
/plugin install drupal-htmx@camoa-skills
```

## Commands

| Command | Purpose |
|---------|---------|
| `/htmx [path]` | Show status and suggest next actions |
| `/htmx-analyze <path>` | Analyze AJAX patterns for migration |
| `/htmx-migrate <file>` | Guided AJAX to HTMX migration |
| `/htmx-pattern <use-case>` | Get pattern recommendation |
| `/htmx-validate <path>` | Validate HTMX implementation |

## Agents

| Agent | Model | Features |
|-------|-------|----------|
| `ajax-analyzer` | sonnet | Read-only (`tools: Read, Grep, Glob`), scans AJAX patterns |
| `htmx-recommender` | sonnet | Read-only (`tools: Read, Glob`), recommends patterns |
| `htmx-validator` | sonnet | Read-only (`tools: Read, Grep, Glob`), validates implementations |

## Skill

The `htmx-development` skill auto-activates when discussing:
- HTMX implementation in Drupal
- AJAX to HTMX migration
- Dynamic forms and content
- Dependent dropdowns, infinite scroll, etc.

## Quick Start

### Analyze Existing AJAX

```bash
/htmx-analyze modules/custom/my_module
```

### Get Pattern Recommendation

```bash
/htmx-pattern dependent dropdown
```

### More Examples

```bash
/drupal-htmx:htmx-analyze web/modules/custom/my_module
/drupal-htmx:htmx-migrate web/modules/custom/my_module/src/Form/MyForm.php
/drupal-htmx:htmx-pattern dependent dropdown
/drupal-htmx:htmx-validate web/modules/custom/my_module
```

### Migrate Specific Pattern

```bash
/htmx-migrate modules/custom/my_module/src/Form/MyForm.php
```

### Validate Implementation

```bash
/htmx-validate modules/custom/my_module
```

## Scope

All agents and commands focus on **custom modules only**. They will not scan or modify contrib or core modules unless explicitly requested.

## Tips

### Deciding HTMX vs AJAX with `/branch`

The core decision this plugin supports is HTMX-vs-AJAX. When a migration could
go either way, use Claude Code's `/branch` to fork the session at the decision
point and try each path against the *same* loaded context — implement the HTMX
version in one branch, keep the AJAX version in another, then compare. The
original session is unchanged and remains in the session picker.

### Effort-adaptive depth

The `htmx-development` skill scales its work to the active effort level
(`${CLAUDE_EFFORT}`): `low` emits HTMX scaffolding and stops; `medium` and above
also run the validation checklist inline; `high`/`xhigh`/`max` additionally
cross-reference the Drupal forms and JS-development dev-guides.

### Skill visibility (`skillOverrides`)

The `htmx-development` skill triggers proactively on common terms like "AJAX"
and "Drupal". On a project where that is noise, use the `skillOverrides`
setting in `.claude/settings.json` (Claude Code v2.1.129+) to dial it back
without editing the plugin:

- `"htmx-development": "user-invocable-only"` — suppress proactive
  auto-invocation, keep the skill loadable on request.
- `"htmx-development": "name-only"` — keep it discoverable for cross-skill
  delegation but drop the aggressive proactive triggers.
- `"htmx-development": "off"` — hide it entirely.

## References

The plugin includes condensed reference guides from comprehensive source documentation:

- `quick-reference.md` - Command equivalents, method tables
- `htmx-implementation.md` - Htmx class API, detection, JS integration
- `migration-patterns.md` - 7 detailed migration patterns
- `ajax-reference.md` - AJAX commands reference for understanding existing code

Online dev-guides from https://camoa.github.io/dev-guides/ provide supplementary Drupal domain context (AJAX architecture, forms, routing, render API, JS behaviors).

## Requirements

- Drupal 11.3+ (native HTMX support)
- Claude Code

## License

MIT
