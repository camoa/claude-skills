---
name: tdd-companion
description: Use during implementation to enforce TDD - reminds test-first, validates Red-Green-Refactor cycle, integrates with superpowers:test-driven-development
version: 1.1.0
---

# TDD Companion

Enforce test-driven development during implementation sessions.

## Activation

Activate automatically during Phase 3 coding when:
- About to write implementation code
- After `task-context-loader` loads a task
- User asks to implement a feature
- Code changes are being discussed

## Core Rule

**STOP before writing any implementation code.**

Ask: "Have you written the failing test first?"

If no test exists, do NOT write implementation. Instead:
1. Help write the test
2. Confirm test fails
3. Only then write implementation

## Red-Green-Refactor Enforcement

### RED Phase
Before any implementation:
```
CHECKPOINT: Is there a failing test for this?

If NO:
  → Write test first
  → Run test to confirm failure
  → Show error message

If YES:
  → Proceed to implementation
```

### GREEN Phase
When writing implementation:
```
CHECKPOINT: Write MINIMUM code to pass.

Rules:
- Only code needed to pass the test
- No additional features
- No premature optimization
- No "while I'm here" additions
```

### REFACTOR Phase
After test passes:
```
CHECKPOINT: Can this be improved?

Only if:
- Tests are green
- Refactoring doesn't change behavior
- Tests stay green after changes
```

## Drupal Test Types Quick Reference

| Type | Location | Use For | Command |
|------|----------|---------|---------|
| Unit | `tests/src/Unit/` | Pure logic, no Drupal | `ddev phpunit --filter Unit` |
| Kernel | `tests/src/Kernel/` | Services, entities, DB | `ddev phpunit --filter Kernel` |
| Functional | `tests/src/Functional/` | Full page requests | `ddev phpunit --filter Functional` |

## Test Template

When helping write tests, use this structure:
```php
<?php

namespace Drupal\Tests\{module}\{Type};

use Drupal\Tests\{TestBase};

class {ClassName}Test extends {TestBase} {

  public function test{Behavior}(): void {
    // Arrange
    $input = ...;

    // Act
    $result = $this->subject->method($input);

    // Assert
    $this->assertEquals($expected, $result);
  }
}
```

## Intervention Points

Intervene when you detect:
- "Let me just add this feature..." → "Stop. Is there a test?"
- "I'll add tests later..." → "Tests first. What behavior are we testing?"
- "This is too simple for tests..." → "Simple now, complex later. Test it."
- Implementing multiple features at once → "One test, one feature at a time."

## Integration with superpowers:test-driven-development

For complex testing scenarios, defer:
```
This needs detailed TDD guidance.
Invoking superpowers:test-driven-development for full methodology.
```

Use superpowers skill for:
- Complex mocking scenarios
- Integration test strategies
- Test refactoring approaches

## Stop Points

STOP and enforce:
- Before ANY implementation code is written
- If implementation goes beyond test requirements
- If user tries to skip testing
- Before moving to next feature (are tests green?)
