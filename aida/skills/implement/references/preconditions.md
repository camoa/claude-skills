# Check the preconditions

The build has started. Now find out whether this repository can run a test at all. This step runs
once per build, not once per work order.

## Resolve one recipe per framework

Read the project's own `frameworks`. A `project.json` recording none refuses outright (exit 77):
no recipe can be chosen for a project the run cannot name a framework for. For each framework,
dispatch `catalog-identifier` to ask the navigator's process-recipe lookup, with the lines
`point: test-execution`, that framework, and the project folder. It answers whether one is
available and, when it is, a path to the body on disk. Name the role, and pass the lookup's
answer in its own word: SKILL.md holds both rules. The role identifies and returns a path, and it
never opens the body.
Never fetch a catalog address yourself and never read a cached copy behind the navigator's back.
The role reads a folder source this project configured itself first, so it wins over the catalog.
When a folder answers for `test-execution`, the role also returns the catalog's copy of the same
recipe. Pass that path as `--catalog-recipe <framework>=<path>`, or the lookup's own word when it
failed. A project copy at a lower version than the catalog's prints on the `staleRecipe:` line,
with both versions. A failed lookup, or a catalog copy with another name, prints there as not
checked. Read that line to the person. The step changes nothing, because the copy belongs to the
project. Review compares the two copies again.

Dispatch `catalog-identifier` once more, with `point: review` and each framework. This is a
second recipe, never the same file as the `test-execution` one above. Pass its path straight
through; the script reads its `## Check commands` block itself, per SKILL.md.

Dispatch it a third time, with `point: implement` and each framework. Do not read that recipe
here and do not pass it to anyone. The per-order tests step resolves it again for its globs. This
dispatch exists so the freeze wall below is named before any order is built.

**Light:** ask for the three points in one dispatch, with the lines `point: test-execution`,
`point: review` and `point: implement`, each framework, and the project folder. The record keeps
the `implement` path, so the tests step and the build step of a light task read it there.

## Check the tools the test recipe names

The script runs the tool skill's `require` itself, from the worktree, for each `test-execution`
recipe. Each tool the recipe names under `requires_tooling` becomes one condition, with the id
`requires_tooling: <tool>`. A present tool reads met. An absent tool reads unknown with
`check-command-not-found`, as a condition whose checker is missing does. Its owner names the tool
skill's install and the recipe path, which documents the setup. So the run stops, and
`nextAdvice:` says to install.

An absent tool that only end-of-task rows run, such as `mutation`, does not stop the run. The
script matches the tool name against each test-command row's argv and cost. Such a tool goes in
`endOfTaskToolsAbsent` in the record, and the `endOfTaskAbsent:` line names it. Read that line to
the person. Review then reads those rows as known since preconditions, not as a fault of the task.
An install would change files no order owns, so the build does not ask for one. A tool that a
row of another cost also runs still stops the run.

A tool that reads unknown with "no recipe" goes to the catalog first, as the tool skill's "No
recipe" section says. The `nextAdvice:` line names this step. Pass each path the catalog returns
as `--tooling <tool>=<path>` and run this step again. When no order needs the harness, the test
recipe's tools are not checked, as the next section says.

The script also checks the tools that the build's own checks run. It reads the `review` recipe's
`requires_tooling`. It keeps each tool whose name is in the argv of a `## Check commands` row that
`build-record` runs. A row that reads files counts only when an order owns a file of a type the
row reads, inside the code repository. The file need not exist yet. Each tool kept is one
condition, read as above, so an absent tool stops the run with the install advice. Its owner
names the tool's tooling recipe, which says how to install it. This holds when no order needs the
harness too. Such a task runs no test, but `build-record` runs these
checks on every order. Without this check, the first order is built and paid for, and then its
checks cannot run. The review recipe's other tools, such as a duplication tool, are review's to
check.

A row that `build-record` runs, whose argv holds no tool the review recipe names, is not checked.
No tool name is guessed from a command. The record keeps that row and its argv under
`buildToolsNotChecked`, and the `buildToolsNotChecked:` line names them. Read that line to the
person. A missing program then reads unknown at `build-record`, after the order was built.

## Run the checks

Run, with one `--recipe` and one `--check-recipe` per framework:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh preconditions "<task_folder>" \
  --recipe <framework>=<path to the test-execution recipe> \
  --check-recipe <framework>=<path to the review recipe> \
  --lookup-failed <framework>=<no-recipe|listing-unreachable|fetch-failed> \
  --implement-lookup <framework>=<path to the implement recipe, or the lookup's own word> \
  --check-lookup-failed <framework>=<no-recipe|listing-unreachable|fetch-failed> \
  --tooling <tool>=<path to a tooling recipe the catalog returned> \
  --catalog-recipe <framework>=<the catalog's copy or the lookup's word, when a folder answered> \
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
declared nothing. `no-recipe` records the framework `undeclared`: the catalog looked and holds
nothing for it, so the build goes on. `listing-unreachable` and `fetch-failed` record it
`unknown`, and stop: nobody looked. Every framework prints its own line on every run.
`--check-recipe` is optional per framework: absent, its three tool checks record
undeclared, with a reason saying no check recipe was resolved. A failed `review` lookup passes
`--check-lookup-failed <framework>=<word>`. The record keeps each framework's answer as
`reviewLookup`. The `reviewNotResolved:` line names each framework with no review recipe, and
`none` when every framework has one. Read that line to the person. A light run asks every point
in one dispatch, and this line is what shows an answer that dispatch dropped.

