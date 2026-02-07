# Hook Events

Complete reference for all 14 hook events in Claude Code.

## Event Reference Table

| Event | Trigger | Can Block? | Matcher Support |
|-------|---------|-----------|-----------------|
| SessionStart | Session begins or resumes | No | Yes (startup, resume, clear, compact) |
| UserPromptSubmit | User submits prompt | Yes | No |
| PreToolUse | Before tool execution | Yes | Yes (tool name regex) |
| PermissionRequest | Permission dialog shown | Yes | Yes (tool name) |
| PostToolUse | After tool succeeds | No | Yes (tool name regex) |
| PostToolUseFailure | After tool fails | No | Yes (tool name regex) |
| Notification | Alert sent | No | Yes (notification type) |
| SubagentStart | Subagent spawned | No | Yes (agent type) |
| SubagentStop | Subagent finishes | Yes | Yes (agent type) |
| Stop | Claude finishes responding | Yes | No |
| TeammateIdle | Agent team teammate going idle | Yes | No |
| TaskCompleted | Task marked complete | Yes | No |
| PreCompact | Before context compaction | No | Yes (manual, auto) |
| SessionEnd | Session terminates | No | Yes (clear, logout, prompt_input_exit) |

## MCP Tool Matcher Syntax

For tool-based events (PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest), MCP tools use the `mcp__server__tool` pattern:

| Pattern | Matches |
|---------|---------|
| `mcp__memory__.*` | All tools from memory server |
| `mcp__.*__write.*` | Any write tool from any server |
| `mcp__github__create_issue` | Specific MCP tool |
| `Write\|Edit\|mcp__fs__write` | Built-in and MCP tools combined |

## Event Details

### SessionStart

**Trigger**: Session begins or resumes (new session, resume, clear, post-compact restart)

**Matcher**: Session type -- `startup`, `resume`, `clear`, `compact`

**Use Cases**:
- Setup output directories
- Load environment variables
- Initialize logging
- Differentiate fresh start vs resume

**Special**: Access to `${CLAUDE_ENV_FILE}` for persisting variables across the session.

