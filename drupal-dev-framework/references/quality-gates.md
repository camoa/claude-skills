# Quality Gates

Checkpoints enforced during `/complete` and `/validate` commands.

## Gate Overview

| Gate | When | What | Blocker? |
|------|------|------|----------|
| **Gate 1** | Pre-commit | Code standards | Yes |
| **Gate 2** | Before complete | Tests pass | Yes |
| **Gate 3** | Before complete | Architecture compliance | Yes |
| **Gate 4** | Before complete | Security review | Yes |

## Gate 1: Code Standards

Before committing code:

| Check | Tool | Command |
|-------|------|---------|
| PHP standards | PHPCS | `phpcs --standard=Drupal,DrupalPractice {path}` |
| Static analysis | PHPStan | `phpstan analyze {path}` |
| JavaScript | ESLint | `npm run lint:js` |
| SCSS | Stylelint | `npm run lint:scss` |

### Checklist
- [ ] PHPCS passes with Drupal/DrupalPractice rulesets
- [ ] PHPStan passes (level 6+ recommended)
- [ ] ESLint passes (if JavaScript present)
- [ ] No linting rules disabled without documented reason

## Gate 2: Tests Pass

Before marking task complete:

| Check | Verification |
|-------|--------------|
| Unit tests | All pass |
| Kernel tests | All pass |
| Functional tests | All pass (if applicable) |
| New code coverage | Tests exist for new code |

### Checklist
- [ ] All existing tests pass
- [ ] New code has test coverage
- [ ] No skipped tests without documented reason
- [ ] Test names describe behavior

### Commands
```bash
# Run all module tests
ddev phpunit web/modules/custom/{module}/tests/

# Run specific test
ddev phpunit --filter {TestClassName}

# Run with coverage
ddev phpunit --coverage-html coverage/
```

## Gate 3: Architecture Compliance

Before completing task:

| Check | Reference |
|-------|-----------|
| SOLID principles | `references/solid-drupal.md` |
| DRY patterns | `references/dry-patterns.md` |
| Library-First | `references/library-first.md` |
| TDD followed | `references/tdd-workflow.md` |

### Checklist
- [ ] Services have single responsibility
- [ ] Dependencies injected (no `\Drupal::service()`)
- [ ] No duplicate code blocks
- [ ] Services built before UI
- [ ] Tests written before implementation

## Gate 4: Security

Before deployment:

| Area | Check |
|------|-------|
| Input | Validated via Form API |
| Output | Escaped (Twig auto, `Html::escape()`) |
| Database | Query API used, no raw SQL |
| Access | Permissions checked |
| CSRF | Tokens present (Form API handles) |

### Checklist
- [ ] All user input validated
- [ ] All output properly escaped
- [ ] No raw SQL with user input
- [ ] Access checks on all routes
- [ ] CSRF protection on state-changing operations

**Reference**: `references/security-checklist.md` for detailed guidance.

## Enforcement Points

| Command | Gates Checked |
|---------|---------------|
| `/validate` | All gates |
| `/complete` | Gate 2, 3, 4 (user confirms Gate 1) |

## Completion Checklist

Before `/complete` succeeds:

```markdown
## Pre-Completion Verification

### Gate 1: Code Standards
- [ ] PHPCS passes
- [ ] PHPStan passes
- [ ] No disabled lint rules

### Gate 2: Tests
- [ ] All tests pass (user confirms)
- [ ] New code has tests

### Gate 3: Architecture
- [ ] SOLID principles followed
- [ ] DRY - no duplication
- [ ] Library-First pattern used

### Gate 4: Security
- [ ] Input validated
- [ ] Output escaped
- [ ] Access controlled

All gates passed? Task can be completed.
```

## Blocking vs Warning

| Severity | Action |
|----------|--------|
| **Blocking** | Cannot complete task until fixed |
| **Warning** | Can complete but should create follow-up task |

### Blocking Issues
- Security vulnerabilities
- Failing tests
- Missing test coverage for critical paths
- `\Drupal::service()` in new code

### Warning Issues
- Minor code style issues
- Missing docblocks
- Low-priority refactoring opportunities
