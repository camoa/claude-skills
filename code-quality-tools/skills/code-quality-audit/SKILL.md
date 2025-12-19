---
name: code-quality-audit
description: Use when auditing code quality, security vulnerabilities, checking coverage, finding SOLID/DRY violations, running TDD - supports both Drupal (PHPStan, PHPMD, PHPCPD, Psalm taint analysis, security scanners via DDEV) and Next.js (ESLint, Jest, jscpd, madge) projects
version: 1.7.0
---

# Code Quality Audit

Run quality audits for **Drupal** and **Next.js** projects with consistent tooling and reporting.

## When to Use

**Drupal projects:**
- "Setup quality tools" / "Install PHPStan"
- "Run code audit" / "Check code quality"
- "Check coverage" / "What's my coverage?"
- "Find SOLID violations" / "Check complexity"
- "Check duplication" / "DRY check"
- "Lint code" / "Check coding standards"
- "Fix deprecations" / "Run rector"
- "Start TDD" / "RED-GREEN-REFACTOR"
- "Check security" / "Find vulnerabilities" / "OWASP audit"

**Next.js projects:**
- "Setup quality tools" / "Install ESLint"
- "Run code audit" / "Check code quality"
- "Check coverage" / "Run Jest coverage"
- "Find SOLID violations" / "Check complexity" / "Check circular deps"
- "Lint code" / "Run ESLint"
- "Check duplication" / "DRY check"
- "Start TDD" / "Jest watch mode"

## Quick Reference

### Drupal Scripts
| Task | Script |
|------|--------|
| Setup tools | `scripts/core/install-tools.sh` |
| Full audit | `scripts/core/full-audit.sh` |
| Coverage | `scripts/drupal/coverage-report.sh` |
| SOLID check | `scripts/drupal/solid-check.sh` |
| DRY check | `scripts/drupal/dry-check.sh` |
| Lint check | `scripts/drupal/lint-check.sh` |
| Fix deprecations | `scripts/drupal/rector-fix.sh` |
| TDD cycle | `scripts/drupal/tdd-workflow.sh` |
| Security audit | `scripts/drupal/security-check.sh` |

### Next.js Scripts
| Task | Script |
|------|--------|
| Setup tools | `scripts/core/install-tools.sh` |
| Full audit | `scripts/core/full-audit.sh` |
| Coverage | `scripts/nextjs/coverage-report.sh` |
| SOLID check | `scripts/nextjs/solid-check.sh` |
| Lint check | `scripts/nextjs/lint-check.sh` |
| DRY check | `scripts/nextjs/dry-check.sh` |
| TDD cycle | `scripts/nextjs/tdd-workflow.sh` |

## Before Any Operation

**Drupal:**
1. Locate Drupal root: check `web/core/lib/Drupal.php` or `docroot/core/lib/Drupal.php`
2. Verify DDEV: `ddev describe`
3. Create reports directory: `mkdir -p .reports && echo ".reports/" >> .gitignore`

**Next.js:**
1. Verify npm: `npm --version`
2. Create reports directory: `mkdir -p .reports && echo ".reports/" >> .gitignore`

## When to Run What

Read `decision-guides/quality-audit-checklist.md` for detailed guidance.

| Context | What to Run | Time |
|---------|-------------|------|
| Pre-commit | `quality:cs` only | ~5s |
| Pre-push | PHPStan + Unit/Kernel tests | ~2min |
| Pre-merge | Full audit | ~10min |
| Weekly | Full audit + HTML reports | ~15min |

---

## Operation 1: Setup Tools

When user says "setup tools", "install PHPStan", "install testing tools":

1. Create `.reports/` directory, add to `.gitignore`
2. Check installed: `ddev exec vendor/bin/phpstan --version`
3. Install missing:
   ```bash
   ddev composer require --dev phpstan/phpstan phpstan/extension-installer \
     mglaman/phpstan-drupal phpstan/phpstan-deprecation-rules \
     phpmd/phpmd systemsdk/phpcpd drupal/coder
   ```
4. Copy templates to project root:
   - `templates/drupal/phpstan.neon` (PHPStan 2.x - extensions auto-load)
   - `templates/drupal/phpmd.xml`
   - `templates/drupal/phpunit.xml`
