# Code Quality Tools

Code quality auditing plugin for Claude Code. Provides TDD, SOLID, and DRY principle checks for Drupal projects via DDEV.

## Installation

```bash
/plugin install code-quality-tools@camoa-skills
```

## What Claude Can Do

Once installed, Claude handles these requests:

| Request | What Claude Does |
|---------|------------------|
| "Setup code quality tools" | Installs tools, copies configs, creates `.reports/` |
| "Install testing tools" | Same as above |
| "Run a code quality audit" | Runs all checks, saves JSON to `.reports/`, shows summary |
| "Check test coverage" | Coverage only, saves `.reports/coverage-report.json` |
| "Find SOLID violations" | PHPStan + PHPMD, saves `.reports/solid-report.json` |
| "Check for duplication" | PHPCPD, saves `.reports/dry-report.json` |
| "Check contentbench_organizations" | Targets specific module |
| "Add test scripts to composer" | Adds quality/test scripts to `composer.json` |
| "Add quality checks to CI" | Creates GitHub Actions workflow |
| "Generate quality report" | Converts JSON to `.reports/audit-report.md` |

## Reports

All audit results are saved to `.reports/` (git-ignored):

```
.reports/
├── coverage-report.json    # Test coverage data
├── solid-report.json       # PHPStan + PHPMD results
├── dry-report.json         # PHPCPD duplication
├── audit-report.json       # Full audit (aggregated)
├── phpstan-raw.json        # Raw PHPStan output
├── phpmd-raw.json          # Raw PHPMD output
└── audit-report.md         # Human-readable report
```

**JSON reports** are always generated for programmatic use.
**Markdown report** is generated on request ("Generate quality report").

## Example Conversations

**Setup tools:**
```
You: Install testing tools for this project
Claude: I'll set up the quality tools...
       - Installed PHPStan, PHPMD, PHPCPD, drupal-check, coder
       - Created phpstan.neon, phpmd.xml, phpunit.xml
       - Created .reports/ directory (added to .gitignore)
```

**Run audit:**
```
You: Run a code quality audit
Claude: Running all checks...

       | Check | Result | Status |
       |-------|--------|--------|
       | Coverage | 72% | WARN |
       | PHPStan | 3 errors | WARN |
       | Duplication | 4.2% | PASS |

       Reports saved to .reports/
       Run "Generate quality report" for detailed Markdown.
```

**Generate report:**
```
You: Generate quality report
Claude: Generated .reports/audit-report.md with:
       - Summary table
       - SOLID violations by severity
       - Duplication clones
       - Prioritized recommendations
```

## Operations

### Setup (One-time)
- Installs composer dev dependencies
- Copies config templates (phpstan.neon, phpmd.xml, phpunit.xml)
- Creates `.reports/` directory
- Recommends PCOV and composer scripts

### Individual Checks
Each check runs independently and saves its own JSON:
- **Coverage**: PHPUnit + PCOV
- **SOLID**: PHPStan + PHPMD + static call detection
- **DRY**: PHPCPD duplication

### Full Audit
Runs all checks, aggregates into `audit-report.json`, shows summary.

### Markdown Report
Converts JSON to human-readable `.reports/audit-report.md`.

## Thresholds

| Metric | Pass | Warning | Fail |
|--------|------|---------|------|
| Coverage | >80% | 70-80% | <70% |
| Duplication | <5% | 5-10% | >10% |
| Complexity | <10 | 10-15 | >15 |
| PHPStan | 0 | 1-10 | >10 |

## Requirements

- **DDEV** - All tools run inside DDEV container
- **Drupal 10.3+** or **11.x**
- **PHP 8.2+** (8.3+ recommended for PHPCPD)

## Directory Structure

```
code-quality-tools/
├── skills/
│   └── code-quality-audit/
│       ├── SKILL.md              # Claude instructions (231 lines)
│       ├── references/           # Detailed docs
│       │   ├── tdd-workflow.md
│       │   ├── solid-detection.md
│       │   ├── dry-detection.md
│       │   ├── composer-scripts.md
│       │   └── json-schemas.md
│       ├── decision-guides/
│       ├── templates/drupal/     # Config files to copy
│       └── templates/ci/         # GitHub Actions
```

## Tools Used

| Tool | Version | Purpose |
|------|---------|---------|
| [phpstan/phpstan](https://phpstan.org/) | 2.x | Static analysis |
| [mglaman/phpstan-drupal](https://github.com/mglaman/phpstan-drupal) | Latest | Drupal rules |
| [phpmd/phpmd](https://phpmd.org/) | Latest | Code smells |
| [systemsdk/phpcpd](https://github.com/systemsdk/phpcpd) | 8.x | Duplication |
| [mglaman/drupal-check](https://github.com/mglaman/drupal-check) | 1.5+ | Deprecations |
| [drupal/coder](https://www.drupal.org/project/coder) | 9.x | Standards |

## Acknowledgments

### Tools
- **[PHPStan](https://phpstan.org/)** by Ondrej Mirtes
- **[phpstan-drupal](https://github.com/mglaman/phpstan-drupal)** by Matt Glaman
- **[PHPMD](https://phpmd.org/)**
- **[PHPCPD](https://github.com/systemsdk/phpcpd)** (systemsdk fork)
- **[PCOV](https://github.com/krakjoe/pcov)** by Joe Watkins

### Methodologies
- **[Sandi Metz](https://sandimetz.com/)** - Rule of Three for DRY
- **[Oliver Davies](https://www.oliverdavies.uk/)** - TDD in Drupal
- **[Matt Glaman](https://mglaman.dev/)** - DI anti-patterns

## License

MIT
