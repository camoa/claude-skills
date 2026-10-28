# Review, fix and verify one work order

This step runs once an order reaches `checks-passed`. It reviews the code, repairs what a review
finds, and closes the order once nothing actionable is left open.

## Resolve the recipe for this step

Read the `test-execution` and `review` recipe paths from the records preconditions already wrote,
instead of asking the navigator again. `implementation/preconditions.json` holds the
test-execution recipe at `frameworks[].recipePath`, and `implementation/baseline.json` holds the
review recipe at `checkRecipes[].path`, one per framework. A framework absent from a list had no
recipe at the baseline; pass no flag for it. These are the same paths `references/build.md` read
for this order. Pass the test recipe straight through to `fix-record` below, in the fix section; the script
reads their command blocks itself, per SKILL.md. A fresh lookup could only agree with the record
or fail.

## Review

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh review-brief "<task_folder>" <order id>
```
It refuses when the order is not at `checks-passed`, when the order is stopped, or when a review
record already exists for it. **One order gets one review, ever.** Read a refusal and act on it.

It writes `implementation/brief-<order id>-review.json`:

- the criteria this order serves and owns, and the non-goals;
- the order record;
- the diff as a path. It holds the commits the order's build and fix records list, the earlier
  attempts' lists included. So every build attempt is in it, and another order's commit stays
  out. A record written before the lists has its list read from its own range;
- the frozen tests, and the builder's report path; on an order whose proof
  is `record` the diff is the project folder's whole, and `deliverables` names
  each owned file by path. The reviewer reads the document whole rather than a patch;
- the three check results;
- both interface texts, and `recordBefore` when go-on's check read an amended record;
- the path the reviewer's findings go to;
- `playbooksPath`, the path of `records/playbooks.json` when research loaded one, else null;
- `recipes`, the implement recipe for each framework, which the reviewer answers one by one.

It prints the brief's path, the diff path, the findings path and the report path. It prints one
line per check with its verdict, and counts. Never the brief.

No script compares the builder's interface record with the declared interface. The brief carries
both texts, unchanged, and the reviewer compares them. Ask the person nothing about them, in
either mode. A person shown the two texts would be making the comparison the reviewer is about
to make, from the same texts (live-run row 88).

After go-on's check read an amended interface record, the brief's `interface` also holds
`recordBefore`, the text the attempt recorded. The reviewer reads both records beside the
declaration. An amendment that names an element the diff does not expose is a finding.

Open a dispatch record for the reviewer before dispatching it, with nothing denied and nothing
allowed:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh dispatch-open "<task_folder>" reviewer <order id>
```
The reviewer holds Write, for its own findings file, and the frozen-test write hook only enforces
the freeze while a dispatch record is open. With no record open, that hook reports itself
not enforced for the whole review, and a write into a frozen test is caught only afterward, as a
dirty tree. The empty lists still let the hook see this dispatch and protect every frozen test
against it, the same way the freeze protects it against everyone else.

**Dispatch `reviewer`**, on opus, with the message SKILL.md names: the role, the run mode, and the
brief's path. The brief's own `mode` field says review. Its read is wide by design, one named
file outside the diff for one named risk. Close the dispatch record as soon as it returns, per
SKILL.md. Its write is refused by the script, not by a hook, when the tree is dirty. Leaving a
probe file behind is a refusal, not a finding. Code that moved while it ran is a warning in the
task record, unless it changes a frozen test or a file the order does not own (exit 63).

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh review-record "<task_folder>" <order id> \
  --findings <path to the reviewer's findings file>
