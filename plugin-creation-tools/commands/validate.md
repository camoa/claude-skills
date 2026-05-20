---
description: Validate plugin structure, frontmatter, and best practices. Use when user says "validate plugin", "check plugin", "audit plugin", "verify plugin", "is my plugin correct", or before distributing/publishing a plugin.
allowed-tools: Read, Glob, Grep
argument-hint: "[plugin-path] [--fix] [--strict]"
context: fork
---

# Validate Plugin

Validate a plugin's structure and components against best practices.

## Steps

1. Determine plugin path: use `$1` if provided, otherwise detect from current directory
2. Parse flags: `--fix` enables auto-migration for rules tagged below; `--strict` promotes warnings to errors for CI gating
3. Find `.claude-plugin/plugin.json` to confirm it's a plugin root
4. Run all validation checks below
5. If `--fix` is set, after the report ask the user to confirm before applying any auto-migration. Apply each fix atomically (write-tempfile-then-rename) and append an entry to `.claude-plugin/.validate-fixes.log`
6. Report results as a structured checklist

## Auto-fix (`--fix`)

The validator gains an opt-in `--fix` flag that performs **only** mechanical, reversible migrations. Every fix:

- Is logged to `.claude-plugin/.validate-fixes.log` (append-only) with timestamp + rule ID + summary
- Writes atomically (tempfile + rename), so a failure leaves the original intact
- Is reversible via `git diff` / `git restore`
- Requires user confirmation before any file is changed in this release

Rules that ship with `--fix` in v3.5.0: **H05**, **H06**, **H10**. Other auto-fixable rules (M07/M08/M09/M10, C05/C06, etc.) land in later releases.

Log entry format:

```
2026-05-19T14:22:01Z  H05  hooks/hooks.json: SessionStart → exec form (added "args": [])
2026-05-19T14:22:01Z  H10  scripts/post-write.sh: updatedMCPToolOutput → updatedToolOutput
```

## Validation Checks

### Plugin Structure
- [ ] `.claude-plugin/plugin.json` exists and is valid JSON
- [ ] `name` field present in plugin.json
- [ ] `name` is kebab-case — if not, warn: "Plugin name '[X]' is not kebab-case. Claude.ai marketplace sync requires kebab-case names."
- [ ] `version` follows semver
- [ ] `description` present and not placeholder text
- [ ] README.md exists at plugin root
- [ ] CHANGELOG.md exists at plugin root
- [ ] **Info** (not warning) if a `CLAUDE.md` is present at the plugin root: "Plugin-root `CLAUDE.md` is NOT loaded as project context. Instructions belong in a skill — put them in `skills/<name>/SKILL.md` so they reach Claude. The file is fine to keep as authoring reference (this plugin uses it that way)."

#### ST04 — Redundant `skills: ["./"]` on a single-skill-at-root plugin (info)

When a plugin has all three of: (a) `SKILL.md` at the plugin root, (b) no `skills/` subdirectory, AND (c) a manifest `skills` field set to exactly `["./"]` (or `"./"`), emit info:

> "This plugin is auto-loaded as a single-skill plugin (v2.1.142+) when `SKILL.md` lives at the root and no `skills/` subdirectory exists. The `\"skills\": [\"./\"]` field is redundant — Claude Code discovers the root `SKILL.md` automatically. The field still works; you can remove it to declutter the manifest."

#### ST05 — Manifest references a folder that doesn't exist (warn)

For every path in `commands`, `agents`, `skills`, `outputStyles`, `experimental.themes`, `experimental.monitors`, resolve it against the plugin root and check the target exists. Missing target → warn:

> "Plugin manifest references `<path>` which does not exist under the plugin root. Common cause: typo (`agents/` ↔ `agents`, `agnets/`, `commnads/`) or a folder that was renamed but not updated in `plugin.json`."

Skip glob-style entries (`./commands/*.md`) — those are evaluated at load time and an empty match is not an error.

