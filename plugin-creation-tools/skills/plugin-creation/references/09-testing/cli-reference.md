# CLI Reference

Complete reference for plugin-related CLI commands.

## Plugin Management

### Marketplace Commands

```bash
# List all configured marketplaces
/plugin marketplace list

# Add marketplace from GitHub
/plugin marketplace add owner/repo

# Add marketplace from Git URL
/plugin marketplace add https://gitlab.com/company/plugins.git

# Add local marketplace (for development)
/plugin marketplace add ./my-marketplace

# Update marketplace metadata (refresh plugins list)
/plugin marketplace update marketplace-name

# Remove a marketplace
/plugin marketplace remove marketplace-name
```

### Plugin Commands

```bash
# Browse available plugins (interactive)
/plugin

# Install a plugin
/plugin install plugin-name@marketplace-name

# Enable a disabled plugin
/plugin enable plugin-name@marketplace-name

# Disable plugin (without uninstalling)
/plugin disable plugin-name@marketplace-name

# Uninstall a plugin
/plugin uninstall plugin-name@marketplace-name

# Get plugin details
/plugin info plugin-name@marketplace-name
```

## Command Line Flags

### Plugin Directory Loading

```bash
# Load plugins from specific directory
claude --plugin-dir ./my-plugins

# Load from multiple directories
claude --plugin-dir ./plugins1 --plugin-dir ./plugins2
```

### Validation

```bash
# Validate plugin structure in current directory
claude plugin validate .

# Check if commands exist
claude plugin validate --check-commands

# Strict validation of all plugin.json files
claude plugin validate --strict
```

### Debug Mode

```bash
# Enable full debug output
claude --debug

# Debug specific categories
claude --debug "plugins,hooks"

# Exclude categories (! prefix)
claude --debug "!statsig,!file"
```

### Other Flags

```bash
# Run in plan mode (read-only)
claude --permission-mode plan

# Override settings for session
claude --settings ./custom-settings.json

# Start with specific agent config
claude --agents '{"reviewer": {"description": "Code reviewer"}}'

# Run plugin doctor (health check)
claude doctor
```

## In-Session Commands

### Plugin Info

```bash
# View all plugins
/plugin

# List commands
/help

# List agents
/agents

# View hooks
/hooks

# View MCP servers
/mcp
```

### Debug Tools

```bash
# Toggle verbose mode
Ctrl+O

# Check overall health
claude doctor
```

## Common Workflows

### Install Plugin from GitHub

```bash
# 1. Add marketplace
/plugin marketplace add owner/repo

# 2. Browse plugins
/plugin

# 3. Install specific plugin
/plugin install plugin-name@marketplace-name
```

### Local Development Testing

```bash
# 1. Add local marketplace
/plugin marketplace add ./path/to/dev-marketplace

# 2. Install plugin
/plugin install my-plugin@dev-marketplace

# 3. Test components
/help                    # Check commands
/agents                  # Check agents
claude --debug           # Check loading

# 4. After changes, reinstall
/plugin uninstall my-plugin@dev-marketplace
/plugin install my-plugin@dev-marketplace
```

### Debug Plugin Loading

```bash
# 1. Start with debug
claude --debug "plugins"

# 2. Check for errors in output
# Look for: "Loading plugin", "Failed to load", "Invalid"

# 3. Run doctor for health check
claude doctor
```

## Environment Variables

These are available during plugin execution:

| Variable | Description |
|----------|-------------|
| `CLAUDE_PLUGIN_ROOT` | Plugin installation directory |
| `CLAUDE_PROJECT_DIR` | Current project root |
| `CLAUDE_ENV_FILE` | Session env file (SessionStart) |
| `CLAUDE_CONFIG_DIR` | Claude config directory |

## Quick Reference

| Task | Command |
|------|---------|
| Add marketplace | `/plugin marketplace add owner/repo` |
| Install plugin | `/plugin install name@marketplace` |
| List commands | `/help` |
| List agents | `/agents` |
| Debug loading | `claude --debug "plugins"` |
| Validate plugin | `claude plugin validate .` |
| Health check | `claude doctor` |
