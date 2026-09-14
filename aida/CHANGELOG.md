# Changelog

All notable changes to this plugin are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Live-run rows 43 to 53.

### Added
- Every stage's closing action commits the task folder, with the stage's own result as the
  reason: scope's `distill`, research's coverage `check`, design `close`, implement `finish`,
  review `close`. Mid-stage writes stay uncommitted until then, and each skill says so.
- `task environment up` runs the recipe's `## Preconditions` line after it writes the
  `## Files` and before it commits anything. A non-zero exit removes what that run wrote,
  commits nothing, and exits 3 with the script's message. `show` lists the line it will run.
- `project create` asks once where playbooks come from, per framework: a catalog set or a
  local folder. `subscribe-playbook` proposes the framework from the project's declared ones
  and the set id from the catalog when either is not given.
- The surfaces skill commits `project.json` after `install` and `decline`.

### Changed
- The session-start line says `playbook file:` and the pick-up line names `/aida:next`.
- The report reads an absent `runMode` as `interactive`, the value every other reader prints.
- The catalog identifier tests a store path before answering with it, and answers
  `fetch-failed` when the file is absent.

### Fixed
- A never-saved task blocks compaction only once it holds a version 6 record, so a repaired
  version 5 task with no version 6 run compacts freely.
- `task create` step 4 stops only on the refused worktree entry.
- A recipe step that reads standard input no longer swallows the steps after it. The step loop
  fed its lines through the loop's own stdin, and a command such as `ddev composer require`
  read them, so the install ended early with no error. Every step now runs with stdin closed,
  and so does every `## Tokens` command and check row. Reported by the catalog side while
  consuming the setup recipes.

## [6.0.0-beta.9] - 2026-09-14

Rows 33 to 42 of the live run, the seven items the owner reopened on 2026-09-13, and the
catalog's answers to three asks. The worktree moves out of the repository.

### Added
- Narrowing. A surface declares the paths that render it, `register --path <glob>` repeatable,
  and `--critical`. Review runs a surface when the diff touched one of its paths, when it is
  critical, or when it declares none; the rest are recorded as not run and named. The ids
  reach the suite through the `{surfaces}` token; a recipe row without the token runs the
  whole set and says so.
- `task environment <id> show|up|down`: a task's worktree gets its own running site from the
  catalog's `worktree-environment` recipe. `up` writes and commits the recipe's files, runs
  its `## Tokens`, the bring-up before `## Address`, the address command whose `key: value`
  lines become tokens and are kept in the record, then the rest, then each enabled surfaces
  kind's setup install in the tree. The task skill offers it once after the worktree is made,
  and at `start` for a task opened later. Review and `baseline` read the recorded address.
- `task prune`: lists the worktrees of complete tasks and removes them one yes at a time,
  tearing the site down first, deleting only a merged branch, never forcing. Autonomous lists
  and stops. Completion's after-merge line names it.
- The design critique: before the close, three fresh `design-critic` readers, one lens each
  (contract, reuse, buildability), write findings a person answers one by one. Autonomous
  records and goes on. The close names the files and the count and never blocks on them.
- `hooks/pre-compact.sh`: a manual `/compact` with task work newer than the last `task save`
  is refused with the save command; an automatic compaction leaves a marker session start
  names once. `task save` with no text records `savedAt`.
- `review-actions.sh audit`: one line per check with its verdict and how it arose (ran, read,
  could-not-look, off), one per surface, and a counts line. The skill shows it before the
  verdict word; completion's body carries it above the verdict.
- `tests/vocabulary.txt` and `tests/vocabulary-spec.sh`: the controlled vocabulary and the
  check that flags every banned synonym in shipped prose. `docs/glossary.md` is now
  `docs/vocabulary.md`, written.
- The playbook loader reads a set's `plays.json` through the navigator's `playbook` mode, so
  `rationale` and `when` reach the roles; `project subscribe-playbook` refuses a topic that is
  not a playbook.
- `templates/process-recipe-setup.md`, the shape a setup recipe follows; `tests/execute-bits-spec.sh`.

### Changed
- The worktree is a sibling of the checkout, `<parent>/<repo>-<task id>`, because a nested
  one is handed to the parent DDEV project and a tear-down there deleted the main site. A
  new task id is lowercase letters, digits and hyphens, since the folder name becomes a
  hostname label. The skills print `cd <path> && claude`.
- The end to end and visual regression setup is offered, taken and declined one kind at a
  time; `decline <kind>` writes `surfaces.<kind>.declined`.
- `surfaces register` commits the surface file, so `baseline` finds a clean tree; `show`
  exits 3 on a recipe with no install block; `read` prints each surface's paths and critical
  mark; the project record and the surface file are written pretty.
