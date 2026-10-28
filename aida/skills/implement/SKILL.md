---
name: implement
description: This skill should be used when a task's design has closed cleanly and it is time to begin building, for example "start implementing this task", "begin the build", or "Phase 3". It freezes the criteria and the work orders into a snapshot, opens the ledger that tracks each order's progress, refuses to land the build on the project's own trunk branch, establishes whether this repository can build and test at all, writes the tests for one work order and freezes them, writes the code for that order until it passes all eight deciding checks, reviews the diff, repairs what the review finds, closes the order, and once every order is closed records the task's implementation as finished.
argument-hint: "[<task-id>]"
arguments: [taskId]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/implement/scripts/implement-actions.sh *), Bash(${CLAUDE_PLUGIN_ROOT}/skills/task/scripts/task-actions.sh --run-mode interactive create *), Agent, EnterWorktree
---

# Implement

Implementation builds each work order design wrote, one at a time, against tests it cannot
change once they are frozen. One freezes the contract and the work orders into a snapshot and
opens the ledger that will track every order's progress. Two establishes whether this repository
can run a test at all. Three writes the tests for one work order, watches each one fail, and
freezes them. Four writes the code until it passes all eight deciding checks. Five reviews the
diff, repairs what the review finds, verifies each repair, and closes the order. Once every order
closes, `finish` records the task's own implementation as done and hands it to the review stage.

Before step one, read what a test is in AIDA:
`${CLAUDE_PLUGIN_ROOT}/skills/implement/references/what-a-test-is.md`.

## Find the task

Resolve the active project's own folder first, then the task, `<taskId>` when given or whichever
task is already active in this conversation. Neither known: say so in one line and name the task
skill. Stop; there is nowhere to act.

Once found, the task's own folder is `<projectPath>/tasks/<task-id>`. Every call below takes that
folder.

`implement-actions.sh` takes a text value from a file. Write the text with the Write tool in the
session's scratchpad folder. With no scratchpad, write it in the task folder, and delete it after
the call. Then pass `@/<absolute path>` as the value. In a value such as `<id>=<reason>`, the path
follows the `=` or the `::`. Use this for a text that names a command, such as git. Claude Code
refuses a command whose quoted text names git when the session works in a worktree.