**A task whose orders are all proved by their records runs no test, so it needs no harness.**
The same holds for an order a person confirms, whose task has no automated tests. On such a task
a `gate` order runs its own lines and no suite, so it needs no harness either. Then no order in
the snapshot needs the harness. The script records the conditions and the smoke row of each
framework as `not-needed`, with the reason, and runs neither. The verdict is
`not-needed` and the build goes on. The recipe is still resolved and recorded, because the freeze
reads its path. The baseline runs no suite and records `not-needed` per framework there too. The
`## Check commands` tools still run where an order owns a file under the code path, and read
undeclared where none does. Any other proof needs the harness. A `gate` order on a task with
tests runs the suite after its lines, and an `observe` order's build runs the suite against the
baseline.

**A project with no implement recipe cannot build a test-proved order, and this step says so.**
`tests-freeze` takes its test globs from the implement recipe's `## Oracle files` block. With no
such recipe, every order proved by tests dies at the freeze, exit 27, after the design closed,
the build started and the test author already ran. Pass `--implement-lookup` per framework. What
a project can
still build without that recipe: a `record` order and an `observe` order in full, and a `gate`
order that freezes, but whose own check reads `unknown`, which is not met. The repair is writing
the implement recipe for a framework this project declares, or changing each blocked order's
proof. `--implement-lookup` is optional, and a framework with none records `not-given`: the
lookup was not run, which is a different fact from a catalog holding no recipe.

**Three lines carry this, and each one says a different thing.** The `freeze:` line says what
the lookup found. It names the orders proved by tests on two paths only: where a recipe resolved,
and where none did and orders are blocked. Where the lookup was not run, or where no order is
proved by tests, that line names no order. On the flagless path the `notLookedUp:` line names
them instead.

**The `freezeAdvice:` line carries the instruction that goes with the freeze line.** A summary
value prints 240 characters. The freeze line holds the framework names and the order ids, which
grow with the project. An instruction a person cannot work out
again must never be the part that is cut. It reads `none` where the freeze line needs no
instruction.

**A resolved recipe names its own framework, and never more.** No record maps a work order to a
framework. So check that one of the named frameworks carries the `## Oracle files` globs for
each order proved by tests.

**A `notLookedUp:` line follows, whether or not a framework resolved.** It names every framework
nobody looked up, and the orders proved by tests. A lookup nobody ran says nothing about such an
order, so a run that answered for one framework and skipped a second is told so. It reads `none`
when every framework was answered, or when no order is proved by tests.

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
and writes what it found. It never hands a check to a shell. It prints the verdict and one line per
framework, naming what answered unmet or unknown and who owns it. It prints the baseline's state,
and the paths of the record and the baseline. What a check or the smoke command printed is in the
record; name the path rather than reading it here.

**A verdict that is not met names its cause on three lines.** The `next:` line names the first
condition or smoke row that stopped the run, and the command that row ran. The `failedOutput:` line
holds the first line that command printed. The `nextAdvice:` line says to run the tool skill's
install, only when a condition's tool is absent. Both read `none` when they do not apply. Read all
three to the person. Each is a line of its own, so the 240-character cut of a long command never
takes the cause or the instruction.

## Supply a value where a command needs one

A framework's cheapest test command may carry a placeholder, such as the runner a Python project
declares. Pass it with `--value <name>=<value>`. The script never reads a default out of a
recipe's prose: an unsupplied placeholder makes the run unknown and names which one had no value.

A recipe can derive a placeholder a person would otherwise pass, such as the folder that holds
the project's own code. It declares one `## Tokens` block per name, the name as the fence's second
word, holding one command. The script runs each block in the worktree, as arguments and never
through a shell, and the first line the command prints is the value. A `--value` for the same
name wins. The record keeps the values under `tokens`, and every later step fills its rows from
there. A rerun takes new values and never reads the old ones, and `recipe-refresh` drops them
when it changes a recipe path. A block that fails or prints nothing stops the blocks after it. Its name stays unfilled,
and a row that needs it reads unknown and names it. A recipe with no `## Tokens` section fills nothing.

A `gate` order runs the implement recipe's `## Configuration gate` lines at its build. A line may
hold a token such as `{project}`, which the task's environment record supplies. When any order's
proof is `gate`, the script resolves each token in those lines and runs none of them, because a
gate line reaches the site. A token that nothing fills refuses at 3, names the token, and writes
nothing. Bring the environment up, or pass `--value <name>=<value>`, then run the step again.

