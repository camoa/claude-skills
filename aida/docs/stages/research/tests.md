# Check the automated tests answer

When the contract says the task has no automated tests, research checks whether the project can
run tests after all. It runs the checks that the framework's test recipe declares, before the
coverage check.

## What happens

1. Research finds the test recipe for each of the project's frameworks.
2. It runs the recipe's checks in the task's worktree. When they fall short there, it runs them
   again in the project's code folder. A new worktree often lacks a local environment that the
   code folder has.
3. It writes `records/test-runner.json`, which names the folder that answered.
4. It prints the verdict, each check that fell short, and the suite command when the recipe has
   one.

Only `met` says that this project can run tests.

## What research asks you

- **On `met`.** Research shows the suite command. It asks one question: keep "no automated tests",
  or change the answer to yes.
- **On any other verdict.** Research shows the verdict and each check that fell short, and asks
  nothing. The answer stays no. To change it, set up the test runner, then run research again.

This check can refuse to run, and the coverage check refuses until it has run. See
[The research check refuses to close](../../when-it-stops/research-check.md).

An autonomous or a light run answers for you. See
[Research on an autonomous or light run](unattended.md).

## Why it works this way

- The recipe's own checks decide, not a searcher's prose. A runner named in prose was never run.
- A light run meets no person before review. A kept no would send every criterion to a person by
  hand.

Source: skills/research/SKILL.md, skills/research/scripts/research-actions.sh, skills/scope/scripts/scope-actions.sh