## Read what is already there

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh read "<task_folder>"
```
This prints summary lines, one `key: value` each:

- the contract's state, and whether design has started and how many work order files it left;
- the task's project, its code repository, the current branch, and the trunk branch when derivable;
- the task's own run mode for this stage, from `task.json`;
- the snapshot's path and hash, the ledger's path, and whether a preconditions record and a
  finished record exist;
- one `order(...)` line per work order: its last step, its stop reasons, its counters, its review
  state, and the `roles=` and `lookups=` its proof kind needs;
- the criteria counted by row state;
- a `next:` line naming the step the table below would choose.

No contract, or design has not started: say so in one line and name the missing stage. Stop.

`read` is the one call here that runs from anywhere. Every other call refuses at exit 79 when
the task builds in its worktree and this window is elsewhere. The refusal names the tree and the
route that works from here, either the `EnterWorktree` tool or the call started with
`cd <worktree> &&`. Take the route it names, the way `/aida:next` does, and run the call again.

## Which step, and where its instructions are

The `next:` line from `read` names the step. It is derived from the ledger the way this table
reads it. Match it to one step, open that step's own file, and follow it. Each file holds everything for its
step and nothing for another, so only the step being run is in this conversation. The table is the
derivation, kept here so a person can check the line against the state the other lines report.

| The summary says | The step | Step name |
|---|---|---|
| `snapshot: none`, or a snapshot with `ledger: none` | Start the build | `start` |
| A ledger, `preconditions: none`, and an order that could move | Check the preconditions | `preconditions` |
| Preconditions recorded, and an `order(...)` line reading `not started` whose dependencies are all `closed` | Write the tests for one work order | `tests` |
| An `order(...)` line at `tests-frozen`, or `code-written` with attempts remaining and `stopped: none` | Write the code for one work order | `build` |
| An `order(...)` line at `checks-passed` | Review the order | `review` |
| An `order(...)` line at `reviewed` or `fixed`, with `review: open=` above zero and a fix round left | Fix, then verify | `review` |
| An `order(...)` line at `reviewed` or `fixed`, with `review: open=0` | Close the order | `review` |
| An `order(...)` line at `closed` | Nothing left to do on it. Take the next ready order | |
| Every order `closed` or `dropped`, none stopped, `finished: none` | Finish the task | `finish` |
| `finished: recorded` | The review stage is next. After a failed review, `next:` names `reopen`, which sends its findings back to their orders | `finish` |
| An `order(...)` line whose stop says `the design removed` it, and an order `not started` that could move | Offer `drop` before those tests are written: the removed order's frozen record still guards its test files | `finish` |
| An `order(...)` line with `stopped:` other than `none`, and nothing else can move | Offer the three ways out. `next:` names the go-on choices every reason allows | `finish` |
| An `order(...)` line not started whose dependency is `dropped` | Nothing starts it. Offer `redo` through design, or `drop` | `finish` |

A refusal writes no stop, so no row above routes it. Its message names the route. Take that route.

A recipe the catalog republished after `preconditions` ran is not a step the table derives. Run
`recipe-refresh` before the next freeze, as `references/preconditions.md` says.

An order in flight comes before a new one, and a stopped order is named only when nothing else can
move. The one exception is the order the design removed: it comes before a new order, for the
reason its row gives. A resumed run starts at `start` regardless, because that is where drift since the snapshot is
checked, and it says which orders stopped. Its own `next:` line then applies.

## One order stopping does not stop the run

When an order stops, only the orders that depend on it wait. Everything else that is ready still
builds. A stopped order carries its reasons as a list: each names the step that wrote it, its
words, and the go-on choices it allows. Run `start` again. It reports which orders are ready,
which stopped and why, and which are in flight. Unattended, it also sets aside the files a stopped
role left uncommitted (`references/start.md`). Take the next ready order and apply the table. Stop
only when nothing is ready.

Then report each stop, with the reasons the ledger holds, and what is waiting on it. A person
leaves a stop one of three ways, and each one is a person's answer, recorded through
`person-answer.sh` (`references/finish.md`, "Leave a stop"):

- **Go on**, saying what continues. That is one more build attempt or one more fix round. It can
  also be the checks run again with no new build, or a close with the open findings listed. It may
  name a file the order now owns. The script takes only a choice every stop reason allows.
- **Redo the order.** The person changes its design or its tests first, through design. Redo
  reverts the order's own commits, moves its records to a dated folder with the person's words,
  and sets it back to planned. Its tests are written and frozen again, and they fail first.
- **Drop the order.** It ends without code. Its commits are reverted the same way, and nothing that
  depends on it can start.

Interactive puts the choice to the person, who decides from the recorded attempts which of three
things is true: the test is wrong, the order is wrong, or the code is hard and a person writes it.
A wrong test or a wrong order is a redo. Unattended, the run ends there with the report, and decides
none of the three. A model ruling that a test is wrong, with nobody watching, is the test describing
the code again.

Two decisions do not stop an unattended run: a finding with an empty fix scope, and a departure
from the design. Each is recorded as pending on the order's review record, and the order goes on
to its close. Later orders start, and `finish` runs. The review stage puts each one to the person
before its verdict, and it cannot pass while one is unanswered. A model still decides neither.

A run has a ceiling when the task sets `budget` in its own record, in dispatches or in minutes.
`dispatch-open` recomputes what was spent from the ledger before every dispatch and stops the
order at the ceiling. Absent budget means no ceiling, and the per-order caps still hold.

Open the step file through the script, not through the Read tool:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh step <step name>
```
This prints `references/<step name>.md`. A `Read` rule naming that folder does not reliably
expand `${CLAUDE_PLUGIN_ROOT}`, which is why this skill grants only the one Bash rule above. Run
`step` every time this table sends you to a file, even a file already read this turn. A step run
from memory of an earlier invocation is a step run against rules that may have changed.

## Five rules every step repeats

These hold for every step below, and each step file names them rather than restating them. This
file is always loaded; a step file is loaded only while its own step runs.

**The conversation holds summaries and paths. The records hold the bodies.** Every action prints
`key: value` lines and a path, and each record action ends with `next:`. Never read a record, a
brief, a diff, a tool output or a finding's evidence into this conversation, and never paste one
back. Name the path the script printed, and say the person can open it in an editor. Each brief
action writes its brief to a file and prints the path; the dispatch prompt names that path and
carries no brief content. **Only the dispatched role reads bodies**, and it opens them itself, from
the paths its brief names. The one exception is text a person must read to answer: a checklist row
at `tests-freeze`, or a question a step asks. A body pasted here costs the build the context its own
steps need.

