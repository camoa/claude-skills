# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.6.0] - 2026-05-19

**Theme: Layout & Discovery.** Second release of the consolidated 2026-05-12 roadmap. Catches up on plugin-author-relevant layout features (recursive `agents/` subfolder scoping, single-skill-at-root auto-discovery) and kills one of the longest-standing divergences — `init_plugin.py` now reads the canonical `templates/plugin.json.template` instead of embedding its own truncated copy.

Snapshot baseline: Claude Code v2.1.144, `~/workspace/claude_memory/guides/claude/` refreshed 2026-05-12 (`552b666`). No upstream-version bump from v3.5.0.

### Added — Recursive `agents/` subfolder scoping

- `references/05-agents/writing-agents.md`: new section "Organizing Agents Into Subfolders" — covers recursive scanning, the **plugin-specific** scoped-id behavior (`agents/review/security.md` → `my-plugin:review:security`), contrast with project/user scopes (where subfolders are organizational only), and the `name`-uniqueness-across-tree rule.
- `references/10-distribution/packaging.md`: layout diagram updated with a subfolder example and an inline note distinguishing plugin scope from project/user scope.
- `skills/plugin-creation/SKILL.md`: the directory-structure block now annotates `agents/` with the recursive-scan + scoped-id behavior.

Source: Subagents guide L181–183.

### Added — Single-skill-at-root auto-discovery (v2.1.142+)

- `references/08-configuration/plugin-json.md`: new item #4 in "Important Path Rules" — a plugin with `SKILL.md` at root + no `skills/` subdir + no `skills` field is auto-loaded as a single-skill plugin. No need for `"skills": ["./"]`.
- `references/10-distribution/packaging.md`: flat-layout diagram added beside the standard layout, with the "migrate to standard when you add a second component" caveat.
- `skills/plugin-creation/SKILL.md`: brief mention in the plugin-init section pointing at the plugin-json.md rule.

Source: Plugins Reference L530, L532.

### Added — v2.1.140+ `/doctor` ignored-folder semantics

- `references/08-configuration/plugin-json.md`: "Important Path Rules" item #1 rewritten. **The previous text said "Custom paths SUPPLEMENT default directories" — this was wrong.** For `commands`, `agents`, `outputStyles`, `experimental.themes`, `experimental.monitors`, custom paths **replace** the default. Only `skills` adds; `hooks` / `mcpServers` / `lspServers` have their own merge rules. The rule now explicitly cites the v2.1.140+ tooling that surfaces the ignored folder in `/doctor`, `claude plugin list`, and the `/plugin` detail view.
- `skills/plugin-creation/SKILL.md` troubleshooting row updated: the "components missing" symptom now mentions `/doctor` will name the folder being skipped.

Source: Plugins Reference L515–523.

### Refactored — `init_plugin.py` reads the canonical template

The script's embedded `PLUGIN_JSON_TEMPLATE` string had drifted from `templates/plugin.json.template` since v3.4.0 — it lacked `$schema`, lacked the commented `experimental.*` / `userConfig` / `channels` blocks, lacked `bin/` / `settings.json` notes, and lacked the array-form guidance. A user who invoked the script got a manifest that disagreed with what the docs and templates teach.

Fix: `_render_plugin_json()` reads `templates/plugin.json.template`, strips the `//` documentation comments, parses the remaining JSON, substitutes the plugin name, and writes. The same source-of-truth file is rendered no matter where the user invokes `init_plugin.py` from.

A related v3.5.0 miss is also patched: the embedded `HOOKS_TEMPLATE` now uses exec form (`"args": []`) on its three example command hooks, matching the canonical `templates/hooks/hooks.json.template`. This is a retroactive v3.5.0 fix; functional behavior of the scaffolded hooks is identical (exec form is semantically equivalent for these script invocations).

Source: gap §2.1.

### Added — Validator rules A02, A03, ST04, ST05, ST06

`commands/validate.md` gains:

- **A02 (info)** — Agent file under an `agents/` subfolder; emit a note that the scoped id includes the subfolder so the author can confirm the `name` field matches the label they expect users to type after the colons.
- **A03 (warn)** — Agent file under an `agents/` subfolder missing the `name` frontmatter field. The agent loads with empty metadata and can't be invoked by scoped id.
- **ST04 (info)** — Single-skill-at-root plugin (`SKILL.md` at plugin root, no `skills/` subdir) with a redundant `"skills": ["./"]` manifest field — the field is unnecessary as of v2.1.142+.
- **ST05 (warn)** — Manifest references a folder that doesn't exist (typo catcher).
- **ST06 (info)** — Manifest sets a "Replaces the default" field to a custom path AND the matching default folder still has files. Those files are silently ignored at runtime; `/doctor` flags this in v2.1.140+.

The "Agents" validation section also gains an opener noting that plugin `agents/` is scanned **recursively** — older validator runs that only walked the top level missed subfolder agents.

### Updated

- `plugin.json` 3.5.0 → 3.6.0; description appended with v3.6.0 highlight.
- Root `marketplace.json` `metadata.version` 1.14.40 → 1.14.41. Plugin entry version bumped + description tightened (now ~1200 chars, down from 1400+).

### Notes

- **`init_plugin.py` MARKETPLACE_JSON_TEMPLATE intentionally stays embedded.** The canonical `templates/marketplace.json.template` is a multi-plugin example (git-subdir / npm / pip sources) — not the right shape for a freshly-scaffolded single-plugin marketplace. Reading the canonical there would make the scaffold worse, not better. Roadmap §2.1 only called out the `plugin.json` divergence.
- **Smoke test ran**: `init_plugin.py smoke-test --path /tmp --components skill,hook` — the rendered `plugin.json` contains `$schema`, the `repository` placeholder, and the keywords array, all from the canonical template. JSON parses; structure matches `templates/plugin.json.template` byte-for-byte after comment stripping.
- **Ecosystem migration still deferred** to a `chore/ecosystem-layout-migration` follow-up PR. A02/A03/ST06 are most likely to fire against drupal-dev-framework (recursive `agents/` + several `agents` manifest entries) and brand-content-design (similar structure).
- **Out of scope** (parked per roadmap): v3.6.1 metadata/tools (`displayName`, Task* family, `WaitForMcpServers`, $schema auto-fix); v3.6.2 skill guidance (effort.level skill examples, workspace-trust UI gate, listing budget framing); v3.7.0 cross-plugin session-remembrance helper.

## [3.5.0] - 2026-05-19

**Theme: Hook Authoring Depth.** First release of the consolidated roadmap (2026-05-12). Catches up on the v2.1.139 → v2.1.144 hook revolution and ships paired enforcement rules so the same regressions can't reappear in other plugins.

Snapshot baseline: Claude Code v2.1.144, `~/workspace/claude_memory/guides/claude/` refreshed 2026-05-12 (`552b666`).

### Added — Exec form vs shell form

- `references/06-hooks/writing-hooks.md`: new section "Exec form vs shell form" — covers the `args` field, when exec form is preferred (any time a placeholder appears), the Windows `.cmd`/`.bat` caveat (invoke `node` with the script path), and the bare-name + whitespace warning condition. Fields table gains `args` and `shell` rows.
- All canonical hook examples in `templates/hooks/hooks.json.template`, `references/06-hooks/hook-events.md` (25 examples), `references/06-hooks/hook-patterns.md` (16 examples), `references/06-hooks/writing-hooks.md`, `hooks/hooks.json` (plugin self-application), and `skills/plugin-creation/examples/full-featured-plugin/hooks/hooks.json` (the cross-platform `.cmd` wrapper stays in shell form with an inline note explaining why).

