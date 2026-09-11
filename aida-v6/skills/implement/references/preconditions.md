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

Dispatch `catalog-identifier` once more, for the `review` point and each framework. When that
recipe carries a `check_commands` data block, it names three tool commands, coding-standards,
static-analysis and security. Each is an argv per tool, with `{paths}` as a placeholder. Each
row also carries its own `signal` and `extensions` keys, where present.

When the recipe carries no such block, pass no tool flag for it. The three checks then record
undeclared, and the report says the recipe declares no tool for that check. Never read a tool's
name out of the recipe's own prose.

## Run the checks

Run, with one flag per framework:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh preconditions "<task_folder>" \
  --recipe <framework>=<path to the recipe body> \
  --lookup-failed <framework>=<no-recipe|listing-unreachable|fetch-failed> \
  --standards <argv token>... \
  --static-analysis <argv token>... \
  --security <argv token>... \
  [--standards-signal empty-stdout] [--standards-extensions <comma list>] \
  [--static-analysis-signal empty-stdout] [--static-analysis-extensions <comma list>] \
  [--security-signal empty-stdout] [--security-extensions <comma list>] \
  [--standards-absent <reason>] [--static-analysis-absent <reason>] [--security-absent <reason>]
```
`--standards`, `--static-analysis` and `--security` are each tool's own argv, one token per
repeated flag, from the `review` recipe resolved above. A token that is exactly `{paths}` is a
placeholder. The script expands it itself, to the union of every work order's own owned files, one
argv token per file, relative to codePath. The orders' tests do not exist yet at this step, so this
is the baseline every later check compares against. Never expand `{paths}` here, and never hand any
of the three to a shell. Absent, a tool stays undeclared, the same as `preconditions.json`'s own
fields already do.

Each tool takes its `signal` and `extensions` keys the same way, straight from its `check_commands`
row. Pass `--standards-signal empty-stdout` (and the same for the other two) only when the recipe
names that signal. It marks a tool that exits 0 whether it found something or not. A clean run and
a dirty one are then told apart by whether anything landed on standard output, not by the exit code.

Pass `--standards-extensions <comma list>` (and the same for the other two) when the row names one.
`{paths}` then expands to only the files in scope carrying one of those extensions. A scope with
none of them records that tool's row as undeclared, with the reason, rather than met.

Pass `--standards-absent <reason>` (and the same for the other two) when the recipe's row is
declared absent, with the recipe's own reason text.

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
covering them. The three tools that take paths, `--standards`, `--static-analysis` and `--security`
above, run over the union of every work order's own owned files. A run with none of the three
supplied records each as undeclared instead. A suite that is already red is recorded, never
refused. Knowing it is the point: a builder chasing a failure it did not cause spends every
attempt it has.

The baseline is taken once, at that commit. A second run at the same commit leaves it alone. One
recorded at a different commit refuses rather than overwrites, and names both commits.
