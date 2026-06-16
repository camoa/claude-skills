---
paths:
  - "commands/**"
---

# Command Conventions (this plugin)

## Required Frontmatter
- `description` — clear, action-oriented, includes trigger phrases ("Use when…").
- `allowed-tools` — minimum needed. `validate.md` is read-only (`Read, Glob, Grep`) plus scoped read-only Bash (`Bash(ls:*), Bash(find:*), Bash(wc:*)`) for deterministic component counts (D1 — never let the fork eyeball counts) and `Bash(bash:*)` to run the shipped read-only `scripts/containment-scan.sh` kernel for the P-series containment gate; `create.md` and `add-component.md` need write access.

## Optional Frontmatter
- `argument-hint` — when the command accepts arguments.
- `context: fork` — when the command produces noisy output that would pollute the main context (used by `validate.md` and `add-component.md`).

## Body
- Step-by-step numbered workflow.
- Reference the templates in `skills/plugin-creation/templates/` rather than reproducing them.
- Include error handling for missing prerequisites (e.g., "if `.claude-plugin/plugin.json` is absent, ask the user to confirm the plugin root").
- Validation rules belong in `validate.md`'s checklist sections, not in `create.md` or `add-component.md` — those scaffold; `validate` checks.

## Checklist Discipline (`validate.md`)
- Every recognized hook event, handler type, plugin component type, and reserved marketplace name must appear in the checklist text.
- When upstream adds a new event/type/field, update `validate.md` in the same revision as the corresponding reference page.
- Mark legacy forms as info-level (not warning) when the new schema is additive — let users opt in on their own schedule.
- Section-name guidance must match upstream Claude Code docs. The Skills "Recommended Structure" uses `## Troubleshooting` (not `## Common Mistakes`); the validator's "missing troubleshooting/error handling section" check accepts either name but new templates should use `Troubleshooting`.
