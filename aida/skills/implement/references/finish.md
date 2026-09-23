# Finish the task, grant an attempt, restart the build, or clear a halt

This step covers four actions that act on the task rather than on one order. `finish` runs when
every order is closed. `grant-attempt` answers a spent attempt counter, when a person wants to
grant one more, and a spent run budget, once the person has raised it. `restart` follows a
mid-build design change: it halted one or more orders, and a person wants a fresh build against the
new design. `clear-halt` answers every other halt, once the person has acted on what it names.

## Finish

Every order closed, none halted, and no `implementation/finished.json` on disk means the
implementation stage is done and waiting to be recorded. Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh finish "<task_folder>" \
  [--value <name>=<value>]...
```
It refuses unless every order in the ledger is closed, naming whichever is not. It also refuses
when any order carries a halt reason, closed or not, naming the order and the reason. It refuses
unless every machine-verified criterion reads confirmed too, naming whichever is not. It refuses a
dirty code repository as well, because the commit range it records is a claim about what that
repository holds.

Then it runs the test-execution recipe's suite row once, at the final commit, from the worktree.
The record steps leave a row the recipe costs `end-of-task` unrun and record it `deferred`; this
is the run that decides it. The recipe paths come from `implementation/preconditions.json`, so
pass none. Pass `--value <name>=<value>` for a placeholder the suite row carries, the same as
`build-record`. The baseline's own failures are subtracted the same way. A suite that is unmet
or unknown refuses (exit 86). The message names the first twenty new lines and the sidecar,
`implementation/finished-suite.txt`. A fix commit on the branch and a second `finish` is the
route. A recipe with no suite row passes with `undeclared`, and the record says so.

On success it writes `implementation/finished.json`: the commit range this stage produced, and
each order's own range and rounds used. The suite's verdict is under `suite`, with its output in
the sidecar. The record is committed when the stage closes: `finish` commits
the task folder, in the project folder and never in the code repository. It also records each criterion's row state and who judged it.
The checklists for the criteria a person verifies are copied in too, from the frozen test records.
The review stage reads this one file rather than one per order. It records the findings ruled
deferred with their reasons, and how many rows a model judged rather than a person. It prints
summary lines and the record's path, never the record. The lines carry the commit range and one line
per order. They carry the criteria by row state, the checklist count, the deferred findings by id,
and the model-judged count.

**Finish ends implementation only.** It never touches `task.json`. The task goes to the review
stage next, which reads `finished.json`. Review's close, not this step, confirms the criteria a
person verifies by checklist.

**Finish runs again after a failed review.** The person commits the fix on the task branch, then
takes this step again. It rewrites `finished.json` with a range ending at the new head, and review
runs from its first step. Keep the fix inside the files the orders own. A file no order owns reads
unmet at review's check that every change serves a criterion.

Interactive: stop here. Name the next command for the person, `/aida:review <task-id>`, and never
invoke it yourself. Autonomous: invoke `aida:review` through the Skill tool, once, with the task
id, and stop if it refuses. Invoke it only when the mode covers review too; otherwise end as
interactive does, naming the command. Each stage refuses to start without the previous stage's
record, so a stage cannot run out of order. That is why this chain is safe.

## Offer the grant, when a halt reads "attempts spent"

An order halted with a reason beginning `attempts spent` has used every attempt it was allowed and
still failed a check. Interactive, with a person present, open with: "The builder used every
attempt it was allowed on this unit of work and still failed a check. You decide which of three
things is true; a model choosing would let the test describe the code. The test is
wrong: you correct it, and one more attempt is granted. The unit of work is wrong, too big or
its interface does not fit. Then design changes it, and the build takes it fresh. The code is hard:
you write it, and the same checks judge it. If you want one more attempt as it stands, say so."
Then name the two recorded attempts by
path. SKILL.md's "One order halting" section is where the three things are stated. If they decide
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
Put them to the person, opening with: "The build reached the limit you set on this task, in
dispatches or in minutes, and stopped. Only you can raise it. Raise the limit in the task's
record and the build can continue. Leave it and the build stays stopped." Then name the two
numbers the halt holds. The spend is recomputed at every dispatch, so a grant alone brings the
halt straight back. The person raises `budget.dispatches` or `budget.minutes` in `task.json`
first. Then `grant-attempt` clears the halt as it clears `attempts spent`. It also raises that
order's attempts by one; say so.

## Offer the restart, when a halt reads "design drift"

A halt beginning `design drift` means `start` found the live design changed after this order
started. That can be direct, or through a started order it depends on. The halted orders start
over; every other order keeps what it has.

A halt about an order's own design file clears itself when the drift does. Put the design back
to what the snapshot holds, then run `start` again: it compares, finds no drift for that order,
and removes that segment. Any other segment stays and the order stays halted with it. The
clearing is recorded under `haltsCleared` in the ledger, with the halt text as it stood. Two
drift reasons never clear this way and always take the restart. One names a changed criterion.
The run that wrote it replaced the snapshot's contract, so no later comparison sees the change.
The order's frozen tests still assert the old sentence. One reopen that changed the design file
and a criterion together writes both segments. The criterion one then holds the order when only
the file goes back. The other names another order that
drifted, and it waits for the restart of the order it names. Offer the restart when the new
design is the one to build, and for either of those two reasons.

Put that to the person, opening with: "The design changed after this unit of work was started, so
what was built no longer matches it. Only you can say the new design is the one to build.
Rebuild it and its tests and code are written again; every other unit keeps what it has. A unit
the design removed is dropped. Leave it and it stays stopped." Then name the halted
orders and what changed in each. If they want to rebuild the halted orders against the new
design, run:
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
depended on. A halted order the live design no longer holds is dropped from the snapshot and the
ledger. Its records move aside with the rest, and the summary names it. The next `start` is a
resumed run.

The records move; the commits they name stay on the branch. The restart reads each halted
order's freeze commit and its build and fix ranges. It finds the build and fix records wherever
a retake or an earlier restart moved them. An order's own commits are then never counted as
later ones. It lists the ones still on the branch, one
`commits:` line each, with the order and the kind. It writes them into `restarted.json` too.
It changes nothing in the tree. The `tree:` line then says one of two things. Put it to
the person, opening with: "The tests and code written for this unit are still on the branch.
Its next test author would write against them, and a test that passes at once would prove
nothing. You choose what happens to those commits." Then say the line. When it names a commit
to reset to, nothing later depends on those commits. Say: "Take the branch back to that commit
and they are gone. That is a hard reset, which you run; this session cannot." When it says to
carry them, other commits sit after them. Say: "They stay. This unit's own code stays in the
tree, so its next tests cannot go red. The next start names them, and the
test author is told the tree holds a partial build." Either way the next `start` prints a
`partialBuild` line while any of them is still on the branch.

## Clear any other halt, once the person has acted on it

A halt that reads none of `attempts spent`, `budget spent`, `design drift` or `test wrong` names
something a person does outside this script. That is a rejected row, a finding on a non-goal, a
fixer's scope, a finding ruled load-bearing, or a tree a role left dirty. Fix rounds spent with
findings open halt the same way. A `test wrong` halt is cleared by `retake-tests`, under Rulings
in `references/review.md`, and `clear-halt` refuses it. Put the halt and its reason to the person, opening with: "This unit of
work stopped on something only you can do. It waits until you say you have done it. Do what
the reason names, then say so, and the build resumes where it stopped." Then say the reason in
plain words. When they have repaired the test, ruled on the finding, or committed the tree, run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh clear-halt "<task_folder>" <order id> \
  --because <what the person did about it>
```
It removes the halt from the order and records the reason and the date under `haltsCleared` in
the ledger. It prints the step the order resumes at; nothing moves the order. It refuses a halt
the grant, the restart or the retake answers (exit 85), naming that action, and a closed order
(exit 67). For a drift halt the refusal also names `start`, which clears a segment about the
order's own design file once the design no longer differs. It
refuses when the task's implement stage is autonomous (exit 68), because clearing a halt is a
person's judgement. The person sets the task interactive first. The reason may not hold
`; earlier: `, for the same cause as the grant's. Then run `start` again and take the `next:`
line.
