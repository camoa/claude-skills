# Check the preconditions

The build has started. Now find out whether this repository can run a test at all. This step runs
once per build, not once per work order.

## Resolve one recipe per framework

Read the project's own `frameworks`. For each one, dispatch `catalog-identifier` to ask the
navigator's process-recipe lookup for the `test-execution` point and that framework. It answers
whether one is available and, when it is, a path to the body on disk.

**Name the role.** A dispatch that names none runs as the general agent, with every tool and this
session's own model. The role exists so a catalog listing lands in the agent and not here: it
identifies and returns a path, and it never opens the body. Never fetch a catalog address yourself
and never read a cached copy behind the navigator's back. A source this project configured itself,
a folder of its own, is read the ordinary way and wins over the catalog.

**Three answers, not one.** No recipe for this framework, a listing that could not be reached, and
a failed network are three different things, and only the first says anything about the framework.
Pass the one that happened, in its own word.

## Run the checks

Run, with one flag per framework:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh preconditions "<task_folder>" \
  --recipe <framework>=<path to the recipe body> \
  --lookup-failed <framework>=<no-recipe|listing-unreachable|fetch-failed>
```
Every framework the project declares needs one flag or the other. The script refuses rather than
guess, because a lookup nobody ran must never be recorded as a recipe that declared nothing.

The script reads each recipe's declared conditions, runs each check inside the code repository,
and writes what it found. It never hands a check to a shell.

## Supply a value where a command needs one

A framework's cheapest test command may carry a placeholder, such as the runner a Python project
declares. Pass it with `--value <name>=<value>`. The script never guesses one and never reads a
default out of a recipe's prose: an unsupplied placeholder makes the run undecidable and names
which one had no value.

## Read the four verdicts to the person

- **met.** Every declared condition answered yes. The build can go on.
- **unmet.** A condition answered no. Name it, name the framework, and name the owner the recipe
  gave. An owner is the action; without one the person has to work out what to do.
- **unknown.** Nobody could tell. A checker that is not installed says nothing about the condition
  it was meant to probe, so this is never reported as a failure of the condition.
- **undeclared.** The recipe named no conditions. Say that, and never say met. A recipe that
  declared nothing was not checked.

`met` and `undeclared` both continue. A recipe saying this framework needs nothing before a test
runs has answered, and stopping on it would mean no project on that framework ever builds. Say
which of the two happened; never report `undeclared` as conditions that passed.

`unmet` and `unknown` stop, and the person decides. In an unattended run they halt. Nothing here
judges an unmet condition acceptable.

Say which frameworks were answered from a recipe and which were not. A framework whose recipe could
not be reached was not checked, and reporting the run as clean would be false.

## The smoke run and the baseline

After the conditions, the step runs each framework's cheapest test command, the one that proves the
harness reports at all. It runs only where that framework's conditions came back satisfied or
undeclared, because running it after a condition answered no would fail for a reason already known.
Its result folds into the same verdict, and where it did not succeed the record keeps what the
command printed.

Last, it records what was already broken at the commit the build started from. The suite runs
whole, because the orders' tests do not exist yet and no framework maps changed paths to the tests
covering them. The three tools that take paths have no recipe naming them at this point, so each
records that none is declared. A suite that is already red is recorded, never refused: knowing it
is the point, because a builder chasing a failure it did not cause spends every attempt it has.

The baseline is taken once, at that commit. A second run at the same commit leaves it alone. One
recorded at a different commit refuses rather than overwrites, and names both commits.
