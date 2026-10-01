# Write the tests for one work order

This step runs once per work order, not once per build. An order is ready when every order it
depends on is finished.

The tests are the reference the whole build is measured against. Everything below exists to keep
that reference outside the thing it judges.

## Read what this order needs

Read this order's `order(<id>)` line from `read`. Its `roles=` list names every role this step and
the build dispatch for the order. Its `lookups=` list names every catalog point this step asks.
One function decides both lists from the proof kind: `br_order_needs` in `scripts/lib/proof.sh`.
Do not work them out from the kind here. `dispatch-open` refuses a role the list lacks (exit 102).

## Resolve the recipes for this step

Dispatch `catalog-identifier` to ask the navigator's process-recipe lookup once per point in
`lookups=`, for each framework the project declares. Each message names the point as
`point: <phase>`, then each framework, then the project folder. Name the role, and pass the
lookup's answer in its own word: SKILL.md holds both rules.

**`point: test-authoring`, only when `lookups=` names it.** This answers where a test file goes,
which levels exist and when each is right, what a test may not do in this framework, and how a
criterion id attaches to a test. The test author and the row-checker read it, so an order
whose roles hold neither skips it.

**Light:** do not ask for `point: implement`. Preconditions resolved it, so read each path from
`implementation/preconditions.json`, at `frameworks[].implementRecipePath`. A framework whose
`implementLookup` reads `not-given` was never asked, so ask for it here.

**`point: implement`, for its patterns and its path.** Take the file patterns from its `## Oracle files`
block, the same globs the `test_delete` row names. The catalog index designates that block for
naming test files, so this is not a guess at what the block is for. Pass those globs and the path
to the freeze below. This is the one recipe this step reads itself, because it needs the patterns as data rather
than as instruction.

Do not give this recipe to the test author. It carries the standards and the steps that write
production code, and that role may write neither. Pass its path to `dispatch-open` as
`--deny-read`, so the rule is a permission the runtime applies and not a sentence asking a model to
leave a file alone. It is the one path this step names by hand; the production source is derived
from the snapshot, below.

Resolve the patterns once, here, and let them be recorded. The rule that later refuses a write to a
frozen test reads the record and never the catalog, because a lookup in a write path is a lookup
that can fail open, and a pattern that changed during a build would change what is protected
halfway through it.

## An order with no `test-author` in its roles

Such an order skips `tests-brief` and the test author. The freeze flags still follow the proof
kind, so read the order's `proof` from the frozen snapshot for them. On every kind, each absence
clause the order routes goes to the `row-checker` as a row of its own, the way the checkpoint below
says. "Put no row to anyone" below means no row but those.

`gate` means its deliverable is exported configuration, and a test that reads the YAML back cannot
fail for the right reason. Put no row to anyone. Go straight to the freeze below with no `--test`,
and a `--checklist` for each criterion a person verifies. The build runs the
implement recipe's `## Configuration gate` lines as the order's own check, and `close` judges
its owned machine criterion from that check. The behavioural proof lives with the tests of the
order that consumes what it configures. Every other order takes the steps below. An order with
no `proof` at all is proved by tests; `start` names it on its `proofAbsent:` line. Design's
`update --proof gate` is the way onto the gate.

`record` means its deliverable is a document in the project folder, and nothing runs a document.
Its done-when rows are its checkpoint. Put them to the `row-checker`, or to the person, the way
the checkpoint below puts a test's rows. The question is whether each row names something a reader
can confirm from the deliverable alone.
Freeze with no `--test`, one `--row <order id>=...` carrying that judgement, and a `--checklist`
for each criterion a person verifies. The build reads that row as the order's own check,
`done-when`. `close` writes the row's judge, person or model, on the criteria the order owns.

An order that freezes no test file leaves the build's `frozen-tests` row undeclared. The row
hashed nothing. So it says the row did not apply, rather than that a hash matched.

`observe` means its deliverable is what a page shows, and a model judges that after the build.
Put no row to anyone: there is nothing to judge before the page exists. Freeze with no `--test`
and no `--row`, and a `--checklist` for each criterion a person verifies. The build step opens
the order's surfaces in a browser after the implementer returns. It reads that record as the
order's own check, `observed`. `close` writes `model` on the criteria the order owns.

