# Output Configuration

Plugins often need to write logs, artifacts, and reports. This guide covers best practices for output management.

## Standard Environment Variables

| Variable | Purpose | Availability |
|----------|---------|--------------|
| `CLAUDE_PLUGIN_ROOT` | Plugin installation directory | Always |
| `CLAUDE_PROJECT_DIR` | Project root directory | Always |
| `CLAUDE_ENV_FILE` | Persistent env vars file | SessionStart only |
| `CLAUDE_CONFIG_DIR` | Config directory (~/.claude) | Always |

## Recommended Output Structure

```
project-root/
├── .claude/
│   ├── settings.json
│   └── settings.local.json
├── claude-outputs/            # Generated outputs
│   ├── logs/
│   │   ├── session.log
│   │   ├── operations.log
│   │   └── errors.log
│   ├── artifacts/
│   │   ├── reports/
│   │   ├── builds/
│   │   └── exports/
│   └── temp/
└── .gitignore
```

## SessionStart Output Setup

Use SessionStart hooks to create output directories:

### hooks.json

```json
{
  "SessionStart": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/scripts/setup-output.sh",
          "timeout": 30
        }
      ]
    }
  ]
}
```

### scripts/setup-output.sh

```bash
#!/bin/bash
set -e

# Define output directory
OUTPUT_DIR="${CLAUDE_PROJECT_DIR}/claude-outputs"

# Create directories
mkdir -p "${OUTPUT_DIR}/logs"
mkdir -p "${OUTPUT_DIR}/artifacts"
mkdir -p "${OUTPUT_DIR}/temp"

# Set permissions
chmod 755 "${OUTPUT_DIR}"

# Persist environment variables for session
if [ -n "${CLAUDE_ENV_FILE}" ]; then
  cat >> "${CLAUDE_ENV_FILE}" <<EOF
export PLUGIN_OUTPUT_DIR="${OUTPUT_DIR}"
export PLUGIN_LOG_FILE="${OUTPUT_DIR}/logs/session.log"
export PLUGIN_ARTIFACTS_DIR="${OUTPUT_DIR}/artifacts"
EOF
fi

# Log initialization
echo "[$(date)] Output directories initialized" >> "${OUTPUT_DIR}/logs/setup.log"

exit 0
```

## Custom Environment Variables

Define in settings:

```json
{
  "env": {
    "CLAUDE_PLUGIN_OUTPUT_DIR": "${HOME}/claude-outputs",
    "CLAUDE_PLUGIN_LOG_LEVEL": "info",
    "CLAUDE_PLUGIN_RETENTION_DAYS": "30"
  }
}
```

Use in scripts:

```bash
OUTPUT_DIR="${CLAUDE_PLUGIN_OUTPUT_DIR:-${HOME}/claude-outputs}"
```

## .gitignore Patterns

Add to project `.gitignore`:

```gitignore
# Claude Code outputs
claude-outputs/
.claude/settings.local.json

# Alternative output directories
/output/
/logs/
/artifacts/
/.reports/
```

## Permission Settings for Output

Allow writing to output directories:

```json
{
  "permissions": {
    "allow": [
      "Write(./claude-outputs/**)",
      "Edit(./claude-outputs/**)",
      "Write(./output/**)",
      "Write(./logs/**)"
    ]
  }
}
```

## Structured Logging

### Log to JSON Lines

```python
#!/usr/bin/env python3
import json
import os
from datetime import datetime

log_file = os.path.join(
    os.environ.get("PLUGIN_OUTPUT_DIR", "."),
    "logs",
    "operations.jsonl"
)

def log_operation(event, tool, status="success", details=None):
    entry = {
        "timestamp": datetime.utcnow().isoformat(),
        "event": event,
        "tool": tool,
        "status": status,
        "details": details
    }

    os.makedirs(os.path.dirname(log_file), exist_ok=True)

    with open(log_file, "a") as f:
        f.write(json.dumps(entry) + "\n")
```

### Log Rotation Script

```bash
#!/bin/bash
# scripts/rotate-logs.sh

OUTPUT_DIR="${PLUGIN_OUTPUT_DIR:-./claude-outputs}"
LOG_DIR="${OUTPUT_DIR}/logs"
RETENTION_DAYS="${PLUGIN_RETENTION_DAYS:-7}"

# Archive old logs
find "${LOG_DIR}" -name "*.log" -mtime +${RETENTION_DAYS} -exec gzip {} \;

# Delete very old archives
find "${LOG_DIR}" -name "*.gz" -mtime +30 -delete

echo "[$(date)] Log rotation complete" >> "${LOG_DIR}/rotation.log"
```

## Project-Relative vs User Outputs

### Project-Relative (Recommended)

```bash
OUTPUT_DIR="${CLAUDE_PROJECT_DIR}/claude-outputs"
```

Benefits:
- Outputs stay with project
- Easy to clean up
- Context preserved

### User-Level

```bash
OUTPUT_DIR="${HOME}/claude-outputs"
```

Benefits:
- Persists across projects
- Centralized logs
- Global history

## Cleanup Patterns

### SessionEnd Cleanup

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

### scripts/cleanup.sh

```bash
#!/bin/bash

OUTPUT_DIR="${PLUGIN_OUTPUT_DIR:-./claude-outputs}"

# Remove temp files
rm -rf "${OUTPUT_DIR}/temp/*" 2>/dev/null || true

# Archive session log
SESSION_LOG="${OUTPUT_DIR}/logs/session.log"
if [ -f "$SESSION_LOG" ]; then
  ARCHIVE_NAME="session-$(date +%Y%m%d-%H%M%S).log"
  mv "$SESSION_LOG" "${OUTPUT_DIR}/logs/${ARCHIVE_NAME}"
fi

exit 0
```

## Best Practices

1. **Use standard directories**: `claude-outputs/logs`, `claude-outputs/artifacts`
2. **Always gitignore outputs**: Add patterns to `.gitignore`
3. **Use CLAUDE_ENV_FILE**: Persist paths for session duration
4. **Implement log rotation**: Prevent unbounded growth
5. **Set appropriate permissions**: Allow writing to output paths
6. **Clean up on session end**: Remove temporary files

## See Also

- `settings.md` - settings hierarchy
- `../06-hooks/hook-patterns.md` - session hooks
- `../06-hooks/hook-events.md` - event reference
