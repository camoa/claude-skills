# Check that the repository can test

Once per build, AIDA finds the recipes for each framework the project declares and checks what
must be true before a test can run. Nothing is built until this step answers.

## The recipes

A project that declares no framework refuses here. For each framework, AIDA asks the catalog for
three recipes: how to run tests, which review tools to run, and how to write code. A light task
asks for all three at once. A recipe folder the project configured wins over the catalog.

A lookup has three answers, and only the first says anything about the framework. For the recipe
that runs tests, the answer sets the framework's verdict:

- **No recipe.** The catalog looked and holds none. The framework reads `undeclared`, and the
  build goes on.
- **Listing unreachable** or **fetch failed.** Nobody looked. The framework reads `unknown`, and
  the build stops.

A failed lookup of the other two recipes does not stop the build. It prints on the
`reviewNotResolved:` or the `freeze:` line below.

Read these lines when they print:

- `staleRecipe:` your project's copy of a recipe is older than the catalog's. Nothing changes,
  because the copy is yours.
- `folderRecipeMissing:` your recipe folder holds some recipes for a framework but not these. The
  catalog answers for the missing ones, and its commands can assume a setup your folder replaced.
- `reviewNotResolved:` a framework has no review recipe.
- `freeze:` and `freezeAdvice:` which frameworks have a recipe for writing code. That recipe
  names where tests go. When no framework has one, every order proved by tests would fail at the
  freeze: write that recipe, or change those orders' proof in design. When some framework has
  one, no record says which framework an order uses. Check that one of them covers each order
  proved by tests.
- `notLookedUp:` a framework nobody looked up a code recipe for. That says nothing about the
  orders proved by tests, so the line names them.

## The verdicts

| Verdict | What it means | What happens |
|---|---|---|
| met | every condition answered yes | the build goes on |
| unmet | a condition answered no | stop; the condition, framework and owner are named |
| unknown | nobody could tell, say a checker is not installed | stop |
| undeclared | the recipe named no conditions, or there is no recipe | the build goes on |
| not-needed | no order runs a test, so nothing was checked | the build goes on |

On a stop, three lines carry the cause: `next:` names the condition and its command,
`failedOutput:` holds its first line of output, and `nextAdvice:` says what to do. When the
worktree's site is not running, the owner is the task's environment step. Interactive, AIDA asks
you to install or fix the cause. Unattended, the run halts.

## The tools

Each tool the test recipe lists becomes a condition. An absent tool reads `unknown`, and
`nextAdvice:` says to install it. The tools the build's own checks run are checked the same way.

A tool that only end-of-task rows or review rows use does not stop the build. The
`endOfTaskAbsent:` line names it, so you know before the build. A build check whose command names
no known tool is listed on `buildToolsNotChecked:`. A missing program there shows up at the first
attempt. For a tool with no recipe, AIDA asks the catalog for one and runs the step again.

## A command that needs a value

A test command can hold a placeholder, such as the runner a Python project uses. A recipe can
derive it by running a command in the worktree. Otherwise AIDA asks you for the value. A value you
give always wins. AIDA never guesses one.

A configuration order's lines can need a token from the task's site, such as `{project}`. When
nothing fills it, the step refuses. Bring the site up with `task environment up`, or give the value.

Other refusals here: a framework that can run no named test, and two frameworks that both command
one tool. See [When it stops](../../when-it-stops/).

## Why it works this way

- A recipe that could not be reached says nothing about the framework. Recording it as "declared
  nothing" would let an unchecked build pass as a clean one.
- A missing tool found now costs nothing. Found after the first build, it costs a paid attempt.

Source: skills/implement/references/preconditions.md, skills/tool/references/reading-a-recipe.md
