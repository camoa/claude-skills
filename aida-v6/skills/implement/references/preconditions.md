# Check the preconditions

The build has started. Now find out whether this repository can run a test at all. This step runs
once per build, not once per work order.

## Resolve one recipe per framework

Read the project's own `frameworks`. A `project.json` recording none refuses outright (exit 77):
no recipe can be chosen for a project the run cannot name a framework for. For each framework,
dispatch `catalog-identifier` to ask the navigator's process-recipe lookup for the `test-execution`
point and that framework. It answers whether one is available and, when it is, a path to the body
on disk. Name the role, and pass the lookup's answer in its own word: SKILL.md holds both rules.
The role identifies and returns a path, and it never opens the body. Never fetch a catalog address
yourself and never read a cached copy behind the navigator's back. A source this project configured
itself, a folder of its own, is read the ordinary way and wins over the catalog.

Dispatch `catalog-identifier` once more, for the `review` point and each framework. This is a
second recipe, never the same file as the `test-execution` one above. Pass its path straight
through; the script reads its `## Check commands` block itself, per SKILL.md.

## Run the checks

Run, with one `--recipe` and one `--check-recipe` per framework:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh preconditions "<task_folder>" \
  --recipe <framework>=<path to the test-execution recipe> \
  --check-recipe <framework>=<path to the review recipe> \
  --lookup-failed <framework>=<no-recipe|listing-unreachable|fetch-failed> \
  --value <name>=<value>...
```
`--recipe` names the `test-execution` recipe this step already resolved, for the `## Preconditions`
and `## Test commands` blocks. `--check-recipe` names the `review` recipe, for `## Check commands`.
Pass paths only. The script parses both files itself: the argv for each tool, its `signal` and
`extensions` keys, and which rows a framework declares absent. Nothing here retypes a tool's
command, so nothing here can drop a key a dropped `signal` would silently turn into a check that
always passes.

Every framework the project declares needs a `--recipe` or a `--lookup-failed` for it. The script
refuses rather than guess, because a lookup nobody ran must never be recorded as a recipe that
declared nothing. `--check-recipe` is optional per framework: absent, its three tool checks record
undeclared, with a reason saying no check recipe was resolved.

**Two frameworks may not both command one tool.** A project declaring two frameworks whose review
recipes each carry a coding-standards row, say, gives the script two answers to one question, and
it refuses (exit 72) rather than choose. Resolve one check recipe for the task, or split the
frameworks into two tasks.

**A framework that could never test itself refuses here, not later.** The test-execution recipe's
`## Test commands` block needs a `changed` or a `file` row, the two that can run a named set of
tests. A framework declaring both absent stops the whole run (exit 19), naming the framework. No
order on it could ever have its own tests run. `build-record`'s own floor requires that check to
answer met before an order reaches `checks-passed`. This is the one place `undeclared` does not
continue: continuing would mean no project on that framework ever builds.

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
whole, from the `## Test commands` block's own `suite` row, because the orders' tests do not exist
yet and no framework maps changed paths to the tests covering them. The three tools from the
`## Check commands` block run over the union of every work order's own owned files. A framework
with no `--check-recipe` records each tool undeclared instead. A suite that is already red is
recorded, never refused. Knowing it is the point: a builder chasing a failure it did not cause
spends every attempt it has.

The baseline is taken once, at that commit. A second run at the same commit leaves it alone. One
recorded at a different commit refuses rather than overwrites, and names both commits.
