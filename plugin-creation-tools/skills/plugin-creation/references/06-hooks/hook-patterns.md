# Hook Patterns

Common patterns and recipes for implementing hooks.

## Session Setup Pattern

Create output directories and initialize environment at session start:

### hooks.json

```json
{
  "SessionStart": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/setup-session.sh",
          "timeout": 30
        }
      ]
    }
  ]
}
```

### scripts/setup-session.sh

```bash
#!/bin/bash
set -e

# Create output directories
OUTPUT_DIR="${CLAUDE_PROJECT_DIR}/claude-outputs"
mkdir -p "${OUTPUT_DIR}/logs"
mkdir -p "${OUTPUT_DIR}/artifacts"
mkdir -p "${OUTPUT_DIR}/reports"

# Set permissions
chmod 755 "${OUTPUT_DIR}"

# Persist environment for session
if [ -n "${CLAUDE_ENV_FILE}" ]; then
  echo "export PLUGIN_OUTPUT_DIR=\"${OUTPUT_DIR}\"" >> "${CLAUDE_ENV_FILE}"
  echo "export PLUGIN_LOG_FILE=\"${OUTPUT_DIR}/logs/session.log\"" >> "${CLAUDE_ENV_FILE}"
fi

# Log setup
echo "[$(date)] Session initialized" >> "${OUTPUT_DIR}/logs/setup.log"

exit 0
```

## Code Formatting Pattern

Auto-format code after file modifications:

### hooks.json

```json
{
  "PostToolUse": [
    {
      "matcher": "Write|Edit",
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/format-code.sh",
          "timeout": 30
        }
      ]
    }
  ]
}
```

### scripts/format-code.sh

```bash
#!/bin/bash
set -e

# Read tool output from stdin
INPUT=$(cat)

# Extract file path from input (if available)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Format based on extension
case "$FILE_PATH" in
  *.js|*.ts|*.tsx|*.jsx)
    npx prettier --write "$FILE_PATH" 2>/dev/null || true
    ;;
  *.py)
    black "$FILE_PATH" 2>/dev/null || true
    ;;
  *.php)
    vendor/bin/phpcbf "$FILE_PATH" 2>/dev/null || true
    ;;
esac

exit 0
```

## Structured Logging Pattern

Log all tool operations:

### hooks.json

```json
{
  "PostToolUse": [
    {
      "matcher": "*",
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/log-operation.py",
          "timeout": 5
        }
      ]
    }
  ]
}
```

### scripts/log-operation.py

```python
#!/usr/bin/env python3
import json
import sys
import os
from datetime import datetime

# Read hook input
input_data = json.load(sys.stdin)

# Prepare log entry
log_entry = {
    "timestamp": datetime.utcnow().isoformat(),
    "event": input_data.get("hook_event_name"),
    "tool": input_data.get("tool_name"),
    "status": "success"
}

# Get log file path
log_dir = os.environ.get("PLUGIN_OUTPUT_DIR", "/tmp")
log_file = os.path.join(log_dir, "logs", "operations.jsonl")

# Ensure directory exists
os.makedirs(os.path.dirname(log_file), exist_ok=True)

# Append log entry
with open(log_file, "a") as f:
    f.write(json.dumps(log_entry) + "\n")

sys.exit(0)
```

## Pre-Commit Validation Pattern

Validate code before git commits:

### hooks.json

```json
{
  "PreToolUse": [
    {
      "matcher": "Bash(git commit:*)",
      "hooks": [
        {
          "type": "validation",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/pre-commit-check.sh",
          "timeout": 60
        }
      ]
    }
  ]
}
```

### scripts/pre-commit-check.sh

```bash
#!/bin/bash
set -e

# Run linting
npm run lint 2>&1 || {
  echo "Lint check failed. Fix issues before committing."
  exit 1
}

# Run tests
npm test 2>&1 || {
  echo "Tests failed. Fix tests before committing."
  exit 1
}

echo "Pre-commit checks passed."
exit 0
```

