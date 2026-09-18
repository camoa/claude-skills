# Write the code for one work order

This step runs once per work order, after that order's tests are frozen. The tests are the
reference now. Nothing below may change one.

## Resolve the recipe for this step

Dispatch `catalog-identifier` for the `implement` point and each framework, naming the project
folder. Skip it when an earlier step of this build has resolved it, the tests step included. Name
the role, and pass the lookup's answer in its own word: SKILL.md holds both rules. Once resolved,
reuse the path per framework for every order in this build. No record holds these paths. They
live in the conversation, so a fresh window resolves them again.

This recipe carries the rules applied while code is written. The implementer opens it itself, from
the path. Do not read the body here.

Do not give the test-authoring recipe to the implementer. It chooses a level and names a test, and
this reader may do neither. Pass its path to `dispatch-open` as `--deny-read`.

Read the `test-execution` and `review` recipe paths from the records preconditions already wrote,
instead of asking the navigator again. `implementation/preconditions.json` holds the
test-execution recipe at `frameworks[].recipePath`, for each framework whose lookup resolved.
`implementation/baseline.json` holds the review recipe at `checkRecipes[].path`, for each
framework that had one. A framework absent from a list had no recipe at the baseline; pass no
flag for it, the way the baseline ran without one. Pass the paths straight through to
`build-record` below. The script reads their
command blocks itself, per SKILL.md. The check recipe must equal the one the baseline used, so
reading it from that record costs nothing extra.

## Assemble what the implementer may see

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh build-brief "<task_folder>" <order id>
```

It reads the frozen copy and the frozen tests. It writes seven things to
`implementation/brief-<order id>-build.json`:

- this order's own record, with the files it owns;
- the frozen tests for it, with the criterion each carries; a test with `criterion: null` proves
  the order's own done-when, not a criterion;
- every order it depends on, with its declared interface;
- this attempt's report path;
- how many attempts this order has used of the count it is allowed;
- `headNow`, the commit of the repository this order lands in at the moment of this call, and
  `commitIn`, that repository's path: the code worktree, or the project folder for an order
  whose proof is `record`;
- `playbooksPath`, the path of `records/playbooks.json` when research loaded one, else null.

It prints the brief's path, the report path, `headNow`, the attempt count and counts, never the
brief. The allowed count is two unless a person has granted this order one more; see
`references/finish.md`. It is the order's own recorded allowance, never the constant alone.

**A dependency that has closed carries a second text beside the declared one, `interfaceRecord`:**
what its own builder actually wrote about what it exposes. When it exists, it is what this unit's
code is written against, not the declaration alone. Three files once said the record carries
forward and none of them did; `build-brief` is what actually forwards it now.

It refuses when the tests for this order were never frozen, when an order this one depends on has
no completion record, and when the attempts are already spent. Read a refusal and act on it.

That list is the withheld list. Pass the brief's path and nothing else.

## Open the dispatch record, then dispatch the implementer

Open it first:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh dispatch-open "<task_folder>" implementer <order id> \
  --deny-read <path of the recipe that writes the tests>
```
The script derives the rest itself from the frozen snapshot: this role is denied every other
order's owned files, and allowed its own. Never type those paths here. It prints both lists, and
an order that declares nothing it owns refuses rather than opening a dispatch with nowhere to
write.

**Then dispatch `implementer`.** Name the role, per SKILL.md.

Give it the path to the `implement` recipe for its framework, the path of the brief `build-brief`
wrote, and nothing else. `reportPath` in the brief is where it writes its five answers, and it
writes that file before it edits anything under the code path.

**On an order whose proof is `record`, tell it where to commit.** Its deliverable lives in the
task folder, so it commits in the folder the brief's `commitIn` names. It stages its owned
files and nothing else. The ledger and the briefs beside them belong to this stage, which
commits them when it finishes. The owned-files check sets them aside and counts them in its
detail, so a sweep is visible there, not a failure.

**It writes code only inside the files its order owns.** Not another order's, whatever it finds
there.

**It may not change a test.** A test that seems wrong is a reason to stop, not to edit. A hook
refuses the write and names which order froze the file.

**It may not read another order's source.** What another unit exposes is its interface record. A
hook refuses the read while the dispatch is open.

**It stops rather than working around anything.** A test that seems wrong, an interface that does
not fit, or the attempts running out are all stops. Interactive puts the stop to the person.
Unattended halts the order and records what was left.

