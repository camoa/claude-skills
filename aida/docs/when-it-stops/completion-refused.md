# Completion refuses to close the task

`/aida:completion` closes a reviewed task. It refuses with exit 1 and gives the reason on the
first line. A review that did not pass closes only on your word.

## What you see, and what to do

| The refusal | What to do |
|---|---|
| The task is already complete | Nothing. Completion names its record and stops |
| A child task is still open | Finish each child first. A split parent closes last |
| A high-severity follow-up finding has no task | Create the follow-up task, or say why not with `--leave` |
| The review did not pass, and no reason was given | Answer what review left open, or give your reason (below) |
| A criterion a model looked at through a browser has no answer from you | Accept or reject each one; a no needs a reason |
| A file `task environment up` changed is in the way | See [put back the site files](../stages/completion/restore.md) |

## The review verdict is not `passed`

- **`none`.** No review exists, or the review covers an earlier build. Run `/aida:review` again.
- **A criterion you verify was not answered.** The verdict reads `failed` or `unfinished`, and
  completion prints the route back to the review's close with your answers. Answering there can
  pass the review, so no reason is needed.
- **`unfinished` because a decision waits.** Answer it at the review's close. See
  [the task review refuses or fails](review-refused.md).
- **`failed` for any other cause.** Close only when you mean to, with a reason. Completion
  records your sentence. It never invents or suggests one.

A reason closes the task with the open questions still unanswered.

## With nobody present

A run with nobody present closes a task on a passed review and on nothing else. Otherwise it
halts, and exit 70 means a person's answer was passed. How your answer reaches it is on
[completion on an unattended run](../stages/completion/autonomous.md).

## Why it works this way

- **Completion re-derives nothing.** It reads the review's verdict, so a task cannot close past a
  review that failed without a person saying why.
- **Site files never reach trunk.** They name the worktree's site, and on trunk they would point
  commands at the wrong site.

Source: skills/completion/SKILL.md, skills/completion/references/close.md, skills/completion/scripts/completion-actions.sh
