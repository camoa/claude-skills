# Changelog

All notable changes to this plugin are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [6.0.0-beta.26] - 2026-09-25

Two rows, both design changes the owner asked for, and the navigator's
tooling mode. A task can say it has no automated tests, and a light run mode
builds fast and logs what it skipped.

### Added

- Scope asks, once per task, whether the task has automated tests. The answer
  is stored in `alignment.json` and signed with the scope record. Only
  `scope-actions.sh set-tests` writes it. Research can reopen it.
- A fifth proof kind, `confirm`. On a task with no automated tests, design
  gives it to each code order. The order gets an implementer and a reviewer
  only. The project's static checks still run, no suite runs, and no test
  runner is installed. The person confirms each done-when sentence at review.
- The design check refuses a `confirm` order on a task that has tests. The
  repair is `update --proof tests`.
- A light run mode, `set-run-mode <task> light`. It runs unattended on the
  autonomous machinery. It skips the outward web search, the design critique,
  tests for each order, visual regression, and fix rounds after the first.
- Every light skip is written by the code that makes it to `COMPROMISES.md`
  in the code repository. Each row names the stage, what was skipped, and what
  a normal run would have done. A line marked `AIDA-FAKE:` is logged when its
  order closes. A later normal task takes the log as its scope.
- On a light task, the first work order is the walking skeleton, and every
  other order depends on it.
- On a light task, review fails until one critical end-to-end surface walks
  the demo path. The remedy is `/aida:surfaces e2e`.
- Design opens a tooling recipe with the navigator's new `tooling --name`
  mode, in dev-guides-navigator 0.15.0. It no longer fetches the body by hand.

### Unchanged

- Interactive and autonomous tasks behave as before. Every light rule sits
  behind one test, `task_is_light`. A task with tests keeps the `tests` proof.
  The one visible change is the new scope question.
- A ceiling set with `set-budget` still halts a light run.

### Checks

Sixty-two fixtures, 5,580 rows, pass under bash and under zsh on the merged
branch, every run exit 0. The repository's specs pass. One older fixture
expected a message this release changed on purpose, and now expects the new.

### Known limits

- A light task is never signed off unattended. Its confirmed criteria wait
  for a person at review.
- An order that halts when its one fix round's own checks fail, and then
  closes with no second round, is refused at close. The halt after
  verification was walked and resumes cleanly.
- A light task with no order named `wo1` has every order flagged.
- A halted order can log one skip twice, in two wordings.
- The tool skill's check and research's search for a test runner are skill
  text. No script enforces them.
- Changing the answer to no automated tests after orders own files leaves
  those orders on their proof until `update --proof`.

## [6.0.0-beta.25] - 2026-09-24

Twenty-three rows, and one design change the owner asked for while it
closed. Nine rows were opened by beta.24 itself, while it closed other
rows. Nine more were found while this release closed those, and five came from
a live run on the day it closed. Every row is closed. One closes through a
proposal to the guide catalog, because no AIDA action edits a catalog recipe.
The work also turned up five live defects nobody had written a row for.

### Added
- `aida/tests/records-folder-spec.sh`, with a list naming every file a task's
  `records/` folder may hold, its producer, and what makes it again. The
  compaction refusal skips that folder and nothing checked what landed there.
  The spec's first run corrected the set from thirteen to sixteen. It follows a
  variable, so a path assembled at run time is refused by name and line rather
  than passed in silence. (row 176)
- `aida/tests/shadowed-functions-spec.sh`. A script that defines a function
  whose name a sourced library already holds silently overrides it for that
  whole script, and every test still passes. beta.24 shipped one instance and
  caught it only after the commit. It reads four declaration forms, two of
  which the tree already uses. (row 179)
- `aida/tests/swallowed-refusals-spec.sh`, with a list of the sites where a
  refusal inside a command substitution is safe, and the reason for each. A
  `die` inside `$( )` ends only that subshell. (row 186)
- Every spec header names the test runner from the repository root. The runner
  lives at the marketplace root and the plugin has its own `scripts/` folder, so
  the old wording read as plugin-relative. Three readers across two releases
  concluded the file was missing. The headers also say the runner finds a spec
  through `git ls-files`, so an untracked spec never runs. (row 186)

