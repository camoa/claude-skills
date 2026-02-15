# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.5.0] - 2026-02-15

### Added
- Online dev-guides integration for Drupal domain knowledge (SOLID, DRY, security, testing, TDD)
  - SKILL.md: 45-entry keyword→URL mapping table for WebFetch from https://camoa.github.io/dev-guides/
  - Topics: SOLID principles (19 guides), DRY principles (16 guides), Security (20 guides), Testing (11 guides), TDD (25 guides), JS testing/security, CI/CD
- Security debate enrichment: Step 3b fetches relevant online security guides (OWASP, XSS, SQLi, CSRF, access control) before spawning debate team
- "See also" pointers in solid-detection.md, dry-detection.md, drupal-security.md, tdd-workflow.md, coverage-metrics.md, test-type-selection.md, quality-audit-checklist.md linking to online guides

### Changed
- Security debate spawn prompts now include `security-context.md` path for enriched Drupal context

---

## [2.4.0] - 2026-02-11

### Added
- `/code-quality:security-debate` command — multi-perspective security debate using agent teams
  - Defender agent validates findings, identifies false positives and exploitability
  - Red Team agent constructs attack scenarios, finds gaps audit missed
  - Compliance Checker agent maps to OWASP Top 10 / CWE standards with coverage matrix
  - Cross-challenge debate phase resolves severity disagreements
  - Synthesized output: `.reports/security-debate.md`
- Agent team command convention in CLAUDE.md and command-conventions.md

### Fixed
- `commands/security.md` — corrected report filename from `.reports/security.json` to `.reports/security-report.json`
- `commands/security.md` — added discoverability link to `/code-quality:security-debate`

---

## [2.3.0] - 2026-02-09

### Added
- `model: sonnet` routing on code-quality-audit skill for cost optimization
- `CLAUDE.md` plugin conventions file
- `.claude/rules/skill-conventions.md` for path-scoped skill standards
- `.claude/rules/command-conventions.md` for path-scoped command standards

### Changed
- Aligned with camoa-skills plugin standards (model routing, rules, conventions)
- Version bumped to 2.3.0 across plugin.json, marketplace.json, SKILL.md

---

## [2.2.0] - 2026-01-15

### Added
- **8 Slash Commands** for direct operation access
  - `/code-quality:setup` - Install and configure tools
  - `/code-quality:audit` - Run full audit (all 22 operations)
  - `/code-quality:coverage` - Test coverage analysis
  - `/code-quality:security` - Security scan (10 Drupal layers, 7 Next.js layers)
  - `/code-quality:lint` - Code standards check
  - `/code-quality:solid` - SOLID principles check
  - `/code-quality:dry` - Code duplication detection
  - `/code-quality:tdd` - TDD workflow (test watcher mode)
- **Project Auto-Detection** - Automatically detects Drupal vs Next.js projects
- **Intelligent Error Handling** - Contextual error messages with recovery guidance
- **Troubleshooting Guide** - Common issues and solutions (`references/troubleshooting.md`)
- **marketplace.json** - Enable marketplace distribution

### Changed
- **SKILL.md** - Enhanced description for better auto-discovery
- **SKILL.md** - Added "Quick Commands" section referencing slash commands
- **SKILL.md** - Version updated to 2.2.0
- **README.md** - Added "Quick Start" section with installation and commands table
- **plugin.json** - Version updated to 2.2.0, registered commands directory

### Fixed
- **Discoverability Issue** - Users can now invoke operations via commands without relying on skill auto-discovery
- **Setup Clarity** - Clear installation instructions in README Quick Start section

### Technical
- New scripts: `detect-project.sh`, `error-handler.sh`
- Commands registered in `plugin.json`
- All changes non-breaking - v2.1.0 workflows continue unchanged

## [2.1.0] - 2025-12-19

### Added
- **Operation 22: DAST Tools (Optional)** - Dynamic Application Security Testing
- `references/operations/dast-tools.md` - Complete DAST documentation (585 lines)
- **OWASP ZAP** integration - Full DAST scanner for pre-production
  - Active scanning (SQL injection, XSS, command injection)
  - Passive scanning (security headers, sensitive data)
  - Spider/crawler for endpoint discovery
  - Authentication testing support
