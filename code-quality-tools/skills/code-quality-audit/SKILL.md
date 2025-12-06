---
name: code-quality-audit
description: Use when user asks to audit code quality, check test coverage, find SOLID violations, detect code duplication, setup quality tools, or run TDD workflows - provides step-by-step guidance for PHPStan, PHPMD, PHPCPD via DDEV with actionable recommendations
version: 1.1.0
---

# Code Quality Audit

This skill guides you through code quality auditing for Drupal projects. Follow these instructions based on what the user requests.

## Trigger Recognition

Use this skill when user says things like:
- "Setup code quality tools" / "Install testing tools" / "Install PHPStan"
- "Run a code quality audit" / "Audit my code" / "Check code quality"
- "Check test coverage" / "What's my coverage?"
- "Find SOLID violations" / "Run PHPStan" / "Check for complexity"
- "Check for duplication" / "Find duplicate code" / "DRY check"
- "Check [specific module] for issues"
- "Add quality checks to CI"
- "Generate quality report" / "Show me the audit report"

## Before You Start

### Find the Drupal Project

1. **Check common locations**:
   - `./web/core/lib/Drupal.php` (standard)
   - `./drupal-app/web/core/lib/Drupal.php` (monorepo)
   - `./docroot/core/lib/Drupal.php` (Acquia)

2. **Verify DDEV**: Check `.ddev/config.yaml` exists, run `ddev describe`

3. **If not found**, ask user for path

4. **Set paths**:
   - `DRUPAL_ROOT` = path with `core/lib/Drupal.php`
   - `DRUPAL_MODULES_PATH` = `web/modules/custom`
   - `REPORTS_DIR` = `.reports`

### Reports Directory

All operations save JSON to `.reports/`:
```
.reports/
├── coverage-report.json
├── solid-report.json
├── dry-report.json
├── audit-report.json
└── audit-report.md
```

**First time**: `mkdir -p .reports && echo ".reports/" >> .gitignore`

## Operation 1: Setup Quality Tools

**Triggers**: "Setup tools", "Install testing tools", "Install PHPStan"

1. Create `.reports/` and add to `.gitignore`
2. Check installed tools: `ddev exec vendor/bin/phpstan --version`
3. Install missing:
   ```bash
   ddev composer require --dev phpstan/phpstan phpstan/extension-installer \
     mglaman/phpstan-drupal phpmd/phpmd systemsdk/phpcpd mglaman/drupal-check drupal/coder
   ```
4. Copy templates from `${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/templates/drupal/` to project:
   - `phpstan.neon`, `phpmd.xml`, `phpunit.xml`
5. Check PCOV: `ddev exec php -m | grep pcov` - if missing, recommend adding to `.ddev/config.yaml`
6. Suggest composer scripts (see `references/composer-scripts.md`)

**Report**: List what was installed, files created, next steps.

## Operation 2: Run Full Audit

**Triggers**: "Run audit", "Check code quality", "Full quality check"

1. Verify tools installed, create `.reports/`
2. Determine target path (default: `web/modules/custom`)
3. Run all checks:

**Coverage**:
```bash
ddev exec php -d pcov.enabled=1 vendor/bin/phpunit --testsuite unit,kernel --coverage-text
```

**PHPStan**:
```bash
ddev exec vendor/bin/phpstan analyse {path} --error-format=json > .reports/phpstan-raw.json
```

**PHPMD**:
```bash
ddev exec vendor/bin/phpmd {path} json cleancode,codesize,design --exclude tests > .reports/phpmd-raw.json
```

**PHPCPD**:
```bash
ddev exec vendor/bin/phpcpd {path} --min-lines=10 --exclude tests
```

**Static calls**:
```bash
ddev exec grep -rn "\\Drupal::" {path} --include="*.php" --exclude-dir=tests
```

4. Save aggregated `.reports/audit-report.json` (see schema in `schemas/`)
5. Show console summary table with PASS/WARN/FAIL status
6. Provide top 3-5 recommendations

**Thresholds**: Coverage <70% FAIL, 70-80% WARN | PHPStan >10 FAIL | Duplication >10% FAIL

## Operation 3: Check Coverage Only

**Triggers**: "Check coverage", "What's my test coverage?"

1. `mkdir -p .reports`
2. Run: `ddev exec php -d pcov.enabled=1 vendor/bin/phpunit --testsuite unit,kernel --coverage-text`
3. Parse output for `Lines: XX.XX%`
4. Save `.reports/coverage-report.json`
5. Show summary with 70%/80% thresholds

