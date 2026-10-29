# The verdict

The verdict is passed or failed. Only a criterion that reads unmet fails the review. Every other
result that is not met is a warning. The record lists it, and the close names it to you.
Completion closes over a warning only on your reason.

## The five answers a check gives

| Answer | What happened | Effect on the verdict |
|---|---|---|
| met | it looked, and the answer is yes | passes |
| unmet | it looked, and the answer is no | a warning |
| unknown | it could not look: a tool did not run, a file was missing, a lens never answered | a warning |
| undeclared | the recipe names no tool for it, marks it absent, or it does not apply to this task | passes, named in its own word |
| not-needed | no order in this task asked for it | passes, named in its own word |

A criterion answers in three words: met, unmet or unanswered. Unmet fails the review.
Unanswered means nobody could answer it, and it is a warning.

## The verdict rules

1. A criterion that reads unmet fails the review. The contract is not met.
2. A check that reads unmet or unknown, and a criterion that reads unanswered, is a warning.
3. Met, undeclared and not-needed all pass, and each is reported in its own word.

The report names the criterion that caused a fail, and each warning. Beside the verdict it names
each check that reads undeclared or unknown, the count of unanswered criteria, and the count of
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
| awaiting-person | the acceptance verifier read a row not met, and the check waits for your answer at the close |

Then one line per surface, run or not run with the reason, and a line of counts. Completion puts
the same list in the pull request body.

## The one write into the contract

The close writes each criterion's verdict into the contract, `alignment.json`. Nothing else in
the contract changes. The write stops no order, and the report says that review made it.

## Why it works this way

- Undeclared passes because the framework has answered: it has no such tool. Blocking there
  would block every project on that framework.
- Unknown is a warning, never a pass, because a result nobody could read is never waved through.
  It does not fail the review on its own. Every catch on record came from a person who read the
  finding.
- A person present reads the warnings at the close. With nobody present, completion stops on
  them, which is the one place an unattended task stops on the review.

Source: skills/review/SKILL.md, skills/review/references/close.md, skills/review/references/checks.md, skills/review/scripts/review-actions.sh
