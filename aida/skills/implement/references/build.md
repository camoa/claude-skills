# Write the code for one work order

This step runs once per work order, after that order's tests are frozen. The tests are the
reference now. Nothing below may change one.

## Resolve the recipe for this step

Dispatch `catalog-identifier` with the lines `point: implement`, each framework, and the project
folder. Skip it when an earlier step of this build has resolved it, the tests step included. Name
the role, and pass the lookup's answer in its own word: SKILL.md holds both rules. Once resolved,
reuse the path per framework for every order in this build. They live in the conversation, so a
fresh window resolves them again. **Light:** dispatch nothing here. Read each path from
`implementation/preconditions.json`, at `frameworks[].implementRecipePath`. Read its
`implementLookup` too. `not-given` means nobody asked, so dispatch the lookup for that framework,
as other modes do. A failure word means no implement recipe, so pass no path for it.

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

It reads the frozen copy and the frozen tests. It writes twelve things to
`implementation/brief-<order id>-build.json`:

- this order's own record, with the files it owns and, under `findings`, the research findings
  design used for it. Under `interfaceNames` it lists each name the declared interface holds in
  backticks. Name each one in the interface record, which the reviewer compares;
- the frozen tests for it, with the criterion each carries; a test with `criterion: null` proves
  the order's own done-when, not a criterion;
- every order it depends on, with its declared interface;
- `dependencyInformation`, each dependency's review `information` items: the id, the order it
  came from, the summary and the file;
- `reportPath`, `implementation/answers-<order id>-attempt<n>.md`, where the implementer writes
  its five answers;
- `interfacePath`, `implementation/interface-<order id>.md`, where the implementer writes its
  interface record and where `build-record` reads it;
- how many attempts this order has used of the count it is allowed;
- `previousAttempt`, present only when the order's last recorded attempt failed a check. It holds
  that attempt's number and the path of its build record. It also holds each check that stopped
  it, with its verdict, its detail and any `newLines`;
- `headNow`, the commit of the repository this order lands in at the moment of this call, and
  `commitIn`, that repository's path: the code worktree, or the project folder for an order
  whose proof is `record`;
- `playbooksPath`, the path of `records/playbooks.json` when research loaded one, else null;
- `beforeLookPath`, on an order whose proof is `observe` only: the folder the before-look goes
  in, `implementation/observed-<order id>-before/`;
- `deniedReads`, present only when the order's own text names a path the implementer's dispatch
  denies: another order's owned file. The deny stands. Do not tell the implementer to read one.
  The summary's `next` then asks a person to rule first. A file outside the code path that an
  order this one depends on owns is never denied, so a record it reads is not listed.

It prints the brief's path, the report path, the interface path, `headNow`, the attempt count
and counts, never the brief. The allowed count is two unless a person's go-on granted this order
one more; see `references/finish.md`. It is the order's own recorded allowance, never the constant alone.

**An order with nothing left to write gets no implementer.** Every file it owns is a frozen test or
support file, and every frozen test locks in, so its freeze commit holds the work. A fixture repair
is one, in `references/tests.md`. On its first attempt `build-brief` marks the brief
`nothingToWrite`, writes the report's stop and deviation lines and the declared interface as the
interface record, and its `next` says so. Dispatch nothing. Run `build-record` below with
`--started-at` as `headNow`, the freeze commit, which `build-record` reads as the attempt's range.

**No role writes a file whose name holds "report".** Claude Code refuses that write from a
subagent. So the implementer's and the fixer's files are named `answers-*`.

**A dependency that has closed carries a second text beside the declared one, `interfaceRecord`:**
what its own builder actually wrote about what it exposes. When it exists, it is what this unit's
code is written against, not the declaration alone. Three files once said the record carries
forward and none of them did; `build-brief` is what actually forwards it now.