`confirm` means the task has no automated tests. Put no row to anyone, and dispatch no test
author. Freeze with no `--test` and no `--row`, and a `--checklist` for each criterion a person
verifies. The build's own check, `confirm-at-review`, reads deferred. `finish` turns each
done-when row into a checklist row. The row sits under each criterion the order owns, or serves
when it owns none, and the person answers those criteria at review.

## Assemble what the test author may see

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh tests-brief "<task_folder>" <order id>
```

It reads the frozen copy and never the live files. It writes exactly eight things to
`implementation/brief-<order id>-tests.json`:

- this order's own record, with the criteria it owns named in `criteriaOwned` and its files in
  `ownedFiles`. The author writes its tests into the test file named there;
- the criteria it serves and owns, with their verification and who verifies each;
- the boundaries it names;
- the declared interface of every order it depends on;
- `dependencyInformation`, each dependency's review `information` items: the id, the order it
  came from, the summary and the file;
- `reuses`, the path and the interface of every existing thing design's dispose recorded on
  this order. A reused module is production source of no work order, so this is the only place
  the test author gets its shape. An order disposed with no path carries none;
- `testRecipePath`, the test-execution recipe's path from `implementation/preconditions.json`,
  `frameworks[].recipePath` where the lookup resolved. That recipe holds the run command and the
  `failure_signal` markers the author reads a red against. Null when no lookup resolved, and the
  summary says the author has no runner to read;
- `playbooksPath`, the path of `records/playbooks.json` when research loaded one, else null.

A ninth, `treeHolds`, only after a restart or a retake left this order's build or fix commits on the
branch. It holds those commits and two sentences. The tree holds this unit's own earlier code, so a
test that passes on arrival is suspect. And the author may give one of those commits to
`--locks-in`, below, written `commit:<id>`. The summary prints the commits on a `treeHolds:` line.
After a rebase, `notFound` names each commit with no copy here that can be cited, and why. The
author cannot cite one. If a test arrives green on that code, the author reports it green on arrival
and names the commit.

A tenth, `retake`, only while a `test-wrong` ruling is still unanswered by a freeze. It holds
the ruled finding, the criterion it names, its evidence, its severity, and the file and lines it
cites. It holds the ruling reason too, read from the review record the retake moved. It holds
the rows and the test globs the order already froze, and those rows are keyed by criterion. So
the criterion the finding names says which rows to correct.
And it says what the author must do: correct the tests the finding names,
and leave every other frozen row alone. Its `redAgain` list names each frozen test with a red run
in a file that holds a test of the finding's criterion, the same way `rowsRejected` does below. A
record a person removed is named under `absent`, and the brief carries what is left. The summary
prints a `retake:` line.

`rowsRejected`, only while a row a person rejected at the checkpoint below stands. It holds each
row's key, the person's words verbatim, and the checker's note. Its `redAgain` list names each
test with a red run in a file that holds a rejected row's test. The repair edits that file, so
each of those tests needs a new red run. The `whatToDo` asks for those runs only when the list is
not empty. The summary prints a `rowsRejected:` line.

One more key is for the freeze, not the author. `roundStartedAt` is the time this order's test
round began. A brief written again for a retake or a rejected row keeps the earlier time, because
a test file that the repair does not edit keeps its red runs. A test in an edited file does not,
because the freeze compares each red with its file. It keeps the time only while the order and
its criteria are unchanged. A design change, or a restart that moves the brief aside, starts a
new round.

It prints the brief's path and counts, never the brief.

That list is the withheld list, decided once rather than at each dispatch. Adding an input here
is a change to the role, not a judgement made in the moment.

An interface record is prose a builder wrote about its own code. It is not the code, and that is
the line.

## Open the dispatch record, then dispatch the test author

`--deny-read` below is applied by the runtime, through the read-denial hook. `--allow-write` is
not: no hook reads it. It is recorded for a person reading the dispatch record later, the same as
the read denial and the shell door named under "What this skill does" in `SKILL.md`. The build is
serial, so a task has at most one open dispatch at a time.

Open it first:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh dispatch-open "<task_folder>" test-author <order id> \
  --deny-read <path of the recipe that carries the coding standards> \
  --allow-write <path the tests go in> \
  --test-glob <pattern from the implement recipe>
```
One `--test-glob` per pattern, the same ones the freeze below takes. The script refuses a role
name that matches no agent this plugin ships, and for this role it adds the production source to
the denied reads itself, taken from the owned files every work order in the frozen snapshot
declares. The script denies those paths in the main checkout too, and prints the worktree the
role works in. An owned file of this order that matches a test glob is a test, and it stays
readable, so the author can read back what it writes. So is an owned file under a directory the
glob names literally, `tests` in `**/tests/**/*Test.php`, because the author also writes base
classes and fixtures there. The globs decide, not the write path, because a framework may keep
its tests beside the source; a glob that names no directory adds nothing. Three kinds stay denied
whatever the globs say. Every path an order reuses is one, because a shared test base class shows
its shape as surely as source does. Every other order's owned file is the second, because a
sibling test shows a reuse's shape by its calls (gap rows 248, 249). Every file git tracked when
the build started, in a test tree an order owns or reuses from, is the third. This order's own test
files and the support files its frozen record holds are left out. A test from before the task shows
the same calls. Tests in other trees stay readable, such as a framework's committed core and
contrib tests, which are the fair place to look up a framework base class. A file the author
writes is untracked, so it stays readable. A search of a folder that holds a denied file is
refused, so the author searches its own test file by its path. The
script refuses the dispatch (exit 47) when this order owns no file a test glob matches and no
directory. The freeze would refuse every test the author wrote, so design adds the order's test
file with `add-owned-file` first. The test runner still loads
a denied base class. The hook judges what the role reads, through Read, Grep and the shell's
reading verbs. A run command is none of those, so the files the runner opens are not judged.
Never type the denied paths here. It prints what it denied; read that list, because it is the
whole of what separates the tests from the code they judge.

