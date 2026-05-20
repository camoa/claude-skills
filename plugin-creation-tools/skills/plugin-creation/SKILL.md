---
name: plugin-creation
version: 3.4.1
description: Use when creating Claude Code plugins - covers skills, commands, agents, hooks, MCP servers, and plugin configuration. Use when user says "create plugin", "make a skill", "add command", "add hooks", "skill authoring", "SKILL.md", "plugin components", "package reusable behavior", "distribute skills", "scaffold plugin", "plugin structure", "write a skill description". NOT for: using existing plugins, installing plugins, plugin marketplace browsing. !`ls .claude-plugin/ 2>/dev/null`
user-invocable: false
---

# Plugin Creation

Create complete Claude Code plugins with any combination of components.

## When to Use

- "Create a plugin" / "Make a new plugin"
- "Add a skill" / "Create command" / "Make agent"
- "Add hooks" / "Setup MCP server"
- "Configure settings" / "Setup output directory"
- "Package for marketplace"
- NOT for: Using existing plugins (see /plugin command)

## Quick Reference

| Component | Location | Invocation | Best For |
|-----------|----------|------------|----------|
| Skills | `skills/name/SKILL.md` | Model-invoked (auto) | Complex workflows with resources |
| Commands | `commands/name.md` | User (`/command`) | Quick, frequently used prompts |
| Agents | `agents/name.md` | Auto + Manual | Task-specific expertise |
| Hooks | `hooks/hooks.json` | Event-triggered | Automation and validation |
| MCP | `.mcp.json` | Auto startup | External tool integration |

## Before Creating

1. Read `references/01-overview/component-comparison.md` to decide which components needed
2. Determine if this should be a new plugin or add to existing

## Plugin Project Setup

When creating any plugin, also consider:
- `.claude/rules/` with modular project rules (path-scoped if needed for different component directories)
- `CLAUDE.md` at plugin root **for authoring reference only** — it is NOT loaded as project context when the plugin is installed. To ship instructions Claude reads at runtime, put them in a skill (`skills/<name>/SKILL.md`). The validator emits an info notice when a plugin-root `CLAUDE.md` is present so you don't mistake it for runtime context.
- README.md and CHANGELOG.md at plugin root (for humans — never inside skill directories)

## Documentation Principles

All plugin documentation should follow lean principles:
- **Current truth only** — no historical narratives or "previously we did X"
- **Replace, don't append** — superseded content gets replaced entirely
- **Delete what's irrelevant** — every edit is a chance to prune
- Read `references/02-philosophy/core-philosophy.md` for full philosophy

## Plugin Initialization

When user says "create plugin", "initialize plugin", "new plugin":

**Option A - Use init script**:
```bash
python scripts/init_plugin.py my-plugin --path ./plugins --components skill,command,hook
```

**Option B - Manual creation**:

1. Create plugin directory structure:
   ```
   plugin-name/
   ├── .claude-plugin/
   │   └── plugin.json
   ├── commands/        # if needed
   ├── agents/          # if needed (recursively scanned — subfolders join the scoped id, e.g. agents/review/security.md → my-plugin:review:security)
   ├── skills/          # if needed
   │   └── skill-name/
   │       └── SKILL.md
   ├── hooks/           # if needed
   │   └── hooks.json
   └── .mcp.json        # if needed
   ```

   **Single-skill minimum layout (v2.1.142+)**: if the plugin is exactly one skill and nothing else, put `SKILL.md` at the plugin root with no `skills/` subdirectory and no `skills` field — Claude Code auto-discovers it. See `references/08-configuration/plugin-json.md` § Important Path Rules item 4.

2. Copy template from `templates/plugin.json.template`

3. Ask user which components they need

## Creating Skills

When user says "add skill", "create skill", "make skill":

1. Read `references/03-skills/writing-skillmd.md` for structure
2. Copy template from `templates/skill/SKILL.md.template`
3. Key requirements:
   - Name: lowercase, hyphens, max 64 chars
   - Description: WHAT it does + WHEN to use it, max 1024 chars, third person
   - Body: imperative instructions, under 500 lines
   - Use progressive disclosure - reference files for details

