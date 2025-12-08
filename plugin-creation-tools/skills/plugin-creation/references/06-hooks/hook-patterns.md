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
