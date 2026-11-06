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

A finding you ruled `fix` at the review's close is no follow up, whatever its severity. It goes
back to its order through the build's `reopen`. If you close the task on a reason before that fix
lands, the task record keeps a warning that names the finding.

Review may already have offered a task for some of them. Completion offers again for each one
that still has none.

## What completion asks

One question per finding. Each question names the finding, its severity, and the task id it will
get: this task's id followed by the finding's id. Nobody has to name the task.

A yes creates the task the same way `/aida:task create` does. Its goal is the finding's evidence
and one sentence that names where it came from. The task gets no worktree yet. Its tree is made
from the trunk when it starts, so a follow-up nobody starts costs no disk. A follow-up you find
moot closes with `/aida:task complete` and the reason.

## Several findings in one task

When more than one finding has no task, completion first asks whether any go together. For a yes,
it makes one task whose goal names each finding and the review record. Each finding then records
that task, and the pull request body lists it beside the finding. An open task whose goal already
names the findings can take them instead.

The close refuses a shared task, with nothing written, in these cases:

- the task does not exist, is complete, or is the task that is closing;
- its goal does not name the finding;
- the finding is a deferred decision, or you ruled it `contract-wrong`.

Each of those two kinds keeps its own task, because that task carries text the review findings do
not hold.

## A high severity finding

A high severity finding left with no task is a warning in the task record. Create the task, send
it to a shared task, or say in one sentence why not. The record and the pull request body keep that sentence. A finding below high
severity may be left with no reason.

## Why it works this way

- Folding leftover work into this task silently is what scope exists to prevent. A new task
  changes the contract least.
- A queued security fault ships if nobody tracks it, so a high severity finding needs a task or a
  reason.
- A close runs once, so a wrong shared task would stay in the record. The close checks it first.

Source: skills/completion/references/close.md, skills/completion/scripts/completion-actions.sh, skills/review/references/close.md
