# Code Quality Audit Skill

Automated code quality auditing for Drupal projects via DDEV.

## Quick Start

```bash
# 1. Detect environment
./scripts/core/detect-environment.sh

# 2. Install tools (if needed)
./scripts/core/install-tools.sh

# 3. Run full audit
./scripts/core/full-audit.sh
```

## Contents

### Scripts

| Script | Purpose |
|--------|---------|
| `scripts/core/detect-environment.sh` | Detect project type, validate DDEV |
| `scripts/core/install-tools.sh` | Install quality tools |
| `scripts/core/full-audit.sh` | Run all checks |
| `scripts/core/report-processor.sh` | Convert JSON to Markdown |
| `scripts/drupal/coverage-report.sh` | PHPUnit + PCOV coverage |
| `scripts/drupal/solid-check.sh` | PHPStan + PHPMD |
| `scripts/drupal/dry-check.sh` | PHPCPD duplication |
| `scripts/drupal/tdd-workflow.sh` | TDD helper |

### References

| Document | Topic |
|----------|-------|
| `references/tdd-workflow.md` | RED-GREEN-REFACTOR |
| `references/solid-detection.md` | SOLID detection methods |
| `references/dry-detection.md` | Duplication analysis |
| `references/coverage-metrics.md` | PCOV vs Xdebug |
| `references/tool-comparison.md` | PHP vs JS tools |

### Decision Guides

| Guide | Purpose |
|-------|---------|
| `decision-guides/test-type-selection.md` | Unit vs Kernel vs Functional |
| `decision-guides/quality-audit-checklist.md` | When to run what |

### Templates

| Template | Purpose |
|----------|---------|
| `templates/drupal/phpunit.xml` | PHPUnit configuration |
| `templates/drupal/phpstan.neon` | PHPStan configuration |
| `templates/drupal/phpmd.xml` | PHPMD ruleset |
| `templates/ci/github-drupal.yml` | GitHub Actions workflow |

### Schemas

| Schema | Purpose |
|--------|---------|
| `schemas/audit-report.schema.json` | JSON report structure |

## Thresholds

| Metric | Default | Environment Variable |
|--------|---------|----------------------|
| Coverage minimum | 70% | `COVERAGE_MINIMUM` |
| Coverage target | 80% | `COVERAGE_TARGET` |
| Max duplication | 5% | `DUPLICATION_MAX` |
| Max complexity | 10 | `COMPLEXITY_MAX` |

## Requirements

- DDEV
- Drupal 10.3+ or 11.x
- PHP 8.2+