- `tests-freeze --absence <clause>` routes a done-when clause that asserts an
  absence to review. A test of an absence cannot be watched failing, so the
  clause needs a reviewer rather than a red run. The clause must be verbatim in
  the order's done-when and carry a negation word. A word ending in `n't` and
  the word `cannot` count, with straight or curly apostrophes. The architecture
  reviewer gives each routed clause a verdict. It also says whether a test
  could have watched the clause fail. Review's `absence-clauses` check fails an
  unjudged clause, and fails one a test could have covered. The review summary
  prints one line per clause. (row 184)
- `drop-retired <name>` in the project skill. The schema now lists retired
  fields, and the check names this action when a project file holds one. It
  removes exactly those fields and commits. (row 192)
- `aida/scripts/lib/project-findings.sh` holds the version 5 task-rule markers
  and their detection once. The check, the project actions and the
  session-start hook all read it. (row 191)

- A work order can carry its own proof, in a `verify` list. When a catalog
  recipe covers the order, its verifier's commands become checks that run, and
  its prose items become checks the reviewer judges. No command is ever made
  from prose. When no recipe covers it, research's best-practice findings can
  become checks too. Each cites its source and is marked not binding. A
  command from research runs only after a person approves it at the design
  close, and never in an unattended run.
- `br_order_needs` in `scripts/lib/proof.sh` decides which roles and catalog
  lookups an order needs, in one place. The per-order reviewer, the row
  checker on a record order, and every top-tier critic are never cut.
### Fixed
- A failed write never empties a record. The guard went into `write_atomic`
  itself rather than the seven call sites the row named. The same shape sits at
  about ninety more sites across six skills. A per-site test does not stop the
  next new action, which is how this one was found. All 86 callers were traced
  and none can legitimately pass empty content. Before it, an unreadable record
  made `save` exit 0, print success, and truncate a 226-byte record to one
  byte. (row 173)
- A refusal reaches the caller that asked for it. Of 54 command substitutions
  calling a function that can refuse, fourteen tested neither the exit code nor
  the value. Five of those were live defects. One swallowed the refusal
  that stops a stage action running outside its task's worktree. The action
  carried on and printed a second message that was false. One dropped a
  criterion out of the record a person signs off. One let a framework whose
  entry could not be recorded read as met, which is a failed write becoming a
  passing condition. Two ran a site's bring-up lines from whatever directory
  the caller stood in. (rows 173, 186)
- The registry rebuild tests a name and a code path before it writes a row. It
  was the fourth door past a test three other routes share. Two rows on one code
  path make the directory lookup answer with whichever was written first, and
  nothing reported it. The rebuild reads the folders outside the base first, so
  a skip falls where a later rebuild can undo it. (row 178)
- A pickup that registered a folder reports success. It returned the project
  checker's exit code, which is never 0 on a folder no producer has filled.
  (row 177)
- The design close commits the critique it cites. The record named three paths
  in an ignored folder, so a committed record cited evidence the repository
  never held. Three critics write those files at opus, so a second dispatch
  answers differently and re-running is not a recovery. (row 176)
- A tool run's record says what produced its output. Arguments a caller typed
  reached no file, so after a compaction the record held output nobody could
  account for. The skill documents the form that supplies them, and the two
  actions that used to drop it now refuse it. (row 176)
- The compaction refusal's stated reason. beta.24 said every file in that folder
  is derived and its producer runs again. That is false for four records written
  by a model, and for two more whose inputs do not survive. One comes from the
  clock at the instant an automatic compaction fired. One holds output whose
  command arguments reached no file. The claim that carries the skip has two halves. No
  file there carries a person's answer. And none is the only copy of anything a
  person still needs. (row 176)
- The project checker sees a duplicate code path, and says it compares the
  spellings the registry holds rather than resolving them. (rows 178, 187)
- A branch in the task checker is gone. It was unreachable from the day it was
  written, and so is the header sentence that made it look necessary. (row 174)
- The design critic no longer reports a path the close moves. (row 189)

- A resume line reads the branch, not a record. `start`'s `partialBuild:` line
  finds an order's freeze commits by their subject on the branch. It reads every
  restart record, not only the newest one. It covers every retaken order, and
  it lists only the build and fix commits a test author can cite. An order that
  was built again since its halt gets no line. (rows 182, 183)
- A still-green test can cite a commit. `--locks-in <test>=commit:<id>` names
  one of the order's own build or fix commits, and any other id is refused.
  After `start --rebased-onto`, a commit is followed onto the new branch by its
  change, author, author date and subject. (row 183)
- A site the record can always find. `environment up` writes a marker before
  the first bring-up line, so `down` can tear down a site that failed halfway.
  `down` reads only the keys under the last bring-up. (row 185)
- The records-folder spec reads four more shapes. The one it cannot read is
  stated in its list header, where a person adding a record meets it. (row 188)
- A critique whose lens did not finish is kept. The design close moves it into
  `design/` as `unfinished-design-critique-<lens>.md` and leaves it uncounted.
  (row 190)
- A version 5 task rule is named on every project check, not only at pickup.
  The session start names it too, before any stage runs. The rewrite offer stays
  open until it is accepted or declined. A block with no end marker is never
  rewritten or removed; every route names the line to fix. A file holding both
  blocks keeps one version 6 block. `uninstall` removes a version 5 block. (row
  191)
- A project action commits only the files it wrote. Before, a commit took
  anything the person had already staged. (row 192)
- Task create asks the catalog one question per dispatch. It asked for two
  recipes at once, so the visual-regression setup recipe was never looked up.
  (row 193)
- `environment show` runs the recipe's precondition checks before the site is
  offered. `show` and `up` share one block for this. A failing check names the
  task branch, and the branch the worktree was cut from, which is now recorded.
  It also says a commit on that base branch arrives only after a merge. An
  interrupted or failed run leaves the tree and the index as they were. (row
  194)

- Design chooses how an order is proved from what the order produces. Code a
  test can pin is proved by tests. Tools that change state get a gate. A
  document or analysis is proved as a record. What a person or a browser sees
  gets a look. Before, any machine-checked criterion pointed to tests, so a
  dependency update got an invented test.
- A gate order runs its own checks first, then the framework's configuration
  gate when the recipe has one. The worse result stands. All check lines go
  through one runner. A placeholder given several values runs once per value.
- The architecture reviewer is not dispatched when no order commits code and
  no absence clause is routed. The review record says why.
- The test-authoring lookup runs only for orders proved by tests or by a
  record. It ran for every order.
- A check command gets only the files its `extensions:` key names. A folder
  row with no matching file ran over the whole tree and passed. A row left
  with no file now reads as not applicable.
### Checks
Sixty fixtures, 5,346 rows, pass under bash and under zsh on the merged
branch, every run exit 0. The repository's specs pass. Four older fixtures
expected behaviour this release changed on purpose, and now expect the new. Each
build had a fresh checker over its artifacts.

### Known limits
- A rebase that changes a build commit's diff, through a conflict, loses the
  link to that commit. The resume line and the refusal name it as not found and
  say why. A person decides whether the green test stands.
- A reviewer can answer that a routed absence clause could not have been
  tested when it could. The route rests on the reviewer's answer.
- A Drupal project whose docroot is the repository root cannot bring its site
  up until the catalog recipe reads the project row safely. The ask is filed
  with the guide catalog. (row 195)
- A command written from research runs only with a person's approval, so an
  unattended run judges it instead of running it.

## [6.0.0-beta.24] - 2026-09-23

Fifteen rows, every one left open by beta.23. Most were a record page and the
code disagreeing. The triage of the 2026-09-15 pass named which side was wrong
in each. Three were not page corrections. The gates survey had asked for a per-order
reader. A project folder outside the base had no way back. And the freeze
warning was half built.

### Added
- `task set-budget <task-id> --dispatches <n> --minutes <n>`, either flag or
  both. The record has always described `budget` as a field a person sets. No
  action wrote it, so the only route was editing `task.json` by hand. One site
  reads the field, and the halt it drives is routed in four more. So the field
  stays and gains a producer. A call naming one number keeps the other. That
  departs from `set-run-mode`, and four pages and the schema say so. A value
  below one is refused in the action. The schema check enforces no minimum, and
  a zero would halt the first dispatch. (row 151)
- `switch <path>` registers a version 6 project folder again, from its own
  `project.json`. A folder outside the projects base had no way back once
  unregistered. `create` refuses an existing folder, the rebuild walks the base
  only, and the version 5 pickup requires that no project file exist. Four
  refusals guard the new branch. A folder holding a version 5 state file
  and a version 6 project file takes the new branch. The old branch ends in a
  writer that would overwrite a good project file. A code path that is gone is registered
  and reported, which is what both routes it copies do. (row 169)
- `scripts/lib/proof.sh`, one reader for what a work order's proof kind means.
  It answers which check takes the order's slot, which repository holds its
  range, and whether it owns a file in the code path. Twenty-three sites read
  the field, each converting it in its own words, so adding a kind meant finding
  all of them. Twenty-two now read the reader. Nine of those live inside one jq
  program and read its jq twin. The twenty-third writes the word into a build
  brief, where it is a record's value and not a question. Adding a fifth kind is
  now one file. Nothing changes for any of the four kinds, proved against a tree
  at the merge base under both shells. (row 170)

### Changed
- The restart lists every freeze an order has had. A retake records the freeze
  commit it supersedes, and the restart read only the current one. The reset it
  offered could leave the order's first freeze standing, with the test a person
  had ruled wrong still in the tree. A superseded freeze is listed only when its
  commit subject names this order. The recorded commit is the head at that
  moment, so it can belong to another order. (row 147)
- The freeze warning fires on the ordinary path. It was reachable only by
  passing the lookup flag, which is the documented path and not the common one.
  The flag stays optional. Requiring it would touch 31 call sites in 27 of this
  rewrite's own fixtures. It would also delete the state that tells a lookup
  which never ran from one that found nothing. The resolved line no longer says
  every order can be built when one framework of several resolved. It names what
  it read. A message that grows keeps the `freeze:` line, and the fixed
  instruction it carries moves to `freezeAdvice:`, which no project can
  lengthen. The first split had moved the truncation risk onto the tightest
  branch, where fourteen test-proved orders cut the line mid-identifier.
  (row 171)
- The completion body names `environment down` when a site is up. It drops the
  tear-down clause when none is. The task page has promised that since it was
  written. (row 150)
- The compaction refusal counts what this task's own work wrote. A file under
  `inputs/`, the check record `task start` writes, and the task file no longer
  read as unsaved stage work. A task that had done nothing refused a manual
  compact. One step sits in a window the hook cannot see: research's playbooks
  step writes only under `records/`. It is safe, because nobody answers anything
  in it and every record it writes has a producer that runs again. Three places
  say so, with the rule a later author needs. (row 152)
- The two messages telling a person to take the baseline again say what is true.
  No action retakes it, and none should. The baseline runs each tool against the
  tree as it stands, so one taken after the build would record this task's own
  findings as pre-existing. The reason recorded for the exclusion was circular,
  and now states the real one. (row 153)
- Review's surface offer takes the same three answers as scope and design. "Not
  this task" has a meaning at the last stage. It leaves the kind to be asked
  again, while a no silences it project wide. (row 155)
- The contract a person approves names each question an unattended run answered
  for them. The record has carried those questions since it was written, and the
  rendering showed none. So a person could approve a contract holding answers
  nobody gave. A non-goal an unattended run decided records one entry naming its
  id. The distiller raises a list that is not empty. (row 165)
- Research's run mode is counted correctly. The page named a difference it never
  defined, at an unaccepted guide source, where both modes record the same
  thing. It omitted two that exist. The skill also shows the criteria no person
  approved, which its own script header said it routed on. (row 164)
- Research reads the parent's research before planning its searches. A split
  hands down the goal and the criteria and copies no research. So every child
  re-ran the searches its parent had already run, one folder away. The child
  reads the parent's folder through the `parent` field it already carries. It
  records what covers a criterion with the parent's own source and date. Copying
  the records was rejected: criterion ids do not survive a split, so every
  copied finding would cite an id the child does not hold. (row 166)
- Four implement pages name review's close as the stage that confirms a
  criterion a person verifies. Completion names neither a checklist nor a
  verification, and never has. (row 162)
- The implement skill says that finish runs again after a failed review. The
  route already worked, and the skill would not say so. Its read printed that
  nothing was left, and its step table held no row for a finished task.
  (row 163)
- Six record pages say what the plugin does, where they disagreed with it. The
  playbook capture is live. A split is judged rather than counted. One open task
  is loaded whatever its state. A body from an unconfigured source is recorded
  and not shown. The run ceiling binds every run. The write hooks have run in a
  live dispatch. Four places still counted five stages and now read six.
  (rows 156, 162, 166)

### Fixed
- The version 5 pickup tests the name before it writes a registry row. Two
  folders sharing a basename wrote two rows with one name. The switch then
  resolved by basename and took the first, so a person was sent into the wrong
  project in silence. The rename that the refusal names as the repair could not
  work before this release. The failed pickup had already written a project
  file, which made the guard refuse the renamed folder. Pointing the switch at a
  project that is still registered now switches to it. It used to refuse, with a
  message telling a person to rename a project over a collision with itself.
  (row 169)

### Checks
Forty-six fixtures, 3,438 rows, pass under bash and under zsh, every run exit 0.
Line-count, vocabulary and execute-bit specs pass. Shellcheck at warning level
is clean over every script this release changed. Each of the eight builds had a
fresh checker over the artifacts and one fix round. Four checks failed and were
fixed.

Caught before commit, each by a checker or a builder's own sweep:

- A brief of ours that would have taken the test harness away from a task of
  configuration orders. It was disproved three ways on one input.
- A new action that truncated `task.json` to one byte and exited 0.
- Three fixture rows asserting over an array that was always empty. They held
  under every variant, including the wrong one.
- A message cut before its repair sentence. The first fix moved the same risk
  onto the tightest line.
- A new function whose name a sourced library already used. It silently
  overrode that function for the whole script.
- Four pages saying a pickup writes nothing into a folder it writes a record
  into.

## [6.0.0-beta.23] - 2026-09-23

Sixteen rows, in two batches. The first five come from the live run on beta.22
and from the owner's own asks. The second eleven come from re-reading the
thirty-nine findings of the 2026-09-15 documentation pass against this branch,
eight betas after they were written: eight were already fixed, one was deferred
work rather than a defect, and one was wrong about itself.

### Added
- `tests-brief` writes a `retake` key after `retake-tests`, while no freeze has
  answered the retake. It carries the ruled finding with its evidence,
  severity, file, lines, `linkedTo` and ruling reason, read from the review
  record at the retake entry's own `movedTo`, and the rows and globs the order
  already froze. A record a person removed is named, not dropped. The test
  author reads the key as a correction and leaves every other frozen test
  alone. Before this a fresh author read a first-run brief and wrote the
  order's tests again, which the wrong-test route forbids. (row 142)
- `add` and `update` print the proof an order's owned criteria imply, beside
  the proof it declares, on every call. `check-design.sh` reports every order
  whose proof is `tests` and that owns no machine-verified criterion, and
  never raises the exit code; `check` prints `impliedProofDisagrees:` at every
  exit code, with the repair. The design critic sends a criterion nothing
  would settle back to scope, rather than giving it a proof kind. (row 145)
- `project check-machine`, report only: the Claude Code version against the
  two that matter, whether the plugin changed after this session started,
  whether the check ran inside a worktree, trees git lists that are gone from
  disk, and trees git lists that no task record names. The session start hook
  exports the loaded version through the hook environment file. (row 146)

### Changed
- A resumed `start` clears a drift halt whose order no longer drifts. It
  removes only a segment about the order's own design copy, keeps every other
  segment, and records the clearing. A reopen that changes both an order's
  design file and a criterion it serves now writes both segments, so restoring
  the file alone leaves the order halted. `clear-halt` keeps exit 85 and names
  `start`. The design page says a change to a started order halts it, and the
  rulings page says to correct the design and restart when the ruling's cause
  is the done-when wording. (row 143)
- `restart` finds an order's build and fix records wherever they are: the top
  of the implementation folder, each folder a retake recorded moving them to,
  and every earlier restart's archive. The `tree:` line then counts only the
  commits that are not the order's own, and its carry answer says the order's
  own code stays in the tree, so its next tests cannot go red. (row 144)
- The exit 79 refusal names the route that works where the call ran: the
  `cd <tree> &&` prefix alone from outside the code repository or from another
  task's tree, and entry first from inside the checkout. The test asks git
  through `active_tree_for`, repairs `worktree.path` when a tree moved, and
  falls back to the string test when git cannot be asked. Eight stage pages
  relay both routes, and `next` says what to do after a decline and after a
  refusal. (row 146)
- The design page says a tooling recipe body is fetched, checked against the
  catalog's sha and stored by hand, until a navigator mode serves one. Owed
  since beta.22. (row 126)


### Added, in the second batch
- The review stage learns the proof kinds. A criterion owned by a `gate` or a
  `record` order reads the judgement the build wrote on the ledger, as an
  `observe` order's criterion already read the observed record. `not-needed` is
  legal in the check row enum and ranks above `undeclared`. (rows 154, 167)
- `project check-machine` and the worktree route, from the first batch, gain a
  producer that recomputes a task's tree path when the recorded one is not this
  machine's. One reader answers where a task's tree is. (row 148)
- A declared `playbooks` folder is read, in declared order. One walk serves
  every kind that resolves by path, and agentic recipes gain a layout, a reader
  and a dispatch that reaches it. (rows 157, 159)
- `preconditions` names each order that cannot be frozen without an implement
  recipe, so a person hears before any order is built. (row 160)

### Changed, in the second batch
- The schema comparison reads a field at every depth. It applies the type test
  and four keywords at every level, enforces undeclared fields everywhere, and
  descends through properties, items, a resolved reference, every branch of an
  all-of and a one-of. A reference it cannot resolve fails the whole call. 255
  constraints in 23 of the 24 schema files were decoration. Seven keyword
  families are still unevaluated and `docs/project.md` names them. (row 168)
- `project` and `tool` drop `disable-model-invocation`, decision 27's third
  amendment, so a dispatched session can set a project up. Six actions refuse
  with nobody present; the run mode is validated, so a misspelled value is
  refused rather than read as interactive. (row 172)
- `answersFor` is gone: every source carried the same value and nothing read
  it. An older project file that still holds it passes its own check. (row 158)
- `rebuild-registry` walks the canonical base, so a base path ending in a
  symlink no longer writes an empty registry in silence, and a project outside
  the base is kept. (row 149)

### Fixed, in the second batch
- Every review lens that returned no finding was recorded met, whether it was
  judged or never had anything to judge. All six now answer `undeclared` when
  no order commits in the code repository. The reviewer cannot see a record
  order's deliverable, so a lens judging an empty diff was reporting met about
  work it could not read. (row 154)
- The well-formed field tally counted faults at any depth against a field count
  of the top level alone, so a task with twenty faults in one list printed a
  negative number. It counts fields.
- Review's practices floor did not count a declared playbooks folder, so a
  folder that failed to load read met. It counts a folder, and only a folder.
- A recipe on disk that could not be read fell through to the catalog. Missing
  and unreadable are different. (row 161 and the walk)

### Fixed
- A resumed `start` rebuilt the ledger without `haltsCleared`, dropping every
  clearing `clear-halt` and `retake-tests` had recorded.
- A stage action ran from any folder when the project's code path was off
  disk, found while building row 146 and fixed before it shipped.

## [6.0.0-beta.22] - 2026-09-22

Live-run rows 111 to 141. Rows 111 to 116 come from the implement stage on beta.21, rows 112 to
115 being the first live use of the `observe` proof kind. Rows 117 to 141 come from a second
project's run on beta.15 to beta.21 (`volunteer-role-complexity-analysis`), every stage.

### Added
- A task action `decline-recipe` records that a framework needs no process recipe in this task,
  so the missing-recipe ask is not repeated for it at research or design. (row 123)
- The outward searcher names a `fetch-failed` finding for a page it could not fetch, and the
  research page lets the conversation fetch that one page into `inputs/`. Prior art on another
  branch is extracted with `git show` into `inputs/prior-art/<branch>/` and named to the
  internal searcher. (rows 124, 125)
- `design update --append-reasoning <text>` appends a paragraph; `--reasoning` replaces, and
  the page says so. `design close --critique-outcome <text>` records how the critiques were
  answered beside the finding count; unattended refuses it. (rows 131, 135)
- Every stage's close record carries `pluginVersion`, the plugin that wrote it, so a task that
  spans an update shows which rules produced which record. (row 134)
- The dispatch record lives at `<task_folder>/implementation/dispatch.json` with `openedAt`;
  both hooks find it through one helper, and two tasks of one project can build at once.
  Exit 75 is retired. (row 139)
- `repair` moves a version 5 epic's nested children to `tasks/<child>/` in the same call, sets
  `parent` and `children`, and accepts `## Problem` as the goal heading when `## Goal` is
  absent. (rows 140, 141)
