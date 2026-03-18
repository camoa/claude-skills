# Hook Events

Complete reference for all 18 hook events in Claude Code.

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
| InstructionsLoaded | CLAUDE.md/instructions loaded | No | No |
| ConfigChange | Configuration changes during session | No | No |
| WorktreeCreate | Worktree created for agent | No | No |
| WorktreeRemove | Worktree removed after agent completion | No | No |

## MCP Tool Matcher Syntax

For tool-based events (PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest), MCP tools use the `mcp__server__tool` pattern:

| Pattern | Matches |
|---------|---------|
| `mcp__memory__.*` | All tools from memory server |
| `mcp__.*__write.*` | Any write tool from any server |
| `mcp__github__create_issue` | Specific MCP tool |
| `Write\|Edit\|mcp__fs__write` | Built-in and MCP tools combined |

## Common Input Fields

All hook events receive JSON input with the following common fields:

| Field | Type | Description |
|-------|------|-------------|
| `hook_event_name` | string | The event that triggered the hook |
| `agent_id` | string | Identifier of the agent (or main session) running the hook |
| `agent_type` | string | Type of agent (e.g., the agent name, or `main` for the primary session) |

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
- Stdout `ask`: Escalate the decision to the user — shows the normal permission prompt to the user, letting them decide instead of the hook. Useful when a hook can't determine safety on its own.

**Return Fields** (JSON stdout, optional):
- `statusMessage`: Custom status text displayed in the Claude Code status line while the tool runs. Useful for showing progress like "Running linter..." or "Validating schema...".

**Example with statusMessage**:
```json
{
  "PreToolUse": [
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "echo '{\"decision\": \"approve\", \"statusMessage\": \"Running validated bash...\"}'"
        }
      ]
    }
  ]
}
```

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

**Input Fields**: In addition to common fields, SubagentStop receives:
- `last_assistant_message` -- the final assistant message from the subagent
- `agent_transcript_path` -- path to the subagent's full transcript file

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

**Input Fields**: In addition to common fields, Stop receives:
- `last_assistant_message` -- the final assistant message content before stopping

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

**Matcher**: Termination type -- `clear`, `logout`, `prompt_input_exit` (expanded reason values available)

**Can Block**: No

**Timeout**: 1.5 seconds (hooks must complete quickly as the session is ending)

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

### InstructionsLoaded

**Trigger**: When CLAUDE.md or other instruction files are loaded

**Matcher**: Not supported

**Can Block**: No

**Use Cases**:
- React to instruction changes
- Log which instructions were loaded
- Validate instruction content

**Example**:
```json
{
  "InstructionsLoaded": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/on-instructions-loaded.sh"
        }
      ]
    }
  ]
}
```

### ConfigChange

**Trigger**: When configuration changes during a session

**Matcher**: Not supported

**Can Block**: No

**Use Cases**:
- React to runtime configuration changes
- Log config modifications
- Refresh cached configuration state

**Example**:
```json
{
  "ConfigChange": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/on-config-change.sh"
        }
      ]
    }
  ]
}
```

### WorktreeCreate

**Trigger**: When a worktree is created for an agent

**Matcher**: Not supported

**Can Block**: No

**Use Cases**:
- Initialize worktree-specific resources
- Log worktree creation for tracking
- Set up environment in the new worktree

**Example**:
```json
{
  "WorktreeCreate": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/on-worktree-create.sh"
        }
      ]
    }
  ]
}
```

### WorktreeRemove

**Trigger**: When a worktree is removed after agent completion

**Matcher**: Not supported

**Can Block**: No

**Use Cases**:
- Clean up worktree-specific resources
- Archive worktree results
- Log worktree lifecycle completion

**Example**:
```json
{
  "WorktreeRemove": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/on-worktree-remove.sh"
        }
      ]
    }
  ]
}
```

## Hook Configuration Fields

### The `once` Field

Set `once: true` on a hook to fire it only once per session, regardless of how many times the event triggers. After the first execution, the hook is skipped for subsequent events.

```json
{
  "PostToolUse": [
    {
      "matcher": "Write",
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/first-write-notification.sh",
          "once": true
        }
      ]
    }
  ]
}
```

**Use cases**: One-time initialization that shouldn't repeat (e.g., "first file written" notification), license check on first tool use, session-start-like logic triggered by first tool use rather than session start.

### Hook Execution Order

When multiple hooks match the same event, they run **in parallel** (not sequentially). If you need ordered execution, combine logic into a single script. Within a matcher group, all hooks fire simultaneously.

### Hook Timeout Behavior

Hooks have configurable timeouts (via `timeout` field, in seconds). When a hook times out:
- **Command hooks**: Process is killed, treated as exit 0 (non-blocking)
- **SessionEnd hooks**: Fixed 1.5-second timeout (cannot be overridden)
- Best practice: keep hooks fast; use `timeout` field for safety

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
