---
name: review
description: This skill should be used when a task's implementation has finished and the whole task needs one pass against its contract and its code, for example "review this task", "run the review", "gate check", "check this task before completion", or "Phase 4". It runs sixteen checks over the frozen contract, the diff at the final commit, the coding-standards and analysis and security and suite results, the mutation survivors, the research records and the surfaces a person can see. It dispatches one architecture reviewer over seven lenses, asks the person the rows only a person can answer, and records one verdict a person acts on.
disable-model-invocation: true
argument-hint: "[<task-id>]"
arguments: [taskId]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/review/scripts/review-actions.sh *), Agent
---

# Review

Review runs once per task, after implementation's `finish` wrote `implementation/finished.json`. It
answers sixteen checks over three subjects: the contract, the code as written, and the surfaces a
person can see. One step runs every check a script can decide. One step dispatches the architecture
reviewer and records what it found. One step runs the surfaces and takes the person's walk. The last
step asks the person the checklist rows and writes the verdict.

**Review starts no fixer and runs no second pass.** A failed review goes to the person, with the
record. A reviewer holding no reference outside the code checks the code against itself, so a second
round finds new things forever. The reference here is the frozen contract and the frozen tests.

**Review is not completion.** It never marks the task complete, writes no pull request body, and
repairs no finding. The task stays in progress, and the completion stage is what moves it. A person
may run their own reviews in between.

## Find the task

Resolve the active project's own folder first. Then resolve the task, `<taskId>` when given, or
whichever task is already active in this conversation. Neither known: say so in one line, name the
task skill, and stop. There is nowhere to act.

The task's own folder is `<projectPath>/tasks/<task-id>`. Every call below takes that folder.

## Read what is already there

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/review/scripts/review-actions.sh read "<task_folder>"
```
This reports whether `implementation/finished.json` exists, and the commit range and the final commit
it records. It reports how many criteria a machine verifies and how many a person does, the task's
run mode from the ledger, and the project's frameworks. It reports whether end to end and visual
regression are on, and whether a registry is recorded. It says how far an existing review record got.
Last, it prints the checklist rows whole, because a person has to read those words to answer them.

No `finished.json`: say so in one line, name the implementation skill's finish step, and stop. Exit
66 says the same thing when a later action is run first.

## Which step, and where its instructions are

The report from `read` says where this task is. Match it to one step, open that step's own file
through the script, and follow it. Each file holds its own step and nothing for another, so only the
step being run is in this conversation.

| The report says | The step | Step name |
|---|---|---|
| No review record, or a record with no check rows | Run the scripted checks | `checks` |
| Checks 3 to 8 recorded, and no findings recorded | Dispatch the reviewer, then record the findings | `reviewer` |
| The findings recorded, and no surface rows | Run the surfaces, and walk them | `surfaces` |
| The surface rows recorded, and no verdict | Ask the person's rows, and close | `close` |
| A verdict recorded | Nothing is left. Read the verdict and the rows that caused it to the person | |

A recorded verdict is the end of the pass, and `read` says so in that word. Start a second review
only when a person asks for one, and start it at `checks`, because the range and the tools answer
against the code as it stands now. The old record is archived before anything is written, and exit 63
refuses the write when that move fails.

Open a step file through the script, never through the Read tool:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/review/scripts/review-actions.sh step <step name>
```
This prints `references/<step name>.md`. A `Read` rule naming that folder does not reliably expand
`${CLAUDE_PLUGIN_ROOT}`, which is why this skill grants the one Bash rule above. Run `step` every
time this table sends you to a file, even one already read this turn. A step run from memory of an
earlier invocation is a step run against rules that may have changed.

## Four rules every step repeats

These hold for every step, and each step file names them rather than restating them. This file stays
loaded; a step file is loaded only while its own step runs.

**The conversation holds summaries and paths. The records hold the bodies.** Every action prints
`key: value` lines and a path. Never read a record, a diff, a tool output or a research finding into
this conversation, and never paste one back. Name the path the script printed, and say the person can
open it in an editor. **Only the dispatched reviewer reads bodies**, and it opens them itself, from
the paths its brief names. A body pasted here costs the review the context its own steps need.

**Name the role on every dispatch.** A dispatch that names none runs as the general agent, with
every tool and this session's own model. Review opens no dispatch record, so the role's own
frontmatter is the only thing bounding its tools, and an unnamed dispatch loses that bound too.