#### ST06 — Manifest path overrides a populated default folder (info)

For each "Replaces the default" field (`commands`, `agents`, `outputStyles`, `experimental.themes`, `experimental.monitors`), if the manifest sets a **custom** path that is NOT `./<default>/` or a sub-path of `./<default>/`, AND the default folder at `./<default>/` exists AND contains files matching the expected extension, emit info:

> "Plugin manifest overrides `<field>` to `<custom-path>` but `<default-folder>/` is also populated. Those files will be **silently ignored** at runtime — the `<field>` field replaces the default for this component type (only `skills` adds). v2.1.140+ flags this in `/doctor`, `claude plugin list`, and the `/plugin` detail view. Either remove the default folder, or include it in the manifest array: `\"<field>\": [\"./<default>/\", \"<custom-path>\"]`."

Heuristic exclusion: don't fire when the manifest path resolves into the default folder (e.g. `"commands": ["./commands/deploy.md"]`) — that's the explicit-address case upstream documents as not warning-worthy.

### plugin.json Schema Migration (soft-breaking — `experimental.*`)
- [ ] **Warning** if top-level `themes` or `monitors` is set in `plugin.json`: "`themes` / `monitors` should live under `experimental.*`. `claude plugin validate` flags this and a future release will require the nested form." Offer an auto-migration diff that wraps both keys under an `experimental` object (preserve existing values, deduplicate if `experimental.themes` / `experimental.monitors` is already partially set).
- [ ] **Warning** if `agents` is a bare string path: "The `agents` field is array-only. Wrap the path in an array: `\"agents\": [\"./agents/foo.md\"]`."
- [ ] **Info** (not warning) if `commands` or `skills` is a bare string path: "The array form is preferred — `\"commands\": [\"./cmd.md\"]`. The string form still loads but is being phased out."
- [ ] **Info** if `$schema` is missing: "Consider adding `\"$schema\": \"https://json.schemastore.org/claude-code-plugin-manifest.json\"` for editor autocomplete. Claude Code ignores the field at load time."
- [ ] **Info** when `channels` is declared in `plugin.json`: each entry must have a `server` field that matches a key in the plugin's `mcpServers` (or an externally-known MCP server name). Flag a warning if `server` references an undeclared MCP server. Per-channel `userConfig` follows the same schema as the top-level `userConfig` — apply the same legacy/required checks.
- [ ] **Info** when a `bin/` directory is present at the plugin root: confirm files are executable (warn on non-executable entries — they will appear on `PATH` but fail to run). Auto-discovered, no manifest entry needed.

### Plugin settings.json (if present at plugin root)
- [ ] Valid JSON.
- [ ] Recognized keys only: `agent`, `subagentStatusLine`. Unknown keys are silently ignored upstream (forward-compatible) — emit **info** noting the value will be ignored at runtime.
- [ ] `agent` value matches an agent file under `agents/` (warn on dangling reference).
- [ ] `subagentStatusLine` matches the upstream status-line schema (object with `type` + `command`/`script`, or string command).

### Marketplace (`marketplace.json` if present)
- [ ] `owner` field is present and non-empty (error if missing)
- [ ] Marketplace `name` is not in the reserved list: `claude-code-marketplace`, `claude-code-plugins`, `claude-plugins-official`, `anthropic-marketplace`, `anthropic-plugins`, `agent-skills`, `life-sciences`, `knowledge-work-plugins`
- [ ] Plugin source objects use `"source"` as the discriminator key — flag `"type"` as an error (e.g., `{"source": "github", ...}` not `{"type": "github", ...}`)
- [ ] No `..` path traversal in source paths (error if found)
- [ ] No duplicate plugin names within the plugins array (error if found)
- [ ] Each plugin's `version` in the marketplace entry matches the `version` in its `.claude-plugin/plugin.json` (error if drifted — reference `feedback_marketplace_json`)

