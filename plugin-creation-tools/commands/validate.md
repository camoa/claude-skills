---
description: Validate plugin structure, frontmatter, and best practices. Use when user says "validate plugin", "check plugin", "audit plugin", "verify plugin", "is my plugin correct", or before distributing/publishing a plugin.
allowed-tools: Read, Glob, Grep
argument-hint: [plugin-path]
context: fork
---

# Validate Plugin

Validate a plugin's structure and components against best practices.

## Steps

1. Determine plugin path: use `$1` if provided, otherwise detect from current directory
2. Find `.claude-plugin/plugin.json` to confirm it's a plugin root
3. Run all validation checks below
4. Report results as a structured checklist

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

### plugin.json Schema Migration (soft-breaking — `experimental.*`)
- [ ] **Warning** if top-level `themes` or `monitors` is set in `plugin.json`: "`themes` / `monitors` should live under `experimental.*`. `claude plugin validate` flags this and a future release will require the nested form." Offer an auto-migration diff that wraps both keys under an `experimental` object (preserve existing values, deduplicate if `experimental.themes` / `experimental.monitors` is already partially set).
- [ ] **Warning** if `agents` is a bare string path: "The `agents` field is array-only. Wrap the path in an array: `\"agents\": [\"./agents/foo.md\"]`."
- [ ] **Info** (not warning) if `commands` or `skills` is a bare string path: "The array form is preferred — `\"commands\": [\"./cmd.md\"]`. The string form still loads but is being phased out."
- [ ] **Info** if `$schema` is missing: "Consider adding `\"$schema\": \"https://json.schemastore.org/claude-code-plugin-manifest.json\"` for editor autocomplete. Claude Code ignores the field at load time."

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

### Agents (for each `agents/*.md`)
- [ ] Valid YAML frontmatter — invalid frontmatter causes agent to load with no metadata at runtime
- [ ] `name` field present
- [ ] `description` field present (includes delegation triggers)
- [ ] `tools` field present
- [ ] `model` field present (haiku, sonnet, opus, or inherit)

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
- [ ] Valid JSON structure — **Note:** malformed hooks.json prevents the entire plugin from loading
- [ ] Each event name is one of the 29 recognized events: `Setup`, `SessionStart`, `UserPromptSubmit`, `UserPromptExpansion`, `PreToolUse`, `PermissionRequest`, `PermissionDenied`, `PostToolUse`, `PostToolUseFailure`, `PostToolBatch`, `Notification`, `SubagentStart`, `SubagentStop`, `TaskCreated`, `TaskCompleted`, `Stop`, `StopFailure`, `TeammateIdle`, `InstructionsLoaded`, `ConfigChange`, `CwdChanged`, `FileChanged`, `WorktreeCreate`, `WorktreeRemove`, `PreCompact`, `PostCompact`, `Elicitation`, `ElicitationResult`, `SessionEnd`
- [ ] Each hook entry has `type` — one of `command`, `prompt`, `agent`, or `mcp_tool` — plus the matching required fields for that type. `agent` is upstream-marked experimental; flag a one-line info note when used.
- [ ] `mcp_tool` handlers: require `server` and `tool`; if `server` is not declared in the plugin's `mcpServers` (and isn't a known external server the user wires up themselves), emit a **warning**: "`mcp_tool` references server `<name>` not declared in this plugin's `mcpServers`. The handler will produce a non-blocking error if the server isn't already connected at runtime."
- [ ] No `http` type hooks — `http` hooks only work in `settings.json`, not `hooks.json` (error if found)
- [ ] Command hooks reference executable files
- [ ] Timeouts are reasonable (< 120s for sync hooks)
- [ ] `$CLAUDE_PROJECT_DIR` / `${CLAUDE_PROJECT_DIR}` / `$CLAUDE_PLUGIN_ROOT` / `${CLAUDE_PLUGIN_ROOT}` / `$CLAUDE_PLUGIN_DATA` / `${CLAUDE_PLUGIN_DATA}` usage is quoted in all command strings (paths with spaces break otherwise)
- [ ] **Warning**: hook handlers on tool events (`PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `PermissionDenied`) with a broad matcher (`*`, `""`, omitted, or `.*`) should include an `if` field to pre-filter. Emit a **suggestion** (not error): "Consider adding an `if` field to this handler to avoid spawning a process on every tool call."
- [ ] `if` field is only valid on tool events — flag as warning if set on non-tool events (silently ignored at runtime)
- [ ] **Info** when a `PostToolUse` JSON output example or hook script uses `updatedMCPToolOutput`: "Upstream now prefers `updatedToolOutput` (works for all tools, not just MCP). The old field still works; new code should use `updatedToolOutput`."

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
