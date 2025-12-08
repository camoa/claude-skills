# MCP Server Overview

MCP (Model Context Protocol) servers provide connections to external tools, databases, and APIs. This guide covers MCP configuration within Claude Code plugins.

## Scope

This is an **overview guide** for configuring MCP servers within plugins. For comprehensive MCP server development, see the official documentation:

- **Official MCP Documentation**: https://modelcontextprotocol.io/
- **MCP Specification**: https://spec.modelcontextprotocol.io/

## File Location

Place MCP configuration in:
```
plugin-name/
├── .mcp.json              # MCP server configuration
└── servers/               # Server binaries (optional)
    └── my-server
```

Or inline in `plugin.json`:
```json
{
  "name": "my-plugin",
  "mcpServers": {
    "server-name": { ... }
  }
}
```

## Basic Configuration

### Stdio Transport (Local)

```json
{
  "database-tools": {
    "command": "${CLAUDE_PLUGIN_ROOT}/servers/db-server",
    "args": ["--config", "${CLAUDE_PLUGIN_ROOT}/config.json"],
    "env": {
      "DB_PATH": "${CLAUDE_PLUGIN_ROOT}/data"
    }
  }
}
```

### HTTP Transport (Remote)

```json
{
  "remote-api": {
    "type": "http",
    "url": "https://api.example.com/mcp",
    "headers": {
      "Authorization": "Bearer ${API_KEY}"
    }
  }
}
```

## Configuration Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| command | string | Yes (stdio) | Executable path |
| type | string | No | "http" or "sse" (omit for stdio) |
| url | string | Yes (http/sse) | Remote server URL |
| args | array | No | Command-line arguments |
| env | object | No | Environment variables |
| cwd | string | No | Working directory |
| headers | object | No | HTTP headers (http only) |

## Transport Types

### stdio (Local Processes)

- Direct system access
- Fastest performance
- No network overhead
- Use for: Local tools, databases, file operations

### HTTP (Remote Services)

- Network-based
- Cloud API integration
- Cross-machine communication
- Use for: Cloud services, remote APIs

### SSE (Deprecated)

- Server-Sent Events
- Legacy support only
- Use HTTP for new implementations

## Environment Variables

Use environment variables for configuration:

```json
{
  "my-server": {
    "command": "${CLAUDE_PLUGIN_ROOT}/servers/my-server",
    "env": {
      "API_KEY": "${MY_API_KEY}",
      "DB_URL": "${DATABASE_URL}",
      "LOG_LEVEL": "info"
    }
  }
}
```

## When to Use MCP

| Use Case | MCP Appropriate? |
|----------|------------------|
| External API integration | Yes |
| Database queries | Yes |
| Custom tools beyond Claude's built-ins | Yes |
| Third-party service access | Yes |
| Simple prompts | No - use Commands |
| Complex workflows | No - use Skills |
| Event automation | No - use Hooks |

## Example: Database Server

```json
{
  "sqlite-tools": {
    "command": "${CLAUDE_PLUGIN_ROOT}/servers/sqlite-mcp",
    "args": ["--db", "${CLAUDE_PROJECT_DIR}/app.db"],
    "env": {
      "SQLITE_TIMEOUT": "5000"
    }
  }
}
```

## Example: External API

```json
{
  "github-api": {
    "type": "http",
    "url": "https://api.github.com/mcp",
    "headers": {
      "Authorization": "token ${GITHUB_TOKEN}",
      "Accept": "application/vnd.github.v3+json"
    }
  }
}
```

## Using MCP Tools in Skills

When referencing MCP tools in skill instructions, **always use fully qualified names**:

```markdown
# Good - fully qualified
Use the BigQuery:bigquery_schema tool to retrieve table schemas.
Use the GitHub:create_issue tool to create issues.

# Bad - will fail with "tool not found"
Use the bigquery_schema tool...
Use create_issue to...
```

Format: `ServerName:tool_name`

## Best Practices

1. **Use fully qualified tool names**
   - Format: `ServerName:tool_name`
   - Required when multiple MCP servers available
   - Prevents "tool not found" errors

2. **Choose appropriate transport**
   - stdio for local tools
   - HTTP for remote services

3. **Secure credentials**
   - Use environment variables for secrets
   - Never hardcode API keys

4. **Error handling**
   - Log errors clearly
   - Provide helpful messages
   - Handle timeouts gracefully

5. **Performance**
   - Avoid unnecessary initialization
   - Cache when possible
   - Set reasonable timeouts

6. **Security**
   - Validate all inputs
   - Limit command execution scope
   - Audit access patterns

## Server Startup

MCP servers defined in plugins:
1. Start automatically when plugin is enabled
2. Run in the background
3. Appear as tools in Claude's toolkit
4. Restart if they crash (with limits)

## Debugging

Run Claude Code with debug mode:
```bash
claude --debug
```

Look for MCP-related logs to troubleshoot connection issues.

## Resources

- **Official MCP Documentation**: https://modelcontextprotocol.io/
- **MCP Specification**: https://spec.modelcontextprotocol.io/
- **MCP Servers Repository**: https://github.com/modelcontextprotocol/servers

## See Also

- `../01-overview/what-are-mcp.md` - MCP overview
- `../08-configuration/plugin-json.md` - plugin configuration
