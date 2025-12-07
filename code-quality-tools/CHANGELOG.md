# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
