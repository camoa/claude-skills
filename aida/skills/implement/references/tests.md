# Write the tests for one work order

This step runs once per work order, not once per build. An order is ready when every order it
depends on is finished.

The tests are the reference the whole build is measured against. Everything below exists to keep
that reference outside the thing it judges.

## Resolve the recipes for this step

Dispatch `catalog-identifier` to ask the navigator's process-recipe lookup twice, for each
framework the project declares. Each message names the point as `point: <phase>`, then each
framework, then the project folder. Name the role, and pass the lookup's answer in its own word:
SKILL.md holds both rules.

**`point: test-authoring`.** This answers where a test file goes, which levels exist and when
each is right, what a test may not do in this framework, and how a criterion id attaches to a test.

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

## An order whose proof is `gate`, `record` or `observe` has no test author

Read the order's `proof` from the frozen snapshot first. `gate` means its deliverable is
exported configuration, and a test that reads the YAML back cannot fail for the right reason.
Skip `tests-brief`, dispatch nobody, and put no row to anyone. Go straight to the freeze below
with no `--test`, and a `--checklist` for each criterion a person verifies. The build runs the
implement recipe's `## Configuration gate` lines as the order's own check, and `close` judges
its owned machine criterion from that check. The behavioural proof lives with the tests of the
order that consumes what it configures. Every other order takes the steps below. An order with
no `proof` at all is proved by tests; `start` names it on its `proofAbsent:` line. Design's
`update --proof gate` is the way onto the gate.

`record` means its deliverable is a document in the project folder, and nothing runs a document.
Skip `tests-brief` and dispatch no test author. Its done-when rows are its checkpoint. Put them
to the `row-checker`, or to the person, the way the checkpoint below puts a test's rows. The
question is whether each row names something a reader can confirm from the deliverable alone.
Freeze with no `--test`, one `--row <order id>=...` carrying that judgement, and a `--checklist`
for each criterion a person verifies. The build reads that row as the order's own check,
`done-when`. `close` writes the row's judge, person or model, on the criteria the order owns.

An order that freezes no test file leaves the build's `frozen-tests` row undeclared. The row
hashed nothing. So it says the row did not apply, rather than that a hash matched.

`observe` means its deliverable is what a page shows, and a model judges that after the build.
Skip `tests-brief` and dispatch no test author. Put no row to anyone: there is nothing to judge
before the page exists. Freeze with no `--test` and no `--row`, and a `--checklist` for each
criterion a person verifies. The build step opens the order's surfaces in a browser after the
implementer returns, and reads that record as the order's own check, `observed`. `close`
writes `model` on the criteria the order owns.

