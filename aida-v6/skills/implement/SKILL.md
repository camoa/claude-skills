---
name: implement
description: This skill should be used when a task's design has closed cleanly and it is time to begin building, for example "start implementing this task", "begin the build", or "Phase 3". It freezes the criteria and the work orders into a snapshot, opens the ledger that tracks each order's progress, refuses to land the build on the project's own trunk branch, establishes whether this repository can build and test at all, and then writes the tests for one work order and freezes them. It does not yet write the code.
disable-model-invocation: true
argument-hint: "[<task-id>]"
arguments: [taskId]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/implement/scripts/implement-actions.sh *), Agent
---

# Implement

Implementation builds each work order design wrote, one at a time, against tests it cannot
change once they are frozen. **Only the first three steps of that exist today. One freezes the
contract and the work orders into a snapshot and opens the ledger that will track every order's
progress. Two establishes whether this repository can run a test at all. Three writes the tests
for one work order, watches each one fail, and freezes them.** Writing the code, running the
deciding checks, reviewing, fixing and closing an order are not built yet. Say this plainly once
the reports below are shown, so nobody expects more than these three steps did.

## Find the task

Resolve the active project's own folder first, then the task, `<taskId>` when given or whichever
task is already active in this conversation. Neither known: say so in one line and name the task
skill. Stop; there is nowhere to act.

Once found, the task's own folder is `<projectPath>/tasks/<task-id>`. Every call below takes that
folder.

## Read what is already there

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh read "<task_folder>"
```
This reports the contract's state, whether design has started and how many work order files it
left, the task's project and its code repository, the repository's current branch and its trunk
branch when derivable, the task's own run mode, and whether a snapshot or a ledger already exist.

No contract, or design has not started: say so in one line and name the missing stage. Stop.

## Start the build

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh start "<task_folder>"
```

This is the whole first step. It checks, in order: the task folder and its contract, that design
closed cleanly, that the task's project is a git repository, that codePath is on a named branch,
and that the build would not land on that repository's own trunk branch. Any one of these refuses
before anything is written, and the message names what to fix. Read a refusal and act on it; do
not repeat the same call unchanged.

A first run also checks that design has formally closed: <task_folder>/design-closed.json must
exist and its recorded hash must agree with a hash re-derived from the live contract and work
orders. Missing means design has never closed; run the design skill's close action. A disagreeing
hash means design closed once and something changed since, without closing again; close design
again. Both are refusals, and both leave nothing written.

A detached HEAD in codePath refuses outright, whether or not the trunk branch can even be derived.
A commit made there belongs to no branch, which this build must never risk.

When the trunk branch cannot be derived, because there is no `origin` remote or its head is
unset, the script says so and continues. That is a check that could not look, not a pass and not
a refusal. Tell the person plainly that the trunk was not confirmed, rather than reporting it as
either.

On success the script prints one report: whether this is a new run or a resumed one, the frozen
snapshot's own counts, which order is in flight and at what step, what drifted since an earlier
snapshot and which work orders that halted, which orders are ready to build, and what the trunk
check could establish. Read the whole report to the person before doing anything else.

A first run has no earlier snapshot to compare against. The report says the drift check did not
apply, never that nothing changed; those are different facts and only the report's own `checked`
field tells them apart. Say the same to the person: nothing was compared yet, not that a check
found nothing.

A resumed run that halts one or more work orders for drift is not a failure. Say plainly which
orders halted and why. A halted order stays halted until a person looks at it; nothing here
un-halts one automatically, and nothing here decides whether the drift is acceptable.

## Check the preconditions

The build has started. Now find out whether this repository can run a test at all. This step runs
once per build, not once per work order.

### Resolve one recipe per framework

Read the project's own `frameworks`. For each one, dispatch `catalog-identifier` to ask the
navigator's process-recipe lookup for the `test-execution` point and that framework. It answers
whether one is available and, when it is, a path to the body on disk.

**Name the role.** A dispatch that names none runs as the general agent, with every tool and this
session's own model. The role exists so a catalog listing lands in the agent and not here: it
identifies and returns a path, and it never opens the body. Never fetch a catalog address yourself
and never read a cached copy behind the navigator's back. A source this project configured itself,
a folder of its own, is read the ordinary way and wins over the catalog.

**Three answers, not one.** No recipe for this framework, a listing that could not be reached, and
a failed network are three different things, and only the first says anything about the framework.
Pass the one that happened, in its own word.

### Run the checks