It refuses when the tests for this order were never frozen, when an order this one depends on has
no completion record, and when the attempts are already spent. It also refuses an order past its
build: a build starts only from `tests-frozen` or `code-written` (exit 3). It refuses an order
whose done-when gained rows after the freeze until a freeze judges them (exit 120). Read a refusal
and act on it.

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
write. It also refuses for each reason `build-brief` refuses above, with the same words. Tests
never frozen exit 114 here. An order with no build brief exits 115, because the implementer then
has no answers file to write. Nothing is written. Act on the refusal first.

**Then dispatch `implementer`**, with the message SKILL.md names. Its lines are the role, the run
mode, and two paths: the `implement` recipe for its framework and the brief `build-brief` wrote.

**On an order whose proof is `record`, the brief's `commitIn` is the project folder.** The
implementer commits its owned files there and nothing else. The ledger and the briefs beside
them belong to this stage, which commits them when it finishes. The owned-files check sets them
aside and counts them in its detail, so a sweep is visible there, not a failure.

**It writes code only inside the files its order owns.** Not another order's, whatever it finds
there. A file the order shares with another order is its own too, and the rendered order tells
the implementer to add entries there only. The review diff of that file holds this order's own
commits. The dispatch record carries the list, and a hook refuses the implementer a write under
the code path outside it while the record is open. The reason tells it to stop and report.

**It may not change a test.** A test that seems wrong is a reason to stop, not to edit. A hook
refuses the write and names which order froze the file.

**It may not read another order's source.** What another unit exposes is its interface record. A
hook refuses the Read, the Grep and the plain shell reads while the dispatch is open. A path a
shell assembles at run time passes the hook and is still denied.

**It stops rather than working around anything.** A test that seems wrong, an interface that does
not fit, or the attempts running out are all stops. So is a file the unit needs and does not own.
A stop looks like this in the conversation: the role returns early. Its report's stop line names
the cause, and nothing is committed. Every report holds exactly one stop line, `Stop: none` or a
cause and its reason, and `build-record` refuses a report without one (exit 106). It refuses a
placeholder such as `Stop: pending` the same way. Under `Stop: none`, the report
also holds exactly one deviation line, `Deviation: none` or `Deviation: <what>: <why>`, and the
same refusal applies. The builder writes each line alone, and puts any note on its own line.
A deviation other than none, or a heading that starts with "Deviation", in
the report or the interface record, is a stop. A cause is a stop even
when code was committed after it. `build-record` refuses it (exit 105), records nothing and spends no
attempt. It names each commit made after the attempt began and records them on the order, so redo and
drop revert them. The order stops in both run modes. Interactive puts the stop to the person,
opening with: "The builder stopped instead of working around something, and only you may change
it. It says a test is wrong, a done-when row is wrong, the interface does not fit, it needs a file
it does not own, or its attempts ran out.
Repair that and the next attempt continues. Leave it and this unit of work stays stopped." Then
say in plain words
what the builder's report names. The person, or design, adds a file the unit needs:
`add-owned-file` on the order, design `close`, then `start` again. A wider owned list does not
stop a started order. `build-record` refuses while the order's owned or shared files in the
design differ from the snapshot (exit 117), and spends no attempt. Run `start` first. In both run
modes, `build-record` stops the order itself, so do not stop it again. A
stopped order records no attempt: `build-record` refuses it (exit 49) until a person takes a way
out. The next `start` sets aside what was left.
An order past its review records no attempt either: `build-record` refuses it (exit 3). One order
gets one review, so code after it comes from a fix round.

