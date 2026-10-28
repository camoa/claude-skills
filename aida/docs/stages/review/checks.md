# What the checks ask

Review answers sixteen checks over three subjects: the contract, the code, and the surfaces a
person can see. Each check is one question with one answer.

## The sixteen checks

| Group | Check | The question |
|---|---|---|
| Contract | every criterion | is each criterion met, by its tests or by your answer |
| Contract | every non-goal | did the task do something it said it would not do |
| Contract | everything serves a criterion | is every changed file owned by an order, and every hunk there for a reason |
| Contract | a test per criterion, and mutation | was each criterion signed off on a real test, and can the tests fail |
| Tools | coding standards, static analysis, security, the suite | do the framework's tools pass over the whole task |
| Lenses | SOLID, DRY, architecture fit | does the code follow the principles and the orders design wrote |
| Lenses | guides, framework practices | does the code follow the guides research cited and the practices this project accepted |
| Surfaces | end to end, visual regression, visual parity | do the pages and commands a person sees still work and look right |

The lens checks are the reviewer's. See [the reviewer](reviewer.md). "Everything serves a criterion"
and the mutation check each have a script half and a reviewer half. The surface checks are on
[their own page](acceptance.md). Visual parity runs only when the review recipe
commands it. Otherwise it reads undeclared.

A recipe may declare more tool rows, such as a duplication tool. Each row adds one check, so the
list can run past sixteen. A build can also leave checks for you: a decision it could not take,
or a non-goal that changed after the freeze. You answer those at the [close](close.md).

## What the tool checks read

- **The frozen tests are left out.** No step after the freeze may change them, so the tool rows
  skip them. Static analysis then runs once more over the frozen tests alone. A finding there
  blocks nothing. It becomes a follow up task for the test author.
- **Each tool row has a time limit** of 600 seconds. A row that runs longer is stopped and reads
  unknown.
- **A row reads only the file types its recipe names.** When no row reads a file the task
  changed, every tool row reads undeclared, and review writes a catalog note that names the
  files. To check them, add a row with its own id and file types to your own copy of the review
  recipe. A task already past its build start adopts the copy as
  [the build's baseline page](../implement/baseline.md) says.
- **The suite is not run again.** Finishing the build ran it at this commit, and review reads
  that result. Finish stops on a newly broken test, so the suite never reads unmet here. It reads
  met when every failure left was in the baseline or recorded as not caused by this task. That
  case still carries finish's warning. It reads warned or unknown when finish recorded those.
- **Mutation testing runs only when the project opts in.** With mutation off, the mutation
  command never runs, and the audit list names the check `off`. Turn it on with
  [`/aida:project set-mutation`](../../project/mutation.md).
- **A run that selected no tests reads unknown**, never met.

## Old findings do not fail a new task

Before the build, implementation ran the same tools over the files the orders own, and kept
their output. That is the baseline. At review, a tool whose baseline was already failing has
that old output subtracted from the new output, line by line. Numbers are set aside first, so a
moved line number does not read as new. No new line reads met. A new line reads unmet, and the
record lists the first twenty.

A finding in a file no order owns counts as this task's. "Everything serves a criterion" already
reports that file as work nobody asked for.

The subtraction holds only while both runs read one recipe. When the catalog changed the recipe
during the task, review refuses and gives three routes. See
[when it stops](../../when-it-stops/README.md).

## A task that writes documents, not code

An order proved by its record commits its document in the project folder, not in the code
repository. A task built only from such orders has an empty range. "Everything serves a
criterion", the tool rows, the mutation row and every lens read undeclared. The suite reads
not-needed. The criteria still read the judgement each order recorded at build time.

## Why it works this way

- A finding that predates the build is not this task's. Blocking on it would block every task.
- A check with two inputs that got one answers from that one and names the other, so one network
  failure does not stop every review.

Source: skills/review/references/checks.md, skills/review/references/reviewer.md, skills/review/SKILL.md, skills/review/scripts/review-actions.sh
