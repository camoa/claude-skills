# Writing Hooks

Hooks are event handlers that execute automatically when specific events occur in Claude Code. They enable automation, validation, and logging without user intervention.

## File Location

Place hooks configuration in:
```
plugin-name/
└── hooks/
    └── hooks.json
```

Or inline in `plugin.json`:
```json
{
  "name": "my-plugin",
  "hooks": {
    "PostToolUse": [...]
  }
}
```

## Basic Structure

```json
{
  "description": "Description of what these hooks do",
  "hooks": {
    "EventName": [
      {
        "matcher": "ToolPattern",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/action.sh",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

## Hook Configuration Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| matcher | string | No | Pattern to match (regex, exact, or `*`) |
| hooks | array | **Yes** | Array of hook actions |
| type | string | **Yes** | Hook type (command, validation, notification, prompt) |
| command | string | Depends | Shell command to execute |
| timeout | number | No | Timeout in seconds (default varies) |
| prompt | string | Depends | LLM prompt (for prompt type) |

## Hook Types

### Command Hook

Execute a bash script:

```json
{
  "type": "command",
  "command": "${CLAUDE_PLUGIN_ROOT}/scripts/format.sh",
  "timeout": 30
}
```

### Validation Hook

Validate input/output:

```json
{
  "type": "validation",
  "command": "${CLAUDE_PLUGIN_ROOT}/scripts/lint-check.py"
}
```

### Notification Hook

Send alerts:

```json
{
  "type": "notification",
  "command": "${CLAUDE_PLUGIN_ROOT}/scripts/notify.sh"
}
```

### Prompt Hook

LLM-based decision:

```json
{
  "type": "prompt",
  "prompt": "Evaluate if the task is complete based on: $ARGUMENTS",
  "timeout": 30
}
```

## Matcher Patterns

| Pattern | Behavior | Example |
|---------|----------|---------|
| Exact | Matches exactly | `Write` |
| Regex | Pattern match | `Write\|Edit` |
| Wildcard | All events | `*` |
| Omit | Global (no filter) | Don't include field |

Examples:
```json
// Match Write tool only
"matcher": "Write"

// Match Write OR Edit
"matcher": "Write|Edit"

// Match all tools
"matcher": "*"

// Match Bash commands starting with git
"matcher": "Bash(git:*)"
```

## Environment Variables

Available in hook scripts:

| Variable | Description |
|----------|-------------|
| `${CLAUDE_PLUGIN_ROOT}` | Plugin installation directory |
| `${CLAUDE_PROJECT_DIR}` | Project root directory |
| `${CLAUDE_ENV_FILE}` | Env file path (SessionStart only) |

## Example: Complete hooks.json

```json
{
  "description": "Code quality and logging hooks",
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh",
            "timeout": 30
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
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/format.sh",
            "timeout": 30
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/cleanup.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

## Hook Scripts

### Basic Script Structure

```bash
#!/bin/bash
# ${CLAUDE_PLUGIN_ROOT}/scripts/format.sh

# Exit on error
set -e

# Read input from stdin if available
if [ -t 0 ]; then
  INPUT=""
else
  INPUT=$(cat)
fi

# Your logic here
echo "Hook executed successfully"

exit 0
```

### Script with Input Processing

```python
#!/usr/bin/env python3
import json
import sys

# Read hook input
input_data = json.load(sys.stdin)

# Process
event = input_data.get("hook_event_name")
tool = input_data.get("tool_name")

# Your logic here
print(f"Processed {event} for {tool}")

sys.exit(0)
```

## Timeout Configuration

| Use Case | Recommended Timeout |
|----------|---------------------|
| Quick validation | 10-15 seconds |
| Formatting | 30 seconds |
| Long-running tasks | 60+ seconds |
| Network operations | 30-60 seconds |

## Best Practices

1. **Use specific matchers** - Avoid `*` for performance
2. **Set appropriate timeouts** - Don't block too long
3. **Handle errors gracefully** - Return meaningful messages
4. **Log for debugging** - Include logging in scripts
5. **Test in isolation** - Run scripts manually first

## See Also

- `hook-events.md` - all available events
- `hook-patterns.md` - common patterns and examples