### Plugin Dependencies (if `dependencies` is declared in `plugin.json`)
- [ ] `dependencies` is an array
- [ ] Each entry is either a bare string (plugin name) or an object with a required `name` field
- [ ] Object entries with a `version` field use valid semver-range syntax (`~2.1.0`, `^2.0`, `>=1.4`, `=2.1.0`, hyphen ranges, `||` unions) — flag `range-conflict` on invalid syntax
- [ ] Object entries with a `marketplace` field (cross-marketplace dependency): flag as **error** if the root marketplace's `marketplace.json` does not list the referenced marketplace name in `allowCrossMarketplaceDependenciesOn`. Error message: "Cross-marketplace dependency on `<marketplace-name>` requires the root marketplace.json to include `<marketplace-name>` in `allowCrossMarketplaceDependenciesOn`. Trust does not chain — only the root marketplace's allowlist is consulted." Distinct from `strictKnownMarketplaces` (which lives in user/managed `settings.json` and gates marketplace install location, not dependency trust).
- [ ] Pre-release ranges are only matched when the range opts in with a pre-release suffix (e.g. `^2.0.0-0`)
- [ ] Use official error names when reporting: `range-conflict`, `dependency-version-unsatisfied`, `no-matching-tag` (align with `claude plugin list` output)

### Skills (for each skill in `skills/*/`)
- [ ] `SKILL.md` exists with valid YAML frontmatter — invalid frontmatter causes skill to load with no metadata at runtime
- [ ] Frontmatter has `name` (hyphen-case, max 64 chars)
- [ ] Frontmatter has `description` (starts with "Use when" or three-part structure, max 1024 chars)
- [ ] Description includes WHAT it does AND WHEN to use it (trigger conditions)
- [ ] Description uses third person (no "you")
- [ ] No XML angle brackets (< >) in frontmatter (security restriction)
- [ ] `compatibility` field valid if present (1-500 chars)
- [ ] Body is instructions, not documentation (imperative voice)
- [ ] Body under 500 lines
- [ ] Body includes examples section with user scenarios (warning if missing)
- [ ] Body includes troubleshooting/error handling section (warning if missing)
- [ ] Referenced files in `references/` exist
- [ ] Referenced scripts in `scripts/` exist
- [ ] No README.md inside skill directories (belongs at plugin root)
- [ ] **Info** when `allowed-tools` is present on a project-scoped skill (path matches `.claude/skills/`): "`.claude/skills/*` skills with `allowed-tools` only take effect after the workspace trust dialog is accepted. Review the skill carefully before trusting a repository — a skill can grant itself broad tool access this way." (Plugin-shipped skills are not subject to this — their trust is established at install time.)

### Commands (for each `commands/*.md`)
- [ ] Valid YAML frontmatter — invalid frontmatter causes command to load with no metadata at runtime
- [ ] `description` field present
- [ ] `allowed-tools` field present
- [ ] No inline code with backtick+exclamation or backtick+at-sign that could trigger execution

### Agents (for each `agents/**/*.md`)

Plugin `agents/` directories are scanned **recursively** (Claude Code v2.x+). Walk every `.md` file under `agents/`, not just the top level.

- [ ] **A01 (error)** — Valid YAML frontmatter. Invalid frontmatter causes agent to load with no metadata at runtime.
- [ ] **(error)** — `name` field present.
- [ ] **(error)** — `description` field present (includes delegation triggers).
- [ ] **(warn)** — `tools` field present.
- [ ] **(warn)** — `model` field present (haiku, sonnet, opus, or inherit).

#### A02 — Subfolder agents and the scoped id (info)

When an agent file sits under a subfolder of `agents/` (e.g. `agents/review/security.md`), the resulting plugin-scoped id includes the subfolder path — `<plugin>:review:security`, not `<plugin>:security`. If the agent's frontmatter `name` field differs in a way that suggests the author didn't realise the subfolder is part of the id, emit info:

