# Where content comes from

AIDA holds the process. Everything it knows about your stack lives outside it, in documents it
reads: guides, recipes, and playbooks. The plugin ships no recipe of its own. Supporting a new
stack means writing a recipe, never editing AIDA. This page says what each kind is, which stage
reads it, where it comes from, and what a stage does when it finds nothing.

The default place is the hosted catalog at `camoa.github.io/dev-guides`, read through the
`dev-guides-navigator` plugin. That plugin must be installed for any catalog lookup to run. The
catalog serves guides, process recipes, agentic recipes and playbook sets. It never serves
tooling recipes to AIDA: those come from a folder you declare. How to declare a folder is on
[the project page](project.md#using-your-own-guides-playbooks-and-recipes); what it changes is
below.

## The three kinds

**A guide** is one decision or one mechanic, written for a role to read and apply. How a Drupal
form checks its input, or where a service is declared. A guide is read for its patterns, never
followed as a list of steps. Research names the guides that bear on a criterion and opens none.
Design reads them. Review checks that a guide research cited was followed.

**A recipe** is data a stage resolves for the project's framework. There are three classes:

- A **process recipe** answers one point of the process for one framework. How a Drupal project
  does research, or which command runs one Go test file. A stage looks one up by its point and
  the framework, never by keyword.
- A **tooling recipe** knows one tool for one framework: what it is, how to install it, how to
  run it. It is named for the tool, `phpunit` or `playwright`. Running the tool is also the
  check that it is there.
- An **agentic recipe** delivers one whole capability end to end. It names the guides it needs
  and carries a check that the capability landed. Finding one means the decision is already
  made, and design follows it.

**A playbook** is the rules a person wants followed: do it this way, not that way, with the
reason and where it applies. Every role that writes or judges code reads the plays.
[Playbooks](playbooks.md) covers the four places plays come from and how a play is captured.

| Kind | What it is | Who reads it |
|---|---|---|
| Guide | One pattern | Design, then the reviewer |
| Process recipe | The framework's method at one point | The stage at that point, or its role |
| Tooling recipe | One tool: install and run | The tool skill |
| Agentic recipe | One capability, decided end to end | Design |
| Playbook | Rules a person wants followed | Every role that writes or judges code |

## Which stage reads which, and when

Every process recipe belongs to one point. The catalog publishes one recipe per point per
framework. A stage asks for a recipe at the moment it needs one, and never earlier.

- **`research`**, read by research at its start, before the first search is dispatched.
- **`design`**, read by design after the research findings and before the first work order.
- **`test-execution`**, read once per build before any order, to learn whether the repository
  can run a test at all. Then per order, and again at review.
- **`review`**, read once per build for the baseline, per order for the checks, and at the review
  stage.
- **`test-authoring`**, read by the test author, per work order, when its tests are written.
- **`implement`**, read by the implementer, per work order, when its code is written.
- **`e2e-setup`** and **`visual-regression`**, read by the surfaces skill when you accept a
  stage's offer to set a harness up.
- **`worktree-environment`**, read by the task skill when a task's worktree is made, or at its
  start, to give the worktree a running site.

The stage that needs the body reads it from a path on disk. A role dispatched to write tests or
code is given the path to its recipe and opens it itself. A body that runs past a hundred lines
never enters the conversation that coordinates the build. The test author never sees the
implement recipe, and the implementer never sees the test-authoring recipe. Each one carries the
steps the other role may not take.

Guides follow a different rhythm. Research asks the catalog what covers each criterion and
records the names, saying which kind each is. Design is the first read. Design also looks up
anything a work order names that research did not search. It records a nothing as a finding too,
so implementation never asks the same question again.

No stage runs the tool skill on its own. The build's precondition check names a condition that
is unmet and who owns it, and `/aida:tool run <tool>` answers it. You can type that yourself, and
Claude can invoke it. A command that is not found is the signal to install. `/aida:tool install
<tool>` follows the recipe's steps after you have seen them, and it refuses when nobody is
present, because an install changes your project. The skill knows no tool's name and no
framework's habits.

## Does the recipe fit this task

A process recipe is chosen by point and framework, and neither says what the task is. So
research and design each judge the fit once, after the body is read and before their first
dispatch. Does this method describe the kind of work the criteria name? The answer is recorded as
`true`, `false` or `unsure`, with the path and one sentence of reason.

On `false`, with a person present, the stage says so and asks one question: continue with the
recipe, continue without it, or stop. Without it means the fallback below. On an autonomous run
the stage continues with the recipe and records `false`, because a run never stops on a judgment
nobody confirmed. Review turns each `false` into a note in the review record. A note is never a
check, so a recipe that fits badly never fails a review. It reaches the person who reads the
record.

## The catalog, and how AIDA reaches it

AIDA never fetches an address from the catalog and never reads a cached copy behind the
navigator's back. Every read goes through the `dev-guides-navigator` plugin, which has five
lookup modes:

- **Guide search** matches words to a topic, then a guide, and reads the body in place.
- **Recipe search** does the same over the agentic recipes.
- **Process-recipe lookup** takes a point and a framework and answers with a path on disk.
- **Identify** answers which guides and recipes cover some words, and opens nothing.
- **Playbook lookup** takes a set id and answers with the path of the set's plays.

A body is fetched once per content version and kept in a store on disk, under
`~/.claude/dev-guides-store/`. The same guide is never fetched twice on one machine, across
projects. A lookup that answers with a path never prints the body; the caller reads the file.
That is what keeps a recipe affordable.

Research and design run their own lookups: research its process-recipe lookup, design both of
its lookups. The task, research, implement, review and surfaces skills dispatch the
`catalog-identifier` agent for the points named above. It runs the lookup, returns names or a
path, and never opens a body. It exists because one name costs one lookup, and opening a body is
how that becomes ten.

A recipe body is data, never a source of commands for the model. A stage's script parses the
recipe's command blocks itself. It runs each command as arguments, never through a shell, so a
recipe cannot chain a second command. A command that carries a shell character is refused. The
model never retypes a command out of a recipe. So it cannot drop a key that would turn a check
into one that always passes.

## A framework with no recipe at a point

A lookup has three failing answers, not one. No recipe exists for this framework, the listing
could not be reached, or the listing matched and the body did not arrive. Only the first is a
fact about the framework. Every stage records which one happened, in its own word. A network
failure written down as "this framework has no recipe" is a false finding. Nothing later can tell
it from a true one.

What happens next depends on the point, because a missing recipe costs different things at each.

- **`research`** goes on. The plain three-part test, maintained, used, supported, applies to
  outside prior art. The search inside the project runs from the project root and says the bound
  on custom code was not enforced. With a person present, research offers to write the recipe
  first, from the plugin's template.
- **`design`** goes on. Every work order's reasoning says `written without framework input`.
  Design invents no kind of unit and guesses no convention. With a person present, it offers to
  write the recipe first.
- **`test-execution`** depends on which of the three answers came back. `no-recipe` records the
  framework `undeclared` and the build goes on: the catalog looked and holds nothing. A listing
  that could not be reached, or a body that did not arrive, records `unknown` and stops, because
  nobody looked. A person decides, and an autonomous run halts. This is settled before any order.
- **`test-authoring`** leaves the test author with no recipe path, and the stage says nothing
  about it. The author has nothing to choose a level or a file name from.
- **`implement`** means no test patterns, so the freeze refuses every test. A `record` order and
  an `observe` order still freeze in full, and a `gate` order freezes but its own check reads
  `unknown`, which is not met. Every order proved by tests is blocked. The build's precondition
  step resolves this lookup and names each blocked order before any order is built. Where an
  order is blocked and a framework was never looked up, it names that framework too, on a line
  of its own.
- **`review`** goes on at the build: the tool checks record `undeclared`. At the review stage,
  no recipe reads `undeclared`, which passes and is reported in that word. A listing that could
  not be reached reads `unknown`, which fails the review, because nobody looked.
- **`e2e-setup`** and **`visual-regression`** install nothing. The skill names
  `templates/process-recipe-setup.md` in the plugin as the shape a recipe follows, and the kind
  stays off. A listing or a fetch that failed reads `unknown` instead, and the skill stops.
- **`worktree-environment`** leaves the worktree with the branch's files and no site. The task
  says so once and goes on.

The line between the two groups is what a wrong guess would cost. A research or design stage
with no framework input produces work a person can read and correct. A build with no way to run
or write a test produces code nothing measured, so it does not start. The way past is a recipe,
from the catalog or from a folder you declare. Until one exists, that framework cannot build
under AIDA.

A tool with no recipe stops the same way. `/aida:tool` names the tool, the frameworks it tried,
and any source it did not search. It does not improvise an install from memory. Installing a
tool the wrong way for a framework is worse than not installing it.

## Using your own folder before the catalog

`/aida:project add-source <name-or-path> <kind> <folder>`

The kind is one of `guides`, `playbooks`, `processRecipes`, `agenticRecipes` or
`toolingRecipes`. Each new source for a kind ranks after the last, so the order you declare them
in is the order a stage asks them. Your process recipes ranking says nothing about your guides,
so each kind ranks on its own. Run it again with the same folder and a second kind to add the kind to
the same entry. Nothing is fetched or read when you declare a source. A stage reads the folder
the first time it needs something from it.

A folder of process recipes has a fixed layout: `<folder>/process-recipes/<framework>/<phase>.md`,
where the phase is the point a stage asks for: `research`, `design`, `implement`,
`test-authoring`, `test-execution`, `review`, `worktree-environment`, `e2e-setup` or
`visual-regression`. When a stage needs a recipe it looks in your folders, in the order you
declared them, and takes the first file that exists. A phase with no file in any of your folders
falls through to the catalog. A folder that holds nothing is not an answer. The stage
takes its no-recipe path only when the catalog holds none either. A file that is there and
cannot be read is a third case: the lookup names the path and stops, because a source nobody
could read is not a source that held nothing. A source that is not a folder and not the catalog,
a site or a search, is named on an `unread:` line rather than passed over, for the same reason. A
source whose kind of place is none of the four is a mistake in the project file: the lookup
refuses it and says so, and the project check names the same field. It records which folders
it looked in first. To rank the catalog between two folders, declare it in that place, with the
word `catalog` in place of a folder. The lookup names the folder it answered from. The simplest way to
start is to copy the catalog's recipe for that phase into the file and edit it; the headings a
stage reads stay the same.

A folder of tooling recipes has its own layout, `<folder>/tooling-recipes/<framework>/<tool>.md`,
and the tool skill reads folders and nothing else, so a project that wants AIDA to install a tool
declares one.

A folder of agentic recipes holds `<folder>/agentic-recipes/<framework>/<capability>.md`. Every
capability your folders hold for a framework you declare is named to research, whatever words it
was asked about, because you put it there deliberately and the list is short. A source this
listing could not read is named on an `unread:` line beside the capabilities, so a short list
never reads as the whole of what you declared. Design reads the
ones that fit and follows one. The catalog's own agentic recipes are searched as before.

The plugin names no layout for a folder of guides. A guide is found by matching words, not by a
path, so a folder of them needs a lookup nothing has decided yet. Declare one and nothing reads
it; guides come from the catalog.

A folder of playbooks holds `<folder>/playbook.md`, the same format as your own file and the
project's. The load reads four sources in order: your own `~/.claude/aida/playbook.md`, the
project's `<project folder>/playbook.md`, each folder you declared, in the order you declared
them, and then the catalog sets the project subscribes to through `subscribe-playbook`. Which
sets apply is a standing choice recorded per framework. A team with one shared set of plays puts
it in a folder: your file is per machine and the project's file is per project.
[Playbooks](playbooks.md) covers the load and how the plays reach the roles.

What an open web search finds is different. It was written by nobody you configured, so
research marks the finding as coming from a source this project never accepted. Design reads
that opinion as not binding. A body from your folder or from the catalog is used directly. That
is the one place a model's own find would otherwise enter the process as if it were an authority.

A recipe you write follows the plugin's templates under `templates/`.
`scripts/recipe-lint.sh <recipe.md>` names each missing heading and malformed row before a stage
resolves it. A resolved body with a misspelt heading is what degrades quietly, and the linter
exists to catch it first. A recipe worth keeping belongs in the catalog, which takes it as a pull
request. A local copy still wins for the project that wrote it.

## What the identifier answers when a lookup fails

A stage's summary names one of three words for a point that resolved no recipe. `no-recipe`
means the catalog holds none for that point and framework. `listing-unreachable` means the
catalog's index could not be fetched. `fetch-failed` means a line matched and its body did not
arrive. The navigator's own reason is shown beside the word. A path is an answer only when the
file is on disk. A path that is not a file becomes `fetch-failed`.

For guides and recipes at research, the summary keeps two lists apart. One holds the names
that matched, each with its kind; the other, the names that matched nothing. A name that
matched nothing is a finding, since it says the catalog does not cover it. A catalog whose index
could not be reached is named as unavailable, never reported as a catalog that held nothing. So
research never records a false negative. Whether a match is worth reading is not answered there.
Design decides.