- `catalog-identifier` has a 30-turn budget, since a cold recipe lookup takes 16 tool uses.
- One recipe run loop, file writer and commit helper in `scripts/lib/recipes.sh`, called by the
  task, surfaces and tool scripts; `resolve_recipe` and `require_person` live there too.

### Fixed
- Rows 33 and 34: scope named the decline field it reads; three scripts lacked their execute bit.
- The library reset a caller's `RECIPE` at load, which had silently broken `recipe-lint.sh`.
- The compaction hook's worktree match never matched; a task with several in progress now
  names the marker of the one holding the session's directory.

## [6.0.0-beta.8] - 2026-09-13

Rows 31 and 32 of the live run: the end to end and visual regression setup is offered where a
page is first named, and the setup lands in the tree the task runs in.

### Added
- Row 31: scope offers the surfaces setup once, when the goal names a page, a form, a screen or
  a journey, neither kind is on and the project has not declined. Three answers: yes invokes the
  `surfaces` skill and scope reads the project again; "not this task" records nothing; no
  records the decline that every later offer reads. Design makes the same offer once per task
  when a work order first names a page. Review's offer stays. Autonomous runs get no offer.
- `surfaces` `install` commits what it wrote, with the reason in the message, the way `baseline`
  does, and refuses a dirty tree at 61 before writing anything.

### Fixed
- Row 32: `surfaces` wrote the harness, the surface file and the baseline commit at the code
  path while every stage action runs from the task's worktree, so review ran a harness the tree
  did not hold. Setup now runs in the tree it is called from: the task's worktree when inside
  one, the code path otherwise. `registryPath` is stored relative, `.visual-review/surfaces.json`,
  and every reader joins it to the tree it runs in.
- `task_worktree` writes `.claude/worktrees/` into the repository's local exclude file once,
  before making a tree. Git listed the nested worktree as an untracked folder, so every
  clean-tree check refused the code path once any task existed.

### Changed
- The `surfaces` skill drops `disable-model-invocation`, the way `task` did in beta.5, so a
  stage's offer can invoke it. The guards are in the script: `--enable` and `decline` refuse
  unattended, and the skill waits for a plain yes before `install`.

## [6.0.0-beta.7] - 2026-09-13

Rows 25 to 30 of the live run: a task picked up from version 5 with scope and research done.
The old work is carried forward now, and nothing overwrites it.

### Fixed
- Row 25: `render` overwrote the version 5 `alignment.md`, which lives under the name version 6
  renders to. `repair` now keeps `alignment.md`, `research.md`, `architecture.md` and `research/`
  under `.v5` names, prints one `KEPT:` line each, and refuses when a `.v5` name exists.
- Row 30: `next` prints `legacyStages`, the stages version 5 finished that version 6 holds no
  record of, and offers to run the first one. A yes invokes that stage; autonomous invokes it
  without asking. The producer runs again; there is no converter.
- Row 26: scope reads `alignment.v5.md` as the person's earlier words on a first run, keeps the
  criteria in order so the ids line up, shows what changed, and asks the usual approval.
  Research does the same with `research.v5.md` and `research.v5/`, recording a finding that
  still holds under `--search version-5-<file>` and searching only for what they do not cover.
- Row 27: `processRecipes` is gone; nothing wrote it and nothing read it. After a pickup, the
  project skill offers to rewrite a version 5 task rule in the code repository's `CLAUDE.md`, and
  `task-rule`, `task-rule-remove` and `uninstall` match version 5's markers.
- Row 28: scope names `surfaces.e2e.enabled`, the field that exists, not `e2e.enabled`.
- Row 29: not a defect; the record and the rendered page hold one verify line per criterion.

## [6.0.0-beta.6] - 2026-09-13

Playbooks: the rules a person wants followed, put in front of every role that writes or judges
code. Version 5 never put a play in front of the model, and its adherence gate checked citations
of plays the model had never seen. The acceptance test row: subscribe the demo project to
`drupal/best-practices/camoa`, and add one project play that contradicts the obvious
implementation. Then show the reviewer's finding naming it.

### Added
- The `playbooks` skill: `list` prints one line per play from the three sources; `capture`
  appends one play to the project's file and commits.
- The `playbook-loader` agent reads each subscribed catalog set and writes
  `records/playbooks-catalog.json`, its only write.
- Research runs `playbooks load` once at its start. The record marks each source `loaded`,
  `absent`, `empty` or `unreachable`.
- Design reads `records/playbooks.md` before the work orders, and an order's `reasoning` names
  the play that decided its shape.
- The four implementation briefs carry `playbooksPath`; the reviewer's `practices` lens reports
  one finding per play the diff contradicts.
