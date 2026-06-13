---
description: "Get pattern recommendations for a use case. Trigger: 'recommend pattern', 'which approach', 'Drupal pattern for', 'how should I implement'."
allowed-tools: Read, Glob, Grep, Task
argument-hint: <use-case>
---

# Pattern

Get pattern recommendations for a specific use case (Drupal-flavored today: FormBase vs ListBuilder, Entity vs Config, etc.).

## Usage

```
/ai-dev-assistant:pattern <use-case>
```

## What This Does

1. Invokes `pattern-recommender` agent
2. Analyzes the use case
3. Compares available patterns
4. Provides recommendation with core/contrib references

## Common Use Cases

### Forms
```
/ai-dev-assistant:pattern module settings form
/ai-dev-assistant:pattern data entry form
/ai-dev-assistant:pattern confirmation dialog
/ai-dev-assistant:pattern multi-step wizard
```

### Data Storage
```
/ai-dev-assistant:pattern user-generated content
/ai-dev-assistant:pattern module configuration
/ai-dev-assistant:pattern high-volume logging
/ai-dev-assistant:pattern exportable bundles
```

### Extensibility
```
/ai-dev-assistant:pattern swappable implementations
/ai-dev-assistant:pattern third-party integration points
/ai-dev-assistant:pattern event-driven behavior
```

## Output Format

```markdown
## Pattern Recommendation: {use-case}

### Requirements Understood
- Requirement 1
- Requirement 2

### Options Considered
1. **Option A**: Description
   - Pros: ...
   - Cons: ...

2. **Option B**: Description
   - Pros: ...
   - Cons: ...

### Recommendation
**{Pattern}** because {reasoning}

### Reference Implementation
`core/modules/.../src/...`

### Key Code to Study
- Method X: Does Y
- Class Z: Implements W
```

## Phase

This is a **Phase 2** command. Use during Architecture phase.

## Integration

Pattern recommendations are added to architecture files for reference during implementation.
