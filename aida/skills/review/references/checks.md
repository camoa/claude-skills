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

Dispatch `catalog-identifier` with the lines `point: review`, each framework the project declares,
and the project folder. Then dispatch it again with `point: test-execution` and each
framework. **These are review's only two lookups.** Name the role, and pass the lookup's answer in
its own word: SKILL.md holds both rules. The role identifies a path and never opens the body. Never
fetch a catalog address yourself, and never read a cached copy behind the navigator's back. The
role reads a folder source this project configured itself first, so it wins over the catalog.
When a folder answers for `test-execution` or `review`, the role also returns the catalog's copy,
or the lookup's word. Pass the `test-execution` one as `--catalog-recipe` and the `review` one as
`--catalog-check-recipe`. A project copy behind the catalog's copy becomes a catalog note, because
the copy can fall behind after preconditions compared them.

Then invoke the tool skill with `require --advisory <path>` for each `review` recipe path, from
the worktree. Read its `TOOLING:` lines to the person, and go on whatever they say. A missing tool
makes its own check row read unknown.

## Run it

Run, with one `--recipe` and one `--check-recipe` per framework:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/review/scripts/review-actions.sh checks "<task_folder>" \
  --recipe <framework>=<path to the test-execution recipe> \
  --check-recipe <framework>=<path to the review recipe> \
  --lookup-failed <framework>=<no-recipe|listing-unreachable|fetch-failed> \
  --catalog-recipe <framework>=<the catalog's copy or the lookup's word, when a folder answered> \
  --catalog-check-recipe <framework>=<the same, for the review recipe> \
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
and checks 3 to 8 into `review/review.json`. It prints one summary line per check, with the verdict
and the framework, and the two paths. A tool's own output stays in the record. Name a path when the
person wants more, and say they can open it in an editor.

## How to read what it recorded

**The check block is not fixed at three rows.** The script runs every row the `review` recipe
declares, including a duplication tool or a design-metrics tool, and records one check row each. The
reviewer reads those rows before it judges, so do not re-derive a measurement here.

**A change no tool row reads gets a catalog note.** A row that names `extensions` reads only those
files. When no row read a file this change touched, every tool row reads undeclared, and the note
names the files. A project adds a tool for them as a row with its own id and `extensions` in its
own copy of the review recipe. Review then runs that row like any other. The baseline keeps a
result for every row by its id, so a failing added row subtracts as the three floor rows do. A
task past preconditions adopts the copy with `implement-actions.sh recipe-refresh --check-recipe`,
or every check stops at exit 73.

**The tool rows leave the frozen tests out.** The frozen tests are the reference
this stage judges against, and no role after the freeze may change them. A row's detail names each
test it left out. A row whose files are all frozen tests reads undeclared.

**Each tool row has a time limit.** A tool row that runs past 600 seconds is stopped and reads
unknown, naming the limit. Preconditions already ran each tool once, so a tool that cannot run at
all was found before the build.

**The static-analysis row runs once more, over the frozen tests alone.** The project's own analyser
reads the tests after the merge. A run that reads unmet or unknown becomes one finding on the
`frozen-tests` lens, with disposition `follow-up`. No check reads that lens, so it blocks nothing.
Completion offers it as a follow-up task for the test author.

**Checks 5 to 7 subtract the baseline** in `implementation/baseline.json`. A finding that predates
the build is not this task's, and blocking on it blocks every task forever. The baseline is scoped to
the orders' owned files, so a finding in a file no order owns reads as this task's. That is right:
check 3 already reports that file as work no order asked for.

The subtraction is the build's own. A tool the baseline recorded unmet has that baseline's kept
output subtracted from the run now, line by line. Numbers and dots are set aside first. No new
line is met. A new line is unmet, and the record lists the first twenty under `newLines` with the
count.
The check reads unknown only when the baseline kept no output or the run printed nothing.

**Check 8 reads the suite result that `finish` recorded, and runs nothing.** `finish` ran the whole
suite once at this commit and subtracted the baseline. It stops on a newly broken test, so check 8
never reads unmet. It reads warned or unknown when `finish` recorded a warning. The record names
each framework's `failure_line` under `failureLine`.

**Mutation testing runs only when the project opts in.** With no `review.mutation` in
`project.json`, or with it false, the mutation command never runs. Check 4 then reads the
coverage half alone, and `audit` names it `off`. The project skill's `set-mutation` turns it on.

**Check 4 records the score and every survivor, as the record holds them.** No mutation row reads
undeclared, never met. The survivors go to the reviewer at the next step, as one more lens. The score
is the line the tool's own recipe names, chosen by the tool in the row. An Infection run with no
score line ran no mutant, so its lines are never survivors. It reads met on exit 0, and unknown
with a note on the recipe on any other exit. A mutmut run prints no
survivor by file, so its survivors are recorded as not readable and named as unread in the detail.
The row still reads met on exit 0, because the coverage half and the score were read. The outcome
counts are in the score, and `mutmut results` lists the survivors by mutant name. A mutation
command with no path placeholder is never run, because it mutates the tool's whole default scope.
It reads undeclared with a note on the recipe, so the review does not block on it.

**A task that commits nothing in the code repository answers in its own word.** An order proved by
its record commits its document in the project folder, so the range holds nothing. Check 3 reads
undeclared, not met: it opened no file. The three tool rows and the mutation row read undeclared
too, the word the build stage answers with. The mutation command never runs over zero paths. The
suite reads not-needed, which finishing the build already decided. Every lens reads undeclared:
the diff holds nothing, and this stage does not hand the reviewer the deliverables. Check 4 reads
the judgement such an order left on the ledger, from the run lines that proved it, as for a page
order. A criterion judged at build time is covered. A look judges no machine criterion.

**Check 3 is decided twice.** A changed file no order owns is unmet, decided here. A support file
that an order's tests froze is set aside while it holds the content the freeze hashed. A hunk
inside an owned file that serves nothing is the reviewer's to raise, and its finding cites an id
or is not acted on.

**A check answers unknown only when nothing it reads could be read.** A check with two inputs that
got one answers from that one, and names what it did not get. Otherwise one network failure stops
every review, which is how version 5 trained the habit of skipping a check.

**Check 16 has a floor the `findings` step applies before its lens.** The `practices` lens reads
the plays research loaded into `records/playbooks.json`. The floor applies when `project.json`
carries a playbook subscription, declares a folder as a source of playbooks, or the project folder
holds `playbook.md`, or the person has `~/.claude/aida/playbook.md`. Then the check reads unknown, with the detail "playbooks not loaded", when that
record is absent or no source in it is `loaded`. Otherwise the lens verdict stands: with nothing to
load, an absent record says what a record of absent sources says. A missing load means the lens did
not run, never that there was nothing to follow. The repair is running `/aida:research <task-id>`
again, which loads the plays at its start. Nobody runs the load by hand.

## Report what the range itself said

An empty range is reported as empty. Say which of two things happened: the range held no commit, or
it could not be resolved. A head with no upstream is reported too, because work on one machine is
worth less than work that is pushed.

Say which frameworks answered from a recipe and which did not. A framework whose recipe could not be
reached was not checked, and reporting the run as clean would be false. Name each check reading
undeclared in that word, per SKILL.md.