Ask it to return what it changed, one line on the tests, the path to the interface record it wrote,
and any concern. Under fifteen lines. The interface record is prose about what this unit exposes,
and it is what the next order's tests are written against.

Close the dispatch record as soon as the role returns, per SKILL.md.

## Record the attempt

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh build-record "<task_folder>" <order id> \
  --interface <path to the record the builder wrote> \
  --report <path to the builder's report> \
  --started-at <the commit the attempt began from> \
  --test-recipe <framework>=<path to the test-execution recipe> \
  --check-recipe <framework>=<path to the review recipe> \
  [--implement-recipe <framework>=<path to the implement recipe>]... \
  [--value <name>=<value>]... \
  [--nothing-ran <literal substring>]
```
`--implement-recipe` is the path resolved above, the one the implementer was given. Pass it for
an order whose proof is `gate`: the script reads that recipe's `## Configuration gate` lines and
runs them as the order's own check. Every other order ignores it.

The commit the attempt began from is `build-brief`'s own `headNow`, read before the implementer
starts, not after. Without it nothing can tell this order's changes from what was already there.
Equal to the code repository's own current commit, or not an ancestor of it, refuses (exit 71):
either makes the range this attempt claims false.

**`build-record` refuses when the code repository's tree is not clean.** The implementer commits
its own work before it returns. A dirty tree means that commit did not happen. This attempt is not
recorded. Interactive puts that to the person. Unattended halts the order with that reason, and
a person clears it with `clear-halt` once the tree is committed, in `references/finish.md`.

**On an order whose proof is `record`, every one of those reads the project folder instead.**
The range, the empty-range refusal (exit 71), the unchanged refusal (exit 45) and the clean-tree
refusal (exit 61) all read the project folder's history. That is where the deliverable
landed, and the code repository may hold no commit at all for it. The tree read is the owned
files alone, since this stage keeps the rest of that folder uncommitted until it finishes. A
project folder with no history refuses (exit 87).

**A `record` order's diff is the task folder's alone.** AIDA commits the project folder between
a build brief and its record. A task note commits `tasks/` whole, and another task's stage
close commits its folder. None of that is the implementer's. So the owned-files check, the
review diff and the fix patch read `git diff <range> -- <task folder>`. Inside the task
folder, the files AIDA's own scripts write are set aside before the owned list is compared.
Those are `task.json`, `alignment.json`, their renderings, `design-closed.json`, and the
`research/`, `design/`, `implementation/`, `implementation-<date>-<commit>/`, `review/`,
`completion/`, `notes/` and `records/` folders. The check's detail says how many were set
aside. A person's places are `inputs/` and `deliverables/`, and a file under a stage folder is
set aside even when a person wrote it. A file under `deliverables/` is never set aside, so a
second document there that the order does not own still reads unmet.

`--test-recipe` and `--check-recipe` are paths only, one pair per framework, the same two files
`references/preconditions.md` already resolved for the baseline. The script parses `## Test
commands` and `## Check commands` itself: the suite command, the command that runs this order's
own frozen tests, and the three tool commands, each with its own argv, `{paths}` placeholder,
`signal` and `extensions` keys, and which rows a framework declares absent. Nothing here retypes a
command. A `{paths}` token expands to this order's own owned files, relative to codePath, and never
reaches a shell. For the three tool rows, the order's own frozen test files come out of that
expansion first. The implementer may not write them, so the tools judge only what it may write.
An owned file outside codePath comes out too, because a tool run in the repository cannot see
it. An owned file the order deleted comes out as well, because the tools refuse a missing path.
The detail says how many were left out, and a row with nothing left reads undeclared.
The record names the paths the token expanded to and the frozen tests left out.

**Two frameworks may not both command one tool.** The same refusal preconditions.md names (exit
72) applies here: a project whose two frameworks each carry a coding-standards row, say, gives
nothing here two answers to choose between.

**The check recipe must be the one the baseline used.** A check recipe that resolves to a
different file than the baseline read refuses (exit 73), naming both: a tool's own result is
compared against the baseline it ran against, and a changed recipe makes that comparison false.

**The record holds exactly eight checks.** Fewer refuses (exit 84), naming the absent check, and
no attempt is spent.

Pass `--value <name>=<value>` for a placeholder a command carries, the same as
`references/preconditions.md` does. Pass `--nothing-ran <literal substring>` only when the
framework's own recipe names no `silent_pass` marker of its own; where it does, the script reads
that marker and this flag is not read.

## Read the eight checks to the person