Close the dispatch record as soon as the role returns, per SKILL.md. A record left open makes the
next dispatch refuse, and it names the role and order still holding it.

**Then dispatch `test-author`**, with the message SKILL.md names. Its lines are the role, the run
mode, and two paths: the test-authoring recipe for its framework and the brief `tests-brief`
wrote. It is not
the context that writes the code, and it is not this conversation either. Both hooks recognise a
role by the agent's own type, so writing the tests here instead of dispatching leaves every rule
below unenforced while the record on disk says otherwise.

**It may not read production source.** Not this order's, and not any order already built. If it
sees the code, the tests describe the code instead of the intent, which is the same failure one
step earlier. A hook refuses the read while the dispatch record is open. The same hook refuses it
a shell command that names a runtime form in `scripts/introspection-forms.txt`, such as
`php:eval` or `ReflectionClass`. A runtime shows the code's shape as surely as its source does.

**A missing signature is design's gap.** The author stops when a test needs a signature the brief
does not hold. Its reply ends with `Stop: missing-signature: <class or method>: <test>`, and its
report holds the same line. No script reads either, so the route below is yours to take. The brief
carries every reuse and dependency design declared, so the order did not declare what its tests
call. A sibling test that calls the method is not a source for its signature either. Do not give
the signature in the dispatch. Put it to the person: design adds the reuse, and the build takes
the order fresh, as `references/finish.md` says for design drift. A run nobody attends cannot
change the design, so it reports the stop and the author's words.

**It may not write production code.** It writes the test, watches it fail, and stops.

**Set the tier on the dispatch.** A mid tier, in both modes. The checker reads every row at the
top tier before anything is frozen, and a person reads the rows it rejected. So the author's work
is checked before the build is measured against it, whether or not a person is present.

Resolving which recipe is this step's job; reading it is the role's. The recipe runs to well over
a hundred lines per framework, and reading it into this conversation is the cost the dispatch
exists to avoid. What the author returns is in its definition, and each item has a flag in the
freeze below. The red-run file per test goes under `--red`, each support file under
`--support`, and each absence clause under `--absence`.

