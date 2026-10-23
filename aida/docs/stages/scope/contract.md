# What the contract holds

The contract has five parts: the goal, the expected result, whether the task has automated tests,
the acceptance criteria and the non-goals. You approve all five together, as one document.

## The five parts

- **The goal.** One plain sentence, in your words, that says what the task is for.
- **The expected result.** One plain sentence that says what is true when the task is done.
- **Whether the task has automated tests.** Yes or no, for this task alone. A project can hold
  tasks of both kinds. See [Tests and the test setup offer](tests.md).
- **The acceptance criteria.** One line each, described below.
- **The non-goals.** What the task will not do, one line each.

## An acceptance criterion

A criterion is an outcome you can see when the task is done. It reads like a user story: "An
admin can download the user list as CSV." It is written from outside the code. It names no class,
no file and no stage. It is not a reminder to check something.

Each criterion also carries three facts:

- **Its verify clause**: how the outcome is observed, and whether a machine runs that check or a
  person looks. Scope recommends a machine when a command can read the fact, such as a test, a
  linter or a status call to an API. A person judges things such as how a page looks. A clause
  that only restates the criterion names no signal, so scope asks you for a better one.
- **Who asked for it**: you (`owner`) or AIDA's draft (`designer`). Every line AIDA drafts stays
  `designer` until you approve the whole document.
- **Its verdict**: met, unmet or unanswered. It starts unanswered. Only the review at the end of
  the task writes it.

Some facts exist only after a step the task never takes, such as a push that needs sudo. Scope
writes such a criterion for a person. The outcome names the step as your action. The verify
clause names the command that reads the fact. At review, you answer met or unmet for it.

## Ids

Each criterion and each non-goal gets a short id, in the order it was written: `c1`, `c2`, and
`n1`, `n2`. Later stages refer to a line by its id, never by its words. So you can reword a line
and every reference still points at it. An id is never used again after you remove its line.

## Where it lives

The contract lives in the task folder. `alignment.json` is the contract that every stage reads.
`alignment.md` is the same contract, rendered for you to read. Nothing reads `alignment.md` back,
so an edit there changes nothing. The page says so on itself.

## Why it works this way

- A wrong criterion gives a wrong feature with every check passing. So a person approves the
  contract, and the stages after it only check against it.
- The builder must not be the one who says what it had to do. The `designer` mark shows every
  line that you did not write or approve.
- The verify clause lets the review check a criterion instead of argue about it.

Source: skills/scope/SKILL.md, skills/scope/scripts/scope-actions.sh
