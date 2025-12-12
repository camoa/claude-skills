# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2025-12-12

### Added
- **Built-in Reference Documents** - 7 self-contained reference files in `references/`:
  - `tdd-workflow.md` - TDD with Red-Green-Refactor cycle, Drupal test types
  - `solid-drupal.md` - SOLID principles with Drupal-specific examples
  - `dry-patterns.md` - DRY extraction patterns (Service, Trait, Component)
  - `library-first.md` - Library-First and CLI-First development patterns
  - `quality-gates.md` - 4 quality gates enforced at completion
  - `security-checklist.md` - Input validation, output escaping, access control
  - `frontend-standards.md` - BEM, mobile-first, Drupal behaviors, SDC

### Changed
- **BREAKING**: Plugin is now fully self-contained - no hardcoded external guide paths
- **architecture-drafter** (v2.0.0): Now enforces SOLID, Library-First, CLI-First with mandatory checklist
- **architecture-validator** (v2.0.0): Added security checks, blocking vs warning distinction
- **tdd-companion** (v2.0.0): References internal TDD workflow, enforces Gate 2
- **code-pattern-checker** (v2.0.0): References internal docs for SOLID, DRY, Security, Frontend
- **task-completer** (v2.0.0): Runs all 4 quality gates before allowing completion
- **guide-integrator** (v2.0.0): Removed hardcoded guide filenames, uses built-in references first
- **WORKFLOW.md**: Added Enforced Principles section

### Removed
- Hardcoded guide filenames (eca_development_guide.md, drupal_configuration_forms_guide.md, etc.)
- Dependency on user having specific external guide files

### Philosophy
- Principles are now **enforced**, not just documented
- Each phase has blocking checks that prevent progression if not met
- Plugin works out-of-box without external configuration

## [1.3.1] - 2025-12-10

### Fixed
- requirements-gatherer now has Step 7 to handle task creation after user provides task name
- Previously, after requirements gathering, the flow could skip straight to research without creating a task
- Now explicitly: validates task name → asks for description → waits for confirmation → invokes `/research`

### Changed
- SessionStart hook now runs `session-start.sh` script that:
  - Checks registry for existing projects
  - Shows project count and directs user to run `/next`
  - Provides clear entry point for new sessions

## [1.3.0] - 2025-12-06

### Added
- WORKFLOW.md with complete workflow documentation
- Step 0 (Project Selection) - lists projects from registry when `/next` called without argument
- Step 2 (Task Selection) - lists existing tasks and offers to create new (follows `/start` pattern)
- Components by Phase documentation showing all 15 skills and 5 agents
- Component activation flow diagram

### Changed
- `/next` command now follows original guide's `/start` pattern:
  1. Lists projects if none specified
  2. Lists tasks in `in_progress/` after project selected
  3. User picks existing task OR enters new name
- project-orchestrator updated with Step 0 (project selection) and Step 2 (task selection)

## [1.2.0] - 2025-12-06

### Changed
- **BREAKING**: Phases now apply to TASKS, not projects (aligns with drupal_development_guide.md)
- Projects contain requirements (gathered once) + multiple tasks
- Each task independently goes through Research → Architecture → Implementation
- Multiple tasks can be in `in_progress/` simultaneously

### Updated
- project-orchestrator: Now manages tasks, asks "What task do you want to work on?" after requirements
- phase-detector: Detects phase per task file, not per project
- requirements-gatherer: Transitions to task definition after requirements complete
- project_state.md template: Uses "Current Implementation Task" / "Up Next" / "Completed" format
- /next command: Task-aware decision logic

### Added
- Project registry system at `~/.claude/drupal-dev-framework/active_projects.json`
- project-initializer now registers projects on creation
- session-resume lists registered projects for easy selection
- memory-manager maintains registry

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