- A fix scope outside the order's files is named at birth, withheld from the fixer, allowed
  only by a person, and refused by the hook. `review-record` stores and prints `outsideOwned`
  for a finding whose `fixScope` leaves the order's `ownedFiles`. `fix-brief` hands the fixer
  only the owned paths and the paths `--allow <path>` names, resolved relative to the code
  path; the rest is withheld per finding, so the fixer reports it scope-insufficient and the
  ruling route opens. `fix-record`'s owned-files check reads the round's allowed paths. The
  fixer's dispatch record carries `ownedFiles`, and the write hook's rule two holds the fixer
  as it holds the implementer. `--allow` unattended is exit 100. (row 116)
- An observe order gets a look before the build. `build-brief` names the before folder and says
  whether the before-look is owed or taken; the look is the same surfaces at the same viewports
  at `headNow`, before the implementer runs. Each observed row carries `before` beside
  `screenshot`, both checked on disk under their folders, and completion names both images to
  the person. (row 114)
- The look judges each owned criterion's own clause. `build-record --observed` owes one row per
  sentence per surface per viewport, where the sentences are the done-when rows and the
  verification clause of each machine criterion the order owns; a clause row carries
  `criterion`. The critic's buildability lens reads each owned clause beside the rows.
  `design update --proof` prints `stillNamesATest:` for fields whose text still names a test
  file. (row 115)

