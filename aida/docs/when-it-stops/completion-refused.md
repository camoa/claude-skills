# Completion refuses to close the task

`/aida:completion` closes a reviewed task. It refuses with exit 1 and gives the reason on the
first line. A review that did not pass, or passed with warnings, closes only on your word.

## What you see, and what to do

| The refusal | What to do |
|---|---|
| The task is already complete | Nothing. Completion names its record and stops |
| The review did not pass, or warns, and no reason was given | Answer what review left open, or give your reason (below) |

These close, and each leaves a `warning:` line in the task record. A child task is still open. A
high-severity follow-up finding has no task. A `--leave` decides nothing. A file
`task environment up` changed cannot go back. For the last, see
[put back the site files](../stages/completion/restore.md).

## The review verdict is not `passed`

- **`none`.** No review exists, or the review covers an earlier build. Run `/aida:review` again.
- **A criterion you verify was not answered.** The verdict reads `failed` or `unfinished`, and
  completion prints the route back to the review's close with your answers. Answering there can
  pass the review, so no reason is needed.
- **`unfinished` because a decision waits.** Answer it at the review's close. See
  [the task review refuses or fails](review-refused.md).
- **`failed` for any other cause, or `passed` with warnings.** Close only when you mean to, with
  a reason. Completion records your sentence. It never invents or suggests one.

A reason closes the task with the open questions still unanswered.

## With nobody present

A run with nobody present closes a task on a passed review with no warning and on nothing else.
Otherwise it halts, the one place an unattended task stops on the review, and exit 70 means a person's answer was passed. How your answer reaches it is on
[completion on an unattended run](../stages/completion/autonomous.md).

## Why it works this way

- **Completion re-derives nothing.** It reads the review's verdict, so a task cannot close past a
  review that failed without a person saying why.
- **Site files never reach trunk.** They name the worktree's site, and on trunk they would point
  commands at the wrong site.

Source: skills/completion/SKILL.md, skills/completion/references/close.md, skills/completion/scripts/completion-actions.sh