**A defect in a closed order's file has its own route.** The stop line reads
`Stop: closed-order-defect: <file>: <what fails>`. `build-record` finds the order that owns the
file in the snapshot. When that order is closed, the script reopens it for a repair, in both run
modes. It adds one high finding with origin `repair` to that order's review record. The finding
cites the owner's first criterion by position, and says so. The script sends the order back to its
review step and adds one fix round to its allowance, so no counter goes down. The ledger entry
keeps the repair under `repairs`, with the range the order closed with. `finished.json` carries
that range beside the new one. The script exits 0 and prints a `repair:` line. The stopped order
spends no attempt. Commits it made after it began are named, as at any stop, and recorded on the
repair entry. They stop the stopped order for a person, in both run modes. The owner's fixer works in the owner's files, and the
reviewer verifies the round. The verifier also answers whether the failure arises in that file.
A `no` makes the finding pending, and the person rules on it at the task review. So the route
runs unattended too. Follow the `next:` line to the reopened order. Run `start` first when the
builder left files uncommitted. Then fix, verify and close that order under
`references/review.md`. Until it closes, `build-brief` refuses the stopped order (exit 40). Then
build the stopped order again. Its next stop of this kind at the same attempt opens another repair
once every earlier one reads addressed. The stopped order's attempt allowance caps how many. A
file no closed order owns, or a stop past that cap, stops the order as any other stop does. Interactive,
open with: "A finished unit of work had a defect, and the next unit found it. Its own fixer
repairs it, and a reviewer checks the repair and where the defect lies. Nothing needs your
decision unless the reviewer finds the defect elsewhere." Then name the file and the reopened
order.

**A done-when row that cannot hold is no defect, so it never reopens an order.** The stop line
reads `Stop: row-wrong: <row number>: <the evidence>`. `build-record` stops as at any stop
(exit 105), and its message quotes that row from the snapshot. The person rules on the row. A
wrong row is reworded in design, and design closes again. Then `start` names the change on the
order, and a redo answers it. A row that stands goes back to the builder.
The order stops in both run modes, and the stop reason quotes the row. Each way out refuses without the
person's answer on record (exit 68), as "A person's answer" in `references/finish.md` says.

A deviation is a stop even when it departs from a play and not from the design. The line has no
kind that a script can read, so a person sees each one. The order stops in both run modes. The person may keep a deviation with
go-on `keep` ("Leave a stop" in `references/finish.md`). Then run `build-record` again with the
same flags. The build record holds the person's words, and review does not ask again about that
line. A stop line other than `Stop: none` has no keep.

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
attempt, it refuses (exit 76). Then a redo with the person's ruling sends the order back to
planned, under "Redo the order" in `references/finish.md`. Other orders may have committed since
the first freeze. The freeze still takes the new tests, because the report holds the
`Stop: test-wrong` line. The stop stopped the order in both run modes, so the freeze refuses
(exit 35) until a person goes on with `build`. The second
freeze prints `retaken:` with the earlier commit and the new one, and the record names the
earlier one under `retakenFrom`. No attempt is spent, because none was recorded. The builder's
stop left the tree dirty on purpose. The freeze commits only the test paths, and the next
attempt continues over that uncommitted build. So the person either keeps it or cleans the tree
before the re-freeze, and says which. Then build again from "Open the dispatch record" above.
After the build, a frozen test found wrong at review is ruled `test-wrong`, and a redo brings the
order back to planned, under Rulings in `references/review.md`.

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
  [--implement-recipe <framework>=<path to the implement recipe>]... \
  [--observed <path to the observed record>] \
  [--value <name>=<value>]... \
  [--nothing-ran <literal substring>]
```
`--interface` defaults to the brief's `interfacePath`, the path the implementer was told to write
to. Pass it only for a record a person put somewhere else. `--implement-recipe` is the path
resolved above, the one the implementer was given. Pass it for
an order whose proof is `gate`: the script reads that recipe's `## Configuration gate` lines and
runs them as the order's own check. Every other order ignores it. Left out on a gate order, the
recorded implement recipe that carries the block is taken from `preconditions.json`. A gate order
with no verify lines refuses (exit 3) when no recorded implement recipe carries the block. Two
recorded recipes that carry it also refuse (exit 3), so pass the one to use. Neither refusal
spends an attempt.

`--observed` is the record written above. An order whose proof is `observe` refuses without it
(exit 92). The script refuses a missing or malformed record (exit 93). It refuses a row whose
screenshot or before image is not on disk or lies outside its folder (94), naming which. It
refuses a surface the order does not name (95). It refuses a sentence the order does not hold (96). Nothing is
recorded on any of these.

