# Quality Audit Checklist

When to run which checks and how to interpret results.

> **Online Dev-Guides:** For quality gates, audit checklists, and testing best practices beyond tool-specific commands, see https://camoa.github.io/dev-guides/drupal/tdd/quality-gates-audit-checklist/ and https://camoa.github.io/dev-guides/drupal/testing/best-practices-anti-patterns/.

## Pre-Commit Checks (Fast)

Run before every commit:

```bash
# Quick lint check (~5s)
ddev exec vendor/bin/phpcs \
    --standard=Drupal \
    --extensions=php,module \
    web/modules/custom/my_module
```

**Pass criteria:** No errors (warnings OK)

## Pre-Push Checks (Medium)

Run before pushing to remote:

```bash
# Static analysis (~30s)
ddev exec vendor/bin/phpstan analyse \
    web/modules/custom \
    --level=5

# Unit + Kernel tests (~1-2min)
ddev exec vendor/bin/phpunit \
    --testsuite unit,kernel
```

**Pass criteria:**
- PHPStan: No errors at level 5
- Tests: All passing

## Pre-Merge Checks (Full)

Run before merging PRs:

```bash
# Full audit (~5-10min)
./scripts/core/full-audit.sh
```

**Pass criteria:**
- Coverage: ≥70%
- SOLID: No critical violations
- DRY: <10% duplication
- All tests passing

## Periodic Deep Analysis

Run weekly or before releases:

```bash
# Full audit with HTML reports
REPORT_DIR=./reports/weekly ddev exec vendor/bin/phpmetrics \
    --report-html=reports/weekly/metrics \
    web/modules/custom

# Branch coverage (slower but thorough)
XDEBUG_MODE=coverage ddev exec vendor/bin/phpunit \
    --path-coverage \
    --coverage-html reports/weekly/coverage
```

## Check-by-Check Guide

### Coverage Check

**When:** Always before merge

**Command:**
```bash
./scripts/drupal/coverage-report.sh
```

**Interpret results:**

| Coverage | Action |
|----------|--------|
| ≥80% | Excellent, merge |
| 70-80% | Good, merge with note |
| 60-70% | Add tests before merge |
| <60% | Block merge |

**Focus areas:**
- New code should have ≥80%
- Critical paths should have ≥90%
- Skip coverage for simple getters/setters

### SOLID Check

**When:** Before merge, after major refactoring

**Command:**
```bash
./scripts/drupal/solid-check.sh
```

**Interpret results:**

| Issue | Severity | Action |
|-------|----------|--------|
| Static `\Drupal::` calls | Warning | Refactor to DI |
| Complexity >15 | Critical | Split method/class |
| Complexity 10-15 | Warning | Consider refactoring |
| Methods >25 | Critical | Split class |
| PHPStan errors | Varies | Fix type issues |

**Priority order:**
1. Critical issues → Block merge
2. Warnings in new code → Fix before merge
3. Warnings in existing code → Create tech debt ticket

### DRY Check

**When:** Before merge, quarterly audit

**Command:**
```bash
./scripts/drupal/dry-check.sh
```

**Interpret results:**

| Duplication | Action |
|-------------|--------|
| <5% | Excellent |
| 5-10% | Monitor |
| 10-15% | Schedule refactoring |
| >15% | Immediate refactoring |

**Before extracting:**
1. Is this knowledge duplication or coincidence?
2. Will these change together?
3. Is abstraction clear or forced?

**Rule of Three:** Only extract after 3rd occurrence.

### TDD Check

**When:** During development

**Command:**
```bash
./scripts/drupal/tdd-workflow.sh cycle
```

**Checklist:**
- [ ] Test written BEFORE implementation
- [ ] Test failed first (RED confirmed)
- [ ] Minimal code to pass (no extras)
- [ ] Refactored after green
- [ ] Test name describes behavior

## CI/CD Pipeline Stages

### Stage 1: Lint (1min)

```yaml
- phpcs --standard=Drupal
```

**Fail:** Merge blocked

### Stage 2: Static Analysis (2min)

```yaml
- phpstan analyse --level=8
```

**Fail:** Merge blocked (errors), Warning (level <8)

### Stage 3: Unit + Kernel Tests (5min)

```yaml
- phpunit --testsuite unit,kernel
```

**Fail:** Merge blocked

### Stage 4: Coverage (5min)

```yaml
- phpunit --coverage-clover
- check coverage >= 70%
```

**Fail:** Merge blocked (<70%)
**Warn:** Coverage decreased

### Stage 5: Full Tests (10min)

```yaml
- phpunit --testsuite functional
```

**Fail:** Merge blocked

### Stage 6: Security & Deprecations (optional)

```yaml
- phpstan analyse --level=2  # Includes deprecation rules
- composer audit
```

**Fail:** Warning (critical: block)

> **Note**: Use `phpstan/phpstan-deprecation-rules` instead of deprecated `drupal-check`.

## Issue Triage

### Must Fix Before Merge

- [ ] Test failures
- [ ] PHPStan errors (not warnings)
- [ ] Coverage below minimum
- [ ] Critical SOLID violations
- [ ] Security issues

### Should Fix Before Merge

- [ ] New code without tests
- [ ] Coverage decrease
- [ ] SOLID warnings in changed files
- [ ] Static `\Drupal::` calls in services

### Can Fix Later (Tech Debt)

- [ ] SOLID warnings in unchanged code
- [ ] Duplication in legacy code
- [ ] Coverage gaps in old code
- [ ] PHPStan warnings

## Report Interpretation

### Audit Report Summary

```markdown
Overall: ✅ PASS | ⚠️ WARNING | ❌ FAIL

Coverage:  72% (target: 80%)     ⚠️
SOLID:     3 warnings            ⚠️
DRY:       4.2% duplication      ✅
Tests:     47 passing, 0 failed  ✅
```

**Decision:**
- All ✅ → Merge
- Mix of ✅/⚠️ → Review warnings, merge if acceptable
- Any ❌ → Do not merge

### Reading Recommendations

1. **High priority** → Must address
2. **Medium priority** → Should address
3. **Low priority** → Nice to have

Address high priority before merge.
Medium/low can be tickets for later.
