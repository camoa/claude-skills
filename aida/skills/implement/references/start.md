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

Before it writes, the script reads the task's tree. It names each file that git reports untracked
or changed and not committed, and the orders whose owned files hold it. A role stopped mid-run
leaves such files, and the next role would work beside them. A gitignored file is never named.
The usual first-run case is `package-lock.json`, changed by a surfaces harness install at `environment up`. Commit it.

Interactive, such a file refuses with exit 104, and nothing is written. Read the paths to the
person and offer two choices. To keep a file, the person commits it. Or you run start again with
`--leftovers keep` to leave it as it is, for that run only. To set the files aside, run start
again with `--leftovers set-aside`. Unattended, with no `--leftovers`, the script sets them aside
itself. In either mode, `--leftovers keep` refuses without the person's answer on record (exit 68).

Set aside moves each untracked file to `<task_folder>/implementation/set-aside/<time>/`, under its
own path. A modified file is copied there, and its committed version comes back. Nothing is
deleted. Any other change, such as a deleted file or a staged new one, refuses with exit 104 in
both modes. The ledger records each move under `setAside`. The `setAside:` line names the folder,
so give the person that path. The `leftovers:` line names each file that was kept or set aside.

Unattended, a start after a design reopen sets aside the tests an author has not frozen yet. Do
not copy them back by hand. The next fresh `dispatch-open` of a test author names the latest copy
of each test file that order owns. Put its `earlier tests:` paths in the dispatch message.

The freeze keeps its own warning about uncommitted files. It names a file that the test author
made during its own run, after this check.

On success the script prints summary lines. They say whether this is a new run or a resumed one.
They give the snapshot's path, hash and counts, and the ledger's path. They name which order is in
flight and at what step, what drifted since an earlier snapshot, and which work orders stopped.
Each stop has its reasons. They name which orders are ready to build, what the trunk check could
establish, and `next:`. Read those lines to the person before doing anything else. The snapshot
and the ledger stay in their files; name the paths rather than opening them here.

A first run has no earlier snapshot to compare against. The `drift:` line then reads `not checked`,
never that nothing changed; those are different facts and only that line tells them apart. Say the
same to the person: nothing was compared yet, not that a check found nothing.

A resumed run that finds the design changed mid-build is not a failure. Attended, each order the
change touches goes on with its frozen copy, and the `changed:` line names it. A warning goes into
the task record, naming the change, and naming any criterion no order serves now. Put each one to
the person: go on with the frozen copy, keep the change with go-on `keep`, or redo the order.
Unattended, the change stops each order it touches, and the stop allows go-on `keep` and redo. In
both modes, an order the design removed stops, and a person drops it. Say plainly which orders
changed or stopped and why. This run removes a `design drift` reason about an order's own design
file, or a criterion, once no drift is found for it. Every other reason stays until a person takes
one of the three ways out, and nothing here decides whether the change is acceptable.

The `driftCleared:` line names each order whose own design file no longer differs, and whose
drift reason this run removed. It prints only when one was removed. An order left with no other
reason is no longer stopped and resumes at its own step. An order carrying another reason stays
stopped for that one. The ledger records each clearing under `stopsCleared`, with the reasons as
they stood. Tell the person which orders cleared, and which are still stopped and why.

The `drift:` line's `contractChanged` says whether the live `alignment.json` differs from the
snapshot's copy. A changed criterion that a started order serves or owns is held. Each order that
serves or owns it stops, closed and not started included, with a reason naming the criterion. The
snapshot keeps the held criterion's frozen copy, because the started orders' tests prove that
text. So the stop clears when the live text equals it again, and review refuses the change until
then. A changed criterion that only unstarted orders serve is not held. The snapshot takes its
live text, so the tests are written from the criterion the person approved. An order serving none
of the changed criteria is untouched. Taking live text needs design closed on the live files too.

