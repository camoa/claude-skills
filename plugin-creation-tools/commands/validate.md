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

Rules that ship with `--fix` (cumulative across releases): **H05**, **H06**, **H10** (v3.5.0); **M06**, **M07**, **M08**, **M09**, **M10**, **C01**, **C02** (v3.6.1). Future releases add more.

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
- [ ] **ST03 (info)** — if a `CLAUDE.md` is present at the plugin root: "Plugin-root `CLAUDE.md` is NOT loaded as project context. Instructions belong in a skill — put them in `skills/<name>/SKILL.md` so they reach Claude. The file is fine to keep as authoring reference (this plugin uses it that way)."

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

### plugin.json Schema Migration (M-series)

- [ ] **M06 (info, `--fix`)** — `$schema` field missing. Auto-fix inserts `"$schema": "https://json.schemastore.org/claude-code-plugin-manifest.json"` as the first key. Ignored by Claude Code at load time — purely for editor autocomplete.
- [ ] **M07 (warn, `--fix`)** — Top-level `themes` should live under `experimental.themes`. Auto-fix wraps the key under an `experimental` object. **Merge semantics**: if `experimental.themes` already exists, combine the two values (arrays concatenated and deduped; mixed string + array coerced to an array). Preserve existing keys order. Upstream `claude plugin validate` also warns; we add the migration.
- [ ] **M08 (warn, `--fix`)** — Top-level `monitors` → `experimental.monitors`. Same merge semantics as M07.
- [ ] **M09 (warn, `--fix`)** — `agents` is a bare string path. Auto-fix wraps in `[...]`: `"agents": "./agents/foo.md"` → `"agents": ["./agents/foo.md"]`.
- [ ] **M10 (info, `--fix`)** — `commands` or `skills` is a bare string path. Auto-fix wraps in `[...]`. The string form still loads but is being phased out.
- [ ] **(info)** — `channels` declared in `plugin.json`: each entry must have a `server` field that matches a key in the plugin's `mcpServers` (or an externally-known MCP server name). Flag warning if `server` references an undeclared MCP server. Per-channel `userConfig` follows the top-level schema — apply the same legacy/required checks.
- [ ] **(info)** — `bin/` directory present at the plugin root: confirm files are executable (warn on non-executable entries — they appear on `PATH` but fail to run). Auto-discovered, no manifest entry needed.

#### M14 — Unknown top-level manifest keys (info)

For each top-level key in `plugin.json` that is **not** in the documented schema (canonical list: `$schema`, `name`, `displayName`, `version`, `description`, `author`, `homepage`, `repository`, `license`, `keywords`, `commands`, `agents`, `skills`, `hooks`, `mcpServers`, `lspServers`, `outputStyles`, `experimental`, `channels`, `userConfig`, `settings`, `dependencies`), emit info:

> "Plugin manifest contains unknown top-level key `<name>`. Claude Code silently ignores keys not in the schema (forward-compatible). If this is intentional forward-compat or vendor-specific metadata, you can suppress this notice. Real-world example: `defaults`, `recommended` in drupal-dev-framework — both intentional, both load fine."

Info only; never warn or error — surfacing for author confirmation, not enforcement.

#### M15 — Keywords cap (warn)

`keywords` array has more than **25** entries:

> "Plugin manifest declares `<n>` keywords (cap: 25). Marketplace UIs typically truncate long keyword lists, and budget pressure on each keyword decreases the chance any single tag drives a match. Trim to your most distinctive 20–25 entries."

This is the proposed cap from enforcement design — brand-content-design v3.3.1 ships 29 keywords as a real-world ecosystem hit.

#### M16 — License is non-SPDX (info)

`license` value is not a recognized SPDX identifier AND not the literal `"proprietary"`. Common SPDX values: `MIT`, `Apache-2.0`, `BSD-2-Clause`, `BSD-3-Clause`, `GPL-3.0-or-later`, `LGPL-3.0-or-later`, `MPL-2.0`, `CC-BY-4.0`, `CC0-1.0`, `Unlicense`, `ISC`. Info:

> "Plugin manifest uses `<license-value>`, which is not a recognized SPDX identifier. Use an SPDX value when possible (https://spdx.org/licenses/) so marketplace UIs and license-scanners interpret it correctly. `\"proprietary\"` is acceptable when the repository is private and the value reflects company policy — the validator only surfaces this so you confirm intent."

Info only — palcera/design-system-converter ships `"license": "proprietary"` intentionally.

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

#### X02 — Marketplace per-plugin description >600 chars (warn)

For each entry in the `plugins` array, if the `description` field exceeds 600 characters, emit warn:

