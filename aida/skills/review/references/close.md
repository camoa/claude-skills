# Ask the person's rows, and close the review

This step asks the one question a script cannot answer, decides check 1, and writes the verdict.

## Ask the checklist rows, once

`read` emits `checklists[]` whole, each row with the criterion it belongs to. A task with no
automated tests adds a row for each done-when sentence of each order a person confirms. The
row sits under each criterion that order owns, or serves when it owns none. Show each row
**verbatim** from that output, and open no file yourself: this skill grants no Read rule, and a
summary asks a different question than the row a person signed up to answer. Show every row in one
pass, and ask for each one only once.

Ask the same once about each check the summary prints as `unknown answeredBy=nobody`. A lens
check names the low findings of one lens. The person confirms them, met, or rejects them, unmet.

A check whose id begins `decision-` is a decision a build left. Ask it in the
words of `references/review.md` under the implement skill, under Rulings for a finding and under
the departure halt for a departure. The answer decides what happens next:

- `wrong`: the reviewer was mistaken, and the work stands as built.
- `deferred`: the finding is real and waits. Completion offers it as a follow up task, the way
  it offers a follow-up finding (`skills/completion/scripts/completion-actions.sh`, `cp_load_follow_ups`).
- `keep`: the departure stands as built.
- `load-bearing`, `test-wrong` or `rebuild`: the check reads unmet, so the review fails. The
  order is closed, so the routes inside implement no longer reach it. The route is a fix
  commit on the task branch, then finish again, per "Finish runs again after a failed review"
  in `skills/implement/references/finish.md`. A load-bearing finding is fixed. A wrong
  test is corrected by the person, not a model. A departure is rebuilt to the design. That
  finish carries no decision the person already answered, so the next review asks it no more.

`close` writes no verdict while a `decision-` check is unanswered. The record keeps every row,
and a later `close` with the person present answers each one with no fresh pass. Autonomous,
nobody answers, so the review has no verdict and completion's halt names each decision.

The person answers met or unmet per criterion, from its rows. Their answer becomes one flag
below. Autonomous, there is
nobody to ask: each such criterion reads unanswered, no row flag is accepted, and the task gets no
sign off. A run with nobody present cannot sign off a task carrying one person verified criterion.

## Check 1 joins on the test name

A machine verified criterion reads met when its row state is confirmed and no failing test in check 8
carries its id. It reads unmet when a failing test carries the id. It reads unanswered when the suite
could not run. Implementation puts the criterion id at the end of each test's name, delimited, so the
script compares strings. Do not re-derive that join by hand.

A suite reading not-needed reads the row state the same way a passing suite does. No order in the
task runs a test, so no suite was ever going to name the criterion, and the build already confirmed
the row.

## Close

Run, with one `--row` per criterion a person verified, and one per criterion that carries the
done-when rows of an order proved by `confirm`, and one per check the person answered:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/review/scripts/review-actions.sh close "<task_folder>" \
  --row <criterion>=met|unmet --row <check id>=met|unmet \
  --row <decision id>=wrong|deferred|load-bearing|test-wrong|keep|rebuild
```
On a record that already holds a verdict, it archives that pass's files as `checks` does, per
SKILL.md, and stops at exit 63.

It writes check 1, one verdict per criterion, and the review's own verdict into
`review/review.json`. The record is committed when the stage closes: `close` commits the task
folder, and the steps before it commit nothing. It prints the verdict, the rows that decided it, and that path. Give the person
the path, and say the record holds the evidence for every row, per SKILL.md.

## The verdict rules

The verdict is two words, `passed` and `failed`.

1. **A check reading unmet fails the review.** A failure dominates.
2. **A check reading unknown fails the review.** A result nobody could read is never waved through.
3. **Met, undeclared and not-needed all pass**, and each is reported in its own word. A framework
   with no tool has answered, and blocking there blocks every project on that framework. A check no
   order asked for has answered too.
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

Interactive: stop here. Name the next command for the person, `/aida:completion <task-id>`, and
never invoke it yourself. Autonomous: invoke `aida:completion` through the Skill tool, once, with
the task id, and stop if it refuses. Invoke it only when the mode covers completion too; otherwise
end as interactive does, naming the command. Each stage refuses to start without the previous
stage's record, so a stage cannot run out of order. That is why this chain is safe.

When close says the task was marked complete before this review, completion does not run in
either mode. Name the review record for the person, and stop.
