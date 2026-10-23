# Process recipes

A process recipe answers one point of the process for one framework. A stage asks for it by the
point and the framework, at the moment it needs it, never by keyword and never earlier.

## The points

| Point | Who reads it, and when |
|---|---|
| `research` | Research, at its start, before the first search |
| `design` | Design, after the research findings and before the first work order |
| `test-execution` | Implementation, once per build before any order, to learn whether the repository can run a test. Then per order, and again at review |
| `review` | Implementation, once per build for the baseline and per order for the checks. Then the review stage |
| `test-authoring` | The test author, per work order |
| `implement` | The implementer, per work order |
| `e2e-setup`, `visual-regression` | The surfaces skill, when you set a harness up |
| `worktree-environment` | The task skill, to give a task's worktree its own running site |

A role dispatched to write tests or code gets the path to its recipe and opens it itself. The test
author never sees the implement recipe, and the implementer never sees the test-authoring recipe.
Each one holds steps the other role may not take.

The worktree site is described with the task: see [the task pages](../task/README.md).

## Does the recipe fit this task

A recipe is chosen by point and framework, and neither says what the task is. So research and
design each judge the fit once, after the body is read and before their first dispatch. The answer
is `true`, `false` or `unsure`, with the path and one sentence of reason.

**At research**, on `false` or `unsure`, AIDA says the verdict and its reason. Then it asks you one
question with three answers:

- continue with the recipe;
- continue without it, which takes the no-recipe path;
- stop.

**At design**, on `false`, AIDA asks one question with four answers: continue with the recipe,
continue without it, write the recipe first, or stop.

On an autonomous run, the stage continues with the recipe and records the verdict. Review turns
each `false` into a note in its summary. A note is never a check, so a recipe that fits badly
never fails a review. It reaches the person who reads the review.

## When no recipe answers

See [When a framework has no recipe](missing-recipe.md).

## Why it works this way

- One recipe per point keeps each stage's method in one place, and a stage reads only the part it
  needs.
- A run never stops on a judgment nobody confirmed, so an autonomous run continues and leaves the
  verdict for a person.

Source: skills/research/SKILL.md, skills/design/SKILL.md, skills/implement/references/preconditions.md,
skills/review/references/checks.md, skills/review/SKILL.md, skills/surfaces/SKILL.md