**Critical**: SKILL.md files are INSTRUCTIONS for Claude, not documentation. Write imperatives telling Claude what to do.

| Documentation (WRONG) | Instructions (CORRECT) |
|----------------------|------------------------|
| "This skill helps with PDF processing" | "Process PDF files using this workflow" |
| "The description field is important" | "Write the description starting with 'Use when...'" |

**Consider these optional frontmatter fields:**
- `model: haiku` for simple lookup/formatting skills, `opus` for complex reasoning
- `context: fork` with `agent: <type>` for heavy operations that would pollute main context
- `disable-model-invocation: true` for command-only skills (no auto-trigger)
- `user-invocable: false` to hide from `/` menu (Claude can still invoke via Skill tool)

**Dynamic context injection**: Use `` !`command` `` in the skill body to inject runtime state (git status, file contents, etc.) when the skill loads.

**Extended thinking**: Include "ultrathink" in the skill body for tasks requiring deep reasoning.

## Creating Commands

When user says "add command", "create command", "slash command":

1. Read `references/04-commands/writing-commands.md`
2. Copy template from `templates/command/command.md.template`
3. Key requirements:
   - Frontmatter: description, allowed-tools, argument-hint
   - Support `$ARGUMENTS`, `$1`, `$2` for arguments
   - Prefix lines with exclamation mark for bash execution
   - Prefix lines with at-sign for file references

## Creating Agents

When user says "add agent", "create agent", "make agent":

1. Read `references/05-agents/writing-agents.md`
2. Copy template from `templates/agent/agent.md.template`
3. Key requirements:
   - Frontmatter: name, description, tools, model, permissionMode
   - Description should include "Use proactively" for auto-delegation
   - One agent = one clear responsibility

**Consider these agent-specific features:**
- `memory: project` for agents that benefit from cross-session learning (architecture decisions, code review patterns)
- `memory: user` for personal preferences that carry across projects
- `model:` matched to task complexity — `haiku` for lookup/formatting, `sonnet` for balanced tasks, `opus` for complex reasoning
- `tools` restriction to minimum needed (reduces cost and attack surface)
- `disallowedTools` to block specific tools (e.g., `Edit`, `Write` for read-only agents)
- `hooks` in agent frontmatter for scoped validation (runs only when that agent is active)

