# Scope on an autonomous or light run

When the task's run mode is `autonomous` or `light`, nobody answers scope's questions. Scope takes
the draft as it is, takes the recommended answer on each question, and records each answer as
decided on your behalf. See [the task pages](../../task/) for how to set a run mode.

A mode that names stages in brackets, such as `autonomous (implement)`, covers scope only when the
list names `scope`. Otherwise scope runs with you, as usual.

## What changes

- **Each answer is recorded.** Every question scope would have asked is written into the contract
  as a decision taken without a person. The rendered contract lists them under "Decided without a
  person". A non-goal the run wrote is named there by its id, because a non-goal has no author.
- **Nothing becomes yours.** Every drafted criterion stays `designer`, because nobody approved it.
  The approval itself is recorded as given on your behalf.
- **No test setup offer.** Scope says that it skipped the offer.
- **No site offer.** Scope says that the offer waits for a person.
- **The next stage starts.** After the close, scope starts research itself, once, when the run
  mode covers research. It stops if research refuses.

## What a light run also changes

- Scope does not ask whether the task has automated tests. See
  [Tests and the test setup offer](tests.md).
- Scope sends no distiller at its close. The close commits the contract and prints
  `distill: deferred to the design close`. The design close then checks all three stages at once.

## When you come back

Read the contract with `/aida:scope <task-id>`. Then do one of these:

- **Approve it.** Each decision is marked as approved by you, with the date. No later stage asks
  you about it again. See [Approve the contract](approve.md).
- **Change an answer first.** For example, set automated tests to no after the run took yes. Scope
  marks the decision it replaced as superseded and tells you which one. Approval never approves a
  superseded decision.
- **Retire a decision.** A decision can stop holding after you approved it. Tell scope which one
  no longer holds and why. Name it by its words, because the rendered contract groups the
  decisions and shows no numbers. Scope refuses a decision already superseded or retired. Only a
  person can retire a decision. Retiring commits nothing, so approve again afterwards.

## Why it works this way

- Silence is never your answer. So an approved contract and an unattended one look different on
  disk, and you can see which lines nobody approved.
- Each stage refuses to start without the record of the stage before it. So one stage can safely
  start the next.

Source: skills/scope/SKILL.md, skills/scope/scripts/scope-actions.sh, skills/task/scripts/task-actions.sh
