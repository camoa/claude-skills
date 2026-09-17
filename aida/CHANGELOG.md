# Changelog

All notable changes to this plugin are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [6.0.0-beta.15] - 2026-09-17

Live-run rows 83 and 84, the implement stage's review reference on beta.14.

### Changed
- The review step reads the `test-execution` and `review` recipe paths from the records
  `preconditions` wrote (`frameworks[].recipePath`, `checkRecipes[].path`), the way the build
  step does, instead of dispatching the identifier again; a fresh lookup could only agree with
  the record or be refused at `fix-record` (exit 73). (row 83)
- The interface question, asked only when the interface check read unknown, shows the declared
  interface and the builder's record before asking whether they agree; a person cannot judge
  two texts they may not read. (row 84)

## [6.0.0-beta.14] - 2026-09-17

Live-run rows 75 to 82 (the design stage on beta.12, and a resumed build after a merge); row 81 corrected row 78 and asked nothing.

### Added
- `design-actions.sh remove-done-when --text` and `remove-owned-file --path`, the removals the
  sizing rules need beside `remove-test`. Removing a task-folder file from a `record` order
  re-runs the proof inference; the last owned file is refused, since the schema requires one.
  (row 76)
- `design-actions.sh read-guide <task> --path <path> [--name <name>]` records each guide body
  design opens (path, sha256, date, research's name) in `design-guides-read.json`, one entry
  per path. `read` and `start` print the count, and a resumed run lists each entry as
  `changed`, `unchanged` or `missing`, so it reads only what changed and what research named
  that no entry records. The design check refuses a malformed record. (row 77)
- `dispose --verdict decline --why <text>`: a candidate design weighed and set aside gets a
  recorded verdict, in both run modes, with no cost dimension. The confirmer reads it. The
  other half of row 79, a disposition for every exported entity of the same kind as a unit,
  is a catalog ask. (row 79)

### Changed
- A malformed distiller sidecar (`distill` exit 4, and the split advisor's read) is set aside
  beside itself with a UTC timestamp, so the next dispatch writes fresh and a reader can see what
  was wrong. The four skill passages give exit 4 the recovery exit 2 has: dispatch a fresh agent
  with the rule it broke quoted, run the call again, and stop for the person on a second exit 4.
  The distiller's own file names the refusal beside its rule. (row 80)
- A resumed implement `start` drops a frozen order the live design no longer holds when it
  never started, prints `removed: <ids>`, and re-derives the snapshot hash; a started one halts
  with a drift reason saying the design removed it, which `restart` answers by moving its
  records aside and dropping it. The step router names that restart before the survivor's
  tests, because the removed order's frozen-test record still guards the files the survivor
  absorbed. (row 82)
- Every stage skill names the worktree refusal: exit 79 means the task builds in its worktree
  and this window is elsewhere; enter the tree with `EnterWorktree`, then run the call again.
  The tool is granted in each stage skill. (row 75)
- `merge` appends the folded order's `interface` and `reasoning` to the survivor's under a
  `From <id>:` line and prints what it carried; the survivor's title is kept and said. It had
  appended them space-joined and silently. (row 78)
- `dispose` appends one paragraph per call to the order's `reasoning` instead of replacing
  it, so several candidates on one unit keep every verdict, and the text `create` or `merge`
  wrote survives. (row 79)

## [6.0.0-beta.13] - 2026-09-17

### Added
- `research-actions.sh serve <task> --search <slug> --index <n> --criteria-served <ids>` and
  `drop <task> --search <slug> --index <n>` repair one recorded finding: reattach it to the
  criteria it serves, or remove it (and its file when none is left). `record` appends and had
  no repair path, so the skill's "record it again" and "can stand as recorded" sentences could
  not be followed: the check counts every orphan finding (exit 5) and design refuses to start
  on it. The skill now closes research at exit 0 only, repairs one entry per check run since
  `drop` moves later indexes down, and stops on an unreadable file for a person to decide.

### Changed
- A record order's diffs (owned-files, the review patch, the fix patch) read the task folder
  alone, through one helper, and set aside the files AIDA's own scripts write there
  (`task.json`, the stage records and their renderings, `implementation/` and its restart
  archives, `records/`). A task note saved or another task closed between the brief and the
  record no longer reads as files the order did not own. A person's places are `inputs/` and
  `deliverables/`; a file placed under a stage folder is set aside even when a person wrote it.

## [6.0.0-beta.12] - 2026-09-16

The thirteen defects the nyc project's live run found against beta.10 and beta.11 (items 9 to 21
of the owner's report), and live-run rows 73 and 74.

### Added
- `proof: record`, the third proof kind, for a work order whose deliverable is a document in the
  task folder. Design marks an order `record` when every owned file is under the task folder and
  no `--proof` was given, and refuses an owned file the project ignores (`records/` holds derived
  check output; `deliverables/` is the place). The order freezes no test; its done-when rows are
  the checkpoint, judged by a person or the row-checker. Its range and its unchanged-tree
  refusal read the project folder's git history, so no empty commit is needed; the suite, the
  tool rows and the gate do not run; the reviewer is handed the owned files by path and no code
  patch. (item 17)
- `scope-actions.sh approve <task>`: promotes every designer criterion to the owner, runs the
  distill check and commits. The scope skill answers a correction with the changed lines and
  ends the turn; it never asks the whole-document question. The person closes with
  `/aida:scope approve <task>` or in their own words. Design's critique loop takes the same
  shape, and `close` from a fresh session runs the critique first. An eval case,
  `evals/scope-five-corrections/`, in the shape `claude plugin eval init` scaffolds, fails when
  the approval question appears more than once. (item 14)
- `task set-run-mode <task> autonomous --stage <stage>` scopes the mode to named stages;
  `runModeStages` in `task.json`. One helper, `task_run_mode <folder> <stage>`, answers every
  reader; implement reads the task at every `start` and rewrites the ledger's copy; review reads
  the task, not the ledger. An autonomous stage invokes the next only when the next is
  autonomous too. (item 20)
- `implement-actions.sh clear-halt <task> <wo-id> --because <text>` clears a halt the grant and
  the restart do not answer (a rejected row, a non-goal hit, a fixer's scope, a load-bearing
  finding, a dirty tree), records it under `haltsCleared`, and refuses under an autonomous
  implement stage (exit 68) or on a halt another action answers (exit 85). The grant, the restart
  and `clear-halt` read the task's mode, so `set-run-mode interactive` then the action is the path
  past an autonomous halt. (item 20)
- `design-actions.sh remove-test` and `merge`, the actions the sizing rules name. `remove-test`
  refuses the last test only where the design check would, an order owning a machine-verified
  criterion. `merge` folds one order into another, de-duplicates, rewrites `dependsOn`, and
  removes the folded order's files. (live-run row 74)
- `start --rebased-onto <commit>`: a resumed `start` whose HEAD does not descend from the
  ledger's `startedFrom` refuses (exit 82) and names this flag, which rewrites the field and
  keeps the old value under `startedFromBefore`. Refused when the branch was not rewritten.
  `startedFrom:` prints the ledger's value, never HEAD. (item 19)
- `start` prints `proofAbsent:` naming the orders whose frozen copy carries no `proof`, and that
  tests prove them unless design sets `gate` or `record`. (live-run row 73)

### Changed
- The run record travels by file at every jq hop: the suite and tool outputs by `--rawfile`,
  the growing checks and runs by `--slurpfile`, in the implement and review scripts (fourteen
  hops in review). A record with fewer checks than the schema requires is refused (exit 84)
  instead of written with a check silently absent. (items 9 and 12)
- Owned files outside the code repository leave the tool rows and the baseline tools, the way
  frozen tests do; a row with nothing left reads undeclared and names how many lay outside.
  (item 11)
- A resumed `start` checks `baseline.json` against the shape this version writes and refuses
  (exit 83) naming the retake; no attempt is spent on an old baseline. (item 10)
- The record steps honour the recipe's `cost`. A suite row costed `end-of-task` is not run per
  attempt; the check reads `deferred`, which passes like `undeclared` and never satisfies the
  order-tests floor. `finish` runs the suite once at HEAD with the baseline subtraction, writes
  `finished.json.suite` with the output in `implementation/finished-suite.txt`, and refuses
  unmet or unknown (exit 86). Review reuses that result at the same commit instead of running
  the suite again. (item 18)
- A folder source of process recipes falls through: the declared folder first, then the
  dev-guides catalog, then research's missing-recipe path. `recipe-source` answers
  `RECIPE: catalog searched=<folders>` on a folder miss; the `none` answer is gone. This reverses
  the beta.11 rule. (item 16)
- `task create` names the worktree folder with the slug of the code folder (lowercase, runs of
  other characters to one hyphen), so a dot in the folder name no longer reaches the site name.
  (item 15)

### Catalog asks, not plugin changes
- The Drupal test-execution recipe's `failure_line` uses `\w` inside a bracket, which POSIX ERE
  reads literally, so GNU `grep -E` never matches it; the ask spells it POSIX. (item 13)
- The recipe's PHPUnit rows run `ddev phpunit`, which ignores `{file}` and `--filter` when
  `phpunit.xml` is not at the root; the ask moves every row to `ddev exec vendor/bin/phpunit -c`.
  (item 21)

## [6.0.0-beta.11] - 2026-09-15

### Added
- A process recipe resolves from the project's own folder source. `add-source <name>
  processRecipes <folder>` had recorded a source nothing read. `project-actions.sh
  recipe-source <project folder> <phase> <framework>` walks the sources providing process
  recipes in declared order and answers the first `process-recipes/<framework>/<phase>.md` that
  exists. A declared folder is the source for that kind, so a miss is `none`, naming the folders
  searched, and the stage takes its no-recipe path; the catalog answers only when the project
  declares nothing for the kind, or declares it too with `add-source <name> processRecipes
  catalog`, in its own rank. Each new source takes the next rank. The identifier and the
  research and design lookups run it before the navigator, and every dispatch line hands the
  identifier the project folder. Version 5 resolved a local recipe on every miss; the rewrite
  had kept the recording and dropped the reading.
- The ten documentation pages that were placeholders are written: scope, research, design,
  implementation, review, finishing, run modes, sources, testing and continuity. Each was
  written from its skill and read against it by someone who did not write it. Where the plugin
  lacks a path, the page says so.

## [6.0.0-beta.10] - 2026-09-14

Live-run rows 43 to 72, and the defects found picking a version 5 project up on another machine.

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
- A work order carries `proof: tests` or `proof: gate`. A configuration unit is proved by the
  implement recipe's `## Configuration gate` lines, run by the build step as `configuration-gate`
  in the order-tests slot. It freezes with no test, and `close` records its criteria as judged
  by the gate, a third value beside person and model. The design skill says a configuration
  unit owns every file the Drupal operation rewrites.
- `tests-freeze --test-recipe <framework>=<path>` reads each red run against the recipe's
  failure signal: an assertion marker is a red, a harness marker is a setup gap refused with
  exit 80, and the suite row's `failure_line` selector is read when the recipe names neither.
  A red with no recipe is refused; a recipe with nothing to read freezes the red as unchecked.
- `tests-freeze --implement-recipe <framework>=<path>` reads the implement recipe's
  `## Unit declaration` globs. A red that holds only a harness marker is accepted as
  `harness-new-unit` for an order whose owned files match one, because nothing can fail an
  assertion before the unit exists; every other order is refused as before.
- A serving order freezes tests against its own done-when, judged with `--row <order id>=...`
  and recorded on its ledger entry. Rows follow what the tests claim.
- `tests-freeze` commits the frozen paths alone, before it writes the record, and the record
  names that commit. A failed commit refuses with git's message and writes nothing.
- `preconditions` keeps each baseline run's whole output under `implementation/baseline-output/`.
  A check whose baseline was red subtracts that output line by line, so only a new line reads
  unmet. The suite subtracts on the lines the recipe's `failure_line` selects. The review
  stage's four checks subtract the same way, through one copy of the helpers in the library,
  and the review record carries the same fields.
- `dispose --path <file> --interface <text>` records a reused path and its interface on the
  order; `tests-brief` carries them, and the test author is denied the reused paths.
- `dispatch-open test-author --test-glob` leaves owned files that match the recipe's test
  patterns out of the author's denial.

### Changed
- Scope drafts the whole contract from what is on the table, renders it once and asks what is
  wrong or missing; corrections become single writes in the person's words. Single questions
  remain for a gap the draft cannot fill, the non-goal probes and the surfaces offer. Version 6
  had made version 5's opt-in interrogation the ordinary behaviour; the owner found it painful.
- The session-start line says `playbook file:` and the pick-up line names `/aida:next`.
- The report reads an absent `runMode` as `interactive`, the value every other reader prints.
- The catalog identifier tests a store path before answering with it, and answers
  `fetch-failed` when the file is absent.
- The row-checker judges every row in both modes, given the test-authoring recipe's path. A
  person on an attended run answers only a row the checker rejected, with the checker's note.
  A model's row is recorded as the model's in either mode, and `rowsJudgedByModel` lists the
  rows no person read. Version 6 had asked a person about every row; the owner found the
  question added a turn and no judgement.
- The coding-standards, static-analysis and security rows run over the order's owned files
  minus its frozen tests, directories expanded, and the record names the paths and the frozen
  tests left out. The tests step runs the coding-standards row over the new test files before
  the freeze, so the tests' own standards are judged once, there.
- Research closes by showing what it found, per search, from the rendered files: the guides
  and recipes identified, each prior art candidate with its closeness, each assumption shown
  false. A presentation, not a question.
- The design check's remedy states its direction: an order that owns nothing is reached when
  an owning order depends on it, and a feature's entry point belongs in the feature's order.
- The build step reads the test-execution recipe path from `preconditions.json` and the check
  recipe paths from `baseline.json`, and resolves the implement recipe once per build.
- `start` re-snapshots an unstarted order the live design changed and halts nothing for it;
  `restart` moves only the halted orders' records aside and keeps every finished order.
- The catalog identifier names its five callers, and for a process-recipe point such as
  `worktree-environment` it runs the navigator's process-recipe lookup and answers with the
  body's store path, a file `environment` can read, never a URL.
- The scope, research and design close steps resend the same distiller once when its sidecar
  is missing, rather than dispatching a fresh one.

### Fixed
- Every action script ignores SIGPIPE, so a caller that pipes an action through `head` cannot
  lose the writes that follow the lines it keeps. Found through `record`, whose render came
  after its summary; a sweep found sixteen more actions in that shape, and the trap covers all.
- A never-saved task blocks compaction only once it holds a version 6 record, so a repaired
  version 5 task with no version 6 run compacts freely.
- `task create` step 4 stops only on the refused worktree entry.
- A recipe step that reads standard input no longer swallows the steps after it. The step loop
  fed its lines through the loop's own stdin, and a command such as `ddev composer require`
  read them, so the install ended early with no error. Every step now runs with stdin closed,
  and so does every `## Tokens` command and check row. Reported by the catalog side while
  consuming the setup recipes.
- A version 5 project header is read in either case (`**Code Path:**` as well as
  `**Code path:**`), so a version 5 pickup no longer refuses and offers a second project.
- The field-list comparison runs on jq 1.6: its parameter was named `$def`, a jq keyword that
  1.6 rejects, so every check exited 3 on Ubuntu 22.04.
- Every project-folder commit takes `project.json` alone, so a `task-rule` write no longer
  sweeps another task's uncommitted files into its commit.
- `alignment-render.sh` adds a full stop only when the clause has none.
- Research's `record` renders before it prints, so a caller that keeps its first line cannot
  lose the render.
- The drift walk halted every order with a dependency whoever drifted, because of a jq
  binding; the reached order is bound first now.

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
