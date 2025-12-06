---
name: core-pattern-finder
description: Use when needing Drupal core implementation examples - searches core modules for specific patterns and returns file path references
version: 1.0.0
---

# Core Pattern Finder

Find implementation examples in Drupal core for specific patterns.

## Triggers

- User asks "How does core do X?"
- User asks "Find core example of X"
- Need reference implementation for a pattern
- Researching Drupal best practices

## Common Patterns and Locations

### Forms
| Pattern | Example Location |
|---------|------------------|
| ConfigFormBase | `core/modules/system/src/Form/SiteInformationForm.php` |
| FormBase | `core/modules/node/src/Form/NodeForm.php` |
| ConfirmFormBase | `core/modules/node/src/Form/NodeDeleteForm.php` |
| EntityForm | `core/modules/user/src/ProfileForm.php` |

### Entities
| Pattern | Example Location |
|---------|------------------|
| Content Entity | `core/modules/node/src/Entity/Node.php` |
| Config Entity | `core/modules/field/src/Entity/FieldConfig.php` |
| Entity List Builder | `core/modules/node/src/NodeListBuilder.php` |

### Services
| Pattern | Example Location |
|---------|------------------|
| Entity Type Manager | `core/lib/Drupal/Core/Entity/EntityTypeManager.php` |
| Plugin Manager | `core/lib/Drupal/Core/Block/BlockManager.php` |
| Event Subscriber | `core/modules/system/src/EventSubscriber/ConfigCacheTag.php` |

### Plugins
| Pattern | Example Location |
|---------|------------------|
| Block Plugin | `core/modules/system/src/Plugin/Block/SystemBrandingBlock.php` |
| Field Formatter | `core/modules/text/src/Plugin/Field/FieldFormatter/TextDefaultFormatter.php` |
| Condition Plugin | `core/modules/system/src/Plugin/Condition/RequestPath.php` |

### Controllers
| Pattern | Example Location |
|---------|------------------|
| Controller | `core/modules/system/src/Controller/SystemController.php` |
| Entity Controller | `core/modules/node/src/Controller/NodeController.php` |

## Process

1. Identify the pattern needed
2. Search core for implementations
3. Return file paths with brief descriptions
4. Highlight key aspects of the implementation

## Output Format

```markdown
## Core Pattern: {Pattern Name}

### Primary Example
`core/modules/{module}/src/{path}.php`

Key aspects:
- {Aspect 1}
- {Aspect 2}

### Additional Examples
- `core/modules/{module2}/...` - {variation description}
- `core/modules/{module3}/...` - {variation description}

### Key Code Sections
Look at:
- Line X-Y: {what it demonstrates}
- Method `methodName()`: {purpose}
```

## Search Strategy

When pattern not in quick reference:
1. Use Grep to search for class names, interfaces
2. Use Glob to find files in expected locations
3. Read promising files to confirm pattern match
4. Return most relevant examples

## Human Control Points

- User specifies what pattern they need
- User chooses which example to study further