A criterion whose verify clause alone changed stops fewer orders. A started order is spared when
its frozen test record exists and names that criterion in no row. Its observed record must not
name it either, and the ledger must hold no judgement of it by that order. The briefs quoted the
old clause, but nothing frozen or judged rests on it. Review reads the clause from the refreshed
snapshot. The `clauseSpared:` line names each spared order and its criteria. When a review
already closed, that pass moves aside, the line says so, and review runs again. A clause changed
unattended spares nothing without a recorded reason: a scope decision on that criterion, added
after the snapshot.

Only a started order stops for drift: one with a step reached, a frozen test record or a build
record. A dropped order is never compared. A drifted order that has not started is taken fresh
from the live design instead, and nothing stops for it. Nothing was built against its old shape, so its dependents are untouched.
The `resnapshotted:` line names those orders, and the ledger records each with the two hashes.
A started order that only gained owned files is taken in place the same way, and nothing stops
for it. So is a started or closed order whose research findings changed through `account`. So is
one whose reasoning only grew through `update --append-reasoning`. So is one whose absence rows
design marked reviewed. Its frozen tests were written from
fields that did not change. An order already built carries the new findings only into a review it
has not had yet, never into the build it already had. So is one that dropped an owned or shared
path that names no file now and named none where the build started. Such a path never existed.
A started order whose done-when only gained rows after its frozen rows is taken in place too.
Tests are frozen against criteria, and only the done-when row reads the done-when text. When that
row was judged, the order keeps its tests only at `tests-frozen`. The judgement leaves its ledger
entry, and `doneWhenGained` lists the new rows. Its next step judges the row again and freezes
the same tests. Past `tests-frozen` it is a change mid-build, because a build already rests on
the old text. An order with no done-when row keeps its tests until review. From `reviewed` on it
is a change mid-build, because nothing would read the new row.
A removed owned file the code holds or held, or any other change, is a change mid-build, as above.
So is a reasoning whose earlier text changed, and a changed or removed done-when row. A person
keeps the change, redoes such an order once design closes on the change, or puts the design back.
An order the live design no longer holds, because design merged or removed it, has no live copy
to take. When it has not started, it is dropped from the snapshot and the ledger, and the
`removed:` line names it. That line prints only when an order was dropped. When it has started,
it stops with a reason that says the design removed it. A person drops it then. Its owned files
take no part in the build order, so the survivor that absorbed them is ready. Drop it before the
survivor's tests are written, because the removed order's frozen record still guards its test
files. The `next:` line names the drop first for that reason. Taking a live copy needs design
closed on the live files; otherwise the run refuses with exit 13 and says to close design again.
An order that depends on a changed order is not stopped. Unbuilt, `build-brief` refuses it until
the changed order closes again (exit 40). Built, review reads it.
An order the live design holds and the snapshot does not was added after the snapshot was taken.
It enters the snapshot and the ledger as not started, and the `added:` line names it. That needs
design closed on the live files too. It is ready when every order it depends on is closed.
`implementation/finished.json` stands only while every order is closed or dropped and none is
stopped. When that stops being true, the run removes the record and the `finished:` line says why.
Take `finish` again when every order is closed or dropped.

A resumed run refuses two more things, before it writes. Exit 82: HEAD does not descend from the
commit the ledger started from. The branch was rewritten under the build, by a rebase or an
amend. Run `start "<task_folder>" --rebased-onto <commit>`, naming the commit the branch now
builds on. It rewrites `startedFrom` and keeps the old value in the ledger with the date. The
`startedFrom:` line then says the baseline must be retaken: move `baseline.json` and
`baseline-output` aside, then run `preconditions`. Until then, `build-record`, `go-on`'s check,
`fix-record` and `finish` refuse with exit 21. The same flag takes a branch moved forward onto a
later commit, such as a trunk fix. The flag refuses if a commit between the two starts is on no
other branch, or if an order has committed. Exit 3: `baseline.json` was written by an
earlier version, in a shape this one cannot subtract from. The message names the same retake.
Neither refusal spends an attempt. The `startedFrom:` line always prints what the ledger holds,
never the current HEAD.

The `proofAbsent:` line names the orders whose frozen copy carries no `proof`, from a design
closed before the field existed. Each is proved by tests unless design sets `gate` on it. Read
the line to the person before the first order is taken, because a configuration order on it
would land on the test-author path.
