---
name: implement
description: This skill should be used when a task's design has closed cleanly and it is time to begin building, for example "start implementing this task", "begin the build", or "Phase 3". It freezes the criteria and the work orders into a snapshot, opens the ledger that tracks each order's progress, refuses to land the build on the project's own trunk branch, establishes whether this repository can build and test at all, then writes the tests for one work order and freezes them, and then writes the code for that order until they pass. It does not yet review, fix or close an order.
disable-model-invocation: true
argument-hint: "[<task-id>]"
arguments: [taskId]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/implement/scripts/implement-actions.sh *), Read(/${CLAUDE_PLUGIN_ROOT}/skills/implement/references/*), Agent
---

# Implement

Implementation builds each work order design wrote, one at a time, against tests it cannot
change once they are frozen. **Only the first four steps of that exist today. One freezes the
contract and the work orders into a snapshot and opens the ledger that will track every order's
progress. Two establishes whether this repository can run a test at all. Three writes the tests
for one work order, watches each one fail, and freezes them. Four writes the code until they pass
and runs four of the eight deciding checks.** Reviewing, fixing and closing an order are not built
yet. Say this plainly once a step's report is shown, so nobody expects more than these four steps
do.

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
branch when derivable, the task's own run mode, whether a snapshot, a ledger and a preconditions
record already exist, and each order's last step from the ledger.

No contract, or design has not started: say so in one line and name the missing stage. Stop.

## Which step, and where its instructions are

The report from `read` says where this task is. Match it to one step, open that step's own file,
and follow it. Each file holds everything for its step and nothing for another, so only the step
being run is in this conversation.

| The report says | The step | Read |
|---|---|---|
| No snapshot, or a snapshot with no ledger | Start the build | `references/start.md` |
| A ledger, and `preconditions.exists` is false | Check the preconditions | `references/preconditions.md` |
| Preconditions recorded, and a ready order whose last step is null | Write the tests for one work order | `references/tests.md` |
| An order whose last step is `tests-frozen`, or `code-written` with attempts remaining and no halt reason | Write the code for one work order | `references/build.md` |
| An order at `checks-passed` | Nothing yet. Review is not built. Say so and leave it | |

A resumed run starts at `start` regardless, because that is where drift since the snapshot is
checked, and it says which orders halted. Then the table applies.

## One order halting does not stop the run

When an order halts, at its attempt cap or for drift, only the orders that depend on it wait.
Everything else that is ready still builds. Run `start` again: it is safe on a resumed run, and it
reports which orders are ready, which halted and why, and which are in flight. Take the next ready
order and apply the table. Stop only when nothing is ready.

Then report what halted, with the reason the ledger holds, and what is waiting on it. Interactive
puts that to the person, who decides from the recorded attempts which of three things is true: the
test is wrong, the order is wrong, or the code is hard and a person writes it. Unattended, the run
ends there with the report, and decides none of the three. A model ruling that a test is wrong,
with nobody watching, is the test describing the code again.

Read the file with the Read tool from the plugin's own folder, at
`${CLAUDE_PLUGIN_ROOT}/skills/implement/references/`. A step run from memory of an earlier
invocation is a step run against rules that may have changed.

## What this skill does not do yet

It does not run a review, fix a finding, or close a work order. There is no action for any of
those yet, and four of the eight deciding checks have no step that runs them.

The permissions this step describes are applied by the runtime, not by the words above. Two hooks
do it, and both report through a message when they cannot find what they need rather than passing in
silence. Neither has run inside a live dispatch yet, so say that plainly rather than reporting them
as proven.

The read denial covers Read and Grep, and not the shell. The test author runs its own tests, so it
holds Bash, so a `cat` of a denied file is not refused. That is deliberate: the rule exists to stop
the role opening the source because reading the code is the obvious way to write a test about it,
and a role working around the rule on purpose has already failed in ways no hook catches. Say that
when the person asks what the dispatch enforces, rather than describing the denial as complete.
