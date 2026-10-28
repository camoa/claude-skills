# Finish the task, or leave a stop

This step covers `finish`, which runs when every order is closed or dropped, and `reopen`, which
follows a failed task review. It also covers the three ways a person leaves a stopped order:
`go-on`, `redo` and `drop`.

## Finish

Every order closed or dropped, none stopped, and no `implementation/finished.json` on disk means
the implementation stage is done and waiting to be recorded. Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh finish "<task_folder>" \
  [--value <name>=<value>]...
```
It refuses unless every order in the ledger is closed or dropped, naming whichever is not. It also
refuses when any order is stopped, closed or not, naming the order and its reasons. It refuses
unless every machine-verified criterion reads confirmed too, naming whichever is not. A criterion
a dropped order serves or owns is not asked: nothing built it. It refuses a
dirty code repository as well, because the commit range it records is a claim about what that
repository holds.

Then it runs the test-execution recipe's suite row once, at the final commit, from the worktree.
The record steps leave a row the recipe costs `end-of-task` unrun and record it `deferred`; this
is the run that decides it. The recipe paths come from `implementation/preconditions.json`, so
pass none. Pass `--value <name>=<value>` for a placeholder the suite row carries, the same as
`build-record`. The baseline's own failures are subtracted the same way. A suite that is unmet
or unknown refuses (exit 86). The message names the first twenty new lines and the sidecar,
`implementation/finished-suite.txt`. A fix commit on the branch and a second `finish` is the
route. A recipe with no suite row passes with `undeclared`, and the record says so.

A suite row may also declare `warning_line`, the lines a runner prints that fail no test. A
failing suite where no line matches `failure_line` and at least one matches `warning_line` reads
`warned`. That holds whether the baseline was red, green or absent. No test failed, so a fix
commit is not the route. `finish` refuses (exit 86), lists the warning lines, and names each
framework's own verdict. It never passes on warnings by itself, because the project's own
configuration made them fail the run. A `warning_line` with no `failure_line` is not read, and
the suite's detail says so.

The message names three routes, and a person picks one. Put them to the person in these words:
"Accept the warnings: record the person's answer with person-answer.sh, then run finish
again with --accept-warnings <the person's reason>. Change the suite row's command in the project's copy of the test-execution recipe, so these
warnings do not fail the run. Or repair the project configuration that raises them, in a change
outside this task."

`--accept-warnings` passes only a suite that reads `warned`, and only when every other framework
passed. It refuses without the person's answer on record (exit 68). The record keeps the suite
`warned`, with the warning lines, the reason, and `judgedBy: person`. Review reports the suite row
met and says it is that person's answer.

A recipe can lack `warning_line`. Then the same red reads `unknown` over a red baseline, and
`unmet` over a green or absent one. When no line matches `failure_line`, the detail names the
recipe file, the missing key, and what the key reads. No action writes a recipe. For a file in
a recipe folder the project declares, a person adds the key to the suite row, under
`failure_line`, and runs `finish` again. `finish` reads that file on each run. Any other file is
a catalog copy, and a refresh replaces it. The person copies it to
`<folder>/process-recipes/<framework>/test-execution.md` and adds the key there. A folder the
project does not declare yet is declared first, with the project skill's `add-source`. Then
`recipe-refresh` points the task at the copy, and `finish` runs again. Without the key,
`--accept-warnings` does not pass. An `unknown` suite can hide a failure that prints no test line.

On success it writes `implementation/finished.json`: the commit range this stage produced, and
each order's own range and rounds used. Each dropped order is under `dropped`, with the person's
words and the criteria it leaves unbuilt. The review brief carries that list, and review's close
reads each such criterion unanswered. The suite's verdict is under `suite`, with its output in
the sidecar. The record is committed when the stage closes: `finish` commits
the task folder, in the project folder and never in the code repository. It also records each criterion's row state and who judged it.
The checklists for the criteria a person verifies are copied in too, from the frozen test records.
The review stage reads this one file rather than one per order. It records the findings ruled
deferred with their reasons, and how many rows a model judged rather than a person. It prints
summary lines and the record's path, never the record. The lines carry the commit range and one line
per order. They carry the criteria by row state, the checklist count, the deferred findings by id,
and the model-judged count.

**Finish ends implementation only.** It never touches `task.json`. The task goes to the review
stage next, which reads `finished.json`. Review's close, not this step, confirms the criteria a
person verifies by checklist.

**Finish runs again after a failed review.** When the task review of this finish failed, `next:`
names `reopen`. Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh reopen "<task_folder>"
```
It takes each review finding that fails a criterion, unless the person ruled it wrong. The finding
goes to the closed order that owns its file and owns that criterion, else to one that serves it.
When no such order exists, it goes to the one order that owns the file. That order gets one finding with origin `repair` per
review finding, scoped to the file, and one more fix round. It goes back to its fix step. Its own
fixer repairs it under a dispatch record, its owned files and the frozen-test hook. A fresh
verifier then reads the round, and answers whether the failure arises in that file. The order
closes again, and this step runs again. It rewrites `finished.json` with a range ending at the new
head, and review runs from its first step. `reopen` removes `finished.json`, because an order is
open again.

