# Finish refuses

When every work order is closed, `/aida:implement` runs `finish`. It runs the whole test suite
once at the final commit, and records the build for review. It refuses when the build is not
done, or the suite does not pass. The finish step itself is on [finish](../stages/implement/finish.md).

## The build is not done (exit 66)

The message names each order that is neither closed nor dropped, each order that is stopped, and
each machine-verified criterion that is not confirmed. A criterion a dropped order served is not
asked. For an order, close it, drop it, or take its stop's way out. See
[a work order stopped](stopped.md). For a criterion, the message says which case it is:

- **Its orders have not all closed.** Close them.
- **A checker rejected its test.** The test writer repairs the test, and the tests of that order
  are frozen again. Take the order out of its stop first when it stopped on the rejection.
- **No work order serves or owns it.** Nothing will ever judge it. Close design again with an
  order behind it, then run `/aida:implement`, whose `start` takes the added order in.

Uncommitted work refuses too (exit 61).

## The suite fails (exit 86)

The failures the suite already had before the build are subtracted first.

- **`unmet`.** New failures appear. The message names the first twenty new lines, and
  `implementation/finished-suite.txt` holds the whole output. Commit a fix on the task branch,
  then run `/aida:implement` again.
- **`unknown`.** The suite could not answer. The message names why: no baseline to compare with,
  a value nobody gave, a runner not found, or a run that selected no test.
- **`warned`.** No test failed, only the runner's warning lines did. Finish never passes on
  warnings by itself. Accept them with your reason, change the suite command in the project's
  copy of the test recipe, or repair the settings that raise them. Accepting needs a person
  (exit 68 otherwise). The three routes, and what to do when the recipe has no `warning_line`,
  are on [finish](../stages/implement/finish.md).

## Why it works this way

- **The suite runs once, at the end.** Each order's tests ran during its build. The whole suite at
  the final commit catches what the orders broke together.
- **Warnings are your project's rule, not AIDA's.** So AIDA never decides alone that a warning is
  harmless.

Source: skills/implement/references/finish.md, skills/implement/scripts/implement-actions.sh