## Auto-Approve Pattern

Auto-approve certain operations:

### hooks.json

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
    },
    {
      "matcher": "Read(.env*)",
      "hooks": [
        {
          "type": "command",
          "command": "echo 'deny'"
        }
      ]
    }
  ]
}
```

## Context Injection Pattern

Add context to user prompts:

### hooks.json

```json
{
  "UserPromptSubmit": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/inject-context.sh",
          "timeout": 10
        }
      ]
    }
  ]
}
```

### scripts/inject-context.sh

```bash
#!/bin/bash

# Read the prompt
PROMPT=$(cat)

# Add project context
PROJECT_INFO="Project: $(basename "$CLAUDE_PROJECT_DIR")"
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")

# Output modified context (this gets injected)
echo "Context: $PROJECT_INFO (branch: $BRANCH)"

exit 0
```

## Cleanup Pattern

Clean up on session end:

### hooks.json

```json
{
  "SessionEnd": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/cleanup.sh",
          "timeout": 15
        }
      ]
    }
  ]
}
```

### scripts/cleanup.sh

```bash
#!/bin/bash

OUTPUT_DIR="${CLAUDE_PROJECT_DIR}/claude-outputs"

# Archive logs older than 7 days
find "${OUTPUT_DIR}/logs" -name "*.log" -mtime +7 -exec gzip {} \;

# Clean temporary files
rm -rf "${OUTPUT_DIR}/temp/*" 2>/dev/null || true

# Final log entry
echo "[$(date)] Session ended, cleanup complete" >> "${OUTPUT_DIR}/logs/session.log"

exit 0
```

## Combining Multiple Hooks

Multiple hooks for the same event:

```json
{
  "PostToolUse": [
    {
      "matcher": "Write|Edit",
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/format.sh"
        },
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/log.sh"
        }
      ]
    }
  ]
}
```

Both hooks run (in parallel) for matching operations.

## Status Message Pattern

Show custom status text during tool execution:

### hooks.json

```json
{
  "PreToolUse": [
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/status-message.sh"
        }
      ]
    }
  ]
}
```

### scripts/status-message.sh

```bash
#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Set status message based on command type
if echo "$COMMAND" | grep -q "npm test"; then
  echo '{"decision": "approve", "statusMessage": "Running tests..."}'
elif echo "$COMMAND" | grep -q "npm run build"; then
  echo '{"decision": "approve", "statusMessage": "Building project..."}'
else
  echo "approve"
fi

exit 0
```

## One-Time Hook Pattern

Fire a hook only once per session using `once: true`:

```json
{
  "PostToolUse": [
    {
      "matcher": "Write|Edit",
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/first-modification-alert.sh",
          "once": true
        }
      ]
    }
  ]
}
```

The hook fires on the first matching event, then is skipped for the rest of the session.

## Three-Way Decision Pattern

Use `ask` to escalate uncertain decisions to the user:

```json
{
  "PreToolUse": [
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/risk-assessment.sh"
        }
      ]
    }
  ]
}
```

### scripts/risk-assessment.sh

```bash
#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Known safe commands — auto-approve
if echo "$COMMAND" | grep -qE '^(ls|cat|echo|git status|git log)'; then
  echo "approve"
  exit 0
fi

# Known dangerous — auto-deny
if echo "$COMMAND" | grep -qE '(rm -rf /|DROP TABLE|format)'; then
  echo "deny"
  exit 2
fi

# Uncertain — let the user decide
echo "ask"
exit 0
```

## FileChanged Watch-Mode Lint Pattern

Run a linter automatically when specific config files change on disk:

### hooks.json

```json
{
  "FileChanged": [
    {
      "matcher": ".eslintrc.json|.prettierrc",
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/relint-on-config-change.sh",
          "async": true,
          "timeout": 60
        }
      ]
    }
  ]
}
```

### scripts/relint-on-config-change.sh

```bash
#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.file_path')
EVENT=$(echo "$INPUT" | jq -r '.event')