The summary names each finding no order takes, with the reason. One reason is two orders that own
the file when neither serves the criterion. Another is a file no order owns. That finding waits
for the person. The person commits the fix on the task branch before this step runs again,
or rules it at the next review. Keep that fix inside the files the orders own. A file no order
owns reads unmet at review's check that every change serves a criterion.

`reopen` refuses (exit 119) when the review of this finish did not fail, and when no finding can
go to an order. It runs in either run mode: the review recorded the findings, so no one decides
here.

Interactive: stop here. Name the next command for the person, `/aida:review <task-id>`, and never
invoke it yourself. Autonomous: invoke `aida:review` through the Skill tool, once, with the task
id, and stop if it refuses. Invoke it only when the mode covers review too; otherwise end as
interactive does, naming the command. Each stage refuses to start without the previous stage's
record, so a stage cannot run out of order. That is why this chain is safe.

## Leave a stop

A stopped order carries its reasons as a list. Each names the step that wrote it, its words, and the
go-on choices it allows. `read` prints them on the order's line, and `next:` names the choices every
reason allows. A person leaves the stop one of three ways. Each one is a person's answer, recorded
first as "A person's answer" below says. None runs on a person's behalf because an order is
stopped: put the reasons and the recorded attempts to them first.

Open with: "This unit of work stopped, and only you can say how it goes on. It waits until you
choose." Then say each reason in plain words, and offer the ways out the next sections name.

### Go on

`go-on` takes the order out of its stop and says what continues. It takes one choice:

- `build`: one more build attempt. When the attempts are spent, it raises the order's allowance by
  one, and the attempts used never go down.
- `fix`: one more fix round. When the rounds are spent, it raises the allowance by one.
- `check`: the checks run again over the last record's range, with no new build and no attempt or
  round spent. A pass moves the order on and clears the stop. A fail records the checks and leaves
  the order stopped. It takes the recipe flags `build-record` takes, and `--interface`.
- `close`: the order closes with its open and pending findings listed. Each one is ruled `deferred`
  with the person's words, so `close` closes and `finish` carries each one to the task review.
- `keep`: the change stays. A builder's deviation or a departure is kept with the person's words,
  and the next `build-record` or `review-record` reads them. A changed design file of the order is
  taken into the snapshot with no revert, so the order builds on the new design. It needs design
  closed on the live files (exit 13).

Run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh go-on "<task_folder>" <order id> \
  --continue <build|fix|check|close|keep> --because <the person's words> [--owns <path>]...
```
The answer's step is `implement go-on <choice>`, so a yes to one choice passes no other. It refuses
a choice a reason does not allow (exit 67), and names the choices every reason allows. A reason that
allows none, such as a wrong test, leaves only redo and drop. An order that is not stopped has
nothing to leave, so go-on says so and exits 0. The one exception is an attended change mid-build,
which leaves the order going on with a `changed` list: go-on `keep` and redo answer it the way
they answer the same change as a stop. `--owns` names a file the order now
owns, such as the file the owned-files check refused, or one a fixer reported out of its scope. The
person's words name each such file. It refuses a file another order owns, or a frozen test. The
build brief, the dispatch record, the fix scope and the owned-files check then read it as owned.

Which choices a reason allows:

| The reason | The choices |
|---|---|
| `attempts spent`, at `build-record` | `build` or `check` |
| a builder's stop, or commits by a stopped builder | `build` |
| a builder's deviation | `build` or `keep` |
| uncommitted changes, unattended | `build`, or `fix` after a fix round; commit the tree first |
| a rejected row, unattended, at `tests-freeze` | `build`, once the person judged the row at a second freeze |
| `budget spent`, at `dispatch-open` | `build`, or `fix` in review; raise the budget first |
| a finding on a non-goal, or a disputed already-correct claim, unattended | `fix` or `close` |
| a fixer short of scope | `fix`, often with `--owns` |
| the fix round cap with findings open, unattended | `fix` or `close`; and `check` when every open finding is a check finding |
| a finding ruled load-bearing | `check`, over the fix the person committed, or `close` |
| a departure, or `design drift` naming the order's own design file or a criterion it serves | `keep` |
| `test wrong`, or `design drift` saying the design removed the order | none: redo or drop |

**Budget spent.** The spend is recomputed at every dispatch, so going on alone brings the stop
straight back. Put the numbers to the person, opening with: "The build reached the limit you set on
this task, in dispatches or in minutes, and stopped. Only you can raise it." The person raises the
ceiling first, with the task skill:
```
/aida:task set-budget <task-id> --dispatches <n>
```
`--minutes <n>` raises the other ceiling. Name the command and let them run it. Then go on.

**A finding ruled load-bearing** leaves no fix round, so the person commits the fix on the task
branch, in the order's own files. Then go on with `check`. It runs the checks over the last
record's range, extended to HEAD, and writes a warning for the later commits. It moves the
record's commit to HEAD, under `personFix`, so `close` takes the commits. A failed check leaves the
order stopped. Repair the fix, and go on with `check` again, with a new answer. A commit that
changes a frozen test or a file the order does not own refuses (exit 63).

**A dirty tree.** An unattended start may have moved the files a role left into a `setAside`
folder. Copy them back from the folder the ledger names, and commit them first.

### Redo the order

A redo is the route for a wrong test, a wrong order, a design change and a departure. The person
changes the order's design or its tests first, through design, and design closes again. Open with:
"The order is built again from its design. Its own commits are reverted, and its tests are written
again and must fail first. Every other unit keeps what it has." Then run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh redo "<task_folder>" <order id> \
  --because <what changed and why the order is built again>
```
It reverts the order's own commits, newest first, each with `git revert --no-edit`. It reads them
from its records' commit lists: its freezes, its build attempts and its fix rounds. No other order's
commit is touched, and the history keeps every one. It moves the order's records to a dated folder,
`implementation-<date>-<commit>/`, or `-<n>` after it when that name is taken, with `redone.json`
holding the person's words. The ledger entry goes back to planned and keeps the list of its redos.
The criteria it serves go back to not judged. The snapshot takes the order's live copy, so design
must have closed on the live files (exit 13). Then run `start`, which refreshes the frozen contract
and takes in an order design added, as before. The tests brief carries the person's words under
`redo`.

