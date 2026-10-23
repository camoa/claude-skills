# The pull request body

The close writes `completion/pr-body.md` in the task folder and prints its path. Open the file and
open the pull request from it by hand, changing nothing in it first.

Every section reads one field of one record. Completion computes nothing. A missing record is
written in words, never left blank, so the body claims only what a record holds.

| Section | What it carries |
|---|---|
| Goal | the goal from the scope contract |
| Success criteria | every criterion with the verdict review gave it |
| Non-goals | the non-goals from the contract |
| Commit range | the range the build finished, the branch, and the worktree to push from |
| Review audit | one line per check, one per surface, and a line of counts |
| Review | the verdict, and every finding grouped by what review decided |
| Grounds for closing | who closed the task, on which verdict, and the reason when one was given |
| Follow-up tasks | each finding with its task, or the reason it was left with none |
| Catalog notes | what review saw that a guide or a recipe should hear about |

## What the reviewer of the pull request should read

- **The review audit** says how each check got its answer: it ran, a record decided it, the
  project turned it off, or it could not look. The reader sees what did not run before the
  verdict.
- **A criterion that reads `unanswered`** is one nobody verified. Either it waited for a person
  and nobody was present, or its test suite could not run. The pull request reviewer still has to
  verify it by hand.

## Extra lines in the commit range

The commit range section adds a line when each of these applies:

- both ends of the range are one commit: the code repository holds nothing from this task, and
  every deliverable is in the project folder;
- the branch has no upstream: push before you open the pull request;
- the task has a worktree: the branch, and the worktree to push from;
- a restore commit put back the site's files: the commit and the files;
- the task's site was adopted: it stays up after the merge, and the line says how to tear it
  down before pruning.

## Why it works this way

- A body that claims only what a record holds cannot claim a check ran when it did not.
- Completion never prints the body into the conversation. It costs context and gains nothing.

Source: skills/completion/references/close.md, skills/completion/scripts/completion-actions.sh
