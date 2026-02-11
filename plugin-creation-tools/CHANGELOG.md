# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