### Changed
- The way into a task's tree is `/cd <path>` (Claude Code 2.1.169 or later), with
  `cd <path> &&` at the front of a Bash call as the per-call form; the exit 79 message names it.
  `start` puts the site offer, or records `not-applicable`, whoever called it. `save` on a task
  with no stage record skips the distiller, and the stage reads scope until scope's sidecar
  exists. Every task commit stages the task's own folder, `split` its children too, never
  `tasks/` whole. (rows 117 to 120)
- Every scope action that writes `alignment.json` renders `alignment.md`; `render` only shows
  it, and the design critic reads the JSON. The distiller's definition says what
  `decidedWithoutAPerson` holds. The retry rule on the scope, research and design pages gains
  the case of a dispatch that ends before its first write. (rows 121, 129, 130, 132, 133)
- Research fit `unsure` takes the `false` branch and asks. (row 122)
- A record order may own a path under the project folder in a folder the project commits,
  not only under the task folder; the implement stage scopes such an order's diff to the
  project folder and sets aside AIDA's own records. The false-fit question folds in "write the
  recipe first". (rows 127, 128)
- Preconditions and `finish` on a record-only snapshot record the suite and the smoke as
  `not-needed` instead of running a harness no order needs. `no-recipe` scores `undeclared`
  and every framework prints on every run; the recipe command no longer reads the framework
  list from stdin, which swallowed a framework name. The identifier's message carries
  `point: <phase>`. (rows 136 to 138)
