# Drupal TDD Workflow

Test-Driven Development workflow for Drupal projects.

## Contents

- [Overview](#overview)
- [Test Type Selection](#test-type-selection)
- [TDD Phases](#tdd-phases)
- [Watch Mode](#watch-mode)
- [Cycle Targets](#cycle-targets)

---

## Overview

When user says "start TDD", "TDD cycle", "RED-GREEN-REFACTOR":

Read `references/tdd-workflow.md` for detailed patterns.

**Key Principle:** Write the test FIRST, watch it FAIL, then write minimal code to PASS.

---

## Test Type Selection

Determine test type from `decision-guides/test-type-selection.md`:

| Use Case | Test Type | Speed | When |
|----------|-----------|-------|------|
| Pure logic, no dependencies | Unit | ~1ms | Calculations, formatters, helpers |
| Needs services/DB | Kernel | ~100ms | **← Default for Drupal** |
| Needs browser | Functional | ~1s | Full page rendering |
| Needs JavaScript | FunctionalJS | ~5s | Interactive features |

**Default:** Use Kernel tests for most Drupal code (services, entities, forms).

---

## TDD Phases

### RED Phase (Test Must Fail)

```bash
scripts/drupal/tdd-workflow.sh red [TestFile.php]
```

1. Write a failing test
2. Run the test - **it must fail**
3. If test passes, warn: "In RED phase, test should fail first"

**Example:**
```php
public function testUserCanSubmitForm() {
  $form = \Drupal::formBuilder()->getForm('Drupal\mymodule\Form\MyForm');
  $this->assertArrayHasKey('#submit', $form);
}
```

### GREEN Phase (Minimal Code to Pass)

```bash
scripts/drupal/tdd-workflow.sh green [TestFile.php]
```

1. Write **only enough code** to make the test pass
2. Don't optimize yet
3. Run test - it must pass

**Example:**
```php
public function buildForm(array $form, FormStateInterface $form_state) {
  $form['#submit'] = ['::submitForm'];
  return $form;
}
```

### REFACTOR Phase (Clean Up, Stay Green)

```bash
scripts/drupal/tdd-workflow.sh refactor [TestFile.php]
```

1. Improve naming, extract methods
2. Tests must stay green
3. Don't add functionality

**Example:**
```php
public function buildForm(array $form, FormStateInterface $form_state) {
  $form['#submit'] = [$this, 'submitForm'];
  $form = $this->addFormElements($form);
  return $form;
}

private function addFormElements(array $form): array {
  // Extracted for clarity
  return $form;
}
```

---

## Watch Mode

For continuous TDD:

```bash
scripts/drupal/tdd-workflow.sh watch
```

Watches for file changes and reruns tests automatically.

---

## Cycle Targets

**Target:** 20-40 cycles/hour during active TDD

**A cycle is:** RED → GREEN → REFACTOR → commit

**Too slow (<10/hour)?**
- Tests too large (split into smaller tests)
- Too much code per cycle (write less code)
- Not using watch mode

**Too fast (>50/hour)?**
- Tests too trivial (increase test quality)
- Skipping REFACTOR phase (maintain code quality)
