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
