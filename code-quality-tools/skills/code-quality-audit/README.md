# Code Quality Audit Skill

Automated code quality auditing for **Drupal** (via DDEV) and **Next.js** projects.

## Quick Start

```bash
# 1. Detect environment (auto-detects Drupal or Next.js)
./scripts/core/detect-environment.sh

# 2. Install tools (if needed)
./scripts/core/install-tools.sh

# 3. Run full audit
./scripts/core/full-audit.sh
```

## Contents

### Scripts

#### Core (Both Platforms)
| Script | Purpose |
|--------|---------|
| `scripts/core/detect-environment.sh` | Detect project type (Drupal/Next.js) |
| `scripts/core/install-tools.sh` | Install quality tools |
| `scripts/core/full-audit.sh` | Run all checks |
| `scripts/core/report-processor.sh` | Convert JSON to Markdown |

#### Drupal
| Script | Purpose |
|--------|---------|
| `scripts/drupal/coverage-report.sh` | PHPUnit + PCOV coverage |
| `scripts/drupal/solid-check.sh` | PHPStan + PHPMD |
| `scripts/drupal/dry-check.sh` | PHPCPD duplication |
| `scripts/drupal/lint-check.sh` | phpcs coding standards |
| `scripts/drupal/rector-fix.sh` | Auto-fix deprecations |
| `scripts/drupal/tdd-workflow.sh` | TDD helper |

#### Next.js
| Script | Purpose |
|--------|---------|
| `scripts/nextjs/coverage-report.sh` | Jest coverage |
| `scripts/nextjs/solid-check.sh` | madge + complexity + TS strict |
| `scripts/nextjs/dry-check.sh` | jscpd duplication |
| `scripts/nextjs/lint-check.sh` | ESLint + TypeScript |
| `scripts/nextjs/tdd-workflow.sh` | Jest TDD helper |

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

#### Drupal
| Template | Purpose |
|----------|---------|
| `templates/drupal/phpunit.xml` | PHPUnit configuration |
| `templates/drupal/phpstan.neon` | PHPStan configuration |
| `templates/drupal/phpmd.xml` | PHPMD ruleset |
| `templates/ci/github-drupal.yml` | GitHub Actions workflow |

#### Next.js
| Template | Purpose |
|----------|---------|
| `templates/nextjs/eslint.config.js` | ESLint v9 flat config |
| `templates/nextjs/jest.config.js` | Jest configuration |
| `templates/nextjs/jest.setup.js` | Jest setup file |
| `templates/nextjs/.prettierrc` | Prettier configuration |

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
| Max file lines | 300 | `MAX_FILE_LINES` |

## Requirements

### Drupal
- DDEV
- Drupal 10.3+ or 11.x
- PHP 8.2+

### Next.js
- Node.js 18+
- npm or yarn
- TypeScript (recommended)

## Version

**v1.6.0** - 19 operations (12 Drupal, 7 Next.js)