```
It refuses when a review record already exists for this order, unless the ledger never moved past
`checks-passed`: a crash between writing the record and writing the ledger leaves that one state,
and this call then finishes the write rather than refusing forever. It also refuses when the code
path moved, or its tree is dirty, since the build record. A commit that another order's record
holds, on that order's files alone, does not count as a move. And it refuses when the findings file
named by `--findings` is missing, empty, or not the shape it reads. A finding citing neither a
criterion nor a non-goal, or an id the contract does not hold, is recorded but never reaches a
fixer.

The findings file may carry an `information` list beside `findings`. It holds what the reviewer
saw that the person or the next order needs, and that cites no criterion the diff fails. Each
item is an id, one sentence, a file and lines, with no severity and no fix scope. The script
refuses a malformed item (exit 52), the way it refuses a malformed finding. It records the list
beside the findings and prints one `information:` line per item, then a count. `tests-brief` and
`build-brief` carry the items to every order that depends on this one, under
`dependencyInformation`. Nothing routes an item to a fixer. Read the lines; a person may need to
act on one outside this task.

A departure the builder declared never closes clean, whatever the review holds. The script scans
the latest attempt's report and the interface record in its build record, the way `build-record`
does. A recipe the reviewer answers `departed` is a hit too, unless its `finding` names an
actionable finding with a fix scope. That departure opens a fix round like any finding, in both run modes. The verifier
answers `departureCured`, and a `no` waits for the person. With no `finding`, the script pairs the
one such finding on a file the evidence names, and prints a `paired:` line. Exit 52 refuses a
`finding` on another verdict, or one that names no finding in the file. It also refuses a finding
on a file the evidence does not name, and two candidates for one answer. The findings file answers each item of the brief's
`recipes` once. Otherwise the script refuses (exit 3): run `review-brief` again for this order,
then dispatch the reviewer again. On a hit it refuses (exit 107), writes no review record, and
stops the order for design drift. The stop reason names the file and the line number, or the
recipe.
What is wrong is the design, or a recipe it relies on, so no fixer can repair it. Put it to the
person, opening with: "What was built departs from the design of this unit of work. Only you can
say which one stands. Change the design and the unit is built again. Keep the departure and the
review goes on." Then say what that line or that recipe answer says. To
change the design, amend the order in design and close design, then offer the redo in
`references/finish.md`. To keep the departure, go on with `keep`
("Leave a stop" in `references/finish.md`), then run `review-record` again with the same
`--findings`. The review record holds the person's words, and the order goes on as below. The
order stops in both run modes. A finding the reviewer marks `declaredDeparture` is that same
departure. When a person keeps the departure, here or at `build-record`, each marked finding is
ruled `wrong` with their words. The other findings take the fix round. Once the record holds the
keep, the person may rule any open finding with `verify-record --ruling`, before any fix round. That ruling
refuses without the person's answer on record (exit 55). Without a kept departure, it refuses a finding that has a fix scope
(exit 3).

An information item the reviewer marks `departsFromDesign` true is a note, not a finding. It never
stops the order or the orders after it, in either run mode. `review-record` holds it as
`deviationPending` and prints a `departurePending:` line. The person decides it at the task
review: keep it or rebuild. It waits only when no departure above was found, so it never hides one.
The record holds one departure. So when a departure above was found, the item is not put to the
person; it stays in the record's `information` list only.

Unattended, a finding that hits a non-goal stops the order there, naming the non-goal. A person
goes on with `fix` or `close` once they have ruled, under "Leave a stop" in
`references/finish.md`. Interactive,
it is actionable like any other finding, and it goes to the person with the rest. No open
actionable finding: the order is reviewed and clean, so go to Close.

Interactive, the script also prints one `unrouted:` line per finding of medium or higher
severity that cites no id, then a count line. Nothing prints when there are none. Such a finding
has no route inside this task. `fix-brief` hands a fixer open actionable findings only, and has
nothing to do when there are none. A hand fix after the review record is a warning at `close`,
and review never reads it, so nobody fixes it by hand before the close. A new order needs a criterion to
serve, and this finding cites none. `finish` carries only findings ruled deferred into
`finished.json`, so the review stage sees this one only if its own reviewer finds it again. When an
`unrouted:` line prints, put it to the person, opening with: "The reviewer found a problem this task
has no criterion or non-goal for, so nothing here will fix it. Only you can say what happens to it.
Close as recorded: the finding stays in the order's review record, and the order closes. Track it as
a task, then close: a follow up task takes it as its goal, and the order closes." Then say each
finding in plain words and name its file. A yes to the second answer is the person's ask for
that task, so run, once per finding said yes to:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/task/scripts/task-actions.sh --run-mode interactive \
  create --project "<projectPath>" --name "<task-id>-<finding id>" \
  -- <the finding's evidence, then one sentence naming the finding, the order and the file>
```
That is the id and the goal completion gives a leftover finding, in `docs/stages/completion/follow-ups.md`. Show
the whole output, and do not enter the new worktree. Then go to Close in either answer.
Unattended, nothing prints, and the record holds them.

## Fix, one round at a time

Repeat this section while an actionable finding is open and a fix round remains.

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh fix-brief "<task_folder>" <order id> \
  [--allow <path relative to codePath>]...
