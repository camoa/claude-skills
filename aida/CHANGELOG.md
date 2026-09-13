# Changelog

All notable changes to this plugin are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [6.0.0-beta.3] - 2026-09-13

Eight gaps from the first pickup of a version 5 project with beta.2 installed.

### Added

- `report`, when nothing owns the directory, names each version 5 folder under the projects base
  whose code path is this directory. The skill then offers the switch before a new project.
- A version 5 pickup runs the framework detector on the code path and writes what it names.
- `set-frameworks <name-or-path> <framework>...` writes the stack by hand when the detector
  named none. The skill asks "What is the stack?" once after a pickup that still lacks it.
- The skill offers `git init` once, interactively, when the check names it as the repair.

### Changed

- `rebuild-registry` with no argument walks the recorded projects base, not only the built-in
  default, so a base chosen elsewhere is rebuilt.
- On exit 1 the skill names each missing field, its producer, and any repair printed beside them.

### Fixed

- A version 5 pickup records the folder's parent as the projects base when none is recorded.
- `report` exits 0 at case 4. Exit 1 collided with the check's "field missing" code.
- `switch` no longer prints "belongs to another project" when the owner is the target itself.
- A version 5 pickup writes `state: active` into the project file, matching its registry row.

## [6.0.0-beta.2] - 2026-09-13

The version 5 disposition pass. Every version 5 file now has a verdict, and twenty-three
behaviours version 6 had dropped without a decision come back in a version 6 form. Two defects
from the first live run are fixed.

### Added

- The session start names the project, the one task in progress, its stage, the run mode when
  autonomous, a per-project `reminders.md`, and the newest note. No session file, no per-prompt
  hook.
- A hook refuses a force push, a hard reset, `git clean`, a recursive delete of root, home or the
  tree, plain `git push`, `git branch -D`, `git checkout .` and `git restore .`. Fail-open,
  `AIDA_ALLOW_DANGEROUS` overrides.
- A worktree per task, always: `task create` makes one on the task's branch at the platform's
  location; every stage action runs there and refuses at exit 79 from anywhere else.
- A distiller reads each closed record from disk after scope, research and design, and names the
  decisions it holds and the gaps. `task save` keeps a mid-stage note.
- Research reads the task's `inputs/` folder, searches the project's own task records for prior
  art, and may run a throwaway spike. Design refuses to start without a research record.
- Review asks where the business logic lives and whether every hunk has a purpose: a call that
  exists, a comment for a reader, a guard for a case that can happen.
- Design reads the recipe for where logic belongs and the non-UI entry point, decides reuse by a
  fixed table, and checks the contract's stated mechanisms against research's hash.
- Research and design record whether the recipe fits the task; review reports a `false`.
- A test green on its first run may lock in existing behaviour with a recorded reason.
- An unattended run may carry a ceiling on dispatches and minutes, recomputed from the records.
- A `surfaces` skill sets up end-to-end and visual regression from the recipe, built against a
  recipe shape the catalog does not ship yet (proposal in dev-guides).
- `skills/tool/references/reading-a-recipe.md` states how a process recipe is read; every reader
  points at it. `scripts/recipe-lint.sh` tells an author what a recipe lacks.
- `tests/prose-lengths-spec.sh` fails when a skill body grows past its recorded count.
- The plugin reads the catalog's shipped blocks: `{dirs}`, `silent_pass` per row, the mutation
  score per tool.
- `switch <path>` picks up a version 5 project folder.

### Changed

- The six stages and `next` are model-invocable, so an autonomous task moves to its next stage
  on its own. `project`, `task`, `tool` and `surfaces` stay user-only.
- Every script derives its own root; nothing depends on `CLAUDE_PLUGIN_ROOT` being set.
- The read and write guards are silent when there is nothing to enforce.
- `detect-framework.sh` prints `php-cli` and `python-cli`, the catalog's names, with evidence.
- The manifest declares the navigator dependency.

### Removed

- `worktreeByDefault` and `memoryHook` from the project record: nothing read them.

## [6.0.0-beta] - 2026-09-13

A rewrite of `ai-dev-assistant`, which this plugin replaces. Nothing from version 5 was
carried without being read, and most of it was not carried.

### Added

- Six stages as skills: scope, research, design, implement, review, completion. Each reads the
  records the stage before it wrote and writes its own, validated against a schema.
- A contract of criteria, written at scope and frozen at design close. Every later stage is
  checked against it, in both directions.
- Tests written before the code by a role that never sees the code, then frozen. A hook refuses a
  write to a frozen test. The build passes or it does not.
- Eight deciding checks per work order, run by script before any judgement. The tool rows come
  from the framework's process recipe in dev-guides.
- One review per task over sixteen checks: the contract, the tools at the final commit, one
  model pass over the whole change, and the surfaces when set up. Mutation testing runs under
  test coverage.
- Completion closes on the verdict or a person's reason, offers a follow-up task per open
  finding, and writes the pull request body from the records. It never calls a remote.
- Every action prints summary lines and paths. Record bodies, tool output and briefs stay in
  files that only a dispatched role reads.

### Removed

- Epics, playbooks, the work-order loop, the fourteen-check review battery, session save,
  maintainer mode, and the guardrail installer. The reasons are in the rewrite's own records.

### Not yet proved

- No skill has run inside a live conversation. This beta exists to run the first two tasks.
