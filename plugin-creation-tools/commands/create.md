---
description: Create a new Claude Code plugin or standalone skill with selected components. Use when user says "create plugin", "new plugin", "initialize plugin", "start a plugin", "make a skill plugin", "scaffold plugin", or wants to package any reusable Claude Code behavior.
allowed-tools: Read, Write, Bash, Glob, AskUserQuestion
argument-hint: <plugin-name> [--skill|--command|--agent|--hook|--mcp]
---

# Create Plugin

Create a new Claude Code plugin with any combination of components.

## Steps

1. Parse `$ARGUMENTS`: the first non-`--` token is the plugin name; `--` tokens are component flags. (Claude Code's `$N` placeholders are **0-based** — `$0` is the first argument — so do not read `$1` for the plugin name; parse `$ARGUMENTS` for the first non-flag token, or use `$0`.)
2. If no arguments, ask the user for plugin name and desired components
3. Validate plugin name (lowercase, hyphens, max 64 chars)
4. Ask user for target directory if not obvious from context
5. Run the init script (substitute the parsed plugin name for `<plugin-name>`):
   ```
   python3 ${CLAUDE_PLUGIN_ROOT}/skills/plugin-creation/scripts/init_plugin.py <plugin-name> --path <target> --components <list>
   ```
6. After scaffolding, load the plugin-creation skill for guidance on completing each component
7. Read `references/02-philosophy/core-philosophy.md` for design principles

## Component Selection Guide

If user doesn't specify components, ask which they need:

| Component | Choose when... |
|-----------|---------------|
| Skill | Complex workflow, auto-triggered by context, needs reference files |
| Command | User-triggered via `/name`, quick prompts, explicit invocation |
| Agent | Specialized expertise, own context window, auto-delegated |
| Hook | Event-based automation, validation, logging, no LLM involved |
| MCP | External API/database integration, custom tools |

## Post-Creation Guidance

After creating, guide the user to:
1. Edit `.claude-plugin/plugin.json` - update description and metadata
2. Complete each component file using the plugin-creation skill's references
3. Set up `.claude/rules/` if the plugin needs path-scoped rules
4. Consider agent `memory:` and `model:` settings for agents
5. Consider `model:` for cost optimization on skills
6. Test locally: `/plugin marketplace add <path> && /plugin install`

## Arguments

- **Plugin name**: first non-`--` token in `$ARGUMENTS` (equivalently `$0` — `$N` is 0-based). Hyphen-case, e.g. `my-tools`.
- **Component flags**: the `--skill` / `--command` / `--agent` / `--hook` / `--mcp` tokens in `$ARGUMENTS`.
