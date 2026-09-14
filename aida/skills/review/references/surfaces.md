# Run the surfaces, and walk them

This step answers checks 13 to 15: end to end, visual regression and visual parity. A script runs
what the recipe declares. A person looks at every surface. Both halves are recorded.

## They run only when they are set up

The project record carries one field, `surfaces`, with `e2e.enabled` and `visualRegression.enabled`.
Review runs nothing that is off. `surfaces.registryPath` is the only pointer at the surface file,
and **one surface file serves all three kinds**, so read that field whichever kind is on. The
`surfaces` skill writes the field and the file.

The surface block comes from the `review` recipe the `checks` step already resolved. The script reads
the path the record holds, so this step resolves no recipe and runs no lookup.

## Offer the setup once

Offer setup for each kind that is off, not declined, and carries surface rows in the recipe. Name
every such kind on its own, and take an answer per kind. The two are separate capabilities, so a
person may take one and refuse the other.

Ask once per kind. A yes on a kind invokes the `surfaces` skill through the Skill tool, naming that
kind. A no on a kind runs `decline <kind>`, and that kind is never asked again. An offer repeated
every task is a nag, and a nag gets clicked through. Autonomous, the offer is not made, and the
record says it was not offered.

## Run them

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/review/scripts/review-actions.sh surfaces "<task_folder>"
```
It runs every row the surface block declares, and it records checks 13 to 15 and one row per
registered surface, with the verdict and whether it ran. It prints one summary line per surface. A
harness's own output stays in the record, per SKILL.md.

**Review narrows by the paths each surface declares.** A surface runs when the diff touched one of
its paths. A critical surface always runs. A surface with no declared paths always runs. The rest
are recorded as not run, and the check's detail names them. A recipe row without a `{surfaces}`
token cannot be narrowed, so the whole set runs and the detail says so.

**Zero tests ran is never a pass.** A run that selected nothing reads unknown. A registry surface
with no result reads unmet, because a gate that cannot notice its subject going absent cannot inform.

**Every command waits for the recipe.** Until the surface block lands in the `review` recipe, the
script records checks 13 to 15 as undeclared and says why. **Visual parity gets no more than that**:
it has no recipe, no field and no harness, and version 6 records it as unavailable. Say that plainly
rather than reporting parity as a check that passed.

## The walk is the person's

Put every surface to the person, at every viewport, **including the ones that passed**. Version 5
measured why: an aggregate moved from 37 percent to 28 percent while six visible defects sat inside
the passing surfaces.

Record the walk with one flag per surface the person looked at:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/review/scripts/review-actions.sh surfaces "<task_folder>" \
  --walked <surface id>
```
Autonomous, there is nobody to look. The walk is recorded as not done, and checks 13 to 15 read
unknown. Do not stand a script's own result in for the walk, per SKILL.md.

## A new baseline is accepted in two stages

Plan it, show the person the surfaces and the viewports it would replace, and take their yes. Then
write it:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/review/scripts/review-actions.sh surfaces "<task_folder>" \
  --accept-baseline <surface id>
```
This runs the accept row the surface block declares for that kind. It refuses when the block declares
none, because there is then no command that writes a baseline. Never write one automatically, and
never unattended. The call refuses on an autonomous run too, and the refusal is recorded.
