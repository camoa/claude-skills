---
name: code-quality-audit
description: Use when auditing code for TDD compliance, SOLID principles, DRY violations, or test coverage - runs PHPStan, PHPMD, PHPCPD via DDEV and generates structured reports with actionable recommendations
version: 1.0.0
---

# Code Quality Audit

Automated code quality auditing for Drupal projects. Runs TDD, SOLID, and DRY checks via DDEV.

## When to Use This Skill

**Trigger phrases:**
- "Run a code quality audit"
- "Check my test coverage"
- "Find SOLID violations"
- "Check for code duplication"
- "Is my code following DRY principles?"
- "Setup quality tools"

## Quick Start

### 1. Detect Environment
```bash
${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/core/detect-environment.sh
```

### 2. Install Tools (if needed)
```bash
${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/core/install-tools.sh
```

### 3. Run Full Audit
```bash
${CLAUDE_PLUGIN_ROOT}/skills/code-quality-audit/scripts/core/full-audit.sh
```

## Audit Types

| Type | Script | What It Checks |
|------|--------|----------------|
| **Full Audit** | `full-audit.sh` | All checks, aggregated report |
| **Coverage** | `drupal/coverage-report.sh` | PHPUnit + PCOV line coverage |
| **SOLID** | `drupal/solid-check.sh` | PHPStan, PHPMD, drupal-check |
| **DRY** | `drupal/dry-check.sh` | PHPCPD duplication |
| **TDD Helper** | `drupal/tdd-workflow.sh` | Watch mode for RED-GREEN-REFACTOR |

## Thresholds (Environment Variables)

| Variable | Default | Description |
|----------|---------|-------------|
| `COVERAGE_MINIMUM` | 70 | CI gate (fail below) |
| `COVERAGE_TARGET` | 80 | Goal for new code |
| `DUPLICATION_MAX` | 5 | Max duplication % |
| `COMPLEXITY_MAX` | 10 | Max cyclomatic complexity |
| `DRUPAL_MODULES_PATH` | `web/modules/custom` | Path to analyze |
| `REPORT_DIR` | `./reports/quality` | Output directory |

## Output Format

All scripts produce JSON reports, converted to Markdown via `report-processor.sh`.

**Exit Codes:**
- `0` = Pass (all checks within thresholds)
- `1` = Warning (some checks exceeded soft thresholds)
- `2` = Fail (critical thresholds exceeded)

## SOLID Principle Detection

| Principle | Tool | Detection | Threshold |
|-----------|------|-----------|-----------|
| **SRP** | PHPMD | Cyclomatic complexity | >10 |
| **SRP** | PHPMD | Methods per class | >25 |
| **OCP** | Manual | Switch on types | Review |
| **LSP** | PHPStan | Type checking level 8 | 0 errors |
| **ISP** | Manual | Interface method count | >7 |
| **DIP** | phpstan-drupal | Static `\Drupal::` calls | 0 |
| **DIP** | drupal-check | Deprecated service usage | 0 |

See `references/solid-detection.md` for detailed detection methods.

## DRY Thresholds

| Duplication % | Rating | Action |
|---------------|--------|--------|
| <5% | Excellent | Maintain |
| 5-10% | Acceptable | Monitor |
| 10-15% | Warning | Refactor |
| >15% | Critical | Immediate action |

See `references/dry-detection.md` for PHPCPD configuration.

## Coverage Interpretation

| Level | Coverage | Use Case |
|-------|----------|----------|
| Minimum | 70% | CI gate |
| Target | 80% | New code goal |
| Excellent | 90%+ | Mature projects |

See `references/coverage-metrics.md` for PCOV vs Xdebug comparison.

## Test Type Selection

When writing tests, choose the right type:

| Need DB? | Need Services? | Need Browser? | Test Type |
|----------|----------------|---------------|-----------|
| No | No | No | Unit |
| Yes | Yes | No | Kernel |
| Yes | Yes | Yes (no JS) | Functional |
| Yes | Yes | Yes (with JS) | FunctionalJavascript |