**A criterion this order serves but does not own is proved by its owner.** Exactly one order owns a
criterion, and most orders own none. A supporting order cannot observe a criterion whose outcome a
later order builds, so its tests are written against its own done-when. Such a test ends its name
with the order id, `Wo1`, and no criterion id. The author writes a test for every machine-verified
criterion the order owns, and for its done-when where nothing it owns covers that.

**A test green on its first run has four outcomes.** The test was wrong: it is corrected once.
Still green, and the author can name the existing code that satisfies it: it locks that behaviour
in, and the reason is recorded with `--locks-in`. Still green with no existing code to name: it is
reported by name and the step stops. Failed: it is frozen with its red run. A green test is never
deleted quietly and never weakened into failing.

**A test of the order's own work names a commit, not code.** After a retake the tree still holds
this order's earlier build, so a test of its done-when arrives green. The code that satisfies it is
the order's own, which the author may not read, and no interface record of this order exists yet. So
the author gives `--locks-in` one of the build or fix commits the brief carries under `treeHolds`,
written `commit:<id>`. The prefix is what marks a commit, so a reason without it stays prose
whatever it looks like. The freeze checks the commit is this order's own and is on the branch, and
refuses anything else (exit 101). The author reads no source. It names a commit the brief already
printed. This is honest. The code is on the branch because a retake kept the build and corrected
only the test.

**A done-when clause that asserts an absence gets no test, and goes to review.** Such a clause says
the change added nothing of a named kind. No second engine for one job. No new dependency. No
static call to the container. No test of it can be watched failing. The tree is already in the
state the clause asserts, and making the test fail means adding what the clause forbids. None of
the four outcomes above fits. The author is then left choosing between an unprovable test and none
(live-run row 184). Route the clause instead, on the freeze below:
`--absence <the clause, verbatim>`, one flag per clause. The freeze records it on the order's
ledger entry. Review's brief carries it to the architecture reviewer, which judges it against the
task's own diff. A clause routed this way is visible as owed, rather than untested in silence.
The tests brief names each done-when clause that holds a negation word, under `absenceCandidates`.
So the author, who decides what to test, returns an absence verbatim and writes no test for it.

**What makes a clause an absence.** It is a claim about what the change added, answered by reading
the diff and nothing else. "No new Composer dependency" is one. "The form shows the repeat field" is
not. Neither is "the saved date matches the one entered". Each of those is a claim about what the
code does, and a test can watch it fail. A clause that merely holds the word `no` is not an absence
either. "The form shows no legacy field" is a behaviour, so it takes a test. Judge the clause and
not its wording, and route only what nothing can run. The row checker asks the same question
before the freeze, below, and review asks it again. The reviewer says whether a test could have
watched each routed clause fail, and a yes fails the review.

The freeze refuses the flag (exit 81) on two facts. The clause is not, verbatim, one of the order's
frozen done-when entries. Or the clause carries no negation word at all. A contraction such as
doesn't counts, with a straight or a curly apostrophe. That second refusal is a floor and not the
whole rule. A script cannot read meaning, so it catches a clause plainly asserting a presence and
leaves the rest to the judgement above. **This route relaxes nothing else.** Every `--test` still
needs its red run or its `--locks-in` reason (exit 33). An order that froze no test at all still
refuses, at exit 29 or exit 74. A clause a test could have proved, routed here, is how the rule that
every frozen test was watched failing gets worked around. So route narrowly, and name every routed
clause when you report this step to the person.

**A failure is read from the framework's own signal, never from the exit status.** Three of five
frameworks exit zero when a filter selects nothing. Only an assertion that ran and did not hold is
a red run. A harness that never reached the behaviour is a setup gap, and a run that selected
nothing looks like success and is the dangerous one.

**When the author returns, run the coding-standards row over the new test files.** Take the
command from the check recipe `references/preconditions.md` resolved, with `{paths}` as the test
paths the author returned, and run it here. When the row lists `extensions`, pass only the test
files that end in one of them. When none is left, the row does not apply: say so, and run
nothing. Send any finding back to the author before the freeze. No script action runs one recipe row on its own, so this conversation runs the command.
This is the one place the tests' own standards are judged. The build and review leave the frozen
tests out of their tool rows, because no role after the freeze may write them.

