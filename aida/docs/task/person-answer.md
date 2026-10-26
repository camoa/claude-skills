# Answer for a person in an unattended run

An unattended run refuses a call only a person can make. You answer it in one of two ways: set
the task interactive, or write your answer as a record and keep the run mode.

## The calls that wait for you

- In design: `close --approve-runs`, your approval of the verify lines research wrote.
- In implementation: `grant-attempt`, `clear-halt`, `restart`, `retake-tests --because`,
  `finish --accept-warnings`, the keeps
  of a design departure, `verify-record --ruling` and `fix-brief --allow`.
- In review: `close --row`.
- In completion: `close` with `--reason`, `--leave`, `--captures-offered` or
  `--observed-accepted`.
- In the task skill: `environment up`, `environment not-applicable`, and a second
  `environment down` on an adopted site when no status line can tell whether it is gone.
- `/aida:task prune` with a task id or `--all`. Prune takes no record: set the task interactive,
  or run it yourself.

Each refusal names the call and what it waits for. See [when it stops](../when-it-stops/).

## Route one: set the task interactive

```
/aida:task set-run-mode <task-id> interactive
```

Then make the call yourself, through the stage. Set the mode back to autonomous afterwards if you
want the rest of the run unattended.

## Route two: your answer as a record

Tell the main session your answer, in your own words. It writes `person-answer.json` with the
task, the step, the work order where there is one, and your exact words. Then it runs the refused
call again, and the call passes with the run mode unchanged.

- The record sits in the task's `implementation/`, `review/` or `completion/` folder. For
  design's close and for `environment` it sits in the task folder itself.
- The refusals of completion and the task skill print the record to write.
- The call removes the record when it is done. No task commit takes it.

## When one session coordinates agents

A dispatched agent never answers for you. A hook refuses every dispatched agent a write of
`person-answer.json` with the file tools. It also refuses a shell command part that names the file
beside a write: a redirect, a copy, move or delete, `sed -i`, or an interpreter such as python. A
grep or a read of the file passes. The hook also refuses an agent, in every run mode, the steps
that record your approval, ruling or answer and cannot be undone. Examples are `set-run-mode`,
scope `approve`, and `prune` of a tree. An agent that meets a person's call reports it once to the
coordinating session and stops. That session puts the question to you, then makes the call or
writes the record itself.

## Coming back to an autonomous run

1. Read the session start lines. In the session that works the task, they name the task, its
   stage and `Run mode: autonomous`. See [sessions](sessions.md).
2. Run `/aida:next <task-id>`. It names the stage command. Each stage prints a summary of its
   records first. Implementation's summary names each halted order and why it halted.
3. Look for the decisions made without you. Each stage marks them in its own record;
   [run modes](run-modes.md#where-each-stage-stops-or-decides) lists where, stage by stage.

A halt is not a failure. It says the next step is yours.

## Why it works this way

- The record carries your exact words from the session you type in, so no agent can stand in
  for you.
- Each stage marks what it decided for you, so you can check it without the conversation you
  were not in.

Source: skills/task/SKILL.md, skills/implement/references/finish.md, skills/scope/SKILL.md, hooks/session-start.sh