Run, with one flag per framework:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh preconditions "<task_folder>" \
  --recipe <framework>=<path to the recipe body> \
  --lookup-failed <framework>=<no-recipe|listing-unreachable|fetch-failed>
```
Every framework the project declares needs one flag or the other. The script refuses rather than
guess, because a lookup nobody ran must never be recorded as a recipe that declared nothing.

The script reads each recipe's declared conditions, runs each check inside the code repository,
and writes what it found. It never hands a check to a shell.

### Supply a value where a command needs one

A framework's cheapest test command may carry a placeholder, such as the runner a Python project
declares. Pass it with `--value <name>=<value>`. The script never guesses one and never reads a
default out of a recipe's prose: an unsupplied placeholder makes the run undecidable and names
which one had no value.

### Read the four verdicts to the person

- **met.** Every declared condition answered yes. The build can go on.
- **unmet.** A condition answered no. Name it, name the framework, and name the owner the recipe
  gave. An owner is the action; without one the person has to work out what to do.
- **unknown.** Nobody could tell. A checker that is not installed says nothing about the condition
  it was meant to probe, so this is never reported as a failure of the condition.
- **undeclared.** The recipe named no conditions. Say that, and never say met. A recipe that
  declared nothing was not checked.

`met` and `undeclared` both continue. A recipe saying this framework needs nothing before a test
runs has answered, and stopping on it would mean no project on that framework ever builds. Say
which of the two happened; never report `undeclared` as conditions that passed.

`unmet` and `unknown` stop, and the person decides. In an unattended run they halt. Nothing here
judges an unmet condition acceptable.

Say which frameworks were answered from a recipe and which were not. A framework whose recipe could
not be reached was not checked, and reporting the run as clean would be false.


## Write the tests for one work order

This step runs once per work order, not once per build. An order is ready when every order it
depends on is finished.

The tests are the reference the whole build is measured against. Everything below exists to keep
that reference outside the thing it judges.

### Resolve the recipes for this step

Dispatch `catalog-identifier` to ask the navigator's process-recipe lookup twice, for each
framework the project declares. Name the role, for the reason the step before gives.

**The `test-authoring` point.** This answers where a test file goes, which levels exist and when
each is right, what a test may not do in this framework, and how a criterion id attaches to a test.
The same three answers apply as in the step before: no recipe for this framework, a listing that
could not be reached, and a failed network are different things, and only the first says anything
about the framework.

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

### Assemble what the test author may see

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

### Open the dispatch record, then dispatch the test author

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

### Put the rows to the person, before anything is frozen

Show one row per criterion: the criterion, its verification sentence, and the names of the tests
that prove it. Show the rows and not the test code. The question is whether the tests named
exercise the sentence beside them, and test code invites a review of the code instead.

A row the person sends back goes to the test author again. A row they accept is ready to freeze.

Unattended, there is nobody to ask. Record that the rows were not read, and freeze. This is the one
place where the person is the only check on whether a test asserts deeply enough, so a run that
skips it is saying so out loud.

### Freeze what came back

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

## What this skill does not do yet

It does not write code, run the deciding checks, run a review, fix a finding, or close a work
order. There is no action for any of those yet.

The permissions this step describes are applied by the runtime, not by the words above. Two hooks
do it, and both report through a message when they cannot find what they need rather than passing in
silence. Neither has run inside a live dispatch yet, so say that plainly rather than reporting them
as proven.

The read denial covers Read and Grep, and not the shell. The test author runs its own tests, so it
holds Bash, so a `cat` of a denied file is not refused. That is deliberate: the rule exists to stop
the role opening the source because reading the code is the obvious way to write a test about it,
and a role working around the rule on purpose has already failed in ways no hook catches. Say that
when the person asks what the dispatch enforces, rather than describing the denial as complete.

After the conditions, the step runs each framework's cheapest test command, the one that proves the
harness reports at all. It runs only where that framework's conditions came back satisfied or
undeclared, because running it after a condition answered no would fail for a reason already known.
Its result folds into the same verdict, and where it did not succeed the record keeps what the
command printed.

Last, it records what was already broken at the commit the build started from. The suite runs
whole, because the orders' tests do not exist yet and no framework maps changed paths to the tests
covering them. The three tools that take paths have no recipe naming them at this point, so each
records that none is declared. A suite that is already red is recorded, never refused: knowing it
is the point, because a builder chasing a failure it did not cause spends every attempt it has.

The baseline is taken once, at that commit. A second run at the same commit leaves it alone. One
recorded at a different commit refuses rather than overwrites, and names both commits.

This step stops there. Once the report above is shown, the
conversation for this stage is finished until the next part is built.