**Agent teams**: For tasks benefiting from multiple perspectives or parallel research, consider agent teams (competing perspectives, hypothesis investigation, parallel tasks). See `references/05-agents/agent-patterns.md` for team patterns. Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`.

## Creating Hooks

When user says "add hooks", "setup hooks", "event handlers":

1. Read `references/06-hooks/writing-hooks.md`
2. Read `references/06-hooks/hook-events.md` for all 29 events
3. Copy template from `templates/hooks/hooks.json.template`
4. Key events:
   - `Setup` - one-time `--init-only` / `--init -p` / `--maintenance -p` preparation. **Distinct from `SessionStart`**: Setup does NOT fire on every launch, so a plugin that needs a dependency installed cannot rely on Setup alone — pair with a `${CLAUDE_PLUGIN_DATA}` "check on first use, install on miss" pattern.
   - `PreToolUse` - before tool execution (can block)
   - `PostToolUse` - after tool execution (formatting, logging). Use the `updatedToolOutput` JSON return field to rewrite what Claude sees (replaces the older MCP-only `updatedMCPToolOutput`).
   - `PostToolBatch` - after a parallel batch resolves (one-shot summary)
   - `SessionStart` - setup, output directories
   - `SessionEnd` - cleanup
   - `UserPromptSubmit` - validation, context injection (can block)
   - `UserPromptExpansion` - intercept direct `/skillname` invocations (can block)
   - `SubagentStart`/`SubagentStop` - agent lifecycle
   - `WorktreeCreate`/`WorktreeRemove` - replace default git worktree behavior with custom VCS logic (SVN/Perforce/Mercurial). Input: `name` via stdin; `WorktreeCreate` must print the worktree path on stdout, and any non-zero exit aborts creation.
   - `PreCompact` - inject context before compaction
   - `Notification`, `Stop`, `TaskCompleted`, `TeammateIdle`

**Adaptive hooks**: Hook stdin JSON includes an `effort` object (`{ "level": ... }`) on tool-use-context events; the same level is exported as `$CLAUDE_EFFORT` to command hooks and the Bash tool. Use it to adapt verbosity, recursion depth, or external-call budget to the user's effort setting.

**Exec form vs shell form** (v2.1.139+): Command hooks run in **exec form** when `args` is set — `command` resolves as an executable and is spawned directly with each `args` element passed as one argument, no shell tokenization, no quoting. Prefer exec form for any hook that references a path placeholder (`${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PROJECT_DIR}`, `${CLAUDE_PLUGIN_DATA}`). Omit `args` to fall back to shell form when you need pipes, `&&`, or redirects.

**No controlling terminal** (v2.1.139+): On macOS and Linux, command hooks run without `/dev/tty`. To surface a message, return `systemMessage` in JSON stdout; to ring the bell or fire a desktop notification, return `terminalSequence` (allowlisted OSC sequences). All hook output is capped at 10,000 characters — longer output is replaced with a file-path preview.

**Five handler types** — choose the right one:
- `command` — shell script, fastest, no LLM cost. Use for logging, file ops, env setup.
- `http` — POST event JSON to a webhook (settings.json only). Use for external services.
- `mcp_tool` — call a tool on an already-connected MCP server, no shell. Use to file an issue, sync state, log to an external system without spawning a process.
- `prompt` — single-turn LLM evaluation, zero script overhead. Use for lightweight validation.
- `agent` — multi-turn subagent with tools (Read, Grep, Glob). **Experimental** upstream — behavior may change.

**Async execution**: Add `"async": true` on command hooks for background operations (logging, analytics) that shouldn't block the main flow.

**MCP tool matching**: Use `mcp__<server>__<tool>` pattern in matchers for PreToolUse/PostToolUse.

## Configuring Plugin

When user says "configure plugin", "setup plugin.json":

1. Read `references/08-configuration/plugin-json.md` for full schema
2. Required fields: `name`
3. Recommended fields: `$schema` (SchemaStore JSON Schema for editor autocomplete), `version`, `description`, `author`, `license`
4. Component paths: `commands` (array), `agents` (array — string form no longer accepted), `hooks`, `mcpServers`
5. **Experimental components** (`themes`, `monitors`) belong under `experimental.*`. Top-level `themes` / `monitors` still load but `claude plugin validate` warns and a future release will require the nested form. The validator (`/plugin-creation-tools:validate`) flags top-level usage and offers an auto-migration diff.
6. **Niche but valid manifest fields**: `channels` (Telegram/Slack/Discord-style message injection — each entry binds to one of the plugin's `mcpServers`); `bin/` directory auto-discovered (executables there are added to the Bash tool's `PATH` while the plugin is enabled — chmod +x; useful for CLI helpers users invoke directly, distinct from `hooks/` which are event-driven). Plugin-root `settings.json` supports two keys: `agent` (activates one of the plugin's agents as the main thread agent) and `subagentStatusLine` (default status-line config for subagents). See `references/08-configuration/plugin-json.md` and `references/08-configuration/settings.md`.

### Suppressing a plugin skill without forking

Users who want to silence a single plugin skill don't need to uninstall the plugin or edit its SKILL.md. Two escape hatches, in priority order:

- **`skillOverrides` setting** (`.claude/settings.local.json`) — four states: `on` / `name-only` / `user-invocable-only` / `off`. The `/skills` menu writes this for them. Note: upstream caveat is that `skillOverrides` does NOT affect plugin-shipped skills — for those, point users at `/plugin disable` for the whole plugin. Surface this in your README's troubleshooting section.
- **`/plugin disable <name>@<marketplace>`** for the entire plugin, scoped per scope (user/project/local).

See `references/08-configuration/settings.md#skilloverrides` for details.

## Settings and Output

When user says "configure settings", "setup output", "output directory":

