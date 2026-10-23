# How the scope conversation runs

Scope reads what you already gave it, drafts the whole contract at once, and shows it to you. You
then correct what is wrong, one change at a time, until you approve.

## What scope reads first

- The words you typed after `/aida:scope <task-id>`. This is the freshest source of what you
  want, and scope reads it before it asks anything.
- On a first run, the task's `task.md`. A task made by a split carries its handed-down criteria
  there, as prose. Scope treats that prose as a draft, not as an agreed contract.
- On a first run, `alignment.v5.md` when the task comes from version 5. Scope drafts from it,
  keeps the old criteria order, and says what it changed.
- On a later run, the existing contract.

When you already have a specification, paste it after the command, or write it into `task.md`
before you start. A file in the task's `inputs/` folder is read by research, not by scope.

## The draft

On a first run, scope drafts every part: the goal, the expected result, each criterion with its
verify clause, and the non-goals. It shows the whole rendered contract once and asks one thing:
what is wrong or missing. Every line is a draft until you approve it. When most of a contract is
already there, scope shows it and asks what is wrong, without a new draft.

When nothing is on the table at all, scope asks one open question first: what should be true when
this is done?

On a first run, scope can also offer to bring up the task's own site. This is the task skill's
site offer. See [the task pages](../../task/).

## Your corrections

Each correction you give becomes one change, in your words. Rephrase the goal, and the goal
changes. Reword a criterion, add one or drop one, and only that line changes. A criterion you
wrote or corrected is recorded as yours at once. Scope answers with the changed line, and the turn
ends. It does not show the whole page again unless you ask.

## What scope asks one at a time

A few things cannot be drafted. Scope asks each once, with a recommended answer for you to confirm
or correct:

- A gap the draft could not fill, such as no goal, or a criterion with no observable outcome.
- A non-goal probe. The draft lists the things next to the goal that nobody mentioned, each
  recommended out, in one block. You correct any of them in your one answer. Scope asks a probe on
  its own only when it recommends in or is not sure. Out becomes a non-goal. In becomes a
  criterion.
- Whether the task has automated tests. See [Tests and the test setup offer](tests.md).
- The test setup offer, only when the goal names something a person sees.

## A stated approach

A task often says how to do the work, not only what it must achieve. Scope records a stated
approach as `suggested`, or `required` when you insist. It goes into `task.json`, not into the
contract, and later stages challenge it. When you state no approach, scope invents none.

## Why it works this way

- A whole draft shown once puts less work on you than a chain of single questions.
- Scope answers a correction and stops. A question the model decides when to ask is one it can
  repeat, so approval is an action you take instead.

Source: skills/scope/SKILL.md