> "Marketplace entry for `<plugin-name>` has a `<n>`-character description (cap: 600). Marketplace UIs typically truncate at this length, so the long form is invisible to users browsing the catalog. Move the verbose history into the plugin's CHANGELOG.md and keep the marketplace description to a one-paragraph elevator pitch plus the latest release highlight."

Real ecosystem hit: drupal-dev-framework v4.3.0 shipped a ~3,500-character description (multi-version changelog dump) before the v3.5.0 cycle trimmed it.

**No auto-fix** — trimming a description is a content decision. The validator surfaces the issue and points at CHANGELOG.md as the destination.

#### X03 — Marketplace entry missing for a plugin directory (info)

When validating a marketplace root (a directory containing `.claude-plugin/marketplace.json` and subdirectories that look like plugins — each has its own `.claude-plugin/plugin.json`), for each subdirectory NOT referenced by an entry in the marketplace `plugins` array, emit info:

> "Plugin directory `./<dir>/` has its own `plugin.json` but is not listed in `marketplace.json`. Add it to the `plugins` array to make it installable through this marketplace, or move it out of the marketplace root if it's an in-progress branch."

Info only — sometimes a plugin lives in the marketplace root on a feature branch before it's added to `plugins`.

### Plugin Dependencies (if `dependencies` is declared in `plugin.json`)
- [ ] `dependencies` is an array
- [ ] Each entry is either a bare string (plugin name) or an object with a required `name` field
- [ ] Object entries with a `version` field use valid semver-range syntax (`~2.1.0`, `^2.0`, `>=1.4`, `=2.1.0`, hyphen ranges, `||` unions) — flag `range-conflict` on invalid syntax
- [ ] Object entries with a `marketplace` field (cross-marketplace dependency): flag as **error** if the root marketplace's `marketplace.json` does not list the referenced marketplace name in `allowCrossMarketplaceDependenciesOn`. Error message: "Cross-marketplace dependency on `<marketplace-name>` requires the root marketplace.json to include `<marketplace-name>` in `allowCrossMarketplaceDependenciesOn`. Trust does not chain — only the root marketplace's allowlist is consulted." Distinct from `strictKnownMarketplaces` (which lives in user/managed `settings.json` and gates marketplace install location, not dependency trust).
- [ ] Pre-release ranges are only matched when the range opts in with a pre-release suffix (e.g. `^2.0.0-0`)
- [ ] Use official error names when reporting: `range-conflict`, `dependency-version-unsatisfied`, `no-matching-tag` (align with `claude plugin list` output)

### Skills (for each skill in `skills/*/` — plus a root `SKILL.md` for single-skill plugins)

- [ ] **S01 (error)** — `SKILL.md` exists with valid YAML frontmatter. Invalid frontmatter causes the skill to load with no metadata at runtime.
- [ ] **S02 (error)** — Frontmatter has `name` (hyphen-case, max 64 chars).
- [ ] **(error)** — `name` contains no reserved words (`anthropic`, `claude`).
- [ ] **(warn)** — Description includes WHAT it does AND WHEN to use it (trigger conditions).
- [ ] **(warn)** — Description uses third person (no "you").
- [ ] **(error)** — No XML angle brackets (`<` `>`) in any frontmatter value (security restriction — prompt-injection vector).
- [ ] **(warn)** — `compatibility` field valid if present (1–500 chars).
- [ ] **(warn)** — Body is instructions, not documentation (imperative voice).
- [ ] **(warn)** — Body includes an examples section with user scenarios.
- [ ] **(warn)** — Body includes a troubleshooting / error-handling section.
- [ ] **(error)** — Referenced files in `references/` exist.
- [ ] **(error)** — Referenced scripts in `scripts/` exist.
- [ ] **(warn)** — No `README.md` inside skill directories (belongs at plugin root).

#### S04 — Description trigger phrase (warn)

The `description` must give Claude a routing signal — either it opens with a trigger phrase ("Use when …") OR it follows the three-part WHAT / WHEN / NOT-FOR structure. A description that only says WHAT the skill does, with no WHEN, leaves Claude unable to route to it. Emit warn:

> "Skill `<name>` description has no trigger phrase. Start with 'Use when …' or include an explicit WHEN/NOT-FOR boundary so Claude can route to the skill. A WHAT-only description is loaded into context but rarely matched."

Severity is **warn**, promoted to error under `--strict`. (Routing-critical, but making it a hard error would fail existing skills on day one — soft-nudge adoption.)

#### S05 — Description length cap (warn)

