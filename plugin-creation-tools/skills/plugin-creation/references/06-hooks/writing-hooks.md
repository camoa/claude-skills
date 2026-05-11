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
| matcher | string | No | Pattern to filter when the matcher group fires (see Matcher Patterns) |
| hooks | array | **Yes** | Array of hook handlers |
| type | string | **Yes** | Handler type: `command`, `http`, `mcp_tool`, `prompt`, or `agent` |
| command | string | For command | Shell command to execute |
| prompt | string | For prompt/agent | LLM prompt (`$ARGUMENTS` for context) |
| if | string | No | Permission-rule syntax (e.g. `"Bash(git *)"`, `"Edit(*.ts)"`) to pre-filter tool events before spawning the handler. See [The `if` Field](#the-if-field). |
| timeout | number | No | Timeout in seconds (default varies by type) |
| async | boolean | No | Run in background (command type only) |
| asyncRewake | boolean | No | Like `async` but wakes Claude on exit-code 2 with stderr as a system reminder. Implies `async`. |
| statusMessage | string | No | Message shown in the TUI while the hook runs |
| once | boolean | No | Fires once per session then is removed. Only honored in skill frontmatter; ignored in settings/agent frontmatter. |

## Hook Handler Types

Five handler types are available. Each serves a different complexity level. (`agent` is upstream-marked **experimental** — behavior may change.)

### 1. Command Hook

Execute a shell script. Receives JSON on stdin with event context. Returns exit code + stdout.

```json
{
  "type": "command",
  "command": "${CLAUDE_PLUGIN_ROOT}/scripts/format.sh",
  "timeout": 30
}
```

**Stdin JSON** includes: `hook_event_name`, `tool_name`, `tool_input`, `tool_output` (varies by event), and an `effort` object (`{ "level": "low" | "medium" | "high" | "xhigh" | "max" }`) on tool-use-context events when the current model supports effort. The same level is exported as the `$CLAUDE_EFFORT` env var to command hooks and Bash-tool subprocesses — adapt verbosity or invocation depth to it.

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

### 4. HTTP Hook

Send event JSON as an HTTP POST to a URL. Configure via settings JSON only (not in hooks.json files).

> **Important:** `http` type hooks can only be configured in `settings.json` files. They cannot be placed in `hooks.json` — they will be silently ignored.

```json
{
  "type": "http",
  "url": "https://example.com/hooks/post-tool",
  "headers": {
    "Authorization": "Bearer $API_TOKEN",
    "X-Custom-Header": "value"
  }
}
```

**Configuration**:
- `url` (required) -- the endpoint to receive the POST request
- `headers` (optional) -- custom headers; supports env var interpolation via `$ENV_VAR` syntax
- `allowedEnvVars` (optional) -- whitelist of environment variables that can be interpolated in headers

**Behavior**:
- Event JSON is sent as the POST body
- Non-2xx responses are treated as non-blocking errors (the action proceeds)
- To block an action, return a 2xx response with a decision JSON body (e.g., `{"decision": "deny"}`)
- Only configurable through settings JSON, not hooks.json files

### 5. MCP Tool Hook

Call a tool on an already-connected MCP server directly from a hook — no shell script, no `.cmd` shim. The tool's text output is treated like command-hook stdout: if it parses as a [JSON output](hook-events.md) decision it is honored, otherwise it is shown as plain text.

```json
{
  "type": "mcp_tool",
  "server": "linear",
  "tool": "create_issue",
  "input": {
    "title": "Build failed in CI",
    "description": "${tool_input.command}"
  }
}
```

**Configuration**:
- `server` (required) — name of a configured MCP server. Must already be connected; the hook never triggers OAuth or connection flows.
- `tool` (required) — name of the tool to call on that server.
- `input` (optional) — arguments passed to the tool. String values support `${path}` substitution from the hook's [JSON input](hook-events.md) (e.g. `"${tool_input.file_path}"`).

**Behavior**:
- Available on every hook event once Claude Code has connected to the MCP servers. `SessionStart` and `Setup` typically fire before servers finish connecting, so expect a "not connected" non-blocking error on first run.
- If the named server is not connected, or the tool returns `isError: true`, the hook produces a non-blocking error and execution continues.

**Use cases**: file an issue from a `Stop` hook, sync state to a remote service from `PostToolUse`, log to an external system from `SessionEnd` — without spawning a shell or maintaining a separate webhook.

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

The `matcher` evaluation mode is determined by the **characters the matcher contains**, not by a flag:

| Matcher value | Evaluated as | Example |
|---------------|--------------|---------|
| `"*"`, `""`, or omitted | Match all | Fires on every occurrence of the event |
| Only letters, digits, `_`, and `\|` | Exact string, or `\|`-separated list of exact strings | `Bash` matches only Bash; `Edit\|Write` matches either tool exactly |
| Contains any other character | JavaScript regular expression | `^Notebook` matches any tool starting with Notebook; `mcp__memory__.*` matches every tool from the `memory` server |

**Important:** A value like `mcp__memory` contains only letters and underscores, so it is evaluated as an exact string and matches **no** tool. To match all tools from a server you must append `.*` (e.g. `mcp__memory__.*`) so the matcher contains a non-alphanumeric character and is treated as a regex.

### Matcher field per event

Each event matches on a different field. Tool events (`PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `PermissionDenied`) match on the tool name. Other events match on the value documented in their [hook-events.md](hook-events.md) entry — e.g. `SessionStart` matches `startup|resume|clear|compact`, `Notification` matches `permission_prompt|idle_prompt|auth_success|elicitation_dialog`, `StopFailure` matches error types.

Events with **no matcher support** (`UserPromptSubmit`, `Stop`, `TeammateIdle`, `TaskCreated`, `TaskCompleted`, `WorktreeCreate`, `WorktreeRemove`, `CwdChanged`) silently ignore a `matcher` field.

### Examples

```json
// Exact match — no regex chars
"matcher": "Write"

// Alternation of exact strings — only | is allowed before it's a regex
"matcher": "Write|Edit"

// Regex — the period forces regex evaluation
"matcher": "mcp__memory__.*"

// Regex — any server, any write tool
"matcher": "mcp__.*__write.*"

// Regex — starts-with anchor
"matcher": "^Notebook"
```

To filter more narrowly than the matcher allows — for example, "only `Bash` calls that run `git`" — use the `if` field on the handler. The `matcher` is a coarse event-level filter; `if` is a cheap per-handler pre-spawn filter.

## The `if` Field

The `if` field on a hook handler is a **pre-spawn filter** evaluated before the handler runs. It uses [permission-rule syntax](../08-configuration/permission-modes.md) (same as Claude Code's permission rules), so it can match the tool name and arguments together.

**Only evaluated on tool events**: `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `PermissionDenied`. On any other event, a hook with `if` set never runs.

**Bash subcommand semantics**: The rule matches each subcommand of the Bash input after leading `VAR=value` assignments are stripped. So `if: "Bash(rm *)"` matches **both** `FOO=bar rm file` and `npm test && rm file`. The hook also runs when the command is too complex to parse safely.

### Why it matters

The `if` field avoids the "spawn a process just to check and exit 0" anti-pattern. Declare hooks against broad matchers, then filter cheaply with `if`:

**Before (spawns on every Bash call):**
```json
{
  "PreToolUse": [
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/block-rm.sh"
        }
      ]
    }
  ]
}
```
The script itself checks whether the command is `rm *` and exits 0 otherwise. Every `Bash` call spawns the process.

**After (spawns only on `rm *`):**
```json
{
  "PreToolUse": [
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "if": "Bash(rm *)",
          "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/block-rm.sh"
        }
      ]
    }
  ]
}
```
Claude Code evaluates `Bash(rm *)` against the tool input and only spawns `block-rm.sh` when it matches.

### Common `if` patterns

```json
// Only Edit calls on TypeScript files
"if": "Edit(*.ts)"

// Only git subcommands
"if": "Bash(git *)"

// Only writes under a specific path
"if": "Write(src/**)"

// Compound: multiple rules
"if": "Bash(npm *) || Bash(yarn *)"
```

See [`../08-configuration/permission-modes.md`](../08-configuration/permission-modes.md) for the full permission-rule syntax.

## Permission Mode Interaction

Hooks behave differently depending on the active [permission mode](../08-configuration/permission-modes.md):

| Mode | Hook behavior |
|------|---------------|
| `default` | All hook return values honored. `PreToolUse` `deny`/`ask` are both respected; `PermissionRequest` hooks run before the user sees a dialog. |
| `auto` | The classifier may deny tool calls **without ever showing a dialog**. `PermissionDenied` fires for classifier denials. `PreToolUse` still runs and can block. `PermissionRequest` hooks do **not** fire unless a dialog is actually shown. |
| `dontAsk` | Existing permission rules are honored, but no new dialogs appear. Hook `ask` return values fall back to the configured default. |
| `bypassPermissions` | All permission checks bypassed. **Hooks still run** — they are the only guardrail. Do not assume the user is reviewing tool calls. |

**Security callout:** In `auto` and `bypassPermissions` modes, a `PreToolUse` hook that silently approves is the primary safety barrier. Write hook scripts defensively:
- Never assume the user will see or review the tool call
- Log denied attempts for later audit (PostToolUseFailure / PermissionDenied)
- Treat broad matchers + `auto` mode as requiring an `if` filter that narrows to known-safe patterns

## Environment Variables

Available in hook scripts:

| Variable | Description |
|----------|-------------|
| `${CLAUDE_PLUGIN_ROOT}` | Plugin installation directory |
| `${CLAUDE_PLUGIN_DATA}` | Persistent data directory (`~/.claude/plugins/data/{plugin-id}/`). Survives plugin updates. |
| `${CLAUDE_PROJECT_DIR}` | Project root directory |
| `${CLAUDE_ENV_FILE}` | Env file path. Available to `SessionStart`, `Setup`, `CwdChanged`, and `FileChanged` hooks. Variables written here persist into subsequent Bash commands for the session. |
| `${CLAUDE_EFFORT}` | Active [effort level](../03-skills/writing-skillmd.md#string-substitutions) for the current turn -- `low`, `medium`, `high`, `xhigh`, `max`. Use to adapt hook behavior to the user's effort setting. |

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
| command | 600s | 10-600s |
| command (async) | 120s | 30-300s |
| prompt | 30s | 10-60s |
| agent | 120s | 60-300s |

## Persistent Dependencies Pattern

Use `${CLAUDE_PLUGIN_DATA}` with a `SessionStart` hook to install dependencies once and reuse them across plugin updates. Because `${CLAUDE_PLUGIN_ROOT}` is wiped on update, dependencies installed there are lost. `${CLAUDE_PLUGIN_DATA}` persists.

```json
{
  "SessionStart": [
    {
      "matcher": "startup",
      "hooks": [
        {
          "type": "command",
          "command": "[ -d \"${CLAUDE_PLUGIN_DATA}/node_modules\" ] || npm install --prefix \"${CLAUDE_PLUGIN_DATA}\" \"${CLAUDE_PLUGIN_ROOT}/package.json\"",
          "timeout": 60
        }
      ]
    }
  ]
}
```

This pattern checks if `node_modules` exists in the persistent data directory and only runs `npm install` if it is missing. Use the same approach for Python venvs (`[ -d \"${CLAUDE_PLUGIN_DATA}/venv\" ] || python3 -m venv ...`).

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

- `hook-events.md` -- all 29 available events with return values
- `hook-patterns.md` -- common patterns and examples
