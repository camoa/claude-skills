# Approve the contract

You approve the contract yourself. Scope never asks for a yes. When the contract is right, run
`/aida:scope approve <task-id>`, or say that it is right in your own words.

## What approval does

1. Scope sends a fresh reader, the distiller, over the written contract. The distiller did not see
   your conversation. It reads the contract and the task files from disk.
2. Scope then runs the approve action. Every criterion still marked `designer` becomes `owner`.
   Any decision an unattended run took is marked as approved by you, with the date.
3. The action commits the task folder.
4. Scope shows what the distiller found: whether the contract stands alone, and one line per gap.

That moment is the approval, and there is no other. A yes on the draft alone promotes nothing.

## The gaps

A contract stands alone when a fresh reader can use it without the conversation that produced it.
Each gap names what is missing and where it belongs. A gap never blocks. To act on one, correct the
contract, then approve again.

When the contract changed after the distiller read it, scope says that the answer is stale. It
shows no old gaps and sends the distiller again.

## Approve a second time

You can approve again at any time. When nothing is left to promote, scope prints
`ALREADY APPROVED`. This is not a fault. The action still commits any later edit and reads the
distiller's answer again.

## What comes next

Scope names the next command, `/aida:research <task-id>`, and stops. It does not start research
for you, unless the task's run mode covers research. See
[Scope on an autonomous or light run](unattended.md).

If you stop before you approve, the draft stays on disk, marked `designer`, and is not committed.
Research can still run on it. It lists the criteria that no person approved, so an unfinished
contract is yours to notice.

The distiller can fail: it writes nothing, or it writes a record in the wrong shape. Scope tries
again, and stops for you when it cannot recover. See [When a stage stops](../../when-it-stops/).

## Why it works this way

- Approval is an action you take, so scope cannot ask for it again and again.
- The distiller never saw the conversation. A record checked against its author's own account of
  it is not checked.

Source: skills/scope/SKILL.md, skills/scope/scripts/scope-actions.sh, agents/distiller.md
