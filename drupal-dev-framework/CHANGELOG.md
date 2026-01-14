# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.0.0-beta.1] - 2026-01-14

### Added
- **NEW: task-folder-migrator skill (v3.0.0)** - Migrate v2.x single-file tasks to v3.0.0 folder structure
  - Scans for old `.md` files
  - Creates folder structure with separate phase files
  - Preserves all content with automatic backups
  - Idempotent and safe to run multiple times
- **NEW: Folder-based task structure** - Each task gets own folder with organized files:
  - `task.md` - Lightweight tracker with links, status, acceptance criteria
  - `research.md` - Phase 1 research findings
  - `architecture.md` - Phase 2 architecture design
  - `implementation.md` - Phase 3 implementation notes
- **NEW: MIGRATION.md guide** - Complete migration guide for v2.x → v3.0.0
  - Step-by-step migration instructions
  - Troubleshooting section
  - Rollback procedures
  - FAQ for common questions

### Changed
- **BREAKING**: Task structure changed from single file to folder-based organization
- **memory-manager (v3.0.0)** - Updated to scan directories instead of files
  - Detects old v2.x format and warns users
  - Supports both v2.x (backward compat) and v3.0.0 structures
- **phase-detector (v3.0.0)** - Updated to read from folder structure
  - Checks for phase files (research.md, architecture.md, implementation.md)
  - Backward compatible with v2.x single files
- **task-context-loader (v3.0.0)** - Updated to load phase files separately
  - Loads task.md for main info
  - Loads research.md, architecture.md, implementation.md as needed
  - Full context loading from all phase files
- **task-completer (v1.1.0)** - Updated to move entire directory instead of single file
- **/research command** - Now writes to `research.md` instead of section in single file
  - Creates task folder structure
  - Updates task.md with phase status
- **/design command** - Now writes to `architecture.md` instead of section
  - Updates task.md to mark Phase 2 in progress
- **/implement command** - Now writes to `implementation.md` instead of section
  - Updates task.md to mark Phase 3 in progress
- **/complete command** - Now moves entire task directory to completed/
- **README.md** - Updated with v3.0.0 structure, migration instructions, benefits

### Migration Path

Upgrading from v2.x:
1. Backup projects before upgrading
2. Install v3.0.0-beta.1
3. Run `/drupal-dev-framework:migrate-tasks` for each project
4. Verify migration results
5. Delete `.bak` files when confident

See [MIGRATION.md](./MIGRATION.md) for detailed guide.

### Benefits

**Why This Change:**
- ✅ Separates content by phase
- ✅ Keeps files small and focused (no more huge single files)
- ✅ Easy to navigate (max 4 files per task)
- ✅ Simple flat structure (no nested folders)
- ✅ Better organization and maintainability

**What Stays The Same:**
- All 15 skills still available
- All 9 commands still work
- All 5 agents unchanged (path updates only)
- All 8 reference documents preserved
- Same 3-phase workflow (Research → Architecture → Implementation)

### Breaking Changes

- v2.x single-file tasks (`task.md`) must be migrated to folder structure (`task/`)
- Migration tool provided: `/drupal-dev-framework:migrate-tasks`
- Backward compatibility: Updated skills detect old format and warn users
- v2.x support: Security fixes only after v3.0.0 stable release

## [2.1.0] - 2025-12-18

### Added
- **Gate 5: Code Purposefulness** - New reference document `purposeful-code.md` with:
  - Every-Line-Has-a-Purpose principle
  - Intentional complexity vs accidental complexity
  - Code archaeology and dead code detection
  - Redundancy elimination patterns
  - Real-world examples of purposeless code
- **Expanded Security Checklist** - Enhanced `security-checklist.md` with:
  - Detailed input validation patterns
  - Output escaping context-specific examples
  - Access control implementation strategies
  - CSRF protection guidelines
  - File upload security
  - SQL injection prevention
- **Quality Gates Update** - `quality-gates.md` now includes Gate 5 as 5th enforcement checkpoint
- **Architecture Validator Enhancement** - Updated to check for purposeful code patterns
- **Restored `/new` command** - Dedicated command for starting new projects (removed in 2.0.0)
  - Clearer separation: `/new` for new projects, `/next` for continuing work
  - Interactive mode (no arguments) or direct mode (with project name)
  - Automatically registers project and gathers requirements

### Changed
- Quality gate count increased from 4 to 5
- Security checks now more comprehensive with real-world attack vectors
- `/next` command now focused on continuing existing projects/tasks

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
- **`/new` command** - consolidated into `/next` (single entry point)
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
