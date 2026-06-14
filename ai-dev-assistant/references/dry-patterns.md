# DRY Patterns

Don't Repeat Yourself principles enforced during Phase 3 implementation. The extraction patterns are stack-neutral. The base classes, file layout, and APIs for a given stack live in the phase recipes (implement standards-and-tests recipe), which reference the dev-guides knowledge guides.

## The Rule

Every piece of knowledge has a single, unambiguous representation.

## Extraction Patterns

| Pattern | When to Use | Example |
|---------|-------------|---------|
| **Service / module** | Same logic in 2+ places | Business logic, calculations |
| **Mixin / trait** | Same methods in multiple units | Shared behaviors, logging |
| **Base class** | Same structure across units | Shared lifecycle, common scaffolding |
| **Shared component** | Same markup in templates | Cards, buttons, alerts |
| **Config / constants** | Same values used everywhere | Settings, defaults |

## Logic Extraction

When the same logic appears in 2+ places:

```
1. Create a logic unit (service or module)
2. Define its interface
3. Register or import it where needed
4. Depend on it instead of duplicating
```

**Result**: Single source of truth, testable, maintainable.

## Shared-Behavior Extraction

When the same methods are needed in multiple units:

```
1. Create a mixin or trait
2. Add the shared methods
3. Use it in the units that need it
4. Override only when necessary
```

**Caution**: Don't overuse. Prefer composition over inheritance.

## Base Class Leverage

When several units share the same structure, lift the common scaffolding into a shared base class and have each unit extend it. Reach for the most specific base that already fits before writing a more generic one.

## Shared Component Patterns

When the same markup repeats:

```
1. Create a reusable component
2. Define a clear interface (its variables)
3. Include it where needed
4. Encapsulate so callers only pass data
```

## Config Sharing

Default values and settings:

```
1. Define the values in one place (config or constants)
2. Give them a schema or type where the platform supports it
3. Load them through a single accessor
4. Override through the platform's config mechanism
```

## Detection During Implementation

Red flags for DRY violations:

| Sign | Action |
|------|--------|
| Copy-pasting code | Extract to a logic unit or mixin |
| Same validation in multiple places | Create a shared validator |
| Identical queries in multiple units | Create a repository or query unit |
| Repeated markup | Create a shared component |
| Magic numbers or strings | Move to config or constants |

## Enforcement Checkpoints

During `/implement`:

1. **Before writing**: "Does this logic exist elsewhere?"
2. **After writing**: "Is this duplicating something?"
3. **During review**: Check for copy-paste patterns
4. **Before complete**: Scan for repeated code blocks

## Common Violations

| Violation | Example | Fix |
|-----------|---------|-----|
| Copy-paste logic | Same 10 lines in 3 places | Extract to a logic unit |
| Duplicate validation | Same rules in 2 forms | Create a shared validator |
| Repeated queries | Same query everywhere | Create a repository unit |
| Hardcoded strings | Same message in 5 places | Use constants or config |