```
It refuses when nothing is open, when the rounds are spent, when the order is stopped, or when the
last fix round has not been verified yet. A resumed run hits that last refusal most. A round
recorded but never carried through `verify-record` still counts as open, so the next round may not
start over it. It also refuses (exit 53) when every open finding has an empty fix scope. Such a
finding asks for no code change, so a fixer could change nothing. The message names the route, a
ruling with no round, under Rulings below. It writes `implementation/brief-<order id>-fix-<round>.json`:

- the open findings in severity order, with their evidence, each with `withheld`, the paths of
  its fix scope the fixer does not get;
- the union of their fix scope, holding only paths inside the order's owned files and the
  paths `--allow` names;
- `allowedFiles`, the `--allow` list;
- the frozen tests;
- `reportPath`, `implementation/answers-<order id>-fix<round>.md`, and the order's diff budget;
- the round number;
- `headNow`, the code repository's own commit at the moment of this call, or the order's last
  record when commits came after it, so the round holds them. A later commit that changes only
  another order's files is that order's, so the round begins after each one that comes first. The
  first round after a closed-order-defect reopens the order begins at the current commit, when
  each later commit is in another order's record or only on the stopped order's files. A second
  call for one round keeps the first brief's `headNow`;
- `playbooksPath`, the path of `records/playbooks.json` when research loaded one, else null.

It prints the brief's path, the report path and `headNow`. It prints one line per finding with its
severity and what it cites, and the scope. Never the evidence. Then `withheld(<id>): <paths>`
per finding that lost a path, and `allowed:` with the `--allow` paths, or `none`.

**A fix scope outside the order's files.** `review-record` printed `outsideOwned: <id>: <paths>`
for each finding whose fix scope names a file the order does not own. It stored the list on the
finding. `fix-brief` withholds those paths from the fixer. A person may grant one with `--allow`,
one flag per path. The path joins the scope union and the brief records it under `allowedFiles`.
The fixer's dispatch record carries it, and the owned-files check after the round accepts it.
`--allow` refuses without the person's answer on record (exit 100). A path the order owns needs no grant. When no fix
scope names it, it joins the scope union in any round, and not `allowedFiles`. A finding with
origin `repair` needs this, because its fix scope is the one file the stopped build named.
Three paths refuse (exit 3):

- a frozen test or a support file;
- an owned path that a fix scope already names;
- a path outside the order's files that no open finding's fix scope names.

**A file a closed order owns** is never this order's to change. Grant it alone, and `fix-brief`
reopens the closed order for one repair round. That order gets one finding on the file and one
more fix round. When tests prove it, its test author first writes one failing test of the bug. The
`repair:` line names it. This order gets no brief. `fix-brief` on it refuses (exit 40) until the
closed order closes again. Then run `fix-brief` on it again.

A finding whose whole fix scope is withheld is still handed over. The fixer reports it
scope-insufficient in round one, and the ruling route below opens for it. When an
`outsideOwned:` line printed, put it to the person before running `fix-brief`. Open with: "A review finding wants a change in a
file this order does not own. Only you can allow that. Allow the file and the fixer may change
it. Withhold it and the fixer reports the finding, and you rule on it after the round." Then
name the finding and the files.

**The repair round.** At the cap, a light order gets one more round, once, for three kinds of open
finding. The first is new breakage that the last round made. The fix caused it, so the order's own
scope can repair it, and the round opens unattended too. The second is a finding that the last
fixer reported scope-insufficient, when a person is present and grants paths with `--allow`.
The third is a finding the verifier read not-addressed in the last round, when a person is
present. A commit that answers the verifier then gets a fresh verifier, not a ruling. A person is
present when the task's implement stage is interactive. A light task reads unattended until
`task set-run-mode` sets it interactive. In
that round `--allow` may name a path that no fix scope names, because the fixer's report names
it. A path only an open order owns refuses (exit 3). `fix-brief` opens the round only when the round
can take every open finding. The ledger records it, and the order's allowed rounds rise by one.
Otherwise `fix-brief` refuses (exit 54), and the message names what to rule or allow first. A second `fix-brief` call
reuses the open repair round, so a mistyped `--allow` can be corrected. A second repair round
never opens.

Open the dispatch record before dispatching:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh dispatch-open "<task_folder>" fixer <order id> \
  --deny-read <path of the recipe that writes the tests>
```
The script derives the rest itself, the same way it does for the implementer: this order's owned
files allowed, every other order's denied. The record's `ownedFiles` holds the order's files plus
this round's `allowedFiles`, read from the fix brief. It refuses when no fix brief exists for the
round. Deny the test-authoring recipe by hand, the same way
build.md does for the implementer: a fixer chooses no level and names no test, so that recipe is
not its to read.

