---
description: "DEPRECATED PLUGIN. Runs the one-time forced migration from drupal-dev-framework to ai-dev-assistant: moves the global project store, re-stamps each registered project's session-remembrance hooks to the new paths, then tells you it is safe to uninstall this plugin. Every drupal-dev-framework command now redirects here."
allowed-tools: Bash, Read
argument-hint: "[--dry-run]"
---

# Upgrade to ai-dev-assistant

**`drupal-dev-framework` has been renamed to `ai-dev-assistant`.** This plugin is
now a deprecation shell — its only job is to migrate your local wiring to the new
plugin. Every old `/drupal-dev-framework:*` command redirects to this one.

The migration is a **forced upgrade** (no back-compat): it rewrites every old-name
wiring point to the new name. It is **idempotent** — safe to re-run.

## What it changes

1. **Global store** — moves `~/.claude/drupal-dev-framework/` →
   `~/.claude/ai-dev-assistant/` (project registry, sessions, logs).
2. **Per-project remembrance hooks** — for each registered project that still
   carries old-name wiring: moves the baked hook dir
   `<project>/.claude/drupal-dev-framework/` → `<project>/.claude/ai-dev-assistant/`
   and rewrites the two hook command strings in `<project>/.claude/settings.json`.

## Prerequisite

Install the **ai-dev-assistant** plugin first (it is the migration target). You can
keep this shell installed alongside it to run the upgrade, then uninstall the shell.

## Run it

First, **always show the user a dry run** so they see exactly what will change:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/upgrade-to-ai-dev-assistant.sh" --dry-run
```

Show the output. Ask the user to confirm. On confirmation, run the real migration:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/upgrade-to-ai-dev-assistant.sh"
```

If the user passed `--dry-run` as the command argument, run only the dry run and stop.

## After it completes

Tell the user:

- The global store now lives at `~/.claude/ai-dev-assistant/`.
- Each migrated project's `settings.json` hooks and baked scripts now point at
  `.claude/ai-dev-assistant/`. New hooks take effect on the next session in that
  directory.
- **This plugin is now safe to uninstall.** Use `ai-dev-assistant` going forward
  (`/ai-dev-assistant:next` to resume work).

## Notes

- The script reads the registry from the old store first, falling back to the
  already-moved new store, so a second run is a clean no-op.
- It never deletes data — it moves directories and rewrites path strings in place,
  validating JSON before committing any `settings.json` change.
- If a project already has a `.claude/ai-dev-assistant/` dir (partial prior
  migration), the script leaves the old dir in place and flags it for manual review
  rather than overwriting.