Do not run the static-analysis row here. The tests name code that does not exist yet, so an
analyser reports each missing name. Once the code exists, an analyser can read a test's guard as
always true. No role may then change the test. So review runs the row over the frozen tests once
more, and each finding becomes a follow-up for the test author (gap row 270).

## Put the rows to the checker, before anything is frozen

Build one row per criterion the tests name: the criterion, its verification sentence, and the names
of the tests that prove it. Build one more row when a test proves the order's done-when: the order
id, its done-when text, and those tests. That row also names each criterion the order owns and
the tests named for it. Add the verdict that stands on that criterion, the person's where a
person answered it. Add it only when an earlier round gave one. The author tests the done-when
only where nothing the order owns covers it. So the checker needs the owned criteria to judge the
done-when row (gap row 210). The rows carry names and not test code. The question is whether the
tests named exercise the sentence beside them.

Build one row per absence clause the author returned. Its key is `<order id>:absence:<n>`, with n
its done-when row counted from 1. It holds the clause verbatim and names no test. The checker
answers one question: could a test prove this clause? A yes is a rejected row. The freeze refuses
(exit 64) an `--absence` clause with no row, so the clause reaches a checker before the build (gap
row 273). An order with no test row dispatches the checker with these rows alone, and with no
`--test-glob` and no recipe. A rejected one on such an order is frozen again without its
`--absence`, so the order's own proof covers the clause, or design splits it.

**Dispatch `row-checker` in both modes.** It reads each named test against the test-authoring
recipe and the sentence beside it. A person shown test names cannot see what it sees. It finds a
case the recipe asks for that no test covers, and a test that measures something easier than the
sentence. Asking the person every row added a turn and no judgement the checker had not given
(live-run row 70). Pay the top tier. Open the dispatch record first, the same way every other role
gets one:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh dispatch-open "<task_folder>" row-checker <order id> \
  --test-glob <pattern from the implement recipe>
```
One `--test-glob` per pattern, the same values the freeze below takes. The script derives the
denied reads itself, the same way it does for the test author. It denies every order's owned
files and every reused path, less this order's own files that a test glob matches. It keeps
readable each test in another order's frozen record that names a criterion this order serves or
owns, because the checker reads it. Design lists an order's tests under its owned files. The checker
reads those tests, so the globs decide which owned files stay readable. Without them every owned
test file is denied, and the script refuses the call (live-run row 106). The task folder holds
copies of production code too. So the checker is also denied its diffs, build and fix records,
review and verify records, briefs, reports and set-aside files. So `row-checker` cannot
open the production source behind a hook. Without this record open, the hook denies nothing. The
checker's own instructions to stay off the implementation are then just words, with nothing
enforcing them.

**Then dispatch `row-checker`**, on opus, with the message SKILL.md names. Its lines are the
role, the run mode, the rows built above and the test-authoring recipe's path. Then come the
interface file path `dispatch-open` prints, and the verdict file's path. That path is
`implementation/row-check-<order id>.json` under the task folder. The rows are the one input
typed by hand, because no brief action writes them. The denial above covers every reused path and
every other order's files. A test that calls one would reach the checker with nothing to judge the
call against. So `dispatch-open` copies the tests brief's `reuses` and `dependencyInterfaces` to
`implementation/interfaces-<order id>.json`, the text the author tested against (gap row 257).
It copies only those two keys. The rest of the brief holds the person's words, earlier notes and
review evidence, and a read returns the whole file. An order with no tests brief gets no file.
The checker's note names the entry it relied on. No script checks that, because no hook reads an
agent's answer.
Close the dispatch record as soon as it returns, per SKILL.md.

**A confirmed row is the checker's, in both modes.** It becomes
`--row <criterion id>=confirmed::model::<its note>` for the freeze below. The done-when row is keyed
by the order id in place of a criterion id: `--row wo1=confirmed::model::...`. Do not put a
confirmed row to the person. There is one exception: an interactive run where another row of this
order goes back to the test author. Then list this order's confirmed rows, each with the checker's
note, and ask once whether any of them goes back too. The author rewrites this order's tests
anyway, so a doubt costs nothing to act on now (live-run row 208). A confirmed row the person sends
back becomes `--row <criterion id>=rejected::person::<the person's words>`. The record says a model
judged every other confirmed row, so a person can list those rows later and read any of them again.

