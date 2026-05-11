# Plugin Themes

Plugins can ship color themes that appear in the user's `/theme` picker alongside built-in presets and the user's local themes. Each theme is a JSON file in `themes/` with a `base` preset and a sparse `overrides` map of color tokens.

## When to ship a theme

Ship a theme when the plugin has a visual identity that the user would notice in the terminal — brand-styled tooling, dark-mode-first plugins, accessibility-focused contrast presets, or plugins that visualize state through color (status, progress, severity). Skip themes for plugins that have no visual surface (silent hooks, MCP servers, code-quality checkers).

## File layout

```
plugin-name/
├── .claude-plugin/
│   └── plugin.json
└── themes/
    ├── default.json
    └── high-contrast.json
```

Default scan path is `themes/`. Override with `experimental.themes` in `plugin.json` (`string` or `array` of paths). When set, the default `themes/` directory is **not** scanned — your custom path replaces it.

> **Schema migration:** Themes are an [experimental component](plugin-json.md#experimental-components-migration). Declare the path under `experimental.themes`; top-level `themes` still loads but `claude plugin validate` warns and a future release will require the nested form.

## Theme schema

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Display name shown in `/theme`. |
| `base` | Yes | Built-in preset to inherit from. Common values: `dark`, `light`, `dark-daltonized`, `light-daltonized`. The base supplies every token; `overrides` only changes the ones you list. |
| `overrides` | Yes | Sparse map of color tokens (hex strings) that replace values from the `base` preset. Common tokens: `claude`, `error`, `success`, `warning`, `info`, `text`, `dim`, `border`. |

## Complete example

`themes/dracula.json`:

```json
{
  "name": "Dracula",
  "base": "dark",
  "overrides": {
    "claude": "#bd93f9",
    "error": "#ff5555",
    "success": "#50fa7b",
    "warning": "#f1fa8c",
    "info": "#8be9fd"
  }
}
```

This validates as JSON and is enough to appear in `/theme`. The base preset fills in every token you didn't override — you don't have to enumerate the full palette.

## How users select a plugin theme

When a plugin is enabled, its themes appear in `/theme` alongside the built-in and user-local themes. Selecting a plugin theme persists `custom:<plugin-name>:<slug>` in the user's config — `<slug>` derives from the theme's filename, so `themes/dracula.json` shipped by `my-brand` persists as `custom:my-brand:dracula`.

## User customization (read-only + Ctrl+E copy)

Plugin themes are **read-only** in the picker. To customize one, the user presses **`Ctrl+E`** while a plugin theme is selected — Claude Code copies it to `~/.claude/themes/<filename>` so the user can edit the copy without modifying the plugin's bundled file. Updates to the plugin do not overwrite the user's local copy. (See [`../01-overview/claude-directory.md`](../01-overview/claude-directory.md) for the full `~/.claude/` layout.)

## Plugin manifest entry

Themes are auto-discovered from `themes/`. Declare an explicit path only when you store them elsewhere:

```json
{
  "name": "my-brand",
  "experimental": {
    "themes": "./themes/"
  }
}
```

Or list specific files:

```json
{
  "experimental": {
    "themes": ["./themes/dark.json", "./themes/light.json"]
  }
}
```

## Validation

`/plugin-creation-tools:validate` checks each `themes/*.json` for valid JSON and the three required fields (`name`, `base`, `overrides`). Missing fields produce warnings; invalid JSON is an error.

## See also

- `plugin-json.md` — the `themes` component-path field
- `../01-overview/claude-directory.md` — where user-copied themes live
- Upstream: Plugins Reference → Themes section
