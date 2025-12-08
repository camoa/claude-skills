#!/usr/bin/env python3
"""
Plugin Initializer - Creates a new plugin from template

Usage:
    init_plugin.py <plugin-name> --path <path> [--components <components>]

Components:
    skill, command, agent, hook, mcp (comma-separated)

Examples:
    init_plugin.py my-tools --path ./plugins
    init_plugin.py enterprise-tools --path ./plugins --components command,agent,hook
    init_plugin.py doc-processor --path ./plugins --components skill
"""

import sys
import re
import json
from pathlib import Path


PLUGIN_JSON_TEMPLATE = """{
  "name": "%s",
  "version": "1.0.0",
  "description": "Brief description of plugin purpose",
  "author": {
    "name": "Your Name"
  },
  "license": "MIT"
}
"""

SKILL_TEMPLATE = """---
name: %s
description: Use when [triggers] - [what it does]. Keywords: [terms]
---

# %s

## When to Use
- [Trigger phrase 1]
- [Trigger phrase 2]
- NOT for: [exclusions]

## Workflow

1. Step one
2. Step two
3. Step three

## See Also
- `references/` - detailed documentation
"""

COMMAND_TEMPLATE = """---
description: Brief description of what this command does
allowed-tools: Read, Edit, Bash
argument-hint: [arg1] [arg2]
---

# %s

Execute this command to [purpose].

## Steps

1. First, [action]
2. Then, [action]
3. Finally, [action]

## Arguments

- `$1`: First argument (e.g., environment)
- `$2`: Second argument (e.g., version)
- `$ARGUMENTS`: All arguments
"""

AGENT_TEMPLATE = """---
name: %s
description: [Expertise]. Use proactively when [trigger conditions].
tools: Read, Grep, Glob
model: sonnet
---

# %s

## Role

[Detailed description of the agent's expertise and responsibilities]

## Capabilities

- [Capability 1]
- [Capability 2]
- [Capability 3]

## When to Use

Use this agent when:
- [Scenario 1]
- [Scenario 2]
"""

HOOKS_TEMPLATE = """{
  "description": "Plugin hooks for automation",
  "hooks": {
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
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/example-hook.sh",
            "timeout": 30
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
            "timeout": 30
          }
        ]
      }
    ]
  }
}
"""

SETUP_OUTPUT_SCRIPT = """#!/bin/bash
# SessionStart hook - Create output directories and set env vars
set -e

OUTPUT_DIR="${CLAUDE_PROJECT_DIR}/claude-outputs"

# Create directories
mkdir -p "${OUTPUT_DIR}/logs"
mkdir -p "${OUTPUT_DIR}/artifacts"
mkdir -p "${OUTPUT_DIR}/temp"

# Persist environment variables for session
if [ -n "${CLAUDE_ENV_FILE}" ]; then
  cat >> "${CLAUDE_ENV_FILE}" <<EOF
export PLUGIN_OUTPUT_DIR="${OUTPUT_DIR}"
export PLUGIN_LOG_FILE="${OUTPUT_DIR}/logs/session.log"
EOF
fi

echo "[$(date)] Output initialized at ${OUTPUT_DIR}" >> "${OUTPUT_DIR}/logs/setup.log"
exit 0
"""

CLEANUP_SCRIPT = """#!/bin/bash
# SessionEnd hook - Clean up temporary files
OUTPUT_DIR="${PLUGIN_OUTPUT_DIR:-${CLAUDE_PROJECT_DIR}/claude-outputs}"

# Remove temp files
rm -rf "${OUTPUT_DIR}/temp/"* 2>/dev/null || true

# Archive session log if exists
SESSION_LOG="${OUTPUT_DIR}/logs/session.log"
if [ -f "$SESSION_LOG" ] && [ -s "$SESSION_LOG" ]; then
  ARCHIVE_NAME="session-$(date +%Y%m%d-%H%M%S).log"
  mv "$SESSION_LOG" "${OUTPUT_DIR}/logs/${ARCHIVE_NAME}"
fi

exit 0
"""

