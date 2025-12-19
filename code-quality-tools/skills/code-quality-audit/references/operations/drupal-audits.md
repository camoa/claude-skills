# Drupal Audit Operations

Quality audit operations for Drupal projects.

## Contents

- [Operation 2: Full Audit](#operation-2-full-audit)
- [Operation 3: Coverage Check](#operation-3-coverage-check)
- [Operation 4: SOLID Check](#operation-4-solid-check)
- [Operation 5: DRY Check](#operation-5-dry-check)
- [Operation 11: Lint Check](#operation-11-lint-check)
- [Operation 12: Rector Fix](#operation-12-rector-fix)

---

## Operation 2: Full Audit

When user says "run audit", "check code quality", "full quality check":

Run `scripts/core/full-audit.sh` or execute manually:

1. Verify tools installed
2. Run all checks on `web/modules/custom`:
   - PHPStan: `ddev exec vendor/bin/phpstan analyse {path} --error-format=json`
   - PHPMD: `ddev exec vendor/bin/phpmd {path} json cleancode,codesize,design`
   - PHPCPD: `ddev exec vendor/bin/phpcpd {path} --min-lines=10`
   - Static calls: `grep -rn "\\Drupal::" {path} --include="*.php"`
   - Coverage: `ddev exec php -d pcov.enabled=1 vendor/bin/phpunit --coverage-text`
3. Save `.reports/audit-report.json` following `schemas/audit-report.schema.json`
4. Show summary with PASS/WARN/FAIL per category
5. Provide top 3-5 recommendations

**Thresholds:**
| Metric | Pass | Warning | Fail |
|--------|------|---------|------|
| Coverage | >80% | 70-80% | <70% |
| Duplication | <5% | 5-10% | >10% |
| PHPStan errors | 0 | 1-10 | >10 |

---

## Operation 3: Coverage Check

When user says "check coverage", "what's my coverage?":

Run `scripts/drupal/coverage-report.sh` or:

1. Execute: `ddev exec php -d pcov.enabled=1 vendor/bin/phpunit --testsuite unit,kernel --coverage-text`
2. Parse output for `Lines: XX.XX%`
3. Apply targets from `references/coverage-metrics.md`:

   | Code Type | Target |
   |-----------|--------|
   | Business logic services | 90%+ |
   | Security-related code | 95%+ |
   | API controllers | 85%+ |
   | Form validation | 85%+ |
   | Simple CRUD, getters/setters | 60-70% |

4. Save `.reports/coverage-report.json` following schema
5. Compare against code-type targets, not just blanket 70%

---

## Operation 4: SOLID Check

When user says "find SOLID violations", "run PHPStan", "check complexity":

Run `scripts/drupal/solid-check.sh` or:

1. PHPStan: `ddev exec vendor/bin/phpstan analyse {path} --error-format=json`
2. PHPMD: `ddev exec vendor/bin/phpmd {path} json cleancode,codesize,design`
3. Static calls: `grep -rn "\\Drupal::" {path} --include="*.php" --exclude-dir=tests`
4. Categorize by principle:

   | Issue | Principle | Severity |
   |-------|-----------|----------|
   | Complexity >15 | SRP | Critical |
   | Methods >25 per class | SRP | Critical |
   | Static `\Drupal::` in services | DIP | Critical |
   | Type errors | LSP | Warning |

5. Save `.reports/solid-report.json` following schema

---

## Operation 5: DRY Check

When user says "check duplication", "find duplicate code", "DRY check":

Run `scripts/drupal/dry-check.sh` or:

1. Execute: `ddev exec vendor/bin/phpcpd {path} --min-lines=10 --min-tokens=70 --exclude tests`
2. Parse duplication percentage
3. **Before recommending extraction**, evaluate per `references/dry-detection.md`:

   **Rule of Three Questions:**
   - Is this the 3rd+ occurrence? (If <3, duplication OK)
   - Knowledge duplication or coincidental similarity?
   - Will these change together? (Same reason to change?)
   - Is the abstraction clear or would it be forced?

   **Skip extraction when:**
   - Test setup code (tests should be independent)
   - Only 2 occurrences (wait for 3rd)
   - Would need many parameters (wrong abstraction)
   - Similar but different reasons to change

4. Save `.reports/dry-report.json` following schema
5. Rate: <5% excellent | 5-10% acceptable | >10% needs refactoring

---

## Operation 11: Lint Check

When user says "lint code", "check coding standards", "run phpcs":

Run `scripts/drupal/lint-check.sh` or:

1. Execute: `ddev exec vendor/bin/phpcs --standard=Drupal,DrupalPractice {path} --report=json`
2. Save `.reports/lint-report.json`
3. Show summary with error/warning counts

**Auto-fix mode:**
```bash
scripts/drupal/lint-check.sh --fix
# or: ddev exec vendor/bin/phpcbf --standard=Drupal,DrupalPractice {path}
```

---

## Operation 12: Rector Fix

When user says "fix deprecations", "run rector", "auto-fix deprecated code":

Run `scripts/drupal/rector-fix.sh` or:

1. Dry run first: `ddev exec vendor/bin/rector process {path} --dry-run`
2. Show proposed changes
3. If user confirms: `ddev exec vendor/bin/rector process {path}`
4. Save output to `.reports/rector/`

**Usage:**
```bash
scripts/drupal/rector-fix.sh          # Dry run (preview changes)
scripts/drupal/rector-fix.sh --apply  # Apply fixes
```