**Example**:
```json
{
  "SessionStart": [
    {
      "matcher": "startup",
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

### UserPromptSubmit

**Trigger**: User submits a prompt (before Claude processes it)

**Matcher**: Not supported (fires for all prompts)

**Can Block**: Yes -- exit non-zero to reject the prompt

**Use Cases**:
- Validate user input
- Inject additional context into the prompt
- Block certain prompts

**Example**:
```json
{
  "UserPromptSubmit": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/validate-prompt.sh"
        }
      ]
    }
  ]
}
```

**Return Values**:
- Exit 0 + stdout: Stdout content is added as context to the prompt
- Exit non-zero: Prompt is blocked

### PreToolUse

**Trigger**: Before Claude executes any tool

**Matcher**: Tool name regex (e.g., `Bash`, `Write`, `Write|Edit`, `mcp__memory__.*`)

**Can Block**: Yes -- return `deny` or exit non-zero to block

**Use Cases**:
- Block dangerous operations
- Validate tool inputs before execution
- Log intended actions

**Example**:
```json
{
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
  ]
}
```

**Return Values**:
- Exit 0: Allow execution
- Exit non-zero: Block execution
- Stdout `approve`: Bypass permission check
- Stdout `deny`: Block with denial message

### PermissionRequest

**Trigger**: Permission dialog is shown to the user

**Matcher**: Tool name (supports path patterns like `Read(./docs/**)`)

**Can Block**: Yes -- auto-approve or auto-deny

**Use Cases**:
- Auto-approve trusted operations
- Auto-deny risky operations
- Reduce permission fatigue for known-safe patterns

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
- Stdout `approve`: Auto-approve the permission
- Stdout `deny`: Auto-deny the permission
- Other/empty: Show normal permission prompt

### PostToolUse

**Trigger**: After a tool executes successfully

**Matcher**: Tool name regex (e.g., `Write|Edit`, `mcp__.*__create.*`)

**Can Block**: No

**Use Cases**:
- Format code after writes
- Log completed operations
- Validate tool output
- Trigger follow-up actions

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

### PostToolUseFailure

**Trigger**: After a tool execution fails (error or non-zero exit)

**Matcher**: Tool name regex (same patterns as PostToolUse)

**Can Block**: No

**Use Cases**:
- Log failures for debugging
- Capture error patterns
- Trigger recovery actions
- Alert on repeated failures

**Example**:
```json
{
  "PostToolUseFailure": [
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/log-failure.sh"
        }
      ]
    }
  ]
}
```

### Notification

**Trigger**: When Claude sends a notification/alert

**Matcher**: Notification type

**Can Block**: No

**Use Cases**:
- Route alerts to external systems (Slack, email)
- Notification logging
- Custom alert handling

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

### SubagentStart

**Trigger**: When a subagent is spawned

**Matcher**: Agent type

**Can Block**: No

**Use Cases**:
- Log subagent creation
- Track concurrent agent activity
- Initialize subagent-specific resources

**Example**:
```json
{
  "SubagentStart": [
    {
      "matcher": "*",
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/log-subagent-start.sh"
        }
      ]
    }
  ]
}
```

### SubagentStop

**Trigger**: When a subagent finishes its work

**Matcher**: Agent type

**Can Block**: Yes -- can request continuation

**Use Cases**:
- Verify subagent task completion
- Chain subagent operations
- Quality-check subagent output

**Example**:
```json
{
  "SubagentStop": [
    {
      "matcher": "*",
      "hooks": [
        {
          "type": "prompt",
          "prompt": "Evaluate if the subagent completed its assigned task. $ARGUMENTS"
        }
      ]
    }
  ]
}
```

**Return Values**:
- Stdout `continue`: Request the subagent to continue working
- Other/empty: Accept completion

### Stop

**Trigger**: When Claude finishes responding (end of turn)

**Matcher**: Not supported

**Can Block**: Yes -- can force continuation

**Use Cases**:
- Intelligent continuation decisions
- Task completion checks
- Enforce multi-step workflows

**Example**:
```json
{
  "Stop": [
    {
      "hooks": [
        {
          "type": "prompt",
          "prompt": "Check if all tasks are complete based on the conversation. Return 'continue' if more work is needed. $ARGUMENTS"
        }
      ]
    }
  ]
}
```

**Return Values**:
- Stdout `continue`: Force Claude to continue
- Other/empty: Allow stop

### TeammateIdle

**Trigger**: When a teammate agent in an agent team is about to go idle

**Matcher**: Not supported

**Can Block**: Yes -- can assign new work

**Use Cases**:
- Assign follow-up tasks to idle teammates
- Load-balance work across agents
- Keep agent teams productive

**Example**:
```json
{
  "TeammateIdle": [
    {
      "hooks": [
        {
          "type": "prompt",
          "prompt": "A teammate is going idle. Check if there are pending tasks to assign. $ARGUMENTS"
        }
      ]
    }
  ]
}
```

**Return Values**:
- Stdout with task description: Assign new work
- Empty: Allow teammate to go idle

### TaskCompleted

**Trigger**: When a task is marked as complete

**Matcher**: Not supported

**Can Block**: Yes -- can reject completion

**Use Cases**:
- Verify task completion criteria
- Run acceptance checks
- Enforce quality gates before marking done

**Example**:
```json
{
  "TaskCompleted": [
    {
      "hooks": [
        {
          "type": "agent",
          "prompt": "Verify the completed task meets all acceptance criteria by inspecting the relevant files. $ARGUMENTS"
        }
      ]
    }
  ]
}
```

**Return Values**:
- Exit 0: Accept task completion
- Exit non-zero / stdout `deny`: Reject completion, continue working

### PreCompact

**Trigger**: Before conversation context is compacted

**Matcher**: Compaction type -- `manual`, `auto`

**Can Block**: No

**Use Cases**:
- Save important context before compaction
- Log compaction events
- Pre-compaction state snapshots

**Example**:
```json
{
  "PreCompact": [
    {
      "matcher": "auto",
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/save-context.sh"
        }
      ]
    }
  ]
}
```

### SessionEnd

**Trigger**: When the session terminates

**Matcher**: Termination type -- `clear`, `logout`, `prompt_input_exit`

**Can Block**: No

**Use Cases**:
- Cleanup temporary files
- Save session state
- Final logging and reports

**Example**:
```json
{
  "SessionEnd": [
    {
      "matcher": "prompt_input_exit",
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

## Multiple Hooks per Event

Multiple matcher groups and multiple hooks per group:

```json
{
  "PreToolUse": [
    {
      "matcher": "Bash",
      "hooks": [
        { "type": "command", "command": "..." }
      ]
    },
    {
      "matcher": "Write|Edit",
      "hooks": [
        { "type": "command", "command": "..." },
        { "type": "prompt", "prompt": "..." }
      ]
    },
    {
      "matcher": "mcp__memory__.*",
      "hooks": [
        { "type": "command", "command": "..." }
      ]
    }
  ]
}
```

## See Also

- `writing-hooks.md` -- hook configuration and handler types
- `hook-patterns.md` -- common implementation patterns