**Interactive, a rejected row goes to the person, one question per row.** Open with: "The checker
doubts that the new tests for one requirement prove what it asks. A model may not settle that
alone. Confirm and the tests are kept as written. Reject and the test author rewrites them before
anything is built." Then name the requirement in its own words, the tests, the checker's note,
and the answer the note recommends. The person's answer becomes
`--row <criterion id>=confirmed::person::<the person's words>` or
`--row <criterion id>=rejected::person::<the person's words>`. A row the person rejects goes back to
the test author before anything is frozen, in three steps. Run `tests-freeze` with every row as
answered. It refuses (exit 65) and writes no test record. It records each rejected row on the
order's ledger entry, with the person's words and the checker's note. Run `tests-brief` again, which
carries those rows under `rowsRejected`. Then open a new dispatch record and dispatch the test
author fresh, with the same message as before. Do not resume the earlier author with a message: the
brief is the one carrier. A role that stopped with no report is a different case, in SKILL.md.
The refusal ends with a `checkAgain:` line, which names each row the next checker dispatch covers.
Those are the rejected rows and each confirmed row with a test in a rejected row's file. The
done-when row is there too when an owned criterion's row went back. The repair edits those files,
so an earlier verdict on them no longer holds. The refusal records each other confirmed row on the
order's ledger entry as `rowsConfirmed`. A checker's row keeps the note from the verdict file, so
the note is the checker's own. The next checker writes the same verdict file, and that file holds
only the rows put to it. So the next freeze takes a `--row` for each `checkAgain` row alone. It
carries each recorded row itself and names them on a `rowsCarried:` line (gap row 259). It does
not carry a recorded row whose test file changed after the verdict file was written. Exit 64 then
names that row, and it goes to the checker again. Exit 64 for a missing row also records the confirmed rows it was given.
Their notes then survive the next checker's verdict file. Freeze once every row for this order
reads confirmed; that freeze clears both records. A note may not hold the text
`; earlier: `. This stage joins one halt reason to another with that text, so a note
carrying it would forge a halt nobody wrote. `tests-freeze` refuses the flag rather than write it.

**Unattended, there is nobody to ask.** A rejected row becomes
`--row <criterion id>=rejected::model::<its note>`, and it is not sent back to the test author the
way a person's rejection is. Nobody is present to judge the correction, so `tests-freeze` writes
the halt onto the order, with the checker's own note as the reason. Then it refuses. Report the
halt, and take the next ready order instead. A person clears it with `clear-halt` once the test
is repaired, in `references/finish.md`.

**A person's row needs a person.** A row judged `person` on an autonomous run refuses, because
nobody was there to say it. A row judged `model` is accepted on both runs, because the checker runs
on both. The freeze exists to record who actually looked.

## Freeze what came back

Run, with one flag per test, per failure output, per framework, per pattern, and per row:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh tests-freeze "<task_folder>" <order id> \
  --test <path>::<test name>=<criterion id> \
  --test <path>::<test name>=<order id> \
  --red <test name>=<path to a file holding what the run printed> \
  --test-recipe <framework>=<path to the test-execution recipe> \
  --implement-recipe <framework>=<path to the implement recipe> \
  --locks-in <test name>=<one sentence naming the existing code that satisfies it> \
  --locks-in <test name>=commit:<id of this order's own build or fix commit> \
  --test-glob <pattern from the implement recipe> \
  --checklist <criterion id>=<the verification sentence> \
  --row <criterion id>=<confirmed|rejected>::<person|model>::<note> \
  --row <order id>=<confirmed|rejected>::<person|model>::<note> \
  --support <path of a support file the author returned> \
  --absence <a done-when clause of this order that asserts an absence, verbatim>
