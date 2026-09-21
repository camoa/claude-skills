# Review, fix and verify one work order

This step runs once an order reaches `checks-passed`. It reviews the code, repairs what a review
finds, and closes the order once nothing actionable is left open.

## Resolve the recipe for this step

Read the `test-execution` and `review` recipe paths from the records preconditions already wrote,
instead of asking the navigator again. `implementation/preconditions.json` holds the
test-execution recipe at `frameworks[].recipePath`, and `implementation/baseline.json` holds the
review recipe at `checkRecipes[].path`, one per framework. A framework absent from a list had no
recipe at the baseline; pass no flag for it. These are the same paths `references/build.md` read
for this order. Pass them straight through to `fix-record` below, in the fix section; the script
reads their command blocks itself, per SKILL.md. The check recipe must equal the one the baseline
used, and `fix-record` refuses any other (exit 73). A fresh lookup could only agree with the
record or fail.

## Review

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh review-brief "<task_folder>" <order id>
```
It refuses when the order is not at `checks-passed`, when the order is halted, or when a review
record already exists for it. **One order gets one review, ever.** Read a refusal and act on it.

It writes `implementation/brief-<order id>-review.json`:

- the criteria this order serves and owns, and the non-goals;
- the order record;
- the diff as a path, the frozen tests, and the builder's report path; on an order whose proof
  is `record` the diff is the task folder's, from the project folder, and `deliverables` names
  each owned file by path. The reviewer reads the document whole rather than a patch;
- the eight check results;
- both interface texts;
- the path the reviewer's findings go to;
- `playbooksPath`, the path of `records/playbooks.json` when research loaded one, else null.

It prints the brief's path, the diff path, the findings path and the report path. It prints one
line per check with its verdict, and counts. Never the brief.

Check the interface-record verdict among the eight lines. Unknown means the declaration names
nothing in backticks, so the script could count nothing there. At unknown, ask nothing, in either
mode. Say one line to the person: "No named element of the interface could be counted. The
reviewer reads the declared interface and the builder's record. If they disagree, its finding
cites the criterion." The brief carries both texts, unchanged, and the reviewer is told
nothing else. A person shown the two texts would be making the comparison the reviewer is about
to make, from the same texts (live-run row 88).

A met verdict only means every backticked element is present verbatim. It does not rule out a
deeper disagreement between the two texts. Catching that is the reviewer's job, from both texts
already in the brief.

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

**Dispatch `reviewer`.** Name the role, per SKILL.md. Set the model to opus. Give it the brief's
path and nothing else, and tell it plainly that this is review mode. Its read is wide by design, one named
file outside the diff for one named risk. On a `record` order, say that the brief's
`deliverables` are what it reviews, against the order's done-when rows. Close the dispatch record
as soon as it returns, per SKILL.md. Its write is refused by the script, not by a hook, when the
code moved or the tree is dirty.
Leaving a probe file behind is a refusal, not a finding.

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh review-record "<task_folder>" <order id> \
  --findings <path to the reviewer's findings file>
```
It refuses when a review record already exists for this order, unless the ledger never moved past
`checks-passed`: a crash between writing the record and writing the ledger leaves that one state,
and this call then finishes the write rather than refusing forever. It also refuses when the code
path moved, or its tree is dirty, since the build record. And it refuses when the findings file
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

Unattended, a finding that hits a non-goal halts the order there, naming the non-goal. A person
clears that halt with `clear-halt`, in `references/finish.md`, once they have ruled. Interactive,
it is actionable like any other finding, and it goes to the person with the rest. No open
actionable finding: the order is reviewed and clean, so go to Close.

Interactive, the script also prints one `unrouted:` line per finding of medium or higher
severity that cites no id, then a count line. Nothing prints when there are none. Such a finding
has no route inside this task. `fix-brief` hands a fixer open actionable findings only, and
refuses (exit 53) when there are none. A commit after the review record moves HEAD, and `close`
refuses (exit 63), so nobody fixes it by hand before the close. A new order cannot enter a
running build. `finish` carries only findings ruled deferred into `finished.json`, so the review
stage sees this one only if its own reviewer finds it again. When an `unrouted:` line prints, put
it to the person, opening with: "The reviewer found a problem this task has no criterion or
non-goal for, so nothing here will fix it. Only you can say what happens to it. Close as
recorded: the finding stays in the order's review record, and the order closes. Track it as a
task, then close: a follow up task takes it as its goal, and the order closes." Then say each
finding in plain words and name its file. A yes to the second answer is the person's ask for
that task, so run, once per finding said yes to:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/task/scripts/task-actions.sh --run-mode interactive \
  create --project "<projectPath>" --name "<task-id>-<finding id>" \
  -- <the finding's evidence, then one sentence naming the finding, the order and the file>