5. Ask coverage driver preference:

   | Option | Best For | Trade-off |
   |--------|----------|-----------|
   | **PCOV** | CI/CD, daily dev | 2-5x faster, line coverage only |
   | **Xdebug** | Deep analysis | Slower, has branch/path coverage |

   If PCOV: Check PHP version (`ddev exec php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;"`), add to `.ddev/config.yaml`:
   ```yaml
   webimage_extra_packages:
     - php8.3-pcov  # Use actual version
   ```
6. Show composer scripts (mandatory):
   ```bash
   ddev composer quality:all    # All checks
   ddev composer test:coverage  # Tests with coverage
   ddev composer quality:fix    # Auto-fix standards
   ```

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

## Operation 6: Module-Specific Audit

When user says "check {module_name}", "audit my_module":

1. Verify module exists: `ls -la web/modules/custom/{module_name}`
2. Run all checks scoped to that path
3. Save reports with prefix: `.reports/{module_name}-*.json`

---

## Operation 7: Add Composer Scripts

When user says "add composer scripts", "setup quality scripts":

1. Read existing `composer.json`
2. Detect modules path (`web/modules/custom` or `docroot/modules/custom`)
3. Add scripts (merge with existing):
   ```json
   {
     "scripts": {
       "test": "phpunit",
       "test:unit": "phpunit --testsuite unit",
       "test:kernel": "phpunit --testsuite kernel",
       "test:coverage": "php -d pcov.enabled=1 vendor/bin/phpunit --coverage-text",
       "quality:phpstan": "phpstan analyse {modules_path}",
       "quality:phpmd": "phpmd {modules_path} text phpmd.xml",
       "quality:dry": "phpcpd {modules_path} --min-lines=10",
       "quality:cs": "phpcs --standard=Drupal,DrupalPractice {modules_path}",
       "quality:all": ["@quality:phpstan", "@quality:phpmd", "@quality:dry"],
       "quality:fix": "phpcbf --standard=Drupal,DrupalPractice {modules_path}"
     }
   }
   ```
4. Show usage (mandatory):
   ```bash
   ddev composer quality:all    # All checks
   ddev composer test:coverage  # With coverage
   ddev composer quality:fix    # Auto-fix
   ```

---

## Operation 8: CI Integration

When user says "add to CI", "setup GitHub Actions":

1. Copy `templates/ci/github-drupal.yml` to `.github/workflows/quality.yml`
2. Explain pipeline: Lint → Static Analysis → Tests → Coverage (fails <70%)

---

## Operation 9: Generate Report

When user says "generate report", "show quality report":

1. Read `.reports/audit-report.json`
2. Generate `.reports/audit-report.md` with:
   - Summary table (PASS/WARN/FAIL)
   - Coverage by code type
   - SOLID violations by severity
   - DRY clones with Rule of Three evaluation
   - Prioritized recommendations

---

## Operation 10: TDD Workflow

When user says "start TDD", "TDD cycle", "RED-GREEN-REFACTOR":

Read `references/tdd-workflow.md` for patterns.

1. Determine test type from `decision-guides/test-type-selection.md`:
   - Pure logic, no dependencies → Unit (~1ms)
   - Needs services/DB → Kernel (~100ms) **← Default for Drupal**
   - Needs browser → Functional (~1s)
   - Needs JavaScript → FunctionalJS (~5s)

2. Run TDD phases:

   **RED** (test must fail):
   ```bash
   scripts/drupal/tdd-workflow.sh red [TestFile.php]
   ```
   If test passes, warn: "In RED phase, test should fail first"

   **GREEN** (minimal code to pass):
   ```bash
   scripts/drupal/tdd-workflow.sh green [TestFile.php]
   ```
   Write only enough to pass. Don't optimize yet.

   **REFACTOR** (clean up, stay green):
   ```bash
   scripts/drupal/tdd-workflow.sh refactor [TestFile.php]
   ```
   Improve naming, extract methods. Tests must stay green.

   **Watch mode** (continuous):
   ```bash
   scripts/drupal/tdd-workflow.sh watch
   ```

3. Target: 20-40 cycles/hour during active TDD

---

## Operation 11: Lint Check (Drupal)

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

## Operation 12: Rector Fix (Drupal)

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

---

# Next.js Operations

The following operations apply to Next.js projects (detected by `next.config.js`).

## Operation 13: Setup Tools (Next.js)

When user says "setup tools", "install ESLint" in a Next.js project:

Run `scripts/core/install-tools.sh` or:

1. Install ESLint + Next.js config:
   ```bash
   npm install -D eslint eslint-config-next @typescript-eslint/eslint-plugin \
       eslint-plugin-react-hooks eslint-config-prettier
   ```
