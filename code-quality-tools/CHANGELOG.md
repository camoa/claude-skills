# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.7.0] - 2025-12-18

### Added
- **Operation 20: Security Audit (Drupal)** - Comprehensive OWASP + Drupal security scanning
- `scripts/drupal/security-check.sh` - Multi-tool security audit script
- **Modern Security Stack (2024-2025)**:
  - `yousha/php-security-linter` (PHPCS security - actively maintained Dec 2025)
  - `vimeo/psalm` taint analysis (XSS/SQLi dataflow detection)
  - `drupal/security_review` module integration (v3.1.1)
  - Built-in Drush pm:security (Drupal advisories)
  - Built-in Composer audit (package vulnerabilities)
  - Custom Drupal pattern checks (SQL injection, XSS, deserialization)
- Security report with OWASP 2021 category mapping
- 6-layer security audit approach

### Changed
- Replaced abandoned `pheromone/phpcs-security-audit` (2020) with `yousha/php-security-linter` (2025)
- SKILL.md updated with modern security tools and why old tools are deprecated
- Added security audit to Quick Reference

### Documentation
- Added "Why NOT pheromone/phpcs-security-audit?" section
- Documented modern security stack maintenance status
- Added installation and usage examples for security tools

## [1.6.0] - 2025-12-13 (Not fully tested)

### Added
- **SOLID check for Next.js** with madge circular dependency detection
- Operation 19: SOLID Check (Next.js) - circular deps, complexity, large files, TypeScript strict mode
- `scripts/nextjs/solid-check.sh` - Full SOLID principles analysis
- `madge` npm package for circular dependency detection
- Per-principle status reporting (SRP, OCP, LSP, ISP, DIP)

### Changed
- `full-audit.sh` now runs dedicated SOLID check for Next.js projects (not just lint)
- `install-tools.sh` now installs madge for Next.js projects
- Next.js full audit now runs: coverage → SOLID → lint → DRY (4 checks)
- Added `lint_score` to audit summary for Next.js projects
- `report-processor.sh` now includes Lint Analysis section for Next.js
- SOLID violations now use array format compatible with Markdown generator

## [1.5.0] - 2025-12-12

### Added
- **Full Next.js support** with ESLint, Jest, jscpd tooling
- Operation 11: Lint Check (Drupal) - explicit phpcs operation with `--fix` mode
- Operation 12: Rector Fix (Drupal) - auto-fix deprecations with drupal-rector
- Operations 13-18: Next.js operations (Setup, Full Audit, Lint, Coverage, DRY, TDD)
- Next.js scripts: `scripts/nextjs/lint-check.sh`, `coverage-report.sh`, `dry-check.sh`, `tdd-workflow.sh`
- Next.js templates: `eslint.config.js` (ESLint v9 flat config), `jest.config.js`, `jest.setup.js`, `.prettierrc`
- drupal-rector integration for automated deprecation fixing
- jq dependency check in all scripts

### Changed
- **BREAKING**: Report directory standardized to `.reports/` (was `./reports/quality`)
- `full-audit.sh` now auto-routes to Drupal or Next.js scripts based on project type
- `install-tools.sh` now installs Next.js tools for Next.js projects
- `install-tools.sh` now installs drupal-rector for Drupal projects
- `solid-check.sh` no longer references deprecated drupal-check (PHPStan handles deprecations)
- All 18 operations documented in SKILL.md

### Fixed
- Report directory inconsistency across scripts
- Missing drupal-check in install-tools.sh (replaced with drupal-rector)
- solid-check.sh drupal-check references that would fail

## [1.4.0] - 2025-12-06

### Added
- Operation 10: TDD Workflow with RED-GREEN-REFACTOR guidance using `scripts/drupal/tdd-workflow.sh`
- "When to Run What" section (pre-commit vs pre-push vs pre-merge)
- Coverage targets by code type (services 90%, security 95%, API 85%)
- Rule of Three evaluation in DRY check
- JSON schema enforcement for all reports

### Changed
- **Complete SKILL.md rewrite** in imperative voice (instructions for Claude, not documentation)
- All operations now reference their corresponding scripts
- DRY check includes knowledge vs coincidence evaluation
- Test type selection integrated with decision guide reference
- Composer scripts display is now mandatory

### Fixed
- Scripts were not referenced in operations (Gap 8)
- References and decision guides now integrated inline, not just listed
- JSON schema (`schemas/audit-report.schema.json`) now enforced in all report operations

## [1.3.0] - 2025-12-06

### Added
- Coverage driver preference question in Operation 1 (PCOV vs Xdebug)
- "When to Choose Each" and "Performance When Disabled" sections to coverage-metrics.md
- PHPStan 2.x compatibility note in SKILL.md

### Changed
- **BREAKING**: Updated `phpstan.neon` template for PHPStan 2.x compatibility
  - Removed deprecated `memoryLimit`, `checkMissingIterableValueType`, `checkGenericClassInNonGenericObjectType` parameters
  - Removed `includes:` block (extension-installer auto-loads extensions)
- Fixed `phpmd.xml` template - removed XML comment block that caused parser errors
- Fixed PCOV installation instructions - use version-specific package name (e.g., `php8.3-pcov`)

### Fixed
- PHPStan "files included multiple times" error with extension-installer
- PHPMD "Double hyphen within comment" XML parser error
- PCOV installation failure in DDEV (package name format)

## [1.2.0] - 2025-12-06

### Added
- Operation 7: Add Composer Scripts - adds test/quality scripts to `composer.json`
- New triggers: "Add test scripts to composer", "Add composer scripts", "Setup composer quality scripts"
- Scripts include: test, test:unit, test:kernel, test:coverage, quality:phpstan, quality:phpmd, quality:dry, quality:cs, quality:all, quality:fix

### Changed
- Renumbered operations (CI Integration is now Operation 8, Markdown Report is Operation 9)
- Now 9 operations total (was 8)
- **BREAKING**: Replaced deprecated `mglaman/drupal-check` with `phpstan/phpstan-deprecation-rules`
- Updated all references, scripts, and documentation to use phpstan-deprecation-rules
- Install script now installs 5 tools instead of 6

## [1.1.0] - 2025-12-06

### Added
- `.reports/` directory for all JSON output (git-ignored)
- Operation 8: Generate Markdown Report from JSON
- New reference: `composer-scripts.md` with recommended scripts
- New reference: `json-schemas.md` documenting report structures
- More trigger phrases ("Install testing tools", etc.)

### Changed
- SKILL.md rewritten as Claude instructions (not documentation)
- Each operation now saves JSON reports independently
- Console shows summary, detailed reports saved to files
- Reduced SKILL.md from 612 to 231 lines (moved content to references)

### Fixed
- Skill now properly guides Claude through each operation step-by-step
- Clear separation between setup, individual checks, and full audit

## [1.0.0] - 2025-12-06

### Added
- Initial release of code-quality-audit skill
- Core scripts: detect-environment, install-tools, full-audit, report-processor
- Drupal scripts: coverage-report, solid-check, dry-check, tdd-workflow
- JSON report schema with Markdown conversion
- Templates: phpunit.xml, phpstan.neon, phpmd.xml, GitHub Actions workflow
- References: TDD workflow, SOLID detection, DRY detection, coverage metrics
- Decision guides: test type selection, quality audit checklist
- DDEV integration for all PHP tools
- Environment variable support for threshold customization
