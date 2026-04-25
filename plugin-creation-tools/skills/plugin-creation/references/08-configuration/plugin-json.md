# Plugin Manifest (plugin.json)

The plugin manifest defines your plugin's metadata and component locations.

## Location

**Required**: `.claude-plugin/plugin.json`

```
plugin-name/
└── .claude-plugin/
    └── plugin.json
```

## Complete Schema

```json
{
  "name": "enterprise-tools",
  "version": "3.0.0",
  "description": "Enterprise automation, security, and deployment tools",
  "author": {
    "name": "DevOps Team",
    "email": "devops@company.com",
    "url": "https://github.com/company"
  },
  "homepage": "https://docs.company.com/plugins/enterprise-tools",
  "repository": "https://github.com/company/enterprise-plugin",
  "license": "MIT",
  "keywords": ["enterprise", "deployment", "security", "automation"],
  "commands": [
    "./commands/deploy.md",
    "./custom/commands/special.md"
  ],
  "agents": [
    "./agents/security-reviewer.md",
    "./agents/compliance-checker.md"
  ],
  "hooks": "./hooks/hooks.json",
  "mcpServers": "./.mcp.json",
  "lspServers": "./.lsp.json"
}
```

## Required Fields

| Field | Type | Description |
|-------|------|-------------|
| name | string | Unique identifier (kebab-case, no spaces) |

The `name` field is the **only required field**.

## Metadata Fields

| Field | Type | Description |
|-------|------|-------------|
| version | string | Semantic version (e.g., "2.1.0") |
| description | string | Brief explanation of plugin purpose |
| author | object/string | Author information |
| homepage | string | Documentation URL |
| repository | string | Source code URL |
| license | string | SPDX identifier (MIT, Apache-2.0, etc.) |
| keywords | array | Discovery tags |

### Author Object

```json
{
  "author": {
    "name": "Your Name",
    "email": "you@example.com",
    "url": "https://github.com/username"
  }
}
```

Or simple string:
```json
{
  "author": "Your Name <you@example.com>"
}
```

## Component Path Fields

