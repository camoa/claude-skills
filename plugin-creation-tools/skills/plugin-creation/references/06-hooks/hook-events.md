# Hook Events

Complete reference for all available hook events in Claude Code.

## Event Reference Table

| Event | Trigger | Matcher | Use Case |
|-------|---------|---------|----------|
| PreToolUse | Before tool execution | Yes | Validation, blocking |
| PostToolUse | After tool execution | Yes | Formatting, logging |
| SessionStart | Session begins | Yes | Setup, initialization |
| SessionEnd | Session ends | Yes | Cleanup |
| UserPromptSubmit | User submits prompt | No | Validation, injection |
| PermissionRequest | Permission dialog shown | Yes | Auto-approve/deny |
| Notification | Alert sent | Yes | Alert handling |
| Stop | Claude finishes responding | No | Continuation logic |
| SubagentStop | Subagent finishes | No | Task completion check |
| PreCompact | Before conversation compact | Yes | Pre-compact actions |

## Event Details

### PreToolUse

**Trigger**: Before Claude executes any tool

**Matcher**: Tool name (e.g., `Bash`, `Write`, `Edit`)

**Use Cases**:
- Block dangerous operations
- Validate before execution
- Log intended actions

**Example**:
```json
{
  "PreToolUse": [
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "validation",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/validate-bash.sh"
        }
      ]
    }
  ]
}
```

**Return Values**:
- Exit 0: Allow execution
- Exit non-zero: Block execution

### PostToolUse

**Trigger**: After Claude executes a tool

**Matcher**: Tool name

**Use Cases**:
- Format code after writes
- Log operations
- Validate output

**Example**:
```json
{
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
  ]
}
```

### SessionStart

**Trigger**: When a Claude Code session begins

**Matcher**: Optional (typically omitted)

**Use Cases**:
- Setup output directories
- Load environment variables
- Initialize logging

**Special**: Access to `${CLAUDE_ENV_FILE}` for persisting variables

**Example**:
```json
{
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
```

### SessionEnd

**Trigger**: When session ends

**Matcher**: Optional

**Use Cases**:
- Cleanup temporary files
- Save session state
- Final logging

**Example**:
```json
{
  "SessionEnd": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/cleanup.sh"
        }
      ]
    }
  ]
}
```

### UserPromptSubmit

**Trigger**: When user submits a prompt

**Matcher**: Not supported (fires for all prompts)

**Use Cases**:
- Validate user input
- Inject context
- Block certain prompts

**Example**:
```json
{
  "UserPromptSubmit": [
    {
      "hooks": [
        {
          "type": "validation",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/validate-prompt.sh"
        }
      ]
    }
  ]
}
```

### PermissionRequest

**Trigger**: When permission dialog shown

**Matcher**: Tool name

**Use Cases**:
- Auto-approve trusted operations
- Auto-deny risky operations

**Example**:
```json
{
  "PermissionRequest": [
    {
      "matcher": "Read(./docs/**)",
      "hooks": [
        {
          "type": "command",
          "command": "echo 'approve'"
        }
      ]
    }
  ]
}
```

**Return Values**:
- `approve`: Auto-approve
- `deny`: Auto-deny
- Other/empty: Show prompt

### Notification

**Trigger**: When Claude sends notifications

**Matcher**: Notification type

**Use Cases**:
- External alert routing
- Notification logging

**Example**:
```json
{
  "Notification": [
    {
      "matcher": "*",
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/log-notification.sh"
        }
      ]
    }
  ]
}
```

### Stop

**Trigger**: When Claude finishes responding

**Matcher**: Not supported

**Use Cases**:
- Intelligent continuation decisions
- Task completion checks

**Example**:
```json
{
  "Stop": [
    {
      "hooks": [
        {
          "type": "prompt",
          "prompt": "Check if all tasks are complete. Return 'continue' if more work needed."
        }
      ]
    }
  ]
}
```

### SubagentStop

**Trigger**: When a subagent finishes

**Matcher**: Not supported

**Use Cases**:
- Verify subagent task completion
- Chain subagent operations

**Example**:
```json
{
  "SubagentStop": [
    {
      "hooks": [
        {
          "type": "prompt",
          "prompt": "Evaluate if the subagent completed its assigned task."
        }
      ]
    }
  ]
}
```

### PreCompact

**Trigger**: Before conversation is compacted

**Matcher**: Optional

**Use Cases**:
- Notify user
- Save important context
- Pre-compaction logging

**Example**:
```json
{
  "PreCompact": [
    {
      "hooks": [
        {
          "type": "notification",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/compact-notify.sh"
        }
      ]
    }
  ]
}
```

## Multiple Hooks per Event

You can have multiple hook configurations per event:

```json
{
  "PostToolUse": [
    {
      "matcher": "Write",
      "hooks": [{ "type": "command", "command": "..." }]
    },
    {
      "matcher": "Edit",
      "hooks": [{ "type": "command", "command": "..." }]
    }
  ]
}
```

## See Also

- `writing-hooks.md` - hook configuration basics
- `hook-patterns.md` - common implementation patterns
