# What Are MCP Servers (Model Context Protocol)?

MCP servers are connections to external tools, databases, and APIs through the standard Model Context Protocol. They start automatically when the plugin is enabled.

## Key Characteristics

- Start automatically when plugin enabled
- Support stdio (local) and HTTP (remote) transports
- Can be configured with arguments and environment variables
- Appear as standard tools in Claude's toolkit
- Can execute commands, query databases, interact with APIs

## When to Use MCP

**Good Use Cases**:
- External API integration
- Database connections
- Custom tool implementations
- Third-party service access
- Complex external operations

**Examples**:
- Database query tool
- Jira/GitHub integration
- Custom deployment tools
- External validation services

## Transport Types

| Transport | Use Case | Example |
|-----------|----------|---------|
| stdio | Local processes, direct system access | Database server |
| HTTP | Remote services, cloud APIs | API integrations |
| SSE | (Deprecated) Server-Sent Events | Legacy systems |

## MCP vs Other Components

| Aspect | MCP | Commands | Skills |
|--------|-----|----------|--------|
| Implementation | External binary/server | Markdown | Markdown + files |
| Best For | External tools | Quick prompts | Workflows |
| Complexity | High | Low | Medium |
| Setup | Requires server code | Just markdown | Just markdown |

## File Location

```
plugin-name/
├── .mcp.json              # MCP configuration
└── servers/               # Server binaries (optional)
    └── db-server
```

Or inline in `plugin.json`.

## Basic Format

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

## HTTP Transport

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

## Scope of This Guide

This guide provides an **overview only** of MCP configuration within plugins. For comprehensive MCP server development:

- **Official MCP Documentation**: https://modelcontextprotocol.io/
- **MCP Server Development**: Requires separate learning

## When to Choose MCP vs Other Options

| Requirement | Solution |
|-------------|----------|
| Simple prompts | Commands |
| Complex workflows | Skills |
| Specialized tasks | Agents |
| External API/database | MCP |
| Event-based automation | Hooks |

## See Also

- `../07-mcp/mcp-overview.md` - MCP configuration details
- Official MCP Documentation: https://modelcontextprotocol.io/
