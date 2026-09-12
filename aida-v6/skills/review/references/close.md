# Ask the person's rows, and close the review

This step asks the one question a script cannot answer, decides check 1, and writes the verdict.

## Ask the checklist rows, once

Read `checklists[]` from `finished.json` and show each row **verbatim**, with the criterion it
belongs to. A summary asks a different question than the row a person signed up to answer. Show every
row in one pass, and ask for each one only once.

The person answers met or unmet per row. Their answer becomes one flag below. Autonomous, there is
nobody to ask: each such criterion reads unanswered, no row flag is accepted, and the task gets no
sign off. A run with nobody present cannot sign off a task carrying one person verified criterion.

## Check 1 joins on the test name

A machine verified criterion reads met when its row state is confirmed and no failing test in check 8
carries its id. It reads unmet when a failing test carries the id. It reads unanswered when the suite
could not run. Implementation puts the criterion id at the end of each test's name, delimited, so the
script compares strings. Do not re-derive that join by hand.

## Close

Run, with one `--row` per criterion a person verified:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/review/scripts/review-actions.sh close "<task_folder>" \
  --row <criterion>=met|unmet
```
It archives any previous record to `review/review-<date>-<commit>.json` before it writes, and it
refuses at exit 63 when that move fails. Version 5 ran four review passes on one task, each
overwriting the last, and pass three found a defect pass four's record does not mention.

It writes check 1, one verdict per criterion, and the review's own verdict into
`review/review.json`.

## The verdict rules

The verdict is two words, `passed` and `failed`.

1. **A check reading unmet fails the review.** A failure dominates.
2. **A check reading unknown fails the review.** A result nobody could read is never waved through.
3. **Met and undeclared both pass**, and undeclared is reported in its own word. A framework with no
   tool has answered, and blocking there blocks every project on that framework.
4. **A criterion reading unmet or unanswered means no sign off**, whatever the checks said.

Name the check or the criterion that caused a fail. Then hand the record to the person. No fixer
starts and no second pass runs, per SKILL.md.

## Say what the write did to the contract

`close` writes one field back into the contract, each criterion's `verdict` in `alignment.json`, which
that schema reserves for review. Nothing else in the contract is touched.

**That write moves the contract hash.** The hash covers the whole file, so the next `start` reports
the contract as changed, and it halts no order. Say in the report that review made that write, and
that the drift is review's own. A reader who is not told reads it as a contract somebody edited.

Close the report with the three things SKILL.md requires: the checks reading undeclared or unknown,
the count of criteria reading unanswered, and the count of catalog notes.
