# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2025-12-06

### Added
- Operation 7: Add Composer Scripts - adds test/quality scripts to `composer.json`
- New triggers: "Add test scripts to composer", "Add composer scripts", "Setup composer quality scripts"
- Scripts include: test, test:unit, test:kernel, test:coverage, quality:phpstan, quality:phpmd, quality:dry, quality:cs, quality:all, quality:fix

### Changed
- Renumbered operations (CI Integration is now Operation 8, Markdown Report is Operation 9)
- Now 9 operations total (was 8)

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
