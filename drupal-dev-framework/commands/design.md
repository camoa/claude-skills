---
description: Design architecture or a specific component
allowed-tools: Read, Write, Glob, Grep, Task
argument-hint: [component-name]
---

# Design

Design project architecture or a specific component.

## Usage

```
/drupal-dev-framework:design              # Design overall architecture
/drupal-dev-framework:design service      # Design specific component
/drupal-dev-framework:design form         # Design specific component
```

## What This Does

### Without Arguments (Overall Architecture)
1. Invokes `architecture-drafter` agent
2. Reviews research files
3. Creates/updates `architecture/main.md`
4. Asks clarifying questions
5. Invokes `guide-integrator` for relevant guides

### With Component Argument
1. Invokes `component-designer` skill
2. Creates `architecture/{component}.md`
3. References patterns from core/contrib
4. Defines interface and dependencies

## Output

### Overall Architecture (`architecture/main.md`)
```markdown
# {Project} Architecture

## Overview
## Components
## Data Flow
## Pattern References
## Implementation Order
```

### Component Design (`architecture/{component}.md`)
```markdown
# Component: {Name}

## Type
## Purpose
## Interface
## Dependencies
## Pattern Reference
## Acceptance Criteria
```

## Phase

This is a **Phase 2** command. Use after Research is complete.

## Related Commands

- `/drupal-dev-framework:pattern <use-case>` - Get pattern recommendations
- `/drupal-dev-framework:validate` - Validate design before implementation

## Next Steps

After architecture is complete:
1. Review all component designs
2. Validate with `/drupal-dev-framework:validate`
3. Move to Phase 3: `/drupal-dev-framework:implement <task>`
