# Full-Featured Example Plugin

A complete example plugin demonstrating all component types: skills, commands, and hooks with cross-platform support.

## Structure

```
full-featured-plugin/
├── .claude-plugin/
│   ├── plugin.json           # Plugin manifest
│   └── marketplace.json      # For local testing
├── skills/
│   └── code-helper/
│       ├── SKILL.md          # Main skill
│       └── references/
│           └── patterns.md   # Reference documentation
├── commands/
│   ├── status.md             # /status command
│   └── review.md             # /review command
├── hooks/
│   ├── hooks.json            # Hook configuration
│   ├── run-hook.cmd          # Cross-platform wrapper
│   ├── session-start.sh      # SessionStart hook
│   └── post-edit.sh          # PostToolUse hook
└── README.md
```

## Components

### Skill: code-helper
- Triggers on code review requests
- Uses reference files for patterns
- Provides code quality guidance

### Commands
- `/status` - Show project status (git, TODOs)
- `/review [file]` - Review code for issues

### Hooks
- `SessionStart` - Creates output directories, logs session
- `PostToolUse (Write|Edit)` - Logs file operations

## Cross-Platform Support

The hooks use a polyglot wrapper (`run-hook.cmd`) that works on:
- **Windows** - Uses Git Bash via CMD
- **macOS/Linux** - Runs bash directly

This pattern ensures the plugin works everywhere.

## Installation (Local Testing)

```bash
# Add the plugin as a local marketplace
/plugin marketplace add /path/to/full-featured-plugin

# Install the plugin
/plugin install full-featured-example@full-featured-dev

# Restart Claude Code
```

## Usage

### Use the skill
Ask Claude to review code:
```
Review my code for quality issues
```

### Use commands
```
/status
/review src/main.py
```

### Hooks run automatically
- Session logs appear in `claude-outputs/logs/session.log`
- Edit operations logged in `claude-outputs/logs/operations.log`

## What This Example Demonstrates

1. **Skill with references** - SKILL.md + references/ pattern
2. **Commands with arguments** - Using `$1` and `$ARGUMENTS`
3. **Cross-platform hooks** - The polyglot `.cmd` wrapper
4. **Output directory setup** - SessionStart hook pattern
5. **Operation logging** - PostToolUse hook pattern
6. **Local development** - marketplace.json for testing

## Extending This Example

Ideas for customization:
- Add MCP server for external integrations
- Add more commands for your workflow
- Add agents for specialized tasks
- Customize the code patterns in references/
- Add formatter script called by post-edit hook

## Configuration

Set environment variables in `.claude/settings.json`:

```json
{
  "env": {
    "FULLFEATURE_LOG_LEVEL": "debug"
  }
}
```
