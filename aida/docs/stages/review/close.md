# Answer the close

At the close, review asks you every question a script cannot answer, in one pass, then writes the
verdict. Each answer you give is kept in the record.

## Your criteria

Review shows the checklist rows of each criterion a person verifies, word for word as the build
froze them. You answer met or unmet per criterion. On a task with no automated tests, the
done-when rows of each order you confirm are yours to answer too.

Each criterion shows the acceptance verifier's evidence under it: the verdict, the file it judged
from, and its note. Open the files it names. The verifier's verdict decides nothing. You answer
from what it saw. See [verify the task by running it](acceptance.md).

When a criterion's verify clause names a command, review waits until you say the step before it
is done. Then it runs the command and shows you its output with the question.

A surface check whose run passed, but where the verifier did not judge a row met, is asked too.
Review shows its evidence rows, and you answer the check met or unmet.

A criterion a test proves needs no answer. It reads met when its row was confirmed and no failing
test is one it froze.

## Warnings

Every check that reads unmet or unknown is a warning, and so is a criterion nobody answered. The
close names each one, and the record keeps them. A lens check whose findings are all low reads met,
with the findings left as follow ups. A guides or practices check with nothing to judge against
reads unknown, a warning. Neither waits for your answer.

## Findings that fail a criterion

A medium or high finding that cites a criterion fails it, whatever the criterion's own answer
says. You rule each one once:

- `wrong`: the reviewer was mistaken. The criterion reads its own answer.
- `deferred`: the finding is real and waits. Completion offers it as a follow up task, and the
  criterion reads its own answer.
- `test-wrong`: the finding names a frozen test that is wrong. The criterion still fails, and the
  build's `reopen` sends the finding to that order's test author. See [after a failed
  review](failed.md).
- `contract-wrong:<corrected text>`: the code is right, and the criterion's words are wrong. The
  record keeps your text beside the frozen one, and the criterion reads its own answer. Completion
  offers a follow up task that changes the criterion through `/aida:scope`.

A finding keeps its id across review passes while its content is the same, and a new finding
takes a new id. So an answer you prepared from an earlier pass never rules another finding. With
no ruling, the finding still fails its criterion. A medium or high finding that cites no
criterion fails its lens check, a warning, and you may rule it the same way. An answer to a row
nobody asked decides nothing: the close names it as a warning and asks the row it meant again.

## Decisions the build left

A build with nobody present can leave a decision for you: a finding it could not settle, or a
departure from the design. For a finding, answer `wrong`, `deferred`, `load-bearing` or
`test-wrong`. For a departure, answer `keep` or `rebuild`. The words mean what they mean at the
build; see [implement](../implement/README.md).

`load-bearing`, `test-wrong` and `rebuild` read unmet, a warning. A `rebuild` goes through `redo`
in the implement skill, which builds the order again and sets the departure aside. While one decision is
unanswered, review writes no verdict and prints "no verdict yet". Run the close again when you can
answer.

## A non-goal that changed after the freeze

The reviewer judged the live text. Review shows you both texts and asks whether you approve the
live one. `accept` keeps both texts in the record. `reject` reads unmet, a warning. Put the frozen text
back with `/aida:scope`, or remove an added non-goal there, then review again. A removed non-goal
cannot come back that way, so the route is a redo of the orders it bounds. A standing order never answers
this question.

## Correct an answer

Gave a wrong answer, or left one out? Run `/aida:review <task-id>` again at the same commit, and
say you want to correct an answer. A plain run only reads the verdict back. The close archives
the closed record, keeps the reviewer's work, and asks the rows again. No fresh
pass runs. After a fix commit, the close warns that the code moved, and the review starts again
from the checks. With nobody present, it refuses instead.

## What comes next

Review prints the audit list, then the verdict and the rows that decided it. It names
`/aida:completion <task-id>` and never runs it for you. After a failed review, see
[after a failed review](failed.md).

## Why it works this way

- A summary asks a different question than the row a person signed up to answer, so rows are
  shown word for word.
- A wrong answer costs one more close, not a new review, because the code has not moved.

Source: skills/review/references/close.md, skills/review/SKILL.md, skills/review/scripts/review-actions.sh