1. Read `references/08-configuration/settings.md` for settings hierarchy
2. Read `references/08-configuration/output-config.md` for output patterns
3. Key environment variables:
   - `${CLAUDE_PLUGIN_ROOT}` - plugin installation directory
   - `${CLAUDE_PROJECT_DIR}` - project root
   - `${CLAUDE_ENV_FILE}` - persistent env vars (SessionStart only)
4. Use SessionStart hook to create output directories

## Testing Plugin

When user says "test plugin", "validate plugin":

1. Read `references/09-testing/testing.md`
2. Run `claude --debug` to see plugin loading
3. Validate plugin.json syntax
4. Test each component:
   - Skills: Ask questions matching description
   - Commands: Run `/command-name`
   - Agents: Check `/agents` listing
   - Hooks: Trigger events manually

## Packaging for Marketplace

When user says "package plugin", "publish plugin", "marketplace":

1. Read `references/10-distribution/packaging.md`
2. Create `marketplace.json` in repository root
3. Update README with installation instructions
4. Version using semantic versioning (MAJOR.MINOR.PATCH)

## Decision Framework

Before creating a component, verify it's the right choice:

| Component | Use When |
|-----------|----------|
| Skill | Complex workflow, needs resources, auto-triggered by context |
| Command | User should trigger explicitly, quick one-off prompts |
| Agent | Specialized expertise, own context window, proactive delegation |
| Hook | Event-based automation, validation, logging |
| MCP | External API/service, custom tools, database access |

**The 5-10 Rule**: Done 5+ times? Will do 10+ more? Create a skill or command.

## References

### Overview
- `references/01-overview/what-are-plugins.md` - Plugin overview
- `references/01-overview/what-are-skills.md` - Skills overview
- `references/01-overview/what-are-commands.md` - Commands overview
- `references/01-overview/what-are-agents.md` - Agents overview
- `references/01-overview/what-are-hooks.md` - Hooks overview
- `references/01-overview/what-are-mcp.md` - MCP overview
- `references/01-overview/component-comparison.md` - When to use what

### Philosophy
- `references/02-philosophy/core-philosophy.md` - Design principles
- `references/02-philosophy/decision-frameworks.md` - Decision trees
- `references/02-philosophy/anti-patterns.md` - What to avoid

### Components
- `references/03-skills/anthropic-skill-standards.md` - Official Anthropic skill standards and checklist
- `references/03-skills/skill-patterns.md` - Five skill patterns (Sequential, Multi-MCP, Iterative, Context-Aware, Domain-Specific)
- `references/03-skills/` - Skill creation guides
- `references/04-commands/` - Command creation guides
- `references/05-agents/` - Agent creation guides
- `references/06-hooks/` - Hook creation guides
- `references/06-hooks/cross-platform-hooks.md` - Windows/macOS/Linux support
- `references/07-mcp/` - MCP overview

### Configuration
- `references/08-configuration/plugin-json.md` - Plugin manifest (incl. `userConfig` schema with `type`/`title` fields, `themes` component path)
- `references/08-configuration/marketplace-json.md` - Marketplace config (incl. `allowCrossMarketplaceDependenciesOn`, `claude plugin tag`)
- `references/08-configuration/themes.md` - Plugin themes (`themes/*.json`, base + overrides, `Ctrl+E` user-copy flow)
- `references/08-configuration/settings.md` - Settings hierarchy (incl. `prUrlTemplate`)
- `references/08-configuration/output-config.md` - Output configuration

