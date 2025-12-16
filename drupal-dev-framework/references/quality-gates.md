# Quality Gates

Checkpoints enforced during `/complete` and `/validate` commands.

## Gate Overview

| Gate | When | What | Blocker? |
|------|------|------|----------|
| **Gate 1** | Pre-commit | Code standards | Yes |
| **Gate 2** | Before complete | Tests pass | Yes |
| **Gate 3** | Before complete | Architecture compliance | Yes |
| **Gate 4** | Before complete | Security review | Yes |
| **Gate 5** | Before complete | Code purposefulness | Yes |

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
| Files | Extensions whitelisted, private:// for sensitive |
| Secrets | API keys in `$settings`, not config |
| Logging | No sensitive data in logs |
| Caching | Sensitive content contextualized |
| Serialization | No `unserialize()` on user data |

### Checklist
- [ ] All user input validated
- [ ] All output properly escaped
- [ ] No raw SQL with user input
- [ ] Access checks on all routes
- [ ] CSRF protection on state-changing operations
- [ ] File uploads whitelist extensions only
- [ ] Sensitive files use private:// stream
- [ ] API keys/secrets in $settings, not exportable config
- [ ] No passwords/PII in logs
- [ ] No `unserialize()` on untrusted data

**Reference**: `references/security-checklist.md` for detailed guidance.

## Gate 5: Code Purposefulness

Ensures code is intentional, comprehensible, and not over-engineered.

| Area | Check |
|------|-------|
| Necessity | Every code block serves a clear purpose |
| Complexity | No unnecessary defensive patterns |
| API validity | All called methods/hooks actually exist |
| Comments | Explain "why", not "what" |
| Comprehension | Developer can explain any block |

### Checklist
- [ ] No unnecessary try-catch (Drupal handles most errors)
- [ ] No defensive null-checks for values that can't be null
- [ ] All hook names are valid Drupal hooks
- [ ] All service/method calls reference real APIs
- [ ] Comments explain reasoning, not obvious behavior
- [ ] No "instruction-style" comments (LLM prompt artifacts)
- [ ] Developer can explain the purpose of each component

### Red Flags
| Pattern | Problem |
|---------|---------|
| `try { } catch (\Exception $e) { }` everywhere | Swallowing errors hides bugs |
| Null checks on injected services | Services are never null after injection |
| Comments like "// Handle the case where..." for impossible cases | Over-defensive, bloated code |
| Calls to `$entity->getNonExistentMethod()` | Hallucinated API |
| Comments describing what code does line-by-line | Prompt artifacts or lack of understanding |

**Reference**: `references/purposeful-code.md` for detailed guidance.

## Enforcement Points

| Command | Gates Checked |
|---------|---------------|
| `/validate` | All gates |
| `/complete` | Gate 2, 3, 4, 5 (user confirms Gate 1) |

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
- [ ] File uploads secure
- [ ] Secrets in $settings
- [ ] No sensitive data in logs

### Gate 5: Code Purposefulness
- [ ] No unnecessary try-catch blocks
- [ ] No hallucinated API calls
- [ ] Comments explain "why", not "what"
- [ ] Developer can explain each component

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
- Calls to non-existent APIs/methods
- Excessive try-catch blocks swallowing errors
- Code developer cannot explain

### Warning Issues
- Minor code style issues
- Missing docblocks
- Low-priority refactoring opportunities
- Over-commented obvious code
