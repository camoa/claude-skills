# Come back to a build

Type `/aida:implement <task-id>` again. The build always resumes at `start`, which checks for
changes since the snapshot, then reports where each work order stands and goes on with the next.

## What to read first

The ledger, `implementation/ledger.json` in the task folder, is the state of the build. It holds
each order's step, its stop reasons, its attempts and rounds, each row with who judged it, and the
commit range of each order. It survives a compaction. After an unattended run, read the stops and
the rows a model judged, to decide where to look.

`start` names the orders in flight, the stopped orders with their reasons, and the ready orders.
When a stopped role left files nobody committed, it lists them first. See [Start the
build](start.md).

## A branch rebased under the build

When the branch was rewritten, by a rebase or an amend, `start` refuses. The commit the ledger
started from is no longer under HEAD. To go on:

1. Run `start` again with `--rebased-onto <commit>`, naming the commit the branch now builds on.
   The ledger keeps the old value with the date.
2. Move `implementation/baseline.json` and `implementation/baseline-output/` aside.
3. Run `preconditions` again, to retake the baseline.

Until the baseline is retaken, recording an attempt, a re-check, a fix round and finish all
refuse. The same flag takes a branch moved forward onto a later commit, such as a trunk fix. It
refuses when a commit between the two is on no other branch, or when an order has already
committed. A baseline written by an earlier version of AIDA refuses too, and the message names the
same retake. Neither refusal spends an attempt.

## Trunk merged into the build

You can merge trunk into the task's branch while orders are open. Nothing is recorded, and no
flag is needed. Every check reads git again:

- A commit that the upstream of the task's base holds is trunk's. The upstream is your remote's
  copy, such as `origin/main`. Those commits are set aside, and no order is judged on them.
- A merge commit is judged on its own edits: a conflict it resolved, a hand edit, or a side it
  dropped. An edit to any order's file is set aside too. One warning names each merge, its own
  edits, and the order that owns each file.
- A merge's own edit to a file no order owns stops the order, with exit 63. Go on with `--owns`
  naming the file, or redo or drop the order.
- A stopped order keeps the merge on its commit list, so its edit stays judged. Redo and drop then
  ask you to revert the merge with `git revert -m 1`. That revert also takes out trunk's changes,
  so `--owns` is the cheaper way out where the stop allows it.
- A change to a frozen test stops the order, whether trunk or the merge made it. Redo the order,
  or drop it.

A base with no upstream sets nothing aside, so every trunk commit stops the order as a file it
does not own. Push trunk first, or fetch it, so the remote's copy holds it. A commit on your local
trunk alone is judged as an order's commit.

The baseline is not retaken. At finish, a test trunk brought that fails stops the task, like any
test that did not fail in the baseline. Record it with `finish --regression` when this task did
not cause it.

## A role that never returned

Each task has at most one open dispatch. When a role never returned, the next dispatch refuses and
names the role, the order, and the record's age. A role stopped at its turn limit is resumed once,
or twice for an order with a large diff budget. One more stop writes a turn-cap warning into the
task record, and the role is sent again. A builder's cap spends a build attempt. Any other role's
caps are counted, and the cap that reaches the order's attempt limit stops the order. The role's
commits stay on the order's list, unless one breaks the frozen tests or the owned files, which
stops the order.

## Your answer to a person's call

A person's call, such as a way out of a stop, a ruling, a file you allow, or accepted warnings,
refuses until your answer is on record, in every run mode. Claude Code shows you a permission
prompt, and your yes records the answer in `person-answers.json` in the task folder. The call
passes only on an unused answer for this step, this order and your exact words, and marks it used.
A call that refuses for another reason marks the answer refused, so the next attempt asks again.
See [the person's answer](../../task/person-answer.md).

## A permission prompt partway through

The tool grants a skill holds last one turn. So the same command may ask for permission again
after AIDA asks you something. That is how skill grants work, not a fault in the build.

## Why it works this way

- The ledger is state, not a log. A new session reads one file and knows where the build stands.
- A rebased branch moves the commit the baseline was taken at. Subtracting the old baseline would
  read the new start's failures as the build's own.

Source: skills/implement/SKILL.md, skills/implement/references/start.md, skills/implement/references/finish.md
