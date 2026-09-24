# Write the code for one work order

This step runs once per work order, after that order's tests are frozen. The tests are the
reference now. Nothing below may change one.

## Resolve the recipe for this step

Dispatch `catalog-identifier` with the lines `point: implement`, each framework, and the project
folder. Skip it when an earlier step of this build has resolved it, the tests step included. Name
the role, and pass the lookup's answer in its own word: SKILL.md holds both rules. Once resolved,
reuse the path per framework for every order in this build. No record holds these paths. They
live in the conversation, so a fresh window resolves them again.

This recipe carries the rules applied while code is written. The implementer opens it itself, from
the path. Do not read the body here.

Do not give the test-authoring recipe to the implementer. It chooses a level and names a test, and
this reader may do neither. When the tests step resolved its path, pass that path to
`dispatch-open` as `--deny-read`. An order whose `lookups=` holds no `test-authoring` resolved
none, so pass nothing then.

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

It reads the frozen copy and the frozen tests. It writes ten things to
`implementation/brief-<order id>-build.json`:

- this order's own record, with the files it owns;
- the frozen tests for it, with the criterion each carries; a test with `criterion: null` proves
  the order's own done-when, not a criterion;
- every order it depends on, with its declared interface;
- `dependencyInformation`, each dependency's review `information` items: the id, the order it
  came from, the summary and the file;
- this attempt's report path;
- `interfacePath`, `implementation/interface-<order id>.md`, where the implementer writes its
  interface record and where `build-record` reads it;
- how many attempts this order has used of the count it is allowed;
- `headNow`, the commit of the repository this order lands in at the moment of this call, and
  `commitIn`, that repository's path: the code worktree, or the project folder for an order
  whose proof is `record`;
- `playbooksPath`, the path of `records/playbooks.json` when research loaded one, else null;
- `beforeLookPath`, on an order whose proof is `observe` only: the folder the before-look goes
  in, `implementation/observed-<order id>-before/`.

It prints the brief's path, the report path, the interface path, `headNow`, the attempt count
and counts, never the brief. The allowed count is two unless a person has granted this order one more; see
`references/finish.md`. It is the order's own recorded allowance, never the constant alone.

**A dependency that has closed carries a second text beside the declared one, `interfaceRecord`:**
what its own builder actually wrote about what it exposes. When it exists, it is what this unit's
code is written against, not the declaration alone. Three files once said the record carries
forward and none of them did; `build-brief` is what actually forwards it now.

It refuses when the tests for this order were never frozen, when an order this one depends on has
no completion record, and when the attempts are already spent. Read a refusal and act on it.

That list is the withheld list.

## On an order whose proof is `observe`, look before the build

A done-when row often says the page is as it was apart from one thing. That row needs a before
to judge from, and a script cannot tell which rows say it. So every observe order gets a look
before the build. Take the same surfaces at the same viewports as the look after, at the
brief's `headNow`, before the implementer is dispatched. The viewport and destination rules are
the look after's, below. Save each image as
`<task_folder>/implementation/observed-<order id>-before/<surface>-<viewport>.png`. That is the
brief's `beforeLookPath`. Write no verdict; the images are the before.

One before-look per order, at the first attempt's `headNow`. The brief prints `beforeLook:`
with `(owed)` while the folder holds no image and `(taken)` once it does. A later attempt and
every fix round reuse the images that are there; take them once. Each row of the observed
record names its before image, and `build-record` refuses one not on disk or outside that
folder (exit 94).

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

**Then dispatch `implementer`**, with the message SKILL.md names. Its lines are the role, the run
mode, and two paths: the `implement` recipe for its framework and the brief `build-brief` wrote.

**On an order whose proof is `record`, the brief's `commitIn` is the project folder.** The
implementer commits its owned files there and nothing else. The ledger and the briefs beside
them belong to this stage, which commits them when it finishes. The owned-files check sets them
aside and counts them in its detail, so a sweep is visible there, not a failure.

**It writes code only inside the files its order owns.** Not another order's, whatever it finds
there. The dispatch record carries the list, and a hook refuses the implementer a write under the
code path outside it while the record is open. The reason tells it to stop and report.

