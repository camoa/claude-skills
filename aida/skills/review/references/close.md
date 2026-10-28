# Ask the person's rows, and close the review

This step asks the one question a script cannot answer, decides check 1, and writes the verdict.

## Ask the checklist rows, once

`read` emits `checklists[]` whole, each row with the criterion it belongs to. A task with no
automated tests adds a row for each done-when sentence of each order a person confirms. The
row sits under each criterion that order owns, or serves when it owns none. Show each row
**verbatim** from that output, and open no file yourself: this skill grants no Read rule, and a
summary asks a different question than the row a person signed up to answer. Show every row in one
pass, and ask for each one only once.

Ask the same once about each check the summary prints as `unknown answeredBy=nobody`. Such a
check names the verifier's rows that did not read met. Show its
`evidence(<surface>@<viewport>)` lines, and the person judges the check met or unmet.

A check whose id begins `decision-` is a decision a build left. Ask it in the
words of `references/review.md` under the implement skill, under Rulings for a finding and under
the departure stop for a departure. A check whose id ends `-non-goal` is a non-goal the live
contract changed, removed or added after the freeze. Show both texts from the summary's `nonGoal`
line, verbatim, and ask whether the person approves the live text. A standing order never answers
a non-goal `accept`: ask the person each time. On an unattended run the answer passes only through
the record the main session writes, so this guard is no stronger than that record.
The answer decides what happens next:

- `wrong`: the reviewer was mistaken, and the work stands as built.
- `deferred`: the finding is real and waits. Completion offers it as a follow up task, the way
  it offers a follow-up finding (`skills/completion/scripts/completion-actions.sh`, `cp_load_follow_ups`).
- `keep`: the departure stands as built.
- `accept`: the person approves the live text of a changed non-goal. The record keeps both texts.
- `reject`: the reviewer judged a text the person did not approve, so the check reads unmet. Put the
  frozen text back with `scope update`, then archive the review and run it again. For an added
  non-goal, use `scope remove`. A removed one cannot come back that way, because `scope remove`
  retires its id, so the route is `redo` in the implement skill, for the orders it bounds.
- `test-wrong`: the check reads unmet, which is a warning. The implement skill's `reopen` sends
  the finding to the test author of the order that froze the test, the same way as a finding
  ruled `test-wrong`. Nobody corrects a frozen test by hand.
- `load-bearing` or `rebuild`: the check reads unmet, which is a warning. The
  order is closed, so the routes inside implement no longer reach it. The route is a fix
  commit on the task branch, then finish again, per "Finish runs again after a failed review"
  in `skills/implement/references/finish.md`. A load-bearing finding is fixed. A departure is
  rebuilt to the design. That finish carries no decision the person already answered, so the
  next review asks it no more.
  A `rebuild` reads met when the reviewed branch already holds it: a commit the order's own build
  or fix records list, after its review record, changes a file the order owns.

`close` writes no verdict while a `decision-` check is unanswered. The record keeps every row,
and a later `close` with the person present answers each one with no fresh pass. Autonomous,
nobody answers, so the review has no verdict and completion's halt names each decision.

A finding the summary prints under `disposition(criterion)` fails the criterion it cites, whatever
that criterion's own answer says. Ask the person to rule each unruled one once. The summary prints
a ruled finding with its ruling beside it. The four words:

- `wrong`: the reviewer was mistaken, so the criterion reads its own answer.
- `deferred`: the finding is real and waits. Completion offers it as a follow up task, and the
  criterion reads its own answer.
- `test-wrong`: the finding names a frozen test that is wrong. The criterion still fails. The
  implement skill's `reopen` sends the finding to the test author of the order that froze that
  test. Its corrected copy freezes as a new record. Nobody corrects it by hand.
- `contract-wrong:<corrected text>`: the code is right, and the criterion's wording is wrong. The
  record keeps the corrected text beside the frozen one, and the criterion reads its own answer.
  Completion offers a follow up task that changes the criterion through scope.

A finding keeps its id from one review pass to the next while its lens, file, lines and evidence
stay the same. A new finding takes an id no earlier pass used, so a row prepared from an earlier
pass never rules another finding. With no ruling, the finding still fails its criterion. The record keeps the finding and the
person's word. A medium or high finding that cites no criterion fails its lens check, which is a
warning. The person may rule it the same way. A lens check whose medium and high findings are all
ruled reads met.

