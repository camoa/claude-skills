# Cross-Platform Hooks (Windows/macOS/Linux)

Claude Code plugins need hooks that work across all operating systems. This guide explains the polyglot wrapper technique for cross-platform compatibility.

## The Problem

Claude Code runs hook commands through the system's default shell:
- **Windows**: CMD.exe
- **macOS/Linux**: bash or sh

This creates challenges:

| Issue | Windows | Unix |
|-------|---------|------|
| Script execution | CMD can't run `.sh` files directly | Works natively |
| Path format | Backslashes (`C:\path`) | Forward slashes (`/path`) |
| Environment variables | `%VAR%` syntax | `$VAR` syntax |
| bash availability | Not in PATH by default | Always available |

## The Solution: Polyglot `.cmd` Wrapper

A polyglot script is valid syntax in multiple languages simultaneously. This wrapper works in both CMD and bash:

```cmd
: << 'CMDBLOCK'
@echo off
REM Polyglot wrapper: runs .sh scripts cross-platform
REM Usage: run-hook.cmd <script-name> [args...]

"C:\Program Files\Git\bin\bash.exe" -l "%~dp0%~1"
exit /b
CMDBLOCK

# Unix shell runs from here
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_NAME="$1"
shift
"${SCRIPT_DIR}/${SCRIPT_NAME}" "$@"
```

### How It Works

**On Windows (CMD.exe):**
1. `: << 'CMDBLOCK'` - CMD sees `:` as a label, ignores the rest
2. `@echo off` - Suppresses command echoing
3. Runs bash.exe with `-l` (login shell) for proper PATH
4. `exit /b` - Exits batch script before Unix section

**On Unix (bash/sh):**
1. `: << 'CMDBLOCK'` - `:` is no-op, starts heredoc
2. Everything until `CMDBLOCK` is consumed (ignored)
3. Runs the actual script with Unix paths

## File Structure

```
hooks/
├── hooks.json           # Points to .cmd wrapper
├── run-hook.cmd         # Polyglot wrapper (entry point)
├── session-start.sh     # Actual hook logic (bash)
├── post-edit.sh         # Another hook script
└── cleanup.sh           # Cleanup script
```

## Implementation

### Step 1: Create run-hook.cmd

Save this as `hooks/run-hook.cmd`:

```cmd
: << 'CMDBLOCK'
@echo off
REM Polyglot wrapper: runs .sh scripts cross-platform
REM Usage: run-hook.cmd <script-name> [args...]
REM Requires: Git for Windows (provides bash.exe)

"C:\Program Files\Git\bin\bash.exe" -l "%~dp0%~1"
exit /b
CMDBLOCK

# Unix shell runs from here
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_NAME="$1"
shift
"${SCRIPT_DIR}/${SCRIPT_NAME}" "$@"
```

**Note**: Uses `$0` instead of `${BASH_SOURCE[0]:-$0}` for POSIX compliance. The latter causes "Bad substitution" errors on Ubuntu/Debian where `/bin/sh` is dash.

### Step 2: Create Your Hook Scripts

Write your actual logic in `.sh` files:

```bash
#!/bin/bash
# hooks/session-start.sh

OUTPUT_DIR="${CLAUDE_PROJECT_DIR}/claude-outputs"
mkdir -p "${OUTPUT_DIR}/logs"

echo "[$(date)] Session started" >> "${OUTPUT_DIR}/logs/session.log"
exit 0
```

### Step 3: Configure hooks.json

Point to the `.cmd` wrapper, passing the script name:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" session-start.sh"
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
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" post-edit.sh"
          }
        ]
      }
    ]
  }
}
```

**Important**: Quote the path because `${CLAUDE_PLUGIN_ROOT}` may contain spaces (e.g., `C:\Program Files\...`).

### Step 4: Set Permissions

```bash
chmod +x hooks/run-hook.cmd
chmod +x hooks/*.sh
```

## Requirements

### Windows
- **Git for Windows** must be installed
- Default path: `C:\Program Files\Git\bin\bash.exe`
- If installed elsewhere, modify the wrapper path

### Unix (macOS/Linux)
- Standard bash or sh shell
- `.cmd` file must have execute permission

## Writing Cross-Platform Scripts

### Do:
- Use pure bash builtins when possible
- Use `$(command)` instead of backticks
- Quote all variable expansions: `"$VAR"`
- Use `printf` for consistent output

### Avoid:
- External commands not in Git Bash PATH
- Platform-specific paths
- Assuming specific shell features

### Example: Pure Bash JSON Escaping

Instead of sed/awk (may not be available):

```bash
escape_for_json() {
    local input="$1"
    local output=""
    local i char
    for (( i=0; i<${#input}; i++ )); do
        char="${input:$i:1}"
        case "$char" in
            $'\\') output+='\\\\' ;;
            '"') output+='\\"' ;;
            $'\n') output+='\\n' ;;
            $'\r') output+='\\r' ;;
            $'\t') output+='\\t' ;;
            *) output+="$char" ;;
        esac
    done
    printf '%s' "$output"
}
```

## Troubleshooting

### "bash is not recognized"
CMD can't find bash. The wrapper uses full path `C:\Program Files\Git\bin\bash.exe`. Update if Git is installed elsewhere.

### "cygpath: command not found"
Bash isn't running as login shell. Ensure `-l` flag is used.

### Script opens in text editor instead of running
hooks.json points directly to `.sh` file. Point to `.cmd` wrapper instead.

### Works in terminal but not as hook
Test by simulating hook environment:
```powershell
$env:CLAUDE_PLUGIN_ROOT = "C:\path\to\plugin"
cmd /c "C:\path\to\plugin\hooks\run-hook.cmd" session-start.sh
```

## Template

Copy the complete `run-hook.cmd` from `templates/hooks/run-hook.cmd.template`.

## Credits

This polyglot pattern is adapted from [superpowers-developing-for-claude-code](https://github.com/obra/superpowers-marketplace) by Jesse Vincent, which documented cross-platform hook solutions for Claude Code plugins.

## See Also

- `hook-events.md` - All hook event types
- `hook-patterns.md` - Common hook use cases
- `writing-hooks.md` - Hook basics