**Dispatch `fixer`**, with the message SKILL.md names: the role, the run mode, and the brief's
path. Round one runs on sonnet. Round two runs on opus, set on the Agent call.
**It may not change a test**: a hook refuses the write. **It may not write outside the fix
scope.** The write hook refuses it a write under the code path outside the record's `ownedFiles`.
Its reason tells it to report the finding scope-insufficient. A write inside those files but
outside the scope is not caught there. It surfaces when the reviewer's verify mode reads the fix
diff and reports it under `outOfScope`.

Close the dispatch record as soon as it returns, per SKILL.md.

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh fix-record "<task_folder>" <order id> \
  --report <path to the fixer's report> \
  --started-at <the commit the round began from> \
  --test-recipe <framework>=<path to the test-execution recipe> \
  [--implement-recipe <framework>=<path to the implement recipe>]... \
  [--value <name>=<value>]... \
  [--nothing-ran <literal substring>] \
  [--scope-insufficient <finding id>=<reason>]...
```
`--test-recipe` is the path resolved above, one per framework. The script parses it itself, the
same way `build-record` does. `--implement-recipe` is the path
build.md names, and an order whose proof is `gate` reads it here for the same reason. Left out, it is
taken from `preconditions.json`, the same as at the build step. When two frameworks command one
row, the first in project.json runs it, with a warning. `--value` and `--nothing-ran` work the same way they do at the build step.
`--scope-insufficient` is repeatable, one per finding the fixer's report names as needing more
scope than it had. Interactive puts each one to the person, opening with: "The fixer says this
review finding needs a change in files it was not allowed to edit. Only you can allow that. Allow
the files with `fix-brief --allow`, and the next round can fix it. Or rule on it now, under
Rulings below.
That is for a finding no round can reach. A frozen test, a check only you can make, or a
change the order's done-when does not allow." Then say the finding in plain words and name the files
it asked for. The order stops in both run modes, naming the finding. The person goes on with `fix`, and
`go-on --owns` gives the order the file the fixer needed, under "Leave a stop" in
`references/finish.md`.

The commit the round began from is `fix-brief`'s own `headNow`. Not an ancestor of the current
commit refuses (exit 3), the rule `build-record` applies. Equal to it, the round is recorded with
no commit. The round is spent, and the checks run at HEAD. A fixer that did nothing gets
not-addressed verdicts, so the finding stays open. `fix-record` marks each
already-correct finding with `alreadyCorrectInRound`. Its `alreadyCorrect:` line names them.
The cited file must exist at HEAD. When it changed since the review, the verifier reads its
cited code at HEAD and the report's run for it, and addressed closes the finding. So no ruling is
needed for a finding that is real and already fixed. When it is unchanged since the review, the
claim disputes the reviewer. An addressed reading then makes the finding pending for a person, and
an unattended order stops. Each `--scope-insufficient` needs a line
`Outcome: <id>: scope-insufficient` in the report, and the verifier may not read that finding
addressed in that round (exit 52). A round with no commit addresses no check finding. With a person
present, a finding the verifier read not-addressed at the cap goes to the repair round above.
There the fixer can report it already correct with its run.
A task site that is down refuses (exit 3) before any check runs, as build.md says for `build-record`.

**`fix-record` refuses when the code repository's tree is not clean.** The fixer commits its own
work before it returns. A dirty tree means that commit did not happen. This round is not recorded.
Interactive puts that to the person, opening with: "The fixer left changes in the code that it
did not commit, so this round cannot be recorded. Only you can say whether they are wanted.
Commit them and the round is recorded and checked. Discard them and the round starts over." Then
name the repository and the files git
lists. Unattended
stops the order with that reason.

This re-runs the three checks, with the same order-tests floor build.md names. On a
`gate` order the floor is `configuration-gate`, and on a `record` order `done-when`. A `record`
order's range, tree and diff read from the project folder, as build.md says. Undeclared or unknown
there still spends the round, even when the other two are undeclared. A check answering unmet or unknown
spends the round and leaves every finding open. `review-brief` is never run again for this order.
`verify-record` then opens one finding for that check, with origin `check`, on the order's first
criterion and its owned files, at medium. The verifier does not see it. The next round's checks decide it: all met
addresses it, and a failure keeps it open. At the cap it follows the same rules as any other
finding: a ruling, a stop, or pending on a light task.

A check can stop the round for a cause outside the fix range. Examples are a broken environment,
or a file the order should own. The next round answers it while rounds remain. At the cap,
unattended, the order stops, and when every open finding is a check finding the stop allows
`go-on --continue check`. Repair the cause first, or give the order the file with `--owns`. It
runs the round's checks again over the unchanged range, as references/build.md says. A pass
addresses the check finding, open or pending, and clears the stop. A check that fails again
leaves both in place.

A repeat call at a commit this round already recorded reports that record, and finishes the
write when the ledger never moved past it, a crash between the two. No round is spent twice. A
call at the commit the round before it named records a new round: the round cap bounds it.

Every commit of a round lands before `verify-brief`. A commit after `fix-record` and before
`verify-brief` is the same round's work. Run `fix-record` again with the same `--started-at`. It
records that round again at the current commit, and no round is spent. `verify-brief` with HEAD
past the fix record writes a warning and goes on, and the verifier does not read the later
commits. After `verify-brief`, a verifier reads the round, so later code is not that round. Run
`verify-record` with the reading. With a person present, the repair round above begins at the
last record and holds the later code. Otherwise `close` writes a warning for that code. A commit
that changes a frozen test or a file the order does not own refuses at either step (exit 63).

**When `fix-record` stopped the order, stop here.** Do not dispatch the reviewer in verify
mode: `verify-record` refuses on a stopped order. Report the stop instead, the same way a stop
at the build step is reported. A person goes on with `fix`, and the round is verified after.

Open a dispatch record for the reviewer again, the same way review mode did, with nothing denied
and nothing allowed:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh dispatch-open "<task_folder>" reviewer <order id>
```
The reviewer holds Write in verify mode too, for its verdict file, and the frozen-test hook still
only enforces the freeze while a record is open. The same reasoning applies: without a record, a
write into a frozen test is caught afterward as a dirty tree, not stopped as it happens.

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh verify-brief "<task_folder>" <order id>
```
It refuses when the order is not at `fixed`, or when it is stopped. When nothing is open, or this
round is already verified, it has nothing to do: it says so and names the next step. HEAD past the
fix record is a warning, or exit 63 under the rule above. It writes `implementation/brief-<order id>-verify-<round>.json`. The
brief holds the open findings the fixer received, the scope the fixer was given, the fix diff as a
path, and the fixer's report as a path. It names the path the verdicts go to, `implementation/verify-<order id>-<round>.json`.
Nothing else: not the original diff, not an earlier round's verdicts. It prints the brief's path, the three paths it
names, and one line per finding.

**Dispatch `reviewer` again**, on opus, with the same message: the role, the run mode, and this
brief's path. The brief's own `mode` field says verify. Close the dispatch record as soon as it
returns, per SKILL.md.

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh verify-record "<task_folder>" <order id> \
  --verdicts <the verdicts path verify-brief printed>
```
Addressed closes a finding. Not addressed keeps it open; attempted is not addressed. The brief's
`restsOn` lists the files the findings name and the files the fix changed. An addressed verdict
that cites none of them in `file` or `read`, or that lists a file under `couldNotRead`, reads not
addressed. That catch rests on the verifier's own lists: a file the fix runs or reads that nobody
lists, and the verifier leaves out of `couldNotRead`, is not seen. No script can list such a file,
because what a file calls is language-specific and AIDA parses no source. New breakage
inside the fix diff opens as a finding under the same rule. Anything the reviewer notices outside
the fix diff is recorded and opens nothing. It prints the ids addressed and not addressed, the new
breakage, what is still open, the rulings, the record path and `next:`.