- Review's check 16 reads `unknown` when the record is absent, or nothing loaded while a
  subscription or a playbook file exists.
- Completion offers each task note as a play, one yes or no per note; the record holds
  `capturesOffered` and `capturesSkipped`. Autonomous offers nothing and says so.
- The project skill's `subscribe-playbook` and `unsubscribe-playbook` write a set id under a
  declared framework, fetching nothing.
- The session-start hook prints one `Playbooks:` line per session. Nothing runs per prompt.
- `docs/playbooks.md`.

## [6.0.0-beta.5] - 2026-09-13

Rows of the first live run from the first task on a picked-up project.

### Fixed
- Row 14: the `V5:` offer never fired on a fresh install, because no version 6 base was recorded
  yet. With none recorded, the report now scans the base that version 5 recorded in
  `~/.claude/ai-dev-assistant/active_projects.json`. Nothing is written.
- Row 15: `read-projects-base` ends its line with a newline.
- Row 21: after a version 5 pickup, `switch` prints one `LEGACY:` line per task still under
  `implementation_process/in_progress/`, and the skill names `/aida:next` as the step that moves
  the one the person picks.
- Row 16: a legacy task never reaches "Enter the tree"; the move comes first.
- Row 17: `LEGACY_COMPLETE:` listed every stage sub-folder of a completed version 5 task as a
  task. A folder is a task only when it holds `task.md`, one level down as a child of its epic.
  `open <name>` follows the same rule and never finds a stage sub-folder by name.
- Row 18: the report's `CASE:` and `RUN_MODE:` lines are named in the skill.
- Row 20: every open task line carries `stage`, the first stage whose close record is absent.
  The rule lives once, in `task_stage` in `scripts/lib/task-helpers.sh`; the session-start hook
  reads the field instead of deriving it, and `task save` points at the same field.
- Row 22: a task holding a version 5 `alignment.md` and no `alignment.json` reads
  `legacyRecords: true`, and the skill says the old contract and research are there to read while
  the stage writes its own record.
- Row 23: `task` is model-invocable. The flag made the person type `/aida:task create` after
  saying yes to `next`'s offer, and refused `repair`. The guards stay as prose: `create` runs only
  on the person's ask or yes, and `set-run-mode` only when a person explicitly asks.
- Row 24: the split recommendation after research, never built. A `split-advisor` agent reads the
  contract and the findings once after research closes and writes one recommendation, flat or
  split with the children and the criteria each takes. `split-read` checks every criterion is
  claimed once. Research shows it and asks; a yes runs the task skill's `split` as recommended.
  Autonomous records it and stays flat. The advisor, and a person, decide; no count gates it.
- Row 19: `next` said that moving a version 5 task into `tasks/` "is not built yet". The live run
  concluded it had to delete and recreate the task. `next` now runs the task skill's `repair`
  itself on the legacy task it loads, so a person never types it. `task` no longer calls `next`
  unbuilt.

## [6.0.0-beta.4] - 2026-09-13

Rows 5 to 13 of the first live run, all from picking up a version 5 project. The pickup now ends
usable, or with the one step left named.

### Added

- A version 5 pickup runs the framework detector on the code path and writes what it names.
- `set-frameworks <name-or-path> <framework>...` writes the stack by hand when the detector
  named none. The skill asks "What is the stack?" once after a pickup that still lacks it.
- `git-init <name-or-path>` makes a picked-up folder a repository, commits what is there, and
  runs the check. The skill offers it once, interactively, when the check names the repair.

### Changed

- On exit 1 the skill names each missing field, its producer, and any repair printed beside them.
- One writer for a new project file, and one helper that makes a project folder a repository.
  `create`, the version 5 pickup and `git-init` call them, so the initial shape lives once.

### Fixed

- A version 5 pickup records the folder's parent as the projects base when none is recorded.
- `report` exits 0 at case 4. Exit 1 collided with the check's "field missing" code.
- `switch` no longer prints "belongs to another project" when the owner is the target itself.
- A version 5 pickup writes the same initial file as `create`, `state: active` included, so the
  check names only what is missing in fact.
- The skill names the two files a version 5 pickup writes, `project.json` and
  `records/check-project.json`, and the undo: `unregister` plus removing those two.
- A write on a folder that is not a repository yet says "not committed" and prints no git error.

## [6.0.0-beta.3] - 2026-09-13

Two gaps from the first pickup of a version 5 project with beta.2 installed.

### Added

- `report`, when nothing owns the directory, names each version 5 folder under the projects base
  whose code path is this directory. The skill then offers the switch before a new project.

### Changed

- `rebuild-registry` with no argument walks the recorded projects base, not only the built-in
  default, so a base chosen elsewhere is rebuilt.

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
