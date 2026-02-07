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
| hooks | string/object | Hook config path or inline config |
| mcpServers | string/object | MCP config path or inline config |
| lspServers | string/object | LSP config path or inline config |

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

## See Also

- `marketplace-json.md` - marketplace configuration
- `settings.md` - settings hierarchy
- `../10-distribution/packaging.md` - packaging guide