- **Nuclei** integration - Template-based CVE scanning
  - 1000+ vulnerability templates
  - CVE detection (2015-2025)
  - Misconfiguration detection
  - Exposed panel detection
- CI/CD integration examples (GitHub Actions, GitLab CI)
- Pre-release security checklist script
- Docker-based installation instructions

### Documentation
- SAST vs DAST comparison guide
- When to use DAST (staging, pre-production, security audits)
- Installation guides (Docker, direct install, package managers)
- Usage examples for both tools
- Report interpretation guidelines
- Best practices and troubleshooting

## [2.0.0] - 2025-12-19

### Major Refactoring
- **Progressive Disclosure**: SKILL.md reduced from 632 to 234 lines (63% reduction)
- Created 9 reference files with comprehensive documentation
- Achieved plugin-creation-tools compliance (16/16 criteria)
- Operations reorganized by stack (Drupal: 1-8, 10-12, 20; Next.js: 13-19, 21)

### Added - Phase 1: Cross-Stack Security Tools
- **Semgrep SAST** - Multi-language static analysis
  - 20,000+ security rules for PHP, React, JS, TS
  - OWASP Top 10 coverage
  - Auto-updating rule sets
- **Trivy Scanner** - Comprehensive vulnerability scanner
  - Package vulnerabilities (npm + Composer)
  - Container/IaC misconfigurations
  - Secret detection (800+ patterns)
- **Gitleaks** - Dedicated secret detection
  - 800+ secret patterns
  - Entropy analysis for custom secrets
  - No git required (`--no-git` flag)

### Added - Phase 2: Enhancement Tools
- **Roave Security Advisories** (Drupal)
  - Composer prevention layer
  - Blocks installation of vulnerable packages
  - Integrated into `install-tools.sh` and `security-check.sh`
- **Socket CLI** (Next.js)
  - Supply chain attack detection
  - Malicious package detection
  - Install script analysis
  - Integrated into `install-tools.sh` and `security-check.sh`

### Changed
- **Security Coverage Expanded**:
  - Drupal: 40% → 90% (6 → 10 security layers)
  - Next.js: 0% → 85% (0 → 7 security layers, NEW!)
- **Drupal Security Layers** (10 total):
  1. Drush pm:security
  2. Composer audit
  3. yousha/php-security-linter
  4. Psalm taint analysis
  5. Custom Drupal patterns
  6. Security Review module (optional)
  7. Semgrep SAST
  8. Trivy scanner
  9. Gitleaks
  10. Roave Security Advisories
- **Next.js Security Layers** (7 total):
  1. npm audit
  2. ESLint security plugins
  3. Semgrep SAST
  4. Trivy scanner
  5. Gitleaks
  6. Custom React/Next.js patterns
  7. Socket CLI
- Updated `install-tools.sh`:
  - Drupal: 13 steps (added Roave)
  - Next.js: 11 steps (added Socket CLI)
- Updated security-check.sh scripts with new tools
- plugin.json and marketplace.json descriptions updated

### Documentation
- Created `references/operations/` directory structure
- Split into operation-specific files:
  - drupal-setup.md, drupal-audits.md, drupal-security.md, drupal-tdd.md
  - nextjs-setup.md, nextjs-audits.md, nextjs-security.md, nextjs-tdd.md
- Added `references/scope-targeting.md` (env vars + cd approach)
- All reference files include TOC and cross-references
- Updated SKILL.md with progressive disclosure structure

## [1.8.0] - 2025-12-18

### Added
- **Cross-Stack Security Tools** for both Drupal and Next.js:
  - Semgrep SAST (20,000+ security rules)
  - Trivy scanner (dependency/container/secret scanner)
  - Gitleaks (secret detection with 800+ patterns)
- Integration into security-check.sh for both stacks
- Installation via install-tools.sh

### Documentation
- Added cross-stack tools to SKILL.md
- Updated security documentation for both stacks

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
