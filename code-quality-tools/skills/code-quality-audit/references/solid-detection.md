# SOLID Detection Reference

How each SOLID principle is detected and measured in Drupal projects.

> **Online Dev-Guides:** For comprehensive Drupal SOLID patterns, examples, and best practices beyond tool detection, see https://camoa.github.io/dev-guides/drupal/solid-principles/ (12 guides covering SRP, OCP, LSP, ISP, DIP with Drupal-specific patterns, anti-patterns, and code reference maps).

## S - Single Responsibility Principle

**Definition:** A class should have only one reason to change.

### Detection Methods

| Tool | Metric | Threshold | Severity |
|------|--------|-----------|----------|
| PHPMD | Cyclomatic Complexity | >10 | Warning |
| PHPMD | NPath Complexity | >200 | Warning |
| PHPMD | Methods per class | >25 | Critical |
| PHPMD | Public methods | >20 | Warning |
| PHPMetrics | LCOM (Lack of Cohesion) | >1 | Warning |

### Commands

```bash
# PHPMD codesize ruleset
ddev exec vendor/bin/phpmd web/modules/custom text codesize

# Check specific metric
ddev exec vendor/bin/phpmd web/modules/custom text codesize \
    --minimumpriority 1
```

### Fixing SRP Violations

**Signs of violation:**
- Class does multiple unrelated things
- Many private methods
- Long constructor with many dependencies
- Methods that don't use most instance variables

**Solutions:**
- Extract related functionality to new service
- Use composition over inheritance
- Create focused helper classes

## O - Open/Closed Principle

**Definition:** Open for extension, closed for modification.

### Detection Methods

Manual review required. Look for:
- `switch` statements on type/class
- `instanceof` checks in conditionals
- Modifying existing code when adding features

### Drupal Patterns (Good)

```php
// Plugin system - extend without modifying
/** @QueueWorker(id = "my_worker") */
class MyWorker extends QueueWorkerBase {}

// Event subscribers - extend behavior
class MySubscriber implements EventSubscriberInterface {
    public static function getSubscribedEvents() {
        return [KernelEvents::REQUEST => 'onRequest'];
    }
}

// Hook system
function mymodule_entity_presave(EntityInterface $entity) {}
```

### Anti-patterns (Bad)

```php
// Switch on type - violates OCP
switch ($entity->getEntityTypeId()) {
    case 'node': handleNode($entity); break;
    case 'user': handleUser($entity); break;
    // Adding new type requires modifying this
}
```

## L - Liskov Substitution Principle

**Definition:** Subtypes must be substitutable for their base types.

### Detection Methods

| Tool | Check | Threshold |
|------|-------|-----------|
| PHPStan Level 8 | Return type violations | 0 errors |
| PHPStan Level 8 | Parameter type violations | 0 errors |
| Psalm Level 1 | Covariance/contravariance | 0 errors |

### Commands

```bash
# PHPStan strict type checking
ddev exec vendor/bin/phpstan analyse \
    web/modules/custom \
    --level=8 \
    --error-format=json
```

### Common Violations

```php
// Base class
class ContentProcessor {
    public function process(ContentInterface $content): Result {}
}

// VIOLATION: Narrower parameter type
class ArticleProcessor extends ContentProcessor {
    public function process(Article $content): Result {} // BAD
}

// VIOLATION: Wider return type
class ArticleProcessor extends ContentProcessor {
    public function process(ContentInterface $content): ?Result {} // BAD
}
```

### Drupal Context

- Plugin interfaces must be honored exactly
- Service substitution for testing must maintain contract
- Entity type handlers must follow base class contracts

## I - Interface Segregation Principle

**Definition:** Clients shouldn't depend on interfaces they don't use.

### Detection Methods

| Indicator | Threshold | Action |
|-----------|-----------|--------|
| Interface method count | >7 | Split interface |
| Unused methods in impl | Any | Review design |
| Empty method bodies | Any | Interface too broad |

### Commands

```bash
# Count methods per interface (manual)
grep -c "public function" src/MyInterface.php
```

### Good Drupal Examples

```php
// Drupal uses focused interfaces
interface EntityChangedInterface {
    public function getChangedTime();
    public function setChangedTime($timestamp);
}

interface EntityOwnerInterface {
    public function getOwner();
    public function setOwner(UserInterface $account);
    public function getOwnerId();
    public function setOwnerId($uid);
}

// Entity implements only what it needs
class Node implements EntityChangedInterface, EntityOwnerInterface {}
```

### Anti-pattern

```php
// Too many methods - violates ISP
interface ContentManagerInterface {
    public function create();
    public function read();
    public function update();
    public function delete();
    public function publish();
    public function unpublish();
    public function archive();
    public function restore();
    public function translate();
    public function clone();
    // Classes often don't need all of these
}
```

## D - Dependency Inversion Principle

**Definition:** Depend on abstractions, not concretions.

### Detection Methods

| Tool | Detection | Severity |
|------|-----------|----------|
| phpstan-drupal | Static `\Drupal::service()` | Warning |
| phpstan-drupal | Static `\Drupal::entityTypeManager()` | Warning |
| drupal-check | Deprecated service usage | Critical |
| PHPMD | StaticAccess rule | Warning |

### Commands

```bash
# Find static Drupal calls
ddev exec grep -rn "\\\\Drupal::" web/modules/custom \
    --include="*.php" \
    --exclude-dir=tests

# drupal-check deprecations
ddev exec vendor/bin/drupal-check web/modules/custom

# PHPStan with Drupal rules
ddev exec vendor/bin/phpstan analyse web/modules/custom --level=8
```

### Bad Pattern (Static calls)

```php
class MyService {
    public function process() {
        // VIOLATION: Direct static call
        $storage = \Drupal::entityTypeManager()->getStorage('node');
        $config = \Drupal::config('my_module.settings');
    }
}
```

### Good Pattern (Dependency Injection)

```php
class MyService {
    public function __construct(
        private readonly EntityTypeManagerInterface $entityTypeManager,
        private readonly ConfigFactoryInterface $configFactory,
    ) {}

    public function process() {
        // Uses injected dependencies
        $storage = $this->entityTypeManager->getStorage('node');
        $config = $this->configFactory->get('my_module.settings');
    }
}
```

### services.yml

```yaml
services:
  my_module.my_service:
    class: Drupal\my_module\MyService
    arguments:
      - '@entity_type.manager'
      - '@config.factory'
```

## Aggregated SOLID Report

The `solid-check.sh` script produces:

```json
{
  "violations": [
    {
      "principle": "SRP",
      "severity": "warning",
      "file": "src/Service/BigService.php",
      "line": 45,
      "message": "Cyclomatic complexity of 15 exceeds 10",
      "metric": "complexity",
      "value": 15,
      "threshold": 10
    }
  ],
  "metrics": {
    "total_violations": 5,
    "static_drupal_calls": 3,
    "phpstan_errors": 2,
    "phpmd_violations": 8
  }
}
```

## Resources

- [Matt Glaman: DI Anti-Patterns](https://mglaman.dev/blog/dependency-injection-anti-patterns-drupal)
- [Drupal.org: Services and DI](https://www.drupal.org/docs/drupal-apis/services-and-dependency-injection)
- [PHPStan Rule Levels](https://phpstan.org/user-guide/rule-levels)
