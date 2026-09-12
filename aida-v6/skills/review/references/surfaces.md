# Run the surfaces, and walk them

This step answers checks 13 to 15: end to end, visual regression and visual parity. A script runs
what the recipe declares. A person looks at every surface. Both halves are recorded.

## They run only when they are set up

The project record carries `visualRegression` and `e2e`, each with an `enabled` flag. Review runs
nothing that is off. `visualRegression.registryPath` is the only pointer at the registry, and **one
registry serves all three kinds**, so read that field whichever kind is on. A project with end to end
alone has no pointer, and that is recorded in `deferred-changes.md` rather than worked around here.

The surface block comes from the `review` recipe the `checks` step already resolved. The script reads
the path the record holds, so this step resolves no recipe and runs no lookup.

## Offer the setup once

Offer setup when the framework's recipe carries surface rows that are not absent, and the project has
no registry. Rows that are not absent are how review knows the framework has surfaces at all.

Ask once. A recorded refusal is never asked again, because an offer repeated every task is a nag, and
a nag gets clicked through. Autonomous, the offer is not made, and the record says it was not offered.

## Run them

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/review/scripts/review-actions.sh surfaces "<task_folder>"
```
It runs every row the surface block declares, and it records checks 13 to 15 and one row per
registered surface, with the verdict and whether it ran.

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
