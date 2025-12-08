# Quick Reference

Templates and guidelines for rapid plugin development.

## Component Overview

| Component | Location | Invocation | Best For |
|-----------|----------|------------|----------|
| Skills | `skills/name/SKILL.md` | Model-invoked | Complex workflows |
| Commands | `commands/name.md` | User (`/command`) | Quick prompts |
| Agents | `agents/name.md` | Auto + Manual | Task expertise |
| Hooks | `hooks/hooks.json` | Event-triggered | Automation |
| MCP | `.mcp.json` | Auto startup | External tools |

## Plugin Structure

```
plugin-name/
├── .claude-plugin/
│   └── plugin.json          # Required
├── commands/
│   └── command.md
├── agents/
│   └── agent.md
├── skills/
│   └── skill-name/
│       └── SKILL.md
├── hooks/
│   └── hooks.json
├── scripts/
│   └── script.sh
├── .mcp.json
├── README.md
└── CHANGELOG.md
```

## plugin.json Template

```json
{
  "name": "plugin-name",
  "version": "1.0.0",
  "description": "Brief description",
  "author": { "name": "Your Name" },
  "license": "MIT"
}
```

## SKILL.md Template

```markdown
---
name: skill-name
description: Use when [triggers] - [what it does]
---

# Skill Name

## When to Use
- "[trigger phrase]"
- NOT for: [exclusions]

## Operations

### Operation 1
When user says "[trigger]":
1. Step 1
2. Step 2

## References
- `references/file.md` - Description
```

## Command Template

```markdown
---
description: What it does
allowed-tools: Read, Edit, Bash
argument-hint: [arg1] [arg2]
---

# Command Name

Use $1 for first arg, $ARGUMENTS for all.

1. Step 1
2. Step 2
```

## Agent Template

```markdown
---
name: agent-name
description: What it does. Use proactively when [triggers].
tools: Read, Grep, Glob
model: sonnet
---

# Agent Name

## Role
Expertise description.

## Capabilities
- Capability 1
- Capability 2
```

## hooks.json Template

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/format.sh"
          }
        ]
      }
    ]
  }
}
```

## MCP Template

```json
{
  "server-name": {
    "command": "${CLAUDE_PLUGIN_ROOT}/servers/binary",
    "args": ["--config", "${CLAUDE_PLUGIN_ROOT}/config.json"]
  }
}
```

## Description Patterns

**Skills** (model-invoked):
```
Use when [triggers] - [what it does, third person]
```

**Commands** (user-invoked):
```
[What it does and when to use it]
```

**Agents** (auto-delegated):
```
[Expertise]. Use proactively when [trigger conditions].
```

## Size Guidelines

| Component | Target | Maximum |
|-----------|--------|---------|
| Skill description | 200-500 chars | 1024 chars |
| SKILL.md body | <500 lines | - |
| Reference files | <1000 lines | - |
| Command description | 50-100 chars | - |
| Agent description | 100-200 chars | - |

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `${CLAUDE_PLUGIN_ROOT}` | Plugin directory |
| `${CLAUDE_PROJECT_DIR}` | Project root |
| `${CLAUDE_ENV_FILE}` | Session env file |

## Hook Events

| Event | Use Case |
|-------|----------|
| SessionStart | Setup, initialization |
| SessionEnd | Cleanup |
| PreToolUse | Validation before tools |
| PostToolUse | Formatting, logging |
| UserPromptSubmit | Input validation |

## Validation Checklist

- [ ] plugin.json is valid JSON
- [ ] All markdown has valid frontmatter
- [ ] Scripts are executable
- [ ] No hardcoded paths
- [ ] Commands appear in `/help`
- [ ] Agents appear in `/agents`
- [ ] Skills trigger on matching queries

## CLI Commands

```bash
# Debug mode
claude --debug

# List plugins
/plugin list

# Install plugin
/plugin install name@marketplace

# List agents
/agents

# Help
/help
```