The commit the attempt began from is `build-brief`'s own `headNow`, read before the implementer
starts, not after. Without it nothing can tell this order's changes from what was already there.
Not an ancestor of the code repository's current commit (exit 3), it makes the range this attempt
claims false. Equal to the current commit, the range is empty, and the attempt is recorded: the
order's tests still run on the tree. From that range the script lists the
implementer's commits in the build record. It leaves out each commit another order's records
name, in a build or fix list or as a freeze. The owned-files check reads the files those commits
change, and no range. The earlier attempts' lists move to `commitsBefore`, which review reads, so a
second attempt that changes one line is reviewed with the code the first attempt wrote. Commits a
person kept after a builder's stop go there too. The check also reads each path those commits
change that still differs, so a stray change nobody reverted still stops the attempt.
When an equal commit is this order's own freeze commit and every frozen test locks in, the
freeze commit holds the order's work. A tests order whose deliverable is its test
file is this case. So is a code order whose tests all pass on the code that is there already, and
its range then holds its test files alone. The range then starts at the parent of the freeze commit, so the
freeze commit is on the order's list.

**`build-record` refuses when the code repository's tree is not clean.** The implementer commits
its own work before it returns. A dirty tree means that commit did not happen. This attempt is not
recorded. Interactive puts that to the person, opening with: "The builder left changes in the
code that it did not commit, so this attempt cannot be recorded. Only you can say whether they
are wanted. Commit them and the attempt is recorded and checked. Discard them and the attempt
starts over." Then name the repository and
the files git lists. Unattended stops the order with that reason, and a person goes on once the
tree is committed, under "Leave a stop" in `references/finish.md`.

**On an order whose proof is `record`, every one of those reads the project folder instead.**
The range and the clean-tree refusal (exit 61) both read the project folder's history. That is where the deliverable
landed, and the code repository may hold no commit at all for it. The tree read is the owned
files alone, since this stage keeps the rest of that folder uncommitted until it finishes. A
project folder with no history refuses (exit 3).

**A `record` order's diff is the project folder's.** Its deliverable may sit beside earlier
reports outside the task folder. So the owned-files check, the review diff and the fix patch
read the listed commits over the project folder whole. AIDA commits that folder between a
build brief and its record. A task note commits `tasks/` whole, and another task's stage close
commits its folder. None of that is the implementer's, so the files AIDA's own scripts write
are set aside before the owned list is compared. Inside this task's folder those are
`task.json`, `alignment.json`, their renderings, `design-closed.json`, `COMPROMISES.md`, and
the `research/`, `design/`, `implementation/`, `implementation-<date>-<commit>/`, `review/`,
`completion/`, `notes/` and `records/` folders. Outside it, every other task's folder and `project.json`.
The check's detail says how many were set aside. A person's places are `inputs/`,
`deliverables/` and the project folders a report lands in. A file under a stage folder is set
aside even when a person wrote it. A file in a person's place is never set aside, so a second
document there that the order does not own still reads unmet.

`--test-recipe` is a path only, one per framework, the file `references/preconditions.md` already
resolved. Left out, it is taken from `preconditions.json`, here and at `fix-record`. No check
recipe is read here, because no tool row runs. An
order proved by its own tests with no test recipe on record refuses (exit 3), and no attempt or
round is spent. The script parses `## Test commands` itself: the command that runs this order's
own frozen tests, with its argv and its `{paths}` placeholder. Nothing here retypes a command. A
`{paths}` token expands to this order's own frozen test files, relative to codePath, and never
reaches a shell. No tool row and no suite runs at this step. Preconditions ran each tool once, and
review runs them over the whole task, so a tool finding never spends an attempt.

**Two frameworks may not both command one row.** The same refusal preconditions.md names (exit
72) applies here.

**The record holds exactly three checks.** Fewer refuses (exit 3), and no attempt is spent.