```
That is the id and the goal completion gives a leftover finding, in `docs/finishing.md`. Show
the whole output, and do not enter the new worktree. Then go to Close in either answer.
Unattended, nothing prints, and the record holds them.

## Fix, one round at a time

Repeat this section while an actionable finding is open and a fix round remains.

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh fix-brief "<task_folder>" <order id>
```
It refuses when nothing is open, when the rounds are spent, when the order is halted, or when the
last fix round has not been verified yet. A resumed run hits that last refusal most. A round
recorded but never carried through `verify-record` still counts as open, so the next round may not
start over it. It writes `implementation/brief-<order id>-fix-<round>.json`:

- the open findings in severity order, with their evidence;
- the union of their fix scope;
- the frozen tests;
- this round's own report path, and the order's diff budget;
- the round number;
- `headNow`, the code repository's own commit at the moment of this call;
- `playbooksPath`, the path of `records/playbooks.json` when research loaded one, else null.

It prints the brief's path, the report path and `headNow`. It prints one line per finding with its
severity and what it cites, and the scope. Never the evidence.

Open the dispatch record before dispatching:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh dispatch-open "<task_folder>" fixer <order id> \
  --deny-read <path of the recipe that writes the tests>
```
The script derives the rest itself, the same way it does for the implementer: this order's owned
files allowed, every other order's denied. Deny the test-authoring recipe by hand, the same way
build.md does for the implementer: a fixer chooses no level and names no test, so that recipe is
not its to read.

**Dispatch `fixer`.** Name the role, per SKILL.md. Round one runs on sonnet. Round two runs on
opus, set on the Agent call. Give it the brief's path and nothing else. The brief holds the open
findings, the fix scope union, the frozen tests, the diff budget, and its report path. It writes
the report before it edits anything under the code path.
**It may not change a test**: a hook refuses the write. **It may not write outside the fix
scope.** No hook enforces that bound. The owned-files check after the round only bounds it to the
order's own files, which is wider than the scope. A write inside those files but outside the scope
is not caught there. It surfaces when the reviewer's verify mode reads the fix diff and reports it
under `outOfScope`.

Close the dispatch record as soon as it returns, per SKILL.md.

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh fix-record "<task_folder>" <order id> \
  --report <path to the fixer's report> \
  --started-at <the commit the round began from> \
  --test-recipe <framework>=<path to the test-execution recipe> \
  --check-recipe <framework>=<path to the review recipe> \
  [--implement-recipe <framework>=<path to the implement recipe>]... \
  [--value <name>=<value>]... \
  [--nothing-ran <literal substring>] \
  [--scope-insufficient <finding id>=<reason>]...
```
`--test-recipe` and `--check-recipe` are the two paths resolved above, one pair per framework. The
script parses both itself, the same way `build-record` does. `--implement-recipe` is the path
build.md names, and an order whose proof is `gate` needs it here for the same reason. It refuses (exit 72) when two
frameworks command one tool. It refuses (exit 73) when the check recipe it resolves is not the one
the baseline read. `--value` and `--nothing-ran` work the same way they do at the build step.
`--scope-insufficient` is repeatable, one per finding the fixer's report names as needing more
scope than it had. Interactive puts each one to the person, opening with: "The fixer says this
review finding needs a change in files it was not allowed to edit. Only you can allow that. Make
or allow the change, and the next round can fix it. Otherwise the finding stays open, and you
rule on it when the fix rounds run out." Then say the finding in plain words and name the files
it asked for. Unattended halts the order, naming the
finding, and `clear-halt` is the person's way past. Its reason may not hold the text
`; earlier: `, the same refusal every halt reason applies: that text is how one halt is joined to
another, and a reason carrying it would forge one.

The commit the round began from is `fix-brief`'s own `headNow`. Equal to the current commit, or
not an ancestor of it, refuses (exit 71), the same rule `build-record` applies.

**`fix-record` refuses when the code repository's tree is not clean.** The fixer commits its own
work before it returns. A dirty tree means that commit did not happen. This round is not recorded.
Interactive puts that to the person, opening with: "The fixer left changes in the code that it
did not commit, so this round cannot be recorded. Only you can say whether they are wanted.
Commit them and the round is recorded and checked. Discard them and the round starts over." Then
name the repository and the files git
lists. Unattended
halts the order with that reason.

This re-runs seven of the eight checks, with the same order-tests floor build.md names. On a
`gate` order the floor is `configuration-gate`, and on a `record` order `done-when`. A `record`
order's range, tree and diff read from the project folder, as build.md says. Undeclared or unknown there still spends the
round, even when every other check is undeclared. Not
interface-record: a fix round does not rewrite that record. A check answering unmet or unknown
spends the round and leaves every finding open. At the round cap, the script halts the order
itself, naming the check that stopped it. `review-brief` is never run again for this order.

