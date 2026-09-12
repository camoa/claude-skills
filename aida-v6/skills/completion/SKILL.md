---
name: completion
description: This skill should be used when a reviewed task is ready to close, for example "close this task", "finish the task", "mark the task done", "write the pull request body", or "complete the task". It reads the review verdict, offers one follow up task per finding the review left open, writes a pull request body from the records, records on what grounds the task closed, and calls the task skill's complete last.
disable-model-invocation: true
argument-hint: "[<task-id>]"
arguments: [taskId]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/skills/completion/scripts/completion-actions.sh *)
---

# Completion

Completion runs once per task, after review closed, or after a person decides to close without
one. It reads the records and offers a task per follow up finding. It writes a pull request body
as a file and its own record, then calls the task skill's `complete` last.

**Completion is not review.** It runs no check, dispatches no model, and re-derives no verdict. It
creates no code change and repairs no finding. It calls no remote: no GitHub, no push, no merge.
The person opens the pull request from the file. Review is a separate skill so a person can run
their own reviews between the two.

## Find the task

Resolve the active project's own folder first. Then resolve the task, `<taskId>` when given, or
whichever task is already active in this conversation. Neither known: say so in one line, name
the task skill, and stop. There is nowhere to act.

The task's own folder is `<projectPath>/tasks/<task-id>`. Every call below takes that folder.

## Read what is already there

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/completion/scripts/completion-actions.sh read "<task_folder>"
```
It reports the task's state and run mode. It says whether the contract, the build record and the
review record exist. It gives the review verdict in one of four words: `passed`, `failed`,
`unfinished` or `none`. It lists each follow up finding with the task that exists for it, or
`none`. It counts the children still open. Its `closes` line says whether the task closes on the
verdict or on a person's reason. It writes nothing.

`nextStep: done` means the task is already complete. Say so in one line, name the record path
under `<task_folder>/completion/`, and stop. `nextStep: close` sends you to the one step file.

## The step, and where its instructions are

Open the step file through the script, never through the Read tool:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/completion/scripts/completion-actions.sh step close
```
This prints `references/close.md`. A `Read` rule naming that folder does not reliably expand
`${CLAUDE_PLUGIN_ROOT}`, which is why this skill grants the one Bash rule above. Run `step` every
time, even when the file was read earlier this turn. A step run from memory is a step run against
rules that may have changed.

## Three rules the step repeats

**The conversation holds summaries and paths. The records hold the bodies.** Every action prints
`key: value` lines and a path. Never read the review record, the contract or the pull request body
into this conversation, and never paste one back. Name the path the script printed, and say the
person can open it in an editor. A body pasted here costs context this skill does not need.

**Every task write goes through the task skill.** `follow-ups` creates a task through `task
create`, and `close` moves the state through `task complete`. Completion writes no task field
itself. When the task script refuses, its own line is printed above the refusal; relay it as
printed.

**A reason is a sentence, not a bypass.** A review that did not pass closes only on a person's
word. The record keeps that sentence. Never invent one, and never suggest one. Ask the person
why the task closes without a passed review, and pass what they said.

## The run mode decides who answers

The run mode is `runMode` in `task.json`, absent meaning interactive. A person's answer is
accepted only when a person is present.

| Question | Interactive | Autonomous |
|---|---|---|
| A follow up finding with no task | the person accepts or declines each one | every one is created and listed |
| A review that did not pass | the person gives the reason | the close halts, naming the verdict |
| A high severity follow up with no task | the person creates it, or says why not | the close refuses, since the tasks were created first |
| The summary for `task complete` | the person gives one or two lines | one line naming the grounds |

`close` refuses `--reason` and `--leave` on an autonomous run at exit 70. A run with nobody
present closes a task on a passed review and on nothing else.

## The exit codes

One number never means two things, and none is new to this plugin.

| Code | What it says |
|---|---|
| 1 | refused, with the reason on the first line: the path holds no `task.json`, the task is already complete, a child is open, a high severity follow up has no task, or the review did not pass and no reason was given |
| 3 | the script could not do its job: a missing argument, a record it could not read, a record that does not match its schema, a file it could not write, or a task name the task script refused |
| 70 | `--reason` or `--leave` was passed on a run with nobody present |

Read a refusal and act on it. Do not repeat the same call unchanged.
