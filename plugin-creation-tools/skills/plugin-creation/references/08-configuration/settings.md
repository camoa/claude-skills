# Settings Configuration

Claude Code settings control plugin behavior, permissions, and environment. Settings follow a hierarchy where more specific settings override general ones.

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

Custom environment variables:

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
