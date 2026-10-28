# The code repository is not ready

The build and the review make claims about what the code repository holds at a commit. So they
refuse when the repository is in a state that would make the claim false. Fix the state, then run
the same step again.

## The build would land on trunk, or on no branch

- **Exit 6.** The task's code is on the project's trunk branch. Implementation never builds on
  trunk. Work in the task's worktree, on its `feature/<name>` branch.
- **Exit 16.** The code is on a detached HEAD. A commit there belongs to no branch. Check out the
  task branch.
- **Exit 5, 14 or 15.** The recorded code path is not a git repository, `project.json` is not
  valid JSON, or the code path is gone. See [change the code path](../project/change-code-path-or-stack.md).

When AIDA cannot work out the trunk, it says so and goes on. See
[start the build](../stages/implement/start.md).

## Uncommitted files

- **Exit 61.** The tree holds uncommitted work. A record step, `close`, `finish`, a redo, a drop,
  and review's checks all refuse it. Commit the work, then run the step again. On an unattended
  run the record step also stops the order; AIDA goes on after you commit.
- **Exit 104 at `start`.** A role stopped mid-run left files, or an install changed one, such as
  `package-lock.json`. Commit a file to keep it, keep the files for this run only, or set them
  aside. The choices, and where set-aside files go, are on
  [start the build](../stages/implement/start.md).

## The code moved after a record

- **In the task review, exit 51.** The code changed after `checks` ran. Run `checks` again.
- **In a work order, exit 63.** Commits landed after the order's last record, and they change a
  frozen test or a file the order does not own. No record judged them. Move the branch back to the
  commit the message names, or redo the order. See [a work order stopped](stopped.md). Commits
  inside the order's own files do not stop the build: AIDA writes a warning into the task record,
  keeps them on the order's commit list, and goes on. Review lists the warning.

## The branch was rewritten

- **Exit 82.** A rebase or an amend rewrote the branch under the build. Run
  `start --rebased-onto <commit>`, then retake the baseline by hand. Until then the record steps
  and `finish` refuse with exit 21.
- **Exit 3.** The baseline was written by an earlier version of AIDA. Retake it the same way.

The steps, and when the flag refuses, are on [come back to a build](../stages/implement/resume.md).

## Why it works this way

- **A commit range is a claim.** A dirty tree or a moved HEAD makes it a claim about something
  else, so AIDA refuses rather than record it.
- **The baseline is never retaken silently.** A new baseline reads this task's own code as the
  starting point, and would hide its findings. So only a person moves it.

Source: skills/implement/references/start.md, skills/implement/references/review.md, skills/implement/scripts/implement-actions.sh, skills/review/SKILL.md
