---
description: Get pattern recommendations for a use case
allowed-tools: Read, Glob, Grep, Task
argument-hint: <use-case>
---

# Pattern

Get Drupal pattern recommendations for a specific use case.

## Usage

```
/drupal-dev-framework:pattern <use-case>
```

## What This Does

1. Invokes `pattern-recommender` agent
2. Analyzes the use case
3. Compares available patterns
4. Provides recommendation with core/contrib references

## Common Use Cases

### Forms
```
/drupal-dev-framework:pattern module settings form
/drupal-dev-framework:pattern data entry form
/drupal-dev-framework:pattern confirmation dialog
/drupal-dev-framework:pattern multi-step wizard
```

### Data Storage
```
/drupal-dev-framework:pattern user-generated content
/drupal-dev-framework:pattern module configuration
/drupal-dev-framework:pattern high-volume logging
/drupal-dev-framework:pattern exportable bundles
```

### Extensibility
```
/drupal-dev-framework:pattern swappable implementations
/drupal-dev-framework:pattern third-party integration points
/drupal-dev-framework:pattern event-driven behavior
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
