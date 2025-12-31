---
description: Show HTMX development status and suggest next actions for a Drupal module
allowed-tools: Read, Glob, Grep
argument-hint: [module-path]
---

# HTMX Status

Show current HTMX/AJAX usage and suggest next actions.

## Usage

`/htmx [module-path]`

## Parameters

- `$1` - Module path (optional). Defaults to `modules/custom/`

## Steps

1. If module path provided:
   - Quick scan for AJAX patterns (`#ajax`, `AjaxResponse`)
   - Quick scan for HTMX usage (`new Htmx()`, `HtmxRequestInfoTrait`)
   - Summarize findings
   - Suggest appropriate next command

2. If no path provided:
   - Show available commands
   - Explain when to use each

## Output

### With Module Path

```markdown
## HTMX Status: [module-name]

### Current State
- AJAX patterns found: X
- HTMX implementations: X

### Suggested Actions
- [Based on findings]

### Available Commands
- `/htmx-analyze [path]` - Full AJAX analysis
- `/htmx-migrate [file]` - Migrate specific pattern
- `/htmx-pattern [use-case]` - Get pattern recommendation
- `/htmx-validate [path]` - Validate HTMX code
```

### Without Module Path

```markdown
## HTMX Development Commands

| Command | Purpose |
|---------|---------|
| `/htmx [path]` | Quick status scan |
| `/htmx-analyze <path>` | Analyze AJAX for migration |
| `/htmx-migrate <file>` | Guided migration |
| `/htmx-pattern <use-case>` | Pattern recommendation |
| `/htmx-validate <path>` | Validate implementation |

### Getting Started
1. Run `/htmx-analyze modules/custom/my_module` to find migration candidates
2. Run `/htmx-pattern dependent dropdown` for new implementations
```