### Added — JSON output return fields

- `references/06-hooks/writing-hooks.md`: new section "JSON Output Return Fields" — table of `continue` / `stopReason` / `suppressOutput` / `systemMessage` / `terminalSequence` / `hookSpecificOutput.additionalContext`. Covers the v2.1.139 "no controlling terminal" change (hooks can no longer write to `/dev/tty` or emit raw escape sequences), the OSC allowlist for `terminalSequence` (0/1/2/9/99/777 + BEL), and the 10,000-character output cap with file-fallback behavior.
- `references/06-hooks/hook-events.md`: top-of-file callout summarising the three v2.1.139+ rules (no controlling terminal, 10K cap, exec form for placeholders) with links to the writing-hooks section.

### Added — Hook execution semantics

- `references/06-hooks/writing-hooks.md`: new section "Hook Execution Order & Precedence" — parallel-then-merge, dedup-by-`command`+`args` for command hooks (HTTP by URL), and PreToolUse decision precedence `deny > defer > ask > allow`. Replaces the "most restrictive setting wins" misconception that authors sometimes ship.

### Added — Validator rules H05–H13 (paired with `--fix` machinery)

`commands/validate.md` gains:

- **H05 (warn, `--fix`)** — Command hook with a `${CLAUDE_*}` path placeholder in `command` but no `args` field → suggest exec form. Auto-fix inserts `"args": []`; skips when the command contains shell metacharacters (`|`, `&&`, `;`, redirects, etc.).
- **H06 (warn, `--fix`)** — Bare `$CLAUDE_PROJECT_DIR` / `$CLAUDE_PLUGIN_ROOT` / `$CLAUDE_PLUGIN_DATA` / `$CLAUDE_ENV_FILE` / `$CLAUDE_EFFORT` inside JSON command-string values in `hooks.json` → rewrite to `${VAR}`. Only scans JSON command strings; bare `$VAR` inside `.sh` scripts is correct bash and is **not** flagged.
- **H07 (warn)** — Shell-form command hooks must quote `${CLAUDE_*}` placeholders. Skipped when `args` is present (exec form needs no quoting).
- **H08 (info)** — Broad-matcher tool-event hooks (`*` / `""` / `.*` / omitted) without `if` field may spawn on every tool call. Info-level suggestion, not warn — some authors intentionally spawn for logging.
- **H09 (warn)** — `if` field on non-tool events (silently ignored at runtime).
- **H10 (warn, `--fix`)** — `updatedMCPToolOutput` literal → `updatedToolOutput` in `hooks.json` and referenced hook scripts. Old field still works, but the rename means the hook also catches built-in tools, not only MCP.
- **H11 (info)** — `SessionStart` hook script doing one-time install (check-then-install + package-install heuristic) → suggest moving to `Setup` event.
- **H12 (error)** — Hook script writes to `/dev/tty`. Broken as of v2.1.139; surfaces as error with pointer to `terminalSequence` / `systemMessage`.
- **H13 (warn)** — Best-effort heuristic on hook output approaching the 10K cap (large heredocs, `cat` of large files used as the only stdout).

`--fix` is opt-in and reversible. All auto-fixes are logged to `.claude-plugin/.validate-fixes.log` (append-only, timestamp + rule + summary) so the author can grep the change history if a later version regresses.

### Updated

- `skills/plugin-creation/SKILL.md`: new "Exec form vs shell form" + "No controlling terminal" paragraphs in the Hooks section.
- `README.md`: hook bullet expanded with exec form / JSON output fields / 10K cap / no controlling terminal / parallel-then-merge precedence. Compatibility line bumped from 2.1.119 → 2.1.144.
- `CLAUDE.md`: Drift to Watch list gains hook command-form pair, output cap, controlling-terminal note, terminal-sequence allowlist, and PreToolUse decision precedence.
- Marketplace description rewritten as an elevator pitch + v3.5.0 highlight (down from ~3500-char history dump).
- Root marketplace.json `metadata.version` 1.14.39 → 1.14.40 (plugin-version pointer update).

### Notes

- **Rule numbering follows the roadmap (H05–H13).** Enforcement-design §4 uses overlapping IDs for different rules; the next release will reconcile if needed. The roadmap is authoritative for what each release ships.
- **Ecosystem migration deferred.** The `--fix` machinery lands here; bulk migration of camoa-skills + palcera_skills hooks is a separate `chore/ecosystem-hook-migration` PR so the change history per plugin stays auditable.
- **Out of scope** (parked for later releases per the roadmap): single-skill-at-root auto-discovery, recursive `agents/` subfolder scoping, `init_plugin.py` template-source refactor (v3.6.0); `$schema` / `experimental.*` auto-fix, `TodoWrite` deprecation, `WaitForMcpServers` / LSP tool rows (v3.6.1); skill-listing budget guidance, workspace-trust UI gate, `effort.level` skill examples (v3.6.2); cross-plugin session-remembrance helper (v3.7.0, conditional on DDF adopting the pattern first).

## [3.4.1] - 2026-05-12

Post-v3.4.0 audit patch. A read-only comparison against the current `claude_memory/guides/claude/` snapshot surfaced three missing-content gaps (not stale-content). None affect the typical plugin-authoring path; all are scoped to short additions in existing reference files.

### Added — `channels` manifest field
- `references/08-configuration/plugin-json.md`: new `channels` row in the component-paths table + new "Channels" section with full schema (`server` required, must match a key in `mcpServers`; per-channel `userConfig` mirrors the top-level schema; Telegram/Slack/Discord-style message-injection use case).
- `templates/plugin.json.template`: commented `channels` example block.
- `commands/validate.md`: info-level check — when `channels` is declared, verify `server` matches a key in the plugin's `mcpServers` (warn on dangling reference); apply userConfig legacy/required checks to per-channel `userConfig`.

