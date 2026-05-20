# Plugin Creation Tools — Plugin Conventions

This plugin teaches plugin authoring; it must hold itself to the same standards it teaches.

## Self-Application Rule

Every change to this plugin must pass the gates this plugin defines:

1. `/plugin-creation-tools:validate` (path-targeted at this plugin) — clean or all-warnings.
2. `skill-quality-reviewer` agent on `skills/plugin-creation/SKILL.md` — no regressions.
3. `plugin-structure-auditor` agent on the plugin root — score ≥ 24/30.

If a gate flags this plugin, fix this plugin. Do not loosen the gate.

## Doc-Snapshot Discipline

This plugin tracks a specific upstream Claude Code doc snapshot. The active snapshot lives in `~/workspace/claude_memory/guides/claude/` and the commit it was captured at is recorded in the most recent `CHANGELOG.md` entry.

- When upstream docs change, capture a new snapshot, write a *findings* doc that maps each delta to the affected reference files, and write a *plan* before editing.
- "Upstream doc wins" — when this plugin's reference text disagrees with the snapshot, the snapshot is authoritative. Note any deliberate deviation in the CHANGELOG.

## Versioning

- Patch — typo / metadata / single-doc clarification with no schema change.
- Minor — new reference page, new validator rule, new template, new optional component, version-table column added.
- Major — breaking schema change, removed reference, renamed required field.

Bump in **all** of: `.claude-plugin/plugin.json`, the root `marketplace.json` plugin entry, `skills/plugin-creation/SKILL.md` frontmatter, and `CHANGELOG.md`. Plugin-version pointer updates also bump the root `marketplace.json` `metadata.version` by one patch.

## Drift to Watch

Every revision must keep these counts in sync between SKILL.md, `commands/validate.md`, and the relevant reference files:

- Hook event count (currently **29** — added `Setup` in the 2026-05-08 doc snapshot).
- Hook handler types (currently **5** — `command`, `http`, `mcp_tool`, `prompt`, `agent` with `agent` marked experimental).
- **Hook command-form pair** (v2.1.139+ — exec form via `args` field is preferred whenever a path placeholder appears; shell form remains valid for pipes/redirects/chains).
- **Hook output cap** (10,000 characters across `additionalContext` / `systemMessage` / stdout; overflow becomes a file-path preview).
- **No controlling terminal in hooks** (v2.1.139+ — `/dev/tty` writes from hook scripts no longer reach the user; surface via `systemMessage` / `terminalSequence` JSON output).
- **Terminal sequence allowlist** (OSC `0`/`1`/`2`/`9`/`99`/`777` + BEL — anything else is rejected and the field is ignored).
- **PreToolUse decision precedence** (`deny > defer > ask > allow`) and parallel-then-merge across all matching hooks.
- Plugin component types (skills, commands, agents, hooks, mcpServers, lspServers, outputStyles, **`experimental.themes`**, **`experimental.monitors`** — themes and monitors are upstream-marked experimental and live under the `experimental.*` key; top-level still loads but `claude plugin validate` warns).
- **Path-field replacement semantics** (`commands` / `agents` / `outputStyles` / `experimental.themes` / `experimental.monitors` **replace** the default; only `skills` **adds**; `hooks` / `mcpServers` / `lspServers` have their own merge rules). v2.1.140+ surfaces ignored defaults in `/doctor`, `claude plugin list`, and the `/plugin` detail view.
- **Recursive `agents/` scanning + plugin-scoped subfolder ids** (subfolders join the scoped id with colons: `agents/review/security.md` → `my-plugin:review:security`). Project/user scopes do NOT join subfolders; this is plugin-only behavior.
- **Single-skill-at-root auto-discovery** (v2.1.142+): `SKILL.md` at the plugin root + no `skills/` subdir + no `skills` field is auto-loaded as a single-skill plugin; the `"skills": ["./"]` field becomes redundant.
- **Canonical templates source-of-truth**: `init_plugin.py` reads `templates/plugin.json.template` rather than embedding its own. Don't add new manifest fields in the script — add them to the template; the script will pick them up.
- **TodoWrite is disabled by default v2.1.142+** — new content uses `TaskCreate` / `TaskGet` / `TaskList` / `TaskUpdate` / `TaskStop`. Validator rule C01 flags `TodoWrite` references.
- **Skill listing budget**: per-skill cap `maxSkillDescriptionChars` (default 1,536); aggregate cap `skillListingBudgetFraction` (default 0.01 = 1%); descriptions for least-used skills collapse to bare names when the listing overflows. `/doctor` shows truncation count.
- **`displayName` manifest field** (v2.1.143+) — optional, human-readable, falls back to `name`. Not used for namespacing/lookup.
- **License hygiene** — prefer SPDX identifiers; `"proprietary"` only with private repository; validator M16 surfaces non-SPDX at info.
- **Keywords cap** — soft cap 25; validator M15 warns past this (marketplace UI truncation + per-tag budget pressure).
- **Marketplace per-plugin description cap** — soft cap 600 chars; validator X02 warns past this. Verbose history goes in CHANGELOG.md.
- **Skill body line model** — target < 250 lines; validator S10 warns ≥ 250, errors ≥ 500. This plugin's own `plugin-creation` SKILL.md (~334 lines) trips the warn — an accepted self-finding (large hub skill, heavy progressive disclosure).
- **Skill description caps** — runtime cap `maxSkillDescriptionChars` 1,536 (validator S05); agentskills.io portability target ~1,024. Don't conflate the two — 1,024 is a recommendation, 1,536 is the hard truncation point.
- **Skill discovery** — project skills load from `.claude/skills/` in the starting dir AND every parent up to repo root; nested `.claude/skills/` load on demand (monorepo pattern).
- **Session-remembrance pattern** — `add-component remembrance-hooks` scaffolds it; validator R01–R05 enforce conformance. Two rules are load-bearing and must never be "fixed" out of the templates: **no `PostCompact` hook** (stdout not injected into context) and **copy `save-session.sh` into the project** (`${CLAUDE_PLUGIN_ROOT}` doesn't resolve in project `settings.json`). The pattern is two hook events — `SessionStart` + `SessionEnd`. drupal-dev-framework v4.5.0 is the reference adopter.
- Reserved marketplace names list.
- The skill-description budget numbers (1% / 8,000-char fallback / 1,536-char per-entry cap / 500-line SKILL.md soft cap).

## Anti-Patterns Specific to This Plugin

- Don't strip `PROACTIVELY` / `MUST` / `NEVER` imperatives from the SKILL.md description across revisions.
- Don't drop the `` !`ls .claude-plugin/ 2>/dev/null` `` dynamic-context injection from the SKILL.md description.
- Don't add reference content that duplicates what's already in another reference file — link instead.
- Don't web-fetch upstream guides during edits — read the local snapshot. The snapshot is the contract.

## Components

- `skills/plugin-creation/SKILL.md` — single large skill, progressive disclosure into `references/`.
- `commands/create.md` — scaffold a new plugin.
- `commands/add-component.md` — add a skill / command / agent / hook / MCP / theme.
- `commands/validate.md` — validate plugin structure and wiring.
- `agents/plugin-structure-auditor.md` — Architecture / Cross-Component Consistency / Performance audit (read-only).
- `agents/skill-quality-reviewer.md` — SKILL.md description-and-body review (read-only).
- `hooks/hooks.json` — `PreCompact` only, instructs Claude to read plugin files on demand instead of dumping metadata.
