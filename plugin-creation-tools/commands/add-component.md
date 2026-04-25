---
description: Add a skill, command, agent, hook, MCP server, or theme to an existing plugin. Use when user says "add skill", "add command", "add agent", "add hook", "add MCP", "add theme", "new component", or wants to extend an existing plugin with additional functionality.
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
argument-hint: <component-type> <name>
context: fork
---

# Add Component

Add a new component to an existing Claude Code plugin.

## Steps

1. Parse arguments: `$1` = component type, `$2` = component name
2. If missing arguments, ask user for component type and name
3. Find the plugin root (look for `.claude-plugin/plugin.json` in current or parent directories)
4. Validate the component name (hyphen-case, max 64 chars)
5. Scaffold the component from templates
6. Guide user to complete the component

## Component Types

### `skill`
1. Create `skills/$2/SKILL.md` from `templates/skill/SKILL.md.template`
2. Create `skills/$2/references/` directory
3. Remind: SKILL.md is instructions for Claude, not documentation
4. Consider: `model:` field, dynamic context injection, `context: fork` for heavy ops

### `command`
1. Create `commands/$2.md` from `templates/command/command.md.template`
2. Remind: set `allowed-tools` to minimum needed
3. Remind: use `$ARGUMENTS`, `$1`, `$2` for argument handling

### `agent`
1. Create `agents/$2.md` from `templates/agent/agent.md.template`
2. Remind: description must include delegation triggers ("Use proactively when...")
3. Consider: `memory: project` for cross-session learning
4. Consider: `model:` matched to task complexity (haiku for simple, opus for complex)
5. Consider: `tools` restriction to minimum needed
6. Consider: `hooks` in agent frontmatter for scoped validation

### `hook`
1. If `hooks/hooks.json` exists, add new event entry
2. If not, create from `templates/hooks/hooks.json.template`
3. Ask which event(s) to handle (28 available — see `references/06-hooks/hook-events.md`)
4. Consider the five handler types: `command` (shell, fastest), `mcp_tool` (call an already-connected MCP server tool — no shell, cross-platform-safe), `prompt` (single-turn LLM), `agent` (multi-turn subagent — **experimental**), `http` (POST to webhook — **settings.json only**, will be silently ignored in `hooks.json`)
5. For cross-platform support when shell logic is genuinely needed, use `templates/hooks/run-hook.cmd.template`. If the hook only calls an MCP server, use `type: "mcp_tool"` instead — it removes the cross-platform footgun.

### `mcp`
1. Create or update `.mcp.json` from `templates/mcp.json.template`
2. Guide user to configure server command and args

### `theme`
1. Create `themes/$2.json` with `name`, `base`, `overrides` fields (see `references/08-configuration/themes.md`)
2. Default `base` to `"dark"`; keep `overrides` sparse (only the tokens you actually change)
3. Remind: theme appears in `/theme` once the plugin is enabled, persisted as `custom:<plugin-name>:$2` when the user selects it
4. Remind: users press `Ctrl+E` to copy the plugin theme into `~/.claude/themes/` for editing — your bundled file is read-only in the picker

## After Adding

1. Update `.claude-plugin/plugin.json` if component paths need explicit configuration
2. Test the new component: `claude --debug` to verify loading
3. For skills: verify auto-trigger by asking matching questions
4. For commands: verify `/plugin-name:command-name` works
5. For agents: verify in `/agents` listing

## Arguments

- `$1`: Component type (skill, command, agent, hook, mcp, theme)
- `$2`: Component name (hyphen-case)
