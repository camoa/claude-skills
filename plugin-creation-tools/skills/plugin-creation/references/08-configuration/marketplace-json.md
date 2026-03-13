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
  "tags": ["internal", "devtools"],
  "strict": true,
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
| tags | array | No | Marketplace-level categorization tags for filtering and discovery |
| strict | boolean | No | Default: `true`. When true, `plugin.json` in each plugin is the authority for plugin metadata. When false, the marketplace entry itself is the entire plugin definition (no separate `plugin.json` needed). |

### Metadata Object Fields

| Field | Description |
|-------|-------------|
| `description` | Human-readable marketplace description |
| `version` | Marketplace schema version |
| `pluginRoot` | Base directory prepended to relative source paths in plugin entries. Example: with `"pluginRoot": "./plugins"`, a source of `"./formatter"` resolves to `./plugins/formatter`. |

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

### Git Subdirectory (Monorepo)

Plugin in a subdirectory of a larger repository. Uses sparse clone for efficiency:

```json
{
  "name": "monorepo-plugin",
  "source": {
    "source": "git-subdir",
    "url": "https://github.com/org/monorepo.git",
    "path": "packages/claude-plugin",
    "ref": "main",
    "sha": "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
  }
}
```

| Field | Required | Description |
|-------|----------|-------------|
| url | Yes | Repository URL |
| path | Yes | Subdirectory path within the repo |
| ref | No | Branch or tag name |
| sha | No | Full 40-character commit SHA for pinning |

### npm

Install from npm registry:

```json
{
  "name": "npm-plugin",
  "source": {
    "source": "npm",
    "package": "@company/claude-plugin",
    "version": "^2.0.0",
    "registry": "https://registry.npmjs.org"
  }
}
```

| Field | Required | Description |
|-------|----------|-------------|
| package | Yes | npm package name |
| version | No | Version or range (semver ranges supported) |
| registry | No | Custom registry URL (defaults to npmjs.org) |

### pip

Install from pip:

```json
{
  "name": "pip-plugin",
  "source": {
    "source": "pip",
    "package": "claude-plugin-name"
  }
}
```

### Ref and SHA Pinning

GitHub and URL sources support `ref` and `sha` fields for version pinning:

```json
{
  "name": "pinned-plugin",
  "source": {
    "source": "github",
    "repo": "org/plugin-repo",
    "ref": "v2.1.0",
    "sha": "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
  }
}
```

- `ref` — branch name or tag (e.g., `"main"`, `"v2.1.0"`)
- `sha` — full 40-character commit SHA for exact pinning

When both are specified, `sha` takes precedence. Using `sha` ensures reproducible installs regardless of branch changes.

## Private Repository Authentication

For private repositories, Claude Code uses environment variables for authentication:

| Variable | Service |
|----------|---------|
| `GITHUB_TOKEN` or `GH_TOKEN` | GitHub |
| `GITLAB_TOKEN` or `GL_TOKEN` | GitLab |
| `BITBUCKET_TOKEN` | Bitbucket |

Set the appropriate token in your environment before adding marketplaces or installing plugins from private repositories.

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
