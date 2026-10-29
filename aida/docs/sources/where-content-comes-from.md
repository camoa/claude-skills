# Where content comes from

AIDA reads three kinds of document: guides, recipes and playbooks. Recipes come in three classes:
process, tooling and agentic. All of them come from the hosted catalog at
`camoa.github.io/dev-guides`, or from folders your project declares first.

The plugin ships no recipe of its own. To support a new stack, you write a recipe. You never edit
AIDA.

## The kinds, and the three classes of recipe

| Kind | What it is | Who reads it |
|---|---|---|
| Guide | One pattern or one mechanic, such as how a Drupal form checks its input | Design, then the reviewer |
| Process recipe | The framework's method at one point of the process | The stage at that point, or its role |
| Tooling recipe | One tool for one framework: install it and run it | The tool skill |
| Agentic recipe | One whole capability, decided end to end | Design, which follows it |
| Playbook | Rules a person wants followed, with the reason | Every role that writes or judges code |

A guide is read for its patterns. It is never followed as a list of steps. A recipe is data that a
stage resolves for the project's framework. A playbook holds plays: do it this way, not that way.

## The catalog

Every catalog read goes through the `dev-guides-navigator` plugin. Install it, or no catalog
lookup runs. AIDA never fetches a catalog address itself.

The navigator keeps each body it fetches in a store on disk, under `~/.claude/dev-guides-store/`.
One machine fetches a guide once, across all projects. A lookup answers with a path, and the
stage reads the file. So a long recipe never enters the conversation that runs the build.

## A recipe is data, not commands

A stage's script reads the command blocks of a recipe itself. It runs each command as a list of
arguments, never through a shell. It does not run a command that carries a shell character: the
record names it unknown, and a warning says so. The model never retypes a command out of a recipe.

## A failed lookup has three answers

- `no-recipe`: the catalog holds no recipe for this point and framework.
- `listing-unreachable`: the catalog's index could not be fetched.
- `fetch-failed`: an entry matched, and its body did not arrive.

Only `no-recipe` is a fact about the framework. Each stage records which answer came back. What
it then does depends on the point: see [When a framework has no recipe](missing-recipe.md).

## Why it works this way

- Knowledge of a stack changes faster than a process. Keeping it in documents lets one person fix
  a recipe for every project.
- A network failure written down as "no recipe" is a false finding that nothing later can tell
  from a true one.
- A command run as arguments cannot chain a second command, and a model that never retypes it
  cannot drop a key.

Source: skills/research/SKILL.md, skills/design/SKILL.md, skills/tool/SKILL.md,
skills/tool/references/reading-a-recipe.md
