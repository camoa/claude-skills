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
| owner | object | **Yes** | Marketplace owner info |
| metadata | object | No | Marketplace metadata |
| plugins | array | **Yes** | List of available plugins |
| tags | array | No | Marketplace-level categorization tags for filtering and discovery |
| strict | boolean | No | Default: `true`. When true, `plugin.json` in each plugin is the authority for plugin metadata. When false, the marketplace entry itself is the entire plugin definition (no separate `plugin.json` needed). |
| allowCrossMarketplaceDependenciesOn | array | No | Names of other marketplaces whose plugins this marketplace's plugins are permitted to depend on. Without this allowlist, dependencies that name a different marketplace are blocked at install. See [Cross-marketplace dependencies](#allow-cross-marketplace-dependencies-allowcrossmarketplacedependencieson). |

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
| homepage | string | No | Plugin homepage URL; overrides value from plugin.json |
| repository | string | No | Plugin repository URL; overrides value from plugin.json |
| license | string | No | Plugin license identifier; overrides value from plugin.json |
| `defaultEnabled` | boolean | No | **v2.1.154+** Whether the plugin is enabled after install (default: `true`). Set `false` to install it disabled until the user opts in. Overrides the same field in the plugin's `plugin.json`. |
| commands | array/string | No | Command paths; overrides value from plugin.json |
| agents | array/string | No | Agent paths; overrides value from plugin.json |
| hooks | string | No | Hooks file path; overrides value from plugin.json |
| mcpServers | string | No | MCP servers file path; overrides value from plugin.json |
| lspServers | string | No | LSP servers file path; overrides value from plugin.json |

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

## Plugin Dependencies — Marketplace Author Responsibilities

When a plugin in your marketplace declares [dependencies](plugin-json.md#dependencies-version-constrained), your marketplace must support the resolution model:

### 1. Tag releases for version resolution

Version constraints resolve against git tags on the marketplace repository. Each plugin release must be tagged as `{plugin-name}--v{version}`:

```bash
git tag secrets-vault--v2.1.0
git tag deploy-kit--v3.1.0
git push origin --tags
```

The `{plugin-name}--v` prefix lets one repository host multiple plugins with independent version lines. The `version` tagged must match the `version` field in that commit's `plugin.json`.

**Without matching tags**, dependents fail with `no-matching-tag` and are disabled.

### 2. Allow cross-marketplace dependencies (`allowCrossMarketplaceDependenciesOn`)

A plugin in your marketplace can depend on a plugin in a **different** marketplace by setting `"marketplace": "<other-marketplace-name>"` in its dependency entry. This is **blocked by default**: name the trusted marketplaces in `allowCrossMarketplaceDependenciesOn` on the marketplace's root `marketplace.json`.

```json
{
  "name": "camoa-skills",
  "owner": {"name": "camoa"},
  "allowCrossMarketplaceDependenciesOn": ["palcera_skills", "anthropic-tools"],
  "plugins": [
    {
      "name": "design-toolkit",
      "source": "./plugins/design-toolkit"
    }
  ]
}
```

With the entry above, `design-toolkit` may declare `{"name": "brand-engine", "marketplace": "palcera_skills"}` in its `dependencies`. Without the entry, the install fails with a clear cross-marketplace-dependency error.

**Trust does not chain.** Only the **root** marketplace's allowlist is consulted — i.e., the marketplace the user installed the dependent plugin from. If `palcera_skills` itself allows `third-party-marketplace`, that does **not** transitively grant `camoa-skills` access; you must list `third-party-marketplace` in `camoa-skills`'s own `allowCrossMarketplaceDependenciesOn` if a `camoa-skills` plugin needs it.

#### `allowCrossMarketplaceDependenciesOn` vs `hostPattern` / `pathPattern`

These solve different problems. Don't confuse them:

| Field | Lives in | Controls |
|-------|----------|----------|
| `allowCrossMarketplaceDependenciesOn` | Root `marketplace.json` (the marketplace you author) | Which **other marketplaces** your plugins are allowed to declare cross-marketplace dependencies on. |
| `hostPattern` / `pathPattern` (inside `strictKnownMarketplaces` / `extraKnownMarketplaces` in managed/user `settings.json`) | User or admin `settings.json` | Which **sources** (host + path regex) the user's installation is allowed to add a marketplace from. Gates marketplace **install location**, not dependency trust. |

A plugin install can fail for either reason: the marketplace the dependency lives in isn't allowlisted in your `allowCrossMarketplaceDependenciesOn` (your problem to fix), or the user's `strictKnownMarketplaces` doesn't permit the upstream marketplace's source (their admin's problem to fix).

#### `blockedMarketplaces` enforcement points

When admins configure `blockedMarketplaces` in managed settings, the block is checked at every entry point — `add`, `install`, **`update`**, **`refresh`**, and **`auto-update`** — not just at first install. A marketplace that gets added to the blocklist after install is denied on the next refresh/update cycle.

### 3. Tag plugin releases (`claude plugin tag`)

Use `claude plugin tag` (run from inside a plugin's folder) to create the `{plugin-name}--v{version}` git tag that version constraints resolve against. Pinned plugins (those whose dependents declare `version`) auto-update to the **highest satisfying tag** — without tags, dependents fail with `no-matching-tag` and stay disabled.

```bash
# From inside the plugin directory
claude plugin tag             # create {plugin-name}--v{version} from plugin.json
claude plugin tag --push      # also push the tag to origin
claude plugin tag --dry-run   # show what would be tagged
claude plugin tag --force     # tag even if working tree is dirty or tag exists
```

This replaces the manual `git tag {plugin-name}--v{version} && git push origin --tags` flow. The tag's `{version}` must match the `version` field in that commit's `plugin.json`.

### 4. Validator behavior

When a plugin is installed, Claude Code:

1. Reads its `dependencies` array from `plugin.json`
2. Resolves each entry against the marketplace's tag list (tag-based sources) or declared version (npm/pip)
3. Intersects the resolved range with constraints from other installed plugins
4. Fails the install if any error fires (`range-conflict`, `no-matching-tag`, `dependency-version-unsatisfied`)

Surfaced in `claude plugin list`, `/plugin`, and `/doctor`. The affected plugin is disabled until resolved. See [`plugin-json.md`](plugin-json.md#common-dependency-errors) for the full error table.

## Reserved Marketplace Names

The following names are reserved by Anthropic and cannot be used for custom marketplaces:

- `claude-code-marketplace`
- `claude-code-plugins`
- `claude-plugins-official`
- `anthropic-marketplace`
- `anthropic-plugins`
- `agent-skills`
- `life-sciences`
- `knowledge-work-plugins`

Using a reserved name will cause marketplace registration to fail.

## See Also

- `plugin-json.md` - plugin manifest
- `settings.md` - settings configuration
- `../10-distribution/marketplace.md` - distribution strategies
