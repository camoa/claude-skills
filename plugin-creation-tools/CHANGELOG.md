# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