A repeat call over a round already verified reports the verification on record rather than
refusing: nothing was verified twice. With `--ruling` flags, that repeat call rules on the round's
open findings instead, under Rulings below.

## Rulings

A ruling is a person's answer on an open finding. A person may rule a finding at any round, and
at `reviewed` before any round. Rulings with no verdicts file land on the open findings and record
no round; a round not yet verified still needs its verdicts file. At the cap: once the
rounds are spent, `verify-record` above refuses when a finding is still open and no ruling names
it. Nothing is written yet, so this is a retry of that same call, not a new one, and each open
finding needs a ruling. Once that round is on the record, the ruling is the same call with the
rulings and no verdicts file. A finding the repair round above may take needs no ruling yet, and
never stops the order. `verify-record` records the round and prints a line that names it. Put
it to the person: run the repair round, or rule the finding. Before the cap, a ruling fits a
finding no round can reach: one the last fixer reported under `--scope-insufficient`, one whose
fix scope is empty, or one that cites a non-goal, since only the person says whether it holds.
Unattended, `fix-brief` marks each finding with an empty fix scope pending and exits 0, and its
`next:` line names the close. Every ruling refuses without the person's answer on record (exit 55).

The words are `wrong`, `deferred`, `load-bearing` or `test-wrong`, with a reason. Put the
findings to the person and ask, opening the same way in every case: "The reviewer found problems
the fix rounds cannot repair. You decide what each one is. Wrong: the reviewer was mistaken,
and the work is accepted as it is. Deferred: the problem is real but put off to a later task,
and the work is accepted. Load-bearing: the work cannot be accepted with it, so this unit of
work stops until you act. Test-wrong: the problem is real and the fix needs a frozen test
changed, so the order is built again with new tests. A model may not make these calls with nobody
watching." Then
say each finding in plain words, with what it cites. At the cap, unattended, `verify-record`
marks each open finding with an empty fix scope pending, as `fix-brief` does. It stops the order
only for an open finding that has a fix scope. On a light task it also marks each open low
finding pending, and the person rules it at the task review. A medium or high finding stops the
order. A person goes on with `fix` or `close`, under "Leave a stop" in `references/finish.md`. A light order keeps its one round when a person later sets the task interactive, so the
ruling is taken at once.