**It may not change a test.** A test that seems wrong is a reason to stop, not to edit. A hook
refuses the write and names which order froze the file.

**It may not read another order's source.** What another unit exposes is its interface record. A
hook refuses the Read, the Grep and the plain shell reads while the dispatch is open. A path a
shell assembles at run time passes the hook and is still denied.

**It stops rather than working around anything.** A test that seems wrong, an interface that does
not fit, or the attempts running out are all stops. So is a file the unit needs and does not own.
A stop looks like this in the conversation: the role returns early, its report names what stopped it,
and nothing is committed. Interactive puts the stop to the person,
opening with: "The builder stopped instead of working around something, and only you may change
it. It says a test is wrong, the interface does not fit, it needs a file it does not own, or its
attempts ran out.
Repair that and the next attempt continues. Leave it and this unit of work stays stopped." Then
say in plain words
what the builder's report names. The person, or design, adds a file the unit needs:
`add-owned-file` on the order, design `close`, then `start` again. A wider owned list does not
halt a started order. Unattended halts the order and records what was left.

The interface record is prose about what this unit exposes, and it is what the next order's
tests are written against.

**When the person rules that the test is wrong, the route is the tests step again, in this
order.** The person rules it; a model never does. Open the test author's dispatch again for this
order, per `references/tests.md`. The write hook lets that author edit the file its own order
froze. It corrects the assertion and nothing else. Run the coding-standards row over the file it
returned. Open the row-checker's dispatch again and put the affected rows to it. Then run
`tests-freeze` again, with every flag the first freeze took, the new red run, and the rows the
checker returned. That freeze is
allowed only while the order is still at `tests-frozen`. Once `build-record` has recorded an
attempt, it refuses (exit 76). The
retake prints `retaken:` with the earlier commit and the new one, and the record names the
earlier one under `retakenFrom`. No attempt is spent, because none was recorded. The builder's
stop left the tree dirty on purpose. The freeze commits only the test paths, and the next
attempt continues over that uncommitted build. So the person either keeps it or cleans the tree
before the re-freeze, and says which. Then build again from "Open the dispatch record" above.
After the build, a frozen test found wrong at review is ruled `test-wrong`, and `retake-tests`
brings the order back here, under Rulings in `references/review.md`. There the attempt counter
stays.

Close the dispatch record as soon as the role returns, per SKILL.md.

## On an order whose proof is `observe`, look at the pages

The implementer does not look. You do. Read the surface file that `surfaces.registryPath` in
`<projectPath>/project.json` names. Review's surface step reads the same file. Take each
surface the order names, its `url`, and the file's `viewports` list. Open each surface at each
viewport with the browser tool, against the task's own site.

The viewport is the requirement: the page must render at the viewport's width. Resizing the
browser window is not that, because the page can still render wider than the window. A tool
that reaches a small width does so by device emulation.

When the implementer's report says it ran the configuration gate, or any restore of the seed
snapshot, the site holds only the seed's content. It stays so until the recipe's restore or
rebuild step has run, and the look waits for that step. A note on a row judged against stale
content is a lie.

