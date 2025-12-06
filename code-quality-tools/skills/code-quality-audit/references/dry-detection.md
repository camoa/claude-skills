# DRY Detection Reference

"Don't Repeat Yourself" principle detection and measurement.

## Core Philosophy

**DRY is about knowledge duplication, not code duplication.**

"Every piece of knowledge must have a single, unambiguous representation in a system."

**Important:** "Duplication is far cheaper than the wrong abstraction" - Sandi Metz

## Detection Tool: PHPCPD

**Package:** `systemsdk/phpcpd` (active fork)
**Note:** Original `sebastian/phpcpd` is abandoned.

### Installation

```bash
ddev composer require --dev systemsdk/phpcpd
```

### Basic Usage

```bash
# Default settings
ddev exec vendor/bin/phpcpd web/modules/custom

# Custom thresholds
ddev exec vendor/bin/phpcpd \
    --min-lines=10 \
    --min-tokens=70 \
    web/modules/custom

# Exclude directories
ddev exec vendor/bin/phpcpd \
    --exclude=tests \
    --exclude=vendor \
    web/modules/custom
```

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `--min-lines` | 5 | Minimum lines for a clone |
| `--min-tokens` | 70 | Minimum tokens for a clone |
| `--exclude` | - | Directories to skip |
| `--fuzzy` | - | Enable fuzzy matching |

### Output Format

```
Found 3 clones with 45 duplicated lines in 2 files:

  - web/modules/custom/my_module/src/Service/ServiceA.php:10-25 (15 lines)
    web/modules/custom/my_module/src/Service/ServiceB.php:30-45

  - web/modules/custom/my_module/src/Form/FormA.php:50-70 (20 lines)
    web/modules/custom/my_module/src/Form/FormB.php:100-120

2.5% duplicated lines out of 1800 total lines of code.
```

## Thresholds

| Duplication % | Rating | Action |
|---------------|--------|--------|
| <5% | Excellent | Maintain current practices |
| 5-10% | Acceptable | Monitor, no immediate action |
| 10-15% | Warning | Schedule refactoring |
| >15% | Critical | Immediate refactoring needed |

## Rule of Three

1. **First time:** Just write the code
2. **Second time:** Duplicate it (WET - Write Everything Twice)
3. **Third time:** Extract and refactor

**Why wait?** Premature abstraction creates wrong abstractions.

## When Duplication is OK

### Acceptable Duplication

- **Test setup code** - Tests should be independent
- **Similar but different** - Code that looks similar but has different reasons to change
- **Configuration** - Repeated config values that might diverge
- **Exploratory code** - Prototypes before patterns emerge

### Signs of Wrong Abstraction

If extracted code has:
- Many parameters
- Complex conditionals for different cases
- Comments explaining which case does what
- Frequent modifications

→ Inline it and duplicate instead.

## Refactoring Strategies

### Extract Trait (Shared Behavior)

```php
// Before: Duplicated in multiple classes
class ServiceA {
    public function logAction($action) {
        $this->logger->info('Action: ' . $action);
    }
}

class ServiceB {
    public function logAction($action) {
        $this->logger->info('Action: ' . $action);
    }
}

// After: Extract to trait
trait LogsActionsTrait {
    public function logAction(string $action): void {
        $this->logger->info('Action: ' . $action);
    }
}
```

### Extract Service (Shared Logic)

```php
// Before: Duplicated validation
class FormA {
    public function validate($data) {
        if (strlen($data['title']) < 3) { /* error */ }
        if (!filter_var($data['email'], FILTER_VALIDATE_EMAIL)) { /* error */ }
    }
}

// After: Extract to service
class ValidationService {
    public function validateTitle(string $title): bool { ... }
    public function validateEmail(string $email): bool { ... }
}
```

### Extract Base Class

```php
// Before: Similar form structure
class NodeEditForm extends FormBase { ... }
class UserEditForm extends FormBase { ... }

// After: Common base
abstract class EntityEditFormBase extends FormBase {
    abstract protected function getEntity();
    // Shared methods
}
```

## Drupal DRY Patterns

### Good: Reusable Form Elements

```php
// Define once
function my_module_get_title_element() {
    return [
        '#type' => 'textfield',
        '#title' => t('Title'),
        '#required' => TRUE,
        '#maxlength' => 255,
    ];
}

// Use everywhere
$form['title'] = my_module_get_title_element();
```

### Good: Configuration Schema Reuse

```yaml
# my_module.schema.yml
my_module.common_settings:
  type: mapping
  mapping:
    enabled:
      type: boolean
    timeout:
      type: integer

my_module.feature_a:
  type: my_module.common_settings

my_module.feature_b:
  type: my_module.common_settings
```

### Good: Plugin Base Classes

```php
// Base with shared functionality
abstract class ContentProcessorBase implements ContentProcessorInterface {
    protected function sanitize($content) { ... }
    protected function validate($content) { ... }
}

// Plugins extend base
class ArticleProcessor extends ContentProcessorBase { ... }
class PageProcessor extends ContentProcessorBase { ... }
```

## Anti-Patterns

### Over-Abstraction

```php
// BAD: Abstraction that's too generic
class GenericProcessor {
    public function process($type, $data, $options = []) {
        switch ($type) {
            case 'article': // 50 lines
            case 'page': // 50 different lines
            case 'user': // 50 more different lines
        }
    }
}

// BETTER: Three separate, clear classes
```

### Config-Driven Behavior

```php
// BAD: Duplication hidden in config
$handlers = [
    'article' => ArticleHandler::class,
    'page' => PageHandler::class,
];
// ...where ArticleHandler and PageHandler are 90% identical

// BETTER: One handler with type-specific behavior
```

## JSON Report Format

```json
{
  "duplication_percentage": 3.2,
  "total_lines": 5000,
  "duplicated_lines": 160,
  "clone_count": 5,
  "clones": [
    {
      "lines": 18,
      "tokens": 120,
      "files": [
        {"file": "src/Service/A.php", "start_line": 45, "end_line": 62},
        {"file": "src/Service/B.php", "start_line": 89, "end_line": 106}
      ]
    }
  ],
  "rating": "excellent",
  "status": "pass"
}
```

## Resources

- [Sandi Metz: The Wrong Abstraction](https://sandimetz.com/blog/2016/1/20/the-wrong-abstraction)
- [SensioLabs: DRY Principle Balance](https://sensiolabs.com/blog/2025/the-dry-principle-finding-the-delicate-balance-between-code-reuse-and-clarity)
- [Drupalize.me: Traits in Drupal](https://drupalize.me/blog/peek-traits-drupal-8)
