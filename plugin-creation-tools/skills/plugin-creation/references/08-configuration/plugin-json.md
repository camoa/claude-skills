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
  "$schema": "https://json.schemastore.org/claude-code-plugin-manifest.json",
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
  "lspServers": "./.lsp.json",
  "experimental": {
    "themes": "./themes/",
    "monitors": "./monitors.json"
  }
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
| `$schema` | string | JSON Schema URL for editor autocomplete and validation (e.g., `"https://json.schemastore.org/claude-code-plugin-manifest.json"`). Ignored by Claude Code at load time — purely a developer-ergonomics hint. |
| version | string | Semantic version (e.g., "2.1.0") |
| description | string | Brief explanation of plugin purpose |
| `displayName` | string | **v2.1.143+** Human-readable name shown in the `/plugin` picker and other UI surfaces. Falls back to `name` when omitted. Unlike `name`, may contain spaces and any casing. Not used for namespacing or lookup. |
| author | object/string | Author information |
| homepage | string | Documentation URL |
| repository | string | Source code URL |
| license | string | SPDX identifier (`MIT`, `Apache-2.0`, `BSD-3-Clause`, `GPL-3.0-or-later`, etc.). Use `"proprietary"` only when the repository is private and the value reflects company policy. The validator surfaces non-SPDX values as info-level so you can confirm intent. |
| keywords | array | Discovery tags. Keep to ≤ 25 entries — marketplace UIs truncate longer lists and the budget pressure isn't worth squeezing in another niche tag. |
| `defaultEnabled` | boolean | **v2.1.154+** Whether the plugin is enabled when the user hasn't set a state. Defaults to `true`. Set `false` to install disabled — the user opts in with `claude plugin enable <plugin>` or `/plugin`. Use for plugins that add cost or scope (e.g. one that connects to an external service). Earlier Claude Code versions ignore the field and enable on install. Precedence: a user's `enabledPlugins` setting and a dependency requirement both override it. A marketplace entry's `defaultEnabled` also overrides this one. |

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
| commands | array | Custom command file paths. The historical string form is being phased out — use an array, even for a single file (`["./custom/cmd.md"]`). |
| agents | array | Custom agent file paths. Array-only — the string-path form no longer loads as of the current schema. |
| skills | string/array | Custom skill directory paths (replaces default `skills/`) |
| hooks | string/object | Hook config path or inline config |
| mcpServers | string/object | MCP config path or inline config |
| lspServers | string/object | LSP config path or inline config |
| outputStyles | string/array | Custom output style paths |
| `experimental.themes` | string/array | Color theme files/directories (replaces default `themes/`). Each file: `name`, `base`, `overrides`. See [`themes.md`](themes.md). **Was top-level `themes`** — see [Experimental components migration](#experimental-components-migration). |
| `experimental.monitors` | string/array | Background [Monitor](https://docs.anthropic.com/en/tools-reference#monitor-tool) configurations that start automatically when the plugin is active. **Was top-level `monitors`** — see [Experimental components migration](#experimental-components-migration). |
| `channels` | array | Channel declarations for message injection (Telegram, Slack, Discord style). Each channel binds to an MCP server the plugin provides. See [Channels](#channels) below. |
| userConfig | object | User-configurable values prompted at enable time. See [User configuration](#user-configuration) below. |
| settings | string | Path to settings.json. Supported keys: `agent` (activates one of the plugin's agents as the main thread agent), `subagentStatusLine` (default status-line config for spawned subagents — see [`settings.md`](settings.md#subagentstatusline)). Unknown keys are silently ignored (forward-compatible). |

### Experimental components migration

`themes` and `monitors` belong under the `experimental` key. Their *manifest schema* is still stabilizing, but the *location migration* is independent and already underway:

- Top-level `themes` / `monitors` still load.
- `claude plugin validate` warns when they appear at the top level.
- A future release will require them under `experimental.*`.

Migrate now to silence the warning:

```diff
- "themes": "./themes/",
- "monitors": "./monitors.json"
+ "experimental": {
+   "themes": "./themes/",
+   "monitors": "./monitors.json"
+ }
```

`/plugin-creation-tools:validate` mirrors the upstream warning and offers an auto-migration diff.

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

1. **Custom paths REPLACE the default for most fields — only `skills` adds.**

   Whether a custom path replaces or extends the plugin's default directory depends on the field. This is the rule that surprises the most plugin authors, so memorize it:

   | Behavior | Fields |
   |---|---|
   | **Replaces the default** — the default folder is no longer scanned | `commands`, `agents`, `outputStyles`, `experimental.themes`, `experimental.monitors` |
   | **Adds to the default** — the default folder is always scanned, and listed paths are loaded alongside it | `skills` |
   | **Own merge rules** — see each section below | `hooks`, `mcpServers`, `lspServers` |

   For "Replaces the default" fields, to keep the default AND add more, list it explicitly:

   ```json
   { "commands": ["./commands/", "./extras/"] }
   ```

   **v2.1.140+ surfaces ignored defaults in tooling**: when a plugin sets a custom path for a "Replaces the default" field AND the matching default folder still exists with files, Claude Code flags the ignored folder in `/doctor`, `claude plugin list`, and the `/plugin` detail view. The plugin still loads using the manifest paths — the default folder's files are simply not scanned. No warning fires when the manifest key points **into** the default folder (e.g. `"commands": ["./commands/deploy.md"]`), because the folder is addressed explicitly.

2. **All paths relative to plugin root**
   - Must start with `./`
   - Example: `./commands/deploy.md`

3. **Use forward slashes**
   - Works across all platforms
   - Example: `./path/to/file.md`

4. **Single-skill-at-root auto-discovery (v2.1.142+)**

   A plugin with **all three** of:

   - `SKILL.md` at the plugin root
   - no `skills/` subdirectory
   - no `skills` field in `plugin.json`

   is **automatically** loaded as a single-skill plugin. You do **not** need `"skills": ["./"]` for this layout. The skill's invocation name comes from the frontmatter `name` field, with the directory basename as a fallback.

   This is the minimum-overhead shape for plugins that ship exactly one skill and nothing else. Use it when:

   - The plugin is a single skill — no commands, no agents, no hooks.
   - You want users to discover the skill by the plugin name without an extra subdirectory hop.
   - You don't anticipate adding more skills (if you do, migrate later to `skills/<name>/SKILL.md`).

   Adding a manifest `skills` field on top of the root-`SKILL.md` layout is redundant; the validator flags it as info-level noise.

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

## Channels

The `channels` field lets a plugin declare one or more **message channels** that inject content into the conversation (Telegram, Slack, Discord-style integrations). Each channel binds to an MCP server that the plugin also provides.

```json
{
  "channels": [
    {
      "server": "telegram",
      "userConfig": {
        "bot_token": {
          "type": "string",
          "title": "Bot token",
          "description": "Telegram bot token",
          "sensitive": true
        },
        "owner_id": {
          "type": "string",
          "title": "Owner ID",
          "description": "Your Telegram user ID"
        }
      }
    }
  ]
}
```

### Per-entry fields

| Field | Required | Description |
|-------|----------|-------------|
| `server` | Yes | Must match a key in the plugin's `mcpServers`. The channel binds to that server. |
| `userConfig` | No | Same schema as the top-level `userConfig` field — prompts the user for per-channel values (bot tokens, owner IDs) when the plugin is enabled. |

Channels is a niche but documented manifest field. If your plugin doesn't ship a message-injection MCP server, omit the field entirely.

## `bin/` Directory (executables on Bash PATH)

A `bin/` directory at the plugin root is a standard plugin component — **not** a manifest field. Files placed in `bin/` are added to the Bash tool's `PATH` while the plugin is enabled, so they're invokable as bare commands in any Bash tool call:

```
plugin-name/
├── .claude-plugin/
│   └── plugin.json
└── bin/
    ├── my-tool          # invokable as `my-tool` in Bash
    └── my-other-tool
```

- Files must be **executable** (`chmod +x`).
- Use cross-platform shebangs (`#!/usr/bin/env bash`, `#!/usr/bin/env python3`) or pair with a `.cmd` wrapper like the hooks polyglot pattern (`templates/hooks/run-hook.cmd.template`).
- Prefer this over `hooks` for utilities the *user* (or another plugin's hook) calls directly, rather than event-driven automation.
- Auto-discovered — no manifest entry needed.

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
| `subagentStatusLine` | object/string | Default status-line configuration for subagents spawned from this plugin. Same shape as the user-level `subagentStatusLine` setting. See [`settings.md`](settings.md#subagentstatusline). |

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
