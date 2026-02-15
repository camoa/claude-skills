# Test Type Selection Guide

Decision tree for choosing the right test type in Drupal.

> **Online Dev-Guides:** For comprehensive test type decision matrix with Drupal-specific patterns, see https://camoa.github.io/dev-guides/drupal/tdd/test-type-decision-matrix/. For PHPUnit test framework details, see https://camoa.github.io/dev-guides/drupal/testing/.

## Quick Decision Matrix

| Need Database? | Need Services? | Need Browser? | Test Type |
|:--------------:|:--------------:|:-------------:|-----------|
| No | No | No | **Unit** |
| Yes | Yes | No | **Kernel** |
| Yes | Yes | Yes (no JS) | **Functional** |
| Yes | Yes | Yes (with JS) | **FunctionalJavascript** |

## Decision Tree

```
What are you testing?
│
├─► Pure PHP logic (no Drupal APIs)?
│   └─► UNIT TEST
│       Speed: ~1ms
│       Base: UnitTestCase
│
├─► Uses Drupal services but no browser?
│   │
│   ├─► Entity CRUD, storage, queries?
│   │   └─► KERNEL TEST
│   │
│   ├─► Service with dependencies?
│   │   └─► KERNEL TEST
│   │
│   ├─► Plugin behavior?
│   │   └─► KERNEL TEST
│   │
│   └─► Config/schema validation?
│       └─► KERNEL TEST
│       Speed: ~100ms
│       Base: KernelTestBase
│
├─► Needs browser/HTML output?
│   │
│   ├─► No JavaScript?
│   │   │
│   │   ├─► Form submission?
│   │   │   └─► FUNCTIONAL TEST
│   │   │
│   │   ├─► Page rendering?
│   │   │   └─► FUNCTIONAL TEST
│   │   │
│   │   └─► Access control?
│   │       └─► FUNCTIONAL TEST
│   │       Speed: ~1s
│   │       Base: BrowserTestBase
│   │
│   └─► Requires JavaScript?
│       │
│       ├─► AJAX interactions?
│       │   └─► FUNCTIONAL JS TEST
│       │
│       ├─► Dynamic UI updates?
│       │   └─► FUNCTIONAL JS TEST
│       │
│       └─► JavaScript validation?
│           └─► FUNCTIONAL JS TEST
│           Speed: ~5s
│           Base: WebDriverTestBase
│
└─► Not sure?
    └─► Start with KERNEL TEST
        (Best balance of speed and realism)
```

## Test Type Details

### Unit Tests

**When to use:**
- Testing pure PHP classes
- No Drupal dependencies needed
- Mathematical calculations
- String manipulation
- Data transformations

**Base class:** `Drupal\Tests\UnitTestCase`

**Example scenarios:**
- Value object validation
- Utility functions
- Parser/formatter classes
- Business logic without services

**Speed:** ~1ms per test

```php
class PriceCalculatorTest extends UnitTestCase {
    public function testCalculate_withDiscount_appliesCorrectly(): void {
        $calculator = new PriceCalculator();
        $result = $calculator->calculate(100, 0.1);
        $this->assertEquals(90, $result);
    }
}
```

### Kernel Tests

**When to use:**
- Testing services with DI
- Entity operations (CRUD)
- Database queries
- Plugin instantiation
- Configuration
- No user-facing output needed

**Base class:** `Drupal\KernelTests\KernelTestBase`

**Required:** `protected static $modules = ['my_module'];`

**Example scenarios:**
- Service methods
- Entity hooks
- Queue workers
- Custom storage
- Event subscribers

**Speed:** ~100ms per test

```php
class MyServiceTest extends KernelTestBase {
    protected static $modules = ['my_module', 'node'];

    public function testProcess_withNode_updatesField(): void {
        $service = $this->container->get('my_module.service');
        $node = Node::create(['type' => 'article', 'title' => 'Test']);
        $node->save();

        $service->process($node);

        $this->assertEquals('processed', $node->field_status->value);
    }
}
```

### Functional Tests

**When to use:**
- Testing page output
- Form submission workflows
- Access control/permissions
- Menu links and routing
- HTTP responses
- No JavaScript needed

**Base class:** `Drupal\Tests\BrowserTestBase`

**Example scenarios:**
- Admin forms
- Content creation UI
- Login/logout flows
- Permission checks
- Block rendering

**Speed:** ~1s per test

```php
class AdminFormTest extends BrowserTestBase {
    protected static $modules = ['my_module'];
    protected $defaultTheme = 'stark';

    public function testForm_withValidInput_savesConfig(): void {
        $admin = $this->createUser(['administer my_module']);
        $this->drupalLogin($admin);

        $this->drupalGet('admin/config/my_module');
        $this->submitForm(['setting' => 'value'], 'Save');

        $this->assertSession()->pageTextContains('saved');
    }
}
```

### Functional JavaScript Tests

**When to use:**
- AJAX-powered forms
- Dynamic content loading
- JavaScript validation
- Drag-and-drop interfaces
- Real-time updates

**Base class:** `Drupal\FunctionalJavascriptTests\WebDriverTestBase`

**Requirements:** ChromeDriver or Selenium

**Example scenarios:**
- Autocomplete fields
- Modal dialogs
- WYSIWYG editors
- Live preview
- Client-side validation

**Speed:** ~5s per test

```php
class AjaxFormTest extends WebDriverTestBase {
    protected static $modules = ['my_module'];
    protected $defaultTheme = 'stark';

    public function testAutocomplete_withSearch_showsResults(): void {
        $this->drupalGet('node/add/article');

        $field = $this->getSession()->getPage()->findField('tags');
        $field->setValue('test');

        $this->assertSession()->waitForElementVisible('css', '.ui-autocomplete');
        $this->assertSession()->elementExists('css', '.ui-autocomplete li');
    }
}
```

## Speed Comparison

| Test Type | ~Time/Test | 100 Tests |
|-----------|------------|-----------|
| Unit | 1ms | 0.1s |
| Kernel | 100ms | 10s |
| Functional | 1s | 100s |
| FunctionalJS | 5s | 500s |

**Rule:** Prefer faster tests when possible.

## Common Mistakes

### Using Functional When Kernel Suffices

❌ **Wrong:** Functional test just to check service output
```php
class MyServiceTest extends BrowserTestBase {
    public function testService(): void {
        // Overkill - boots entire Drupal + browser
    }
}
```

✅ **Right:** Kernel test for service logic
```php
class MyServiceTest extends KernelTestBase {
    public function testService(): void {
        // Fast - only loads what's needed
    }
}
```

### Using Unit When Kernel Needed

❌ **Wrong:** Mocking everything
```php
class EntityProcessorTest extends UnitTestCase {
    public function test(): void {
        // Mocking entity_type.manager, storage, query...
        // Complex, brittle, doesn't test real behavior
    }
}
```

✅ **Right:** Kernel test with real services
```php
class EntityProcessorTest extends KernelTestBase {
    public function test(): void {
        // Real entity storage, real queries
        // Tests actual integration
    }
}
```

## TDD Recommendation

For TDD in Drupal, **start with Kernel tests** as your default.

**Why:**
- Fast enough for rapid cycles (100ms)
- Has real Drupal services
- Tests actual integration
- No browser overhead
- Good balance of speed and realism

Escalate to Functional only when you need browser rendering.
