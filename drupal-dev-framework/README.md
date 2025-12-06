# Drupal Development Framework

A Claude Code plugin implementing a systematic 3-phase Drupal development workflow with human control at every step.

## Installation

```bash
# Add marketplace (if not already added)
/plugin marketplace add https://github.com/camoa/claude-skills

# Install the plugin
/plugin install drupal-dev-framework@camoa-skills
```

## Overview

This plugin automates the Drupal Development Guide v3.0 workflow:

| Phase | Focus | Code? |
|-------|-------|-------|
| **Phase 1: Research** | Understand requirements, study existing solutions | No |
| **Phase 2: Architecture** | Design components, choose patterns | No |
| **Phase 3: Implementation** | Interactive development with TDD | Yes (with approval) |

## Design Principles

1. **AI prepares, Human decides** - Agents gather information and present options
2. **Interactive implementation** - AI writes code piece-by-piece with developer approval
3. **Memory-driven continuity** - Project state persists across sessions
4. **Integration over reinvention** - Leverages superpowers, drupal-dev-tools

## Commands

| Command | Description |
|---------|-------------|
| `/drupal-dev-framework:new` | Start new project with memory structure |
| `/drupal-dev-framework:research <topic>` | Research a topic, store findings |
| `/drupal-dev-framework:design [component]` | Design architecture or component |
| `/drupal-dev-framework:pattern <use-case>` | Get pattern recommendations |
| `/drupal-dev-framework:implement <task>` | Load context, start implementing |
| `/drupal-dev-framework:status` | Show current project state and phase |
| `/drupal-dev-framework:next` | Suggest next action based on state |
| `/drupal-dev-framework:complete` | Mark task done, update memory |
| `/drupal-dev-framework:validate` | Validate against architecture/standards |

## Components

### Agents (5)
- `contrib-researcher` - Searches drupal.org, analyzes contrib modules
- `architecture-drafter` - Creates architecture documents
- `pattern-recommender` - Recommends Drupal patterns for use cases
- `architecture-validator` - Validates implementation against architecture
- `project-orchestrator` - Coordinates project state and workflow

### Skills (15)
- Phase 1: `project-initializer`, `requirements-gatherer`, `core-pattern-finder`
- Phase 2: `component-designer`, `diagram-generator`, `guide-integrator`
- Phase 3: `task-context-loader`, `implementation-task-creator`, `tdd-companion`, `task-completer`, `code-pattern-checker`
- Cross-Phase: `memory-manager`, `phase-detector`, `guide-loader`, `session-resume`

## Memory Structure

Projects are stored in `~/workspace/claude_memory/project_name/`:

```
project_name/
├── project_state.md           # Current status, phase, decisions
├── architecture/
│   ├── main.md               # High-level architecture
│   └── component_name.md     # Component-specific designs
└── implementation_process/
    ├── in_progress/          # Current tasks
    └── completed/            # Finished tasks
```

## Integration

Works with:
- `superpowers:brainstorming` - Design discussions
- `superpowers:test-driven-development` - TDD enforcement
- `superpowers:verification-before-completion` - Final checks
- `drupal-dev-tools:drupal` - Drupal audits, DDEV operations

## License

MIT