HOOK_SCRIPT_TEMPLATE = """#!/bin/bash
# PostToolUse hook - Triggered after Write or Edit operations

# Access tool information via stdin (JSON)
# input=$(cat)

# Example: Log the operation
OUTPUT_DIR="${PLUGIN_OUTPUT_DIR:-./claude-outputs}"
echo "[$(date)] PostToolUse hook executed" >> "${OUTPUT_DIR}/logs/operations.log"

exit 0
"""

MCP_TEMPLATE = """{
  "server-name": {
    "command": "${CLAUDE_PLUGIN_ROOT}/servers/server-binary",
    "args": ["--config", "${CLAUDE_PLUGIN_ROOT}/config.json"],
    "env": {
      "LOG_LEVEL": "info"
    }
  }
}
"""

README_TEMPLATE = """# %s

Brief description of what this plugin does.

## Installation

```bash
/plugin marketplace add path/to/marketplace
/plugin install %s@marketplace-name
```

## Components

%s

## Usage

[How to use this plugin]

## Configuration

[Any configuration options]

## Output

If hooks are enabled, outputs are written to `claude-outputs/`:

```
claude-outputs/
├── logs/        # Session and operation logs
├── artifacts/   # Generated files
└── temp/        # Temporary files (cleaned on session end)
```

Add to `.gitignore`:
```
claude-outputs/
.claude/settings.local.json
```
"""


def title_case(name):
    """Convert hyphenated name to Title Case."""
    return ' '.join(word.capitalize() for word in name.split('-'))


def validate_name(name):
    """Validate plugin/component name follows conventions."""
    if not name:
        return False, "Name cannot be empty"
    if not re.match(r'^[a-z0-9-]+$', name):
        return False, "Name must be hyphen-case (lowercase letters, digits, hyphens only)"
    if name.startswith('-') or name.endswith('-') or '--' in name:
        return False, "Name cannot start/end with hyphen or have consecutive hyphens"
    if len(name) > 64:
        return False, f"Name too long ({len(name)} chars). Maximum is 64."
    return True, "Valid"


