# Start the build

The first step freezes the contract and the work orders into a snapshot and opens the ledger. It
runs every time you type `/aida:implement`, on a new build and on a resumed one.

## What it checks before it writes

- The contract exists, and design closed cleanly. `design-closed.json` must exist, and its hash
  must match the live contract and work orders. Missing means design never closed. A different
  hash means something changed after the close. Close design again in both cases.
- The project is a git repository.
- The code checkout is on a named branch. A detached HEAD always refuses.
- The build would not land on the repository's own trunk branch.

Each refusal writes nothing and names what to fix. See [When it stops](../../when-it-stops/).

When the trunk cannot be found, because there is no `origin` remote or its head is unset, start
goes on. It tells you the trunk was not confirmed. That is a check that could not look, not a pass.

## Files nobody committed

Start lists each file git reports untracked or changed, and the work order that owns it. A
gitignored file is never listed. A role stopped mid-run leaves such files, and the next role
would work beside them.

Start sets such files aside itself, in both run modes, and writes a warning naming them. To keep a
file, commit it before start. Or run start with `--leftovers keep`, and the files stay as they
are, for that run only. Keeping needs your answer on record.

Set aside moves each untracked file to `implementation/set-aside/<time>/` in the task folder. A
changed file is copied there, and its committed version comes back. Nothing is deleted. A deleted
file or a staged new file cannot be set aside, so it stays in the tree, and a warning names it.
Commit it or undo it by hand.

The usual first-run case is `package-lock.json`, changed when `task environment up` installed a
test harness. Commit it.

Unattended, a start after a design reopen also sets aside tests that were not frozen yet. The
next test author is told where the latest copy of each one is.

## What it tells you

Start prints one line per fact. It says whether this is a new run or a resumed one, and gives
the snapshot and ledger paths. It names the order in flight, the orders ready to build, and each
stopped order with its reasons. It ends with `next:`, the step that comes after.

- `drift: not checked` on a first run means nothing was compared yet. It does not mean nothing
  changed.
- `proofAbsent:` names orders from a design closed before work orders had a proof kind. Each is
  proved by tests unless design sets `gate` on it. A configuration order on that line would go to
  a test author, so check it before the first order.

What a resumed run reports about a changed design is in [Change the design
mid-build](drift.md). A rewritten branch is in [Come back to a build](resume.md).

## Why it works this way

- The snapshot is taken here and not at design close. A person can close design and then edit an
  order. The build reads the snapshot, so that edit is noticed instead of built in silence.
- A commit on the trunk or on a detached HEAD is hard to take back. Start refuses before any
  role can make one.
- Leftover files are named, never deleted. Only you know whether a stopped role's work is wanted.

Source: skills/implement/SKILL.md, skills/implement/references/start.md
