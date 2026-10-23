# The process recipe at research

Research looks up one process recipe for each of the project's frameworks, before the first
search. The recipe says where the project's own code lives and how to judge whether a candidate is
safe to depend on.

## Where the recipe comes from

A folder of recipes that the project declared answers first. When no folder holds one, the catalog
answers. See [the sources pages](../../sources/) for both.

## Does it fit

Research reads the recipe and judges once whether it describes the work that the criteria and
non-goals name. The verdict is fits, does not fit, or not sure. When it does not fit, or research
is not sure, research tells you why. It asks one question: go on with the recipe, go on without
it, or stop.

## When there is no recipe

Research records that the recipe is missing, and falls back:

- Outside the project, it applies the plain three-part test: maintained, used, supported.
- Inside the project, it searches from the project root. The finding says that the bound on the
  project's own code was not enforced. Research never guesses a framework's folder layout.

Research then asks whether to write a recipe with you. The answers are three:

- **Write one now.** Research works from a template that holds the sections the catalog requires.
- **Not now.** Research records nothing, so it asks again next time.
- **Not for this framework.** Research records this on the task. Neither research nor design asks
  again for that framework on this task.

A recipe that does not exist, a listing that could not be reached and a network that failed are
three different findings. Research records which one happened, in those words.

## Why it works this way

- Where a project's own code lives is a framework convention. So it comes from a recipe, not from
  a guess.
- Only a recipe that does not exist says something about your framework. A false "no recipe" can
  never be told apart from a true one afterwards.

Source: skills/research/SKILL.md, skills/project/scripts/project-actions.sh, skills/task/scripts/task-actions.sh, templates/process-recipe-research.md