def init_plugin(plugin_name, path, components=None):
    """
    Initialize a new plugin directory with selected components.

    Args:
        plugin_name: Name of the plugin (hyphen-case)
        path: Directory where plugin folder should be created
        components: List of components to include (skill, command, agent, hook, mcp)

    Returns:
        Path to created plugin directory, or None if error
    """
    # Validate name
    valid, msg = validate_name(plugin_name)
    if not valid:
        print(f"Error: Invalid name: {msg}")
        return None

    if components is None:
        components = ['skill']  # Default to skill only

    plugin_dir = Path(path).resolve() / plugin_name

    if plugin_dir.exists():
        print(f"Error: Directory already exists: {plugin_dir}")
        return None

    try:
        plugin_dir.mkdir(parents=True, exist_ok=False)
        print(f"Created: {plugin_dir}")
    except Exception as e:
        print(f"Error creating directory: {e}")
        return None

    # Create .claude-plugin/plugin.json (required)
    try:
        claude_plugin_dir = plugin_dir / '.claude-plugin'
        claude_plugin_dir.mkdir()
        (claude_plugin_dir / 'plugin.json').write_text(
            PLUGIN_JSON_TEMPLATE % plugin_name
        )
        print("Created .claude-plugin/plugin.json")
    except Exception as e:
        print(f"Error creating plugin.json: {e}")
        return None

    plugin_title = title_case(plugin_name)
    component_list = []

    # Create components based on selection
    if 'skill' in components:
        try:
            skill_dir = plugin_dir / 'skills' / plugin_name
            skill_dir.mkdir(parents=True)
            (skill_dir / 'SKILL.md').write_text(
                SKILL_TEMPLATE % (plugin_name, plugin_title)
            )
            (skill_dir / 'references').mkdir()
            print(f"Created skills/{plugin_name}/SKILL.md")
            component_list.append(f"- **Skill**: `{plugin_name}`")
        except Exception as e:
            print(f"Error creating skill: {e}")

    if 'command' in components:
        try:
            cmd_dir = plugin_dir / 'commands'
            cmd_dir.mkdir()
            cmd_name = plugin_name.split('-')[0]  # Use first word
            (cmd_dir / f'{cmd_name}.md').write_text(
                COMMAND_TEMPLATE % plugin_title
            )
            print(f"Created commands/{cmd_name}.md")
            component_list.append(f"- **Command**: `/{cmd_name}`")
        except Exception as e:
            print(f"Error creating command: {e}")

    if 'agent' in components:
        try:
            agent_dir = plugin_dir / 'agents'
            agent_dir.mkdir()
            agent_name = plugin_name.replace('-', '-') + '-agent'
            (agent_dir / f'{agent_name}.md').write_text(
                AGENT_TEMPLATE % (agent_name, plugin_title + ' Agent')
            )
            print(f"Created agents/{agent_name}.md")
            component_list.append(f"- **Agent**: `{agent_name}`")
        except Exception as e:
            print(f"Error creating agent: {e}")

    if 'hook' in components:
        try:
            hooks_dir = plugin_dir / 'hooks'
            hooks_dir.mkdir()
            (hooks_dir / 'hooks.json').write_text(HOOKS_TEMPLATE)
            print("Created hooks/hooks.json")

            scripts_dir = plugin_dir / 'scripts'
            scripts_dir.mkdir(exist_ok=True)

            # SessionStart - output setup
            setup_script = scripts_dir / 'setup-output.sh'
            setup_script.write_text(SETUP_OUTPUT_SCRIPT)
            setup_script.chmod(0o755)
            print("Created scripts/setup-output.sh")

            # PostToolUse - example hook
            hook_script = scripts_dir / 'example-hook.sh'
            hook_script.write_text(HOOK_SCRIPT_TEMPLATE)
            hook_script.chmod(0o755)
            print("Created scripts/example-hook.sh")

            # SessionEnd - cleanup
            cleanup_script = scripts_dir / 'cleanup.sh'
            cleanup_script.write_text(CLEANUP_SCRIPT)
            cleanup_script.chmod(0o755)
            print("Created scripts/cleanup.sh")

            component_list.append("- **Hooks**: SessionStart, PostToolUse, SessionEnd")
            component_list.append("- **Output**: `claude-outputs/` directory (logs, artifacts, temp)")
        except Exception as e:
            print(f"Error creating hooks: {e}")

    if 'mcp' in components:
        try:
            (plugin_dir / '.mcp.json').write_text(MCP_TEMPLATE)
            print("Created .mcp.json")
            component_list.append("- **MCP Server**: server-name")
        except Exception as e:
            print(f"Error creating MCP config: {e}")

    # Create README
    try:
        components_text = '\n'.join(component_list) if component_list else '- None'
        (plugin_dir / 'README.md').write_text(
            README_TEMPLATE % (plugin_title, plugin_name, components_text)
        )
        print("Created README.md")
    except Exception as e:
        print(f"Error creating README: {e}")

    print(f"\nPlugin '{plugin_name}' initialized at {plugin_dir}")
    print("\nNext steps:")
    print("1. Edit plugin.json - update description and metadata")
    print("2. Complete component files with your content")
    print("3. Test locally: /plugin marketplace add ./path && /plugin install")
    print("4. Package for distribution")

    return plugin_dir


def main():
    if len(sys.argv) < 4 or sys.argv[2] != '--path':
        print("Usage: init_plugin.py <plugin-name> --path <path> [--components <list>]")
        print("\nComponents (comma-separated):")
        print("  skill   - Model-invoked capability")
        print("  command - User-invoked slash command")
        print("  agent   - Specialized assistant")
        print("  hook    - Event-triggered automation")
        print("  mcp     - MCP server configuration")
        print("\nExamples:")
        print("  init_plugin.py my-tools --path ./plugins")
        print("  init_plugin.py my-tools --path ./plugins --components command,hook")
        print("  init_plugin.py my-tools --path ./plugins --components skill,agent")
        sys.exit(1)

    plugin_name = sys.argv[1]
    path = sys.argv[3]

    # Parse optional components
    components = ['skill']  # Default
    for i, arg in enumerate(sys.argv):
        if arg == '--components' and i + 1 < len(sys.argv):
            components = [c.strip() for c in sys.argv[i + 1].split(',')]

    print(f"Initializing plugin: {plugin_name}")
    print(f"Location: {path}")
    print(f"Components: {', '.join(components)}\n")

    result = init_plugin(plugin_name, path, components)
    sys.exit(0 if result else 1)


if __name__ == "__main__":
    main()
