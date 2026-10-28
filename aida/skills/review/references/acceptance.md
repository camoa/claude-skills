# Run the surfaces, and verify the task by running it

This step answers checks 13 to 15: end to end, visual regression and visual parity. A script runs
what the recipe declares. Then the acceptance verifier, which did not build the task, runs the real
product and records what it saw. The review record keeps both. Nothing here writes code.

## They run only when they are set up

The project record carries one field, `surfaces`, with `e2e.enabled` and `visualRegression.enabled`.
Review runs nothing that is off. `surfaces.registryPath` is the only pointer at the surface file,
and **one surface file serves all three kinds**, so read that field whichever kind is on. The
`surfaces` skill writes the field and the file.

The surface block comes from the `review` recipe the `checks` step already resolved. The script reads
the path the record holds, so this step resolves no recipe and runs no lookup.

## Offer the setup once

Offer setup for each kind that is off, not declined, and carries surface rows in the recipe. A kind
marked on whose surface file is missing counts as off when a person is present. Name every such
kind on its own, and take an answer per kind. The two are separate capabilities, so a person may
take one and refuse the other.

When another branch holds the surface file, offer no setup, because it would collide with that
file. Do not tell the person to merge that branch. It is often another task's unfinished work, and
a merge puts that work into this task. A kind marked on reads as off here, in both run modes. The
file reaches this task once that branch lands on the trunk. Name the branch, and say that. If that
branch is abandoned, deleting it, local and remote, brings the offer back.

Ask once per kind, with a recommended answer per kind. Give three answers per kind: yes, not this
task, or no. Say the difference between "not this task" and "no" in the ask itself, so the person
knows what a "no" silences. A yes on a kind invokes the `surfaces` skill through the Skill tool,
naming that kind. "Not this task" on a kind runs
`"${CLAUDE_PLUGIN_ROOT}"/skills/task/scripts/task-actions.sh defer-surface --project "<projectPath>" <task-id> <e2e|visual-regression>`.
No later stage or review pass of this task then asks again, and the next task may ask. A kind that
scope or design deferred is not offered here either.
A no on a kind runs `decline <kind>`, project-wide, and that kind is never asked again. An offer
repeated every task is a nag, and a nag gets clicked through. Autonomous, the offer is not made,
and the record says it was not offered.

## Run them

A light task runs no visual regression. Its check reads undeclared and names the light run, and
implementation's start logged the skip. End to end runs as usual, including the one script that
walks the demo path when it is registered. A missing script is not a failure: the check reads
undeclared, and the verifier's evidence is the light task's acceptance.

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/review/scripts/review-actions.sh acceptance "<task_folder>"
```
It runs every row the surface block declares, and it records checks 13 to 15 and one row per
registered surface, with the verdict and whether it ran. It prints one summary line per surface. A
harness's own output stays in the record, per SKILL.md. When the task record has
`environment.address`, pass it as `--value base-url=<address>` and do not ask for one.

**Review narrows by the paths each surface declares.** A surface runs when the diff touched one of
its paths. A critical surface always runs. A surface with no declared paths always runs. The rest
are recorded as not run, and the check's detail names them. A kind whose surfaces were all
unaffected reads met: no run was asked for, which is not a run that selected nothing. A recipe
row without a `{surfaces}` token cannot be narrowed, so the whole set runs and the detail says
so.

**Zero tests ran is never a pass.** A run that selected nothing reads unknown. A registry surface
with no result reads unmet, because a check that cannot notice its subject going absent cannot inform.

**Every command waits for the recipe.** Until the surface block lands in the `review` recipe, the
script records checks 13 to 15 as undeclared and says why. **Visual parity gets no more than that**:
it has no recipe, no field and no harness, and version 6 records it as unavailable. Say that plainly
rather than reporting parity as a check that passed.

## Dispatch the acceptance verifier

Dispatch `aida:acceptance-verifier`, in both run modes. The message is one line per item:

- the run mode
- `<task_folder>/implementation/snapshot.json`
- `<task_folder>/implementation/finished.json`
- `<task_folder>/review/review.json`
- the surface file the summary's `surface-file:` line names, or `none`
- the task record's `environment.address`, or `none`
- `<task_folder>/records/evidence.json`

It runs a smoke test and the examples, explores with a one-line charter, and writes one evidence
row per criterion and per changed surface at each viewport. It looks at every page surface that
ran, **including the ones that passed**. Version 5 measured why: an aggregate moved from 37 percent
to 28 percent while six visible defects sat inside the passing surfaces.

Then record its rows:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/review/scripts/review-actions.sh acceptance "<task_folder>" --evidence
```
It runs the surfaces again and writes the rows into the review record. The evidence file stays
under `records/`, which git ignores. The screenshots stay under `review/evidence/`, where git keeps
text and no image. It refuses at exit 52 when a row is not an
evidence row, names a criterion, surface or viewport this task does not hold, or names a file not on
disk, and when a criterion has no row. Give the refusal to the verifier's next dispatch.

**A page surface with no row at every viewport reads unknown.** The look is half the answer. A
command surface needs no look, because its exit status is the whole answer.

**The verifier's `unmet` decides nothing alone.** A surface check whose run passed, with a row the
verifier did not judge met, waits for the person at close. A criterion's rows are shown beside it
at close. A bug the verifier names reaches the person in its row's note. The person answers that
criterion or check unmet, and the review fails on it.

The verifier may propose a surface, or an extension of the demo-path script, in a note. It never
writes one. Read each such note to the person, who adds it with `/aida:surfaces register`.

## A new baseline is accepted in two stages

Plan it, show the person the surfaces and the viewports it would replace, and take their yes. Then
write it:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/review/scripts/review-actions.sh acceptance "<task_folder>" \
  --accept-baseline <surface id>
```
This runs the accept row the surface block declares for that kind. It refuses when the block declares
none, because there is then no command that writes a baseline. Never write one automatically, and
never unattended. The call refuses on an autonomous run too, and the refusal is recorded. It keeps
the evidence rows the record already holds.
