# Hook Events

Complete reference for all 29 hook events in Claude Code.

## Event Reference Table

| Event | Trigger | Can Block? | Matcher Support |
|-------|---------|-----------|-----------------|
| Setup | One-time preparation: `--init-only`, `--init -p`, `--maintenance -p`. Does **not** fire on every launch. | No | Yes (`init`, `maintenance`) |
| SessionStart | Session begins or resumes | No | Yes (startup, resume, clear, compact) |
| UserPromptSubmit | User submits prompt | Yes | No |
| UserPromptExpansion | A user-typed slash command expands into a prompt | Yes (blocks expansion) | Yes (command name) |
| PreToolUse | Before tool execution | Yes | Yes (tool name) |
| PermissionRequest | Permission dialog shown | Yes | Yes (tool name) |
| PermissionDenied | Auto-mode classifier denies a tool call | No (can request retry) | Yes (tool name) |
| PostToolUse | After tool succeeds | No | Yes (tool name) |
| PostToolUseFailure | After tool fails | No | Yes (tool name) |
| PostToolBatch | After every tool call in a parallel batch resolves | Yes (stops the agentic loop) | No |
| Notification | Alert sent | No | Yes (notification type) |
| SubagentStart | Subagent spawned | No | Yes (agent type) |
| SubagentStop | Subagent finishes | Yes | Yes (agent type) |
| TaskCreated | Task being created via TaskCreate | Yes | No |
| TaskCompleted | Task marked complete | Yes | No |
| Stop | Claude finishes responding | Yes | No |
| StopFailure | Turn ends due to an API error | No | Yes (error type) |
| TeammateIdle | Agent team teammate going idle | Yes | No |
| InstructionsLoaded | CLAUDE.md/instructions loaded | No | Yes (load reason) |
| ConfigChange | Configuration changes during session | No | Yes (config source) |
| CwdChanged | Working directory changes (e.g. `cd`) | No | No |
| FileChanged | Watched file changes on disk | No | Yes (literal filenames) |
| WorktreeCreate | Worktree created for agent | No | No |
| WorktreeRemove | Worktree removed after agent completion | No | No |
| PreCompact | Before context compaction | No | Yes (manual, auto) |
| PostCompact | After context compaction completes | No | Yes (manual, auto) |
| Elicitation | MCP server requests user input via elicitation | No | Yes (MCP server name) |
| ElicitationResult | User responds to MCP elicitation, before response sent to server | No | Yes (MCP server name) |
| SessionEnd | Session terminates | No | Yes (reason) |

## MCP Tool Matcher Syntax

