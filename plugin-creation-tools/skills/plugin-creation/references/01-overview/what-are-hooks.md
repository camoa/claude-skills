# What Are Hooks (Event Handlers)?

Hooks are automatic event handlers that execute actions in response to Claude Code events. They run shell commands or LLM-based evaluation when specific events occur.

## Key Characteristics

- Event-triggered execution
- Support multiple event types
- Can match specific tools or be global
- Support bash commands and LLM-based evaluation
- Useful for automation, validation, logging
- Run in parallel

## When to Use Hooks

**Good Use Cases**:
- Automatic code formatting after file writes
- Validation before tool execution
- Logging and audit trails
- Session setup and cleanup
- Context injection
- Security enforcement

**Examples**:
- Format code after Write/Edit operations
- Run linters before commits
- Set up output directories at session start
- Log all file modifications
- Validate prompt inputs

## Hook Event Types

| Event | Use Case | Matcher |
|-------|----------|---------|
| PreToolUse | Control execution before tools run | Yes |
| PostToolUse | Logging, validation after tools | Yes |
| SessionStart | Setup, initialization | Yes |
| SessionEnd | Cleanup | Yes |
| UserPromptSubmit | Validate input, inject context | No |
| PermissionRequest | Auto-approve/deny tools | Yes |
| Notification | Handle alerts | Yes |
| Stop | Decide if Claude should continue | No |
| SubagentStop | Check if subagent task complete | No |
| PreCompact | Before conversation compaction | Yes |

## Hook Types

1. **Command**: Execute bash scripts
2. **Validation**: File/input validation
3. **Notification**: Send alerts
4. **Prompt**: LLM-based decisions

## File Location

```
plugin-name/
└── hooks/
    └── hooks.json
```

Or inline in `plugin.json`.

## Basic Format

```json
{
  "description": "Automatic formatting hooks",
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/format.sh",
            "timeout": 30
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh"
          }
        ]
      }
    ]
  }
}
```

## Environment Variables

- `${CLAUDE_PLUGIN_ROOT}` - Plugin directory path
- `${CLAUDE_PROJECT_DIR}` - Project root directory
- `${CLAUDE_ENV_FILE}` - (SessionStart only) Path to persist env vars

## Matcher Patterns

| Pattern | Behavior | Example |
|---------|----------|---------|
| Exact | Matches exactly | `Write` |
| Regex | Pattern match | `Write\|Edit` |
| Wildcard | All tools | `*` |
| Empty | No matching | Omit matcher |

## See Also

- `../06-hooks/writing-hooks.md` - how to write hooks
- `../06-hooks/hook-events.md` - event details
- `../06-hooks/hook-patterns.md` - common patterns