## Read the verdicts to the person

- **met.** Every declared condition answered yes. The build can go on.
- **unmet.** A condition answered no. Name it, name the framework, and name the owner the recipe
  gave. An owner is the action; without one the person has to work out what to do. When the
  task record shows the worktree's site is not running, the owner names the task's environment
  step and says why. Name that step as the fix, and the recipe's owner after it.
- **unknown.** Nobody could tell. A checker that is not installed says nothing about the condition
  it was meant to probe, so this is never reported as a failure of the condition.
- **undeclared.** The recipe named no conditions, or the catalog holds no recipe for this
  framework. Say that, and never say met. A recipe that declared nothing was not checked.
- **not-needed.** No order runs a test, so nothing was checked. Say that, and never say met.

`met`, `undeclared` and `not-needed` continue. A recipe saying this framework needs nothing before a test
runs has answered, and stopping on it would mean no project on that framework ever builds. Say
which of the two happened; never report `undeclared` as conditions that passed.

`unmet` and `unknown` stop, and the person decides. Interactive, open with: "Something this
project needs before a test can run is missing, or could not be checked. Only you can install or
fix it. Do that and the build starts. Leave it and nothing is built." Then name the condition,
the framework, and the owner the recipe gave. In an unattended run they halt. Nothing here
judges an unmet condition acceptable.

Say which frameworks were answered from a recipe and which were not. A framework whose recipe could
not be reached was not checked, and reporting the run as clean would be false.

## The smoke run and the baseline

After the conditions, the step runs each framework's cheapest test command, the one that proves the
harness reports at all. It runs only where that framework's conditions came back met or
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

A red suite is also a question for the person. `finish` meets the same red at the end, and it
refuses unless the baseline subtraction clears it. The summary's `baselineRed:` line names each
framework whose suite read unmet or unknown. When that line is not `none`, put it to the person
before the first order. Interactive, open with: "The suite already fails before this build
starts. Finish will refuse on that failure at the end unless it is decided now." When the red is
runner warnings and no failed test, give the routes `finish` offers, in its words: "Accept the
warnings: run finish again with --accept-warnings <the person's reason>, interactive only. Change
the suite row's command in the project's copy of the test-execution recipe, so these warnings do
not fail the run. Or repair the project configuration that raises them, in a change outside this
task." A suite row with no `warning_line` needs the key first, or `--accept-warnings` does not
pass (`references/finish.md`). A failed test is repaired outside this task. In an unattended run the build goes on, and a
person meets the red at `finish`.

What each run printed is kept whole, one file per run under `implementation/baseline-output/`,
and the baseline names each file. The build step subtracts those lines from a later run, so a
red suite or a red tool does not block every order. The subtraction compares lines with numbers
set aside, and it holds no parser. It cannot see a finding whose text changed, which reads as
new, or a finding fixed and reintroduced, which reads as old.

The baseline is taken once, at that commit. A second run at the same commit leaves it alone. One
recorded at a different commit refuses rather than overwrites, and names both commits.

## A recipe changed since the record

The record pins each recipe's path, and every later step reads that path. When the catalog
republishes a recipe this task pinned, the record still names the old body. Resolve the recipe
again the way the first section says: dispatch `catalog-identifier` with `point: test-execution`
and that framework, never a cached copy. Then run, with one flag per framework that changed:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh recipe-refresh "<task_folder>" \
  --recipe <framework>=<path to the test-execution recipe>
```
It replaces the path for the named frameworks only, and records what changed under
`recipeRefreshes`. It re-runs nothing: the verdict stands, because a recipe's preconditions
heading changes more rarely than its markers, and the person who refreshes knows why. It refuses
a framework with no resolved recipe on record, and a path that does not exist (exit 90). The
freeze refuses a `--test-recipe` that is not the record's path (exit 91), so run this first.

The review recipe is pinned by the baseline, with its sha256. The build refuses a body the
baseline did not read (exit 73). A baseline reads the tree before the task. Each tool runs where
the tree stands, so a second reading records this task's own findings as pre-existing. For that
reason a new review body is adopted only when no finding can hide. Resolve it the same way, with
`point: review`, then run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh recipe-refresh "<task_folder>" \
  --check-recipe <framework>=<path to the review recipe>
```
It runs every tool row of the new body over the baseline's scope, on the tree as it stands. When
each row reads met or undeclared, nothing is subtracted. It then pins the new body, writes those
readings into the baseline, and records both hashes under `recipeRefreshes`. When a row reads
unmet or unknown, it refuses (exit 73), names each such row, and writes nothing. Then finish the
task with the pinned body, or repair what the row found and run it again. The last route is to
abandon the baseline by hand, and checks 5 to 7 then subtract this task's own findings.