Judge each of the order's done-when rows against what renders, and each `check` entry of its
`verify` list whose `kind` is `live-site` the same way. A row that says the page is as it was is judged against the before
image of that surface and viewport. Also judge the
`verification` clause of each machine criterion the order owns, as a row of its own beside the
done-when rows. The snapshot's criteria hold the clause. The done-when rows may say less than
the clause, and no script can compare the two, so the look judges the clause itself. Such a row
carries `criterion` with the id, and `build-record` refuses a clause row without it (exit 96).
Give one verdict per row per surface per viewport, `met` or `unmet`, with one sentence on what
you saw. Save each
screenshot under `<task_folder>/implementation/observed-<order id>/<surface>-<viewport>.png`.
The screenshot must lie under that folder, and `build-record` refuses one that does not (exit
94). A tool that refuses to write there writes into a folder inside the worktree. Move the
file, then remove that folder before you record the attempt, because the tree check reads it.
Then write `<task_folder>/implementation/observed-<order id>.json`:
```
{ "order": "<order id>", "observedAt": "<YYYY-MM-DD>", "judgedBy": "model",
  "rows": [ { "doneWhen": "<the row, verbatim>", "surface": "<id>", "viewport": "<name>",
              "screenshot": "<absolute path>", "before": "<absolute path of the before image>",
              "verdict": "met|unmet", "note": "<what you saw>" },
            { "doneWhen": "<the criterion's verification clause, verbatim>", "criterion": "<c-id>",
              "surface": "<id>", "viewport": "<name>", "screenshot": "<absolute path>",
              "before": "<absolute path>", "verdict": "met|unmet", "note": "<what you saw>" } ] }
```
Every done-when row, every live-site verify check and every owned clause goes in, at every
surface and viewport, and `build-record` refuses a record missing one (exit 97). The verdict is what the page
showed, never what the report claims. Pass the record as `--observed` below. Nothing is frozen
for such an order and no row was judged before the build, so this look is its check. The judge
on the record is a model. Completion puts each such criterion to the person.

## Record the attempt

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh build-record "<task_folder>" <order id> \
  [--interface <path to the record the builder wrote>] \
  --report <path to the builder's report> \
  --started-at <the commit the attempt began from> \
  --test-recipe <framework>=<path to the test-execution recipe> \
  --check-recipe <framework>=<path to the review recipe> \
  [--implement-recipe <framework>=<path to the implement recipe>]... \
  [--observed <path to the observed record>] \
  [--value <name>=<value>]... \
  [--nothing-ran <literal substring>]
```
`--interface` defaults to the brief's `interfacePath`, the path the implementer was told to write
to. Pass it only for a record a person put somewhere else. `--implement-recipe` is the path
resolved above, the one the implementer was given. Pass it for
an order whose proof is `gate`: the script reads that recipe's `## Configuration gate` lines and
runs them as the order's own check. Every other order ignores it.

`--observed` is the record written above. An order whose proof is `observe` refuses without it
(exit 92). The script refuses a missing or malformed record (exit 93). It refuses a row whose
screenshot or before image is not on disk or lies outside its folder (94), naming which. It
refuses a surface the order does not name (95). It refuses a sentence the order does not hold (96). Nothing is
recorded on any of these.

The commit the attempt began from is `build-brief`'s own `headNow`, read before the implementer
starts, not after. Without it nothing can tell this order's changes from what was already there.
Equal to the code repository's own current commit, or not an ancestor of it, refuses (exit 71):
either makes the range this attempt claims false.

**`build-record` refuses when the code repository's tree is not clean.** The implementer commits
its own work before it returns. A dirty tree means that commit did not happen. This attempt is not
recorded. Interactive puts that to the person, opening with: "The builder left changes in the
code that it did not commit, so this attempt cannot be recorded. Only you can say whether they
are wanted. Commit them and the attempt is recorded and checked. Discard them and the attempt
starts over." Then name the repository and
the files git lists. Unattended halts the order with that reason, and
a person clears it with `clear-halt` once the tree is committed, in `references/finish.md`.

**On an order whose proof is `record`, every one of those reads the project folder instead.**
The range, the empty-range refusal (exit 71), the unchanged refusal (exit 45) and the clean-tree
refusal (exit 61) all read the project folder's history. That is where the deliverable
landed, and the code repository may hold no commit at all for it. The tree read is the owned
files alone, since this stage keeps the rest of that folder uncommitted until it finishes. A
project folder with no history refuses (exit 87).

**A `record` order's diff is the project folder's.** Its deliverable may sit beside earlier
reports outside the task folder. So the owned-files check, the review diff and the fix patch
read `git diff <range>` over the project folder whole. AIDA commits that folder between a
build brief and its record. A task note commits `tasks/` whole, and another task's stage close
commits its folder. None of that is the implementer's, so the files AIDA's own scripts write
are set aside before the owned list is compared. Inside this task's folder those are
`task.json`, `alignment.json`, their renderings, `design-closed.json`, and the `research/`,
`design/`, `implementation/`, `implementation-<date>-<commit>/`, `review/`, `completion/`,
`notes/` and `records/` folders. Outside it, every other task's folder and `project.json`.
The check's detail says how many were set aside. A person's places are `inputs/`,
`deliverables/` and the project folders a report lands in. A file under a stage folder is set
aside even when a person wrote it. A file in a person's place is never set aside, so a second
document there that the order does not own still reads unmet.

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