# Only react to modifications, not deletions
[ "$EVENT" = "change" ] || exit 0

# Re-run lint across the project when config changes
cd "$CLAUDE_PROJECT_DIR" || exit 0
npx eslint . --quiet 2>&1 | tee -a claude-outputs/logs/lint-reloads.log

exit 0
```

**Why `async: true`:** Full-project lint can take seconds; `async` keeps Claude responsive and surfaces the result on the next turn.

**Matcher note:** Values in the `matcher` are treated as **literal filenames** for `FileChanged`, not regex. Use `|` to list multiple watched files.

## PermissionDenied Retry Pattern

In auto mode, log classifier denials and tell the model it may retry when appropriate:

### hooks.json

```json
{
  "PermissionDenied": [
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/bash-denial-handler.sh"
        }
      ]
    }
  ]
}
```

### scripts/bash-denial-handler.sh

```bash
#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
REASON=$(echo "$INPUT" | jq -r '.reason // empty')

# Log every denial for audit
LOG_DIR="$CLAUDE_PROJECT_DIR/claude-outputs/logs"
mkdir -p "$LOG_DIR"
jq -n --arg cmd "$COMMAND" --arg reason "$REASON" \
  '{ts: now, command: $cmd, reason: $reason}' \
  >> "$LOG_DIR/permission-denials.jsonl"

# For known-safe patterns, tell the model it may retry
if echo "$COMMAND" | grep -qE '^(git status|git log|ls|cat)'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PermissionDenied",
      retry: true
    }
  }'
fi

exit 0
```

**Retry caveat:** `retry: true` does **not** reverse the denial. It adds a message telling the model it may retry with a different approach. If the tool input is identical, the classifier will deny again.

## TaskCreated Tracking Pattern

Enforce task-subject conventions and log created tasks for observability:

### hooks.json

```json
{
  "TaskCreated": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/track-task-creation.sh"
        }
      ]
    }
  ]
}
```

### scripts/track-task-creation.sh

```bash
#!/bin/bash
INPUT=$(cat)
TASK_ID=$(echo "$INPUT" | jq -r '.task_id')
SUBJECT=$(echo "$INPUT" | jq -r '.task_subject')
DESCRIPTION=$(echo "$INPUT" | jq -r '.task_description // empty')

# Require non-empty descriptions
if [ -z "$DESCRIPTION" ]; then
  echo "Task '$SUBJECT' is missing a description. Add one before creating the task." >&2
  exit 2  # rejects task creation, feedback goes to the model
fi

# Require subject to start with a verb (convention)
if ! echo "$SUBJECT" | grep -qiE '^(add|fix|update|refactor|remove|implement|document)'; then
  echo "Task subject must start with a verb (add, fix, update, refactor, remove, implement, document)." >&2
  exit 2
fi

# Log accepted tasks
LOG_DIR="$CLAUDE_PROJECT_DIR/claude-outputs/logs"
mkdir -p "$LOG_DIR"
echo "$(date -u +%FT%TZ) created $TASK_ID: $SUBJECT" >> "$LOG_DIR/tasks.log"

exit 0
```

**Strong reject:** Exit 2 with stderr both rejects the task creation and feeds the stderr back to the model as guidance. Return `{"continue": false, "stopReason": "..."}` instead to stop the teammate entirely.

## Best Practices

1. **Fast hooks**: Keep execution time minimal
2. **Graceful failures**: Don't break the workflow on hook errors
3. **Specific matchers**: Use targeted matchers, avoid `*`
4. **Logging**: Include logging for debugging
5. **Testing**: Test scripts manually before integrating

## See Also

- `writing-hooks.md` - hook basics
- `hook-events.md` - event reference
- `../08-configuration/output-config.md` - output management