- The look step names viewport control as the requirement, not a window resize, and the scratch
  route for a tool that refuses to write under the task folder. `build-record --observed`
  refuses a screenshot outside the order's observed folder. (row 112)
- When the implementer's report says it ran the configuration gate, or restored the seed
  snapshot, the look waits for the site's content to be put back. The recipe change is a
  catalog ask. (row 113)

### Fixed
- `verify-record --ruling` on a round already on the record applied nothing: the branch that
  reports the recorded verification returned before the ruling flags were read, so two rulings a
  person gave were dropped with exit 0 and `ruling: none`. It now applies them through the same
  gates as the recording call (unattended refuses, before the cap only a finding the fixer
  reported out of its scope, nothing open refuses) and writes no second round entry.
  `--verdicts` is required only until the round is on the record; given with a ruling on a
  verified round it is ignored and one summary line says so. The review page names the call as
  how a person reaches a ruling, and the retake, after the verification is on record. (row 111)

## [6.0.0-beta.21] - 2026-09-21

Live-run row 110, the implement stage on beta.20.

### Added
- A fourth ruling, `test-wrong`: the finding is real and its fix needs a frozen test changed.
  The order halts, and `retake-tests` moves its build, fix, verify and review records into
  `implementation/retaken-<order>-<n>/`, sets it back to `tests-frozen` with the attempt
  counter kept, and hands it to the wrong-test route: the author corrects the one test, the
  checker reads the rows again, `tests-freeze` overwrites with `retakenFrom`, build again.
  Until that freeze, `start` and `read` route to the author, never to a build. (row 110)