### Testing & Distribution
- `references/09-testing/testing.md` - Testing guide (all components)
- `references/09-testing/debugging.md` - Debugging guide
- `references/09-testing/cli-reference.md` - CLI commands reference
- `references/10-distribution/packaging.md` - Packaging guide
- `references/10-distribution/marketplace.md` - Marketplace guide
- `references/10-distribution/versioning.md` - Version strategy
- `references/10-distribution/complete-examples.md` - Full plugin examples

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| Plugin doesn't appear after install | Components placed inside `.claude-plugin/` instead of plugin root | Move `commands/` / `agents/` / `skills/` / `hooks/` to the plugin root. Only `plugin.json` belongs in `.claude-plugin/`. |
| Skill exists but Claude never invokes it | Description missing trigger phrase or imperatives | Rewrite to start with "Use when…", include WHAT and WHEN, preserve any `PROACTIVELY` / `MUST` / `NEVER` markers from the prior version. Run `skill-quality-reviewer` agent to audit. |
| Hook configured but never fires | Wrong event name (case-sensitive) or `http` handler in `hooks/hooks.json` | Verify event name is exactly one of the 29 documented in `references/06-hooks/hook-events.md`. `http` handlers only work in `settings.json` — they are silently ignored in `hooks.json`. Run `/plugin-creation-tools:validate`. |
| Hook spawns on every Bash call but only acts on `rm` | Filtering inside the script instead of with `if` | Add `if: "Bash(rm *)"` to the handler. The matcher fires the event; `if` is a cheap pre-spawn filter that avoids the "spawn-and-exit-0" anti-pattern. See `references/06-hooks/writing-hooks.md#the-if-field`. |
| `mcp_tool` hook returns "not connected" on first run | `SessionStart` / `Setup` typically fire before MCP servers finish connecting | Expected on first run. Either accept the non-blocking error, or move the call to a later event (`PostToolUse`, `Stop`, etc.) where the server is reliably connected. |
| Plugin theme doesn't appear in `/theme` | `themes/*.json` missing `name` / `base` / `overrides`, or invalid JSON | Run `/plugin-creation-tools:validate`. See `references/08-configuration/themes.md` for the schema. |
| Cross-marketplace dependency rejected at install | Root marketplace's `marketplace.json` is missing `allowCrossMarketplaceDependenciesOn` | Add the target marketplace name to the root marketplace's `allowCrossMarketplaceDependenciesOn` array. Trust does not chain — only the **root** marketplace's allowlist is consulted. See `references/08-configuration/marketplace-json.md`. |
| Version mismatch errors after release | `version` drifted between `plugin.json` and the marketplace entry | Bump both. The validator enforces this. Use `claude plugin tag` (run from inside the plugin folder) to create the `{plugin-name}--v{version}` git tag dependents resolve against. |
| Frontmatter `hooks` / `mcpServers` ignored on a plugin agent | Plugin-packaged agents silently strip `hooks` / `mcpServers` / `permissionMode` for security | Move the hooks to `hooks/hooks.json` at the plugin root, or scope them via SKILL.md frontmatter. (For agents launched via `--agent` from project-local `.claude/agents/`, those fields fire as of v2.1.117+.) |
| `--debug` shows the plugin loading but components missing | Custom `commands` / `agents` / `outputStyles` / `experimental.themes` / `experimental.monitors` paths in `plugin.json` **replace** defaults — they don't supplement. (`skills` is the only exception — it **adds** to the default `skills/` directory.) | When you set a custom path for a "Replaces the default" field, the default directory is no longer scanned. Either remove the override or include the default path in the array. **v2.1.140+ surfaces the ignored folder in `/doctor`, `claude plugin list`, and the `/plugin` detail view** — those tools name the folder being skipped, which is the fastest way to spot a misconfigured manifest. |

For a symptom-first walkthrough of "what state is the runtime actually in," see the upstream **Debug Your Config** guide (`/context`, `/memory`, `/doctor`, `/hooks`, `/mcp`, `/skills`, `/permissions`, `/status`).

## Examples

Working example plugins in `examples/`:
- `examples/simple-greeter-plugin/` - Minimal plugin with one skill
- `examples/full-featured-plugin/` - Complete plugin with skill, commands, hooks

## Templates

All templates are in the `templates/` directory:
- `templates/skill/SKILL.md.template`
- `templates/command/command.md.template`
- `templates/agent/agent.md.template`
- `templates/hooks/hooks.json.template`
- `templates/hooks/run-hook.cmd.template` - Cross-platform hook wrapper
- `templates/plugin.json.template`
- `templates/marketplace.json.template`
- `templates/settings.json.template`
- `templates/mcp.json.template`

## Scripts

- `scripts/init_plugin.py` - Initialize new plugin with selected components
- `scripts/init_skill.py` - Initialize standalone skill
- `scripts/validate_skill.py` - Validate skill structure
- `scripts/package_skill.py` - Package skill for distribution
