# Start the build

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh start "<task_folder>"
```

This is the whole first step. It checks, in order: the task folder and its contract, that design
closed cleanly, that the task's project is a git repository, that codePath is on a named branch,
and that the build would not land on that repository's own trunk branch. Any one of these refuses
before anything is written, and the message names what to fix. Read a refusal and act on it; do
not repeat the same call unchanged.

A first run also checks that design has formally closed: <task_folder>/design-closed.json must
exist and its recorded hash must agree with a hash re-derived from the live contract and work
orders. Missing means design has never closed; run the design skill's close action. A disagreeing
hash means design closed once and something changed since, without closing again; close design
again. Both are refusals, and both leave nothing written.

A detached HEAD in codePath refuses outright, whether or not the trunk branch can even be derived.
A commit made there belongs to no branch, which this build must never risk.

When the trunk branch cannot be derived, because there is no `origin` remote or its head is
unset, the script says so and continues. That is a check that could not look, not a pass and not
a refusal. Tell the person plainly that the trunk was not confirmed, rather than reporting it as
either.

On success the script prints one report: whether this is a new run or a resumed one, the frozen
snapshot's own counts, which order is in flight and at what step, what drifted since an earlier
snapshot and which work orders that halted, which orders are ready to build, and what the trunk
check could establish. Read the whole report to the person before doing anything else.

A first run has no earlier snapshot to compare against. The report says the drift check did not
apply, never that nothing changed; those are different facts and only the report's own `checked`
field tells them apart. Say the same to the person: nothing was compared yet, not that a check
found nothing.

A resumed run that halts one or more work orders for drift is not a failure. Say plainly which
orders halted and why. A halted order stays halted until a person looks at it; nothing here
un-halts one automatically, and nothing here decides whether the drift is acceptable.
