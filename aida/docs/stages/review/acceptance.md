# Verify the task by running it

The third step of review is the acceptance step. It runs the registered surfaces, then a verifier
runs the real product and records what it saw. You answer each criterion at the close, with that
evidence beside it. Nothing in this step writes code.

## What runs

1. **The surfaces.** Review runs the end to end and visual regression harnesses when the project
   has them on. A light project's one script that walks the demo path runs here when it is
   registered. Which surfaces run, a new baseline and a light task are on
   [surfaces at review](../../sources/surfaces-at-review.md).
2. **The acceptance verifier.** It is a separate role. It did not build the task, it writes no
   code and no test, and it runs on the top model. It reads the frozen contract, the finish
   record, the surface runs, the surface file and the task's site address.

The verifier does four things:

- It reads the surface runs. It does not run them again.
- It runs a smoke test, and the examples the criteria and the docs give.
- It explores with a one-line charter: the target, the resources, and the information it seeks.
- It writes one evidence row per criterion, and one per changed surface at each viewport.

## The evidence

Each row holds the sentence, the surface and viewport where one applies, the screenshot or output
path, the verdict and a note. The verdict is `met`, `unmet` or `unknown`. The rows go into the
review record, beside the surface runs. Screenshots stay under `review/evidence/` in the task
folder. Git keeps no image there, because the project folder holds text only.

A criterion a machine verifies needs nothing run again. Its row cites the suite result that
finish recorded.

A page surface with no row at every viewport reads `unknown`. A command surface needs no look,
because its exit status is the whole answer.

## What a verifier's unmet does

The verifier's `unmet` decides nothing alone. It waits for you at the close:

- **On a surface whose run passed**, the check waits for your met or unmet, from the evidence.
- **On a criterion**, the row is shown beside the criterion, and you answer it.
- **A row that names the code file of a bug** becomes a finding, which fails that criterion. You
  rule it at the close like any finding. Unruled, the review fails, and the build's `reopen` sends
  it to the order that owns the file.

## A surface the verifier proposes

The verifier may propose a new surface, or an extension of the demo-path script, in a note. It
never writes one. Review reads each note to you. You add the surface with `/aida:surfaces
register`, which asks why. See [set up the surfaces](../../sources/surfaces-setup.md).

## Why it works this way

- A role that did not build the task cannot take a builder's claim as evidence. It runs the
  product and keeps what it saw.
- A passing surface can still look wrong. So the verifier looks at every page surface that ran,
  including the ones that passed.
- A model's verdict is not a person's. So every `unmet` waits for your answer, and evidence, not
  code, is what the step leaves behind.

Source: skills/review/references/acceptance.md, agents/acceptance-verifier.md, skills/review/SKILL.md
