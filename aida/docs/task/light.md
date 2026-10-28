# Light mode

Light is for a demo or a first version that has to exist fast. It is an autonomous run over
every stage that skips named steps and logs each skip. It ends at review, where a person closes
the task.

## What you do

```
/aida:task set-run-mode <task-id> light
```

Then start the run with the command for the stage the task is at, such as `/aida:scope <task-id>`
for a new task. Each stage then starts the next one. Light takes no `--stage`. The output adds a `path-script:` line, which says what light does
about the one script that walks the demo path. Everything on [run modes](run-modes.md) about autonomous runs
holds for light too.

## What light skips

- **Tests.** Scope records that the task has no automated tests. So each code order takes the
  proof a person confirms at review. If research finds a test runner in the worktree, it changes
  that answer to yes, and the build writes and freezes tests as on any task.
- **Research** runs no web search. It searches this project and the catalog.
- **Design** runs no critique. The first work order, `wo1`, is the walking skeleton: a tiny
  version that links the input, the logic and the output along the demo path. Every other order
  comes after it.
- **Implement** gives each order one fix round. An open low finding waits for you at review. An
  open medium or high finding stops the order. One repair round can follow, once, for breakage the
  fix round made, and with you present for a few other findings. The builder may build a fake off
  the demo path, marked in the code with `AIDA-FAKE:`.
- **Review** runs no visual regression.
- Fewer helpers run before the first line of code. One distiller reads scope, research and
  design together when design closes.

## What light keeps

- The code review of each order, and the project's own checks, its security check included.
- One script that walks the demo path. That is the project's end to end setup for that one path.
  With end to end on and no such script registered, `wo1` writes it. Once one is registered, no
  order writes or extends it. An order may edit a file the script runs. The design check refuses
  an order that adds a file under a folder the script's command names. A project that declined end to end keeps no such script. A missing
  script is not a failure at review: the acceptance verifier's evidence is the task's acceptance.
  See [sources](../sources/).
- A budget, when you set one. See [set a budget](budget.md).

## The compromises log

Each skip is written to `COMPROMISES.md` in the task folder, by the code that decides it. A row
names the task, the stage, what was skipped, and what a normal run would do. Each marked fake gets
its own row. The log never enters the code repository. A later normal task can take the log as
its scope.

## How a light task ends

With nobody present, review records each criterion a person answers as unanswered. So completion
halts, and the task waits for you. Run review again and answer the rows, or close the task with
a reason.

## Leaving light

`/aida:task set-run-mode <task-id> interactive` takes the task out of light. Two things stay:

- A task whose scope closed in light reads stage scope until one distiller runs. The `distill:`
  line says so.
- The contract still says the task has no automated tests. The `light-contract:` line names the
  steps to change it: scope's `set-tests --automated yes`, then design's `update --proof tests` on
  each code order, then implement's `redo` on each started order.

## Why it works this way

- A skip that nobody records is a gap nobody finds. The log keeps every compromise in one place.
- The path script is written by the build it judges, so it cannot stand in for your answer at
  review.

Source: skills/task/SKILL.md, skills/task/scripts/task-actions.sh, skills/research/SKILL.md, skills/design/SKILL.md, skills/implement/references/review.md
