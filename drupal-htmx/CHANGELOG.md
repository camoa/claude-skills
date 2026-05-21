# Changelog

All notable changes to this project will be documented in this file.

## [1.6.0] - 2026-05-21

### Added
- **Effort-adaptive validation depth** — the `htmx-development` skill now scales its work to `${CLAUDE_EFFORT}`: `low` emits HTMX scaffolding and stops, `medium`+ also runs the Validation Checklist inline, `high`/`xhigh`/`max` additionally delegate to `/dev-guides-navigator` for `drupal/forms` + `drupal/js-development`.
- README notes: a `/branch` tip for exploring the HTMX-vs-AJAX decision (fork the session, try each path against the same context), and `skillOverrides` guidance (`user-invocable-only` / `name-only` / `off`) for projects where the skill's proactive "AJAX"/"Drupal" triggers are noise.

### Changed
- **SKILL.md conciseness pass** (246 → 146 body lines, no behavior change). The Quick Start code blocks, the dependent-dropdown / OOB / URL-history code, and the AJAX→HTMX conversion table moved into the existing `references/` files — all of that detail already lived in `references/htmx-implementation.md`, `references/quick-reference.md`, and `references/migration-patterns.md`. SKILL.md keeps the decision tables, pattern-selection matrix, validation checklist, and common-issues table. A "FAPI Quick Map" section was added to `references/migration-patterns.md` to preserve the form-API-level `#ajax` → `Htmx` mappings.

### Fixed
- **Version drift** — `htmx-development` SKILL.md frontmatter was left at `version: 1.4.0` when the plugin bumped to 1.5.0 (the v1.5.0 PreCompact change). Frontmatter is now `1.6.0`, matching `plugin.json`.
- **Agent tool restriction not applied (pre-existing)** — all three agents declared their tool allowlist as `allowed-tools`, but the recognized agent frontmatter field is `tools` (`allowed-tools` is the skill/command field; on an agent it is silently ignored, so the agents actually inherited *all* tools rather than being read-only). The v1.4.0 changelog's "changed from `tools` to `allowed-tools`" was itself the regression. Renamed `allowed-tools:` → `tools:` on `ajax-analyzer`, `htmx-recommender`, and `htmx-validator` — this restores the intended read-only restriction. Agent `version` fields aligned to `1.6.0` while editing.

### Hygiene
- Plugin-root `CLAUDE.md` renamed to `CONVENTIONS.md` (validator ST03 — a plugin-root `CLAUDE.md` is not loaded as end-user context).
- `$schema` added to `plugin.json`.
- PreCompact hook migrated to exec form (`"args": []`).

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