2. Install Jest + Testing Library:
   ```bash
   npm install -D jest @jest/globals jest-environment-jsdom \
       @testing-library/react @testing-library/jest-dom
   ```
3. Install jscpd: `npm install -D jscpd`
4. Copy templates if needed:
   - `templates/nextjs/eslint.config.js`
   - `templates/nextjs/jest.config.js`
   - `templates/nextjs/jest.setup.js`

---

## Operation 14: Full Audit (Next.js)

When user says "run audit", "check code quality" in a Next.js project:

Run `scripts/core/full-audit.sh` (auto-detects Next.js) or manually:

1. Lint check (ESLint + TypeScript)
2. Coverage check (Jest)
3. DRY check (jscpd)
4. Aggregate results into `.reports/audit-report.json`

**Thresholds:**
| Metric | Pass | Warning | Fail |
|--------|------|---------|------|
| Coverage | >80% | 70-80% | <70% |
| ESLint errors | 0 | 1-10 | >10 |
| TypeScript errors | 0 | - | >0 |
| Duplication | <5% | 5-10% | >10% |

---

## Operation 15: Lint Check (Next.js)

When user says "lint code", "run eslint", "check types":

Run `scripts/nextjs/lint-check.sh` or:

1. ESLint: `npx eslint . --format json > .reports/lint-report.json`
2. TypeScript: `npx tsc --noEmit`
3. Show summary with error/warning counts

**Auto-fix mode:**
```bash
scripts/nextjs/lint-check.sh --fix
# or: npx eslint . --fix
```

---

## Operation 16: Coverage Check (Next.js)

When user says "check coverage", "run jest coverage":

Run `scripts/nextjs/coverage-report.sh` or:

```bash
npx jest --coverage --coverageReporters=json-summary
```

Reports saved to `.reports/coverage/`

---

## Operation 17: DRY Check (Next.js)

When user says "check duplication", "DRY check":

Run `scripts/nextjs/dry-check.sh` or:

```bash
npx jscpd src --reporters json --output .reports/dry/
```

Applies same Rule of Three guidance as Drupal DRY check.

---

## Operation 18: TDD Workflow (Next.js)

When user says "start TDD", "jest watch":

Run `scripts/nextjs/tdd-workflow.sh` with phases:

```bash
scripts/nextjs/tdd-workflow.sh red [test-file]      # Write failing test
scripts/nextjs/tdd-workflow.sh green [test-file]    # Minimal implementation
scripts/nextjs/tdd-workflow.sh refactor [test-file] # Clean up
scripts/nextjs/tdd-workflow.sh watch                # Continuous mode
```

Target: 20-40 cycles/hour during active TDD

---

## Operation 19: SOLID Check (Next.js)

When user says "find SOLID violations", "check complexity", "check circular dependencies":

Run `scripts/nextjs/solid-check.sh` or:

1. **Circular Dependencies (ISP, DIP)**: `npx madge --circular src`
2. **Complexity Analysis (SRP)**: ESLint complexity rules
3. **Large File Detection (SRP)**: Files >300 lines
4. **TypeScript Strict Mode (LSP, DIP)**: Check `tsconfig.json` strict settings

Categorize by principle:

| Issue | Principle | Severity |
|-------|-----------|----------|
| Circular dependency | ISP, DIP | Critical |
| Complexity >10 | SRP | Warning |
| File >300 lines | SRP | Warning |
| strict mode disabled | LSP, DIP | Warning |

Save `.reports/solid-report.json` with:
- Per-principle status (pass/warning/fail)
- Circular dependency chains
- Complexity violations
- Large files list

**Thresholds:**
| Metric | Pass | Warning | Fail |
|--------|------|---------|------|
| Circular deps | 0 | - | >0 |
| Complexity violations | 0 | 1-5 | >5 |
| Large files | 0 | 1-3 | >3 |

---

## Operation 20: Security Audit (Drupal)

When user says "check security", "find vulnerabilities", "security audit", "OWASP check":

Run `scripts/drupal/security-check.sh` which performs:

