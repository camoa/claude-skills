# After a failed review

A review fails when a criterion reads unmet. It hands you the record and stops. You fix the code
and review again, or you close the task without a passed review. A review that passed with
warnings is handled the same way, with your reason at completion.

## Fix the code, then review again

Run `/aida:implement <task-id>`. Its next step is `reopen`. It sends each finding that fails a
criterion back to the order that owns its file, unless you ruled the finding `wrong`. That
order's own fixer repairs it, a fresh verifier checks the round, and the order closes again. The
build then finishes again, with a range that ends at the new head. Then run
`/aida:review <task-id>`. It starts from the checks, and archives the old record first.

`reopen` takes findings that fail a criterion, and findings you ruled `test-wrong`. A test ruled
wrong goes to the order whose frozen record holds it. That order's test author corrects it, and
the correction freezes as a new record. You never correct a frozen test by hand. `reopen` names
each finding it could not send, with the reason. The finding names no file, or no order owns the
file. Or two orders own it and neither serves the criterion, or the owning order is not closed.
When it can send none, it refuses and keeps the build record.

`reopen` never takes these, and never names them:

- a failed check that cites no finding;
- a medium or high finding that cites no criterion, unless you ruled it `test-wrong`. Rule it at
  the [close](close.md), or fix it yourself;
- a decision you ruled `load-bearing`, `test-wrong` or `rebuild`.

For each one you fix yourself, commit the fix on the task branch, then run the build's finish
again. Keep the fix inside the files the orders own. A file no order owns reads unmet at
"everything serves a criterion". The [implement](../implement/README.md) pages cover reopen and
finish.

## When a check reads unknown

Find the check in the audit list, where it carries the word could-not-look. Then fix the cause
and review again.

| Cause | What to do |
|---|---|
| the catalog could not be reached, or the recipe fetch failed | reach the catalog |
| the reviewer's output was missing or unreadable | review again |
| the playbooks were never loaded | run `/aida:research <task-id>` again |
| the tool printed nothing, and the baseline kept nothing | open the tool's output in the record and see why |
| the suite, or a surface run, selected no tests | make it select tests |
| the end to end preflight failed, so the run never started | fix what it checks, such as the site being up |
| nobody walked the surfaces, on an autonomous run | review again with a person present |

## Close without a passed review

Completion closes a task on a failed review, or on one with warnings, only on your reason, one
sentence that the record keeps. See [completion](../completion/README.md).

## Why it works this way

- Review starts no fixer and runs no second pass. Each fix goes to the order that owns the file,
  so the fix stays inside that order's tests and files.
- A deferral is not a pass. The review judges a deferred finding again on the next pass.

Source: skills/review/references/close.md, skills/review/SKILL.md, skills/implement/references/finish.md
