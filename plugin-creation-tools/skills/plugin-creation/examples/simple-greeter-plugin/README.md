# Simple Greeter Plugin

A minimal example plugin demonstrating the basic plugin structure with one skill.

## Structure

```
simple-greeter-plugin/
├── .claude-plugin/
│   ├── plugin.json        # Plugin manifest (required)
│   └── marketplace.json   # For local testing
├── skills/
│   └── greeter/
│       └── SKILL.md       # The skill
└── README.md
```

## Installation (Local Testing)

```bash
# Add the plugin as a local marketplace
/plugin marketplace add /path/to/simple-greeter-plugin

# Install the plugin
/plugin install simple-greeter@greeter-dev

# Restart Claude Code
```

## Usage

Just say hello:
- "Hi!"
- "Good morning"
- "Hello there"

The greeter skill will trigger and provide a friendly response.

## What This Example Shows

1. **Minimal structure** - Only required files
2. **plugin.json** - Basic manifest with name, version, description
3. **marketplace.json** - For local development testing
4. **SKILL.md** - Simple skill with clear triggers

## Customization Ideas

- Add time-based greeting logic
- Include user's name if known
- Add seasonal greetings
- Support multiple languages
