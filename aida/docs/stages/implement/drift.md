# Change the design mid-build

When design changes during a build, the next `start` compares the live design with the snapshot.
A work order not yet started takes the new design quietly. A started order whose change touches
what was built stops, and you choose: redo it against the new design, or put the design back.

Design must close again on the live files before the build takes any change. Otherwise `start`
refuses and says to close design again. A changed criterion that only stops orders is not taken,
so it needs no design close, and neither does putting its text back.

## What stops and what does not

A started order is one with a step reached, frozen tests or a build record. Only a started order
stops, except for a changed criterion, below. A dropped order is never compared. An order that has not started is taken fresh from
the live design, and the `resnapshotted:` line names it.

A started order is taken in place, and keeps its step, when it only:

- gained owned files;
- had its research findings changed, or its reasoning added to at the end;
- had its absence clauses marked reviewed by design;
- dropped an owned path that never named a file;
- gained done-when rows after its frozen rows. When its done-when row was already judged, this
  holds only at `tests-frozen`: the checker judges that row again, and the same tests freeze
  again. When it has no done-when judgement, this holds until its review, and from `reviewed` on
  it stops.

Any other change stops it: a removed owned file the code holds, a changed or removed done-when
row, a reasoning whose earlier text changed. Every order that depends on a stopped order stops too.

A changed criterion that a started order serves or owns stops every order that serves or owns it,
closed and not started included. The snapshot keeps the criterion's frozen text, because the
started orders' tests prove that text. A changed criterion that only unstarted orders serve stops
nothing, and the snapshot takes its new text. When only a criterion's verify
clause changed, an order whose frozen tests and judgements never name that criterion is spared.
The `clauseSpared:` line names it. Unattended, a clause change spares nothing without a recorded
scope decision.

An order the live design removed leaves the snapshot when it has not started. When it has started,
it stops, and you drop it. Drop it before the order that absorbed its files gets its tests: the removed order's frozen record still guards those test files. An order added to the
design enters as not started, and the `added:` line names it.

## Put the design back

A stop about an order's own design file clears itself. Put the file back to what the snapshot
holds, then run `start`. The `driftCleared:` line names each order it cleared. A stop for a changed
criterion clears the same way: put the criterion's text back word for word, then run `start`.

## Redo the order

AIDA asks you whether the new design is the one to build. Say yes, give the reason, and AIDA runs
`redo` on each stopped order. Design must have closed on the live files.

- The order's own commits are reverted, newest first, one revert commit each: its freeze, its
  build attempts and its fix rounds. No other order's commit is touched.
- Its records move to a folder named `implementation-<date>-<commit>/`, with a `redone.json` that
  holds your reason. Nothing is deleted.
- The order goes back to planned, and the snapshot takes its live copy. Every other order keeps
  what it has. The next `start` refreshes the frozen contract.
- Its tests are written again from the new design, and they fail first, because its code is gone.

When the order's records list a commit the branch no longer holds, as after a rebase, or a merge,
redo reverts nothing and says so. Revert that work yourself, then redo again. A revert that meets
a conflict is taken back, with the reverts before it.

`implementation/finished.json` stands only while every order is closed or dropped. When a change
reopens an order, `start` removes it and the `finished:` line says why.

## Why it works this way

- A build measured against an old design passes the wrong thing. The snapshot makes the change
  visible instead of building it in silence.
- An order that never depended on the change keeps its work. Only what rests on the old shape
  starts over.

Source: skills/implement/references/start.md, skills/implement/references/finish.md
