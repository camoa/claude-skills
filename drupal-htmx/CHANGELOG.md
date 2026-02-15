# Changelog

All notable changes to this project will be documented in this file.

## [1.2.0] - 2026-02-15

### Added
- Online dev-guides integration for Drupal domain context
  - SKILL.md: 12-entry keyword→URL mapping table for WebFetch from https://camoa.github.io/dev-guides/
  - Topics: AJAX architecture, JS behaviors, forms (#states, multi-step, alter, security), routing, render API
- "See also" pointer in ajax-reference.md linking to online AJAX architecture and JS integration guides

---

## [1.1.0] - 2026-02-09

### Added
- **Tool restrictions**: All 3 agents have `disallowedTools` for read-only enforcement
- **Version fields**: Added `version` to all agents and skill
- **Model routing**: htmx-development skill set to `model: sonnet`
- **CLAUDE.md**: Plugin conventions at plugin root
- **Path-scoped rules**: `.claude/rules/` with agent, skill, and command conventions

## [1.0.0] - 2025-12-31

### Added

- Initial release of drupal-htmx plugin
- **Skill**: `htmx-development` with decision-focused guidance
- **Agents**:
  - `ajax-analyzer` - Scans modules for AJAX patterns
  - `htmx-recommender` - Recommends HTMX patterns for use cases
  - `htmx-validator` - Validates HTMX implementations
- **Commands**:
  - `/htmx` - Status and next actions
  - `/htmx-analyze` - AJAX pattern analysis
  - `/htmx-migrate` - Guided migration
  - `/htmx-pattern` - Pattern recommendation
  - `/htmx-validate` - Implementation validation
- **References**:
  - `quick-reference.md` - Command equivalents, method tables
  - `htmx-implementation.md` - Htmx class API reference
  - `migration-patterns.md` - 7 detailed migration patterns
  - `ajax-reference.md` - AJAX commands reference
