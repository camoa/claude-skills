# Reference, Don't Reproduce

The most important principle for creating maintainable, efficient skills.

## The Core Principle

Instead of copying code into your skill, **reference where the code lives**:

| Don't Do This | Do This Instead |
|---------------|-----------------|
| Copy 50-line implementation into SKILL.md | "See `src/module/handler.py:245`" |
| Reproduce entire API documentation | "See [API Docs](https://docs.example.com) for full details" |
| Include full configuration examples | "Reference `config/` in the module for patterns" |

## Why Reference?

1. **Maintenance**: Source code changes; copied code becomes stale
2. **Context efficiency**: File paths use fewer tokens than implementations
3. **Authority**: Claude can read the actual source for accuracy
4. **DRY**: Single source of truth prevents drift

## Code Example Strategy

Before writing any code example, ask: **"Can I reference existing code instead?"**

| Situation | Action |
|-----------|--------|
| Pattern exists in codebase | Reference the file path |
| Official docs have examples | Link to docs |
| Pattern needs illustration | Brief snippet (5-15 lines) + file reference |
| No existing example exists | Create minimal, tested example |
| Full implementation needed | Put in `scripts/`, reference from SKILL.md |

## What TO Include

Brief snippet showing the pattern, with reference to full implementation:

```markdown
## Form Handling Pattern

Base class: `core/lib/Drupal/Core/Form/FormBase.php`

Key methods to implement:
- `getFormId()` - unique identifier
- `buildForm()` - form structure
- `submitForm()` - submission handler

For config forms, extend `ConfigFormBase` instead.
See: `core/modules/system/src/Form/SiteInformationForm.php` for a complete example.
```

## What NOT to Include

Full reproductions that will become stale:

```markdown
## Form Handling Pattern

<?php
namespace Drupal\my_module\Form;

use Drupal\Core\Form\FormBase;
use Drupal\Core\Form\FormStateInterface;

class MyForm extends FormBase {
  public function getFormId() {
    return 'my_form';
  }

  public function buildForm(array $form, FormStateInterface $form_state) {
    $form['name'] = [
      '#type' => 'textfield',
      '#title' => $this->t('Name'),
      '#required' => TRUE,
    ];
    // ... 40 more lines ...
  }
  // ... etc
}
```

**Problem**: This will drift from actual patterns, wastes tokens, and Claude can read the real file anyway.

## Reference Format Standards

### For Code Files
```
path/to/file.py:line_number
src/module/handler.py:245
core/modules/{module}/src/{path}.php
```

### For Documentation
```
See [Topic Name](https://docs.example.com/path) for {what they'll find there}
```

### For Configuration
```
Reference: config/install/{module}.settings.yml
Pattern location: modules/contrib/{module}/config/schema/
```

### For Scripts in This Skill
```
Run: python scripts/helper.py --flag value
See: scripts/helper.py for implementation details
```

## Code Example Excellence Standards

When you DO need to include code:

1. **One excellent example beats many mediocre ones**
2. **Brief snippets only** - 5-15 lines for pattern recognition
3. **Well-commented** - explain WHY, not just what
4. **Include file path** - point to full implementation
5. **Choose most relevant language** - one language, not multi-language

### Good Example Format

```markdown
## Entity Query Pattern

Brief pattern for loading entities by field value:

```python
# Query for published articles
results = db.query(Entity)
    .filter(Entity.type == 'article')
    .filter(Entity.status == 'published')
    .all()
```

Full examples: `src/repositories/entity_repo.py:89`
See: [ORM documentation](https://docs.example.com/orm) for query options
```

## What NOT to Do

- **Multi-language implementations** - example-js.js, example-py.py (pick one)
- **Fill-in-the-blank templates** - with placeholder comments
- **Contrived scenarios** - that don't reflect real usage
- **Examples over 50 lines** - move to `scripts/` instead
- **Copying code that exists** - in codebase or official docs

## Summary

The reference-first approach:
1. Always ask "Can I reference instead?"
2. If code exists, point to it
3. If example needed, keep it brief (5-15 lines)
4. Always include path to full implementation
5. One excellent example, not many mediocre ones
