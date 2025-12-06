---
name: component-designer
description: Use when designing a specific module component - creates architecture/component_name.md with purpose, interface, dependencies, and pattern references
version: 1.0.0
---

# Component Designer

Design individual components (services, forms, entities) for a Drupal module.

## Triggers

- User says "Design X component" or "Design the service"
- Breaking down architecture into implementable pieces
- Need detailed spec for a single component

## Process

1. **Identify component** - What type (service, form, entity, plugin)?
2. **Define purpose** - What does this component do?
3. **Specify interface** - Public methods, parameters, return types
4. **Map dependencies** - What services does it need?
5. **Reference patterns** - Point to core/contrib examples
6. **Document** - Create architecture/component_name.md

## Output Format

Create `~/workspace/claude_memory/{project}/architecture/{component_name}.md`:

```markdown
# Component: {ComponentName}

## Type
{Service | Form | Entity | Plugin | Controller}

## Purpose
{One paragraph explaining what this component does}

## Interface

### Public Methods
| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `methodName()` | `$param: Type` | `ReturnType` | What it does |

### Events Dispatched (if any)
| Event | When |
|-------|------|
| `event.name` | Condition |

## Dependencies

### Required Services
| Service | Purpose |
|---------|---------|
| `entity_type.manager` | Load entities |

### Configuration
| Config Key | Purpose |
|------------|---------|
| `my_module.settings` | Module settings |

## Pattern Reference
Based on: `core/modules/.../src/...`

Key similarities:
- {similarity 1}
- {similarity 2}

Differences for our use case:
- {difference 1}

## Implementation Notes
{Any specific considerations for implementation}

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2
```

## Component Types

### Service
- Define interface and methods
- Specify dependency injection
- Reference service definition (services.yml)

### Form
- Form type (ConfigFormBase, FormBase, etc.)
- Form elements needed
- Validation requirements
- Submit behavior

### Entity
- Entity type (content, config)
- Fields and properties
- Base table structure
- Access control

### Plugin
- Plugin type
- Annotation/attribute requirements
- Base class to extend

## Human Control Points

- User specifies which component to design
- User reviews interface definition
- User approves before implementation
