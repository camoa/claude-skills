---
description: Validate plugin structure, frontmatter, and best practices. Use when user says "validate plugin", "check plugin", "audit plugin", "verify plugin", "is my plugin correct", or before distributing/publishing a plugin.
allowed-tools: Read, Glob, Grep, Bash(ls:*), Bash(find:*), Bash(wc:*)
argument-hint: "[plugin-path] [--fix] [--dry-run] [--strict]"
context: fork
---

# Validate Plugin

Validate a plugin's structure and components against best practices.

## Steps

1. **Resolve the plugin path from `$ARGUMENTS`.** Parse `$ARGUMENTS` (the full argument string): the first token that does **not** start with `--` is the plugin path; tokens starting with `--` are flags. Do **not** read `$1` — Claude Code's `$N` placeholders are **0-based** (`$0` is the first argument, `$1` the second), so `$1` silently reads the wrong token. If no path token is present, fall back to detecting the plugin from the current directory.
   - Absolute path → use directly.
   - Relative path or bare plugin name → resolve against the current directory; if that misses and the cwd is inside a marketplace, resolve as a sibling plugin directory.
   - This command is `context: fork`; argument substitution happens **before** the fork, so `$ARGUMENTS` is available in the forked run. The cwd of the fork is not reliable — always prefer an explicit path argument.
2. Parse flags from the `--` tokens: `--fix` applies auto-migrations for rules tagged below; `--dry-run` (with `--fix`) reports the proposed migrations without writing; `--strict` promotes warnings to errors for CI gating.
3. Find `.claude-plugin/plugin.json` to confirm it's a plugin root.
4. **Compute the component inventory deterministically (D1).** Do **not** eyeball counts from a file listing — count with the shell so the numbers are stable run-to-run. From the plugin root:
   - skills: `ls -d skills/*/SKILL.md 2>/dev/null | wc -l` (add `1` when a root `SKILL.md` exists for a single-skill plugin)
   - commands: `ls commands/*.md 2>/dev/null | wc -l`
   - agents: `find agents -name '*.md' 2>/dev/null | wc -l` (recursive — agent subfolders count)
   Use these integers verbatim in the `Checked — clean` block of the Output Format. LLM-counted inventories drift across runs (observed 30/37/38 on the same plugin); the shell count does not.
5. Run all validation checks below.
6. If `--fix` is set: apply each auto-fixable finding (unless `--dry-run`), atomically (write-tempfile-then-rename), and append an entry to `.claude-plugin/.validate-fixes.log`. With `--dry-run`, list the proposed changes instead of writing. **No interactive confirmation** — passing `--fix` is the consent; review the result via `git diff`.
7. Report results as a structured checklist.

## Auto-fix (`--fix`)

The validator has an opt-in `--fix` flag that performs **only** mechanical, reversible migrations. Every fix:

- Is logged to `.claude-plugin/.validate-fixes.log` (append-only) with timestamp + rule ID + summary
- Writes atomically (tempfile + rename), so a failure leaves the original intact
- Is reversible via `git diff` / `git restore`

`--fix` is **non-interactive** — it applies directly and relies on `git diff` for review. This is deliberate: the command runs `context: fork`, and a forked subagent has no interactive turn with the user, so a confirmation prompt could never fire. Passing the `--fix` flag is itself the consent. To preview without writing, run `--fix --dry-run` — it reports every proposed migration as a diff and changes nothing.

Rules that ship with `--fix` (cumulative across releases): **H05**, **H06**, **H10** (v3.5.0); **M06**, **M07**, **M08**, **M09**, **M10**, **C01**, **C02** (v3.6.1); **S15**, **A04** (v3.8.0). Future releases add more.

Log entry format:

```
2026-05-19T14:22:01Z  H05  hooks/hooks.json: SessionStart → exec form (added "args": [])
2026-05-19T14:22:01Z  H10  scripts/post-write.sh: updatedMCPToolOutput → updatedToolOutput
```

## Validation Checks

### Frontmatter Integrity (FM-series)