### Changed
- `verify-record` accepts a `--ruling` before the fix-round cap for a finding the fixer
  reported `--scope-insufficient`; the fixer's report is the evidence, so no second round is
  bought to reach a sentence. A finding no fixer reported still waits for the cap. (row 110)

## [6.0.0-beta.20] - 2026-09-21

Live-run rows 99 to 109, the implement and design stages on beta.19.

### Added
- A third proof kind, `observe`: an order whose criterion is what a page shows names its
  surfaces and one done-when row per criterion, freezes no test, and after the build the
  orchestrator opens each surface at each viewport in a browser, judges each row, and writes
  `implementation/observed-<order>.json` with a screenshot per row. `build-record --observed`
  reads it as the order's own check, one row owed per done-when row, surface and viewport;
  `close` writes `model` as the judge; review reads it as the criterion's verdict; completion
  asks the person to accept each observed criterion and records the answers. (row 104)
- `recipe-refresh <task_folder> --recipe <framework>=<path>`: a test-execution recipe the
  catalog republished mid-task replaces the path `preconditions.json` records, with a history
  entry. `tests-freeze` records the recipe each red was read against and refuses a
  `--test-recipe` that is not the record's. A republished review recipe still needs a new
  baseline, and no action takes one mid-task. (row 99)
- The reviewer's findings file takes an `information` list beside `findings`, for what a person
  needs that no criterion covers; `review-record` stores and prints it, and a dependent order's
  briefs carry it. (row 103)