It takes any order that is not closed, and a closed order only while it is stopped or changed. It refuses an
order the live design no longer holds: drop it instead (exit 67). It refuses a dirty tree (exit 61).
It refuses when the records list a commit HEAD does not hold, as after a rebase, and on a merge
commit (exit 113). Then a person reverts that work by hand. A revert that stops on a conflict is
taken back, with every revert before it, so the branch is where it was.

### Drop the order

`drop` ends the order without code. Open with: "This unit of work is dropped. Its commits are
reverted, and nothing that depends on it can start. The criteria it served stay unbuilt, and the
task review reads them unanswered." Then run:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/implement/scripts/implement-actions.sh drop "<task_folder>" <order id> \
  --because <why the order is dropped>
```
It reverts the order's own commits the same way, and moves its records to a dated folder with
`dropped.json`. The order stays in the snapshot, at `dropped`. Its summary names each order that
depends on it, directly or through another order. Each one cannot start: redo it through design,
or drop it too. An order the design removed takes this route, so its frozen test record stops
guarding the files a surviving order took over.

### A design change clears itself when it goes back

A stop about an order's own design file, or the live text of a criterion, clears when the drift
does. Put the design or the criterion text back to what the snapshot holds, then run `start` again.
It compares, finds no drift for that order, and removes those reasons. Each clearing is recorded
under `stopsCleared`, with the reasons as they stood. A reason a person answered with go-on `keep`
is not raised again.

## A person's answer

Some calls are a person's decision only. In implement they are `go-on`, `redo`, `drop`,
`start --leftovers keep` and `finish --accept-warnings` (exit 68). They are also `verify-record --ruling` (exit 55),
`fix-brief --allow` (exit 100), and `tests-freeze` with a row a person judged (exit 70). Each one
refuses without the person's answer on record, in every run mode. The run mode does not decide
whether a person answered.

Record the answer with the task skill's `person-answer.sh`, before the call:
```
"${CLAUDE_PLUGIN_ROOT}"/skills/task/scripts/person-answer.sh --project "<projectPath>" \
  "<task-id>" --step "implement <action>" [--order <order id>] -- <the exact words of the flag>
```
Claude Code shows its permission prompt for this action, and the person approves or denies it. A
denied prompt records nothing, so the call still refuses. In bypassPermissions or dontAsk mode the
hook refuses the action, because no prompt can show there. Then stop and report the step.

The step of a go-on names its choice, such as `implement go-on build`. The words are the exact
value of the call's flag. For a repeated flag, `--ruling` or `--allow`,
they are every value in the call's order, one per line, passed as `@/<file>`. For `tests-freeze`
they are each `--row` a person judged, one per line. For `start` they are `keep`. A final newline
does not count. Each refusal prints the command with the words to use.

Each answer is one entry in `person-answers.json` in the task folder. An entry serves one attempt.
The call marks it used once its own writes are done. A call that refuses after it found the entry
marks it refused, so the next attempt needs a new answer. An argument fault (exit 3) keeps it. No
entry is removed, so review can count every answer. A hook refuses every other write of this file,
and of `task.json`, from any session.

Three other stages still refuse only on an unattended stage (exit 70): review's `close --row`,
completion's `close` flags, and the task skill's `environment` calls. There the same action records
the answer, with step `review close`, `completion close` or `task environment <up|down|not-applicable>`.
For completion's `close`, the words are one `<flag> <value>` line per person's flag, in the call's
order. For `environment`, the words are the reason for `not-applicable`, and `yes` for the other
two.

An agent never runs `person-answer.sh`. A hook refuses it to every dispatched agent. An agent that meets a
person's step reports the stop to the main session and stops. It never asks again.