## Re-run the checks

An attempt can fail on the three tool rows alone: coding-standards, static-analysis and
security. A tool refusing a path it was handed is the plugin's fault, not the implementer's.
Such an attempt needs no second build. `build-brief` would hand over a brief with nothing to
build. `build-record` would refuse the empty range (exit 71) or the unmoved head (exit 45).
Run the checks again over the recorded range instead:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh build-recheck "<task_folder>" <order id> \
  --test-recipe <framework>=<path to the test-execution recipe> \
  --check-recipe <framework>=<path to the review recipe> \
  [--implement-recipe <framework>=<path to the implement recipe>]... \
  [--value <name>=<value>]... \
  [--nothing-ran <literal substring>]
```
The recipe flags are `build-record`'s. The range, the interface record and the report path are
read from the build record, so none is passed. No implementer is dispatched and no attempt is
spent. The `next:` line offers this route beside `build` when the last attempt was stopped by
the tool rows alone.

It refuses (exit 88) in four cases, each with its own message. No build record exists for the
order. The code repository's HEAD is not the record's own commit, because the code moved, and
the route is `build`. Or a check outside the three tool rows stopped the attempt. A test or a
suite that failed is the implementer's work, so a re-check is not a free retry, and the route is
`build`. Or no check stopped the attempt, so it passed and the order is past the build. A
halted order refuses (exit 49), and `references/finish.md` names the grant. The
clean-tree rule applies (exit 61).

It rewrites the record with the new checks and keeps the attempt, its range and its date. The
replaced checks stay under `checksBefore`, id and verdict only, beside `recheckedAt`. The
attempt counter does not move. The order goes to `checks-passed` when the checks pass and stays
at `code-written` otherwise. The summary has `build-record`'s shape plus a `recheck:` line.

## Read the eight checks to the person

This step runs all eight deciding checks. The record holds every one.

- **order-tests.** Do this order's own frozen tests pass. On an order whose proof is `gate` this
  slot is `configuration-gate` instead. Does every line pass, run in the worktree. The order's
  own `verify` run entries run first, then the `## Configuration gate` lines of the implement
  recipe. The worse verdict stands. The first line that does not pass is named, with its
  output. A placeholder given several `--value` entries runs its line once per value. It reads
  unknown when the task records no environment. An order with no verify lines also reads
  unknown when no `--implement-recipe` was passed, or when that recipe carries no such block.
  An order with verify lines runs them alone then, and the detail says the block did not run.
  A verify line that is not binding runs only when the person approved it at the design close.
  A line 2 that printed `There are no changes to import` is a finding for the reviewer, not
  for this check.
  On an order whose proof is `record` this slot is `done-when`. It reads the judgement the
  checkpoint left on the order's done-when row, met when confirmed, naming the judge. Nothing runs.
  On an order whose proof is `observe` this slot is `observed`. It reads the record you wrote
  above, met when every row is met, naming the judge, a model. One unmet row stops the attempt
  the way a failing test does. On every kind but `gate`, the order's own `verify` run entries
  then run in this slot, from the code worktree. The slot is met only when its own answer and
  every line are. The detail names the source.
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
- **frozen-tests.** Does every frozen test file still hash to what the freeze recorded. An order
  that froze none reads undeclared, because the row hashed nothing, and the executed count does
  not count it.
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
one line per check with its verdict and a one-line reason. Interactive, open with: "This attempt
at the work failed one of the checks, and another attempt is allowed. Spending it is your
call, because each attempt costs a dispatch. Say yes and the builder tries again from this
code. Say no and the work stays where it is until you return." Then say which check failed,
in plain words, and name the record path that holds what the tool printed. Do not read the
record here.

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
met there, with a detail saying so, and review's close confirms the checklists. A machine-verified
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
