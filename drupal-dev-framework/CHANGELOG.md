# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.5] - 2025-12-06

### Added
- Project registry system at `~/.claude/drupal-dev-framework/active_projects.json`
- project-initializer now registers projects on creation
- session-resume lists registered projects for easy selection
- project-orchestrator uses registry for project discovery
- memory-manager maintains registry (updates lastAccessed, phase, status)

### Changed
- Projects are now tracked centrally for easier resumption across sessions

## [1.1.4] - 2025-12-06

### Added
- Project type question in requirements-gatherer (new module vs existing vs core issue)
- Auto-trigger rules in guide-integrator for automatic guide loading based on keywords
- Architecture principles validation (Library-First, CLI-First, SOLID) in architecture-validator
- Step 10 in project-initializer to direct users to `/next` command

### Fixed
- `/new` command now directs to `/next` instead of listing manual commands
- Aligned plugin with drupal_development_guide.md requirements

## [1.1.3] - 2025-12-06

### Fixed
- Removed assumption that projects are always modules
- Removed redundant component arrays, rely on auto-discovery
- Added skills arrays to marketplace.json and plugin.json for discovery
- Aligned manifests with official plugin schema

## [1.1.2] - 2025-12-06

### Fixed
- Added skills/agents/commands arrays for plugin discovery

## [1.1.1] - 2025-12-06

### Fixed
- Aligned manifests with official plugin schema

## [1.1.0] - 2025-12-06

### Added
- Version numbers to all SKILL.md frontmatter
- Enhanced skill descriptions

## [1.0.0] - 2025-12-06

### Added
- Initial release of drupal-dev-framework plugin
- 15 skills for 3-phase development workflow
- 9 slash commands for project management
- 5 agents for specialized tasks
- Memory management system with project_state.md
- TDD companion and code pattern checker
- Integration with superpowers and drupal-dev-tools
