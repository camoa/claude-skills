# plugin-creation

Complete guide for creating Claude Code plugins - skills, commands, agents, hooks, MCP servers, settings, and output configuration.

## Triggers

This skill activates when you say:
- "Create a plugin" / "Make a new plugin"
- "Add a skill" / "Create skill"
- "Add a command" / "Create command"
- "Make an agent" / "Add agent"
- "Add hooks" / "Setup hooks"
- "Configure plugin" / "Setup plugin.json"
- "Package for marketplace"

## Commands

| Command | Description |
|---------|-------------|
| `/plugin-creation-tools:create` | Create a new plugin with selected components |
| `/plugin-creation-tools:validate` | Validate plugin structure and best practices |
| `/plugin-creation-tools:add-component` | Add a skill, command, agent, or hook to an existing plugin |

## Quick Start

### Create a New Plugin

```
/plugin-creation-tools:create my-tools --skill --command
```

Or describe what you need:
```
Create a plugin called "my-tools" with a command and a skill
```

The skill will guide you through:
1. Creating the directory structure
2. Setting up plugin.json
3. Creating each component
4. Testing and validation
5. Packaging for distribution

### Add Components to Existing Plugin

```
/plugin-creation-tools:add-component agent security-reviewer
```

Or describe what you need:
```
Add a hook that formats code after every write
```

### Validate a Plugin

```
/plugin-creation-tools:validate ./my-plugin
```

## What This Skill Covers

| Component | Description |
|-----------|-------------|
| **Skills** | Model-invoked workflows with supporting files |
| **Commands** | User-invoked slash commands (`/command`) |
| **Agents** | Specialized assistants with own context |
| **Hooks** | Event-triggered automation (14 event types, 3 handler types) |
| **MCP Servers** | External tool integration |
| **Settings** | Configuration hierarchy and permissions |
| **Output** | Directory setup and logging patterns |

## Structure

```
plugin-creation/
├── SKILL.md           # Main workflow (read first)
├── README.md          # This file
├── templates/         # Starter templates (8 files)
│   ├── skill/
│   ├── command/
│   ├── agent/
│   ├── hooks/
│   └── *.template
├── references/        # Detailed guides (38 files)
│   ├── 01-overview/   # What each component is
│   ├── 02-philosophy/ # Design principles
│   ├── 03-skills/     # Skill-specific guides
│   ├── 04-commands/   # Command guides
│   ├── 05-agents/     # Agent guides
│   ├── 06-hooks/      # Hook guides
│   ├── 07-mcp/        # MCP overview
│   ├── 08-configuration/  # Settings, output
│   ├── 09-testing/    # Testing and CLI reference
│   └── 10-distribution/   # Packaging and marketplace
└── scripts/           # Utility scripts
```

## Usage Examples

### Example 1: Create a formatting plugin

```
Create a plugin that automatically formats code after every edit
```

Result: Plugin with PostToolUse hook running a formatter script.

### Example 2: Create a code review plugin

```
Create a plugin with a security-reviewer agent and a /review command
```

Result: Plugin with agent for auto-delegation and command for manual invocation.

### Example 3: Add skill to existing plugin

```
Add a PDF processing skill to my document-tools plugin
```

Result: New skill directory with SKILL.md and supporting files.

## CLI Reference

```bash
# Add marketplace
/plugin marketplace add camoa/claude-skills

# Install this plugin
/plugin install plugin-creation-tools@camoa-skills

# Verify installation
/help                    # Check commands
/agents                  # Check agents
claude --debug           # Check loading

# Validate your plugin
claude plugin validate ./my-plugin
```

## Official Documentation

- [Plugins Guide](https://code.claude.com/docs/en/plugins)
- [Plugin Reference](https://code.claude.com/docs/en/plugins-reference)
- [Marketplaces](https://code.claude.com/docs/en/plugin-marketplaces)
- [Settings](https://code.claude.com/docs/en/settings)
- [Agent Skills](https://code.claude.com/docs/en/skills)

## Related Tools

- [Anthropic Skills](https://github.com/anthropics/skills) - Official skill-creator
- [Superpowers](https://github.com/obra/superpowers-marketplace) - TDD skill development
- [Skill Seeker MCP](https://github.com/camoa/skill-seeker) - Automated doc scraping