| Field | Type | Description |
|-------|------|-------------|
| commands | string/array | Custom command file paths |
| agents | string/array | Custom agent file paths |
| skills | string/array | Custom skill directory paths |
| hooks | string/object | Hook config path or inline config |
| mcpServers | string/object | MCP config path or inline config |
| lspServers | string/object | LSP config path or inline config |
| outputStyles | string/array | Custom output style paths |
| themes | string/array | Color theme files/directories (replaces default `themes/`). Each file: `name`, `base`, `overrides`. See [`themes.md`](themes.md) for the full schema. |
| userConfig | object | User-configurable values prompted at enable time. See [User configuration](#user-configuration) below. |
| settings | string | Path to settings.json (only `agent` key supported) |

### Path Patterns

**Single path**:
```json
{
  "commands": "./custom-commands/deploy.md"
}
```

**Multiple paths (array)**:
```json
{
  "commands": [
    "./commands/deploy.md",
    "./commands/status.md",
    "./other/special.md"
  ]
}
```

**Inline configuration**:
```json
{
  "hooks": {
    "PostToolUse": [...]
  }
}
```

## mcpServers Configuration

The `mcpServers` field configures MCP (Model Context Protocol) servers that provide external tool integrations. It can be a path to a `.mcp.json` file or an inline object.

### Path reference
```json
{
  "mcpServers": "./.mcp.json"
}
```

### Inline configuration
```json
{
  "mcpServers": {
    "my-database": {
      "command": "${CLAUDE_PLUGIN_ROOT}/servers/db-server",
      "args": ["--port", "5432"],
      "env": {
        "DB_HOST": "localhost"
      },
      "cwd": "${CLAUDE_PLUGIN_ROOT}"
    },
    "my-api": {
      "command": "npx",
      "args": ["-y", "@company/api-mcp-server"],
      "env": {
        "API_KEY": ""
      }
    }
  }
}
```

### MCP Server Fields

| Field | Type | Description |
|-------|------|-------------|
| command | string | Executable to run the server |
| args | array | Command-line arguments |
| env | object | Environment variables |
| cwd | string | Working directory for the server |

The format matches the standard MCP configuration with server name as the key, and command, args, env, and cwd as server properties.

## lspServers Configuration

The `lspServers` field configures Language Server Protocol servers for code intelligence. It can be a path to a `.lsp.json` file or an inline object.

### Path reference
```json
{
  "lspServers": "./.lsp.json"
}
```

### Inline configuration
```json
{
  "lspServers": {
    "typescript": {
      "command": "typescript-language-server",
      "args": ["--stdio"],
      "extensionToLanguage": {
        ".ts": "typescript",
        ".tsx": "typescriptreact"
      },
      "transport": "stdio",
      "env": {},
      "initializationOptions": {},
      "settings": {},
      "workspaceFolder": "${CLAUDE_PLUGIN_ROOT}",
      "startupTimeout": 10000,
      "shutdownTimeout": 5000,
      "restartOnCrash": true,
      "maxRestarts": 3
    }
  }
}
```

### LSP Server Fields

| Field | Type | Description |
|-------|------|-------------|
| command | string | Executable to run the LSP server |
| args | array | Command-line arguments |
| extensionToLanguage | object | Maps file extensions to language IDs |
| transport | string | Communication transport (e.g., "stdio") |
| env | object | Environment variables |
| initializationOptions | object | LSP initialization options |
| settings | object | LSP workspace settings |
| workspaceFolder | string | Workspace root for the LSP server |
| startupTimeout | number | Milliseconds to wait for server startup |
| shutdownTimeout | number | Milliseconds to wait for server shutdown |
| restartOnCrash | boolean | Whether to restart the server on crash |
| maxRestarts | number | Maximum number of automatic restarts |

## Important Path Rules

1. **Custom paths SUPPLEMENT default directories**
   - If `commands/` exists, it's loaded automatically
   - Custom paths add to (don't replace) defaults

2. **All paths relative to plugin root**
   - Must start with `./`
   - Example: `./commands/deploy.md`

3. **Use forward slashes**
   - Works across all platforms
   - Example: `./path/to/file.md`

## Environment Variables and Path Substitution

Available in all path fields including mcpServers and lspServers command, args, and env values:

| Variable | Description |
|----------|-------------|
| `${CLAUDE_PLUGIN_ROOT}` | Plugin installation directory |
| `${CLAUDE_PLUGIN_DATA}` | Persistent data directory at `~/.claude/plugins/data/{plugin-id}/`. Survives plugin updates (unlike `${CLAUDE_PLUGIN_ROOT}` which is wiped). Use for installed dependencies (node_modules, venvs), caches, and generated data. |

Example:
```json
{
  "mcpServers": {
    "my-server": {
      "command": "${CLAUDE_PLUGIN_ROOT}/servers/my-server",
      "args": ["--config", "${CLAUDE_PLUGIN_ROOT}/config/server.json"],
      "env": {
        "DATA_DIR": "${CLAUDE_PLUGIN_ROOT}/data"
      }
    }
  }
}
```

`${CLAUDE_PLUGIN_ROOT}` is substituted at runtime in all path-accepting fields, including nested values in mcpServers and lspServers configurations.

## User Configuration

The `userConfig` field declares values that Claude Code prompts the user for when the plugin is enabled. Use this instead of asking users to hand-edit `settings.json`. Values are exported to plugin subprocesses as `CLAUDE_PLUGIN_OPTION_<KEY>` env vars and substituted as `${user_config.KEY}` in MCP and LSP server configs, hook commands, monitor commands, and (for non-sensitive values) skill and agent content.

### Schema

```json
{
  "userConfig": {
    "api_endpoint": {
      "type": "string",
      "title": "API endpoint",
      "description": "Your team's API endpoint"
    },
    "api_token": {
      "type": "string",
      "title": "API token",
      "description": "API authentication token",
      "sensitive": true
    },
    "max_retries": {
      "type": "number",
      "title": "Max retries",
      "description": "How many times to retry a failed call",
      "default": 3,
      "min": 0,
      "max": 10
    }
  }
}
```

### Per-entry fields

| Field | Required | Description |
|-------|----------|-------------|
| `type` | Yes | One of `string`, `number`, `boolean`, `directory`, `file`. |
| `title` | Yes | Label shown in the configuration dialog. |
| `description` | Yes | Help text shown beneath the field. |
| `sensitive` | No | If `true`, masks input and stores the value in the system keychain (or `~/.claude/.credentials.json` where unavailable) instead of `settings.json`. Keychain has ~2 KB total budget shared with OAuth tokens — keep secrets small. |
| `required` | No | If `true`, validation fails when the field is empty. |
| `default` | No | Value used when the user provides nothing. |
| `multiple` | No | For `string` type, allow an array of strings. |
| `min` / `max` | No | Bounds for `number` type. |

> **Additive change (2.1.118+):** `type` and `title` were added alongside the original `description`-only form. Description-only entries still work but are treated as legacy — `/plugin-creation-tools:validate` flags them at info level so you can opt into the richer schema when convenient.

Non-sensitive values land in `settings.json` under `pluginConfigs[<plugin-id>].options`. Use `${user_config.KEY}` substitution in MCP/LSP/hook/monitor configs and in skill/agent body text (sensitive values are blocked from skill/agent substitution).

## Dependencies (Version-Constrained)

> **Requires Claude Code v2.1.110 or later.**

A plugin can declare other plugins as dependencies. Without a version constraint, a dependency tracks the latest version shipped in its marketplace, so an upstream breaking change can silently break dependents. Version constraints hold a dependency at a tested range until you choose to move.

### Declaring dependencies

```json
{
  "name": "deploy-kit",
  "version": "3.1.0",
  "dependencies": [
    "audit-logger",
    { "name": "secrets-vault", "version": "~2.1.0" }
  ]
}
```

Each entry is either:
- A **bare string** (plugin name) — tracks whatever version its marketplace ships
- An **object** with these fields:

| Field | Type | Description |
|-------|------|-------------|
| `name` | string (required) | Plugin name. Resolves within the same marketplace as the declaring plugin. |
| `version` | string | A [semver range](https://github.com/npm/node-semver#ranges): `~2.1.0`, `^2.0`, `>=1.4`, `=2.1.0`. The dependency is fetched at the highest tagged version that satisfies the range. |
| `marketplace` | string | Resolve `name` in a different marketplace. Cross-marketplace dependencies are blocked unless the target marketplace is allowlisted in the root marketplace's `marketplace.json`. |

Pre-release versions like `2.0.0-beta.1` are excluded unless the range opts in with a pre-release suffix (e.g. `^2.0.0-0`).

### How constraints resolve

Version constraints resolve against **git tags on the marketplace repository**. Each release must be tagged using the convention `{plugin-name}--v{version}`:

```bash
git tag secrets-vault--v2.1.0
git push origin secrets-vault--v2.1.0
```

The plugin-name prefix lets one repository host multiple plugins with independent version lines.

When multiple installed plugins constrain the same dependency, Claude Code intersects the ranges and picks the highest satisfying tag:

| Plugin A requires | Plugin B requires | Result |
|-------------------|-------------------|--------|
| `^2.0` | `>=2.1` | One install at the highest `2.x` tag ≥ `2.1.0`. Both plugins load. |
| `~2.1` | `~3.0` | Plugin B install fails with `range-conflict`. Plugin A unchanged. |
| `=2.1.0` | none | Dependency pinned to `2.1.0`; auto-update skips newer versions. |

Auto-update skips any upstream release that falls outside an active constraint. When the last constraining plugin is uninstalled, the dependency resumes tracking its marketplace entry.

### Common dependency errors

| Error | Meaning | Fix |
|-------|---------|-----|
| `range-conflict` | Combined ranges have no common satisfying version, or syntax is invalid. | Uninstall one plugin, widen an upstream range, or fix invalid semver syntax. |
| `dependency-version-unsatisfied` | Installed version is outside the declared range. | `claude plugin install <dependency>@<marketplace>` to re-resolve. |
| `no-matching-tag` | Marketplace has no `{name}--v*` tag satisfying the range. | Tag releases using the convention, or relax the range. |

Surfaced in `claude plugin list`, `/plugin`, and `/doctor`. The affected plugin is **disabled** until resolved. For machine-readable output: `claude plugin list --json` (read the `errors` field per plugin).

**npm marketplace sources:** Tag-based resolution does not apply. The constraint is still checked at load time; mismatches disable the plugin with `dependency-version-unsatisfied`.

## Installation Scopes

Plugins can be installed with different scopes:

| Scope | Description |
|-------|-------------|
| user | Default. Available to the current user across all projects |
| project | Available only within a specific project |
| local | Local development install, not shared |
| managed | Installed and managed by an organization or team |

## Plugin Caching

Plugins are copied to a cache directory upon installation. This has important implications:

- **Paths that traverse outside the plugin root will not work** after install, because only the plugin directory tree is copied to cache.
- Files referenced via `../` or absolute paths outside the plugin root will be missing in the cached copy.

**Workarounds:**
- Use symlinks within the plugin directory that point to external resources (symlinks are preserved during copy).
- Restructure the marketplace/plugin so all required files are contained within the plugin root directory.

## Minimal Example

```json
{
  "name": "my-plugin"
}
```

This minimal plugin will still load:
- Commands from `commands/` directory
- Agents from `agents/` directory
- Skills from `skills/` directory

## Recommended Example

```json
{
  "name": "code-quality",
  "version": "1.0.0",
  "description": "Code quality tools for linting and formatting",
  "author": {
    "name": "Your Name"
  },
  "license": "MIT",
  "keywords": ["code-quality", "linting", "formatting"]
}
```

## Full Example

```json
{
  "name": "full-featured-plugin",
  "version": "2.0.0",
  "description": "Complete plugin with all component types",
  "author": {
    "name": "Plugin Author",
    "email": "author@example.com"
  },
  "repository": "https://github.com/author/plugin",
  "license": "MIT",
  "keywords": ["complete", "example"],
  "commands": "./commands",
  "agents": [
    "./agents/reviewer.md",
    "./agents/analyzer.md"
  ],
  "hooks": "./hooks/hooks.json",
  "mcpServers": "./.mcp.json",
  "lspServers": "./.lsp.json"
}
```

## Validation

Ensure your plugin.json is valid JSON:

```bash
# Check syntax
cat .claude-plugin/plugin.json | jq .

# Or use Node
node -e "require('./.claude-plugin/plugin.json')"
```

## settings.json

A `settings.json` file can be placed at the plugin root (alongside `.claude-plugin/`) to provide plugin-level settings:

```
plugin-name/
├── .claude-plugin/
│   └── plugin.json
├── settings.json          # Plugin settings
├── commands/
└── skills/
```

### Supported Keys

| Key | Type | Description |
|-----|------|-------------|
| `agent` | string | Activates one of the plugin's agents as the main thread agent |

### Behavior

- Settings from `settings.json` take priority over `plugin.json` when both define the same configuration
- Unknown keys are silently ignored (forward-compatible)
- Currently only the `agent` key is supported; more keys may be added in future releases

### Example

```json
{
  "agent": "code-reviewer"
}
```

This activates the `code-reviewer` agent (defined in `agents/code-reviewer.md`) as the main thread agent for the plugin.

## Runtime Environment Variables

These environment variables control plugin runtime behavior:

| Variable | Description |
|----------|-------------|
| `FORCE_AUTOUPDATE_PLUGINS=true` | Keeps plugin auto-updates enabled even when `DISABLE_AUTOUPDATER` disables Claude Code self-updates. Useful in CI or managed environments where you want plugins to stay current without updating Claude Code itself. |

## See Also

- `marketplace-json.md` - marketplace configuration
- `settings.md` - settings hierarchy
- `../10-distribution/packaging.md` - packaging guide
