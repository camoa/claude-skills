# Run a review

Type `/aida:review <task-id>` from the task's worktree after implementation has finished. Review
then runs four steps and asks you questions at the last one.

## What you type

- `/aida:review <task-id>`. Leave the id off and review takes the task active in this
  conversation. With neither known, it names the task skill and stops.
- Run it inside the task's worktree. Only the first read works from anywhere. Every other step
  refuses outside the worktree, and names the worktree and the way in.

## The four steps

Review reads the task folder first. It tells you how far an earlier review got, then runs the
next step.

| Step | What happens |
|---|---|
| Checks | It writes the task's diff once and runs every tool the framework's recipes declare. |
| Reviewer | One reviewer reads the diff through eight lenses and writes its findings. |
| Acceptance | It runs the end to end and visual harnesses, when the project has them. Then a verifier that did not build the task runs the product and records evidence. |
| Close | It asks you the rows only a person can answer, then writes the verdict. |

The diff covers the range the build recorded: from the commit the build started at to its final
commit. Review reads that range and computes none of its own. Two orders that pass alone can fail
together, so the tools run again over the whole task.

The steps before the close commit nothing. The close commits the task folder with the record,
`review/review.json`. Before the verdict, review prints the audit list, so you see first what did
not run. See [the verdict](verdict.md).

## What review refuses

Review stops, writes nothing, and names the repair when:

- implementation has not finished, so there is no build record;
- the code repository has uncommitted work;
- the repository has moved past the commit the range ends at. A commit past it that only
  removes files `task environment up` added is allowed. A commit that puts back a file the branch
  started with is refused: revert it, review, and put the files back after the review;
- a criterion changed after the freeze, because its frozen tests prove the frozen text;
- the catalog changed the check recipe after the build's baseline was taken.

Each refusal is explained once, in [the task review refuses](../../when-it-stops/review-refused.md).

## A task you marked complete by hand

Review still runs on it, and the task stays complete. The close says completion does not run.
Follow up tasks are still made: you choose which ones, and an unattended run creates them all.

## A second review

A recorded verdict ends the review. A second one starts only when you ask, and it starts from
the checks step, against the code as it stands now. The old record, findings file and brief are
archived first, each with its date and commit in the name, so nothing found before is lost.

## Why it works this way

- The range is one fact with one producer. The build writes it, and review only reads it.
- Uncommitted work makes the range a claim about something else, so review refuses it.

Source: skills/review/SKILL.md, skills/review/references/checks.md, skills/review/scripts/review-actions.sh
