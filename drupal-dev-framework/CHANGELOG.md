# Changelog — drupal-dev-framework

All notable changes to this plugin are documented here.

## [4.24.1] — Deprecation-notice docs tightening

Tightened the deprecation-notice README (problem-first, no em dashes). Positioning pass.

## [4.24.0] — Opt-in permission re-point

**New `--permissions` flag on the upgrade script.** Registered projects can carry
pre-approved `Skill(drupal-dev-framework:*)` permission grants in their
`settings.local.json` (or `settings.json`). After the rename those grants point at
skills that no longer exist. They are harmless (the new `/ai-dev-assistant:*` command
just re-prompts for permission once on first use), so the migration leaves them alone
by default and only reports how many it found.

- `--permissions` (opt-in) re-points `Skill(drupal-dev-framework:*)` →
  `Skill(ai-dev-assistant:*)` in place across both settings files for every registered
  project. The rewrite is scoped to that exact `Skill(...)` token, so it never touches
  a `Bash(...)` cache-path grant or any other allowlist content, and it validates JSON
  before saving (invalid result → file left untouched).
- Without `--permissions`, the script prints a one-line count of the stale tokens it
  found and how to re-point them — discoverable, never silent.
- Flags combine: `--dry-run --permissions` shows the re-point plan without writing.
- `upgrade.md` and `README.md` document the opt-in; `argument-hint` now lists
  `[--dry-run] [--permissions]`.

## [4.23.1] — Deprecation-shell docs

**Documentation only — no functional change.** Clarified the shell's command surface
after the rename:

- The shell carries every old command **name** as a symlink to the single `upgrade`
  command. Claude Code resolves command symlinks to their target and de-duplicates
  them, so **only `/drupal-dev-framework:upgrade` appears in the `/` menu** — by
  design. README now states this explicitly and points the old command names at the
  `ai-dev-assistant:` namespace (names unchanged, namespace moved).
- Added the migrate-then-switch steps to `README.md`: install `ai-dev-assistant`
  first, run `/drupal-dev-framework:upgrade`, then **disable or uninstall** this shell
  via the `/plugin` menu (with the disable/re-enable note for re-running the migration
  on another project).

## [4.23.0] — Deprecation shell

**Renamed to `ai-dev-assistant`.** The full Research → Architecture → Implementation
→ Review framework — every skill, command, agent, hook, and script — moved to the
new `ai-dev-assistant` plugin (git history preserved across the rename).

`drupal-dev-framework` is retained only as a thin, installable **deprecation shell**
so existing installs have something to migrate *from*:

- Keeps a valid `plugin.json` and a `marketplace.json` entry, so the plugin still
  resolves for anyone who has it installed.
- Ships a single one-time **`/drupal-dev-framework:upgrade`** command — every other
  old command symlinks to it — that moves the project store
  (`~/.claude/drupal-dev-framework/` → `~/.claude/ai-dev-assistant/`) and re-stamps
  each registered project's session-remembrance hooks to the new paths (idempotent,
  JSON-validated, `--dry-run` supported).
- Self-deletes after migration; users install `ai-dev-assistant` going forward.

## [4.22.0] and earlier

See `ai-dev-assistant/CHANGELOG.md` — the full history moved there with the rename.
