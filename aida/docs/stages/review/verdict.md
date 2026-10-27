# The verdict

The verdict is passed or failed. A check that reads unmet or unknown fails the review, and so
does a criterion that is not met.

## The five answers a check gives

| Answer | What happened | Effect on the verdict |
|---|---|---|
| met | it looked, and the answer is yes | passes |
| unmet | it looked, and the answer is no | fails |
| unknown | it could not look: a tool did not run, a file was missing, a lens never answered | fails |
| undeclared | the recipe names no tool for it, marks it absent, or it does not apply to this task | passes, named in its own word |
| not-needed | no order in this task asked for it | passes, named in its own word |

A criterion answers in three words: met, unmet or unanswered. Unanswered means nobody could
answer it, and it is never a pass.

## The verdict rules

1. A check that reads unmet fails the review.
2. A check that reads unknown fails the review.
3. Met, undeclared and not-needed all pass, and each is reported in its own word.
4. A criterion that reads unmet or unanswered means no sign off, whatever the checks said.

The report names the check or the criterion that caused a fail. Beside the verdict it names each
check that reads undeclared or unknown, the count of unanswered criteria, and the count of
catalog notes.

## Catalog notes

A catalog note is something a guide or a recipe should hear about. It never fails a review.
Review writes a note for:

- a guide the code contradicts, or a pattern the framework wants and no guide names;
- a recipe whose command no longer runs, or whose commands could not be read;
- a recipe research or design judged not to fit this task;
- a change no tool row read;
- a project copy of a recipe that is behind the catalog's copy.

Review writes nothing to the catalog. You decide whether a note becomes a proposal.

## The audit list

After the close, review prints one line per check: its name, its answer, and how the answer came
about. You see this list before the verdict word.

| Word | What it says |
|---|---|
| ran | a command or a lens ran and gave the answer |
| read | a record decided it, and nothing ran |
| off | the project turned it off, or the recipe declares the row absent |
| could-not-look | a recipe, a row, a file or a tool was missing |
| awaiting-person | the check waits for your answer at the close |

Then one line per surface, run or not run with the reason, and a line of counts. Completion puts
the same list in the pull request body.

## The one write into the contract

The close writes each criterion's verdict into the contract, `alignment.json`. Nothing else in
the contract changes. The write stops no order, and the report says that review made it.

## Why it works this way

- Undeclared passes because the framework has answered: it has no such tool. Blocking there
  would block every project on that framework.
- Unknown fails because a result nobody could read is never waved through.

Source: skills/review/SKILL.md, skills/review/references/close.md, skills/review/references/checks.md, skills/review/scripts/review-actions.sh
