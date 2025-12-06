---
name: tdd-companion
description: Use during implementation to enforce TDD - reminds test-first, validates Red-Green-Refactor cycle, integrates with superpowers:test-driven-development
version: 1.0.0
---

# TDD Companion

Enforce test-driven development discipline during implementation.

## Triggers

- During any coding session in Phase 3
- Auto-activated after `task-context-loader`
- User is about to write implementation code

## Core Principle

**Test First. Always.**

The Red-Green-Refactor cycle:
1. **RED** - Write a failing test
2. **GREEN** - Write minimum code to pass
3. **REFACTOR** - Improve while keeping green

## Reminders

### Before Writing Implementation
Ask: "Have you written the test first?"

If no test exists:
- Stop implementation
- Guide test creation
- Run test to confirm it fails

### Before Running Tests
Ensure:
- Test is specific to current change
- Test describes expected behavior
- Test will fail without implementation

### After Implementation
Check:
- Only minimum code was added
- Test now passes
- No additional untested code

### Before Refactoring
Confirm:
- All tests are green
- Refactoring won't change behavior
- Tests still pass after refactoring

## Integration with superpowers:test-driven-development

This skill works alongside `superpowers:test-driven-development`:

```
Use superpowers:test-driven-development for:
- Detailed TDD methodology
- Complex testing scenarios
- Test structure guidance

Use tdd-companion for:
- Quick reminders during coding
- Cycle enforcement
- Drupal-specific test patterns
```

## Drupal Test Types

| Test Type | Location | Use For |
|-----------|----------|---------|
| Unit | `tests/src/Unit/` | Isolated logic, no Drupal |
| Kernel | `tests/src/Kernel/` | Services, entities, database |
| Functional | `tests/src/Functional/` | Full page requests |
| FunctionalJavascript | `tests/src/FunctionalJavascript/` | JavaScript behavior |

## Quick Test Template

```php
<?php

namespace Drupal\Tests\my_module\Unit;

use Drupal\Tests\UnitTestCase;

class MyServiceTest extends UnitTestCase {

  public function testMethodDoesExpectedThing(): void {
    // Arrange
    $service = new MyService();

    // Act
    $result = $service->method($input);

    // Assert
    $this->assertEquals($expected, $result);
  }

}
```

## Human Control Points

- Developer runs tests (Claude does NOT auto-run)
- Developer confirms test failure before implementation
- Developer confirms tests pass after implementation
- Developer decides when to refactor
