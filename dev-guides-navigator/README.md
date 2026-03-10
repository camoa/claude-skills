# Dev Guides Navigator

Brief description of what this plugin does.

## Installation

```bash
/plugin marketplace add path/to/marketplace
/plugin install dev-guides-navigator@marketplace-name
```

## Components

- **Skill**: `dev-guides-navigator`

## Usage

[How to use this plugin]

## Configuration

[Any configuration options]

## Output

If hooks are enabled, outputs are written to `claude-outputs/`:

```
claude-outputs/
├── logs/        # Session and operation logs
├── artifacts/   # Generated files
└── temp/        # Temporary files (cleaned on session end)
```

Add to `.gitignore`:
```
claude-outputs/
.claude/settings.local.json
```
