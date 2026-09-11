# Write the tests for one work order

This step runs once per work order, not once per build. An order is ready when every order it
depends on is finished.

The tests are the reference the whole build is measured against. Everything below exists to keep
that reference outside the thing it judges.

## Resolve the recipes for this step

Dispatch `catalog-identifier` to ask the navigator's process-recipe lookup twice, for each
framework the project declares. Name the role: a dispatch that names none runs as the general
agent with every tool, and the role exists so a catalog listing lands in the agent and not here.

**The `test-authoring` point.** This answers where a test file goes, which levels exist and when
each is right, what a test may not do in this framework, and how a criterion id attaches to a test.
Three answers, not one: no recipe for this framework, a listing that could not be reached, and a
failed network are different things, and only the first says anything about the framework.

**The `implement` point, for one thing only.** Take the file patterns its declaration names for
tests, and pass them to the freeze below. This is the one recipe this step reads itself, because it
needs the patterns as data rather than as instruction.

Do not give this recipe to the test author. It carries the standards and the steps that write
production code, and that role may write neither. Pass its path to `dispatch-open` as
`--deny-read`, so the rule is a permission the runtime applies and not a sentence asking a model to
leave a file alone. It is the one path this step names by hand; the production source is derived
from the snapshot, below.

Resolve the patterns once, here, and let them be recorded. The rule that later refuses a write to a
frozen test reads the record and never the catalog, because a lookup in a write path is a lookup
that can fail open, and a pattern that changed during a build would change what is protected
halfway through it.

## Assemble what the test author may see

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh tests-brief "<task_folder>" <order id>
```

It reads the frozen copy and never the live files, and it emits exactly four things: this order's
own record, the criteria it serves and owns with their verification and who verifies each, the
boundaries it names, and the declared interface of every order it depends on.

That list is the withheld list, decided once rather than at each dispatch. Pass what it emits and
nothing else. Adding an input here is a change to the role, not a judgement made in the moment.

An interface record is prose a builder wrote about its own code. It is not the code, and that is
the line.

## Open the dispatch record, then dispatch the test author

The two rules below are applied by the runtime. Both read one record, and the build is serial, so a
project has at most one open dispatch at a time.

Open it first:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh dispatch-open "<task_folder>" test-author <order id> \
  --deny-read <path of the recipe that carries the coding standards> \
  --allow-write <path the tests go in>
```
The script refuses a role name that matches no agent this plugin ships, and for this role it adds
the production source to the denied reads itself, taken from the owned files every work order in
the frozen snapshot declares. Never type those paths here. It prints what it denied; read that
list, because it is the whole of what separates the tests from the code they judge.

Close it as soon as the role returns, whether it succeeded or not:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh dispatch-close "<task_folder>"
```
A record left open makes the next dispatch refuse, and it names the role and order still holding it.

**Then dispatch `test-author`.** Name the role. It is not the context that writes the code, and it
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

Give it the **path** to the test-authoring recipe for its framework, what `tests-brief` emitted,
and nothing else. It opens the recipe itself. Do not read the body here and paste it in: the recipe
runs to well over a hundred lines per framework, and reading it into this conversation is the cost
the dispatch exists to avoid. Resolving which recipe is this step's job; reading it is the role's.

Ask it to return, for each test, the path, the name, the criterion the name carries, and what the run
printed when the test failed. Ask it to return a checklist line for each criterion a person
verifies, copying the verification sentence whole.

**A test that passes before any code exists proves nothing.** It is corrected once. If it still
passes, it is reported by name and the step stops. It is never deleted quietly and never weakened
into failing.

**A failure is read from the framework's own signal, never from the exit status.** Three of five
frameworks exit zero when a filter selects nothing. Only an assertion that ran and did not hold is
a red run. A harness that never reached the behaviour is a setup gap, and a run that selected
nothing looks like success and is the dangerous one.

## Put the rows to the person, before anything is frozen

Show one row per criterion: the criterion, its verification sentence, and the names of the tests
that prove it. Show the rows and not the test code. The question is whether the tests named
exercise the sentence beside them, and test code invites a review of the code instead.

**Interactive, ask row by row.** Each answer becomes one
`--row <criterion id>=confirmed::person::<the person's words>` or
`--row <criterion id>=rejected::person::<the person's words>` for the freeze below. A row the
person rejects goes back to the test author before any freeze runs. Never run the freeze with a
rejected row still standing. `tests-freeze` refuses it and writes nothing. Send that row back
first, and freeze once every row for this order reads confirmed.

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
and the path its verdict file goes to, under the task folder, and nothing else. It reads the verify
clause and each named test, never the implementation, and answers confirmed or rejected with a note
for each row. Close the dispatch record as soon as it returns, whether it succeeded or not:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh dispatch-close "<task_folder>"
```

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
  --red <test name>=<path to a file holding what the run printed> \
  --test-glob <pattern from the implement recipe> \
  --checklist <criterion id>=<the verification sentence> \
  --row <criterion id>=<confirmed|rejected>::<person|model>::<note>
```

The script checks the file exists, sits inside the code repository, matches the framework's own
declared pattern, and carries at the end of its name the criterion it claims. It checks every
criterion a machine verifies has a test and every criterion a person verifies has a checklist line.
It checks every test has the output of the run that failed.

**Every machine-verified criterion this order serves or owns needs exactly one row**, naming
whether it was confirmed or rejected and who judged it. A criterion a person verifies carries a
checklist instead, never a row: it has no judgement, and completion is what confirms it. A row for
a criterion this order does not serve or own refuses the freeze, the same way a missing row does.
So does a row for a criterion a person verifies. Every accepted row is appended to that criterion's
own record in the ledger. `close` is what decides the criterion from it, once every order serving
it has closed.

Then it records a hash for each test file. That hash is the freeze. From here a hook refuses a
write to one of those files from every dispatched role except the test author of the order that
froze it.

A person is not a role, and is not refused. A freeze is not a lock: it exists so a change is
noticed, and the hash is what notices one. The hook allows the write and says which file changed and
which order froze it.

Report a test that passed on arrival with `--green-on-arrival <test name>=<reason>`. The script
stops the step rather than recording it, which is the right outcome: a test nobody watched fail is
not a reference.

A record is taken once per commit. A second run at the same commit leaves it alone. One taken at a
different commit refuses and names both.
