# Finish the task, grant an attempt, restart the build, or clear a halt

This step covers four actions that act on the task rather than on one order. `finish` runs once
every order is closed. `grant-attempt` answers a spent attempt counter, when a person wants to
grant one more, and a spent run budget, once the person has raised it. `restart` follows a
mid-build design change: it halted one or more orders, and a person wants a fresh build against the
new design. `clear-halt` answers every other halt, once the person has acted on what it names.

## Finish

Every order closed, none halted, and no `implementation/finished.json` on disk means the
implementation stage is done and waiting to be recorded. Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh finish "<task_folder>"
```
It refuses unless every order in the ledger is closed, naming whichever is not. It also refuses
when any order carries a halt reason, closed or not, naming the order and the reason. It refuses
unless every machine-verified criterion reads confirmed too, naming whichever is not. It refuses a
dirty code repository as well, because the commit range it records is a claim about what that
repository holds.

On success it writes `implementation/finished.json`: the commit range this stage produced, and each
order's own range and rounds used. The record is committed when the stage closes: `finish` commits
the task folder, in the project folder and never in the code repository. It also records each criterion's row state and who judged it.
The checklists for the criteria a person verifies are copied in too, from the frozen test records.
The review stage reads this one file rather than one per order. It records the findings ruled
deferred with their reasons, and how many rows a model judged rather than a person. It prints
summary lines and the record's path, never the record. The lines carry the commit range and one line
per order. They carry the criteria by row state, the checklist count, the deferred findings by id,
and the model-judged count.

**Finish ends implementation only.** It never touches `task.json`. The task goes to the review
stage next, which reads `finished.json`; completion, not this step, is what confirms the criteria a
person verifies by checklist.

Interactive: stop here. Name the next command for the person, `/aida:review <task-id>`, and never
invoke it yourself. Autonomous: invoke `aida:review` through the Skill tool, once, with the task
id, and stop if it refuses. Invoke it only when the mode covers review too; otherwise end as
interactive does, naming the command. Each stage refuses to start without the previous stage's
record, so a stage cannot run out of order. That is why this chain is safe.

## Offer the grant, when a halt reads "attempts spent"

An order halted with a reason beginning `attempts spent` has used every attempt it was allowed and
still failed a check. Interactive, with a person present, put the two recorded attempts to them.
Ask which of the three things named in `references/build.md`'s halt section is true. If they decide
the order needs one more attempt, run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh grant-attempt "<task_folder>" <order id> \
  --reason <why this order gets another attempt>
```
It raises the order's own allowed count by one, and records the reason and the date. It clears the
halt only when the halt began with `attempts spent`; any other halt refuses, naming it. It never
touches the attempts already used, so the counter still never goes down. It refuses outright on an
autonomous implement stage: the grant is a person's judgement, and the person sets the task
interactive first. The reason may not hold the text `; earlier: `, the text this stage joins one
halt reason to another with; a reason carrying it would forge a segment nobody wrote.

The grant is the person's to offer and the person's to take. Do not run it on their own behalf
because an order is halted; put the halt and its recorded attempts to them first.

## Offer the grant, when a halt reads "budget spent"

An order halted with a reason beginning `budget spent` was about to be dispatched when the run
reached its ceiling. `budget` in `task.json` sets that ceiling, and the halt names the numbers.
Put them to the person. The spend is recomputed at every dispatch, so a grant alone brings the
halt straight back. The person raises `budget.dispatches` or `budget.minutes` in `task.json`
first. Then `grant-attempt` clears the halt as it clears `attempts spent`. It also raises that
order's attempts by one; say so.

## Offer the restart, when a halt reads "design drift"

A halt beginning `design drift` means `start` found the live design changed after this order
started. That can be direct, or through a started order it depends on. The halted orders start
over; every other order keeps what it has.

Put that to the person. If they want to rebuild the halted orders against the new design, run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh restart "<task_folder>" \
  --reason <what changed and why these orders start over>
```
It refuses when no order is halted for design drift, or when the code repository's tree is not
clean. It refuses on an autonomous implement stage too: a restart is a person's judgement. The
reason may not hold `; earlier: `, the same refusal the grant's own reason takes, for the same
cause. Design has to close again on the live files first. The restart takes the halted orders'
live copies into the snapshot, and refuses with exit 13 until `design-closed.json` records a
close over them.

On success it moves only the halted orders' records to `implementation-<date>-<commit>/`. A
record is the order's when its file name carries the order id, the way every record the script
writes does. It writes the reason and the halted orders there as `restarted.json`, and prints
that path. It keeps every other order's records, and the snapshot and the ledger, in place. In
the ledger the halted orders go back to not started, and their judgements are dropped. The
criteria they serve go back to not judged. A finished order is never redone for a change it never
depended on. A halted order the live design no longer holds refuses. Removing an order from a
running build is not built, and the message names the by-hand path. The next `start` is a
resumed run.

## Clear any other halt, once the person has acted on it

A halt that reads none of `attempts spent`, `budget spent` or `design drift` names something a
person does outside this script. That is a rejected row, a finding on a non-goal, a fixer's
scope, a finding ruled load-bearing, or a tree a role left dirty. Fix rounds spent with findings
open halt the same way. Put the halt and its reason to the person. When they have
repaired the test, ruled on the finding, or committed the tree, run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh clear-halt "<task_folder>" <order id> \
  --because <what the person did about it>
```
It removes the halt from the order and records the reason and the date under `haltsCleared` in
the ledger. It prints the step the order resumes at; nothing moves the order. It refuses a halt
the grant or the restart answers (exit 85), naming that action, and a closed order (exit 67). It
refuses when the task's implement stage is autonomous (exit 68), because clearing a halt is a
person's judgement. The person sets the task interactive first. The reason may not hold
`; earlier: `, for the same cause as the grant's. Then run `start` again and take the `next:`
line.