**Rule of thumb:** Start with Kernel tests for Drupal (10-15x faster than Functional).

See `decision-guides/test-type-selection.md` for detailed decision tree.

## Tools Reference

### Installed via install-tools.sh

```bash
composer require --dev \
  phpstan/phpstan \
  phpstan/extension-installer \
  mglaman/phpstan-drupal \
  phpstan/phpstan-deprecation-rules \
  phpmd/phpmd \
  systemsdk/phpcpd \
  mglaman/drupal-check \
  drupal/coder
```

### Tool Versions (December 2025)

| Tool | Version | Notes |
|------|---------|-------|
| PHPStan | 2.x | Level 10 max, 50% less memory |
| phpstan-drupal | Latest | Drupal 11 support |
| PHPMD | Latest | JSON output support |
| PHPCPD | 8.x | systemsdk fork (PHP 8.3+) |
| drupal-check | 1.5+ | Drupal 11 support |
| Drupal Coder | 9.x | PHP_CodeSniffer 4.x |

## TDD Workflow

RED-GREEN-REFACTOR cycle:

1. **RED**: Write failing test first
2. **GREEN**: Minimal code to pass
3. **REFACTOR**: Clean up, maintain green

Use `drupal/tdd-workflow.sh` for watch mode.

See `references/tdd-workflow.md` for when TDD makes sense.

## Integration with Other Skills

This skill references but does not duplicate:

| Skill | Use For |
|-------|---------|
| `drupal-testing` | PHPUnit test patterns, assertions |
| `drupal-ai-1.2` | Testing AI agent integrations |
| `drupal-jsonapi` | API testing patterns |

## Templates

Copy templates to your project:

| Template | Purpose |
|----------|---------|
| `templates/drupal/phpunit.xml` | PHPUnit + coverage config |
| `templates/drupal/phpstan.neon` | PHPStan level 8 + Drupal |
| `templates/drupal/phpmd.xml` | PHPMD rulesets |
| `templates/ci/github-drupal.yml` | GitHub Actions workflow |

## Troubleshooting

### DDEV Not Running
```bash
ddev start
```

### PCOV Not Available
Add to `.ddev/config.yaml`:
```yaml
webimage_extra_packages:
  - php${DDEV_PHP_VERSION}-pcov
```
Then: `ddev restart`

### PHPStan Memory Issues
```bash
ddev exec vendor/bin/phpstan analyse --memory-limit=2G
```

### PHPCPD Requires PHP 8.3
Update `.ddev/config.yaml`:
```yaml
php_version: "8.3"
```

## References

- `references/tdd-workflow.md` - When and how to use TDD
- `references/solid-detection.md` - Detailed SOLID principle detection
- `references/dry-detection.md` - PHPCPD configuration and thresholds
- `references/coverage-metrics.md` - PCOV vs Xdebug, interpretation
- `references/tool-comparison.md` - Drupal vs Next.js tools

## Decision Guides

- `decision-guides/test-type-selection.md` - Unit vs Kernel vs Functional
- `decision-guides/quality-audit-checklist.md` - When to run what

## Scripts

### Core
- `scripts/core/detect-environment.sh` - Detect project type, validate DDEV
- `scripts/core/install-tools.sh` - Install quality tools via composer
- `scripts/core/full-audit.sh` - Run all checks, aggregate report
- `scripts/core/report-processor.sh` - Convert JSON to Markdown

### Drupal
- `scripts/drupal/coverage-report.sh` - PHPUnit + PCOV coverage
- `scripts/drupal/solid-check.sh` - PHPStan + PHPMD + drupal-check
- `scripts/drupal/dry-check.sh` - PHPCPD duplication analysis
- `scripts/drupal/tdd-workflow.sh` - TDD watch mode helper
