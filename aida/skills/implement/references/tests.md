# Write the tests for one work order

This step runs once per work order, not once per build. An order is ready when every order it
depends on is finished.

The tests are the reference the whole build is measured against. Everything below exists to keep
that reference outside the thing it judges.

## Resolve the recipes for this step

Dispatch `catalog-identifier` to ask the navigator's process-recipe lookup twice, for each
framework the project declares. Name the role, and pass the lookup's answer in its own word:
SKILL.md holds both rules.

**The `test-authoring` point.** This answers where a test file goes, which levels exist and when
each is right, what a test may not do in this framework, and how a criterion id attaches to a test.

**The `implement` point, for one thing only.** Take the file patterns from its `## Oracle files`
block, the same globs the `test_delete` row names. The catalog index designates that block for
naming test files, so this is not a guess at what the block is for. Pass those globs to the freeze
below. This is the one recipe this step reads itself, because it needs the patterns as data rather
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

## An order whose proof is `gate` has no test author

Read the order's `proof` from the frozen snapshot first. `gate` means its deliverable is
exported configuration, and a test that reads the YAML back cannot fail for the right reason.
Skip `tests-brief`, dispatch nobody, and put no row to anyone. Go straight to the freeze below
with no `--test`, and a `--checklist` for each criterion a person verifies. The build runs the
implement recipe's `## Configuration gate` lines as the order's own check, and `close` judges
its owned machine criterion from that check. The behavioural proof lives with the tests of the
order that consumes what it configures. Every other order takes the steps below.

## Assemble what the test author may see

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh tests-brief "<task_folder>" <order id>
```

It reads the frozen copy and never the live files. It writes exactly six things to
`implementation/brief-<order id>-tests.json`:

- this order's own record, with the criteria it owns named in `criteriaOwned`;
- the criteria it serves and owns, with their verification and who verifies each;
- the boundaries it names;
- the declared interface of every order it depends on;
- `reuses`, the path and the interface of every existing thing design's dispose recorded on
  this order. A reused module is production source of no work order, so this is the only place
  the test author gets its shape. An order disposed with no path carries none;
- `playbooksPath`, the path of `records/playbooks.json` when research loaded one, else null.

It prints the brief's path and counts, never the brief.

That list is the withheld list, decided once rather than at each dispatch. Pass the brief's path
and nothing else. Adding an input here is a change to the role, not a judgement made in the moment.

An interface record is prose a builder wrote about its own code. It is not the code, and that is
the line.

## Open the dispatch record, then dispatch the test author

`--deny-read` below is applied by the runtime, through the read-denial hook. `--allow-write` is
not: no hook reads it. It is recorded for a person reading the dispatch record later, the same as
the read denial and the shell door named under "What this skill does" in `SKILL.md`. The build is
serial, so a project has at most one open dispatch at a time.

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

**Then dispatch `test-author`.** Name the role, per SKILL.md. It is not the context that writes the code, and it
is not this conversation either: a dispatch that names no role runs as the general agent, with
every tool and this session's own model, and the record just opened matches nothing. Both hooks
recognise a role by the agent's own type, so writing the tests here instead of dispatching leaves
every rule below unenforced while the record on disk says otherwise.

**It may not read production source.** Not this order's, and not any order already built. If it
sees the code, the tests describe the code instead of the intent, which is the same failure one
step earlier. A hook refuses the read while the dispatch record is open.

**It may not write production code.** It writes the test, watches it fail, and stops.

**Set the tier on the dispatch.** A mid tier where a person will read the rows before anything is
frozen. The top tier where the run is unattended, because then nobody reads them and the whole
build is measured against work nothing checked first.

Give it the **path** to the test-authoring recipe for its framework, the **path** of the brief
`tests-brief` wrote, and nothing else. It opens both itself. Do not read either body here and paste
it in. The recipe runs to well over a hundred lines per framework, and reading it into this
conversation is the cost the dispatch exists to avoid. Resolving which recipe is this step's job;
reading it is the role's.

Ask it to return, for each test, the path, the name, and the criterion the name carries. A test of
the order's own done-when returns the order id in place of a criterion. For each test, it writes
what the run printed when the test failed to its own file, under the task folder's `implementation/`
folder, one file per test, and returns that file's path in its report. `--red` below reads that
path. Ask it to return a checklist line for each criterion a person verifies, copying the
verification sentence whole.

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

## Put the rows to the person, before anything is frozen

Show one row per criterion the tests name: the criterion, its verification sentence, and the names
of the tests that prove it. Show one more row when a test proves the order's done-when: the order
id, its done-when text, and those tests. Show the rows and not the test code. The question is
whether the tests named exercise the sentence beside them, and test code invites a review of the
code instead.

**Interactive, ask row by row.** Each answer becomes one
`--row <criterion id>=confirmed::person::<the person's words>` or
`--row <criterion id>=rejected::person::<the person's words>` for the freeze below. The done-when
row is keyed by the order id in place of a criterion id: `--row wo1=confirmed::person::...`. A row the
person rejects goes back to the test author before any freeze runs. Never run the freeze with a
rejected row still standing. `tests-freeze` refuses it and writes nothing. Send that row back
first, and freeze once every row for this order reads confirmed. A note may not hold the text
`; earlier: `, the text this stage joins one halt reason to another with; a note carrying it would
forge a halt nobody wrote, so `tests-freeze` refuses the flag rather than write it.