### Added — `bin/` directory
- `references/08-configuration/plugin-json.md`: new "`bin/` Directory" section. Auto-discovered (no manifest entry), executables added to the Bash tool's `PATH` while the plugin is enabled. Cross-platform shebang guidance; "use this over `hooks/` for utilities users invoke directly" distinction; chmod +x requirement.
- `references/10-distribution/packaging.md`: `bin/` added to the standard plugin-layout diagram alongside `scripts/`, `output-styles/`, `themes/`, `monitors/`, `.lsp.json` (which were also missing from the diagram).
- `references/quick-reference.md`: `bin/` added to the structure diagram.
- `templates/plugin.json.template`: explanatory note about `bin/` auto-discovery.
- `commands/validate.md`: info-level check — when `bin/` is present, warn on non-executable entries (they'll appear on `PATH` but fail to run).

### Added — `subagentStatusLine` plugin setting
- `references/08-configuration/settings.md`: new `subagentStatusLine` section with example, precedence note (user-level overrides plugin default), pointer to upstream Status Line guide.
- `references/08-configuration/plugin-json.md`: settings.json supported-keys table updated — `agent` joined by `subagentStatusLine`. Confirmed upstream: these two are the only currently-supported plugin-settings keys (unknown keys silently ignored).
- `templates/plugin.json.template`: settings.json note updated to mention both keys.

### Added — Validator: plugin-root `settings.json`
- `commands/validate.md`: new "Plugin settings.json" check block — valid JSON, recognized keys only (`agent` / `subagentStatusLine`), `agent` value must match an agent file, `subagentStatusLine` must match upstream schema shape. Forward-compat info note on unknown keys.

### Changed — SKILL.md niche-fields pointer
- `SKILL.md` "Configuring Plugin" section: added a 6th bullet covering `channels`, `bin/`, and plugin-root `settings.json` (both keys), so authors building atypical plugins are routed to the right reference without bloating the main flow.

### Metadata sync
- `.claude-plugin/plugin.json`: `version` 3.4.0 → **3.4.1**.
- `skills/plugin-creation/SKILL.md` frontmatter `version` 3.4.0 → **3.4.1**.
- Root `marketplace.json`: `plugin-creation-tools` entry version 3.4.0 → **3.4.1**; `metadata.version` 1.14.34 → **1.14.35** (patch bump per `feedback_marketplace_version_bump`).

### Notes
- Doc baseline unchanged from v3.4.0 (2026-05-08 snapshot).
- Audit source: `claude_docs/improvements/plugin-creation-tools-audit-2026-05-12.md` (in-conversation).
- Still deferred for the next refresh cycle (v3.5.0): output-style **authoring** depth (the field is documented but custom-style `.md` schema isn't) and Agent SDK coverage breadth (9 of 29 upstream pages — explicitly deferred in v3.4.0). Not blocking — manifest-field documentation exists; authors aren't stuck.

## [3.4.0] - 2026-05-11

Doc-snapshot refresh covering Claude Code **v2.1.120 → v2.1.136**. Source: tracking memo `claude_docs/improvements/plugin-creation-tools-2026-05-08.md`. Plan-driven, additive — no breaking changes for plugin authors who haven't migrated yet (top-level `themes`/`monitors` still load).

### Added — Manifest schema (`experimental.*`, `$schema`, array-only `agents`)
- **NEW migration section** in `references/08-configuration/plugin-json.md`: themes/monitors belong under `experimental.*`. Top-level still loads but `claude plugin validate` warns; a future release will require the nested form. Includes a `diff` block showing the wrapping change.
- `templates/plugin.json.template`: emits `$schema` (SchemaStore JSON Schema URL — editor autocomplete only, Claude Code ignores it at load time), commented `experimental.{themes,monitors}` block, and array-form guidance for `commands`/`agents`/`skills`.
- `references/08-configuration/themes.md`: examples updated to nest under `experimental.themes`.
- `references/08-configuration/plugin-json.md`: `$schema` row added to metadata table; `agents` row tightened to array-only; `commands`/`skills` flagged as array-preferred.
- `commands/add-component.md`: `theme` subcommand now writes paths under `experimental.themes` and warns about the top-level form.

### Added — Hook event #29: `Setup`
- **NEW `Setup` event** in `references/06-hooks/hook-events.md`. Fires only on `--init-only`, `--init -p`, `--maintenance -p` — distinct from `SessionStart` which fires every launch. Receives `trigger: "init" | "maintenance"`. Has `CLAUDE_ENV_FILE`. Cannot block (exit 2 shows stderr only). Only `command` and `mcp_tool` handler types supported. Documents the "check on first use, install on miss" pattern with `${CLAUDE_PLUGIN_DATA}` since Setup doesn't fire on every launch.
- Hook event count drift sweep — 28 → **29** across `SKILL.md`, `commands/validate.md`, `commands/add-component.md`, `hook-events.md` (intro + See Also), `writing-hooks.md` (See Also), `plugin.json` description, `README.md`, root `CLAUDE.md` Drift to Watch list, `references/quick-reference.md` (was stale at 22 — caught during count audit).

### Added — Worktree hook input/output schema
- `references/06-hooks/hook-events.md`: `WorktreeCreate` and `WorktreeRemove` entries refined with input schema (stdin JSON `{ "name": "..." }`), the stdout-path contract for `WorktreeCreate` command hooks (`hookSpecificOutput.worktreePath` for HTTP hooks), and the "any non-zero exit aborts creation" exception (unlike most events where only exit 2 blocks). Use case framed as "replace default git worktree behavior with custom VCS logic" — SVN/Perforce/Mercurial wrapper plugins.

### Added — Adaptive effort (`effort.level` / `${CLAUDE_EFFORT}`)
- `references/06-hooks/hook-events.md`: `effort` object added to Common Input Fields — present on tool-use-context events (`PreToolUse`, `PostToolUse`, `Stop`, `SubagentStop`) when the current model supports effort. Reflects the level the model actually used (downgraded if requested level exceeded support).
- `references/06-hooks/writing-hooks.md`: `$CLAUDE_EFFORT` env var added to the env-vars table; `${CLAUDE_ENV_FILE}` row extended to list all four events that can write to it (`SessionStart`, `Setup`, `CwdChanged`, `FileChanged`).
- `references/03-skills/writing-skillmd.md`: `${CLAUDE_EFFORT}` added to skill body substitutions with usage note (terser steps at `low`, fuller checklists at `high`+).
- `SKILL.md`: hooks section gets an "Adaptive hooks" paragraph linking the two.

### Added — `updatedToolOutput` preferred over `updatedMCPToolOutput`
- `references/06-hooks/hook-events.md`: PostToolUse return-fields block now documents `updatedToolOutput` (works for all tools) and explicitly marks `updatedMCPToolOutput` as legacy MCP-only. Includes the "tool already ran" warning — `updatedToolOutput` only changes what Claude sees, not what the tool did.
- `commands/validate.md`: new info-level check flagging `updatedMCPToolOutput` usage in hook scripts/JSON.

### Added — `skillOverrides` setting
- **NEW `skillOverrides` section** in `references/08-configuration/settings.md`. Four states (`on` / `name-only` / `user-invocable-only` / `off`), how the `/skills` menu writes it to `.claude/settings.local.json`, and the upstream caveat that `skillOverrides` does NOT affect plugin-shipped skills — for those, point users at `/plugin disable`. Surface this distinction in plugin READMEs.
- `SKILL.md`: new "Suppressing a plugin skill without forking" subsection under Configuring Plugin.
- `README.md`: Distribution housekeeping paragraph mentioning the lever.

### Added — Lifecycle CLI commands
- `references/09-testing/cli-reference.md`: **`claude plugin prune`** (remove auto-installed dependencies no other plugin requires, requires v2.1.121+, alias `autoremove`, `--dry-run`/`--yes`/`--scope` flags), **`--prune` flag on `plugin uninstall`**, and **`--plugin-url`** session-only flag (load a packaged `.zip` from a URL — useful for previewing pre-release plugins without writing to `~/.claude/plugins`).
- `README.md`: Distribution housekeeping section surfaces all three.

### Added — Plugin Hints (CLI-driven install prompts)
- **NEW section** in `references/10-distribution/packaging.md`. Mechanism: CLI checks `CLAUDECODE=1` env var, emits `<claude-code-hint plugin="namespace/plugin-name" />` on its own line (stderr preferred). Claude Code strips the line before sending to the model (zero token cost). User sees a one-time install prompt. Constraints: **official Anthropic marketplace only** (so out-of-scope for camoa-skills / palcera_skills plugins — documented as such); gate on the env var; one line, no surrounding text; stderr preferred.

### Added — Workspace-trust gating clarification
- `references/03-skills/writing-skillmd.md`: `allowed-tools` row rewritten to (a) clarify it *grants* permission not *restricts* (existing wording was wrong), and (b) document the workspace-trust gate for `.claude/skills/*` skills. Notes that plugin-shipped skills are not subject to this gate — trust is established at install time.
- `commands/validate.md`: new info-level check for project-scoped skills with `allowed-tools`, pointing at the trust-dialog gate.

### Added — Plugin-root `CLAUDE.md` clarification
- `SKILL.md`: "Plugin Project Setup" section reframes plugin-root `CLAUDE.md` as authoring reference only (NOT loaded as project context when the plugin is installed). Instructions belong in a skill.
- `commands/validate.md`: new info-level (not warning) notice when a plugin-root `CLAUDE.md` is present.

### Validator drift sweep (`commands/validate.md`)
New checks added in one batch:
- Top-level `themes`/`monitors` → **warning** with auto-migration diff offer.
- String-form `agents` → **warning** (array-only).
- String-form `commands`/`skills` → **info** (array preferred).
- Missing `$schema` → **info** (developer ergonomics).
- `updatedMCPToolOutput` → **info** (prefer `updatedToolOutput`).
- Plugin-root `CLAUDE.md` → **info** (not loaded as context).
- Project-scoped skill `allowed-tools` → **info** (workspace-trust gate).
- Hook event whitelist bumped to 29 names including `Setup`.

### Out of scope (deferred to follow-up sessions)
- **Existing-plugin audit.** Sister plugins (`brand-content-design`, design-* on the feature branch) were not run through `claude plugin validate` this cycle — that's a separate migration session.
- **Native binary distribution / `claude project purge` / routines on web / `/ultrareview` / `/usage` / Agent SDK Python/TS API churn** — per the plan's "Out of Scope" list. Tracked in other docs.

### Metadata sync
- `.claude-plugin/plugin.json`: `version` 3.3.1 → **3.4.0**; description "28 hook events" → "29 hook events".
- `skills/plugin-creation/SKILL.md` frontmatter `version` 3.3.0 → **3.4.0**.
- Root `marketplace.json`: `plugin-creation-tools` entry version 3.3.1 → **3.4.0** + description sync; `metadata.version` 1.14.33 → **1.14.34** (patch bump per `feedback_marketplace_version_bump`).
- `README.md`: hook count, validator coverage line, new Distribution housekeeping section.
- Root `CLAUDE.md` Drift to Watch: 28 → 29, themes/monitors flagged as experimental.

### Notes
- Doc baseline: upstream `claude_memory/guides/claude/` snapshot from 2026-05-08 (per the tracking memo). Plan + Implementation notes live at `claude_docs/improvements/plugin-creation-tools-2026-05-08.md`.
- Caught during this cycle: `references/quick-reference.md` "Hook Events" was stale at "22 total events" — drifted unnoticed since pre-v3.3.0. Fixed in the same sweep.
- Did NOT touch `scripts/init_plugin.py` (no hardcoded `themes`/`monitors` strings found) or `examples/{simple-greeter,full-featured}-plugin/` (no manifest fields needing migration).

## [3.3.1] - 2026-04-27

### Skill visibility hygiene (Tier 2 of multi-plugin command-naming research)

Set `user-invocable: false` on `skills/plugin-creation/SKILL.md`. The umbrella skill was defaulting user-invocable and substring-matching `/plugin` in the typeahead, but the user-facing entry points are the commands (`/plugin-creation-tools:create`, `:add-component`, `:validate`). No behavior change — Claude and parent commands can still invoke the skill via the Skill tool per docs line 290 + 496.

## [3.3.0] - 2026-04-25

Doc-snapshot: upstream `claude_memory/guides/claude/` at commit `c142d14` (135 guides). Covers Claude Code releases **2.1.116 → 2.1.119**. Single PR, additive — no breaking changes.

### Added — Hooks (Track A)
- **2 new hook events** in `references/06-hooks/hook-events.md`: `UserPromptExpansion` (intercept direct `/skillname` invocations — covers the path `PreToolUse` on the `Skill` tool does not) and `PostToolBatch` (one-shot context injection after a parallel batch resolves). Total event count: **26 → 28**.
- `duration_ms` field on `PostToolUse` and `PostToolUseFailure` payloads (release 2.1.119).
- **5th hook handler type** `mcp_tool` in `references/06-hooks/writing-hooks.md` — call a tool on an already-connected MCP server directly from a hook with `server` / `tool` / `input` fields. Worked example: file a Linear issue from a `Stop` hook.
- Note that the `agent` handler type is upstream-marked **experimental** in writing-hooks.md.
- Re-confirmed `if`-field Bash-subcommand semantics: `if: "Bash(rm *)"` matches both `FOO=bar rm file` and `npm test && rm file` (after stripping leading `VAR=value` assignments and splitting on subcommands), and runs when the command is too complex to parse.
- New patterns in `references/06-hooks/hook-patterns.md`: **UserPromptExpansion skill-invocation guard** (block `/deploy` until an approval file exists; inject team checklist) and **PostToolBatch summary** (single batch-summary message instead of per-tool noise).
- `references/06-hooks/cross-platform-hooks.md`: leading note that `mcp_tool` removes the `.cmd` polyglot-wrapper need when the work is an MCP call.
- `templates/hooks/hooks.json.template`: commented-out `mcp_tool` example block.

### Added — Plugin Themes (Track B)
- **NEW `references/08-configuration/themes.md`**: full reference for `themes/*.json` — `name` / `base` / `overrides` schema, the `Ctrl+E` user-customization-by-copy flow, `custom:<plugin-name>:<slug>` persistence naming, when to ship a theme, complete Dracula-style worked example.
- `themes` added to the component-paths table in `references/08-configuration/plugin-json.md`, with a one-line schema teaser and link to `themes.md`.
- `templates/plugin.json.template`: optional `themes` field, commented out, with a comment pointing at `themes.md`.
- `scripts/init_plugin.py`: new `theme` component option (`--components ...,theme` scaffolds `themes/default.json` from `THEME_TEMPLATE`).
- `commands/add-component.md`: `theme` component with the Ctrl+E read-only reminder.
- `commands/validate.md`: themes block validates `name` / `base` / `overrides` (warning on missing fields, error on invalid JSON).
- `agents/plugin-structure-auditor.md`: low-severity opportunity flag in Cross-Component Consistency for visual-identity-named plugins (`*-theme`, `*-design`, `brand-*`, names containing `theme`/`palette`/`color`) shipping no `themes/` directory.

### Added — `userConfig` schema (Track C)
- **`userConfig` section** added to `references/08-configuration/plugin-json.md` — full `type` / `title` / `description` schema, plus `sensitive` / `required` / `default` / `multiple` / `min` / `max`. Notes the additive change (description-only entries still load) and the keychain ~2 KB shared-with-OAuth budget.
- `templates/plugin.json.template`: full-schema `userConfig` example, commented out.
- `commands/validate.md`: per-entry `type` / `title` recommended (info-level message marking description-only as legacy form), `sensitive` substitution restriction noted.

### Added — Marketplace deps + tagging (Track D)
- **`allowCrossMarketplaceDependenciesOn`** documented in `references/08-configuration/marketplace-json.md`. Replaces the previously-conflated section that mixed this field with `strictKnownMarketplaces` (managed-settings-only). Now a clean table distinguishes the two: `allowCrossMarketplaceDependenciesOn` lives in root `marketplace.json` and gates **dependency trust**; `hostPattern` / `pathPattern` (in `strictKnownMarketplaces` / `extraKnownMarketplaces`) live in user/managed `settings.json` and gate **marketplace install location**. Adds explicit "trust does not chain" note (only the root marketplace's allowlist is consulted).
- `blockedMarketplaces` enforcement-points list expanded: now also runs on `update`, `refresh`, and `auto-update` (not just `add` / `install`).
- **`claude plugin tag`** documented in `references/08-configuration/marketplace-json.md` (release-tagging workflow) and `references/09-testing/cli-reference.md` (CLI-subcommand block with `--push`, `--dry-run`, `--force` flags). Pinned plugins auto-update to the highest satisfying git tag (release 2.1.119).
- `commands/validate.md`: cross-marketplace dep check rewritten to consult the root marketplace's `allowCrossMarketplaceDependenciesOn` (was previously checking `strictKnownMarketplaces`, which is the wrong field for trust). Error message points to the correct field.

### Added — Forked subagents + `--agent` behavior fix (Track E)
- New **"Forked Subagents (experimental)"** subsection in `references/05-agents/agent-patterns.md`: `CLAUDE_CODE_FORK_SUBAGENT=1` opt-in, manual `/fork <directive>`, what's inherited (system prompt, tools, model, message history), three side effects of fork mode (general-purpose becomes a fork; all spawns background; `/fork` no longer aliases `/branch`), when to use vs when not, fork-vs-named-subagent comparison table.
- **Behavior change callout** in `references/05-agents/writing-agents.md`: frontmatter `hooks` and inline `mcpServers` now fire/connect when an agent runs as the main session via `--agent` (previously dropped). Plugin-packaged agents are unchanged — `hooks` / `mcpServers` / `permissionMode` still silently ignored there for security.
- **Skill preload caveat** in `references/03-skills/writing-skillmd.md`: skills with `disable-model-invocation: true` cannot be preloaded via a subagent's `skills:` frontmatter list (preload draws from the same set Claude is allowed to invoke; disabled skills are silently skipped with a debug-log warning).

### Added — Settings, env vars, and cross-references (Track F)
- `references/08-configuration/settings.md`: **`prUrlTemplate`** setting with `{owner}` / `{repo}` / `{number}` substitutions for non-GitHub remotes. Notes `--from-pr` now accepts GitLab/Bitbucket/GHES URLs (release 2.1.119+).
- `references/09-testing/debugging.md`: leading cross-link to the upstream **Debug Your Config** guide as the primary reference for runtime-introspection slash commands (`/context`, `/memory`, `/doctor`, `/hooks`, `/mcp`, `/skills`, `/permissions`, `/status`). Note about `CLAUDE_CODE_HIDE_CWD` for sharing terminal logs and screenshots without leaking customer/internal paths.
- `references/08-configuration/permission-modes.md`: cross-link to upstream **Auto Mode Config** guide (the full `autoMode` schema is now standalone — was previously embedded in the Permissions doc).
- `references/02-philosophy/core-philosophy.md`: new **"Env Vars Relevant to Plugin Authors"** callout — `CLAUDE_CODE_HIDE_CWD`, `DISABLE_UPDATES` vs `DISABLE_AUTOUPDATER`, `CLAUDE_CODE_FORK_SUBAGENT` (experimental). Explicitly out of scope: terminal config, OTEL, voice (end-user concerns).

### Changed — Skill body, version, descriptions (Track G)
- `skills/plugin-creation/SKILL.md`: hook-event count 26 → 28, hook handler types 3 → 5 (`command` / `http` / `mcp_tool` / `prompt` / `agent` with `agent` marked experimental). New key events listed: `PostToolBatch`, `UserPromptExpansion`. References block updated for new themes.md and the v3.3.0 deltas in plugin-json/marketplace-json/settings.
- `.claude-plugin/plugin.json`: `version` 3.2.1 → **3.3.0**; description updated to mention the 28 events, `mcp_tool` handler, plugin themes, `userConfig`, cross-marketplace dependencies.
- Root `marketplace.json`: `plugin-creation-tools` entry version 3.2.1 → **3.3.0** with synced description; `metadata.version` 1.14.25 → 1.14.26 (patch bump for plugin-version pointer update per `feedback_marketplace_version_bump`).
- `agents/plugin-structure-auditor.md`: Architecture section gains the `mcp_tool` migration-candidate flag (shell handlers shelling out to call MCP tools — e.g., `claude mcp call …` — should switch to `type: "mcp_tool"`).

### Deferred — out of scope for this cycle
- **Voice / interactive-mode deltas** (Gap 9 in findings): `voiceEnabled` → `voice.enabled` / `voice.mode` schema change and voice tap mode are end-user terminal config, not plugin authoring. PCT does not document end-user voice settings — no change.
- **Monitoring / OTEL span schema** (Gap 10 in findings): the +315 lines on the upstream Monitoring guide are useful reference, but PCT does not currently teach OTEL instrumentation for plugins. The Agent SDK observability page (`references/11-agent-sdk/observability.md`) was authored against the prior snapshot and remains consistent with the new schema (no contradicting facts). Defer until we add a "monitor your plugin" track.

### Notes
- Doc baseline: `~/workspace/claude_memory/guides/claude/` at commit `c142d14`. Plan + findings (now deleted from `claude_docs/improvements/`) lived alongside this PR for review.
- Per `feedback_no_half_measures`: the `marketplace-json.md` cross-marketplace section was incorrect (used `strictKnownMarketplaces`, the wrong field). Replaced wholesale with the correct `allowCrossMarketplaceDependenciesOn` model rather than patching around the existing text.

## [3.2.1] - 2026-04-21

### Changed
- **`agents/plugin-structure-auditor.md`** — narrowed scope to three areas (Architecture, Cross-Component Consistency, Performance). Distribution Readiness, Dependency Review, and SDK Rename Review removed — those checks are handled by `/plugin-creation-tools:validate` and duplicating them caused output truncation (report ran past the response budget and got cut off mid-section in live runs).
- Output format tightened: max 3 bullets per section, scoring now `/30` total, added explicit "do not split across turns" instruction and a "next step" line pointing to `/validate` for distribution checks.
- Description updated to steer users to `/validate` for documentation-only or small content changes (the auditor is now reserved for structural changes — new agents, skills, hooks, or layout refactors).

### Why
Live run on a 15-line heredoc CHANGELOG change in another plugin produced two consecutive truncated reports. Root cause: 7 sections × verbose findings exceeded the single-response output budget. Fix splits responsibility cleanly — `/validate` owns distribution/syntax checks, auditor owns structural judgement.

## [3.2.0] - 2026-04-20

### Added — Hooks (Track B)
- **4 new hook events** documented: `PermissionDenied`, `CwdChanged`, `FileChanged`, `TaskCreated` (total now 26).
- **`if` pre-spawn filter** section in `writing-hooks.md` — avoids the "spawn a process just to check and exit 0" anti-pattern on tool events.
- **Permission Mode Interaction** section in `writing-hooks.md` covering `default`/`acceptEdits`/`plan`/`auto`/`dontAsk`/`bypassPermissions`.
- New hook patterns: FileChanged watch-mode lint, PermissionDenied retry/escalate, TaskCreated tracking.
- `asyncRewake` handler field and `once` frontmatter-scoping caveat.
- `hooks.json.template` demonstrates the `if` field.

### Added — Configuration (Track C)
- **Plugin Dependencies** (`08-configuration/plugin-json.md`): `dependencies` array, semver ranges, `{name}--v{version}` tag convention, intersection resolution, and the three official error codes (`range-conflict`, `dependency-version-unsatisfied`, `no-matching-tag`).
- **Marketplace-author responsibilities** (`08-configuration/marketplace-json.md`): tagging releases, allowlisting cross-marketplace dependencies via `hostPattern`/`pathPattern`, validator behavior.
- **NEW `08-configuration/permission-modes.md`**: full reference for the six permission modes, hook-behavior-per-mode table, auto-mode classifier rules, subagent inheritance, protected paths, plugin-author guidance.
- Cross-links from `05-agents/writing-agents.md` and `05-agents/agent-tools.md` to `permission-modes.md`. Plugin-agent caveat noted (`permissionMode`/`hooks`/`mcpServers` silently ignored in plugin-packaged agents).

### Added — Overview + Testing + Philosophy (Track D)
- **NEW `01-overview/claude-directory.md`**: canonical layout for `~/.claude/` and `<project>/.claude/`, precedence tables (settings; skills/commands/hooks; subagents; MCP), and `--add-dir` interaction.
- **NEW `09-testing/errors.md`**: plugin-loading errors (dependencies + manifest) and runtime errors plugin authors hit (auto mode, auth, usage limits, request errors). Validator-alignment checklist.
- **`02-philosophy/core-philosophy.md`**: replaced the stale 2%/16K skill-description budget claim with upstream-documented numbers — **1% dynamic budget**, **8,000-char fallback**, **1,536-char per-entry cap**, **500-line SKILL.md soft cap**, **5,000-tokens-per-skill** and **25,000 tokens total** post-compaction. Added "what survives compaction" table.

### Added — Agent SDK directory (Track A)
New `references/11-agent-sdk/` directory (9 files):
- `overview.md`: when to use SDK vs CLI vs Anthropic Client SDK; `.claude/` loading defaults; authentication; plugin-author testing pattern.
- `migration.md`: Claude Code SDK → Agent SDK. Package/type renames, `ClaudeCodeOptions` → `ClaudeAgentOptions`, two breaking default changes (minimal system prompt, no `.claude/` auto-load), and a grep-checklist.
- `custom-tools.md`: `tool()` / `@tool`, `createSdkMcpServer`, `mcp__{server}__{tool}` naming, optional parameters per language, `isError`, `readOnlyHint` for parallel execution, three plugin-author patterns.
- `subagents-sdk.md`: field parity between Markdown frontmatter and `AgentDefinition`, what subagents inherit, automatic vs explicit invocation, dynamic factory pattern, sessions.
- `permissions.md`: evaluation order (hooks → deny → mode → allow → canUseTool), `allowed_tools` vs `disallowed_tools` with `bypassPermissions` gotcha, `canUseTool` callback patterns.
- `structured-outputs.md`: `output_format` with JSON Schema, Zod/Pydantic generation, validator-output-contract pattern, paper-test harness pattern.
- `tool-search.md`: `ENABLE_TOOL_SEARCH` modes, 30–50 tool accuracy threshold, optimization guidance, the <10-tool opt-out case.
- `observability.md`: OpenTelemetry-via-CLI-child-process model, three signals (metrics/logs/traces), env-merge-vs-replace semantics across languages, sensitive-data controls.
- `agent-loop.md`: 5-step loop, 5 message types with Python/TS access patterns, budget caps, `effort` pass-through, context-window behavior through compaction.

Global rename pass (`Claude Code SDK` → `Agent SDK`): no stale references existed outside of intentional historical mentions in `migration.md`.

### Added — Distribution (Track E)
- **NEW `10-distribution/review-md-v2.md`**: the two-file model (`CLAUDE.md` vs `REVIEW.md`), what to tune, 40-line starter `REVIEW.md` scoped to plugin-repo concerns, `/ultrareview` callout.
- **NEW `10-distribution/routines-auto-validate.md`**: GitHub-triggered Routine that runs `/plugin-creation-tools:validate` on every PR — full creation walkthrough and footgun list. Closes the loop on the repeated "forgot to validate" feedback.
- Cross-links from `packaging.md` to both new files; fixed broken relative path to `09-testing/debugging.md`.

### Changed — Plugin self-improvement (Track F)
- **`commands/validate.md`**: added Plugin Dependencies checks (dependencies array shape, semver syntax, cross-marketplace allowlist, official error names). Expanded hook-event recognition list to all 26 events. Added quoted-`$CLAUDE_PROJECT_DIR` check. Added best-practice suggestion: broad tool-event matchers should use the `if` field. Added version-drift check between `plugin.json` and root `marketplace.json`. Added SDK-rename checks (`Claude Code SDK`, `ClaudeCodeOptions`) and imperatives/`!`-injection preservation checks.
- **`agents/skill-quality-reviewer.md`**: expanded rubric to include trigger-phrase enumeration, concrete action verbs, synonym coverage, quoted-YAML form, the 1,536-char per-entry cap. Added a "regression flags" section (stripped `PROACTIVELY`/`MUST`/`NEVER` imperatives; dropped `` !`command` `` dynamic-context injections; trimmed domain-intelligence prose; weakened triggers). Added "rename flags" for stale SDK references.
- **`agents/plugin-structure-auditor.md`**: added Performance-Review item for broad hook matchers without `if`. Added new sections for Dependency Review and SDK Rename Review.

### Notes
- Plan deviation: upstream Skills guide states the dynamic skill-description budget is **1% / 8,000 chars** (per-entry cap **1,536 chars**), not the 2%/16K the planning doc initially listed. Used upstream numbers per the plan's "Upstream doc wins" rule.

## [3.1.0] - 2026-04-08

### Changed
- **PreCompact hook** — No longer dumps plugin.json metadata and CLAUDE.md content into compaction. Now outputs instructions for Claude to read plugin files on demand, reducing compaction bloat.

## [3.0.0] - 2026-03-20

### Breaking Changes
- **`"type"` → `"source"` in marketplace source objects** — All source type discriminators changed from `"type"` to `"source"`. Affects marketplace.json plugin entries. Old: `{"type": "github", ...}`. New: `{"source": "github", ...}`.
- **GitHub source format combined** — Old: `{"owner": "org", "repo": "plugin-repo"}`. New: `{"repo": "org/plugin-repo"}`. The `owner` field is removed.

### Added
- **4 new hook events**: `StopFailure` (API error notification), `PostCompact` (after compaction), `Elicitation` (MCP user input interception), `ElicitationResult` (after user responds to MCP elicitation). Total hook events: 22 (was 18).
- **`${CLAUDE_PLUGIN_DATA}` environment variable**: Persistent data directory surviving plugin updates (`~/.claude/plugins/data/{id}/`). Added to plugin-json.md, writing-hooks.md with Persistent Dependencies Pattern.
- **`effort` frontmatter field**: Optional field for skills and agents — values: `low`, `medium`, `high`. Controls reasoning effort.
- **`CLAUDE_CODE_PLUGIN_SEED_DIR`**: Container/CI pre-seeding for plugins without runtime git clones. Added to packaging.md.
- **`FORCE_AUTOUPDATE_PLUGINS` env var**: Keep plugin auto-updates enabled while disabling Claude Code self-updates.
- **Plugin agent security restriction** documented: `hooks`, `mcpServers`, `permissionMode` silently ignored in plugin-packaged agents.
- **`hostPattern` and `pathPattern`** in `strictKnownMarketplaces` — regex-based allowlist entries.
- **9 new validation rules**: source key, http hook restriction, marketplace owner required, kebab-case names, reserved names update, path traversal, duplicate names, YAML frontmatter, hooks.json hard-blocking.
- **CLI additions**: `--keep-data` flag on uninstall, `remove`/`rm` aliases, `--scope managed` for update.
- **Reserved marketplace name**: `knowledge-work-plugins` added.
- **Marketplace plugin entry passthrough fields**: `homepage`, `repository`, `license`, `commands`, `agents`, `hooks`, `mcpServers`, `lspServers`.

### Fixed
- **`marketplace.json` `owner` field** marked as required (was incorrectly optional)
- **`plugin.json` manifest** documented as optional (was incorrectly required)
- **`http` hooks restriction** — cannot be placed in `hooks.json`, settings-only
- **`commands/` directory** labeled as legacy — `skills/` recommended for all new work
- **`settings.json`** added to standard plugin directory structure
- **URL-based marketplace limitation** warning added — relative paths don't work

### Changed
- All examples and templates updated for `"source"` key and combined GitHub repo format
- validate command updated with 9 new rules
- init_plugin.py, package_skill.py, validate_skill.py updated for new schemas

## [2.4.0] - 2026-03-17

### Added
- **`statusMessage` return field** in hook-events.md PreToolUse — custom status text displayed in Claude Code status line during tool execution, with JSON return format example
- **`once` field** in hook-events.md — fire a hook only once per session; documented with use cases and example
- **Hook execution order** clarification — hooks within a matcher group run in parallel, not sequentially
- **Hook timeout behavior** — what happens when hooks time out (process killed, treated as exit 0)
- **3 new hook patterns** in hook-patterns.md: Status Message Pattern, One-Time Hook Pattern, Three-Way Decision Pattern (`approve`/`deny`/`ask`)
- **`dontAsk` permission mode** in agent-tools.md — auto-deny all permission prompts for non-interactive agents
- **`outputStyles` field** in plugin-json.md and output-config.md — custom output style paths in plugin.json
- **`skills` and `settings` fields** in plugin-json.md Component Path Fields table
- **`strictKnownMarketplaces`** in settings.md — enterprise managed setting to restrict marketplace additions with host/path pattern matching
- **Reserved marketplace names** in marketplace-json.md — 7 names reserved by Anthropic that cannot be used

### Fixed
- **agent-tools.md**: Replaced invalid `ignore` permission mode with correct `dontAsk` mode (5 modes: default, acceptEdits, dontAsk, bypassPermissions, plan)
- **hook-events.md**: Expanded `ask` decision value from 1-line mention to full explanation of user escalation UX

## [2.3.1] - 2026-03-15

### Added
- **PreCompact hook**: Preserves active plugin context (name, version, component counts) before conversation compaction

## [2.3.0] - 2026-03-12

### Added
- **2 new shipped agents** for plugin quality assurance:
  - `agents/skill-quality-reviewer.md` — reviews SKILL.md description, structure, and progressive disclosure with A/B/C/D scoring
  - `agents/plugin-structure-auditor.md` — deep structural audit covering architecture, consistency, distribution readiness, security, and performance
- **4 new hook events** documented: `InstructionsLoaded`, `ConfigChange`, `WorktreeCreate`, `WorktreeRemove` (total now 18 events)
- **HTTP hook type** documentation (`type: "http"`) — POST event JSON to a URL with header env var interpolation
- **Hook fields**: `"ask"` decision value for PreToolUse (note: `statusMessage` and `once` were identified but not added to reference files until v2.4.0)
- **Agent frontmatter fields**: `isolation: worktree`, `background: true`, `maxTurns`, `mcpServers`, `Agent(type)` tool syntax
- **Full model IDs** in agent docs: `claude-opus-4-6`, `claude-sonnet-4-6`, `claude-haiku-4-5`
- **Skill frontmatter fields**: `hooks` (skill-scoped lifecycle), `argument-hint` (autocomplete hints)
- **String substitutions**: `$ARGUMENTS[N]`/`$N`, `${CLAUDE_SKILL_DIR}`, `${CLAUDE_SESSION_ID}`
- **Context budget** documentation: 2% of context window / 16K-char fallback, `SLASH_COMMAND_TOOL_CHAR_BUDGET` override
- **Skills hot-reload** from `--add-dir` directories
- **Marketplace source types**: `git-subdir` (monorepo sparse clone), `npm`, `pip`
- **Marketplace fields**: `ref`/`sha` pinning, `strict` mode, `tags`, `metadata.pluginRoot`
- **Private repository authentication** docs (GITHUB_TOKEN, GITLAB_TOKEN, BITBUCKET_TOKEN)
- **Official marketplace submission URLs**: `claude.ai/settings/plugins/submit`, `platform.claude.com/plugins/submit`
- **Release channels pattern** (stable/latest with different marketplace files)
- **`strictKnownMarketplaces`** managed setting documentation
- **`settings.json`** at plugin root documentation (agent key)
- **`/reload-plugins`** command for hot-reloading plugins during development
- **Pushy descriptions** guidance — Anthropic insight on combating undertriggering
- **Degrees of freedom** concept in skill patterns — high/medium/low freedom levels
- **Eval-driven development** approach in creation-approaches.md
- **Agent team operations**: display modes, plan approval, task dependencies, quality gates, `/batch` skill
- **Grader/comparator agent patterns** from Anthropic's skill-creator

### Changed
- SKILL.md description made "pushier" with more trigger phrases and negative scope
- SKILL.md now injects dynamic context: `!ls .claude-plugin/ 2>/dev/null`
- Command descriptions (create, add-component, validate) updated with trigger phrases
- Validate command now runs with `context: fork` to isolate output
- Hook event count updated from 14 to 18 throughout
- Default command hook timeout corrected from 30s to 600s
- Hook input fields expanded: `agent_id`, `agent_type`, `last_assistant_message`, `agent_transcript_path`
- Core philosophy updated with specific context budget numbers (2%/16K)
- Full-featured example updated to showcase hooks frontmatter, model routing, and context fork

### Updated Templates
- Agent template: added isolation/background/maxTurns/mcpServers fields
- Hooks template: added HTTP hook type, new events, statusMessage/once
- Marketplace template: added git-subdir/npm/pip sources, tags, ref/sha pinning
- Plugin.json template: added settings.json reference

## [2.2.0] - 2026-02-11

### Added
- **Anthropic official skill standards** reference (`references/03-skills/anthropic-skill-standards.md`) — distilled from "The Complete Guide to Building Skills for Claude" (Jan 2026)
- **Five skill patterns** reference (`references/03-skills/skill-patterns.md`) — Sequential Workflow, Multi-MCP Coordination, Iterative Refinement, Context-Aware Tool Selection, Domain-Specific Intelligence
- **Triggering test methodology** in testing.md — should-trigger / should-NOT-trigger framework with 90% trigger rate target
- **Quantitative success metrics** in testing.md — tool call targets, 0 failed API calls goal, consistency benchmarks
- **Use case categories** in creation workflow Step 1 — Document & Asset Creation, Workflow Automation, MCP Enhancement
- **Structured iteration signals** in creation workflow Step 6 — undertriggering, overtriggering, execution issue diagnosis
- **MCP + Skills synergy** section in mcp-overview.md — value proposition for MCP builders
- **API and organization-level distribution** paths in packaging.md
- **`compatibility` frontmatter field** documentation (1-500 chars, environment requirements)
- **`metadata` suggested keys** (author, version, mcp-server, category, tags, documentation, support)
- **Negative trigger pattern** in description-patterns.md — "Do NOT use for" scope boundaries
- **Three-part description structure** from Anthropic guide — `[What] + [When] + [Capabilities]`
- **Examples and Troubleshooting sections** in SKILL.md template
- **XML tag validation**, examples check, error handling check, compatibility check in validate command
- **Agent team patterns** in agent-patterns.md — competing perspectives (debate), competing hypotheses (investigation), parallel task execution, team composition guidelines, implementation guidance

### Fixed
- Removed README.md from inside skill directory (violated own rules and Anthropic standards)

### Changed
- Description pattern formula now shows both trigger-first and three-part structures
- Validate command expanded with 6 additional checks
- `allowed-tools` field now includes syntax example

## [2.1.0] - 2026-02-07

### Added
- **3 slash commands** for plugin discoverability:
  - `commands/create.md` — create a new plugin with selected components
  - `commands/validate.md` — validate plugin structure, frontmatter, and best practices
  - `commands/add-component.md` — add a skill, command, agent, or hook to an existing plugin
- **Lean documentation principle** added as 6th iron law in `core-philosophy.md`
- **Plugin project setup guidance** in SKILL.md (`.claude/rules/`, CLAUDE.md, README/CHANGELOG placement)

### Updated (references synced against comprehensive guides)
- `writing-agents.md` — added memory field (user/project/local), model selection, disallowedTools, hooks in frontmatter
- `agent-tools.md` — added disallowedTools, MCP tool access, expanded tool list
- `hook-events.md` — expanded from 10 to 14 events, added MCP matcher syntax, matcher values per event
- `writing-hooks.md` — corrected to 3 hook types (command/prompt/agent), added async hooks, MCP matchers
- `writing-skillmd.md` — added model, context, disable-model-invocation, user-invocable, dynamic context injection, ultrathink
- `component-comparison.md` — added CLAUDE.md and Agent Teams, context cost considerations, 6-step decision process
- `plugin-json.md` — added mcpServers, lspServers, path substitution, installation scopes, plugin caching
- `testing.md` — added CLI automation section (--output-format json, -p flag, session resumption, --allowedTools)

### Changed
- Exited beta — version 2.0.0-beta.4 → 2.1.0
- Removed [BETA] prefix from plugin description
- SKILL.md updated with guidance for new features: memory, model routing, context injection, hook handler types

## [2.0.0-beta.4] - 2026-01-09

### Fixed
- **Skill initialization error**: Fixed parsing issue in SKILL.md where inline code containing special characters (backtick + exclamation mark, backtick + at-sign) was causing bash command execution errors during skill loading
  - Changed `` `!` prefix`` to "exclamation mark"
  - Changed `` `@` prefix`` to "at-sign"
  - This resolves the "command not found: prefix" error on skill invocation

## [2.0.0-beta.3] - 2025-12-31

### Added
- **6-step creation process**: Structured workflow for manual skill creation
  - Added to `references/03-skills/creation-approaches.md`
  - Step 1: Understand skill with concrete examples
  - Step 2: Plan reusable skill contents
  - Step 3: Initialize skill (run init_skill.py)
  - Step 4: Edit skill (implement resources + write SKILL.md)
  - Step 5: Package skill (run package_skill.py with validation)
  - Step 6: Iterate based on real usage
  - Includes decision matrices, examples, and completion criteria for each step

### Enhanced
- **Plugin vs skill level distinction**: Clarified README/CHANGELOG placement
  - Updated `references/02-philosophy/anti-patterns.md`
  - ✅ README.md, CHANGELOG.md, LICENSE **required** at plugin root (for humans)
  - ❌ README.md, CHANGELOG.md **forbidden** inside skills (AI-only files)
  - Added visual examples showing correct vs incorrect structure
  - Explains why: Plugin docs for humans, skill SKILL.md for AI

### Attribution
- 6-step creation process adapted from Anthropic's `skill-creator` skill (document-skills@anthropic-agent-skills)
- Plugin vs skill level distinction concept from Anthropic's skill-creator best practices
- We preserve unique value: multi-component coverage (commands, agents, hooks, MCP) not in Anthropic's skill-creator

### Context
Aligned with Anthropic's official skill-creator guidance while preserving our multi-component (skills, commands, agents, hooks, MCP) coverage. The core philosophy (Claude is already smart, context window as public good, degrees of freedom) was already present in v2.0.0-beta.2.

## [2.0.0-beta.2] - 2025-12-08

### Added
- **Cross-platform hooks**: Polyglot wrapper pattern for Windows/macOS/Linux compatibility
  - `references/06-hooks/cross-platform-hooks.md` documentation
  - `templates/hooks/run-hook.cmd.template` wrapper template
  - Uses Git Bash on Windows, native bash on Unix
- **Example plugins**: Two working examples for reference
  - `examples/simple-greeter-plugin/` - Minimal plugin with one skill
  - `examples/full-featured-plugin/` - Complete plugin with skill, commands, and hooks
- Examples section in SKILL.md

### Changed
- Bumped version to 2.0.0-beta.2

### Credits
- Cross-platform hook pattern adapted from superpowers-developing-for-claude-code by Jesse Vincent (MIT license)

## [2.0.0-beta.1] - 2025-12-08

### Added
- **Output configuration**: `init_plugin.py` now creates output management hooks
  - SessionStart hook creates `claude-outputs/` directory structure
  - SessionEnd hook cleans temp files
  - PostToolUse hook logs operations
  - `CLAUDE_ENV_FILE` used to persist `PLUGIN_OUTPUT_DIR` for session
- Output structure: `logs/`, `artifacts/`, `temp/` directories
- **CLI reference**: `references/09-testing/cli-reference.md`
- **Complete examples**: `references/10-distribution/complete-examples.md`
- Plugin-level decision frameworks in `decision-frameworks.md`:
  - Should I Create a Plugin?
  - Single Plugin or Multiple?
  - Which Components Do I Need?
- `init_plugin.py` script for initializing plugins with any component combination

### Changed
- Marked as [BETA] - indicates active development
- `testing.md` expanded to cover all component types (commands, agents, hooks, MCP)
- `writing-commands.md` added `disable-model-invocation` explanation
- `quick-reference.md` expanded with all 10 hook events and CLI section
- `settings.md` added plugin-specific configuration patterns (env vars workaround)
- `writing-skillmd.md` added gerund naming, testing, and time-sensitive info guidance
- `mcp-overview.md` added fully qualified tool name requirement
- `testing.md` added workflow checklist pattern and multi-model testing

### Notes
- Recommended to keep alongside deprecated skill-creation-tools during beta
- Users can migrate when beta stabilizes

## [2.0.0] - 2025-12-08

### Added
- **BREAKING**: Renamed plugin from `skill-creation-tools` to `plugin-creation-tools`
- **Commands documentation**: 3 new guides for slash command creation
  - `references/04-commands/writing-commands.md`
  - `references/04-commands/command-patterns.md`
  - `references/04-commands/command-arguments.md`
- **Agents documentation**: 3 new guides for custom subagent creation
  - `references/05-agents/writing-agents.md`
  - `references/05-agents/agent-patterns.md`
  - `references/05-agents/agent-tools.md`
- **Hooks documentation**: 3 new guides for event handler configuration
  - `references/06-hooks/writing-hooks.md`
  - `references/06-hooks/hook-events.md`
  - `references/06-hooks/hook-patterns.md`
- **MCP overview**: `references/07-mcp/mcp-overview.md`
- **Configuration guides**: 4 new guides
  - `references/08-configuration/plugin-json.md`
  - `references/08-configuration/marketplace-json.md`
  - `references/08-configuration/output-config.md`
  - `references/08-configuration/settings.md`
- **Testing guide**: `references/09-testing/debugging.md`
- **Distribution guides**: 3 new guides
  - `references/10-distribution/packaging.md`
  - `references/10-distribution/marketplace.md`
  - `references/10-distribution/versioning.md`
- **Overview files**: 6 new component overviews in `references/01-overview/`
- **Templates**: 8 template files for all component types
- **New SKILL.md**: Comprehensive guide covering all 5 component types

### Changed
- Restructured references into numbered sections (01-overview through 10-distribution)
- Reorganized existing skill guides into `references/03-skills/`
- Philosophy guides moved to `references/02-philosophy/`

### Migration
- Users should uninstall `skill-creation-tools` and install `plugin-creation-tools`
- Or keep both during transition (skill-creation-tools marked deprecated)

## [1.x] - Legacy

Previous versions were released as `skill-creation-tools` (skills-only guide).
See skill-creation-tools for historical changelog.