A repeat call at a commit this round already recorded finishes the write when the ledger never
moved past it, a crash between the two, rather than spending a round twice; otherwise it refuses
(exit 45). A commit unchanged since the round before it always refuses (exit 45): a round spent on
unchanged code is a round nobody worked.

**When `fix-record` halted the order this way, stop here.** Do not dispatch the reviewer in verify
mode: `verify-record` refuses on a halted order. Report the halt instead, naming the check it
stopped on, the same way a halt at the build step is reported. A person clears it with
`clear-halt` and then rules on the open findings through `verify-record`.

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
It refuses when the order is not at `fixed`, when it is halted, when nothing is open, or when this
round is already verified. It writes `implementation/brief-<order id>-verify-<round>.json`. The
brief holds the open findings the fixer received, the fix diff as a path, and the fixer's report as
a path. It names the path the verdicts go to, `implementation/verify-<order id>-<round>.json`.
Nothing else: not the original diff, not an earlier round's verdicts. It prints the brief's path, the three paths it
names, and one line per finding.

**Dispatch `reviewer` again, in verify mode.** Give it the brief's path and nothing else, and tell
it plainly that this is verify mode. Close the dispatch record as soon as it returns, per SKILL.md.

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh verify-record "<task_folder>" <order id> \
  --verdicts <the verdicts path verify-brief printed>
```
Addressed closes a finding. Not addressed keeps it open; attempted is not addressed. New breakage
inside the fix diff opens as a finding under the same rule. Anything the reviewer notices outside
the fix diff is recorded and opens nothing. It prints the ids addressed and not addressed, the new
breakage, what is still open, the rulings, the record path and `next:`.

A repeat call over a round already verified reports the verification on record rather than
refusing: nothing was verified twice.

## Rulings, at the cap only

Once the rounds are spent, `verify-record` above refuses when a finding is still open and no
ruling names it: nothing is written yet, so this is a retry of that same call, not a new one. Each
open finding needs a ruling, `wrong`, `deferred`, or `load-bearing`, with a reason. Put the open
findings to the person and ask, opening with: "The reviewer found problems that two fix rounds did
not repair, and there are no rounds left. You decide what each one is. Wrong: the reviewer was
mistaken, and the work is accepted as it is. Deferred: the problem is real but put off to a
later task, and the work is accepted. Load-bearing: the work cannot be accepted with it, so
this unit of work stops until you act. A model may not make these calls with
nobody watching." Then say each finding in plain words, with
what it cites. Unattended, `verify-record` already halted the order instead.

Run the same call again, with one `--ruling` flag added per open finding:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh verify-record "<task_folder>" <order id> \
  --verdicts <path to the reviewer's verdict file> \
  --ruling <finding id>=<wrong|deferred|load-bearing>::<reason> \
  --ruling <finding id>=<wrong|deferred|load-bearing>::<reason>
```
`wrong` and `deferred` let the order close with the finding recorded. `load-bearing` halts the
order, the finding named as the reason, and `clear-halt` is what follows once the person has
acted on it. Interactive, this reaches the person as an escalation, not
a question with an obvious answer. A ruling missing for an open finding at the cap refuses. A
ruling's own reason may not hold `; earlier: `, the same refusal `--scope-insufficient` above
takes, for the same reason.

## Close

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh close "<task_folder>" <order id>
```
It refuses when an actionable finding is still open, or when the last fix round was never
verified. It also refuses when the code repository's tree is not clean, or when HEAD is not where
the last record left it. On success it writes `lastStep = "closed"` and the commit range the order
produced. On a `record` order the tree, HEAD and the range are the project folder's. The
machine criteria it owns are written as judged by whoever judged its done-when row, person or
model, never `gate`.

**Close also decides the criteria this order serves or owns.** A machine-verified criterion reads
confirmed once every order serving it is closed and every judgement on it reads confirmed.
Otherwise it stays not-judged. A rejected judgement cannot reach here, since `tests-freeze` already
refused it, but the state is still derived from the judgements every time, never assumed. A
person-verified criterion stays at not-judged too: it carries a checklist instead of a judgement,
and completion is what confirms it.

It prints the closed order's state and commit range. It prints one `criterion(...)` line per
affected criterion, with its row state and judge. `rowsJudgedByModel:` says how many rows across
the whole ledger a model judged rather than a person. Read that count to the person before moving on, so
they can find and re-judge exactly those rows.

Say plainly that the order is done, and move to whichever order is next ready.
