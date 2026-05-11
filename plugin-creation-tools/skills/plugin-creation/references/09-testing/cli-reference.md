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

# Aliases for uninstall
/plugin remove plugin-name@marketplace-name
/plugin rm plugin-name@marketplace-name

# Uninstall but keep persistent data (${CLAUDE_PLUGIN_DATA})
/plugin uninstall plugin-name@marketplace-name --keep-data

# Uninstall a plugin AND remove auto-installed dependencies no other plugin needs
/plugin uninstall plugin-name@marketplace-name --prune
# Or, in one step from the CLI:
claude plugin uninstall plugin-name@marketplace-name --prune --yes

# Get plugin details
/plugin info plugin-name@marketplace-name

# Update a plugin
/plugin update plugin-name@marketplace-name

# Update all plugins in a scope (including managed/org-deployed plugins)
/plugin update --scope managed
```

### Plugin Prune (`claude plugin prune`)

Remove auto-installed dependency plugins that no other installed plugin requires. Plugins you installed directly are never touched. Requires Claude Code v2.1.121+.

```bash
# Show what would be removed
claude plugin prune --dry-run

# Prune at user scope (default)
claude plugin prune

# Prune at project scope
claude plugin prune --scope project

# Non-interactive (CI/scripts) — required when stdin isn't a TTY
claude plugin prune --yes
```

**Aliases:** `autoremove`.

After any large set of plugin upgrades / uninstalls, run `claude plugin prune --dry-run` to see what's orphaned. The validator surfaces this as a reminder under its "after major changes" guidance.

### Plugin Release Tagging (`claude plugin tag`)

Create the `{plugin-name}--v{version}` git tag that dependency-version constraints resolve against. Run from inside the plugin's folder. Pinned dependents auto-update to the highest satisfying git tag.

```bash
# Create the tag from plugin.json's "version" field
claude plugin tag

# Create and push to the configured git remote
claude plugin tag --push

# Show what would be tagged without creating it
claude plugin tag --dry-run

# Tag anyway when the working tree is dirty or the tag exists
claude plugin tag --force
```

Replaces the manual `git tag {plugin-name}--v{version} && git push --tags` flow. See [`../08-configuration/marketplace-json.md`](../08-configuration/marketplace-json.md#3-tag-plugin-releases-claude-plugin-tag) for the full release-tagging workflow.

## Command Line Flags

### Plugin Directory Loading

```bash
# Load plugins from specific directory
claude --plugin-dir ./my-plugins

# Load from multiple directories
claude --plugin-dir ./plugins1 --plugin-dir ./plugins2

# Load a packaged plugin .zip from a URL for the current session only
# (useful for previewing a pre-release plugin without adding it to the marketplace
# or writing to ~/.claude/plugins)
claude --plugin-url https://example.com/my-plugin-v1.2.0.zip
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
| `CLAUDE_PLUGIN_DATA` | Persistent data directory (`~/.claude/plugins/data/{plugin-id}/`). Survives plugin updates. |
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