This step runs all eight deciding checks. The record holds every one.

- **order-tests.** Do this order's own frozen tests pass. On an order whose proof is `gate` this
  slot is `configuration-gate` instead. Does every `## Configuration gate` line of the
  implement recipe exit 0, run in the worktree. The first line that does not is named, with its
  output. It reads unknown when the task records no environment, when no `--implement-recipe`
  was passed, or when that recipe carries no such block. The detail says which. A line 2 that
  printed `There are no changes to import` is a finding for the reviewer, not for this check.
  On an order whose proof is `record` this slot is `done-when`. It reads the judgement the
  checkpoint left on the order's done-when row, met when confirmed, naming the judge. Nothing runs.
- **suite-regression.** Does anything that passed at the baseline now fail. A suite row the
  recipe costs `end-of-task` does not run here. The check reads `deferred`, and `finish` runs
  that row once at the final commit. On a Drupal project the row is ten minutes per run. On a
  `record` order it reads undeclared, and so do the three tool checks. A document in the task
  folder is nothing a suite or a tool reads, and the detail names the proof kind.
- **coding-standards.** Does the coding-standards tool raise anything the baseline did not already
  have.
- **static-analysis.** Does static analysis raise anything the baseline did not already have.
- **security.** Does the security tool raise anything the baseline did not already have.
- **owned-files.** Did the change stay inside the files this order owns. On a `record` order the
  change is the task folder's diff in the project folder, with the files AIDA's own scripts
  write there set aside and counted in the detail.
- **frozen-tests.** Does every frozen test file still hash to what the freeze recorded.
- **interface-record.** Does the interface record name every element the order's own declared
  interface names in backticks.

A suite or a tool the baseline recorded red does not fail these checks by itself. The check
subtracts the baseline's own output from the run now, line by line. Numbers and dots are set
aside first, so a shifted line number, a count or a duration does not read as new. No new line
is met. A new line is unmet, and the record lists the first twenty under `newLines` with the
count. The check reads unknown only when the baseline kept no output or the run printed nothing.

That is enough for a tool, which prints one line per finding. It is not enough for every suite.
PHPUnit and pytest print a progress line and a summary line that change whenever a test is added
or fixed. On the whole output, a red baseline on those still reads unmet. A test-execution
recipe's suite row may declare `failure_line`, a regular expression matching the lines that name
a failed test. Then only those lines are compared, on both sides, and the record names the
selector. With the selector, a failure that matches no line reads unknown, because it is not one
the selector names.

The subtraction holds no parser, so it cannot see four things. A finding whose text changed
reads as new. A finding fixed and reintroduced reads as old. A new finding worded like an old
one in another file reads as old. A second copy of an old finding on another line reads as old.

A failed check is not a failed order. It is this attempt's result, and the order has as many
attempts as its own allowed count says, two unless a person has granted more. The summary prints
one line per check with its verdict and a one-line reason. Say which check failed, name the record
path that holds what the tool printed, and let the person decide whether to spend the next one. Do
not read the record here.

An unknown on interface-record does not spend the attempt. The declaration named no backticked
element, so nothing there was countable, and the disagreement goes to the reviewer instead. Every
other unmet or unknown does.

**order-tests is the floor,** or `configuration-gate` on a `gate` order, or `done-when` on a
`record` order. Every other check may
answer undeclared, or deferred on the suite, and still let the order go on
to `checks-passed`, the same rule step two applies to a precondition nobody declared. order-tests
may not. It is the one check that says this order's own code does what its tests ask. Undeclared or
unknown there means nothing here ran, so the order stays at `code-written`, whatever the other
seven answered.

One order has nothing for this check to run: an order serving only criteria a person verifies.
Its frozen record carries checklist rows and no test, which design allows. order-tests answers
met there, with a detail saying so, and completion confirms the checklists. A machine-verified
criterion frozen with no test path still reads unknown, and the order stays at `code-written`.

The summary's `executed:` line says how many of the eight actually ran a command, a diff or a
hash rather than reading undeclared. Say that count to the person: eight checks answering does not
by itself say the code was tested.

The attempt counter lives in the ledger and is incremented here, and the order's state moves with
it: `checks-passed` when every check but order-tests answered met or undeclared (interface-record's
own unknown excepted) and order-tests itself answered met, `code-written` otherwise. When the
failing attempt was the last one allowed, the script writes the halt and its reason into the ledger
at that moment. It says so. Nothing here un-halts one. Go back to the skill body for what happens
to the run.
