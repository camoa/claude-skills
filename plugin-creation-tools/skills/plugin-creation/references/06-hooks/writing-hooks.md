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
| type | string | **Yes** | Hook handler type: `command`, `prompt`, or `agent` |
| command | string | For command | Shell command to execute |
| prompt | string | For prompt/agent | LLM prompt (`$ARGUMENTS` for context) |
| timeout | number | No | Timeout in seconds (default varies by type) |
| async | boolean | No | Run in background (command type only) |

## Hook Handler Types

Three handler types are available. Each serves a different complexity level.

### 1. Command Hook

Execute a shell script. Receives JSON on stdin with event context. Returns exit code + stdout.

```json
{
  "type": "command",
  "command": "${CLAUDE_PLUGIN_ROOT}/scripts/format.sh",
  "timeout": 30
}
```

**Stdin JSON** includes: `hook_event_name`, `tool_name`, `tool_input`, `tool_output` (varies by event).

**Exit codes**: 0 = success/allow, non-zero = failure/block (for blocking events).

**Stdout**: Returned as hook result. For blocking events, specific strings like `approve`, `deny`, or `continue` control behavior.

### 2. Prompt Hook

Single-turn LLM evaluation. Uses Haiku by default for fast, cheap yes/no decisions. Zero script overhead -- no shell process spawned.

```json
{
  "type": "prompt",
  "prompt": "Evaluate if the task is complete based on: $ARGUMENTS",
  "timeout": 30
}
```

**`$ARGUMENTS`**: Replaced with event context (tool input/output, conversation state). Always include this placeholder so the LLM has context.

**Response handling**: The LLM's response is returned as the hook result. For blocking events, the response determines the action (e.g., returning `continue` from a Stop hook).

### 3. Agent Hook

Multi-turn subagent with access to tools (Read, Grep, Glob). Up to 50 turns of autonomous reasoning. Use for complex verification requiring file inspection.

```json
{
  "type": "agent",
  "prompt": "Verify all test files exist and have proper structure for: $ARGUMENTS",
  "timeout": 120
}
```

**Available tools**: Read, Grep, Glob (read-only file access).

**Turns**: Up to 50 turns of tool use and reasoning.

**When to use**: When a prompt hook cannot answer without reading files -- e.g., verifying code changes, checking file existence, validating cross-file consistency.

## Async Hooks

Command hooks can run asynchronously in the background.

```json
{
  "type": "command",
  "command": "${CLAUDE_PLUGIN_ROOT}/scripts/slow-lint.sh",
  "timeout": 120,
  "async": true
}
```

**Behavior**:
- Claude continues immediately without waiting
- Results are delivered on the next conversation turn
- Cannot block tool calls or return decisions (blocking return values are ignored)
- Only available for `command` type (not prompt or agent)

**Use cases**: Long-running linters, external API calls, background logging, notifications to external systems.

## Matcher Patterns

| Pattern | Behavior | Example |
|---------|----------|---------|
| Exact match | Matches tool name exactly | `Write` |
| Regex | Pattern match on tool name | `Write\|Edit` |
| Wildcard | Matches all | `*` |
| Path pattern | Tool + path constraint | `Read(./docs/**)` |
| MCP tool | Server + tool pattern | `mcp__memory__.*` |
| MCP wildcard | Any server, matching tool | `mcp__.*__write.*` |
| Compound | Multiple patterns combined | `Write\|Edit\|mcp__fs__write` |
| Omitted | No filter (fires for all) | Don't include the field |

Examples:
```json
// Match Write tool only
"matcher": "Write"

// Match Write OR Edit
"matcher": "Write|Edit"

// Match Bash commands starting with git
"matcher": "Bash(git:*)"

// Match all tools from memory MCP server
"matcher": "mcp__memory__.*"

// Match any write tool from any MCP server
"matcher": "mcp__.*__write.*"

// Built-in and MCP tools together
"matcher": "Write|Edit|mcp__fs__write_file"

// Read tool scoped to docs directory
"matcher": "Read(./docs/**)"
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
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh",
            "timeout": 30
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/validate-bash.sh"
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
    "Stop": [
      {
        "hooks": [
          {
            "type": "prompt",
            "prompt": "Check if all tasks from the original request are complete. Return 'continue' if more work is needed. $ARGUMENTS"
          }
        ]
      }
    ],
    "TaskCompleted": [
      {
        "hooks": [
          {
            "type": "agent",
            "prompt": "Verify the completed task by inspecting relevant files. Check that changes are correct and complete. $ARGUMENTS",
            "timeout": 120
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
set -e

# Read JSON input from stdin
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

| Handler Type | Default | Recommended Range |
|-------------|---------|-------------------|
| command | 30s | 10-60s |
| command (async) | 120s | 30-300s |
| prompt | 30s | 10-60s |
| agent | 120s | 60-300s |

## Best Practices

1. **Use specific matchers** -- avoid `*` for performance
2. **Set appropriate timeouts** -- don't block the user unnecessarily
3. **Handle errors gracefully** -- return meaningful messages on failure
4. **Use prompt hooks for simple decisions** -- faster and cheaper than command hooks
5. **Use agent hooks only when file inspection is needed** -- they are the most expensive
6. **Use async for slow operations** -- background logging, linting, external calls
7. **Include `$ARGUMENTS`** in prompt/agent hooks -- without it the LLM has no context
8. **Test scripts in isolation** -- run command hooks manually before wiring them up

## See Also

- `hook-events.md` -- all 14 available events with return values
- `hook-patterns.md` -- common patterns and examples
