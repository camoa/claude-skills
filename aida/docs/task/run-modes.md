# Run modes

A task runs interactive, autonomous, or light. Interactive is the default: AIDA asks you and
waits. Autonomous means nobody is present: AIDA takes the recommended answer where one exists,
records that it did, and stops where only you can decide.

## The modes

- **Interactive.** Every question goes to you, with a recommended answer. At the end of each
  stage AIDA names the next command and stops.
- **Autonomous.** Each stage takes its unattended branch and, at its end, starts the next stage
  itself. One command can carry the task from scope to completion. The chain ends early when a
  work order stops in the build.
- **Autonomous for some stages.** You name the stages. The rest stay interactive. A common use:
  you write the contract and read the review, and the build runs without you.
- **Light.** An autonomous run over every stage that skips named steps. See
  [light mode](light.md).

The mode belongs to the task, never to the project. Two tasks in one project can have different
modes.

## Set the mode

```
/aida:task set-run-mode <task-id> autonomous
/aida:task set-run-mode <task-id> autonomous --stage implement
/aida:task set-run-mode <task-id> light
/aida:task set-run-mode <task-id> interactive
```

`--stage` goes with `autonomous` only, once per stage: `scope`, `research`, `design`,
`implement`, `review`, `completion`. Light and interactive refuse it. A mode for some stages
shows the stages in brackets, such as `autonomous (implement)`; see
[how a stage reads its mode](../stages/scope/unattended.md). `interactive` removes the
mode, because no mode already means interactive. Nothing in AIDA sets or proposes a mode; only you
do. Each change needs your answer first, through a permission prompt; see [the person's
answer](person-answer.md). Every step reads the mode from the task, so a change takes effect at
once.

Then start the run with the command for the stage the task is at, such as `/aida:scope <task-id>`
for a new task. `/aida:next <task-id>` names it. Each autonomous stage then starts the next one.

When the mode covers review, the output can add two lines. `sign-off:` names the criteria only a
person answers, so an unattended review writes no verdict. `review-tools:` names review tools
the build found absent.

## The one rule

An autonomous run never takes silence as a yes. Each question lands in one of three places, and
the record says which:

- **Decided for you, and recorded.** The run takes the recommended answer and marks it as taken
  without you.
- **Not done, and recorded.** An offer is not made. Nothing is switched on or installed on a
  guess.
- **Stopped.** A step you cannot easily undo, or an answer only you can give, stops that piece of
  work. One stopped work order holds back only the orders that depend on it.

## Where each stage stops or decides

Each stage page says what its unattended branch does. In short, with where each stage records it:

- [scope](../stages/scope/README.md) takes its own draft and marks each answer it took for you in
  the contract. Every criterion stays marked as drafted, not approved by you.
  `/aida:scope approve <task-id>` promotes them to yours and marks each such answer approved.
- [research](../stages/research/README.md) records a split recommendation and stays flat. The
  split is still yours to decide.
- [design](../stages/design/README.md) checks each reuse decision with a confirmer, and records
  its verdict in the work order. Its close record says who was present. A verify line that is not
  a recipe's own command waits for your approval at close.
- [implementation](../stages/implement/README.md) stops a work order at each point only you can
  decide, and records each stop with its reasons. A finding with an empty fix scope, and a
  departure from the design, do not stop it: review puts each to you before its verdict. A test
  newly broken at finish stops the task before review. The finished record counts the test rows a
  model judged, which nobody read.
- [review](../stages/review/README.md) leaves each person-answered criterion unanswered and
  writes no verdict. The task has no sign-off until you answer them.
- [completion](../stages/completion/README.md) closes only on a review that passed with no warning.

To answer a stop, see [the person's answer](person-answer.md).

## Why it works this way

- A model that decides for an absent person, with nobody watching, removes the checkpoint that
  person was. So AIDA stops there instead.
- Each stage refuses to start without the record of the stage before it, so an autonomous chain
  cannot run out of order.

Source: skills/task/SKILL.md, skills/task/scripts/task-actions.sh, skills/implement/SKILL.md, skills/research/SKILL.md, skills/design/SKILL.md
