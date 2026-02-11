# Packaging Plugins

Prepare your plugin for distribution through marketplaces.

## Pre-Packaging Checklist

### Required Files

- [ ] `.claude-plugin/plugin.json` - Valid manifest
- [ ] At least one component (command, agent, skill, hook, or MCP)

### Recommended Files

- [ ] `README.md` - Installation and usage instructions
- [ ] `CHANGELOG.md` - Version history
- [ ] `LICENSE` - License file

### Quality Checks

- [ ] All JSON files parse correctly
- [ ] All markdown frontmatter is valid YAML
- [ ] Scripts are executable (`chmod +x`)
- [ ] No hardcoded paths (use `${CLAUDE_PLUGIN_ROOT}`)
- [ ] No secrets in committed files

## Directory Structure

```
plugin-name/
├── .claude-plugin/
│   └── plugin.json          # Required
├── commands/                 # Optional
│   └── *.md
├── agents/                   # Optional
│   └── *.md
├── skills/                   # Optional
│   └── skill-name/
│       └── SKILL.md
├── hooks/                    # Optional
│   └── hooks.json
├── scripts/                  # Optional
│   └── *.sh
├── .mcp.json                # Optional
├── README.md                # Recommended
├── CHANGELOG.md             # Recommended
└── LICENSE                  # Recommended
```

## Validation Script

Create a validation script:

```bash
#!/bin/bash
# validate-plugin.sh

set -e

echo "Validating plugin..."

# Check plugin.json exists
if [ ! -f ".claude-plugin/plugin.json" ]; then
  echo "ERROR: .claude-plugin/plugin.json not found"
  exit 1
fi

# Validate JSON
cat .claude-plugin/plugin.json | jq . > /dev/null
echo "✓ plugin.json is valid JSON"

# Check commands
if [ -d "commands" ]; then
  for cmd in commands/*.md; do
    if [ -f "$cmd" ]; then
      # Check for frontmatter
      if ! head -1 "$cmd" | grep -q "^---"; then
        echo "WARNING: $cmd missing frontmatter"
      fi
    fi
  done
  echo "✓ Commands checked"
fi

# Check agents
if [ -d "agents" ]; then
  for agent in agents/*.md; do
    if [ -f "$agent" ]; then
      if ! head -1 "$agent" | grep -q "^---"; then
        echo "WARNING: $agent missing frontmatter"
      fi
    fi
  done
  echo "✓ Agents checked"
fi

# Check skills
if [ -d "skills" ]; then
  for skill_dir in skills/*/; do
    if [ ! -f "${skill_dir}SKILL.md" ]; then
      echo "WARNING: ${skill_dir} missing SKILL.md"
    fi
  done
  echo "✓ Skills checked"
fi

# Check hooks
if [ -f "hooks/hooks.json" ]; then
  cat hooks/hooks.json | jq . > /dev/null
  echo "✓ hooks.json is valid JSON"
fi

# Check MCP
if [ -f ".mcp.json" ]; then
  cat .mcp.json | jq . > /dev/null
  echo "✓ .mcp.json is valid JSON"
fi

# Check scripts are executable
if [ -d "scripts" ]; then
  for script in scripts/*.sh scripts/*.py; do
    if [ -f "$script" ] && [ ! -x "$script" ]; then
      echo "WARNING: $script is not executable"
    fi
  done
  echo "✓ Scripts checked"
fi

echo ""
echo "Plugin validation complete!"
```

## Plugin.json Requirements

Minimum viable:

```json
{
  "name": "my-plugin"
}
```

Recommended for distribution:

```json
{
  "name": "my-plugin",
  "version": "1.0.0",
  "description": "Brief description of plugin purpose",
  "author": {
    "name": "Your Name"
  },
  "license": "MIT",
  "keywords": ["keyword1", "keyword2"],
  "repository": "https://github.com/username/plugin"
}
```

## README Template

```markdown
# Plugin Name

Brief description of what this plugin does.

## Installation

1. Add marketplace (if not already added):
   ```
   /plugin marketplace add username/marketplace-repo
   ```

2. Install plugin:
   ```
   /plugin install plugin-name@marketplace
   ```

## Features

- Feature 1: Description
- Feature 2: Description

## Commands

- `/command-name` - What it does

## Agents

- `agent-name` - What expertise it provides

## Skills

- `skill-name` - What capability it adds

## Configuration

Any configuration options...

## License

MIT License
```

## Testing Before Distribution

1. **Fresh install test**:
   - Remove local plugin
   - Install from marketplace
   - Verify all components work

2. **Test each component**:
   - Run each command
   - Trigger each agent
   - Query for each skill
   - Trigger hook events

3. **Error handling**:
   - Test with invalid inputs
   - Verify graceful failures

## API & Organization Distribution

Beyond GitHub and marketplace distribution, skills can be deployed programmatically.

### Organization-Level Deployment (since Dec 2025)
- Admins deploy skills workspace-wide for all users
- Automatic updates when skill is updated
- Centralized management via Claude Console

### Skills API
- `/v1/skills` endpoint for listing and managing skills
- Add skills to Messages API requests via `container.skills` parameter
- Version control and management through Claude Console
- Works with Claude Agent SDK for building custom agents

| Use Case | Best Surface |
|----------|-------------|
| End users interacting directly | Claude.ai / Claude Code |
| Manual testing and iteration | Claude.ai / Claude Code |
| Applications using skills programmatically | API |
| Production deployments at scale | API |
| Automated pipelines and agent systems | API |

**Note:** Skills in the API require the Code Execution Tool beta.

## See Also

- `marketplace.md` - marketplace distribution
- `versioning.md` - version management
- `debugging.md` - troubleshooting
