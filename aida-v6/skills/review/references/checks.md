# Run the checks a script can decide

This step writes the diff once, runs every tool the two recipes declare, and records checks 3 to 8.
It is the first step of a review and of a re-review.

## The change set is read, never derived

The range is `commitRange` in `finished.json`. Review reads that field and computes none of its own,
because one fact with two producers is what the foundations forbid.

The step refuses while the code repository's tree is dirty, exit 61. The range is a claim about what
the repository holds, and uncommitted work makes it a claim about something else.

The diff is written once, to `review/diff.patch`, and every later reader opens that file. Never paste
a diff through this conversation. It costs the review the context its own steps need.

## Resolve one recipe per point, per framework

Dispatch `catalog-identifier` for the `review` point and each framework the project declares. Then
dispatch it again for the `test-execution` point and each framework. **These are review's only two
lookups.** Name the role, and pass the lookup's answer in its own word: SKILL.md holds both rules.
The role identifies a path and never opens the body. Never fetch a catalog address yourself, and
never read a cached copy behind the navigator's back. A source this project configured itself is read
the ordinary way and wins over the catalog.

## Run it

Run, with one `--recipe` and one `--check-recipe` per framework:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/review/scripts/review-actions.sh checks "<task_folder>" \
  --recipe <framework>=<path to the test-execution recipe> \
  --check-recipe <framework>=<path to the review recipe> \
  --lookup-failed <framework>=<no-recipe|listing-unreachable|fetch-failed> \
  --value <name>=<value>...
```
`--recipe` names the `test-execution` recipe, for its `## Test commands` block, which carries the
suite row and the mutation row. `--check-recipe` names the `review` recipe, for its `## Check
commands` block and its `## Surface commands` block. Pass paths only.

Every framework needs a `--recipe` or a `--lookup-failed` for it, and the script refuses rather than
guess. A lookup nobody ran must never be recorded as a recipe that declared nothing. A project
recording no framework refuses at exit 77, because no recipe can be chosen for it. Two frameworks
that each command one tool refuse at exit 72, rather than give the script two answers to one question.

`--value` supplies a placeholder a command carries, such as the runner a Python project declares. The
script never guesses one and never reads a default out of a recipe's prose.

On success it writes `review/diff.patch`, one row per tool the recipes declared, the mutation row,
and checks 3 to 8 into `review/review.json`.

## How to read what it recorded

**The check block is not fixed at three rows.** The script runs every row the `review` recipe
declares, including a duplication tool or a design-metrics tool, and records one check row each. The
reviewer reads those rows before it judges, so do not re-derive a measurement here.

**Checks 5 to 7 subtract the baseline** in `implementation/baseline.json`. A finding that predates
the build is not this task's, and blocking on it blocks every task forever. The baseline is scoped to
the orders' owned files, so a finding in a file no order owns reads as this task's. That is right:
check 3 already reports that file as work no order asked for.

**Check 8 reads the recipe's outcome words, not the exit status.** Three of the five frameworks print
that nothing was selected and exit zero. A silent pass reads unknown, never met.

**Check 4 records the mutation score and every survivor.** No mutation row in the recipe reads
undeclared, never met. The survivors go to the reviewer at the next step, as one more lens.

**Check 3 is decided twice.** A changed file no order owns is unmet, decided here. A hunk inside an
owned file that serves nothing is the reviewer's to raise, and its finding cites an id or is not
acted on.

**A check answers unknown only when nothing it reads could be read.** A check with two inputs that
got one answers from that one, and names what it did not get. Otherwise one network failure stops
every review, which is how version 5 trained the habit of skipping a gate.

## Report what the range itself said

An empty range is reported as empty. Say which of two things happened: the range held no commit, or
it could not be resolved. A head with no upstream is reported too, because work on one machine is
worth less than work that is pushed.

Say which frameworks answered from a recipe and which did not. A framework whose recipe could not be
reached was not checked, and reporting the run as clean would be false. Name each check reading
undeclared in that word, per SKILL.md.
