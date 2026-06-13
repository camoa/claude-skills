# DRY Patterns for Drupal

Don't Repeat Yourself principles enforced during Phase 3 implementation.

## The Rule

Every piece of knowledge has a single, unambiguous representation.

## Extraction Patterns

| Pattern | When to Use | Example |
|---------|-------------|---------|
| **Service** | Same logic in 2+ places | Business logic, calculations |
| **Trait** | Same methods in multiple classes | Shared behaviors, logging |
| **Base Class** | Same structure across classes | Form bases, entity bases |
| **Twig Component** | Same markup in templates | Cards, buttons, alerts |
| **Config** | Same values used everywhere | Settings, defaults |

## Service Extraction

When same logic appears in 2+ places:

```
1. Create service in src/
2. Define interface
3. Register in services.yml
4. Inject where needed
```

**Result**: Single source of truth, testable, maintainable.

## Trait Usage

When same methods needed in multiple classes:

```
1. Create trait in src/
2. Add shared methods
3. Use in classes that need it
4. Override only when necessary
```

**Caution**: Don't overuse. Prefer composition over traits.

## Base Class Leverage

Use existing Drupal base classes:

| Need | Base Class |
|------|------------|
| Settings form | `ConfigFormBase` |
| Entity list | `EntityListBuilder` |
| Custom form | `FormBase` |
| Block plugin | `BlockBase` |
| Field formatter | `FormatterBase` |

**Rule**: Only use `FormBase` when `ConfigFormBase` doesn't fit.

## Twig Component Patterns

When same markup repeats:

```
1. Create component in templates/components/
2. Define clear interface (variables)
3. Include where needed
4. Use SDC for encapsulation
```

## Config Sharing

Default values and settings:

```
1. Define in config/install/
2. Create schema in config/schema/
3. Load via ConfigFactory
4. Override via config management
```

## Detection During Implementation

Red flags for DRY violations:

| Sign | Action |
|------|--------|
| Copy-pasting code | Extract to service or trait |
| Same validation in multiple forms | Create shared validator service |
| Identical queries in services | Create repository/query service |
| Repeated markup | Create Twig component |
| Magic numbers/strings | Move to config or constants |

## Enforcement Checkpoints

During `/implement`:

1. **Before writing**: "Does this logic exist elsewhere?"
2. **After writing**: "Is this duplicating something?"
3. **During review**: Check for copy-paste patterns
4. **Before complete**: Scan for repeated code blocks

## Common Violations

| Violation | Example | Fix |
|-----------|---------|-----|
| Copy-paste logic | Same 10 lines in 3 controllers | Extract to service |
| Duplicate validation | Same rules in 2 forms | Create validator service |
| Repeated queries | Same entity query everywhere | Create repository service |
| Hardcoded strings | Same message in 5 places | Use constants or config |