**Every question a step puts to a person opens with one plain sentence.** It names the decision,
says why it is the person's call, and says what each answer causes. Text a person reads uses
plain words. A framework term such as row, freeze, done-when or order is replaced by a plain
word, or defined in the sentence that uses it. Keep each sentence under twenty words. The person
may have returned to the terminal days later, holding none of the order's context (live-run row
89). The shape: "The checker doubts that one new test proves what its criterion asks. A model
may not settle that alone. Confirm it and the test is kept as written; reject it and the test
author rewrites it." Then show what the
step names. Each step file writes its own sentence out; this paragraph is the rule, stated once.

**Name the role on every dispatch.** A dispatch that names none runs as the general agent, with
every tool and this session's own model, and the dispatch record just opened then matches nothing:
the hook compares the agent's own type against the role in the record, so an unnamed dispatch is an
unenforced one.

**The dispatch message is the role, the run mode and the paths.** Name the role on the Agent
call, and set the model where the step says. The message itself is one line per item: the run
mode, `interactive` or `autonomous`, then the worktree, then each path the step hands over.
Where a step names one word beside the paths, such as a lens, that word is a line too. Two lines
carry a label. The worktree line is written `worktree: <path>`, from the path `dispatch-open`
prints and each brief carries. The role works there and starts each shell command with
`cd <worktree> &&`. A role starts in this session's directory, and without the line it worked in
the main checkout (gap row 230). The row checker's interface file carries no worktree, so only
this line and the hooks keep it out of the main checkout. The identifier's process-recipe
point is written `point: <phase>` and never a bare word. A bare
`implement` reads as a task and not a phase (live-run row 138). Nothing else goes in. The
role's rules and its return shape live in its agent definition, which reaches it on every
dispatch.
The data it needs lives in the brief the paths name. So the message restates neither, and two
runs of one step hand the role the same words. Each step below names this shape and lists its
own paths.

**A recipe lookup has three answers, not one.** No recipe for this framework, a listing that could
not be reached, and a failed network are three different things, and only the first says anything
about the framework. Pass the one that happened, in its own word.

**A test green on its first run has four outcomes.** Wrong test: corrected once. Still green, and
the author names the existing code that satisfies it: frozen, and the reason recorded. Still
green with nothing to name: reported, and the step stops. Failed: frozen with its red run.
`references/tests.md` holds the flags.

**The script reads a recipe's command blocks, never you.** Pass a recipe path straight through to
the action that takes it. `## Test commands` and `## Check commands` are parsed by the script, one
entry per tool, each with its own argv, its `{paths}` placeholder, and its `signal` and `extensions`
keys where present. `## Configuration gate` is parsed the same way for an order whose proof is `gate`. An order whose proof is `record` runs no block at all: its done-when row is its check, and its range lives in the project folder. It refuses (exit 72) when two frameworks each command one tool.
Verdict words and a missing heading follow
`${CLAUDE_PLUGIN_ROOT}/skills/tool/references/reading-a-recipe.md`.

