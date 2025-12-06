---
description: Research a topic and store findings in project memory
allowed-tools: Read, Write, WebSearch, WebFetch, Grep, Glob, Task
argument-hint: <topic>
---

# Research

Research existing solutions for a specific topic.

## Usage

```
/drupal-dev-framework:research <topic>
```

## What This Does

1. Invokes `contrib-researcher` agent for drupal.org/contrib search
2. Invokes `core-pattern-finder` skill for core examples
3. Stores findings in `architecture/research_{topic}.md`
4. Updates `project_state.md` with research summary

## Examples

```
/drupal-dev-framework:research workflow automation
/drupal-dev-framework:research content moderation
/drupal-dev-framework:research custom field types
/drupal-dev-framework:research entity references
```

## Output

Creates `{project_path}/architecture/research_{topic}.md`:

```markdown
# Research: {topic}

## Problem Statement
What we're trying to solve.

## Contrib Modules Found
| Module | Maintainers | Usage | Fit |
|--------|-------------|-------|-----|

## Core Patterns Found
| Pattern | Location | Applicability |
|---------|----------|---------------|

## Recommendation
Use / Extend / Build from scratch

## Key Patterns to Apply
- Pattern 1
- Pattern 2
```

## Phase

This is a **Phase 1** command. Use during Research phase.

## Next Steps

After research is complete:
1. Review findings
2. Make decision on approach
3. Move to Phase 2: `/drupal-dev-framework:design`