**Unattended, there is nobody to ask.** Dispatch `row-checker`. This reading stands in for the one
place a person is the only check on whether a test asserts deeply enough. Pay the top tier for what
is left. Open the dispatch record first, the same way every other role gets one:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh dispatch-open "<task_folder>" row-checker <order id>
```
The script derives the denied reads itself, the same way it does for the test author: every order's
owned files. So `row-checker` cannot open the production source behind a hook. Without this record
open, the hook denies nothing. The checker's own instructions to stay off the implementation are
then just words, with nothing enforcing them.

**Then dispatch `row-checker`.** Name the role, and set the model to opus. Give it this order's rows
and the path its verdict file goes to, under the task folder, and nothing else. A done-when row
carries the order id and the done-when text where a criterion row carries the id and the verify
clause. It reads that text and each named test, never the implementation, and answers confirmed or
rejected with a note for each row. Close the dispatch record as soon as it returns, per SKILL.md.

Turn its answers into `--row <criterion id>=<verdict>::model::<its note>` for the freeze. A row it
rejects is not sent back to the test author the way a person's rejection is. Nobody is present to
judge the correction, so `tests-freeze` writes the halt onto the order, with the checker's own note
as the reason. Then it refuses. Report the halt, and take the next ready order instead.

**The judge has to match the run mode.** A row judged `person` on an autonomous run, or judged
`model` on an interactive one, refuses. The freeze exists to record who actually looked, and a
mismatched row would let one stand in for the other silently.

## Freeze what came back

Run, with one flag per test, per failure output, per pattern, and per row:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh tests-freeze "<task_folder>" <order id> \
  --test <path>::<test name>=<criterion id> \
  --test <path>::<test name>=<order id> \
  --red <test name>=<path to a file holding what the run printed> \
  --locks-in <test name>=<one sentence naming the existing code that satisfies it> \
  --test-glob <pattern from the implement recipe> \
  --checklist <criterion id>=<the verification sentence> \
  --row <criterion id>=<confirmed|rejected>::<person|model>::<note> \
  --row <order id>=<confirmed|rejected>::<person|model>::<note>
```

A `--test` names its criteria or the order's own id, never both. The second form marks a test of
the order's done-when, and its name ends with the order id.

This refuses outright (exit 74) when the order serves and owns no criterion at all: there is
nothing for a test to prove and nothing here to freeze, and the repair is the work order, not this
step. A `gate` order is the one order that freezes with no test row, and it refuses a `--test`. It also refuses (exit 76) when the order has already left `tests-frozen`: a second freeze
would rewind the step and leave a spent attempt counter and a stale build record for tests that no
longer exist. Use `references/finish.md`'s restart when the design moved; this order goes forward
from here, not back.

The script checks the file exists, sits inside the code repository, matches the framework's own
declared pattern, and carries at the end of its name the criterion it claims. A done-when test
carries the order id there instead. It checks every machine-verified criterion this order owns has
a test, and every criterion a person verifies has a checklist line. A criterion this order only
serves needs no test from it, because its proof lives with its owner (exit 29 reads the owned
list). A test that names neither a criterion this order serves or owns nor this order's id refuses
(exit 31). A name that does not end in what it claims refuses (exit 28). A record that would hold
no row refuses (exit 74).
It checks every test has the output of the run that failed, or a `--locks-in` reason in its
place. A test with neither refuses (exit 33). That check is a bound, not a proof: it
confirms the file is not empty, and nothing in it confirms the framework's own failure signal
appears there. A file holding "0 tests ran" passes the same way a real assertion failure does. A
`--locks-in` reason is recorded beside the test, and the review brief says where it is.

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

Then it commits the test files it hashed, on the task branch, and only those paths. The
implementer starts from a tree that already holds the tests, and the record's commit is the one
they are in. Work beside them stays uncommitted, and the freeze says so in one line. A commit that
fails, for want of a git identity or any other reason, refuses before the record is written,
with git's own message.

A person is not a role, and is not refused. A freeze is not a lock: it exists so a change is
noticed, and the hash is what notices one. The hook allows the write and says which file changed and
which order froze it.

Report a test that passed on arrival with `--green-on-arrival <test name>=<reason>`. The script
stops the step rather than recording it, which is the right outcome: a test nobody watched fail is
not a reference. This is a bound, not a rule the script enforces on its own: nothing here notices a
green-on-arrival test the caller does not flag, so the flag is on you.

A record is taken once. A second run with the same tests leaves it alone, whatever commit the
tree is at now, because every freeze moves the tree. Different tests at a different commit
refuse and name both commits.