> "Agent `agents/<subfolder>/<file>.md` registers as `<plugin>:<subfolder>:<name>` (the subfolder joins the scoped id in plugins — unlike project/user scopes where the subfolder is purely organizational). Confirm the `name` field is the agent label you want users to invoke after the colons."

Heuristic: only fire when a subfolder is present AND the frontmatter `name` doesn't naturally include the subfolder as a prefix.

#### A03 — Subfolder agent missing `name` frontmatter (warn)

When an agent file sits under an `agents/` subfolder AND its frontmatter is missing the `name` field, emit warn:

> "Agent `agents/<subfolder>/<file>.md` has no `name` frontmatter — it loads with empty metadata at runtime and cannot be invoked by the scoped id. Add `name: <invocation-label>` to the frontmatter."

Flat-layout agents missing `name` are already caught by the general A01-family check; A03 is the subfolder-aware variant that flags the scoped-id breakage explicitly.

### Themes (for each `themes/*.json`)
- [ ] Valid JSON — invalid JSON is an **error** (theme will not load)
- [ ] Required fields present: `name` (display label), `base` (preset name), `overrides` (color-token map). Missing any of the three → **warning** with the field name.
- [ ] `overrides` is an object (not an array or string)
- [ ] No nested directories — `themes/` is a flat folder of `.json` files

### userConfig (in `plugin.json`, if declared)
- [ ] Each entry is an object (not a string or array)
- [ ] Each entry has `type`, `title`, `description` — **info-level** (not warning) when only `description` is present, marking it as the legacy form. Suggest: "Add `type` and `title` for the v2.1.118+ schema; the description-only form still works."
- [ ] `type` value is one of `string`, `number`, `boolean`, `directory`, `file` — flag unknown values as warning
- [ ] If `sensitive: true`, the value is referenced via `${user_config.KEY}` in MCP/LSP/hook configs only (not in skill/agent body — sensitive substitution is blocked there)
- [ ] If `min`/`max` are set, `type` is `number`

### Hooks (`hooks/hooks.json`)

#### H01–H04 — structural

- [ ] **H01 (error)** — Valid JSON structure. Malformed `hooks.json` prevents the entire plugin from loading.
- [ ] **H02 (error)** — Each event name is one of the 29 recognized events: `Setup`, `SessionStart`, `UserPromptSubmit`, `UserPromptExpansion`, `PreToolUse`, `PermissionRequest`, `PermissionDenied`, `PostToolUse`, `PostToolUseFailure`, `PostToolBatch`, `Notification`, `SubagentStart`, `SubagentStop`, `TaskCreated`, `TaskCompleted`, `Stop`, `StopFailure`, `TeammateIdle`, `InstructionsLoaded`, `ConfigChange`, `CwdChanged`, `FileChanged`, `WorktreeCreate`, `WorktreeRemove`, `PreCompact`, `PostCompact`, `Elicitation`, `ElicitationResult`, `SessionEnd`
- [ ] **H03 (error)** — Each hook entry has `type` — one of `command`, `prompt`, `agent`, or `mcp_tool` — plus the matching required fields for that type. `agent` is upstream-marked experimental; flag a one-line info note when used.
- [ ] **H04 (error)** — No `http` type hooks in `hooks.json`. `http` hooks only work in `settings.json` (silently ignored when placed in `hooks.json`).
- [ ] **(error)** — `mcp_tool` handlers: require `server` and `tool`; if `server` is not declared in the plugin's `mcpServers` (and isn't a known external server the user wires up themselves), emit a **warning**: "`mcp_tool` references server `<name>` not declared in this plugin's `mcpServers`. The handler will produce a non-blocking error if the server isn't already connected at runtime."
- [ ] **(warn)** — Command hooks reference executable files (chmod +x missing → warn).
- [ ] **(warn)** — Timeouts are reasonable (< 120s for sync hooks).

#### H05 — Exec form preferred for path placeholders (warn, `--fix`)

For each command hook in `hooks.json` whose `command` string contains a path placeholder (`${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PROJECT_DIR}`, `${CLAUDE_PLUGIN_DATA}`) AND lacks an `args` field, emit:

