# The task review refuses or fails

`/aida:review` checks the whole task against its frozen contract and code. It refuses when what
it would read has moved. It writes no verdict while a decision the build left is unanswered, and
it fails while a criterion you verify is unanswered.

## It refuses

| Exit | What it means | What to do |
|---|---|---|
| 66 | implementation has not finished | run the finish step of `/aida:implement` |
| 62 | a review step ran before the step it reads | run the step the message names |
| 62 | a non-goal changed after the review brief was written | run the brief again, and let AIDA send the reviewer on the new brief |
| 61 | the code repository has uncommitted work | commit it, then run the step again |
| 51 | the code moved, or went dirty, since `checks` ran | run `checks` again |
| 3 | the code is not at the commit the build ended at | see "The code moved past the build" below |
| 3 | a criterion changed after the build froze it | put the frozen text back with `/aida:scope`, or restart the build |
| 73 | the check recipe changed after the baseline | see [the build cannot start](cannot-test.md) |
| 77 | the project records no stack | set it with `/aida:project set-frameworks` |
| 124 | a frozen test changed after its freeze | put the file back as its freeze commit holds it and commit it, then run finish and review again; AIDA will not edit it for you |

## The code moved past the build

Review reads the commit the build ended at. A commit after it is accepted only when it just puts
back the files `task environment up` changed. For any other later commit, check out the commit
the build ended at, or run the finish step of `/aida:implement` again.

A tree that holds those files put back refuses too, because a site command could then reach the
main checkout's site. Run the `git revert <commit>` the message names, run `checks` again, and
put the files back after the review.

## "No verdict yet": a decision waits

A decision the build left pending, such as a finding that names no file to change or a
departure from the design, is asked at close. A
finding takes `wrong`, `deferred`, `load-bearing` or `test-wrong`; a departure takes `keep` or
`rebuild`. While one is unanswered, close writes no verdict. A later close with you present
answers each one, at the same commit, with no fresh review. See
[close the review](../stages/review/close.md).

## The review fails on a question

- **A criterion you verify is unanswered.** It reads unanswered, and the verdict is `failed`.
  Close names each such criterion and its route. Answer it at a later close, at the same commit,
  and the review can pass.
- **A medium or high finding.** It fails the criterion it cites unless you rule it `wrong` or
  `deferred`.
- **A changed non-goal you reject.** The review fails.

A wrong or missing answer is corrected by running close again at the same commit. After a fix
commit, close refuses (exit 51) and the route is `checks`.

On a light or autonomous run nobody answers at close, and exit 70 means a person's answer was
passed with nobody present. How your answer reaches it is on
[review on an unattended run](../stages/review/autonomous.md).

## Why it works this way

- **The verdict is read off one commit.** A review of moving code would judge something no record
  describes.
- **A person answers what a person verifies.** A model may not sign off a criterion the contract
  gives to a person.

Source: skills/review/SKILL.md, skills/review/references/close.md, skills/review/scripts/review-actions.sh