For tool-based events (PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest, PermissionDenied), MCP tools use the `mcp__server__tool` pattern:

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
| `effort` | object | `{ "level": "low" \| "medium" \| "high" \| "xhigh" \| "max" }` — the active [effort level](https://docs.anthropic.com/en/model-config#adjust-effort-level) for the turn. Reflects the level the current model actually used (if requested effort exceeded what the model supports, it's downgraded). Present for events that fire within a tool-use context (`PreToolUse`, `PostToolUse`, `Stop`, `SubagentStop`, etc.) when the current model supports effort. The same level is exported to command hooks and the Bash tool as the `$CLAUDE_EFFORT` environment variable. |

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

### Setup

**Trigger**: One-time preparation. Fires only when Claude Code is launched with `--init-only` (runs Setup + `SessionStart` matcher `startup`, then exits), or with `--init` / `--maintenance` combined with `-p` (print mode). **Does not fire on every launch.** Intended for CI/dependency installation that should run on demand, distinct from `SessionStart` which fires on every session.

**Matcher**: `trigger` value -- `init`, `maintenance`

**Can Block**: No. Exit code 2 shows stderr to the user; other non-zero codes show stderr only with `--verbose`. Execution always continues.

**Handler Types**: Only `type: "command"` and `type: "mcp_tool"` supported.

**Input Fields**: In addition to common fields, Setup receives:
- `trigger` -- `"init"` or `"maintenance"`

**Special**: Access to `${CLAUDE_ENV_FILE}` -- variables written here persist into subsequent Bash commands for the session, same as `SessionStart`.

**Important pattern**: Because Setup does not fire on every launch, a plugin that needs a dependency cannot rely on Setup alone. Use the `${CLAUDE_PLUGIN_DATA}` "check-and-install on first use" pattern documented in `writing-hooks.md` -- Setup is the *opt-in* one-shot path, not a replacement for lazy install.

**Use Cases**:
- One-time CI dependency install separate from session startup
- Maintenance tasks (cache prune, schema migration) triggered manually
- Plugin first-time configuration

**Example**:
```json
{
  "Setup": [
    {
      "matcher": "init",
      "hooks": [
        {
          "type": "command",
          "command": "cd \"${CLAUDE_PLUGIN_DATA}\" && cp \"${CLAUDE_PLUGIN_ROOT}/package.json\" . && npm install"
        }
      ]
    }
  ]
}
```

**Return Fields** (JSON stdout):
- `additionalContext` -- string injected into Claude's context. Plain stdout is debug-log only.

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

### UserPromptExpansion

**Trigger**: A user-typed slash command (skill, custom command, or MCP prompt) expands into a prompt, before it reaches Claude. Distinct from `UserPromptSubmit`: this fires for the direct `/skillname` path that bypasses `PreToolUse` matching on the `Skill` tool.

**Matcher**: `command_name` (e.g. `deploy`, `example-skill`). Empty matcher fires on every prompt-type slash command.

**Can Block**: Yes — `decision: "block"` prevents the expansion.

**Input Fields**: In addition to common fields, UserPromptExpansion hooks receive `expansion_type` (`slash_command` or `mcp_prompt`), `command_name`, `command_args`, `command_source`, and the original `prompt` string.

**Use Cases**:
- Block specific commands from direct invocation (e.g., require an approval file before `/deploy`)
- Inject context for a particular skill via `additionalContext` (e.g., team review checklist)
- Log which commands users invoke

**Example**:
```json
{
  "UserPromptExpansion": [
    {
      "matcher": "deploy",
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/guard-deploy.sh"
        }
      ]
    }
  ]
}
```

**Return Fields** (JSON stdout):
| Field | Description |
|-------|-------------|
| `decision` | `"block"` prevents the slash command from expanding. Omit to allow it to proceed. |
| `reason` | Shown to the user when `decision` is `"block"`. |
| `additionalContext` | String added to Claude's context alongside the expanded prompt. |

Stdout from `UserPromptExpansion` (like `UserPromptSubmit` and `SessionStart`) is added to Claude's visible context — not just the debug log.

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

**Input Fields**: In addition to common fields and the tool's `tool_input` / `tool_response`, the payload includes `duration_ms` — tool execution time in milliseconds (excludes time spent in permission prompts and `PreToolUse` hooks). Same field is also included on `PostToolUseFailure`.

**Use Cases**:
- Format code after writes
- Log completed operations
- Validate tool output
- Trigger follow-up actions
- Rewrite the tool output Claude sees (e.g. redact secrets, trim noisy diffs) via the `updatedToolOutput` JSON return field

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

**Return Fields** (JSON stdout):
- `updatedToolOutput` -- replaces the tool's output before Claude sees it. **Works for all tools.** The value must match the tool's output shape.
- `updatedMCPToolOutput` -- **legacy** MCP-only variant; superseded by `updatedToolOutput`. The old field still works, but new code should use `updatedToolOutput` so it survives moves between MCP and built-in tools.
- `decision: "block"` -- adds the `reason` next to the tool result; Claude still sees the original output unless `updatedToolOutput` is also set.

> `updatedToolOutput` only changes what Claude sees. The tool has already run; any side effects (file writes, shell commands, HTTP requests) have already occurred. To prevent a tool call, use `PreToolUse`.

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

### PostToolBatch

**Trigger**: Once after every tool call in a batch of parallel calls has resolved, before Claude Code sends the next request to the model. `PostToolUse` fires once per tool concurrently; `PostToolBatch` fires once with the full batch — the right place to act on the *set* of tools that ran.

**Matcher**: Not supported.

**Can Block**: Yes — `decision: "block"` or `continue: false` stops the agentic loop before the next model call.

**Input Fields**: In addition to common fields, receives `tool_calls` — an array of `{tool_name, tool_input, tool_use_id, tool_response}` objects, one per tool in the batch. The `tool_response` shape is the **serialized `tool_result` content the model sees** (line-number-prefixed text for `Read`, etc.), not the structured Output object that `PostToolUse` receives.

**Use Cases**:
- Inject a single batch-summary context message instead of per-tool noise
- Run cross-tool checks (e.g., "if Read touched files A and B together, remind to update C")
- Synchronize external state once after parallel writes

**Example**:
```json
{
  "PostToolBatch": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/batch-summary.sh"
        }
      ]
    }
  ]
}
```

**Return Fields** (JSON stdout):
| Field | Description |
|-------|-------------|
| `additionalContext` | Context string injected once before the next model call. Persisted to the transcript and replayed on `--resume`, so prefer static guidance over dynamic values. |
| `decision` | `"block"` stops the agentic loop. |

### PermissionDenied

**Trigger**: When the [auto-mode](../08-configuration/permission-modes.md) classifier denies a tool call. Does **not** fire when a user manually denies a dialog, when a `PreToolUse` hook blocks a call, or when a `deny` rule matches — only for classifier denials in auto mode.

**Matcher**: Tool name (same rules as PreToolUse)

**Can Block**: No — the denial already happened. The hook can tell the model it may retry by returning `{retry: true}`.

**Input Fields**: In addition to common fields, PermissionDenied hooks receive `tool_name`, `tool_input`, `tool_use_id`, and `reason` (the classifier's explanation).

**Use Cases**:
- Log classifier denials for tuning auto-mode rules
- Tell the model it may retry with a different approach
- Escalate repeated denials to monitoring

**Example**:
```json
{
  "PermissionDenied": [
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/log-denial-and-retry.sh"
        }
      ]
    }
  ]
}
```

**Retry return value** (JSON stdout):
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionDenied",
    "retry": true
  }
}
```

When `retry: true`, Claude Code adds a message telling the model it may retry the tool call. The denial itself is not reversed. Returning no JSON or `retry: false` leaves the denial in place.

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

### TaskCreated

**Trigger**: When a task is being created via the `TaskCreate` tool.

**Matcher**: Not supported (fires for every task)

**Can Block**: Yes — exit code 2 rejects task creation; `{"continue": false, "stopReason": "..."}` stops the teammate entirely.

**Input Fields**: In addition to common fields, TaskCreated hooks receive `task_id`, `task_subject`, and optionally `task_description`, `teammate_name`, and `team_name`.

**Use Cases**:
- Enforce naming conventions on task subjects
- Require non-empty task descriptions
- Prevent certain task types from being created
- Track task creation across teammates for observability

**Example**:
```json
{
  "TaskCreated": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/validate-task.sh"
        }
      ]
    }
  ]
}
```

**Return Values**:
- Exit 0: Accept task creation
- Exit 2: Reject; stderr is fed back to the model as feedback
- JSON `{"continue": false, "stopReason": "..."}`: Stop the teammate entirely (matches Stop hook behavior)

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

### CwdChanged

**Trigger**: When the working directory changes during a session (e.g. Claude runs `cd`). Pairs with `FileChanged` for reactive environment management (direnv-style).

**Matcher**: Not supported (fires on every directory change)

**Can Block**: No

**Handler Types**: Only `type: "command"` is supported.

**Input Fields**: In addition to common fields, CwdChanged hooks receive `old_cwd` and `new_cwd`.

**Special**: Access to `${CLAUDE_ENV_FILE}` — variables written here persist into subsequent Bash commands for the session.

**Use Cases**:
- Reload environment variables on directory change (direnv integration)
- Activate project-specific toolchains (pyenv, nvm)
- Update `FileChanged` watch list dynamically via `watchPaths` output

**Example**:
```json
{
  "CwdChanged": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/on-cwd-change.sh"
        }
      ]
    }
  ]
}
```

**Output** (optional JSON stdout):
- `watchPaths`: Array of absolute paths. Replaces the dynamic watch list for `FileChanged`. Empty array clears it (typical when entering a new directory).

### FileChanged

**Trigger**: When a watched file changes on disk. Useful for reloading env vars when project configuration files are modified.

**Matcher**: Serves two roles:
1. **Watch list**: The matcher value is split on `|` and each segment is registered as a **literal filename** in the working directory (`.envrc|.env` watches those two files). Regex patterns are **not** useful here — `^\.env` would watch a file literally named `^\.env`.
2. **Filter**: When a watched file changes, the same value filters which hook groups run, using standard matcher rules against the changed file's basename.

**Can Block**: No (the change already happened on disk)

**Handler Types**: Only `type: "command"` is supported.

**Input Fields**: In addition to common fields, FileChanged hooks receive `file_path` (absolute) and `event` (`"change"`, `"add"`, or `"unlink"`).

**Special**: Access to `${CLAUDE_ENV_FILE}` — variables written here persist into subsequent Bash commands for the session.

**Use Cases**:
- Reload environment variables when `.envrc`, `.env`, or config files change
- Run watch-mode linters/formatters on specific file types
- Re-read cached data when its source file changes

**Example**:
```json
{
  "FileChanged": [
    {
      "matcher": ".envrc|.env",
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/reload-env.sh"
        }
      ]
    }
  ]
}
```

**Output** (optional JSON stdout):
- `watchPaths`: Array of absolute paths to add to the dynamic watch list. Paths from the `matcher` are always watched in addition.

### WorktreeCreate

**Trigger**: A worktree is being created (`--worktree` or `isolation: "worktree"`). The hook **replaces** the default git-based worktree behavior, so it's the entry point for plugins that target non-git VCS (SVN, Perforce, Mercurial) or want a custom isolation strategy.

**Matcher**: Not supported

**Can Block**: Yes — and unlike most events, **any non-zero exit code aborts worktree creation**, not just exit 2.

**Input Fields**: In addition to common fields, receives a `name` field via stdin JSON:
```json
{ "hook_event_name": "WorktreeCreate", "name": "feature-branch-task" }
```

**Output**:
- **Command hooks**: print the absolute path of the created worktree directory on stdout. Hook failure or missing path fails creation.
- **HTTP hooks**: return `hookSpecificOutput.worktreePath`.

**Use Cases**:
- Replace default git worktree behavior with SVN/Perforce/Mercurial equivalent
- Initialize worktree-specific resources (env vars, copied configs)
- Log worktree creation for tracking

**Example**:
```json
{
  "WorktreeCreate": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/svn-checkout.sh"
        }
      ]
    }
  ]
}
```

### WorktreeRemove

**Trigger**: A worktree is being removed (at session exit or when a subagent finishes). Pairs with `WorktreeCreate`.

**Matcher**: Not supported

**Can Block**: No. Failures are logged in debug mode only.

**Input Fields**: In addition to common fields, receives the worktree `name` (same shape as `WorktreeCreate`).

**Use Cases**:
- Clean up the equivalent resources your `WorktreeCreate` hook provisioned (SVN working copy, Perforce client, etc.)
- Archive worktree results before teardown
- Log worktree lifecycle completion

**Example**:
```json
{
  "WorktreeRemove": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/svn-cleanup.sh"
        }
      ]
    }
  ]
}
```

### StopFailure

**Trigger**: When a turn ends due to an API error

**Matcher**: Not supported

**Can Block**: No (notification-only event — output and exit code are ignored)

**Use Cases**:
- Log API errors for debugging
- Alert on repeated failures
- Track error rates

**Example**:
```json
{
  "StopFailure": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/log-api-error.sh"
        }
      ]
    }
  ]
}
```

### PostCompact

**Trigger**: After context compaction completes

**Matcher**: Not supported

**Can Block**: No

**Use Cases**:
- Re-inject important context lost during compaction
- Log compaction events
- Post-compaction state restoration

**Example**:
```json
{
  "PostCompact": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/restore-context.sh"
        }
      ]
    }
  ]
}
```

**Note**: Pairs with the `PreCompact` event. Use `PreCompact` to save state and `PostCompact` to restore it.

### Elicitation

**Trigger**: When an MCP server requests user input via an elicitation

**Matcher**: Not supported

**Can Block**: No

**Use Cases**:
- Intercept and log MCP user prompts
- Validate elicitation content before it reaches the user
- Audit MCP server interactions

**Example**:
```json
{
  "Elicitation": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/log-elicitation.sh"
        }
      ]
    }
  ]
}
```

### ElicitationResult

**Trigger**: After the user responds to an MCP elicitation, before the response is sent to the server

**Matcher**: Not supported

**Can Block**: No

**Use Cases**:
- Log user responses to MCP prompts
- Audit the full elicitation lifecycle
- Track user interaction patterns with MCP servers

**Example**:
```json
{
  "ElicitationResult": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/log-elicitation-result.sh"
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

- `writing-hooks.md` -- hook configuration and handler types (references all 29 events)
- `hook-patterns.md` -- common implementation patterns