**Close the dispatch record as soon as the role returns**, whether it succeeded or not:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh dispatch-close "<task_folder>"
```
The record is the task's own, under its implementation folder. So a task has at most one open
dispatch, and a second task of the same project builds beside it. A close reaches this task's
record only. An open record refuses the next dispatch (exit 37), naming the role and the unit
that hold it. The refusal names the record's age when it opened over a day ago, because a role
that never returned leaves one.
`build-record` and `fix-record` refuse too while a record for their order is open.

**Open the dispatch record just before the Agent call**, never ahead of a question to the person.
The answer can change the brief, and the open record then blocks the record steps. A record whose
role was never dispatched closes with `dispatch-close "<task_folder>" --not-sent`. That close
spends no resume. It refuses when one of these shows that a role may have run. A fixer's or test
author's report exists. Another role's file is newer than the record. A commit is newer than the
record, in the code path or in a record order's files. A brief action that writes the role's brief again
removes a record that shows none of these, and counts nothing. A fresh `dispatch-open` refuses while a fixer's finished
report waits for `fix-record`. Run `fix-record` first, or `fix-brief` again for a changed round.

**A role the runtime stops at its turn limit is resumed once.** This holds for every role this
skill dispatches. An implementer whose order's diff budget starts with `large` is resumed twice.
The script reads that word from the frozen order. The signal is the runtime's own mark that the
role stopped at its turn limit. The script also sees it for the reviewer, the row-checker and the
implementer. A plain close refuses (exit 111) when the file the role writes is missing. That is
the findings or verdicts file the brief names, the row-checker's `row-check-<order id>.json`, or
the implementer's answers file, which also needs its stop line. A placeholder such as
`Stop: pending` is no stop line, so that builder is unfinished and takes this route. The fixer
and the test author end the report their brief pins with `Report: complete`. A fixer's report
also gives each finding an `Outcome:` line, and a `Ran:` line with its output when the finding
is fixed or already correct.
A plain close whose report lacks one of these lines takes the step below itself (exit 112).
The first time a fixer's report misses an outcome or run line, or its fix brief is missing, the
112 spends no resume, with or without `--no-report`, because the fixer finished. Resume it by
message to add the lines. A second such fault spends a resume. After a 112, do not close again: resume
the agent. A `--no-report` close after a 112 spends a resume. Add `--no-report` only on the
runtime's mark. A role can finish before the runtime marks it stopped. If its file passes, the
close says so and removes the record, and the role is not resumed. Otherwise the record stays
open, so both hooks keep applying. Then send one message to the same agent: finish the work and
write the report. Do not
dispatch a fresh role. The brief is unchanged and the work is unfinished, and a fresh role meets
the half-written files. This differs from a row a person rejects, where the brief changes and the
role is dispatched fresh. When the resumed role returns, close again, with `--no-report` if it
stopped again. The `--no-report` after the last resume removes the record and writes a turn-cap
warning into the task record. Report the warning. The role's commits stay on the order's list, and
the next dispatch reads what the role left. A builder's cap spends a build attempt, and any other
role's caps count toward the order's attempt limit, so the last one stops the order. A capped
commit that breaks the frozen tests or the owned files stops the order too (exit 63).

A record already closed takes the same route. Run `dispatch-open` with the same role and unit and
`--resume`, then resume the same agent by message. When that agent cannot be reached, as from
another session, dispatch the role fresh. A fresh `dispatch-open` refuses (exit 104) while the tree
holds uncommitted files, so no role starts beside another role's work. Commit a file to keep it,
or run `start` with `--leftovers set-aside`. A row-checker, and a test author sent back for a
rejected row, are exempt, because their work starts from those files.

## What this skill does

The permissions this step describes are applied by the runtime, not by the words above. Two hooks
do it, and both report through a message when they cannot find what they need rather than passing in
silence. Both hooks have refused inside a live dispatch. The read hook refused a row-checker two
paths on its denied list. The write hook refused an implementer a write outside its owned files.
The message they send when they cannot find the record has not run live, so do not report that
part as proven.

While a record is open, both hooks also guard the project's main checkout, the code path the
project registers. There the role is refused each denied read and every write, also through git
and through a copy in or out. A role in that checkout is matched to the record by its type. A
shell command that builds a path at run time still passes.

The read denial covers Read, Grep and the plain shell reads: `cat`, `head`, `tail`, `less`,
`more`, `sed`, `awk`, `grep`, `rg` and `nl`. A path a shell assembles at run time passes. That
is a limit, not a choice. The rule exists to stop the role opening the source because reading
the code is the obvious way to write a test about it. A role working around the rule on purpose
has already failed in ways no hook catches. Say that when the person asks what the dispatch
enforces, rather than describing the denial as complete.

`dispatch-open`'s `--allow-write` is a third thing withheld, beside the read denial and its shell
limit above. It is recorded for a reader, and no hook applies it. The frozen-test hook decides by
whether a path is frozen, never by this flag. Say the same about it that you say about the other
two: recorded, not enforced. The implementer and the fixer are the two exceptions. Their records
carry the owned files under `ownedFiles`, and the frozen-test hook refuses a write under the code
path outside them. The fixer's list adds the paths a person allowed with `fix-brief --allow`.

The five answers a builder or a fixer writes into its report are a fourth. The record steps refuse
an empty report file, and nothing checks the file holds five answers, that they preceded the write,
or that the diff stayed inside them. Recorded, not enforced.

The tool grants in this file's own frontmatter hold for one turn. The runtime clears them at your
next message to the person, so a multi-turn build asks again for the Bash rule after that message.
That is how a skill's grants work, not a fault in this one. Say so when a person asks why the same
command prompts again partway through a build.