### Changed
- The read denial reaches the shell: `deny-prior-source.sh` refuses `cat`, `head`, `tail`,
  `sed`, `awk`, `grep`, `rg` and their kin on a denied path, and a recursive search from a root
  that holds one; heredoc bodies are dropped by both hooks through one shared library. The
  implementer's definition names what it may not read, closed orders included. (row 101)
- The write hook allows `mkdir` of a directory an owned path lies under. (row 100)
- `build-brief` writes `interfacePath`, the implementer writes the interface record there, and
  `build-record` reads it from the brief when `--interface` is not given. (row 102)
- `tests-brief` carries `testRecipePath`, the test-execution recipe with the runner and the
  markers, so the test author is handed it. (row 107)
- `dispatch-open` for a row-checker refuses without `--test-glob`, so the checker can read the
  tests it judges; the step passes the freeze's globs. (row 106)
- The route for a frozen test whose oracle is wrong is named under the builder's stop: the
  author corrects it, the row is checked again, `tests-freeze` runs again while no attempt is
  recorded and prints `retaken:`. (row 109)
- A dispatch is the role on the Agent call, and a message of the run mode and the paths; the
  pieces each step used to list are gone, and each agent definition ends with what it is
  given. (row 108)

## [6.0.0-beta.19] - 2026-09-20

Live-run rows 95 to 98, the implement and design stages on beta.18.

### Changed
- The write hook's Bash door drops every heredoc body before either rule reads it, so a PHP
  `>=` or `->` inside one is never a write target. The owned-files rule ignores a token that is
  not path-shaped, and its refusal names the token it read and the redirect or verb it
  followed. (row 95)