```

A `--test` names its criteria or the order's own id, never both. The second form marks a test of
the order's done-when, and its name ends with the order id. A `--test` path must be a file the
order owns. The freeze refuses any other (exit 27) and names the test file design chose. Do not
move the tests yourself. Run `dispatch-open` with `--resume` and resume the test author, which
writes the tests into that file and takes a new red run for each. Then freeze again.

`--test-recipe` is a path only, one per framework, read from `implementation/preconditions.json`
at `frameworks[].recipePath`, the same way the build step reads it. It must be the record's path:
a different one refuses (exit 91), naming both. When the catalog republished the recipe, run
`recipe-refresh` first (`references/preconditions.md`). With no flag, the freeze reads the record's
path itself, and the record names what it read under `testRecipePath`. The script reads the recipe's
`failure_signal` block itself. Do not read the body here. `--implement-recipe` is the path
resolved above, one per framework, the same path the build step passes to `build-record`. The
script reads its `## Unit declaration` block itself, for the one exception below.

This refuses outright (exit 74) when the order serves and owns no criterion at all: there is
nothing for a test to prove and nothing here to freeze, and the repair is the work order, not this
step. A `gate`, `record` or `observe` order freezes with no test row, and each refuses a `--test`. A
`record` order owes its done-when row, `--row <order id>=...`, and refuses without it (exit 64).
An `observe` order owes no row but its absence rows: the freeze accepts it with nothing else.
It also refuses (exit 76) when the order has already left `tests-frozen`: a second freeze
would rewind the step and leave a spent attempt counter and a stale build record for tests that no
longer exist. Use `references/finish.md`'s restart when the design moved; this order goes forward
from here, not back.

The script checks the file exists, sits inside the code repository, matches the framework's own
declared pattern, and carries at the end of its name the criterion it claims. A done-when test
carries the order id there instead. It checks every machine-verified criterion this order owns has
a test (a `gate` or `record` order excepted), and every criterion a person verifies has a checklist line. A criterion this order only
serves needs no test from it, because its proof lives with its owner (exit 29 reads the owned
list). A person-verified criterion is different: each order that serves it needs its checklist
line, owned or not (exit 30). A test that names neither a criterion this order serves or owns nor
this order's id refuses (exit 31). A name that does not end in what it claims refuses (exit 28).
A record that would hold no row refuses (exit 74).
It checks every test has the output of the run that failed, or a `--locks-in` reason in its
place. A test with neither refuses (exit 33). A `--locks-in` reason written `commit:<id>` must
name one of this order's own build or fix commits on the branch. An id that is not hexadecimal,
is shorter than seven characters, or is not this order's own refuses (exit 101). A reason with no
`commit:` prefix is prose and names the existing code.
A `--red` file written before the brief's `roundStartedAt` refuses (exit 109). So does one written
before its test file last changed. Either is the run of an earlier test, for example one a restart
moved aside. The message names each file and both times. Its last line, `redAgain:`, holds the
names of those tests as a JSON list. Run each test again and pass the new output. The comparison is
per file, not per test. Many frameworks keep several tests in one file, so an edit to one test
makes each red in that file stale. That is on purpose: the edit can change what the other tests
run, and it moves each line their reds cite. A brief that holds no `roundStartedAt` is read by its
own file time. A freeze with no tests brief compares the test files only.
It reads each `--red` file against the markers the
test-execution recipe declares under `failure_signal`, and against the suite row's `failure_line`.
A file holding an `assertion` marker is a red. A file holding a `harness` marker instead is a
setup gap, and the freeze refuses it (exit 80) saying so. The harness never reached the
behaviour, so nothing in that file says the behaviour is absent. One order is the exception: the
order that creates the unit. The implement recipe's `## Unit declaration` names the file whose
presence makes a unit exist. When an owned file of this order matches one of its globs, the
freeze accepts the harness-only file as its red, recorded `redSignal: harness-new-unit`. No
test can assert before the module exists, so that is the only red the order
can have. The author does not scaffold the module to get a better one: it may write no production
file. With no `--implement-recipe`, no block, or no matching owned file, the refusal stands.
The exception reads the recipe's `harness` markers only, never the recipe's prose. When the
harness printed an undeclared form, the freeze refuses (exit 80), naming the markers and quoting
the file's error line. The author then asks the recipe to declare that form under
`failure_signal` `harness:`, or writes a test with no module-local class.
A file holding neither marker is a red when a line matches `failure_line`. That is how a red is
read under a recipe whose assertion span is a shape rather than a marker. A file none of the
three reads accepts refuses (exit 80), naming the file and the marker words. When the recipes
declare no assertion marker and no `failure_line`, the freeze cannot read the file at all. It
then freezes it as before, records `redSignal: unchecked` on the test, and says so in one summary
line. Every other red carries the reading that accepted it. A freeze with a `--red`, no
`--test-recipe` and no recipe on record refuses, because then no red can be read at all. A `--locks-in` reason is
recorded beside the test, and the review brief says where it is.

