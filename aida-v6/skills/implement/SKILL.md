---
name: implement
description: This skill should be used when a task's design has closed cleanly and it is time to begin building, for example "start implementing this task", "begin the build", or "Phase 3". It freezes the criteria and the work orders into a snapshot, opens the ledger that tracks each order's progress, refuses to land the build on the project's own trunk branch, and then establishes whether this repository can build and test at all. It does not yet build a work order.
disable-model-invocation: true
argument-hint: "[<task-id>]"
arguments: [taskId]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/implement/scripts/implement-actions.sh *)
---

# Implement

Implementation builds each work order design wrote, one at a time, against tests it cannot
change once they are frozen. **Only the first two steps of that exist today. One freezes the
contract and the work orders into a snapshot and opens the ledger that will track every order's
progress. Two establishes whether this repository can run a test at all.** Building a work order,
writing a test, or closing an order is not built yet. Say this plainly once the reports below are
shown, so nobody expects more than these two steps did.

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

Read the project's own `frameworks`. For each one, ask the navigator's process-recipe lookup for
the `test-execution` point and that framework. It answers whether one is available and, when it
is, a path to the body on disk. Never fetch a catalog address yourself and never read a cached copy
behind the navigator's back. A source this project configured itself, a folder of its own, is read
the ordinary way and wins over the catalog.

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

## What this skill does not do yet

It does not resolve the commands that run tests, take a baseline, write a test, watch one fail,
write a trace row, freeze a test file, write code, run the deciding checks, run a review, or close
a work order. There is no action for any of those yet.

After the conditions, the step runs each framework's cheapest test command, the one that proves the
harness reports at all. It runs only where that framework's conditions came back satisfied or
undeclared, because running it after a condition answered no would fail for a reason already known.
Its result folds into the same verdict, and where it did not succeed the record keeps what the
command printed.

This step stops there. Once the report above is shown, the
conversation for this stage is finished until the next part is built.