- Interactive, `review-record` prints each not-actionable finding of medium or higher severity
  after its summary, and the review step asks one plain question: close as recorded, or track
  it as a follow-up task first. Unattended is unchanged. (row 96)
- `add-test` refuses, on a `tests` order, a description that names one of the order's own
  surfaces: review's surface row is not a test a test author writes. The message names the two
  proofs, a spec described by what it observes or scope reopened so the criterion reads
  `person`. The buildability critic reports a test naming a surface, a screenshot or review's
  row. (row 97)
- For the order that creates the unit, `tests-freeze` refusing a red that holds no declared
  marker now says the order creates the unit, lists the recipe's harness markers, quotes the
  file's error line, and names the two repairs: the recipe declares the form, or the test drops
  the module-local class. (row 98)

## [6.0.0-beta.18] - 2026-09-19

Live-run rows 88 to 94, the implement and design stages on beta.17, and the push gate.

### Added
- A write hook holds the implementer to its owned files: `dispatch-open` records the unit's
  `ownedFiles` on the implementer's record, and while it is open a write under the code path
  outside them is refused, with the frozen-test rule first. `agents/implementer.md` says a stop
  means report and end the turn, never "proceeding unless told otherwise". (row 92)
- `tests-freeze --support <path>`, repeatable: a base class or fixture the test author wrote is
  hashed with the tests, committed in the same commit, recorded under `support`, and guarded by
  the write hook. The frozen-tests check hashes it too. A missing path, a path outside the code
  root, or one a test glob matches is refused. (row 90)

### Changed
- `restart` names the halted orders' commits HEAD still holds (freeze, build, fix) in its record
  and its summary, and says which of two things to do: reset the branch to the commit before
  the first of them when nothing later depends on them (a person runs the reset), or carry
  them. A resumed `start` prints `partialBuild` while they remain, and the test author's brief
  says the tree holds a partial build. (row 94)
- A started order whose live copy differs from the snapshot only by added owned files is not
  halted at a resumed `start`: it is re-snapshotted in place, once design has closed on the live
  files, and its frozen tests and ledger entry are untouched. The design critic asks of every
  order whether it owns each file its operation rewrites, read against the couplings the design
  recipe names. (row 91)
- A design reopened to change only owned files or done-when rows on an existing order may skip
  the research and guide reading: the change, `check`, `close` with the last recorded recipe
  verdict, `distill`. Any other reopen reads as a first run. (row 93)
- Every question the implement stage puts to a person opens with one plain sentence naming the
  decision, why it is the person's call, and what each answer causes; the rule is stated once
  in `SKILL.md` and twelve ask sites follow it. (row 89)
- At an unknown interface-record verdict nothing is asked: the reviewer decides from both texts
  in its brief, in both run modes. (row 88)
- The push refusal in `deny-destructive-commands.sh` has a gate a person opens on their own
  machine: while `/etc/claude/allow-push` exists and root owns it, the session may run
  `git push`. Only `sudo` can create it, so the model cannot open the gate from a tool call.
  A force push stays refused. `docs/finishing.md` says how.

## [6.0.0-beta.17] - 2026-09-19

Live-run rows 86 and 87, the implement stage on beta.16.

### Added
- `build-recheck` runs the eight deciding checks again over a recorded attempt's own range,
  with no implementer dispatched and no attempt spent. It is the route when an attempt was
  stopped only by the tool rows and the code has not moved; `next:` names it beside `build`.
  It refuses (exit 88) with no record, a moved head, a stopper outside the three tool rows, or
  a record that already passed. The record keeps its attempt and adds `recheckedAt` and
  `checksBefore`. (row 87)

### Changed
- A resumed `start` treats a changed criterion as design drift for every order that serves or
  owns it: started orders halt, unstarted ones are taken fresh, dependents halt, the same rules
  a changed order file follows. The snapshot's alignment is refreshed with the live contract
  whenever the snapshot is rewritten, so tests are written from the criterion the person
  approved. `contractChanged` on the `drift:` line is now explained. (row 86)

## [6.0.0-beta.16] - 2026-09-18

### Changed
- An owned file the order deleted leaves the `{paths}` expansion of the tool rows, the way
  frozen tests and files outside the repository do; the check's detail counts it, and an order
  with nothing left reads undeclared instead of spending an attempt on a tool refusing a
  missing path. (live-run row 85)

### Fixed
- Two `local` declarations inside loop bodies, in design's id minting and implement's dispatch,
  printed under zsh and polluted a captured id and an action summary; `design create` under zsh
  minted a wrong id. Moved above the loops; a fixture scan refuses the pattern.

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
