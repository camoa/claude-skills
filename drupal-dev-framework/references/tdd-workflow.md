# TDD Workflow for Drupal

Test-Driven Development principles enforced during Phase 3 implementation.

## The Non-Negotiable Rule

**Tests MUST precede implementation. No exceptions.**

Before writing ANY implementation code, ask: "Is there a failing test for this?"

## Red-Green-Refactor Cycle

| Phase | Action | Checkpoint |
|-------|--------|------------|
| **RED** | Write failing test | Test MUST fail. If it passes, test is wrong. |
| **GREEN** | Write minimal code to pass | Only enough to pass. No extras. |
| **REFACTOR** | Improve code quality | Tests must stay green. |

## When to Apply TDD

| Component | TDD Required | Test Type |
|-----------|--------------|-----------|
| Services with business logic | **YES - Always** | Unit or Kernel |
| Form validation logic | **YES** | Unit |
| Plugins (actions, conditions) | **YES** | Kernel |
| Entity hooks | **YES** | Kernel |
| Access control logic | **YES** | Kernel |
| Simple getters/setters | Optional | Unit |
| Twig templates | No | Functional |

## Drupal Test Types

| Type | Location | Use For | Isolation |
|------|----------|---------|-----------|
| Unit | `tests/src/Unit/` | Pure logic, no Drupal | Full (mocked) |
| Kernel | `tests/src/Kernel/` | Services, entities, DB | Partial (real container) |
| Functional | `tests/src/Functional/` | Full page requests | None (full bootstrap) |

## Integration Over Mocks

Prefer Kernel tests with real services over Unit tests with heavy mocking:
- Use actual database, cache, entity systems
- Mock only external APIs and third-party services
- Drupal's `KernelTestBase` provides real DI container

## Test Template

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

## Enforcement Checkpoints

During `/implement`, verify at each step:

1. **Before coding**: "What test verifies this works?"
2. **Write test**: Confirm it fails (RED)
3. **Write code**: Minimal implementation only
4. **Run test**: Confirm it passes (GREEN)
5. **Refactor**: Only if tests stay green

## Red Flags to Intercept

| Developer Says | Response |
|----------------|----------|
| "Let me just add this feature..." | "Stop. Is there a test?" |
| "I'll add tests later..." | "Tests first. What behavior are we testing?" |
| "This is too simple for tests..." | "Simple now, complex later. Test it." |
| "Let me implement multiple things..." | "One test, one feature at a time." |

## User-Controlled Testing

- Claude suggests test commands but does NOT auto-run
- User executes: `ddev phpunit --filter {TestClass}`
- User reports results back to Claude
- Claude responds based on pass/fail