Pass `--value <name>=<value>` for a placeholder a command carries, the same as
`references/preconditions.md` does. A placeholder is a whole token, or part of one, such as
`gate-{project}`. It has these forms:
- `{a.b}` is the Input contract field at that dotted path. Pass `--value a.b=<value>`. For a
  list of scalars, pass one `--value a.b=<item>` per item, and the line runs once per item.
  Only the first such name in a line makes it run more than once.
- `{a.b:json}` is the whole value of the field as one JSON token. Pass
  `--value 'a.b:json=<JSON text>'`. Pass the JSON on one line. For an absent field pass
  nothing, and the token is `null`.
- `{paths}`, `{file}` and `{dirs}` are the files the order owns. The script supplies them. On
  an order that owns no file, such a line does not apply, and it never passes the order alone.

A name with no `--value` is read from the tokens preconditions recorded. It is then read from
the keys of the task's environment record, such as `project`. A check that reads unknown for a
placeholder with no value refuses at 3. `build-record`, `go-on --continue check` and `fix-record` then
write nothing, and no attempt or round is spent. A `## Configuration gate` line of a `gate` order
refuses at 3 before any check runs. The message names the token. Supply the value, then run the
same step again.

Before the verify lines run, the script writes the `## Files` blocks of the recipe they cite into
the worktree. A line can run a script the recipe ships. After the lines, it removes those
files, so the tree stays clean. A file that holds the block of an earlier version of the recipe
is replaced for the run, then put back. Any other file with different content refuses at 3.

The check's output is the log of the lines. Each line that ran starts with `+`, with every
placeholder filled. A token is in single quotes when it is empty, or when it holds a character
other than a letter, a digit, or one of `_ . / : = @ % + , -`. A line that did not run shows as
written. The failure reason quotes the line the same way. The log names each `## Files` path
written or replaced for the run. It then says which paths were removed or put back after the
run. So a script absent after the run is expected.

The site must be up before the verify lines run. A site command such as `ddev drush` starts a
stopped site and prints its start-up text. A `stdout empty` line then fails for a reason that is
not the check. So before any check runs, the script runs the `## Status` line of the task's
environment recipe in the worktree. It does this when the task records an environment and the
order has verify run lines or a configuration gate. A non-zero exit refuses (exit 3) in both run
modes, because `up` is a person's answer. The message quotes the line's first output. No check
runs and no attempt is spent. Say that the site is down, and show the message. Offer
`task environment <task-id> up`, then run the same step again. A recipe with no `## Status`
block runs no test, and a task with no environment runs none either. No line kind says that a
line leaves the site alone, so every such order is tested.

Pass `--nothing-ran <literal substring>` only when the
framework's own recipe names no `silent_pass` marker of its own; where it does, the script reads
that marker and this flag is not read.

## Run the checks again with no new build

Some rows the same code can answer differently. A test may fail for a reason outside the code, such
as a broken environment. A file the owned-files check refused may be one the order should own.
While attempts remain, the next attempt answers a failure. When the last attempt fails, the order
stops, and its reason allows `go-on --continue check` for any failed row, under "Go on" in
`references/finish.md`. Repair the cause first, or give the order the file with `--owns`. The check
runs over the recorded range, dispatches no implementer and spends no attempt. It takes
`build-record`'s recipe flags and `--interface`. A flag left out is taken from its record, and the
`filledFromRecords:` line names each one. It rewrites the record with the new checks. The replaced
checks stay under `checksBefore`, beside `recheckedAt`. When the interface record's text changed,
the attempt's own text stays under `interfaceRecordBefore`. When the code moved since the record,
it runs over the range extended to HEAD and writes a warning. It refuses (exit 63) when those
commits change a frozen test or a file the order does not own. After a fix round it runs that
round's checks again over the fix record's range, and a pass addresses the round's check finding.

## Read the three checks to the person

This step runs the three deciding checks. The record holds every one.

