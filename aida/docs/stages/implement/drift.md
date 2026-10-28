# Change the design mid-build

When design changes during a build, the next `start` compares the live design with the snapshot.
A work order not yet started takes the new design quietly. A started order whose change touches
what was built is a change mid-build. With you present, AIDA writes a warning into the task
record and the order goes on with its frozen copy. You choose: go on as it is, keep the new
design, redo the order against it, or put the design back. With nobody present, the change stops
the order, and a person makes the same choice later.

Design must close again on the live files before the build takes any change. Otherwise `start`
refuses and says to close design again. A changed criterion that only touches started orders is
not taken, so it needs no design close, and neither does putting its text back.

## What is a change mid-build

A started order is one with a step reached, frozen tests or a build record. Only a started order
is touched, except for a changed criterion, below. A dropped order is never compared. An order that has not started is taken fresh from
the live design, and the `resnapshotted:` line names it.

A started order is taken in place, and keeps its step, when it only:

- gained owned files;
- had its research findings changed, or its reasoning added to at the end;
- had its absence clauses marked reviewed by design;
- dropped an owned path that never named a file;
- gained done-when rows after its frozen rows. When its done-when row was already judged, this
  holds only at `tests-frozen`: the checker judges that row again, and the same tests freeze
  again. When it has no done-when judgement, this holds until its review, and from `reviewed` on
  it is a change mid-build.

Any other change is a change mid-build: a removed owned file the code holds, a changed or removed
done-when row, a reasoning whose earlier text changed. An order that depends on a changed order
goes on. Until the changed order closes again, it cannot start.

A changed criterion that a started order serves or owns touches every order that serves or owns
it, closed and not started included. The snapshot keeps the criterion's frozen text, because the
started orders' tests prove that text. A changed criterion that only unstarted orders serve
touches nothing, and the snapshot takes its new text. When only a criterion's verify
clause changed, an order whose frozen tests and judgements never name that criterion is spared.
The `clauseSpared:` line names it. Unattended, a clause change spares nothing without a recorded
scope decision.

The warning also names any criterion that no order serves now, because no build would answer it.

An order the live design removed leaves the snapshot when it has not started. When it has started,
it stops in both run modes, and you drop it. Drop it before the order that absorbed its files gets its tests: the removed order's frozen record still guards those test files. An order added to the
design enters as not started, and the `added:` line names it.

## Put the design back

A change to an order's own design file clears itself. Put the file back to what the snapshot
holds, then run `start`. The `driftCleared:` line names each order whose stop it cleared. A changed
criterion clears the same way: put the criterion's text back word for word, then run `start`.

## Keep the new design

A change to an order's own design file, or to a criterion it serves, can be kept. AIDA asks you
whether the order goes on as it stands. Say yes, give the reason, and AIDA goes on with `keep`.
Design must have closed on the live files. For a design file, the snapshot takes the order's live
copy. For a criterion, the order keeps its tests on the frozen text, and review judges against
it. Nothing is reverted, the order goes on from its own step, and the same change is not raised
again. An order the design removed has no keep: drop it.

## Redo the order

AIDA asks you whether the new design is the one to build. Say yes, give the reason, and AIDA runs
`redo` on each order the change touches. Design must have closed on the live files.

- The order's own commits are reverted, newest first, one revert commit each: its freeze, its
  build attempts and its fix rounds. No other order's commit is touched.
- Its records move to a folder named `implementation-<date>-<commit>/`, with a `redone.json` that
  holds your reason. Nothing is deleted.
- The order goes back to planned, and the snapshot takes its live copy. Every other order keeps
  what it has. The next `start` refreshes the frozen contract.
- Its tests are written again from the new design, and they fail first, because its code is gone.

When the order's records list a commit the branch no longer holds, as after a rebase, redo skips
it and lists it under `skipped`. It skips a commit the branch already reverts the same way. A merge
commit refuses: revert it with `git revert -m 1`, then redo again. A revert that meets
a conflict is taken back, with the reverts before it.

`implementation/finished.json` stands only while every order is closed or dropped, and none is
stopped. When a change stops an order, `start` removes it and the `finished:` line says why.

## Why it works this way

- A build measured against an old design passes the wrong thing. The snapshot makes the change
  visible instead of building it in silence.
- An order that never depended on the change keeps its work. Only what rests on the old shape
  starts over.

Source: skills/implement/references/start.md, skills/implement/references/finish.md
