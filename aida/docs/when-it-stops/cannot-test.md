# The build cannot start: the repository cannot run tests

Before the first work order, `/aida:implement` checks that this repository can build and run a
test, and runs each tool review will run. When a condition answers no, nobody can tell, or a
tool cannot run, the build stops (exit 3) and nothing is built. A missing tool is found here, not
after every order is built. The verdicts and the lines it prints are on [the preconditions](../stages/implement/preconditions.md).

## What you see

AIDA opens with "Something this project needs before a test can run is missing, or could not be
checked." Then it names the condition, the stack, and the owner: the action that fixes it.

## What to do

- **A tool is missing.** The `nextAdvice:` line says to install it. Install it with
  `/aida:tool install <tool>`, commit what the install changed, then run `/aida:implement` again.
  See [a tool will not install](tool-or-harness.md).
- **The site is not running.** The owner names the task's environment step. Bring the site up
  with `/aida:task environment <task-id> up`. See [the site is down](site-down.md).
- **A value is missing.** A test command holds a placeholder that nothing fills, so the run reads
  `unknown`. Bring the environment up, or give the value when AIDA asks. A configuration order's
  gate line with no value refuses at exit 3 for the same reason.
- **A stack has no recipe answer** (exit 3). Every stack the project records needs a recipe
  answer, or the word for why there is none. AIDA asks the catalog again.

Lines such as `endOfTaskAbsent:`, `baselineRed:`, `freeze:` and `staleRecipe:` do not stop the
build, but each asks you to know or decide something now. The preconditions page says what each
one means. A suite already red before the build is on [the baseline](../stages/implement/baseline.md).

## A recipe changed in the middle of a task (exit 73)

The check recipe changed after the baseline was taken, and review refuses to run its tools against
the old baseline. There are three routes:

- Run review with the recipe the baseline read.
- Adopt the new recipe with `recipe-refresh`. When a tool row does not pass on the current tree,
  AIDA adopts it anyway and writes a warning. Review then reads that finding as one from before
  the task.
- Move the baseline aside by hand and retake it. The new baseline then holds this task's own
  code, so its findings disappear. Only you move it.

## Why it works this way

- **A build that cannot test cannot prove anything.** Stopping before the first order costs
  nothing. Finding out after it is built costs every attempt.
- **`undeclared` is never `met`.** A recipe that declared nothing was not checked, so AIDA says
  which of the two happened.

Source: skills/implement/references/preconditions.md, skills/implement/scripts/implement-actions.sh, skills/review/SKILL.md