The person answers met or unmet per criterion, from its rows and its evidence. `close` prints each
criterion's `evidence(<criterion>)` lines under its own line: the acceptance verifier's verdict,
the file it judged from, and its note. Show them verbatim with the question, and name each file so
the person can open it. When a criterion's verify clause names a command, wait until the person
says the step before that check is done. Then run the command, and show its output with the
question. Their answer becomes one flag below.
Autonomous, there is nobody to ask: with no recorded answer, each such criterion reads
unanswered, and the task gets no sign off. A run with nobody present and no recorded answer
cannot sign off a task carrying one person verified criterion. `close` names each one and its
route. When the person answers, `close` runs again at the same commit with the rows.
On a light or autonomous run, a row passes only through the person's recorded answer, step
`review close`. The task skill's `person-answer.sh` records it, after Claude Code asks.

## Check 1 joins on the test name

A machine verified criterion reads met when its row state is confirmed and no failing test in check 8
is one it froze. It reads unmet when a failing test is one it froze. It reads unanswered when the
suite could not run. The freeze record names the tests each criterion froze, so the script compares
strings. Do not re-derive that join by hand.

A suite reading not-needed reads the row state the same way a passing suite does. No order in the
task runs a test, so no suite was ever going to name the criterion, and the build already confirmed
the row.

## Close

Run, with one `--row` per criterion a person verified, and one per criterion that carries the
done-when rows of an order proved by `confirm`, and one per check the person answered, and one per
finding the person ruled:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/review/scripts/review-actions.sh close "<task_folder>" \
  --row <criterion>=met|unmet --row <check id>=met|unmet \
  --row <decision id>=wrong|deferred|load-bearing|test-wrong|keep|rebuild|accept|reject \
  --row <finding id>=wrong|deferred|test-wrong --row "<finding id>=contract-wrong:<corrected text>"
```
A close with no row prints every row that waits and the words each takes. Ask the person those
rows in one go. A row nobody asked, or a word its row does not take, decides nothing. `close` names
it in the task record as a warning, and the row it meant still waits.

On a record that already holds a verdict, it archives that record alone and writes the new
verdict in its place. The brief, the findings and every check stay, because the commit has not
moved. So a person who gave a wrong row, or left one out, runs `close` again. After a fix commit,
`close` warns that the code moved, and the route is `checks`. On an autonomous run it refuses at
exit 51 instead.

It writes check 1, one verdict per criterion, and the review's own verdict into
`review/review.json`. The record is committed when the stage closes: `close` commits the task
folder, and the steps before it commit nothing. It prints the verdict, the rows that decided it, and that path. Give the person
the path, and say the record holds the evidence for every row, per SKILL.md.

## The verdict rules

The verdict is two words, `passed` and `failed`.

1. **A criterion reading unmet fails the review.** The contract is not met.
2. **Every other result is a warning.** A check reading unmet or unknown, and a criterion reading
   unanswered, never fails the review. `close` lists each one in the record's `warnings` and on its
   `warnings:` line. Read each to the person.
3. **Met, undeclared and not-needed all pass**, and each is reported in its own word.

Name the criterion that caused a fail, and every warning. Then hand the record to the person. No
fixer starts and no second pass runs, per SKILL.md. Completion closes over a fail or a warning
only on the person's reason, and an unattended completion stops there. A finding that fails a
criterion, or a test ruled wrong, goes back to its order through the implement skill's `reopen`.
Its `next:` line names it, per "Finish runs again after a failed review" in
`skills/implement/references/finish.md`.

## Say what the write did to the contract

`close` writes one field back into the contract, each criterion's `verdict` in `alignment.json`, which
that schema reserves for review. Nothing else in the contract is touched.

**That write changes the file, not the contract.** The implement stage's `start` compares the
contract without verdicts, so it reports no change and stops no order. Say in the report that
review wrote the verdicts. A reader of the file's history who is not told reads it as an edit.

Close the report with the three things SKILL.md requires: the checks reading undeclared or unknown,
the count of criteria reading unanswered, and the count of catalog notes.

Then hand off to `completion`, as `${CLAUDE_PLUGIN_ROOT}/skills/next/references/handoff.md` says:
interactive, name `/aida:completion <task-id>` and stop; autonomous, invoke it when the run mode covers it.

When close says the task was marked complete before this review, completion does not run in
either mode. Run this once, then name the review record for the person, and stop:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/completion/scripts/completion-actions.sh follow-ups "<task_folder>"
```
Unattended, it creates the task for each follow up finding that has none.
