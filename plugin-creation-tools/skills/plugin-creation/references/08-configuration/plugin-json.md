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
  "mcpServers": "./.mcp.json"
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

## Environment Variables

Available in paths:

| Variable | Description |
|----------|-------------|
| `${CLAUDE_PLUGIN_ROOT}` | Plugin installation directory |

Example:
```json
{
  "mcpServers": {
    "my-server": {
      "command": "${CLAUDE_PLUGIN_ROOT}/servers/my-server"
    }
  }
}
```

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
  "mcpServers": "./.mcp.json"
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
