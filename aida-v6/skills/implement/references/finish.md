# Finish the task, grant an attempt, or restart the build

This step covers three actions that act on the task rather than on one order. `finish` runs once
every order is closed. `grant-attempt` answers a spent attempt counter, when a person wants to
grant one more. `restart` follows a mid-build design change: it halted one or more orders, and a
person wants a fresh build against the new design.

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
order's own range and rounds used. It also records each criterion's row state and who judged it.
The checklists for the criteria a person verifies are copied in too, from the frozen test records.
The review stage reads this one file rather than one per order. It records the findings ruled
deferred with their reasons, and how many rows a model judged rather than a person. It prints the
record on standard output and the file path on standard error.

**Finish ends implementation only.** It never touches `task.json`. The task goes to the review
stage next, which reads `finished.json`; completion, not this step, is what confirms the criteria a
person verifies by checklist.

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
autonomous run: the grant is a person's judgement, and nobody is present to make it. The reason may
not hold the text `; earlier: `, the text this stage joins one halt reason to another with; a
reason carrying it would forge a segment nobody wrote.

The grant is the person's to offer and the person's to take. Do not run it on their own behalf
because an order is halted; put the halt and its recorded attempts to them first.

## Offer the restart, when a halt reads "design drift"

A halt beginning `design drift` means `start` found the live design changed after this order's
snapshot was taken. That can be direct, or through an order it depends on. There is no mid-build
path that redoes one order alone; the whole implementation folder starts over, or nothing does.

Put that to the person. If they want to rebuild against the new design, run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh restart "<task_folder>" \
  --reason <what changed and why the build starts over>
```
It refuses when no order is halted for design drift, or when the code repository's tree is not
clean. It refuses on an autonomous run too: a restart is a person's judgement. The reason may not
hold `; earlier: `, the same refusal the grant's own reason takes, for the same cause. On success
it moves
`implementation/` to `implementation-<date>-<commit>/`, writes the reason and the drifted orders
into that archive as `restarted.json`, and prints the archive path.

Design has to close again before the next `start` can take a fresh snapshot: `start` refuses
without a current `design-closed.json`, drift or no drift. **Selective redo of one order is not
built.** A restart always starts the whole implementation stage over; say so when the person asks
for less.