Run these against **every** component file with a YAML frontmatter block — every `commands/*.md`, every `skills/**/SKILL.md`, every `agents/**/*.md`. These rules supersede the lenient per-key checks: a file can have a `description` key extractable by eye yet still fail a real parse.

#### FM01 — Frontmatter block parses as YAML (error)

Take the text **between** the opening `---` and closing `---` and run it through a real YAML parser (`yaml.safe_load` or equivalent) as a single document. If it raises, emit an **error**:

> "Frontmatter of `<file>` fails YAML parsing: `<parser error>`. A file whose frontmatter block does not parse **loads with no metadata at runtime** — every frontmatter field (`description`, `allowed-tools`, `name`, …) is silently dropped. Fix the YAML."

Do **not** extract individual keys leniently and call it valid — parse the whole block. Common real failures:

- `argument-hint: [<task-name>] [--all]` — a YAML flow sequence (`[<task-name>]`) followed by more content (`[--all]`) on the same line is a syntax error for the whole value, and can break the block.
- An unquoted `:` inside a value — `description: Do X: then Y` parses `X` as a nested mapping key. Quote the value.
- A bare `%`, `@`, `` ` ``, or leading `[`/`{` in an unquoted scalar.

The fix for almost all of these is to **quote the value**: `argument-hint: "[task-name] [--all]"`.

#### FM02 — String-typed field parsed as a non-string (info)

After a successful FM01 parse, check fields that are meant to be strings — `argument-hint`, `description`, `name`, `compatibility`. If the parsed value is a **list** or **mapping** instead of a string, emit info:

> "`<field>` in `<file>` parses as a YAML `<list|mapping>`, not a string. Most commonly `argument-hint: [task-name]` → the list `[\"task-name\"]`. Quote it — `argument-hint: \"[task-name]\"` — so it's an unambiguous string."

Info, not warn: the upstream Slash Commands guide's own `argument-hint` examples use the unquoted bracket form, so a single clean flow sequence is tolerated at runtime — but quoting removes the ambiguity and is the safer authoring habit.

### Plugin Structure
- [ ] `.claude-plugin/plugin.json` exists and is valid JSON
- [ ] `name` field present in plugin.json
- [ ] `name` is kebab-case — if not, warn: "Plugin name '[X]' is not kebab-case. Claude.ai marketplace sync requires kebab-case names."
- [ ] `version` follows semver
- [ ] `description` present and not placeholder text
- [ ] README.md exists at plugin root
- [ ] CHANGELOG.md exists at plugin root
- [ ] **ST03 (warn)** — if a `CLAUDE.md` is present at the plugin root: "Plugin-root `CLAUDE.md` is NOT loaded as project context. Instructions belong in a skill — put them in `skills/<name>/SKILL.md` so they reach Claude; maintainer/contributor conventions belong in a `CONTRIBUTING.md` (a non-`CLAUDE.md` filename). Upstream `claude plugin validate` also warns on a plugin-root `CLAUDE.md` — this rule matches that severity so a plugin can't pass here yet warn upstream." (Raised from info to warn in v3.7.1 for upstream parity.)

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

#### M14 — Unknown top-level manifest keys (warn)

For each top-level key in `plugin.json` that is **not** in the documented schema (canonical list: `$schema`, `name`, `displayName`, `version`, `description`, `author`, `homepage`, `repository`, `license`, `keywords`, `defaultEnabled`, `commands`, `agents`, `skills`, `hooks`, `mcpServers`, `lspServers`, `outputStyles`, `experimental`, `channels`, `userConfig`, `settings`, `dependencies`), emit warn:

> "Plugin manifest contains unknown top-level key `<name>`. Claude Code silently ignores keys not in the schema (forward-compatible), and upstream `claude plugin validate` warns on them. If this is intentional forward-compat or vendor-specific metadata, the warning is expected — keep it or move the data under a recognized key. Real-world example: `defaults`, `recommended` in drupal-dev-framework."

Severity is **warn** (raised from info in v3.7.1): upstream `claude plugin validate` warns on unknown keys, so this rule matches it — a plugin must not pass `/plugin-creation-tools:validate` "clean" while still warning upstream.

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

- [ ] **S01 (error)** — `SKILL.md` exists, and its frontmatter passes the **FM01** strict YAML parse (see Frontmatter Integrity). Invalid frontmatter causes the skill to load with no metadata at runtime.
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

#### S14 — Skill `model:` pins a sub-1M-context model (warn)

For each `skills/**/SKILL.md` (and a root `SKILL.md` on a single-skill plugin), read the frontmatter `model:` value. A skill's `model:` is an **inline, current-turn model override with no context isolation** — per the Skills guide, *"the model to use when this skill is active… the override applies for the rest of the current turn."* The skill runs in the live conversation on the pinned model, so pinning a model whose context window is **smaller than a realistic session** (`sonnet`/`haiku` ≈ 200k) makes the skill **overflow whenever it activates from a conversation larger than that window** — an API context error until the user `/compact`s. This is BUG-1, confirmed in production on `code-paper-test/paper-test`.

**Fires (warn)** when `model:` resolves to a sub-1M window:
- `sonnet`, `haiku`
- any dated `claude-sonnet-*` / `claude-haiku-*` id **without** a long-context suffix (`1m` / `[1m]`)

**Exempt — no finding:**
- `model:` absent (no override — inherits the session model)
- `model: inherit` (explicitly inherits the 1M session model)
- `opus` / any `opus*` value (Opus is the 1M tier)
- any value carrying a `1m` / `[1m]` long-context suffix (e.g. `sonnet[1m]`)

Fires **regardless of `user-invocable` / `disable-model-invocation`** — the override is always inline whether the skill is user- or model-triggered.

**Agents are exempt.** This rule scans **only** `SKILL.md` files. A `model:` pin on an `agents/**/*.md` file runs in a fresh subagent context (its own empty window), so it is safe and must **not** be flagged. If S14 ever fires on an agent file, the rule is mis-scoped.

> "Skill `<name>` pins `model: <value>`, a sub-1M-context model. A skill's `model:` is an inline current-turn override with no context isolation, so the skill overflows when activated from a conversation larger than ~200k. Two fixes: (1) if the skill is a pure reader/transform that needs only its input, convert it to a **Task-dispatched agent** — keeps the cheap model AND isolates context in a fresh window; (2) if it needs the conversation context, set **`model: inherit`** to run on the 1M session model. See `references/03-skills/writing-skillmd.md` § Don't pin a skill below the session window."

**Not auto-fixable** — the choice between convert-to-agent and `inherit` is intent-dependent. Report only. Severity is **warn**, promoted to error under `--strict` so it's caught at authoring time.

#### S15 — Skill uses camelCase `disallowedTools` (error, `--fix`)

Skills use the **kebab-case** `disallowed-tools` frontmatter field (Skills guide). The camelCase `disallowedTools` is the **agent** field and does **nothing** on a skill — it is silently ignored, so the tool restriction the author intended never takes effect. For each `SKILL.md`, if the frontmatter contains a `disallowedTools:` key, emit **error**:

> "Skill `<name>` declares `disallowedTools` (camelCase). On a skill the field is `disallowed-tools` (kebab-case); the camelCase form is the agent field and is silently ignored here, so the intended tool restriction never applies. Rename to `disallowed-tools`."

**`--fix`**: rename the frontmatter key `disallowedTools` → `disallowed-tools` (value unchanged). Paired with **A04** (the reciprocal agent rule). See `references/05-agents/agent-tools.md` § The disallowedTools Field for the kebab-vs-camel split.

### Commands (for each `commands/*.md`)
- [ ] Frontmatter passes the **FM01** strict YAML parse (see Frontmatter Integrity) — invalid frontmatter causes the command to load with no metadata at runtime
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

- [ ] **A01 (error)** — Frontmatter passes the **FM01** strict YAML parse (see Frontmatter Integrity). Invalid frontmatter causes the agent to load with no metadata at runtime.
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

#### A04 — Agent uses kebab-case `disallowed-tools` (error, `--fix`)

Agents use the **camelCase** `disallowedTools` frontmatter field (Subagents guide). The kebab-case `disallowed-tools` is the **skill** field and does **nothing** on an agent — it is silently ignored, so the agent inherits ALL tools instead of being restricted. For each `agents/**/*.md`, if the frontmatter contains a `disallowed-tools:` key, emit **error**:

> "Agent `<name>` declares `disallowed-tools` (kebab-case). On an agent the field is `disallowedTools` (camelCase); the kebab form is the skill field and is silently ignored here, so the agent inherits all tools instead of the intended restriction. Rename to `disallowedTools`."

**`--fix`**: rename the frontmatter key `disallowed-tools` → `disallowedTools` (value unchanged). Reciprocal of **S15** (the skill rule). The same defect with the fields reversed has historically shipped in ecosystem plugins (agents mis-"standardized" on the skill field) — see `references/05-agents/agent-tools.md` § The disallowedTools Field.

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
- [ ] **H02 (error)** — Each event name is one of the 30 recognized events: `Setup`, `SessionStart`, `UserPromptSubmit`, `UserPromptExpansion`, `PreToolUse`, `PermissionRequest`, `PermissionDenied`, `PostToolUse`, `PostToolUseFailure`, `PostToolBatch`, `Notification`, `MessageDisplay`, `SubagentStart`, `SubagentStop`, `TaskCreated`, `TaskCompleted`, `Stop`, `StopFailure`, `TeammateIdle`, `InstructionsLoaded`, `ConfigChange`, `CwdChanged`, `FileChanged`, `WorktreeCreate`, `WorktreeRemove`, `PreCompact`, `PostCompact`, `Elicitation`, `ElicitationResult`, `SessionEnd`
- [ ] **H03 (error)** — Each hook entry has `type` — one of `command`, `prompt`, `agent`, or `mcp_tool` — plus the matching required fields for that type. `agent` is upstream-marked experimental; flag a one-line info note when used.
- [ ] **H04 (error)** — No `http` type hooks in `hooks.json`. `http` hooks only work in `settings.json` (silently ignored when placed in `hooks.json`).
- [ ] **(error)** — `mcp_tool` handlers: require `server` and `tool`; if `server` is not declared in the plugin's `mcpServers` (and isn't a known external server the user wires up themselves), emit a **warning**: "`mcp_tool` references server `<name>` not declared in this plugin's `mcpServers`. The handler will produce a non-blocking error if the server isn't already connected at runtime."
- [ ] **(warn)** — Command hooks reference executable files (chmod +x missing → warn).
- [ ] **(warn)** — Timeouts are reasonable (< 120s for sync hooks).

#### H05 — Exec form preferred for path placeholders (warn, `--fix`)

For each command hook in `hooks.json` whose `command` string contains a path placeholder (`${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PROJECT_DIR}`, `${CLAUDE_PLUGIN_DATA}`) AND lacks an `args` field, emit a warning.

**Fire regardless of whether the path contains spaces.** The Hooks Reference says exec form is preferred for *any* hook that references a path placeholder — "Set `args` whenever the hook references a [path placeholder]" — not only when the resolved path happens to contain spaces. A hook can `PASS` H05 only if it has no path placeholder, or already uses exec form (`args` present). "No spaces in the path" is **not** a pass condition — do not reason "exec form not needed since no spaces."

> "Hook `<event>` handler uses shell form with a path placeholder. Prefer exec form: add `\"args\": []` so the script path is passed as one argument with no quoting needed — this is the recommended shape for every placeholder reference, independent of spaces. See `references/06-hooks/writing-hooks.md` § Exec form vs shell form."

**`--fix`**: Insert `"args": []` as a sibling to `command` in the hook handler. Do **not** auto-migrate when the command string contains shell metacharacters (`|`, `&&`, `||`, `;`, `>`, `<`, `` ` ``, `$(`, glob `*`/`?` outside placeholder, `~`) — those need shell form. In that case, emit the warning but skip the fix and note "shell form required for this command".

#### H06 — Curly-brace placeholders in command strings (warn, `--fix`)

In each `hooks.json` command-string value (and only in command-string values — NOT inside referenced `.sh` script files, where bare `$VAR` is normal bash), flag bare-dollar `$CLAUDE_PROJECT_DIR` / `$CLAUDE_PLUGIN_ROOT` / `$CLAUDE_PLUGIN_DATA` / `$CLAUDE_ENV_FILE` / `$CLAUDE_EFFORT` references:

> "Use `${VAR}` (curly-brace form) instead of bare `$VAR` inside JSON command strings — the curly form is the canonical placeholder syntax and is unambiguous to the placeholder resolver."

**`--fix`**: Literal rewrite of `$CLAUDE_<NAME>` → `${CLAUDE_<NAME>}` inside JSON string values in `hooks.json` only. Skip script files (`.sh`, `.py`, etc.) entirely.

H06 fires on **any** bare-dollar placeholder in a command string — like H05 it is not conditioned on spaces or any other property of the resolved path.

#### H07 — Placeholder quoting (warn)

In **shell form** command hooks (no `args` field), path placeholders inside the `command` string must be wrapped in double quotes (`"${CLAUDE_PROJECT_DIR}"`) — paths with spaces break otherwise. Exec form does not need quoting. Skip this check when `args` is present.

#### H08 — Broad-matcher tool hooks without `if` (info)

Hook handlers on tool events (`PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `PermissionDenied`) with a broad matcher (`*`, `""`, omitted, or `.*`) **may** spawn a process on every tool call. Emit an info-level suggestion (not warn, not error):

> "Consider adding an `if` field to this handler to pre-filter tool calls cheaply — broad-matcher hooks spawn a process on every call. See `references/06-hooks/writing-hooks.md` § The if Field."

This is intentionally **info**, not warn — some authors deliberately spawn on every call (logging, analytics). Don't punish them.

**Scope — what counts as a "broad" matcher.** H08 fires only on `*`, `""`, an omitted matcher, or `.*`. A **named-tool** matcher — `Write`, `Edit`, `Bash`, `Write|Edit` — is considered narrow enough and does **not** trip H08, even with no `if` field. Rationale: the matcher already scopes the hook to specific tool(s); an `if` would narrow it further (to specific arguments) but the spawn-on-every-call cost is bounded to one tool's frequency, which is an acceptable, common design. If you want argument-level filtering on a named-tool hook, `if` is still available — H08 just doesn't *demand* it there.

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
- {rule-id} {file}: {what's wrong}

### Warnings (should fix)
- {rule-id} {file}: {what's wrong}

### Info
- {rule-id} {file}: {note}

### Checked — clean
- {n} skills, {n} commands, {n} agents, hooks: {yes/no}, MCP: {yes/no}  ← counts from the deterministic inventory (Step 4), not eyeballed
- {rule-ids that were evaluated and found nothing}

### Result: PASS / FAIL
```

**Header discipline (one finding, one correct bucket):**

- Place an entry under **Errors** / **Warnings** / **Info** strictly by its actual emitted severity. A rule that was evaluated and produced **no finding** is not a warning — it does not appear under Warnings at all.
- Do **not** list a ruled-out check under Warnings with body text that concludes it's clean (e.g. "S04 — no actual hits", "S10 — below the 250-line line"). A consumer or gate that counts entries under the Warnings header would over-count. Ruled-out checks go under **Checked — clean**, or are simply omitted.
- The `### Result` line is `PASS` only when Errors is empty (and, under `--strict`, Warnings is empty too).

## Arguments

- **Plugin path** (optional): the first non-`--` token in `$ARGUMENTS`. Resolve per Step 1. Defaults to current-directory detection when absent. Do not read `$1` — `$N` is 0-based; the path is `$0` if you index positionally, but parsing `$ARGUMENTS` for the first non-flag token is the robust approach.
- `--fix`: apply auto-migrations for `--fix`-tagged rules (non-interactive; see Auto-fix section).
- `--dry-run`: with `--fix`, report proposed migrations without writing.
- `--strict`: promote warnings to errors (CI gating).