1. **Drush pm:security** - Drupal security advisories (built-in)
2. **Composer audit** - PHP package vulnerabilities (built-in)
3. **yousha/php-security-linter** - PHPCS security rules (OWASP/CIS) - **actively maintained 2025**
4. **Psalm taint analysis** - XSS/SQLi detection via dataflow analysis - **optional but powerful**
5. **drupal/security_review** - Drupal configuration audit (if installed)
6. **Custom Drupal Patterns**:
   - SQL Injection: Unsafe `db_query()` with variable concatenation
   - XSS: Twig `|raw` filter usage
   - Insecure Deserialization: `unserialize()` on user input
   - Command Injection: `exec()`, `shell_exec()` patterns

Save `.reports/security-report.json` with:
- Security issues by severity (critical/high/medium/low)
- OWASP 2021 category mapping
- File locations with line numbers
- Remediation suggestions

**Modern Security Stack (2024-2025):**

| Tool | Status | Purpose | OWASP Coverage |
|------|--------|---------|----------------|
| Drush pm:security | Built-in | Drupal advisories | A06:2021 |
| Composer audit | Built-in | Package vulns | A06:2021 |
| yousha/php-security-linter | ✅ Dec 2025 | PHPCS security | CIS + OWASP Top 10 |
| Psalm taint analysis | ✅ Active | XSS/SQLi dataflow | A03:2021, A03:2021 |
| drupal/security_review | ✅ Nov 2024 | Config audit | A05:2021 |
| Custom patterns | Built-in | Drupal-specific | Various |

**Thresholds:**

| Severity | Pass | Warning | Fail |
|----------|------|---------|------|
| Critical | 0 | 0 | >0 |
| High | 0 | 1-3 | >3 |
| Medium | 0 | 1-10 | >10 |
| Low | 0 | any | >20 |

**Installation:**
```bash
# Required
ddev composer require --dev yousha/php-security-linter

# Recommended (Psalm taint analysis)
ddev composer require --dev vimeo/psalm

# Optional (Drupal config audit)
ddev composer require drupal/security_review
ddev drush pm:enable security_review
```

**Usage:**
```bash
# Full security audit
ddev exec bash skills/code-quality-audit/scripts/drupal/security-check.sh

# View report
cat .reports/security-report.json | jq .
```

**Why NOT pheromone/phpcs-security-audit?**
- Last updated March 2020 (abandoned)
- No PHP 8.x support
- Security rules outdated
- Use yousha/php-security-linter instead (updated Dec 2025)

---

## Saving Reports

All reports must follow `schemas/audit-report.schema.json`:

```json
{
  "meta": {
    "project_type": "drupal|nextjs|monorepo",
    "timestamp": "2025-12-06T12:00:00Z",
    "thresholds": { "coverage_minimum": 70, "duplication_max": 5 }
  },
  "summary": {
    "overall_score": "pass|warning|fail",
    "coverage_score": "pass|warning|fail",
    "solid_score": "pass|warning|fail",
    "dry_score": "pass|warning|fail"
  },
  "coverage": { "line_coverage": 75.5, "files_analyzed": 45 },
  "solid": { "violations": [{ "principle": "SRP", "severity": "critical", "file": "...", "message": "..." }] },
  "dry": { "duplication_percentage": 3.2, "clones": [] },
  "recommendations": [{ "category": "coverage", "priority": "high", "message": "...", "action": "..." }]
}
```

---

## References

- `references/tdd-workflow.md` - RED-GREEN-REFACTOR patterns, test naming, cycle targets
- `references/coverage-metrics.md` - Coverage targets by code type, PCOV vs Xdebug
- `references/dry-detection.md` - Rule of Three, when duplication is OK
- `references/solid-detection.md` - SOLID detection patterns and fixes
- `references/composer-scripts.md` - Ready-to-use composer scripts

## Decision Guides

- `decision-guides/test-type-selection.md` - Unit vs Kernel vs Functional decision tree
- `decision-guides/quality-audit-checklist.md` - When to run what (pre-commit vs pre-merge)

## Templates

### Drupal
- `templates/drupal/phpstan.neon` - PHPStan 2.x config (extensions auto-load)
- `templates/drupal/phpmd.xml` - PHPMD ruleset for Drupal
- `templates/drupal/phpunit.xml` - PHPUnit config with testsuites
- `templates/ci/github-drupal.yml` - GitHub Actions workflow

### Next.js
- `templates/nextjs/eslint.config.js` - ESLint v9 flat config with TypeScript
- `templates/nextjs/jest.config.js` - Jest config with coverage thresholds
- `templates/nextjs/jest.setup.js` - Jest setup with Testing Library
- `templates/nextjs/.prettierrc` - Prettier config with Tailwind plugin