## Operation 4: Check SOLID Only

**Triggers**: "Find SOLID violations", "Run PHPStan", "Check complexity"

1. `mkdir -p .reports`
2. Run PHPStan: `ddev exec vendor/bin/phpstan analyse {path} --error-format=json > .reports/phpstan-raw.json`
3. Run PHPMD: `ddev exec vendor/bin/phpmd {path} json cleancode,codesize,design > .reports/phpmd-raw.json`
4. Check DIP: `ddev exec grep -rn "\\Drupal::" {path} --include="*.php" --exclude-dir=tests`
5. Save `.reports/solid-report.json`
6. Categorize by principle (SRP, DIP, LSP) and show with fix suggestions

**SOLID Mapping**:
| Issue | Principle | Severity |
|-------|-----------|----------|
| Complexity >15 | SRP | Critical |
| Static `\Drupal::` in services | DIP | Critical |
| Type errors | LSP | Warning |

## Operation 5: Check DRY Only

**Triggers**: "Check duplication", "Find duplicate code", "DRY check"

1. `mkdir -p .reports`
2. Run: `ddev exec vendor/bin/phpcpd {path} --min-lines=10 --min-tokens=70 --exclude tests`
3. Save `.reports/dry-report.json`
4. Show duplication % with threshold (<5% PASS, 5-10% WARN, >10% FAIL)
5. List clones with file locations

**Before recommending extraction**: Is it knowledge duplication or coincidence? Rule of Three.

## Operation 6: Check Specific Module

**Triggers**: "Check {module_name}", "Audit contentbench_organizations"

1. Verify module: `ls -la web/modules/custom/{module_name}`
2. Run all checks scoped to that path
3. Save reports with module prefix: `.reports/{module_name}-*.json`

## Operation 7: Setup CI Integration

**Triggers**: "Add to CI", "Setup GitHub Actions"

1. Copy `${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/templates/ci/github-drupal.yml`
2. Write to `.github/workflows/quality.yml`
3. Explain: Lint → Static Analysis → Tests → Coverage (fails <70%)

## Operation 8: Generate Markdown Report

**Triggers**: "Generate report", "Show quality report"

1. Check `.reports/audit-report.json` exists
2. Read and parse JSON
3. Generate `.reports/audit-report.md` with:
   - Summary table (PASS/WARN/FAIL icons)
   - Coverage details
   - SOLID violations by severity
   - Code duplication clones
   - Prioritized recommendations
4. Tell user: "Generated `.reports/audit-report.md`"

## Quick Reference

### Thresholds

| Metric | Pass | Warning | Fail |
|--------|------|---------|------|
| Coverage | >80% | 70-80% | <70% |
| Duplication | <5% | 5-10% | >10% |
| Complexity | <10 | 10-15 | >15 |
| PHPStan | 0 | 1-10 | >10 |

### Test Type Selection

| Need DB? | Need Services? | Need Browser? | Use |
|----------|----------------|---------------|-----|
| No | No | No | Unit |
| Yes | Yes | No | Kernel |
| Yes | Yes | Yes | Functional |

**Default**: Kernel tests (10-15x faster than Functional)

### Tool Commands

| Check | Command |
|-------|---------|
| PHPStan | `ddev exec vendor/bin/phpstan analyse {path}` |
| PHPMD | `ddev exec vendor/bin/phpmd {path} text cleancode,codesize` |
| PHPCPD | `ddev exec vendor/bin/phpcpd {path} --min-lines=10` |
| Coverage | `ddev exec php -d pcov.enabled=1 vendor/bin/phpunit --coverage-text` |

## References

- `references/tdd-workflow.md` - RED-GREEN-REFACTOR cycle
- `references/solid-detection.md` - Detailed SOLID detection and fixes
- `references/dry-detection.md` - PHPCPD config, refactoring patterns
- `references/coverage-metrics.md` - PCOV vs Xdebug
- `references/composer-scripts.md` - Recommended composer scripts
- `references/json-schemas.md` - Report JSON structures

## Decision Guides

- `decision-guides/test-type-selection.md` - Full decision tree
- `decision-guides/quality-audit-checklist.md` - When to run what

## Templates

- `templates/drupal/phpunit.xml`
- `templates/drupal/phpstan.neon`
- `templates/drupal/phpmd.xml`
- `templates/ci/github-drupal.yml`
