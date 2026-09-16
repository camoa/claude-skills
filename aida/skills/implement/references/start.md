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

On success the script prints summary lines. They say whether this is a new run or a resumed one.
They give the snapshot's path, hash and counts, and the ledger's path. They name which order is in
flight and at what step, what drifted since an earlier snapshot, and which work orders that halted.
Each halt has its reason. They name which orders are ready to build, what the trunk check could
establish, and `next:`. Read those lines to the person before doing anything else. The snapshot
and the ledger stay in their files; name the paths rather than opening them here.

A first run has no earlier snapshot to compare against. The `drift:` line then reads `not checked`,
never that nothing changed; those are different facts and only that line tells them apart. Say the
same to the person: nothing was compared yet, not that a check found nothing.

A resumed run that halts one or more work orders for drift is not a failure. Say plainly which
orders halted and why. A halted order stays halted until a person looks at it; nothing here
un-halts one automatically, and nothing here decides whether the drift is acceptable.

Only a started order halts for drift: one with a step reached, a frozen test record or a build
record. A drifted order that has not started is taken fresh from the live design instead, and
nothing is halted for it. Nothing was built against its old shape, so its dependents are untouched.
The `resnapshotted:` line names those orders, and the ledger records each with the two hashes.
This needs design closed on the live files; otherwise the run refuses with exit 13 and says to
close design again. The `haltedDependents:` line names only orders the ledger halts, each of which
depends on a started drifted order, directly or through another order.

A resumed run refuses two more things, before it writes. Exit 82: HEAD does not descend from the
commit the ledger started from. The branch was rewritten under the build, by a rebase or an
amend. Run `start "<task_folder>" --rebased-onto <commit>`, naming the commit the branch now
builds on. It rewrites `startedFrom` and keeps the old value in the ledger with the date. The
`startedFrom:` line then says the baseline must be retaken: move `baseline.json` and
`baseline-output` aside, then run `preconditions`. Exit 83: `baseline.json` was written by an
earlier version, in a shape this one cannot subtract from. The message names the same retake.
Neither refusal spends an attempt. The `startedFrom:` line always prints what the ledger holds,
never the current HEAD.

The `proofAbsent:` line names the orders whose frozen copy carries no `proof`, from a design
closed before the field existed. Each is proved by tests unless design sets `gate` on it. Read
the line to the person before the first order is taken, because a configuration order on it
would land on the test-author path.
