# Set a budget on the build

A budget is a ceiling on one implementation run, in dispatches, in minutes, or both. You set it;
AIDA never proposes one.

## What you do

```
/aida:task set-budget <task-id> --dispatches <n>
/aida:task set-budget <task-id> --minutes <n>
/aida:task set-budget <task-id> --dispatches <n> --minutes <n>
```

- `--dispatches` counts the roles the build dispatches over the whole run.
- `--minutes` counts wall-clock time from the start of the build.
- Each takes a whole number of 1 or more. AIDA refuses anything else.
- A number you do not name keeps the value it had. So raising one ceiling never drops the other.
- No action removes a budget. No budget means no ceiling.

A budget works in every run mode. The per-order limits on attempts still hold either way.

## What happens when the budget runs out

The build counts its spend again from its own records before every dispatch. When either number
is reached, the work order it was about to dispatch halts with `budget spent`.

## How to continue after `budget spent`

Do these two steps in this order:

1. Raise the number: `/aida:task set-budget <task-id> --dispatches <bigger n>`, or `--minutes`.
2. Grant the order another attempt with `grant-attempt`, in the implementation stage. See
   [implement](../stages/implement/README.md).

The reverse sequence does not work. A grant before the raise brings the halt straight back, because
the spend is counted again at the next dispatch.

`grant-attempt` is a person's call, in every run mode. See [the person's answer](person-answer.md).

## Why it works this way

- The spend is counted from the build's own records each time, so nothing a builder writes can
  reset it.
- Only a person sets the ceiling, so only a person raises it.

Source: skills/task/SKILL.md, skills/task/scripts/task-actions.sh
