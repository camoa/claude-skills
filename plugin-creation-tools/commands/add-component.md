---
description: Add a skill, command, agent, or hook to an existing plugin
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
argument-hint: <component-type> <name>
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
3. Ask which event(s) to handle
4. Consider all three handler types: `command`, `prompt`, `agent`
5. For cross-platform support, use `templates/hooks/run-hook.cmd.template`

### `mcp`
1. Create or update `.mcp.json` from `templates/mcp.json.template`
2. Guide user to configure server command and args

## After Adding

1. Update `.claude-plugin/plugin.json` if component paths need explicit configuration
2. Test the new component: `claude --debug` to verify loading
3. For skills: verify auto-trigger by asking matching questions
4. For commands: verify `/plugin-name:command-name` works
5. For agents: verify in `/agents` listing

## Arguments

- `$1`: Component type (skill, command, agent, hook, mcp)
- `$2`: Component name (hyphen-case)
