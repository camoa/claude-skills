# What Are Commands (Slash Commands)?

Commands are custom slash commands that integrate with Claude Code's command system. They are **user-invoked** via `/command-name` and appear in the `/help` listing.

## Key Characteristics

- User-invoked via `/command-name`
- Support arguments and bash execution
- Can reference files with `@` prefix
- Appear in `/help` listing
- Discoverable in slash command menu
- Single markdown file per command

## When to Use Commands

**Good Use Cases**:
- Quick, frequently used prompts
- One-off automation
- Explicit workflows the user should trigger
- Simple templates and reminders
- Tasks that need user control over when they run

**Examples**:
- `/review-pr` - Review current PR
- `/deploy` - Deploy to staging
- `/fix-issue 123` - Fix specific issue
- `/summarize @file.md` - Summarize a file

## Commands vs Other Components

| Aspect | Commands | Skills | Agents |
|--------|----------|--------|--------|
| Invocation | User (`/command`) | Model-invoked | Auto + Manual |
| Files | Single .md | Directory + SKILL.md | Single .md |
| Discovery | `/help` | Automatic | `/agents` |
| Best For | Quick prompts | Complex workflows | Task expertise |

## File Location

```
plugin-name/
└── commands/
    ├── review.md
    ├── deploy.md
    └── frontend/        # Namespace: /frontend:component
        └── component.md
```

## Basic Format

```markdown
---
description: What this command does and when to use it
allowed-tools: Read, Edit, Bash
argument-hint: [file] [options]
---

# Command Title

Instructions for Claude when this command is invoked.

Use $1 for first argument, $2 for second, $ARGUMENTS for all.
```

## Key Features

1. **Arguments**: `$1`, `$2`, `$ARGUMENTS`
2. **Bash execution**: `!git status` runs bash inline
3. **File references**: `@src/file.js` includes file content
4. **Namespacing**: Subdirectories create namespaced commands

## The 5-10 Rule

Use commands when:
- Task is done 5+ times
- Will be done 10+ more times
- User should control when it runs

## See Also

- `../04-commands/writing-commands.md` - how to write commands
- `../04-commands/command-patterns.md` - advanced patterns
- `../04-commands/command-arguments.md` - argument handling
