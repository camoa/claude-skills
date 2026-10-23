# Research on an autonomous or light run

Research runs almost the same way with or without a person, because it decides nothing about the
problem. When the run mode is `autonomous` or `light`, research takes a fixed answer at each point
where it would ask you. See [the task pages](../../task/) for how to set a run mode.

A mode that names stages in brackets covers research only when the list names `research`. See
[Scope on an autonomous or light run](../scope/unattended.md) for the rule.

## What changes on an autonomous run

- **A recipe that does not fit.** Research uses it anyway, and records the verdict.
- **A missing recipe.** Research records a note in the finding. It does not offer to write one.
- **A runner found for a task with no automated tests.** Research keeps the answer no, and shows
  the suite command for you to see later.
- **A split recommendation.** Research records it and goes on flat. You decide when you come back.
- **The next stage.** Research starts design itself, once, when the run mode covers design. It
  stops if design refuses.

## What a light run also changes

- **No outside search.** Research sends no searcher outside the project. It prints
  `outward-search: skipped, light run`, and logs the skip in `COMPROMISES.md` in the task folder.
  The search inside the project and the catalog lookup still run. A criterion only an outside
  search would serve gets one finding that says the search was skipped.
- **The tests answer.** When the runner check reads `met`, research changes the answer to yes
  itself. The work orders then take tests, and the skipped tests leave `COMPROMISES.md`. See
  [Check the automated tests answer](tests.md).
- **No distiller.** Research prints `distill: deferred to the design close`. The design close then
  checks all three stages at once.

## Why it works this way

- Every finding carries its source. So a wrong finding is caught the moment someone reads its
  source, and research needs no person to approve it.
- One stage can safely start the next, for the reason given on
  [Scope on an autonomous or light run](../scope/unattended.md).

Source: skills/research/SKILL.md, skills/research/scripts/research-actions.sh
