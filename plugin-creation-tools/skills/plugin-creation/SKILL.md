---
name: plugin-creation
description: Use when creating Claude Code plugins - covers skills, commands, agents, hooks, MCP servers, and plugin configuration. Use when user says "create plugin", "make a skill", "add command", "add hooks", etc.
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

## Plugin Initialization

When user says "create plugin", "initialize plugin", "new plugin":

1. Create plugin directory structure:
   ```
   plugin-name/
   ├── .claude-plugin/
   │   └── plugin.json
   ├── commands/        # if needed
   ├── agents/          # if needed
   ├── skills/          # if needed
   │   └── skill-name/
   │       └── SKILL.md
   ├── hooks/           # if needed
   │   └── hooks.json
   └── .mcp.json        # if needed
   ```

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

## Creating Commands

When user says "add command", "create command", "slash command":

1. Read `references/04-commands/writing-commands.md`
2. Copy template from `templates/command/command.md.template`
3. Key requirements:
   - Frontmatter: description, allowed-tools, argument-hint
   - Support `$ARGUMENTS`, `$1`, `$2` for arguments
   - Use `!` prefix for bash execution
   - Use `@` prefix for file references

## Creating Agents

When user says "add agent", "create agent", "make agent":

1. Read `references/05-agents/writing-agents.md`
2. Copy template from `templates/agent/agent.md.template`
3. Key requirements:
   - Frontmatter: name, description, tools, model, permissionMode
   - Description should include "Use proactively" for auto-delegation
   - One agent = one clear responsibility

## Creating Hooks

When user says "add hooks", "setup hooks", "event handlers":

1. Read `references/06-hooks/writing-hooks.md`
2. Read `references/06-hooks/hook-events.md` for event types
3. Copy template from `templates/hooks/hooks.json.template`
4. Key events:
   - `PreToolUse` - before tool execution
   - `PostToolUse` - after tool execution (formatting, logging)
   - `SessionStart` - setup, output directories
   - `SessionEnd` - cleanup
   - `UserPromptSubmit` - validation, context injection

## Configuring Plugin

When user says "configure plugin", "setup plugin.json":

1. Read `references/08-configuration/plugin-json.md` for full schema
2. Required fields: `name`
3. Recommended fields: `version`, `description`, `author`, `license`
4. Component paths: `commands`, `agents`, `hooks`, `mcpServers`

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
- `references/03-skills/` - Skill creation guides
- `references/04-commands/` - Command creation guides
- `references/05-agents/` - Agent creation guides
- `references/06-hooks/` - Hook creation guides
- `references/07-mcp/` - MCP overview

### Configuration
- `references/08-configuration/plugin-json.md` - Plugin manifest
- `references/08-configuration/marketplace-json.md` - Marketplace config
- `references/08-configuration/settings.md` - Settings hierarchy
- `references/08-configuration/output-config.md` - Output configuration

### Testing & Distribution
- `references/09-testing/testing.md` - Testing guide
- `references/09-testing/debugging.md` - Debugging guide
- `references/10-distribution/packaging.md` - Packaging guide
- `references/10-distribution/marketplace.md` - Marketplace guide
- `references/10-distribution/versioning.md` - Version strategy

## Templates

All templates are in the `templates/` directory:
- `templates/skill/SKILL.md.template`
- `templates/command/command.md.template`
- `templates/agent/agent.md.template`
- `templates/hooks/hooks.json.template`
- `templates/plugin.json.template`
- `templates/marketplace.json.template`
- `templates/settings.json.template`
- `templates/mcp.json.template`
