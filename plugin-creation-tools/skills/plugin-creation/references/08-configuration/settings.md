# Settings Configuration

Claude Code settings control plugin behavior, permissions, and environment. Settings follow a hierarchy where more specific settings override general ones.

## Important: Plugins Cannot Define Custom Settings

**Plugins cannot add their own settings fields to settings.json.** The available settings fields are fixed by Claude Code. To configure plugin-specific options, use the `env` block pattern described below.

## Settings Hierarchy (Precedence Order)

```
1. Enterprise Managed Policies (Highest Priority)
   ├── /Library/Application Support/ClaudeCode/managed-settings.json (macOS)
   ├── /etc/claude-code/managed-settings.json (Linux/WSL)
   └── C:\Program Files\ClaudeCode\managed-settings.json (Windows)

2. Command Line Arguments
   └── --settings flag overrides for current session

3. Local Project Settings (Not Committed)
   └── .claude/settings.local.json

4. Shared Project Settings (Version Controlled)
   └── .claude/settings.json

5. User Settings (Lowest Priority)
   └── ~/.claude/settings.json
```

Higher priority settings override lower ones.

## Settings File Locations

### User Settings

Global settings for all projects:

| OS | Location |
|----|----------|
| macOS | `~/.claude/settings.json` |
| Linux | `~/.claude/settings.json` |
| Windows | `%USERPROFILE%\.claude\settings.json` |

### Project Settings

Project-specific settings:

```
project/
└── .claude/
    ├── settings.json        # Shared (commit to git)
    └── settings.local.json  # Local (gitignore)
```

## Plugin Settings Fields

### enabledPlugins

Control which plugins are enabled:

```json
{
  "enabledPlugins": {
    "formatter@company-tools": true,
    "deployer@company-tools": true,
    "analyzer@security-plugins": false
  }
}
```

Format: `"plugin-name@marketplace-name": true/false`

### extraKnownMarketplaces

Define additional marketplaces for the team:

```json
{
  "extraKnownMarketplaces": {
    "company-tools": {
      "source": {
        "source": "github",
        "repo": "company/claude-plugins"
      }
    },
    "project-specific": {
      "source": {
        "source": "git",
        "url": "https://git.company.com/project-plugins.git"
      }
    }
  }
}
```

Team members are prompted to install when trusting the folder.

### env

Custom environment variables - **this is how plugins provide configurable options**:

```json
{
  "env": {
    "PLUGIN_OUTPUT_DIR": "${HOME}/claude-outputs",
    "PLUGIN_LOG_LEVEL": "debug",
    "PLUGIN_CONFIG_PATH": "${HOME}/.config/plugins"
  }
}
```

Variables support expansion like `${HOME}`.

## Plugin-Specific Configuration Pattern

Since plugins cannot define custom settings fields, use environment variables with a naming convention:

### Naming Convention

Use `PLUGINNAME_SETTING` format:

```json
{
  "env": {
    "MYFORMATTER_STYLE": "prettier",
    "MYFORMATTER_LINE_WIDTH": "100",
    "MYFORMATTER_TABS": "false",
    "MYDEPLOYER_ENV": "staging",
    "MYDEPLOYER_DRY_RUN": "true"
  }
}
```

### Using in Scripts

```bash
#!/bin/bash
# Use environment variable with fallback default
STYLE="${MYFORMATTER_STYLE:-prettier}"
LINE_WIDTH="${MYFORMATTER_LINE_WIDTH:-80}"

# Boolean handling
if [ "${MYFORMATTER_TABS}" = "true" ]; then
  echo "Using tabs"
fi
```

### Using in Python

```python
import os

style = os.environ.get("MYFORMATTER_STYLE", "prettier")
line_width = int(os.environ.get("MYFORMATTER_LINE_WIDTH", "80"))
use_tabs = os.environ.get("MYFORMATTER_TABS", "false").lower() == "true"
```

### Alternative: Plugin Config File

For complex configuration, your plugin can ship with or read a config file:

```json
// ${CLAUDE_PLUGIN_ROOT}/config.json
{
  "defaults": {
    "style": "prettier",
    "lineWidth": 80
  },
  "rules": {
    "noConsoleLog": true
  }
}
```

Read in scripts:
```bash
CONFIG_FILE="${CLAUDE_PLUGIN_ROOT}/config.json"
STYLE=$(jq -r '.defaults.style' "$CONFIG_FILE")
```

### Documenting Configuration

Always document available configuration in your plugin README:

```markdown
## Configuration

Set these environment variables in `.claude/settings.json`:

| Variable | Default | Description |
|----------|---------|-------------|
| `MYPLUGIN_OUTPUT_DIR` | `./output` | Where to save generated files |
| `MYPLUGIN_LOG_LEVEL` | `info` | Logging verbosity (debug, info, warn, error) |
| `MYPLUGIN_FEATURE_X` | `false` | Enable experimental feature X |
```

### permissions

Control tool permissions:

```json
{
  "permissions": {
    "allow": [
      "Bash(npm run:*)",
      "Edit(./output/**)",
      "Edit(./logs/**)"
    ],
    "deny": [
      "Read(.env)",
      "Read(.env.*)",
      "Read(./secrets/**)"
    ],
    "ask": [
      "Bash(rm:*)"
    ]
  }
}
```

| Permission | Behavior |
|------------|----------|
| allow | Run without prompting |
| deny | Block completely |
| ask | Prompt for confirmation |

## Complete Example

```json
{
  "enabledPlugins": {
    "code-quality@camoa-skills": true,
    "security-tools@org-plugins": true
  },
  "extraKnownMarketplaces": {
    "org-plugins": {
      "source": {
        "source": "github",
        "repo": "myorg/claude-plugins"
      }
    }
  },
  "env": {
    "PLUGIN_OUTPUT_DIR": "${HOME}/claude-outputs",
    "PLUGIN_LOG_LEVEL": "info"
  },
  "permissions": {
    "allow": [
      "Read(./docs/**)",
      "Edit(./output/**)"
    ],
    "deny": [
      "Read(.env*)",
      "Read(./secrets/**)"
    ]
  }
}
```

## Recommended .gitignore

```gitignore
# Claude Code local settings
.claude/settings.local.json
.claude/outputs/
```

## Project vs User Settings

### Use Project Settings For:

- Team-shared configurations
- Project-specific plugins
- Repository marketplace references
- Shared permissions

### Use User Settings For:

- Personal preferences
- Global plugin enablement
- Personal environment variables
- Development overrides

### Use Local Settings For:

- Machine-specific paths
- Temporary overrides
- Secrets and credentials
- Development-only configs

## See Also

- `plugin-json.md` - plugin manifest
- `output-config.md` - output configuration
- `marketplace-json.md` - marketplace setup