**A recipe lookup answers four ways, and review passes the one that happened.** One answer is a path
on disk. The other three are no recipe for this framework, a listing that could not be reached, and
a failed fetch. Only the first of those three says anything about the framework, so pass the one that
happened in its own word. No recipe records that framework's checks undeclared. An unreachable
listing or a failed fetch records them unknown, because nobody looked.

**The script reads a recipe's blocks, never you.** Pass a recipe path straight through to the action
that takes it. The script parses each row's own argv, its `signal` and `extensions` keys, and which
rows a framework declares absent. Nothing here retypes a command, so nothing here can drop a
`signal` key and turn a check into one that always passes.

## The run mode decides who answers

The run mode comes from the ledger, which copied it from the task when the build started. A person's
answer is accepted only when a person is present. Every question has an autonomous branch, and the
branch is recorded rather than assumed.

| Question | Interactive | Autonomous |
|---|---|---|
| A person verified criterion | the person answers met or unmet | `unanswered`, and no sign off |
| The walk of the surfaces | the person walks every one | recorded as not done, and checks 13 to 15 read unknown |
| A finding citing neither a criterion nor a non-goal | a follow up task is offered | recorded, and no task is created |
| A new baseline for a surface | plan, show, confirm, then write | refused, and recorded as refused |
| Setting up a surface | offered once | not offered, and recorded as not offered |

`surfaces` refuses `--accept-baseline` on an autonomous run, and `close` refuses a `--row` there.
A run with nobody present cannot sign off a task carrying one person verified criterion. That is
intended: a check that could not run has established nothing.

## The line the person is shown

Claim only what the run measured. Name every check reading undeclared and every check reading
unknown, in its own word, and give the count of criteria reading unanswered. Never report a check
reading undeclared as one that passed. Version 5 printed that every layer ran and found nothing
while one tool had not run.

Name the catalog notes by count as well. A note is a guide the code contradicts, a recipe whose
command no longer runs, or a pattern the framework wants and no guide names. Review writes nothing to
the catalog. A person decides whether a note becomes a proposal.

## What this skill records, and what it does not enforce

The architecture reviewer runs under no dispatch record, so no hook bounds it. `dispatch-open`
requires a work order id, and a task level review has no order. Widening that pattern would weaken
the field protecting every per order permission, and this role needs no permission. Its tool list and
its own instructions are therefore the whole of the bound. Say that plainly when a person asks what
the dispatch enforces, rather than describing the role as fenced.

The script refuses the reviewer's findings at exit 51 when the code path moved, or its tree went
dirty, since `checks` ran. A file the role left behind is caught there. It is a refusal, not a
finding.

The tool grants in this file's own frontmatter hold for one turn. The runtime clears them at your
next message to the person, so a review spanning several turns asks again for the Bash rule. That is
how a skill's grants work, not a fault in this one.

## The exit codes

One number never means two things, and these keep the meanings implementation gave them.

| Code | What it says |
|---|---|
| 1 | the given path holds no `task.json`, so it is not a task folder |
| 3 | the script could not do its job: a missing argument, a tool not on PATH, a folder or a record it could not resolve or read, or a head that is not where the range ends |
| 5 | the recorded code path exists and is not a git repository |
| 14 | the project's own `project.json` exists and is not valid JSON |
| 15 | the recorded code path does not exist on disk |
| 51 | the code path moved, or went dirty, since `checks` ran |
| 52 | the findings file could not be read as a findings file |
| 61 | the code repository's tree is dirty |
| 62 | a step ran out of order, and what it depends on recorded nothing |
| 63 | the previous record could not be archived, so the write was refused |
| 66 | implementation has not finished, so there is no `finished.json` |
| 70 | a person's answer was passed on a run with nobody present |
| 72 | two frameworks each command one tool |
| 73 | the check recipe resolved now is not the one the baseline was taken with, so take the baseline again first |
| 77 | the project records no framework |

Eight of these are review's own. The other seven arrive with the library both stages source, and each
keeps the meaning implementation gave it. Code 70 is the one an autonomous run meets in ordinary use,
the first time a `--walked` or a `--row` is passed.

Read a refusal and act on it. Do not repeat the same call unchanged.
