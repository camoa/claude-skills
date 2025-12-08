# What Are Claude Code Plugins?

Marketplace plugins are extensible packages that add custom functionality to Claude Code. They can be discovered, installed, and managed through plugin marketplaces—catalogs distributed via Git repositories, GitHub, or local paths.

## Why Use Plugins?

- **Team Standardization**: Share tools and workflows across projects
- **Easy Distribution**: Distribute through marketplaces
- **Encapsulation**: Package multiple components together
- **Reusability**: Use same plugin across different projects
- **Discoverability**: Browse and install from centralized catalogs
- **Version Management**: Track and update plugin versions

## What Plugins Can Contain

Plugins can contain up to 5 core component types:

| Component | Location | Format | Invocation | Best For |
|-----------|----------|--------|-----------|----------|
| Commands | `commands/` | Markdown | User (`/command`) | Quick, frequently used prompts |
| Agents | `agents/` | Markdown | Auto + Manual | Task-specific expertise |
| Skills | `skills/` | Directory + SKILL.md | Model-invoked | Complex workflows with files |
| Hooks | `hooks/hooks.json` | JSON | Event-triggered | Automation and validation |
| MCP Servers | `.mcp.json` | JSON | Auto startup | External tool integration |

## Plugin Structure

```
plugin-name/
├── .claude-plugin/
│   └── plugin.json          # REQUIRED - plugin manifest
├── commands/                 # Slash commands (optional)
├── agents/                   # Custom agents (optional)
├── skills/                   # Agent skills (optional)
│   └── skill-name/
│       └── SKILL.md
├── hooks/                    # Event hooks (optional)
│   └── hooks.json
├── .mcp.json                 # MCP servers (optional)
├── scripts/                  # Utility scripts
├── README.md
└── CHANGELOG.md
```

## Required vs Optional

**Required**:
- `.claude-plugin/plugin.json` - the plugin manifest

**Optional (at least one recommended)**:
- Commands, Agents, Skills, Hooks, or MCP servers

## Plugin vs Other Extension Methods

| Extension | Use Case |
|-----------|----------|
| **Plugin** | Distribute multiple components, team sharing |
| **Project CLAUDE.md** | Project-specific context |
| **User ~/.claude/CLAUDE.md** | Personal preferences |
| **Standalone MCP** | External tool without plugin wrapper |

## Key Points

- Plugins are the **primary distribution mechanism** for sharing custom tools
- Support **semantic versioning** for tracking updates
- Can be hosted on GitHub, GitLab, or any git hosting
- **Enterprise policy management** available for organizations
- Full **CLI control** for automation

## See Also

- `component-comparison.md` - deciding which components to use
- `../08-configuration/plugin-json.md` - plugin manifest schema
- `../10-distribution/marketplace.md` - distributing plugins