> "Hook `<event>` handler uses shell form with a path placeholder. Prefer exec form: add `\"args\": []` so the script path is passed as one argument with no quoting needed. See `references/06-hooks/writing-hooks.md` § Exec form vs shell form."

**`--fix`**: Insert `"args": []` as a sibling to `command` in the hook handler. Do **not** auto-migrate when the command string contains shell metacharacters (`|`, `&&`, `||`, `;`, `>`, `<`, `` ` ``, `$(`, glob `*`/`?` outside placeholder, `~`) — those need shell form. In that case, emit the warning but skip the fix and note "shell form required for this command".

#### H06 — Curly-brace placeholders in command strings (warn, `--fix`)

In each `hooks.json` command-string value (and only in command-string values — NOT inside referenced `.sh` script files, where bare `$VAR` is normal bash), flag bare-dollar `$CLAUDE_PROJECT_DIR` / `$CLAUDE_PLUGIN_ROOT` / `$CLAUDE_PLUGIN_DATA` / `$CLAUDE_ENV_FILE` / `$CLAUDE_EFFORT` references:

> "Use `${VAR}` (curly-brace form) instead of bare `$VAR` inside JSON command strings — the curly form is the canonical placeholder syntax and is unambiguous to the placeholder resolver."

**`--fix`**: Literal rewrite of `$CLAUDE_<NAME>` → `${CLAUDE_<NAME>}` inside JSON string values in `hooks.json` only. Skip script files (`.sh`, `.py`, etc.) entirely.

#### H07 — Placeholder quoting (warn)

In **shell form** command hooks (no `args` field), path placeholders inside the `command` string must be wrapped in double quotes (`"${CLAUDE_PROJECT_DIR}"`) — paths with spaces break otherwise. Exec form does not need quoting. Skip this check when `args` is present.

#### H08 — Broad-matcher tool hooks without `if` (info)

Hook handlers on tool events (`PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `PermissionDenied`) with a broad matcher (`*`, `""`, omitted, or `.*`) **may** spawn a process on every tool call. Emit an info-level suggestion (not warn, not error):

> "Consider adding an `if` field to this handler to pre-filter tool calls cheaply — broad-matcher hooks spawn a process on every call. See `references/06-hooks/writing-hooks.md` § The if Field."

This is intentionally **info**, not warn — some authors deliberately spawn on every call (logging, analytics). Don't punish them.

#### H09 — `if` on non-tool events (warn)

The `if` field is only evaluated on tool events (`PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `PermissionDenied`). On any other event, `if` is silently ignored at runtime. Flag as warn so authors notice the dead config.

#### H10 — `updatedMCPToolOutput` → `updatedToolOutput` (warn, `--fix`)

`updatedMCPToolOutput` is the legacy MCP-only field; `updatedToolOutput` supersedes it and works for all tools. Search for `updatedMCPToolOutput` literally in:

1. `hooks.json` JSON output snippets (rare — usually only seen in `command` strings that emit JSON inline).
2. Referenced hook scripts (`.sh`, `.py`, `.js`, etc.) in `hooks/`, `scripts/`, and `bin/`.

Emit warn: "`updatedMCPToolOutput` is the legacy field. Rewrite to `updatedToolOutput` so the hook works for built-in tools too."

**`--fix`**: Literal string rewrite `updatedMCPToolOutput` → `updatedToolOutput` in matched files. Old field still works, but the rename is semantically equivalent.

#### H11 — `Setup` hook recommended for one-time install (info)

Heuristic: if a `SessionStart` hook's referenced script grep-matches **all three** of:

- `mkdir -p` OR an existence check (`[ -d`, `[ -f`, `test -d`, `test -e`)
- A package-install command (`npm install`, `pip install`, `composer install`, `bundle install`, `yarn install`, `pnpm install`, `python -m venv`, `python3 -m venv`)
- A "skip-if-already-installed" pattern (`||` after the check, OR an `if ... else` guard)

Then the script is doing one-time install on every session start. Emit info:

> "This `SessionStart` hook looks like a one-time install (check-then-install pattern). Consider moving the install to a `Setup` hook (fires on `--init-only` / `--init -p` / `--maintenance -p`) and keeping `SessionStart` for per-session state. See `references/06-hooks/hook-events.md` § Setup."

Info-only; don't autofix — moving install logic is a content decision.

#### H12 — Hook writes to `/dev/tty` (error)

For each referenced hook script (any file under `hooks/`, `scripts/`, `bin/` referenced by a command hook), grep for `/dev/tty`. Any match is an **error**:

> "Hook script writes to `/dev/tty`. Command hooks run without a controlling terminal as of Claude Code v2.1.139 — `/dev/tty` writes fail silently. Return `terminalSequence` or `systemMessage` in JSON output instead. See `references/06-hooks/writing-hooks.md` § Terminal Sequences."

Heuristic exclusions: commented-out lines (`# .* /dev/tty`), lines inside a heredoc clearly marked as documentation, lines inside string literals that are JSON output snippets (`"systemMessage": "...wrote to /dev/tty..."`). Best-effort grep — surface the line for human review.

#### H13 — Hook output >10K chars (warn)

Hook output strings (`additionalContext`, `systemMessage`, plain stdout) are capped at 10,000 characters. Heuristic best-effort:

- Heredocs (`<<EOF ... EOF`, `<<'EOF' ... EOF`) inside hook scripts that exceed 10K characters between the open and close marker.
- `cat` of files known to be large (>10K) inside a hook script.
- Large string-literal assignments to a variable used as the only `echo`/`printf`/`jq` output.

Emit warn: "This hook may emit >10K characters. Claude Code truncates oversize output to a file with a preview; large diffs/logs should be written to a side file under `${CLAUDE_PLUGIN_DATA}/` and referenced by path instead."

Best-effort heuristic. Don't autofix.

#### Hooks: legacy / cross-form

- [ ] `$CLAUDE_PROJECT_DIR` / `${CLAUDE_PROJECT_DIR}` / `$CLAUDE_PLUGIN_ROOT` / `${CLAUDE_PLUGIN_ROOT}` / `$CLAUDE_PLUGIN_DATA` / `${CLAUDE_PLUGIN_DATA}` usage is quoted in **shell-form** command strings (covered by H07 above; exec-form hooks need no quoting).

### Best Practices (warnings, not errors)
- [ ] Skills use progressive disclosure (references for details)
- [ ] Skills include scope boundaries / negative triggers in description if broad
- [ ] Agents specify `model:` for cost optimization
- [ ] Skills consider `model:` field
- [ ] Hook scripts are executable (chmod +x)
- [ ] (plugin-creation-tools repo only) Skills cross-checked against `references/03-skills/anthropic-skill-standards.md` — skip this item when validating external plugins that don't ship that reference file
- [ ] No stale `Claude Code SDK` / `claude-code-sdk` / `@anthropic-ai/claude-code` references — the SDK was renamed to Agent SDK (`claude-agent-sdk` / `@anthropic-ai/claude-agent-sdk`). Flag any hit as a warning pointing to `references/11-agent-sdk/migration.md`.
- [ ] Skill descriptions preserve `PROACTIVELY`, `MUST`, and `NEVER` imperatives from prior versions when present (do not auto-strip)
- [ ] Skill descriptions preserve `` !`command` `` dynamic-context injections when present (these are a documented Claude Code feature — do not treat as noise)

## Output Format

```
## Plugin Validation: {name} v{version}

### Errors (must fix)
- ...

### Warnings (should fix)
- ...

### Info
- {n} skills, {n} commands, {n} agents, hooks: {yes/no}, MCP: {yes/no}

### Result: PASS / FAIL
```

## Arguments

- `$1`: Path to plugin directory (optional, defaults to current directory)
