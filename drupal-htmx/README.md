# Drupal HTMX Plugin

HTMX development guidance and AJAX-to-HTMX migration tools for Drupal 11.3+.

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
| `ajax-analyzer` | sonnet | Read-only (`disallowedTools: Edit, Write`), scans AJAX patterns |
| `htmx-recommender` | sonnet | Read-only (`disallowedTools: Edit, Write, Bash`), recommends patterns |
| `htmx-validator` | sonnet | Read-only (`disallowedTools: Edit, Write`), validates implementations |

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

## References

The plugin includes condensed reference guides from comprehensive source documentation:

- `quick-reference.md` - Command equivalents, method tables
- `htmx-implementation.md` - Htmx class API, detection, JS integration
- `migration-patterns.md` - 7 detailed migration patterns
- `ajax-reference.md` - AJAX commands reference for understanding existing code

## Requirements

- Drupal 11.3+ (native HTMX support)
- Claude Code

## License

MIT