## Assemble what the test author may see

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh tests-brief "<task_folder>" <order id>
```

It reads the frozen copy and never the live files. It writes exactly eight things to
`implementation/brief-<order id>-tests.json`:

- this order's own record, with the criteria it owns named in `criteriaOwned`;
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

A ninth, `treeHolds`, only after a restart left this order's earlier commits on the branch.
It holds those commits and one sentence. The tree holds a partial build of this unit, so a
test that passes on arrival is suspect. The summary prints the commits on a `treeHolds:` line.

A tenth, `retake`, only while a `test-wrong` ruling is still unanswered by a freeze. It holds
the ruled finding, the criterion it names, its evidence, its severity, and the file and lines it
cites. It holds the ruling reason too, read from the review record the retake moved. It holds
the rows and the test globs the order already froze, and those rows are keyed by criterion. So
the criterion the finding names says which rows to correct.
And it says what the author must do: correct the tests the finding names,
and leave every other frozen row alone. A record a person removed is named under `absent`, and
the brief carries what is left. The summary prints a `retake:` line.

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
declares. An owned file that matches a test glob is a test, and it stays readable, so the author
can read back what it writes. So is an owned file under a directory the glob names literally,
`tests` in `**/tests/**/*Test.php`, because the author also writes base classes and fixtures
there. The globs decide, not the write path, because a framework may keep its tests beside the
source; a glob that names no directory adds nothing. Never type the denied paths here. It prints what it denied; read
that list, because it is the whole of what separates the tests from the code they judge.

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
step earlier. A hook refuses the read while the dispatch record is open.

**It may not write production code.** It writes the test, watches it fail, and stops.

**Set the tier on the dispatch.** A mid tier, in both modes. The checker reads every row at the
top tier before anything is frozen, and a person reads the rows it rejected. So the author's work
is checked before the build is measured against it, whether or not a person is present.

Resolving which recipe is this step's job; reading it is the role's. The recipe runs to well over
a hundred lines per framework, and reading it into this conversation is the cost the dispatch
exists to avoid. What the author returns is in its definition, and each item has a flag in the
freeze below. The red-run file per test goes under `--red`, and each support file under
`--support`.

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

**A failure is read from the framework's own signal, never from the exit status.** Three of five
frameworks exit zero when a filter selects nothing. Only an assertion that ran and did not hold is
a red run. A harness that never reached the behaviour is a setup gap, and a run that selected
nothing looks like success and is the dangerous one.

**When the author returns, run the coding-standards row over the new test files.** Take the
command from the check recipe `references/preconditions.md` resolved, with `{paths}` as the test
paths the author returned, and run it here. Send any finding back to the author before the
freeze. No script action runs one recipe row on its own, so this conversation runs the command.
This is the one place the tests' own standards are judged. The build step leaves the frozen tests
out of its tool rows, because the implementer may not write them.

## Put the rows to the checker, before anything is frozen

Build one row per criterion the tests name: the criterion, its verification sentence, and the names
of the tests that prove it. Build one more row when a test proves the order's done-when: the order
id, its done-when text, and those tests. The rows carry names and not test code. The question is
whether the tests named exercise the sentence beside them.

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
files, less the ones a test glob matches. Design lists an order's tests under its owned files. The checker
reads those tests, so the globs decide which owned files stay readable. Without them every owned
test file is denied, and the script refuses the call (live-run row 106). So `row-checker` cannot
open the production source behind a hook. Without this record open, the hook denies nothing. The
checker's own instructions to stay off the implementation are then just words, with nothing
enforcing them.

**Then dispatch `row-checker`**, on opus, with the message SKILL.md names. Its lines are the
role, the run mode, the rows built above, the test-authoring recipe's path, and its verdict
file's path under the task folder. The rows are the one input typed by hand, because no brief
action writes them.
Close the dispatch record as soon as it returns, per SKILL.md.

**A confirmed row is the checker's, in both modes.** It becomes
`--row <criterion id>=confirmed::model::<its note>` for the freeze below. The done-when row is keyed
by the order id in place of a criterion id: `--row wo1=confirmed::model::...`. Do not put a
confirmed row to the person. The record says a model judged it, so a person can list those rows
later and read any of them again.

**Interactive, a rejected row goes to the person, one question per row.** Open with: "The checker
doubts that the new tests for one requirement prove what it asks. A model may not settle that
alone. Confirm and the tests are kept as written. Reject and the test author rewrites them before
anything is built." Then name the requirement in its own words, the tests, the checker's note,
and the answer the note recommends. The person's answer becomes
`--row <criterion id>=confirmed::person::<the person's words>` or
`--row <criterion id>=rejected::person::<the person's words>`. A row the person rejects goes back to
the test author before any freeze runs. Never run the freeze with a rejected row still standing.
`tests-freeze` refuses it and writes nothing. Send that row back first. A repaired test goes
through the checker again. Freeze once every row for this order reads confirmed. A note may not
hold the text `; earlier: `. This stage joins one halt reason to another with that text, so a note
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
  --test-glob <pattern from the implement recipe> \
  --checklist <criterion id>=<the verification sentence> \
  --row <criterion id>=<confirmed|rejected>::<person|model>::<note> \
  --row <order id>=<confirmed|rejected>::<person|model>::<note> \
  --support <path of a support file the author returned>
```

A `--test` names its criteria or the order's own id, never both. The second form marks a test of
the order's done-when, and its name ends with the order id.

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
An `observe` order owes no row: the freeze accepts it with nothing.
It also refuses (exit 76) when the order has already left `tests-frozen`: a second freeze
would rewind the step and leave a spent attempt counter and a stale build record for tests that no
longer exist. Use `references/finish.md`'s restart when the design moved; this order goes forward
from here, not back.

The script checks the file exists, sits inside the code repository, matches the framework's own
declared pattern, and carries at the end of its name the criterion it claims. A done-when test
carries the order id there instead. It checks every machine-verified criterion this order owns has
a test (a `gate` or `record` order excepted), and every criterion a person verifies has a checklist line. A criterion this order only
serves needs no test from it, because its proof lives with its owner (exit 29 reads the owned
list). A test that names neither a criterion this order serves or owns nor this order's id refuses
(exit 31). A name that does not end in what it claims refuses (exit 28). A record that would hold
no row refuses (exit 74).
It checks every test has the output of the run that failed, or a `--locks-in` reason in its
place. A test with neither refuses (exit 33). It reads each `--red` file against the markers the
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

**Every machine-verified criterion a `--test` names needs exactly one row**, naming whether it was
confirmed or rejected and who judged it. A done-when test needs the done-when row, keyed by the
order id. Rows follow the tests. A criterion this order only serves and names on no test needs no
row from it; the row for it belongs to its owner. A criterion a person verifies carries a
checklist instead, never a row: it has no judgement, and completion is what confirms it. A row for
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
