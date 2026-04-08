# Changelog

All notable changes to this project will be documented in this file.

## [1.5.0] - 2026-04-08

### Changed
- **PreCompact hook** — No longer runs grep scans and dumps HTMX/AJAX module listings into compaction. Now outputs instructions for Claude to scan custom modules on demand, reducing compaction bloat.

## [1.4.3] - 2026-03-20

### Changed
- Maintenance audit: verified CLAUDE.md (28 lines, within limit), agent frontmatter clean (no ignored fields)
- Version bump: 1.4.2 → 1.4.3

## [1.4.1] - 2026-03-15

### Added
- **PreCompact hook**: Preserves HTMX migration context (modules using HTMX, AJAX migration candidates, in-progress migrations) before conversation compaction

## [1.4.0] - 2026-03-14

### Fixed
- **Agent frontmatter**: All 3 agents changed from `tools`/`disallowedTools` to `allowed-tools` (current standard)
- **Version alignment**: Skill version now matches plugin version (was 1.2.0 vs 1.3.0)
- **Dev-guides reference**: Replaced direct llms.txt URL with dev-guides-navigator delegation

### Changed
- Pushy descriptions with trigger phrases on all 5 commands and main skill
- Added `allowed-tools` and `user-invocable: true` to skill frontmatter
- Enhanced dev-guides integration section with relevant Drupal topics for HTMX context

## [1.3.0] - 2026-02-16

### Changed
- **Dev-guides integration v2**: Replaced 12-entry keyword→URL mapping table in SKILL.md with lightweight `llms.txt` discovery + topic hints
- **CLAUDE.md**: Added Online Dev-Guides section with `llms.txt` index URL and topic hints for session-wide awareness

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