**Two tests that fail at one place have no red.** The freeze reads each red it accepted on an
assertion for the places it prints: every `<test file name>:<line>`, in order. Two tests of one
file whose reds print the same places failed at one shared line. That line is a precondition, such
as a guard that the class or service exists, and the freeze refuses (exit 80). Ten tests that fail
on one guard prove one fact ten times, and none was watched failing for its criterion (live-run row
207). The repair is the test: each test reaches its own assertion. A guard may stay if it asserts
nothing, for example a lookup that gives the empty value when the service is absent. The red is
then taken against an empty result, so a test that an empty result passes arrives green. A red
that prints no place in its test file is not compared, and neither is a harness red. This check is
a floor. A guard written again at the top of each test fails at a different line each time, so
the freeze cannot see it. The test author's own instructions forbid that guard.
The check also assumes the harness prints every frame of the failure. `pytest --tb=line` prints
only the deepest one, so two tests failing in one helper read as one place there.

**Every machine-verified criterion a `--test` names needs exactly one row**, naming whether it was
confirmed or rejected and who judged it. A done-when test needs the done-when row, keyed by the
order id. Rows follow the tests. A criterion this order only serves and names on no test needs no
row from it; the row for it belongs to its owner. A criterion a person verifies carries a
checklist instead, never a row: it has no judgement, and review's close is what confirms it. A row for
anything no test of this order claims refuses the freeze, the same way a missing row does. So does
a row for a criterion a person verifies. Every accepted criterion row is appended to that
criterion's own record in the ledger, and the done-when row to this order's own entry. `close` is
what decides a criterion from its rows, once every order serving it has closed and its owner has
judged it.

Then it records a hash for each test file. That hash is the freeze. From here a hook refuses a
write to one of those files from every dispatched role except the test author of the order that
froze it.

Pass each support file the author returned as `--support`. The freeze hashes it with the tests,
records it under `support`, and the hook guards it the same way. Without this, the implementer,
which owns the file, may rewrite the setup the tests stand on and the frozen-tests check stays
met. The freeze refuses a support path that does not exist (exit 89). It also refuses one a test
glob matches (exit 89), because that file is a test: pass it as `--test`.

Then it commits the test files it hashed, and the support files, on the task branch, and only
those paths. The implementer starts from a tree that already holds the tests, and the record's
commit is the one they are in. Work beside them stays uncommitted, and the freeze says so in one
line. A commit that fails, for want of a git identity or any other reason, refuses before the
record is written, with git's own message.

A person is not a role, and is not refused. A freeze is not a lock: it exists so a change is
noticed, and the hash is what notices one. The hook allows the write and says which file changed and
which order froze it.

Report a test that passed on arrival with `--green-on-arrival <test name>=<reason>`. The script
stops the step rather than recording it, which is the right outcome: a test nobody watched fail is
not a reference. This is a bound, not a rule the script enforces on its own: nothing here notices a
green-on-arrival test the caller does not flag, so the flag is on you.

A record is taken once. A second run with the same tests leaves it alone, whatever commit the
tree is at now, because every freeze moves the tree. Different tests at a different commit
refuse and name both commits. Different tests at the same commit retake the record, while the
order is still at `tests-frozen`. The freeze then prints `retaken:` with both commits and records
the earlier one under `retakenFrom`. That is the route for a frozen test that is wrong, named under
the builder's stop in `references/build.md`.
