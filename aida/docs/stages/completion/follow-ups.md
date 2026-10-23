# Follow up tasks

Completion offers one new task for each piece of leftover work that review found and nobody has a
task for yet. You say yes or no per finding.

## What becomes a follow up

Review leaves these as follow ups:

- a finding that cites neither a criterion nor a non-goal;
- a low severity finding that cites a criterion;
- a finding you ruled `deferred` at the review's close;
- a decision from the build you ruled `deferred`;
- a static analysis finding in the frozen tests, for the test author.

Review may already have offered a task for some of them. Completion offers again for each one
that still has none.

## What completion asks

One question per finding. Each question names the finding, its severity, and the task id it will
get: this task's id followed by the finding's id. Nobody has to name the task.

A yes creates the task the same way `/aida:task create` does. Its goal is the finding's evidence
and one sentence that names where it came from. For each new task, completion prints the commit
its worktree was cut from.

## A high severity finding

A high severity finding left with no task refuses the close. Create the task, or say in one
sentence why not. The record and the pull request body keep that sentence. A finding below high
severity may be left with no reason.

## Why it works this way

- Folding leftover work into this task silently is what scope exists to prevent. A new task
  changes the contract least.
- A queued security fault ships if nobody tracks it, so a high severity finding needs a task or a
  reason.

Source: skills/completion/references/close.md, skills/completion/scripts/completion-actions.sh, skills/review/references/close.md
