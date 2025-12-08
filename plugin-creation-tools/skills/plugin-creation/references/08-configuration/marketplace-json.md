# Marketplace Configuration

Marketplaces are catalogs that distribute Claude Code plugins. Configure them with `marketplace.json`.

## File Location

**Location**: `.claude-plugin/marketplace.json` in repository root

```
marketplace-repo/
├── .claude-plugin/
│   └── marketplace.json
├── plugins/
│   ├── plugin-one/
│   └── plugin-two/
└── README.md
```

## Complete Schema

```json
{
  "name": "company-tools",
  "owner": {
    "name": "DevTools Team",
    "email": "devtools@company.com"
  },
  "metadata": {
    "description": "Internal tools and utilities",
    "version": "1.0.0",
    "pluginRoot": "./plugins"
  },
  "plugins": [
    {
      "name": "code-formatter",
      "source": "./plugins/formatter",
      "description": "Automatic code formatting",
      "version": "2.1.0",
      "author": {
        "name": "DevTools Team"
      },
      "keywords": ["formatting", "code-quality"],
      "category": "productivity"
    }
  ]
}
```

## Top-Level Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| name | string | **Yes** | Marketplace identifier |
| owner | object | No | Marketplace owner info |
| metadata | object | No | Marketplace metadata |
| plugins | array | **Yes** | List of available plugins |

## Plugin Entry Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| name | string | **Yes** | Plugin name |
| source | string/object | **Yes** | Plugin location |
| description | string | No | Plugin description |
| version | string | No | Plugin version |
| author | object | No | Plugin author |
| keywords | array | No | Search tags |
| category | string | No | Plugin category |

## Plugin Source Types

### Relative Path

Same repository:

```json
{
  "name": "my-plugin",
  "source": "./plugins/my-plugin"
}
```

### GitHub

Separate repository on GitHub:

```json
{
  "name": "github-plugin",
  "source": {
    "source": "github",
    "repo": "owner/plugin-repo"
  }
}
```

### Git URL

Any git hosting:

```json
{
  "name": "git-plugin",
  "source": {
    "source": "url",
    "url": "https://gitlab.com/team/plugin.git"
  }
}
```

## Hosting Options

### GitHub (Recommended)

```bash
# Add marketplace
/plugin marketplace add owner/repo
```

Benefits:
- Version control
- Collaboration
- Easy sharing

### Other Git Services

```bash
# GitLab
/plugin marketplace add https://gitlab.com/company/plugins.git

# Gitea
/plugin marketplace add https://git.company.com/plugins.git
```

### Local/Development

```bash
# Local path
/plugin marketplace add ./path/to/marketplace
```

## Example: Single Repository Marketplace

All plugins in one repository:

```json
{
  "name": "team-tools",
  "owner": {
    "name": "Dev Team"
  },
  "plugins": [
    {
      "name": "linter",
      "source": "./plugins/linter",
      "description": "Code linting tools"
    },
    {
      "name": "formatter",
      "source": "./plugins/formatter",
      "description": "Code formatting"
    },
    {
      "name": "tester",
      "source": "./plugins/tester",
      "description": "Test utilities"
    }
  ]
}
```

## Example: Distributed Marketplace

Plugins in separate repositories:

```json
{
  "name": "org-plugins",
  "plugins": [
    {
      "name": "core-tools",
      "source": {
        "source": "github",
        "repo": "org/core-tools-plugin"
      }
    },
    {
      "name": "deploy-tools",
      "source": {
        "source": "github",
        "repo": "org/deploy-plugin"
      }
    }
  ]
}
```

## User Installation

Users add marketplaces and install plugins:

```bash
# Add marketplace
/plugin marketplace add owner/repo

# List available plugins
/plugin marketplace list

# Install plugin
/plugin install plugin-name@marketplace-name
```

## Team Distribution

For team-wide availability, add to project settings:

```json
{
  "extraKnownMarketplaces": {
    "team-tools": {
      "source": {
        "source": "github",
        "repo": "company/claude-plugins"
      }
    }
  }
}
```

Team members are prompted to install when they trust the folder.

## See Also

- `plugin-json.md` - plugin manifest
- `settings.md` - settings configuration
- `../10-distribution/marketplace.md` - distribution strategies
