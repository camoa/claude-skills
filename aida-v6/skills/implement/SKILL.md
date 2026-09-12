---
name: implement
description: This skill should be used when a task's design has closed cleanly and it is time to begin building, for example "start implementing this task", "begin the build", or "Phase 3". It freezes the criteria and the work orders into a snapshot, opens the ledger that tracks each order's progress, refuses to land the build on the project's own trunk branch, establishes whether this repository can build and test at all, writes the tests for one work order and freezes them, writes the code for that order until it passes all eight deciding checks, reviews the diff, repairs what the review finds, closes the order, and once every order is closed records the task's implementation as finished.
disable-model-invocation: true
argument-hint: "[<task-id>]"
arguments: [taskId]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/implement/scripts/implement-actions.sh *), Agent
---

# Implement

Implementation builds each work order design wrote, one at a time, against tests it cannot
change once they are frozen. One freezes the contract and the work orders into a snapshot and
opens the ledger that will track every order's progress. Two establishes whether this repository
can run a test at all. Three writes the tests for one work order, watches each one fail, and
freezes them. Four writes the code until it passes all eight deciding checks. Five reviews the
diff, repairs what the review finds, verifies each repair, and closes the order. Once every order
closes, `finish` records the task's own implementation as done and hands it to the review stage.

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
record already exist, and each order's last step and halt reason from the ledger.

No contract, or design has not started: say so in one line and name the missing stage. Stop.

## Which step, and where its instructions are

The report from `read` says where this task is. Match it to one step, open that step's own file,
and follow it. Each file holds everything for its step and nothing for another, so only the step
being run is in this conversation.

| The report says | The step | Step name |
|---|---|---|
| No snapshot, or a snapshot with no ledger | Start the build | `start` |
| A ledger, and `preconditions.exists` is false | Check the preconditions | `preconditions` |
| Preconditions recorded, and a ready order whose last step is null | Write the tests for one work order | `tests` |
| An order whose last step is `tests-frozen`, or `code-written` with attempts remaining and no halt reason | Write the code for one work order | `build` |
| An order at `checks-passed` | Review the order | `review` |
| An order `reviewed` or `fixed`, with an open actionable finding and a fix round left | Fix, then verify | `review` |
| An order `reviewed` or `fixed`, with nothing open | Close the order | `review` |
| An order `closed` | Nothing left to do on it. Take the next ready order | |
| Every order closed, no `finished` record | Finish the task | `finish` |
| An order whose `haltedBecause` holds a `design drift...` segment, anywhere in it | Offer the restart | `finish` |
| An order whose `haltedBecause` holds an `attempts spent...` segment and no `design drift...` one, a person present | Offer the grant | `finish` |

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

A halt beginning `attempts spent` or `design drift` has its own next step in `references/finish.md`:
the grant of one more attempt, or the restart after a design change. Offer either only when a
person is present to decide it.

Open the step file through the script, not through the Read tool:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh step <step name>
```
This prints `references/<step name>.md`. A `Read` rule naming that folder does not reliably
expand `${CLAUDE_PLUGIN_ROOT}`, which is why this skill grants only the one Bash rule above. Run
`step` every time this table sends you to a file, even a file already read this turn. A step run
from memory of an earlier invocation is a step run against rules that may have changed.

## Four rules every step repeats

These hold for every step below, and each step file names them rather than restating them. This
file is always loaded; a step file is loaded only while its own step runs.

**Name the role on every dispatch.** A dispatch that names none runs as the general agent, with
every tool and this session's own model, and the dispatch record just opened then matches nothing:
the hook compares the agent's own type against the role in the record, so an unnamed dispatch is an
unenforced one.

**A recipe lookup has three answers, not one.** No recipe for this framework, a listing that could
not be reached, and a failed network are three different things, and only the first says anything
about the framework. Pass the one that happened, in its own word.

**The script reads a recipe's command blocks, never you.** Pass a recipe path straight through to
the action that takes it. `## Test commands` and `## Check commands` are parsed by the script, one
entry per tool, each with its own argv, its `{paths}` placeholder, and its `signal` and `extensions`
keys where present. It refuses (exit 72) when two frameworks each command one tool.

**Close the dispatch record as soon as the role returns**, whether it succeeded or not:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh dispatch-close "<task_folder>"
```
It refuses (exit 75) when the open record names a different task than this one: closing another
task's record would leave that task's own role holding every permission the record withheld.

## What this skill does

The permissions this step describes are applied by the runtime, not by the words above. Two hooks
do it, and both report through a message when they cannot find what they need rather than passing in
silence. Neither has run inside a live dispatch yet, so say that plainly rather than reporting them
as proven.

The read denial covers Read and Grep, and not the shell. The test author runs its own tests, so it
holds Bash, so a `cat` of a denied file is not refused. That is deliberate: the rule exists to stop
the role opening the source because reading the code is the obvious way to write a test about it,
and a role working around the rule on purpose has already failed in ways no hook catches. Say that
when the person asks what the dispatch enforces, rather than describing the denial as complete.

`dispatch-open`'s `--allow-write` is a third thing withheld, beside the read denial and the shell
door above. It is recorded for a reader, and no hook applies it. The frozen-test hook decides by
whether a path is frozen, never by this flag. Say the same about it that you say about the other
two: recorded, not enforced.

The five answers a builder or a fixer writes into its report are a fourth. The record steps refuse
an empty report file, and nothing checks the file holds five answers, that they preceded the write,
or that the diff stayed inside them. Recorded, not enforced.

The tool grants in this file's own frontmatter hold for one turn. The runtime clears them at your
next message to the person, so a multi-turn build asks again for the Bash rule after that message.
That is how a skill's grants work, not a fault in this one. Say so when a person asks why the same
command prompts again partway through a build.
