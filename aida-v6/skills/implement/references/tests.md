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

A row the person sends back goes to the test author again. A row they accept is ready to freeze.

Unattended, there is nobody to ask. Record that the rows were not read, and freeze. This is the one
place where the person is the only check on whether a test asserts deeply enough, so a run that
skips it is saying so out loud.

## Freeze what came back

Run, with one flag per test, per failure output, and per pattern:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh tests-freeze "<task_folder>" <order id> \
  --test <path>::<test name>=<criterion id> \
  --red <test name>=<path to a file holding what the run printed> \
  --test-glob <pattern from the implement recipe> \
  --checklist <criterion id>=<the verification sentence>
```

The script checks the file exists, sits inside the code repository, matches the framework's own
declared pattern, and carries at the end of its name the criterion it claims. It checks every
criterion a machine verifies has a test and every criterion a person verifies has a checklist line.
It checks every test has the output of the run that failed.

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