- **order-tests.** Do this order's own frozen tests pass. The run is as narrow as the recipe's
  machine-readable rows allow. On an order whose proof is `gate` this slot is
  `configuration-gate` instead. Does every line pass, run in the worktree. The order's
  own `verify` run entries run first, then the `## Configuration gate` lines of the implement
  recipe. The worse verdict stands. The first line that does not pass is named, with its
  output. A placeholder given several `--value` entries runs its line once per value. It reads
  unknown when the task records no environment. `task environment up` records a site the
  worktree already runs, with no bring-up. An order with no verify lines also reads
  unknown when no implement recipe was passed or recorded, or when it carries no such block.
  An order with verify lines runs them alone then, and the detail says the block did not run.
  A verify line that is not binding runs only when the person approved it at the design close.
  A gate line that printed `There are no changes to import` is a finding for the reviewer, not
  for this check. The section's second `sh` block is the put-back line. It runs after a gate
  that reached its fourth line, whatever the verdict, and never changes the verdict. When it
  fails, the detail starts with its exit. Tell the person to run that line again by hand.
  On an order whose proof is `record` this slot is `done-when`. It reads the judgement the
  checkpoint left on the order's done-when row, met when confirmed, naming the judge. Nothing runs.
  On an order whose proof is `observe` this slot is `observed`. It reads the record you wrote
  above, met when every row is met, naming the judge, a model. One unmet row stops the attempt
  the way a failing test does.
  On an order whose proof is `confirm` this slot is `confirm-at-review`. It reads deferred. The task has
  no automated tests, so nothing runs, and the person confirms the order's done-when rows at
  review. Deferred passes here, in this slot alone. On every kind but `gate`, the order's own
  `verify` run entries
  then run in this slot, from the code worktree. The slot is met only when its own answer and
  every line are. The detail names the source.
- **owned-files.** Did the order's own commits stay inside the files this order owns. On a
  `record` order the change is the task folder's diff in the project folder, with the files AIDA's
  own scripts write there set aside and counted in the detail.
- **frozen-tests.** Does every frozen test file still hash to what the freeze recorded. An order
  that froze none reads undeclared, because the row hashed nothing, and the executed count does
  not count it.

A failed check is not a failed order. It is this attempt's result, and the order has as many
attempts as its own allowed count says, two unless a person's go-on granted more. The summary prints
one line per check with its verdict and a one-line reason. Say which check failed, in plain words,
and name the record path that holds what the check printed. Do not read the record here. Then
brief the next attempt, in both run modes. Do not ask whether to spend it: the attempt cap and the
run budget bound the attempts, and a person can stop the run at any time.

Every unmet or unknown fails the attempt. Every attempt counts against the allowed number,
whatever the checks said.

**order-tests is the floor,** or `configuration-gate` on a `gate` order, or `done-when` on a
`record` order. The other two checks may
answer undeclared and still let the order go on to `checks-passed`. Step two applies the same rule
to a precondition nobody declared. order-tests may not. It is the one check that says this order's
own code does what its tests ask. Undeclared or unknown there means nothing here ran, so the order
stays at `code-written`, whatever the other two answered.

One order has nothing for this check to run: an order serving only criteria a person verifies.
Its frozen record carries checklist rows and no test, which design allows. order-tests answers
met there, with a detail saying so, and review's close confirms the checklists. A machine-verified
criterion frozen with no test path still reads unknown, and the order stays at `code-written`.

The summary's `executed:` line says how many of the three actually ran a command, a diff or a
hash rather than reading undeclared. Say that count to the person: three checks answering does not
by itself say the code was tested.

The attempt counter lives in the ledger and is incremented here, and the order's state moves with
it: `checks-passed` when the other two checks answered met or undeclared and order-tests itself
answered met, `code-written` otherwise. When the
failing attempt was the last one allowed, the script writes the stop and its reason into the
ledger at that moment. It says so. Nothing here takes the order out of its stop. Go back to the
skill body for what happens to the run.