Run the same call again, with one `--ruling` flag added per finding ruled:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh verify-record "<task_folder>" <order id> \
  --verdicts <path to the reviewer's verdict file> \
  --ruling <finding id>=<wrong|deferred|load-bearing|test-wrong>::<reason> \
  --ruling <finding id>=<wrong|deferred|load-bearing|test-wrong>::<reason>
```
When the round is already on the record, or no round ran, leave the verdicts file out:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh verify-record "<task_folder>" <order id> \
  --ruling <finding id>=<wrong|deferred|load-bearing|test-wrong>::<reason>
```
The round's verdicts stand and no second round is recorded. A verdicts file given anyway is
ignored, and the summary says so in its `verdicts:` line.

`wrong` and `deferred` let the order close with the finding recorded. `load-bearing` stops the
order, the finding named as the reason. The person commits the fix in the order's own files. Then
they go on with `check`, under "Go on" in `references/finish.md`. It runs the checks over those
commits before `close`. Or the person goes on with `close`, and the finding stays listed.
Interactive, this reaches the person as an escalation, not a question with an obvious answer. A
ruling missing for an open finding at the cap refuses.

`test-wrong` stops the order with `test wrong: <finding id>` as the reason, and that reason allows
no go-on. A `test-wrong` and a `load-bearing` ruling in one call stop on the test-wrong text. Once
the round is on the record, the person reaches it with that same call, the `test-wrong` ruling and
no verdicts file. The route is a redo, under "Redo the order" in `references/finish.md`. The person
changes the test through design, and design closes again. Redo reverts the order's commits, moves
its records aside and sets it back to planned. The tests brief carries the person's words. The test
author writes the tests again, the checker reads them, and `tests-freeze` freezes them, failing
first. Then build again.

When the finding's cause is the done-when row's own wording, the design is wrong and not only the
test. Rule the finding, correct the design, then redo the order.

## Close

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh close "<task_folder>" <order id>
```
It refuses when an actionable finding is still open, or when the last fix round was never
verified. It also refuses when the code repository's tree is not clean, or when HEAD is not where
the last record left it. Another order's commits, as review-record reads them, do not count, and
the range then ends at the last record. Nothing is open then, so no round or ruling can take the
later commits.
A person moves the branch back, and that work goes to a follow-up task, or redoes the order. On
success it writes `lastStep = "closed"` and the commit range the
order produced, from the freeze. When another order's commit sits between two attempts, the range
starts after it, and close prints this order's earlier commits as `earlierCommits`. On a `record`
order the tree, HEAD and the range are the project folder's, from the last attempt.

**Close also decides the criteria this order serves or owns.** A machine-verified criterion reads
confirmed once every order serving it is closed and every judgement on it reads confirmed.
Otherwise it stays not-judged. A rejected judgement cannot reach here, since `tests-freeze` already
refused it, but the state is still derived from the judgements every time, never assumed. A
person-verified criterion stays at not-judged too: it carries a checklist instead of a judgement,
and review's close is what confirms it.

It prints the closed order's state and commit range. It prints one `criterion(...)` line per
affected criterion, with its row state and judge. `rowsJudgedByModel:` says how many rows across
the whole ledger a model judged rather than a person. Read that count to the person before moving on, so
they can find and re-judge exactly those rows.

Say plainly that the order is done, and move to whichever order is next ready.