The combined `description` + `when_to_use` text is capped at `maxSkillDescriptionChars` (default **1,536**; read the actual value from settings if the validated environment sets it). Past the cap, text is silently truncated from the listing Claude sees. Emit warn when the description exceeds the cap:

> "Skill `<name>` description is `<n>` characters, over the `maxSkillDescriptionChars` cap (`<cap>`). Text past the cap is silently dropped from the skill listing. Trim to the cap — put the key trigger phrase first so it survives truncation."

(This replaces the old flat "max 1024 chars" check — 1,024 was stale; 1,536 is the runtime cap. ~1,024 remains a stricter agentskills.io portability target, not a validator error.)

#### S10 — Body length (warn ≥ 250, error ≥ 500)

Count the SKILL.md body lines (excluding frontmatter). Warn at **≥ 250 lines**, error at **≥ 500 lines**:

> warn: "Skill `<name>` body is `<n>` lines. Consider extracting detail into `references/` — every body line is loaded into context on invocation. Mature skills legitimately reach 250–400 lines, so this is a nudge, not a defect."
> error: "Skill `<name>` body is `<n>` lines, over the 500-line ceiling. Extract detail into `references/` and keep only the essential workflow in SKILL.md."

Configurable via `--max-skill-lines`. Note: this plugin's own `plugin-creation` SKILL.md exceeds 250 lines — an accepted finding (it's a deliberately large hub skill with heavy progressive disclosure).

#### S11 — Body conciseness threshold (info)

Body exceeds **150 lines** — info-level conciseness nudge below the S10 warn threshold:

> "Skill `<name>` body is `<n>` lines. Skills that load frequently benefit from staying under ~150 lines. If this skill is invoked often, consider whether more detail can move to `references/`."

Info only — many legitimate skills sit in the 150–250 band.

#### S12 — Project-scoped skill `allowed-tools` without a workspace-trust note (warn)

When a **project-scoped** skill (path matches `.claude/skills/`) declares `allowed-tools` AND the skill **body** contains no note explaining the workspace-trust gating, emit warn:

> "Project-scoped skill `<name>` declares `allowed-tools` but the body doesn't document the workspace-trust gating. `allowed-tools` on a `.claude/skills/` skill only takes effect after the user accepts the workspace trust dialog — and grants the skill prompt-free tool access. Add a note so a user reviewing the skill before trusting the repo understands what they're granting."

(Plugin-shipped skills are exempt — trust is established at install time. This rule targets skills checked into a project repo, where the reader IS the person deciding whether to trust.)

The validator additionally emits its own **info** note on every project-scoped `allowed-tools` skill (unchanged behavior): "`.claude/skills/*` skills with `allowed-tools` only take effect after the workspace trust dialog is accepted. Review the skill carefully before trusting a repository."

#### S13 — Nested skill directory (info)

A `skills/<name>/` directory that itself contains a subdirectory with its own `SKILL.md`. Claude Code recursively discovers nested skill directories, which may not be the author's intent (e.g. a `references/` folder accidentally named such that it looks like a skill). Emit info:

> "Skill directory `skills/<name>/` contains a nested subdirectory `<sub>/` with its own `SKILL.md`. Claude Code discovers nested skill directories recursively — if `<sub>` is meant to be a separate skill, give it a top-level `skills/` entry; if it's reference material, it shouldn't contain a `SKILL.md`."

Info only — surfaces a layout that's usually unintended.

### Commands (for each `commands/*.md`)
- [ ] Valid YAML frontmatter — invalid frontmatter causes command to load with no metadata at runtime
- [ ] `description` field present
- [ ] `allowed-tools` field present
- [ ] No inline code with backtick+exclamation or backtick+at-sign that could trigger execution

#### C01 — `TodoWrite` referenced in command/skill body or examples (warn, `--fix`)

`TodoWrite` is disabled by default as of Claude Code v2.1.142 (replaced by the `Task*` family). For each command file, skill body, agent file, or referenced reference doc, grep for the literal token `TodoWrite`. Each hit emits warn:

> "References `TodoWrite`, which is disabled by default as of Claude Code v2.1.142. Use `TaskCreate` / `TaskGet` / `TaskList` / `TaskUpdate` instead. To re-enable `TodoWrite` for users on a managed environment, set `CLAUDE_CODE_ENABLE_TASKS=0`."

**`--fix`**: literal text replacement of `TodoWrite` → `TaskCreate` in non-ambiguous contexts. The auto-fix flags **ambiguous** cases for human review rather than silently transforming them:

- A sentence like "use `TodoWrite` to track session todos" → ambiguous (which Task* operation? Create? Update?). Flag, don't fix.
- A list like "Available tools: Read, Write, TodoWrite, Bash" → safe to rewrite to `TaskCreate, TaskUpdate, TaskList, TaskGet` (the canonical replacement set). Auto-fix.
- A code example using TodoWrite-specific arguments (e.g. `TodoWrite({ todos: [...] })`) → ambiguous; the Task* family has a different argument shape. Flag, don't fix.

#### C02 — `/extra-usage` reference (warn, `--fix`)

`/extra-usage` was renamed to `/usage-credits`. Literal references in command bodies, skill descriptions, agent prompts, and reference docs should be updated. Auto-fix performs the literal rename. Source: Built-in Commands guide L127 ("Previously `/extra-usage`").

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

### Session-Remembrance Pattern (R-series)

These rules run **only when the plugin adopts the [session-remembrance pattern](../skills/plugin-creation/references/06-hooks/remembrance-hooks-pattern.md)**. Detect adoption by either: a `commands/install-remembrance-hook.md` file, or any command whose body references `session-primer`. If the plugin doesn't adopt the pattern, skip this whole section.

> Rule IDs are **R-series** here, not the enforcement-design's `X01`. `X` is already the marketplace cross-file series (X02/X03). R-series is the dedicated remembrance-pattern group.

#### R01 — Install command writes only inside the project (error)

The install command must write **only** under `${CLAUDE_PROJECT_DIR}/.claude/` — never above it. Scan the install command body for write targets (the `settings.json` path, the primer destination, the script copy destination). Any of these is an **error**:

- a `..` path-traversal segment in a write target
- an absolute path that is not rooted at `${CLAUDE_PROJECT_DIR}` (e.g. `$HOME`, `/etc`, a hardcoded `/Users/...`)
- writing to a parent of the project directory

> "Install command writes to `<path>`, outside `${CLAUDE_PROJECT_DIR}/.claude/`. A remembrance installer must confine all writes to the project's own `.claude/` tree — it runs against the user's project, not the plugin."

#### R02 — `PostCompact` hook is dead config (warn)

If the install command emits a `PostCompact` hook entry into the project `settings.json`, emit warn:

> "Install command wires a `PostCompact` hook. `PostCompact` stdout is **not** injected into Claude's context — only `SessionStart` / `UserPromptSubmit` / `UserPromptExpansion` stdout is. A no-matcher `SessionStart` hook already fires after compaction (`source: \"compact\"`) and re-injects the primer. Remove the `PostCompact` entry — it's dead config. The pattern is two hook events, not three."

#### R03 — `${CLAUDE_PLUGIN_ROOT}` in an emitted project-settings hook (warn)

Inspect the hook `command` strings the install command writes into the **project** `settings.json` (typically the values of the `jq --arg` variables). If any references `${CLAUDE_PLUGIN_ROOT}` (or `$CLAUDE_PLUGIN_ROOT`), emit warn:

> "An emitted project-`settings.json` hook command references `${CLAUDE_PLUGIN_ROOT}`. That placeholder is plugin-context only — it does not resolve in a project settings file, and an absolute plugin path breaks on every plugin update. Copy `save-session.sh` into `<project>/.claude/<plugin-name>/` and reference it via `${CLAUDE_PROJECT_DIR}` instead."

(`${CLAUDE_PLUGIN_ROOT}` is fine **elsewhere** in the install command — e.g. reading the template, copying the script *from* the plugin. R03 only flags it inside a string destined for the project `settings.json`.)

#### R04 — Incomplete adoption (info)

A plugin adopting the pattern should ship all four artifacts. If some but not all are present, emit info listing what's missing:

- `templates/session-primer.md`
- `commands/install-remembrance-hook.md`
- `commands/save-session.md`
- `scripts/save-session.sh`

> "Plugin adopts the session-remembrance pattern but is missing `<artifact(s)>`. The pattern needs all four — primer template, install command, save-session command, and the bash persistence script. Scaffold the missing pieces with `/plugin-creation-tools:add-component remembrance-hooks`."

#### R05 — `SessionEnd` hook missing an explicit `timeout` (warn)

The `SessionEnd` hook entry the install command emits must set an explicit `timeout`. `SessionEnd`'s default budget is 1.5 s, and timeouts on plugin-provided hooks do **not** raise it — only a per-hook `timeout` written into the project `settings.json` does. If the emitted `SessionEnd` entry has no `timeout`, emit warn:

> "The `SessionEnd` hook the install command emits has no explicit `timeout`. `SessionEnd`'s default budget is 1.5 s — too short for a save script — and plugin-provided timeouts don't raise it. Set `timeout` (the pattern uses `10`) on the entry written into the project `settings.json`."

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
