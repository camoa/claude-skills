#!/usr/bin/env bash
# The plugin root: the variable when the platform sets it (hooks), else this file's own place.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
# implement-actions.sh: the deterministic half of the implement skill (ideal/implementation.md).
#
# The skill body holds the conversation. This script holds the deterministic half: it freezes the
# contract and the work orders into a snapshot, opens the ledger, establishes whether the code
# repository can run a test at all, briefs and freezes one order's tests, briefs and records one
# order's build against eight deciding checks, briefs and records its review, its fix rounds and
# their verification, closes the order, and finishes the task once every order is closed. It never
# asks a question and never judges whether a criterion is met. What each step is for, and why, is
# ideal/implementation.md; this header says only what a caller needs.
#
# `dispatch-open` and `dispatch-close` open and clear the one record per task,
# <task_folder>/implementation/dispatch.json. The two permission hooks (hooks/deny-prior-source.sh,
# hooks/deny-frozen-test-writes.sh) read it to tell a dispatched role apart from a person working
# their own repository.
#
# Two steps halt an order rather than refuse. A halt is the run continuing correctly, so it exits 0,
# writes the reason into the ledger and says so on standard error. The one exception is an
# unattended run reaching the fix cap with findings still open: a ruling is a person's judgement, so
# that one refuses with its own code and halts the order in the same call (exit 56).
#
# Usage:
#   implement-actions.sh read  <task_folder>
#   implement-actions.sh start <task_folder> [--rebased-onto <commit>]
#   implement-actions.sh preconditions <task_folder> [--recipe <framework>=<path>]...
#                                                    [--check-recipe <framework>=<path>]...
#                                                    [--lookup-failed <framework>=<reason>]...
#                                                    [--implement-lookup <framework>=<path|reason>]...
#                                                    [--check-lookup-failed <framework>=<reason>]...
#                                                    [--tooling <tool>=<path>]...
#                                                    [--catalog-recipe <framework>=<path|reason>]...
#                                                    [--value <name>=<value>]...
#   implement-actions.sh recipe-refresh <task_folder> [--recipe <framework>=<path>]...
#                                                     [--check-recipe <framework>=<path>]...
#   implement-actions.sh tests-brief  <task_folder> <unit_id>
#   implement-actions.sh tests-freeze <task_folder> <unit_id> \
#                            [--test <path>::<test name>=<criterion id>[,<criterion id>...] | <unit_id>]...
#                            [--red <test name>=<path to a file holding what the run printed>]...
#                            [--test-recipe <framework>=<path>]...
#                            [--implement-recipe <framework>=<path>]...
#                            [--test-glob <glob>]...
#                            [--checklist <criterion id>=<verification text>]...
#                            [--row <criterion id> | <unit_id>=<confirmed|rejected>::<person|model>::<note>]...
#                            [--green-on-arrival <test name>=<reason>]...
#                            [--locks-in <test name>=<reason or commit:<id>>]...
#                            [--support <path relative to codePath>]...
#   implement-actions.sh build-brief  <task_folder> <unit_id>
#   implement-actions.sh build-record <task_folder> <unit_id> \
#                            --interface <path to the record the builder wrote> \
#                            --report <path to the builder's report> \
#                            --started-at <commit the attempt began from> \
#                            [--observed <path to the observed record, on an order whose proof is observe>] \
#                            [--test-recipe <framework>=<path>]... \
#                            [--check-recipe <framework>=<path>]... \
#                            [--implement-recipe <framework>=<path>]... \
#                            [--value <name>=<value>]... \
#                            [--nothing-ran <literal substring>] \
#                            [--accept-deviation <the person's reason>]
#   implement-actions.sh build-recheck <task_folder> <unit_id> \
#                            [--interface <path to the interface record the builder wrote>] \
#                            [--test-recipe <framework>=<path>]... \
#                            [--check-recipe <framework>=<path>]... \
#                            [--implement-recipe <framework>=<path>]... \
#                            [--value <name>=<value>]... \
#                            [--nothing-ran <literal substring>]
#   implement-actions.sh review-brief  <task_folder> <unit_id>
#   implement-actions.sh review-record <task_folder> <unit_id> --findings <path> \
#                            [--accept-deviation <the person's reason>]
#   implement-actions.sh fix-brief     <task_folder> <unit_id> [--allow <path relative to codePath>]...
#   implement-actions.sh fix-record    <task_folder> <unit_id> \
#                            --report <path to the fixer's report> \
#                            --started-at <commit the round began from> \
#                            [--test-recipe <framework>=<path>]... \
#                            [--check-recipe <framework>=<path>]... \
#                            [--implement-recipe <framework>=<path>]... \
#                            [--value <name>=<value>]... \
#                            [--nothing-ran <literal substring>] \
#                            [--scope-insufficient <finding id>=<reason>]...
#   implement-actions.sh verify-brief  <task_folder> <unit_id>
#   implement-actions.sh verify-record <task_folder> <unit_id> [--verdicts <path>] \
#                            [--ruling <finding id>=<wrong|deferred|load-bearing|test-wrong>::<reason>]...
#                            (--verdicts is required until the round is on the record; after that,
#                            --ruling alone rules on the round's open findings, or at reviewed on
#                            findings whose fix scope is empty)
#   implement-actions.sh close <task_folder> <unit_id>
#   implement-actions.sh finish <task_folder> [--value <name>=<value>]... \
#                            [--accept-warnings <the person's reason>]
#   implement-actions.sh grant-attempt <task_folder> <unit_id> --reason <text>
#   implement-actions.sh restart <task_folder> --reason <text>
#   implement-actions.sh unattributed <task_folder>
#   implement-actions.sh clear-halt <task_folder> <unit_id> --because <text>
#   implement-actions.sh retake-tests <task_folder> <unit_id>
#   implement-actions.sh dispatch-open <task_folder> <role> <unit_id> \
#                            [--deny-read <path relative to codePath>]... \
#                            [--allow-write <path relative to codePath>]... \
#                            [--test-glob <glob>]... [--resume]
#
# `dispatch-open` checks <role> against the agent definitions this plugin ships and refuses a name
# that matches none of them. For the four roles that read or write the code, it also derives the
# path lists itself from the frozen snapshot, so none is a list a caller assembles per dispatch: a
# test author is denied every order's owned files, a row-checker takes that same derivation because
# it must answer from the test and never from the implementation, and an implementer is denied every
# order's but its own and is allowed its own. A fixer takes the implementer's derivation exactly, because a fix round
# writes the same order's files for the same reason (decision 8 of step five). `--deny-read` adds to what was derived; it is how a path outside codePath is
# denied, such as the recipe each role may not open. An implementer's record also carries its own
# owned files under `ownedFiles`, the list hooks/deny-frozen-test-writes.sh holds it to while the
# record is open (live-run row 92). A fixer's record carries the key too: the order's list plus
# the `allowedFiles` of the round's fix brief, which must exist (live-run row 116). No other
# role's record carries the key.
# A test author's record carries `denyCommand`, the runtime forms scripts/introspection-forms.txt
# lists, which hooks/deny-prior-source.sh refuses in its Bash commands (gap row 231).
#   implement-actions.sh dispatch-close <task_folder> [--no-report]
#
# `dispatch-close --no-report` is for a role the runtime marks as stopped at its turn limit. A
# fixer or test author whose pinned report lacks its completion line takes that path unasked (112). The
# first time, the record stays open and takes `resumedAt`, and the role is resumed once by message.
# The second time, the order halts and the record is removed (exit 110, gap row 228). An
# implementer whose order's diff budget starts with `large` carries `resumesAllowed` 2, so it is
# resumed twice and the third time halts (gap row 301). For a
# reviewer, a plain close also refuses when its brief's findings or verdicts file is missing (111).
# `dispatch-open --resume` reopens a record already closed for that one resume. It skips the
# leftover check `dispatch-open` otherwise runs (exit 104) and writes `resumedAt` at once.
#   implement-actions.sh step <name>
#
# `step` prints one of this skill's own step files, from
# ${CLAUDE_PLUGIN_ROOT}/skills/implement/references/<name>.md. The skill reads them through this
# action rather than with Read: the documentation mirror scopes ${CLAUDE_PLUGIN_ROOT} substitution
# in `allowed-tools` to Bash rules, so a Read rule naming that variable never matches and every
# step-file read raises a prompt an unattended run cannot answer. A name carrying a slash, and a
# name no file matches, both refuse with exit 3 and name the steps that exist.
#
# Every action prints a summary of `key: value` lines and nothing else: no record body, no diff, no
# command output, no brief, no finding's evidence. Each line that a person may want in full names
# the path that holds it. The five brief actions write their brief to a file under
# <task_folder>/implementation/ and print its path, which the dispatch then names. Each brief
# carries the task's worktree under `worktree`, and prints it (gap row 230):
# brief-<unit_id>-tests.json, brief-<unit_id>-build.json, brief-<unit_id>-review.json,
# brief-<unit_id>-fix-<round>.json and brief-<unit_id>-verify-<round>.json. `read`, `start` and
# every record action end with a `next:` line, derived from the ledger the way SKILL.md's routing
# table reads it. The two exceptions to the summary rule are the bodies a person or a caller has to
# read verbatim: `tests-freeze`'s checklist rows, and `step`'s own step file. `restart` prints the
# archive path alone, and `dispatch-open` the worktree, the denied paths and the record path. For
# a row-checker it also writes and prints implementation/interfaces-<unit_id>.json, when a tests
# brief exists.
#
# `preconditions` never resolves a recipe itself. The skill body asks the guides navigator for the
# one belonging to this point and this framework, or reads a source the project configured itself,
# and hands over a path. A framework whose lookup failed is passed with the reason it failed, and
# the three reasons stay apart: no-recipe, listing-unreachable, fetch-failed. Only the first says
# anything about the framework.
#
# There is no --run-mode flag on this script, deliberately. The mode is the task's own for the
# implement stage, read from <task_folder>/task.json through task_run_mode at every `start`
# (task-schema.json, `runMode` and `runModeStages`), not something a caller passes for one
# invocation the way research-actions.sh and design-actions.sh accept it for their own
# conversational choices. `start` writes it into the ledger, new or resumed, and every step
# between two starts reads the ledger's copy: the mode the build runs under.
#
# Depends on, shipped by other builders of this same project and never edited here:
#   ${CLAUDE_PLUGIN_ROOT}/scripts/check-design.sh       called by `start`, unmodified
#   ${CLAUDE_PLUGIN_ROOT}/scripts/lib/recipes.sh        sourced. The recipe block parsers, the
#                                                        resolver behind every commanded check, the
#                                                        command runner, the clean-tree refusal and
#                                                        the code-path loader. Every one of them was
#                                                        written in this file and moved there when
#                                                        the review stage needed the same ones, so
#                                                        the two stages read one parser and one
#                                                        resolver. Nothing in this file carries a
#                                                        second copy.
#   ${CLAUDE_PLUGIN_ROOT}/scripts/lib/task-helpers.sh   sourced, for resolve_task_folder,
#                                                        write_atomic, mark_task_in_progress and
#                                                        task_run_mode, the same ones every other
#                                                        stage reads.
#   ${CLAUDE_PLUGIN_ROOT}/scripts/lib/records-hash.sh   sourced. Its records_hash_for is the only
#                                                        place this script computes a hash over a
#                                                        contract and its work orders, the same
#                                                        computation design-actions.sh's own
#                                                        `close` calls to write design-closed.json.
#                                                        Both always agree on the same number for
#                                                        the same files, because both call the
#                                                        same function; this script never carries
#                                                        a second copy of that formula.
#   ${CLAUDE_PLUGIN_ROOT}/scripts/lib/schema-check.sh   sourced, for schema_check_compare, the
#                                                        one field-list comparison every stage
#                                                        reads; `start` runs it over baseline.json
#   ${CLAUDE_PLUGIN_ROOT}/scripts/lib/proof.sh          sourced. br_order_facts says which check
#                                                        takes one order's proof slot, which
#                                                        repository holds its range, and whether
#                                                        it owns a file in the code path. Every
#                                                        step below asks one of those three, and
#                                                        never reads the proof kind itself.
#   ${CLAUDE_PLUGIN_ROOT}/scripts/lib/builder-lines.sh  sourced. The builder's stop and deviation
#                                                        lines, which build-record and
#                                                        hooks/require-stop-lines.sh both read.
#   ${CLAUDE_PLUGIN_ROOT}/scripts/baseline-schema.json   the shape `preconditions` writes to
#                                                        baseline.json, which `start` compares a
#                                                        resumed run's copy against (exit 83)
#   ${CLAUDE_PLUGIN_ROOT}/scripts/snapshot-schema.json   the shape `start` writes to snapshot.json
#   ${CLAUDE_PLUGIN_ROOT}/scripts/ledger-schema.json     the shape `start` writes to ledger.json
#   ${CLAUDE_PLUGIN_ROOT}/scripts/dispatch-schema.json   the shape `dispatch-open` writes to
#                                                        <task_folder>/implementation/dispatch.json
#   ${CLAUDE_PLUGIN_ROOT}/scripts/finished-schema.json   the shape `finish` writes to
#                                                        <task_folder>/implementation/finished.json
#
# This script never runs a schema comparison against snapshot-schema.json or ledger-schema.json
# itself. Every field it writes is built from those two schemas' own field lists by construction;
# a stale or hand-edited file already on disk before this script's first call on it is a fact this
# script reports (present-but-unreadable, or a hash mismatch), not one it repairs. The one record
# it does compare is baseline.json, on a resumed `start`, because an earlier version wrote that
# file in a shape `build-record` cannot subtract from (exit 83).
#
# Freezing (ideal/implementation.md, "Freezing, and what a freeze is for"). A new run re-derives
# the design-closed hash from the live files and refuses when the two disagree. Once a snapshot
# exists this script never reads design-closed.json again: a resumed run re-derives from the live
# files and compares against the SNAPSHOT's own recorded hash, and only the snapshot governs a
# resumed run.
#
# What `start` does, in order, is ideal/implementation.md, "Before the first order: start, then
# preconditions". Every refusal it can make runs before its own first write, so a refused run
# leaves nothing on disk; a later refusal can follow the snapshot write, and that file is never
# half-formed and never wrong to have, because it is exactly what the next `start` would compute.
#
# Exit codes, each one and only one meaning:
#   0  did what was asked. For `read`, this includes an honest report that nothing has run yet.
#      For `start`, this includes a resumed run that halted one or more drifted orders (that is
#      the run continuing correctly, not a failure) and a trunk check that could not look.
#   1  the given path does not exist, is not a folder, or holds no task.json: not a task folder.
#      The one meaning of exit 1 here, for every action.
#   2  `start` was asked to act on a task with no contract at all: alignment.json is missing.
#      There is nothing to freeze. See exit 10 for a contract that exists but cannot be used;
#      the two never share a value.
#   3  the script could not do its job: a missing task folder argument, an unrecognized argument,
#      jq or git not on PATH, neither sha256sum nor `shasum -a 256` on PATH (reported by
#      scripts/lib/records-hash.sh), the plugin root, check-design.sh or the records-hash library
#      could not be resolved or loaded, check-design.sh itself failed to run (its own exit 3), a
#      file that must already be valid JSON on disk is not (snapshot.json present but unreadable,
#      ledger.json present but unreadable, baseline.json present but unreadable, tests-<unit_id>.json
#      or build-<unit_id>.json present but unreadable, or a design/*.json file that check-design.sh
#      itself did not refuse on but this script still could not parse),
#      a ledger.json missing a required field or holding one of the
#      wrong type on reopen, a write that failed, or an internal state this script's own logic
#      should have already ruled out (a ledger existing with no snapshot beside it; a snapshot
#      appearing between this script's own presence check and its own write, which is another
#      `start` call on this task finishing first and winning the race, not a defect).
#   4  design has not closed cleanly: scripts/check-design.sh, run against the live design/*.json
#      files, did not exit 0. The message names what it reported as open.
#   5  the task's own project (resolved from the task folder, never asked for) points at a
#      codePath that exists on disk but is not a git repository.
#   6  the build would land on the project's own trunk branch: the branch currently checked out in
#      codePath is the one derived as trunk.
#   7  a new run found no work orders at all under design/. Nothing for implementation to build.
#   8  the build order could not be derived from the snapshot's own work orders: a dependency
#      cycle among them (naming every order in it), or two orders declaring the same path in
#      ownedFiles (naming both).
#   9  a resumed run's ledger.json does not belong to the snapshot on disk: its own recorded
#      snapshotHash disagrees with the snapshot file's own hash field.
#  10  `start` was asked to act on a task whose alignment.json exists but cannot be used as a
#      contract: not valid JSON, not an object, or missing a required field. A different fact from
#      exit 2, and the two never share a value.
#  11  a new run found no <task_folder>/design-closed.json. Design has never closed. Run the
#      design skill's close action on this task first.
#  12  a new run found design-closed.json but could not read it as a close record: not valid
#      JSON, not an object, or its hash field is missing or the wrong shape. Close design again.
#  13  a new run found design-closed.json, readable, but its recorded hash disagrees with a hash
#      re-derived from the live alignment.json and design/*.json. Design changed after it closed,
#      without closing again. Close design again. A resumed run answers the same when a drifted
#      order that has not started would take its live copy, or a started or closed order that
#      changed only in fields its frozen tests were not written from would take its copy in place.
#      The message names each such order and what changed in it. `restart` answers the same when
#      the halted orders would take their copies: a live copy design did not close on is never frozen.
#  14  the task's own project.json exists but is not valid JSON, so its codePath cannot be read.
#      A different fact from exit 3's "no usable codePath", which is a valid file with the field
#      absent or empty.
#  15  the codePath recorded in project.json does not exist on disk. A different fact from exit 5,
#      where codePath exists but is not a git repository. Exit 77 names a third fact: a valid
#      project.json that records no framework at all.
#  16  codePath is not currently on a named branch: a detached HEAD, or the branch could not be
#      read for any other reason. Refused before the trunk check runs, because a commit landing
#      nowhere is worse than one landing on trunk.
#  17  a resumed run's snapshot.json does not agree with itself: a hash re-derived from its own
#      copied alignment and work orders disagrees with its own stored hash field. The snapshot
#      file was edited after it was written.
#  18  `preconditions` was given a framework from project.json that the caller answered for
#      neither way: no --recipe and no --lookup-failed. Refused rather than guessed, because a
#      lookup nobody ran recorded as a recipe that declared nothing is the exact defect the
#      declaration exists to close.
#  19  `preconditions` ran and something stops the build: a condition answered no, nobody could
#      tell, or a framework's own smoke run came back the same way. The record is written first
#      and names every condition, every smoke run, and its reason, so this exit says do not
#      proceed, never that nothing was learned. `undeclared` does not land here: a recipe saying
#      this framework needs nothing before a test runs, or nothing before a smoke command proves
#      one, has answered, and refusing on it would stop every project on that framework. It is
#      reported, never counted as met. A framework passed as `--lookup-failed <fw>=no-recipe` is
#      `undeclared` too: the catalog looked and holds nothing for it (live-run row 137). The other
#      two lookup failures are nobody looking, and they land here as `unknown`. `not-needed` does
#      not land here either. Every order in the snapshot is proved by its record, so no condition
#      and no smoke row was run. The record says so per framework (live-run row 136).
#  20  an action after `start` was asked to run on a task whose build has never started: no
#      snapshot and no ledger. `preconditions` names this fact with it, and so does every step-five
#      action. Run `start` first.
#  21  `preconditions` found <task_folder>/implementation/baseline.json already recorded at a
#      commit other than the one this run's own ledger started from. A baseline is taken once, at
#      the commit the build started from, and this refuses rather than overwrite a different one.
#      The message names both commits.
#  22  `tests-brief`, `tests-freeze` or `build-record` was given a unit id that is not in the frozen
#      snapshot. `build-brief` names the same fact as exit 38 instead; see that entry for why.
#  23  `tests-brief` found a unit in the given unit's dependsOn with no completion record in the
#      ledger (its lastStep is not "closed"), so that unit's interface record does not exist yet.
#  24  `tests-brief` found the given unit owns a criterion whose verifiedBy is machine while its
#      own frozen tests field is empty. check-design.sh should already have refused this at design
#      close; this is a second reading against the frozen copy, never a live one.
#  25  `tests-brief` or `tests-freeze` ran before `start`, so <task_folder>/implementation/
#      snapshot.json does not exist. Run `start` first.
#  26  `tests-freeze` was given a --test whose path does not exist on disk.
#  27  `tests-freeze` was given a --test whose path matches none of the given --test-glob patterns.
#      A test written outside the framework's own pattern is not protected by anything later.
#      Or its path is not a file the order owns (gap row 249); the refusal names the owned one.
#  28  `tests-freeze` was given a --test whose test name does not carry, at its own end, the
#      criterion id (or ids, chained from the right) it claims, or the unit's own id when the test
#      proves the unit's doneWhen instead of a criterion.
#  29  `tests-freeze` found a criterion the unit owns whose verifiedBy is machine with no --test
#      row naming it. A criterion the unit only serves needs no test from it: exactly one order
#      owns a criterion, and that order's tests are the ones that can observe it (live-run row
#      59). A serving order freezes its tests against its own doneWhen instead. An order whose
#      proof is gate is exempt: it takes no --test at all, and its owned machine criterion is
#      judged by the recipe's `## Configuration gate` lines at build time (live-run row 65). An
#      order whose proof is record is exempt the same way: its done-when row, `--row <unit_id>=`,
#      is its checkpoint, and exit 64 asks for that row (nyc defect 17). An order whose proof is
#      observe is exempt too, and takes no --row either: nothing is judged before its build
#      (live-run row 104).
#  30  `tests-freeze` found a criterion the unit serves or owns whose verifiedBy is person with no
#      --checklist row.
#  31  `tests-freeze` was given a --test naming a criterion the unit does not serve or own.
#  32  `tests-freeze` was given a --red whose file is missing or empty, or that names a test with
#      no --test row.
#  33  `tests-freeze` found a test with neither a --red nor a --locks-in naming the existing code.
#  34  `tests-freeze` was given a --green-on-arrival. Not a defect in the script: it stops the step
#      and says the test proves nothing, which is the escalation this stage requires.
#  35  `tests-freeze` found <task_folder>/implementation/tests-<unit_id>.json already recorded at a
#      commit other than the one this run is at. The message names both commits. The one freeze
#      exempt is the first after `retake-tests`: HEAD holds the attempt the record was frozen
#      before, so the ledger's last retake names the record's commit and the freeze overwrites it
#      with `retakenFrom` instead (live-run row 110).
#  36  `tests-freeze` was given a --test whose path, once resolved against codePath, names
#      something outside codePath altogether. The message names the path and the code root. Every
#      path this step records is relative to codePath (baseline.json's own `scope` field is
#      relative for the same reason: a frozen path must survive the checkout moving), so a path
#      that cannot be made relative to it at all cannot be recorded either.
#  37  `dispatch-open` found <task_folder>/implementation/dispatch.json already open. The build
#      of one task is serial, so a task has at most one active dispatch. The message names the
#      role and unit that hold it, and its age when it opened over a day ago (live-run row 139).
#      Another task's open record does not refuse this one. `dispatch-close` clears it.
#  38  `build-brief` was given a unit id that is not in the frozen snapshot. The same fact exit 22
#      already names for `tests-brief` and `tests-freeze`; `build-brief` shares the number rather
#      than minting a second one for the same meaning.
#  39  `build-brief` found no <task_folder>/implementation/tests-<unit_id>.json for this unit. Step
#      three (`tests-brief` and `tests-freeze`) has not run for it yet.
#  40  `build-brief` or `dispatch-open implementer` found an order in the given unit's dependsOn
#      with no completion record in the ledger (its lastStep is not "closed"), so that order's
#      interface record does not exist yet. Or a repair the given unit opened on another order
#      has not closed again (gap row 286).
#      The same fact exit 23 names for `tests-brief`, kept apart because the two actions read the
#      dependency for two different reasons: `tests-brief` needs the interface to write tests
#      against it, `build-brief` needs it to hand to the model writing the code.
#  41  `build-brief` or `dispatch-open implementer` found the given unit's attempt counter
#      already at its allowed limit. Nothing is handed over; the order is exhausted.
#  42  `build-brief` ran before `start`, so <task_folder>/implementation/snapshot.json does not
#      exist. A different number from exit 25, which `tests-brief` and `tests-freeze` share for the
#      same fact: `build-brief` gets its own so a caller can tell which step never started without
#      inspecting the message text.
#  43  `build-record` or `fix-record` was given a --started-at that is not a commit in the code
#      repository, or, for an order whose proof is record, in the project folder: such an order's
#      deliverable lives in the task folder, so its range, its tree and its diff are read there
#      (nyc defect 17). Exits 45, 51, 61, 63 and 71 read the same repository for such an order.
#  44  `build-record` or `build-recheck` found the interface record file missing or empty while
#      the given unit declares a non-empty interface. The file is the one --interface names, or
#      without that flag the one the brief's `interfacePath` names (live-run row 102). A file
#      present for a unit that declares no interface is read and recorded without complaint;
#      nothing here judges its content.
#  45  a record for this attempt or this round already exists, so the call would write it twice.
#      `build-record` found build-<unit_id>.json already recorded at the same commit and the same
#      attempt number; `fix-record` found fix-<unit_id>-<round>.json already recorded at the same
#      commit; `verify-brief` found the round already verified in review-<unit_id>.json, so there is
#      nothing left to hand a verifier. The message names both values, because a caller who calls
#      this twice for one attempt or one round is not shown a stale success silently.
#      `verify-record` on a round already verified reports the verification on record instead.
#      With --ruling it applies the rulings to that round's open findings, and writes no second
#      round entry (live-run row 111).
#
#  46  `dispatch-open` was given a role that names no agent under ${CLAUDE_PLUGIN_ROOT}/agents, or
#      found that folder empty. A role nothing checks opens a record no agent's own `agent_type`
#      can match, and both hooks then allow every read and every write in silence, so this refuses
#      rather than writing a record that looks like a permission and is not one.
#  47  `dispatch-open` was asked to open a dispatch whose derived path list would be empty: a test
#      author or a row-checker on a snapshot whose work orders declare no owned file between them,
#      or an implementer
#      or a fixer on an order that declares none of its own. A role's lists are derived from those
#      files, so an empty set means the denial the role exists for would apply to nothing, or the
#      role would be dispatched with nowhere it is meant to write. Or a test author on an order
#      that owns no file a test glob matches and no directory, whose every test the freeze would
#      refuse (gap row 249).
#
# The step-five exit codes. Six actions share these, and each number carries one meaning across all
# six rather than one number per action per fact.
#  48  the ledger records this order at a step the action cannot follow. `review-brief` and
#      `review-record` follow `checks-passed`; `fix-brief` and `fix-record` follow `reviewed` or
#      `fixed`; `verify-brief` and `verify-record` follow `fixed`; `verify-record` with --ruling and
#      no --verdicts also follows `reviewed` (gap row 265); `close` follows `reviewed` or `fixed`.
#      The message names the step found and the steps allowed.
#  49  the order is halted, so the step refuses. Every step-five action refuses on it, and the
#      message carries the halt's own recorded reason. `build-record` refuses on it too, so a
#      halted order records no attempt; --accept-deviation lets the deviation's own halt through.
#  50  a review record already exists for this order, and an order gets one review, ever
#      (ideal/implementation.md, 'One review per order'). `review-brief` refuses to hand over a
#      second brief and `review-record` refuses to write a second record.
#  51  `review-record` found the code repository is not where the build record left it: HEAD moved,
#      or the working tree is dirty. The reviewer holds Write for one purpose, its own findings
#      file under the task folder, and this is the check that enforces it. A probe test left inside
#      the reviewed code is a refusal here, never a finding later.
#  52  a findings or verdict file named on the command line is missing, is empty, or does not hold
#      the shape the action reads. The message names the entry and what was wrong with it. A file
#      this script half understands is worse than no file at all. `review-record` also refuses a
#      finding that cites a file the order owns, or one its diff changes, with an empty or missing
#      fixScope: an empty fix scope skips the fix rounds (gap row 265).
#  53  `fix-brief` or `fix-record` found no open actionable finding for this order, so there is
#      nothing for a fixer to do. `verify-brief` shares it: nothing open means nothing to verify.
#      `fix-brief` also refuses when every open finding has an empty fix scope, and names the
#      ruling route (gap row 265). Unattended, it marks each such finding pending instead, and
#      exits 0: the person rules it at the task review (gap row 279).
#  54  `fix-brief` or `fix-record` found this order's fix rounds already spent (roundsUsed at
#      FIX_ROUNDS_ALLOWED). Every open finding needs a ruling now, not another round. The mirror of
#      exit 41 for the build attempts.
#  55  `verify-record` was given a --ruling on an unattended run. A ruling is a person's judgement,
#      and an unattended run has none to offer (decision 12).
#  56  `verify-record` reached the round cap on an unattended run with findings still open. The
#      order is halted with them named, and the verification itself is recorded first, so a refusal
#      never throws away the verdicts it already read. On a light task a low finding goes pending
#      instead, and the person rules it at the task review (gap row 296).
#  57  `verify-record` reached the round cap with an open finding no --ruling names. Each one needs
#      a ruling and a reason before the order may close. Before the cap a ruling is taken only on a
#      finding a fixer reported out of its scope (`scopeInsufficientInRound`), or on one whose fix
#      scope is empty (gap row 265); any other is exit 3 with the findings that may be ruled now
#      named (live-run row 110).
#  58  `verify-record`'s verdict file and this order's open findings do not correspond: a verdict is
#      missing for an open finding, or a verdict names something that is not open on this order.
#  59  `close` found open actionable findings on this order. An order closes with nothing open.
#  60  `close` found the last fix round unverified: the ledger counts more rounds than the review
#      record holds verifications. A round whose findings only the fixer called addressed is not a
#      round this stage takes as finished.
#  61  `build-record` or `fix-record` was asked to record a run whose working tree is not clean:
#      something is modified, staged or untracked in the code repository. Every check but one reads
#      the working tree, and the owned-files check reads two commits, so an uncommitted change
#      passes that one check while staying in the tree and leaves the round's own diff empty. The
#      role's work is committed before the record is written. Unattended, the two record steps write
#      the halt onto the order before refusing, because an order left in flight with no reason is a
#      halt nobody sees until they ask; interactive they only refuse, since a person is there to
#      commit and run the step again. `build-recheck`, `close`, `finish` and `restart` refuse on
#      the same fact and share this number, because a commit range is a claim about a repository and a dirty tree
#      makes it a claim about something else. A restart with uncommitted work would move the record
#      of that work aside and leave the work itself behind. `review-record` names a related fact with exit 51,
#      and the two stay apart: 51 says the code moved after a record was already written, and 61
#      says it was never committed at all.
#  62  `fix-brief` or `fix-record` was asked for a round while the last one has no verification.
#      `verify-record` is what turns a fixer's own account into a verdict this stage holds, so two
#      rounds spent back to back leave the first round's findings judged by nobody. Exit 60 names
#      the same gap at `close`, by which point both rounds are already spent.
#  63  `close` found the code repository at a commit other than the one the last record for this
#      order was written at: the build record when no fix round ran, the last fix record otherwise.
#      The range this would write would name work nothing in this stage judged.
#
# The exit codes the checkpoint, the finish, the grant and the restart add.
#  64  `tests-freeze`'s own `--row` flags and this order's tests do not correspond: a
#      machine-verified criterion a --test names with no row, a doneWhen test with no doneWhen row,
#      an --absence clause with no row on an order that has other rows (gap row 273), a row
#      naming a criterion no --test claims or the doneWhen with no doneWhen test, a row naming a
#      criterion a person verifies, or two rows naming one thing. The message names
#      which. A row set this script half understands would put a judgement on the wrong criterion,
#      which nothing later could tell from a real one. On missing rows the confirmed rows given
#      are recorded as `rowsConfirmed` first, the same way exit 65 records them (gap row 259).
#  65  `tests-freeze` was given a `--row` that answers rejected. Not a defect in the script: the
#      freeze stops, writes no test record, and the row goes back to the test author, the same way
#      exit 34 stops the step on a test that was green on arrival. Unattended, a row the checker
#      itself rejected halts the order first, because a refusal nobody is there to read leaves the
#      order in flight with no reason on it. A row a person rejected never halts anything: the
#      person is already there. It lands on the order's ledger entry as `rowsRejected`, which the
#      next `tests-brief` carries to the test author. A rejection that lands on no ledger entry
#      ends with a `redAgain: [<test name>, ...]` line instead, as JSON (gap row 258). Either way a
#      `checkAgain: [<row key>, ...]` line names the rows the next checker dispatch covers: each
#      rejected row, each confirmed row with a test in a rejected row's file, and the doneWhen row
#      when an owned row is rejected. Each other confirmed row lands on the ledger entry as
#      `rowsConfirmed`, with its note, and the next freeze carries it when no `--row` gives it and
#      its test files did not change since. A freeze that then writes prints a
#      `rowsCarried: <row key>, ...` line naming the rows it carried. A repair round's checker
#      judges only the rows put to it, so those notes are on disk nowhere else (gap row 259).
#  66  `finish` found implementation is not finished for this task: an order that is not closed, an
#      order carrying a halt whether or not it closed, or a machine-verified criterion whose row
#      state is not confirmed. The message names every one of them.
#  67  `grant-attempt` was asked for an attempt it cannot grant: the order is already closed, so
#      there is nothing left to attempt, or it is halted for something other than a spent attempt
#      counter. A grant answers a spent counter and answers nothing else, so the message names what
#      it found and nothing is written. One number, because both are the same fact: this order is
#      not waiting on another attempt.
#  68  `grant-attempt`, `restart` or `clear-halt` was called on an autonomous run. Each is a
#      person's judgement, and an unattended run has none to offer. One number, because it is one
#      fact. `review-record --accept-deviation` is the same fact (gap row 224), and so is
#      `build-record --accept-deviation` (gap row 266).
#  69  `restart` found no order halted for design drift. There is nothing to restart from, and a
#      restart that reset an order anyway would throw away a build that is fine.
#  70  `tests-freeze` was given a `--row` judged by a person on an autonomous run. An autonomous run
#      has no person to judge a row, so `person` there is a claim nobody made. Nothing is written.
#      `model` is accepted on both runs. The row-checker judges every row in both modes, and a
#      person on an attended run answers only a row it rejected (live-run row 70).
#
# The codes the paper test added. Each one is a fact nothing refused before.
#  71  `build-record` or `fix-record` was given a `--started-at` that cannot be the commit the work
#      began from: it is the commit HEAD is at now, so the diff would be empty and every check would
#      answer about nothing, or it is not an ancestor of HEAD, so the range between the two is not
#      this order's own work. Exit 43 stays the separate fact that the value is not a commit at all.
#  72  two frameworks each declare a command for one check row, and nothing here may choose between
#      two answers to one question. The message names both frameworks and the row.
#  73  the check recipe resolved for a framework moved after this task's baseline was taken: its
#      sha256 differs. Every tool check compares its own result against that baseline, so a changed
#      recipe compares one tool's output against another tool's baseline. The baseline is not
#      retaken mid-task: it reads the tree before the task, and the tree now holds this task's own
#      code. Run again with the recipe body the baseline read. `recipe-refresh --check-recipe`
#      refuses with this code too, when a tool row of the new body reads neither met nor
#      undeclared on the current tree (gap row 295). The message names each such row.
#  74  `tests-freeze` was asked to freeze an order that serves and owns no criterion at all, or one
#      whose record would hold no row: no test named, no doneWhen test, no checklist. Every guard
#      in that step reads a per-criterion list, so an order with none passes all of them and
#      freezes a reference that proves nothing. An order whose proof is gate, record or observe is
#      exempt from the second half: its record holds no test row on purpose.
#  75  retired on 2026-09-22 (live-run row 139). `dispatch-close` refused a task folder that was
#      not the one the open record named, while the record lived at the project root. It now
#      lives under the task's own folder, so a close reaches this task's record and no other.
#  76  `tests-freeze` was asked to re-freeze an order that has already left the frozen state. A
#      re-freeze rewinds the step and leaves the spent attempt counter and the stale build record
#      where they are, so the order would rebuild with no attempts and a record for tests that no
#      longer exist. `retake-tests` is the route back: it moves those records aside and sets the
#      step, so the freeze after it does not fire this (exit 99 below).
#  77  `preconditions` read a valid project.json that records no framework, so no recipe can be
#      chosen for it. Exit 14 stays the separate fact that the file is not valid JSON at all.
#  78  `dispatch-open` found the run at the ceiling task.json's `budget` sets, in dispatches or in
#      minutes. The order is halted with `budget spent` and both numbers; the grant path answers it.
#  79  the action was run from outside the task's own worktree; every stage action but `read` runs there.
#  80  `tests-freeze` was given a --red whose file holds none of the assertion markers the
#      test-execution recipes declare under `failure_signal:` and no line their suite row's
#      `failure_line` names (`--test-recipe`, the flag `build-record` already takes), so the run it
#      holds did not fail a test. A file that holds a harness marker instead is named as a setup
#      gap: the run never reached the behaviour (live-run row 68), unless the order creates the
#      unit: an owned file matches a glob under `## Unit declaration` in an `--implement-recipe`,
#      and the file is then accepted as `harness-new-unit`. The same exit when no
#      --test-recipe was given beside a --red, because then no red can be read at all. A recipe set
#      declaring neither a marker nor a selector records the red unchecked instead of refusing.
#      The same exit when two tests of one file have reds that print the same places in it: they
#      failed on a shared precondition, not on their own assertions (live-run row 207).
#  81  `tests-freeze` was given an --absence the order cannot route to review. Two facts, one
#      refusal, because both say the same thing: the flag names something that is not an absence
#      clause of this order. The clause is not, verbatim, one of the order's frozen `doneWhen`
#      entries; or it carries no negation word, which makes it a clause asserting a presence, and a
#      presence is proved by a test that was watched failing (live-run row 184).
#  84  the assembled checks do not count what the record schema requires: eight at `build-record`
#      (build-record-schema.json) and seven at `fix-record` (fix-record-schema.json). A record
#      that lost one would read complete while it is not. The message names the absent check.
#      Nothing is written and no attempt or round is spent.
#
# The codes a resumed `start` added (nyc defects 10 and 19).
#  82  a resumed `start` found HEAD is not a descendant of the ledger's own startedFrom. The branch
#      was rewritten under the build, by a rebase or an amend. Left alone, `preconditions` labels
#      the baseline with a commit on no branch and `finish` computes a range git cannot resolve.
#      The message names `start --rebased-onto <commit>`. That sets startedFrom to the commit the
#      branch now builds on and keeps the old value under startedFromBefore with the date. The
#      flag is an argument error, exit 3, in four cases. Its value is not a commit, not an
#      ancestor of HEAD, or the value already held. HEAD still descends from startedFrom, so
#      nothing was rewritten. The run has no ledger to rewrite.
#  83  a resumed `start` found baseline.json outside the shape this version writes. That is a
#      required field missing or of the wrong type against baseline-schema.json. Or it is a suite
#      or tool entry that ran (it carries exitCode) with no outputFile. `build-record` subtracts from
#      outputFile alone, so such a baseline reads every failing tool check unknown. An attempt is
#      then spent on a schema change. The message names the retake. Exit 3 stays the separate fact
#      that the file is not JSON at all.
#  86  `finish` ran the suite once at HEAD and it did not answer met or undeclared (nyc defect 18).
#      The record steps leave a suite row the recipe costs `end-of-task` unrun, recorded deferred,
#      so this run is the one that decides it. Unmet names the lines new since the baseline, the
#      first twenty, and the sidecar holding the whole output; a fix commit on the branch and a
#      second `finish` is the route. Unknown names its own cause: no baseline to subtract from, a
#      placeholder with no --value, a runner not found, or a run that selected nothing. Nothing
#      is recorded; the sidecar stays, because it is what a person reads next. `not-needed` never
#      lands here. A task whose every order is proved by its record ran no test, so the suite
#      is recorded not-needed and not run (live-run row 136).
#
# The code the record proof added (nyc defect 17).
#  87  a step reading the range of an order whose proof is record found the project folder is not
#      a git repository. Such an order lands its deliverable in the task folder, so its commits are
#      the project folder's, and with no history there the range cannot be read. Exit 5 stays the
#      separate fact that the code path is not a repository.
#
# The code `clear-halt` added (nyc defect 20).
#  85  `clear-halt` was asked to clear a halt another action answers: one holding an `attempts
#      spent` or `budget spent` segment, which `grant-attempt` clears, a `design drift` segment,
#      which `restart` clears, or a `test wrong` segment, which `retake-tests` clears. The message
#      names that action, and for a drift halt it also names `start`, which clears a segment about
#      the order's own design file once its comparison finds no drift. Nothing is written. Every other
#      halt (a row the checker rejected, a finding on a non-goal, a fixer's scope, a finding ruled
#      load-bearing, a dirty tree, spent fix rounds) is a person's to clear, once they have acted on
#      what it names, and this is the one action that clears it. A closed order shares exit 67 with
#      the grant: there is nothing to resume.
#
# The code the re-check added (live-run row 87).
#  88  `build-recheck` cannot run the checks again over the recorded range, for one of five facts,
#      each named in its own message. No build record exists for the order, so there is no range.
#      The repository's HEAD is not the record's own `commit`, so the code moved and the route is
#      `build`. Or the record's stopping checks include one outside `coding-standards`,
#      `static-analysis`, `security` and `interface-record`. A test or a suite that failed is the
#      implementer's work, so a re-check would be a free retry, and the route is `build`. Or no
#      check stopped the attempt, so it passed and the order is past the build. Or a path the
#      interface check named does not exist at the recorded commit, so no amended record can
#      answer it (gap row 253). A halted order refuses at exit 49 like every step-five action, and
#      `grant-attempt` is its route.
#
# The code the support files added (live-run row 90).
#  89  `tests-freeze` was given a --support whose path does not exist on disk, or whose path
#      matches one of the given --test-glob patterns. A support file is a base class or a fixture
#      the test author wrote beside the tests, hashed and committed with them; a path a test glob
#      matches is a test, and belongs on --test. A support path outside codePath shares exit 36.
#
# The codes a recipe refreshed mid-task added (live-run row 99).
#  90  `recipe-refresh` was given a framework preconditions.json holds no resolved recipe for, or a
#      path that does not exist. With --check-recipe, it is a framework baseline.json pins no review
#      recipe for, or a task with no readable baseline. Both are a lookup that answered for nothing on record: every
#      reader of a recipe path filters on `lookup == "resolved"`, so a path written beside a failed
#      lookup would reach nothing, and the first path is preconditions' to record. Nothing is
#      written.
#  91  `tests-freeze` was given a --test-recipe whose path is not the one preconditions.json
#      records for that framework. The freeze reads reds against one recipe and build-record reads
#      the record's, so two paths for one order would stand its two records on two recipes. The
#      message names both paths and `recipe-refresh` as the route. Nothing is frozen.
# The codes the observe proof added (live-run row 104). An order whose proof is observe is judged
# by a model's look through a browser after the build: the orchestrator opens each of the order's
# surfaces at each viewport, judges each done-when row against what renders, and writes
# <task_folder>/implementation/observed-<unit_id>.json (observed-schema.json) with a screenshot
# per row. `build-record` reads it through --observed and refuses, one number per fact:
#  92  no --observed was passed for an order whose proof is observe. The message names the flag.
#  93  the --observed file is missing, is not JSON, or does not match observed-schema.json: no
#      order, observedAt, judgedBy or rows, an order that is not this unit, a judgedBy that is
#      not model, or a row without doneWhen, surface, viewport, screenshot, before, verdict and
#      note. Or it is at a path other than <task_folder>/implementation/observed-<unit_id>.json: a fix
#      round and a re-check read that path and no other, so a record accepted from elsewhere
#      would pass the build and stop every fix round. The message names the path.
#  94  a row names a screenshot that is not on disk, or one that lies outside
#      <task_folder>/implementation/observed-<unit_id>/. The look is the evidence, and a row with
#      no image is a claim. A file where a browser tool put it vanishes with that folder (live-run
#      row 112). The same for a row's before image, against
#      <task_folder>/implementation/observed-<unit_id>-before/: a sameness row has no before to
#      judge from without it (live-run row 114). The message names which field, each path and
#      the folder.
#  95  a row names a surface the order does not name. The order's surfaces are the pages it
#      changes, and a look at another page proves nothing about this order.
#  96  a row's doneWhen is not one of the order's own done-when rows, nor the verification clause
#      of a machine criterion the order owns. The row is the sentence a model judges, and a
#      judgement of another sentence is not this order's proof. A row whose sentence is a clause
#      carries `criterion`. The same code refuses a clause row without it. It refuses a
#      `criterion` the order does not own, or one whose clause is not the row's sentence
#      (live-run row 115).
#  97  a row the order owes is missing: one per sentence, per surface the order names, per
#      viewport the surface file declares. The sentences are the done-when rows and each owned
#      machine criterion's verification clause. The rows may say less than the clause, and no
#      script can tell, so the look judges the clause too (live-run row 115). A look not taken
#      is not a met, and the check reads every row present as the whole only when the whole is
#      there. The message names the first missing row and whether it is a done-when row or a
#      criterion's clause.
#  98  the surface file cannot be read, so the rows the order owes cannot be known: the project
#      record names no surfaces.registryPath, the file is missing or unreadable, or it declares
#      no viewport. The surfaces skill's install writes it.
#
# The code a wrong frozen test after the build added (live-run row 110).
#  99  `retake-tests` was asked for an order whose halt does not begin `test wrong:`. A retake moves
#      the build, review, fix and verify records aside and sends the order back to `tests-frozen`,
#      which is right only after a person ruled a finding `test-wrong` at `verify-record`. The
#      message names the halt found, or that the order is not halted, and nothing is written.
#
# The code a fix scope outside the order's files added (live-run row 116).
# 100  `fix-brief` was given `--allow` on an unattended run. An allow is a person's grant of one
#      path outside the order's ownedFiles to one fix round. An unattended run has nobody to
#      grant it. Nothing is written. Three argument faults stay exit 3: a path already owned, a
#      frozen test or support file, and a path no open finding's fixScope names.
#
# The code the commit form of a locks-in reason added (live-run row 183).
# 101  `tests-freeze` was given a `--locks-in` reason written `commit:<id>` whose id is not
#      hexadecimal, is shorter than seven characters, or is not one of this order's own build or
#      fix commits on the branch. The message names the id and lists the commits that are this
#      order's own, which `tests-brief` already put in the brief under `treeHolds`. After a rebase
#      it also names each recorded commit with no copy here that can be cited, and why. A reason
#      with no `commit:` prefix is prose, names the existing code, and never reaches this check.
# 102  `dispatch-open` was given a role the order's proof kind does not need: a test author on an
#      order that freezes no test, or a row-checker on one that freezes no row. br_order_needs in
#      scripts/lib/proof.sh decides, and `read` prints its answer on the order's line.
#
# The code the site check before the verify lines added (gap row 212).
# 103  `build-record`, `build-recheck` or `fix-record` found the task's site down. The `## Status`
#      line of the environment recipe exited non-zero, in either run mode. The message quotes its
#      first line of output and names `task environment <id> up`. No check ran and nothing is
#      written, so the same step runs again once the site is up.
# The code the leftover check added (gap row 217).
# 104  `start` found uncommitted files in the task's tree, on an interactive run given no
#      `--leftovers`. Or `--leftovers set-aside` met a change other than an untracked or a modified
#      file. The message names each path and the orders whose owned files hold it. Nothing is
#      written and nothing moves. Since gap row 228 `dispatch-open` refuses the same way before a
#      fresh role meets such files. A row-checker, a test author sent back for a rejected row, and
#      `--resume` are exempt.
# The code the builder's stop added (gap row 219).
# 105  `build-record` was given a report whose stop line is not `Stop: none`. The builder
#      stopped, so this is not an attempt, whatever it committed. The message quotes the line and
#      names each commit after --started-at. Nothing is recorded and no attempt is spent.
#      Unattended, the order halts first, and the halt names the commits. A deviation line other
#      than `Deviation: none`, or a heading that starts with "Deviation", in the report or the
#      interface record, is a stop too (gap row 221). A person keeps a deviation with
#      --accept-deviation, interactive only (exit 68), and the message and the halt name that
#      route. A stop line other than `Stop: none` has no such route (gap row 266). Unattended, a
#      deviation is no stop: the attempt is recorded, and review-record keeps it (gap row 279).
#      A `Stop: closed-order-defect: <file>: <what fails>` line naming a file a closed order owns
#      exits 0 instead: br_open_repair reopens that order for one fix round (gap row 286).
# 106  `build-record` was given a report with no stop line, or more than one. Or its stop line is
#      `Stop: none`, and it holds no deviation line, or more than one. Nothing is recorded and no
#      attempt is spent. A builder stopped at its turn limit writes no stop line, so the message
#      names `dispatch-open --resume` (gap row 228). A stop or deviation line in the report or the
#      interface record that reads none followed by more text refuses the same way (gap row 298).
#
# The code a departure at review added (gap row 224).
# 107  `review-record` found a departure the builder declared, by build-record's own scan, in the
#      latest attempt's report or in the interface record the build record holds. What is wrong is
#      the design, or a recipe it relies on, so the order halts for design drift, whatever the
#      review holds. The halt names the file and the line. No review record is written. A person
#      accepts the departure with --accept-deviation instead, interactive only (exit 68). A recipe
#      the reviewer answers departed takes the same route, under a halt of its own wording (gap
#      row 225). Unattended, nothing halts: the record holds the departure as deviationPending,
#      and the person decides it at the task review (gap row 279). A departed recipe answer whose
#      `finding` names an actionable finding with a fix scope halts nothing in either mode: the
#      fix round cures it and verify confirms the cure (gap row 303).
#
# The code the reviewer's recipe answers added (gap row 225).
# 108  `review-record` found the findings file's `recipes` list does not answer the review
#      brief's `recipes` list one to one: a recipe with no answer, an answer given twice, or an
#      answer naming one the order does not carry. Nothing is written. The message names the next
#      step: review-brief again, then the reviewer again. The check runs before --accept-deviation
#      is read, so a person never accepts on a review that skipped a recipe.
#
# The code the stale red run added (gap row 229).
# 109  `tests-freeze` was given a --red file written before the order's test round began, the
#      tests brief's `roundStartedAt`, or before its own test file last changed. It is a run of
#      earlier tests, such as those a restart set aside. The message names each file and both
#      times, and a last line `redAgain: [<test name>, ...]` names each test to run again, as
#      JSON (gap row 258). Nothing is frozen.
# The codes the turn cap added (gap row 228).
# 110  `dispatch-close --no-report` found the open record's resumes already at its
#      `resumesAllowed`, 1 when absent: the role was resumed that many times and returned with no
#      report again. The order halts with a reason naming
#      the role and its `maxTurns`, and the record is removed. A person runs clear-halt, then
#      start, then dispatches again.
# 111  a plain `dispatch-close` on a reviewer's record found the file its brief names missing, or
#      no newer than the record: `findingsPath` in review mode, `verdictsPath` in verify mode after
#      the ledger's `fixed`. The record stays open. The message names `--no-report`.
# The code the completion line added (gap row 250).
# 112  a plain `dispatch-close` on a fixer's or a test author's record found the report its brief
#      pins missing, no newer than the record, not ending with the line `Report: complete`, or
#      holding nothing but that line. A fixer's report must also be no older than the last commit
#      in codePath, because the fixer commits and then writes the line. A test author commits
#      nothing, so its report is read by the line alone. The role stopped before its last act, so
#      the close runs as `--no-report` does: the record stays open and takes `resumedAt`. A second
#      such close halts the order at exit 110, and the halt names the cause. `dispatch-open`
#      without --resume removes the role's earlier report, so an old complete one cannot pass.
#      `fix-record` refuses a --report other than the one the fix brief pins (exit 3).
# The code the reverting restart added (gap row 252).
# 113  `restart` found a commit of a halted order that also changes a file the order does not own,
#      or a merge that changes the order's files. A revert of the first would undo that other work
#      too, and a revert of a merge needs a person to choose its parent. So nothing is reverted,
#      moved or written. The message names each such commit, its order and the other files. A
#      person splits or reverts the commit, then runs restart again.
# The code the implementer's freeze check added (gap row 267).
# 114  `dispatch-open` was given the implementer role for an order with no
#      <task_folder>/implementation/tests-<unit_id>.json. The same fact exit 39 names for
#      `build-brief`, with the same message. Nothing is written, so no record opens for a build
#      that has no brief. Run tests-freeze on the order first. The implementer role also takes
#      `build-brief`'s ledger refusals and its exits 40, 41 and 116, with the same codes and words
#      (gap row 281).
# 115  `dispatch-open` was given the reviewer role for an order with no reviewer brief:
#      brief-<unit_id>-review.json, or brief-<unit_id>-verify-<round>.json after a fix round. The
#      message names the step that writes it. Nothing is written. Kept apart from 114 because the
#      repair differs: a missing brief needs review-brief or verify-brief, not tests-freeze.
# The code the build-step check added (gap row 281).
# 116  `build-brief` or `dispatch-open implementer` found the order at a ledger step no build starts
#      from. A build starts from tests-frozen, or from code-written to rebuild a failed attempt. The
#      message names the step and what to run instead. Nothing is written.
#
# Portability: bash 3.2+ and zsh. No mapfile, no associative arrays, no GNU-only flag, no awk, no
# regular-expression interval quantifier anywhere (foundations.md, Honesty). sha256sum exists on
# Linux and `shasum -a 256` on macOS; scripts/lib/records-hash.sh tries both. An id's own shape,
# where one is checked, uses a `case` glob, never a regular expression.
#
# Five zsh traps have each cost a round of debugging in this file. They are listed here because
# three of them were re-introduced by somebody who had already been told about them, and a warning
# that has to be repeated is not a control.
#   1. Never name a variable `path`. zsh ties that exact name to $PATH as a special array. Under
#      this file's own nounset the tie makes a plain assignment unreadable, and every external
#      command inside that function stops resolving. Check any new name against zsh's own special
#      parameters with `typeset -p <name>` before using it.
#   2. zsh does not word-split an unquoted expansion. Anything that relies on splitting sets
#      SH_WORD_SPLIT inside its own subshell first, and never leaks the option to the caller.
#   3. zsh does not expand an unquoted variable used as a `case` pattern. It matches the literal
#      text instead. GLOB_SUBST fixes it, scoped the same way.
#   4. A `local a=X b="$a"` statement evaluates every assignment word before any of them takes
#      effect, in bash and zsh alike, so `b` reads the value from before the call. Declare bare,
#      then assign in a statement of its own.
#   5. Never put `local` inside a loop body. zsh prints a parameter when `local` names one that
#      already exists in the same scope, with no option asking it to, so the second round of the
#      loop writes `name=<the previous round's value>` to standard output. Every action here prints
#      `key: value` summary lines on standard output, so that line reads as one more of them, and it
#      appears only when the loop runs more than once: a fixture with one criterion per order never
#      sees it.
#      Declare every name the loop uses above the loop, and assign inside it.

set -uo pipefail  # not -e: several branches test a command's exit code on purpose.
trap '' PIPE  # a closed pipe must not kill the writes after a print; research-actions.sh says why

if [ -n "${ZSH_VERSION:-}" ]; then
  setopt KSH_ARRAYS 2>/dev/null
fi

if [ -n "${ZSH_VERSION:-}" ]; then
  SCRIPT_SOURCE="$0"
else
  SCRIPT_SOURCE="${BASH_SOURCE[0]}"
fi
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd -- "$(dirname -- "$SCRIPT_SOURCE")/../../.." >/dev/null 2>&1 && pwd -P)}"
if [ -z "$PLUGIN_ROOT" ] || [ ! -d "$PLUGIN_ROOT" ]; then
  printf 'implement-actions: could not resolve the plugin root (CLAUDE_PLUGIN_ROOT is not set and the script'"'"'s own location could not be resolved)\n' >&2
  exit 3
fi
CHECK_DESIGN_SCRIPT="${PLUGIN_ROOT}/scripts/check-design.sh"
STEPS_DIR="${PLUGIN_ROOT}/skills/implement/references"
RECORDS_HASH_LIB="${PLUGIN_ROOT}/scripts/lib/records-hash.sh"
RECIPES_LIB="${PLUGIN_ROOT}/scripts/lib/recipes.sh"
TASK_HELPERS_LIB="${PLUGIN_ROOT}/scripts/lib/task-helpers.sh"
SCHEMA_CHECK_LIB="${PLUGIN_ROOT}/scripts/lib/schema-check.sh"
PROOF_LIB="${PLUGIN_ROOT}/scripts/lib/proof.sh"
SURFACES_LIB="${PLUGIN_ROOT}/scripts/lib/surfaces.sh"
PATHS_LIB="${PLUGIN_ROOT}/scripts/lib/paths.sh"
BUILDER_LINES_LIB="${PLUGIN_ROOT}/scripts/lib/builder-lines.sh"
BASELINE_SCHEMA_FILE="${PLUGIN_ROOT}/scripts/baseline-schema.json"
OBSERVED_SCHEMA_FILE="${PLUGIN_ROOT}/scripts/observed-schema.json"

command -v jq >/dev/null 2>&1 || { printf 'implement-actions: jq is required and was not found on PATH\n' >&2; exit 3; }

die() { printf 'implement-actions: %s\n' "$2" >&2; exit "$1"; }
# One refusal function, one exit code as its first argument. The exit-code table above is the
# only place a number gets a meaning, and nothing here mints one that table does not carry.

# task-helpers.sh takes these three from its caller, so a refusal still says which script refused.
die1() { die 1 "$1"; }
die3() { die 3 "$1"; }
die79() { die 79 "$1"; }

# The task-folder resolver, the atomic write and the task start, shared with every other stage.
[ -f "$TASK_HELPERS_LIB" ] || die 3 "cannot find the task-helper library at $TASK_HELPERS_LIB"
# shellcheck source=/dev/null
source "$TASK_HELPERS_LIB" || die 3 "the task-helper library failed to load: $TASK_HELPERS_LIB"

[ -f "$RECORDS_HASH_LIB" ] || die 3 "cannot find the records-hash library at $RECORDS_HASH_LIB"
# shellcheck source=/dev/null
source "$RECORDS_HASH_LIB" || die 3 "the records-hash library failed to load: $RECORDS_HASH_LIB"

# The recipe blocks, the commands they declare, the command runner, the clean-tree refusal and the
# code-path loader. They were written here and moved to the library when the review stage needed
# the same ones; this file calls them and never carries a second copy. It is sourced after
# records-hash.sh, which cr_resolve and tf_sha256_of both depend on.
[ -f "$RECIPES_LIB" ] || die 3 "cannot find the recipes library at $RECIPES_LIB"
# shellcheck source=/dev/null
source "$RECIPES_LIB" || die 3 "the recipes library failed to load: $RECIPES_LIB"

[ -f "$SCHEMA_CHECK_LIB" ] || die 3 "cannot find the schema-check library at $SCHEMA_CHECK_LIB"
# shellcheck source=/dev/null
source "$SCHEMA_CHECK_LIB" || die 3 "the schema-check library failed to load: $SCHEMA_CHECK_LIB"

# What one order's proof kind means for a check about to answer. Every step below reads its three
# variables, or its jq twin where the question is asked over the whole snapshot at once.
[ -f "$PROOF_LIB" ] || die 3 "cannot find the proof-kind library at $PROOF_LIB"
# shellcheck source=/dev/null
source "$PROOF_LIB" || die 3 "the proof-kind library failed to load: $PROOF_LIB"

# The surface file reader review uses, and the path join it needs: the observed check reads the
# viewport list from the same file review's surface step reads, so there is one reader.
[ -f "$SURFACES_LIB" ] || die 3 "cannot find the surfaces library at $SURFACES_LIB"
# shellcheck source=/dev/null
source "$SURFACES_LIB" || die 3 "the surfaces library failed to load: $SURFACES_LIB"
[ -f "$PATHS_LIB" ] || die 3 "cannot find the paths library at $PATHS_LIB"
# shellcheck source=/dev/null
source "$PATHS_LIB" || die 3 "the paths library failed to load: $PATHS_LIB"
# The builder's stop and deviation lines, read the same way by build-record and by the hook that
# sends the implementer back to its answers file before it returns (gap row 304).
[ -f "$BUILDER_LINES_LIB" ] || die 3 "cannot find the builder-lines library at $BUILDER_LINES_LIB"
# shellcheck source=/dev/null
source "$BUILDER_LINES_LIB" || die 3 "the builder-lines library failed to load: $BUILDER_LINES_LIB"

# How many times `build-brief` will hand one order to a builder before refusing (exit 41). Two, not
# version 5's three: nothing in version 5 justifies three beyond a clamp guarding a corrupted
# counter, never the cap itself. A constant here rather than a project or task field, because
# nothing yet gives it a producer of its own; a later stage may compute it instead.
BUILD_ATTEMPTS_ALLOWED=2

# The default above is what an order gets when its own ledger entry carries no `attemptsAllowed`.
# `grant-attempt` writes that field, one higher, when a person grants another attempt. The count
# used never goes down, so the grant raises the allowance instead (ideal/implementation.md, "What a
# halt at the attempt cap leads to"). $1 the order's own ledger entry. Prints the number.
attempts_allowed_for() {
  local entry="$1" value
  value="$(printf '%s' "$entry" | jq -r --argjson d "$BUILD_ATTEMPTS_ALLOWED" '.attemptsAllowed // $d')"
  case "$value" in ''|*[!0-9]*) value="$BUILD_ATTEMPTS_ALLOWED" ;; esac
  printf '%s' "$value"
}

# How many fix rounds one order gets after a review, before every still-open finding needs a ruling.
# Two, for the same reason the build gets two attempts: a third round is a model repeating itself
# rather than learning something new. A constant here beside the attempt cap, so the two caps are
# read and changed in one place.
FIX_ROUNDS_ALLOWED=2

# The fix rounds one order is allowed. A light task gets one. So does an order whose rounds were
# recorded on a light task: a person who sets the task interactive to rule is then not offered a
# second round light never allows (gap row 296). Each repair a dependent order opened adds its one
# round, so roundsUsed never goes down (gap row 286). $1 the order's ledger entry.
order_fix_rounds_allowed() {
  local allowed="$FIX_ROUNDS_ALLOWED"
  if task_is_light "$TASK_PATH" || [ "$(printf '%s' "$1" | jq '.lightRounds // false')" = "true" ]; then
    allowed=1
  fi
  printf '%s' "$((allowed + $(printf '%s' "$1" | jq '(.repairs // []) | length')))"
}

# The last line a fixer and a test author write in the report their brief pins, as their last act
# (gap row 250). dispatch-close reads its absence as a stop before the role finished.
IM_REPORT_DONE="Report: complete"

# A light task allows a fake off the demo path, marked in the code with this text. The build brief
# names it, and `close` logs every added line that carries it (gap row 197).
FAKE_MARKER="AIDA-FAKE:"

usage() {
  cat <<'EOF' >&2
usage: implement-actions.sh read  <task_folder>
       implement-actions.sh start <task_folder> [--rebased-onto <commit>]
                            [--leftovers <keep|set-aside>]
       implement-actions.sh preconditions <task_folder>
                            [--recipe <framework>=<path>]...
                            [--check-recipe <framework>=<path>]...
                            [--lookup-failed <framework>=<no-recipe|listing-unreachable|fetch-failed>]...
                            [--implement-lookup <framework>=<path|no-recipe|listing-unreachable|fetch-failed>]...
                            [--check-lookup-failed <framework>=<no-recipe|listing-unreachable|fetch-failed>]...
                            [--tooling <tool>=<path>]...
                            [--catalog-recipe <framework>=<path|no-recipe|listing-unreachable|fetch-failed>]...
                            [--value <name>=<value>]...
       implement-actions.sh recipe-refresh <task_folder> [--recipe <framework>=<path>]...
                            [--check-recipe <framework>=<path>]...
       implement-actions.sh tests-brief  <task_folder> <unit_id>
       implement-actions.sh tests-freeze <task_folder> <unit_id>
                            [--test <path>::<test name>=<criterion id>[,<criterion id>...] | <unit_id>]...
                            [--red <test name>=<path to a file holding what the run printed>]...
                            [--test-recipe <framework>=<path>]...
                            [--implement-recipe <framework>=<path>]...
                            [--test-glob <glob>]...
                            [--checklist <criterion id>=<verification text>]...
                            [--row <criterion id> | <unit_id>=<confirmed|rejected>::<person|model>::<note>]...
                            [--green-on-arrival <test name>=<reason>]...
                            [--locks-in <test name>=<reason or commit:<id>>]...
                            [--absence <a doneWhen clause of this order, verbatim>]...
       implement-actions.sh build-brief  <task_folder> <unit_id>
       implement-actions.sh build-record <task_folder> <unit_id>
                            [--interface <path to the record the builder wrote>]
                            --report <path to the builder's report>
                            --started-at <commit the attempt began from>
                            [--test-recipe <framework>=<path>]...
                            [--check-recipe <framework>=<path>]...
                            [--value <name>=<value>]...
                            [--nothing-ran <literal substring>]
                            [--accept-deviation <the person's reason>]
       implement-actions.sh build-recheck <task_folder> <unit_id>
                            [--interface <path to the interface record the builder wrote>]
                            [--test-recipe <framework>=<path>]...
                            [--check-recipe <framework>=<path>]...
                            [--implement-recipe <framework>=<path>]...
                            [--value <name>=<value>]...
                            [--nothing-ran <literal substring>]
       implement-actions.sh review-brief  <task_folder> <unit_id>
       implement-actions.sh review-record <task_folder> <unit_id> --findings <path>
                            [--accept-deviation <the person's reason>]
       implement-actions.sh fix-brief     <task_folder> <unit_id> [--allow <path relative to codePath>]...
       implement-actions.sh fix-record    <task_folder> <unit_id>
                            --report <path to the fixer's report>
                            --started-at <commit the round began from>
                            [--test-recipe <framework>=<path>]...
                            [--check-recipe <framework>=<path>]...
                            [--value <name>=<value>]...
                            [--nothing-ran <literal substring>]
                            [--scope-insufficient <finding id>=<reason>]...
       implement-actions.sh verify-brief  <task_folder> <unit_id>
       implement-actions.sh verify-record <task_folder> <unit_id> [--verdicts <path>]
                            [--ruling <finding id>=<wrong|deferred|load-bearing|test-wrong>::<reason>]...
                            (--verdicts is required until the round is on the record; after that,
                            --ruling alone rules on the round's open findings, or at reviewed on
                            findings whose fix scope is empty)
       implement-actions.sh close <task_folder> <unit_id>
       implement-actions.sh finish <task_folder> [--value <name>=<value>]...
                            [--accept-warnings <the person's reason>]
       implement-actions.sh grant-attempt <task_folder> <unit_id> --reason <text>
       implement-actions.sh restart <task_folder> --reason <text>
       implement-actions.sh unattributed <task_folder>
       implement-actions.sh clear-halt <task_folder> <unit_id> --because <text>
       implement-actions.sh retake-tests <task_folder> <unit_id>
       implement-actions.sh dispatch-open <task_folder> <role> <unit_id>
                            [--deny-read <path relative to codePath>]...
                            [--allow-write <path relative to codePath>]...
                            [--test-glob <glob from the implement recipe>]... [--resume]
       implement-actions.sh dispatch-close <task_folder> [--no-report]
       implement-actions.sh step <name>
EOF
}

# The one definition of how a halt reason is written, as a jq function every caller prepends to its
# own program. The new reason goes first and the older ones follow, joined by "; earlier: ", so a
# second halt never erases the first and the newest is what a reader sees first. A segment already
# in the text is moved to the front rather than added again, so running a step twice repeats no
# text. Every reader that looks for one kind of halt splits on the same separator and tests each
# segment, never only the front (`restart` and `grant-attempt` below).
#
# The separator is literal text inside a reason, so a reason carrying "; earlier: " of its own would
# split into two segments. Every reason this script writes is its own words plus a tool's output or
# a checker's note, and none has carried it; the alternative, a list field on the order, is a shape
# no reader outside this file asks for yet.
# The new reason is split on the same separator too. One run that found two reasons for one order
# writes them as two segments, and a later run that finds the same two repeats neither.
HALT_MERGE_JQ='def halt_merge($old; $new):
  (($new // "") | if . == "" then [] else split("; earlier: ") end) as $fresh
  | (($old // "") | if . == "" then [] else split("; earlier: ") end) as $segments
  | ($fresh + ($segments | map(select(. as $s | ($fresh | index($s)) == null)))) | join("; earlier: ");
'

# Every segment of halt reason $1, one per line. Empty prints nothing.
halt_segments() {
  printf '%s' "$1" | jq -r 'if . == "" then empty else split("; earlier: ")[] end' 2>/dev/null
}

# The two drift reasons a later `start` can re-derive: both compare the snapshot's own copy of one
# order against the live design file, and the snapshot keeps that copy while the order is halted.
# A criterion reason and a reason naming another order are not here; the comment in `start` says why.
DRIFT_OWN_COPY_PREFIXES='["design drift: the design file for ","design drift: the design removed "]'

# The segments of halt reason $1 that begin with one of the prefixes in JSON array $2, joined back
# into a halt reason. $3 is `keep` for those segments, or `drop` for every other one. Empty prints
# nothing. One splitter for both actions that remove one halt and keep the rest: `grant-attempt`
# answers a spent counter, and `start` answers a drift its own comparison no longer finds.
halt_segments_matching() {
  printf '%s' "$1" | jq -Rr --argjson prefixes "$2" --arg how "$3" '
    if . == "" then empty
    else (split("; earlier: ")
          | map(. as $segment
                | select(([ $prefixes[] | . as $prefix | select($segment | startswith($prefix)) ] | length > 0) == ($how == "keep")))
          | join("; earlier: "))
    end'
}

# Applies a halt to one order in ledger document $1. $2 the unit id, $3 the reason. Prints the
# updated document, or nothing when the update failed; never dies, because one caller refuses
# afterwards and another carries on.
# Refuses free text that carries the separator halt reasons are joined and split on. Two reasons
# embed text this script does not write: a row-checker note and a fixer report of its own scope. A
# note reading "the assertion is weak; earlier: design drift: forced" forges a segment, and every
# reader that splits on the separator then reads a halt nobody wrote. The separator is refused at
# the flag rather than stripped, because a reason silently altered is a reason a person cannot
# match against what they typed. $1 the action, $2 the flag, $3 the text.
HALT_SEPARATOR="; earlier: "
halt_refuse_separator() {
  case "$3" in
    *"$HALT_SEPARATOR"*)
      die 3 "$1: $2 was given a reason holding the text '$HALT_SEPARATOR', which is how this stage joins one halt reason to another. A reason carrying it would forge a halt nobody wrote. The reason given: $3"
      ;;
  esac
}

halt_order_in() {
  printf '%s' "$1" | jq -c --arg id "$2" --arg why "$3" "$HALT_MERGE_JQ
    .orders = (.orders | map(if .id == \$id then (.haltedBecause = halt_merge(.haltedBecause; \$why)) else . end))"
}

# Records a deviation a person kept, for `build-record` and `review-record` --accept-deviation
# (gap rows 224 and 266). In ledger document $1, removes from order $2 each halt segment that
# begins with a prefix in JSON array $3, and keeps the rest. It adds one haltsCleared entry: the
# segments removed, or $4 when the order carried none, and the person's reason $5. Prints the
# updated document, or nothing when the update failed.
accept_deviation_in() {
  local halt kept rest
  halt="$(printf '%s' "$1" | jq -r --arg id "$2" '[ .orders[] | select(.id == $id) | .haltedBecause // empty ] | .[0] // ""')"
  kept="$(halt_segments_matching "$halt" "$3" keep)"
  rest="$(halt_segments_matching "$halt" "$3" drop)"
  printf '%s' "$1" | jq -c --arg id "$2" --arg reason "${kept:-$4}" --arg rest "$rest" \
    --arg today "$(date -u +%Y-%m-%d)" --arg because "$5" '
    .orders = (.orders | map(if .id == $id then
                 (if $rest == "" then del(.haltedBecause) else .haltedBecause = $rest end) else . end))
    | .haltsCleared = ((.haltsCleared // []) + [{id: $id, reason: $reason, clearedAt: $today, because: $because}])'
}

# Prints one of: missing, unreadable, ok. Never dies. "unreadable" covers every way the file
# fails to read as a contract once it exists: not readable, not valid JSON, not an object, or
# missing a required field. Only "missing" and "unreadable" are distinguished as separate facts
# beyond a task folder existing at all; a finer split of "unreadable" is not needed anywhere this
# script acts on it.
alignment_state() {
  [ -f "$ALIGNMENT_FILE" ] || { printf 'missing'; return; }
  [ -r "$ALIGNMENT_FILE" ] || { printf 'unreadable'; return; }
  jq empty "$ALIGNMENT_FILE" 2>/dev/null || { printf 'unreadable'; return; }
  local shape
  shape="$(jq -r '
      if type != "object" then "no"
      elif (has("schemaVersion") | not) then "no"
      elif (has("goal") | not) then "no"
      elif (has("expectedResult") | not) then "no"
      elif ((.criteria | type) != "array") then "no"
      elif ((.nonGoals | type) != "array") then "no"
      else "yes"
      end
    ' "$ALIGNMENT_FILE" 2>/dev/null)"
  if [ "$shape" = "yes" ]; then printf 'ok'; else printf 'unreadable'; fi
}

# Prints the branch name (never the remote-qualified form) that codePath's own origin/HEAD names,
# or nothing when it cannot be derived. `git symbolic-ref --short` on refs/remotes/origin/HEAD
# would print "origin/main", the remote name still attached, which never equals a local branch
# name like "main"; this reads the full ref instead and strips the known "refs/remotes/<remote>/"
# prefix itself; so the caller can compare it to a local branch by name.
derive_trunk_branch() {
  local code_path="$1" full
  full="$(git -C "$code_path" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null)"
  [ -n "$full" ] || return 1
  case "$full" in
    refs/remotes/origin/*) printf '%s' "${full#refs/remotes/origin/}" ;;
    *) printf '%s' "$full" ;;
  esac
}

# Prints one of: missing, unreadable, ok, for <task_folder>/design-closed.json ($CLOSED_FILE).
# Never dies. "unreadable" covers not valid JSON, not an object, and a hash field that is absent,
# null, or the wrong shape: the same one-word-per-fact split alignment_state uses for a contract,
# with the same reasoning that a finer split of "unreadable" is not needed here.
design_closed_state() {
  [ -f "$CLOSED_FILE" ] || { printf 'missing'; return; }
  [ -r "$CLOSED_FILE" ] || { printf 'unreadable'; return; }
  jq empty "$CLOSED_FILE" 2>/dev/null || { printf 'unreadable'; return; }
  local shape
  shape="$(jq -r '
      if type != "object" then "no"
      elif (has("hash") | not) then "no"
      elif ((.hash | type) != "string") then "no"
      elif (.hash | test("^[0-9a-f]{64}$") | not) then "no"
      else "yes"
      end
    ' "$CLOSED_FILE" 2>/dev/null)"
  if [ "$shape" = "yes" ]; then printf 'ok'; else printf 'unreadable'; fi
}

# The hash recorded in design-closed.json. Call only after design_closed_state prints "ok".
design_closed_hash() {
  jq -r '.hash' "$CLOSED_FILE" 2>/dev/null
}

# Re-derives a hash from a snapshot's own copied alignment and work orders, through the one
# producer every hash in this script uses, records_hash_for, never a second formula. Rebuilds a
# temporary task folder shaped the way records_hash_for expects, an alignment.json plus a design/
# folder of *.json files, from the two JSON values already parsed out of snapshot.json, calls
# records_hash_for on it, and removes it. Prints the hash and returns 0 on success. Prints nothing
# and returns 1 on any failure, with a message already on stderr, either this function's own or
# records_hash_for's.
snapshot_self_hash() {
  local alignment_json="$1" orders_json="$2" tmp_dir count i id entry_json hash rc
  tmp_dir="$(mktemp -d)" \
    || { printf 'implement-actions: could not create a temporary folder to re-derive the snapshot'"'"'s own hash\n' >&2; return 1; }
  printf '%s' "$alignment_json" > "$tmp_dir/alignment.json" \
    || { rm -rf "$tmp_dir"; printf 'implement-actions: could not write a temporary alignment.json\n' >&2; return 1; }
  mkdir -p "$tmp_dir/design" \
    || { rm -rf "$tmp_dir"; printf 'implement-actions: could not create a temporary design folder\n' >&2; return 1; }
  count="$(printf '%s' "$orders_json" | jq 'length' 2>/dev/null)"
  case "$count" in ''|*[!0-9]*) count=0 ;; esac
  i=0
  while [ "$i" -lt "$count" ]; do
    id="$(printf '%s' "$orders_json" | jq -r --argjson i "$i" '.[$i].id // empty' 2>/dev/null)"
    [ -n "$id" ] || id="wo_unnamed_$i"
    entry_json="$(printf '%s' "$orders_json" | jq -c --argjson i "$i" '.[$i]' 2>/dev/null)"
    printf '%s' "$entry_json" > "$tmp_dir/design/$id.json" \
      || { rm -rf "$tmp_dir"; printf 'implement-actions: could not write a temporary work order file\n' >&2; return 1; }
    i=$((i + 1))
  done
  hash="$(records_hash_for "$tmp_dir")"
  rc=$?
  rm -rf "$tmp_dir"
  [ "$rc" -eq 0 ] && [ -n "$hash" ] || return 1
  printf '%s' "$hash"
  return 0
}

# The snapshot document $1 with the orders named in $2 (a JSON array of ids) replaced by their
# live copies from $3 (the live work orders), its alignment replaced by $4 (the live alignment),
# and its hash re-derived through snapshot_self_hash. Prints the new document, or nothing and
# returns 1 when the hash could not be derived. takenAt is kept: the ledger's resnapshots entry
# carries the date of the replacement. An order is frozen when it starts, not when the stage
# starts, so an order nothing was built against takes the live shape design closed on
# (ideal/implementation.md, the 2026-09-14 paragraph under "Freezing"). Both callers require
# design closed over the live files, so the alignment taken is the one design closed on; a live
# copy frozen beside a stale contract would hand a test author the old criterion (live-run row 86).
snapshot_with_live_orders() {
  local doc="$1" ids="$2" live="$3" alignment="$4" orders hash
  orders="$(printf '%s' "$doc" | jq -c --argjson ids "$ids" --argjson live "$live" '
      ($live | map({(.id): .}) | add // {}) as $lm
      | .workOrders | map(. as $o | if (($ids | index($o.id)) != null) then $lm[$o.id] else $o end)')"
  hash="$(snapshot_self_hash "$alignment" "$orders")" || return 1
  printf '%s' "$doc" | jq -c --arg hash "$hash" --argjson orders "$orders" --argjson alignment "$alignment" \
    '.hash = $hash | .alignment = $alignment | .workOrders = $orders'
}

# Every design/*.json under $1, parsed and sorted by numeric work order id (wo1, wo2, ... wo10),
# never by filename: a lexicographic sort would put wo10 before wo2. Prints a JSON array on
# stdout, [] when the folder holds no *.json files. Sets READ_FAILED to the path of the first
# file that would not parse as JSON, and returns 1, rather than silently dropping it: a file
# check-design.sh already passed as clean should always parse here too, and one that does not is
# reported, never skipped.
READ_FAILED=""
gather_workorders_json() {
  local dir="$1" entries='[]' f doc
  READ_FAILED=""
  [ -d "$dir" ] || { printf '[]'; return 0; }
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    doc="$(jq -c '.' "$f" 2>/dev/null)"
    if [ -z "$doc" ]; then
      READ_FAILED="$f"
      return 1
    fi
    entries="$(printf '%s' "$entries" | jq --argjson d "$doc" '. + [$d]')"
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort)
  printf '%s' "$entries" | jq -c '
    sort_by(
      (.id // "wo0")
      | if test("^wo[1-9][0-9]*$") then (ltrimstr("wo") | tonumber) else 0 end
    )
  '
}

# Prints the string value of field $2 in ledger JSON $1, or prints nothing and returns 1 with a
# message on stderr naming which of three facts is true: the field is missing, it is present but
# null, or it is present but not a string. jq -r alone would print the four characters "null" for
# the first two and never distinguish the third; none of the three is ever written forward into a
# record this script produces.
ledger_required_string() {
  local doc="$1" field="$2" state value
  state="$(printf '%s' "$doc" | jq -r --arg f "$field" '
      if (has($f) | not) then "missing"
      elif (.[$f] == null) then "null"
      elif ((.[$f] | type) != "string") then "wrong-type"
      else "ok"
      end
    ' 2>/dev/null)"
  case "$state" in
    ok)
      value="$(printf '%s' "$doc" | jq -r --arg f "$field" '.[$f]' 2>/dev/null)"
      printf '%s' "$value"
      return 0
      ;;
    missing)
      printf 'implement-actions: %s is missing from %s\n' "$field" "$LEDGER_FILE" >&2
      return 1
      ;;
    null)
      printf 'implement-actions: %s is present but null in %s\n' "$field" "$LEDGER_FILE" >&2
      return 1
      ;;
    *)
      printf 'implement-actions: %s is present in %s but is not a string\n' "$field" "$LEDGER_FILE" >&2
      return 1
      ;;
  esac
}

# ------------------------------------------------------------------------------------------------
# What an action prints. A summary, never a body: one `key: value` line at a time, and nothing
# that came out of a tool, a record, a diff, a brief or a finding's evidence. The orchestrator
# reads standard output in its own conversation, and a record printed there costs the build the
# context its own steps need, so every line a person may want in full names the path that holds
# it. The one body any action prints is `tests-freeze`'s checklist rows, because the person
# answering them has to read those words.
#
# $1 the action. $2 a JSON object whose entries print in order, one line each. A string is made
# one line, and one holding a space is cut to 240 characters: prose is what runs long, and a path
# or a hash holds no space and prints whole. An array of strings joins with ", ", and an empty one
# prints "none". An array of objects prints one line per element, `key(first value): the other
# values joined by " | "`, which is how a check, a finding, a framework or an order gets its own
# line. Every action builds one object and calls this once, so there is one writer and not one per
# action.
im_print_summary() {
  local who="$1" fields="$2"
  printf '%s' "$fields" | jq -r --arg who "$who" '
    def short: gsub("\n"; " ") | if contains(" ") then .[0:240] else . end;
    def one:
      if type == "string" then short
      elif type == "array" then (if length == 0 then "none" else (map(tostring) | join(", ")) end)
      elif . == null then "none"
      else tostring end;
    ([ "action: \($who)" ]
     + [ to_entries[] | .key as $k | .value as $v
         | if ($v | type) == "array" and ($v | length) > 0 and (($v[0] | type) == "object") then
             ($v[] | [ .[] ] | "\($k)(\(.[0] | one)): \(.[1:] | map(one) | join(" | "))")
           else "\($k): \($v | one)" end ])
    | .[]'
}

# True while a retake is still unanswered: `retake-tests` recorded the freeze commit the order's
# test record held, and that record still holds it, so the freeze after the retake has not run.
# $1 the ledger document, $2 the implementation folder, $3 the order id. Prints true or false.
# One producer for the fact, read by the routing line below and by the tests brief.
#
# A test record that is gone, unreadable, or holding no commit reads as pending too: the freeze is
# the one producer of that commit, so no freeze can have answered the retake. The brief then names
# the missing record and carries what is left, the way it names an absent review record.
im_retake_pending() {
  local record="$2/tests-$3.json" answer
  answer="$(printf '%s' "$1" | jq -r --arg id "$3" --arg c "$(jq -r '.commit // ""' "$record" 2>/dev/null)" \
    '(([ (.orders // [])[] | select(.id == $id) ][0].retakes // []) | last // {} | .freezeCommit // "") as $f
     | $f != "" and ($c == "" or $f == $c)')"
  [ "$answer" = "true" ] || answer=false
  printf '%s' "$answer"
}

# What each order's proof kind needs, from br_order_needs, as one JSON object keyed by order id.
# `read` prints the value on the order's line, so the tests step reads the roles and the lookups
# there and never re-derives them from the kind. $1 the snapshot document, or empty.
im_order_needs_json() {
  local count i one acc='{}'
  [ -n "$1" ] || { printf '{}'; return 0; }
  count="$(printf '%s' "$1" | jq '(.workOrders // []) | length')"
  i=0
  while [ "$i" -lt "$count" ]; do
    one="$(printf '%s' "$1" | jq -c --argjson i "$i" '.workOrders[$i]')"
    br_order_needs "$one"
    acc="$(printf '%s' "$acc" | jq -c --arg id "$(printf '%s' "$one" | jq -r '.id')" \
      --arg v "roles=$BR_ORDER_ROLES lookups=$BR_ORDER_LOOKUPS" '. + {($id): $v}')"
    i=$((i + 1))
  done
  printf '%s' "$acc"
}

# The next step, derived the way SKILL.md's routing table reads the ledger, so `read`, `start` and
# every record action print the same answer from the same facts. $1 the ledger document, or empty
# when none is readable; $2 the snapshot document, or empty; $3 the implementation folder, for the
# review records that say which order has a finding open; $4 whether the preconditions record
# exists; $5 whether the finished record exists. Prints one line and nothing else.
#
# An order in flight comes before a new one, because the build is serial and the in-flight order is
# the one the ledger is waiting on. A halted order is named only when nothing else can move: the
# orders that do not depend on it still build (SKILL.md, "One order halting does not stop the run").
# The preconditions step is named only while some order could move once it has run; a ledger whose
# every order is halted for drift is waiting on the restart, whether or not step two ever ran.
# An order halted because the design removed it outranks a ready order: its frozen test record
# stays in implementation/ until `restart` moves it aside, and hooks/deny-frozen-test-writes.sh
# reads every such record, so the survivor that absorbed its test files would be refused writing
# them (live-run row 82). An order in flight still comes first; its tests were frozen already.
im_next_step() {
  local ledger="$1" snapshot="$2" impl="$3" precon="$4" finished="$5"
  if [ -z "$ledger" ] || [ -z "$snapshot" ]; then
    printf 'start'
    return 0
  fi
  if [ "$finished" = "true" ]; then
    printf 'none: implementation is finished, the review stage is next, and a failed review takes a fix and a second finish'
    return 0
  fi
  # How many actionable findings each reviewed order still has open, read once per order here so
  # the jq below decides fix-or-close without opening a file itself. And whether each order's
  # build record was stopped by the three tool rows alone, read from the record's own checks, so
  # the line can name the re-check without running git (live-run row 87). And whether each
# order's tests are still the ones a retake sent back: the record's commit equals the last
# retake's freezeCommit until the freeze after the retake rewrites it, the predicate the
# freeze's own exemption reads, so the line names the author and not a build against the
# wrong test (live-run row 110).
  local opens ids count i id file n recheck_route retake_pending
  opens='{}'
  recheck_route='{}'
  retake_pending='{}'
  ids="$(printf '%s' "$ledger" | jq -c '[ (.orders // [])[] | .id ]')"
  count="$(printf '%s' "$ids" | jq 'length')"
  i=0
  while [ "$i" -lt "$count" ]; do
    id="$(printf '%s' "$ids" | jq -r --argjson i "$i" '.[$i]')"
    file="$impl/review-$id.json"
    n=0
    if [ -f "$file" ]; then
      n="$(jq '[ (.findings // [])[] | select(.actionable == true and .status == "open") ] | length' "$file" 2>/dev/null)"
      case "$n" in ''|*[!0-9]*) n=0 ;; esac
    fi
    opens="$(printf '%s' "$opens" | jq -c --arg id "$id" --argjson n "$n" '. + {($id): $n}')"
    # The re-check route, when the recheck rows alone stopped the attempt. An attempt that
    # interface-record stopped is answered by amending the record first, so the route names its
    # file, the brief's interfacePath (gap row 253).
    file="$impl/build-$id.json"
    n=""
    if [ -f "$file" ]; then
      n="$(jq -r "$BR_STOPPERS_JQ"'(.checks // []) | if (stoppers | length > 0) and (outside_recheck | length == 0)
        then (if (stoppers | index("interface-record")) != null then "interface" else "tools" end) else "" end' "$file" 2>/dev/null)"
      case "$n" in
        tools) n="build-recheck" ;;
        interface)
          n="$(jq -r '.interfacePath // ""' "$impl/brief-$id-build.json" 2>/dev/null)"
          n="amend ${n:-the interface record} with the elements interface-record names, then build-recheck" ;;
        *) n="" ;;
      esac
    fi
    recheck_route="$(printf '%s' "$recheck_route" | jq -c --arg id "$id" --arg n "$n" '. + {($id): $n}')"
    n="$(im_retake_pending "$ledger" "$impl" "$id")"
    retake_pending="$(printf '%s' "$retake_pending" | jq -c --arg id "$id" --argjson n "$n" '. + {($id): $n}')"
    i=$((i + 1))
  done
  printf '%s' "$ledger" | jq -r --argjson opens "$opens" --argjson recheck_route "$recheck_route" --argjson snap "$snapshot" \
    --argjson retake_pending "$retake_pending" --argjson departure_prefixes "$RR_DEPARTURE_PREFIXES" \
    --argjson allowed "$BUILD_ATTEMPTS_ALLOWED" --argjson precon "$precon" '
    (.orders // []) as $orders
    | ([ $orders[] | select(.lastStep == "closed") | .id ]) as $closed
    | ([ $orders[] | select((.haltedBecause // "") == "") ]) as $live
    | (($snap.workOrders // []) | map({(.id): (.dependsOn // [])}) | add // {}) as $deps
    | ([ $live[] | select(.lastStep == "checks-passed" or .lastStep == "reviewed" or .lastStep == "fixed") ] | .[0]) as $rv
    # An order that stopped on a closed order'"'"'s defect waits until that repair closes (gap row 286).
    | ([ $orders[] | select(.lastStep != "closed") | (.repairs // [])[] | .by ]) as $waiting
    | ([ $live[] | select(.id as $i | $waiting | index($i) | not) | select(.lastStep == "tests-frozen"
                          or (.lastStep == "code-written" and ((.attemptsUsed // 0) < (.attemptsAllowed // $allowed)))) ] | .[0]) as $bd
    | ([ $live[] | select(.lastStep == null) | select((($deps[.id] // []) - $closed) | length == 0) ] | .[0]) as $ts
    | ([ $orders[] | select((.haltedBecause // "") | contains("design drift")) ] | .[0]) as $drift
    # A departure routes to accept-deviation only while it is the one drift segment of the order. A
    # design change drifted it too, so keeping the departure no longer answers the halt.
    | ([ $orders[] | select((.haltedBecause // "") as $h | any($departure_prefixes[]; . as $p | $h | contains($p)))
         | select([ (.haltedBecause | split("; earlier: "))[] | select(startswith("design drift"))
                    | . as $seg | select(any($departure_prefixes[]; . as $p | $seg | startswith($p)) | not) ] | length == 0) ] | .[0]) as $departure
    | ([ $orders[] | select((.haltedBecause // "") | contains("design drift: the design removed ")) ] | .[0]) as $removed
    | ([ $orders[] | select((.haltedBecause // "") | (contains("attempts spent") or contains("budget spent"))) ] | .[0]) as $spent
    | ([ $orders[] | select((.haltedBecause // "") | startswith("test wrong: ")) ] | .[0]) as $testwrong
    | ([ $orders[] | select((.haltedBecause // "") != "") ] | length) as $halted
    | if ($precon | not) and ($rv != null or $bd != null or ($ts != null and $removed == null)) then "preconditions"
      elif $rv != null then
        (if $rv.lastStep == "checks-passed" then "review \($rv.id): review the order"
         elif (($opens[$rv.id] // 0) > 0) then "review \($rv.id): fix, then verify"
         else "review \($rv.id): close the order" end)
      elif $bd != null then
        (if $bd.lastStep == "code-written" and (($recheck_route[$bd.id] // "") != "") then
           "build \($bd.id), or \($recheck_route[$bd.id]) \($bd.id) when the code has not moved"
         elif $bd.lastStep == "tests-frozen" and ($retake_pending[$bd.id] // false) then
           "tests \($bd.id): the tests were retaken and not frozen again yet"
         else "build \($bd.id)" end)
      elif $removed != null and $ts != null then "finish: offer the restart, the design removed \($removed.id), and its frozen test record still guards its test files"
      elif $ts != null then "tests \($ts.id)"
      elif (($orders | length) > 0 and ($closed | length) == ($orders | length) and $halted == 0) then "finish"
      elif $departure != null then "review: \($departure.id) is halted for a departure from the design, so offer review-record --accept-deviation or the restart"
      elif $drift != null then "finish: offer the restart, \($drift.id) is halted for design drift"
      elif $spent != null then "finish: offer the grant, \($spent.id) is halted with its attempts or its budget spent"
      elif $testwrong != null then "review: offer retake-tests \($testwrong.id), a frozen test is ruled wrong, and the retake sends the order back to its tests"
      elif $halted > 0 then "finish: offer clear-halt, every order that is not closed is halted for a reason a person clears"
      else "none: nothing is ready, and every remaining order waits on a dependency that is not closed" end'
}

# ------------------------------------------------------------------------------------------------
# read: the current state, never a failure just because nothing has run yet.
# ------------------------------------------------------------------------------------------------

do_read() {
  [ "$#" -ge 1 ] || die 3 "read: a task folder is required"
  [ "$#" -le 1 ] || die 3 "read: unrecognized extra argument: $2"
  local task_path="$1"
  local resolve_rc
  TASK_PATH="$(resolve_task_folder "$task_path" "read")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  ALIGNMENT_FILE="$TASK_PATH/alignment.json"
  DESIGN_DIR="$TASK_PATH/design"
  IMPL_DIR="$TASK_PATH/implementation"
  SNAPSHOT_FILE="$IMPL_DIR/snapshot.json"
  LEDGER_FILE="$IMPL_DIR/ledger.json"

  local astate design_started design_file_count
  astate="$(alignment_state)"
  if [ -d "$DESIGN_DIR" ]; then
    design_started=true
    design_file_count="$(find "$DESIGN_DIR" -mindepth 1 -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d '[:space:]')"
  else
    design_started=false
    design_file_count=0
  fi

  local project_path project_note code_path
  project_path=""
  project_note=""
  code_path=""
  if project_path="$(resolve_project_folder "$TASK_PATH")"; then
    case "$(project_code_path_state "$project_path")" in
      unreadable)
        project_note="$project_path/project.json exists but is not valid JSON"
        ;;
      missing)
        project_note="$project_path/project.json is missing"
        ;;
      ok)
        [ -n "$(project_code_path_value "$project_path")" ] || project_note="$project_path/project.json is valid JSON but has no usable codePath field"
        ;;
    esac
  else
    project_path=""
    project_note="could not resolve a project folder two levels up from the task folder, or it has no project.json"
  fi
  # The code this task builds in is its own worktree, read from the field and never made here.
  code_path="$(jq -r '.worktree.path // empty' "$TASK_PATH/task.json" 2>/dev/null)"

  local git_is_repo git_branch trunk_derived trunk_branch trunk_note
  git_is_repo=false
  git_branch=""
  trunk_derived=false
  trunk_branch=""
  trunk_note="not checked"
  if [ -n "$code_path" ]; then
    if is_git_repo "$code_path"; then
      git_is_repo=true
      git_branch="$(git -C "$code_path" symbolic-ref --short -q HEAD 2>/dev/null)"
      if git -C "$code_path" remote get-url origin >/dev/null 2>&1; then
        trunk_branch="$(derive_trunk_branch "$code_path")"
        if [ -n "$trunk_branch" ]; then
          trunk_derived=true
          trunk_note="derived from refs/remotes/origin/HEAD"
        else
          trunk_note="origin's HEAD is not set (refs/remotes/origin/HEAD is missing); the trunk branch could not be derived"
        fi
      else
        trunk_note="no remote named origin is configured; the trunk branch could not be derived"
      fi
    else
      trunk_note="not checked: $code_path is not a git repository"
    fi
  fi

  local run_mode
  run_mode="$(task_run_mode "$TASK_PATH" implement)"

  local snap_exists snap_readable snap_summary
  snap_exists=false; snap_readable=false; snap_summary='null'
  if [ -f "$SNAPSHOT_FILE" ]; then
    snap_exists=true
    if [ -r "$SNAPSHOT_FILE" ] && jq empty "$SNAPSHOT_FILE" 2>/dev/null; then
      snap_readable=true
      snap_summary="$(jq -c '{schemaVersion, takenAt, hash, workOrderCount: ((.workOrders // []) | length)}' "$SNAPSHOT_FILE" 2>/dev/null)"
      [ -n "$snap_summary" ] || snap_summary='null'
    fi
  fi

  local ledger_exists ledger_readable ledger_summary
  ledger_exists=false; ledger_readable=false; ledger_summary='null'
  if [ -f "$LEDGER_FILE" ]; then
    ledger_exists=true
    if [ -r "$LEDGER_FILE" ] && jq empty "$LEDGER_FILE" 2>/dev/null; then
      ledger_readable=true
      ledger_summary="$(jq -c '{
          schemaVersion, startedFrom, runMode, snapshotHash,
          orderCount: ((.orders // []) | length),
          ordersByLastStep: ((.orders // []) | group_by(.lastStep // "null") | map({key: (.[0].lastStep // "null"), value: length}) | from_entries),
          criteriaCount: ((.criteria // []) | length),
          criteriaByRowState: ((.criteria // []) | group_by(.rowState) | map({key: .[0].rowState, value: length}) | from_entries),
          orderStates: [ (.orders // [])[] | {id: .id, lastStep: .lastStep, haltedBecause: (.haltedBecause // null)} ],
          rowsJudgedByModel: (([ (.criteria // [])[] | (.judgements // [])[] | select(.judgedBy == "model") ] | length)
                              + ([ (.orders // [])[] | select(.doneWhenJudgement.judgedBy == "model") ] | length)),
          rowsJudgedByModelCriteria: ([ (.criteria // [])[] | select((.judgements // []) | map(.judgedBy == "model") | any) | .id ]
                                      + [ (.orders // [])[] | select(.doneWhenJudgement.judgedBy == "model") | .id ])
        }' "$LEDGER_FILE" 2>/dev/null)"
      [ -n "$ledger_summary" ] || ledger_summary='null'
    fi
  fi

  # The skill routes on this: a ledger with no preconditions record means step two has not run.
  # Reported the same way the snapshot and the ledger are, so the three read alike.
  local precon_exists precon_readable precon_note
  precon_exists=false; precon_readable=false; precon_note="not recorded"
  if [ -f "$IMPL_DIR/preconditions.json" ]; then
    precon_exists=true
    if [ -r "$IMPL_DIR/preconditions.json" ] && jq empty "$IMPL_DIR/preconditions.json" 2>/dev/null; then
      precon_readable=true; precon_note="ok"
    else
      precon_note="present but could not be read as JSON"
    fi
  fi

  # The skill routes the end of the stage on this: a task with every order closed and no finished
  # record is waiting for `finish`. Reported the same way the three records above are.
  local finished_exists finished_readable finished_note
  finished_exists=false; finished_readable=false; finished_note="not recorded"
  if [ -f "$IMPL_DIR/finished.json" ]; then
    finished_exists=true
    if [ -r "$IMPL_DIR/finished.json" ] && jq empty "$IMPL_DIR/finished.json" 2>/dev/null; then
      finished_readable=true; finished_note="ok"
    else
      finished_note="present but could not be read as JSON"
    fi
  fi

  # The skill routes step five on this: an order with no review record is waiting for one, and an
  # order with open findings is waiting for a fixer. One row per order in the ledger, in the
  # ledger's own order, so a reader never has to open six files to learn where a task stands. A
  # ledger that could not be read leaves the list empty rather than guessing at it.
  local reviews_json order_ids order_count oi one_id one_file one_exists one_open one_note one_pending
  reviews_json='[]'
  if [ "$ledger_readable" = "true" ]; then
    order_ids="$(jq -c '[ (.orders // [])[] | .id ]' "$LEDGER_FILE" 2>/dev/null)"
    [ -n "$order_ids" ] || order_ids='[]'
    order_count="$(printf '%s' "$order_ids" | jq 'length')"
    oi=0
    while [ "$oi" -lt "$order_count" ]; do
      one_id="$(printf '%s' "$order_ids" | jq -r --argjson i "$oi" '.[$i]')"
      one_file="$IMPL_DIR/review-$one_id.json"
      one_exists=false; one_open=0; one_pending=0; one_note="no review record"
      if [ -f "$one_file" ]; then
        one_exists=true
        if jq empty "$one_file" 2>/dev/null; then
          one_open="$(jq '[ (.findings // [])[] | select(.actionable == true and .status == "open") ] | length' "$one_file" 2>/dev/null)"
          case "$one_open" in ''|*[!0-9]*) one_open=0 ;; esac
          # What waits for the person at the task review (gap row 279).
          one_pending="$(jq '([ (.findings // [])[] | select(.status == "pending") ] | length) + (if has("deviationPending") then 1 else 0 end)' "$one_file" 2>/dev/null)"
          case "$one_pending" in ''|*[!0-9]*) one_pending=0 ;; esac
          one_note="ok"
        else
          one_note="present but could not be read as JSON"
        fi
      fi
      reviews_json="$(printf '%s' "$reviews_json" | jq -c --arg unit "$one_id" \
        --argjson exists "$one_exists" --argjson open "$one_open" --argjson pending "$one_pending" --arg note "$one_note" \
        '. + [{unit: $unit, reviewRecordExists: $exists, openActionableFindings: $open, pendingForReview: $pending, note: $note}]')"
      oi=$((oi + 1))
    done
  fi

  # The state the router needs, as summary lines: SKILL.md's table reads `snapshot`, `ledger`,
  # `preconditions`, `finished`, each `order(...)` line and `next`. The snapshot body, the ledger
  # body and the review records stay in their files, each named here by path.
  local snap_line snap_hash ledger_line started_from precon_line finished_line orders_json
  local criteria_line judged_line next_line ledger_doc_for_next snapshot_doc_for_next
  snap_line="none"
  snap_hash="none"
  [ "$snap_exists" = "true" ] && snap_line="present but could not be read as JSON, at $SNAPSHOT_FILE"
  if [ "$snap_readable" = "true" ]; then
    snap_line="$SNAPSHOT_FILE"
    snap_hash="$(printf '%s' "$snap_summary" | jq -r '"\(.hash // "none") | workOrders=\(.workOrderCount) | takenAt=\(.takenAt)"')"
  fi
  ledger_line="none"
  started_from="none"
  [ "$ledger_exists" = "true" ] && ledger_line="present but could not be read as JSON, at $LEDGER_FILE"
  if [ "$ledger_readable" = "true" ]; then
    ledger_line="$LEDGER_FILE"
    started_from="$(printf '%s' "$ledger_summary" | jq -r '"\(.startedFrom // "none") | runMode=\(.runMode) | snapshotHash=\(.snapshotHash)"')"
  fi
  precon_line="none"
  [ "$precon_exists" = "true" ] && precon_line="$precon_note, at $IMPL_DIR/preconditions.json"
  [ "$precon_readable" = "true" ] && precon_line="recorded at $IMPL_DIR/preconditions.json"
  finished_line="none"
  [ "$finished_exists" = "true" ] && finished_line="$finished_note, at $IMPL_DIR/finished.json"
  [ "$finished_readable" = "true" ] && finished_line="recorded at $IMPL_DIR/finished.json"
  orders_json='[]'
  criteria_line="none"
  judged_line="0"
  if [ "$ledger_readable" = "true" ]; then
    local needs_json='{}'
    [ "$snap_readable" = "true" ] && needs_json="$(im_order_needs_json "$(jq -c '.' "$SNAPSHOT_FILE" 2>/dev/null)")"
    orders_json="$(jq -c --argjson reviews "$reviews_json" --argjson needs "$needs_json" '
      ($reviews | map({(.unit): .}) | add // {}) as $rv
      | [ (.orders // [])[] | . as $o
          | {id: .id,
             step: (.lastStep // "not started"),
             halt: ("halt: " + (.haltedBecause // "none")),
             attempts: ("attempts=" + ((.attemptsUsed // 0) | tostring)),
             rounds: ("rounds=" + ((.roundsUsed // 0) | tostring)),
             review: (if ($rv[$o.id].reviewRecordExists // false) then "review: open=\($rv[$o.id].openActionableFindings) pending=\($rv[$o.id].pendingForReview)" else "review: none" end),
             needs: ($needs[$o.id] // "unknown: no readable snapshot names this order")} ]' \
      "$LEDGER_FILE")"
    criteria_line="$(printf '%s' "$ledger_summary" | jq -r \
      '(.criteriaByRowState // {}) | to_entries | map("\(.key)=\(.value)") | join(" ") | if . == "" then "none" else . end')"
    judged_line="$(printf '%s' "$ledger_summary" | jq -r \
      '"\(.rowsJudgedByModel // 0)" + (if ((.rowsJudgedByModelCriteria // []) | length) > 0 then " (" + (.rowsJudgedByModelCriteria | join(", ")) + ")" else "" end)')"
  fi
  ledger_doc_for_next=""
  snapshot_doc_for_next=""
  [ "$ledger_readable" = "true" ] && ledger_doc_for_next="$(jq -c '.' "$LEDGER_FILE" 2>/dev/null)"
  [ "$snap_readable" = "true" ] && snapshot_doc_for_next="$(jq -c '.' "$SNAPSHOT_FILE" 2>/dev/null)"
  if { [ "$snap_exists" = "true" ] && [ "$snap_readable" != "true" ]; } \
     || { [ "$ledger_exists" = "true" ] && [ "$ledger_readable" != "true" ]; }; then
    next_line="none: a record under $IMPL_DIR could not be read as JSON; repair or remove it by hand first"
  elif [ "$snap_exists" != "true" ] && { [ "$astate" != "ok" ] || [ "$design_started" != "true" ]; }; then
    next_line="none: no usable contract or design has not started; the stage before this one is missing"
  else
    next_line="$(im_next_step "$ledger_doc_for_next" "$snapshot_doc_for_next" "$IMPL_DIR" "$precon_readable" "$finished_readable")"
  fi

  im_print_summary "read" "$(jq -n \
    --arg task "$TASK_PATH" --arg alignment "$astate" \
    --arg design "$(if [ "$design_started" = "true" ]; then printf 'started, %s file(s) under %s' "$design_file_count" "$DESIGN_DIR"; else printf 'not started'; fi)" \
    --arg project "$(if [ -n "$project_path" ]; then printf '%s' "$project_path"; else printf 'none'; fi)$(if [ -n "$project_note" ]; then printf ' | %s' "$project_note"; fi)" \
    --arg codePath "$(if [ -n "$code_path" ]; then printf '%s' "$code_path"; else printf 'none'; fi)" \
    --arg branch "$(if [ "$git_is_repo" = "true" ]; then printf '%s' "${git_branch:-detached}"; else printf 'not a git repository'; fi)" \
    --arg trunk "$(if [ "$trunk_derived" = "true" ]; then printf '%s | ' "$trunk_branch"; fi)$trunk_note" \
    --arg runMode "$run_mode, from task.json for the implement stage" \
    --arg snapshot "$snap_line" --arg snapshotHash "$snap_hash" \
    --arg ledger "$ledger_line" --arg startedFrom "$started_from" \
    --arg preconditions "$precon_line" --arg finished "$finished_line" \
    --argjson orders "$orders_json" --arg criteria "$criteria_line" --arg judged "$judged_line" \
    --arg next "$next_line" '
    {task: $task, alignment: $alignment, design: $design, project: $project, codePath: $codePath,
     branch: $branch, trunk: $trunk, runMode: $runMode,
     snapshot: $snapshot, snapshotHash: $snapshotHash, ledger: $ledger, startedFrom: $startedFrom,
     preconditions: $preconditions, finished: $finished, order: $orders,
     criteria: $criteria, rowsJudgedByModel: $judged, next: $next}')"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# start: the first step of implementation. See this script's own header for the full sequence.
# ------------------------------------------------------------------------------------------------

do_start() {
  local task_path="" rebased_onto="" leftovers_choice=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --rebased-onto)
        [ "$#" -ge 2 ] || die 3 "start: --rebased-onto needs the commit the branch now builds on"
        [ -n "$2" ] || die 3 "start: --rebased-onto was given an empty commit."
        rebased_onto="$2"; shift 2 ;;
      --leftovers)
        case "${2:-}" in
          keep|set-aside) leftovers_choice="$2"; shift 2 ;;
          *) die 3 "start: --leftovers takes keep or set-aside" ;;
        esac ;;
      -*) die 3 "start: unrecognized argument: $1" ;;
      *)
        [ -z "$task_path" ] || die 3 "start: unrecognized extra argument: $1"
        task_path="$1"; shift ;;
    esac
  done
  [ -n "$task_path" ] || die 3 "start: a task folder is required"

  # --- step 1: resolve the task folder and its contract -----------------------------------------
  local resolve_rc
  TASK_PATH="$(resolve_task_folder "$task_path" "start")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  ALIGNMENT_FILE="$TASK_PATH/alignment.json"
  DESIGN_DIR="$TASK_PATH/design"
  IMPL_DIR="$TASK_PATH/implementation"
  SNAPSHOT_FILE="$IMPL_DIR/snapshot.json"
  LEDGER_FILE="$IMPL_DIR/ledger.json"
  CLOSED_FILE="$TASK_PATH/design-closed.json"

  case "$(alignment_state)" in
    missing)
      die 2 "start: $ALIGNMENT_FILE not found. Run the scope skill on this task before implementation can freeze a contract to build from."
      ;;
    unreadable)
      die 10 "start: $ALIGNMENT_FILE exists but cannot be read as a contract (not valid JSON, not an object, or missing a required field). Fix it, or re-run the scope skill on this task, before implementation can freeze a contract to build from."
      ;;
  esac

  # --- step 2: design must have closed cleanly, on the live files -------------------------------
  [ -f "$CHECK_DESIGN_SCRIPT" ] || die 3 "start: cannot find check-design.sh at $CHECK_DESIGN_SCRIPT"
  local design_stderr_file design_report_json design_rc design_stderr_text
  design_stderr_file="$(mktemp)" || die 3 "start: could not create a temporary file"
  design_report_json="$(bash "$CHECK_DESIGN_SCRIPT" "$TASK_PATH" 2>"$design_stderr_file")"
  design_rc=$?
  design_stderr_text="$(cat "$design_stderr_file" 2>/dev/null)"
  rm -f "$design_stderr_file"

  case "$design_rc" in
    0) : ;;
    1|4)
      local open_summary
      open_summary="$(printf '%s' "$design_report_json" | jq -r '
          [
            ((.coverage.criteriaWithNoServingOrder // [])[] | "criterion " + .id + " has no serving order"),
            ((.coverage.criteriaWithNoOwner // [])[] | "criterion " + .id + " has no owner"),
            ((.coverage.criteriaWithMultipleOwners // [])[] | "criterion " + .id + " is owned by more than one order"),
            ((.coverage.criteriaWithUnusableVerifiedBy // [])[] | "criterion " + .id + " has a verifiedBy of " + (.verifiedBy | tostring) + ", which is neither machine nor person"),
            ((.coverage.ordersServingNothing // [])[] | "order " + .id + " serves no criterion"),
            ((.coverage.ordersMissingRequiredTests // [])[] | "order " + .id + " owns a machine-verified criterion (" + .criterionId + ") with no test"),
            ((.coverage.unknownCriteriaIds // [])[] | "file " + .path + " names an unknown criterion id " + .id + " in " + .field),
            ((.coverage.unknownNonGoalIds // [])[] | "file " + .path + " names an unknown non-goal id " + .id),
            ((.graph.dependencyCycles // [])[] | "dependency cycle includes " + .),
            ((.graph.orphanSupportOrders // [])[] | "order " + . + " owns nothing and no owning order depends on it"),
            ((.graph.overlappingOwnedFiles // [])[] | "orders " + (.ids | join(", ")) + " both declare " + .path),
            ((.graph.unknownDependsOnIds // [])[] | "file " + .path + " depends on an unknown work order id " + .id),
            ((.duplicateWorkOrderIds // [])[] | "work order id " + .id + " is used by more than one file: " + (.paths | join(", "))),
            ((.files // [])[] | select((.schema.issueCount // 0) > 0) | "file " + .path + " does not match the design shape"),
            ((.files // [])[] | .path as $p | (.content.issues // [])[] | "file " + $p + ": " + .problem)
          ] | join("; ")
        ' 2>/dev/null)"
      [ -n "$open_summary" ] || open_summary="design left something open; see check-design.sh against $TASK_PATH for detail"
      die 4 "start: design has not closed cleanly. Finish design first. Open: $open_summary"
      ;;
    3)
      die 3 "start: check-design.sh could not run: $design_stderr_text"
      ;;
    *)
      die 3 "start: check-design.sh exited with an unexpected code $design_rc"
      ;;
  esac

  # --- step 3: read the live records once, and re-derive one hash over them together -------------
  local live_alignment_json live_workorders_json live_hash
  live_alignment_json="$(jq -c '.' "$ALIGNMENT_FILE" 2>/dev/null)"
  [ -n "$live_alignment_json" ] || die 3 "start: $ALIGNMENT_FILE could not be re-read as JSON immediately after passing its own check"

  live_workorders_json="$(gather_workorders_json "$DESIGN_DIR")"
  if [ -n "$READ_FAILED" ]; then
    die 3 "start: $READ_FAILED is under design/ but could not be read as JSON, even though check-design.sh just reported design closed cleanly"
  fi

  local live_hash_stderr_file live_hash_rc live_hash_stderr_text
  live_hash_stderr_file="$(mktemp)" || die 3 "start: could not create a temporary file"
  live_hash="$(records_hash_for "$TASK_PATH" 2>"$live_hash_stderr_file")"
  live_hash_rc=$?
  live_hash_stderr_text="$(cat "$live_hash_stderr_file" 2>/dev/null)"
  rm -f "$live_hash_stderr_file"
  [ "$live_hash_rc" -eq 0 ] && [ -n "$live_hash" ] \
    || die 3 "start: could not compute a hash over the live alignment.json and design/*.json: $live_hash_stderr_text"

  # --- step 4: the task's own project must point at a git repository ----------------------------
  local project_path code_path
  rv_load_codepath "start"
  project_path="$RV_PROJECT_FOLDER"
  code_path="$RV_CODEPATH"

  # --- step 5: codePath must be on a named branch, never a detached HEAD ------------------------
  local current_branch
  current_branch="$(git -C "$code_path" symbolic-ref --short -q HEAD 2>/dev/null)"
  [ -n "$current_branch" ] \
    || die 16 "start: $code_path is not currently on a named branch (a detached HEAD, or the branch could not be read for another reason). A commit made there belongs to no branch, and this build must not risk that. Check out a real branch first."

  # --- step 6: derive the trunk branch, and refuse only when the build would land on it ---------
  local trunk_derived trunk_branch trunk_note
  trunk_derived=false
  trunk_branch=""
  if ! git -C "$code_path" remote get-url origin >/dev/null 2>&1; then
    trunk_note="could not look: no remote named origin is configured in $code_path"
  else
    trunk_branch="$(derive_trunk_branch "$code_path")"
    if [ -n "$trunk_branch" ]; then
      trunk_derived=true
      trunk_note="derived from refs/remotes/origin/HEAD: $trunk_branch"
    else
      trunk_note="could not look: origin's HEAD is not set (refs/remotes/origin/HEAD is missing) in $code_path"
    fi
  fi
  if [ "$trunk_derived" = "true" ] && [ "$current_branch" = "$trunk_branch" ]; then
    die 6 "start: $code_path is currently on $trunk_branch, which is derived as its trunk branch. The build must not land there. Check out a branch other than $trunk_branch first."
  fi

  # --- step 7: the run mode is the task's own, never a flag on this call -------------------------
  # task_run_mode answers for this stage from runMode and runModeStages (task-schema.json). The
  # field's value against the schema is check-task.sh's to refuse, not this script's.
  local run_mode
  run_mode="$(task_run_mode "$TASK_PATH" implement)"

  # --- step 7b: files a stopped role left in the tree (gap row 217) -------------------------------
  # im_scan_leftovers names them. Interactive refuses until a person picks keep or set-aside.
  # Unattended sets them aside. Only an untracked or a modified file can move. Any other change is
  # a person's to undo, in both modes.
  local lo_xy lo_rel lo_tab lo_tracked leftovers_json
  lo_tab="$(printf '\t')"
  im_scan_leftovers "$code_path" "$( { jq -ce '.workOrders' "$SNAPSHOT_FILE" 2>/dev/null || printf '%s' "$live_workorders_json"; } )"
  leftovers_json="$LO_LEFTOVERS_JSON"
  lo_tracked="$LO_TRACKED"
  if [ "$leftovers_json" != "[]" ]; then
    if [ "$run_mode" = "autonomous" ]; then
      [ "$leftovers_choice" != "keep" ] || die 3 "start: --leftovers keep is a person's call, and this run is unattended."
      leftovers_choice="set-aside"
    fi
    [ -n "$leftovers_choice" ] \
      || die 104 "start: uncommitted files in $code_path: $(printf '%s' "$leftovers_json" | jq -r "[ $LO_TEXT_JQ ] | join(\", \")"). A role stopped mid-run may have left them, and the next role would work beside them. To keep a file, commit it, or run start again with --leftovers keep to leave it as it is. To set them aside, run start again with --leftovers set-aside. That moves them under $IMPL_DIR/set-aside/ and deletes nothing."
    [ "$leftovers_choice" != "set-aside" ] || [ -z "$lo_tracked" ] \
      || die 104 "start: these changes cannot be set aside: ${lo_tracked%, }. Only an untracked or a modified file moves aside. Commit them, or undo them by hand, then run start again."
  fi

  # --- step 8: look for an existing snapshot: absent, present-readable, or present-unreadable ----
  local snapshot_present snapshot_doc
  snapshot_present=false
  snapshot_doc=""
  if [ -f "$SNAPSHOT_FILE" ]; then
    if [ -r "$SNAPSHOT_FILE" ] && snapshot_doc="$(jq -c '.' "$SNAPSHOT_FILE" 2>/dev/null)" && [ -n "$snapshot_doc" ]; then
      snapshot_present=true
    else
      die 3 "start: $SNAPSHOT_FILE exists but could not be read as JSON. This is a third fact, distinct from absent or readable, and is a refusal: repair or remove it by hand before running this again."
    fi
  fi

  local run_kind snapshot_hash_on_disk snapshot_alignment_json snapshot_workorders_json
  local drifted_orders_json='[]' contract_changed=false new_live_order_ids_json='[]'
  local changed_criteria_json='[]' dependent_halts_json='[]' drift_halts_json='[]'
  local drift_checked=false
  local resnapshot_ids_json='[]' resnapshot_doc='' resnapshot_hash='' removed_ids_json='[]' halted_removed_ids_json='[]'
  local widened_ids_json='[]' widened_json='[]'

  if [ "$snapshot_present" = "false" ]; then
    # ---- new run: design must be formally closed on exactly these live files --------------------
    run_kind="new"

    case "$(design_closed_state)" in
      missing)
        die 11 "start: $CLOSED_FILE not found. Design has never closed. Run the design skill's close action on this task before implementation can freeze anything."
        ;;
      unreadable)
        die 12 "start: $CLOSED_FILE exists but cannot be read as a close record (not valid JSON, not an object, or its hash field is missing or malformed). Close design again."
        ;;
    esac
    local closed_hash
    closed_hash="$(design_closed_hash)"
    [ "$closed_hash" = "$live_hash" ] \
      || die 13 "start: $CLOSED_FILE recorded a hash over the contract and the work orders design closed on, and it disagrees with a hash just re-derived from the live alignment.json and design/*.json. Design changed after it closed. Close design again before implementation can freeze it."

    local wo_count
    wo_count="$(printf '%s' "$live_workorders_json" | jq 'length')"
    [ "$wo_count" -gt 0 ] \
      || die 7 "start: design/ under $TASK_PATH has no work orders. There is nothing for implementation to build. (A contract with no criteria closes design with none; add criteria and redesign, or this task has nothing to implement.)"

    [ ! -e "$LEDGER_FILE" ] \
      || die 3 "start: $LEDGER_FILE already exists but $SNAPSHOT_FILE does not. A ledger with no snapshot beside it is not a supported state; remove $LEDGER_FILE by hand if this task is meant to start fresh, or restore the snapshot it was opened against."

    [ ! -e "$SNAPSHOT_FILE" ] \
      || die 3 "start: $SNAPSHOT_FILE appeared between this script's own presence check and its own write. Another start call on this task finished first and won that race; this call lost it normally. Re-run read to see what the winner produced."

    mark_task_in_progress "$TASK_PATH" "implementation started" implement
    mkdir -p "$IMPL_DIR" || die 3 "start: could not create $IMPL_DIR"

    local taken_at snapshot_json
    taken_at="$(date -u +%Y-%m-%d)"
    snapshot_json="$(jq -n \
      --arg takenAt "$taken_at" --arg hash "$live_hash" \
      --argjson alignment "$live_alignment_json" --argjson workOrders "$live_workorders_json" \
      '{schemaVersion: 1, takenAt: $takenAt, hash: $hash, alignment: $alignment, workOrders: $workOrders}')"
    write_atomic "$SNAPSHOT_FILE" "$snapshot_json"

    snapshot_hash_on_disk="$live_hash"
    snapshot_alignment_json="$live_alignment_json"
    snapshot_workorders_json="$live_workorders_json"

  else
    # ---- resumed run: the snapshot must agree with itself, then with the live files -------------
    run_kind="resumed"
    drift_checked=true

    snapshot_hash_on_disk="$(printf '%s' "$snapshot_doc" | jq -r '.hash // empty')"
    snapshot_alignment_json="$(printf '%s' "$snapshot_doc" | jq -c '.alignment')"
    snapshot_workorders_json="$(printf '%s' "$snapshot_doc" | jq -c '.workOrders')"
    [ -n "$snapshot_hash_on_disk" ] || die 3 "start: $SNAPSHOT_FILE has no usable hash field"

    local self_hash
    self_hash="$(snapshot_self_hash "$snapshot_alignment_json" "$snapshot_workorders_json")" \
      || die 3 "start: could not re-derive a hash from $SNAPSHOT_FILE's own alignment and workOrders fields (see stderr above)"
    [ "$self_hash" = "$snapshot_hash_on_disk" ] \
      || die 17 "start: $SNAPSHOT_FILE's own hash field ($snapshot_hash_on_disk) disagrees with a hash re-derived from its own alignment and workOrders fields ($self_hash). The snapshot file was edited after it was written; restore it from git history, or remove it and accept that the frozen state is lost. Never edit it by hand."

    if [ "$live_hash" != "$snapshot_hash_on_disk" ]; then
      contract_changed="$(jq -n --argjson a "$snapshot_alignment_json" --argjson b "$live_alignment_json" \
        'if $a == $b then false else true end')"
      # Every drift halt reason begins with "design drift: ", which is what `restart` reads to tell
      # an order halted by a design change from one halted for a spent attempt counter or a
      # load-bearing finding. A prefix rather than a field of its own, the same way the attempt cap
      # already writes "attempts spent" and `grant-attempt` already reads it.
      drifted_orders_json="$(jq -n --argjson snap "$snapshot_workorders_json" --argjson live "$live_workorders_json" '
          ($live | map({(.id): .}) | add // {}) as $liveMap
          | [ $snap[] | . as $s
              | ($liveMap[$s.id]) as $l
              | if ($l == null) then
                  {id: $s.id, reason: ("design drift: the design removed " + $s.id + " since the snapshot was taken, so its design file no longer exists")}
                elif ($l != $s) then
                  {id: $s.id, reason: ("design drift: the design file for " + $s.id + " has changed since the snapshot was taken")}
                else
                  empty
                end
            ]
        ')"
      # A changed criterion is design drift for every order that serves or owns it, the same as
      # a changed order file: the tests are written from the frozen criterion, so an order built
      # after the change would assert the old sentence (live-run row 86). Changed means the
      # snapshot's criterion object differs from the live one or is gone from it. An order that
      # already drifted on its own file carries both reasons, as two segments of one halt. The
      # clearing below removes the segment about the design file alone. So one reopen that changed
      # the file and the criterion keeps the order halted when only the file goes back.
      if [ "$contract_changed" = "true" ]; then
        changed_criteria_json="$(jq -cn --argjson a "$snapshot_alignment_json" --argjson b "$live_alignment_json" '
            (($b.criteria // []) | map({(.id): .}) | add // {}) as $liveMap
            | [ ($a.criteria // [])[] | select($liveMap[.id] != .) | .id ]')"
        drifted_orders_json="$(jq -cn --argjson drifted "$drifted_orders_json" --argjson snap "$snapshot_workorders_json" --argjson changed "$changed_criteria_json" "$HALT_MERGE_JQ"'
            [ $snap[] | . as $s
              | ([ (($s.criteriaServed // []) + ($s.criteriaOwned // [])) | unique[] | . as $c | select(($changed | index($c)) != null) ]) as $hits
              | select(($hits | length) > 0)
              | {id: $s.id, reason: ("design drift: criterion " + ($hits | join(", ")) + ", which " + $s.id + " serves, changed since the snapshot was taken")}
            ] as $byCriterion
            | ($drifted | map(.id)) as $have
            | ($drifted | map(. as $d
                | (([ $byCriterion[] | select(.id == $d.id) | .reason ])[0]) as $c
                | if $c == null then $d else ($d + {reason: halt_merge($c; $d.reason)}) end))
              + [ $byCriterion[] | . as $b | select(($have | index($b.id)) == null) ]')"
      fi
      # A drifted order that has not started is not halted: nothing was built against its old
      # shape, so it is replaced in the snapshot by the live copy instead, and its dependents are
      # untouched (live-run row 72). Started means a ledger step reached or an attempt spent, a
      # frozen test record, or a build record. An order gone from the live design has no copy to
      # take: unstarted, it is dropped from the snapshot and the ledger, because its frozen copy
      # declares owned files and dependencies the live design no longer has, and a build order
      # derived over them refuses a conflict that does not exist (live-run row 82); started, it
      # stays a halt and `restart` drops it. The live copy is taken, or the frozen one dropped,
      # only when design closed on the live files, the same rule a new run applies to the whole
      # design.
      local started_ids_json
      started_ids_json="$(started_orders_json "$TASK_PATH")"
      resnapshot_ids_json="$(jq -n --argjson drifted "$drifted_orders_json" --argjson started "$started_ids_json" --argjson live "$live_workorders_json" '
          ($live | map(.id)) as $liveIds
          | [ $drifted[] | .id as $d | select(($started | index($d)) == null) | select(($liveIds | index($d)) != null) | $d ]')"
      removed_ids_json="$(jq -n --argjson drifted "$drifted_orders_json" --argjson started "$started_ids_json" --argjson live "$live_workorders_json" '
          ($live | map(.id)) as $liveIds
          | [ $drifted[] | .id as $d | select(($started | index($d)) == null) | select(($liveIds | index($d)) == null) | $d ]')"
      # A started order whose live copy differs from the frozen one only by added owned files is
      # not halted either (live-run row 91), nor by files it newly shares (gap row 287), and neither is one that only took research findings
      # from `account` (gap row 226), and neither is one whose reasoning only grew by
      # `update --append-reasoning`: the live value starts with the frozen one (gap row 227).
      # Neither is one whose absence rows design marked reviewed (gap row 237). Its
      # frozen tests were written from the criteria and the order's other fields, and none of
      # those changed, so the live copy is taken in place:
      # the ledger entry keeps its step and attempts, and its dependents are untouched. The next
      # build brief then carries the new findings. Any other difference, a removed owned file, a
      # reasoning whose earlier text changed, or a changed criterion it serves, halts as before.
      # The program also lists what changed in each order, and a refusal names that list (gap row
      # 241), so the cause a person reads is the one this comparison found.
      widened_json="$(jq -n --argjson drifted "$drifted_orders_json" --argjson started "$started_ids_json" \
          --argjson snap "$snapshot_workorders_json" --argjson live "$live_workorders_json" --argjson changed "$changed_criteria_json" '
          ($live | map({(.id): .}) | add // {}) as $liveMap
          | ($snap | map({(.id): .}) | add // {}) as $snapMap
          | [ $drifted[] | .id as $d
              | select(($started | index($d)) != null)
              | ($snapMap[$d]) as $s | ($liveMap[$d]) as $l
              | select($l != null)
              | select(($l | del(.ownedFiles, .sharedFiles, .findings, .reasoning, .absenceReviewed)) == ($s | del(.ownedFiles, .sharedFiles, .findings, .reasoning, .absenceReviewed)))
              | select(($l.reasoning // "") | startswith($s.reasoning // ""))
              | select(((($s.ownedFiles // []) - ($l.ownedFiles // [])) | length) == 0)
              | select(((($s.sharedFiles // []) - ($l.sharedFiles // [])) | length) == 0)
              | select(([ (($s.criteriaServed // []) + ($s.criteriaOwned // []))[] | . as $c | select(($changed | index($c)) != null) ] | length) == 0)
              | [ (if ((($l.ownedFiles // []) - ($s.ownedFiles // [])) | length) > 0 then "gained owned files" else empty end),
                  (if ((($l.sharedFiles // []) - ($s.sharedFiles // [])) | length) > 0 then "gained shared files" else empty end),
                  (if $l.findings != $s.findings then "findings changed" else empty end),
                  (if $l.reasoning != $s.reasoning then "reasoning appended" else empty end),
                  (if $l.absenceReviewed != $s.absenceReviewed then "absence rows marked reviewed changed" else empty end) ] as $why
              | select(($why | length) > 0)
              | {id: $d, why: $why} ]')"
      widened_ids_json="$(printf '%s' "$widened_json" | jq -c 'map(.id)')"
      # A changed contract refreshes the snapshot's alignment under the same rule, whether or not
      # an order is taken fresh: a criterion nobody serves yet, or one only halted orders serve,
      # still has to be the frozen copy the next order's tests are written from.
      local drift_what=""
      if [ "$(printf '%s' "$resnapshot_ids_json" | jq 'length')" -gt 0 ] || [ "$(printf '%s' "$removed_ids_json" | jq 'length')" -gt 0 ]; then
        drift_what="these work orders changed since the snapshot was taken and have not started: $(jq -nr --argjson a "$resnapshot_ids_json" --argjson b "$removed_ids_json" '$a + $b | join(", ")'). Each would be taken fresh from the live design, or dropped where the live design no longer holds it"
      fi
      if [ "$(printf '%s' "$widened_ids_json" | jq 'length')" -gt 0 ]; then
        [ -z "$drift_what" ] || drift_what="$drift_what; and "
        drift_what="${drift_what}these started work orders changed only in fields their frozen tests were not written from: $(printf '%s' "$widened_json" | jq -r 'map(.id + " (" + (.why | join(", ")) + ")") | join(", ")'). Each would take its live copy in place, with its frozen tests untouched"
        resnapshot_ids_json="$(jq -cn --argjson a "$resnapshot_ids_json" --argjson b "$widened_ids_json" '$a + $b')"
      fi
      if [ "$contract_changed" = "true" ]; then
        [ -z "$drift_what" ] || drift_what="$drift_what; and "
        drift_what="${drift_what}the contract changed since the snapshot was taken, and the snapshot would take the live alignment.json"
      fi
      if [ -n "$drift_what" ]; then
        [ "$(design_closed_state)" = "ok" ] && [ "$(design_closed_hash)" = "$live_hash" ] \
          || die 13 "start: $drift_what, but $CLOSED_FILE does not record a close over the live alignment.json and design/*.json. Close design again, then run start."
        # The removed orders leave the document before the helper runs, so the one hash it
        # re-derives covers the live copies taken in and the frozen copies dropped together.
        resnapshot_doc="$(snapshot_with_live_orders "$(printf '%s' "$snapshot_doc" | jq -c --argjson ids "$removed_ids_json" \
            '.workOrders = [ .workOrders[] | . as $o | select(($ids | index($o.id)) == null) ]')" "$resnapshot_ids_json" "$live_workorders_json" "$live_alignment_json")" \
          || die 3 "start: could not re-derive a hash for the snapshot with the live copies taken in (see stderr above)"
        resnapshot_hash="$(printf '%s' "$resnapshot_doc" | jq -r '.hash')"
        snapshot_alignment_json="$(printf '%s' "$resnapshot_doc" | jq -c '.alignment')"
        snapshot_workorders_json="$(printf '%s' "$resnapshot_doc" | jq -c '.workOrders')"
        drifted_orders_json="$(jq -cn --argjson drifted "$drifted_orders_json" --argjson ids "$resnapshot_ids_json" --argjson gone "$removed_ids_json" \
          '[ $drifted[] | . as $d | select(($ids + $gone | index($d.id)) == null) ]')"
      fi
      # A started order the design removed stays in the snapshot, halted, until `restart` moves
      # its records aside. It will never build again, so its owned files take no part in the build
      # order derived below: the live survivor that absorbed them would otherwise refuse a
      # conflict with a copy nothing will build.
      halted_removed_ids_json="$(jq -cn --argjson drifted "$drifted_orders_json" --argjson live "$live_workorders_json" '
          ($live | map(.id)) as $liveIds
          | [ $drifted[] | .id | . as $d | select(($liveIds | index($d)) == null) ]')"
      # An order that depends on a drifted one, directly or through another order, is halted too.
      # It would otherwise build against an interface that moved, which is the same unbounded work
      # the drifted order itself is halted for (ideal/implementation.md, the unattended-answers
      # table: "Halt every order the change touches"). The reason names the drifted orders it
      # reaches, so a person reads what to look at without walking the graph themselves. An order
      # that drifted itself keeps its own reason and never takes this one.
      dependent_halts_json="$(jq -n --argjson orders "$snapshot_workorders_json" --argjson drifted "$drifted_orders_json" '
          def reach($adj; $start):
            def go($frontier; $visited):
              if ($frontier | length) == 0 then $visited
              else
                ($frontier[0]) as $node
                | ($frontier[1:]) as $rest
                | (($adj[$node] // []) - $visited) as $new
                | go($rest + $new; ($visited + $new))
              end;
            go(($adj[$start] // []); ($adj[$start] // []));
          ($drifted | map(.id)) as $bad
          | ($orders | map({id: .id, dependsOn: (.dependsOn // [])})) as $trimmed
          | (reduce $trimmed[] as $o ({}; .[$o.id] = $o.dependsOn)) as $adj
          | [ $trimmed[] | .id as $x
              | select(($bad | index($x)) == null)
              | (reach($adj; $x)) as $r
              # Bound first: after the pipe `.` would be $bad, and an array always finds itself.
              | ([ $r[] | . as $d | select(($bad | index($d)) != null) ]) as $hits
              | select(($hits | length) > 0)
              | {id: $x, reason: ("design drift: " + $x + " depends on " + ($hits | join(", ")) + ", directly or through another order, and that order drifted since the snapshot was taken")}
            ]
        ')"
      drift_halts_json="$(jq -cn --argjson a "$drifted_orders_json" --argjson b "$dependent_halts_json" '$a + $b')"
      new_live_order_ids_json="$(jq -n --argjson snap "$snapshot_workorders_json" --argjson live "$live_workorders_json" \
        '([ $live[].id ]) - ([ $snap[].id ])')"
    fi
  fi

  # --- step 9: read criteria and work orders from the snapshot only, from here on ----------------
  local snapshot_criteria_json
  snapshot_criteria_json="$(printf '%s' "$snapshot_alignment_json" | jq -c '[ (.criteria // [])[] | {id: .id} ]')"

  # --- step 10: derive the build order; refuse on a cycle or an owned-file overlap ----------------
  local build_orders_json cycles_json overlap_json
  build_orders_json="$(jq -cn --argjson orders "$snapshot_workorders_json" --argjson gone "$halted_removed_ids_json" \
    '[ $orders[] | . as $o | select(($gone | index($o.id)) == null) ]')"
  cycles_json="$(jq -c -n --argjson orders "$build_orders_json" '
      def reach($adj; $start):
        def go($frontier; $visited):
          if ($frontier | length) == 0 then $visited
          else
            ($frontier[0]) as $node
            | ($frontier[1:]) as $rest
            | (($adj[$node] // []) - $visited) as $new
            | go($rest + $new; ($visited + $new))
          end;
        go(($adj[$start] // []); ($adj[$start] // []));
      ($orders | map({id: .id, dependsOn: (.dependsOn // [])})) as $trimmed
      | ($trimmed | map(.id)) as $ids
      | (reduce $trimmed[] as $o ({}; .[$o.id] = $o.dependsOn)) as $adj
      | [ $ids[] | . as $x | select((reach($adj; $x) | index($x)) != null) ]
    ')"
  overlap_json="$(printf '%s' "$build_orders_json" | jq -c "$OWNED_OVERLAP_JQ")"
  local cycle_count overlap_count
  cycle_count="$(printf '%s' "$cycles_json" | jq 'length')"
  overlap_count="$(printf '%s' "$overlap_json" | jq 'length')"
  if [ "$cycle_count" -gt 0 ] || [ "$overlap_count" -gt 0 ]; then
    local msg=""
    if [ "$cycle_count" -gt 0 ]; then
      msg="a dependency cycle among $(printf '%s' "$cycles_json" | jq -r 'join(", ")')"
    fi
    if [ "$overlap_count" -gt 0 ]; then
      local overlap_text
      overlap_text="$(printf '%s' "$overlap_json" | jq -r '[.[] | (.ids | join(" and ")) + " both declare " + .path] | join("; ")')"
      if [ -n "$msg" ]; then msg="$msg; and $overlap_text"; else msg="$overlap_text"; fi
    fi
    die 8 "start: the build order could not be derived from the frozen work orders: $msg"
  fi

  # A light task's review runs no visual regression (gap row 197). The log is written here, before
  # the build's first commit is read, because review refuses a tree that moved after finish.
  if task_is_light "$TASK_PATH" \
    && [ "$(jq -r '.surfaces.visualRegression.enabled // false' "$(resolve_project_folder "$TASK_PATH")/project.json" 2>/dev/null)" = "true" ]; then
    log_compromise "$TASK_PATH" review "visual regression" \
      "run the visual regression surfaces at review and compare each one with its baseline"
  fi

  # --- step 11: capture the commit the build starts from -------------------------------------------
  local started_from started_from_rc
  started_from="$(git -C "$code_path" rev-parse HEAD 2>/dev/null)"
  started_from_rc=$?
  [ "$started_from_rc" -eq 0 ] && [ -n "$started_from" ] \
    || die 3 "start: could not capture the current commit (git rev-parse HEAD failed in $code_path). An empty repository with no commit yet has nothing to roll back to."

  # --- step 12: open the ledger, or reopen it -------------------------------------------------------
  local ledger_present ledger_doc opened_as
  ledger_present=false
  ledger_doc=""
  if [ -f "$LEDGER_FILE" ]; then
    if [ -r "$LEDGER_FILE" ] && ledger_doc="$(jq -c '.' "$LEDGER_FILE" 2>/dev/null)" && [ -n "$ledger_doc" ]; then
      ledger_present=true
    else
      die 3 "start: $LEDGER_FILE exists but could not be read as JSON. Repair or remove it by hand before running this again."
    fi
  fi

  local final_orders_json final_criteria_json ledger_started_from ledger_run_mode ledger_started_at
  local halts_cleared_json='[]' drift_cleared_ids_json='[]'
  local started_from_before_json='[]' rewritten_from=""
  if [ "$ledger_present" = "true" ]; then
    opened_as="reopened"
    local stored_snapshot_hash
    stored_snapshot_hash="$(printf '%s' "$ledger_doc" | jq -r '.snapshotHash // empty')"
    [ "$stored_snapshot_hash" = "$snapshot_hash_on_disk" ] \
      || die 9 "start: $LEDGER_FILE was opened against a different snapshot (its snapshotHash is $stored_snapshot_hash) than the one now on disk (hash $snapshot_hash_on_disk). A ledger and a snapshot that do not belong together are never read as a pair; investigate before proceeding."

    ledger_started_from="$(ledger_required_string "$ledger_doc" "startedFrom")" \
      || die 3 "start: $LEDGER_FILE is damaged (see stderr above). Repair or remove it by hand before running this again."
    # The mode is read from the task at every start, so a person who set it interactive after the
    # build halted, or scoped it to the build alone, is obeyed by the steps that follow
    # (nyc defect 20). The ledger keeps the mode the build runs under from here on.
    ledger_run_mode="$run_mode"

    # --- exit 82: the branch was rewritten under the ledger ---------------------------------------
    # A rebase or an amend leaves startedFrom on no branch. preconditions would label the baseline
    # with it and finish would compute a range git cannot resolve, so HEAD must descend from it, or
    # the person names the new base with --rebased-onto and the old value is kept beside the new.
    started_from_before_json="$(printf '%s' "$ledger_doc" | jq -c '.startedFromBefore // []')"
    if [ -n "$rebased_onto" ]; then
      local rebased_full
      rebased_full="$(git -C "$code_path" rev-parse --verify --quiet "${rebased_onto}^{commit}" 2>/dev/null)"
      [ -n "$rebased_full" ] \
        || die 3 "start: --rebased-onto ($rebased_onto) is not a commit in the code repository at $code_path."
      [ "$rebased_full" != "$ledger_started_from" ] \
        || die 3 "start: --rebased-onto ($rebased_onto) is the commit $LEDGER_FILE already holds as startedFrom. Nothing to rewrite."
      # The flag answers exit 82 alone. On a branch that still descends from startedFrom it would
      # move the start past the build's own commits, so a wrong rewrite is undone by hand instead.
      if git -C "$code_path" merge-base --is-ancestor "$ledger_started_from" "$started_from" >/dev/null 2>&1; then
        die 3 "start: --rebased-onto was given, but HEAD ($started_from) still descends from startedFrom ($ledger_started_from). The branch was not rewritten, so there is nothing to repair. A wrong earlier rewrite is corrected by editing startedFrom in $LEDGER_FILE by hand."
      fi
      git -C "$code_path" merge-base --is-ancestor "$rebased_full" "$started_from" >/dev/null 2>&1 \
        || die 3 "start: --rebased-onto ($rebased_full) is not an ancestor of HEAD ($started_from) in $code_path. The build's own commits must follow it."
      rewritten_from="$ledger_started_from"
      started_from_before_json="$(printf '%s' "$started_from_before_json" | jq -c --arg c "$ledger_started_from" --arg at "$(date -u +%Y-%m-%d)" '. + [{commit: $c, at: $at}]')"
      ledger_started_from="$rebased_full"
    elif ! git -C "$code_path" merge-base --is-ancestor "$ledger_started_from" "$started_from" >/dev/null 2>&1; then
      die 82 "start: HEAD ($started_from) in $code_path does not descend from the commit this build started from ($ledger_started_from). The branch was rewritten since the ledger was opened, by a rebase or an amend. The ledger keeps that commit: preconditions would label the baseline with it, and finish would compute a range git cannot resolve. Run start again with --rebased-onto <commit>, naming the commit the branch now builds on. That rewrites startedFrom and keeps the old value under startedFromBefore. The baseline must then be retaken: move $IMPL_DIR/baseline.json and $IMPL_DIR/baseline-output aside, then run preconditions."
    fi

    # --- exit 83: a baseline this version cannot subtract from --------------------------------------
    # An earlier version kept each tool's output inline and named no outputFile. build-record reads
    # only outputFile, so that baseline turns every failing tool check unknown and spends an attempt
    # on a schema change. The schema comparison reads the shape; the one rule it states in words
    # and cannot express, outputFile present whenever the entry ran, is read here beside it.
    local bl_compare bl_gaps
    if [ -f "$IMPL_DIR/baseline.json" ]; then
      bl_compare="$(schema_check_compare "$BASELINE_SCHEMA_FILE" "$IMPL_DIR/baseline.json")" \
        || die 3 "start: $IMPL_DIR/baseline.json exists but could not be read as JSON, or could not be compared against $BASELINE_SCHEMA_FILE. Repair or remove it by hand before running this again."
      bl_gaps="$(jq -r --argjson r "$bl_compare" '
          [ ($r.missing // [])[] | "no " + .field ]
          + [ ($r.unreadable // [])[] | .field + " " + .reason ]
          + [ ( [ (if (.suite | type) == "array" then .suite[] else empty end) | {name: ("suite " + ((.framework // "?") | tostring)), row: .} ]
                + [ {name: "codingStandards", row: .codingStandards}, {name: "staticAnalysis", row: .staticAnalysis}, {name: "security", row: .security} ] )[]
              | select((.row | type) == "object" and (.row | has("exitCode")) and ((.row | has("outputFile")) | not))
              | .name + " ran but names no outputFile" ]
          | join("; ")' "$IMPL_DIR/baseline.json" 2>/dev/null)"
      [ -z "$bl_gaps" ] \
        || die 83 "start: $IMPL_DIR/baseline.json is not in the shape this version writes: $bl_gaps. build-record subtracts from outputFile alone, so every failing tool check would read unknown. An attempt would be spent on that. Move $IMPL_DIR/baseline.json and $IMPL_DIR/baseline-output aside, then run preconditions to retake the baseline at commit $ledger_started_from."
    fi
    # A ledger opened before startedAt existed is repaired here, by its one producer running again.
    ledger_started_at="$(printf '%s' "$ledger_doc" | jq -r '.startedAt // empty')"
    [ -n "$ledger_started_at" ] || ledger_started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # A drift halt never writes over a reason the order already carries. The old text is kept after
    # the new one, joined by "; earlier: ", so nothing loses a reason; and a start run repeated on
    # the same drift adds nothing, because the reason it would write is already at the front.
    # An unstarted order the design removed leaves the order list here, as it left the snapshot.
    final_orders_json="$(printf '%s' "$ledger_doc" | jq -c --argjson drifted "$drift_halts_json" --argjson gone "$removed_ids_json" "$HALT_MERGE_JQ"'
        .orders | map(. as $o | select(($gone | index($o.id)) == null)) | map(
          . as $o
          | (([ $drifted[] | select(.id == $o.id) | .reason ])[0]) as $r
          | if $r == null then $o else ($o + {haltedBecause: halt_merge($o.haltedBecause; $r)}) end
        )
      ')"
    # A drift halt outlives the drift that wrote it (live-run row 143). The design goes back to
    # what it was, this run finds no drift, and the order stays stopped with the old reason. So
    # an order this run found no drift for loses the `design drift` segment naming its own design
    # copy. Every other segment stays and the order stays halted with it, the way a grant keeps
    # what it does not answer. An order left with no segment is no longer halted and resumes at
    # its own step. Only a resumed run clears, because only a resumed run compares the live design
    # to the snapshot; a new run has nothing to compare and writes no halt.
    # `clear-halt` still refuses a drift halt (exit 85). `start` is the one action that computes
    # drift, and a second computation there would be a second producer for one fact.
    #
    # Two drift reasons are left for `restart`, because this comparison cannot re-derive either.
    # A criterion halt is written in the same run that replaces the snapshot's alignment with the
    # live contract, so the next comparison finds no difference while the order's frozen tests
    # still assert the old sentence. Clearing it would let that order build against them. And a
    # halt that names another order stands on that order's state, not on this comparison, so it
    # waits for the restart that takes the order it names fresh.
    halts_cleared_json="$(printf '%s' "$ledger_doc" | jq -c '.haltsCleared // []')"
    if [ "$drift_checked" = "true" ]; then
      local cleared_id cleared_halt cleared_rest cleared_today
      cleared_today="$(date -u +%Y-%m-%d)"
      for cleared_id in $(printf '%s' "$final_orders_json" | jq -r --argjson drifted "$drift_halts_json" '
          ($drifted | map(.id)) as $bad
          | [ .[] | . as $o | select(($bad | index($o.id)) == null) | select($o | has("haltedBecause")) | $o.id ][]'); do
        cleared_halt="$(printf '%s' "$final_orders_json" | jq -r --arg id "$cleared_id" \
          '.[] | select(.id == $id) | .haltedBecause')"
        [ -n "$(halt_segments_matching "$cleared_halt" "$DRIFT_OWN_COPY_PREFIXES" keep)" ] || continue
        cleared_rest="$(halt_segments_matching "$cleared_halt" "$DRIFT_OWN_COPY_PREFIXES" drop)"
        final_orders_json="$(printf '%s' "$final_orders_json" | jq -c --arg id "$cleared_id" --arg rest "$cleared_rest" '
            map(if .id == $id then
                  (if $rest == "" then del(.haltedBecause) else .haltedBecause = $rest end)
                else . end)')"
        halts_cleared_json="$(printf '%s' "$halts_cleared_json" | jq -c --arg id "$cleared_id" \
          --arg reason "$cleared_halt" --arg today "$cleared_today" --arg rest "$cleared_rest" '
          . + [{id: $id, reason: $reason, clearedAt: $today,
                because: ("start: this resumed run compared the live design to the snapshot and found no drift for "
                          + $id + ", so the design drift segment naming its own design copy cleared"
                          + (if $rest == "" then "" else "; the order stays halted for what is left" end))}]')"
        drift_cleared_ids_json="$(printf '%s' "$drift_cleared_ids_json" | jq -c --arg id "$cleared_id" '. + [$id]')"
      done
    fi
    # The list follows the snapshot's criteria, which a contract change just refreshed: an entry
    # the ledger holds is kept with its judgements, a new criterion opens as not judged, and one
    # the contract dropped leaves. A changed criterion's serving orders are unstarted or halted
    # here, so no judgement is reset; `restart` resets the halted ones' when it takes them fresh.
    final_criteria_json="$(printf '%s' "$ledger_doc" | jq -c --argjson live "$snapshot_criteria_json" '
        ((.criteria // []) | map({(.id): .}) | add // {}) as $have
        | [ $live[] | .id as $id | ($have[$id] // {id: $id, rowState: "not-judged"}) ]')"
  else
    opened_as="opened"
    [ -z "$rebased_onto" ] \
      || die 3 "start: --rebased-onto rewrites the startedFrom a ledger holds, and this task has no ledger yet. Run start without it."
    ledger_started_from="$started_from"
    ledger_run_mode="$run_mode"
    ledger_started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    local base_orders_json
    base_orders_json="$(printf '%s' "$snapshot_workorders_json" | jq -c '[ .[] | {id: .id, lastStep: null, attemptsUsed: 0, roundsUsed: 0} ]')"
    # A ledger opened here carries no halt yet, so there is nothing to keep. The same expression is
    # written anyway, so the two paths cannot drift into halting two different ways.
    final_orders_json="$(jq -n --argjson orders "$base_orders_json" --argjson drifted "$drift_halts_json" "$HALT_MERGE_JQ"'
        $orders | map(
          . as $o
          | (([ $drifted[] | select(.id == $o.id) | .reason ])[0]) as $r
          | if $r == null then $o else ($o + {haltedBecause: halt_merge($o.haltedBecause; $r)}) end
        )
      ')"
    final_criteria_json="$(printf '%s' "$snapshot_criteria_json" | jq -c '[ .[] | {id: .id, rowState: "not-judged"} ]')"
  fi

  # The leftovers move only here, after every refusal, so a refused start moves nothing. An untracked
  # file moves. A modified file is copied, then its tracked version comes back from HEAD.
  local set_aside_json='[]' set_aside_dir="" lo_move_tsv
  [ -z "$ledger_doc" ] || set_aside_json="$(printf '%s' "$ledger_doc" | jq -c '.setAside // []')"
  if [ "$leftovers_choice" = "set-aside" ] && [ "$leftovers_json" != "[]" ]; then
    set_aside_dir="$IMPL_DIR/set-aside/$(date -u +%Y%m%dT%H%M%SZ)"
    [ ! -e "$set_aside_dir" ] || die 3 "start: $set_aside_dir already exists. Run start again in a second."
    lo_move_tsv="$(printf '%s' "$leftovers_json" | jq -r '.[] | .status + "\t" + .path')"
    while IFS="$lo_tab" read -r lo_xy lo_rel; do
      [ -n "$lo_rel" ] || continue
      mkdir -p "$(dirname -- "$set_aside_dir/$lo_rel")" || die 3 "start: could not create a folder under $set_aside_dir"
      if [ "$lo_xy" = "??" ]; then
        mv -- "$code_path/$lo_rel" "$set_aside_dir/$lo_rel" \
          || die 3 "start: could not move $lo_rel to $set_aside_dir. The files moved before it are in that folder, and the ledger does not record them."
      else
        cp -p -- "$code_path/$lo_rel" "$set_aside_dir/$lo_rel" && git -C "$code_path" checkout -q HEAD -- "$lo_rel" \
          || die 3 "start: could not set aside the change to $lo_rel in $set_aside_dir. The files moved before it are in that folder, and the ledger does not record them."
      fi
    done <<LO_MOVE
$lo_move_tsv
LO_MOVE
    set_aside_json="$(printf '%s' "$set_aside_json" | jq -c --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg folder "$set_aside_dir" --argjson paths "$leftovers_json" \
      '. + [{at: $at, folder: $folder, paths: [ $paths[] | {path, orders} ]}]')"
  fi

  # The re-snapshot lands after the ledger's hash check above, which reads the hash the ledger was
  # opened against; the ledger written below carries the new one, and one line per replaced order
  # naming both, so a reader can tell which shape each order was built from.
  local resnapshots_json='[]'
  [ -z "$ledger_doc" ] || resnapshots_json="$(printf '%s' "$ledger_doc" | jq -c '.resnapshots // []')"
  if [ -n "$resnapshot_doc" ]; then
    write_atomic "$SNAPSHOT_FILE" "$resnapshot_doc"
    resnapshots_json="$(jq -cn --argjson have "$resnapshots_json" --argjson ids "$resnapshot_ids_json" \
      --arg from "$snapshot_hash_on_disk" --arg to "$resnapshot_hash" --arg at "$(date -u +%Y-%m-%d)" \
      '$have + [ $ids[] | {id: ., from: $from, to: $to, at: $at} ]')"
    snapshot_hash_on_disk="$resnapshot_hash"
  fi

  mkdir -p "$IMPL_DIR" || die 3 "start: could not create $IMPL_DIR"
  local ledger_json_out
  ledger_json_out="$(jq -n \
    --arg startedFrom "$ledger_started_from" --arg runMode "$ledger_run_mode" \
    --arg snapshotHash "$snapshot_hash_on_disk" --arg startedAt "$ledger_started_at" \
    --argjson orders "$final_orders_json" --argjson criteria "$final_criteria_json" \
    --argjson resnapshots "$resnapshots_json" --argjson startedFromBefore "$started_from_before_json" \
    --argjson haltsCleared "$halts_cleared_json" --argjson setAside "$set_aside_json" \
    '{schemaVersion: 1, startedFrom: $startedFrom, startedAt: $startedAt, runMode: $runMode, snapshotHash: $snapshotHash,
      orders: $orders, criteria: $criteria}
     | if ($startedFromBefore | length) > 0 then .startedFromBefore = $startedFromBefore else . end
     | if ($setAside | length) > 0 then .setAside = $setAside else . end
     | if ($haltsCleared | length) > 0 then .haltsCleared = $haltsCleared else . end
     | if ($resnapshots | length) > 0 then .resnapshots = $resnapshots else . end')"
  write_atomic "$LEDGER_FILE" "$ledger_json_out"

  # --- step 13: the report --------------------------------------------------------------------------
  local ready_ids_json halted_json in_flight_json
  ready_ids_json="$(jq -n --argjson orders "$snapshot_workorders_json" --argjson ledgerOrders "$final_orders_json" '
      ($ledgerOrders | map({(.id): .}) | add // {}) as $lm
      | [ $orders[] | . as $o
          | ($lm[$o.id]) as $le
          | select($le.lastStep == null)
          | select(($le.haltedBecause // null) == null)
          | select( (($o.dependsOn // []) | map($lm[.].lastStep == "closed") | all) )
          | $o.id
        ]
    ')"
  halted_json="$(printf '%s' "$final_orders_json" | jq -c '[ .[] | select((.haltedBecause // null) != null) | {id: .id, haltedBecause: .haltedBecause} ]')"
  in_flight_json="$(printf '%s' "$final_orders_json" | jq -c '
      [ .[] | select(.lastStep != null) | select(.lastStep != "closed") | select((.haltedBecause // null) == null)
        | {id: .id, lastStep: .lastStep, attemptsUsed: .attemptsUsed, roundsUsed: .roundsUsed} ]
    ')"

  local contract_changed_json
  if [ "$drift_checked" = "true" ]; then
    contract_changed_json="$contract_changed"
  else
    contract_changed_json='null'
  fi

  # An empty ready list with nothing halted and nothing in flight is a state, not a blank. Every
  # order closed is a finished build; anything else with nothing ready is a dependency graph where
  # no order can start, which a person needs told rather than left to infer from an empty list.
  local run_state all_closed_count order_total removed_halted
  order_total="$(printf '%s' "$final_orders_json" | jq 'length')"
  all_closed_count="$(printf '%s' "$final_orders_json" | jq '[ .[] | select(.lastStep == "closed") ] | length')"
  removed_halted="$(printf '%s' "$final_orders_json" | jq -r '[ .[] | select((.haltedBecause // "") | contains("design drift: the design removed ")) | .id ] | join(", ")')"
  if [ -n "$removed_halted" ] && [ "$(printf '%s' "$ready_ids_json" | jq 'length')" -gt 0 ]; then
    run_state="the design removed $removed_halted, and the frozen test record of each still guards its test files; run restart before the survivor's tests are written"
  elif [ "$(printf '%s' "$ready_ids_json" | jq 'length')" -gt 0 ]; then
    run_state="orders are ready to build"
  elif [ "$(printf '%s' "$in_flight_json" | jq 'length')" -gt 0 ]; then
    run_state="an order is in flight; continue it at the step the ledger records"
  elif [ "$(printf '%s' "$halted_json" | jq 'length')" -gt 0 ]; then
    run_state="every order that is not closed is halted; read the halt reasons and use grant-attempt, restart or clear-halt"
  elif [ "$order_total" -gt 0 ] && [ "$all_closed_count" -eq "$order_total" ]; then
    run_state="every order is closed; run finish on this task"
  else
    run_state="no order is ready, none is in flight and none is halted. Every remaining order waits on a dependency that is not closed, so nothing can start; read the order states below."
  fi
  # The ledger's copy was just written from the task, new or resumed, and every later step reads
  # it there (ledger-schema.json). So the report names the task, and the two agree.
  local reported_run_mode run_mode_source
  reported_run_mode="$run_mode"
  run_mode_source="task.json for the implement stage, written into the ledger"
  # The report, as summary lines. The snapshot and the ledger stay in their files, named by path;
  # the orders that drifted, halted and are ready are named by id, and `next` is the same answer
  # `read` gives from the same ledger. The preconditions record cannot exist before the first
  # start, and a resumed run reads whether it is there the way `read` does.
  # startedFrom prints what the ledger holds, never HEAD: after a rewrite the two differ on
  # purpose. An order with no proof in its frozen copy predates the field; every step reads it as
  # tests, and this is the one place that says so before a test author is dispatched (row 73).
  local st_started_from proof_absent
  st_started_from="$ledger_started_from"
  [ -z "$rewritten_from" ] \
    || st_started_from="$ledger_started_from | rewritten from $rewritten_from | retake the baseline: move baseline.json and baseline-output aside, then run preconditions"
  proof_absent="$(printf '%s' "$snapshot_workorders_json" | jq -r '[ .[] | select(has("proof") | not) | .id ] | join(", ")')"
  if [ -n "$proof_absent" ]; then
    proof_absent="$proof_absent | no proof in the snapshot, so each is proved by tests unless design sets gate, record or observe"
  else
    proof_absent="none: every order in the snapshot names its proof"
  fi
  local st_precon st_finished st_ledger_now st_next
  st_precon=false
  st_finished=false
  [ -f "$IMPL_DIR/preconditions.json" ] && jq empty "$IMPL_DIR/preconditions.json" 2>/dev/null && st_precon=true
  [ -f "$IMPL_DIR/finished.json" ] && jq empty "$IMPL_DIR/finished.json" 2>/dev/null && st_finished=true
  st_ledger_now="$(jq -c '.' "$LEDGER_FILE" 2>/dev/null)"
  st_next="$(im_next_step "$st_ledger_now" "$(jq -nc --argjson w "$snapshot_workorders_json" '{workOrders: $w}')" "$IMPL_DIR" "$st_precon" "$st_finished")"
  # After a retake, or a restart from before restart reverted (gap row 252), the order's own build
  # and fix commits may still be on the branch; one line per order names them while they are. Not
  # a refusal: a retake keeps them on purpose (live-run row 94). The line is dropped when there is
  # none, the way `removed:` is.
  local st_partial_json='[]'
  if [ "$run_kind" = "resumed" ]; then
    st_partial_json="$(rs_carried_commits_in_head "$TASK_PATH" "$code_path" "" "$st_ledger_now" | jq -c '
      group_by(.order) | map({order: .[0].order, commits: (map(.commit[0:7] + " " + .kind
        + (if has("missing") then " not found on this branch: " + .missing else "" end)))})')"
  fi
  im_print_summary "start" "$(jq -n \
    --arg task "$TASK_PATH" --arg codePath "$code_path" \
    --arg run "${run_kind}, ledger ${opened_as}" \
    --arg runMode "${reported_run_mode}, from ${run_mode_source}" \
    --arg branch "$current_branch" \
    --arg trunk "$(if [ "$trunk_derived" = "true" ]; then printf '%s | ' "$trunk_branch"; fi)$trunk_note" \
    --arg snapshot "$SNAPSHOT_FILE" \
    --arg snapshotHash "$snapshot_hash_on_disk | workOrders=$(printf '%s' "$snapshot_workorders_json" | jq 'length') | criteria=$(printf '%s' "$snapshot_criteria_json" | jq 'length')" \
    --arg ledger "$LEDGER_FILE" --arg startedFrom "$st_started_from" \
    --arg proofAbsent "$proof_absent" \
    --arg drift "$(if [ "$drift_checked" = "true" ]; then printf 'checked | contractChanged=%s' "$contract_changed_json"; else printf 'not checked: a first run has no earlier snapshot to compare against'; fi)" \
    --argjson drifted "$(printf '%s' "$drifted_orders_json" | jq -c '[ .[] | .id ]')" \
    --argjson haltedDependents "$(printf '%s' "$dependent_halts_json" | jq -c '[ .[] | .id ]')" \
    --argjson resnapshotted "$resnapshot_ids_json" \
    --argjson driftCleared "$drift_cleared_ids_json" \
    --argjson removed "$removed_ids_json" \
    --argjson newLiveOrders "$new_live_order_ids_json" \
    --argjson partialBuild "$st_partial_json" \
    --argjson leftovers "$(printf '%s' "$leftovers_json" | jq -c "[ $LO_TEXT_JQ ]")" \
    --arg setAside "$set_aside_dir" \
    --argjson halted "$(printf '%s' "$halted_json" | jq -c '[ .[] | {id, haltedBecause} ]')" \
    --argjson inFlight "$(printf '%s' "$in_flight_json" | jq -c '[ .[] | {id, lastStep, attempts: ("attempts=" + (.attemptsUsed | tostring)), rounds: ("rounds=" + (.roundsUsed | tostring))} ]')" \
    --argjson ready "$ready_ids_json" \
    --arg state "$run_state" --arg next "$st_next" '
    {task: $task, codePath: $codePath, run: $run, runMode: $runMode, branch: $branch, trunk: $trunk,
     snapshot: $snapshot, snapshotHash: $snapshotHash, ledger: $ledger, startedFrom: $startedFrom, proofAbsent: $proofAbsent,
     drift: $drift, drifted: $drifted, haltedDependents: $haltedDependents, resnapshotted: $resnapshotted,
     driftCleared: $driftCleared, removed: $removed, newLiveOrders: $newLiveOrders,
     partialBuild: $partialBuild, leftovers: $leftovers, setAside: $setAside,
     halted: $halted, inFlight: $inFlight, ready: $ready, state: $state, next: $next}
    | if ($leftovers | length) == 0 then del(.leftovers) else . end
    | if $setAside == "" then del(.setAside) else . end
    | if ($removed | length) == 0 then del(.removed) else . end
    | if ($driftCleared | length) == 0 then del(.driftCleared) else . end
    | if ($partialBuild | length) == 0 then del(.partialBuild) else . end')"
  exit 0
}


# ------------------------------------------------------------------------------------------------
# Step two: preconditions. Can this repository build and test at all?
#
# The skill resolves each framework's recipe, through the guides navigator for anything the catalog
# publishes and directly for a source the project configured itself, and hands the path here. This
# script never fetches a catalog address and never reads the navigator's cache behind its back
# (foundations.md, "Everything published in the catalog is read through the guides navigator").
# That split is also what keeps this action exercisable against a file on disk.
#
# Four verdicts, and version 5 paid for every one of them. `undeclared` is not `met`: a recipe that
# declared nothing was not checked, and a caller treating that as met has re-created the defect the
# declaration exists to close. A heading with nothing readable under it is `unknown`, not
# `undeclared`. A missing checker says nothing about the condition, so exit 127 is `unknown` and
# never `unmet`, because reporting it unmet sends a person to fix the wrong thing.
#
# No timeout. `timeout` is not on a stock macOS and this script runs on bash 3.2 and zsh, so a
# check that hangs hangs the step. Every check the catalog declares today is a filesystem probe or
# a version print. A recipe that ever declares a check reaching the network needs this revisited,
# and pretending to a timeout we cannot portably enforce would be worse than saying so here.
#
# The same recipe carries a second machine-readable block, `## Test commands` / `test_commands:`,
# five rows per framework (suite, file, test, changed, smoke). This step reads and records it
# alongside the conditions, in the same record, but resolves nothing and substitutes nothing: a
# row's `argv` or `nearest` tokens are copied verbatim, placeholders included, for the part of the
# step that will one day run them. Three states, the same discipline as the conditions section:
# no `## Test commands` heading and no `test_commands:` key is `undeclared`; the heading present
# with no key (indistinguishable from a misspelled key) is `unparseable`; the key present with
# rows, however many, is `ok`. A row answers with `argv` and `cost`, or with `absent` (optionally
# `nearest`); the folded prose carried by `trap:`, `id_form:` and `absent:`'s own text is for a
# person and a model reading the recipe itself, never parsed here. An `argv` or `nearest` value
# that does not parse as a JSON array of strings is a defect in the recipe: the row is kept, named
# `unreadable`, rather than dropped. None of this changes the run's verdict for four of the five
# rows; a framework with no test commands at all is unrelated to whether its preconditions are
# met. The fifth, `smoke`, is different: once every declared condition comes back `met` or
# `undeclared`, this step runs that row and folds what it found into the same worst-of verdict the
# conditions already compute, on the same terms: `met` and `undeclared` continue, `unmet` and
# `unknown` stop the run.
#
# The fifth row, `smoke`, is run rather than merely recorded, once every declared condition for
# that framework has already come back `met` or `undeclared`: running it before that would only
# fail for a reason a condition already named, and teach nothing new. A token in its `argv` that
# is exactly one placeholder (`{runner}`, `{file}`, ...) is replaced whole by a value the caller
# supplies with a repeatable `--value <name>=<value>` flag; nothing else in a token is touched, and
# a placeholder nobody supplied a value for makes the run `unknown`, naming which one. A recipe
# documenting a default for a placeholder in its own prose, the way python-cli documents one for
# `{runner}`, is never read here as a fallback: the caller supplies it or the run says so.
# A name the recipe's own `## Tokens` blocks give is the one exception, filled after cr_resolve. The
# command runs the same way a condition's own check runs, as arguments from inside the code
# repository and never through a shell. `met` on exit 0, `unmet` on any other exit the command
# actually returned, `unknown` when it could not be run at all (the conditions did not permit it,
# the recipe carries no readable smoke row, or a placeholder went unsupplied) with a reason saying
# why, and `undeclared` when the recipe's own smoke row is one of its `absent:` rows, which
# `claude-code-plugins` writes for all five. Standard output and standard error are captured
# together and recorded, trimmed to the last 2000 characters with a flag saying so, whenever the
# verdict is not `met`; a `met` run records none. This is the one row where the discipline changes:
# every other row here is read and never run, because this step still resolves nothing else and
# substitutes nothing else. Effect on the run is the same rule the conditions already follow: `met`
# and `undeclared` continue, `unmet` and `unknown` stop with the same exit 19 a condition itself
# would stop it with; no new exit code exists for this.
#
# Once every framework's own verdict and its own smoke run both land on `met` or `undeclared`, this
# step takes the baseline: what was already broken at the commit the build starts from, read from
# the ledger's own `startedFrom` rather than a fresh `git rev-parse`, so the commit this baseline
# claims and the commit the ledger would roll back to are always the same value. It is a separate
# record, <task_folder>/implementation/baseline.json (baseline-schema.json), taken once per commit:
# a second `preconditions` run at the same commit leaves it alone, and a run whose ledger started
# from a different commit refuses rather than overwrite it, naming both commits (exit 21). Four
# parts. The suite runs whole and unscoped, from the same `suite` test-command row this step
# already resolved for each framework; a placeholder none of the caller's `--value` flags supplied
# makes it `unknown`, naming the placeholder, the same rule the smoke row already follows, and its
# exit code and output are kept whenever the command actually ran, `met` or not, because a baseline
# is a record of the whole state and not only of what pointed at a defect. Coding standards, static
# analysis and the security tool each take their own argv from the caller, one token per repeated
# `--standards`, `--static-analysis` or `--security` flag, and run over the scope below, with a
# token that is exactly `{paths}` expanding to that scope one argv token per path. A tool the caller
# named no command for is recorded `undeclared` with a reason saying so, never guessed from the
# project and never invented. These three are what `build-record`'s own tool checks compare a
# failure against later, which is the whole reason they are measured here first.
# The scope, the union of every work order's own `ownedFiles` from the snapshot, is recorded too. It
# is what a `{paths}` token in any of the three tool commands expands to, and it is recorded rather
# than re-derived so a later reader sees what was measured. It is deliberately not what the suite
# scopes to, because at this point the
# orders' own tests do not exist and no framework declares a command mapping paths to the tests
# that cover them. The baseline never changes this run's own verdict or its exit code: a suite that
# is already red here is a fact worth recording, not a reason to refuse.
# ------------------------------------------------------------------------------------------------

# True when a check value would mean something other than what its author read. A recipe body is
# data written elsewhere, and nothing here reaches a shell: the value is split on whitespace and
# run as arguments. A value carrying a shell metacharacter is refused by name rather than run with
# that character passed through as a literal, because either reading surprises whoever wrote it.
pc_check_is_unsafe() {
  case "$1" in
    *[\;\|\&\$\`\<\>\(\)\{\}\*\?\[\]\~\!\\\"\']*) return 0 ;;
  esac
  return 1
}

# Runs one check as arguments from inside $2, and prints only its exit status. Globbing is off for
# the split, so a `*` that survived the refusal above could not expand against the working
# directory anyway. Standard input is empty. The caller reads the framework names from a pipe.
# A command that reads its input would swallow the frameworks still to come (live-run row 137).
pc_run_check() {
  local value="$1" dir="$2" outfile="$3"
  (
    cd "$dir" || exit 127
    # zsh does not split an unquoted expansion on whitespace the way bash and every other
    # POSIX-family shell do (foundations.md, Honesty: this script runs under both). Scoped to
    # this subshell only, so it never changes how the rest of the script's own expansions behave.
    if [ -n "${ZSH_VERSION:-}" ]; then
      setopt SH_WORD_SPLIT 2>/dev/null
    fi
    set -f
    # shellcheck disable=SC2086
    set -- $value
    set +f
    # An `exec` with no operands returns 0 without replacing the shell, so a check whose command
    # came out empty would read as a condition that passed. Exit 126 instead.
    [ "$#" -gt 0 ] || exit 126
    exec "$@"
  ) >"$outfile" 2>/dev/null </dev/null
  printf '%s' "$?"
}

# The entry being read, held between lines. Bash 3.2 has no nameref, so the parse loop and its
# flush share these rather than passing a record around.
PC_ID=""; PC_WHAT=""; PC_CHECK=""; PC_OWNER=""; PC_EXPECT=""; PC_ANY=0

# Runs the held entry's check and appends one JSON object to $1. Clears the entry afterwards, so a
# second call with nothing held writes nothing.
pc_flush_entry() {
  local out="$1" codepath="$2"
  local verdict reason rc exitjson first
  [ -n "$PC_ID" ] || return 0
  PC_ANY=1
  verdict=""; reason=""; exitjson="null"; first=""
  if [ -z "$PC_WHAT" ]; then
    verdict="unknown"; reason="entry-unparseable"
  elif [ -z "$PC_CHECK" ]; then
    verdict="unknown"; reason="no-check-declared"
  elif pc_check_is_unsafe "$PC_CHECK"; then
    verdict="unknown"; reason="unsafe-check-shape"
  else
    rc="$(pc_run_check "$PC_CHECK" "$codepath" "$out.stdout")"
    exitjson="$rc"
    case "$rc" in
      0)   verdict="met" ;;
      127) verdict="unknown"; reason="check-command-not-found" ;;
      *)   verdict="unmet" ;;
    esac
    # The exit status is read first and keeps every meaning it has. Only on a zero exit does an
    # expected string decide, and it decides one way: the string is in what the command wrote, or
    # the condition answered no. A substring test and nothing more, for the same reason the command
    # never reaches a shell. An unmet carrying exit code 0 and an expected string is this test
    # deciding, which is why it needs no reason of its own.
    if [ "$verdict" = "met" ] && [ -n "$PC_EXPECT" ]; then
      if ! pc_output_holds "$out.stdout" "$PC_EXPECT"; then
        verdict="unmet"
      fi
    fi
    [ "$verdict" = "met" ] || first="$(grep -m1 '[^[:space:]]' "$out.stdout" 2>/dev/null)"
    rm -f "$out.stdout"
  fi
  jq -n --arg id "$PC_ID" --arg what "$PC_WHAT" --arg owner "$PC_OWNER" --arg check "$PC_CHECK" \
        --arg expect "$PC_EXPECT" --arg first "$first" \
        --arg verdict "$verdict" --arg reason "$reason" --argjson exitCode "$exitjson" '
    {id: $id, what: (if $what == "" then $id else $what end), verdict: $verdict}
    + (if $check    == ""   then {} else {check: ([$check | splits("[ \t]+")] | map(select(length > 0)))} end)
    + (if $expect   == ""   then {} else {expect: $expect} end)
    + (if $owner    == ""   then {} else {owner: $owner} end)
    + (if $reason   == ""   then {} else {reason: $reason} end)
    + (if $exitCode == null then {} else {exitCode: $exitCode} end)
    + (if $first    == ""   then {} else {firstLine: $first} end)
  ' >>"$out" || die 3 "preconditions: could not record the entry $PC_ID"
  PC_ID=""; PC_WHAT=""; PC_CHECK=""; PC_OWNER=""; PC_EXPECT=""
}

# Reads the `## Preconditions` section of the recipe at $1, runs each check from inside $3, and
# appends one JSON object per entry to $2. Prints the section's own state: `undeclared` when the
# heading is absent, `unparseable` when the heading is there with nothing readable under it, or
# `ok`.
pc_parse_recipe() {
  local recipe_file="$1" out="$2" codepath="$3"
  local section_file block_file line trimmed

  section_file="$out.section"
  sed -n '/^##[[:space:]]*Preconditions[[:space:]]*$/,/^##[[:space:]]/p' "$recipe_file" >"$section_file" 2>/dev/null
  if [ ! -s "$section_file" ]; then
    rm -f "$section_file"
    printf 'undeclared'
    return 0
  fi

  # The key's presence and the entries under it are two facts. A recipe that wrote the key and put
  # nothing in it has declared there are none. A recipe with no key at all may have misspelled it,
  # and nobody can tell that from a recipe that meant to declare nothing, so it is unknown. That
  # difference is the only thing standing between a misspelled `check:` and a run that reads clean
  # while checking less than its author wrote.
  if ! grep -q '^preconditions:' "$section_file"; then
    rm -f "$section_file"
    printf 'unparseable'
    return 0
  fi

  block_file="$out.block"
  sed -n '/^preconditions:/,$p' "$section_file" | sed '1d' >"$block_file"
  rm -f "$section_file"

  PC_ID=""; PC_WHAT=""; PC_CHECK=""; PC_OWNER=""; PC_EXPECT=""; PC_ANY=0
  while IFS= read -r line; do
    case "$line" in
      '##'*) break ;;
    esac
    trimmed="$(pc_trim "$line")"
    [ -n "$trimmed" ] || continue
    case "$trimmed" in
      '- id:'*)   pc_flush_entry "$out" "$codepath"; PC_ID="$(pc_trim "${trimmed#- id:}")" ;;
      'what:'*)   PC_WHAT="$(pc_trim "${trimmed#what:}")" ;;
      'check:'*)  PC_CHECK="$(pc_trim "${trimmed#check:}")" ;;
      'owner:'*)  PC_OWNER="$(pc_trim "${trimmed#owner:}")" ;;
      'expect:'*) PC_EXPECT="$(pc_unquote "$(pc_trim "${trimmed#expect:}")")" ;;
    esac
  done <"$block_file"
  pc_flush_entry "$out" "$codepath"
  rm -f "$block_file"

  if [ "$PC_ANY" = "1" ]; then printf 'ok'; else printf 'declared-empty'; fi
}

# Who owns a condition that answered no while the task's worktree has no running site (gap row
# 246). The recipe's owner then sends a person to the wrong fix. The task record decides, never
# the check's words. A marker with no address means a bring-up did not finish. An address whose
# `## Status` line exits non-zero means the site is down. No `environment` says nothing: a project
# with no environment recipe has none, and `environment down` removes it. Prints the step and the
# reason, or nothing: no worktree, no record, a person said no site, the site is up, or the recipe
# has no `## Status` line to ask. Reads TASK_PATH.
pc_environment_owner() {
  local task_json="$TASK_PATH/task.json" id wt recipe rc
  wt="$(jq -r '.worktree.path // empty' "$task_json" 2>/dev/null)"
  [ -n "$wt" ] && [ -d "$wt" ] || return 0
  id="$(jq -r '.id' "$task_json")"
  case "$(jq -r '.environment as $e
      | if ($e | type) != "object" then "absent"
        elif ($e["not-applicable"] // "") != "" then "not-applicable"
        elif ($e.address // "") != "" then "up"
        elif $e.state == "coming-up" then "coming-up"
        else "other" end' "$task_json")" in
    coming-up) printf 'task environment %s down, then up: the bring-up of this worktree did not finish' "$id" ;;
    up)
      recipe="$(jq -r '.environment.recipe // empty' "$task_json")"
      [ -f "$recipe" ] || return 0
      BRC_WHO="preconditions" br_site_status "$recipe" "$wt"; rc=$?
      [ "$rc" -ne 1 ] \
        || printf 'task environment %s up: the ## Status line of %s says the site is down' "$id" "$recipe" ;;
  esac
}

# The worse of two verdicts, best to worst: met, undeclared, unknown, unmet. A recipe that declared
# nothing is a smaller hole than a check that could not answer, and a check that answered no is the
# only one of the four that names something a person can fix.
pc_rank() {
  case "$1" in
    met) printf '0' ;; undeclared) printf '1' ;; unknown) printf '2' ;; *) printf '3' ;;
  esac
}
pc_worse() {
  if [ "$(pc_rank "$1")" -ge "$(pc_rank "$2")" ]; then printf '%s' "$1"; else printf '%s' "$2"; fi
}

# ------------------------------------------------------------------------------------------------
# `## Test commands`: read alongside the conditions, from the same recipe, resolving nothing.
#
# The two block parsers, the resolver, the command runner, the clean-tree refusal and the code-path
# loader now live in scripts/lib/recipes.sh, sourced at the top of this file, because the review
# stage reads the same blocks over the whole task. What stays here is the smoke runner below, which
# belongs to this stage's own preconditions step.
# ------------------------------------------------------------------------------------------------


# Runs the smoke row's own argv, a JSON array of tokens, as arguments from inside $2, after
# replacing every token that is exactly one placeholder with the value $4 supplies for it under
# that name. This is a second runner rather than a reuse of pc_run_check: that helper discards
# standard error, because a condition's own check is judged on its exit status and, on the rare
# entry carrying `expect`, a substring test against standard output alone; a smoke run needs
# whatever the command wrote on either stream, so the two are captured together here instead. It
# still runs the command the same way pc_run_check does otherwise: as arguments, never through a
# shell, from inside the code repository, with nothing here reaching a shell to be unsafe in.
# Prints one of two tab-separated results on stdout, never dies: `UNRESOLVED<TAB><name>` when a
# token still held a placeholder $4 supplied no value for, naming it; or `RAN<TAB><exit status>`
# once the command actually ran, whatever it exited with. $3 receives standard output and standard
# error together, exactly as the command wrote them, for the caller to trim and record. Standard
# input is empty, for the reason pc_run_check gives.
tc_run_smoke() {
  local argv_json="$1" dir="$2" outfile="$3" values="$4"
  local count i tok name
  set --
  count="$(printf '%s' "$argv_json" | jq 'length' 2>/dev/null)"
  case "$count" in ''|*[!0-9]*) count=0 ;; esac
  i=0
  while [ "$i" -lt "$count" ]; do
    tok="$(printf '%s' "$argv_json" | jq -r --argjson i "$i" '.[$i]' 2>/dev/null)"
    case "$tok" in
      '{'*'}')
        name="${tok#\{}"; name="${name%\}}"
        tok="$(cr_lookup "$values" "$name")"
        if [ -z "$tok" ]; then
          printf 'UNRESOLVED\t%s' "$name"
          return 0
        fi
        ;;
    esac
    set -- "$@" "$tok"
    i=$((i + 1))
  done
  [ "$#" -gt 0 ] || { printf 'EMPTY\t'; return 0; }
  (
    cd "$dir" || exit 127
    exec "$@"
  ) >"$outfile" 2>&1 </dev/null
  printf 'RAN\t%s' "$?"
}

# ------------------------------------------------------------------------------------------------
# The baseline: what was already broken at the commit the build starts from. Taken once, at the
# end of `preconditions`, only when that run's own verdict permits the build to continue.
# ------------------------------------------------------------------------------------------------

# The folder beside baseline.json that keeps what each baseline command printed, whole, one file
# per run. baseline.json names each file in `outputFile`, relative to its own folder.
BL_OUTPUT_DIR="baseline-output"

# The ledger and the snapshot of a task whose build has started, from $IMPL_DIR. Sets
# STARTED_LEDGER_FILE, STARTED_LEDGER_DOC and SNAPSHOT_DOC. $1 the action, for the message.
#
# Four facts, and they must not read alike: neither file present is a build that never started
# (exit 20, "run start first"); one present without the other is a state this script own logic
# rules out; and either file present but unparseable is a third. `preconditions`, every step-five
# action and `finish` all ask this one question, and asking it in three places is how one of them
# ends up sending a reader to the wrong repair, which is the defect this replaced.
STARTED_LEDGER_FILE=""; STARTED_LEDGER_DOC=""
require_started_build() {
  local who="$1" snapshot_file
  STARTED_LEDGER_FILE="$IMPL_DIR/ledger.json"
  snapshot_file="$IMPL_DIR/snapshot.json"
  if [ ! -f "$STARTED_LEDGER_FILE" ]; then
    [ -f "$snapshot_file" ] \
      && die 3 "$who: $STARTED_LEDGER_FILE not found, though $snapshot_file exists. A snapshot with no ledger beside it is not a supported state; run start again."
    die 20 "$who: this task's build has never started. There is no $STARTED_LEDGER_FILE and no $snapshot_file. Run start on this task first."
  fi
  STARTED_LEDGER_DOC="$(jq -c '.' "$STARTED_LEDGER_FILE" 2>/dev/null)"
  [ -n "$STARTED_LEDGER_DOC" ] \
    || die 3 "$who: $STARTED_LEDGER_FILE exists but could not be read as JSON. Repair or remove it by hand before running this again."
  [ -f "$snapshot_file" ] \
    || die 3 "$who: $snapshot_file not found, though $STARTED_LEDGER_FILE exists. A ledger with no snapshot beside it is not a supported state; run start again."
  SNAPSHOT_DOC="$(jq -c '.' "$snapshot_file" 2>/dev/null)"
  [ -n "$SNAPSHOT_DOC" ] \
    || die 3 "$who: $snapshot_file exists but could not be read as JSON, though start already wrote it. Repair or remove it by hand before running this again."
}

# Prints one of: missing, unreadable, ok, for <task_folder>/implementation/baseline.json
# ($BASELINE_FILE). Never dies. "unreadable" covers not valid JSON, not an object, and a commit
# field that is absent, null, or the wrong shape: the same one-word-per-fact split
# design_closed_state uses for a close record.
bl_state() {
  [ -f "$BASELINE_FILE" ] || { printf 'missing'; return; }
  [ -r "$BASELINE_FILE" ] || { printf 'unreadable'; return; }
  jq empty "$BASELINE_FILE" 2>/dev/null || { printf 'unreadable'; return; }
  local shape
  shape="$(jq -r '
      if type != "object" then "no"
      elif (has("commit") | not) then "no"
      elif ((.commit | type) != "string") then "no"
      elif (.commit | test("^[0-9a-f]{7,40}$") | not) then "no"
      else "yes"
      end
    ' "$BASELINE_FILE" 2>/dev/null)"
  if [ "$shape" = "yes" ]; then printf 'ok'; else printf 'unreadable'; fi
}

# The commit recorded in baseline.json. Call only after bl_state prints "ok".
bl_commit_of() {
  jq -r '.commit' "$BASELINE_FILE" 2>/dev/null
}

# Runs the `suite` test-command row for every framework in the preconditions record $1 (the same
# object this run already assembled, before it is written), the whole suite and unscoped, and
# appends one JSON object per framework to $4. Reuses tc_run_smoke rather than a third runner: the
# same placeholder substitution from $3's --value flags, the same "as arguments, never through a
# shell, from inside $2" discipline, and the same UNRESOLVED/RAN split. The one difference from the
# smoke row is what gets recorded: the suite's own exit code and output are kept whenever the
# command actually ran, met or not, because a baseline is a record of the whole state and not only
# of what pointed at a defect.
bl_run_suite() {
  local record_json="$1" codepath="$2" values="$3" out="$4"
  local count i fw_obj fw tc_state row_json argv_json
  local out_file output_file kept_file result kind payload verdict reason exit_code_json output truncated raw_len
  count="$(printf '%s' "$record_json" | jq '.frameworks | length' 2>/dev/null)"
  case "$count" in ''|*[!0-9]*) count=0 ;; esac
  i=0
  while [ "$i" -lt "$count" ]; do
    fw_obj="$(printf '%s' "$record_json" | jq -c --argjson i "$i" '.frameworks[$i]' 2>/dev/null)"
    fw="$(printf '%s' "$fw_obj" | jq -r '.framework')"
    tc_state="$(printf '%s' "$fw_obj" | jq -r '.testCommands.state')"
    verdict=""; reason=""; exit_code_json="null"; output=""; truncated=false; kept_file=""
    if [ "$tc_state" != "ok" ]; then
      verdict="unknown"
      reason="this framework's own test-commands section could not be read (state: $tc_state), so there is no suite row to run"
    else
      # The same reader every other caller of a test-command row uses: a row absent, a row whose
      # argv did not parse, a row with no argv and a row that is simply not there each have their
      # own answer, and one copy of that chain is what keeps the four worded alike.
      row_json="$(cr_row_command "$(printf '%s' "$fw_obj" | jq -c '.testCommands.rows')" "suite" "suite")"
      if [ "$(printf '%s' "$row_json" | jq -r 'has("argv")')" != "true" ]; then
        verdict="unknown"
        reason="$(printf '%s' "$row_json" | jq -r '.absent // .missing')"
      else
        argv_json="$(printf '%s' "$row_json" | jq -c '.argv')"
        # The whole capture is kept beside the record, because build-record subtracts it line by
        # line later and the 4000-character tail in `output` is not enough to subtract from.
        output_file="$BL_OUTPUT_DIR/suite-$fw.txt"
        out_file="$(dirname -- "$out")/$output_file"
        mkdir -p "$(dirname -- "$out_file")" || die 3 "preconditions: could not create $(dirname -- "$out_file")"
        result="$(tc_run_smoke "$argv_json" "$codepath" "$out_file" "$values")"
        kind="$(printf '%s' "$result" | cut -f1)"
        payload="$(printf '%s' "$result" | cut -f2-)"
        if [ "$kind" = "UNRESOLVED" ]; then
          verdict="unknown"
          reason="the token {$payload} in the suite command has no supplied value; pass --value $payload=<value>"
        elif [ "$kind" = "EMPTY" ]; then
          verdict="unknown"
          reason="the suite row's argv holds no token at all, so there was nothing to run"
        else
          exit_code_json="$payload"
          kept_file="$output_file"
          case "$payload" in
            0)   verdict="met" ;;
            127) verdict="unknown"; reason="the suite command could not be found (exit 127)" ;;
            *)   verdict="unmet" ;;
          esac
          if [ -f "$out_file" ]; then
            raw_len="$(wc -c <"$out_file" 2>/dev/null | tr -d '[:space:]')"
            case "$raw_len" in ''|*[!0-9]*) raw_len=0 ;; esac
            if [ "$raw_len" -gt 4000 ]; then
              output="$(tail -c 4000 "$out_file" 2>/dev/null)"
              truncated=true
            else
              output="$(cat "$out_file" 2>/dev/null)"
            fi
          fi
        fi
        [ -n "$kept_file" ] || rm -f "$out_file"
      fi
    fi
    jq -n --arg framework "$fw" --arg verdict "$verdict" --arg reason "$reason" \
          --arg output "$output" --argjson truncated "$truncated" --argjson exitCode "$exit_code_json" \
          --arg outputFile "$kept_file" '
      {framework: $framework, verdict: $verdict}
      + (if $reason   == ""   then {} else {reason: $reason} end)
      + (if $exitCode == null then {} else {exitCode: $exitCode} end)
      + (if $output   == ""   then {} else {output: $output} end)
      + (if $truncated == true then {truncated: true} else {} end)
      + (if $outputFile == "" then {} else {outputFile: $outputFile} end)
    ' >>"$out" || die 3 "preconditions: could not record the baseline suite result for framework $fw"
    i=$((i + 1))
  done
}

# Keeps the entries of $1, a JSON array of owned paths, that lie in the code repository at $2:
# every relative path, and every absolute one under it. An order may own a record in the task
# folder, an absolute path outside the repository, and a tool run in the repository fails on a
# file it cannot see, which spent two attempts on the nyc task (nyc defect 11). Then drops every
# path that does not exist in the tree at $2. An order whose operation deletes a file owns it
# (design's sizing rule), and phpcs and phpstan refuse a missing path, so every configuration
# order that deleted a file failed the tool rows by construction (live-run row 85). Sets
# BR_INSIDE_JSON to what is kept, BR_OUTSIDE_COUNT to how many lay outside and BR_DELETED_COUNT
# to how many were absent. Both the build's tool rows and the baseline's read it, so the two
# answer over the same files; at the baseline's commit a file the order later deletes still
# exists, so the second filter only matters there for a file already absent.
BR_INSIDE_JSON="[]"; BR_OUTSIDE_COUNT=0; BR_DELETED_COUNT=0
# The first filter alone: prints the entries of $1 that lie in the code repository at $2.
br_inside_repository() {
  jq -cn --argjson paths "$1" --arg cp "$2/" '[ $paths[] | select((startswith("/") | not) or startswith($cp)) ]'
}
br_scope_to_repository() {
  local inside_json inside_count pi entry full
  inside_json="$(br_inside_repository "$1" "$2")"
  BR_OUTSIDE_COUNT="$(jq -n --argjson paths "$1" --arg cp "$2/" \
    '[ $paths[] | select(startswith("/") and (startswith($cp) | not)) ] | length')"
  BR_INSIDE_JSON="[]"; BR_DELETED_COUNT=0
  inside_count="$(printf '%s' "$inside_json" | jq 'length')"
  pi=0
  while [ "$pi" -lt "$inside_count" ]; do
    entry="$(printf '%s' "$inside_json" | jq -r --argjson i "$pi" '.[$i]')"
    case "$entry" in /*) full="$entry" ;; *) full="$2/$entry" ;; esac
    if [ -e "$full" ]; then
      BR_INSIDE_JSON="$(printf '%s' "$BR_INSIDE_JSON" | jq -c --arg e "$entry" '. + [$e]')"
    else
      BR_DELETED_COUNT=$((BR_DELETED_COUNT + 1))
    fi
    pi=$((pi + 1))
  done
}

# One sentence for a tool row's detail when br_scope_to_repository dropped something, or nothing.
br_outside_note() {
  case "$BR_OUTSIDE_COUNT" in
    0) printf '' ;;
    1) printf ' 1 owned file lies outside the code repository and was left out.' ;;
    *) printf ' %s owned files lie outside the code repository and were left out.' "$BR_OUTSIDE_COUNT" ;;
  esac
}

# The same, for the owned files that no longer exist in the tree the tool would run in.
br_deleted_note() {
  case "$BR_DELETED_COUNT" in
    0) printf '' ;;
    1) printf ' 1 owned file deleted by this order was not passed.' ;;
    *) printf ' %s owned files deleted by this order were not passed.' "$BR_DELETED_COUNT" ;;
  esac
}

# Runs one baseline tool command over the baseline scope and prints the field object baseline.json
# holds for it. $1 the check id, $2 a word for the message, $3 the code repository, $4 the scope as
# a JSON array of paths, $5 the folder baseline.json lives in. The command, its signal and its
# extensions come from the resolved recipe in CR_DOC, never from a flag a caller typed.
#
# The baseline has nothing earlier to compare itself against, so the rule is the suite own: met on
# exit 0, unknown when the command could not be run at all with a reason saying so, unmet on any
# other exit it actually returned. A row the recipe declares absent stays undeclared and carries
# the recipe own reason. The exit code and the output are kept met or not, because a baseline is a
# record of the whole state and not only of what pointed at a defect. The whole capture stays on
# disk at $5/$BL_OUTPUT_DIR/<check id>.txt whenever the command ran, named in `outputFile`, because
# build-record subtracts it line by line and the 4000-character tail is not enough to subtract from.
bl_tool_result() {
  local check_id="$1" label="$2" codepath="$3" paths_json="$4" outfile="$5/$BL_OUTPUT_DIR/$1.txt"
  local row argv_json signal exts_json absent_declared missing_why
  local verdict reason exit_json output truncated rc raw_len kept_file
  local has_paths scoped_json scoped_count errfile stdout_len result kind payload
  verdict=""; reason=""; exit_json="null"; output=""; truncated=false; kept_file=""

  row="$(printf '%s' "$CR_DOC" | jq -c --arg id "$check_id" '[ (.tools // [])[] | select(.id == $id) ][0] // null')"
  absent_declared=""; missing_why=""
  if [ "$row" = "null" ]; then
    missing_why="no check recipe was resolved for this task, so $label was not checked"
  else
    absent_declared="$(printf '%s' "$row" | jq -r 'if (.absent // false) then (.absentReason // "the recipe declares this row absent") else "" end')"
    missing_why="$(printf '%s' "$row" | jq -r '.missing // ""')"
  fi
  if [ -n "$absent_declared" ]; then
    jq -n --arg reason "$absent_declared" '{verdict: "undeclared", reason: $reason, absent: true}'
    return 0
  fi
  if [ -n "$missing_why" ]; then
    jq -n --arg reason "$missing_why" '{verdict: "undeclared", reason: $reason}'
    return 0
  fi

  argv_json="$(printf '%s' "$row" | jq -c '.argv // []')"
  signal="$(printf '%s' "$row" | jq -r '.signal // ""')"
  exts_json="$(printf '%s' "$row" | jq -c 'if has("extensions") then .extensions else empty end')"

  has_paths=false
  br_argv_takes_paths "$argv_json" && has_paths=true
  scoped_json="$paths_json"
  if [ -n "$exts_json" ]; then
    scoped_json="$(br_filter_extensions "$paths_json" "$exts_json")"
  fi
  br_scope_to_repository "$scoped_json" "$codepath"
  scoped_json="$BR_INSIDE_JSON"
  scoped_count="$(printf '%s' "$scoped_json" | jq 'length')"

  if [ "$has_paths" = "true" ] && [ "$(printf '%s' "$paths_json" | jq 'length')" -eq 0 ]; then
    # A tool handed no path at all reads that as its own default scope, so it would answer about the
    # whole repository while this record claims it answered about the scope. That is a wrong verdict,
    # not a missing one.
    verdict="unknown"
    reason="the $label command holds a path placeholder, and no work order declares an owned file, so the command would run over no path at all"
  elif [ "$has_paths" = "true" ] && [ "$scoped_count" -eq 0 ]; then
    verdict="undeclared"
    if [ "$BR_OUTSIDE_COUNT" -gt 0 ]; then
      reason="the $label command would read no file of the scope inside the code repository ($BR_OUTSIDE_COUNT owned outside it), so the row does not apply"
    elif [ "$BR_DELETED_COUNT" -gt 0 ]; then
      reason="the $label command would read no file of the scope present at the baseline commit ($BR_DELETED_COUNT owned but absent from it), so the row does not apply"
    else
      reason="the $label command reads only $(printf '%s' "$exts_json" | jq -r 'join(", ")'), and the scope holds no file with one of those extensions, so the row does not apply"
    fi
  else
    stdout_len=0
    errfile=""
    mkdir -p "$(dirname -- "$outfile")" || die 3 "preconditions: could not create $(dirname -- "$outfile")"
    if [ -n "$signal" ]; then
      errfile="$outfile.err"
      result="$(br_run_resolved "$argv_json" "$codepath" "$outfile" "$scoped_json" "$PC_VALUES" "$errfile")"
    else
      result="$(br_run_resolved "$argv_json" "$codepath" "$outfile" "$scoped_json" "$PC_VALUES")"
    fi
    kind="$(printf '%s' "$result" | cut -f1)"
    payload="$(printf '%s' "$result" | cut -f2-)"
    if [ "$kind" = "UNRESOLVED" ]; then
      verdict="unknown"
      reason="the token {$payload} in the $label command has no supplied value; pass --value $payload=<value>"
    elif [ "$kind" = "EMPTY" ]; then
      verdict="unknown"
      reason="the $label command came out with no token at all, so nothing ran and nothing was decided"
    else
      rc="$payload"
      kept_file="$BL_OUTPUT_DIR/$check_id.txt"
      if [ -n "$signal" ]; then
        stdout_len="$(wc -c <"$outfile" 2>/dev/null | tr -d '[:space:]')"
        case "$stdout_len" in ''|*[!0-9]*) stdout_len=0 ;; esac
        cat "$errfile" >>"$outfile" 2>/dev/null
      fi
      [ -z "$errfile" ] || rm -f "$errfile"
      exit_json="$rc"
      if [ "$rc" = "0" ] && [ -n "$signal" ] && [ "$stdout_len" -gt 0 ]; then
        verdict="unmet"
        reason="the $label command exited 0 and printed on standard output, and its row declares signal empty-stdout"
      else
        case "$rc" in
          0)   verdict="met" ;;
          126) verdict="unknown"; reason="the $label command list came out empty, so nothing ran" ;;
          127) verdict="unknown"; reason="the $label command could not be found (exit 127)" ;;
          *)   verdict="unmet" ;;
        esac
      fi
      if [ -f "$outfile" ]; then
        raw_len="$(wc -c <"$outfile" 2>/dev/null | tr -d '[:space:]')"
        case "$raw_len" in ''|*[!0-9]*) raw_len=0 ;; esac
        if [ "$raw_len" -gt 4000 ]; then
          output="$(tail -c 4000 "$outfile" 2>/dev/null)"
          truncated=true
        else
          output="$(cat "$outfile" 2>/dev/null)"
        fi
      fi
    fi
    [ -n "$kept_file" ] || rm -f "$outfile"
  fi
  jq -n --arg verdict "$verdict" --arg reason "$reason" --arg output "$output" \
        --argjson truncated "$truncated" --argjson exitCode "$exit_json" \
        --arg signal "$signal" --arg exts "${exts_json:-}" --arg outputFile "$kept_file" '
    {verdict: $verdict}
    + (if $reason   == ""   then {} else {reason: $reason} end)
    + (if $exitCode == null then {} else {exitCode: $exitCode} end)
    + (if $output   == ""   then {} else {output: $output} end)
    + (if $truncated == true then {truncated: true} else {} end)
    + (if $outputFile == "" then {} else {outputFile: $outputFile} end)
    + (if $signal == "" then {} else {signal: $signal} end)
    + (if $exts   == "" then {} else {extensions: ($exts | fromjson)} end)
  '
}

# Prints {entries, end} for the tools recipe $1 names under requires_tooling, checked by the tool
# skill's own require from the worktree. Without it a missing tool is first met after an order was
# paid for (gap rows 271 and 285). An absent tool reads as a condition whose check command was not
# found. One that only end-of-task rows of $2, the test-command rows, run by name in their argv is
# recorded under `end` instead, and the build goes on: review reads those rows as known. No recipe
# field says which rows a tool serves yet. $3 says what runs the tool, for `what`. $4 is a newline
# list of tool names, and require checks only those; empty checks every name. $5 `tooling` names
# the tool's tooling recipe as the place its setup lives, in place of $1. Reads codepath, tooling
# and task_folder from do_preconditions.
pc_tooling_check() {
  local recipe="$1" rows="$2" runs="$3" only="$4" setup="${5:-}" said given
  if said="$(cd "$codepath" || exit 3
      set --
      while IFS= read -r pair; do [ -z "$pair" ] || set -- "$@" --tooling "$pair"; done <<PC_TOOLING
$tooling
PC_TOOLING
      set -- "$@" require --advisory --task "$task_folder"
      while IFS= read -r name; do [ -z "$name" ] || set -- "$@" --only "$name"; done <<PC_ONLY
$only
PC_ONLY
      "$PLUGIN_ROOT/skills/tool/scripts/tool-actions.sh" "$@" "$recipe" 2>&1 </dev/null)"; then
    given="$(printf '%s' "$tooling" | jq -Rsc 'split("\n") | map(select(contains("=")) | {key: sub("=.*"; ""), value: sub("^[^=]*="; "")}) | from_entries')"
    printf '%s\n' "$said" | jq -Rsc --arg recipe "$recipe" --arg runs "$runs" --argjson rows "$rows" \
      --arg setup "$setup" --argjson given "$given" '
      [ split("\n")[] | capture("^TOOLING: (?<tool>[^ ]+) (?<state>present|absent|unknown)(: (?<said>.*))?$") ]
      | map(. as $t
        | [ $rows[] | select((.argv // []) | any(contains($t.tool))) ] as $used
        | (if ($t.said // "") == "" then {} else {firstLine: $t.said} end) as $first
        | if $t.state == "absent" and ($used | length) > 0 and all($used[]; .cost == "end-of-task")
          then {end: ({tool: $t.tool, rows: [ $used[].id ]} + $first)}
          else {entry: ({id: ("requires_tooling: " + $t.tool),
              what: ("the tool " + $t.tool + ", which " + $runs),
              verdict: (if $t.state == "present" then "met" else "unknown" end)}
            + (if $t.state == "absent" then {reason: "check-command-not-found",
                 owner: ("the tool skill: install " + $t.tool + ". "
                   + if $setup != "tooling" then "The recipe documents its setup: " + $recipe
                     elif $given[$t.tool] then "Its tooling recipe says how: " + $given[$t.tool]
                     else "Its tooling recipe says how, and the tool skill'"'"'s show " + $t.tool + " names it" end)} else {} end)
            + (if $t.state == "present" then {} else $first end))} end)
      | {entries: [ .[].entry // empty ], end: [ .[].end // empty ]}'
  else
    jq -nc --arg said "$(printf '%s\n' "$said" | grep -m1 '[^[:space:]]')" --arg runs "$runs" '
      {entries: [ {id: "requires_tooling", what: ("the tools " + $runs),
                   verdict: "unknown"} + (if $said == "" then {} else {firstLine: $said} end) ], end: []}'
  fi
}

# Prints {tools, unchecked} for framework $1 and its review recipe $2 (gap row 285). The rows are
# cr_resolve's own, the ones build-record runs. A row reading files applies only when an order owns
# a file of a type it reads inside the code repository, whether or not that file exists yet.
# `tools` holds each name the recipe lists under requires_tooling that an applying row's argv
# holds. `unchecked` holds each applying row whose argv holds none of them, with that argv: no
# tool name is guessed from a command. Returns 2 on a list the reader cannot see.
pc_build_tools() {
  local names="" listed name scope rows row row_argv exts scoped applying='[]'
  listed="$(recipe_requires_tooling_of "$2")" || return 2
  while IFS= read -r name; do
    [ -z "$name" ] || names="$names$(pc_unquote "$name")
"
  done <<PC_NAMES
$listed
PC_NAMES
  scope="$(br_inside_repository "$(printf '%s' "$SNAPSHOT_DOC" | jq -c '[ (.workOrders // [])[] | (.ownedFiles // [])[] ] | unique')" "$codepath")"
  rows="$(printf '%s' "$CR_DOC" | jq -c --arg fw "$1" '(.tools // [])[] | select(.framework == $fw and (.argv | type) == "array")')"
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    row_argv="$(printf '%s' "$row" | jq -c '.argv')"
    if br_argv_takes_paths "$row_argv"; then
      exts="$(printf '%s' "$row" | jq -c '.extensions // empty')"
      scoped="$scope"; [ -z "$exts" ] || scoped="$(br_filter_extensions "$scope" "$exts")"
      [ "$scoped" != "[]" ] || continue
    fi
    applying="$(jq -nc --argjson have "$applying" --argjson row "$row" '$have + [$row]')"
  done <<PC_ROWS
$rows
PC_ROWS
  jq -nc --argjson rows "$applying" --arg names "$names" '
    ($names | split("\n") | map(select(length > 0))) as $n
    | def holds($t): any(.argv[]; contains($t));
    {tools: [ $n[] as $t | select(any($rows[]; holds($t))) | $t ],
     unchecked: [ $rows[] | select(any($n[] as $t | holds($t); .) | not) | {row: .id, argv} ]}'
}

# The step. Every framework the project declares must be answered for, because the build runs in
# one repository that is all of them at once.
do_preconditions() {
  local task_folder="" project_folder codepath resolve_rc
  local recipes="" failures="" values="" check_recipes="" fw
  local implement_lookups="" im_answer im_lookup im_path im_resolved im_blocked im_freeze
  local im_notgiven im_by_tests im_unlooked im_advice check_failures="" rv_lookup rv_unresolved
  local cs_json sa_json sec_json
  local frameworks fw_count entries_file fw_json_file tc_rows_file
  local lookup recipe_path section_state fw_verdict entries_json run_verdict
  local tc_state tc_rows_json
  local smoke_verdict smoke_reason smoke_output smoke_truncated smoke_exit_code_json
  local smoke_row_json smoke_argv_json smoke_out_file smoke_result smoke_kind smoke_payload
  local smoke_raw_len smoke_json smoke_first tokens_json token_failures tokens_out token_first token_entry
  local record_file record_json today
  local baseline_status baseline_note baseline_commit_report baseline_summary_json
  local ledger_doc ledger_started_from check_recipes_json order_tests_absent
  local snapshot_doc scope_json suite_json_file suite_json baseline_json existing_commit
  local harness_needed harness_reason env_asked=no env_owner="" tooling_entries
  local tooling="" tooling_json end_absent_json pc_no_recipe check_path build_tools build_rc build_json build_entries unchecked_json smoke_state catalog_recipes="" pc_stale="" pc_line pc_catalog

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --recipe)
        [ "$#" -ge 2 ] || die 3 "preconditions: --recipe needs <framework>=<path>"
        case "$2" in *=*) ;; *) die 3 "preconditions: --recipe takes <framework>=<path>, got: $2" ;; esac
        [ -n "${2%%=*}" ] || die 3 "preconditions: --recipe was given no framework name: $2"
        [ -n "${2#*=}" ] || die 3 "preconditions: --recipe was given no path: $2"
        recipes="$recipes$(printf '%s' "$2" | sed 's/=/\t/')
"
        shift 2 ;;
      --check-recipe)
        [ "$#" -ge 2 ] || die 3 "preconditions: --check-recipe needs <framework>=<path>"
        cr_recipe_pair "preconditions" "--check-recipe" "$2"
        check_recipes="$check_recipes$CR_PAIR
"
        shift 2 ;;
      --lookup-failed)
        [ "$#" -ge 2 ] || die 3 "preconditions: --lookup-failed needs <framework>=<reason>"
        cr_lookup_failure_pair "preconditions" "--lookup-failed" "$2"
        failures="$failures$CR_PAIR
"
        shift 2 ;;
      --check-lookup-failed)
        [ "$#" -ge 2 ] || die 3 "preconditions: --check-lookup-failed needs <framework>=<reason>"
        cr_lookup_failure_pair "preconditions" "--check-lookup-failed" "$2"
        check_failures="$check_failures$CR_PAIR
"
        shift 2 ;;
      --implement-lookup)
        [ "$#" -ge 2 ] || die 3 "preconditions: --implement-lookup needs <framework>=<path|no-recipe|listing-unreachable|fetch-failed>"
        case "$2" in *=*) ;; *) die 3 "preconditions: --implement-lookup takes <framework>=<path or reason>, got: $2" ;; esac
        [ -n "${2%%=*}" ] || die 3 "preconditions: --implement-lookup was given no framework name: $2"
        [ -n "${2#*=}" ] || die 3 "preconditions: --implement-lookup was given neither a path nor a reason: $2"
        implement_lookups="$implement_lookups$(printf '%s' "$2" | sed 's/=/\t/')
"
        shift 2 ;;
      --tooling)
        [ "$#" -ge 2 ] || die 3 "preconditions: --tooling needs <tool>=<path>"
        tooling="$tooling$2
"
        shift 2 ;;
      --catalog-recipe)
        [ "$#" -ge 2 ] || die 3 "preconditions: --catalog-recipe needs <framework>=<path>"
        cr_catalog_pair "preconditions" "$2"
        catalog_recipes="$catalog_recipes$CR_PAIR
"
        shift 2 ;;
      --value)
        [ "$#" -ge 2 ] || die 3 "preconditions: --value needs <name>=<value>"
        case "$2" in *=*) ;; *) die 3 "preconditions: --value takes <name>=<value>, got: $2" ;; esac
        pc_refuse_forged_value "preconditions" "$2"
        values="$values$(printf '%s' "$2" | sed 's/=/\t/')
"
        shift 2 ;;
      -*) die 3 "preconditions: unrecognized argument: $1" ;;
      *)
        [ -z "$task_folder" ] || die 3 "preconditions: more than one task folder given"
        task_folder="$1"; shift ;;
    esac
  done

  task_folder="$(resolve_task_folder "$task_folder" "preconditions")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  # Every other action calls the folder TASK_PATH, and the shared loaders read that name.
  TASK_PATH="$task_folder"

  # This step belongs to a run, so a run must have opened. Writing a record for a build that never
  # started would leave a file nothing can be read against. The same reader every step-five action
  # and `finish` use, so the four name the same four facts in the same words.
  IMPL_DIR="$task_folder/implementation"
  require_started_build "preconditions"

  rv_load_codepath "preconditions"
  project_folder="$RV_PROJECT_FOLDER"
  codepath="$RV_CODEPATH"

  frameworks="$(jq -r '.frameworks // [] | .[]' "$project_folder/project.json" 2>/dev/null)"
  [ -n "$frameworks" ] \
    || die 77 "preconditions: $project_folder/project.json is valid and records no frameworks, so no recipe can be chosen for this project. Exit 14 is the separate fact that the file is not valid JSON."

  # A task whose every order is proved by its record writes no test and runs none, so the test
  # harness is not needed. Its conditions and its smoke row are recorded `not-needed` and never
  # run, and the baseline runs no suite (live-run row 136). An order a person confirms runs no
  # test either: its task has no automated tests (gap row 196). On such a task a `gate` order runs
  # its own lines and no suite, so it needs no harness (gap row 246). BR_HARNESS_JQ holds the rule.
  # The recipe is still resolved and recorded, because the freeze and finish read its path.
  harness_needed="$(printf '%s' "$SNAPSHOT_DOC" | jq -r "$BR_HARNESS_JQ harnessNeeded")"
  harness_reason="no order in the snapshot is proved by a test. Every order's proof is record or confirm, or a configuration gate on a task with no automated tests, so no test is written or run"

  # Every commanded check the build runs later comes from a recipe, resolved once here so a
  # framework that can never answer is named now rather than at the first build-record. An order
  # whose own tests nothing runs never reaches checks-passed, so a framework declaring both rows
  # that run a named set of tests absent stops the run here, with the framework named.
  PC_VALUES="$values"
  CR_WHO="preconditions"
  CR_TEST_RECIPES="$recipes"
  CR_CHECK_RECIPES="$check_recipes"
  cr_resolve
  # A test-execution recipe's `## Tokens` blocks give the names its rows use for a fact no recipe
  # can know. The folder that holds the project's own code is one (live-run row 205). Each block
  # runs here in the worktree, through the runner the environment action uses. A --value for the
  # same name wins, because cr_lookup reads the first. The values this run used are recorded, and
  # every later step reads them there (br_recorded_token). A block that fails stops that recipe's
  # blocks, and a row that needs one of its tokens names it.
  tokens_json='{}'; token_failures=""
  if [ "$harness_needed" = "yes" ]; then
    tokens_out="$(mktemp)" || die 3 "preconditions: could not create a temporary file"
    while IFS="$(printf '\t')" read -r fw recipe_path; do
      [ -n "$fw" ] && [ -f "$recipe_path" ] || continue
      if ! recipe_tokens_run preconditions "$recipe_path" "$tokens_out" "$codepath" "" \
          "The tokens are the ## Tokens names before this one" >/dev/null; then
        token_first="$(sed -n "$((RT_BEFORE + 2))p" "$tokens_out")"
        token_failures="$token_failures$RT_FAILED	${token_first:-it printed nothing}
"
      fi
      values="$values$RT_TOKENS"
      while IFS= read -r token_entry; do
        [ -n "$token_entry" ] || continue
        tokens_json="$(printf '%s' "$tokens_json" | jq -c --arg n "${token_entry%%	*}" \
          --arg v "$(cr_lookup "$values" "${token_entry%%	*}")" '.[$n] //= $v')"
      done <<PC_TOKENS
$RT_TOKENS
PC_TOKENS
    done <<PC_RECIPES
$recipes
PC_RECIPES
    rm -f "$tokens_out"
    PC_VALUES="$values"
  fi
  # A gate order's `## Configuration gate` lines may hold a token, such as `{project}`. Each one
  # is resolved here and never run, because a gate line reaches the site (gap row 288). A token
  # that nothing fills refuses now, before a build spends an attempt on it.
  local pc_gate_missing=""
  printf '%s' "$SNAPSHOT_DOC" | jq -e "$BR_ORDER_FACTS_JQ"' any((.workOrders // [])[]; orderFacts.slot == "configuration-gate")' >/dev/null \
    && pc_gate_missing="$(br_gate_unfilled "$implement_lookups" "$PC_VALUES")"
  [ -z "$pc_gate_missing" ] \
    || die 3 "preconditions: a gate order runs the ## Configuration gate of ${pc_gate_missing#*	}, and its token {${pc_gate_missing%%	*}} has no value. Nothing was recorded. Pass --value ${pc_gate_missing%%	*}=<value>, or bring the environment up with task environment <task-id> up, which records it."
  order_tests_absent="$(printf '%s' "$CR_DOC" | jq -r '
    [ (.frameworks // [])[] | select(.testRecipe != "" and ((.orderTests | has("argv")) | not)) | .framework ]
    | join(", ")')"
  if [ -n "$order_tests_absent" ]; then
    printf 'implement-actions: preconditions: %s\n' "these frameworks declare no test-command row that runs a named set of tests, so no order on them can ever have its own tests run, and no order on them can ever pass its checks: $order_tests_absent" >&2
    exit 19
  fi
  check_recipes_json="$(printf '%s' "$CR_DOC" | jq -c '
    [ (.frameworks // [])[] | select(.checkRecipe != "")
      | {framework: .framework, path: .checkRecipe, sha256: .checkRecipeSha256} ]')"

  entries_file="$task_folder/implementation/.preconditions-entries.$$"
  tc_rows_file="$task_folder/implementation/.preconditions-testcommands.$$"
  fw_json_file="$task_folder/implementation/.preconditions-frameworks.$$"
  : >"$fw_json_file"
  run_verdict="met"

  # A framework the caller answered for neither way is a caller that did not look. Guessing here
  # would turn a lookup nobody ran into a recipe that declared nothing.
  printf '%s\n' "$frameworks" | while IFS= read -r fw; do
    [ -n "$fw" ] || continue
    recipe_path="$(cr_lookup "$recipes" "$fw")"
    lookup=""
    if [ -n "$recipe_path" ]; then
      lookup="resolved"
    else
      lookup="$(cr_lookup "$failures" "$fw")"
      [ -n "$lookup" ] || die 18 "preconditions: nothing was said about the recipe for framework $fw; pass --recipe or --lookup-failed"
    fi

    # The implement recipe is a second lookup, and this step is the first place a person can be
    # told about it. Its `## Oracle files` block holds the globs `tests-freeze` needs, so without
    # it a test-proved order dies at the freeze, after the design closed and the test author ran.
    # A path is a resolved recipe; the three reason words are the navigator's own answers; nothing
    # passed is `not-given`, which says the lookup was not run rather than that it found nothing.
    im_answer="$(cr_lookup "$implement_lookups" "$fw")"
    im_path=""
    case "${im_answer:-not-given}" in
      not-given|no-recipe|listing-unreachable|fetch-failed)
        im_lookup="${im_answer:-not-given}" ;;
      *)
        im_lookup="resolved"; im_path="$im_answer"
        [ -f "$im_path" ] || die 3 "preconditions: the implement recipe handed over for $fw is not a file: $im_path" ;;
    esac

    # The review recipe's answer, recorded the way implementLookup is (gap row 292). Without a
    # path, build-record runs no check command, and a light run that asks every point in one
    # dispatch can drop this answer unseen. `not-given` says nobody passed one.
    if [ -n "$(cr_lookup "$check_recipes" "$fw")" ]; then rv_lookup="resolved"
    else rv_lookup="$(cr_lookup "$check_failures" "$fw")"; rv_lookup="${rv_lookup:-not-given}"; fi

    : >"$entries_file"
    : >"$tc_rows_file"
    if [ "$lookup" = "resolved" ]; then
      [ -f "$recipe_path" ] || die 3 "preconditions: the recipe handed over for $fw is not a file: $recipe_path"
      if [ "$harness_needed" = "no" ]; then
        section_state="not-needed"
        fw_verdict="not-needed"
      else
        # pc_parse_recipe refuses through pc_flush_entry when an entry cannot be recorded, and that
        # die ends the substitution's subshell alone. An empty section_state falls to the `*` arm
        # below and reads as met, so the code is re-raised here. This loop's own `done || exit $?`
        # carries it out of the pipeline.
        section_state="$(pc_parse_recipe "$recipe_path" "$entries_file" "$codepath")" || exit $?
        case "$section_state" in
          undeclared)     fw_verdict="undeclared" ;;
          declared-empty) fw_verdict="undeclared" ;;
          unparseable)    fw_verdict="unknown" ;;
          *)              fw_verdict="met" ;;
        esac
      fi
      # The test-commands block never affects a verdict; it is read here only because it lives in
      # the same recipe file this framework already resolved, and the record already has a place
      # for the rest of what that recipe declared. cr_resolve above already parsed it, so this
      # reads that result rather than opening the same file a second time.
      tc_state="$(printf '%s' "$CR_DOC" | jq -r --arg f "$fw" \
        '[ (.frameworks // [])[] | select(.framework == $f) ][0].testCommandsState // "not-given"')"
      printf '%s' "$CR_DOC" | jq -c --arg f "$fw" \
        '[ (.frameworks // [])[] | select(.framework == $f) ][0].testCommandsRows // [] | .[]' >"$tc_rows_file"
    else
      # The catalog looked and holds no recipe for this framework: it declared nothing, and the
      # build goes on (live-run row 137). A listing that could not be reached or a fetch that
      # failed is nobody looking, a different fact, and that stops. A harness nobody needs is
      # not-needed whichever it was.
      section_state="not-looked"
      if [ "$harness_needed" = "no" ]; then
        fw_verdict="not-needed"
      elif [ "$lookup" = "no-recipe" ]; then
        fw_verdict="undeclared"
      else
        fw_verdict="unknown"
      fi
      tc_state="not-looked"
    fi

    entries_json="$(jq -s '.' "$entries_file" 2>/dev/null)" || entries_json="[]"
    # A condition that answered no names the environment step as its owner when the worktree has
    # no running site. The recipe's owner stays beside it, as recipeOwner. Asked once per run.
    if printf '%s' "$entries_json" | jq -e 'any(.[]; .verdict == "unmet")' >/dev/null; then
      [ "$env_asked" = "yes" ] || { env_owner="$(pc_environment_owner)"; env_asked=yes; }
      [ -z "$env_owner" ] || entries_json="$(printf '%s' "$entries_json" | jq --arg o "$env_owner" '
        map(if .verdict == "unmet" then . + {owner: $o} + (if .owner then {recipeOwner: .owner} else {} end) else . end)')"
    fi
    tc_rows_json="$(jq -s '.' "$tc_rows_file" 2>/dev/null)" || tc_rows_json="[]"
    tooling_entries=""; end_absent_json='[]'
    if [ "$lookup" = "resolved" ] && [ "$fw_verdict" != "not-needed" ]; then
      tooling_json="$(pc_tooling_check "$recipe_path" "$tc_rows_json" \
        "the test-execution recipe names under requires_tooling" "")"
      end_absent_json="$(printf '%s' "$tooling_json" | jq -c '.end')"
      if [ "$(printf '%s' "$tooling_json" | jq '.entries | length')" -gt 0 ]; then
        tooling_entries="$(printf '%s' "$tooling_json" | jq -c '.entries')"
        entries_json="$(jq -nc --argjson have "$entries_json" --argjson add "$tooling_entries" '$have + $add')"
      fi
    fi
    # The tools the checks build-record runs need, from the review recipe. A task with no harness
    # still runs those checks on every order, so not-needed checks them too (gap row 285).
    check_path="$(printf '%s' "$CR_DOC" | jq -r --arg f "$fw" '[ (.frameworks // [])[] | select(.framework == $f) ][0].checkRecipe // ""')"
    # A list pc_build_tools cannot read goes to require whole, which refuses it by name.
    build_json=""; build_rc=0
    [ -z "$check_path" ] || { build_json="$(pc_build_tools "$fw" "$check_path")" || build_rc=$?; }
    [ -n "$build_json" ] || build_json='{}'
    build_tools="$(printf '%s' "$build_json" | jq -r '(.tools // [])[]')"
    unchecked_json="$(printf '%s' "$build_json" | jq -c '.unchecked // []')"
    if [ -n "$build_tools" ] || [ "$build_rc" -ne 0 ]; then
      tooling_json="$(pc_tooling_check "$check_path" '[]' \
        "the review recipe names under requires_tooling, for a check build-record runs on each order" "$build_tools" tooling)"
      build_entries="$(printf '%s' "$tooling_json" | jq -c '.entries')"
      if [ "$build_entries" != "[]" ]; then
        entries_json="$(jq -nc --argjson have "$entries_json" --argjson add "$build_entries" '$have + $add')"
        tooling_entries="$build_entries"
      fi
    fi
    if [ "$section_state" = "ok" ] || [ -n "$tooling_entries" ]; then
      # A tool check on a framework that needs no harness leaves it not-needed, unless it stopped.
      fw_verdict="$(jq -r --arg fw "$fw_verdict" '
        def rank: if . == "not-needed" then -1 elif . == "met" then 0 elif . == "undeclared" then 1 elif . == "unknown" then 2 else 3 end;
        (map(.verdict) + [$fw]) | max_by(rank)
        | if $fw == "not-needed" and (. == "met" or . == "undeclared") then "not-needed" else . end
      ' <<EOF
$entries_json
EOF
)"
    fi

    # The smoke row is run, never merely recorded, and only once this framework's own conditions
    # have already answered `met` or `undeclared`. Running it any earlier would only fail for a
    # reason a condition already named.
    smoke_verdict=""; smoke_reason=""; smoke_output=""; smoke_truncated=false; smoke_first=""
    smoke_exit_code_json="null"
    smoke_state="$fw_verdict"; [ "$harness_needed" = "yes" ] || smoke_state="not-needed"
    case "$smoke_state" in
      not-needed)
        smoke_verdict="not-needed"
        smoke_reason="$harness_reason"
        ;;
      met|undeclared)
        if [ "$tc_state" = "undeclared" ] || [ "$tc_state" = "not-looked" ]; then
          # No `## Test commands` heading at all is the recipe declaring nothing about a smoke
          # command, the same fact `undeclared` already names at the framework's own conditions.
          # A framework the catalog holds no recipe for has no smoke row either. It is the only
          # not-looked framework whose verdict lets this run reach here.
          smoke_verdict="undeclared"
        elif [ "$tc_state" != "ok" ]; then
          smoke_verdict="unknown"
          smoke_reason="the recipe's test commands section could not be read (state: $tc_state), so there is no smoke row to run"
        else
          smoke_row_json="$(printf '%s' "$tc_rows_json" | jq -c '[ .[] | select(.id == "smoke") ][0] // null')"
          if [ "$smoke_row_json" = "null" ]; then
            smoke_verdict="unknown"
            smoke_reason="the recipe's test commands carry no row with id smoke"
          elif [ "$(printf '%s' "$smoke_row_json" | jq -r '.absent // false')" = "true" ]; then
            smoke_verdict="undeclared"
          elif printf '%s' "$smoke_row_json" | jq -e '(.unreadable // []) | index("argv")' >/dev/null 2>&1; then
            smoke_verdict="unknown"
            smoke_reason="the smoke row's argv did not parse as a JSON array of strings"
          else
            smoke_argv_json="$(printf '%s' "$smoke_row_json" | jq -c '.argv // empty')"
            if [ -z "$smoke_argv_json" ] || [ "$smoke_argv_json" = "null" ]; then
              smoke_verdict="unknown"
              smoke_reason="the smoke row declares no argv to run"
            else
              smoke_out_file="$task_folder/implementation/.preconditions-smoke.$$"
              smoke_result="$(tc_run_smoke "$smoke_argv_json" "$codepath" "$smoke_out_file" "$values")"
              smoke_kind="$(printf '%s' "$smoke_result" | cut -f1)"
              smoke_payload="$(printf '%s' "$smoke_result" | cut -f2-)"
              if [ "$smoke_kind" = "UNRESOLVED" ]; then
                smoke_verdict="unknown"
                smoke_reason="the token {$smoke_payload} in the smoke command has no supplied value; pass --value $smoke_payload=<value>"
                token_first="$(cr_lookup "$token_failures" "$smoke_payload")"
                [ -z "$token_first" ] \
                  || smoke_reason="the token {$smoke_payload} in the smoke command has no value, because the recipe's ## Tokens block for it failed or printed nothing ($token_first); pass --value $smoke_payload=<value>"
              elif [ "$smoke_kind" = "EMPTY" ]; then
                smoke_verdict="unknown"
                smoke_reason="the smoke row's argv holds no token at all, so there was nothing to run"
              else
                smoke_exit_code_json="$smoke_payload"
                case "$smoke_payload" in
                  0)   smoke_verdict="met" ;;
                  127) smoke_verdict="unknown"; smoke_reason="the smoke command could not be found (exit 127)" ;;
                  *)   smoke_verdict="unmet" ;;
                esac
              fi
              if [ "$smoke_verdict" != "met" ] && [ -f "$smoke_out_file" ]; then
                smoke_raw_len="$(wc -c <"$smoke_out_file" 2>/dev/null | tr -d '[:space:]')"
                case "$smoke_raw_len" in ''|*[!0-9]*) smoke_raw_len=0 ;; esac
                if [ "$smoke_raw_len" -gt 2000 ]; then
                  smoke_output="$(tail -c 2000 "$smoke_out_file" 2>/dev/null)"
                  smoke_truncated=true
                else
                  smoke_output="$(cat "$smoke_out_file" 2>/dev/null)"
                fi
                smoke_first="$(grep -m1 '[^[:space:]]' "$smoke_out_file" 2>/dev/null)"
              fi
              rm -f "$smoke_out_file"
            fi
          fi
        fi
        ;;
      *)
        smoke_verdict="unknown"
        smoke_reason="this framework's own conditions did not come back met or undeclared, so the smoke command was not run: it would only fail for a reason already known"
        ;;
    esac

    smoke_json="$(jq -n --arg verdict "$smoke_verdict" --arg reason "$smoke_reason" \
          --arg output "$smoke_output" --argjson truncated "$smoke_truncated" \
          --argjson exitCode "$smoke_exit_code_json" --arg first "$smoke_first" '
      {verdict: $verdict}
      + (if $reason == "" then {} else {reason: $reason} end)
      + (if $output == "" then {} else {output: $output} end)
      + (if $truncated == true then {truncated: true} else {} end)
      + (if $exitCode == null then {} else {exitCode: $exitCode} end)
      + (if $first == "" then {} else {firstLine: $first} end)
    ')"

    jq -n --arg framework "$fw" --arg lookup "$lookup" --arg recipePath "$recipe_path" \
          --arg verdict "$fw_verdict" --argjson entries "$entries_json" \
          --arg tcState "$tc_state" --argjson tcRows "$tc_rows_json" --argjson smoke "$smoke_json" \
          --arg reason "$harness_reason" --argjson endAbsent "$end_absent_json" \
          --arg imLookup "$im_lookup" --arg imPath "$im_path" --argjson unchecked "$unchecked_json" \
          --arg rvLookup "$rv_lookup" '
      {framework: $framework, lookup: $lookup, verdict: $verdict, entries: $entries,
       testCommands: {state: $tcState, rows: $tcRows}, smoke: $smoke,
       implementLookup: $imLookup, reviewLookup: $rvLookup}
      + (if $recipePath == "" then {} else {recipePath: $recipePath} end)
      + (if $imPath == "" then {} else {implementRecipePath: $imPath} end)
      + (if $verdict == "not-needed" then {reason: $reason} else {} end)
      + (if $endAbsent == [] then {} else {endOfTaskToolsAbsent: $endAbsent} end)
      + (if $unchecked == [] then {} else {buildToolsNotChecked: $unchecked} end)
    ' >>"$fw_json_file" || die 3 "preconditions: could not record the result for framework $fw"
  done || exit $?

  rm -f "$entries_file" "$tc_rows_file"

  # The worst of every framework's own verdict AND its own smoke run's verdict: the run's answer
  # is never met while a framework's smoke command is unmet or unknown, the same way it is never
  # met while a condition is. A check that was not needed did not run, so it is left out, and a
  # run where none ran answers not-needed.
  run_verdict="$(jq -s -r '
    def rank: if . == "met" then 0 elif . == "undeclared" then 1 elif . == "unknown" then 2 else 3 end;
    ([ .[] | .verdict, .smoke.verdict ] | map(select(. != "not-needed")))
    | if length == 0 then "not-needed" else (. + ["met"]) | max_by(rank) end
  ' "$fw_json_file")"

  today="$(date -u +%Y-%m-%d)"
  record_json="$(jq -s --arg takenAt "$today" --arg verdict "$run_verdict" --argjson tokens "$tokens_json" '
    {schemaVersion: 1, takenAt: $takenAt, verdict: $verdict, frameworks: .}
    + (if $tokens == {} then {} else {tokens: $tokens} end)
  ' "$fw_json_file")" || die 3 "preconditions: could not assemble the record"
  rm -f "$fw_json_file"

  record_file="$task_folder/implementation/preconditions.json"
  write_atomic "$record_file" "$record_json"

  # A project's own copy of the test-execution recipe behind the catalog's copy (gap row 284). The
  # folder source wins the lookup, so nothing else would say the copy fell behind. Reported only.
  while IFS="$(printf '\t')" read -r fw pc_catalog; do
    [ -n "$fw" ] || continue
    recipe_path="$(cr_lookup "$recipes" "$fw")"
    [ -n "$recipe_path" ] || continue
    pc_line="$(recipe_stale_line "$fw" "$recipe_path" "$pc_catalog")"
    [ -z "$pc_line" ] || pc_stale="$pc_stale${pc_stale:+ }$pc_line"
  done <<PC_CATALOG
$catalog_recipes
PC_CATALOG

  # The freeze wall, announced here rather than at the first order's freeze. `tests-freeze` takes
  # its test globs from the implement recipe's `## Oracle files` block, so with no such recipe a
  # test-proved order dies at exit 27, after the design closed, the build started and the test
  # author already ran. This step is the first place a person can be told, and telling them is
  # what this line is for. A lookup nobody ran is a third answer, never folded into the other two.
  im_resolved="$(printf '%s' "$record_json" | jq -r '[ .frameworks[] | select(.implementLookup == "resolved") | .framework ] | join(", ")')"
  im_blocked="$(printf '%s' "$SNAPSHOT_DOC" | jq -r "$BR_ORDER_FACTS_JQ"'[ (.workOrders // [])[] | select(orderFacts.slot == "order-tests") | .id ] | join(", ")')"
  im_notgiven="$(printf '%s' "$record_json" | jq -r '[ .frameworks[] | select(.implementLookup == "not-given") | .framework ] | join(", ")')"
  # The warning of its own, printed beside the freeze line (live-run row 171). A framework nobody
  # looked up says nothing about a test-proved order, so the run that answered for one framework
  # and skipped a second is warned too, not the flagless run alone. It carries its own line
  # because the freeze line is already near the 240 characters a summary value prints.
  im_unlooked="none"
  im_advice="none"
  rv_unresolved="$(printf '%s' "$record_json" | jq -r '[ .frameworks[] | select(.reviewLookup != "resolved") | .framework + "=" + .reviewLookup ] | join(", ")')"
  [ -n "$rv_unresolved" ] \
    && rv_unresolved="no review recipe for $rv_unresolved, so build-record runs no check command there. Ask for point: review and pass --check-recipe, or --check-lookup-failed with the lookup's word" \
    || rv_unresolved="none"
  [ -z "$im_notgiven" ] || [ -z "$im_blocked" ] \
    || im_unlooked="nobody looked up $im_notgiven, so nothing here says whether these test-proved orders can freeze: $im_blocked"
  # A summary value prints 240 characters (`im_print_summary`), and two of these messages carry a
  # value that grows with the project: the framework names and every test-proved order id. So a
  # growing message keeps the freeze line, and the fixed instruction that goes with it takes the
  # `freezeAdvice` line, which no project can make longer. A cut instruction is the one part a
  # person cannot work out again.
  im_by_tests="No order in this snapshot is proved by tests, so none of them needs one"
  [ -z "$im_blocked" ] || im_by_tests="These orders are proved by tests: $im_blocked"
  if [ -n "$im_resolved" ]; then
    im_freeze="an implement recipe resolved for $im_resolved. $im_by_tests"
    # No record maps a work order to a framework, so a resolved recipe cannot say which orders it
    # covers. The line names what it read, and a person makes the match.
    [ -z "$im_blocked" ] \
      || im_advice="No record maps an order to a framework. Check that one of those frameworks carries the ## Oracle files globs for each of those orders"
  elif ! printf '%s' "$record_json" | jq -e '[ .frameworks[] | select(.implementLookup != "not-given") ] | length > 0' >/dev/null; then
    im_freeze="the implement recipe lookup was not run. Ask the navigator for point: implement, once per framework, and pass --implement-lookup <framework>=<path or reason>. A test-proved order cannot freeze without that recipe's ## Oracle files globs"
  elif [ -z "$im_blocked" ]; then
    im_freeze="no implement recipe for any framework. No order in this snapshot is proved by tests, so none of them needs one"
  else
    im_freeze="no implement recipe for any framework, so these orders cannot be built and each freeze exits 27: $im_blocked"
    im_advice="a project builds its record and observe orders in full. A gate order freezes, but its own check reads unknown, which is not met. Write the implement recipe for a framework this project declares, or change each blocked order's proof"
  fi

  # ---- the baseline: only when this run's own verdict permits the build to continue -------------
  # A baseline taken after a condition answered no would measure a broken environment, so
  # `unmet`/`unknown` skip this whole section and the fields below stay at their "not attempted"
  # defaults. Read from the ledger's own startedFrom, never a fresh git call, so the commit this
  # baseline claims and the commit the ledger would roll back to are always the same value.
  BASELINE_FILE="$task_folder/implementation/baseline.json"
  baseline_status="not-attempted"
  baseline_note="this run's own verdict ($run_verdict) does not permit the build to continue; a baseline taken now would measure a broken environment"
  baseline_commit_report=""
  baseline_summary_json='null'

  case "$run_verdict" in
    met|undeclared|not-needed)
      LEDGER_FILE="$STARTED_LEDGER_FILE"
      ledger_doc="$STARTED_LEDGER_DOC"
      ledger_started_from="$(ledger_required_string "$ledger_doc" "startedFrom")" \
        || die 3 "preconditions: $LEDGER_FILE is damaged (see stderr above). Repair or remove it by hand before running this again."
      baseline_commit_report="$ledger_started_from"

      case "$(bl_state)" in
        missing)
          snapshot_doc="$SNAPSHOT_DOC"
          scope_json="$(printf '%s' "$snapshot_doc" | jq -c '[ (.workOrders // [])[] | (.ownedFiles // [])[] ] | unique')"

          suite_json_file="$task_folder/implementation/.baseline-suite.$$"
          : >"$suite_json_file"
          if [ "$harness_needed" = "no" ]; then
            # No suite runs for a task that runs no test. One entry per framework says so, so a
            # reader sees the row was skipped and not forgotten.
            printf '%s' "$record_json" | jq -c --arg reason "$harness_reason" \
              '.frameworks[] | {framework: .framework, verdict: "not-needed", reason: $reason}' >"$suite_json_file"
          else
            bl_run_suite "$record_json" "$codepath" "$values" "$suite_json_file"
          fi
          suite_json="$(jq -s '.' "$suite_json_file" 2>/dev/null)" || suite_json="[]"
          rm -f "$suite_json_file"

          # The three tools run over the baseline scope, the same union of every order's ownedFiles
          # recorded above. A caller that passed no flag for one of them leaves it undeclared, with
          # the reason this record has always carried.
          # bl_tool_result runs in a command substitution, so a die inside it ends that subshell
          # alone and leaves nothing here. Each value is tested where it lands, because a helper
          # around the call would hold the same die in the same subshell. Without these three the
          # jq below fails on an empty --argjson, and write_atomic then refuses naming the
          # baseline file, which tells a person the wrong thing about what went wrong.
          cs_json="$(bl_tool_result "coding-standards" "coding-standards" "$codepath" "$scope_json" "$task_folder/implementation")"
          [ -n "$cs_json" ] || die 3 "preconditions: the coding-standards run produced no result. No baseline was written"
          sa_json="$(bl_tool_result "static-analysis" "static-analysis" "$codepath" "$scope_json" "$task_folder/implementation")"
          [ -n "$sa_json" ] || die 3 "preconditions: the static-analysis run produced no result. No baseline was written"
          sec_json="$(bl_tool_result "security" "security" "$codepath" "$scope_json" "$task_folder/implementation")"
          [ -n "$sec_json" ] || die 3 "preconditions: the security run produced no result. No baseline was written"

          baseline_json="$(jq -n \
            --arg takenAt "$today" --arg commit "$ledger_started_from" \
            --argjson scope "$scope_json" --argjson suite "$suite_json" \
            --argjson codingStandards "$cs_json" \
            --argjson staticAnalysis "$sa_json" \
            --argjson security "$sec_json" \
            --argjson checkRecipes "$check_recipes_json" \
            '{
              schemaVersion: 1, takenAt: $takenAt, commit: $commit, scope: $scope, suite: $suite,
              codingStandards: $codingStandards,
              staticAnalysis:  $staticAnalysis,
              security:        $security,
              checkRecipes:    $checkRecipes
            }')" || die 3 "preconditions: could not assemble the baseline record"
          write_atomic "$BASELINE_FILE" "$baseline_json"

          baseline_status="written"
          baseline_note="taken at commit $ledger_started_from"
          ;;
        ok)
          existing_commit="$(bl_commit_of)"
          if [ "$existing_commit" = "$ledger_started_from" ]; then
            baseline_status="already-recorded"
            baseline_note="a baseline already exists for commit $ledger_started_from; a baseline retaken after code is written measures nothing, so it was left alone"
          else
            die 21 "preconditions: $BASELINE_FILE already holds a baseline taken at commit $existing_commit, but this run's own ledger started from a different commit, $ledger_started_from. A baseline is taken once, at the commit the build started from, and never retaken after that: retaking it here would measure the wrong repository state. Investigate before proceeding; remove $BASELINE_FILE and its baseline-output/ folder by hand only if this task's baseline is meant to start over."
          fi
          ;;
        unreadable)
          die 3 "preconditions: $BASELINE_FILE exists but could not be read as a baseline record (not valid JSON, not an object, or its commit field is missing or malformed). Repair or remove it by hand before running this again."
          ;;
      esac

      [ "$baseline_status" = "not-attempted" ] \
        || baseline_summary_json="$(jq -c '{
             suite: [ .suite[] | {framework, verdict} ],
             codingStandards: {verdict: .codingStandards.verdict},
             staticAnalysis: {verdict: .staticAnalysis.verdict},
             security: {verdict: .security.verdict}
           }' "$BASELINE_FILE")"
      ;;
  esac

  # The report, as summary lines. One line per framework carries its verdict, its lookup, the ids
  # of what answered unmet or unknown with the owner each recipe named, the state of its test
  # commands and its smoke verdict. What a condition or a smoke run printed stays in the record.
  # A verdict not met names the first row that stopped it and the command that row ran (live-run
  # row 206). The first line that command printed takes the `failedOutput:` line. The install
  # advice takes the `nextAdvice:` line, and only for an absent condition tool. Each is a line of
  # its own, so the 240-character cut of a long argv never takes the cause or the instruction.
  # A suite the baseline recorded unmet or unknown takes the `baselineRed:` line (gap row 261):
  # the build goes on, but finish meets that red again, and only a person can decide it.
  local pc_next pc_advice="none" pc_failed="none" pc_cause
  pc_next="$(im_next_step "$STARTED_LEDGER_DOC" "$SNAPSHOT_DOC" "$task_folder/implementation" "true" "false")"
  case "$run_verdict" in
    met|undeclared|not-needed) ;;
    *)
      pc_cause="$(printf '%s' "$record_json" | jq -c --arg values "$values" '
        ($values | split("\n") | map(select(contains("\t")) | {key: sub("\t.*"; ""), value: sub("^[^\t]*\t"; "")})
          | reverse | from_entries) as $v
        | def bad: . == "unmet" or . == "unknown";
          def ran($argv): "It ran: " + ($argv | map(if test("^\\{[^{}]+\\}$") then ($v[.[1:-1]] // .) else . end) | join(" "));
          def said: if (.firstLine // "") == "" then "the command printed nothing" else .firstLine end;
          def how: " read " + .verdict
            + ([ (.exitCode // empty | "exit " + tostring), (.reason // empty) ] | if length == 0 then "" else " (" + join(", ") + ")" end);
        [ .frameworks[] | . as $f
          | ( (.entries[] | select(.verdict | bad)
               | if .check then {next: ("The \($f.framework) condition \(.id)" + how + ". " + ran(.check)), output: said}
                 else {next: ("The \($f.framework) condition \(.id)" + how), output: (.firstLine // "none")} end),
              (.smoke | select(.verdict | bad)
               | if .exitCode == null then {next: "The \($f.framework) smoke row read \(.verdict): \(.reason // "")", output: "none"}
                 else {next: ("The \($f.framework) smoke row" + ({verdict, exitCode} | how) + ". "
                   + ran([ $f.testCommands.rows[] | select(.id == "smoke") ][0].argv // [])), output: said} end),
              (select(.verdict | bad) | {next: "The \(.framework) framework read \(.verdict), and its recipe lookup answered \(.lookup)", output: "none"}) ) ]
        | .[0] // {next: "Read the record", output: "none"}')"
      pc_next="none: the build does not go on. $(printf '%s' "$pc_cause" | jq -r '.next')"
      pc_failed="$(printf '%s' "$pc_cause" | jq -r '.output')"
      printf '%s' "$record_json" | jq -e '[ .frameworks[].entries[] | select(.reason == "check-command-not-found") ] | length > 0' >/dev/null \
        && pc_advice="A condition's tool is absent. Run the tool skill's install from the worktree, which holds tracked files only: $codepath"
      # The catalog comes first, as the tool skill's exit 2 wins over its exit 4.
      pc_no_recipe="$(printf '%s' "$record_json" | jq -r '[ .frameworks[].entries[]
        | select(.verdict == "unknown" and ((.firstLine // "") | startswith("no recipe"))) | .id | ltrimstr("requires_tooling: ") ] | join(", ")')"
      [ -z "$pc_no_recipe" ] \
        || pc_advice="No folder holds a tooling recipe for $pc_no_recipe. Dispatch catalog-identifier with tooling: <tool> per tool, then run preconditions again with --tooling <tool>=<path>"
      ;;
  esac
  im_print_summary "preconditions" "$(jq -n --arg verdict "$run_verdict" --arg record "$record_file" \
        --argjson report "$record_json" --arg freeze "$im_freeze" --arg notLookedUp "$im_unlooked" \
        --arg freezeAdvice "$im_advice" --arg reviewNotResolved "$rv_unresolved" \
        --arg baselineFile "$BASELINE_FILE" --arg baselineStatus "$baseline_status" \
        --arg baselineNote "$baseline_note" --arg baselineCommit "$baseline_commit_report" \
        --argjson baselineSummary "$baseline_summary_json" --arg next "$pc_next" --arg nextAdvice "$pc_advice" \
        --arg failedOutput "$pc_failed" --arg staleRecipe "$pc_stale" '
    def named($v): [ .entries[] | select(.verdict == $v) | .id + (if (.owner // "") == "" then "" else " (owner: " + .owner + ")" end) ]
                   | if length == 0 then "none" else join(", ") end;
    {verdict: $verdict,
     record: $record,
     framework: [ $report.frameworks[] | {
        framework: .framework,
        verdict: .verdict,
        lookup: ("lookup=" + .lookup),
        unmet: ("unmet: " + named("unmet")),
        unknown: ("unknown: " + named("unknown")),
        testCommands: ("testCommands=" + .testCommands.state
                       + (([ .testCommands.rows[] | select((.unreadable // []) | length > 0) | .id ]) as $u
                          | if ($u | length) == 0 then "" else " unreadable=" + ($u | join(",")) end)),
        implement: ("implement=" + .implementLookup
                    + (if (.implementRecipePath // "") == "" then "" else " " + .implementRecipePath end)),
        smoke: ("smoke=" + .smoke.verdict + (if (.smoke.reason // "") == "" then "" else " (" + .smoke.reason + ")" end)) } ],
     freeze: $freeze,
     notLookedUp: $notLookedUp,
     freezeAdvice: $freezeAdvice,
     reviewNotResolved: $reviewNotResolved,
     baseline: ($baselineStatus + " | " + $baselineNote),
     baselineFile: (if $baselineStatus == "not-attempted" then "none" else $baselineFile end),
     baselineCommit: (if $baselineCommit == "" then "none" else $baselineCommit end),
     baselineSuite: (if $baselineSummary == null then "none"
                     else ([ $baselineSummary.suite[] | .framework + "=" + .verdict ] | if length == 0 then "none" else join(" ") end) end),
     baselineRed: (if $baselineSummary == null then "none"
                   else ([ $baselineSummary.suite[] | select(.verdict == "unmet" or .verdict == "unknown")
                           | .framework + "=" + .verdict ]
                         | if length == 0 then "none"
                           else join(" ") + ": the suite already fails before the build. finish refuses on this red at the end unless the baseline subtraction clears it. Put it to the person now, before the first order." end) end),
     baselineTools: (if $baselineSummary == null then "none"
                     else "codingStandards=" + $baselineSummary.codingStandards.verdict
                          + " staticAnalysis=" + $baselineSummary.staticAnalysis.verdict
                          + " security=" + $baselineSummary.security.verdict end),
     endOfTaskAbsent: ([ $report.frameworks[] | (.endOfTaskToolsAbsent // [])[] | .tool + " (" + (.rows | join(", ")) + ")" ]
                       | if length == 0 then "none"
                         else join(", ") + ": absent, and only end-of-task rows run it, so the build goes on and review reads those rows as known. Install it with the tool skill to run them." end),
     buildToolsNotChecked: ([ $report.frameworks[] | (.buildToolsNotChecked // [])[] | .row + " (" + (.argv | join(" ")) + ")" ]
                       | if length == 0 then "none"
                         else join(", ") + ": the review recipe names no tool under requires_tooling that this row runs, so nothing checked its program before the build. A missing program reads unknown at build-record." end),
     staleRecipe: (if $staleRecipe == "" then "none" else $staleRecipe end),
     failedOutput: $failedOutput,
     nextAdvice: $nextAdvice,
     next: $next}')"

  # `met` and `undeclared` both go on. A recipe that says this framework needs nothing before a
  # test runs, or nothing before a smoke command proves one, has answered, and refusing on it
  # would mean no project on that framework ever builds. The two never share a value in the
  # record, and the report names which one happened, which is the whole of what "undeclared is
  # not met" protects: a caller must not report a recipe that declared nothing as a set of
  # conditions that passed. `not-needed` goes on too: nothing was checked because nothing runs.
  case "$run_verdict" in
    met|undeclared|not-needed) ;;
    *) exit 19 ;;
  esac
}

# A recipe the catalog republished after `preconditions` ran (live-run row 99). The step resolves
# the recipe again through the navigator, the way references/preconditions.md says, and hands the
# new path over. This replaces the path the record holds for the named frameworks only, and
# appends what changed under `recipeRefreshes`. It re-runs nothing: the verdict stands, because a
# recipe's preconditions heading changes more rarely than its markers do, and the person who
# refreshes knows why. The review recipe is pinned by baseline.json with its sha256, and a baseline
# reads the tree before the task. bl_tool_result runs each tool where the tree stands, so a second
# reading would record this task's own findings as pre-existing. So --check-recipe adopts a new
# review body only when every tool row of it reads met or undeclared on the current tree (gap row
# 295). Such a baseline subtracts nothing, so no finding of this task is hidden. Any other reading
# refuses at exit 73 and names the row. The adoption replaces the pin and the baseline fields of
# the rows it ran, and records both hashes under `recipeRefreshes`. Every refusal but one runs
# before the first write, so a refused call leaves the records as they were. The one after is a
# failed move into baseline-output/, which runs after the old output of that row was removed.
# The staging folder is a global, because zsh runs the EXIT trap after the locals are gone.
RR_STAGE=""
rr_stage_remove() { [ -z "$RR_STAGE" ] || rm -rf "$RR_STAGE"; RR_STAGE=""; }
do_recipe_refresh() {
  local task_folder="" recipes="" fw rp line from kind resolve_rc
  local record_file record_doc today refreshed=""
  local check_recipes="" baseline_doc="" scope_json was_path was_sha now_sha cc_state
  local tool_id result verdict failed adopted="" unchanged="" reads="" moves="" field
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --recipe)
        [ "$#" -ge 2 ] || die 3 "recipe-refresh: --recipe needs <framework>=<path>"
        case "$2" in *=*) ;; *) die 3 "recipe-refresh: --recipe takes <framework>=<path>, got: $2" ;; esac
        fw="${2%%=*}"; rp="${2#*=}"
        [ -n "$fw" ] || die 3 "recipe-refresh: --recipe was given no framework name: $2"
        [ -f "$rp" ] || die 90 "recipe-refresh: the path handed over for $fw does not exist: $rp. Nothing was written."
        cr_recipe_pair "recipe-refresh" "--recipe" "$2"
        recipes="$recipes$CR_PAIR
"
        shift 2 ;;
      --check-recipe)
        [ "$#" -ge 2 ] || die 3 "recipe-refresh: --check-recipe needs <framework>=<path>"
        case "$2" in *=*) ;; *) die 3 "recipe-refresh: --check-recipe takes <framework>=<path>, got: $2" ;; esac
        [ -f "${2#*=}" ] || die 90 "recipe-refresh: the path handed over for ${2%%=*} does not exist: ${2#*=}. Nothing was written."
        cr_recipe_pair "recipe-refresh" "--check-recipe" "$2"
        check_recipes="$check_recipes$CR_PAIR
"
        shift 2 ;;
      -*) die 3 "recipe-refresh: unrecognized argument: $1" ;;
      *)
        [ -z "$task_folder" ] || die 3 "recipe-refresh: more than one task folder given"
        task_folder="$1"; shift ;;
    esac
  done
  [ -n "$recipes$check_recipes" ] \
    || die 3 "recipe-refresh: nothing to refresh; pass --recipe or --check-recipe <framework>=<path>"

  task_folder="$(resolve_task_folder "$task_folder" "recipe-refresh")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  TASK_PATH="$task_folder"
  IMPL_DIR="$task_folder/implementation"
  require_started_build "recipe-refresh"

  record_file="$IMPL_DIR/preconditions.json"
  [ -f "$record_file" ] \
    || die 90 "recipe-refresh: $record_file does not exist, so no framework has a recipe on record to replace. Run preconditions first."
  record_doc="$(jq -c '.' "$record_file" 2>/dev/null)"
  [ -n "$record_doc" ] \
    || die 3 "recipe-refresh: $record_file exists but could not be read as JSON. Repair or remove it by hand before running this again."
  today="$(date -u +%Y-%m-%d)"

  # A framework is refreshed only where the record already holds a resolved path: a lookup that
  # failed recorded no recipe, and every reader of the path filters on `lookup == "resolved"`, so
  # a path written beside a failed lookup would reach nothing. The first path is preconditions'.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    fw="${line%%	*}"; rp="${line#*	}"
    from="$(printf '%s' "$record_doc" | jq -r --arg f "$fw" \
      '[ (.frameworks // [])[] | select(.framework == $f and .lookup == "resolved") ][0].recipePath // ""')"
    [ -n "$from" ] \
      || die 90 "recipe-refresh: $record_file records no resolved recipe for framework $fw, so there is no path of its own to replace. A first path is preconditions' to record, with --recipe $fw=<path>. Nothing was written."
    # A new body may declare other ## Tokens blocks. So a changed path drops the values the old
    # body gave, and a later step reads unknown rather than a stale value.
    record_doc="$(printf '%s' "$record_doc" | jq -c --arg f "$fw" --arg from "$from" --arg to "$rp" --arg at "$today" '
      .frameworks |= map(if .framework == $f then .recipePath = $to else . end)
      | (if $from != $to then del(.tokens) else . end)
      | .recipeRefreshes = ((.recipeRefreshes // []) + [{framework: $f, kind: "test-execution", from: $from, to: $to, at: $at}])')"
    [ -n "$record_doc" ] || die 3 "recipe-refresh: the record update for $fw failed."
    refreshed="$refreshed$fw	test-execution	$from	$rp
"
  done <<RR_EOF
$recipes
RR_EOF

  if [ -n "$check_recipes" ]; then
    BASELINE_FILE="$IMPL_DIR/baseline.json"
    [ "$(bl_state)" = "ok" ] \
      || die 90 "recipe-refresh: $BASELINE_FILE is missing or unreadable, so no review recipe is pinned to replace. preconditions takes the baseline and pins the first one. Nothing was written."
    baseline_doc="$(jq -c '.' "$BASELINE_FILE")"
    rv_load_codepath "recipe-refresh"
    scope_json="$(printf '%s' "$baseline_doc" | jq -c '.scope // []')"
    trap 'rr_stage_remove' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    RR_STAGE="$(mktemp -d "$IMPL_DIR/.recipe-refresh.XXXXXX")" || die 3 "recipe-refresh: could not create a temporary folder"
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      fw="${line%%	*}"; rp="${line#*	}"
      was_path="$(printf '%s' "$baseline_doc" | jq -r --arg f "$fw" '[ (.checkRecipes // [])[] | select(.framework == $f) ][0].path // ""')"
      was_sha="$(printf '%s' "$baseline_doc" | jq -r --arg f "$fw" '[ (.checkRecipes // [])[] | select(.framework == $f) ][0].sha256 // ""')"
      [ -n "$was_sha" ] || { die 90 "recipe-refresh: $BASELINE_FILE pins no review recipe for framework $fw, so there is none to replace. A first one is preconditions' to pin, with --check-recipe $fw=<path>. Nothing was written."; }
      CR_WHO="recipe-refresh"; CR_TEST_RECIPES=""; CR_CHECK_RECIPES="$line"; PC_VALUES=""
      # shellcheck disable=SC2034 # read by the sourced library
      CR_TOOL_IDS_ALL=true
      cr_resolve
      now_sha="$(printf '%s' "$CR_DOC" | jq -r '.frameworks[0].checkRecipeSha256')"
      if [ "$now_sha" = "$was_sha" ]; then
        unchanged="$unchanged$fw	$rp	$was_sha
"
        continue
      fi
      cc_state="$(printf '%s' "$CR_DOC" | jq -r '.frameworks[0].checkCommandsState')"
      [ "$cc_state" = "ok" ] \
        || { die 73 "recipe-refresh: the review recipe $rp for $fw cannot be adopted: its Check commands block could not be read (state: $cc_state). Nothing was written."; }
      failed=""
      while IFS= read -r tool_id; do
        [ -n "$tool_id" ] || continue
        result="$(bl_tool_result "$tool_id" "$tool_id" "$RV_CODEPATH" "$scope_json" "$RR_STAGE/$fw")"
        [ -n "$result" ] || { die 3 "recipe-refresh: the $tool_id run produced no result. Nothing was written."; }
        verdict="$(printf '%s' "$result" | jq -r '.verdict')"
        reads="$reads$fw	$tool_id	$verdict
"
        # An undeclared row passes when the recipe declares it absent or the scope holds no file it
        # reads. A row the recipe holds but whose argv did not parse is `missing`, and refuses.
        [ "$verdict" != "undeclared" ] \
          || ! printf '%s' "$CR_DOC" | jq -e --arg id "$tool_id" 'any((.tools // [])[]; .id == $id and has("missing"))' >/dev/null \
          || verdict="unknown"
        case "$verdict" in
          met|undeclared) ;;
          *) failed="$failed $tool_id reads $verdict ($(printf '%s' "$result" | jq -r 'if .reason then .reason else "exit \(.exitCode)" end'))." ;;
        esac
        field="$(rw_baseline_field_for "$tool_id")"
        [ -n "$field" ] || continue
        baseline_doc="$(printf '%s' "$baseline_doc" | jq -c --arg k "$field" --argjson r "$result" '.[$k] = $r')"
        moves="$moves$fw	$tool_id
"
      done <<RR_TOOLS
$(printf '%s' "$CR_DOC" | jq -r '(.tools // [])[].id')
RR_TOOLS
      [ -z "$failed" ] \
        || { die 73 "recipe-refresh: the review recipe $rp for $fw cannot be adopted, because not every tool row of it reads met or undeclared on the current tree:$failed A new baseline would subtract that finding from every later check. Finish the task with the pinned body, sha256 $was_sha, or repair the finding and run this again. Nothing was written."; }
      baseline_doc="$(printf '%s' "$baseline_doc" | jq -c --arg f "$fw" --arg p "$rp" --arg sha "$now_sha" \
        '.checkRecipes |= map(if .framework == $f then .path = $p | .sha256 = $sha else . end)')"
      record_doc="$(printf '%s' "$record_doc" | jq -c --arg f "$fw" --arg from "$was_path" --arg to "$rp" \
        --arg fromSha "$was_sha" --arg toSha "$now_sha" --arg at "$today" '
        .recipeRefreshes = ((.recipeRefreshes // []) + [{framework: $f, kind: "review", from: $from, to: $to,
          fromSha256: $fromSha, toSha256: $toSha, at: $at}])')"
      [ -n "$baseline_doc" ] && [ -n "$record_doc" ] \
        || { die 3 "recipe-refresh: the record update for $fw failed. Nothing was written."; }
      adopted="$adopted$fw	$was_path	$was_sha	$rp	$now_sha
"
    done <<RR_CHECK
$check_recipes
RR_CHECK
    # Each output the new baseline names replaces the old file of that row. A row that ran no
    # command names no file, so its old file goes too.
    while IFS='	' read -r fw tool_id; do
      [ -n "$fw" ] || continue
      rm -f "${IMPL_DIR:?}/${BL_OUTPUT_DIR:?}/${tool_id:?}.txt"
      [ ! -f "$RR_STAGE/$fw/$BL_OUTPUT_DIR/$tool_id.txt" ] || {
        mkdir -p "$IMPL_DIR/$BL_OUTPUT_DIR" \
          && mv "$RR_STAGE/$fw/$BL_OUTPUT_DIR/$tool_id.txt" "$IMPL_DIR/$BL_OUTPUT_DIR/$tool_id.txt"
      } || die 3 "recipe-refresh: could not move the $tool_id output into $IMPL_DIR/$BL_OUTPUT_DIR"
    done <<RR_MOVES
$moves
RR_MOVES
    rr_stage_remove
    [ -z "$adopted" ] || write_atomic "$BASELINE_FILE" "$baseline_doc"
  fi

  write_atomic "$record_file" "$record_doc"
  echo "action: recipe-refresh"
  # One line per entry, the fields the record holds. No field is ever empty, so a tab-split read
  # never shifts one.
  while IFS='	' read -r fw kind from rp; do
    [ -n "$fw" ] || continue
    printf 'refreshed: %s %s %s -> %s\n' "$fw" "$kind" "$from" "$rp"
  done <<RR_EOF
$refreshed
RR_EOF
  while IFS='	' read -r fw tool_id verdict; do
    [ -n "$fw" ] || continue
    printf 'read: %s %s %s\n' "$fw" "$tool_id" "$verdict"
  done <<RR_EOF
$reads
RR_EOF
  while IFS='	' read -r fw from was_sha rp now_sha; do
    [ -n "$fw" ] || continue
    printf 'adopted: %s review %s (sha256 %s) -> %s (sha256 %s)\n' "$fw" "$from" "$was_sha" "$rp" "$now_sha"
  done <<RR_EOF
$adopted
RR_EOF
  while IFS='	' read -r fw rp was_sha; do
    [ -n "$fw" ] || continue
    printf 'unchanged: %s review %s has the sha256 the baseline pinned, %s, so nothing was adopted\n' "$fw" "$rp" "$was_sha"
  done <<RR_EOF
$unchanged
RR_EOF
  [ -z "$adopted" ] || printf 'baseline: %s\n' "$BASELINE_FILE"
  printf 'record: %s\n' "$record_file"
  printf 'verdict: %s (unchanged; the refresh re-runs nothing)\n' "$(printf '%s' "$record_doc" | jq -r '.verdict')"
}

# ------------------------------------------------------------------------------------------------
# Step three: tests-brief and tests-freeze. The model that writes a test chooses the level, writes
# the file, and runs it. This script never writes a test and never judges one. `tests-brief`
# assembles exactly what that model may see, from the frozen snapshot, and refuses when the inputs
# are not ready. `tests-freeze` verifies what came back and freezes it.
#
# Both actions read only <task_folder>/implementation/snapshot.json and, for a dependency's
# completion, ledger.json: the frozen copies `start` already wrote and hash-verified. Neither ever
# reads alignment.json or design/*.json live, for the same reason `start`, once a snapshot exists,
# never reads design-closed.json again: the frozen copy is what the build is frozen against, and
# only the frozen copy governs a resumed or later step.
#
# `tb_` and `tt_` are this section's own helper prefixes, kept apart from `pc_` and `tc_` above,
# which belong to a different step and read a different kind of document (a recipe, not a snapshot).
# ------------------------------------------------------------------------------------------------

# The ids in $1 (served) followed by the new ids in $2 (owned), each id kept once, in the order it
# was first seen. Not `unique`, which sorts: a criterion's own authoring order is worth keeping,
# and c10 sorting before c2 would be a cosmetic defect nobody asked for.
tt_ordered_union() {
  jq -cn --argjson a "$1" --argjson b "$2" '
    ($a + $b) | reduce .[] as $x ([]; if index($x) then . else . + [$x] end)
  '
}

# Loads the frozen work order $2 from the frozen snapshot document $1, and the frozen record of
# every criterion it serves or owns, in that first-seen order. Sets three globals a caller reads
# afterward: UNIT_JSON (the whole frozen work order object), CRITERIA_IDS_JSON (the ordered id
# list), and CRITERIA_JSON (the full frozen criterion record for each). Exits directly (exit 22 or
# exit 3) rather than returning a code, because every caller of this helper treats both problems as
# fatal and would only turn around and exit itself.
UNIT_JSON=""; CRITERIA_IDS_JSON="[]"; CRITERIA_JSON="[]"
tt_load_unit_and_criteria() {
  local snapshot_doc="$1" unit_id="$2" who="$3"
  UNIT_JSON="$(printf '%s' "$snapshot_doc" | jq -c --arg id "$unit_id" \
    '(.workOrders // []) | map(select(.id == $id)) | .[0] // null')"
  [ "$UNIT_JSON" != "null" ] || die 22 "$who: $unit_id is not in the frozen copy."

  local served_json owned_json count j id one
  served_json="$(printf '%s' "$UNIT_JSON" | jq -c '.criteriaServed // []')"
  owned_json="$(printf '%s' "$UNIT_JSON" | jq -c '.criteriaOwned // []')"
  CRITERIA_IDS_JSON="$(tt_ordered_union "$served_json" "$owned_json")"

  CRITERIA_JSON='[]'
  count="$(printf '%s' "$CRITERIA_IDS_JSON" | jq 'length')"
  j=0
  while [ "$j" -lt "$count" ]; do
    id="$(printf '%s' "$CRITERIA_IDS_JSON" | jq -r --argjson j "$j" '.[$j]')"
    one="$(printf '%s' "$snapshot_doc" | jq -c --arg id "$id" \
      '(.alignment.criteria // []) | map(select(.id == $id)) | .[0] // null')"
    [ "$one" != "null" ] \
      || die 3 "$who: $unit_id names criterion $id, which is not in the frozen contract."
    CRITERIA_JSON="$(printf '%s' "$CRITERIA_JSON" | jq -c --argjson c "$one" '. + [$c]')"
    j=$((j + 1))
  done
}

# Reads the frozen snapshot beside <task_folder>/implementation, dying (exit 25 missing, exit 3
# unreadable) when it is not ready. Sets SNAPSHOT_DOC. Shared by tests-brief and tests-freeze,
# which both refuse for the same reason on the same missing file.
SNAPSHOT_DOC=""
# Writes one order's state into the ledger. $1 the ledger file, $2 the unit id, $3 a jq expression
# applied to that order's entry with `.` bound to it. The ledger is the state file, and until
# 2026-09-11 no step after start wrote anything into it but the attempt counter, so the ready list
# and the resume logic both read a lastStep that never moved.
tt_ledger_update() {
  local ledger_file="$1" unit_id="$2" expr="$3" doc
  [ -f "$ledger_file" ] || die 3 "the ledger at $ledger_file is missing, though start writes it. Run start again."
  doc="$(jq -c --arg id "$unit_id" \
    ".orders = (.orders | map(if .id == \$id then ($expr) else . end))" "$ledger_file" 2>/dev/null)"
  [ -n "$doc" ] || die 3 "the ledger at $ledger_file could not be read as JSON, or the update to $unit_id failed."
  write_atomic "$ledger_file" "$doc"
}

# Appends to list $1 the `information` items the review record of order $2 holds, each as
# {id, from, summary, file}. Prints the list. Empty when the record is missing or holds none. Both
# brief actions carry these to a dependent order the way they carry the interface record, so what
# a reviewer wrote for the person reaches the next order's author and builder instead of living in
# the conversation that dispatched the review (live-run row 103).
im_dependency_information() {
  local list="$1" dep_id="$2" review_file="$IMPL_DIR/review-$2.json" items='[]'
  if [ -f "$review_file" ]; then
    items="$(jq -c --arg from "$dep_id" \
      '[ (.information // [])[] | {id, from: $from, summary, file} ]' "$review_file" 2>/dev/null)"
    [ -n "$items" ] || items='[]'
  fi
  printf '%s' "$list" | jq -c --argjson items "$items" '. + $items'
}

tt_load_snapshot() {
  local who="$1"
  local snapshot_file="$IMPL_DIR/snapshot.json"
  [ -f "$snapshot_file" ] \
    || die 25 "$who: $snapshot_file not found. This step ran before start, so there is no frozen copy. Run start on this task first."
  SNAPSHOT_DOC="$(jq -c '.' "$snapshot_file" 2>/dev/null)"
  [ -n "$SNAPSHOT_DOC" ] \
    || die 3 "$who: $snapshot_file exists but could not be read as JSON, though start already wrote it. Repair or remove it by hand before running this again."
}

# im_mtime <file>: the file's modification time in seconds since the epoch, or nothing. GNU stat
# first, then the BSD form macOS carries.
im_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }
# im_iso_of <seconds>: that time as an ISO 8601 UTC string, or nothing.
im_iso_of() { jq -rn --arg e "$1" '$e | tonumber | todate' 2>/dev/null; }

# The tests a repair of one row makes stale (gap row 258). `tests-freeze` compares each red run
# with its test file, so a repair makes stale every red in each file that holds one of the row's
# tests. $tests holds one entry per test and row key, {name, path, key, red}. The key is a
# criterion id, or the order id for a done-when test. `red` is false for a --locks-in test, which
# has no red run to go stale. The rejected-row freeze and the retake brief both call it.
RED_AGAIN_JQ='def red_again($tests; $key):
  ([ $tests[] | select(.key == $key) | .path ]) as $files
  | [ $tests[] | select(.red and (.path as $p | $files | index($p))) | .name ] | unique;
'

# tf_record_confirmed <ledger file> <ledger doc> <unit id> <rows>: puts the confirmed rows among
# <rows> on the order's ledger entry as rowsConfirmed, with their notes, and replaces what an earlier
# refusal put there. A refused freeze calls it, because a repair round's checker judges only the rows
# put to it and writes the same verdict file (gap row 259). A model's row takes its note from that
# verdict file when the file confirms the row, so the note is the checker's own and not a copy.
# recordedAt is the file's time when that is earlier than now: an edit after the checker read the
# test and before this freeze is then seen as a change. Sets TF_CONFIRMED_DOC to the document
# written, and TF_CARRY_NEXT to a sentence naming the rows recorded, or to nothing.
tf_record_confirmed() {
  local check_file check_doc='{}' check_epoch at
  check_file="$(dirname -- "$1")/row-check-$3.json"
  at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [ -f "$check_file" ]; then
    check_doc="$(jq -c '.' "$check_file" 2>/dev/null)"
    [ -n "$check_doc" ] \
      || die 3 "tests-freeze: $check_file exists but could not be read as JSON. The confirmed rows are recorded with the checker's note from it. Repair or remove it by hand before running this again."
    check_epoch="$(im_mtime "$check_file")"
    [ -n "$check_epoch" ] || die 3 "tests-freeze: could not read when $check_file was written."
    [ "$check_epoch" -lt "$(date -u +%s)" ] && at="$(im_iso_of "$check_epoch")"
  fi
  TF_CONFIRMED_DOC="$(printf '%s' "$2" | jq -c --arg id "$3" --argjson rows "$4" --argjson check "$check_doc" \
      --arg at "$at" '
      [ $rows[] | select(.verdict == "confirmed") | .criterion as $c
        | ([ ($check.rows // [])[] | select(.criterion == $c and .verdict == "confirmed") | .note ][0]) as $own
        | {criterion, judgedBy, note: (if .judgedBy == "model" and $own != null then $own else .note end),
           recordedAt: $at} ] as $kept
      | .orders = (.orders | map(if .id != $id then .
          elif $kept == [] then del(.rowsConfirmed) else .rowsConfirmed = $kept end))' 2>/dev/null)"
  [ -n "$TF_CONFIRMED_DOC" ] \
    || die 3 "tests-freeze: the ledger update for $3 failed. When $check_file exists, it must be in the checker's shape, {\"rows\": [{\"criterion\", \"verdict\", \"note\"}]}."
  write_atomic "$1" "$TF_CONFIRMED_DOC"
  TF_CARRY_NEXT="$(printf '%s' "$TF_CONFIRMED_DOC" | jq -r --arg id "$3" '
      [ (.orders // [])[] | select(.id == $id) | (.rowsConfirmed // [])[] | .criterion ]
      | if length == 0 then "" else " The ledger holds the confirmed rows \(join(", ")), and the next freeze carries them with no --row." end')"
}

do_tests_brief() {
  [ "$#" -ge 2 ] || die 3 "tests-brief: a task folder and a unit id are required"
  [ "$#" -le 2 ] || die 3 "tests-brief: unrecognized extra argument: $3"
  local resolve_rc unit_id="$2"
  TASK_PATH="$(resolve_task_folder "$1" "tests-brief")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  IMPL_DIR="$TASK_PATH/implementation"

  tt_load_snapshot "tests-brief"
  local ledger_file="$IMPL_DIR/ledger.json"
  [ -f "$ledger_file" ] \
    || die 3 "tests-brief: $ledger_file not found, though $IMPL_DIR/snapshot.json exists. A snapshot with no ledger beside it is not a supported state; run start again."
  local ledger_doc
  ledger_doc="$(jq -c '.' "$ledger_file" 2>/dev/null)"
  [ -n "$ledger_doc" ] \
    || die 3 "tests-brief: $ledger_file exists but could not be read as JSON. Repair or remove it by hand before running this again."

  tt_load_unit_and_criteria "$SNAPSHOT_DOC" "$unit_id" "tests-brief"

  # --- exit 23: every dependency needs a completion record before its interface is handed over ----
  # dep_interface is declared here and not inside the loop below. zsh prints a parameter when
  # `local` names one that already exists in the same scope, so a `local` inside a loop body writes
  # the previous round's value to standard output on every round after the first (trap 5 in this
  # file's own header).
  local depends_json dep_count i dep_id dep_entry dep_step dep_interface dependency_interfaces_json='[]'
  local dep_record_file dep_record_text dependency_information_json='[]'
  depends_json="$(printf '%s' "$UNIT_JSON" | jq -c '.dependsOn // []')"
  dep_count="$(printf '%s' "$depends_json" | jq 'length')"
  i=0
  while [ "$i" -lt "$dep_count" ]; do
    dep_id="$(printf '%s' "$depends_json" | jq -r --argjson i "$i" '.[$i]')"
    dep_entry="$(printf '%s' "$ledger_doc" | jq -c --arg id "$dep_id" \
      '(.orders // []) | map(select(.id == $id)) | .[0] // null')"
    [ "$dep_entry" != "null" ] \
      || die 3 "tests-brief: $unit_id depends on $dep_id, which has no entry in $ledger_file, though start opens one entry per snapshot work order."
    dep_step="$(printf '%s' "$dep_entry" | jq -r '.lastStep // "not started"')"
    if [ "$dep_step" = "closed" ]; then
      dep_interface="$(printf '%s' "$SNAPSHOT_DOC" | jq -r --arg id "$dep_id" \
        '(.workOrders // []) | map(select(.id == $id)) | .[0].interface // ""')"
      # Both texts, each labelled. The declaration is what design promised; the record is what the
      # builder says it exposed, and the two can differ. The next order writes its tests and its
      # code against the record where one exists, which is what build.md and the two agent files
      # already say and what neither brief carried.
      dep_record_file="$IMPL_DIR/build-$dep_id.json"
      dep_record_text=""
      if [ -f "$dep_record_file" ]; then
        dep_record_text="$(jq -r '.interfaceRecord // ""' "$dep_record_file" 2>/dev/null)"
      fi
      dependency_interfaces_json="$(printf '%s' "$dependency_interfaces_json" | jq -c \
        --arg id "$dep_id" --arg iface "$dep_interface" --arg rec "$dep_record_text" '
        . + [ {id: $id, declaredInterface: $iface, interface: $iface}
              + (if $rec == "" then {} else {interfaceRecord: $rec} end) ]')"
      # What the dependency's reviewer recorded for the person and not as a finding, carried the
      # same way the interface record is (live-run row 103).
      dependency_information_json="$(im_dependency_information "$dependency_information_json" "$dep_id")"
    else
      die 23 "tests-brief: $unit_id depends on $dep_id, which has no completion record ($ledger_file records its last step as $dep_step), so its interface record does not exist yet."
    fi
    i=$((i + 1))
  done

  # The test-execution recipe path, from the preconditions record, for the runner and the
  # `failure_signal` markers the author reads a red against. The author is denied the catalog, and
  # the test-authoring recipe only points at this one (live-run row 107). The first framework whose
  # lookup resolved; null, and the summary says so, when none did.
  local test_recipe_path=""
  if [ -f "$IMPL_DIR/preconditions.json" ]; then
    test_recipe_path="$(jq -r '[ (.frameworks // [])[]
        | select(.lookup == "resolved" and (.recipePath // "") != "") | .recipePath ] | .[0] // ""' \
      "$IMPL_DIR/preconditions.json" 2>/dev/null)"
  fi

  # --- exit 24: an owned, machine-verified criterion with no declared test at all ------------------
  local unit_tests_count owned_json owned_machine_unmet
  unit_tests_count="$(printf '%s' "$UNIT_JSON" | jq '(.tests // []) | length')"
  if [ "$unit_tests_count" -eq 0 ]; then
    owned_json="$(printf '%s' "$UNIT_JSON" | jq -c '.criteriaOwned // []')"
    owned_machine_unmet="$(printf '%s' "$CRITERIA_JSON" | jq -r --argjson owned "$owned_json" '
        [ .[] | select(.verifiedBy == "machine") | select(.id as $i | $owned | index($i) != null) | .id ]
        | join(", ")
      ')"
    [ -z "$owned_machine_unmet" ] \
      || die 24 "tests-brief: $unit_id owns $owned_machine_unmet, whose verifiedBy is machine, and declares no test in its own tests field."
  fi

  # --- assemble the brief: these fixed keys, then the optional ones: treeHolds, retake, rowsRejected, absenceCandidates ---
  local non_goal_ids_json non_goals_out unit_out
  non_goal_ids_json="$(printf '%s' "$UNIT_JSON" | jq -c '.nonGoals // []')"
  non_goals_out="$(printf '%s' "$SNAPSHOT_DOC" | jq -c --argjson ids "$non_goal_ids_json" \
    '(.alignment.nonGoals // []) | map(select(.id as $i | $ids | index($i) != null))')"
  local criteria_out
  criteria_out="$(printf '%s' "$CRITERIA_JSON" | jq -c \
    '[ .[] | {id, text, verification, verifiedBy} ]')"
  # ownedFiles names the test file design chose, so the author writes there (gap row 249).
  unit_out="$(printf '%s' "$UNIT_JSON" | jq -c \
    '{id, title, tests: (.tests // []), doneWhen: (.doneWhen // []), criteriaOwned: (.criteriaOwned // []),
      ownedFiles: (.ownedFiles // []), interface: (.interface // ""), diffBudget: (.diffBudget // "")}')"

  # `reuses` is the existing code design's dispose recorded on this order, with the interface the
  # design stage read from it. It sits beside the dependency interfaces because it answers the same
  # question for code that is no work order: the test author may not open production source, and a
  # brief that carried only work orders left it reading a reused module (live-run row 69). An order
  # disposed before the field existed has none, and the brief says so.
  local reuses_out
  reuses_out="$(printf '%s' "$UNIT_JSON" | jq -c '.reuses // []')"

  # Another key, only when a done-when clause carries a negation word: the author decides what to
  # test, and was never told an absence goes to review instead (gap row 209). A negation word is
  # the floor a script can read, so the author still judges each clause by references/tests.md.
  local absence_out
  absence_out="$(printf '%s' "$UNIT_JSON" | jq -c "$DENIES_JQ"'
    [ (.doneWhen // [])[] | select(type == "string" and denies) ]
    | if length == 0 then null
      else {clauses: .,
            whatToDo: "Each clause here carries a negation word. Return one that asserts an absence, verbatim, and write no test for it. The freeze routes it to review with --absence. A clause that states a behaviour still takes a test."} end')"

  # A ninth thing, only after a restart or a retake left this order's build and fix commits on the
  # branch: a test that passes on arrival is suspect, and the author is told rather than left to
  # find it (live-run row 94).
  local tree_holds_json
  rv_load_codepath "tests-brief"
  tree_holds_json="$(rs_carried_commits_in_head "$TASK_PATH" "$RV_CODEPATH" "$unit_id" "$ledger_doc" | jq -c '
    if length == 0 then null
    else {commits: [ .[] | select(has("missing") | not) | {kind, commit} ],
          note: "the tree holds these build and fix commits of this unit from an earlier attempt, which a restart or a retake sent back to the tests step, so a test that passes on arrival is suspect",
          greenOnArrival: "A test of this unit that arrives green may pass because of one of the build or fix commits above. Give that commit as the --locks-in reason, written commit:<id>. Read no source to decide it."}
      + (if any(.[]; has("missing")) then
          {notFound: [ .[] | select(has("missing")) | {kind, commit, why: .missing} ],
           notFoundNote: "A rebase left no copy of these commits on the branch that can be cited. If a test arrives green on this code, report the test green on arrival and name that commit. A person decides."}
         else {} end) end')"

  # A tenth thing, only while a retake is still unanswered: a person ruled one frozen test wrong
  # at `verify-record`, and `retake-tests` sent the order back to this step (live-run row 142).
  # The author is dispatched again to correct that one test, and nothing in the first-run brief
  # says which, or that the order already has frozen tests. So the brief carries the ruled
  # finding and the frozen rows, and the dispatch stays the role, the run mode and the paths.
  # The review record holding the finding moved with the rest, so it is read from the retake's
  # own `movedTo` and never from a guessed folder name. A record a person removed is absent, not
  # fatal: the key says which one is gone and carries what is left.
  local retake_json='null' retake_entry retake_review_file retake_finding_json retake_frozen_json
  local retake_absent_json='[]'
  if [ "$(im_retake_pending "$ledger_doc" "$IMPL_DIR" "$unit_id")" = "true" ]; then
    retake_entry="$(printf '%s' "$ledger_doc" | jq -c --arg id "$unit_id" \
      '(.orders // []) | map(select(.id == $id)) | .[0].retakes | last')"
    retake_review_file="$(printf '%s' "$retake_entry" | jq -r '.movedTo')/review-$unit_id.json"
    retake_finding_json='null'
    if [ -f "$retake_review_file" ]; then
      # `linkedTo` names the criterion the finding is about, and the frozen rows below are keyed by
      # criterion and hold each test's path and name. It is the join from the finding to the tests
      # to correct, so the author reads which rows the ruling reaches instead of guessing.
      retake_finding_json="$(jq -c --arg f "$(printf '%s' "$retake_entry" | jq -r '.finding')" '
        [ (.findings // [])[] | select(.id == $f) ] | .[0] // null
        | if . == null then null
          else {id, linkedTo: (.linkedTo // null), severity: (.severity // null),
                file: (.file // null), lines: (.lines // null),
                evidence: (.evidence // null), ruling: (.ruling // null),
                rulingReason: (.rulingReason // null)} end' "$retake_review_file" 2>/dev/null)"
      [ -n "$retake_finding_json" ] || retake_finding_json='null'
    fi
    if [ "$retake_finding_json" = "null" ]; then
      retake_absent_json="$(printf '%s' "$retake_absent_json" | jq -c --arg p "$retake_review_file" \
        '. + ["the review record at \($p) does not hold the ruled finding, so its evidence and its ruling reason are not here"]')"
    fi
    retake_frozen_json="$(jq -c '{testGlobs: (.testGlobs // []), rows: (.rows // [])}' \
      "$IMPL_DIR/tests-$unit_id.json" 2>/dev/null)"
    if [ -z "$retake_frozen_json" ]; then
      retake_frozen_json='null'
      retake_absent_json="$(printf '%s' "$retake_absent_json" | jq -c --arg p "$IMPL_DIR/tests-$unit_id.json" \
        '. + ["the frozen test record at \($p) is not there or could not be read, so the rows this order already has are not here"]')"
    fi
    # A correction edits a test file just as a repair does, so the finding's criterion names the
    # reds it makes stale the same way (gap row 258). No criterion, or no frozen rows, names none.
    retake_json="$(jq -cn --argjson entry "$retake_entry" --argjson finding "$retake_finding_json" \
      --argjson frozenTests "$retake_frozen_json" --argjson absent "$retake_absent_json" \
      --arg reviewRecord "$retake_review_file" --arg unit "$unit_id" "$RED_AGAIN_JQ"'
      ([ ($frozenTests.rows // [])[] | (.criterion // $unit) as $k | (.tests // [])[]
         | {name, path, key: $k, red: has("red")} ]) as $entries
      | (if ($finding.linkedTo // null) == null then [] else red_again($entries; $finding.linkedTo) end) as $again
      | {at: $entry.at, finding: $finding, reviewRecord: $reviewRecord, frozenTests: $frozenTests,
         absent: $absent, redAgain: $again,
         whatToDo: ("This order already has frozen tests. Correct the tests the finding names, and leave every other frozen row alone. Write no new test for a criterion the frozen rows already cover."
                    + (if ($again | length) == 0 then ""
                       else " Then run again each test that redAgain names, and write each new run. Each shares a test file with a corrected test, so its earlier red is older than that file." end))}')"
    [ -n "$retake_json" ] || die 3 "tests-brief: could not assemble the retake key for $unit_id."
  fi

  # Another key, only while a row a person rejected at the checkpoint stands: `tests-freeze`
  # recorded it on the ledger with the person's words and the checker's note (gap row 218).
  local rows_rejected_json
  rows_rejected_json="$(printf '%s' "$ledger_doc" | jq -c --arg id "$unit_id" '
    ([ (.orders // [])[] | select(.id == $id) ][0].rowsRejected // [])
    | if length == 0 then null
      else ([ .[] | (.redAgain // [])[] ] | unique) as $again
        | {rows: ., redAgain: $again,
           whatToDo: ("A person rejected these rows at the checkpoint. Repair the tests of these rows only, from the person'"'"'s words and the checker'"'"'s note, and leave every other test alone."
                      + (if ($again | length) == 0 then ""
                         else " Then run again each test that redAgain names, and write each new red run. Each shares a test file with a repaired test, so its earlier red is older than that file." end))} end')"

  # The brief is a file the dispatch names, never text printed through this conversation. It
  # carries the criteria, the non-goals and every dependency's interface record, and printing it
  # would spend the orchestrator's own context on words only the test author reads.
  # `roundStartedAt` is when this order's test round began, and `tests-freeze` refuses a red run
  # older than it (exit 109). A brief written again in the same round, for a retake or a rejected
  # row, keeps the first time, because a test file the repair leaves alone keeps its red runs. A
  # red older than its own test file still refuses, so each test in an edited file runs again
  # (gap row 258). The round is the same only while the order and its criteria are. A restart
  # moves the brief aside, so the next brief starts a new round.
  local brief_file brief_json round_started_at=""
  brief_file="$IMPL_DIR/brief-$unit_id-tests.json"
  if [ -f "$brief_file" ] && [ "$(jq -c --argjson unit "$unit_out" --argjson criteria "$criteria_out" \
      '.unit == $unit and .criteria == $criteria' "$brief_file" 2>/dev/null)" = "true" ]; then
    round_started_at="$(jq -r '.roundStartedAt // empty' "$brief_file" 2>/dev/null)"
    [ -n "$round_started_at" ] || round_started_at="$(im_iso_of "$(im_mtime "$brief_file")")"
  fi
  [ -n "$round_started_at" ] || round_started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  brief_json="$(jq -n --argjson unit "$unit_out" --argjson criteria "$criteria_out" \
        --argjson nonGoals "$non_goals_out" --argjson dependencyInterfaces "$dependency_interfaces_json" \
        --argjson dependencyInformation "$dependency_information_json" \
        --argjson reuses "$reuses_out" --argjson treeHolds "$tree_holds_json" \
        --argjson retake "$retake_json" --argjson absenceCandidates "$absence_out" \
        --argjson rowsRejected "$rows_rejected_json" \
        --arg testRecipePath "$test_recipe_path" --arg roundStartedAt "$round_started_at" \
        --argjson playbooksPath "$(playbooks_path_json "$TASK_PATH")" --arg worktree "$RV_CODEPATH" \
        --arg reportPath "$IMPL_DIR/answers-$unit_id-tests.md" \
    '{unit: $unit, criteria: $criteria, nonGoals: $nonGoals, dependencyInterfaces: $dependencyInterfaces,
      dependencyInformation: $dependencyInformation, reuses: $reuses,
      testRecipePath: (if $testRecipePath == "" then null else $testRecipePath end),
      playbooksPath: $playbooksPath, roundStartedAt: $roundStartedAt, reportPath: $reportPath}
     | if $treeHolds == null then . else .treeHolds = $treeHolds end
     | if $retake == null then . else .retake = $retake end
     | if $rowsRejected == null then . else .rowsRejected = $rowsRejected end
     | if $absenceCandidates == null then . else .absenceCandidates = $absenceCandidates end
     | .worktree = $worktree')"
  [ -n "$brief_json" ] || die 3 "tests-brief: could not assemble the brief for $unit_id."
  write_atomic "$brief_file" "$brief_json"
  im_print_summary "tests-brief" "$(printf '%s' "$brief_json" | jq -c --arg brief "$brief_file" '
    {order: .unit.id,
     brief: $brief,
     worktree: .worktree,
     reportPath: .reportPath,
     criteria: ([ .criteria[] | .id + " (" + .verifiedBy + ")" ]),
     nonGoals: (.nonGoals | length),
     declaredTests: (.unit.tests | length),
     dependencyInterfaces: ([ .dependencyInterfaces[] | .id + (if has("interfaceRecord") then " (record)" else " (declared only)" end) ]),
     dependencyInformation: (.dependencyInformation | length),
     testRecipePath: (.testRecipePath // "none: no framework has a resolved test-execution recipe in preconditions.json, so the author has no runner to read"),
     reuses: (.reuses | if length == 0 then null else length end),
     treeHolds: (if has("treeHolds") then ([ .treeHolds.commits[] | .commit[0:7] + " " + .kind ]) else null end),
     retake: (if has("retake") then
                ((.retake.finding.id // "the ruled finding") + ": "
                 + (.retake.finding.rulingReason // "the ruling reason is not on record")
                 + " | correct the tests it names and leave the other frozen rows alone")
              else null end),
     rowsRejected: (if has("rowsRejected") then ([ .rowsRejected.rows[] | .criterion ] | join(", ")) else null end),
     absenceCandidates: (if has("absenceCandidates") then (.absenceCandidates.clauses | length) else null end),
     next: "dispatch test-author with the brief path and the test-authoring recipe path, then tests-freeze"}
    | if .treeHolds == null then del(.treeHolds) else . end
    | if .absenceCandidates == null then del(.absenceCandidates) else . end
    | if .retake == null then del(.retake) else . end
    | if .rowsRejected == null then del(.rowsRejected) else . end')"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# tests-freeze helpers. Every parsing helper reads its raw multi-line argument through a heredoc,
# never a pipe: a pipe puts the loop in a subshell, where a die below would only end the subshell,
# and the exit code this whole file promises for that die would never reach the caller.
# ------------------------------------------------------------------------------------------------

# True when test name $1 ends with every criterion id in comma list $2, chained from the right: the
# last-listed id must be the name's own trailing characters, the id before it must trail what is
# left once that is stripped, and so on. A test naming only one criterion is the common case and
# this degrades to it directly. The leading letter of an id may appear as c or C in the name, since
# a test method's own naming convention may capitalise it; every other character, all digits, must
# match exactly, which is also what keeps `c3` from matching a trailing `c30`: the last two
# characters of `c30` are `3` and `0`, never equal to the two characters of `c3`. Prints nothing;
# returns 1 on the first id that does not fit and 0 once every id has been stripped from the end.
# Never uses `for x in $unquoted` or `set -- $unquoted`: zsh does not word-split those by default,
# so every list here is walked by peeling one comma-separated token off the front instead.
tf_name_carries() {
  # A `local` statement's own assignment words are all evaluated before any of them takes effect
  # (true in bash and zsh alike), so declaring and reading a value back in the same statement (as
  # `remaining="$name"` would be here) is never safe; and zsh separately reports a variable declared
  # and initialised to an empty string in the very same `local` statement as "parameter not set" on
  # its first `-z`/`-n` test under this file's own `set -u` and `KSH_ARRAYS` (Honesty: proven while
  # building tf_segments_match). Every local below is therefore declared bare, then assigned.
  local name csv remaining reversed id first rest lower upper
  name="$1"
  csv="$2"
  remaining="$name"
  reversed=""
  while [ -n "$csv" ]; do
    case "$csv" in
      *,*) id="${csv%%,*}"; csv="${csv#*,}" ;;
      *)   id="$csv"; csv="" ;;
    esac
    [ -n "$id" ] || continue
    reversed="$id${reversed:+,$reversed}"
  done
  while [ -n "$reversed" ]; do
    case "$reversed" in
      *,*) id="${reversed%%,*}"; reversed="${reversed#*,}" ;;
      *)   id="$reversed"; reversed="" ;;
    esac
    lower="$id"
    first="$(printf '%s' "$id" | cut -c1 | tr '[:lower:]' '[:upper:]')"
    rest="$(printf '%s' "$id" | cut -c2-)"
    upper="${first}${rest}"
    case "$remaining" in
      *"$lower") remaining="${remaining%$lower}" ;;
      *"$upper") remaining="${remaining%$upper}" ;;
      *) return 1 ;;
    esac
  done
  return 0
}

# Parses --test values, one per line of $1 (`<path>::<test name>=<criterion id>[,<criterion
# id>...]`), appending one `{path, name, criteria}` JSON object per line to file $2. `criteria` is
# always a JSON array, however many ids the line named.
tf_parse_tests() {
  local raw="$1" out="$2" line p rest name csv ids_json
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      *"::"*) : ;;
      *) die 3 "tests-freeze: --test value has no '::' separating the path from the test name: $line" ;;
    esac
    p="${line%%::*}"
    rest="${line#*::}"
    case "$rest" in
      *"="*) : ;;
      *) die 3 "tests-freeze: --test value has no '=' separating the test name from its criteria: $line" ;;
    esac
    name="${rest%%=*}"
    csv="${rest#*=}"
    [ -n "$p" ]    || die 3 "tests-freeze: --test value has an empty path: $line"
    [ -n "$name" ] || die 3 "tests-freeze: --test value has an empty test name: $line"
    [ -n "$csv" ]  || die 3 "tests-freeze: --test value names no criterion: $line"
    ids_json="$(printf '%s' "$csv" | tr ',' '\n' | jq -R -s 'split("\n") | map(select(length>0))')"
    jq -n --arg path "$p" --arg name "$name" --argjson criteria "$ids_json" \
      '{path: $path, name: $name, criteria: $criteria}' >>"$out" \
      || die 3 "tests-freeze: could not record the --test row for $name"
  done <<TF_EOF
$raw
TF_EOF
}

# Parses --red values, one per line of $1 (`<test name>=<path>`), appending one `{name, path}` JSON
# object per line to file $2.
tf_parse_reds() {
  local raw="$1" out="$2" line name p
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      *"="*) : ;;
      *) die 3 "tests-freeze: --red value has no '=' separating the test name from the file path: $line" ;;
    esac
    name="${line%%=*}"
    p="${line#*=}"
    [ -n "$name" ] || die 3 "tests-freeze: --red value has an empty test name: $line"
    [ -n "$p" ]    || die 3 "tests-freeze: --red value has an empty file path: $line"
    jq -n --arg name "$name" --arg path "$p" '{name: $name, path: $path}' >>"$out" \
      || die 3 "tests-freeze: could not record the --red row for $name"
  done <<TF_EOF
$raw
TF_EOF
}

# Parses --checklist values, one per line of $1 (`<criterion id>=<verification text>`), appending
# one `{id, text}` JSON object per line to file $2.
tf_parse_checklists() {
  local raw="$1" out="$2" line id text
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      *"="*) : ;;
      *) die 3 "tests-freeze: --checklist value has no '=' separating the criterion id from the verification text: $line" ;;
    esac
    id="${line%%=*}"
    text="${line#*=}"
    [ -n "$id" ]   || die 3 "tests-freeze: --checklist value has an empty criterion id: $line"
    [ -n "$text" ] || die 3 "tests-freeze: --checklist value has empty verification text: $line"
    jq -n --arg id "$id" --arg text "$text" '{id: $id, text: $text}' >>"$out" \
      || die 3 "tests-freeze: could not record the --checklist row for $id"
  done <<TF_EOF
$raw
TF_EOF
}

# Parses --row values, one per line of $1
# (`<criterion id>=<confirmed|rejected>::<person|model>::<note>`), appending one
# `{criterion, verdict, judgedBy, note}` JSON object per line to file $2. The three parts after the
# id are split on "::" from the left, so a note holding "::" of its own keeps it: only the first two
# separators are read as separators, and everything after them is the note.
tf_parse_rows() {
  local raw="$1" out="$2" line id rest verdict judged note
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      *"="*) : ;;
      *) die 3 "tests-freeze: --row value has no '=' separating the criterion id from the verdict: $line" ;;
    esac
    id="${line%%=*}"
    rest="${line#*=}"
    case "$rest" in
      *"::"*) : ;;
      *) die 3 "tests-freeze: --row value has no '::' separating the verdict from who judged it: $line" ;;
    esac
    verdict="${rest%%::*}"
    rest="${rest#*::}"
    case "$rest" in
      *"::"*) : ;;
      *) die 3 "tests-freeze: --row value has no '::' separating who judged it from the note: $line" ;;
    esac
    judged="${rest%%::*}"
    note="${rest#*::}"
    [ -n "$id" ] || die 3 "tests-freeze: --row value has an empty criterion id: $line"
    case "$verdict" in
      confirmed|rejected) ;;
      *) die 3 "tests-freeze: --row value answers '$verdict'. The two answers are confirmed and rejected: $line" ;;
    esac
    case "$judged" in
      person|model) ;;
      *) die 3 "tests-freeze: --row value says '$judged' judged it. The two words are person and model: $line" ;;
    esac
    [ -n "$note" ] || die 3 "tests-freeze: --row value for $id carries no note. A verdict with nothing to read beside it is not a verdict."
    jq -n --arg id "$id" --arg v "$verdict" --arg j "$judged" --arg n "$note" \
      '{criterion: $id, verdict: $v, judgedBy: $j, note: $n}' >>"$out" \
      || die 3 "tests-freeze: could not record the --row for $id"
  done <<TF_EOF
$raw
TF_EOF
}

# Parses --green-on-arrival values, one per line of $1 (`<test name>=<reason>`), appending one
# `{name, reason}` JSON object per line to file $2. --locks-in has the same shape and passes $3.
tf_parse_goa() {
  local raw="$1" out="$2" flag="${3:---green-on-arrival}" line name reason
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      *"="*) : ;;
      *) die 3 "tests-freeze: $flag value has no '=' separating the test name from the reason: $line" ;;
    esac
    name="${line%%=*}"
    reason="${line#*=}"
    [ -n "$name" ]   || die 3 "tests-freeze: $flag value has an empty test name: $line"
    [ -n "$reason" ] || die 3 "tests-freeze: $flag value has an empty reason: $line"
    jq -n --arg name "$name" --arg reason "$reason" '{name: $name, reason: $reason}' >>"$out" \
      || die 3 "tests-freeze: could not record the $flag row for $name"
  done <<TF_EOF
$raw
TF_EOF
}

# Resolves --test path $1 against code root $2 (already canonical, no trailing slash), the way a
# recipe's own `## Test commands` rows are resolved: this step never carries a second, absolute
# copy of a path that belongs to the repository, for the same reason baseline.json's own `scope`
# field is repository-relative and not absolute (scripts/baseline-schema.json, `scope`). A frozen
# path must still mean the same file once the checkout moves. An absolute $1 is relativised against
# $2; anything else is taken as already relative to $2. Checked as a declared string only, the same
# bound the overlap check on ownedFiles already accepts (`start`'s own step 10 comment): this never
# resolves a symlink and never requires $1 to exist yet, which is what lets exit 26 tell "does not
# exist" apart from this. Prints one tab-separated result: `REL<TAB><path relative to $2>` on
# success, or `OUTSIDE<TAB><the absolute form>` when $1 names something outside $2 altogether.
tf_relativize_path() {
  local raw="$1" root="$2" abs rootlen
  case "$raw" in
    /*) abs="$raw" ;;
    *)  abs="$root/$raw" ;;
  esac
  if [ "$abs" = "$root" ]; then
    printf 'REL\t.'
    return 0
  fi
  rootlen=${#root}
  # zsh reads a bare name after the second ":" as a history-style modifier, not a length, unless it
  # is itself a "$"-expansion (Honesty: this script runs under both); bash accepts either form, so
  # every offset and length below is written as an explicit "$" or arithmetic expansion.
  if [ "${abs:0:$rootlen}" = "$root" ] && [ "${abs:$rootlen:1}" = "/" ]; then
    printf 'REL\t%s' "${abs:$((rootlen + 1))}"
    return 0
  fi
  printf 'OUTSIDE\t%s' "$abs"
}

# The frozen entries for the --test rows in $1 (each already carrying absPath and relPath), as one
# JSON array on stdout: path relative to codePath, name, sha256, and the red run from $2 or the
# locks-in reason from $3. One copy of this block, called once per criterion row and once for the
# doneWhen row. A die inside ends only the command substitution that called this, so each caller
# re-raises the status with `|| exit "$?"`.
tf_frozen_tests_of() {
  local names_json="$1" reds_json="$2" locks_json="$3"
  local ntests tj tpath trelpath tname tsha tredpath tredtext tredsig tlocks tests_out_tmp
  ntests="$(printf '%s' "$names_json" | jq 'length')"
  tests_out_tmp="$IMPL_DIR/.tests-freeze-rowtests.$$"
  : >"$tests_out_tmp"
  tj=0
  while [ "$tj" -lt "$ntests" ]; do
    tpath="$(printf '%s' "$names_json" | jq -r --argjson tj "$tj" '.[$tj].absPath')"
    tname="$(printf '%s' "$names_json" | jq -r --argjson tj "$tj" '.[$tj].name')"
    trelpath="$(printf '%s' "$names_json" | jq -r --argjson tj "$tj" '.[$tj].relPath')"
    tsha="$(tf_sha256_of "$tpath")"
    [ -n "$tsha" ] || die 3 "tests-freeze: could not compute a sha256 for $tpath"
    tredpath="$(printf '%s' "$reds_json" | jq -r --arg n "$tname" '[ .[] | select(.name == $n) ][0].path // empty')"
    tredtext="$(cat "$tredpath" 2>/dev/null)"
    tredsig="$(printf '%s' "$reds_json" | jq -r --arg n "$tname" '[ .[] | select(.name == $n) ][0].signal // empty')"
    tlocks="$(printf '%s' "$locks_json" | jq -r --arg n "$tname" '[ .[] | select(.name == $n) ][0].reason // empty')"
    # The record stores the path relative to codePath, never the absolute form: a frozen path
    # must still mean the same file once the checkout moves (see exit 36's own reasoning).
    jq -n --arg path "$trelpath" --arg name "$tname" --arg sha "$tsha" --arg red "$tredtext" --arg sig "$tredsig" --arg locks "$tlocks" \
      '{path: $path, name: $name, sha256: $sha}
       + (if $red == "" then {} else {red: $red, redSignal: $sig} end) + (if $locks == "" then {} else {locksIn: $locks} end)' >>"$tests_out_tmp" \
      || die 3 "tests-freeze: could not record the test row for $tname"
    tj=$((tj + 1))
  done
  jq -s '.' "$tests_out_tmp"
  rm -f "$tests_out_tmp"
}

do_tests_freeze() {
  local task_arg="" unit_id="" test_raw="" red_raw="" glob_raw="" checklist_raw="" goa_raw="" row_raw="" locks_raw=""
  local support_raw="" absence_raw="[]"
  local test_recipes="" unit_recipes=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --test)
        [ "$#" -ge 2 ] || die 3 "tests-freeze: --test needs <path>::<test name>=<criterion id>[,<criterion id>...], or =<unit id> for a test of the unit's own doneWhen"
        test_raw="$test_raw$2
"
        shift 2 ;;
      --red)
        [ "$#" -ge 2 ] || die 3 "tests-freeze: --red needs <test name>=<path to a file holding what the run printed>"
        red_raw="$red_raw$2
"
        shift 2 ;;
      --test-recipe)
        [ "$#" -ge 2 ] || die 3 "tests-freeze: --test-recipe needs <framework>=<path>"
        cr_recipe_pair "tests-freeze" "--test-recipe" "$2"
        test_recipes="$test_recipes$CR_PAIR
"
        shift 2 ;;
      --implement-recipe)
        [ "$#" -ge 2 ] || die 3 "tests-freeze: --implement-recipe needs <framework>=<path>"
        cr_recipe_pair "tests-freeze" "--implement-recipe" "$2"
        unit_recipes="$unit_recipes$CR_PAIR
"
        shift 2 ;;
      --test-glob)
        [ "$#" -ge 2 ] || die 3 "tests-freeze: --test-glob needs <glob>"
        glob_raw="$glob_raw$2
"
        shift 2 ;;
      --checklist)
        [ "$#" -ge 2 ] || die 3 "tests-freeze: --checklist needs <criterion id>=<verification text>"
        checklist_raw="$checklist_raw$2
"
        shift 2 ;;
      --row)
        [ "$#" -ge 2 ] || die 3 "tests-freeze: --row needs <criterion id or unit id>=<confirmed|rejected>::<person|model>::<note>"
        [ -n "$2" ] || die 3 "tests-freeze: --row was given an empty value."
        halt_refuse_separator "tests-freeze" "--row" "$2"
        row_raw="$row_raw$2
"
        shift 2 ;;
      --green-on-arrival)
        [ "$#" -ge 2 ] || die 3 "tests-freeze: --green-on-arrival needs <test name>=<reason>"
        goa_raw="$goa_raw$2
"
        shift 2 ;;
      --locks-in)
        [ "$#" -ge 2 ] || die 3 "tests-freeze: --locks-in needs <test name>=<the existing code that satisfies it>, or <test name>=commit:<id> naming this order's own build"
        locks_raw="$locks_raw$2
"
        shift 2 ;;
      --support)
        [ "$#" -ge 2 ] || die 3 "tests-freeze: --support needs <path relative to codePath>"
        [ -n "$2" ] || die 3 "tests-freeze: --support was given an empty path."
        support_raw="$support_raw$2
"
        shift 2 ;;
      --absence)
        [ "$#" -ge 2 ] || die 3 "tests-freeze: --absence needs one doneWhen clause of this order, verbatim"
        [ -n "$2" ] || die 3 "tests-freeze: --absence was given an empty clause."
        # Collected as a JSON array and not as one value per line, the way every other repeatable
        # flag here is. A doneWhen clause is prose design wrote, and nothing refuses a newline in
        # one (scripts/check-design.sh). Split on newlines, such a clause would match no doneWhen
        # entry and be refused for the wrong reason.
        absence_raw="$(printf '%s' "$absence_raw" | jq -c --arg t "$2" '. + [$t]')"
        [ -n "$absence_raw" ] || die 3 "tests-freeze: could not record the --absence clause."
        shift 2 ;;
      -*) die 3 "tests-freeze: unrecognized argument: $1" ;;
      *)
        if [ -z "$task_arg" ]; then
          task_arg="$1"
        elif [ -z "$unit_id" ]; then
          unit_id="$1"
        else
          die 3 "tests-freeze: unrecognized extra argument: $1"
        fi
        shift ;;
    esac
  done
  [ -n "$task_arg" ] || die 3 "tests-freeze: a task folder is required"
  [ -n "$unit_id" ]  || die 3 "tests-freeze: a unit id is required"

  local resolve_rc
  TASK_PATH="$(resolve_task_folder "$task_arg" "tests-freeze")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  IMPL_DIR="$TASK_PATH/implementation"

  tt_load_snapshot "tests-freeze"
  tt_load_unit_and_criteria "$SNAPSHOT_DOC" "$unit_id" "tests-freeze"

  # An order whose proof is gate freezes no test: its deliverable is exported configuration, and
  # its build runs the implement recipe's `## Configuration gate` lines as its own check (live-run
  # row 65). It still takes a --checklist for a person-verified criterion it serves or owns. An
  # order whose proof is record freezes no test either: its deliverable is a document in the task
  # folder, and its done-when row, judged here, is its checkpoint (nyc defect 17). An order whose
  # proof is observe freezes no test and no row: a model judges its done-when rows against its
  # surfaces after the build, so there is nothing to judge here (live-run row 104). An order whose
  # proof is confirm freezes no test and no row either: its task has no automated tests, and a
  # person confirms its done-when rows at review (gap row 196).
  # The frozen record carries the proof word itself, below, because a record holds the value. The
  # refusals and the guards read the check that takes this order's proof slot.
  local tf_proof
  tf_proof="$(printf '%s' "$UNIT_JSON" | jq -r '.proof // "tests"')"
  br_order_facts "$UNIT_JSON"
  if [ "$BR_ORDER_SLOT" = "configuration-gate" ] && [ -n "$test_raw" ]; then
    die 3 "tests-freeze: $unit_id is proved by the configuration gate and takes no --test. A test for exported configuration reads the YAML back and cannot fail for the right reason; the gate lines are its check."
  fi
  if [ "$BR_ORDER_SLOT" = "done-when" ] && [ -n "$test_raw" ]; then
    die 3 "tests-freeze: $unit_id is proved by its record and takes no --test. Its deliverable is a document in the task folder; its done-when row, --row $unit_id=..., is its checkpoint."
  fi
  if [ "$BR_ORDER_SLOT" = "observed" ] && [ -n "$test_raw" ]; then
    die 3 "tests-freeze: $unit_id is proved by a model's observation and takes no --test. A model judges its done-when rows against its surfaces in a browser after the build; nothing is frozen and nothing is judged here."
  fi
  if [ "$BR_ORDER_SLOT" = "confirm-at-review" ] && [ -n "$test_raw" ]; then
    die 3 "tests-freeze: $unit_id is confirmed by a person and takes no --test. Its task has no automated tests; a person confirms its done-when rows at review."
  fi

  # --- 81: an --absence routes one doneWhen clause to review, because no test can prove it --------
  # A done-when clause that asserts an absence cannot be watched failing. The tree is already in the
  # state the clause asserts, and making a test of it fail means adding the very thing the clause
  # forbids (live-run row 184). Such a clause is answered where it can be: at review, against the
  # task's own diff. The clause is recorded on the ledger, so a clause routed this way is visible
  # rather than silently untested.
  #
  # Two facts refuse, and they share one code because both say the flag names something that is not
  # an absence clause of this order. First, a clause the order's frozen doneWhen does not hold
  # verbatim: review judges the words design wrote, never a paraphrase the freeze was handed.
  # Second, a clause with no negation word, which asserts a presence and is proved by a test.
  # This route relaxes nothing else. Every --test still needs its red run or its --locks-in reason
  # (exit 33), and an order whose record would hold no row still refuses (exit 74).
  #
  # Sorted in one jq pass, and no clause is ever carried through a shell variable: a command
  # substitution strips the trailing newlines of whatever it reads, and a doneWhen clause is prose
  # nothing refuses a newline in. A clause the shell had reshaped would fail the verbatim match and
  # be refused for a cause that is not the real one. Only the three lists come back out, and the two
  # for the refusals are joined into a message and never matched on again.
  #
  # `denies` is a floor and not the whole rule: "the form shows no legacy field" carries `no` and a
  # test can watch it fail, so references/tests.md carries the judgement and this carries the
  # refusal a script can make. `denies` is DENIES_JQ, from scripts/lib/task-helpers.sh, which
  # the tests brief reads too.
  local absence_sorted absence_json absence_unknown absence_asserts
  absence_sorted="$(printf '%s' "$absence_raw" | jq -c \
    --argjson dw "$(printf '%s' "$UNIT_JSON" | jq -c '.doneWhen // []')" "$DENIES_JQ"'
    def known: . as $t | ($dw | index($t)) != null;
    . as $given
    | { routed: (reduce ($given[] | select(known) | select(denies)) as $t
                  ([]; if (index($t)) then . else . + [$t] end)),
        unknown: [ $given[] | select(known | not) ],
        asserts: [ $given[] | select(known) | select(denies | not) ] }')"
  [ -n "$absence_sorted" ] || die 3 "tests-freeze: the --absence clauses could not be read."
  absence_json="$(printf '%s' "$absence_sorted" | jq -c '.routed')"
  absence_unknown="$(printf '%s' "$absence_sorted" | jq -r '.unknown | join("; ")')"
  absence_asserts="$(printf '%s' "$absence_sorted" | jq -r '.asserts | join("; ")')"
  [ -z "$absence_unknown" ] \
    || die 81 "tests-freeze: these --absence clauses are not, verbatim, a doneWhen entry of $unit_id: $absence_unknown. Review judges the clause design wrote, so the flag carries the order's own words. Read the doneWhen in implementation/snapshot.json and pass one of its entries."
  [ -z "$absence_asserts" ] \
    || die 81 "tests-freeze: these --absence clauses carry no negation word, so each asserts a presence: $absence_asserts. An absence clause says the change added nothing of a named kind, and that is the only clause with no red run to watch. A clause asserting a presence is proved by a test that failed first."

  # --- 74: an order that serves and owns no criterion ---------------------------------------------
  # Every guard below iterates a per-criterion list, so an order with none passes all of them and
  # freezes a record with no test and no glob in it. The reference then proves nothing, and the
  # frozen-tests check later hashes nothing and answers met.
  [ "$(printf '%s' "$CRITERIA_IDS_JSON" | jq 'length')" -gt 0 ] \
    || die 74 "tests-freeze: $unit_id serves and owns no criterion, so there is nothing for a test to prove and nothing for this step to freeze. Design left this order with no criteriaServed and no criteriaOwned; repair the work order and close design again."

  # --- 76: a re-freeze after the order has already left the frozen state ---------------------------
  # A re-freeze rewinds lastStep and leaves attemptsUsed and the build record where they are, so the
  # order would rebuild with a spent counter and a record for tests that no longer exist.
  # The commit the record was frozen at when `retake-tests` last sent this order back, read here
  # with the step: the freeze after a retake finds HEAD past that commit, and 35 below lets it
  # through on this value alone (live-run row 110).
  local tf_prior_step tf_prior_ledger tf_retake_commit=""
  if [ -f "$IMPL_DIR/ledger.json" ]; then
    tf_prior_ledger="$(jq -c '.' "$IMPL_DIR/ledger.json" 2>/dev/null)"
    if [ -n "$tf_prior_ledger" ]; then
      tf_prior_step="$(printf '%s' "$tf_prior_ledger" | jq -r --arg id "$unit_id" \
        '[ (.orders // [])[] | select(.id == $id) ][0].lastStep // ""')"
      case "$tf_prior_step" in
        ""|null|tests-frozen) ;;
        *) die 76 "tests-freeze: $unit_id is at step $tf_prior_step, so it has already left tests-frozen. A second freeze rewinds the step and leaves the spent attempt counter and the stale build record where they are. Use restart when the design moved, retake-tests when a person ruled a frozen test wrong at verify-record; otherwise this order goes forward, not back." ;;
      esac
      tf_retake_commit="$(printf '%s' "$tf_prior_ledger" | jq -r --arg id "$unit_id" \
        '([ (.orders // [])[] | select(.id == $id) ][0].retakes // []) | last // {} | .freezeCommit // ""')"
    fi
  fi

  # --- turn every raw --flag value into JSON, through temporary files beside the implementation dir
  local tests_tmp reds_tmp checklists_tmp goa_tmp rows_meta_tmp locks_tmp
  tests_tmp="$IMPL_DIR/.tests-freeze-tests.$$"
  reds_tmp="$IMPL_DIR/.tests-freeze-reds.$$"
  checklists_tmp="$IMPL_DIR/.tests-freeze-checklists.$$"
  goa_tmp="$IMPL_DIR/.tests-freeze-goa.$$"
  rows_meta_tmp="$IMPL_DIR/.tests-freeze-rowmeta.$$"
  locks_tmp="$IMPL_DIR/.tests-freeze-locks.$$"
  : >"$tests_tmp"; : >"$reds_tmp"; : >"$checklists_tmp"; : >"$goa_tmp"; : >"$rows_meta_tmp"; : >"$locks_tmp"
  tf_parse_tests      "$test_raw"      "$tests_tmp"
  tf_parse_reds       "$red_raw"       "$reds_tmp"
  tf_parse_checklists "$checklist_raw" "$checklists_tmp"
  tf_parse_goa        "$goa_raw"       "$goa_tmp"
  tf_parse_goa        "$locks_raw"     "$locks_tmp" "--locks-in"
  tf_parse_rows       "$row_raw"       "$rows_meta_tmp"

  local tests_json reds_json checklists_json goa_json test_globs_json rows_meta_json locks_json
  tests_json="$(jq -s '.' "$tests_tmp")"
  reds_json="$(jq -s '.' "$reds_tmp")"
  checklists_json="$(jq -s '.' "$checklists_tmp")"
  goa_json="$(jq -s '.' "$goa_tmp")"
  rows_meta_json="$(jq -s '.' "$rows_meta_tmp")"
  locks_json="$(jq -s '.' "$locks_tmp")"
  rm -f "$tests_tmp" "$reds_tmp" "$checklists_tmp" "$goa_tmp" "$rows_meta_tmp" "$locks_tmp"
  test_globs_json="$(printf '%s' "$glob_raw" | jq -R -s 'split("\n") | map(select(length>0))')"

  # A --test whose value is this unit's own id proves the unit's doneWhen, not a criterion. A
  # supporting order serves criteria it cannot observe, because the thing they observe is built by
  # the owner later (live-run row 59), so its tests are frozen against what the order itself said
  # it would make true. Such a test carries no criterion, and the doneWhen row below judges it.
  tests_json="$(printf '%s' "$tests_json" | jq -c --arg unit "$unit_id" \
    'map(if .criteria == [$unit] then (.criteria = [] | .provesDoneWhen = true) else . end)')"
  local has_done_when_tests
  has_done_when_tests="$(printf '%s' "$tests_json" | jq 'any(.[]; .provesDoneWhen == true)')"

  # --- the task's own project, resolved the same way start and preconditions already resolve it --
  local codepath
  rv_load_codepath "tests-freeze"
  codepath="$RV_CODEPATH"
  local current_commit
  current_commit="$(git -C "$codepath" rev-parse HEAD 2>/dev/null)"
  [ -n "$current_commit" ] \
    || die 3 "tests-freeze: could not capture the current commit (git rev-parse HEAD failed in $codepath)."

  # --- 36: every --test path must resolve inside codePath, and is stored relative to it -----------
  local codepath_canon
  codepath_canon="$(cd "$codepath" 2>/dev/null && pwd -P)"
  [ -n "$codepath_canon" ] \
    || die 3 "tests-freeze: could not resolve $codepath to a canonical path, though it was already checked to be a directory."

  local norm_tmp norm_count nk raw_path row_json rel_result rel_kind rel_value abs_path outside_paths=""
  norm_tmp="$IMPL_DIR/.tests-freeze-norm.$$"
  : >"$norm_tmp"
  norm_count="$(printf '%s' "$tests_json" | jq 'length')"
  nk=0
  while [ "$nk" -lt "$norm_count" ]; do
    row_json="$(printf '%s' "$tests_json" | jq -c --argjson nk "$nk" '.[$nk]')"
    raw_path="$(printf '%s' "$row_json" | jq -r '.path')"
    rel_result="$(tf_relativize_path "$raw_path" "$codepath_canon")"
    rel_kind="$(printf '%s' "$rel_result" | cut -f1)"
    rel_value="$(printf '%s' "$rel_result" | cut -f2-)"
    if [ "$rel_kind" = "OUTSIDE" ]; then
      outside_paths="$outside_paths$raw_path, "
      abs_path="$rel_value"
      rel_value=""
    else
      abs_path="$codepath_canon/$rel_value"
    fi
    jq -c -n --argjson row "$row_json" --arg abs "$abs_path" --arg rel "$rel_value" \
      '$row + {absPath: $abs, relPath: $rel}' >>"$norm_tmp" \
      || die 3 "tests-freeze: could not record the resolved path for $raw_path"
    nk=$((nk + 1))
  done
  [ -z "$outside_paths" ] \
    || die 36 "tests-freeze: these --test paths are outside the code root $codepath_canon: ${outside_paths%, }"
  tests_json="$(jq -s '.' "$norm_tmp")"
  rm -f "$norm_tmp"

  # --- 26: every --test path must exist on disk ----------------------------------------------------
  local unique_paths missing_paths=""
  unique_paths="$(printf '%s' "$tests_json" | jq -r '[.[].absPath] | unique | .[]')"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ -f "$p" ] || missing_paths="$missing_paths$p, "
  done <<TF_EOF
$unique_paths
TF_EOF
  [ -z "$missing_paths" ] \
    || die 26 "tests-freeze: these --test paths do not exist on disk: ${missing_paths%, }"

  # --- 27: every --test path (relative to codePath) must match at least one --test-glob, under the
  # catalog's own `**` semantics -----------------------------------------------------------------
  local unique_rel_paths glob_count unmatched_paths="" matched gi g
  unique_rel_paths="$(printf '%s' "$tests_json" | jq -r '[.[].relPath] | unique | .[]')"
  glob_count="$(printf '%s' "$test_globs_json" | jq 'length')"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    matched=false
    gi=0
    while [ "$gi" -lt "$glob_count" ]; do
      g="$(printf '%s' "$test_globs_json" | jq -r --argjson gi "$gi" '.[$gi]')"
      tf_path_matches_catalog_glob "$p" "$g" && matched=true
      [ "$matched" = "true" ] && break
      gi=$((gi + 1))
    done
    [ "$matched" = "true" ] || unmatched_paths="$unmatched_paths$p, "
  done <<TF_EOF
$unique_rel_paths
TF_EOF
  [ -z "$unmatched_paths" ] \
    || die 27 "tests-freeze: these --test paths (relative to $codepath_canon) match none of the given --test-glob patterns: ${unmatched_paths%, }"

  # --- 27 also: every --test path must be a file this order owns. Design names the order's test
  # file, and a test written anywhere else sits in a file no order owns, which nothing saw before
  # review (gap row 249).
  local unowned_paths="" owned_list owned_tests="" o
  owned_list="$(printf '%s' "$UNIT_JSON" | jq -r '(.ownedFiles // [])[]')"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    matched=false
    while IFS= read -r o; do
      [ -n "$o" ] || continue
      tf_path_matches_catalog_glob "$p" "$o" && { matched=true; break; }
    done <<TF_EOF
$owned_list
TF_EOF
    [ "$matched" = "true" ] || unowned_paths="$unowned_paths$p, "
  done <<TF_EOF
$unique_rel_paths
TF_EOF
  if [ -n "$unowned_paths" ]; then
    while IFS= read -r o; do
      [ -n "$o" ] || continue
      gi=0
      while [ "$gi" -lt "$glob_count" ]; do
        g="$(printf '%s' "$test_globs_json" | jq -r --argjson gi "$gi" '.[$gi]')"
        tf_path_matches_catalog_glob "$o" "$g" && { owned_tests="$owned_tests$o, "; break; }
        gi=$((gi + 1))
      done
    done <<TF_EOF
$owned_list
TF_EOF
    if [ -n "$owned_tests" ]; then
      owned_tests="The test file design named for it is ${owned_tests%, }. Run dispatch-open with --resume and resume the test author: it writes the tests into that file and takes a new red run for each. Then freeze again. Do not move the tests here."
    else
      owned_tests="It owns no file a test glob matches, only $(printf '%s' "$owned_list" | paste -sd, - | sed 's/,/, /g'). If the tests belong where they are, design adds that file with add-owned-file and closes again."
    fi
    die 27 "tests-freeze: these --test paths are files $unit_id does not own: ${unowned_paths%, }. $owned_tests"
  fi

  # --- 89: a --support path is a base class or a fixture the author wrote beside the tests -------
  # It is resolved, checked and hashed the way a --test path is, and refused when it is missing
  # or when a test glob matches it: such a file is a test and belongs on --test (live-run row 90).
  # Outside codePath it shares exit 36, the same fact a --test path gets. One list, no name. A
  # path is resolved to its real place first, so `../` cannot read as inside the root and leave a
  # record naming a file git then refuses to commit.
  local support_tmp support_rel support_abs support_missing="" support_tests="" support_outside="" support_sha support_real
  support_tmp="$IMPL_DIR/.tests-freeze-support.$$"
  : >"$support_tmp"
  if [ -n "$support_raw" ]; then
    records_hash__resolve_sha256_cmd \
      || die 3 "tests-freeze: neither sha256sum nor 'shasum -a 256' was found on PATH"
  fi
  while IFS= read -r raw_path; do
    [ -n "$raw_path" ] || continue
    case "$raw_path" in /*) support_real="$raw_path" ;; *) support_real="$codepath_canon/$raw_path" ;; esac
    support_real="$(cd "$(dirname "$support_real")" 2>/dev/null && pwd -P)/$(basename "$support_real")"
    rel_result="$(tf_relativize_path "$support_real" "$codepath_canon")"
    rel_kind="$(printf '%s' "$rel_result" | cut -f1)"
    support_rel="$(printf '%s' "$rel_result" | cut -f2-)"
    if [ "$rel_kind" = "OUTSIDE" ]; then
      support_outside="$support_outside$raw_path, "
      continue
    fi
    support_abs="$codepath_canon/$support_rel"
    if [ ! -f "$support_abs" ]; then
      support_missing="$support_missing$support_rel, "
      continue
    fi
    matched=false
    gi=0
    while [ "$gi" -lt "$glob_count" ]; do
      g="$(printf '%s' "$test_globs_json" | jq -r --argjson gi "$gi" '.[$gi]')"
      tf_path_matches_catalog_glob "$support_rel" "$g" && matched=true
      [ "$matched" = "true" ] && break
      gi=$((gi + 1))
    done
    if [ "$matched" = "true" ]; then
      support_tests="$support_tests$support_rel, "
      continue
    fi
    support_sha="$(tf_sha256_of "$support_abs")"
    [ -n "$support_sha" ] || die 3 "tests-freeze: could not compute a sha256 for $support_abs"
    jq -n --arg p "$support_rel" --arg sha "$support_sha" '{path: $p, sha256: $sha}' >>"$support_tmp" \
      || die 3 "tests-freeze: could not record the support row for $support_rel"
  done <<TF_EOF
$support_raw
TF_EOF
  [ -z "$support_outside" ] \
    || { rm -f "$support_tmp"; die 36 "tests-freeze: these --support paths are outside the code root $codepath_canon: ${support_outside%, }"; }
  [ -z "$support_missing" ] \
    || { rm -f "$support_tmp"; die 89 "tests-freeze: these --support paths do not exist on disk (relative to $codepath_canon): ${support_missing%, }"; }
  [ -z "$support_tests" ] \
    || { rm -f "$support_tmp"; die 89 "tests-freeze: these --support paths match a --test-glob pattern, so each is a test and belongs on --test: ${support_tests%, }"; }
  local support_json
  support_json="$(jq -s 'unique_by(.path)' "$support_tmp")"
  rm -f "$support_tmp"

  # --- 28: a test name must carry, at its own end, the criterion id(s) it claims, or the unit's own
  # id when it proves the doneWhen. The same check either way: an order id is one more token the
  # name ends with, and the case rule for its first letter is the one a criterion id already gets.
  local test_rows_count ti name id_list bad_carry=""
  test_rows_count="$(printf '%s' "$tests_json" | jq 'length')"
  ti=0
  while [ "$ti" -lt "$test_rows_count" ]; do
    name="$(printf '%s' "$tests_json" | jq -r --argjson ti "$ti" '.[$ti].name')"
    id_list="$(printf '%s' "$tests_json" | jq -r --argjson ti "$ti" --arg unit "$unit_id" \
      'if .[$ti].provesDoneWhen == true then $unit else (.[$ti].criteria | join(",")) end')"
    tf_name_carries "$name" "$id_list" || bad_carry="$bad_carry$name (claims $id_list), "
    ti=$((ti + 1))
  done
  [ -z "$bad_carry" ] \
    || die 28 "tests-freeze: these test names do not carry, at the end, the criterion id they claim, or $unit_id for a test of its own doneWhen: ${bad_carry%, }"

  # --- 29: every machine-verified criterion the unit owns needs a --test row ----------------------
  # Owns, not serves. Exactly one order owns a criterion and most own none (ideal/design.md), and
  # the owner is the order whose tests can observe it. A served criterion's proof lives with its
  # owner, and this order's own tests are frozen against its doneWhen.
  local owned_ids_json missing_machine
  owned_ids_json="$(printf '%s' "$UNIT_JSON" | jq -c '.criteriaOwned // []')"
  missing_machine="$(jq -nr --argjson criteria "$CRITERIA_JSON" --argjson tests "$tests_json" --argjson owned "$owned_ids_json" '
      ($tests | map(.criteria) | add // []) as $named
      | [ $criteria[] | select(.verifiedBy == "machine") | .id as $cid
          | select(($owned | index($cid)) != null)
          | select(($named | index($cid)) == null) | $cid ]
      | join(", ")
    ')"
  [ -z "$missing_machine" ] || [ "$BR_ORDER_SLOT" != "order-tests" ] \
    || die 29 "tests-freeze: these machine-verified criteria $unit_id owns have no --test row naming them: $missing_machine"

  # --- 30: every person-verified criterion the unit serves or owns needs a --checklist row ---------
  local missing_person
  missing_person="$(jq -nr --argjson criteria "$CRITERIA_JSON" --argjson checklists "$checklists_json" '
      ($checklists | map(.id)) as $named
      | [ $criteria[] | select(.verifiedBy == "person") | .id as $cid
          | select(($named | index($cid)) == null) | $cid ]
      | join(", ")
    ')"
  [ -z "$missing_person" ] \
    || die 30 "tests-freeze: these person-verified criteria have no --checklist row: $missing_person"

  # --- 31: a --test must never name a criterion the unit does not serve or own ---------------------
  local bad_criteria
  bad_criteria="$(jq -nr --argjson allowed "$CRITERIA_IDS_JSON" --argjson tests "$tests_json" '
      ($tests | map(.criteria) | add // []) as $named
      | [ $named[] as $cid | select(($allowed | index($cid)) == null) | $cid ] | unique | join(", ")
    ')"
  [ -z "$bad_criteria" ] \
    || die 31 "tests-freeze: a --test names criteria $unit_id does not serve or own: $bad_criteria"

  # --- the run's own mode, read once: the row checks below and the rejected-row halt both use it ---
  # The mode is the task's own for this stage, the one producer clear-halt reads too, so a person
  # who sets the task interactive is heard at once (gap row 265). A ledger that is present and
  # unreadable refuses here rather than further down, because the rejected-row halt writes into it.
  # A ledger that is absent is a different fact, left to the steps below, which refuse on it by name.
  local tf_ledger_file tf_ledger_doc tf_run_mode
  tf_ledger_file="$IMPL_DIR/ledger.json"
  tf_ledger_doc=""
  if [ -f "$tf_ledger_file" ]; then
    tf_ledger_doc="$(jq -c '.' "$tf_ledger_file" 2>/dev/null)"
    [ -n "$tf_ledger_doc" ] \
      || die 3 "tests-freeze: $tf_ledger_file exists but could not be read as JSON. A rejected row halts the order in it. Repair or remove it by hand before running this again."
  fi
  tf_run_mode="$(task_run_mode "$TASK_PATH" implement)"

  # --- 64: a criterion whose frozen verifiedBy is neither word answers nothing ----------------------
  # Such a criterion needs no test (exit 29 reads machine), no checklist (exit 30 reads person) and
  # no row, so it would be frozen with nothing at all behind it. scripts/check-alignment.sh refuses
  # the value when scope closes, and scripts/check-design.sh refuses it again when design closes.
  # This is a third reading, against the frozen copy rather than the live file: a snapshot taken
  # before either check carried the rule still holds whatever it froze.
  local bad_kinds
  bad_kinds="$(printf '%s' "$CRITERIA_JSON" | jq -r '
      [ .[] | select((.verifiedBy // "") != "machine") | select((.verifiedBy // "") != "person")
        | .id + " (verifiedBy " + ((.verifiedBy // null) | tostring) + ")" ] | join(", ")')"
  [ -z "$bad_kinds" ] \
    || die 64 "tests-freeze: $unit_id serves or owns criteria whose verifiedBy is neither machine nor person: $bad_kinds. Such a criterion takes no test, no checklist and no row, so freezing it would record nothing at all. Fix the contract and close design again."

  # --- 70: a person's row is a claim only an attended run can make ---------------------------------
  # A model's row is accepted on both runs. The row-checker judges every row in both modes, and on
  # an attended run the person answers only a row it rejected. So `model` on an interactive run is
  # the common case, not a checker standing in for a person (live-run row 70).
  local wrong_judge
  if [ "$tf_run_mode" = "autonomous" ]; then
    wrong_judge="$(printf '%s' "$rows_meta_json" | jq -r '
        [ .[] | select(.judgedBy == "person") | .criterion ] | join(", ")')"
    [ -z "$wrong_judge" ] \
      || die 70 "tests-freeze: these rows say a person judged them, and this run is autonomous: $wrong_judge. No person is here to read a row, and a row recorded as a person's is one nobody can list again later. Nothing is written."
  fi

  # --- 64: the --row set and this order's tests must correspond, in all four ways ------------------
  # Rows follow the tests' claims. A machine-verified criterion a --test names needs exactly one
  # row: the checkpoint asks, per order, whether these tests observe the part of the verify clause
  # this order is responsible for. Every owned machine criterion is named, by exit 29 above; a
  # served one is named only when this order chose to claim part of it. A doneWhen test needs the
  # doneWhen row, keyed by the unit's own id, judged against the doneWhen text. A person-verified
  # criterion never gets a row, because it carries a checklist and completion is what confirms it
  # (ideal/implementation.md, "A criterion a person inspects has no tests").
  local rows_expected_json rows_missing rows_unknown rows_person rows_twice
  # A record order has no test, so the doneWhen row is the one row it owes: the rows are what
  # judge the deliverable, and the freeze is where they are judged (nyc defect 17).
  rows_expected_json="$(jq -nc --argjson criteria "$CRITERIA_JSON" --argjson tests "$tests_json" \
      --arg unit "$unit_id" --argjson dw "$has_done_when_tests" --arg slot "$BR_ORDER_SLOT" '
      ($tests | map(.criteria) | add // []) as $named
      | [ $criteria[] | select(.verifiedBy == "machine") | .id as $cid | select(($named | index($cid)) != null) | $cid ]
        + (if $dw or $slot == "done-when" then [$unit] else [] end)
    ')"
  # Each routed clause is a row of its own, keyed <unit>:absence:<n>, n its doneWhen row counted
  # from 1. The checker asks whether a test could prove it, before the freeze rather than at the
  # task review (gap row 273). This holds on every proof kind, so br_order_needs gives every kind
  # the row-checker.
  rows_expected_json="$(printf '%s' "$rows_expected_json" | jq -c --argjson routed "$absence_json" \
      --argjson dw "$(printf '%s' "$UNIT_JSON" | jq -c '.doneWhen // []')" --arg unit "$unit_id" '
      . + [ $routed[] as $t | $unit + ":absence:" + (($dw | index($t)) + 1 | tostring) ]')"
  [ -n "$rows_expected_json" ] || die 3 "tests-freeze: could not list the rows of $unit_id's routed clauses."
  # One entry per test and row key, {name, path, key, red}: what red_again reads, and the files
  # each row's tests sit in.
  local tf_red_entries
  tf_red_entries="$(jq -nc --argjson tests "$tests_json" --argjson reds "$reds_json" --arg unit "$unit_id" '
      ($reds | map(.name)) as $red_names
      | [ $tests[] | . as $t
          | (if .provesDoneWhen == true then [$unit] else .criteria end)[]
          | {name: $t.name, path: $t.absPath, key: ., red: (($red_names | index($t.name)) != null)} ]')"
  [ -n "$tf_red_entries" ] || die 3 "tests-freeze: could not list the tests of $unit_id's rows."
  # A repair round's checker judges only the rows put to it, and writes the same verdict file, so a
  # row confirmed in an earlier round is on the ledger alone (gap row 259). Each one a --row does not
  # give is carried from there. A row whose test file changed after it was recorded is not carried,
  # because the checker judged the file as it was then.
  local tf_rec_src tf_recorded tf_rec_key tf_rec_at tf_rec_path tf_rec_keep tf_carried='[]' tf_changed=""
  local tf_test_epoch TF_CONFIRMED_DOC TF_CARRY_NEXT=""
  tf_rec_src="$tf_ledger_doc"
  [ -n "$tf_rec_src" ] || tf_rec_src='{}'
  while IFS= read -r tf_recorded; do
    [ -n "$tf_recorded" ] || continue
    tf_rec_key="$(printf '%s' "$tf_recorded" | jq -r '.criterion')"
    tf_rec_at="$(printf '%s' "$tf_recorded" | jq -r '.recordedAt | fromdateiso8601' 2>/dev/null)"
    [ -n "$tf_rec_at" ] || die 3 "tests-freeze: could not read when $unit_id's recorded row $tf_rec_key was confirmed."
    tf_rec_keep=true
    while IFS= read -r tf_rec_path; do
      [ -n "$tf_rec_path" ] || continue
      tf_test_epoch="$(im_mtime "$tf_rec_path")"
      [ -n "$tf_test_epoch" ] || die 3 "tests-freeze: could not read when $tf_rec_path was written."
      [ "$tf_test_epoch" -gt "$tf_rec_at" ] && tf_rec_keep=false
    done <<TF_REC_PATHS
$(printf '%s' "$tf_red_entries" | jq -r --arg k "$tf_rec_key" '[ .[] | select(.key == $k) | .path ] | unique | .[]')
TF_REC_PATHS
    if [ "$tf_rec_keep" = true ]; then
      tf_carried="$(printf '%s' "$tf_carried" | jq -c --argjson r "$tf_recorded" \
        '. + [{criterion: $r.criterion, verdict: "confirmed", judgedBy: $r.judgedBy, note: $r.note}]')"
    else
      tf_changed="$tf_changed$tf_rec_key, "
    fi
  done <<TF_RECORDED
$(printf '%s' "$tf_rec_src" | jq -c --arg id "$unit_id" --argjson expected "$rows_expected_json" \
    --argjson rows "$rows_meta_json" '
    ($rows | map(.criterion)) as $given
    | ([ (.orders // [])[] | select(.id == $id) ][0].rowsConfirmed // [])[]
    | select(.criterion as $k | ($expected | index($k)) != null and ($given | index($k)) == null)')
TF_RECORDED
  rows_meta_json="$(printf '%s' "$rows_meta_json" | jq -c --argjson c "$tf_carried" '. + $c')"
  rows_missing="$(jq -nr --argjson expected "$rows_expected_json" --argjson rows "$rows_meta_json" '
      ($rows | map(.criterion)) as $named
      | [ $expected[] as $k | select(($named | index($k)) == null) | $k ] | join(", ")
    ')"
  [ -z "$tf_changed" ] \
    || tf_changed=" These recorded rows are not carried, because a test file changed after the checker confirmed it: ${tf_changed%, }. Put them to the checker again."
  # The confirmed rows this freeze holds are recorded first. The checker dispatch for the missing
  # rows writes the same verdict file, and would take the notes of these rows with it.
  if [ -n "$rows_missing" ]; then
    if [ -n "$tf_ledger_doc" ]; then
      tf_record_confirmed "$tf_ledger_file" "$tf_ledger_doc" "$unit_id" \
        "$(printf '%s' "$rows_meta_json" | jq -c --argjson expected "$rows_expected_json" \
          'map(select(.criterion as $k | ($expected | index($k)) != null))')"
    fi
    die 64 "tests-freeze: these rows are missing: $rows_missing. Every criterion a --test names, and the doneWhen when a --test proves it or the order is proved by its record, is judged before the tests are frozen. So is each --absence clause, as <order id>:absence:<its doneWhen row>. Put the missing rows to the checker, then run tests-freeze again with a --row for each.$TF_CARRY_NEXT$tf_changed"
  fi
  rows_person="$(jq -nr --argjson criteria "$CRITERIA_JSON" --argjson rows "$rows_meta_json" '
      ($criteria | map(select(.verifiedBy == "person") | .id)) as $people
      | [ $rows[] | .criterion as $cid | select(($people | index($cid)) != null) | $cid ]
      | unique | join(", ")
    ')"
  [ -z "$rows_person" ] \
    || die 64 "tests-freeze: a --row names $rows_person, which a person verifies. Such a criterion carries a checklist and never a judgement; completion confirms it."
  rows_unknown="$(jq -nr --argjson expected "$rows_expected_json" --argjson rows "$rows_meta_json" '
      [ $rows[] | .criterion as $k | select(($expected | index($k)) == null) | $k ] | unique | join(", ")
    ')"
  [ -z "$rows_unknown" ] \
    || die 64 "tests-freeze: a --row names something no --test of $unit_id claims: $rows_unknown. A row judges the tests named against it; the row for a criterion this order only serves belongs to its owner."
  rows_twice="$(jq -nr --argjson rows "$rows_meta_json" '
      [ $rows | group_by(.criterion)[] | select(length > 1) | .[0].criterion ] | join(", ")
    ')"
  [ -z "$rows_twice" ] \
    || die 64 "tests-freeze: these criteria have more than one --row: $rows_twice. One order judges one criterion once."

  # --- 65: a rejected row stops the freeze, and no test record is written ---------------------------
  # Unattended, a row the checker rejected also halts the order before the refusal, the same way a
  # dirty tree already halts one at `build-record`. A refusal is a message to whoever ran the step,
  # and unattended nobody is reading it: the order would sit in flight with no reason on it. A row a
  # person rejected refuses without a halt either way, because the person is already there and the
  # row goes straight back to the test author.
  local rejected_rows rejected_by_model
  rejected_rows="$(printf '%s' "$rows_meta_json" | jq -r '
      [ .[] | select(.verdict == "rejected") | .criterion + " (" + .judgedBy + "): " + .note ] | join("; ")')"
  if [ -n "$rejected_rows" ]; then
    # Each rejected row is repaired, which edits its test file and makes the other reds in it
    # stale (gap row 258). red_again reads tf_red_entries to name them. The repair also moves what
    # a confirmed row in that file was judged on, so the next checker dispatch covers it too. It
    # covers the doneWhen row when an owned row is rejected, because that row names the owned
    # verdicts it rests on.
    local tf_check_again
    tf_check_again="$(jq -nc --argjson rows "$rows_meta_json" --argjson entries "$tf_red_entries" \
        --argjson owned "$owned_ids_json" --arg unit "$unit_id" '
        ($rows | map(.criterion)) as $keys
        | ([ $rows[] | select(.verdict == "rejected") | .criterion ]) as $rej
        | ([ $entries[] | select(.key as $k | ($rej | index($k)) != null) | .path ] | unique) as $files
        | $rej
          + [ $entries[] | select(.path as $p | ($files | index($p)) != null) | .key ]
          + (if [ $rej[] | select(. as $k | ($owned | index($k)) != null) ] == [] then [] else [$unit] end)
        | map(select(. as $k | ($keys | index($k)) != null)) | unique')"
    [ -n "$tf_check_again" ] || die 3 "tests-freeze: could not list the rows of $unit_id the checker judges again."
    # A rejected absence row has no test to repair, so the refusal names its two routes. An order
    # with no test author drops the --absence instead: its own check, the gate lines, the
    # observation, the record's done-when row or the person's checklist at review, then covers it.
    # The test author is named only on a kind whose roles hold one.
    local tf_absence_route="" tf_has_author=false tf_person_next tf_model_next
    br_order_needs "$UNIT_JSON"
    case " $BR_ORDER_ROLES " in *" test-author "*) tf_has_author=true ;; esac
    if printf '%s' "$rows_meta_json" | jq -e 'any(.[]; .verdict == "rejected" and (.criterion | test(":absence:[0-9]+$")))' >/dev/null; then
      if [ "$tf_has_author" = true ]; then
        tf_absence_route=" A rejected absence row says a test could prove that clause. The test author writes a test for it and returns no absence for it, or design splits the clause."
      else
        tf_absence_route=" A rejected absence row says that clause can be proved. Freeze again without that --absence, so the order's own proof covers the clause, or design splits the clause."
      fi
    fi
    if [ "$tf_has_author" = true ]; then
      tf_person_next=" A row a person rejected is on $unit_id's ledger entry: run tests-brief, then dispatch the test author fresh. Then put the rows checkAgain names to the checker."
      tf_model_next=" Send the row back to the test author. Then put the rows checkAgain names to the checker, and run tests-freeze again once the test observes what the criterion asks."
    else
      tf_person_next=" Put the rows checkAgain names to the checker."
      tf_model_next="$tf_person_next"
    fi
    rejected_by_model="$(printf '%s' "$rows_meta_json" | jq -r '
        [ .[] | select(.verdict == "rejected") | select(.judgedBy == "model")
          | .criterion + ": " + .note ] | join("; ")')"
    if [ -n "$rejected_by_model" ]; then
      local tf_why tf_halted_doc
      if [ "$tf_run_mode" = "autonomous" ] && [ -n "$tf_ledger_doc" ]; then
        tf_why="row rejected by the checker: $rejected_by_model"
        tf_halted_doc="$(halt_order_in "$tf_ledger_doc" "$unit_id" "$tf_why")"
        [ -n "$tf_halted_doc" ] || die 3 "tests-freeze: the ledger update for $unit_id failed."
        write_atomic "$tf_ledger_file" "$tf_halted_doc"
        tf_ledger_doc="$tf_halted_doc"
        echo "TESTS-FREEZE: $unit_id is halted. $tf_why" >&2
      fi
    fi
    # The confirmed rows the checker need not judge again are recorded. The next freeze carries them.
    if [ -n "$tf_ledger_doc" ]; then
      tf_record_confirmed "$tf_ledger_file" "$tf_ledger_doc" "$unit_id" \
        "$(printf '%s' "$rows_meta_json" | jq -c --argjson again "$tf_check_again" \
          'map(select(.criterion as $k | ($again | index($k)) == null))')"
      tf_ledger_doc="$TF_CONFIRMED_DOC"
    fi
    # A row a person rejected goes back to the test author, and the person's words existed only in
    # the conversation (gap row 218). So they land on the order's ledger entry, with the checker's
    # note from its verdict file, and `tests-brief` carries them to a fresh test author.
    local tf_person_rejected tf_rejected_doc tf_check_file tf_check_doc='{}'
    tf_person_rejected="$(printf '%s' "$rows_meta_json" | jq -c '
        [ .[] | select(.verdict == "rejected" and .judgedBy == "person") ]')"
    if [ "$tf_person_rejected" != "[]" ] && [ -n "$tf_ledger_doc" ]; then
      # A missing verdict file leaves each note null. A present one that does not read refuses,
      # because the rejection would otherwise be lost with it.
      tf_check_file="$IMPL_DIR/row-check-$unit_id.json"
      if [ -f "$tf_check_file" ]; then
        tf_check_doc="$(jq -c '.' "$tf_check_file" 2>/dev/null)"
        [ -n "$tf_check_doc" ] \
          || die 3 "tests-freeze: $tf_check_file exists but could not be read as JSON. The rejected rows are recorded with the checker's note from it. Repair or remove it by hand before running this again."
      fi
      tf_person_rejected="$(printf '%s' "$tf_person_rejected" | jq -c --argjson check "$tf_check_doc" \
          --argjson entries "$tf_red_entries" "$RED_AGAIN_JQ"'
          [ .[] | .criterion as $c
            | {criterion: $c, personWords: .note,
               checkerNote: ([ ($check.rows // [])[] | select(.criterion == $c) | .note ][0] // null),
               redAgain: red_again($entries; $c)} ]' 2>/dev/null)"
      [ -n "$tf_person_rejected" ] \
        || die 3 "tests-freeze: $tf_check_file is not in the checker's shape, {\"rows\": [{\"criterion\", \"verdict\", \"note\"}]}. Repair or remove it by hand before running this again."
      tf_rejected_doc="$(printf '%s' "$tf_ledger_doc" | jq -c --arg id "$unit_id" --argjson r "$tf_person_rejected" \
        '.orders = (.orders | map(if .id == $id then .rowsRejected = $r else . end))')"
      [ -n "$tf_rejected_doc" ] || die 3 "tests-freeze: the ledger update for $unit_id failed."
      write_atomic "$tf_ledger_file" "$tf_rejected_doc"
      die 65 "tests-freeze: a --row answers rejected, so nothing is frozen: $rejected_rows.$tf_person_next$tf_absence_route$TF_CARRY_NEXT
checkAgain: $tf_check_again"
    fi
    # No ledger record carries this rejection, so the refusal names the tests to run again.
    die 65 "tests-freeze: a --row answers rejected, so nothing is frozen: $rejected_rows.$tf_model_next$tf_absence_route$TF_CARRY_NEXT
checkAgain: $tf_check_again
redAgain: $(printf '%s' "$rows_meta_json" | jq -c --argjson entries "$tf_red_entries" "$RED_AGAIN_JQ"'
    [ .[] | select(.verdict == "rejected") | red_again($entries; .criterion)[] ] | unique')"
  fi

  # --- 32: a --red file must exist, hold something, and name a test that has a --test row ----------
  local bad_red_names
  bad_red_names="$(jq -nr --argjson tests "$tests_json" --argjson reds "$reds_json" --argjson locks "$locks_json" '
      ($tests | map(.name)) as $known
      | [ ($reds + $locks)[] | .name as $n | select(($known | index($n)) == null) | $n ] | unique | join(", ")
    ')"
  [ -z "$bad_red_names" ] \
    || die 32 "tests-freeze: these --red or --locks-in rows name a test with no --test row: $bad_red_names"

  local red_count ri red_name red_path bad_red_files=""
  red_count="$(printf '%s' "$reds_json" | jq 'length')"
  ri=0
  while [ "$ri" -lt "$red_count" ]; do
    red_name="$(printf '%s' "$reds_json" | jq -r --argjson ri "$ri" '.[$ri].name')"
    red_path="$(printf '%s' "$reds_json" | jq -r --argjson ri "$ri" '.[$ri].path')"
    [ -s "$red_path" ] || bad_red_files="$bad_red_files$red_name ($red_path), "
    ri=$((ri + 1))
  done
  [ -z "$bad_red_files" ] \
    || die 32 "tests-freeze: these --red files are missing or empty: ${bad_red_files%, }"

  # --- 109: a red run older than its round or its test file is a run of other tests (row 229) ---
  # The round began at the tests brief's `roundStartedAt`. A restart moves the brief aside, and a
  # changed order or criterion restamps it, so the time is never older than either. A brief from
  # before the stamp is read by its file time. With no brief, only the test files are compared.
  # A red names its test by name, and every --test row of that name is the file it ran. The file
  # time is per file, not per test: a framework that keeps several tests in one file makes each
  # red in it stale when one test changes (gap row 258). That is kept on purpose. An edit to one
  # test can change what the others run, and it moves every line their reds cite. The refusal
  # prints the names on a `redAgain:` line, as JSON, so whoever runs them again need not guess.
  local tf_brief tf_round_at="" tf_round_epoch="" tf_red_epoch tf_test_path tf_test_epoch stale_reds=""
  local stale_names=""
  tf_brief="$IMPL_DIR/brief-$unit_id-tests.json"
  if [ "$red_count" -gt 0 ] && [ -f "$tf_brief" ]; then
    tf_round_at="$(jq -r '.roundStartedAt // empty' "$tf_brief" 2>/dev/null)"
    if [ -n "$tf_round_at" ]; then
      tf_round_epoch="$(jq -rn --arg t "$tf_round_at" '$t | fromdateiso8601' 2>/dev/null)"
    else
      tf_round_epoch="$(im_mtime "$tf_brief")"
      tf_round_at="$(im_iso_of "$tf_round_epoch")"
    fi
    [ -n "$tf_round_epoch" ] && [ -n "$tf_round_at" ] \
      || die 3 "tests-freeze: could not read when the test round began from $tf_brief."
  fi
  ri=0
  while [ "$ri" -lt "$red_count" ]; do
    red_name="$(printf '%s' "$reds_json" | jq -r --argjson ri "$ri" '.[$ri].name')"
    red_path="$(printf '%s' "$reds_json" | jq -r --argjson ri "$ri" '.[$ri].path')"
    tf_red_epoch="$(im_mtime "$red_path")"
    [ -n "$tf_red_epoch" ] || die 3 "tests-freeze: could not read when $red_path was written."
    if [ -n "$tf_round_epoch" ] && [ "$tf_red_epoch" -lt "$tf_round_epoch" ]; then
      stale_reds="$stale_reds$red_name ($red_path, written $(im_iso_of "$tf_red_epoch"), before the round began at $tf_round_at), "
      stale_names="$stale_names$red_name
"
    fi
    while IFS= read -r tf_test_path; do
      [ -n "$tf_test_path" ] || continue
      tf_test_epoch="$(im_mtime "$tf_test_path")"
      [ -n "$tf_test_epoch" ] || die 3 "tests-freeze: could not read when $tf_test_path was written."
      if [ "$tf_red_epoch" -lt "$tf_test_epoch" ]; then
        stale_reds="$stale_reds$red_name ($red_path, written $(im_iso_of "$tf_red_epoch"), before its test file $tf_test_path changed at $(im_iso_of "$tf_test_epoch")), "
        stale_names="$stale_names$red_name
"
      fi
    done <<TF_RED_TESTS
$(printf '%s' "$tests_json" | jq -r --arg n "$red_name" '[ .[] | select(.name == $n) | .absPath ] | unique | .[]')
TF_RED_TESTS
    ri=$((ri + 1))
  done
  [ -z "$stale_reds" ] \
    || die 109 "tests-freeze: these --red files are runs of earlier tests: ${stale_reds%, }. Run each test again and pass the new output.
redAgain: $(printf '%s' "$stale_names" | jq -R -s -c 'split("\n") | map(select(length > 0)) | unique')"

  # --- 91: the reds are read against the recipe preconditions recorded (live-run row 99) -----------
  # The record is the one producer of a test-execution recipe path, and build-record reads it from
  # there for the same order. A --test-recipe is accepted only when it restates the record's path,
  # and a freeze with none reads the record's path itself, so the two records of one order never
  # stand on two recipes. A framework the record holds no path for is left to the flag as given:
  # there is nothing to disagree with. A recorded path gone from disk cannot be read either way,
  # and that message names the refresh. Read only when a red is to be read, because the recipe
  # serves nothing else here.
  local tf_pre_file tf_pre_line tf_pre_fw tf_pre_path tf_given_path tf_from_record="" tf_fallback=""
  tf_pre_file="$IMPL_DIR/preconditions.json"
  if [ "$red_count" -gt 0 ] && [ -f "$tf_pre_file" ]; then
    tf_from_record="$(jq -r '[ (.frameworks // [])[] | select(.lookup == "resolved" and (.recipePath // "") != "")
                               | .framework + "\t" + .recipePath ] | join("\n")' "$tf_pre_file" 2>/dev/null)"
    while IFS= read -r tf_pre_line; do
      [ -n "$tf_pre_line" ] || continue
      tf_pre_fw="${tf_pre_line%%	*}"; tf_pre_path="${tf_pre_line#*	}"
      if [ -z "$test_recipes" ]; then
        [ -f "$tf_pre_path" ] \
          || die 3 "tests-freeze: the test-execution recipe $tf_pre_file records for $tf_pre_fw is not a file: $tf_pre_path. Resolve it again and run recipe-refresh --recipe $tf_pre_fw=<path> first."
        cr_recipe_pair "tests-freeze" "frameworks[].recipePath in $tf_pre_file" "$tf_pre_fw=$tf_pre_path"
        tf_fallback="$tf_fallback$CR_PAIR
"
        continue
      fi
      tf_given_path="$(cr_lookup "$test_recipes" "$tf_pre_fw")"
      [ -n "$tf_given_path" ] || continue
      if [ -f "$tf_pre_path" ]; then
        cr_recipe_pair "tests-freeze" "frameworks[].recipePath in $tf_pre_file" "$tf_pre_fw=$tf_pre_path"
        tf_pre_path="${CR_PAIR#*	}"
      fi
      [ "$tf_given_path" = "$tf_pre_path" ] \
        || die 91 "tests-freeze: --test-recipe names $tf_given_path for $tf_pre_fw, and $tf_pre_file records $tf_pre_path. The reds would be read against one recipe and build-record would read the other, so the two records of one order would stand on two recipes. Nothing is frozen. If the catalog republished the recipe, run recipe-refresh --recipe $tf_pre_fw=$tf_given_path first, then freeze again."
    done <<TF_EOF
$tf_from_record
TF_EOF
    [ -n "$test_recipes" ] || test_recipes="$tf_fallback"
  fi

  # --- 80: a --red file must hold the failure signal the test-execution recipe declares ------------
  # A non-empty file is not a red. wo7's six kernel tests all errored in setUp() before any
  # assertion ran, and the freeze took that file as a red (live-run row 68). The recipe declares,
  # under failure_signal, what the harness prints when an assertion ran and did not hold
  # (`assertion:`) and what it prints when it never reached the behaviour (`harness:`), and its
  # suite row declares `failure_line`, one line per test the harness numbered. Two readings accept
  # a file: an assertion marker, or, where no harness marker is present, a line the selector
  # matches. The second is what reads a red under a recipe whose assertion span is a shape rather
  # than a marker (pytest's `FAILED <node id>`). The markers and selectors of every recipe
  # handed over are read together, the way build-record reads silent_pass. A file that neither
  # reading accepts refuses; when it holds a harness marker the refusal says setup gap, and the
  # repair is the harness or the unit's own declaration, never the test. A recipe set declaring
  # no assertion marker and no selector leaves nothing to read: the file is recorded unchecked,
  # said in one summary line, rather than refused, because three catalog recipes declare a shape
  # in place of a marker today and refusing would stop every red under them.
  local red_recipe_path recipe_markers red_rows_tmp red_selector
  local assertion_markers="" harness_markers="" failure_lines=""
  if [ "$red_count" -gt 0 ]; then
    [ -n "$test_recipes" ] \
      || die 80 "tests-freeze: a --red was given, no --test-recipe, and implementation/preconditions.json records no resolved test-execution recipe, so no failure marker can be read and no red can be told from a run that never asserted. Run preconditions with --recipe <framework>=<path> for each framework first."
    red_rows_tmp="$IMPL_DIR/.tests-freeze-recipe-rows.$$"
    while IFS= read -r red_recipe_path; do
      [ -n "$red_recipe_path" ] || continue
      red_recipe_path="$(printf '%s' "$red_recipe_path" | cut -f2-)"
      recipe_markers="$(cc_failure_signal_markers "$red_recipe_path" "assertion")"
      [ -z "$recipe_markers" ] || assertion_markers="$assertion_markers$recipe_markers
"
      recipe_markers="$(cc_failure_signal_markers "$red_recipe_path" "harness")"
      [ -z "$recipe_markers" ] || harness_markers="$harness_markers$recipe_markers
"
      : >"$red_rows_tmp"
      tc_parse_recipe "$red_recipe_path" "$red_rows_tmp"
      red_selector="$(pc_unquote "$(jq -s -r '[ .[] | select(.id == "suite") ][0].failureLine // ""' "$red_rows_tmp" 2>/dev/null)")"
      [ -z "$red_selector" ] || failure_lines="$failure_lines$red_selector
"
    done <<TF_EOF
$test_recipes
TF_EOF
    rm -f "$red_rows_tmp"
  fi
  # A harness-only red is the one red the order that creates the unit can have (live-run row 68,
  # second half): every test errors where the harness enables the module, before an assertion
  # runs, and nothing in the build may write the module first. The implement recipe names, under
  # `## Unit declaration`, the file whose presence makes a unit exist, and an owned file matching
  # one of its globs makes this order that order. The globs of every recipe handed over are read
  # together, the way the markers above are. No flag, no block or no matching owned file leaves
  # the setup-gap refusal below as it is.
  local unit_recipe_path unit_glob owned_file unit_file="" unit_file_glob="" unit_file_recipe=""
  if [ "$red_count" -gt 0 ] && [ -n "$unit_recipes" ]; then
    while IFS= read -r unit_recipe_path; do
      [ -n "$unit_recipe_path" ] || continue
      unit_recipe_path="$(printf '%s' "$unit_recipe_path" | cut -f2-)"
      while IFS= read -r unit_glob; do
        [ -n "$unit_glob" ] || continue
        unit_glob="$(pc_unquote "$unit_glob")"
        while IFS= read -r owned_file; do
          [ -n "$owned_file" ] || continue
          [ -z "$unit_file" ] || continue
          if tf_path_matches_catalog_glob "$owned_file" "$unit_glob"; then
            unit_file="$owned_file"; unit_file_glob="$unit_glob"; unit_file_recipe="$unit_recipe_path"
          fi
        done <<TF_OWNED
$(printf '%s' "$UNIT_JSON" | jq -r '(.ownedFiles // [])[]')
TF_OWNED
      done <<TF_GLOBS
$(cc_unit_declaration_globs "$unit_recipe_path")
TF_GLOBS
    done <<TF_RECIPES
$unit_recipes
TF_RECIPES
  fi
  local red_signal marker unread_reds="" setup_gap_reds="" marker_words signals_tmp
  local first_unread_path="" harness_words unread_line
  marker_words="$(printf '%s' "$assertion_markers" | grep -v '^$' | sort -u | sed "s/.*/'&'/" | tr '\n' ' ')"
  signals_tmp="$IMPL_DIR/.tests-freeze-signals.$$"
  : >"$signals_tmp"
  ri=0
  while [ "$ri" -lt "$red_count" ]; do
    red_name="$(printf '%s' "$reds_json" | jq -r --argjson ri "$ri" '.[$ri].name')"
    red_path="$(printf '%s' "$reds_json" | jq -r --argjson ri "$ri" '.[$ri].path')"
    red_signal=""
    while IFS= read -r marker; do
      [ -n "$marker" ] || continue
      if pc_output_holds "$red_path" "$marker"; then red_signal="assertion"; break; fi
    done <<TF_EOF
$assertion_markers
TF_EOF
    # The harness marker is read before the selector. PHPUnit numbers a test that errored in
    # setUp() the same way as one that failed (`1) Class::method`), so the row 68 output matches
    # the selector, and reading the selector first would freeze it as a red again. For the order
    # that creates the unit the same file is its red, recorded as harness-new-unit.
    if [ -z "$red_signal" ]; then
      while IFS= read -r marker; do
        [ -n "$marker" ] || continue
        if pc_output_holds "$red_path" "$marker"; then
          if [ -n "$unit_file" ]; then red_signal="harness-new-unit"; break; fi
          red_signal="harness"; setup_gap_reds="$setup_gap_reds$red_name (holds '$marker'), "; break
        fi
      done <<TF_EOF
$harness_markers
TF_EOF
    fi
    if [ -z "$red_signal" ]; then
      while IFS= read -r red_selector; do
        [ -n "$red_selector" ] || continue
        # Exit 2 is a selector grep cannot compile, read as no match, the same as build-record.
        if grep -a -E -q -e "$red_selector" "$red_path" 2>/dev/null; then red_signal="failure-line"; break; fi
      done <<TF_EOF
$failure_lines
TF_EOF
    fi
    if [ -z "$red_signal" ] && [ -z "$assertion_markers" ] && [ -z "$failure_lines" ]; then
      red_signal="unchecked"
    fi
    case "$red_signal" in
      ""|harness)
        unread_reds="$unread_reds$red_name ($red_path), "
        [ -n "$first_unread_path" ] || first_unread_path="$red_path" ;;
    esac
    printf '%s\t%s\n' "$red_name" "$red_signal" >>"$signals_tmp"
    ri=$((ri + 1))
  done
  if [ -n "$unread_reds" ]; then
    rm -f "$signals_tmp"
    [ -z "$setup_gap_reds" ] \
      || die 80 "tests-freeze: these --red files hold the recipe's harness marker and no assertion marker: ${setup_gap_reds%, }. The harness stopped in an error before any assertion held or failed, which is a setup gap and not a red: for a unit whose module does not exist yet, nothing can fail an assertion before it does. Nothing is frozen. Repair the harness or the unit's own declaration, never the test, and run that test on its own again. An order that creates the unit passes --implement-recipe <framework>=<path>, so its unit declaration can be read. An assertion failure prints one of ${marker_words% }. Every file read as no red: ${unread_reds%, }."
    # For the order that creates the unit, "run it again until it fails for the reason it names"
    # is wrong advice: nothing can fail an assertion before the unit exists, and the file already
    # shows why the harness stopped. On the live run (row 98) every red was a PHP fatal the recipe
    # names in prose and declares under no marker, so the exception above never fired. The plugin
    # reads whatever markers the recipe declares; the recipe is the repair, and this says so.
    if [ -n "$unit_file" ]; then
      harness_words="$(printf '%s' "$harness_markers" | grep -v '^$' | sort -u | sed "s/.*/'&'/" | tr '\n' ' ')"
      # The first line holding "error" is the one that says why: a PHP fatal names the missing
      # class there and ends in "thrown in <file>". A file with no such line quotes its last one.
      unread_line="$(grep -a -i -m 1 'error' "$first_unread_path" | cut -c1-160)"
      [ -n "$unread_line" ] || unread_line="$(grep -a -v '^[[:space:]]*$' "$first_unread_path" | tail -n 1 | cut -c1-160)"
      die 80 "tests-freeze: $unit_id creates the unit, so a red holding only a harness marker would be accepted. These --red files hold none of the harness markers the test-execution recipe declares: ${unread_reds%, }. The recipe's harness markers are ${harness_words% }. One line of $first_unread_path reads: $unread_line. Nothing is frozen. Repair one: the test-execution recipe declares the form the harness printed, under failure_signal harness:. Repair two: the test does not depend on a module-local class before the unit exists."
    fi
    die 80 "tests-freeze: these --red files hold none of the assertion markers the test-execution recipe declares, and no line its suite row's failure_line names: ${unread_reds%, }. A run that did not fail an assertion is not a red. An assertion failure prints one of ${marker_words% }; read the file, and run the test again until it fails for the reason it names."
  fi
  # The signal each red was accepted on rides with its --red row into the record (redSignal).
  reds_json="$(jq -c --rawfile sig "$signals_tmp" --argjson reds "$reds_json" -n '
      ($sig | split("\n") | map(select(length > 0) | split("\t") | {key: .[0], value: .[1]}) | from_entries) as $by
      | $reds | map(. + {signal: ($by[.name] // "")})')"
  rm -f "$signals_tmp"
  if [ "$red_count" -gt 0 ] && [ -z "$assertion_markers" ] && [ -z "$failure_lines" ]; then
    echo "TESTS-FREEZE: red files unchecked, the test-execution recipe declares no assertion marker and no suite failure_line to read them against: $(printf '%s' "$test_recipes" | cut -f2- | grep -v '^$' | tr '\n' ' ')"
  fi
  if printf '%s' "$reds_json" | jq -e 'any(.[]; .signal == "harness-new-unit")' >/dev/null; then
    echo "TESTS-FREEZE: $unit_id creates a unit: $unit_file matches $unit_file_glob under ## Unit declaration in $unit_file_recipe. A red holding only the harness marker is accepted for it, because nothing can fail an assertion before the unit exists."
  fi

  # --- 80: two tests that fail at one place failed on a shared precondition (live-run row 207) ----
  # Ten tests opened with one guard that the service exists, and all ten reds stopped on that
  # line. Each held an assertion marker, yet no test was watched failing on its own assertion. A
  # red's place is every `<test file name>:<line>` its file prints, in order: the failing line and,
  # through a helper, the test's own call line. Two tests of one file whose reds print the same
  # places failed at one shared line, so that red counts for neither. Only the reds read on an
  # assertion are compared, because every harness red of the order that creates the unit stops at
  # one place by nature.
  local places_tmp place_name place_rel place_path place_chain shared_places
  places_tmp="$IMPL_DIR/.tests-freeze-places.$$"
  : >"$places_tmp"
  ri=0
  while [ "$ri" -lt "$red_count" ]; do
    place_name="$(printf '%s' "$reds_json" | jq -r --argjson ri "$ri" '.[$ri] | select(.signal == "assertion" or .signal == "failure-line") | .name')"
    place_path="$(printf '%s' "$reds_json" | jq -r --argjson ri "$ri" '.[$ri].path')"
    ri=$((ri + 1))
    [ -n "$place_name" ] || continue
    place_rel="$(printf '%s' "$tests_json" | jq -r --arg n "$place_name" '[ .[] | select(.name == $n) ][0].relPath')"
    # A regex match, because jq's `indices` counts bytes and its slices count characters, so a
    # position read past any non-ASCII character (jest's bullet) pointed at the wrong text.
    place_chain="$(jq -n -r --rawfile text "$place_path" --arg b "${place_rel##*/}" '
        [ $text | match("(?<![A-Za-z0-9_.-])" + ($b | gsub("(?<c>[\\\\^$.|?*+()\\[\\]{}])"; "\\\(.c)")) + ":(?<n>[0-9]+)"; "g")
          | "\($b):\(.captures[0].string)" ] | join(" then ")')"
    [ -z "$place_chain" ] || printf '%s\t%s\t%s\n' "$place_rel" "$place_chain" "$place_name" >>"$places_tmp"
  done
  shared_places="$(jq -R -s -r '
      split("\n") | map(select(length > 0) | split("\t")) | group_by(.[0] + "\t" + .[1])
      | map(select(length > 1) | "\(.[0][1]) (\(map(.[2]) | join(", ")))") | join("; ")' "$places_tmp")"
  rm -f "$places_tmp"
  [ -z "$shared_places" ] \
    || die 80 "tests-freeze: these tests' reds all stop at one place: $shared_places. A failure there is a shared precondition, such as a guard that the class or service exists, so it is a red for none of them. Nothing is frozen. Make each test reach its own assertion: write the guard so that it asserts nothing, for example a lookup that gives the empty value when the service is absent. Then run each test again."

  # --- 101: a --locks-in reason written commit:<id> names one of this order's own commits --------
  # A test of the order's own done-when that arrives green has no code the author may cite: the
  # code is this order's earlier build, which a restart or a retake left in the tree, and the author
  # reads no production source (live-run row 183). So the reason may be a commit instead. `tests-brief`
  # prints this order's own build and fix commits under `treeHolds`, and the author names one of
  # them. The same reader answers here, so the freeze accepts exactly what the brief offered, and
  # a commit of another order or one git no longer holds refuses.
  # The `commit:` prefix is what marks a commit, and a reason without it is prose whatever it looks
  # like. Reading a bare hex word as an id would refuse a prose reason nobody meant as one. The id
  # may be shorter than the brief printed, because `start`'s own line prints seven characters.
  local tf_lock_total tf_lock_i tf_lock_reason tf_lock_id tf_lock_name tf_lock_hit
  local tf_own_commits tf_own_loaded tf_own_c tf_carried tf_lost=""
  tf_lock_total="$(printf '%s' "$locks_json" | jq 'length')"
  tf_own_commits=""
  tf_own_loaded=false
  tf_lock_i=0
  while [ "$tf_lock_i" -lt "$tf_lock_total" ]; do
    tf_lock_reason="$(printf '%s' "$locks_json" | jq -r --argjson i "$tf_lock_i" '.[$i].reason')"
    case "$tf_lock_reason" in
      commit:*) ;;
      *) tf_lock_i=$((tf_lock_i + 1)); continue ;;
    esac
    tf_lock_id="${tf_lock_reason#commit:}"
    tf_lock_name="$(printf '%s' "$locks_json" | jq -r --argjson i "$tf_lock_i" '.[$i].name')"
    case "$tf_lock_id" in
      ""|*[!0-9a-f]*)
        die 101 "tests-freeze: --locks-in for $tf_lock_name reads commit:$tf_lock_id, and a commit id is hexadecimal and nothing else. Write commit:<id> with one of $unit_id's own build or fix commits, or drop the commit: prefix and name the existing code in a sentence." ;;
    esac
    [ "${#tf_lock_id}" -ge 7 ] \
      || die 101 "tests-freeze: --locks-in for $tf_lock_name reads commit:$tf_lock_id, which is shorter than seven characters and names no commit on its own. Read the whole id from treeHolds in the tests brief."
    if [ "$tf_own_loaded" = "false" ]; then
      tf_carried="$(rs_carried_commits_in_head "$TASK_PATH" "$RV_CODEPATH" "$unit_id" "$tf_prior_ledger")"
      tf_own_commits="$(printf '%s' "$tf_carried" | jq -r '.[] | select(has("missing") | not) | .commit')"
      tf_lost="$(printf '%s' "$tf_carried" | jq -r '[ .[] | select(has("missing")) | .commit + " " + .kind + ": " + .missing ] | join("; ")')"
      tf_own_loaded=true
    fi
    tf_lock_hit=""
    while IFS= read -r tf_own_c; do
      [ -n "$tf_own_c" ] || continue
      [ "${tf_own_c:0:${#tf_lock_id}}" = "$tf_lock_id" ] || continue
      tf_lock_hit="$tf_own_c"
    done <<TF_OWN_COMMITS
$tf_own_commits
TF_OWN_COMMITS
    [ -n "$tf_lock_hit" ] \
      || die 101 "tests-freeze: --locks-in for $tf_lock_name gives the commit $tf_lock_id, which is not one of $unit_id's own build or fix commits on this branch. Those commits are: $(if [ -n "$tf_own_commits" ]; then printf '%s' "$tf_own_commits" | tr '\n' ' '; elif [ -n "$tf_lost" ]; then printf 'none that can be cited'; else printf 'none, so no restart or retake left this order a build here'; fi). Read them from treeHolds in the tests brief.$(if [ -n "$tf_lost" ]; then printf ' These were not found on this branch after the rebase: %s. None of them can be cited. If the test arrives green on that code, report the test green on arrival and name that commit. A person decides.' "$tf_lost"; fi) A reason with no commit: prefix names the existing code instead."
    tf_lock_i=$((tf_lock_i + 1))
  done

  # --- 33: every declared test needs a --red, or a --locks-in naming the existing code it locks in --
  local missing_red
  missing_red="$(jq -nr --argjson tests "$tests_json" --argjson reds "$reds_json" --argjson locks "$locks_json" '
      (($reds + $locks) | map(.name)) as $named
      | [ $tests[] | .name as $n | select(($named | index($n)) == null) | $n ] | unique | join(", ")
    ')"
  [ -z "$missing_red" ] \
    || die 33 "tests-freeze: these tests have neither a --red nor a --locks-in: $missing_red"

  # --- 34: a green-on-arrival stops the step outright -----------------------------------------------
  if [ "$(printf '%s' "$goa_json" | jq 'length')" -gt 0 ]; then
    local goa_text
    goa_text="$(printf '%s' "$goa_json" | jq -r 'map(.name + ": " + .reason) | join("; ")')"
    die 34 "tests-freeze: reported green on arrival, which proves nothing: $goa_text. Fix the test or the code until it fails for the right reason, then run tests-freeze again."
  fi

  # --- 35: a record already exists for this unit at a different commit -----------------------------
  local record_file existing_doc existing_commit=""
  record_file="$IMPL_DIR/tests-$unit_id.json"
  if [ -f "$record_file" ]; then
    existing_doc="$(jq -c '.' "$record_file" 2>/dev/null)"
    [ -n "$existing_doc" ] \
      || die 3 "tests-freeze: $record_file exists but could not be read as JSON. Repair or remove it by hand before running this again."
    existing_commit="$(printf '%s' "$existing_doc" | jq -r '.commit // empty')"
    [ -n "$existing_commit" ] \
      || die 3 "tests-freeze: $record_file exists but has no usable commit field."
    # A different commit is decided once the rows are built, below: the freeze itself commits, so
    # HEAD moves with every order frozen, and a re-run with the same tests is unchanged wherever
    # HEAD stands. Only changed tests under a moved HEAD refuse with 35.
  fi

  # --- every check passed: build the rows ----------------------------------------------------------
  # One per machine criterion the tests name, one per person criterion the unit serves or owns, and
  # one for the doneWhen when a test proves it. A served machine criterion no test names gets no
  # row here: its proof lives with its owner, and a row with no test under it is what the frozen-
  # tests check later reads as unknown.
  local need_sha
  need_sha="$(printf '%s' "$tests_json" | jq -r 'length > 0')"
  if [ "$need_sha" = "true" ]; then
    records_hash__resolve_sha256_cmd \
      || die 3 "tests-freeze: neither sha256sum nor 'shasum -a 256' was found on PATH"
  fi

  # Every name the loop below uses is declared here, never inside it. zsh prints a parameter when
  # `local` names one that already exists in the same scope, so a `local` inside a loop body puts
  # the previous round's value on standard output from the second round on, which corrupts this
  # action's own output for any order serving two criteria (trap 5 in this file's own header).
  local rows_tmp crit_count ci cid ckind
  local names_json tests_out_json
  local checklist_text
  rows_tmp="$IMPL_DIR/.tests-freeze-rows.$$"
  : >"$rows_tmp"
  crit_count="$(printf '%s' "$CRITERIA_JSON" | jq 'length')"
  ci=0
  while [ "$ci" -lt "$crit_count" ]; do
    cid="$(printf '%s' "$CRITERIA_JSON" | jq -r --argjson ci "$ci" '.[$ci].id')"
    ckind="$(printf '%s' "$CRITERIA_JSON" | jq -r --argjson ci "$ci" '.[$ci].verifiedBy')"
    if [ "$ckind" = "machine" ]; then
      names_json="$(printf '%s' "$tests_json" | jq -c --arg cid "$cid" \
        '[ .[] | select(.criteria | index($cid) != null) ]')"
      if [ "$(printf '%s' "$names_json" | jq 'length')" -gt 0 ]; then
        tests_out_json="$(tf_frozen_tests_of "$names_json" "$reds_json" "$locks_json")" || exit "$?"
        jq -n --arg cid "$cid" --argjson tests "$tests_out_json" \
          '{criterion: $cid, kind: "machine", tests: $tests}' >>"$rows_tmp" \
          || die 3 "tests-freeze: could not record the row for $cid"
      fi
    else
      checklist_text="$(printf '%s' "$checklists_json" | jq -r --arg id "$cid" \
        '[ .[] | select(.id == $id) ][0].text // empty')"
      jq -n --arg cid "$cid" --arg text "$checklist_text" \
        '{criterion: $cid, kind: "person", checklist: $text}' >>"$rows_tmp" \
        || die 3 "tests-freeze: could not record the row for $cid"
    fi
    ci=$((ci + 1))
  done
  # The doneWhen row keeps `kind: machine`, so every later reader that selects machine rows for
  # their tests (the frozen-tests check, the selected-tests command, the two briefs) runs and
  # hashes these tests the same as a criterion's.
  if [ "$has_done_when_tests" = "true" ]; then
    names_json="$(printf '%s' "$tests_json" | jq -c '[ .[] | select(.provesDoneWhen == true) ]')"
    tests_out_json="$(tf_frozen_tests_of "$names_json" "$reds_json" "$locks_json")" || exit "$?"
    jq -n --argjson tests "$tests_out_json" \
      '{criterion: null, kind: "machine", provesDoneWhen: true, tests: $tests}' >>"$rows_tmp" \
      || die 3 "tests-freeze: could not record the doneWhen row for $unit_id"
  fi
  local rows_json
  rows_json="$(jq -s '.' "$rows_tmp")"
  rm -f "$rows_tmp"
  # --- 74 again: a record with no row proves nothing, the same fact as an order with no criterion --
  [ "$(printf '%s' "$rows_json" | jq 'length')" -gt 0 ] || [ "$BR_ORDER_SLOT" != "order-tests" ] \
    || die 74 "tests-freeze: $unit_id named no test, no doneWhen test and no checklist, so the record would hold no row and freeze a reference that proves nothing. A serving order freezes its tests against its own doneWhen: --test <path>::<name>=$unit_id, with the name ending in $unit_id, and one --row $unit_id=... judged against the doneWhen text."

  # --- 35: a record already frozen is unchanged when its rows are the same, whatever HEAD is now ---
  # The freeze commits (below), so freezing wo1, then wo2, then wo1 again finds HEAD moved by wo2's
  # commit. The same rows are the same freeze; different rows under a moved HEAD are the case 35
  # exists for, tests changed under a record nobody re-took.
  #
  # The same rows leave the frozen paths already in HEAD, so the commit below finds nothing to
  # commit. This run therefore sets a word here and returns after the ledger write, rather than
  # returning here. A judgement and a routed clause are in none of the rows compared here. So a
  # re-run that changes one of them and no test used to stop here and write nothing, and a routed
  # clause that never reaches the ledger never reaches review.
  local tf_unchanged_at=""
  if [ -f "$record_file" ] && [ "$existing_commit" != "$current_commit" ] && [ "$existing_commit" != "$tf_retake_commit" ]; then
    local existing_rows new_rows
    existing_rows="$(jq -cS '{unit, testGlobs, rows, support: (.support // [])}' "$record_file" 2>/dev/null)"
    new_rows="$(jq -cS -n --arg unit "$unit_id" --argjson testGlobs "$test_globs_json" --argjson rows "$rows_json" --argjson support "$support_json" '{unit: $unit, testGlobs: $testGlobs, rows: $rows, support: $support}')"
    [ "$existing_rows" = "$new_rows" ] \
      || die 35 "tests-freeze: $record_file was already frozen at commit $existing_commit, and this run is at a different commit, $current_commit, with different tests. A record is taken once per commit; investigate before proceeding."
    tf_unchanged_at="$existing_commit"
  fi

  # --- the test files go into a commit before anything is measured against them --------------------
  # The intent puts the commit before the build ("Tests are committed and hash-frozen before the
  # slice's implementer starts"). Without this, the implementer is the role that commits the tests
  # it is measured against, and the record names a commit the tests are not in (live-run row 62).
  # Only the frozen paths are taken, through a pathspec, so work beside them stays where it is, and
  # the line at the end says what was left. The helper dies before the record is written when the
  # commit fails, so a record never names a commit that did not happen. Paths already in HEAD carry
  # no change and make no commit: a pathspec commit of unchanged paths is a git error, not a no-op.
  # The support files ride in the same commit as the tests, so they are the author's in the
  # history and never land in the implementer's range (live-run row 90).
  local frozen_rel_paths tree_left
  frozen_rel_paths="$(jq -nr --argjson tests "$tests_json" --argjson support "$support_json" \
    '(($tests | map(.relPath)) + ($support | map(.path))) | unique | .[]')"
  if [ -n "$frozen_rel_paths" ]; then
    set --
    while IFS= read -r p; do
      [ -n "$p" ] && set -- "$@" "$p"
    done <<TF_EOF
$frozen_rel_paths
TF_EOF
    if [ -n "$(git -C "$codepath" status --porcelain -- "$@")" ]; then
      recipe_commit_if_changed "$codepath" tests-freeze "the test files are already in HEAD" \
        "Freeze the tests of $unit_id through the implement skill: $(printf '%s' "$frozen_rel_paths" | tr '\n' ' ')" \
        "$frozen_rel_paths"
      current_commit="$(git -C "$codepath" rev-parse HEAD 2>/dev/null)"
      [ -n "$current_commit" ] \
        || die 3 "tests-freeze: could not read the commit just made (git rev-parse HEAD failed in $codepath)."
    fi
  fi
  tree_left="$(git -C "$codepath" status --porcelain)"
  [ -z "$tree_left" ] \
    || printf 'tests-freeze: the tests are committed or unchanged, and other uncommitted changes remain in %s: %s\n' "$codepath" "$(printf '%s' "$tree_left" | tr '\n' ' ')" >&2

  # --- the checkpoint's verdict goes into the ledger, one judgement per order per criterion --------
  # Written before the record below, and on every path that reaches an exit, because a second freeze
  # with the same tests writes no record and must still carry the judgement a person or a checker
  # just made. A judgement this order already left is replaced rather than added to: one order
  # judges one criterion once, and two entries under one unit would count that row twice.
  #
  # The clauses routed to review ride here too, on the order's own entry. This runs whatever the
  # rows counted, because the routed list is replaced on every freeze: a re-freeze that drops a
  # clause must not leave it owed to review, and an order with no row at all can still route one.
  # The freeze already refuses a missing ledger at its last step, so requiring one here is no new
  # refusal.
  #
  # It runs after the commit above, and every return that follows it has written it. A commit that
  # fails refuses before this, so the ledger keeps what the live frozen record was taken with. A
  # write before the commit destroyed those values on a re-freeze whose commit failed, and that
  # freeze refused with two routed clauses already gone from the ledger (check ev).
  local ledger_file_now ledger_doc_now ledger_with_judgements
  ledger_file_now="$IMPL_DIR/ledger.json"
  [ -f "$ledger_file_now" ] \
    || die 3 "tests-freeze: $ledger_file_now is missing, though start writes it. Run start again."
  ledger_doc_now="$(jq -c '.' "$ledger_file_now" 2>/dev/null)"
  [ -n "$ledger_doc_now" ] \
    || die 3 "tests-freeze: $ledger_file_now exists but could not be read as JSON. Repair or remove it by hand before running this again."
  # The doneWhen row is keyed by the unit's own id and belongs to the order, not to a criterion,
  # so it lands on the order's ledger entry. Replaced or removed on every freeze, the same way a
  # criterion judgement this order already left is replaced rather than added to. The routed
  # clauses are replaced the same way, and removed when this freeze routed none. A freeze that gets
  # here had no rejected row, so the rows a person rejected earlier are answered and removed.
  ledger_with_judgements="$(printf '%s' "$ledger_doc_now" | jq -c \
    --arg unit "$unit_id" --argjson rows "$rows_meta_json" --argjson absences "$absence_json" '
    ([ $rows[] | select(.criterion == $unit) ][0]) as $dw
    | .criteria = ((.criteria // []) | map(
      . as $c
      | ([ $rows[] | select(.criterion == $c.id) ][0]) as $r
      | if $r == null then $c
        else ($c + {judgements: (
                (($c.judgements // []) | map(select(.unit != $unit)))
                + [{unit: $unit, verdict: $r.verdict, judgedBy: $r.judgedBy, note: $r.note}])})
        end))
    | .orders = ((.orders // []) | map(
      if .id != $unit then .
      else ((if $dw == null then del(.doneWhenJudgement)
             else .doneWhenJudgement = {verdict: $dw.verdict, judgedBy: $dw.judgedBy, note: $dw.note} end)
            | (if ($absences | length) == 0 then del(.absenceClauses)
               else .absenceClauses = $absences end)
            | del(.rowsRejected, .rowsConfirmed))
      end))')"
  [ -n "$ledger_with_judgements" ] \
    || die 3 "tests-freeze: the ledger update for $unit_id's judgements failed."
  write_atomic "$ledger_file_now" "$ledger_with_judgements"
  printf 'absenceClauses: %s (routed to review, on %s'"'"'s ledger entry)\n' \
    "$(printf '%s' "$absence_json" | jq 'length')" "$unit_id"
  [ "$tf_carried" = "[]" ] \
    || printf 'rowsCarried: %s\n' "$(printf '%s' "$tf_carried" | jq -r 'map(.criterion) | join(", ")')"

  if [ -n "$tf_unchanged_at" ]; then
    echo "TESTS-FREEZE: unchanged (already frozen at commit $tf_unchanged_at with the same tests)"
    printf '%s\n' "$record_file"
    exit 0
  fi

  # The recipe each red was read against, per framework, so the record says what the freeze read
  # and a later reader can compare it with what preconditions.json holds now (live-run row 99).
  # Absent when no red was read: a recipe served nothing then.
  local today record_json test_recipe_paths_json='null'
  if [ "$red_count" -gt 0 ] && [ -n "$test_recipes" ]; then
    test_recipe_paths_json="$(printf '%s' "$test_recipes" | jq -R -s '
      split("\n") | map(select(length > 0) | split("\t") | {key: .[0], value: .[1]}) | from_entries')"
  fi
  today="$(date -u +%Y-%m-%d)"
  record_json="$(jq -n --arg takenAt "$today" --arg unit "$unit_id" --arg commit "$current_commit" \
    --argjson testGlobs "$test_globs_json" --argjson rows "$rows_json" --arg proof "$tf_proof" --argjson support "$support_json" \
    --argjson testRecipePath "$test_recipe_paths_json" \
    '{schemaVersion: 1, takenAt: $takenAt, unit: $unit, commit: $commit, testGlobs: $testGlobs, rows: $rows, proof: $proof, support: $support}
     + (if $testRecipePath == null then {} else {testRecipePath: $testRecipePath} end)')"

  # A record that reaches here with different rows is retaken: the order is still at tests-frozen
  # (76 above) and HEAD was the earlier freeze commit (35 above), which is the route for a frozen
  # test whose oracle was wrong (live-run row 109). The earlier commit and date go under
  # retakenFrom, so the retake is visible in the record and not only in the branch. The comparison
  # sets retakenFrom aside with takenAt, so a rerun with the same rows after a retake stays unchanged.
  if [ -f "$record_file" ]; then
    local existing_no_date new_no_date existing_taken_at
    existing_no_date="$(jq -cS 'del(.takenAt, .retakenFrom)' "$record_file" 2>/dev/null)"
    new_no_date="$(printf '%s' "$record_json" | jq -cS 'del(.takenAt)')"
    if [ "$existing_no_date" = "$new_no_date" ]; then
      echo "TESTS-FREEZE: unchanged (already frozen at commit $current_commit with the same tests)"
      printf '%s\n' "$record_file"
      exit 0
    fi
    existing_taken_at="$(printf '%s' "$existing_doc" | jq -r '.takenAt // empty')"
    record_json="$(printf '%s' "$record_json" | jq -c --arg c "$existing_commit" --arg t "$existing_taken_at" \
      '. + {retakenFrom: {commit: $c, takenAt: $t}}')"
    echo "TESTS-FREEZE: retaken: $existing_commit -> $current_commit"
  fi

  write_atomic "$record_file" "$record_json"
  # The freeze is one step in this version: red was watched, the rows exist, and the hash is taken,
  # all checked above. So the order moves straight to tests-frozen and not through the four steps
  # the ledger's vocabulary keeps for a finer grain.
  tt_ledger_update "$IMPL_DIR/ledger.json" "$unit_id" '.lastStep = "tests-frozen"'
  echo "TESTS-FREEZE: written (commit $current_commit)"
  printf '%s\n' "$record_file"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# Step four: build-brief and build-record. The model writes the code; this script never does.
# `build-brief` assembles exactly what that model may see, from the frozen snapshot, the frozen
# test record for one unit, and the ledger. `build-record` verifies what came back: it runs all
# eight deciding checks docs/implementation.md names ("The deciding checks run before anything
# judges") and moves the attempt counter. Seven of them come from `br_seven_checks`, which a fix
# round calls again; the eighth, the interface record, is this step's own, and a fix round never
# re-runs it, because a fix round does not rewrite that record.
#
# `bb_` and `br_` are this section's own helper prefixes, kept apart from `pc_`, `tc_`, `tf_` and
# `tt_` above, which each belong to a different step. `build-record` still reuses `tf_` directly
# rather than carrying a second copy: `tf_path_matches_catalog_glob` for the owned-files check, and
# `tf_sha256_of` (with `records_hash__resolve_sha256_cmd`) for the frozen-tests check, because both
# are exactly the same computation `tests-freeze` already made, and a second matcher or a second
# hash function would be a second producer for one fact.
# ------------------------------------------------------------------------------------------------

# The frozen work order $2 from frozen snapshot $1. Sets BB_UNIT_JSON. Dies (exit 38) when the unit is
# not in the frozen copy, rather than returning a code: every caller of this helper treats that as
# fatal and would only turn around and exit itself. Kept apart from tt_load_unit_and_criteria, which
# dies on the same fact with exit 22, because build-brief's own refusal list names this fact as exit
# 38 rather than sharing tests-brief and tests-freeze's number (see exit 38's own comment above).
BB_UNIT_JSON=""
bb_load_unit() {
  local snapshot_doc="$1" unit_id="$2"
  BB_UNIT_JSON="$(printf '%s' "$snapshot_doc" | jq -c --arg id "$unit_id" \
    '(.workOrders // []) | map(select(.id == $id)) | .[0] // null')"
  [ "$BB_UNIT_JSON" != "null" ] || die 38 "build-brief: $unit_id is not in the frozen copy."
}

# The frozen tests record of unit $2, which step three writes. Sets IM_TESTS_DOC. $1 names the step
# in the message, and $3 is the exit code for a missing record: `build-brief` dies 39, and
# `dispatch-open implementer` dies 114 (gap row 267).
IM_TESTS_DOC=""
im_require_tests_record() {
  local tests_file="$IMPL_DIR/tests-$2.json"
  [ -f "$tests_file" ] \
    || die "$3" "$1: $tests_file not found. Step three has not run for $2 yet; run tests-brief and tests-freeze on it first."
  IM_TESTS_DOC="$(jq -c '.' "$tests_file" 2>/dev/null)"
  [ -n "$IM_TESTS_DOC" ] \
    || die 3 "$1: $tests_file exists but could not be read as JSON. Repair or remove it by hand before running this again."
}

# Every refusal build-brief takes from the order's records rather than from its own arguments:
# the tests record (exit $3, as above), the ledger, each dependency's completion record (exit
# 40), the order's step (exit 116) and the attempt counter (exit 41). `dispatch-open implementer` runs the same checks before
# it writes, so no builder opens for an order build-brief would refuse (gap row 281). The order's
# frozen work order is $4. Sets IM_TESTS_DOC, IM_ATTEMPTS_USED and IM_ATTEMPTS_ALLOWED.
IM_ATTEMPTS_USED=0; IM_ATTEMPTS_ALLOWED=0
im_require_build_ready() {
  local who="$1" unit_id="$2" unit_json="$4" ledger_doc
  im_require_tests_record "$who" "$unit_id" "$3"

  # --- the ledger: needed for the dependency check and the attempt count ---------------------------
  local ledger_file="$IMPL_DIR/ledger.json"
  [ -f "$ledger_file" ] \
    || die 3 "$who: $ledger_file not found, though $IMPL_DIR/snapshot.json exists. A snapshot with no ledger beside it is not a supported state; run start again."
  ledger_doc="$(jq -c '.' "$ledger_file" 2>/dev/null)"
  [ -n "$ledger_doc" ] \
    || die 3 "$who: $ledger_file exists but could not be read as JSON. Repair or remove it by hand before running this again."

  # --- exit 40, first: a repair this unit opened on a closed order has not closed again (gap row 286) --
  local repairing
  repairing="$(printf '%s' "$ledger_doc" | jq -r --arg u "$unit_id" \
    '[ (.orders // [])[] | select(.lastStep != "closed") | select(any((.repairs // [])[]; .by == $u)) | .id ] | join(", ")')"
  [ -z "$repairing" ] \
    || die 40 "$who: $unit_id stopped on a defect in a file $repairing owns, and that repair has not closed, so nothing of $unit_id is built until it does."

  # --- exit 40: every dependency needs a completion record before its interface is handed over ------
  local dep_id dep_entry dep_step
  while IFS= read -r dep_id; do
    [ -n "$dep_id" ] || continue
    dep_entry="$(printf '%s' "$ledger_doc" | jq -c --arg id "$dep_id" \
      '(.orders // []) | map(select(.id == $id)) | .[0] // null')"
    [ "$dep_entry" != "null" ] \
      || die 3 "$who: $unit_id depends on $dep_id, which has no entry in $ledger_file, though start opens one entry per snapshot work order."
    dep_step="$(printf '%s' "$dep_entry" | jq -r '.lastStep // "not started"')"
    [ "$dep_step" = "closed" ] \
      || die 40 "$who: $unit_id depends on $dep_id, which has no completion record ($ledger_file records its last step as $dep_step), so its interface record does not exist yet."
  done <<IM_DEPS
$(printf '%s' "$unit_json" | jq -r '(.dependsOn // [])[]')
IM_DEPS

  # --- exit 41: the attempt counter for this unit must still have room -----------------------------
  local order_entry
  order_entry="$(printf '%s' "$ledger_doc" | jq -c --arg id "$unit_id" \
    '(.orders // []) | map(select(.id == $id)) | .[0] // null')"
  [ "$order_entry" != "null" ] \
    || die 3 "$who: $unit_id has no entry in $ledger_file, though start opens one entry per snapshot work order."

  # --- exit 116: a build starts or resumes only where `read` routes one --------------------------
  # tests-frozen is the first build, and the step a retake-tests returns to. code-written is a
  # failed attempt, rebuilt while attempts remain. A builder stopped at its turn limit records
  # nothing, so its resume finds one of these two. A fix round dispatches the fixer, not this role.
  local step after
  step="$(printf '%s' "$order_entry" | jq -r '.lastStep // "not started"')"
  case "$step" in
    tests-frozen|code-written) ;;
    *)
      case "$step" in
        checks-passed) after="Its checks passed, so run review-brief on $unit_id next." ;;
        reviewed|fixed) after="It is in review, so run fix-brief, verify-brief or close on $unit_id, as read routes it." ;;
        closed) after="It is closed, so nothing more is built for it." ;;
        *) after="Run tests-freeze on $unit_id first." ;;
      esac
      die 116 "$who: $unit_id is at step $step in $ledger_file, and a build starts only from tests-frozen or code-written. $after" ;;
  esac
  IM_ATTEMPTS_USED="$(printf '%s' "$order_entry" | jq -r '.attemptsUsed // 0')"
  case "$IM_ATTEMPTS_USED" in ''|*[!0-9]*) IM_ATTEMPTS_USED=0 ;; esac
  IM_ATTEMPTS_ALLOWED="$(attempts_allowed_for "$order_entry")"
  [ "$IM_ATTEMPTS_USED" -lt "$IM_ATTEMPTS_ALLOWED" ] \
    || die 41 "$who: $unit_id has already used $IM_ATTEMPTS_USED of $IM_ATTEMPTS_ALLOWED allowed attempts. Nothing more is handed over."
}

do_build_brief() {
  [ "$#" -ge 2 ] || die 3 "build-brief: a task folder and a unit id are required"
  [ "$#" -le 2 ] || die 3 "build-brief: unrecognized extra argument: $3"
  local unit_id="$2"
  local resolve_rc
  TASK_PATH="$(resolve_task_folder "$1" "build-brief")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  IMPL_DIR="$TASK_PATH/implementation"

  # --- exit 42: this step ran before start, so there is no frozen copy to read from ---------------
  local snapshot_file="$IMPL_DIR/snapshot.json"
  [ -f "$snapshot_file" ] \
    || die 42 "build-brief: $snapshot_file not found. This step ran before start, so there is no frozen copy. Run start on this task first."
  local snapshot_doc
  snapshot_doc="$(jq -c '.' "$snapshot_file" 2>/dev/null)"
  [ -n "$snapshot_doc" ] \
    || die 3 "build-brief: $snapshot_file exists but could not be read as JSON, though start already wrote it. Repair or remove it by hand before running this again."

  # --- exit 38: the unit itself must be in the frozen copy -----------------------------------------
  bb_load_unit "$snapshot_doc" "$unit_id"

  # --- exits 39, 40 and 41, and the ledger: the order's records must allow a build ----------------
  im_require_build_ready "build-brief" "$unit_id" 39 "$BB_UNIT_JSON"
  local attempts_used="$IM_ATTEMPTS_USED" attempts_allowed="$IM_ATTEMPTS_ALLOWED"

  # Every dependency is closed by now. dep_interface is declared here, never inside the loop, for
  # the reason tests-brief states above and this file's own header records as trap 5.
  local depends_json dep_count i dep_id dep_interface dependency_interfaces_json='[]'
  local dep_record_file dep_record_text dependency_information_json='[]'
  depends_json="$(printf '%s' "$BB_UNIT_JSON" | jq -c '.dependsOn // []')"
  dep_count="$(printf '%s' "$depends_json" | jq 'length')"
  i=0
  while [ "$i" -lt "$dep_count" ]; do
    dep_id="$(printf '%s' "$depends_json" | jq -r --argjson i "$i" '.[$i]')"
    dep_interface="$(printf '%s' "$snapshot_doc" | jq -r --arg id "$dep_id" \
      '(.workOrders // []) | map(select(.id == $id)) | .[0].interface // ""')"
    # Both texts, each labelled. The declaration is what design promised; the record is what the
    # builder says it exposed, and the two can differ. The next order writes its tests and its
    # code against the record where one exists, which is what build.md and the two agent files
    # already say and what neither brief carried.
    dep_record_file="$IMPL_DIR/build-$dep_id.json"
    dep_record_text=""
    if [ -f "$dep_record_file" ]; then
      dep_record_text="$(jq -r '.interfaceRecord // ""' "$dep_record_file" 2>/dev/null)"
    fi
    dependency_interfaces_json="$(printf '%s' "$dependency_interfaces_json" | jq -c \
      --arg id "$dep_id" --arg iface "$dep_interface" --arg rec "$dep_record_text" '
      . + [ {id: $id, declaredInterface: $iface, interface: $iface}
            + (if $rec == "" then {} else {interfaceRecord: $rec} end) ]')"
    dependency_information_json="$(im_dependency_information "$dependency_information_json" "$dep_id")"
    i=$((i + 1))
  done

  # A later attempt starts from the earlier one's committed code. The build record keeps the last
  # attempt only, so its stoppers are what that attempt failed on, read here and not recomputed
  # (gap row 220).
  local previous_attempt_json="null" prev_record_file="$IMPL_DIR/build-$unit_id.json"
  if [ "$attempts_used" -gt 0 ] && [ -f "$prev_record_file" ]; then
    previous_attempt_json="$(jq -c --arg path "$prev_record_file" "$BR_STOPPERS_JQ"'
      (.checks // []) as $checks | ($checks | stoppers) as $ids
      | {attempt, recordPath: $path,
         failedChecks: [ $checks[] | select(.id as $i | $ids | index($i))
                         | {id, verdict, detail} + (if has("newLines") then {newLines} else {} end) ]}
      | if (.failedChecks | length) == 0 then null else . end' \
      "$prev_record_file" 2>/dev/null)"
    [ -n "$previous_attempt_json" ] || previous_attempt_json="null"
  fi

  # --- assemble the brief: exactly these keys, and nothing else ------------------------------------
  local unit_out tests_out
  unit_out="$(printf '%s' "$BB_UNIT_JSON" | jq -c \
    --argjson interfaceNames "$(br_interface_names "$(printf '%s' "$BB_UNIT_JSON" | jq -r '.interface // ""')")" \
    "$REASONING_JQ"'
    {id, title, ownedFiles: (.ownedFiles // []), interface: (.interface // ""), interfaceNames: $interfaceNames,
      doneWhen: (.doneWhen // []), diffBudget: (.diffBudget // ""), reasoning: liveReasoning,
      proof: (.proof // "tests"), verify: (.verify // []),
      findings: [ (.findings // [])[] | select(has("setAside") | not) | {ref, text} ]}')"
  # One entry per (row, test): a test naming several criteria appears once in each criterion's own
  # row in the frozen record, and this keeps that same shape rather than collapsing it.
  tests_out="$(printf '%s' "$IM_TESTS_DOC" | jq -c \
    '[ (.rows // [])[] | select(.kind == "machine") | .criterion as $c | (.tests // [])[]
       | {path, name, criterion: $c} ]')"

  # The caller needs the commit this attempt begins from, for --started-at when it records. It was
  # told to run `git rev-parse HEAD` itself, which needs a grant the skill does not carry. An
  # order whose proof is record commits in the project folder, so its commit is read there and
  # the brief says so under commitIn (nyc defect 17).
  local bb_codepath bb_head
  bb_head=""
  rv_load_codepath "build-brief"
  br_order_facts "$BB_UNIT_JSON"
  if [ "$BR_ORDER_RANGE" = "project" ]; then
    bb_codepath="$(resolve_project_folder "$TASK_PATH")"
  else
    bb_codepath="$RV_CODEPATH"
  fi
  if [ -n "$bb_codepath" ] && [ -d "$bb_codepath" ]; then
    bb_head="$(git -C "$bb_codepath" rev-parse HEAD 2>/dev/null)"
  fi
  # An order whose proof is observe owes a look before the build, at this headNow. A row that
  # says the page is as it was needs that before to judge from (live-run row 114). The folder is
  # named here; the orchestrator fills it once, on the first attempt, and every later attempt
  # and fix round reuse it. The state is read from the folder, not the ledger: an image there is
  # a look taken, and nothing else records one.
  local bb_before bb_before_state
  bb_before=""; bb_before_state=""
  if [ "$BR_ORDER_SLOT" = "observed" ]; then
    bb_before="$IMPL_DIR/observed-$unit_id-before"
    if [ -n "$(find "$bb_before" -mindepth 1 -maxdepth 1 -type f -name '*.png' 2>/dev/null | head -n 1)" ]; then
      bb_before_state="taken"
    else
      bb_before_state="owed"
    fi
  fi
  # The report has one named path per attempt, so a later attempt never writes over the answers a
  # reviewer already compared a diff against. The brief is one file per order, rewritten on each
  # attempt: only its counters and its report path change between two attempts. The interface
  # record has one path per order, named here so the implementer writes it where build-record
  # reads it, instead of a path each implementer chose (live-run row 102).
  local brief_file brief_json
  brief_file="$IMPL_DIR/brief-$unit_id-build.json"
  brief_json="$(jq -n --argjson unit "$unit_out" --argjson tests "$tests_out" --arg headNow "$bb_head" \
        --arg commitIn "$bb_codepath" --arg worktree "$RV_CODEPATH" \
        --argjson dependencyInterfaces "$dependency_interfaces_json" \
        --argjson dependencyInformation "$dependency_information_json" \
        --arg reportPath "$IMPL_DIR/answers-$unit_id-attempt$((attempts_used + 1)).md" \
        --arg interfacePath "$IMPL_DIR/interface-$unit_id.md" \
        --argjson attemptsUsed "$attempts_used" --argjson attemptsAllowed "$attempts_allowed" \
        --argjson playbooksPath "$(playbooks_path_json "$TASK_PATH")" \
        --arg beforeLookPath "$bb_before" \
        --argjson previousAttempt "$previous_attempt_json" \
        --arg fakeMarker "$(! task_is_light "$TASK_PATH" || printf '%s' "$FAKE_MARKER")" \
    '{unit: $unit, worktree: $worktree, tests: $tests, headNow: $headNow, commitIn: $commitIn,
      dependencyInterfaces: $dependencyInterfaces, dependencyInformation: $dependencyInformation,
      reportPath: $reportPath, interfacePath: $interfacePath, playbooksPath: $playbooksPath,
      attemptsUsed: $attemptsUsed, attemptsAllowed: $attemptsAllowed}
     + (if $beforeLookPath == "" then {} else {beforeLookPath: $beforeLookPath} end)
     + (if $previousAttempt == null then {} else {previousAttempt: $previousAttempt} end)
     + (if $fakeMarker == "" then {} else {fakeMarker: $fakeMarker} end)')"
  [ -n "$brief_json" ] || die 3 "build-brief: could not assemble the brief for $unit_id."
  write_atomic "$brief_file" "$brief_json"
  # headNow is printed because the caller passes it back as --started-at, and the report path
  # because the dispatch names it. Everything else the implementer reads from the file. The
  # before-look line prints only for an observe order, with its state, and next names the look
  # while it is owed.
  im_print_summary "build-brief" "$(printf '%s' "$brief_json" | jq -c --arg brief "$brief_file" --arg beforeState "$bb_before_state" '
    {order: .unit.id,
     brief: $brief,
     worktree: .worktree,
     reportPath: .reportPath,
     interfacePath: .interfacePath,
     headNow: (if .headNow == "" then "none: the commit of \(.commitIn) could not be read" else .headNow end),
     commitIn: .commitIn,
     attempts: "\(.attemptsUsed) of \(.attemptsAllowed) used",
     ownedFiles: (.unit.ownedFiles | length),
     frozenTests: (.tests | length),
     dependencyInterfaces: ([ .dependencyInterfaces[] | .id + (if has("interfaceRecord") then " (record)" else " (declared only)" end) ]),
     dependencyInformation: (.dependencyInformation | length)}
    + (if has("beforeLookPath") then {beforeLook: "\(.beforeLookPath) (\($beforeState))"} else {} end)
    + {next: (if $beforeState == "owed"
              then "take the before-look at headNow into the beforeLook folder, then dispatch implementer with the brief path and the implement recipe path, then build-record"
              else "dispatch implementer with the brief path and the implement recipe path, then build-record" end)}')"
  exit 0
}


# Exit 71. A base commit that is HEAD itself makes the diff empty, so the owned-files check answers
# met over nothing, the round writes an empty patch, and a reviewer reads no findings on it. A base
# commit that is not an ancestor of HEAD names a range that is not this order own work at all.
# Exit 43 stays the separate fact that the value is not a commit in this repository.
# $1 the action, $2 the code repository, $3 the value as given, $4 it peeled to a commit, $5 HEAD.
br_require_real_base() {
  local who="$1" repo="$2" given="$3" full="$4" head_now="$5"
  [ "$full" != "$head_now" ] \
    || die 71 "$who: --started-at ($given) is the commit $repo is at now. The range between them is empty, so every check would answer about no change at all. Pass the commit the work began from."
  git -C "$repo" merge-base --is-ancestor "$full" "$head_now" >/dev/null 2>&1 \
    || die 71 "$who: --started-at ($given, $full) is not an ancestor of HEAD ($head_now) in $repo, so the range between the two is not this order own work."
}

# ------------------------------------------------------------------------------------------------
# The seven computable deciding checks (ideal/implementation.md, "The deciding checks run before
# anything judges"). `build-record` runs these seven and the interface check below it.
# `fix-record` runs these seven again after a fix round and never the interface check, because a
# fix round does not rewrite the interface record. One function for both, so the two steps cannot
# drift into checking different things.
#
# Redirect this function's stdout to a file. Never capture it with `$(...)`: a command substitution
# runs in a subshell, and a refusal inside this function would then exit that subshell alone and
# let the caller carry on past it.
#
# The caller sets these globals first. They are globals rather than fourteen positional arguments,
# because a positional list that long is read wrong sooner than it is read right.
#   BRC_WHO             the action's own name, for a message
#   BRC_CODEPATH        the code repository every command runs from inside
#   BRC_STARTED_AT      the commit this attempt or round began from, full form
#   BRC_CURRENT         the code repository's HEAD now
#   BRC_SCOPE           the one path the owned-files diff is scoped to, RV_RANGE_SCOPE: the task
#                       folder for an order whose proof is record, empty for the whole tree
#   BRC_UNIT_JSON       the frozen work order
#   BRC_TESTS_DOC       the frozen test record for this order
#   BRC_BASELINE_FILE   where step two wrote the baseline
#   BRC_RECIPES         the resolved recipe document cr_resolve wrote (CR_DOC): one entry per
#                       framework with its suite and selected-tests commands, and one entry per
#                       tool row with its argv, its signal and its extensions. Every command this
#                       function runs comes from here, never from a flag a caller typed
#   BRC_SELECTED_JSON   the paths a `{paths}` or `{file}` token in the selected-tests row expands
#                       to: this order's own frozen test files, relative to codePath. The three
#                       tool rows leave these same paths out of their own expansion
#   BRC_VALUES          the tab-separated `--value` list every other placeholder is read from
#   BRC_NOTHING_RAN, BRC_HAVE_NOTHING_RAN   the caller's own marker for a green run that selected
#                       nothing, used only where the framework's recipe declares none of its own
#   BRC_GATE_RECIPES    the tab-separated `--implement-recipe` list, one `<framework>\t<path>` per
#                       line, read only for an order whose proof is gate: the recipe whose
#                       `## Configuration gate` lines are that order's own check
#   BRC_END_OF_TASK     true only under `finish`. A suite row the recipe costs `end-of-task` is
#                       deferred by the two record steps and runs here once (nyc defect 18)
#   BRC_OBSERVED        the observed record's path, read only for an order whose proof is
#                       observe: `build-record` takes it from --observed, checked first; a fix
#                       round and a re-check read the path the build step names,
#                       <task_folder>/implementation/observed-<unit_id>.json
#   BRC_ALLOWED_JSON    the paths a person allowed for this fix round with `fix-brief --allow`,
#                       the round's brief's `allowedFiles`. The owned-files check reads them
#                       beside the order's ownedFiles (live-run row 116). A build attempt
#                       leaves it `[]`
# ------------------------------------------------------------------------------------------------
BRC_WHO=""; BRC_CODEPATH=""; BRC_STARTED_AT=""; BRC_CURRENT=""; BRC_SCOPE=""
BRC_UNIT_JSON=""; BRC_TESTS_DOC=""; BRC_BASELINE_FILE=""; BRC_ALLOWED_JSON="[]"
BRC_RECIPES='{"frameworks":[],"tools":[]}'; BRC_SELECTED_JSON="[]"; BRC_VALUES=""
BRC_NOTHING_RAN=""; BRC_HAVE_NOTHING_RAN=false
BRC_GATE_RECIPES=""
BRC_END_OF_TASK=false
BRC_OBSERVED=""

# One tool check: coding standards, static analysis, or the security tool. $1 the check id, $2 the
# baseline field holding the same tool's own verdict, $3 a word for the message. The command itself
# comes from the resolved recipe in BRC_RECIPES, never from a flag: a caller retyping a recipe row
# drops a key, and a dropped `signal` key turns a tool that cannot fail by exit status into a check
# that always passes. Prints the check object.
#
# Exit 0 is met. Any other exit is compared against the baseline for that tool, the same rule
# suite-regression already applies: a baseline that was met makes this unmet, because this order
# introduced the finding; a baseline that was unmet has its own output subtracted line by line
# (br_subtract_baseline), so a finding already there at the commit the build started from is not
# this order's; a baseline that was unknown or undeclared makes this unknown, naming which,
# because there is nothing to subtract from.
#
# Two optional keys change that (dev-guides, process-recipes, `## Check commands` is parsed).
# `extensions` narrows what {paths} expands to; a row whose expansion comes out empty did not apply
# to this order and is recorded undeclared, never met. `empty-stdout` marks a tool that cannot fail
# by exit status, gofmt -l being the case it was written for: a zero exit with anything on standard
# output counts as a failure. Both ways of failing then go through the same baseline comparison,
# because a finding this tool already reported at the commit the build started from is not one this
# order introduced, and which of the two ways the tool used to say so changes nothing about that.
br_tool_check() {
  local check_id="$1" field="$2" label="$3"
  local row argv_json signal exts_json absent_declared missing_why
  local verdict detail exit_json out_src outfile errfile rc has_paths
  local owned_json owned_count scoped_json scoped_count stdout_len failed how
  local baseline_doc baseline_verdict baseline_output result kind payload new_json new_count
  local left_out_json paths_json expanded_json oi entry
  verdict=""; detail=""; exit_json="null"; out_src="/dev/null"; outfile=""; new_json="[]"; new_count=0
  left_out_json="[]"; paths_json="null"

  row="$(printf '%s' "$BRC_RECIPES" | jq -c --arg id "$check_id" '[ (.tools // [])[] | select(.id == $id) ][0] // null')"
  absent_declared=""
  missing_why=""
  if [ "$row" = "null" ]; then
    missing_why="no check recipe was resolved for this task, so $label was not checked."
  else
    absent_declared="$(printf '%s' "$row" | jq -r 'if (.absent // false) then (.absentReason // "the recipe declares this row absent") else "" end')"
    missing_why="$(printf '%s' "$row" | jq -r '.missing // ""')"
  fi

  if [ -n "$absent_declared" ]; then
    # A recipe that declares this framework has no such tool answered the question, and its own
    # reason text is what a person reads when they ask why the check never ran. A row nobody
    # resolved answered nothing. Both are undeclared, because undeclared is never satisfied either
    # way, and `absent` is what tells the two apart.
    jq -n --arg id "$check_id" --arg detail "$absent_declared" \
      '{id: $id, verdict: "undeclared", detail: $detail, absent: true}'
    return 0
  fi
  if [ -n "$missing_why" ]; then
    jq -n --arg id "$check_id" --arg detail "$missing_why" \
      '{id: $id, verdict: "undeclared", detail: $detail}'
    return 0
  fi

  argv_json="$(printf '%s' "$row" | jq -c '.argv // []')"
  signal="$(printf '%s' "$row" | jq -r '.signal // ""')"
  exts_json="$(printf '%s' "$row" | jq -c 'if has("extensions") then .extensions else empty end')"

  has_paths=false
  br_argv_takes_paths "$argv_json" && has_paths=true
  owned_json="$(printf '%s' "$BRC_UNIT_JSON" | jq -c '.ownedFiles // []')"
  owned_count="$(printf '%s' "$owned_json" | jq 'length')"
  # The tools judge the files the builder may write. A frozen test is owned, so the diff may touch
  # it, but the implementer may not: hooks/deny-frozen-test-writes.sh refuses the write, and the
  # only role that may edit it has already returned (live-run row 71). So the frozen paths, which
  # the caller already resolved into BRC_SELECTED_JSON, come out of the expansion first, and the
  # record names both what the token expanded to and what was left out. An owned entry may be a
  # directory (design-schema.json), and a whole-string subtraction would hand the tool the frozen
  # tests under it, so a directory is expanded to the files the repository tracks under it first.
  expanded_json="[]"
  oi=0
  while [ "$oi" -lt "$owned_count" ]; do
    entry="$(printf '%s' "$owned_json" | jq -r --argjson i "$oi" '.[$i]')"
    if [ -d "$BRC_CODEPATH/$entry" ]; then
      expanded_json="$(git -C "$BRC_CODEPATH" ls-files -- "$entry" 2>/dev/null \
        | jq -Rsc --argjson acc "$expanded_json" '$acc + (split("\n") | map(select(length > 0)))')"
    else
      expanded_json="$(printf '%s' "$expanded_json" | jq -c --arg e "$entry" '. + [$e]')"
    fi
    oi=$((oi + 1))
  done
  if [ "$has_paths" = "true" ]; then
    left_out_json="$(jq -cn --argjson owned "$expanded_json" --argjson frozen "$BRC_SELECTED_JSON" \
      '[ $owned[] | select(. as $p | $frozen | index($p) != null) ]')"
  fi
  scoped_json="$(jq -cn --argjson owned "$expanded_json" --argjson frozen "$BRC_SELECTED_JSON" \
    '[ $owned[] | select(. as $p | $frozen | index($p) == null) ]')"
  if [ -n "$exts_json" ]; then
    scoped_json="$(br_filter_extensions "$scoped_json" "$exts_json")"
  fi
  br_scope_to_repository "$scoped_json" "$BRC_CODEPATH"
  scoped_json="$BR_INSIDE_JSON"
  scoped_count="$(printf '%s' "$scoped_json" | jq 'length')"

  if [ "$has_paths" = "true" ] && [ "$owned_count" -eq 0 ]; then
    # A tool handed no path at all reads that as its own default scope, so it would answer about
    # the whole repository under this order's name. That is a wrong verdict, not a missing one.
    verdict="unknown"
    detail="the $label command holds a path placeholder, and this order declares no ownedFiles, so the command would run over no path at all."
  elif [ "$has_paths" = "true" ] && [ "$scoped_count" -eq 0 ]; then
    # The order owns files, and none of them is a file this tool judges: every one is a frozen test,
    # or none carries an extension the tool reads, or every one lies outside the repository, or
    # every one was deleted by this order. The row did not apply here.
    verdict="undeclared"
    if [ "$BR_OUTSIDE_COUNT" -gt 0 ]; then
      detail="the $label command would read no file this order owns inside the code repository ($BR_OUTSIDE_COUNT owned outside it), so the row does not apply to it.$(br_deleted_note)"
    elif [ "$BR_DELETED_COUNT" -gt 0 ]; then
      detail="the $label command would read no file this order owns that still exists at the attempt's head, so the row does not apply to it.$(br_deleted_note)"
    elif [ -n "$exts_json" ]; then
      detail="the $label command reads only $(printf '%s' "$exts_json" | jq -r 'join(", ")'), and this order owns no file with one of those extensions outside its frozen tests, so the row does not apply to it."
    else
      detail="every file this order owns is a frozen test, which the implementer may not write, so the row does not apply to it."
    fi
  else
    [ "$has_paths" = "false" ] || paths_json="$scoped_json"
    outfile="$(mktemp)" || die 3 "$BRC_WHO: could not create a temporary file"
    errfile=""
    stdout_len=0
    if [ -n "$signal" ]; then
      errfile="$(mktemp)" || die 3 "$BRC_WHO: could not create a temporary file"
      result="$(br_run_resolved "$argv_json" "$BRC_CODEPATH" "$outfile" "$scoped_json" "$BRC_VALUES" "$errfile")"
    else
      result="$(br_run_resolved "$argv_json" "$BRC_CODEPATH" "$outfile" "$scoped_json" "$BRC_VALUES")"
    fi
    kind="$(printf '%s' "$result" | cut -f1)"
    payload="$(printf '%s' "$result" | cut -f2-)"
    if [ "$kind" = "UNRESOLVED" ]; then
      verdict="unknown"
      detail="the token {$payload} in the $label command has no supplied value; pass --value $payload=<value>."
    elif [ "$kind" = "EMPTY" ]; then
      verdict="unknown"
      detail="the $label command came out with no token at all, so nothing ran and nothing was decided."
    else
      rc="$payload"
      if [ -n "$signal" ]; then
        stdout_len="$(wc -c <"$outfile" 2>/dev/null | tr -d '[:space:]')"
        case "$stdout_len" in ''|*[!0-9]*) stdout_len=0 ;; esac
        # The baseline joined the two streams the same way, standard output first.
        cat "$errfile" >>"$outfile" 2>/dev/null
      fi
      out_src="$outfile"
      exit_json="$rc"
      failed=false; how=""
      if [ "$rc" = "0" ] && [ -n "$signal" ] && [ "$stdout_len" -gt 0 ]; then
        failed=true
        how="exited 0 and printed on standard output, which its row's own signal empty-stdout makes a finding"
      elif [ "$rc" = "126" ]; then
        verdict="unknown"
        detail="the $label command list came out empty, so nothing ran and nothing was decided."
      elif [ "$rc" != "0" ]; then
        failed=true
        how="exited $rc"
      fi
      if [ -z "$verdict" ]; then
        if [ "$failed" = "false" ]; then
          verdict="met"
          if [ -n "$signal" ]; then
            detail="the $label command exited 0 with nothing on standard output, which is what signal empty-stdout asks for."
          else
            detail="the $label command exited 0 over this order's own files."
          fi
        else
          baseline_verdict=""; baseline_output=""
          if [ -f "$BRC_BASELINE_FILE" ]; then
            baseline_doc="$(jq -c '.' "$BRC_BASELINE_FILE" 2>/dev/null)"
            if [ -n "$baseline_doc" ]; then
              baseline_verdict="$(printf '%s' "$baseline_doc" | jq -r --arg f "$field" '.[$f].verdict // ""')"
              baseline_output="$(printf '%s' "$baseline_doc" | jq -r --arg f "$field" '.[$f].outputFile // ""')"
              [ -z "$baseline_output" ] || baseline_output="$(dirname -- "$BRC_BASELINE_FILE")/$baseline_output"
            fi
          fi
          case "$baseline_verdict" in
            met)
              verdict="unmet"
              detail="the $label command $how, and the baseline recorded this tool met at the commit the build started from; this order introduced the finding."
              ;;
            unmet)
              br_subtract_baseline "$baseline_output" "$outfile" "$label" "$how"
              verdict="$BR_SUB_VERDICT"; detail="$BR_SUB_DETAIL"
              new_json="$BR_SUB_NEW"; new_count="$BR_SUB_COUNT"
              ;;
            unknown|undeclared)
              verdict="unknown"
              detail="the $label command $how, and the baseline recorded this tool $baseline_verdict at the commit the build started from, so there is nothing to subtract and this cannot tell an old finding from a new one."
              ;;
            *)
              verdict="unknown"
              detail="the $label command $how, and $BRC_BASELINE_FILE could not be read for this tool's own baseline verdict, so this cannot tell an old finding from a new one."
              ;;
          esac
        fi
      fi
    fi
    [ -z "$errfile" ] || rm -f "$errfile"
    [ "$has_paths" = "false" ] || detail="$detail$(br_outside_note)$(br_deleted_note)"
  fi
  # The output is read from its file, never passed as an argument (nyc defect 9).
  jq -n --arg id "$check_id" --arg verdict "$verdict" --arg detail "$detail" \
        --argjson exitCode "$exit_json" --rawfile output "$out_src" \
        --arg signal "$signal" --arg exts "${exts_json:-}" \
        --argjson newLines "$new_json" --argjson newLineCount "$new_count" \
        --argjson paths "$paths_json" --argjson leftOut "$left_out_json" \
        --arg framework "$(printf '%s' "$row" | jq -r '.framework // ""')" '
    {id: $id, verdict: $verdict, detail: $detail}
    + (if $framework == "" then {} else {framework: $framework} end)
    + (if $exitCode == null then {} else {exitCode: $exitCode, output: $output} end)
    + (if $newLineCount == 0 then {} else {newLines: $newLines, newLineCount: $newLineCount} end)
    + (if $signal == "" then {} else {signal: $signal} end)
    + (if $exts   == "" then {} else {extensions: ($exts | fromjson)} end)
    + (if $paths == null then {} else {paths: $paths} end)
    + (if ($leftOut | length) == 0 then {} else {frozenTestsLeftOut: $leftOut} end)
  '
  [ -z "$outfile" ] || rm -f "$outfile"
}

# The clause a finish suite detail ends with when no line matched the selector and the row has no
# warning_line (gap row 268). $1 the row's warning_line, $2 the framework entry. Prints nothing
# outside finish or with a key. A recipe outside the project's own recipe folders is a catalog
# copy a refresh replaces, so the person copies it into a folder and points the task at the copy.
br_warning_hint() {
  local warning="$1" fw_obj="$2" recipe fw line loc="" own="" name tab
  [ "$BRC_END_OF_TASK" = "true" ] && [ -z "$warning" ] && [ -n "${RV_PROJECT_FOLDER:-}" ] || return 0
  recipe="$(printf '%s' "$fw_obj" | jq -r '.testRecipe')"
  fw="$(printf '%s' "$fw_obj" | jq -r '.framework')"
  tab="$(printf '\t')"
  while IFS= read -r line; do
    [ "${line%%"$tab"*}" = "folder" ] || continue
    [ -n "$loc" ] || loc="${line#*"$tab"}"
    case "$recipe" in "${line#*"$tab"}"/*) own="yes" ;; esac
  done <<BWH_LINES
$(sw_source_lines "$RV_PROJECT_FOLDER/project.json" processRecipes)
BWH_LINES
  printf ' The suite row in %s declares no warning_line, so finish cannot read this red as runner warnings. warning_line is a regular expression for the lines a runner prints that fail no test.' "$recipe"
  if [ -n "$own" ]; then
    printf ' If the output holds no failed test, only runner warnings, a person adds warning_line to that row, under failure_line, and runs finish again.'
  else
    name="$(jq -r '.name // empty' "$RV_PROJECT_FOLDER/project.json" 2>/dev/null)"
    printf ' That file is not in a recipe folder this project declares, and a catalog refresh replaces it.'
    printf ' If the output holds no failed test, only runner warnings, a person copies it to %s/process-recipes/%s/test-execution.md and adds warning_line to its suite row, under failure_line.' "${loc:-<folder>}" "$fw"
    [ -n "$loc" ] || printf ' Declare that folder first, with project-actions.sh add-source %s processRecipes <folder>.' "$name"
    printf ' Then point this task at the copy, with implement-actions.sh recipe-refresh %s --recipe %s=<the copy>, and run finish again.' "$TASK_PATH" "$fw"
  fi
  printf ' finish then names the routes.'
}

# One commanded test check: order-tests or suite-regression. $1 the check id, $2 the field of each
# framework entry holding the command (`orderTests` or `suite`), $3 a word for the message. The
# command comes from the recipe, and it runs once per framework the task resolved one for, because
# the build runs in one repository that is all of them at once. Prints the check object.
#
# suite-regression compares a failure against the baseline suite; order-tests does not, because a
# test this order owns did not exist when the baseline was taken.
#
# A suite row the recipe costs `end-of-task` does not run at a record step. On a Drupal project
# that row is ten minutes and a site boot per Functional test, and it ran seven times for one
# order (nyc defect 18). The check is recorded deferred, which passes the way undeclared does, and
# `finish` runs the same row once with BRC_END_OF_TASK set. order-tests already runs this order's
# own frozen tests every attempt, so the evidence about this order's code is not lost.
#
# The suite row's `warning_line` is read under `finish` alone, and a suite red only on those
# lines reads warned (gap row 261). A record step's pass and stop rules know five verdicts, and a
# sixth there would stop an attempt without naming a stopper; `finish` refuses on it by name.
br_test_check() {
  local check_id="$1" field="$2" label="$3"
  local fw_count fwi fw_obj fw cmd argv_json paths_json result kind payload
  local runs='[]' verdicts='[]' verdict detail outfile rc marker_json markers_len mi marker
  local nothing_ran_hit baseline_doc baseline_verdict baseline_output new_json new_count selector
  local runs_file warning warn_json

  fw_count="$(printf '%s' "$BRC_RECIPES" | jq '(.frameworks // []) | length')"
  case "$fw_count" in ''|*[!0-9]*) fw_count=0 ;; esac
  paths_json='[]'
  [ "$field" = "orderTests" ] && paths_json="$BRC_SELECTED_JSON"
  # The suite's whole output goes into the record, and a command-line argument caps at 128KB on
  # Linux, so a long run made jq refuse to start and the check went missing from the record (nyc
  # defects 9 and 12). Every hop that carries the output reads it from a file instead.
  runs_file="$(mktemp)" || die 3 "$BRC_WHO: could not create a temporary file"

  fwi=0
  while [ "$fwi" -lt "$fw_count" ]; do
    fw_obj="$(printf '%s' "$BRC_RECIPES" | jq -c --argjson i "$fwi" '.frameworks[$i]')"
    fw="$(printf '%s' "$fw_obj" | jq -r '.framework')"
    cmd="$(printf '%s' "$fw_obj" | jq -c --arg f "$field" '.[$f] // {}')"
    verdict=""; detail=""; rc=""; new_json="[]"; new_count=0; warn_json="[]"; warning=""
    selector="$(pc_unquote "$(printf '%s' "$cmd" | jq -r '.failureLine // ""')")"
    [ "$BRC_END_OF_TASK" != "true" ] || warning="$(pc_unquote "$(printf '%s' "$cmd" | jq -r '.warningLine // ""')")"
    if [ "$(printf '%s' "$cmd" | jq -r 'has("absent")')" = "true" ]; then
      verdict="undeclared"
      detail="$(printf '%s' "$cmd" | jq -r '.absent')"
    elif [ "$(printf '%s' "$cmd" | jq -r 'has("missing")')" = "true" ]; then
      verdict="undeclared"
      detail="$(printf '%s' "$cmd" | jq -r '.missing')"
    elif [ "$field" = "orderTests" ] && [ "$(printf '%s' "$paths_json" | jq 'length')" -eq 0 ]; then
      # An order serving only criteria a person verifies legitimately froze no test: its rows are
      # checklists, and completion confirms those, not the build (ideal/implementation.md, "A
      # criterion a person inspects has no tests"). The floor stays for every other order: a
      # machine row with no test path is a record nothing can run, and it reads unknown.
      if [ "$(printf '%s' "$BRC_TESTS_DOC" | jq '(.rows // []) | length > 0 and all(.[]; .kind == "person")')" = "true" ]; then
        verdict="met"
        detail="this order serves only criteria a person verifies, so its frozen record carries checklist rows and no test. Nothing here runs; completion confirms the checklists."
      else
        verdict="unknown"
        detail="this order froze no test file, so the selected-tests command would run over nothing."
      fi
    elif [ "$check_id" = "suite-regression" ] && [ "$BRC_END_OF_TASK" != "true" ] \
      && [ "$(printf '%s' "$cmd" | jq -r '.cost // ""')" = "end-of-task" ]; then
      verdict="deferred"
      detail="the recipe costs the suite row end-of-task, so this attempt did not run it; finish runs it once over the whole task range."
    else
      argv_json="$(printf '%s' "$cmd" | jq -c '.argv')"
      outfile="$(mktemp)" || { rm -f "$runs_file"; die 3 "$BRC_WHO: could not create a temporary file"; }
      result="$(br_run_resolved "$argv_json" "$BRC_CODEPATH" "$outfile" "$paths_json" "$BRC_VALUES")"
      kind="$(printf '%s' "$result" | cut -f1)"
      payload="$(printf '%s' "$result" | cut -f2-)"
      if [ "$kind" = "UNRESOLVED" ]; then
        verdict="unknown"
        detail="the token {$payload} in the $label command has no supplied value; pass --value $payload=<value>."
      elif [ "$kind" = "EMPTY" ]; then
        verdict="unknown"
        detail="the $label command came out with no token at all, so nothing ran and nothing was decided."
      else
        rc="$payload"
        # A green run that selected nothing is not a pass. The framework's own recipe names the
        # marker, under failure_signal's silent_pass; the caller's --nothing-ran is read only where
        # the recipe names none.
        nothing_ran_hit=false
        marker_json="$(printf '%s' "$fw_obj" | jq -c '.silentPass // []')"
        markers_len="$(printf '%s' "$marker_json" | jq 'length')"
        if [ "$markers_len" -gt 0 ]; then
          mi=0
          while [ "$mi" -lt "$markers_len" ]; do
            marker="$(printf '%s' "$marker_json" | jq -r --argjson i "$mi" '.[$i]')"
            if pc_output_holds "$outfile" "$marker"; then nothing_ran_hit=true; fi
            [ "$nothing_ran_hit" = "true" ] && break
            mi=$((mi + 1))
          done
        elif [ "$BRC_HAVE_NOTHING_RAN" = "true" ] && pc_output_holds "$outfile" "$BRC_NOTHING_RAN"; then
          nothing_ran_hit=true
          marker="$BRC_NOTHING_RAN"
        fi
        if [ "$nothing_ran_hit" = "true" ]; then
          verdict="unknown"
          detail="the $label command's output on $fw holds the nothing-ran marker ('$marker'); an exit status cannot decide a green run when nothing was selected."
        elif [ "$rc" = "0" ]; then
          verdict="met"
          detail="the $label command exited 0 on $fw."
        elif [ "$rc" = "127" ]; then
          # A runner that is not there answers nothing about the tests. Read as unmet it would say
          # the tests failed, which is a different fact and sends a reader to the wrong repair.
          verdict="unknown"
          detail="the $label command could not be found on $fw (exit 127), so nothing here ran and nothing was decided."
        elif [ "$rc" = "126" ]; then
          verdict="unknown"
          detail="the $label command list came out empty on $fw, so nothing ran and nothing was decided."
        elif [ "$check_id" = "order-tests" ]; then
          verdict="unmet"
          detail="the order-tests command exited $rc on $fw."
        else
          # The baseline records one verdict per framework, taken whole, and the whole output of
          # that run (baseline-schema.json, suite[].outputFile). A suite failing now, with this
          # framework's baseline already unmet, has that output subtracted line by line
          # (br_subtract_baseline): a test red then and red now is not a regression, and a
          # failure line absent then is one this order introduced. A suite row declaring
          # `failure_line` narrows both sides to the lines that name a failed test, because a
          # harness's progress and summary lines change whenever a test is added or fixed and
          # would read as new on the whole output.
          baseline_doc=""; baseline_verdict=""; baseline_output=""
          if [ -f "$BRC_BASELINE_FILE" ]; then
            baseline_doc="$(jq -c '.' "$BRC_BASELINE_FILE" 2>/dev/null)"
          fi
          if [ -n "$baseline_doc" ]; then
            baseline_verdict="$(printf '%s' "$baseline_doc" | jq -r --arg fw "$fw" \
              '[ (.suite // [])[] | select(.framework == $fw) ][0].verdict // ""')"
            baseline_output="$(printf '%s' "$baseline_doc" | jq -r --arg fw "$fw" \
              '[ (.suite // [])[] | select(.framework == $fw) ][0].outputFile // ""')"
            [ -z "$baseline_output" ] || baseline_output="$(dirname -- "$BRC_BASELINE_FILE")/$baseline_output"
            case "$baseline_verdict" in
              unmet)
                br_subtract_baseline "$baseline_output" "$outfile" "suite" "exited $rc on $fw" "$selector" "$warning"
                verdict="$BR_SUB_VERDICT"; detail="$BR_SUB_DETAIL"
                new_json="$BR_SUB_NEW"; new_count="$BR_SUB_COUNT"; warn_json="$BR_SUB_WARNINGS"
                ;;
              unknown)
                verdict="unknown"
                detail="the suite exited $rc on $fw, and the baseline recorded $fw unknown at the commit the build started from, so there is nothing to subtract and this cannot tell an old failure from a new one."
                ;;
              met)
                verdict="unmet"
                detail="the suite exited $rc on $fw, and the baseline recorded $fw met at the commit the build started from; this order introduced the failure."
                ;;
              *)
                verdict="unmet"
                detail="the suite exited $rc on $fw, and the baseline holds no suite entry for $fw, so nothing there predates this failure; this order introduced it."
                ;;
            esac
            # A baseline with no red to subtract, and a run red only on runner warnings: warned,
            # the same test the subtraction makes, never a failure this order introduced. A run
            # the selector names no line of, on a row with no warning_line, gets the hint.
            case "$baseline_verdict" in
              unmet)
                [ "$BR_SUB_UNSELECTED" != "true" ] || detail="$detail$(br_warning_hint "$warning" "$fw_obj")"
                ;;
              unknown) ;;
              *)
                if br_warnings_only "$selector" "$warning" "$outfile"; then
                  verdict="warned"; warn_json="$BR_WARN_LINES"
                  detail="the suite exited $rc on $fw, where the baseline recorded no failure, and $BR_WARN_DETAIL"
                elif br_selector_misses "$selector" "$outfile"; then
                  detail="$detail$(br_warning_hint "$warning" "$fw_obj")"
                fi
                ;;
            esac
          else
            verdict="unknown"
            detail="the suite exited $rc on $fw, and $BRC_BASELINE_FILE could not be read to tell whether this failure predates this order."
          fi
        fi
        [ -z "$warning" ] || [ -n "$selector" ] \
          || detail="$detail The recipe's suite row declares warning_line without failure_line, so warning_line was not read."
        printf '%s' "$runs" >"$runs_file"
        runs="$(jq -nc --slurpfile r "$runs_file" --arg fw "$fw" --arg v "$verdict" \
          --arg d "$detail" --argjson rc "$rc" --rawfile out "$outfile" \
          --argjson newLines "$new_json" --argjson newLineCount "$new_count" --argjson warn "$warn_json" \
          --arg failureLine "$([ "$check_id" = "suite-regression" ] && printf '%s' "$selector")" \
          '$r[0] as $runs
           | $runs + [{framework: $fw, verdict: $v, detail: $d, exitCode: $rc, output: $out,
                       newLines: $newLines, newLineCount: $newLineCount}
                      + (if $failureLine == "" then {} else {failureLine: $failureLine} end)
                      + (if ($warn | length) == 0 then {} else {warningLines: $warn} end)]')"
      fi
      rm -f "$outfile"
    fi
    if [ -z "$rc" ]; then
      printf '%s' "$runs" >"$runs_file"
      runs="$(jq -nc --slurpfile r "$runs_file" --arg fw "$fw" --arg v "$verdict" --arg d "$detail" \
        '$r[0] as $runs | $runs + [{framework: $fw, verdict: $v, detail: $d}]')"
    fi
    verdicts="$(jq -nc --argjson v "$verdicts" --arg x "$verdict" '$v + [$x]')"
    fwi=$((fwi + 1))
  done

  if [ "$fw_count" -eq 0 ]; then
    rm -f "$runs_file"
    jq -n --arg id "$check_id" --arg detail "no framework recipe was resolved for this task, so $label was not checked." \
      '{id: $id, verdict: "undeclared", detail: $detail}'
    return 0
  fi

  verdict="$(br_worst_verdict "$verdicts")"
  printf '%s' "$runs" >"$runs_file"
  jq -n --arg id "$check_id" --arg verdict "$verdict" --slurpfile r "$runs_file" '
    $r[0] as $runs
    | ([ $runs[] | .newLineCount // 0 ] | add) as $newCount
    | {id: $id, verdict: $verdict,
       detail: ([ $runs[] | (.framework + ": " + .detail) ] | join(" ")),
       runs: [ $runs[] | {framework, verdict} + (if has("failureLine") then {failureLine} else {} end) ]}
    + (if ([ $runs[] | select(has("exitCode")) ] | length) == 0 then {}
       else {exitCode: ([ $runs[] | select(has("exitCode")) | (.exitCode | tonumber) ] | max),
             output:   ([ $runs[] | select(has("output")) | .output ] | join("\n"))} end)
    + (if $newCount == 0 then {}
       else {newLines: ([ $runs[] | (.newLines // [])[] ] | .[:20]), newLineCount: $newCount} end)
    + ([ $runs[] | (.warningLines // [])[] ] | if length == 0 then {} else {warningLines: .[:20]} end)
  '
  rm -f "$runs_file"
}

# The run entries of the order's `verify` list that may run, as a JSON array of {run, pass}, and
# the sources they cite, into BRV_RUNS and BRV_CITES, and one per line into BRV_SOURCES. A binding
# entry came from a recipe this project accepts and runs. An entry that is not binding was
# written by a model from research, and runs only when a person approved it at the design close.
# Without that stamp it never runs, attended or not: the reviewer judges it as a check. Reads
# BRC_UNIT_JSON.
BRV_RUNS="[]"; BRV_CITES=""; BRV_SOURCES=""
br_verify_runs() {
  local keep='[ (.verify // [])[] | select(has("run") and (.binding != false or has("approved"))) ]'
  BRV_RUNS="$(printf '%s' "$BRC_UNIT_JSON" | jq -c "$keep | map({run, pass})")"
  BRV_SOURCES="$(printf '%s' "$BRC_UNIT_JSON" | jq -r "$keep | map(.cites) | unique | .[]")"
  BRV_CITES="$(printf '%s\n' "$BRV_SOURCES" | awk 'NF { printf "%s%s", sep, $0; sep = ", " }')"
}

# What br_verify_files_remove takes out of the tree after the verify lines ran. They are globals,
# because it is also the EXIT trap, and zsh runs that trap after the locals are gone. BRV_TREE:
# the tree the files went into. BRV_FILES_DIR: the temporary folder of blocks and saved files.
# BRV_WRITTEN and BRV_REPLACED: the paths written and replaced. BRV_DIRS: the folders made for them.
BRV_TREE=""; BRV_FILES_DIR=""; BRV_WRITTEN=""; BRV_REPLACED=""; BRV_DIRS=""

# Removes each file the verify lines' recipes wrote, puts back each earlier version they replaced,
# then removes the folders made for them and the temporary folder. RF_WRITTEN_PATHS and
# RF_REPLACED_PATHS are read too, because a refusal or an interrupt inside recipe_files_write
# leaves that recipe's paths there alone. RF_NEW_DIRS holds the folders a `## Status` run made. It is safe to run twice. A path it could not take out
# is named, and the tree is then not what it was. $1, when given, is the verify log, which then
# names each path put back and each path removed.
br_verify_files_remove() {
  local left="" took="" back="" gone=""
  if [ -n "$BRV_TREE" ]; then
    took="$(recipe_files_take_out "$BRV_TREE" "$BRV_FILES_DIR/was" "$BRV_WRITTEN$RF_WRITTEN_PATHS" \
      "$BRV_REPLACED$RF_REPLACED_PATHS" "$BRV_DIRS$RF_NEW_DIRS")"
    back="$(printf '%s\n' "$took" | sed -n 1p)"; gone="$(printf '%s\n' "$took" | sed -n 2p)"
    left="$(printf '%s\n' "$took" | sed -n 3p)"
    if [ -n "${1:-}" ]; then
      [ -z "$back" ] || printf 'put back after the run:%s\n' "$back" >>"$1"
      [ -z "$gone" ] || printf 'removed after the run:%s\n' "$gone" >>"$1"
    fi
    [ -z "$left" ] || printf '%s: could not take the recipe files back out of %s:%s. Remove them by hand.\n' "$BRC_WHO" "$BRV_TREE" "$left" >&2
  fi
  [ -z "$BRV_FILES_DIR" ] || rm -rf "$BRV_FILES_DIR"
  BRV_TREE=""; BRV_FILES_DIR=""; BRV_WRITTEN=""; BRV_REPLACED=""; BRV_DIRS=""
  RF_WRITTEN_PATHS=""; RF_REPLACED_PATHS=""; RF_NEW_DIRS=""
}

# Runs the order's own verify lines through br_run_lines from the folder $1, output into $2. A line
# may run a script its recipe ships in `## Files` (gap row 198). So the `## Files` blocks of every
# recipe the lines cite are written into $1 first, under the rule the environment uses: an absent
# file is written, an earlier version is replaced, and any other differing file refuses at 3.
# br_verify_files_remove then takes them out again on every exit, a refusal or an interrupt
# included. Nothing written persists, so the clean-tree rule and `git worktree remove` see the
# tree as the order left it. Only a cited file with a `## Verifier` section is a recipe here, so a
# guide or a research record writes nothing, and a recipe with no `## Files` writes nothing either.
# Reads BRV_RUNS, BRV_CITES and BRV_SOURCES.
br_run_verify_lines() {
  local dir="$1" outfile="$2" recipe list
  trap 'br_verify_files_remove' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  BRV_TREE="$dir"
  BRV_FILES_DIR="$(mktemp -d)" || die 3 "$BRC_WHO: could not create a temporary folder"
  while IFS= read -r recipe; do
    [ -n "$recipe" ] && [ -f "$recipe" ] && grep -q '^## Verifier' "$recipe" || continue
    list="$(recipe_files_into "$recipe" Files "$BRV_FILES_DIR")"
    [ -n "$list" ] || continue
    recipe_files_refuse_differing "$BRC_WHO" "$recipe" "$list" "$dir" "$BRV_FILES_DIR"
    BRV_DIRS="$BRV_DIRS$(recipe_files_new_dirs "$dir" "$list")
"
    recipe_files_write "$BRC_WHO" "$list" "$dir" "$BRV_FILES_DIR" >/dev/null
    BRV_WRITTEN="$BRV_WRITTEN$RF_WRITTEN_PATHS"; BRV_REPLACED="$BRV_REPLACED$RF_REPLACED_PATHS"
    # The log names each file the run wrote, because nothing written is in the tree after the run.
    [ -z "$RF_WRITTEN_PATHS" ] || printf 'written for this run: %s (from %s)\n' "$(printf '%s' "$RF_WRITTEN_PATHS" | paste -s -d ' ' -)" "$recipe" >>"$outfile"
    [ -z "$RF_REPLACED_PATHS" ] || printf 'replaced for this run: %s (from %s)\n' "$(printf '%s' "$RF_REPLACED_PATHS" | paste -s -d ' ' -)" "$recipe" >>"$outfile"
  done <<BRV_RECIPES
$BRV_SOURCES
BRV_RECIPES
  br_run_lines "$BRV_RUNS" "$BRV_CITES" "$dir" "$outfile" "the verify line above, from $BRV_CITES, is refused."
  br_verify_files_remove "$outfile"
  trap - EXIT INT TERM
}

# Runs a list of lines through the one gate runner, the `## Configuration gate` block's and a work
# order's own `verify` lines alike. $1 a JSON array of {run, pass}, $2 the source a refusal names,
# $3 the folder every line runs from, $4 the file that receives each command line and its output,
# $5 the words a refusal ends on. A line that ran is logged with every token filled (gap row 264).
# Each line is refused on a shell character, split on spaces and run as argv through
# br_run_resolved, so `{paths}` expands to this order's owned files and every other token comes
# from --value. A name given several --value rows runs its line once per value, in the order
# given: each run puts that value's row first, where cr_lookup finds it, so the one filler fills
# it. Only the first such name in a line multiplies it; any other token takes its first value.
# A line holding `{paths}`, `{file}` or `{dirs}` on an order that owns no file does not apply,
# as a check row does not (gap row 203). A tool handed no path reads its own default scope. The
# output names it and the list goes on. When no line applies, the list reads undeclared, which
# never passes an order alone, because br_checks_pass needs its deciding check met.
# The first run that fails stops the list. A non-zero exit fails a run whatever its pass says.
# `stdout empty` and `stdout contains <text>` then read standard output alone, because a status
# command writes its message to standard error and exits 0 either way. It sets BRL_VERDICT,
# empty when every line that applies passed, undeclared when none applies, else unmet or unknown;
# BRL_WHY, the reason in words; BRL_RC, the last exit code or empty; BRL_N, how many lines ran;
# BRL_SKIPPED, how many did not apply; and BRL_LINE, the last line.
BRL_VERDICT=""; BRL_WHY=""; BRL_RC=""; BRL_N=0; BRL_SKIPPED=0; BRL_LINE=""
br_run_lines() {
  local lines_json="$1" source="$2" dir="$3" outfile="$4" refused="$5"
  local count i pass literal argv_json result kind payload owned_json run_out run_err
  local tok multi_name="" multi_values="" value values shown tab owned_count
  tab="$(printf '\t')"
  BRL_VERDICT=""; BRL_WHY=""; BRL_RC=""; BRL_N=0; BRL_SKIPPED=0; BRL_LINE=""
  owned_json="$(printf '%s' "$BRC_UNIT_JSON" | jq -c '.ownedFiles // []')"
  owned_count="$(printf '%s' "$owned_json" | jq 'length')"
  run_out="$(mktemp)" || die 3 "$BRC_WHO: could not create a temporary file"
  run_err="$(mktemp)" || die 3 "$BRC_WHO: could not create a temporary file"
  count="$(printf '%s' "$lines_json" | jq 'length')"
  i=0
  while [ "$i" -lt "$count" ]; do
    BRL_LINE="$(printf '%s' "$lines_json" | jq -r --argjson i "$i" '.[$i].run')"
    pass="$(printf '%s' "$lines_json" | jq -r --argjson i "$i" '.[$i].pass // "exit 0"')"
    i=$((i + 1))
    refuse_if_unsafe "$BRC_WHO" "$source" "$BRL_LINE" || die 3 "$BRC_WHO: $refused"
    argv_json="$(printf '%s' "$BRL_LINE" | jq -Rc 'split(" ") | map(select(. != ""))')"
    if [ "$owned_count" -eq 0 ] && br_argv_takes_paths "$argv_json"; then
      printf '+ %s\nnot applicable: gate line %s holds a path placeholder, and this order declares no ownedFiles, so the line does not apply to it.\n' "$BRL_LINE" "$i" >>"$outfile"
      BRL_SKIPPED=$((BRL_SKIPPED + 1))
      continue
    fi
    BRL_N=$((BRL_N + 1))
    multi_name=""; multi_values=""
    while IFS= read -r tok; do
      case "$tok" in ''|paths|file|dirs) continue ;; esac
      values="$(printf '%s\n' "$BRC_VALUES" | awk -F "$tab" -v n="$tok" '$1 == n { sub(/^[^\t]*\t/, ""); print }')"
      if [ "$(printf '%s\n' "$values" | grep -c .)" -gt 1 ]; then multi_name="$tok"; multi_values="$values"; break; fi
    done <<BR_RUN_TOKENS
$(printf '%s' "$argv_json" | jq -r '.[] | scan("[{]([^{}]+)[}]") | .[0]')
BR_RUN_TOKENS
    while IFS= read -r value; do
      if [ -n "$multi_name" ]; then
        values="$multi_name$tab$value
$BRC_VALUES"
      else
        values="$BRC_VALUES"
      fi
      : >"$run_out"
      case "$pass" in
        stdout*) result="$(br_run_resolved "$argv_json" "$dir" "$run_out" "$owned_json" "$values" "$run_err" "$outfile")" ;;
        *)       result="$(br_run_resolved "$argv_json" "$dir" "$run_out" "$owned_json" "$values" "" "$outfile")" ;;
      esac
      kind="$(printf '%s' "$result" | cut -f1)"
      payload="$(printf '%s' "$result" | cut -f2-)"
      # br_run_resolved logs a line only when it runs it, so a line that did not run is logged as written.
      [ "$kind" = "RAN" ] || printf '+ %s\n' "$BRL_LINE" >>"$outfile"
      # A reason quotes the line as the log shows it, so the two never differ.
      shown="$(tail -n 1 "$outfile")"; shown="${shown#+ }"
      cat "$run_out" "$run_err" >>"$outfile"; : >"$run_err"
      if [ "$kind" = "UNRESOLVED" ]; then
        BRL_VERDICT="unknown"; BRL_RC=""
        BRL_WHY="the token {$payload} in gate line $i ($shown) has no supplied value; pass --value $payload=<value>."
        break
      fi
      BRL_RC="$payload"
      if [ "$BRL_RC" != "0" ]; then
        BRL_VERDICT="unmet"; BRL_WHY="gate line $i ($shown) exited $BRL_RC"
        break
      fi
      case "$pass" in
        'exit 0') ;;
        'stdout empty')
          if grep -q '[^[:space:]]' "$run_out"; then
            BRL_VERDICT="unmet"; BRL_WHY="gate line $i ($shown) exited 0 and printed to standard output, and its pass is stdout empty"
            break
          fi ;;
        'stdout contains '?*)
          literal="$(pc_unquote "${pass#stdout contains }")"
          if ! pc_output_holds "$run_out" "$literal"; then
            BRL_VERDICT="unmet"; BRL_WHY="gate line $i ($shown) exited 0, and its standard output does not hold $literal"
            break
          fi ;;
        *)
          BRL_VERDICT="unknown"; BRL_WHY="gate line $i ($shown) names a pass this runner does not read: $pass"
          break ;;
      esac
    done <<BR_RUN_VALUES
${multi_values:-one}
BR_RUN_VALUES
    [ -z "$BRL_VERDICT" ] || break
  done
  if [ -z "$BRL_VERDICT" ] && [ "$count" -gt 0 ] && [ "$BRL_SKIPPED" -eq "$count" ]; then
    BRL_VERDICT="undeclared"
    BRL_WHY="each line holds a path placeholder, and this order declares no ownedFiles, so no line applies to it"
  fi
  rm -f "$run_out" "$run_err"
}

# The configuration check, in the order-tests slot of an order whose proof is gate (live-run row
# 65). Its deliverable is exported configuration, which no test of its own can prove. Two lists
# prove it, in one slot. The order's own `verify` run lines run first: design copied them from
# the recipe that covers the order, or wrote them from research's findings. They prove the site
# the build left. The implement recipe's `## Configuration gate` lines run after them, when the
# recipe carries the block: they prove the export imports onto the seed. The worse verdict
# stands. An order with no lines runs the block alone, and then reads unknown without an
# --implement-recipe or without the block. An order with lines runs them alone in either case,
# and the detail says the block did not run. Every line passing is met; the first line that
# does not is named, with its exit and its output. Both lists run through br_run_lines from the
# worktree. The first block line restores the snapshot the environment's bring-up took, so a task
# with no environment recorded reads unknown before any line runs. Two recipes each carrying the
# block are two answers to one question, exit 72. The gate is the section's first `sh` block. Its
# second is the put-back line, which puts the site back after a gate that reached its fourth line,
# whatever the gate's verdict (gap row 288). It runs into the same output and never changes the
# verdict or the exit code. A put-back that fails leads the detail, because the summary cuts a
# long detail and the person must put the site back by hand. Prints the check object.
br_gate_check() {
  local verdict="" detail="" outfile lines gate_fw="" gate_recipe="" gate_lines="" fw rp count=0
  local own_json cites own_verdict="" own_detail="" gate_verdict="" gate_detail="" rc="" lines_json
  local back_lines="" back_note="" gate_n gate_why gate_rc gate_skipped
  br_verify_runs; own_json="$BRV_RUNS"; cites="$BRV_CITES"
  if [ -z "$(jq -r '.environment.address // empty' "$TASK_PATH/task.json" 2>/dev/null)" ]; then
    detail="task.json records no environment address, so the worktree has no site and no snapshot for the first gate line to restore. Bring the environment up, then record the attempt again."
    # The marker task environment up writes before its bring-up. A site may be half up, so the
    # bring-up is not the next step here; the tear-down is. The verdict is unknown either way.
    [ "$(jq -r '.environment.state // empty' "$TASK_PATH/task.json" 2>/dev/null)" != "coming-up" ] \
      || detail="task.json holds the marker task environment up writes before its bring-up, so a site may be half up and no snapshot exists. Run task environment $(jq -r '.id // "<task-id>"' "$TASK_PATH/task.json" 2>/dev/null) down first. Then bring the environment up and record the attempt again."
    jq -n --arg detail "$detail" '{id: "configuration-gate", verdict: "unknown", detail: $detail}'
    return 0
  fi
  outfile="$(mktemp)" || die 3 "$BRC_WHO: could not create a temporary file"
  if [ "$own_json" != "[]" ]; then
    br_run_verify_lines "$BRC_CODEPATH" "$outfile"
    own_verdict="${BRL_VERDICT:-met}"; rc="$BRL_RC"
    case "$own_verdict" in
      met) own_detail="every verify line of $(printf '%s' "$BRC_UNIT_JSON" | jq -r '.id') ($BRL_N of them$([ "$BRL_SKIPPED" -eq 0 ] || printf ', %s did not apply' "$BRL_SKIPPED")) passed, from $cites." ;;
      undeclared) own_detail="$BRL_WHY, from $cites." ;;
      *)   own_detail="$BRL_WHY, from $cites. Every verify line before it passed." ;;
    esac
  fi
  if [ -z "$BRC_GATE_RECIPES" ]; then
    if [ "$own_json" = "[]" ]; then
      gate_verdict="unknown"
      gate_detail="no --implement-recipe was passed, so the ## Configuration gate lines could not be read. Pass the implement recipe path the build step holds."
    else
      gate_detail="No --implement-recipe was passed, so no ## Configuration gate ran after them."
    fi
  else
    while IFS="$(printf '\t')" read -r fw rp; do
      [ -n "$fw" ] || continue
      lines="$(sh_blocks_under "$rp" "Configuration gate" 1 | grep '[^[:space:]]')"
      [ -n "$lines" ] || continue
      count=$((count + 1))
      [ "$count" -le 1 ] \
        || die 72 "$BRC_WHO: $gate_fw and $fw each carry a ## Configuration gate, and nothing here may choose between two answers to one question."
      gate_fw="$fw"; gate_recipe="$rp"; gate_lines="$lines"
      back_lines="$(sh_blocks_under "$rp" "Configuration gate" 2 | grep '[^[:space:]]')"
    done <<BR_GATE
$BRC_GATE_RECIPES
BR_GATE
    if [ -z "$gate_recipe" ]; then
      if [ "$own_json" = "[]" ]; then
        gate_verdict="unknown"
        gate_detail="the implement recipe carries no ## Configuration gate block, so nothing here can prove exported configuration: $(printf '%s' "$BRC_GATE_RECIPES" | cut -f2 | paste -s -d ' ' -). The recipe lacks it."
      else
        gate_detail="The implement recipe carries no ## Configuration gate block, so none ran after them."
      fi
    else
      lines_json="$(printf '%s\n' "$gate_lines" | jq -Rc '[ ., inputs ] | map(select(. != "") | {run: ., pass: "exit 0"})')"
      br_run_lines "$lines_json" "$gate_recipe" "$BRC_CODEPATH" "$outfile" "the ## Configuration gate line above is refused."
      gate_verdict="${BRL_VERDICT:-met}"; gate_n="$BRL_N"; gate_why="$BRL_WHY"; gate_rc="$BRL_RC"; gate_skipped="$BRL_SKIPPED"
      # The exit code the check carries is the first failing list's, else the last that ran.
      [ -z "$gate_rc" ] || [ "$own_verdict" = "unmet" ] || rc="$gate_rc"
      if [ -n "$back_lines" ] && [ "$gate_n" -ge 4 ]; then
        br_run_lines "$(printf '%s\n' "$back_lines" | jq -Rc '[ ., inputs ] | map(select(. != "") | {run: ., pass: "exit 0"})')" \
          "$gate_recipe" "$BRC_CODEPATH" "$outfile" "the put-back line above is refused."
        if [ "${BRL_RC:-}" = "0" ]; then
          back_note=" The put-back line exited 0."
        else
          back_note="The put-back line ($BRL_LINE) exited ${BRL_RC:-without running}, so the site does not hold what the build left. Run that line again by hand. "
        fi
      fi
      case "$gate_verdict" in
        met)   gate_detail="every ## Configuration gate line ($gate_n of them$([ "$gate_skipped" -eq 0 ] || printf ', %s did not apply' "$gate_skipped")) exited 0 on $gate_fw, from $gate_recipe. A gate line that printed 'There are no changes to import' is a finding the reviewer reads in the output." ;;
        unmet) gate_detail="$gate_why on $gate_fw; the recipe's prose under ## Configuration gate says what a failure of that line means. Every line before it exited 0." ;;
        *)     gate_detail="$gate_why" ;;
      esac
    fi
  fi
  verdict="$(br_worst_verdict "$(jq -nc --arg a "$own_verdict" --arg b "$gate_verdict" '[ $a, $b ] | map(select(. != ""))')")"
  detail="$own_detail${own_detail:+${gate_detail:+ }}$gate_detail"
  case "$back_note" in
    ' '*) detail="$detail$back_note" ;;
    ?*)   detail="$back_note$detail" ;;
  esac
  if [ -n "$rc" ]; then
    jq -n --arg verdict "$verdict" --arg detail "$detail" --argjson rc "$rc" --rawfile out "$outfile" \
      '{id: "configuration-gate", verdict: $verdict, detail: $detail, exitCode: $rc, output: $out}'
  else
    jq -n --arg verdict "$verdict" --arg detail "$detail" \
      '{id: "configuration-gate", verdict: $verdict, detail: $detail}'
  fi
  rm -f "$outfile"
}

# Runs the order's own `verify` run lines inside the first deciding check of an order whose proof
# is not gate, after that check's own answer. $1 the file that holds the check object. A gate
# order ran its lines as the check itself, and an order with none passes the object through. The
# lines run from the code worktree, because a record order's range lives in the project folder
# and a re-run of what the document reports belongs to the code. The check is met only when its
# own answer and every line are: the worse verdict stands, the detail gains one sentence naming
# the source, and the output gains the lines' output. Prints the check object.
br_verify_fold() {
  local own_json cites outfile verdict
  br_verify_runs; own_json="$BRV_RUNS"
  br_order_facts "$BRC_UNIT_JSON"
  if [ "$own_json" = "[]" ] || [ "$BR_ORDER_SLOT" = "configuration-gate" ]; then
    cat "$1"
    return 0
  fi
  cites="$BRV_CITES"
  outfile="$(mktemp)" || die 3 "$BRC_WHO: could not create a temporary file"
  br_run_verify_lines "${RV_CODEPATH:-$BRC_CODEPATH}" "$outfile"
  verdict="$(br_worst_verdict "$(jq -c --arg v "${BRL_VERDICT:-met}" '[.verdict, $v]' "$1")")"
  # The exit code follows the verdict that stands: the lines' own when they failed, the check's
  # own when it failed, and the lines' when both passed and the check ran no command.
  jq --arg v "$verdict" --arg lv "${BRL_VERDICT:-met}" --arg rc "$BRL_RC" --rawfile out "$outfile" \
     --arg add "$(if [ -z "$BRL_VERDICT" ]; then printf 'Every verify line (%s of them%s) passed, from %s.' "$BRL_N" "$([ "$BRL_SKIPPED" -eq 0 ] || printf ', %s did not apply' "$BRL_SKIPPED")" "$cites"; elif [ "$BRL_VERDICT" = "undeclared" ]; then printf 'Its verify lines do not apply: %s, from %s.' "$BRL_WHY" "$cites"; else printf 'Its verify lines did not pass: %s, from %s.' "$BRL_WHY" "$cites"; fi)" '
    .verdict = $v | .detail = (.detail + " " + $add)
    | .output = (if (.output // "") == "" then $out else .output + "\n" + $out end)
    | if $rc == "" then .
      elif $lv == "unmet" then .exitCode = ($rc | tonumber)
      elif (has("exitCode") | not) and $v == "met" then .exitCode = ($rc | tonumber)
      else . end' "$1"
  rm -f "$outfile"
}

# The done-when check, in the order-tests slot of an order whose proof is record (nyc defect 17).
# Its deliverable is a document in the task folder, which no test and no tool can judge, so the
# check reads the judgement the checkpoint left on the order's ledger entry: the done-when row,
# `--row <unit_id>=...` at tests-freeze, judged by a person or the row-checker. Confirmed is met,
# and the detail names the judge; no row is unknown. Prints the check object.
br_record_check() {
  local unit judgement verdict detail
  unit="$(printf '%s' "$BRC_UNIT_JSON" | jq -r '.id')"
  judgement="$(jq -c --arg id "$unit" '[ (.orders // [])[] | select(.id == $id) ][0].doneWhenJudgement // null' "$IMPL_DIR/ledger.json" 2>/dev/null)"
  if [ -z "$judgement" ] || [ "$judgement" = "null" ]; then
    verdict="unknown"
    detail="$unit is proved by its record, and the ledger holds no done-when judgement for it: tests-freeze records one from --row $unit=..., and none was recorded."
  elif [ "$(printf '%s' "$judgement" | jq -r '.verdict')" = "confirmed" ]; then
    verdict="met"
    detail="the done-when row of $unit was confirmed at the checkpoint, judged by $(printf '%s' "$judgement" | jq -r '.judgedBy'): $(printf '%s' "$judgement" | jq -r '.note')"
  else
    verdict="unmet"
    detail="the done-when row of $unit reads $(printf '%s' "$judgement" | jq -r '.verdict') at the checkpoint, judged by $(printf '%s' "$judgement" | jq -r '.judgedBy'): $(printf '%s' "$judgement" | jq -r '.note')"
  fi
  jq -n --arg verdict "$verdict" --arg detail "$detail" --arg judgedBy "$(printf '%s' "$judgement" | jq -r '.judgedBy // ""')" '
    {id: "done-when", verdict: $verdict, detail: $detail}
    + (if $judgedBy == "" then {} else {judgedBy: $judgedBy} end)'
}

# The confirm-at-review check, in the order-tests slot of an order whose proof is confirm (gap row
# 196). The task has no automated tests, so nothing here can judge the order's own work. The check
# reads deferred: `finish` hands the order's done-when rows to review as checklist rows, and the
# person answers there. The floor accepts deferred in this slot alone. Prints the check object.
br_confirm_check() {
  jq -n --arg unit "$(printf '%s' "$BRC_UNIT_JSON" | jq -r '.id')" \
    '{id: "confirm-at-review", verdict: "deferred",
      detail: ($unit + " is confirmed by a person: its task has no automated tests, so no test ran. The person confirms its done-when rows at review.")}'
}

# The observed check, in the order-tests slot of an order whose proof is observe (live-run row
# 104). Its deliverable is what a page shows, which no test of its own proves, so the check reads
# the record the orchestrator wrote after looking at each surface at each viewport through a
# browser: met when every row is met, unmet naming the first row that is not, unknown when the
# record at BRC_OBSERVED is not there to read. The judge is always a model, and the check carries
# it as judgedBy so `close` copies it onto the criteria the order owns. `build-record` checks the
# record's shape and its rows against the order before any check runs (exits 93 to 96), so a fix
# round or a re-check reads a file the build step already refused or accepted. Prints the check
# object.
br_observed_check() {
  local unit verdict detail unmet_row rows_count
  unit="$(printf '%s' "$BRC_UNIT_JSON" | jq -r '.id')"
  if [ -z "$BRC_OBSERVED" ] || ! jq empty "$BRC_OBSERVED" >/dev/null 2>&1; then
    jq -n --arg unit "$unit" --arg observed "${BRC_OBSERVED:-none}" \
      '{id: "observed", verdict: "unknown",
        detail: ($unit + " is proved by a model\u0027s observation, and no observed record could be read at " + $observed + ". The build step writes it after the implementer returns and passes it as --observed.")}'
    return 0
  fi
  rows_count="$(jq '(.rows // []) | length' "$BRC_OBSERVED")"
  unmet_row="$(jq -r '[ (.rows // [])[] | select(.verdict != "met") ][0] // empty
    | .surface + " at " + .viewport + ": " + .doneWhen + " (" + .note + ")"' "$BRC_OBSERVED")"
  if [ -n "$unmet_row" ]; then
    verdict="unmet"
    detail="a model judged a row unmet on $unmet_row; the observed record holds every row and the screenshots."
  else
    verdict="met"
    detail="a model judged every done-when row and every owned clause met at every surface and viewport ($rows_count rows); the observed record holds the screenshots."
  fi
  jq -n --arg verdict "$verdict" --arg detail "$detail" --arg judgedBy "$(jq -r '.judgedBy' "$BRC_OBSERVED")" \
    '{id: "observed", verdict: $verdict, detail: $detail, judgedBy: $judgedBy}'
}

# True when $1, a path relative to its task folder, is one AIDA's own scripts write there. Those
# are the task record and the contract, each with its rendering, and the design close. Also the
# stage folders, the archive `restart` leaves, the notes a save appends, and records/. The
# owned-files check on a record order sets these aside. A task note or a stage close commits
# them inside the order's range, and no implementer wrote them. A deliverable a person writes is
# never here: inputs/ and deliverables/ are theirs. The one list of what a script writes under a task.
br_aida_writes_in_task() {
  case "$1" in
    task.json|task.md|alignment.json|alignment.md|design-closed.json) return 0 ;;
    research/*|design/*|implementation/*|implementation-*/*|review/*|completion/*|notes/*|records/*) return 0 ;;
  esac
  return 1
}

# True when $1, a path relative to the project folder, is one AIDA's own scripts write there
# (live-run row 127). A record order's diff reads the project folder whole, since its
# deliverable may sit beside earlier reports outside the task folder. Inside this task's own
# folder the list above decides. Another task's folder is written by that task's stage closes
# and notes, never by this order's implementer. project.json is the project skill's. The
# project's records/ is ignored, so it never appears in a diff.
br_aida_writes_in_project() {
  local task_rel rel
  task_rel="${TASK_PATH#"$BRC_CODEPATH"/}"
  rel="${1#"$task_rel"/}"
  if [ "$rel" != "$1" ]; then
    br_aida_writes_in_task "$rel"
    return $?
  fi
  case "$1" in
    project.json|tasks/*) return 0 ;;
  esac
  return 1
}

# Runs the `## Status` line of the environment recipe $1 in the worktree $2, and returns what
# recipe_status_run returns: 0 up, 1 down, 2 no such block. The status script's files go out
# through br_verify_files_remove, on every exit. Its callers run it before their temporary files
# exist. br_require_site_up and preconditions both ask it. Reads TASK_PATH and BRC_WHO.
br_site_status() {
  local rc
  trap 'br_verify_files_remove' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  BRV_TREE="$2"
  BRV_FILES_DIR="$(mktemp -d)" || die 3 "$BRC_WHO: could not create a temporary folder"
  recipe_status_run "$BRC_WHO" "$1" "$2" "$TASK_PATH/task.json" "$BRV_FILES_DIR"; rc=$?
  br_verify_files_remove
  trap - EXIT INT TERM
  return "$rc"
}

# The first token no source fills in the run lines $1, one per line, with $2 as the `--value`
# list. Prints its name, or nothing when every token fills. It resolves each argument the way
# br_run_resolved does and runs nothing, because a gate line reaches the site (gap row 288).
br_first_unfilled() {
  local arg name
  while IFS= read -r arg; do
    case "$arg" in '{paths}'|'{file}'|'{dirs}') continue ;; *'{'*'}'*) ;; *) continue ;; esac
    if ! name="$(br_fill_arg "$2" "$arg")"; then
      printf '%s' "$name"
      return 0
    fi
  done <<BR_UNFILLED_ARGS
$(printf '%s\n' "$1" | jq -Rr 'split(" ") | .[] | select(. != "")')
BR_UNFILLED_ARGS
}

# The first token no source fills in the `## Configuration gate` lines of the recipes $1, a
# `<framework><TAB><path>` list, with $2 as the `--value` list. Prints `<name><TAB><path>`, or
# nothing when every token fills. Both of the section's blocks are read, the put-back line too.
br_gate_unfilled() {
  local fw rp name
  while IFS="$(printf '\t')" read -r fw rp; do
    [ -n "$fw" ] && [ -f "$rp" ] || continue
    name="$(br_first_unfilled "$(sh_blocks_under "$rp" "Configuration gate")" "$2")"
    [ -z "$name" ] || { printf '%s\t%s' "$name" "$rp"; return 0; }
  done <<BR_GATE_RECIPES
$1
BR_GATE_RECIPES
}

# Refuses at 3, before any check runs, when a line a gate order runs holds a token nothing fills:
# a line of its own `verify` list or of the `## Configuration gate`. Such a line would fail for a
# reason that is not the order's, so no attempt is spent, and the same step runs again once the
# value exists. Reads BRC_WHO, BRC_UNIT_JSON, BRC_GATE_RECIPES and BRC_VALUES.
br_require_gate_tokens() {
  local found="" name
  br_order_facts "$BRC_UNIT_JSON"
  [ "$BR_ORDER_SLOT" = "configuration-gate" ] || return 0
  br_verify_runs
  name="$(br_first_unfilled "$(printf '%s' "$BRV_RUNS" | jq -r '.[].run')" "$BRC_VALUES")"
  [ -z "$name" ] || found="$name	$BRV_CITES, a verify line of this order"
  [ -n "$found" ] || found="$(br_gate_unfilled "$BRC_GATE_RECIPES" "$BRC_VALUES")"
  [ -z "$found" ] \
    || die 3 "$BRC_WHO: the token {${found%%	*}} in the lines from ${found#*	} has no value, so no check ran and no attempt was spent. A value comes from --value ${found%%	*}=<value>, from the tokens preconditions recorded, or from the task's environment record, which task environment <task-id> up writes."
}

# Refuses at 103, before any check runs, when the task's site is down (gap row 212). A site
# command such as `ddev drush` starts a stopped site and prints its start-up text. So every
# `stdout empty` line would fail for a reason that is not the check. The test runs when the task
# records an environment address and the order has verify run lines or holds the configuration
# gate. The recipe must also carry a `## Status` block. No line kind says that a line leaves the
# site alone, so every such order is tested. The refusal holds in both run modes, because
# `task environment up` is a person's answer and refuses unattended. No attempt is spent, so the
# same step runs again once the site is up. Reads TASK_PATH, BRC_WHO and BRC_UNIT_JSON.
br_require_site_up() {
  local task_json="$TASK_PATH/task.json" recipe wt rc
  [ -n "$(jq -r '.environment.address // empty' "$task_json" 2>/dev/null)" ] || return 0
  recipe="$(jq -r '.environment.recipe // empty' "$task_json")"
  wt="$(jq -r '.worktree.path // empty' "$task_json")"
  [ -f "$recipe" ] && [ -d "$wt" ] || return 0
  br_verify_runs; br_order_facts "$BRC_UNIT_JSON"
  [ "$BRV_RUNS" != "[]" ] || [ "$BR_ORDER_SLOT" = "configuration-gate" ] || return 0
  br_site_status "$recipe" "$wt"; rc=$?
  [ "$rc" -ne 1 ] \
    || die 103 "$BRC_WHO: the site of this task is down, so no check ran and no attempt was spent. The ## Status line of $recipe said: ${RS_FIRST:-nothing}. Run task environment $(jq -r '.id' "$task_json") up, then run the same step again once the site is up."
}

# The seven, in the fixed order this stage records them: order-tests, suite-regression,
# coding-standards, static-analysis, security, owned-files, frozen-tests. On an order whose proof
# is gate the first slot holds configuration-gate instead, and on one whose proof is record it
# holds done-when, with the suite and the three tool rows undeclared: a document in the task
# folder is nothing a suite or a tool reads (nyc defect 17). On one whose proof is observe it
# holds observed, and the rest run as they do for a code order (live-run row 104). On one whose
# proof is confirm it holds confirm-at-review, the suite reads undeclared, and the three tool rows
# run (gap row 196). A gate order on a task with no automated tests reads its suite undeclared
# too (gap row 246). Prints the JSON array.
br_seven_checks() {
  local parts_file rc_id
  parts_file="$(mktemp)" || die 3 "$BRC_WHO: could not create a temporary file"

  # The slot's own answer goes to a file first, never through a `$(...)`, so a refusal inside it
  # still ends the script. The order's own verify lines then run inside that same slot.
  local slot_file
  slot_file="$(mktemp)" || die 3 "$BRC_WHO: could not create a temporary file"
  br_order_facts "$BRC_UNIT_JSON"
  case "$BR_ORDER_SLOT" in
    configuration-gate) br_gate_check >"$slot_file" ;;
    done-when)          br_record_check >"$slot_file" ;;
    observed)           br_observed_check >"$slot_file" ;;
    confirm-at-review)  br_confirm_check >"$slot_file" ;;
    *)                  br_test_check "order-tests" "orderTests" "order-tests" >"$slot_file" ;;
  esac
  br_verify_fold "$slot_file" >>"$parts_file"
  rm -f "$slot_file"
  if [ "$BR_ORDER_OWNS_CODE" = "no" ]; then
    for rc_id in suite-regression coding-standards static-analysis security; do
      jq -n --arg id "$rc_id" --arg detail "this order is proved by its record: its deliverable is a document in the project folder, which the $rc_id row does not read, so the row does not apply to it." \
        '{id: $id, verdict: "undeclared", detail: $detail}' >>"$parts_file"
    done
  else
    if [ "$BR_ORDER_SLOT" = "confirm-at-review" ]; then
      jq -n '{id: "suite-regression", verdict: "undeclared", detail: "this order is confirmed by a person: its task has no automated tests, so no suite runs."}' >>"$parts_file"
    elif [ "$BR_ORDER_SLOT" = "configuration-gate" ] \
      && [ "$(printf '%s' "$SNAPSHOT_DOC" | jq -r "$BR_HARNESS_JQ noAutomatedTests")" = "true" ]; then
      jq -n '{id: "suite-regression", verdict: "undeclared", detail: "this order is proved by its configuration gate, and its task has no automated tests, so no suite runs."}' >>"$parts_file"
    else
      br_test_check "suite-regression" "suite"      "suite"       >>"$parts_file"
    fi
    br_tool_check "coding-standards" "codingStandards" "coding-standards" >>"$parts_file"
    br_tool_check "static-analysis"  "staticAnalysis"  "static-analysis"  >>"$parts_file"
    br_tool_check "security"         "security"        "security"         >>"$parts_file"
  fi

  # --- the realized diff touches only the files this order owns ------------------------------------
  local ofc_verdict ofc_detail
  local diff_output owned_files_json owned_count unmatched="" p matched gi g set_aside=0 aside_noun
  local own_count allowed_hit="" env_aside="" rerun_step="" light=false
  task_is_light "$TASK_PATH" && light=true
  # --no-renames: git reads a delete plus an add as one rename by default, and a rename shows only
  # the new path, so a deleted file this order does not own would never appear here.
  diff_output="$(git_diff_of "$BRC_CODEPATH" "$BRC_STARTED_AT" "$BRC_CURRENT" "$BRC_SCOPE" --no-renames --name-only)"
  # The paths a person allowed for a fix round follow the order's own. So an index at or past
  # own_count is an allowed path, and the detail names it (live-run row 116).
  owned_files_json="$(printf '%s' "$BRC_UNIT_JSON" | jq -c --argjson a "$BRC_ALLOWED_JSON" '(.ownedFiles // []) + $a')"
  own_count="$(printf '%s' "$BRC_UNIT_JSON" | jq '.ownedFiles // [] | length')"
  owned_count="$(printf '%s' "$owned_files_json" | jq 'length')"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    # A light task's compromises log is AIDA's own file, and no order owns it (gap row 197).
    [ "$light" = "true" ] && [ "$p" = "$COMPROMISES_FILE" ] && continue
    # A record order owns absolute paths under the project folder, and its diff is the project
    # folder's, whose names are relative to it; the two meet on the absolute form. A file AIDA's
    # own scripts write there is counted and set aside: nobody dispatched wrote it.
    if [ "$BR_ORDER_RANGE" = "project" ]; then
      if br_aida_writes_in_project "$p"; then
        set_aside=$((set_aside + 1))
        continue
      fi
      p="$BRC_CODEPATH/$p"
    # A file `task environment up` recorded in the code tree, still as it recorded it (gap row 256).
    elif task_env_recipe_change "$TASK_PATH" "$p" "$BRC_CODEPATH" "$BRC_CURRENT"; then
      env_aside="$env_aside$p, "
      continue
    fi
    matched=false
    gi=0
    while [ "$gi" -lt "$owned_count" ]; do
      g="$(printf '%s' "$owned_files_json" | jq -r --argjson gi "$gi" '.[$gi]')"
      tf_path_matches_catalog_glob "$p" "$g" && matched=true
      if [ "$matched" = "true" ]; then
        [ "$gi" -lt "$own_count" ] || case ", $allowed_hit" in *", $g, "*) ;; *) allowed_hit="$allowed_hit$g, " ;; esac
        break
      fi
      gi=$((gi + 1))
    done
    [ "$matched" = "true" ] || unmatched="$unmatched$p, "
  done <<BR_DIFF
$diff_output
BR_DIFF
  if [ -n "$unmatched" ]; then
    ofc_verdict="unmet"
    ofc_detail="these changed files match none of $(printf '%s' "$BRC_UNIT_JSON" | jq -r '.id')'s own ownedFiles: ${unmatched%, }"
    [ "$BRC_ALLOWED_JSON" = "[]" ] || ofc_detail="${ofc_detail%.}, nor the paths allowed for this round: $(printf '%s' "$BRC_ALLOWED_JSON" | jq -r 'join(", ")')"
    rerun_step="$(task_env_rerun_step "$TASK_PATH" "${unmatched%, }")"
    [ -z "$rerun_step" ] || ofc_detail="${ofc_detail%.}.$rerun_step"
  elif [ -n "$env_aside" ]; then
    ofc_verdict="met"
    ofc_detail="every other file changed between $BRC_STARTED_AT and $BRC_CURRENT matches this order's own ownedFiles."
  else
    ofc_verdict="met"
    ofc_detail="every file changed between $BRC_STARTED_AT and $BRC_CURRENT matches this order's own ownedFiles."
  fi
  [ -z "$env_aside" ] || ofc_detail="$ofc_detail Set aside as files \`task environment up\` recorded: ${env_aside%, }."
  [ -z "$allowed_hit" ] || ofc_detail="$ofc_detail The paths a person allowed for this round that the diff touched: ${allowed_hit%, }."
  if [ "$BR_ORDER_RANGE" = "project" ]; then
    aside_noun="files"
    [ "$set_aside" -ne 1 ] || aside_noun="file"
    ofc_detail="$ofc_detail The diff is the project folder's, with $set_aside $aside_noun AIDA's own scripts write there (a task note, the ledger, another task's close) set aside."
  fi
  jq -n --arg verdict "$ofc_verdict" --arg detail "$ofc_detail" \
    '{id: "owned-files", verdict: $verdict, detail: $detail}' >>"$parts_file"

  # --- every frozen test file is unchanged, and every support file frozen with them ---------------
  # A support file is a base class or a fixture the author wrote beside the tests (live-run row
  # 90). It is hashed here the same as a test: the implementer owns it and may not rewrite it.
  records_hash__resolve_sha256_cmd \
    || die 3 "$BRC_WHO: neither sha256sum nor 'shasum -a 256' was found on PATH"
  local ftc_verdict ftc_detail
  local frozen_paths frozen_count support_count support_noun fidx frozen_file fsha current_sha changed_tests=""
  frozen_paths="$(printf '%s' "$BRC_TESTS_DOC" | jq -c \
    '([ (.rows // [])[] | select(.kind == "machine") | (.tests // [])[] | {path, sha256} ]
      + [ (.support // [])[] | {path, sha256} ]) | unique_by(.path)')"
  frozen_count="$(printf '%s' "$frozen_paths" | jq 'length')"
  support_count="$(printf '%s' "$BRC_TESTS_DOC" | jq '(.support // []) | length')"
  fidx=0
  while [ "$fidx" -lt "$frozen_count" ]; do
    frozen_file="$(printf '%s' "$frozen_paths" | jq -r --argjson fidx "$fidx" '.[$fidx].path')"
    fsha="$(printf '%s' "$frozen_paths" | jq -r --argjson fidx "$fidx" '.[$fidx].sha256')"
    if [ -f "$BRC_CODEPATH/$frozen_file" ]; then
      current_sha="$(tf_sha256_of "$BRC_CODEPATH/$frozen_file")"
    else
      current_sha=""
    fi
    [ "$current_sha" = "$fsha" ] || changed_tests="$changed_tests$frozen_file, "
    fidx=$((fidx + 1))
  done
  if [ -n "$changed_tests" ]; then
    ftc_verdict="unmet"
    ftc_detail="these frozen test or support files no longer match the hash tests-freeze recorded: ${changed_tests%, }"
  elif [ "$frozen_count" -eq 0 ]; then
    # This order froze no test file, so the row hashed nothing and does not apply to it. met read
    # as a hash that was taken and matched, and the executed count then counted a check that ran
    # nothing, which is the one thing that count exists to stop (live-run row 167). undeclared is
    # the word the suite row and the three tool rows already carry on such an order.
    ftc_verdict="undeclared"
    ftc_detail="$(printf '%s' "$BRC_UNIT_JSON" | jq -r '.id') froze no test file, so there is nothing to hash and the row does not apply to it."
  else
    ftc_verdict="met"
    ftc_detail="every frozen test file for $(printf '%s' "$BRC_UNIT_JSON" | jq -r '.id') is unchanged."
    if [ "$support_count" -gt 0 ]; then
      support_noun="files"
      [ "$support_count" -ne 1 ] || support_noun="file"
      ftc_detail="${ftc_detail%.}, and so is each of its $support_count support $support_noun."
    fi
  fi
  jq -n --arg verdict "$ftc_verdict" --arg detail "$ftc_detail" \
    '{id: "frozen-tests", verdict: $verdict, detail: $detail}' >>"$parts_file"

  jq -s '.' "$parts_file" || die 3 "$BRC_WHO: could not assemble the checks"
  rm -f "$parts_file"
}

# How many of the checks in $1 actually executed. A check executed when it ran a command, which is
# every check carrying an exitCode, or when it computed a diff or a hash, which is owned-files and
# frozen-tests. interface-record compares two texts the caller handed over and runs nothing, so it
# is never counted. Prints the number.
#
# The count exists because a record saying eight checks answered, without saying how many of them
# ran, reads the same whether the code was tested or nothing was. That was the defect this count
# closes, and it is recorded and printed for the same reason. So a frozen-tests row that hashed
# nothing is not counted: it reads undeclared, and counting it did the thing the count prevents
# (live-run row 167).
br_executed_count() {
  printf '%s' "$1" | jq -r '
    [ .[] | select(has("exitCode") or .id == "owned-files"
                   or (.id == "frozen-tests" and .verdict != "undeclared")) ] | length'
}

# Whether the checks in $1 let the order pass. $2 is the id whose unknown does not stop the attempt
# (interface-record at build-record, nothing at fix-record). Prints true or false.
#
# Two rules, and the second is the floor. Every check must answer met, undeclared or deferred, with
# the one exempt unknown allowed. And order-tests must have answered met: that check is the only
# one that says this order's own code does what its tests ask, so undeclared or unknown there is an
# order nothing executed. configuration-gate is the same floor for an order whose proof is gate,
# done-when for one whose proof is record, and observed for one whose proof is observe.
# confirm-at-review, for one whose proof is confirm, passes the floor at deferred: its task has no
# automated tests, and the person answers at review (gap row 196).
# Undeclared on every other check still continues, which is the rule step two already applies to
# a precondition a recipe declared nothing for. Deferred continues the same way: the suite row
# is `finish`'s to run, and its answer lands there (nyc defect 18).
br_checks_pass() {
  printf '%s' "$1" | jq -r --arg exempt "$2" '
    (all(.[]; .verdict == "met" or .verdict == "undeclared" or .verdict == "deferred"
              or (.verdict == "unknown" and $exempt != "" and .id == $exempt)))
    and (any(.[]; ((.id == "order-tests" or .id == "configuration-gate" or .id == "done-when" or .id == "observed") and .verdict == "met")
                  or (.id == "confirm-at-review" and .verdict == "deferred")))'
}

# The first check that stopped the order in $1, in the recorded order, with $2 the exempt id as
# above. Prints "<id>: <verdict>, <detail>", or "none: " when nothing stopped it.
br_first_stopper() {
  printf '%s' "$1" | jq -r --arg exempt "$2" '
    [ .[] | select(.verdict == "unmet"
                   or (.verdict == "unknown" and ($exempt == "" or .id != $exempt))
                   or ((.id == "order-tests" or .id == "configuration-gate" or .id == "done-when" or .id == "observed") and .verdict != "met")
                   or (.id == "confirm-at-review" and .verdict != "deferred")) ]
    | .[0] // {id:"none",verdict:"",detail:""}
    | "\(.id): \(.verdict)" + (if .detail == "" then "" else ", " + .detail end)'
}

# The checks that stopped a build attempt, as a jq function two readers prepend to their own
# program: the selection br_first_stopper makes, with interface-record's unknown exempt, over a
# record's own `checks`. `stoppers` is their ids; `outside_recheck` is those ids minus the three
# tool rows and interface-record. A re-check answers an attempt only those rows stopped (live-run
# row 87): a tool refusing a path is the plugin's fault, and an interface record is a record file
# the builder amends without moving the code (gap row 253). A test or a suite failing is the
# implementer's work.
BR_STOPPERS_JQ='def stoppers:
  [ .[] | select(.verdict == "unmet"
                 or (.verdict == "unknown" and .id != "interface-record")
                 or ((.id == "order-tests" or .id == "configuration-gate" or .id == "done-when" or .id == "observed") and .verdict != "met")
                 or (.id == "confirm-at-review" and .verdict != "deferred"))
    | .id ];
def outside_recheck: stoppers | map(select(. != "coding-standards" and . != "static-analysis" and . != "security" and . != "interface-record"));
'

# The interface record's path, for `build-record` and `build-recheck`. $1 the action, $2 the unit
# id, $3 the --interface path, empty when none was passed. Without the flag the path is the brief's
# own interfacePath, the one the implementer was told to write to. The flag stays for a record a
# person put somewhere else (live-run row 102). Sets BR_INTERFACE_PATH and BR_INTERFACE_FROM.
BR_INTERFACE_PATH=""; BR_INTERFACE_FROM=""
br_interface_path() {
  BR_INTERFACE_PATH="$3"
  BR_INTERFACE_FROM="named by --interface"
  [ -z "$BR_INTERFACE_PATH" ] || return 0
  BR_INTERFACE_PATH="$(jq -r '.interfacePath // ""' "$IMPL_DIR/brief-$2-build.json" 2>/dev/null)"
  [ -n "$BR_INTERFACE_PATH" ] \
    || die 3 "$1: --interface was not given, and $IMPL_DIR/brief-$2-build.json names no interfacePath. Run build-brief on $2 again, or pass --interface."
  BR_INTERFACE_FROM="the brief's interfacePath"
}

# Exit 44, and the record's text. $1 the action, $2 the unit id, $3 the interface the order
# declares. Reads BR_INTERFACE_PATH and BR_INTERFACE_FROM. The record is required only when the
# order declares a non-empty interface. Sets BR_INTERFACE_TEXT, empty when there is no file.
BR_INTERFACE_TEXT=""
br_interface_text() {
  BR_INTERFACE_TEXT=""
  if [ -n "$3" ]; then
    [ -s "$BR_INTERFACE_PATH" ] \
      || die 44 "$1: $2 declares a non-empty interface, and the interface record at $BR_INTERFACE_PATH ($BR_INTERFACE_FROM) is missing or empty."
  fi
  [ -f "$BR_INTERFACE_PATH" ] && BR_INTERFACE_TEXT="$(cat "$BR_INTERFACE_PATH" 2>/dev/null)"
  return 0
}

# The names a text holds in backticks, once each, in the order they first appear. $1 the text.
# Prints a JSON array. The build brief lists an order's declared names from this, and check eight
# counts the same names, so the builder is told exactly what the check looks for (gap row 299).
br_interface_names() {
  jq -n --arg s "$1" '
    [ $s | scan("`[^`]*`") | ltrimstr("`") | rtrimstr("`") | select(length > 0) ]
    | reduce .[] as $x ([]; if index($x) then . else . + [$x] end)
  ' 2>/dev/null
}

# Check eight, the interface record, and the countable half of it only. $1 the interface this order
# declares in the frozen snapshot, $2 the text the builder wrote. Prints the check object.
#
# Every backtick-quoted token in the declaration must appear in the record. It appears when the
# record holds it verbatim, or holds a shortened form of it in backticks. A record token is read up
# to its first `(`, so a signature names its function. A shortened form is a name the token ends
# with after a `.` or `::`, and no other declared token ends with it. So `load_rules` names
# `periplus.engine.packload.load_rules`, and a `run_all` that two declared names end with names
# neither (gap row 299). A record token that is itself a declared name stands for that name only.
# A declared token holding a slash or a space is a path or a phrase, and is never shortened. A
# declared token whose last segment holds only lowercase letters and digits may be a file name,
# such as `a.php`. Its shortened form must keep a `.` or `::`, so `map.run` counts and `php` does
# not. The detail lists each shortened form for the reviewer. Any token still missing is unmet,
# naming them. All present is met. A declaration naming no element in backticks has
# nothing countable in it, so this answers unknown and the reviewer reads both texts instead. That
# unknown is the one unknown in this stage that does not spend an attempt (ideal/implementation.md).
# `build-record` runs this check; `fix-record` never does.
br_interface_check() {
  local declared="$1" record="$2"
  local tokens_json token_count missing_json missing_count verdict detail short_json short_text
  tokens_json="$(br_interface_names "$declared")"
  [ -n "$tokens_json" ] || tokens_json='[]'
  token_count="$(printf '%s' "$tokens_json" | jq 'length')"
  if [ "$token_count" -eq 0 ]; then
    verdict="unknown"
    detail="the declaration names no element in backticks, so nothing here is countable; the reviewer reads both texts"
  else
    # The token is bound to $t before the pipe. Inside `$rec | contains(.)` the dot is already $rec,
    # so an unbound form asks whether the record holds itself and every token reads as present.
    missing_json="$(jq -n --argjson toks "$tokens_json" --arg rec "$record" \
      '[ $toks[] as $t | select(($rec | contains($t)) | not) | $t ]')"
    short_json="$(jq -n --argjson toks "$tokens_json" --argjson miss "$missing_json" \
      --argjson recs "$(br_interface_names "$record")" '
      def ends($r): endswith("." + $r) or endswith("::" + $r);
      [ $miss[] as $d | select($d | test("[/\\s]") | not)
        | [ $recs[] | sub("\\(.*$"; "") | select(test("^[A-Za-z_]\\S*$")) | . as $r
            | select(($toks | index([$r])) == null)
            | select($d | ends($r))
            | select(($d | test("[.:][a-z0-9]+$") | not) or ($r | test("\\.|::")))
            | select([ $toks[] | select(ends($r)) ] | length == 1) ]
        | select(length > 0) | {declared: $d, record: .[0]} ]' 2>/dev/null)"
    [ -n "$short_json" ] || short_json='[]'
    missing_json="$(jq -n --argjson miss "$missing_json" --argjson short "$short_json" \
      '$miss - [ $short[].declared ]')"
    short_text="$(printf '%s' "$short_json" | jq -r '
      if length == 0 then "" else "; shortened in the record: " + (map(.record + " for " + .declared) | join(", ")) end')"
    missing_count="$(printf '%s' "$missing_json" | jq 'length')"
    if [ "$missing_count" -eq 0 ] && [ -z "$short_text" ]; then
      verdict="met"
      detail="every element the declaration names in backticks ($token_count of them) appears verbatim in the interface record."
    elif [ "$missing_count" -eq 0 ]; then
      verdict="met"
      detail="every element the declaration names in backticks ($token_count of them) appears in the interface record$short_text."
    else
      verdict="unmet"
      detail="these elements the declaration names in backticks do not appear in the interface record: $(printf '%s' "$missing_json" | jq -r 'join(", ")')$short_text"
    fi
  fi
  jq -n --arg verdict "$verdict" --arg detail "$detail" \
    '{id: "interface-record", verdict: $verdict, detail: $detail}'
}

# Exit 84. The record schema requires exactly eight checks at build-record and seven at fix-record
# (build-record-schema.json and fix-record-schema.json, `checks`), and a check that went missing on
# the way is a record that reads complete while it is not. $1 the action, $2 the file holding the
# assembled checks array, $3 the count the schema requires. Names the check that is absent, and
# removes the file first, so the refusal leaves nothing behind.
br_require_check_count() {
  local who="$1" checks_file="$2" want="$3" have absent
  have="$(jq 'length' "$checks_file" 2>/dev/null)"
  [ "$have" != "$want" ] || return 0
  absent="$(jq -r --argjson want "$want" '
    [ .[] | .id ] as $have
    | ([ "order-tests", "suite-regression", "coding-standards", "static-analysis", "security",
         "owned-files", "frozen-tests" ] + (if $want == 8 then ["interface-record"] else [] end))
    | map(select(. as $id | ($have | index($id)) == null))
    | map(if . == "order-tests" and (($have | index("configuration-gate")) != null or ($have | index("done-when")) != null or ($have | index("observed")) != null or ($have | index("confirm-at-review")) != null) then empty else . end)
    | join(", ")' "$checks_file" 2>/dev/null)"
  rm -f "$checks_file"
  die 84 "$who: the record would hold ${have:-0} checks, and the schema requires $want. Absent: ${absent:-none by name, so one is repeated}. Nothing was written."
}

# The check half of `build-record`, shared with `build-recheck` so a re-check runs exactly what the
# attempt ran (live-run row 87). Seven checks come from the function a fix round calls too, so the
# steps cannot drift into checking different things. The eighth, the interface record, is the build
# step's own: a fix round does not rewrite that record, so it is never re-run there.
#
# Reads the BRC_* globals the caller set, and CR_TEST_RECIPES and CR_CHECK_RECIPES. Every commanded
# check runs a command the recipe declares, resolved here rather than retyped by the caller, and the
# selected-tests row runs this order's own frozen test files. $1 the interface the order declares,
# $2 the text the builder wrote.
#
# Sets BR_CHECKS_FILE, a temporary file holding the eight checks, which the caller reads into its
# record and then removes. The checks carry whole tool outputs, so they travel by file: a
# command-line argument caps at 128KB, and a record that lost a check to that cap printed
# `executed: 5 of 8` over seven checks (nyc defects 9 and 12). Sets BR_CHECKS_JSON, the same eight,
# and BR_EXECUTED, how many of them ran a command, a diff or a hash.
BR_CHECKS_FILE=""; BR_CHECKS_JSON=""; BR_EXECUTED=0
br_eight_checks() {
  local declared="$1" record_text="$2"
  local unit_id seven_file interface_check_json
  unit_id="$(printf '%s' "$BRC_UNIT_JSON" | jq -r '.id')"
  BRC_SELECTED_JSON="$(br_frozen_test_paths "$(printf '%s' "$BRC_TESTS_DOC" | jq -c '.rows // []')")"
  CR_WHO="$BRC_WHO"
  cr_resolve
  cr_require_baseline_recipes "$BRC_WHO" "$BRC_BASELINE_FILE"
  BRC_RECIPES="$CR_DOC"

  interface_check_json="$(br_interface_check "$declared" "$record_text")"
  [ -n "$interface_check_json" ] \
    || die 3 "$BRC_WHO: the interface-record check produced nothing for $unit_id."

  br_require_gate_tokens
  br_require_site_up
  seven_file="$(mktemp)" || die 3 "$BRC_WHO: could not create a temporary file"
  br_seven_checks >"$seven_file"
  [ -s "$seven_file" ] \
    || { rm -f "$seven_file"; die 3 "$BRC_WHO: the seven computable checks produced nothing for $unit_id."; }
  BR_CHECKS_FILE="$(mktemp)" || { rm -f "$seven_file"; die 3 "$BRC_WHO: could not create a temporary file"; }
  jq -c --argjson eighth "$interface_check_json" '. + [$eighth]' "$seven_file" >"$BR_CHECKS_FILE"
  rm -f "$seven_file"
  br_require_check_count "$BRC_WHO" "$BR_CHECKS_FILE" 8
  BR_CHECKS_JSON="$(cat "$BR_CHECKS_FILE" 2>/dev/null)"
  BR_EXECUTED="$(br_executed_count "$BR_CHECKS_JSON")"
  case "$BR_EXECUTED" in ''|*[!0-9]*) BR_EXECUTED=0 ;; esac
}

# The observed record for an order whose proof is observe, refused on one of five facts, each its
# own number (live-run row 104). $1 the action, $2 the unit id, $3 the --observed path, empty when
# none was passed. The record is compared against observed-schema.json through the one library
# every record check uses. The rows are read here as well; since 2026-09-23 that comparison
# descends into them too, so this is a second reading, kept until something removes it.
# The two image fields go through the helper below it. Reads UNIT_JSON for the order's surfaces
# and done-when rows. Reads CRITERIA_JSON for the verification clause of each machine criterion
# the order owns. The look judges those clauses as rows of their own (live-run row 115).
br_require_observed() {
  local who="$1" unit_id="$2" observed="$3" compare gaps bad_surfaces bad_done_when clauses_json
  [ -n "$observed" ] \
    || die 92 "$who: $unit_id is proved by a model's observation, and no --observed was passed. After the implementer returns, open each of the order's surfaces at each viewport with the browser tool, judge each done-when row against what renders, write $IMPL_DIR/observed-$unit_id.json with a screenshot per row, and pass it as --observed."
  [ -f "$observed" ] \
    || die 93 "$who: the observed record at $observed is not there. Write it first, then record the attempt."
  # One path, so a fix round and a re-check read what the build read. Both sides are resolved
  # through the directory, so a relative path or a symlinked folder compares by where it lands.
  local canonical given_real canonical_real
  canonical="$IMPL_DIR/observed-$unit_id.json"
  given_real="$(cd "$(dirname -- "$observed")" 2>/dev/null && printf '%s/%s' "$(pwd -P)" "$(basename -- "$observed")")"
  canonical_real="$(cd "$(dirname -- "$canonical")" 2>/dev/null && printf '%s/%s' "$(pwd -P)" "$(basename -- "$canonical")")"
  [ -n "$given_real" ] && [ "$given_real" = "$canonical_real" ] \
    || die 93 "$who: --observed names $observed, and the observed record for $unit_id lives at $canonical and nowhere else. A fix round and a re-check read that path, so a record accepted from another path would pass the build and stop every fix round. Write it there and pass that path."
  compare="$(schema_check_compare "$OBSERVED_SCHEMA_FILE" "$observed")" \
    || die 93 "$who: $observed could not be read as JSON, or could not be compared against $OBSERVED_SCHEMA_FILE."
  gaps="$(jq -r --argjson r "$compare" --arg unit "$unit_id" '
      [ ($r.missing // [])[] | "no " + .field ]
      + [ ($r.unreadable // [])[] | .field + " " + .reason ]
      + (if (.order // "") == $unit or ((.order // null) == null) then [] else ["order is " + (.order | tostring) + ", not " + $unit] end)
      + (if (.rows | type) != "array" then []
         else [ .rows | to_entries[] | select((.value | type) != "object"
                  or ((.value.doneWhen | type) != "string") or (.value.doneWhen == "")
                  or ((.value.surface | type) != "string") or (.value.surface == "")
                  or ((.value.viewport | type) != "string") or (.value.viewport == "")
                  or ((.value.screenshot | type) != "string") or (.value.screenshot == "")
                  or ((.value.before | type) != "string") or (.value.before == "")
                  or ((.value.verdict != "met") and (.value.verdict != "unmet"))
                  or ((.value.note | type) != "string")
                  or (.value.criterion != null and (if (.value.criterion | type) != "string" then true
                                                    else (.value.criterion | test("^c[1-9][0-9]*$") | not) end)))
                | "row " + (.key | tostring) + " lacks doneWhen, surface, viewport, screenshot, before, a met or unmet verdict, or a note, or its criterion is not a c<n> id" ] end)
      | join("; ")' "$observed" 2>/dev/null)"
  [ -z "$gaps" ] \
    || die 93 "$who: $observed does not match $OBSERVED_SCHEMA_FILE: $gaps. Nothing is recorded."
  # The look after lies under the observed folder, and the look before under the before folder
  # (live-run rows 112 and 114).
  br_require_observed_images "$who" "$observed" screenshot "$IMPL_DIR/observed-$unit_id"
  br_require_observed_images "$who" "$observed" before "$IMPL_DIR/observed-$unit_id-before"
  bad_surfaces="$(jq -r --argjson unit "$UNIT_JSON" '
      ($unit.surfaces // []) as $named
      | [ .rows[].surface | select(. as $s | ($named | index($s)) == null) ] | unique | join(", ")' "$observed")"
  [ -z "$bad_surfaces" ] \
    || die 95 "$who: the observed record names surfaces $unit_id does not: $bad_surfaces. The order's own surfaces are $(printf '%s' "$UNIT_JSON" | jq -r '(.surfaces // []) | join(", ")'). A look at another page proves nothing about this order."
  # A row's sentence is a done-when row, or the verification clause of a machine criterion the
  # order owns, named by `criterion`. The rows may say less than the clause and no script can
  # tell, so the look judges the clause itself (live-run row 115).
  clauses_json="$(printf '%s' "$CRITERIA_JSON" | jq -c --argjson owned "$(printf '%s' "$UNIT_JSON" | jq -c '.criteriaOwned // []')" '
      [ .[] | select(.verifiedBy == "machine" and ((.id as $i | $owned | index($i)) != null)) | {id, clause: .verification} ]')"
  # A verify check of kind live-site is a sentence the order holds too: design carried it from the
  # source that covers the order, and the look judges it as a row of its own. Only that kind needs
  # a served site, so only it is something a page can show. A config-assert reads configuration,
  # and a self-fixture seeds and removes its own data. The reviewer judges those, and a check
  # with no kind.
  bad_done_when="$(jq -r --argjson unit "$UNIT_JSON" --argjson clauses "$clauses_json" --arg unit_id "$unit_id" '
      (($unit.doneWhen // []) + [ ($unit.verify // [])[] | select(.kind == "live-site") | .check // empty ]) as $held
      | [ .rows[] | .criterion as $c | .doneWhen as $d
          | if $c != null then
              (([ $clauses[] | select(.id == $c) ][0]) as $k
               | if $k == null then "\"" + $d + "\" carries criterion " + $c + ", which " + $unit_id + " does not own as a machine criterion"
                 elif $k.clause != $d then "\"" + $d + "\" carries criterion " + $c + ", whose verification clause is \"" + $k.clause + "\""
                 else empty end)
            elif ($held | index($d)) != null then empty
            else (([ $clauses[] | select(.clause == $d) ][0]) as $k
                  | if $k == null then "\"" + $d + "\" is neither a done-when row, a live-site verify check, nor an owned criterion\u0027s clause"
                    else "\"" + $d + "\" is the verification clause of " + $k.id + " and carries no criterion" end)
            end ] | unique | join(" | ")' "$observed")"
  [ -z "$bad_done_when" ] \
    || die 96 "$who: the observed record judges a sentence $unit_id does not hold: $bad_done_when. A row is one of the order's own done-when rows or live-site verify checks, verbatim, or the verification clause of a machine criterion it owns, verbatim, with criterion: <id>."
  # Every row the order owes: each done-when row and each owned machine criterion's clause, at
  # each surface the order names, at each viewport the surface file declares. The file is the
  # one review's surface step reads, at surfaces.registryPath in the project record, joined to
  # the task's own tree.
  local project_folder registry surface_file missing_row
  project_folder="$(resolve_project_folder "$TASK_PATH")" \
    || die 3 "$who: could not resolve a project folder two levels up from $TASK_PATH, or it has no project.json"
  registry="$(jq -r '.surfaces.registryPath // ""' "$project_folder/project.json" 2>/dev/null)"
  [ -n "$registry" ] \
    || die 98 "$who: $project_folder/project.json names no surfaces.registryPath, so the viewports $unit_id owes a look at cannot be known. The surfaces skill's install writes the surface file and that field."
  surface_file="$(sf_surface_path "$registry" "$RV_CODEPATH")"
  sf_load_surfaces "$surface_file"
  [ "$SF_STATE" = "ok" ] \
    || die 98 "$who: the surface file at $surface_file is $SF_STATE, so the viewports $unit_id owes a look at cannot be known. The surfaces skill's install writes it."
  [ "$(printf '%s' "$SF_VIEWPORTS" | jq 'length')" -gt 0 ] \
    || die 98 "$who: the surface file at $surface_file declares no viewport, so the rows $unit_id owes cannot be known. Run the surfaces skill's install with a viewport list."
  missing_row="$(jq -r --argjson unit "$UNIT_JSON" --argjson viewports "$SF_VIEWPORTS" --argjson clauses "$clauses_json" '
      [ .rows[] | (.criterion // "") + "\u001f" + .doneWhen + "\u001f" + .surface + "\u001f" + .viewport ] as $have
      | ([ ($unit.doneWhen // [])[] | {criterion: "", sentence: ., kind: "a done-when row"} ]
         + [ ($unit.verify // [])[] | select(.kind == "live-site") | .check // empty | {criterion: "", sentence: ., kind: "a verify check"} ]
         + [ $clauses[] | {criterion: .id, sentence: .clause, kind: ("the verification clause of " + .id)} ]) as $owed
      | [ $owed[] as $o | ($unit.surfaces // [])[] as $s | $viewports[] as $v
          | select(($have | index($o.criterion + "\u001f" + $o.sentence + "\u001f" + $s + "\u001f" + $v)) == null)
          | "\"" + $o.sentence + "\" at " + $s + " at " + $v + ", " + $o.kind ][0] // ""' "$observed")"
  [ -z "$missing_row" ] \
    || die 97 "$who: the observed record for $unit_id has no row for $missing_row. The order owes one row per sentence, per surface it names, per viewport in $surface_file. The sentences are its done-when rows, its live-site verify checks and the verification clause of each machine criterion it owns. A look not taken is not a met; take it and add the row."
}

# One image field of the observed record, on every row. Each path is on disk and lies under its
# folder, resolved the way the record's path is above. A file where a browser tool put it, in
# /tmp or a scratch folder in the worktree, vanishes with that folder (live-run row 112). Dies 94
# naming the field, each path once and the folder: a clause row shares its image with a done-when
# row (live-run row 115). $1 the action, $2 the record, $3 the field, `screenshot` or `before`,
# $4 the folder the field's images belong under. Every name the loop uses is declared above it
# (trap 5 in this file's own header).
br_require_observed_images() {
  local who="$1" observed="$2" field="$3" folder="$4" shot shot_dir folder_real missing_shots stray_shots
  folder_real="$(cd "$folder" 2>/dev/null && pwd -P)"
  missing_shots=""; stray_shots=""
  while IFS= read -r shot; do
    [ -n "$shot" ] || continue
    if [ ! -f "$shot" ]; then missing_shots="$missing_shots$shot, "; continue; fi
    shot_dir="$(cd "$(dirname -- "$shot")" 2>/dev/null && pwd -P)"
    [ -n "$folder_real" ] && is_under "$shot_dir" "$folder_real" \
      || stray_shots="$stray_shots$shot, "
  done <<BR_SHOTS
$(jq -r --arg f "$field" '[ .rows[][$f] ] | unique[]' "$observed")
BR_SHOTS
  [ -z "$missing_shots" ] \
    || die 94 "$who: these $field images the observed record names are not on disk: ${missing_shots%, }. The look is the evidence, and a row with no image is a claim. Save each under $folder/<surface>-<viewport>.png and name it in the row's $field."
  [ -z "$stray_shots" ] \
    || die 94 "$who: these $field images the observed record names lie outside $folder/: ${stray_shots%, }. A file where a browser tool put it vanishes with that folder, and the evidence with it. Move each under that folder and name the new path in the row's $field."
}

# The fronts of the halts a builder's stop line and a builder's deviation write unattended.
# `build-record --accept-deviation` clears the deviation segments only, so a stop line still halts.
BR_STOP_PREFIX="the builder stopped:"
BR_DEVIATION_PREFIX="the builder declared a deviation:"

# Gap row 286. A builder that meets a defect in a file a closed order owns stops with
# `Stop: closed-order-defect: <file>: <what fails>`. A closed order cannot be reopened, two orders
# may not own one file, and the live fix was a hand commit no reviewer read. So the stop reopens
# the owner for a repair: one finding on its review record, one round added to its allowance, and
# its own fixer and verifier. The owner is found from the snapshot, never from the builder's word.
# Whether the failure really lies in that file is the verifier's to answer, and a no waits for the
# person. The stopped order spends no attempt and waits, through im_require_build_ready and the
# next line, until the owner closes. Fixing one fatal error often shows the next, so another repair
# at the same attempt opens once every earlier one reads addressed. The stopped order's attempt
# allowance caps them, so a builder that stops on every run halts as today. Commits the builder
# made after it began are handled as at any stop: named, and unattended the stopped order halts.
# Exits 0 once the route opens. Returns 1 when it does not apply, and BR_REPAIR_NOTE then says why
# when the line named the kind. $1 the stopped order, $2 the stop line's value, $3 the report,
# $4 the attempt it did not spend, $5 the ledger file, $6 its document, $7 the commits after start,
# $8 the run mode.
BR_REPAIR_KIND="closed-order-defect"
BR_REPAIR_NOTE=""
br_open_repair() {
  local unit_id="$1" value="$2" report="$3" attempt="$4" ledger_file="$5" ledger_doc="$6" commits="$7" run_mode="$8"
  local rest file defect abs rel owner="" owner_glob="" one g owner_entry linked review_file review_doc raw built new_id new_ledger
  local earlier allowed repair_state commit_count commit_text="" rounds_allowed
  case "$value" in "$BR_REPAIR_KIND:"*) ;; *) return 1 ;; esac
  rest="${value#*:}"
  file="$(printf '%s' "${rest%%:*}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  defect="$(printf '%s' "${rest#*:}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  case "$rest" in *:*) ;; *) defect="" ;; esac
  if [ -z "$file" ] || [ -z "$defect" ]; then
    BR_REPAIR_NOTE=" No repair opened: the line must read '$BR_REPAIR_KIND: <file>: <what fails>'."
    return 1
  fi
  abs="$(normalize_abs "$(resolve_against "$file" "$RV_CODEPATH")")"
  rel="${abs#"$RV_CODEPATH"/}"
  # A file the stopped order owns, shared with a closed order, is its own to change, so no other
  # sharer reopens (gap row 287).
  if [ -n "$(im_path_claim "$rel" "$(printf '%s' "$SNAPSHOT_DOC" | jq -c --arg u "$unit_id" '[ .workOrders[] | select(.id == $u) ][0] // {}')")" ]; then
    BR_REPAIR_NOTE=" No repair opened: $unit_id owns $file itself, so the fix is its own."
    return 1
  fi
  while IFS='	' read -r one g; do
    [ -n "$g" ] && [ -z "$owner" ] || continue
    case "$g" in
      /*) tf_path_matches_catalog_glob "$abs" "$g" || continue ;;
      *) tf_path_matches_catalog_glob "$rel" "$g" || continue ;;
    esac
    owner="$one"; owner_glob="$g"
  done <<BR_OWNED
$(printf '%s' "$SNAPSHOT_DOC" | jq -r --arg u "$unit_id" '.workOrders[] | select(.id != $u) | .id as $i | (.ownedFiles // [])[] | $i + "\t" + .')
BR_OWNED
  owner_entry="$(printf '%s' "$ledger_doc" | jq -c --arg id "$owner" '[ (.orders // [])[] | select(.id == $id) ][0] // null')"
  if [ -z "$owner" ] || [ "$(printf '%s' "$owner_entry" | jq -r '.lastStep // ""')" != "closed" ]; then
    BR_REPAIR_NOTE=" No repair opened: no closed order owns $file."
    return 1
  fi
  earlier="$(printf '%s' "$ledger_doc" | jq -r --arg u "$unit_id" --argjson a "$attempt" \
    '(.orders // [])[] | .id as $o | (.repairs // [])[] | select(.by == $u and .attempt == $a) | $o + " " + .finding')"
  allowed="$(attempts_allowed_for "$(printf '%s' "$ledger_doc" | jq -c --arg id "$unit_id" '[ (.orders // [])[] | select(.id == $id) ][0] // {}')")"
  if [ "$(printf '%s' "$earlier" | grep -c .)" -ge "$allowed" ]; then
    BR_REPAIR_NOTE=" No repair opened: $unit_id has opened $allowed at attempt $attempt, as many as its attempts allowed."
    return 1
  fi
  while IFS=' ' read -r one g; do
    [ -n "$g" ] || continue
    repair_state="$(jq -r --arg f "$g" '[ (.findings // [])[] | select(.id == $f) ][0].status // ""' "$IMPL_DIR/review-$one.json" 2>/dev/null)"
    if [ "$repair_state" != "addressed" ]; then
      BR_REPAIR_NOTE=" No repair opened: the repair $unit_id opened on $one at attempt $attempt, $g, reads $repair_state, not addressed."
      return 1
    fi
  done <<BR_EARLIER
$earlier
BR_EARLIER
  linked="$(printf '%s' "$SNAPSHOT_DOC" | jq -r --arg id "$owner" \
    '[ .workOrders[] | select(.id == $id) | (.criteriaOwned // []) + (.criteriaServed // []) | .[] ][0] // ""')"
  review_file="$IMPL_DIR/review-$owner.json"
  review_doc="$(jq -c '.' "$review_file" 2>/dev/null)"
  [ -n "$review_doc" ] \
    || die 3 "build-record: $review_file is missing or not JSON, though the ledger records $owner as closed."
  new_id="f$(printf '%s' "$review_doc" | jq '[ (.findings // [])[] | .id | ltrimstr("f") | tonumber? // 0 ] | max // 0 | . + 1')"
  case "$owner_glob" in /*) rel="$abs" ;; esac
  raw="$(jq -cn --arg id "$new_id" --arg file "$rel" --arg linked "$linked" \
    --arg evidence "$unit_id stopped at attempt $attempt on a defect in this file: $defect. Its report: $report." \
    '{id: $id, severity: "high", file: $file, lines: "", linkedTo: $linked, evidence: $evidence, fixScope: [$file]}')"
  built="$(rv_finding_record "$raw" "$(printf '%s' "$SNAPSHOT_DOC" | jq -c '.alignment // {}')" repair)"
  if [ "$(printf '%s' "$built" | jq -r '.actionable')" != "true" ]; then
    BR_REPAIR_NOTE=" No repair opened: $owner serves no criterion, so no fixer could act on the finding."
    return 1
  fi
  built="$(printf '%s' "$built" | jq -c '.actionableBecause += "; the repair took the owner'"'"'s first criterion by position, and nobody judged the link"')"
  review_doc="$(printf '%s' "$review_doc" | jq -c --argjson f "$built" '.findings = ((.findings // []) + [$f])')"
  [ -n "$review_doc" ] || die 3 "build-record: the repair finding on $owner could not be written."
  # Back to the step its fix rounds follow. The range close wrote stays on the repair entry, and
  # close writes the order's range again.
  new_ledger="$(printf '%s' "$ledger_doc" | jq -c --arg id "$owner" --arg u "$unit_id" --argjson a "$attempt" \
    --arg f "$new_id" --arg report "$report" --arg at "$(date -u +%Y-%m-%d)" '
    .orders = (.orders | map(if .id == $id then
      (.repairs = ((.repairs // []) + [{by: $u, attempt: $a, finding: $f, report: $report, at: $at}
                                       + (if .commitRange then {closedRange: .commitRange} else {} end)])
       | .lastStep = (if (.roundsUsed // 0) > 0 then "fixed" else "reviewed" end)
       | del(.commitRange))
      else . end))')"
  [ -n "$new_ledger" ] || die 3 "build-record: the repair on $owner could not be written to the ledger."
  if [ -n "$commits" ]; then
    commit_count="$(printf '%s' "$commits" | wc -w | tr -d ' ')"
    commit_text="It committed $commit_count after it began: $commits."
    if [ "$run_mode" = "autonomous" ]; then
      new_ledger="$(halt_order_in "$new_ledger" "$unit_id" "$BR_STOP_PREFIX a Stop: line says so, at $report. $commit_text")"
      [ -n "$new_ledger" ] || die 3 "build-record: the halt on $unit_id could not be written."
    fi
    commit_text="$commit_text Revert them, or have the person keep them, before the next build."
  fi
  rounds_allowed="$(order_fix_rounds_allowed "$(printf '%s' "$new_ledger" | jq -c --arg id "$owner" '[ .orders[] | select(.id == $id) ][0]')")"
  write_atomic "$review_file" "$review_doc"
  write_atomic "$ledger_file" "$new_ledger"
  im_print_summary "build-record" "$(jq -cn --arg order "$unit_id" --arg owner "$owner" --arg f "$new_id" \
    --arg linked "$linked" --arg file "$rel" --arg commits "$commit_text" --arg record "$review_file" \
    --arg rounds "$(printf '%s' "$owner_entry" | jq -r '.roundsUsed // 0') used of $rounds_allowed" \
    --arg next "$(im_next_step "$new_ledger" "$SNAPSHOT_DOC" "$IMPL_DIR" "true" "false")" '
    {order: $order,
     state: "stopped on a defect in a closed order'"'"'s file. A stop is not an attempt, so no attempt is spent",
     repair: "\($owner) reopened on \($f), citing \($linked) as its first criterion, in \($file). Its fix rounds allowed rose by one: \($rounds)",
     waiting: ("\($order) builds again once \($owner) closes." + (if $commits == "" then "" else " " + $commits end)),
     record: $record,
     next: $next}')"
  exit 0
}

do_build_record() {
  local task_arg="" unit_id="" interface_path="" report_path="" started_at="" observed_path=""
  local nothing_ran="" have_nothing_ran=false accept=""
  local test_recipes="" check_recipes="" gate_recipes="" values=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --accept-deviation)
        [ "$#" -ge 2 ] || die 3 "build-record: --accept-deviation needs the person's reason for keeping the deviation"
        [ -n "$2" ] || die 3 "build-record: --accept-deviation was given an empty reason."
        accept="$2"; shift 2 ;;
      --interface)
        [ "$#" -ge 2 ] || die 3 "build-record: --interface needs a path to the record the builder wrote"
        [ -n "$2" ] || die 3 "build-record: --interface was given an empty path."
        interface_path="$2"; shift 2 ;;
      --observed)
        [ "$#" -ge 2 ] || die 3 "build-record: --observed needs a path to the observed record the orchestrator wrote"
        [ -n "$2" ] || die 3 "build-record: --observed was given an empty path."
        observed_path="$2"; shift 2 ;;
      --report)
        [ "$#" -ge 2 ] || die 3 "build-record: --report needs a path to the builder's report"
        [ -n "$2" ] || die 3 "build-record: --report was given an empty path."
        report_path="$2"; shift 2 ;;
      --started-at)
        [ "$#" -ge 2 ] || die 3 "build-record: --started-at needs a commit"
        [ -n "$2" ] || die 3 "build-record: --started-at was given an empty commit."
        started_at="$2"; shift 2 ;;
      --test-recipe)
        [ "$#" -ge 2 ] || die 3 "build-record: --test-recipe needs <framework>=<path>"
        cr_recipe_pair "build-record" "--test-recipe" "$2"
        test_recipes="$test_recipes$CR_PAIR
"
        shift 2 ;;
      --check-recipe)
        [ "$#" -ge 2 ] || die 3 "build-record: --check-recipe needs <framework>=<path>"
        cr_recipe_pair "build-record" "--check-recipe" "$2"
        check_recipes="$check_recipes$CR_PAIR
"
        shift 2 ;;
      --implement-recipe)
        [ "$#" -ge 2 ] || die 3 "build-record: --implement-recipe needs <framework>=<path>"
        cr_recipe_pair "build-record" "--implement-recipe" "$2"
        gate_recipes="$gate_recipes$CR_PAIR
"
        shift 2 ;;
      --value)
        [ "$#" -ge 2 ] || die 3 "build-record: --value needs <name>=<value>"
        case "$2" in *=*) ;; *) die 3 "build-record: --value takes <name>=<value>, got: $2" ;; esac
        pc_refuse_forged_value "build-record" "$2"
        values="$values$(printf '%s' "$2" | sed 's/=/\t/')
"
        shift 2 ;;
      --nothing-ran)
        [ "$#" -ge 2 ] || die 3 "build-record: --nothing-ran needs a literal substring"
        [ -n "$2" ] || die 3 "build-record: --nothing-ran was given an empty substring, which every output holds."
        have_nothing_ran=true
        nothing_ran="$2"
        shift 2 ;;
      -*) die 3 "build-record: unrecognized argument: $1" ;;
      *)
        if [ -z "$task_arg" ]; then
          task_arg="$1"
        elif [ -z "$unit_id" ]; then
          unit_id="$1"
        else
          die 3 "build-record: unrecognized extra argument: $1"
        fi
        shift ;;
    esac
  done

  [ -n "$task_arg" ]        || die 3 "build-record: a task folder is required"
  [ -n "$unit_id" ]         || die 3 "build-record: a unit id is required"
  [ -n "$report_path" ]     || die 3 "build-record: --report is required"
  [ -s "$report_path" ]     || die 3 "build-record: --report names no file, or an empty one: $report_path"
  [ -n "$started_at" ]      || die 3 "build-record: --started-at is required"

  local resolve_rc
  TASK_PATH="$(resolve_task_folder "$task_arg" "build-record")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  IMPL_DIR="$TASK_PATH/implementation"
  [ -z "$accept" ] || fn_require_interactive "build-record" "keeping a deviation the builder declared"

  tt_load_snapshot "build-record"
  tt_load_unit_and_criteria "$SNAPSHOT_DOC" "$unit_id" "build-record"

  local tests_file="$IMPL_DIR/tests-$unit_id.json" tests_doc
  [ -f "$tests_file" ] \
    || die 3 "build-record: $tests_file not found, though a build attempt implies tests-brief and tests-freeze already ran for $unit_id. Run tests-freeze on it first."
  tests_doc="$(jq -c '.' "$tests_file" 2>/dev/null)"
  [ -n "$tests_doc" ] \
    || die 3 "build-record: $tests_file exists but could not be read as JSON. Repair or remove it by hand before running this again."

  local ledger_file="$IMPL_DIR/ledger.json" ledger_doc
  [ -f "$ledger_file" ] \
    || die 3 "build-record: $ledger_file not found, though $IMPL_DIR/snapshot.json exists. A snapshot with no ledger beside it is not a supported state; run start again."
  ledger_doc="$(jq -c '.' "$ledger_file" 2>/dev/null)"
  [ -n "$ledger_doc" ] \
    || die 3 "build-record: $ledger_file exists but could not be read as JSON. Repair or remove it by hand before running this again."
  local order_entry attempts_used_before attempt_number
  order_entry="$(printf '%s' "$ledger_doc" | jq -c --arg id "$unit_id" \
    '(.orders // []) | map(select(.id == $id)) | .[0] // null')"
  [ "$order_entry" != "null" ] \
    || die 3 "build-record: $unit_id has no entry in $ledger_file, though start opens one entry per snapshot work order."
  attempts_used_before="$(printf '%s' "$order_entry" | jq -r '.attemptsUsed // 0')"
  case "$attempts_used_before" in ''|*[!0-9]*) attempts_used_before=0 ;; esac
  attempt_number=$((attempts_used_before + 1))
  local attempts_allowed
  attempts_allowed="$(attempts_allowed_for "$order_entry")"
  # Exit 49. A halted order records no attempt, or a build after a Stop: line halt records over it.
  # --accept-deviation answers the deviation's own halt, so only that segment lets the step through.
  local br_halted
  br_halted="$(printf '%s' "$order_entry" | jq -r '.haltedBecause // ""')"
  [ -z "$accept" ] || br_halted="$(halt_segments_matching "$br_halted" "$(jq -cn --arg p "$BR_DEVIATION_PREFIX" '[$p]')" drop)"
  [ -z "$br_halted" ] \
    || die 49 "build-record: $unit_id is halted, so this step refuses. The ledger records the reason: $br_halted"

  # --- the task's own project, through the one reader every step-five action already uses ---------
  # The range lives in the code worktree, or in the project folder for an order whose proof is
  # record; every git read below goes to that one repository.
  local codepath
  rv_load_codepath "build-record"
  rv_load_range_repo "build-record" "$UNIT_JSON"
  codepath="$RV_RANGE_REPO"

  # --- exit 43: --started-at must be a real commit in this repository ------------------------------
  local started_at_full current_commit
  started_at_full="$(git -C "$codepath" rev-parse --verify --quiet "${started_at}^{commit}" 2>/dev/null)"
  [ -n "$started_at_full" ] \
    || die 43 "build-record: --started-at ($started_at) is not a commit in $RV_RANGE_NAME at $codepath."
  current_commit="$(git -C "$codepath" rev-parse HEAD 2>/dev/null)"
  [ -n "$current_commit" ] \
    || die 3 "build-record: could not capture the current commit (git rev-parse HEAD failed in $codepath)."

  br_interface_path "build-record" "$unit_id" "$interface_path"
  interface_path="$BR_INTERFACE_PATH"

  # --- exits 105 and 106: the builder's stop and deviation lines, read before anything is judged ---
  # A builder once named a misfit in prose and then built around it (gap row 219). So every report
  # carries exactly one stop line, `Stop: none` or `Stop: <cause>: <reason>`, and the builder has to
  # choose. It then wrote the misfit up as a deviation under `Stop: none` (gap row 221). So a report
  # also carries exactly one `Deviation: none` or `Deviation: <what>: <why>`, and the interface
  # record may carry the same line. A deviation other than none is a stop, and so is a heading
  # that starts with "Deviation" in either file, checked before the count. A stop recorded as an
  # attempt spends the budget on work the rule forbade. The halt reason names the file and the
  # commits, never the builder's text, because that text may hold the halt separator.
  # A person may keep a deviation, never a stop line: --accept-deviation records the attempt with
  # the first deviation line and the reason, the way review-record keeps a departure (gap row 266).
  # A deviation from a play stops too. The line has no kind a script can read, and a kind the
  # builder writes itself would let it mark any deviation as a play. So a person sees each one.
  local ledger_run_mode stop_lines stop_value stop_file="$report_path"
  local is_deviation=false accepted_json=""
  # The task's own mode, not the ledger's copy from start (gap row 265).
  ledger_run_mode="$(task_run_mode "$TASK_PATH" implement)"
  local lines_fault lines_rc turn_note=""
  lines_fault="$(br_lines_fault "$report_path" "$interface_path")"
  lines_rc=$?
  [ "$lines_rc" != "2" ] \
    || turn_note=" A builder stopped at its turn limit writes none: run dispatch-open with implementer, $unit_id and --resume, then resume the same agent by message."
  [ -z "$lines_fault" ] \
    || die 106 "build-record: $lines_fault Nothing is recorded and no attempt is spent. Have the builder write the line alone, put any note on its own line, then run build-record again.$turn_note"
  stop_lines="$(br_marked_lines "$report_path" stop)"
  stop_value="$(printf '%s' "${stop_lines#*:}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  case "$stop_value" in
    [Nn][Oo][Nn][Ee])
      stop_lines="$(br_deviations "$report_path")"
      if [ -z "$stop_lines" ] && [ -f "$interface_path" ]; then
        stop_file="$interface_path"
        stop_lines="$(br_deviations "$interface_path")"
      fi
      if [ -z "$stop_lines" ]; then
        [ -z "$accept" ] \
          || die 3 "build-record: --accept-deviation was given, and neither the report nor the interface record of $unit_id names a deviation. Nothing is written."
      else
        is_deviation=true
      fi
      ;;
  esac
  if $is_deviation && [ -n "$accept" ]; then
    accepted_json="$(jq -cn --arg d "$(printf '%s\n' "$stop_lines" | head -n 1)" --arg f "$stop_file" --arg b "$accept" \
      '{departure: $d, file: $f, because: $b}')"
    stop_lines=""
  fi
  # Gap row 279. Unattended, a deviation stops nothing: the attempt is recorded, and review-record
  # finds the same line and keeps it for the person at the task review.
  if $is_deviation && [ "$ledger_run_mode" = "autonomous" ]; then
    stop_lines=""
  fi
  if [ -n "$stop_lines" ]; then
    local stop_commits stop_commit_count stop_commit_text=""
    stop_commits="$(git -C "$codepath" log --format=%h "$started_at_full..$current_commit" 2>/dev/null | tr '\n' ' ')"
    stop_commits="${stop_commits% }"
    $is_deviation \
      || br_open_repair "$unit_id" "$stop_value" "$report_path" "$attempt_number" "$ledger_file" "$ledger_doc" "$stop_commits" "$ledger_run_mode"
    stop_commit_count="$(printf '%s' "$stop_commits" | wc -w | tr -d ' ')"
    if [ "$stop_commit_count" -gt 0 ]; then
      stop_commit_text=" It committed $stop_commit_count after it began: $stop_commits."
    fi
    local keep_route="" halt_front="$BR_STOP_PREFIX a Stop: line says so"
    if $is_deviation; then
      keep_route=" Or, interactive only, a person keeps the deviation: run build-record again with --accept-deviation <their reason>."
      halt_front="$BR_DEVIATION_PREFIX a Deviation: line or heading says so"
    fi
    if [ "$ledger_run_mode" = "autonomous" ]; then
      local stop_ledger_doc
      stop_ledger_doc="$(halt_order_in "$ledger_doc" "$unit_id" "$halt_front, at $stop_file.$stop_commit_text$keep_route")"
      [ -n "$stop_ledger_doc" ] || die 3 "build-record: the halt on $unit_id could not be written."
      write_atomic "$ledger_file" "$stop_ledger_doc"
    fi
    [ -z "$stop_commit_text" ] \
      || stop_commit_text="$stop_commit_text Revert them, or have the person keep them, before the next build."
    die 105 "build-record: the builder's file at $stop_file says it stopped: $stop_lines. A stop is not an attempt, so nothing is recorded and no attempt is spent.$stop_commit_text Put the stop to the person as the builder's stop in references/build.md.$keep_route$BR_REPAIR_NOTE"
  fi
  br_require_real_base "build-record" "$codepath" "$started_at" "$started_at_full" "$current_commit"

  # --- exit 45: refuse a duplicate of an attempt already recorded, before anything else runs -------
  local record_file="$IMPL_DIR/build-$unit_id.json"
  if [ -f "$record_file" ]; then
    local existing_doc existing_commit existing_attempt
    existing_doc="$(jq -c '.' "$record_file" 2>/dev/null)"
    [ -n "$existing_doc" ] \
      || die 3 "build-record: $record_file exists but could not be read as JSON. Repair or remove it by hand before running this again."
    existing_commit="$(printf '%s' "$existing_doc" | jq -r '.commit // empty')"
    existing_attempt="$(printf '%s' "$existing_doc" | jq -r '.attempt // empty')"
    if [ "$existing_commit" = "$current_commit" ] && [ "$existing_attempt" = "$attempt_number" ]; then
      die 45 "build-record: $record_file already holds attempt $attempt_number at commit $current_commit. Nothing has changed since that record was written."
    fi
    # The guard above keys on the commit and the attempt number together, so a repeat call after a
    # failed attempt computed a new attempt number, passed it, re-ran every check against unchanged
    # code and spent the last attempt on work nobody did. The previous attempt's own commit is the
    # fact that decides it, which is the rule fix-record already applies to its previous round.
    if [ -n "$existing_commit" ] && [ "$existing_commit" = "$current_commit" ]; then
      die 45 "build-record: $record_file already holds attempt $existing_attempt at commit $current_commit, so the code has not moved since that attempt. An attempt spent on unchanged code is an attempt nobody worked."
    fi
  fi

  # --- exit 44: the interface record is required only when the unit declares a non-empty interface -
  local unit_interface_declared interface_text
  unit_interface_declared="$(printf '%s' "$UNIT_JSON" | jq -r '.interface // ""')"
  br_interface_text "build-record" "$unit_id" "$unit_interface_declared"
  interface_text="$BR_INTERFACE_TEXT"

  # --- exits 92 to 96: an order whose proof is observe needs the observed record, checked here ------
  # The record is the orchestrator's account of what a model saw at each surface and viewport
  # (observed-schema.json, live-run row 104). Its shape and every row are checked against the
  # frozen order before any check runs, so the observed check below reads a record that is this
  # order's: a screenshot on disk per row, a surface the order names, a done-when the order holds.
  # The summary names the criteria whose clause the look judged (live-run row 115). Null keeps
  # the line off a code order's summary. It also keeps it off an observe order that owns no
  # machine criterion.
  local criteria_judged_json='null'
  br_order_facts "$UNIT_JSON"
  if [ "$BR_ORDER_SLOT" = "observed" ]; then
    br_require_observed "build-record" "$unit_id" "$observed_path"
    criteria_judged_json="$(jq -c '[ .rows[] | .criterion // empty ] | unique | if length == 0 then null else . end' "$observed_path")"
  fi

  br_require_clean_tree "build-record" "$codepath" "$unit_id" "$ledger_run_mode" "$ledger_file" "$ledger_doc" "$RV_RANGE_PATHS"

  # --- the eight deciding checks ---------------------------------------------------------------------
  # Seven of them are computable by the same function a fix round calls, so the two steps can never
  # drift into checking different things. The eighth, the interface record, is this step's own: a fix
  # round does not rewrite that record, so it is never re-run there.
  BRC_WHO="build-record"
  BRC_CODEPATH="$codepath"
  BRC_SCOPE="$RV_RANGE_SCOPE"
  BRC_STARTED_AT="$started_at_full"
  BRC_CURRENT="$current_commit"
  BRC_UNIT_JSON="$UNIT_JSON"
  BRC_TESTS_DOC="$tests_doc"
  BRC_BASELINE_FILE="$IMPL_DIR/baseline.json"
  CR_TEST_RECIPES="$test_recipes"
  CR_CHECK_RECIPES="$check_recipes"
  BRC_VALUES="$values"
  BRC_NOTHING_RAN="$nothing_ran"
  BRC_HAVE_NOTHING_RAN="$have_nothing_ran"
  BRC_GATE_RECIPES="$gate_recipes"
  BRC_OBSERVED="$observed_path"
  br_eight_checks "$unit_interface_declared" "$interface_text"
  local checks_file checks_json
  checks_file="$BR_CHECKS_FILE"
  checks_json="$BR_CHECKS_JSON"

  local today record_json executed_count
  executed_count="$BR_EXECUTED"
  today="$(date -u +%Y-%m-%d)"
  record_json="$(jq -c \
    --arg takenAt "$today" --arg unit "$unit_id" --arg startedAt "$started_at_full" \
    --arg commit "$current_commit" --argjson attempt "$attempt_number" \
    --arg interfaceRecord "$interface_text" --arg reportPath "$report_path" \
    --argjson executed "$executed_count" --argjson accepted "${accepted_json:-null}" \
    '{
      schemaVersion: 1,
      takenAt: $takenAt,
      unit: $unit,
      startedAt: $startedAt,
      commit: $commit,
      attempt: $attempt,
      interfaceRecord: $interfaceRecord,
      reportPath: $reportPath,
      checks: .,
      executed: $executed,
      decidingChecks: { total: 8, ranHere: [ .[] | .id ] }
    }
    + (if $accepted == null then {} else {deviationAccepted: $accepted} end)' "$checks_file")"
  rm -f "$checks_file"
  [ -n "$record_json" ] || die 3 "build-record: could not assemble the record for $unit_id."

  write_atomic "$record_file" "$record_json"

  # The attempt is spent whatever the checks said. Then the order's state: checks-passed when no
  # check answered unmet or unknown, code-written otherwise. Undeclared continues, the same rule
  # step two applies to a precondition: a check nobody declared was not run, and the record says so
  # in that word, but it is not a check that answered no. And when the attempt that did not pass was the last
  # one allowed, the order halts here, at the moment the fact becomes true, rather than when the
  # next build-brief refuses. A halt written only on refusal is a halt nobody sees until they ask,
  # and unattended nobody asks: the run would leave the order "in flight" with no reason on it.
  #
  # interface-record is the one exception, and only for its unknown. That check answers unknown when
  # the declaration names nothing in backticks, which is a question for the reviewer and not a fault
  # in the code (ideal/implementation.md). Its unmet still stops the attempt like any other.
  #
  # order-tests is the floor under all of it. That check is the only one that says this order's own
  # code does what its tests ask, so it must have run and answered met. Undeclared there is an
  # order nothing executed, and an order nothing executed never reaches checks-passed.
  local all_met first_stopper
  all_met="$(br_checks_pass "$checks_json" "interface-record")"
  first_stopper="$(br_first_stopper "$checks_json" "interface-record")"
  # The counter and the step move in one update; the halt, when there is one, goes through the one
  # helper that writes every halt, so this reason never erases a reason the order already carried.
  local step_expr halt_why
  halt_why=""
  if [ "$all_met" = "true" ]; then
    step_expr='.attemptsUsed = (.attemptsUsed + 1) | .lastStep = "checks-passed"'
  else
    step_expr='.attemptsUsed = (.attemptsUsed + 1) | .lastStep = "code-written"'
    if [ "$attempt_number" -ge "$attempts_allowed" ]; then
      halt_why="attempts spent: $attempt_number of $attempts_allowed, and the last was stopped by $first_stopper"
    fi
  fi
  local new_ledger_doc
  new_ledger_doc="$(printf '%s' "$ledger_doc" | jq -c --arg id "$unit_id" \
    ".orders = (.orders | map(if .id == \$id then ($step_expr) else . end))")"
  [ -n "$new_ledger_doc" ] || die 3 "build-record: the ledger update for $unit_id failed."
  # A kept deviation clears the deviation's own halt, and records the reason in haltsCleared whether
  # or not the order carried that halt, as review-record does.
  if [ -n "$accepted_json" ]; then
    new_ledger_doc="$(accept_deviation_in "$new_ledger_doc" "$unit_id" "$(jq -cn --arg p "$BR_DEVIATION_PREFIX" '[$p]')" \
      "$BR_DEVIATION_PREFIX a Deviation: line or heading says so, at $stop_file." "$accept")"
    [ -n "$new_ledger_doc" ] || die 3 "build-record: the ledger update for $unit_id failed."
  fi
  if [ -n "$halt_why" ]; then
    new_ledger_doc="$(halt_order_in "$new_ledger_doc" "$unit_id" "$halt_why")"
    [ -n "$new_ledger_doc" ] || die 3 "build-record: the halt on $unit_id could not be written."
  fi
  write_atomic "$ledger_file" "$new_ledger_doc"

  # The summary: one line per check with its verdict and this script's own one-line detail. What
  # each tool printed stays in the record, named by path.
  local br_state br_next
  if [ "$all_met" = "true" ]; then br_state="checks-passed"; else br_state="code-written, stopped by $first_stopper"; fi
  br_next="$(im_next_step "$new_ledger_doc" "$SNAPSHOT_DOC" "$IMPL_DIR" "true" "false")"
  im_print_summary "build-record" "$(printf '%s' "$record_json" | jq -c \
    --arg attempts "$attempt_number of $attempts_allowed" --arg state "$br_state" \
    --arg halt "${halt_why:-none}" --arg record "$record_file" --arg next "$br_next" \
    --argjson criteriaJudged "$criteria_judged_json" '
    {order: .unit,
     attempt: $attempts,
     range: "\(.startedAt)..\(.commit)",
     check: ([ .checks[] | {id, verdict, detail: (.detail // "")} ])}
    + (if $criteriaJudged == null then {} else {criteriaJudged: $criteriaJudged} end)
    + {executed: "\(.executed) of 8 ran a command, a diff or a hash",
     state: $state}
    + (if has("deviationAccepted") then {departureAccepted: .deviationAccepted.because} else {} end)
    + {halt: $halt,
     record: $record,
     next: $next}')"
  if [ "$all_met" != "true" ] && [ "$attempt_number" -ge "$attempts_allowed" ]; then
    echo "BUILD-RECORD: $unit_id is halted. Attempts spent: $attempt_number of $attempts_allowed. The last was stopped by $first_stopper" >&2
  fi
  exit 0
}

# ------------------------------------------------------------------------------------------------
# build-recheck: the eight checks again, over the range the build record already holds, with no
# implementer dispatched and no attempt spent (live-run row 87). An attempt whose only unmet checks
# were the tool rows refusing had no route back: `build-brief` hands over a brief with nothing to
# build, and `build-record` refuses an empty range (exit 71) or an unmoved head (exit 45). Both
# refusals are right, so this action is the route. It takes the recipe flags `build-record` takes
# and its --interface, and none of its other record flags: the range and the report path are the
# record's own. The interface record is read again from its file, because an attempt that
# interface-record stopped is answered by amending that file, which moves no code (gap row 253).
# It is not a free retry: an attempt a test or a suite stopped is the implementer's work, and it
# refuses (exit 88).
# ------------------------------------------------------------------------------------------------
do_build_recheck() {
  local task_arg="" unit_id="" interface_path=""
  local nothing_ran="" have_nothing_ran=false
  local test_recipes="" check_recipes="" gate_recipes="" values=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --test-recipe)
        [ "$#" -ge 2 ] || die 3 "build-recheck: --test-recipe needs <framework>=<path>"
        cr_recipe_pair "build-recheck" "--test-recipe" "$2"
        test_recipes="$test_recipes$CR_PAIR
"
        shift 2 ;;
      --check-recipe)
        [ "$#" -ge 2 ] || die 3 "build-recheck: --check-recipe needs <framework>=<path>"
        cr_recipe_pair "build-recheck" "--check-recipe" "$2"
        check_recipes="$check_recipes$CR_PAIR
"
        shift 2 ;;
      --implement-recipe)
        [ "$#" -ge 2 ] || die 3 "build-recheck: --implement-recipe needs <framework>=<path>"
        cr_recipe_pair "build-recheck" "--implement-recipe" "$2"
        gate_recipes="$gate_recipes$CR_PAIR
"
        shift 2 ;;
      --value)
        [ "$#" -ge 2 ] || die 3 "build-recheck: --value needs <name>=<value>"
        case "$2" in *=*) ;; *) die 3 "build-recheck: --value takes <name>=<value>, got: $2" ;; esac
        pc_refuse_forged_value "build-recheck" "$2"
        values="$values$(printf '%s' "$2" | sed 's/=/\t/')
"
        shift 2 ;;
      --interface)
        [ "$#" -ge 2 ] || die 3 "build-recheck: --interface needs a path to the record the builder wrote"
        [ -n "$2" ] || die 3 "build-recheck: --interface was given an empty path."
        interface_path="$2"; shift 2 ;;
      --nothing-ran)
        [ "$#" -ge 2 ] || die 3 "build-recheck: --nothing-ran needs a literal substring"
        [ -n "$2" ] || die 3 "build-recheck: --nothing-ran was given an empty substring, which every output holds."
        have_nothing_ran=true
        nothing_ran="$2"
        shift 2 ;;
      -*) die 3 "build-recheck: unrecognized argument: $1" ;;
      *)
        if [ -z "$task_arg" ]; then
          task_arg="$1"
        elif [ -z "$unit_id" ]; then
          unit_id="$1"
        else
          die 3 "build-recheck: unrecognized extra argument: $1"
        fi
        shift ;;
    esac
  done
  [ -n "$task_arg" ] || die 3 "build-recheck: a task folder is required"
  [ -n "$unit_id" ]  || die 3 "build-recheck: a unit id is required"

  local resolve_rc
  TASK_PATH="$(resolve_task_folder "$task_arg" "build-recheck")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  IMPL_DIR="$TASK_PATH/implementation"

  # The step-five state: the ledger, the frozen order, and the halt refusal (exit 49). A halted
  # order's route is `grant-attempt` or `clear-halt`, never a re-check. No step is required here:
  # the record's own checks say whether the attempt is one a re-check answers.
  rv_load_state "build-recheck" "$unit_id"

  # --- exit 88, one: no attempt was recorded, so there is nothing to run the checks over again ----
  local record_file="$IMPL_DIR/build-$unit_id.json"
  [ -f "$record_file" ] \
    || die 88 "build-recheck: $record_file does not exist, so no attempt at $unit_id was recorded and there is no range to run the checks over. The route is build."
  rv_load_build_record "build-recheck" "$unit_id"
  local record_started_at record_commit record_attempt
  record_started_at="$(printf '%s' "$RV_BUILD_DOC" | jq -r '.startedAt // ""')"
  record_commit="$(printf '%s' "$RV_BUILD_DOC" | jq -r '.commit // ""')"
  record_attempt="$(printf '%s' "$RV_BUILD_DOC" | jq -r '.attempt // 0')"
  [ -n "$record_started_at" ] && [ -n "$record_commit" ] \
    || die 3 "build-recheck: $record_file holds no startedAt or no commit, so its range cannot be read. Repair or remove it by hand before running this again."

  # --- exit 88, two: the code moved since the attempt, so the next attempt is a build ------------
  local codepath current_commit
  rv_load_codepath "build-recheck"
  rv_load_range_repo "build-recheck" "$RV_UNIT_JSON"
  codepath="$RV_RANGE_REPO"
  current_commit="$(git -C "$codepath" rev-parse HEAD 2>/dev/null)"
  [ -n "$current_commit" ] \
    || die 3 "build-recheck: could not capture the current commit (git rev-parse HEAD failed in $codepath)."
  [ "$current_commit" = "$record_commit" ] \
    || die 88 "build-recheck: $RV_RANGE_NAME is at $current_commit and the record holds attempt $record_attempt at $record_commit, so the code has moved since that attempt. A re-check runs over the recorded range alone; the route is build."

  # --- exit 88, three: a check outside the tool rows and interface-record stopped the attempt,
  # which is the implementer's work to answer, so a re-check would be a free retry. An attempt
  # nothing stopped is past the build, and there is nothing to run again -------------------------
  local stoppers outside
  stoppers="$(printf '%s' "$RV_BUILD_DOC" | jq -r "$BR_STOPPERS_JQ"'(.checks // []) | stoppers | join(", ")')"
  [ -n "$stoppers" ] \
    || die 88 "build-recheck: attempt $record_attempt at $unit_id passed its checks, so there is nothing to run again. The order is past the build."
  outside="$(printf '%s' "$RV_BUILD_DOC" | jq -r "$BR_STOPPERS_JQ"'(.checks // []) | outside_recheck | join(", ")')"
  [ -z "$outside" ] \
    || die 88 "build-recheck: attempt $record_attempt at $unit_id was stopped by $outside, which is not one of the three tool rows or interface-record. A re-check answers only an attempt those rows alone stopped; the route is build."

  # --- exit 88, four: a path the interface check named is not in the code at the recorded commit.
  # An amended record can name a path the code never had, and the check would pass on words
  # alone. The paths are the declaration's backticked tokens the recorded interface record left
  # out, read as paths by `ifacePath` ---------------------------------------------------------
  local unit_interface_declared missing_paths="" named_path
  unit_interface_declared="$(printf '%s' "$RV_UNIT_JSON" | jq -r '.interface // ""')"
  while IFS= read -r named_path; do
    [ -n "$named_path" ] || continue
    git -C "$codepath" cat-file -e "$record_commit:$named_path" 2>/dev/null \
      || missing_paths="${missing_paths:+$missing_paths, }$named_path"
  done <<EOF_PATHS
$(jq -rn --arg d "$unit_interface_declared" --arg r "$(printf '%s' "$RV_BUILD_DOC" | jq -r '.interfaceRecord // ""')" "$IFACE_PATH_JQ"'
  [ $d | scan("`[^`]+`") | ltrimstr("`") | rtrimstr("`") | select(. as $t | $r | contains($t) | not) | ifacePath ]
  | unique | .[]')
EOF_PATHS
  [ -z "$missing_paths" ] \
    || die 88 "build-recheck: the interface check at $unit_id named $missing_paths, and no such path exists at $record_commit. Amending the record cannot make a path real; the route is build, or a design change."

  local tests_file="$IMPL_DIR/tests-$unit_id.json" tests_doc
  [ -f "$tests_file" ] \
    || die 3 "build-recheck: $tests_file not found, though a build record implies tests-freeze already ran for $unit_id."
  tests_doc="$(jq -c '.' "$tests_file" 2>/dev/null)"
  [ -n "$tests_doc" ] \
    || die 3 "build-recheck: $tests_file exists but could not be read as JSON. Repair or remove it by hand before running this again."

  br_require_clean_tree "build-recheck" "$codepath" "$unit_id" "$RV_RUN_MODE" "$RV_LEDGER_FILE" "$RV_LEDGER_DOC" "$RV_RANGE_PATHS"

  br_interface_path "build-recheck" "$unit_id" "$interface_path"
  br_interface_text "build-recheck" "$unit_id" "$unit_interface_declared"

  # --- the eight deciding checks, the same half build-record runs, over the recorded range --------
  BRC_WHO="build-recheck"
  BRC_CODEPATH="$codepath"
  BRC_SCOPE="$RV_RANGE_SCOPE"
  BRC_STARTED_AT="$record_started_at"
  BRC_CURRENT="$record_commit"
  BRC_UNIT_JSON="$RV_UNIT_JSON"
  BRC_TESTS_DOC="$tests_doc"
  BRC_BASELINE_FILE="$IMPL_DIR/baseline.json"
  CR_TEST_RECIPES="$test_recipes"
  CR_CHECK_RECIPES="$check_recipes"
  BRC_VALUES="$values"
  BRC_NOTHING_RAN="$nothing_ran"
  BRC_HAVE_NOTHING_RAN="$have_nothing_ran"
  BRC_GATE_RECIPES="$gate_recipes"
  # The observed record the build step accepted, at the path it names (live-run row 104).
  BRC_OBSERVED="$IMPL_DIR/observed-$unit_id.json"
  br_eight_checks "$unit_interface_declared" "$BR_INTERFACE_TEXT"

  # The record keeps the attempt, its range and its date, and takes the new checks and the interface
  # record's text as read now. When that text changed, the attempt's own text stays under
  # interfaceRecordBefore, so review reads both. The checks it
  # replaces stay under checksBefore, id and verdict only, so a reader can see what the re-check
  # answered differently. Both check sets carry whole tool outputs, so both are read from a file.
  local today record_json
  today="$(date -u +%Y-%m-%d)"
  record_json="$(jq -c --arg recheckedAt "$today" --argjson executed "$BR_EXECUTED" \
    --arg interfaceRecord "$BR_INTERFACE_TEXT" --slurpfile before "$record_file" '
    . as $new
    | $before[0]
    | .checksBefore = ((.checks // []) | map({id, verdict}))
    | .checks = $new
    | (if $interfaceRecord != (.interfaceRecord // "")
       then .interfaceRecordBefore = (.interfaceRecordBefore // .interfaceRecord // "") else . end)
    | .interfaceRecord = $interfaceRecord
    | .executed = $executed
    | .decidingChecks = { total: 8, ranHere: [ $new[] | .id ] }
    | .recheckedAt = $recheckedAt' "$BR_CHECKS_FILE")"
  rm -f "$BR_CHECKS_FILE"
  [ -n "$record_json" ] || die 3 "build-recheck: could not assemble the record for $unit_id."
  write_atomic "$record_file" "$record_json"

  # No attempt is spent: nobody worked. The step moves to checks-passed when the checks pass, and
  # stays at code-written otherwise, with no halt, because the counter did not move.
  local all_met first_stopper new_ledger_doc
  all_met="$(br_checks_pass "$BR_CHECKS_JSON" "interface-record")"
  first_stopper="$(br_first_stopper "$BR_CHECKS_JSON" "interface-record")"
  new_ledger_doc="$RV_LEDGER_DOC"
  if [ "$all_met" = "true" ]; then
    new_ledger_doc="$(printf '%s' "$RV_LEDGER_DOC" | jq -c --arg id "$unit_id" \
      '.orders = (.orders | map(if .id == $id then .lastStep = "checks-passed" else . end))')"
    [ -n "$new_ledger_doc" ] || die 3 "build-recheck: the ledger update for $unit_id failed."
    write_atomic "$RV_LEDGER_FILE" "$new_ledger_doc"
  fi

  local br_state br_next attempts_allowed
  attempts_allowed="$(attempts_allowed_for "$RV_ORDER_ENTRY")"
  if [ "$all_met" = "true" ]; then br_state="checks-passed"; else br_state="code-written, stopped by $first_stopper"; fi
  br_next="$(im_next_step "$new_ledger_doc" "$SNAPSHOT_DOC" "$IMPL_DIR" "true" "false")"
  im_print_summary "build-recheck" "$(printf '%s' "$record_json" | jq -c \
    --arg attempts "$record_attempt of $attempts_allowed" --arg state "$br_state" \
    --arg record "$record_file" --arg next "$br_next" '
    {order: .unit,
     attempt: $attempts,
     recheck: "attempt \(.attempt), checks replaced",
     range: "\(.startedAt)..\(.commit)",
     check: ([ .checks[] | {id, verdict, detail: (.detail // "")} ]),
     executed: "\(.executed) of 8 ran a command, a diff or a hash",
     state: $state,
     halt: "none",
     record: $record,
     next: $next}')"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# Step five: review, fix, verify, close (ideal/implementation.md, "What a review is given, and what
# it is refused" through "The loop stops on a counter").
#
# Six actions share one shape. Each reads the ledger first, refuses when the order is at a step it
# cannot follow (exit 48) or is halted (exit 49), and only then opens anything else. The helpers
# below hold that shared half, so the six cannot drift into reading the same state six ways.
# ------------------------------------------------------------------------------------------------

# The state every step-five action reads before it acts. Sets five globals: RV_LEDGER_FILE,
# RV_LEDGER_DOC, RV_ORDER_ENTRY, RV_RUN_MODE and RV_UNIT_JSON, plus SNAPSHOT_DOC through
# tt_load_snapshot's own reader. $1 the action's own name, $2 the unit id.
#
# A task with neither a ledger nor a snapshot never started, which is exit 20, the same fact
# `preconditions` already names with that number. A ledger with no snapshot beside it is an
# internal state this script's own logic rules out, which is exit 3.
RV_LEDGER_FILE=""; RV_LEDGER_DOC=""; RV_ORDER_ENTRY=""; RV_RUN_MODE=""; RV_UNIT_JSON=""
rv_load_state() {
  local who="$1" unit_id="$2"
  require_started_build "$who"
  RV_LEDGER_FILE="$STARTED_LEDGER_FILE"
  RV_LEDGER_DOC="$STARTED_LEDGER_DOC"

  RV_UNIT_JSON="$(printf '%s' "$SNAPSHOT_DOC" | jq -c --arg id "$unit_id" \
    '(.workOrders // []) | map(select(.id == $id)) | .[0] // null')"
  [ "$RV_UNIT_JSON" != "null" ] || die 22 "$who: $unit_id is not in the frozen copy."

  RV_ORDER_ENTRY="$(printf '%s' "$RV_LEDGER_DOC" | jq -c --arg id "$unit_id" \
    '(.orders // []) | map(select(.id == $id)) | .[0] // null')"
  [ "$RV_ORDER_ENTRY" != "null" ] \
    || die 3 "$who: $unit_id has no entry in $RV_LEDGER_FILE, though start opens one entry per snapshot work order."

  # The task's own mode for this stage, the producer clear-halt reads, not the ledger's copy from
  # start. With two sources, a person who set the task interactive cleared a halt and was then
  # refused a ruling as unattended (gap row 265).
  RV_RUN_MODE="$(task_run_mode "$TASK_PATH" implement)"
  FIX_ROUNDS_ALLOWED="$(order_fix_rounds_allowed "$RV_ORDER_ENTRY")"

  # Exit 49: a halted order refuses every step after the halt. The reason is the halt's own words,
  # so a reader never has to open the ledger to learn why the step stopped. $3, when given, is a
  # JSON array of the fronts of the halt segments the caller answers itself, so only the other
  # segments refuse.
  local halted
  halted="$(printf '%s' "$RV_ORDER_ENTRY" | jq -r '.haltedBecause // ""')"
  [ -z "${3:-}" ] || halted="$(halt_segments_matching "$halted" "$3" drop)"
  [ -z "$halted" ] \
    || die 49 "$who: $unit_id is halted, so this step refuses. The ledger records the reason: $halted"
}

# The repository an order's range lives in, and the paths a tree check reads there. An order whose
# proof is record lands its deliverable in the project folder, so its commits are the project
# folder's, and every range, HEAD, diff and tree read for it goes there; the tree check reads its
# owned files alone, because the running stage keeps the rest of that folder dirty on purpose
# (nyc defect 17). Its diffs read the project folder whole, because the deliverable may sit
# outside the task folder (live-run row 127). AIDA's own actions commit that folder in the same
# range. A task note commits tasks/ whole; another task's stage close commits its folder. None of
# that is the implementer's, and br_aida_writes_in_project sets each aside. Every other order
# reads the code worktree whole. Call after rv_load_codepath.
# $1 the action's own name, $2 the frozen work order. Sets RV_RANGE_REPO, RV_RANGE_PATHS (one
# pathspec per line, empty for the whole tree) and RV_RANGE_NAME, the words a message uses.
# Also RV_RANGE_SCOPE, the one path every diff is scoped to, empty for the whole tree.
RV_RANGE_REPO=""; RV_RANGE_PATHS=""; RV_RANGE_SCOPE=""; RV_RANGE_NAME=""
rv_load_range_repo() {
  local who="$1" unit_json="$2"
  RV_RANGE_REPO="$RV_CODEPATH"; RV_RANGE_PATHS=""; RV_RANGE_SCOPE=""; RV_RANGE_NAME="the code repository"
  br_order_facts "$unit_json"
  [ "$BR_ORDER_RANGE" = "project" ] || return 0
  is_git_repo "$RV_PROJECT_FOLDER" \
    || die 87 "$who: $(printf '%s' "$unit_json" | jq -r '.id') is proved by its record, so its range lives in the project folder, and $RV_PROJECT_FOLDER is not a git repository. Run git init there and commit it."
  RV_RANGE_REPO="$RV_PROJECT_FOLDER"
  RV_RANGE_PATHS="$(printf '%s' "$unit_json" | jq -r '(.ownedFiles // [])[]')"
  RV_RANGE_SCOPE="$RV_PROJECT_FOLDER"
  RV_RANGE_NAME="the project folder"
}

# Where an order's range starts, for review-brief and close (gap row 222). The build record keeps
# the last attempt only, so its startedAt drops every earlier attempt. In the code repository the
# start is the freeze record's commit, HEAD when the tests froze: `restart` and `retake-tests`
# move the records aside, so the next freeze starts a new range. A record order keeps the build
# record's startedAt, because AIDA's own writes land in the project folder between its attempts.
# $1 the action's own name, $2 the unit id. Call after rv_load_build_record and
# rv_load_range_repo. Sets RV_ORDER_START.
RV_ORDER_START=""
rv_load_order_start() {
  local who="$1" unit_id="$2"
  if [ -n "$RV_RANGE_SCOPE" ]; then
    RV_ORDER_START="$(printf '%s' "$RV_BUILD_DOC" | jq -r '.startedAt // ""')"
  else
    RV_ORDER_START="$(jq -r '.commit // ""' "$IMPL_DIR/tests-$unit_id.json" 2>/dev/null)"
  fi
  [ -n "$RV_ORDER_START" ] \
    || die 3 "$who: the start of $unit_id's range could not be read from its freeze record or its build record, though both steps write it."
}

# How order $2 owns path $1: "own" when the path matches an entry of its ownedFiles it does not
# share, "shared" when it matches only entries of its sharedFiles, nothing when it matches none.
# Another order owns a shared file too, so a path alone never attributes a change to this order.
im_path_claim() {
  local g claim=""
  while IFS= read -r g; do
    [ -n "$g" ] && tf_path_matches_catalog_glob "$1" "$g" || continue
    if printf '%s' "$2" | jq -e --arg g "$g" '(.sharedFiles // []) | index($g) != null' >/dev/null 2>&1; then
      claim=shared
    else
      echo own; return 0
    fi
  done <<IPC_OWNED
$(printf '%s' "$2" | jq -r '(.ownedFiles // [])[]')
IPC_OWNED
  [ -z "$claim" ] || echo "$claim"
}

# The commits a build or fix record of an order other than $2 names, in the repository $1, one per
# line. Every folder under the task folder such a record can sit in is read: the implementation
# folder, its retake folders, and the folders a restart wrote.
im_taken_commits() {
  local f r
  find "$TASK_PATH" -mindepth 2 -maxdepth 3 -type f \( -name 'build-wo*.json' -o -name 'fix-wo*-*.json' \) 2>/dev/null \
    | while IFS= read -r f; do
        case "$(basename "$f")" in "build-$2.json"|"fix-$2-"*) continue ;; esac
        r="$(jq -r 'select(.startedAt != null and .commit != null) | .startedAt + ".." + .commit' "$f" 2>/dev/null)"
        [ -z "$r" ] || git -C "$1" rev-list "$r" 2>/dev/null
      done
}

# Whose commit $3 is, from the paths it changes ($1, one per line) and the frozen work order $2.
# Prints "own" when every path is the order's, "none" when no path is, and "mixed" followed by the
# paths the order does not own otherwise. A path the order shares counts as the order's unless a
# build or fix record of another order holds the commit: $4, as im_taken_commits prints it. So a
# builder's attempt on a shared file is found even when no record names it (gap row 287).
im_commit_claim() {
  local p own_n=0 outside=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$(im_path_claim "$p" "$2")" in
      own) own_n=$((own_n + 1)) ;;
      shared) printf '%s\n' "$4" | grep -Fqx -- "$3" || own_n=$((own_n + 1)) ;;
      *) outside="$outside $p" ;;
    esac
  done <<ICC_PATHS
$1
ICC_PATHS
  if [ "$own_n" -eq 0 ]; then echo none
  elif [ -n "$outside" ]; then echo "mixed$outside"
  else echo own; fi
}

# The commits after $2 up to $3 in the repository $1, oldest first, one line each: "own <sha>" when
# the commit is order $4's, "other <sha>" when it is not. A commit is the order's when a range one
# of its records names holds it: the build record's, or a fix round's. Or when im_commit_claim
# reads it as the order's, which is how an earlier attempt is found. Another order's freeze or
# build changes a file this order does not own, so it reads as other.
# $4 the frozen work order, $5 the folder holding the order's build and fix records.
im_order_commits() {
  local repo="$1" from="$2" to="$3" unit_json="$4" dir="$5" id recorded="" taken f r c paths
  id="$(printf '%s' "$unit_json" | jq -r '.id // ""')"
  taken="$(im_taken_commits "$repo" "$id")"
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    r="$(jq -r 'select(.startedAt != null and .commit != null) | .startedAt + ".." + .commit' "$f" 2>/dev/null)"
    [ -z "$r" ] || recorded="$recorded$(git -C "$repo" rev-list "$r" 2>/dev/null)
"
  done <<IOC_RECORDS
$dir/build-$id.json
$(find "$dir" -mindepth 1 -maxdepth 1 -name "fix-$id-*.json" 2>/dev/null | sort)
IOC_RECORDS
  for c in $(git -C "$repo" rev-list --reverse "$from..$to" 2>/dev/null); do
    if printf '%s' "$recorded" | grep -Fqx "$c"; then echo "own $c"; continue; fi
    paths="$(git -C "$repo" diff-tree --no-commit-id --name-only -r --no-renames "$c" 2>/dev/null)"
    if [ "$(im_commit_claim "$paths" "$unit_json" "$c" "$taken")" = "own" ]; then echo "own $c"; else echo "other $c"; fi
  done
}

# Exit 48: the order must be at one of the steps this action can follow. $1 the action's own name,
# $2 the unit id, $3 the allowed steps, separated by spaces.
rv_require_step() {
  local who="$1" unit_id="$2" allowed="$3" found
  found="$(printf '%s' "$RV_ORDER_ENTRY" | jq -r '.lastStep // "not started"')"
  case " $allowed " in
    *" $found "*) return 0 ;;
  esac
  die 48 "$who: $unit_id is at step $found, and this step follows one of: $allowed."
}

# The build record for this order. $1 the action's own name, $2 the unit id. Sets RV_BUILD_DOC.
RV_BUILD_DOC=""
rv_load_build_record() {
  local who="$1" unit_id="$2" build_file
  build_file="$IMPL_DIR/build-$unit_id.json"
  [ -f "$build_file" ] \
    || die 3 "$who: $build_file not found, though the ledger records $unit_id past the build. Run build-record on it again."
  RV_BUILD_DOC="$(jq -c '.' "$build_file" 2>/dev/null)"
  [ -n "$RV_BUILD_DOC" ] \
    || die 3 "$who: $build_file exists but could not be read as JSON. Repair or remove it by hand before running this again."
}

# The review record for this order. $1 the action's own name, $2 the unit id. Sets RV_REVIEW_FILE
# and RV_REVIEW_DOC.
RV_REVIEW_FILE=""; RV_REVIEW_DOC=""
rv_load_review_record() {
  local who="$1" unit_id="$2"
  RV_REVIEW_FILE="$IMPL_DIR/review-$unit_id.json"
  [ -f "$RV_REVIEW_FILE" ] \
    || die 3 "$who: $RV_REVIEW_FILE not found, though the ledger records $unit_id as reviewed. Run review-record on it again."
  RV_REVIEW_DOC="$(jq -c '.' "$RV_REVIEW_FILE" 2>/dev/null)"
  [ -n "$RV_REVIEW_DOC" ] \
    || die 3 "$who: $RV_REVIEW_FILE exists but could not be read as JSON. Repair or remove it by hand before running this again."
}

# The frozen test paths for this order, one per line, from the frozen test record. $1 the unit id.
rv_frozen_test_paths_json() {
  local unit_id="$1" tests_file tests_doc
  tests_file="$IMPL_DIR/tests-$unit_id.json"
  [ -f "$tests_file" ] || { printf '[]'; return 0; }
  tests_doc="$(jq -c '.' "$tests_file" 2>/dev/null)"
  [ -n "$tests_doc" ] || { printf '[]'; return 0; }
  printf '%s' "$tests_doc" | jq -c \
    '[ (.rows // [])[] | select(.kind == "machine") | (.tests // [])[] | .path ] | unique'
}

# Prints the paths of scope list $1, a JSON array, that lie outside owned list $2, one per line,
# each as the reviewer wrote it. A path is resolved against codePath $3 and compared the way the
# owned-files check compares a diff path, through tf_path_matches_catalog_glob. A path under the
# task folder $4 is never outside: the report and the records live there (live-run row 116).
rv_scope_outside() {
  local scope_json="$1" owned_json="$2" codepath="$3" task_path="$4"
  local count owned_count i gi p abs g matched
  count="$(printf '%s' "$scope_json" | jq 'length')"
  owned_count="$(printf '%s' "$owned_json" | jq 'length')"
  i=0
  while [ "$i" -lt "$count" ]; do
    p="$(printf '%s' "$scope_json" | jq -r --argjson i "$i" '.[$i]')"
    i=$((i + 1))
    [ -n "$p" ] || continue
    abs="$(normalize_abs "$(resolve_against "$p" "$codepath")")"
    is_under "$abs" "$task_path" && continue
    is_under "$abs" "$codepath" && abs="${abs#"$codepath"/}"
    matched=false
    gi=0
    while [ "$gi" -lt "$owned_count" ]; do
      g="$(printf '%s' "$owned_json" | jq -r --argjson gi "$gi" '.[$gi]')"
      tf_path_matches_catalog_glob "$abs" "$g" && matched=true
      [ "$matched" = "true" ] && break
      gi=$((gi + 1))
    done
    [ "$matched" = "true" ] || printf '%s\n' "$p"
  done
}

# How many findings in review record $1 are open and actionable. A finding recorded with
# actionable false is open and stays open: nothing can close it, because no fixer ever sees it
# (ideal/implementation.md, "Every finding cites a criterion or a non-goal"). It never blocks a
# close either, which is why every count that gates a step counts the actionable ones only.
rv_open_actionable_count() {
  printf '%s' "$1" | jq '[ (.findings // [])[] | select(.actionable == true and .status == "open") ] | length'
}

# Decision 10, the whole of it. $1 the finding's own linkedTo value, $2 the frozen contract. Sets
# RV_ACTIONABLE and RV_ACTIONABLE_BECAUSE. One criterion id or one non-goal id makes the finding
# actionable. Anything else is recorded and never reaches a fixer.
RV_ACTIONABLE="false"; RV_ACTIONABLE_BECAUSE=""
rv_actionable_for() {
  local linked="$1" alignment="$2" hit
  if [ -z "$linked" ]; then
    RV_ACTIONABLE="false"
    RV_ACTIONABLE_BECAUSE="the finding cites no criterion and no non-goal, so nothing can act on it"
    return 0
  fi
  hit="$(printf '%s' "$alignment" | jq -r --arg l "$linked" \
    'if ((.criteria // []) | map(.id) | index($l)) != null then "criterion"
     elif ((.nonGoals // []) | map(.id) | index($l)) != null then "non-goal"
     else "" end')"
  case "$hit" in
    criterion)
      RV_ACTIONABLE="true"
      RV_ACTIONABLE_BECAUSE="the finding cites criterion $linked, which the frozen contract holds" ;;
    non-goal)
      RV_ACTIONABLE="true"
      RV_ACTIONABLE_BECAUSE="the finding cites non-goal $linked, which the frozen contract holds" ;;
    *)
      RV_ACTIONABLE="false"
      RV_ACTIONABLE_BECAUSE="the finding cites $linked, which is neither a criterion nor a non-goal in the frozen contract" ;;
  esac
}

# Turns one raw entry from a findings file into the record shape, deciding its own actionability
# against the frozen contract. $1 the raw entry, $2 the frozen contract, $3 where it came from,
# "review", "round<N>", "repair" or "check".
rv_finding_record() {
  local raw="$1" alignment="$2" origin="$3" linked
  linked="$(printf '%s' "$raw" | jq -r '.linkedTo // ""')"
  rv_actionable_for "$linked" "$alignment"
  printf '%s' "$raw" | jq -c --argjson actionable "$RV_ACTIONABLE" \
    --arg because "$RV_ACTIONABLE_BECAUSE" --arg origin "$origin" '
    {
      id: .id,
      severity: .severity,
      file: (.file // ""),
      lines: (.lines // ""),
      linkedTo: (.linkedTo // ""),
      evidence: .evidence,
      fixScope: (.fixScope // []),
      actionable: $actionable,
      actionableBecause: $because,
      status: "open",
      origin: $origin
    }'
}

# Sets RV_INFORMATION_ARRAY to the `information` list of the findings file $1, checked item by
# item, or to [] when the file has no such key. $2 the action's own name. An item is
# {id, summary, file, lines, departsFromDesign}: information for the person that is not a finding,
# so it carries no severity and no fix scope (live-run row 103). departsFromDesign is the
# reviewer's one routed answer: true sends the order back to design (gap row 224). Dies (exit 52,
# the findings shape's own code) on a list that is not an array, an item that is not an object, an
# empty id or summary, a departsFromDesign that is not a boolean, or an id used twice. Called as a plain statement, never with `$(...)`, for the reason rv_read_findings_array
# states. The file's JSON and its duplicate keys were already checked by that reader.
RV_INFORMATION_ARRAY="[]"
rv_read_information_array() {
  local file="$1" who="$2" arr count i one id summary seen_ids=""
  arr="$(jq -c 'if has("information") then .information else [] end' "$file" 2>/dev/null)"
  [ "$(printf '%s' "$arr" | jq -r 'type' 2>/dev/null)" = "array" ] \
    || die 52 "$who: $file holds an information key that is not an array. The shape is { \"findings\": [ ... ], \"information\": [ { \"id\", \"summary\", \"file\", \"lines\", \"departsFromDesign\" } ] }."
  count="$(printf '%s' "$arr" | jq 'length')"
  i=0
  while [ "$i" -lt "$count" ]; do
    one="$(printf '%s' "$arr" | jq -c --argjson i "$i" '.[$i]')"
    [ "$(printf '%s' "$one" | jq -r 'type')" = "object" ] \
      || die 52 "$who: entry $i of information in $file is not an object."
    id="$(printf '%s' "$one" | jq -r '.id // "" | tostring')"
    [ -n "$id" ] || die 52 "$who: entry $i of information in $file has no id."
    summary="$(printf '%s' "$one" | jq -r '.summary // "" | tostring')"
    [ -n "$summary" ] \
      || die 52 "$who: information $id in $file has no summary. One sentence saying what the person needs to know."
    [ "$(printf '%s' "$one" | jq -r '.departsFromDesign | type')" = "boolean" ] \
      || die 52 "$who: information $id in $file has no departsFromDesign boolean. It is true when the item names a departure from the order's design or interface, false otherwise."
    case " $seen_ids " in
      *" $id "*) die 52 "$who: $file names the information item $id more than once. Each item carries its own id." ;;
    esac
    seen_ids="$seen_ids $id"
    i=$((i + 1))
  done
  RV_INFORMATION_ARRAY="$(printf '%s' "$arr" | jq -c \
    '[ .[] | {id: (.id | tostring), summary: (.summary | tostring),
              file: ((.file // "") | tostring), lines: ((.lines // "") | tostring),
              departsFromDesign} ]')"
}

# The recipes the reviewer answers for, one per line, each once (gap row 225): the implement
# recipe preconditions.json holds for each framework. The builder follows its rules and the
# reviewer is given no other copy. No per-rule list exists, so the unit is a whole recipe. The
# order's `verify` sources stay out: the reviewer judges each entry already. Reads IMPL_DIR.
# review-brief hands the list over, and review-record checks the reviewer's answers against it.
rv_recipe_refs() {
  [ -f "$IMPL_DIR/preconditions.json" ] || return 0
  jq -r '[ (.frameworks // [])[] | .implementRecipePath // empty ] | unique | .[]' \
    "$IMPL_DIR/preconditions.json" 2>/dev/null
}

# Sets RV_RECIPE_ANSWERS to the reviewer's `recipes` list in the findings file $1, or to [] when
# the file has none. $2 the action's own name. An answer is {ref, verdict, evidence}: the verdict
# is followed, departed or not-applicable, and the evidence gives the reason on one line. A
# departure's evidence names a file in the order's diff, $3, with or without a line. A departure in
# how files were produced has no one line (gap row 280). A departed answer may name, under
# `finding`, the finding whose fix cures it; review-record checks it (gap row 303). Sets
# RV_RECIPE_NAMED to {ref: [the diff files its departed evidence names]}, for that check. Dies 52 on a malformed
# answer, and 108 when an item of rv_recipe_refs has no answer, or an answer names a ref twice or a
# ref not on that list. Called as a plain statement, never with `$(...)`, for the reason
# rv_read_findings_array states. $4 the order's test globs, one per line, given only when the task
# has no automated tests and the order froze no test file. Then the recipe's rules on frozen tests
# do not apply, so a departure that names only test files is recorded not-applicable, and the
# answer keeps the reviewer's words as departedAnswer (gap row 300). A glob with no "/" matches a
# file name anywhere in the tree, as pytest's patterns do.
RV_RECIPE_ANSWERS="[]"
RV_RECIPE_NAMED="{}"
RR_REDISPATCH="Run review-brief again for this order, then dispatch the reviewer again."
rv_read_recipe_answers() {
  local file="$1" who="$2" diff="$3" test_globs="${4:-}" refs arr count i one ref verdict evidence seen="" diff_paths p in_diff
  local named_tests only_tests is_test g sfx named_files
  RV_RECIPE_NAMED="{}"
  refs="$(rv_recipe_refs)"
  diff_paths=""
  [ ! -f "$diff" ] || diff_paths="$(sed -n 's#^+++ b/##p; s#^--- a/##p' "$diff" | LC_ALL=C sort -u)"
  arr="$(jq -c 'if has("recipes") then .recipes else [] end' "$file" 2>/dev/null)"
  [ "$(printf '%s' "$arr" | jq -r 'type' 2>/dev/null)" = "array" ] \
    || die 52 "$who: $file holds a recipes key that is not an array. The shape is { \"recipes\": [ { \"ref\", \"verdict\", \"evidence\" } ] }."
  count="$(printf '%s' "$arr" | jq 'length')"
  i=0
  while [ "$i" -lt "$count" ]; do
    one="$(printf '%s' "$arr" | jq -c --argjson i "$i" '.[$i]')"
    [ "$(printf '%s' "$one" | jq -r 'type')" = "object" ] \
      || die 52 "$who: entry $i of recipes in $file is not an object."
    ref="$(printf '%s' "$one" | jq -r '.ref // "" | tostring')"
    verdict="$(printf '%s' "$one" | jq -r '.verdict // "" | tostring')"
    evidence="$(printf '%s' "$one" | jq -r '.evidence // "" | tostring')"
    [ -n "$ref" ] || die 52 "$who: entry $i of recipes in $file has no ref."
    case "$verdict" in
      followed|departed|not-applicable) ;;
      *) die 52 "$who: the recipes answer for $ref in $file has the verdict '$verdict'. It is followed, departed or not-applicable." ;;
    esac
    [ -n "$evidence" ] \
      || die 52 "$who: the recipes answer for $ref in $file has no evidence. A not-applicable answer gives its reason there."
    case "$evidence" in
      *"
"*) die 52 "$who: the recipes answer for $ref in $file holds a line break in its evidence. The evidence is one line." ;;
    esac
    if [ "$verdict" = "departed" ]; then
      in_diff=no
      only_tests=yes
      [ -n "$test_globs" ] || only_tests=no
      named_tests=""
      named_files=""
      while IFS= read -r p; do
        [ -n "$p" ] || continue
        is_test="$(printf '%s\n' "$test_globs" | while IFS= read -r g; do
            case "$g" in
              "") continue ;;
              */*) tf_path_matches_catalog_glob "$p" "$g" ;;
              *) tf_path_matches_glob "${p##*/}" "$g" ;;
            esac && { printf 'yes'; break; }
          done)"
        case " $evidence " in
          *[!A-Za-z0-9_./-]"$p"[!A-Za-z0-9_./-]*|*[!A-Za-z0-9_./-]"$p".[!A-Za-z0-9_./-]*)
            in_diff=yes
            named_files="$named_files$p
"
            [ "$is_test" != "yes" ] || named_tests="$named_tests, $p" ;;
        esac
        # Any other file the evidence names, by its path, a path suffix or its bare name, keeps the
        # departure, because only the rules on frozen tests stop applying.
        if [ "$is_test" != "yes" ]; then
          sfx="$p"
          while :; do
            case " $evidence " in
              *[!A-Za-z0-9_./-]"$sfx"[!A-Za-z0-9_./-]*|*[!A-Za-z0-9_./-]"$sfx".[!A-Za-z0-9_./-]*) only_tests=no; break ;;
            esac
            case "$sfx" in */*) sfx="${sfx#*/}" ;; *) break ;; esac
          done
        fi
      done <<RR_DIFF
$diff_paths
RR_DIFF
      [ "$in_diff" = "yes" ] \
        || die 52 "$who: the recipes answer for $ref in $file is departed, and its evidence names no file in $diff. Name the file and the line where the build departs, or the files that a departure in how files were produced made or changed. The recipe's own line is not enough, and neither is a line of the diff itself. The accepted form is <path>:<line>, with the path as the diff names it, for example $(printf '%s\n' "$diff_paths" | grep -v -x -e '' -e /dev/null | head -n 1):<line>."
      halt_refuse_separator "$who" "the recipes answer for $ref" "$evidence"
      RV_RECIPE_NAMED="$(printf '%s' "$RV_RECIPE_NAMED" | jq -c --arg r "$ref" --arg f "$named_files" '.[$r] = ($f | split("\n") | map(select(. != "")))')"
      if [ "$only_tests" = "yes" ] && [ -n "$named_tests" ]; then
        arr="$(printf '%s' "$arr" | jq -c --argjson i "$i" \
          --arg why "the task has no automated tests and this order froze no test file, so the recipe's rules on frozen tests do not apply to ${named_tests#, }" \
          '.[$i].departedAnswer = .[$i].evidence | .[$i].verdict = "not-applicable" | .[$i].evidence = $why | del(.[$i].finding)')"
      fi
    fi
    printf '%s\n' "$refs" | grep -Fxq -- "$ref" \
      || die 108 "$who: $file answers for $ref, which is not a recipe this order carries. The review brief's recipes list is the whole list. $RR_REDISPATCH"
    printf '%s\n' "$seen" | grep -Fxq -- "$ref" \
      && die 108 "$who: $file answers for $ref more than once. Each recipe gets one answer. $RR_REDISPATCH"
    seen="$seen
$ref"
    i=$((i + 1))
  done
  while IFS= read -r ref; do
    [ -z "$ref" ] || printf '%s\n' "$seen" | grep -Fxq -- "$ref" \
      || die 108 "$who: $file gives no answer for $ref, a recipe this order carries. Each item of the review brief's recipes list gets one answer: followed, departed or not-applicable. $RR_REDISPATCH"
  done <<RR_REFS
$refs
RR_REFS
  RV_RECIPE_ANSWERS="$(printf '%s' "$arr" | jq -c '[ .[] | {ref: (.ref | tostring), verdict, evidence: (.evidence | tostring)}
    + (if has("departedAnswer") then {departedAnswer} else {} end)
    + (if has("finding") then {finding: (.finding | tostring)} else {} end) ]')"
}

# Every non-goal the given finding list cites, as a printable list. Empty when none does.
rv_nongoal_hits() {
  local findings="$1" alignment="$2"
  printf '%s' "$findings" | jq -r --argjson a "$alignment" '
    [ .[] | . as $f | ($a.nonGoals // [])[] | select(.id == $f.linkedTo)
      | "\($f.id) cites non-goal \(.id): \(.text)" ] | join("; ")'
}

# Exit 62. A round is verified before the next one starts. `verify-record` is what turns a fixer's
# account of what it did into a verdict this stage holds, so two rounds spent back to back mean the
# first round's findings were never judged by anything. `close` catches it afterwards (exit 60), by
# which point both rounds are gone and every open finding needs a ruling. This catches it at the
# moment it would happen. $1 the action's own name, $2 the unit id, $3 roundsUsed.
rv_require_round_verified() {
  local who="$1" unit_id="$2" rounds_used="$3" verified
  [ "$rounds_used" -gt 0 ] 2>/dev/null || return 0
  verified="$(printf '%s' "$RV_REVIEW_DOC" | jq -r '[ (.rounds // [])[] | .round ] | max // 0')"
  [ "$verified" = "$rounds_used" ] && return 0
  die 62 "$who: $unit_id has used $rounds_used fix round(s) and the last one verified is $verified. Run verify-record on round $rounds_used before another one starts."
}

# ------------------------------------------------------------------------------------------------
# review-brief: everything a reviewer may see, and nothing else.
# ------------------------------------------------------------------------------------------------

do_review_brief() {
  [ "$#" -ge 2 ] || die 3 "review-brief: a task folder and a unit id are required"
  [ "$#" -le 2 ] || die 3 "review-brief: unrecognized extra argument: $3"
  local unit_id="$2" resolve_rc
  TASK_PATH="$(resolve_task_folder "$1" "review-brief")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  IMPL_DIR="$TASK_PATH/implementation"

  rv_load_state "review-brief" "$unit_id"

  # Exit 50: one review per order, ever. A second pass is where a loop that cannot end comes from
  # (ideal/implementation.md, "One review per order"). Asked before the step check, so an order
  # already past its review is told that fact rather than told it is at the wrong step: the second
  # message is true and sends a reader to the wrong repair.
  local review_file="$IMPL_DIR/review-$unit_id.json"
  [ -f "$review_file" ] \
    && die 50 "review-brief: $review_file already exists, so $unit_id has been reviewed. One order gets one review, ever."
  rv_require_step "review-brief" "$unit_id" "checks-passed"

  rv_load_build_record "review-brief" "$unit_id"
  rv_load_codepath "review-brief"
  rv_load_range_repo "review-brief" "$RV_UNIT_JSON"

  # The diff moves as a file the reviewer opens, never pasted through the orchestrator
  # (ideal/implementation.md, "What a review is given, and what it is refused"). For an order
  # whose proof is record it is the task folder's diff in the project folder, and the brief names
  # the deliverables by path, since a document is read whole and not as a patch (nyc defect 17).
  # In the code repository the diff runs over every attempt, and holds only the files this order's
  # own commits changed, so another order built between two attempts stays out (gap row 222).
  # A file this order shares is diffed per own commit instead, so another order's lines in it stay
  # out too (gap row 287).
  local started_at commit diff_path deliverables_json own_commits own_paths shared_paths="" c
  rv_load_order_start "review-brief" "$unit_id"
  started_at="$RV_ORDER_START"
  commit="$(printf '%s' "$RV_BUILD_DOC" | jq -r '.commit // ""')"
  [ -n "$commit" ] \
    || die 3 "review-brief: $IMPL_DIR/build-$unit_id.json holds no commit, though build-record writes it."
  diff_path="$IMPL_DIR/diff-$unit_id.patch"
  deliverables_json="[]"
  if [ -n "$RV_RANGE_SCOPE" ]; then
    git_diff_of "$RV_RANGE_REPO" "$started_at" "$commit" "$RV_RANGE_SCOPE" > "$diff_path" \
      || die 3 "review-brief: could not write the diff from $started_at to $commit into $diff_path."
  else
    own_commits="$(im_order_commits "$RV_RANGE_REPO" "$started_at" "$commit" "$RV_UNIT_JSON" "$IMPL_DIR" \
      | sed -n 's/^own //p')"
    own_paths="$(printf '%s\n' "$own_commits" | while IFS= read -r c; do
          [ -z "$c" ] || git -C "$RV_RANGE_REPO" diff-tree --no-commit-id --name-only -r --no-renames "$c"
        done | LC_ALL=C sort -u)"
    set --
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      if [ "$(im_path_claim "$p" "$RV_UNIT_JSON")" = "shared" ]; then shared_paths="$shared_paths$p
"; else set -- "$@" "$p"; fi
    done <<RB_PATHS
$own_paths
RB_PATHS
    : > "$diff_path" || die 3 "review-brief: could not write $diff_path."
    if [ "$#" -gt 0 ]; then
      git -C "$RV_RANGE_REPO" diff "$started_at" "$commit" -- "$@" > "$diff_path" 2>/dev/null \
        || die 3 "review-brief: could not write the diff from $started_at to $commit into $diff_path."
    fi
    if [ -n "$shared_paths" ]; then
      set --
      while IFS= read -r p; do [ -z "$p" ] || set -- "$@" "$p"; done <<RB_SHARED
$shared_paths
RB_SHARED
      while IFS= read -r c; do
        [ -n "$c" ] || continue
        git -C "$RV_RANGE_REPO" diff "$c^" "$c" -- "$@" >> "$diff_path" 2>/dev/null \
          || die 3 "review-brief: could not write the diff of $c into $diff_path."
      done <<RB_COMMITS
$own_commits
RB_COMMITS
    fi
  fi
  [ -z "$RV_RANGE_PATHS" ] || deliverables_json="$(printf '%s' "$RV_UNIT_JSON" | jq -c '.ownedFiles // []')"

  local criteria_json nongoals_json tests_json
  criteria_json="$(printf '%s' "$SNAPSHOT_DOC" | jq -c --argjson unit "$RV_UNIT_JSON" '
    ((($unit.criteriaServed // []) + ($unit.criteriaOwned // []))
      | reduce .[] as $x ([]; if index($x) then . else . + [$x] end)) as $ids
    | [ $ids[] as $id | (.alignment.criteria // [])[] | select(.id == $id)
        | {id, text, verification, verifiedBy} ]')"
  nongoals_json="$(printf '%s' "$SNAPSHOT_DOC" | jq -c '[ (.alignment.nonGoals // [])[] | {id, text} ]')"
  tests_json="$(rv_frozen_test_paths_json "$unit_id")"
  # A locks-in reason is read with the diff, so the brief says where it sits, and never copies it.
  local locks_note
  locks_note="$(jq -r --arg f "$IMPL_DIR/tests-$unit_id.json" '[ (.rows // [])[] | (.tests // [])[] | select(has("locksIn")) | .name ]
    | if length == 0 then "No test was frozen green."
      else "These tests were frozen green because existing code already satisfies them, and each reason sits beside the test name in \($f): \(join(", "))." end' \
    "$IMPL_DIR/tests-$unit_id.json" 2>/dev/null)"

  # The brief is a file the dispatch names, never text printed through this conversation. It
  # carries the contract, the order, the eight check results with what each tool printed, and both
  # interface texts; the reviewer reads it from the path.
  local brief_file brief_json
  brief_file="$IMPL_DIR/brief-$unit_id-review.json"
  brief_json="$(jq -n \
    --arg unit "$unit_id" \
    --arg locksIn "$locks_note" \
    --argjson criteria "$criteria_json" \
    --argjson nonGoals "$nongoals_json" \
    --argjson order "$(printf '%s' "$RV_UNIT_JSON" | jq -c "$REASONING_JQ"'.reasoning = liveReasoning')" \
    --arg diffPath "$diff_path" \
    --argjson deliverables "$deliverables_json" \
    --argjson frozenTests "$tests_json" \
    --argjson automatedTests "$(printf '%s' "$SNAPSHOT_DOC" | jq -c '.alignment.automatedTests')" \
    --arg reportPath "$(printf '%s' "$RV_BUILD_DOC" | jq -r '.reportPath // ""')" \
    --slurpfile build "$IMPL_DIR/build-$unit_id.json" \
    --arg interfaceDeclared "$(printf '%s' "$RV_UNIT_JSON" | jq -r '.interface // ""')" \
    --arg interfaceRecord "$(printf '%s' "$RV_BUILD_DOC" | jq -r '.interfaceRecord // ""')" \
    --arg findingsPath "$IMPL_DIR/review-$unit_id-findings.json" \
    --arg startedAt "$started_at" --arg commit "$commit" \
    --argjson playbooksPath "$(playbooks_path_json "$TASK_PATH")" \
    --arg recipes "$(rv_recipe_refs)" --arg worktree "$RV_CODEPATH" \
    '{
      unit: $unit,
      mode: "review",
      worktree: $worktree,
      criteria: $criteria,
      nonGoals: $nonGoals,
      order: $order,
      diffPath: $diffPath,
      deliverables: $deliverables,
      startedAt: $startedAt,
      commit: $commit,
      automatedTests: $automatedTests,
      frozenTests: $frozenTests,
      locksIn: $locksIn,
      reportPath: $reportPath,
      checks: ($build[0].checks // []),
      interface: ({ declared: $interfaceDeclared, record: $interfaceRecord }
                  + (if $build[0] | has("interfaceRecordBefore")
                     then { recordBefore: $build[0].interfaceRecordBefore } else {} end)),
      findingsPath: $findingsPath,
      playbooksPath: $playbooksPath,
      recipes: ($recipes | split("\n") | map(select(. != "")))
    }
    + (if $recipes == "" then {} else
       {recipeAnswer: "One answer per recipe: ref, verdict, evidence. A departed answer that a fix inside the order cures adds finding: the id of a finding with a fixScope, on a file the evidence names."} end)')"
  [ -n "$brief_json" ] || die 3 "review-brief: could not assemble the brief for $unit_id."
  write_atomic "$brief_file" "$brief_json"
  # The check verdicts are printed one per line because review.md routes on interface-record's;
  # the detail and the tool output stay in the brief and the build record.
  im_print_summary "review-brief" "$(printf '%s' "$brief_json" | jq -c --arg brief "$brief_file" '
    {order: .unit,
     brief: $brief,
     worktree: .worktree,
     diff: .diffPath,
     deliverables: (.deliverables | length),
     findingsPath: .findingsPath,
     reportPath: .reportPath,
     range: "\(.startedAt)..\(.commit)",
     criteria: ([ .criteria[] | .id ]),
     nonGoals: (.nonGoals | length),
     frozenTests: (.frozenTests | length),
     check: ([ .checks[] | {id, verdict} ]),
     interface: ("declared=" + (if .interface.declared == "" then "empty" else "present" end)
                 + " record=" + (if .interface.record == "" then "empty" else "present" end)),
     next: "dispatch reviewer with the brief path, then review-record with the findings path"}')"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# review-record: what the reviewer wrote, checked and recorded.
# ------------------------------------------------------------------------------------------------

# The fronts of the halt review-record writes for a departure: one the builder declared (gap row
# 224), and one the reviewer answered (gap row 225). Each begins "design drift: " so `restart`
# takes it, and matches no own-copy prefix, so a resumed `start` never clears it.
RR_DEPARTURE_PREFIX="design drift: the builder declared a departure from the design"
RR_REVIEWER_PREFIX="design drift: the reviewer answered that the build departs from"
RR_DEPARTURE_PREFIXES="$(jq -cn --arg a "$RR_DEPARTURE_PREFIX" --arg b "$RR_REVIEWER_PREFIX" '[$a, $b]')"

do_review_record() {
  local task_arg="" unit_id="" findings_path="" accept=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --findings)
        [ "$#" -ge 2 ] || die 3 "review-record: --findings needs a path to the file the reviewer wrote"
        findings_path="$2"; shift 2 ;;
      --accept-deviation)
        [ "$#" -ge 2 ] || die 3 "review-record: --accept-deviation needs the person's reason for keeping the departure"
        [ -n "$2" ] || die 3 "review-record: --accept-deviation was given an empty reason."
        accept="$2"; shift 2 ;;
      -*) die 3 "review-record: unrecognized argument: $1" ;;
      *)
        if [ -z "$task_arg" ]; then task_arg="$1"
        elif [ -z "$unit_id" ]; then unit_id="$1"
        else die 3 "review-record: unrecognized extra argument: $1"; fi
        shift ;;
    esac
  done
  [ -n "$task_arg" ]      || die 3 "review-record: a task folder is required"
  [ -n "$unit_id" ]       || die 3 "review-record: a unit id is required"
  [ -n "$findings_path" ] || die 3 "review-record: --findings is required"

  local resolve_rc
  TASK_PATH="$(resolve_task_folder "$task_arg" "review-record")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  IMPL_DIR="$TASK_PATH/implementation"

  local answers=""
  if [ -n "$accept" ]; then
    fn_require_interactive "review-record" "accepting a departure the builder declared"
    answers="$RR_DEPARTURE_PREFIXES"
  fi
  rv_load_state "review-record" "$unit_id" "$answers"

  # Exit 50 before the step check, for the reason review-brief above states. One case is not a
  # second review: a crash between the record write and the ledger write leaves the record on disk
  # with the ledger still at checks-passed, and the routing table has no row for that. The record
  # is this order own, at this order own commit, so the repair is to finish the write that did not
  # land rather than to refuse forever.
  local review_file="$IMPL_DIR/review-$unit_id.json"
  if [ -f "$review_file" ]; then
    local rr_step rr_doc rr_commit rr_head
    rr_step="$(printf '%s' "$RV_ORDER_ENTRY" | jq -r '.lastStep // ""')"
    rr_doc="$(jq -c '.' "$review_file" 2>/dev/null)"
    rr_commit=""
    [ -n "$rr_doc" ] && rr_commit="$(printf '%s' "$rr_doc" | jq -r '.reviewedAt // ""')"
    rv_load_codepath "review-record"
    rv_load_range_repo "review-record" "$RV_UNIT_JSON"
    rr_head="$(git -C "$RV_RANGE_REPO" rev-parse HEAD 2>/dev/null)"
    if [ "$rr_step" = "checks-passed" ] && [ -n "$rr_commit" ] && [ "$rr_commit" = "$rr_head" ]; then
      RV_REVIEW_FILE="$review_file"
      RV_REVIEW_DOC="$rr_doc"
      local rr_ledger
      rr_ledger="$(printf '%s' "$RV_LEDGER_DOC" | jq -c --arg id "$unit_id" \
        '.orders = (.orders | map(if .id == $id then (.lastStep = "reviewed") else . end))')"
      [ -n "$rr_ledger" ] || die 3 "review-record: the ledger update for $unit_id failed."
      write_atomic "$RV_LEDGER_FILE" "$rr_ledger"
      im_print_summary "review-record" "$(printf '%s' "$rr_doc" | jq -c --arg record "$review_file" \
        --arg next "$(im_next_step "$rr_ledger" "$SNAPSHOT_DOC" "$IMPL_DIR" "true" "false")" '
        {order: .unit, commit: .reviewedAt,
         findings: ([ .findings[] | .id ]),
         openActionable: ([ .findings[] | select(.actionable == true and .status == "open") | .id ]),
         state: "reviewed: the record was already written and the ledger had not moved, so nothing was reviewed twice",
         halt: "none", record: $record, next: $next}')"
      echo "REVIEW-RECORD: $review_file was already written at $rr_commit and the ledger had not moved. The ledger now reads reviewed; nothing was reviewed twice." >&2
      exit 0
    fi
    die 50 "review-record: $review_file already exists, so $unit_id has been reviewed. One order gets one review, ever."
  fi
  rv_require_step "review-record" "$unit_id" "checks-passed"

  rv_load_build_record "review-record" "$unit_id"
  rv_load_codepath "review-record"
  rv_load_range_repo "review-record" "$RV_UNIT_JSON"

  # Exit 51, decision 6. The reviewer holds Write for one reason: its findings file, at the path
  # the brief gave, under the task folder. This is the check that enforces it. A probe test left
  # in the reviewed code is a refusal here, not a finding later. For an order whose proof is
  # record the tree read is the deliverable itself, the owned files in the project folder.
  local recorded_commit current_commit dirty
  recorded_commit="$(printf '%s' "$RV_BUILD_DOC" | jq -r '.commit // ""')"
  current_commit="$(git -C "$RV_RANGE_REPO" rev-parse HEAD 2>/dev/null)"
  [ -n "$current_commit" ] \
    || die 3 "review-record: could not capture the current commit (git rev-parse HEAD failed in $RV_RANGE_REPO)."
  [ "$recorded_commit" = "$current_commit" ] \
    || die 51 "review-record: $RV_RANGE_REPO is at $current_commit, and the build record for $unit_id was taken at $recorded_commit. The code moved while the review ran, so these findings are about code that is no longer there."
  dirty="$(git_status_of "$RV_RANGE_REPO" "$RV_RANGE_PATHS")"
  [ -z "$dirty" ] \
    || die 51 "review-record: the working tree at $RV_RANGE_REPO is dirty, and the review may write nothing but its own findings file. What changed: $(printf '%s' "$dirty" | tr '\n' ' ')"

  local raw_findings alignment count i one built findings_json information_json outside outside_lines=""
  rv_read_findings_array "$findings_path" "findings" "review-record"
  raw_findings="$RV_FINDINGS_ARRAY"
  rv_read_information_array "$findings_path" "review-record"
  information_json="$RV_INFORMATION_ARRAY"
  local rr_test_globs=""
  [ "$(printf '%s' "$SNAPSHOT_DOC" | jq -r '.alignment.automatedTests == false')" != "true" ] \
    || [ "$(rv_frozen_test_paths_json "$unit_id")" != "[]" ] \
    || rr_test_globs="$(jq -r '(.testGlobs // [])[]' "$IMPL_DIR/tests-$unit_id.json" 2>/dev/null)"
  rv_read_recipe_answers "$findings_path" "review-record" "$IMPL_DIR/diff-$unit_id.patch" "$rr_test_globs"

  alignment="$(printf '%s' "$SNAPSHOT_DOC" | jq -c '.alignment // {}')"
  # Gap row 265. An empty fix scope routes a finding to a ruling with no fix round, so the script
  # checks the reviewer's claim. A finding that cites a file the order owns, or a file its diff
  # changes, is about code, and its fix scope names the files a fix changes. A finding that cites
  # a record, not code, may name none. The diff paths are read once, from the build's own diff.
  local diff_paths empty_file empty_abs empty_rel
  diff_paths="$(sed -n -e 's#^+++ b/##p' -e 's#^--- a/##p' "$IMPL_DIR/diff-$unit_id.patch" 2>/dev/null | sort -u)"
  findings_json='[]'
  count="$(printf '%s' "$raw_findings" | jq 'length')"
  i=0
  while [ "$i" -lt "$count" ]; do
    one="$(printf '%s' "$raw_findings" | jq -c --argjson i "$i" '.[$i]')"
    built="$(rv_finding_record "$one" "$alignment" "review")"
    empty_file="$(printf '%s' "$built" | jq -r 'if (.fixScope | length) == 0 then .file else "" end')"
    if [ -n "$empty_file" ]; then
      empty_abs="$(normalize_abs "$(resolve_against "$empty_file" "$RV_CODEPATH")")"
      empty_rel="${empty_abs#"$RV_CODEPATH"/}"
      if ! is_under "$empty_abs" "$TASK_PATH" \
        && { [ -z "$(rv_scope_outside "$(jq -nc --arg p "$empty_file" '[$p]')" "$(printf '%s' "$RV_UNIT_JSON" | jq -c '.ownedFiles // []')" "$RV_CODEPATH" "$TASK_PATH")" ] \
             || printf '%s\n' "$diff_paths" | grep -qxF -- "$empty_rel"; }; then
        die 52 "review-record: finding $(printf '%s' "$built" | jq -r '.id') in $findings_path cites $empty_file, a file $unit_id owns or its diff changes, and its fixScope is empty or missing. A finding about code names the files a fix changes in fixScope. Only a finding about a record, not code, has an empty fix scope. Nothing is written."
      fi
    fi
    # Live-run row 116. The paths of the finding's fixScope outside the order's own ownedFiles are
    # stored on the finding, when there are any, and printed before the summary. Nothing is ruled
    # here: fix-brief withholds them, and a person allows one there.
    outside="$(rv_scope_outside "$(printf '%s' "$built" | jq -c '.fixScope')" \
      "$(printf '%s' "$RV_UNIT_JSON" | jq -c '.ownedFiles // []')" "$RV_CODEPATH" "$TASK_PATH")"
    if [ -n "$outside" ]; then
      built="$(printf '%s' "$built" | jq -c --arg o "$outside" '.outsideOwned = ($o | split("\n"))')"
      outside_lines="$outside_lines$(printf '%s' "$built" | jq -r '"outsideOwned: \(.id): \(.outsideOwned | join(", "))"')
"
    fi
    findings_json="$(printf '%s' "$findings_json" | jq -c --argjson f "$built" '. + [$f]')"
    i=$((i + 1))
  done

  # Exit 107, gap row 224. A departure the builder declared goes back to design, whatever the
  # review holds: the design, or a recipe it relies on, is what is wrong, so no fixer can repair
  # it. The scan is build-record's own, over the latest attempt's report and the interface record
  # its build record holds. A build record written before that scan existed reaches review with
  # one in it. The reviewer's information item with departsFromDesign true is the same fact, and so
  # is a recipe it answers departed (gap row 225); those halts carry the reviewer's own front. The
  # halt names the file and the line, never the builder's text, which may hold the halt separator.
  # The recipe reader already refused that separator, and a line break, in the reviewer's evidence.
  local departure departure_file departure_line="" iface_file halt_why=""
  departure_file="$(printf '%s' "$RV_BUILD_DOC" | jq -r '.reportPath // ""')"
  departure="$(br_deviations "$departure_file" | head -n 1)"
  [ -z "$departure" ] || departure_line="$(sed 's/\*//g' "$departure_file" | grep -n -F -- "$departure" | head -n 1 | cut -d: -f1)"
  if [ -z "$departure" ]; then
    iface_file="$(mktemp)" || die 3 "review-record: could not create a temporary file"
    printf '%s\n' "$(printf '%s' "$RV_BUILD_DOC" | jq -r '.interfaceRecord // ""')" >"$iface_file"
    departure="$(br_deviations "$iface_file" | head -n 1)"
    [ -z "$departure" ] || departure_line="$(sed 's/\*//g' "$iface_file" | grep -n -F -- "$departure" | head -n 1 | cut -d: -f1)"
    rm -f "$iface_file"
    departure_file="the interfaceRecord of $IMPL_DIR/build-$unit_id.json"
  fi
  # Gap row 266. A person kept this line at build-record, so the review carries that answer and
  # does not ask again. A departure the reviewer finds is a new fact, and it still halts.
  local build_accepted
  build_accepted="$(printf '%s' "$RV_BUILD_DOC" | jq -c '.deviationAccepted // null')"
  [ -z "$departure" ] || [ "$departure" != "$(printf '%s' "$build_accepted" | jq -r '.departure // ""')" ] || departure=""
  [ -z "$departure" ] || halt_why="$RR_DEPARTURE_PREFIX, at line $departure_line of $departure_file"
  if [ -z "$departure" ]; then
    departure="$(printf '%s' "$information_json" | jq -r \
      '[ .[] | select(.departsFromDesign) ] | .[0] // empty | "information item \(.id): \(.summary)"')"
    departure_file="$findings_path"
    [ -z "$departure" ] \
      || halt_why="$RR_REVIEWER_PREFIX the design, marked departsFromDesign in $(printf '%s' "$departure" | cut -d: -f1) of $findings_path"
  fi
  # Gap row 303. A recipe the reviewer answers departed, paired by `finding` with an actionable
  # finding that has a fix scope, is one a fix round cures, so it opens that round and halts
  # nothing. The paired finding sits on a file the departed evidence names, so an unrelated finding
  # cannot carry a design departure. With no `finding`, the one curable finding on such a file is
  # paired here; two or more go back to the reviewer. The paired finding carries departureFrom, and
  # verify answers departureCured for it. A departed answer with no such finding takes the route above.
  local pair_json pair_err paired_lines
  pair_json="$(printf '%s' "$RV_RECIPE_ANSWERS" | jq -c --argjson f "$findings_json" --argjson named "$RV_RECIPE_NAMED" '
    [ .[] | . as $a | ($named[$a.ref] // []) as $files
      | if ($a | has("finding")) then
          ([ $f[] | select(.id == $a.finding) ][0]) as $p
          | if $a.verdict != "departed" or $p == null then
              {a: $a, err: "the recipes answer for \($a.ref) (\($a.verdict), finding \($a.finding)) names a finding it cannot carry. Only a departed answer names a finding, and the finding is one of this file'"'"'s findings, by its id."}
            elif ($files | index($p.file)) == null then
              {a: $a, err: "the recipes answer for \($a.ref) names finding \($p.id), on \($p.file), a file its departed evidence does not name. The finding that cures a departure sits on a file the evidence names: \($files | join(", "))."}
            else {a: $a} end
        elif $a.verdict == "departed" then
          [ $f[] | select(.actionable and (.fixScope | length) > 0 and (.file as $pf | $files | index($pf)) != null) | .id ] as $c
          | if ($c | length) == 1 then {a: ($a + {finding: $c[0]}), paired: $c[0]}
            elif ($c | length) > 1 then {a: $a, err: "the recipes answer for \($a.ref) is departed, and \($c | join(", ")) each sit on a file its evidence names. Name the one whose fix cures the departure under finding."}
            else {a: $a} end
        else {a: $a} end ]')"
  [ -n "$pair_json" ] || die 3 "review-record: the recipe answers could not be paired with the findings."
  pair_err="$(printf '%s' "$pair_json" | jq -r '[ .[] | .err // empty ] | .[0] // empty')"
  [ -z "$pair_err" ] || die 52 "review-record: $pair_err in $findings_path. Nothing is written. $RR_REDISPATCH"
  paired_lines="$(printf '%s' "$pair_json" | jq -r '.[] | select(has("paired")) | "paired: \(.a.ref) with \(.paired), the one actionable finding on a file its departed evidence names"')"
  RV_RECIPE_ANSWERS="$(printf '%s' "$pair_json" | jq -c '[ .[].a ]')"
  findings_json="$(printf '%s' "$findings_json" | jq -c --argjson r "$RV_RECIPE_ANSWERS" '
    map(. as $x | ([ $r[] | select(.verdict == "departed" and .finding == $x.id) ][0].ref) as $ref
        | if $ref != null and $x.actionable and ($x.fixScope | length) > 0 then $x + {departureFrom: $ref} else $x end)')"
  if [ -z "$departure" ]; then
    departure="$(printf '%s' "$RV_RECIPE_ANSWERS" | jq -r --argjson f "$findings_json" '
      [ $f[] | select(.actionable and (.fixScope | length) > 0) | .id ] as $cures
      | [ .[] | select(.verdict == "departed" and ((.finding // "") as $id | $cures | index($id)) == null) ]
      | .[0] // empty | "\(.ref): \(.evidence)"')"
    [ -z "$departure" ] || halt_why="$RR_REVIEWER_PREFIX $departure"
  fi
  if [ -z "$departure" ]; then
    [ -z "$accept" ] \
      || die 3 "review-record: --accept-deviation was given, and neither the report, the interface record nor the review of $unit_id names a departure. Nothing is written."
  elif [ -z "$accept" ] && [ "$RV_RUN_MODE" = "autonomous" ]; then
    # Gap row 279. Unattended, the departure waits for the person at the task review, and the
    # record below holds it as deviationPending. Nothing halts.
    :
  elif [ -z "$accept" ]; then
    local departure_ledger
    departure_ledger="$(halt_order_in "$RV_LEDGER_DOC" "$unit_id" "$halt_why")"
    [ -n "$departure_ledger" ] || die 3 "review-record: the halt on $unit_id could not be written."
    write_atomic "$RV_LEDGER_FILE" "$departure_ledger"
    die 107 "review-record: $unit_id is halted for design drift. A departure from the design is named in $departure_file: $departure. What is wrong is the design, or a recipe it relies on, so no fixer can repair it, and no review record is written. Amend the order in design and close design, then run restart to rebuild the order. Or, interactive only, a person accepts the departure: run review-record again with --accept-deviation <their reason>."
  fi

  local today record_json
  today="$(date -u +%Y-%m-%d)"
  # The information list is written only when the reviewer wrote one, so a record without it reads
  # exactly as it did before the key existed.
  record_json="$(jq -n --arg takenAt "$today" --arg unit "$unit_id" --arg commit "$current_commit" \
    --arg findingsPath "$findings_path" --argjson findings "$findings_json" \
    --argjson information "$information_json" --argjson recipes "$RV_RECIPE_ANSWERS" \
    --arg accept "$accept" --arg departure "$departure" \
    --arg departureFile "$departure_file" --argjson carried "$build_accepted" '
    {
      schemaVersion: 1,
      takenAt: $takenAt,
      unit: $unit,
      reviewedAt: $commit,
      findingsPath: $findingsPath,
      findings: $findings,
      rounds: []
    }
    + (if ($information | length) == 0 then {} else {information: $information} end)
    + (if ($recipes | length) == 0 then {} else {recipes: $recipes} end)
    + (if $accept != "" then {deviationAccepted: {departure: $departure, file: $departureFile, because: $accept}}
       elif $carried != null then {deviationAccepted: $carried} else {} end)
    + (if $accept == "" and $departure != "" then {deviationPending: {departure: $departure, file: $departureFile}} else {} end)')"
  write_atomic "$review_file" "$record_json"

  # Decision 11. Unattended, a finding that hits a non-goal halts the order with the non-goal
  # named (ideal/implementation.md, the unattended-answers table). Interactive, it is actionable
  # like any other finding and the skill puts it to the person.
  local nongoal_hits step_expr
  nongoal_hits="$(rv_nongoal_hits "$findings_json" "$alignment")"
  local new_ledger
  step_expr='.lastStep = "reviewed"'
  new_ledger="$(printf '%s' "$RV_LEDGER_DOC" | jq -c --arg id "$unit_id" \
    ".orders = (.orders | map(if .id == \$id then ($step_expr) else . end))")"
  [ -n "$new_ledger" ] || die 3 "review-record: the ledger update for $unit_id failed."
  # An accepted departure lands in haltsCleared the way `clear-halt` writes one, with the halt the
  # order carried, or the one this departure would have written. rv_load_state let only that
  # segment through, so the order is no longer halted.
  if [ -n "$accept" ]; then
    new_ledger="$(accept_deviation_in "$new_ledger" "$unit_id" "$RR_DEPARTURE_PREFIXES" "$halt_why" "$accept")"
    [ -n "$new_ledger" ] || die 3 "review-record: the ledger update for $unit_id failed."
  fi
  halt_why=""
  if [ "$RV_RUN_MODE" = "autonomous" ] && [ -n "$nongoal_hits" ]; then
    halt_why="a finding hits a non-goal and nobody is present to rule on it: $nongoal_hits"
  fi
  # One function writes every halt, so this reason never erases a reason the order already carried.
  if [ -n "$halt_why" ]; then
    new_ledger="$(halt_order_in "$new_ledger" "$unit_id" "$halt_why")"
    [ -n "$new_ledger" ] || die 3 "review-record: the halt on $unit_id could not be written."
  fi
  write_atomic "$RV_LEDGER_FILE" "$new_ledger"

  [ -z "$outside_lines" ] || printf '%s' "$outside_lines"
  [ -z "$paired_lines" ] || printf '%s\n' "$paired_lines"
  # One line per finding: its severity, whether it is actionable and what it cites. Its evidence
  # stays in the record, named by path.
  im_print_summary "review-record" "$(printf '%s' "$record_json" | jq -c --arg record "$review_file" \
    --arg halt "${halt_why:-none}" --arg nongoals "${nongoal_hits:-none}" \
    --arg next "$(im_next_step "$new_ledger" "$SNAPSHOT_DOC" "$IMPL_DIR" "true" "false")" '
    {order: .unit,
     commit: .reviewedAt,
     finding: ([ .findings[] | {id, severity,
                                actionable: (if .actionable then "actionable" else "not actionable" end),
                                linkedTo: ("cites " + (.linkedTo // "nothing")), file} ]),
     openActionable: ([ .findings[] | select(.actionable == true and .status == "open") | .id ]),
     nonGoalHits: $nongoals,
     state: "reviewed",
     halt: $halt}
    + (if has("deviationAccepted") then {departureAccepted: .deviationAccepted.because} else {} end)
    + (if has("deviationPending") then {departurePending: (.deviationPending.departure + ": the person decides at the task review")} else {} end)
    + {record: $record, next: $next}')"
  # Live-run row 96. A finding that cites no id never reaches a fixer, and nothing between here and
  # the close reads it. Interactive, the ones of medium or higher severity print after the summary,
  # so the person present decides. Unattended, nothing prints: the record already holds them. The
  # evidence is cut the way the summary cuts a string, so the line stays one line.
  local unrouted
  if [ "$RV_RUN_MODE" != "autonomous" ]; then
    unrouted="$(printf '%s' "$findings_json" | jq -r '
      [ .[] | select(.actionable == false and (.severity == "medium" or .severity == "high")) ]
      | if length == 0 then empty
        else (.[] | "unrouted: \(.id) \(.severity) \(.evidence | gsub("\n"; " ") | .[0:240]) (\(if .file == "" then "no file named" else .file end))"),
             "unrouted: \(length) of medium or higher severity; the record holds them, a person decides" end')"
    [ -z "$unrouted" ] || printf '%s\n' "$unrouted"
  fi
  # Live-run row 103. What the reviewer wrote for the person and not as a finding, one line each
  # and a count, in both modes: it is in the record either way, and the summary is where a person
  # or a log reader sees it. Nothing prints when the list is empty.
  local information_lines
  information_lines="$(printf '%s' "$information_json" | jq -r '
    if length == 0 then empty
    else (.[] | "information: \(.id) \(.summary | gsub("\n"; " ") | .[0:240])"),
         "information: \(length) for the person, in the record and in the next order\u0027s briefs" end')"
  [ -z "$information_lines" ] || printf '%s\n' "$information_lines"
  # Gap row 300. A departure this action recorded not-applicable is shown, so a person sees it.
  printf '%s' "$RV_RECIPE_ANSWERS" | jq -r '.[] | select(has("departedAnswer"))
    | "recipe: \(.ref) recorded not-applicable: \(.evidence); the reviewer answered departed: \(.departedAnswer)"'
  if [ "$RV_RUN_MODE" = "autonomous" ] && [ -n "$nongoal_hits" ]; then
    echo "REVIEW-RECORD: $unit_id is halted. A finding hits a non-goal and this run is unattended: $nongoal_hits" >&2
  fi
  exit 0
}

# ------------------------------------------------------------------------------------------------
# fix-brief: every open finding of one order, in severity order, with the union of their scopes.
# Not one fixer per finding (ideal/implementation.md, "One fixer per round, verification per
# finding").
# ------------------------------------------------------------------------------------------------

do_fix_brief() {
  local task_arg="" unit_id="" allow_raw=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --allow)
        [ "$#" -ge 2 ] || die 3 "fix-brief: --allow needs a path relative to codePath"
        [ -n "$2" ] || die 3 "fix-brief: --allow was given an empty path."
        allow_raw="$allow_raw$2
"
        shift 2 ;;
      -*) die 3 "fix-brief: unrecognized argument: $1" ;;
      *)
        if [ -z "$task_arg" ]; then task_arg="$1"
        elif [ -z "$unit_id" ]; then unit_id="$1"
        else die 3 "fix-brief: unrecognized extra argument: $1"; fi
        shift ;;
    esac
  done
  [ -n "$task_arg" ] || die 3 "fix-brief: a task folder is required"
  [ -n "$unit_id" ]  || die 3 "fix-brief: a unit id is required"
  local resolve_rc
  TASK_PATH="$(resolve_task_folder "$task_arg" "fix-brief")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  IMPL_DIR="$TASK_PATH/implementation"

  rv_load_state "fix-brief" "$unit_id"
  rv_require_step "fix-brief" "$unit_id" "reviewed fixed"
  rv_load_review_record "fix-brief" "$unit_id"

  local open_count rounds_used
  open_count="$(rv_open_actionable_count "$RV_REVIEW_DOC")"
  [ "$open_count" -gt 0 ] 2>/dev/null \
    || die 53 "fix-brief: $unit_id has no open actionable finding, so there is nothing to hand a fixer."
  rounds_used="$(printf '%s' "$RV_ORDER_ENTRY" | jq -r '.roundsUsed // 0')"
  case "$rounds_used" in ''|*[!0-9]*) rounds_used=0 ;; esac
  [ "$rounds_used" -lt "$FIX_ROUNDS_ALLOWED" ] \
    || die 54 "fix-brief: $unit_id has already used $rounds_used of $FIX_ROUNDS_ALLOWED allowed fix rounds. Every open finding needs a ruling now, not another round."
  rv_require_round_verified "fix-brief" "$unit_id" "$rounds_used"

  rv_load_build_record "fix-brief" "$unit_id"

  local open_json scope_json tests_json owned_json
  open_json="$(printf '%s' "$RV_REVIEW_DOC" | jq -c '
    [ (.findings // [])[] | select(.actionable == true and .status == "open") ]
    | sort_by(if .severity == "high" then 0 elif .severity == "medium" then 1 else 2 end)
    | map({id, severity, file, lines, linkedTo, evidence, fixScope, origin})')"

  # Gap row 265. A finding with an empty fix scope asks for no code change, so a fixer can change
  # nothing and fix-record refuses the empty range. When every open finding is one, no brief is
  # written, and a person rules each one at verify-record with no round. Unattended, each one is
  # marked pending instead, so it is no longer open and the order goes on to its close. The person
  # rules it at the task review, from finished.json (gap row 279).
  local empty_ids empty_why empty_who empty_call empty_doc
  empty_ids="$(printf '%s' "$open_json" | jq -r 'if all(.[]; (.fixScope // []) | length == 0) then [ .[].id ] | join(", ") else "" end')"
  if [ -n "$empty_ids" ]; then
    case "$empty_ids" in
      *,*) empty_why="no fix round can change $empty_ids, because each has an empty fix scope"; empty_who="each one" ;;
      *) empty_why="no fix round can change $empty_ids, because its fix scope is empty"; empty_who="it" ;;
    esac
    empty_call="verify-record $TASK_PATH $unit_id --ruling ${empty_ids%%,*}=<wrong|deferred|load-bearing|test-wrong>::<reason>"
    if [ "$RV_RUN_MODE" = "autonomous" ]; then
      empty_doc="$(printf '%s' "$RV_REVIEW_DOC" | jq -c --arg ids "$empty_ids" '
        ($ids | split(", ")) as $p
        | .findings = [ .findings[] | if (.id as $i | $p | index($i)) != null then .status = "pending" else . end ]')"
      [ -n "$empty_doc" ] || die 3 "fix-brief: the pending findings of $unit_id could not be written."
      write_atomic "$RV_REVIEW_FILE" "$empty_doc"
      im_print_summary "fix-brief" "$(jq -cn --arg order "$unit_id" --arg why "$empty_why" --arg record "$RV_REVIEW_FILE" \
        --arg next "$(im_next_step "$RV_LEDGER_DOC" "$SNAPSHOT_DOC" "$IMPL_DIR" "true" "false")" \
        '{order: $order, pending: ($why + ". Nobody is present to rule, so the person rules at the task review"),
          record: $record, next: $next}')"
      exit 0
    fi
    die 53 "fix-brief: $empty_why. A person rules $empty_who: $empty_call."
  fi
  tests_json="$(rv_frozen_test_paths_json "$unit_id")"
  owned_json="$(printf '%s' "$RV_UNIT_JSON" | jq -c '.ownedFiles // []')"

  rv_load_codepath "fix-brief"
  rv_load_range_repo "fix-brief" "$RV_UNIT_JSON"

  # Live-run row 116. A fixScope path outside the order's ownedFiles is withheld from the fixer
  # unless a person allows it here. An allow is a person's grant, so unattended refuses it
  # (exit 100). A path already owned needs no grant. A frozen test or a support file may never
  # be granted. A path no open finding names is a grant for nothing (exit 3, each).
  local allowed_json='[]' ap ap_abs tf fp frozen_list frozen_hit named
  [ -z "$allow_raw" ] || [ "$RV_RUN_MODE" != "autonomous" ] \
    || die 100 "fix-brief: --allow is a person's grant, and this run is unattended. Nobody is present to allow a path outside $unit_id's own files."
  # Every frozen test and support path of the task, the list the write hook reads.
  frozen_list=""
  for tf in "$IMPL_DIR"/tests-*.json; do
    [ -e "$tf" ] || continue
    frozen_list="$frozen_list$(jq -r '(.rows[]?.tests[]?.path // empty), (.support[]?.path // empty)' "$tf" 2>/dev/null)
"
  done
  while IFS= read -r ap; do
    [ -n "$ap" ] || continue
    ap_abs="$(normalize_abs "$(resolve_against "$ap" "$RV_CODEPATH")")"
    [ -n "$(rv_scope_outside "$(jq -nc --arg p "$ap" '[$p]')" "$owned_json" "$RV_CODEPATH" "$TASK_PATH")" ] \
      || die 3 "fix-brief: --allow names $ap, which $unit_id already owns. A grant is for a path outside the order's own files."
    frozen_hit=""
    while IFS= read -r fp; do
      [ -n "$fp" ] || continue
      [ "$(normalize_abs "$(resolve_against "$fp" "$RV_CODEPATH")")" = "$ap_abs" ] && frozen_hit="$fp"
    done <<FB_FROZEN
$frozen_list
FB_FROZEN
    [ -z "$frozen_hit" ] \
      || die 3 "fix-brief: --allow names $ap, a frozen test or a support file. A fixer never changes a test; rule the finding test-wrong at verify-record instead."
    named="$(printf '%s' "$open_json" | jq -r --arg p "$ap" --arg abs "$ap_abs" --arg code "$RV_CODEPATH" '
      [ .[] | (.fixScope // [])[] | select(. == $p or . == $abs or ($code + "/" + .) == $abs) ] | length')"
    [ "$named" != "0" ] \
      || die 3 "fix-brief: --allow names $ap, which no open finding's fixScope names. A grant is for a finding; the open findings name: $(printf '%s' "$open_json" | jq -r '[ .[] | (.fixScope // [])[] ] | unique | join(", ")')"
    # Stored resolved and relative to codePath, whatever form was typed: the withhold, the
    # owned-files check and the hook all read that one spelling.
    allowed_json="$(printf '%s' "$allowed_json" | jq -c --arg p "${ap_abs#"$RV_CODEPATH"/}" '. + [$p] | unique')"
  done <<FB_ALLOW
$allow_raw
FB_ALLOW

  # Per finding, the fixScope paths outside ownedFiles and the allowed list are withheld. The
  # union the fixer gets is every other fixScope path. A finding wholly withheld is still handed
  # over, so the fixer reports it scope-insufficient and the ruling route opens.
  local fcount fn one withheld reach_json
  reach_json="$(jq -nc --argjson o "$owned_json" --argjson a "$allowed_json" '$o + $a | unique')"
  fcount="$(printf '%s' "$open_json" | jq 'length')"
  fn=0
  while [ "$fn" -lt "$fcount" ]; do
    one="$(printf '%s' "$open_json" | jq -c --argjson i "$fn" '.[$i]')"
    withheld="$(rv_scope_outside "$(printf '%s' "$one" | jq -c '.fixScope // []')" "$reach_json" "$RV_CODEPATH" "$TASK_PATH")"
    if [ -n "$withheld" ]; then
      one="$(printf '%s' "$one" | jq -c --arg w "$withheld" '.withheld = ($w | split("\n"))')"
    else
      one="$(printf '%s' "$one" | jq -c '.withheld = []')"
    fi
    open_json="$(printf '%s' "$open_json" | jq -c --argjson i "$fn" --argjson f "$one" '.[$i] = $f')"
    fn=$((fn + 1))
  done
  scope_json="$(printf '%s' "$open_json" | jq -c '[ .[] | (.fixScope // [])[] as $p | select(.withheld | index($p) | not) | $p ] | unique')"

  local fb_head brief_file brief_json
  fb_head="$(git -C "$RV_RANGE_REPO" rev-parse HEAD 2>/dev/null)"
  # One brief per round, because each round's open findings differ from the last round's and the
  # record of what a fixer was given is worth keeping beside its report.
  brief_file="$IMPL_DIR/brief-$unit_id-fix-$((rounds_used + 1)).json"
  brief_json="$(jq -n --arg unit "$unit_id" --argjson findings "$open_json" --argjson fixScope "$scope_json" \
    --argjson allowedFiles "$allowed_json" \
    --argjson frozenTests "$tests_json" --arg headNow "$fb_head" \
    --arg reportPath "$IMPL_DIR/answers-$unit_id-fix$((rounds_used + 1)).md" \
    --arg diffBudget "$(printf '%s' "$RV_UNIT_JSON" | jq -r '.diffBudget // ""')" \
    --argjson roundsUsed "$rounds_used" --argjson roundsAllowed "$FIX_ROUNDS_ALLOWED" \
    --argjson round "$((rounds_used + 1))" --argjson playbooksPath "$(playbooks_path_json "$TASK_PATH")" \
    --arg worktree "$RV_CODEPATH" '
    {
      unit: $unit,
      worktree: $worktree,
      round: $round,
      roundsUsed: $roundsUsed,
      roundsAllowed: $roundsAllowed,
      findings: $findings,
      fixScope: $fixScope,
      allowedFiles: $allowedFiles,
      frozenTests: $frozenTests,
      headNow: $headNow,
      diffBudget: $diffBudget,
      reportPath: $reportPath,
      playbooksPath: $playbooksPath
    }')"
  [ -n "$brief_json" ] || die 3 "fix-brief: could not assemble the brief for $unit_id."
  write_atomic "$brief_file" "$brief_json"
  # A finding is named by id, severity and the id it cites. Its evidence stays in the brief.
  im_print_summary "fix-brief" "$(printf '%s' "$brief_json" | jq -c --arg brief "$brief_file" '
    {order: .unit,
     round: "\(.round) of \(.roundsAllowed)",
     brief: $brief,
     worktree: .worktree,
     reportPath: .reportPath,
     headNow: (if .headNow == "" then "none: the code repository commit could not be read" else .headNow end),
     finding: ([ .findings[] | {id, severity, linkedTo: ("cites " + (.linkedTo // "nothing")), file} ]),
     fixScope: .fixScope,
     withheld: ([ .findings[] | select((.withheld | length) > 0) | {id, paths: (.withheld | join(", "))} ]),
     allowed: .allowedFiles,
     frozenTests: (.frozenTests | length),
     diffBudget: (if .diffBudget == "" then "none" else .diffBudget end),
     next: "dispatch fixer with the brief path, then fix-record"}')"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# fix-record: one fix round, and the seven computable checks again. A fix is code, and code that
# breaks a passing test is not a fix (ideal/implementation.md, "The fix rounds re-run the first two
# checks"). The interface check is never re-run here: a fix round does not rewrite that record.
# ------------------------------------------------------------------------------------------------

do_fix_record() {
  local task_arg="" unit_id="" report_path="" started_at=""
  local nothing_ran="" have_nothing_ran=false
  local test_recipes="" check_recipes="" gate_recipes="" values="" scope_raw=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --report)
        [ "$#" -ge 2 ] || die 3 "fix-record: --report needs a path to the fixer's report"
        [ -n "$2" ] || die 3 "fix-record: --report was given an empty path."
        report_path="$2"; shift 2 ;;
      --scope-insufficient)
        [ "$#" -ge 2 ] || die 3 "fix-record: --scope-insufficient needs <finding id>=<reason>"
        [ -n "$2" ] || die 3 "fix-record: --scope-insufficient was given an empty value."
        halt_refuse_separator "fix-record" "--scope-insufficient" "${2#*=}"
        scope_raw="$scope_raw$2
"
        shift 2 ;;
      --started-at)
        [ "$#" -ge 2 ] || die 3 "fix-record: --started-at needs a commit"
        [ -n "$2" ] || die 3 "fix-record: --started-at was given an empty commit."
        started_at="$2"; shift 2 ;;
      --test-recipe)
        [ "$#" -ge 2 ] || die 3 "fix-record: --test-recipe needs <framework>=<path>"
        cr_recipe_pair "fix-record" "--test-recipe" "$2"
        test_recipes="$test_recipes$CR_PAIR
"
        shift 2 ;;
      --check-recipe)
        [ "$#" -ge 2 ] || die 3 "fix-record: --check-recipe needs <framework>=<path>"
        cr_recipe_pair "fix-record" "--check-recipe" "$2"
        check_recipes="$check_recipes$CR_PAIR
"
        shift 2 ;;
      --implement-recipe)
        [ "$#" -ge 2 ] || die 3 "fix-record: --implement-recipe needs <framework>=<path>"
        cr_recipe_pair "fix-record" "--implement-recipe" "$2"
        gate_recipes="$gate_recipes$CR_PAIR
"
        shift 2 ;;
      --value)
        [ "$#" -ge 2 ] || die 3 "fix-record: --value needs <name>=<value>"
        case "$2" in *=*) ;; *) die 3 "fix-record: --value takes <name>=<value>, got: $2" ;; esac
        pc_refuse_forged_value "fix-record" "$2"
        values="$values$(printf '%s' "$2" | sed 's/=/\t/')
"
        shift 2 ;;
      --nothing-ran)
        [ "$#" -ge 2 ] || die 3 "fix-record: --nothing-ran needs a literal substring"
        [ -n "$2" ] || die 3 "fix-record: --nothing-ran was given an empty substring, which every output holds."
        have_nothing_ran=true
        nothing_ran="$2"
        shift 2 ;;
      -*) die 3 "fix-record: unrecognized argument: $1" ;;
      *)
        if [ -z "$task_arg" ]; then task_arg="$1"
        elif [ -z "$unit_id" ]; then unit_id="$1"
        else die 3 "fix-record: unrecognized extra argument: $1"; fi
        shift ;;
    esac
  done

  [ -n "$task_arg" ]    || die 3 "fix-record: a task folder is required"
  [ -n "$unit_id" ]     || die 3 "fix-record: a unit id is required"
  [ -n "$report_path" ] || die 3 "fix-record: --report is required"
  [ -s "$report_path" ] || die 3 "fix-record: --report names no file, or an empty one: $report_path"
  [ -n "$started_at" ]  || die 3 "fix-record: --started-at is required"

  local resolve_rc
  TASK_PATH="$(resolve_task_folder "$task_arg" "fix-record")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  IMPL_DIR="$TASK_PATH/implementation"

  rv_load_state "fix-record" "$unit_id"
  rv_require_step "fix-record" "$unit_id" "reviewed fixed"
  rv_load_review_record "fix-record" "$unit_id"

  local open_count rounds_used round_number
  open_count="$(rv_open_actionable_count "$RV_REVIEW_DOC")"
  [ "$open_count" -gt 0 ] 2>/dev/null \
    || die 53 "fix-record: $unit_id has no open actionable finding, so there was nothing for a fixer to do."
  rounds_used="$(printf '%s' "$RV_ORDER_ENTRY" | jq -r '.roundsUsed // 0')"
  case "$rounds_used" in ''|*[!0-9]*) rounds_used=0 ;; esac
  [ "$rounds_used" -lt "$FIX_ROUNDS_ALLOWED" ] \
    || die 54 "fix-record: $unit_id has already used $rounds_used of $FIX_ROUNDS_ALLOWED allowed fix rounds. Every open finding needs a ruling now, not another round."
  rv_require_round_verified "fix-record" "$unit_id" "$rounds_used"
  round_number=$((rounds_used + 1))

  # The report is the one the round's fix brief pins, the file dispatch-close read (gap row 250). A
  # report written elsewhere was never checked there, so it is refused. A brief from before the
  # key existed pins none.
  local pinned_report
  pinned_report="$(jq -r '.reportPath // ""' "$IMPL_DIR/brief-$unit_id-fix-$round_number.json" 2>/dev/null)"
  [ -z "$pinned_report" ] || [ "$report_path" -ef "$pinned_report" ] \
    || die 3 "fix-record: --report names $report_path, and the fix brief for round $round_number pins $pinned_report. The fixer writes its report there. Move the report there, or have the fixer write it there, then run fix-record again with that path."

  # Every --scope-insufficient is read and checked here, before a single check runs. A report that
  # names nothing open, or carries no reason, is a caller fault, and refusing it after the tools
  # have run would leave a fix record on disk that the ledger never learned about. What it changes
  # is applied further down, once the record itself is written.
  local scope_json="[]" scope_line scope_id scope_reason scope_open
  while IFS= read -r scope_line; do
    [ -n "$scope_line" ] || continue
    case "$scope_line" in
      *=*) ;;
      *) die 3 "fix-record: --scope-insufficient takes <finding id>=<reason>; got: $scope_line" ;;
    esac
    scope_id="${scope_line%%=*}"
    scope_reason="${scope_line#*=}"
    rv_is_finding_id "$scope_id" \
      || die 3 "fix-record: --scope-insufficient names '$scope_id'. A finding id is f and then digits, with no leading zero."
    [ -n "$scope_reason" ] \
      || die 3 "fix-record: --scope-insufficient for $scope_id carries no reason. A report with no reason is not a report."
    scope_open="$(printf '%s' "$RV_REVIEW_DOC" | jq -r --arg id "$scope_id" \
      '[ (.findings // [])[] | select(.id == $id and .actionable == true and .status == "open") ] | length')"
    [ "$scope_open" = "1" ] \
      || die 3 "fix-record: --scope-insufficient names $scope_id, which is not an open actionable finding on $unit_id."
    scope_json="$(printf '%s' "$scope_json" | jq -c --arg id "$scope_id" --arg reason "$scope_reason" \
      '. + [{id: $id, reason: $reason}]')"
  done <<RV_SCOPE
$scope_raw
RV_SCOPE

  rv_load_codepath "fix-record"
  rv_load_range_repo "fix-record" "$RV_UNIT_JSON"

  local started_at_full current_commit
  started_at_full="$(git -C "$RV_RANGE_REPO" rev-parse --verify --quiet "${started_at}^{commit}" 2>/dev/null)"
  [ -n "$started_at_full" ] \
    || die 43 "fix-record: --started-at ($started_at) is not a commit in $RV_RANGE_NAME at $RV_RANGE_REPO."
  current_commit="$(git -C "$RV_RANGE_REPO" rev-parse HEAD 2>/dev/null)"
  [ -n "$current_commit" ] \
    || die 3 "fix-record: could not capture the current commit (git rev-parse HEAD failed in $RV_RANGE_REPO)."
  br_require_real_base "fix-record" "$RV_RANGE_REPO" "$started_at" "$started_at_full" "$current_commit"

  # Exit 45, twice over. One round per commit: a second call at the commit a record already names
  # would spend a round on code nobody changed. The round number moves with the ledger, so the
  # duplicate is not always the same file: a caller who runs this twice writes round 1 and then
  # round 2, both at one commit. So this looks at the round it is about to write and at the round
  # before it, and refuses on either.
  local record_file="$IMPL_DIR/fix-$unit_id-$round_number.json"
  local prev_file existing_doc existing_commit
  # The ledger step a recorded round writes, in the crash repair and after the checks. On a light
  # task it also marks the order, so its cap stays one round in any later mode (gap row 296).
  local step_expr='.roundsUsed = (.roundsUsed + 1) | .lastStep = "fixed"'
  ! task_is_light "$TASK_PATH" || step_expr="$step_expr | .lightRounds = true"
  if [ -f "$record_file" ]; then
    existing_doc="$(jq -c '.' "$record_file" 2>/dev/null)"
    [ -n "$existing_doc" ] \
      || die 3 "fix-record: $record_file exists but could not be read as JSON. Repair or remove it by hand before running this again."
    existing_commit="$(printf '%s' "$existing_doc" | jq -r '.commit // empty')"
    if [ "$existing_commit" = "$current_commit" ]; then
      # A crash between this record and the ledger write leaves the round recorded and the counter
      # where it was, and the routing table has no row for that state. The record is this round own
      # at this commit, so the repair is to finish the write that did not land.
      local fr_step fr_ledger
      fr_step="$(printf '%s' "$RV_ORDER_ENTRY" | jq -r '.lastStep // ""')"
      if [ "$fr_step" != "fixed" ]; then
        fr_ledger="$(printf '%s' "$RV_LEDGER_DOC" | jq -c --arg id "$unit_id" \
          ".orders = (.orders | map(if .id == \$id then ($step_expr) else . end))")"
        [ -n "$fr_ledger" ] || die 3 "fix-record: the ledger update for $unit_id failed."
        write_atomic "$RV_LEDGER_FILE" "$fr_ledger"
        im_print_summary "fix-record" "$(printf '%s' "$existing_doc" | jq -c --arg record "$record_file" \
          --arg rounds "$round_number of $FIX_ROUNDS_ALLOWED" \
          --arg next "$(im_next_step "$fr_ledger" "$SNAPSHOT_DOC" "$IMPL_DIR" "true" "false")" '
          {order: .unit, round: $rounds, range: "\(.startedAt)..\(.commit)",
           check: ([ .checks[] | {id, verdict, detail: (.detail // "")} ]),
           executed: "\(.executed) of 7 ran a command, a diff or a hash",
           state: "fixed: the record was already written and the ledger had not moved, so no round was spent twice",
           halt: "none", record: $record, diff: .diffPath, next: $next}')"
        echo "FIX-RECORD: $record_file was already written at $current_commit and the ledger had not moved. The ledger now counts round $round_number; no round was spent twice." >&2
        exit 0
      fi
      die 45 "fix-record: $record_file already holds round $round_number at commit $current_commit. Nothing has changed since that record was written."
    fi
  fi
  if [ "$round_number" -gt 1 ]; then
    prev_file="$IMPL_DIR/fix-$unit_id-$((round_number - 1)).json"
    if [ -f "$prev_file" ]; then
      existing_doc="$(jq -c '.' "$prev_file" 2>/dev/null)"
      if [ -n "$existing_doc" ]; then
        existing_commit="$(printf '%s' "$existing_doc" | jq -r '.commit // empty')"
        [ "$existing_commit" = "$current_commit" ] \
          && die 45 "fix-record: $prev_file already holds round $((round_number - 1)) at commit $current_commit, so the code has not moved since that round. A round spent on unchanged code is a round nobody worked."
      fi
    fi
  fi

  local tests_file="$IMPL_DIR/tests-$unit_id.json" tests_doc
  [ -f "$tests_file" ] \
    || die 3 "fix-record: $tests_file not found, though a fix round implies tests-freeze already ran for $unit_id."
  tests_doc="$(jq -c '.' "$tests_file" 2>/dev/null)"
  [ -n "$tests_doc" ] \
    || die 3 "fix-record: $tests_file exists but could not be read as JSON. Repair or remove it by hand before running this again."

  br_require_clean_tree "fix-record" "$RV_RANGE_REPO" "$unit_id" "$RV_RUN_MODE" "$RV_LEDGER_FILE" "$RV_LEDGER_DOC" "$RV_RANGE_PATHS"

  BRC_WHO="fix-record"
  BRC_CODEPATH="$RV_RANGE_REPO"
  BRC_SCOPE="$RV_RANGE_SCOPE"
  BRC_STARTED_AT="$started_at_full"
  BRC_CURRENT="$current_commit"
  BRC_UNIT_JSON="$RV_UNIT_JSON"
  BRC_TESTS_DOC="$tests_doc"
  BRC_BASELINE_FILE="$IMPL_DIR/baseline.json"
  # The paths a person allowed for this round, from the brief fix-brief wrote for it. The
  # owned-files check reads them beside the order's own, so an allowed change passes (live-run
  # row 116). A round with no brief on disk allows nothing.
  BRC_ALLOWED_JSON="$(jq -c '.allowedFiles // []' "$IMPL_DIR/brief-$unit_id-fix-$round_number.json" 2>/dev/null)"
  [ -n "$BRC_ALLOWED_JSON" ] || BRC_ALLOWED_JSON="[]"
  local selected_tests_json
  selected_tests_json="$(br_frozen_test_paths "$(printf '%s' "$tests_doc" | jq -c '.rows // []')")"
  # shellcheck disable=SC2034 # read by the sourced library
  CR_WHO="fix-record"
  # shellcheck disable=SC2034 # read by the sourced library
  CR_TEST_RECIPES="$test_recipes"
  # shellcheck disable=SC2034 # read by the sourced library
  CR_CHECK_RECIPES="$check_recipes"
  cr_resolve
  cr_require_baseline_recipes "fix-record" "$IMPL_DIR/baseline.json"

  BRC_RECIPES="$CR_DOC"
  BRC_SELECTED_JSON="$selected_tests_json"
  BRC_VALUES="$values"
  BRC_NOTHING_RAN="$nothing_ran"
  BRC_HAVE_NOTHING_RAN="$have_nothing_ran"
  BRC_GATE_RECIPES="$gate_recipes"
  # The observed record the build step accepted, at the path it names (live-run row 104).
  BRC_OBSERVED="$IMPL_DIR/observed-$unit_id.json"

  # The checks travel by file to the record, the same as build-record (nyc defects 9 and 12).
  local seven_file checks_json
  br_require_gate_tokens
  br_require_site_up
  seven_file="$(mktemp)" || die 3 "fix-record: could not create a temporary file"
  br_seven_checks >"$seven_file"
  [ -s "$seven_file" ] \
    || { rm -f "$seven_file"; die 3 "fix-record: the seven computable checks produced nothing for $unit_id."; }
  br_require_check_count "fix-record" "$seven_file" 7
  checks_json="$(cat "$seven_file" 2>/dev/null)"

  local diff_path
  diff_path="$IMPL_DIR/diff-$unit_id-fix$round_number.patch"
  git_diff_of "$RV_RANGE_REPO" "$started_at_full" "$current_commit" "$RV_RANGE_SCOPE" > "$diff_path" \
    || { rm -f "$seven_file"; die 3 "fix-record: could not write the fix diff from $started_at_full to $current_commit into $diff_path."; }

  local today record_json executed_count
  executed_count="$(br_executed_count "$checks_json")"
  case "$executed_count" in ''|*[!0-9]*) executed_count=0 ;; esac
  today="$(date -u +%Y-%m-%d)"
  record_json="$(jq -c --arg takenAt "$today" --arg unit "$unit_id" --arg startedAt "$started_at_full" \
    --arg commit "$current_commit" --argjson round "$round_number" --arg reportPath "$report_path" \
    --arg diffPath "$diff_path" --argjson executed "$executed_count" '
    {
      schemaVersion: 1,
      takenAt: $takenAt,
      unit: $unit,
      startedAt: $startedAt,
      commit: $commit,
      round: $round,
      reportPath: $reportPath,
      diffPath: $diffPath,
      checks: .,
      executed: $executed,
      decidingChecks: { total: 8, ranHere: [ .[] | .id ] }
    }' "$seven_file")"
  rm -f "$seven_file"
  [ -n "$record_json" ] || die 3 "fix-record: could not assemble the record for $unit_id."
  write_atomic "$record_file" "$record_json"

  # A fixer does not widen its own scope. It reports instead, and the report is consumed here
  # (ideal/implementation.md, the unattended-answers table, "A fixer reporting its scope is too
  # small"). Interactive, the report is recorded on the finding and the skill puts it to the
  # person. Unattended, the order halts with the report as the reason, because widening a scope
  # with nobody present is the unbounded work this stage refuses. An earlier draft had nothing
  # consume it at all.
  local si sc_count sc_id sc_reason scope_list=""
  sc_count="$(printf '%s' "$scope_json" | jq 'length')"
  si=0
  while [ "$si" -lt "$sc_count" ]; do
    sc_id="$(printf '%s' "$scope_json" | jq -r --argjson i "$si" '.[$i].id')"
    sc_reason="$(printf '%s' "$scope_json" | jq -r --argjson i "$si" '.[$i].reason')"
    RV_REVIEW_DOC="$(printf '%s' "$RV_REVIEW_DOC" | jq -c --arg id "$sc_id" \
      --arg reason "$sc_reason" --argjson round "$round_number" '
      .findings = (.findings | map(if .id == $id then
        . + {scopeInsufficientInRound: $round, scopeInsufficientBecause: $reason} else . end))')"
    [ -n "$RV_REVIEW_DOC" ] || die 3 "fix-record: the scope report for $sc_id could not be recorded."
    scope_list="$scope_list$sc_id ($sc_reason), "
    si=$((si + 1))
  done
  if [ -n "$scope_list" ]; then
    write_atomic "$RV_REVIEW_FILE" "$RV_REVIEW_DOC"
  fi

  # A check answering unmet or unknown spends the round and leaves every finding open. There is no
  # interface-record here, so no unknown is exempt: that exemption belongs to a check this step
  # never runs. At the cap the order halts, naming the check that stopped it, at the moment the
  # fact becomes true rather than when the next brief refuses.
  # order-tests carries the same floor it carries at build-record: it must have run and answered
  # met. A fix round nothing executed proves nothing about the fix.
  local all_met first_stopper halt_why=""
  all_met="$(br_checks_pass "$checks_json" "")"
  first_stopper="$(br_first_stopper "$checks_json" "")"
  if [ "$RV_RUN_MODE" = "autonomous" ] && [ -n "$scope_list" ]; then
    halt_why="a fixer reported its scope too small and nobody is present to rule on it: ${scope_list%, }"
  fi
  # A check that stopped the round, at the cap too, does not halt here. verify-record opens a
  # finding for it, and the cap rules there decide: a ruling, a halt, or pending (gap row 305).
  local new_ledger
  new_ledger="$(printf '%s' "$RV_LEDGER_DOC" | jq -c --arg id "$unit_id" \
    ".orders = (.orders | map(if .id == \$id then ($step_expr) else . end))")"
  [ -n "$new_ledger" ] || die 3 "fix-record: the ledger update for $unit_id failed."
  if [ -n "$halt_why" ]; then
    new_ledger="$(halt_order_in "$new_ledger" "$unit_id" "$halt_why")"
    [ -n "$new_ledger" ] || die 3 "fix-record: the halt on $unit_id could not be written."
  fi
  write_atomic "$RV_LEDGER_FILE" "$new_ledger"

  local fr_state
  if [ "$all_met" = "true" ]; then fr_state="fixed"; else fr_state="fixed, every finding left open: stopped by $first_stopper"; fi
  im_print_summary "fix-record" "$(printf '%s' "$record_json" | jq -c --arg record "$record_file" \
    --arg rounds "$round_number of $FIX_ROUNDS_ALLOWED" --arg state "$fr_state" \
    --arg scope "${scope_list:-none}" --arg halt "${halt_why:-none}" \
    --arg next "$(im_next_step "$new_ledger" "$SNAPSHOT_DOC" "$IMPL_DIR" "true" "false")" '
    {order: .unit,
     round: $rounds,
     range: "\(.startedAt)..\(.commit)",
     check: ([ .checks[] | {id, verdict, detail: (.detail // "")} ]),
     executed: "\(.executed) of 7 ran a command, a diff or a hash",
     scopeInsufficient: ($scope | if endswith(", ") then .[0:-2] else . end),
     state: $state,
     halt: $halt,
     record: $record,
     diff: .diffPath,
     next: $next}')"
  if [ -n "$scope_list" ]; then
    echo "FIX-RECORD: the fixer reported its scope too small on ${scope_list%, }" >&2
  fi
  if [ "$all_met" != "true" ]; then
    echo "FIX-RECORD: round $round_number of $unit_id left every finding open. It was stopped by $first_stopper" >&2
  fi
  [ -z "$halt_why" ] || echo "FIX-RECORD: $unit_id is halted. $halt_why" >&2
  exit 0
}

# The compromises log row for the fix rounds a light task skips. close calls it for the findings
# the one round left, a failed check among them (gap row 305). $1 the order, $2 what was still
# open.
light_log_fix_rounds() {
  log_compromise "$TASK_PATH" implement "fix rounds after the first on $1, with $2 still open" \
    "run a second fix round, then take a person's ruling on each finding still open"
}

# ------------------------------------------------------------------------------------------------
# verify-brief: what the reviewer is given in verify mode, as a file. The open findings the fixer
# received, the fix diff as a path, the fixer's report as a path, and the path its verdicts go to.
# Nothing else: not the original diff, not an earlier round's verdicts (reviewer.md, verify mode).
# Before this action the skill body assembled that dispatch by hand from fix-brief's output and the
# fix record, which put both through the conversation.
# ------------------------------------------------------------------------------------------------

do_verify_brief() {
  [ "$#" -ge 2 ] || die 3 "verify-brief: a task folder and a unit id are required"
  [ "$#" -le 2 ] || die 3 "verify-brief: unrecognized extra argument: $3"
  local unit_id="$2" resolve_rc
  TASK_PATH="$(resolve_task_folder "$1" "verify-brief")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  IMPL_DIR="$TASK_PATH/implementation"

  rv_load_state "verify-brief" "$unit_id"
  rv_require_step "verify-brief" "$unit_id" "fixed"
  rv_load_review_record "verify-brief" "$unit_id"
  rv_load_codepath "verify-brief"

  local rounds_used already
  rounds_used="$(printf '%s' "$RV_ORDER_ENTRY" | jq -r '.roundsUsed // 0')"
  case "$rounds_used" in ''|*[!0-9]*) rounds_used=0 ;; esac
  [ "$rounds_used" -gt 0 ] 2>/dev/null \
    || die 3 "verify-brief: $unit_id records no fix round, though the ledger records it as fixed."
  # Exit 45: a round is verified once, so a brief for a round already verified would hand the
  # reviewer findings the first verification already closed.
  already="$(printf '%s' "$RV_REVIEW_DOC" | jq -r --argjson r "$rounds_used" \
    '[ (.rounds // [])[] | select(.round == $r) ] | length')"
  [ "$already" = "0" ] \
    || die 45 "verify-brief: round $rounds_used of $unit_id is already verified in $RV_REVIEW_FILE. There is nothing left to hand a verifier."

  local fix_file fix_doc
  fix_file="$IMPL_DIR/fix-$unit_id-$rounds_used.json"
  [ -f "$fix_file" ] \
    || die 3 "verify-brief: $fix_file not found, though the ledger records round $rounds_used of $unit_id. Run fix-record on it again."
  fix_doc="$(jq -c '.' "$fix_file" 2>/dev/null)"
  [ -n "$fix_doc" ] \
    || die 3 "verify-brief: $fix_file exists but could not be read as JSON. Repair or remove it by hand before running this again."

  # The open findings are the ones the fixer received: nothing has closed one since, because this
  # round's verification is what closes findings and it has not run. A scope report the fixer made
  # rides on the finding it names, so the verifier sees it beside the finding rather than in prose.
  # A check finding is left out: verify-record judges it from the fix record's checks (gap row 305).
  local open_json brief_file brief_json
  open_json="$(printf '%s' "$RV_REVIEW_DOC" | jq -c '
    [ (.findings // [])[] | select(.actionable == true and .status == "open" and .origin != "check") ]
    | sort_by(if .severity == "high" then 0 elif .severity == "medium" then 1 else 2 end)
    | map({id, severity, file, lines, linkedTo, evidence, fixScope, origin}
          + (if has("scopeInsufficientInRound") then {scopeInsufficientInRound, scopeInsufficientBecause} else {} end)
          + (if .origin == "repair" then {question: ("Does the cited failure arise in " + .file + "? Answer defectInFile yes or no.")} else {} end)
          + (if has("departureFrom") then {departureFrom, question: ("Is the departure from " + .departureFrom + " gone? Answer departureCured yes or no.")} else {} end))')"
  [ "$(rv_open_actionable_count "$RV_REVIEW_DOC")" -gt 0 ] 2>/dev/null \
    || die 53 "verify-brief: $unit_id has no open actionable finding, so there is nothing to verify."
  brief_file="$IMPL_DIR/brief-$unit_id-verify-$rounds_used.json"
  brief_json="$(jq -n --arg unit "$unit_id" --argjson round "$rounds_used" --argjson findings "$open_json" \
    --slurpfile fix "$fix_file" --arg fixRecord "$fix_file" \
    --arg verdictsPath "$IMPL_DIR/verify-$unit_id-$rounds_used.json" --arg worktree "$RV_CODEPATH" '
    $fix[0] as $fix
    | {unit: $unit,
     mode: "verify",
     worktree: $worktree,
     round: $round,
     findings: $findings,
     fixDiffPath: ($fix.diffPath // ""),
     fixReportPath: ($fix.reportPath // ""),
     fixRange: "\($fix.startedAt // "")..\($fix.commit // "")",
     fixRecord: $fixRecord,
     verdictsPath: $verdictsPath}')"
  [ -n "$brief_json" ] || die 3 "verify-brief: could not assemble the brief for $unit_id."
  write_atomic "$brief_file" "$brief_json"
  im_print_summary "verify-brief" "$(printf '%s' "$brief_json" | jq -c --arg brief "$brief_file" '
    {order: .unit,
     round: .round,
     brief: $brief,
     worktree: .worktree,
     fixDiff: .fixDiffPath,
     fixReport: .fixReportPath,
     verdictsPath: .verdictsPath,
     finding: ([ .findings[] | {id, severity, scope: (if has("scopeInsufficientInRound") then "scope reported insufficient" else "in scope" end)} ]),
     next: "dispatch reviewer in verify mode with the brief path, then verify-record with the verdicts path"}')"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# verify-record: one verdict per open finding, read against the fix diff only. Attempted is not
# addressed (ideal/implementation.md, "One fixer per round, verification per finding"). At the cap
# every still-open finding needs a ruling (decision 12).
# ------------------------------------------------------------------------------------------------

do_verify_record() {
  local task_arg="" unit_id="" verdicts_path="" rulings_raw=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --verdicts)
        [ "$#" -ge 2 ] || die 3 "verify-record: --verdicts needs a path to the file the verifier wrote"
        verdicts_path="$2"; shift 2 ;;
      --ruling)
        [ "$#" -ge 2 ] || die 3 "verify-record: --ruling needs <finding id>=<wrong|deferred|load-bearing|test-wrong>::<reason>"
        [ -n "$2" ] || die 3 "verify-record: --ruling was given an empty value."
        halt_refuse_separator "verify-record" "--ruling" "$2"
        rulings_raw="$rulings_raw$2
"
        shift 2 ;;
      -*) die 3 "verify-record: unrecognized argument: $1" ;;
      *)
        if [ -z "$task_arg" ]; then task_arg="$1"
        elif [ -z "$unit_id" ]; then unit_id="$1"
        else die 3 "verify-record: unrecognized extra argument: $1"; fi
        shift ;;
    esac
  done
  [ -n "$task_arg" ]      || die 3 "verify-record: a task folder is required"
  [ -n "$unit_id" ]       || die 3 "verify-record: a unit id is required"
  [ -n "$verdicts_path" ] || [ -n "$rulings_raw" ] \
    || die 3 "verify-record: --verdicts is required to record a round. On a round already on the record, --ruling alone rules on its open findings."

  local resolve_rc
  TASK_PATH="$(resolve_task_folder "$task_arg" "verify-record")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  IMPL_DIR="$TASK_PATH/implementation"

  rv_load_state "verify-record" "$unit_id"
  # Rulings alone also follow `reviewed`, before any round, for a finding with an empty fix scope
  # (gap row 265). rv_apply_rulings refuses any other finding there.
  if [ -n "$rulings_raw" ] && [ -z "$verdicts_path" ]; then
    rv_require_step "verify-record" "$unit_id" "reviewed fixed"
  else
    rv_require_step "verify-record" "$unit_id" "fixed"
  fi
  rv_load_review_record "verify-record" "$unit_id"

  local rounds_used
  rounds_used="$(printf '%s' "$RV_ORDER_ENTRY" | jq -r '.roundsUsed // 0')"
  case "$rounds_used" in ''|*[!0-9]*) rounds_used=0 ;; esac
  [ "$rounds_used" -gt 0 ] 2>/dev/null || [ "$(printf '%s' "$RV_ORDER_ENTRY" | jq -r '.lastStep')" = "reviewed" ] \
    || die 3 "verify-record: $unit_id records no fix round, though the ledger records it as fixed."

  # Exit 55: a ruling is a person's judgement. An unattended run has none to offer, so it refuses
  # the flag outright rather than recording a model's own word as a person's (decision 12). Read
  # before the round is looked up, so a ruling on a round already recorded meets the same refusal.
  if [ -n "$rulings_raw" ] && [ "$RV_RUN_MODE" = "autonomous" ]; then
    die 55 "verify-record: this run is unattended, and a ruling is a person's judgement. Nothing here may rule on an open finding."
  fi

  # Exit 45: a round is verified once. A second verification of the same round would record a
  # second set of verdicts over findings the first set already closed.
  local already ruled_doc ruled_ledger
  already="$(printf '%s' "$RV_REVIEW_DOC" | jq -r --argjson r "$rounds_used" \
    '[ (.rounds // [])[] | select(.round == $r) ] | length')"
  if [ "$already" != "0" ] && [ -z "$rulings_raw" ]; then
    # The verification is already on the record. rv_write_verification writes the review record and
    # then the ledger, so a crash between the two leaves this state with the ledger unmoved. There
    # is nothing left to verify and nothing to write twice, so this reports the record it found.
    rv_print_verification "$rounds_used" "verified: round $rounds_used was already on the record, so nothing was verified twice" "none"
    echo "VERIFY-RECORD: round $rounds_used of $unit_id is already verified in $RV_REVIEW_FILE. Nothing was verified twice." >&2
    exit 0
  fi
  if [ "$already" != "0" ] || [ "$rounds_used" = "0" ]; then
    # A ruling after the round is on the record (live-run row 111). The round's verdicts stand,
    # and the rulings land on its open findings through the gates the first-call path uses. No
    # second round entry is written, so roundsUsed and lastStep do not move. A --verdicts file
    # given here is not read. The person who re-ran the whole command with the rulings added is
    # told so below, not sent back. Round 0 is a ruling at `reviewed`, before any round.
    rv_apply_rulings "$unit_id" "$(printf '%s' "$RV_REVIEW_DOC" | jq -c '.findings // []')" "$rounds_used" "$rulings_raw"
    ruled_doc="$(printf '%s' "$RV_REVIEW_DOC" | jq -c --argjson f "$RV_RULED_FINDINGS" '.findings = $f')"
    [ -n "$ruled_doc" ] || die 3 "verify-record: the review record update for $unit_id failed."
    write_atomic "$RV_REVIEW_FILE" "$ruled_doc"
    RV_REVIEW_DOC="$ruled_doc"
    if [ -n "$RV_RULING_HALT" ]; then
      ruled_ledger="$(halt_order_in "$RV_LEDGER_DOC" "$unit_id" "$RV_RULING_HALT")"
      [ -n "$ruled_ledger" ] || die 3 "verify-record: the halt on $unit_id could not be written."
      write_atomic "$RV_LEDGER_FILE" "$ruled_ledger"
      RV_LEDGER_DOC="$ruled_ledger"
    fi
    if [ "$rounds_used" = "0" ]; then
      rv_print_verification 0 "ruled before any fix round, because no round can change a finding with an empty fix scope" "${RV_RULING_HALT:-none}"
    else
      rv_print_verification "$rounds_used" "verified: round $rounds_used was already on the record, so its verdicts stand and the rulings were applied" "${RV_RULING_HALT:-none}"
    fi
    [ -z "$verdicts_path" ] || echo "verdicts: ignored, round $rounds_used was already on the record and its verdicts stand"
    [ -z "$RV_RULING_HALT" ] || echo "VERIFY-RECORD: $unit_id is halted. $RV_RULING_HALT" >&2
    exit 0
  fi
  [ -n "$verdicts_path" ] \
    || die 3 "verify-record: --verdicts is required. Round $rounds_used of $unit_id is not on the record yet, and --ruling alone rules only on a round already verified."

  local fix_file
  fix_file="$IMPL_DIR/fix-$unit_id-$rounds_used.json"
  [ -f "$fix_file" ] \
    || die 3 "verify-record: $fix_file not found, though the ledger records round $rounds_used of $unit_id. Run fix-record on it again."

  local verdicts_doc verdict_rows breakage_rows outofscope_json
  [ -f "$verdicts_path" ] || die 52 "verify-record: $verdicts_path not found. The file named on the command line has to exist."
  [ -s "$verdicts_path" ] || die 52 "verify-record: $verdicts_path is empty."
  rv_refuse_duplicate_keys "$verdicts_path" "verify-record"
  verdicts_doc="$(jq -c '.' "$verdicts_path" 2>/dev/null)"
  [ -n "$verdicts_doc" ] || die 52 "verify-record: $verdicts_path is not valid JSON."
  verdict_rows="$(printf '%s' "$verdicts_doc" | jq -c 'if (.verdicts | type) == "array" then .verdicts else null end')"
  [ -n "$verdict_rows" ] && [ "$verdict_rows" != "null" ] \
    || die 52 "verify-record: $verdicts_path holds no verdicts array. The shape is { \"verdicts\": [ ... ] }."
  outofscope_json="$(printf '%s' "$verdicts_doc" | jq -c 'if (.outOfScope | type) == "array" then .outOfScope else [] end')"
  breakage_rows='[]'
  if [ "$(printf '%s' "$verdicts_doc" | jq -r 'if (.newBreakage | type) == "array" then "yes" else "no" end')" = "yes" ]; then
    rv_read_findings_array "$verdicts_path" "newBreakage" "verify-record" minted
    breakage_rows="$RV_FINDINGS_ARRAY"
  fi

  # Exit 58: the verdict list and the open findings have to correspond, both ways. Every open
  # actionable finding needs one verdict, and a verdict about anything else is a verifier reading
  # a list this order does not hold.
  local open_ids verdict_ids missing extra vcount vi vrow vid vverdict vorigin vfrom
  open_ids="$(printf '%s' "$RV_REVIEW_DOC" | jq -c \
    '[ (.findings // [])[] | select(.actionable == true and .status == "open" and .origin != "check") | .id ]')"
  vcount="$(printf '%s' "$verdict_rows" | jq 'length')"
  vi=0
  while [ "$vi" -lt "$vcount" ]; do
    vrow="$(printf '%s' "$verdict_rows" | jq -c --argjson i "$vi" '.[$i]')"
    vid="$(printf '%s' "$vrow" | jq -r '.id // ""')"
    vverdict="$(printf '%s' "$vrow" | jq -r '.verdict // ""')"
    [ -n "$vid" ] || die 52 "verify-record: a verdict in $verdicts_path names no finding id."
    rv_is_finding_id "$vid" \
      || die 52 "verify-record: a verdict in $verdicts_path names '$vid'. A finding id is f and then digits, with no leading zero."
    case "$vverdict" in
      addressed|not-addressed) ;;
      *) die 52 "verify-record: the verdict for $vid is '$vverdict'. The two words are addressed and not-addressed." ;;
    esac
    # A repair finding rests on the stopped builder's word that the failure lies in that file.
    # The verifier answers that too, and a no waits for the person (gap row 286).
    vorigin="$(printf '%s' "$RV_REVIEW_DOC" | jq -r --arg id "$vid" '[ (.findings // [])[] | select(.id == $id) ][0].origin // ""')"
    if [ "$vorigin" = "repair" ]; then
      case "$(printf '%s' "$vrow" | jq -r '.defectInFile // ""')" in
        yes|no) ;;
        *) die 52 "verify-record: $vid is a repair finding, and its verdict has no defectInFile. Answer yes or no: does the cited failure arise in $(printf '%s' "$RV_REVIEW_DOC" | jq -r --arg id "$vid" '[ .findings[] | select(.id == $id) ][0].file')?" ;;
      esac
    fi
    # A finding paired with a recipe departure is addressed only when the departure is gone, and a
    # no waits for the person (gap row 303).
    vfrom="$(printf '%s' "$RV_REVIEW_DOC" | jq -r --arg id "$vid" '[ (.findings // [])[] | select(.id == $id) ][0].departureFrom // ""')"
    if [ -n "$vfrom" ]; then
      case "$(printf '%s' "$vrow" | jq -r '.departureCured // ""')" in
        yes|no) ;;
        *) die 52 "verify-record: $vid cures a departure from $vfrom, and its verdict has no departureCured. Answer yes or no: is the departure from $vfrom gone?" ;;
      esac
    fi
    vi=$((vi + 1))
  done
  verdict_ids="$(printf '%s' "$verdict_rows" | jq -c '[ .[].id ]')"
  local dup_verdicts
  dup_verdicts="$(printf '%s' "$verdict_ids" | jq -r 'group_by(.) | map(select(length > 1) | .[0]) | join(", ")')"
  [ -z "$dup_verdicts" ] \
    || die 58 "verify-record: $verdicts_path carries more than one verdict for: $dup_verdicts. Each open finding gets one verdict."
  missing="$(jq -rn --argjson o "$open_ids" --argjson v "$verdict_ids" '[ $o[] | select(. as $x | $v | index($x) | not) ] | join(", ")')"
  extra="$(jq -rn --argjson o "$open_ids" --argjson v "$verdict_ids" '[ $v[] | select(. as $x | $o | index($x) | not) ] | join(", ")')"
  [ -z "$missing" ] \
    || die 58 "verify-record: these open findings have no verdict in $verdicts_path: $missing. Every open finding needs one."
  [ -z "$extra" ] \
    || die 58 "verify-record: these verdicts in $verdicts_path name nothing open on $unit_id: $extra."

  # Addressed closes the finding. Not addressed keeps it open, and attempted is not addressed.
  local updated_findings
  updated_findings="$(printf '%s' "$RV_REVIEW_DOC" | jq -c --argjson v "$verdict_rows" --argjson r "$rounds_used" '
    .findings | map(
      . as $f
      | ([ $v[] | select(.id == $f.id) ] | .[0]) as $row
      | if $row == null then $f
        elif $row.defectInFile == "no" then
          $f + { status: "pending", defectInFile: "no",
                 pendingBecause: ("the verifier answered that the failure does not arise in " + $f.file + ": " + ($row.evidence // "")) }
        elif $row.departureCured == "no" then
          $f + { status: "pending", departureCured: "no",
                 pendingBecause: ("the verifier answered that the departure from " + $f.departureFrom + " is not gone: " + ($row.evidence // "")) }
        elif $row.verdict == "addressed" then
          $f + (if $row.defectInFile then {defectInFile: $row.defectInFile} else {} end)
          + (if $row.departureCured then {departureCured: $row.departureCured} else {} end)
          + { status: "addressed", addressedInRound: $r,
                 addressedEvidence: ($row.evidence // ""),
                 addressedFile: ($row.file // ""), addressedLines: ($row.lines // "") }
        else $f end
    )')"

  # newBreakage is appended as new findings, actionable by the same rule, and counts as open.
  # Anything the verifier noticed outside the fix diff is recorded in outOfScope and opens nothing.
  local alignment bcount bi braw bbuilt next_n new_id breakage_ids
  alignment="$(printf '%s' "$SNAPSHOT_DOC" | jq -c '.alignment // {}')"
  breakage_ids='[]'
  bcount="$(printf '%s' "$breakage_rows" | jq 'length')"
  bi=0
  while [ "$bi" -lt "$bcount" ]; do
    braw="$(printf '%s' "$breakage_rows" | jq -c --argjson i "$bi" '.[$i]')"
    # A new id is minted here rather than taken from the file: the verifier numbers its own list
    # from f1 and would collide with the review's own ids.
    next_n="$(printf '%s' "$updated_findings" | jq '[ .[] | .id | ltrimstr("f") | tonumber? // 0 ] | max // 0 | . + 1')"
    new_id="f$next_n"
    braw="$(printf '%s' "$braw" | jq -c --arg id "$new_id" '.id = $id')"
    bbuilt="$(rv_finding_record "$braw" "$alignment" "round$rounds_used")"
    updated_findings="$(printf '%s' "$updated_findings" | jq -c --argjson f "$bbuilt" '. + [$f]')"
    breakage_ids="$(printf '%s' "$breakage_ids" | jq -c --arg id "$new_id" '. + [$id]')"
    bi=$((bi + 1))
  done

  # Gap row 305. A check that stopped this round opens one finding, origin check, on the order's
  # first criterion and its owned files. Every other finding may read addressed, and then nothing
  # open would route the failed check. The cap rules apply to it. Its severity is low when
  # coding-standards alone stopped the round, a style line, and medium for any other check, so a
  # light task's cap leaves only a style failure for the review. The script, not the verifier,
  # judges it: a round whose checks pass addresses it, and one that fails again keeps it open.
  local fix_checks check_stop check_severity
  fix_checks="$(jq -c '.checks // []' "$fix_file" 2>/dev/null)"
  if [ "$(br_checks_pass "${fix_checks:-[]}" "")" = "true" ]; then
    updated_findings="$(printf '%s' "$updated_findings" | jq -c --argjson r "$rounds_used" --arg f "$fix_file" '
      map(if .origin == "check" and .status == "open"
          then . + {status: "addressed", addressedInRound: $r, addressedEvidence: ("every check passed in " + $f)}
          else . end)')"
  elif [ "$(printf '%s' "$updated_findings" | jq '[ .[] | select(.origin == "check" and .status == "open") ] | length')" = "0" ]; then
    check_stop="$(br_first_stopper "${fix_checks:-[]}" "")"
    check_severity="$(printf '%s' "${fix_checks:-[]}" | jq -r "$BR_STOPPERS_JQ"'
      if (stoppers | length > 0) and (stoppers - ["coding-standards"] | length == 0) then "low" else "medium" end')"
    new_id="f$(printf '%s' "$updated_findings" | jq '[ .[] | .id | ltrimstr("f") | tonumber? // 0 ] | max // 0 | . + 1')"
    braw="$(printf '%s' "$RV_UNIT_JSON" | jq -c --arg id "$new_id" --arg severity "$check_severity" \
      --arg evidence "fix round $rounds_used of $unit_id was stopped by its check $check_stop" '
      {id: $id, severity: $severity, file: "", lines: "",
       linkedTo: (((.criteriaOwned // []) + (.criteriaServed // []))[0] // ""),
       evidence: $evidence, fixScope: (.ownedFiles // [])}')"
    bbuilt="$(rv_finding_record "$braw" "$alignment" check)"
    updated_findings="$(printf '%s' "$updated_findings" | jq -c --argjson f "$bbuilt" '. + [$f]')"
    echo "VERIFY-RECORD: $new_id opens for the check that stopped round $rounds_used: $check_stop" >&2
  fi

  # Decision 11 again, and for the same reason: a new finding that hits a non-goal is the same
  # fact as one the review raised, and an unattended run has nobody to rule on either.
  local nongoal_hits
  nongoal_hits="$(rv_nongoal_hits "$(printf '%s' "$updated_findings" | jq -c --argjson ids "$breakage_ids" '[ .[] | select(.id as $i | $ids | index($i)) ]')" "$alignment")"

  # Decision 12: the rulings, through the helper the already-verified path shares. The syntax
  # loop, the two gates and the per-ruling loop live there.
  rv_apply_rulings "$unit_id" "$updated_findings" "$rounds_used" "$rulings_raw"
  updated_findings="$RV_RULED_FINDINGS"
  # Gap row 279. Unattended at the cap, a finding with an empty fix scope waits for the task
  # review as fix-brief marks it, so only a finding with a fix scope still halts the order. On a
  # light task a low finding waits there too, so a low leftover does not call a person mid-build.
  # A medium or high one still halts: later orders would build on a real defect. close logs the
  # skipped rounds (gap row 296).
  if [ "$rounds_used" -ge "$FIX_ROUNDS_ALLOWED" ] && [ "$RV_RUN_MODE" = "autonomous" ]; then
    local light=false
    ! task_is_light "$TASK_PATH" || light=true
    updated_findings="$(printf '%s' "$updated_findings" | jq -c --argjson light "$light" '
      map(if .actionable == true and .status == "open" and (($light and .severity == "low") or ((.fixScope // []) | length == 0)) then .status = "pending" else . end)')"
  fi
  local open_now unruled
  open_now="$(printf '%s' "$updated_findings" | jq '[ .[] | select(.actionable == true and .status == "open") ] | length')"
  if [ "$rounds_used" -ge "$FIX_ROUNDS_ALLOWED" ] && [ "$open_now" -gt 0 ] 2>/dev/null && [ "$RV_RUN_MODE" = "autonomous" ]; then
    local open_list
    open_list="$(printf '%s' "$updated_findings" | jq -r '[ .[] | select(.actionable == true and .status == "open") | .id ] | join(", ")')"
    rv_write_verification "$unit_id" "$updated_findings" "$rounds_used" "$verdict_rows" "$breakage_ids" "$outofscope_json" "$fix_file" \
      "a fix round cap reached with findings still open, and nobody is present to rule on them: $open_list"
    echo "VERIFY-RECORD: $unit_id is halted. The fix rounds are spent and these findings are still open: $open_list" >&2
    die 56 "verify-record: this run is unattended, the fix rounds are spent, and these findings are still open: $open_list."
  fi
  if [ "$rounds_used" -ge "$FIX_ROUNDS_ALLOWED" ]; then
    unruled="$(printf '%s' "$updated_findings" | jq -r \
      '[ .[] | select(.actionable == true and .status == "open") | .id ] | join(", ")')"
    [ -z "$unruled" ] \
      || die 57 "verify-record: the fix rounds are spent and these findings have no ruling: $unruled. Each one needs --ruling <id>=<wrong|deferred|load-bearing|test-wrong>::<reason>."
  fi

  local halt_why=""
  if [ "$RV_RUN_MODE" = "autonomous" ] && [ -n "$nongoal_hits" ]; then
    halt_why="a finding hits a non-goal and nobody is present to rule on it: $nongoal_hits"
  elif [ -n "$RV_RULING_HALT" ]; then
    halt_why="$RV_RULING_HALT"
  fi
  rv_write_verification "$unit_id" "$updated_findings" "$rounds_used" "$verdict_rows" "$breakage_ids" "$outofscope_json" "$fix_file" "$halt_why"

  rv_print_verification "$rounds_used" "verified" "${halt_why:-none}"
  [ -z "$halt_why" ] || echo "VERIFY-RECORD: $unit_id is halted. $halt_why" >&2
  exit 0
}

# Decision 12: the rulings, on the round's findings. Shared by verify-record's two paths: the call
# that records the round, and the call on a round already on the record (live-run row 111). So
# both hold the same gates in the same words. A ruling's own syntax is read first, before
# anything asks whether a ruling is allowed yet. A malformed one is then refused for what is
# wrong with it, whatever the round. Refusing it for its timing instead sends the caller to fix
# the round rather than the text. Then the before-the-cap gate, the nothing-left gate, and each
# ruling landing on its finding. The unattended refusal (exit 55) is the caller's, read before
# the round is looked up. $1 unit, $2 the findings array, $3 the round, $4 the raw --ruling
# values, one per line. Sets RV_RULED_FINDINGS and RV_RULING_HALT, empty when nothing halts.
RV_RULED_FINDINGS=""; RV_RULING_HALT=""
rv_apply_rulings() {
  local unit_id="$1" updated_findings="$2" rounds_used="$3" rulings_raw="$4"
  local open_now ruling_halt="" rulings_json="[]"
  open_now="$(printf '%s' "$updated_findings" | jq '[ .[] | select(.actionable == true and .status == "open") ] | length')"
  local rline rid rrest rverdict rreason rulable_now early_ok early_ids rcount ri is_open
  while IFS= read -r rline; do
    [ -n "$rline" ] || continue
    case "$rline" in
      *=*::*) ;;
      *) die 3 "verify-record: --ruling takes <finding id>=<wrong|deferred|load-bearing|test-wrong>::<reason>; got: $rline" ;;
    esac
    rid="${rline%%=*}"
    rrest="${rline#*=}"
    rverdict="${rrest%%::*}"
    rreason="${rrest#*::}"
    rv_is_finding_id "$rid" \
      || die 3 "verify-record: --ruling names '$rid'. A finding id is f and then digits, with no leading zero."
    case "$rverdict" in
      wrong|deferred|load-bearing|test-wrong) ;;
      *) die 3 "verify-record: the ruling for $rid is '$rverdict'. The four words are wrong, deferred, load-bearing and test-wrong." ;;
    esac
    [ -n "$rreason" ] || die 3 "verify-record: the ruling for $rid carries no reason. A ruling with no reason is not a ruling."
    rulings_json="$(printf '%s' "$rulings_json" | jq -c --arg id "$rid" --arg ruling "$rverdict" \
      --arg reason "$rreason" '. + [{id: $id, ruling: $ruling, reason: $reason}]')"
  done <<RV_RULINGS
$rulings_raw
RV_RULINGS

  # Before the cap, a ruling is taken on two kinds of finding alone. One a fixer reported out of
  # its scope, which fix-record marked scopeInsufficientInRound: the fixer's own report is the
  # evidence that no round can reach it, so a second dispatch bought to hear it again is spent on
  # nothing (live-run row 110). And one whose fix scope is empty: it asks for no code change, so
  # no round can reach it either (gap row 265). Any other finding waits for the cap, as before.
  rulable_now="$(printf '%s' "$updated_findings" | jq -r \
    '[ .[] | select(.actionable == true and .status == "open" and (has("scopeInsufficientInRound") or ((.fixScope // []) | length == 0))) | .id ] | join(", ")')"
  if [ -n "$rulings_raw" ] && [ "$rounds_used" -lt "$FIX_ROUNDS_ALLOWED" ]; then
    early_ids="$(printf '%s' "$rulings_json" | jq -r '[ .[].id ] | join(", ")')"
    early_ok="$(printf '%s' "$updated_findings" | jq -r --argjson r "$rulings_json" \
      '[ $r[].id ] as $ids | [ .[] | select((has("scopeInsufficientInRound") or ((.fixScope // []) | length == 0)) and (.id as $i | $ids | index($i))) | .id ] | length == ($ids | length)')"
    if [ "$early_ok" != "true" ]; then
      if [ -n "$rulable_now" ]; then
        die 3 "verify-record: a ruling is taken only after the last allowed round. $unit_id has used $rounds_used of $FIX_ROUNDS_ALLOWED, so another round is still available. These findings may be ruled now, because a fixer reported them out of its scope or their fix scope is empty: $rulable_now. The ruling named: $early_ids."
      fi
      die 3 "verify-record: a ruling is taken only after the last allowed round. $unit_id has used $rounds_used of $FIX_ROUNDS_ALLOWED, so another round is still available. No finding may be ruled now: no fixer has reported one out of its scope, and none has an empty fix scope."
    fi
  fi
  # A ruling with nothing left to rule on is refused rather than dropped. A caller who wrote one
  # believes a finding is still open, and silence would let that belief stand.
  if [ -n "$rulings_raw" ] && [ "$open_now" = "0" ]; then
    die 3 "verify-record: a --ruling was given and $unit_id has no open actionable finding left to rule on."
  fi
  # Each ruling lands on its finding. `test-wrong` halts the way `load-bearing` does, and its
  # reason begins `test wrong:` because `retake-tests` and `clear-halt` read the front of it; it
  # takes the halt over a load-bearing ruling in the same call, since the retake moves the review
  # record aside and the load-bearing finding is ruled again after the rebuild.
  rcount="$(printf '%s' "$rulings_json" | jq 'length')"
  ri=0
  while [ "$ri" -lt "$rcount" ]; do
    rid="$(printf '%s' "$rulings_json" | jq -r --argjson i "$ri" '.[$i].id')"
    rverdict="$(printf '%s' "$rulings_json" | jq -r --argjson i "$ri" '.[$i].ruling')"
    rreason="$(printf '%s' "$rulings_json" | jq -r --argjson i "$ri" '.[$i].reason')"
    is_open="$(printf '%s' "$updated_findings" | jq -r --arg id "$rid" \
      '[ .[] | select(.id == $id and .actionable == true and .status == "open") ] | length')"
    [ "$is_open" = "1" ] \
      || die 3 "verify-record: --ruling names $rid, which is not an open actionable finding on $unit_id."
    updated_findings="$(printf '%s' "$updated_findings" | jq -c --arg id "$rid" \
      --arg ruling "$rverdict" --arg reason "$rreason" '
      map(if .id == $id then . + {status: "ruled", ruling: $ruling, rulingReason: $reason} else . end)')"
    case "$rverdict" in
      test-wrong) ruling_halt="test wrong: $rid: $rreason" ;;
      load-bearing)
        case "$ruling_halt" in
          "test wrong: "*) ;;
          *) ruling_halt="$rid is ruled real and load-bearing: $rreason" ;;
        esac ;;
    esac
    ri=$((ri + 1))
  done
  RV_RULED_FINDINGS="$updated_findings"
  RV_RULING_HALT="$ruling_halt"
}

# The verify-record summary, from the review record as it now stands: one line per verdict this
# round wrote, the new breakage it opened, what it noted outside the diff, the rulings, and what is
# still open. Evidence stays in the record. $1 the round, $2 the state line, $3 the halt or "none".
# Shared by the ordinary exit and the already-verified one, so the two print the same lines.
rv_print_verification() {
  local round="$1" state="$2" halt="$3"
  im_print_summary "verify-record" "$(printf '%s' "$RV_REVIEW_DOC" | jq -c --argjson round "$round" \
    --arg state "$state" --arg halt "$halt" --arg record "$RV_REVIEW_FILE" \
    --arg rounds "$round of $FIX_ROUNDS_ALLOWED" \
    --arg next "$(im_next_step "$RV_LEDGER_DOC" "$SNAPSHOT_DOC" "$IMPL_DIR" "true" "false")" '
    ([ (.rounds // [])[] | select(.round == $round) ] | .[0] // {}) as $r
    | {order: .unit,
       round: $rounds,
       addressed: ($r.addressed // []),
       notAddressed: ($r.notAddressed // []),
       newBreakage: ($r.newBreakage // []),
       outOfScope: (($r.outOfScope // []) | length),
       ruling: ([ .findings[] | select(.status == "ruled") | {id, ruling} ]),
       openActionable: ([ .findings[] | select(.actionable == true and .status == "open") | .id ]),
       state: $state,
       halt: $halt,
       record: $record,
       next: $next}')"
}

# Writes the verified review record and moves the ledger. Shared by verify-record's two exits, the
# ordinary one and the unattended refusal at the cap, so a refusal never leaves the verification
# it already did unrecorded. $1 unit, $2 the findings array, $3 the round, $4 the verdict rows,
# $5 the new finding ids, $6 outOfScope, $7 the fix record path, $8 a halt reason or empty.
rv_write_verification() {
  local unit_id="$1" findings="$2" round="$3" verdicts="$4" breakage="$5" outofscope="$6" fix_file="$7" halt_why="$8"
  local round_entry new_doc step_expr new_ledger
  round_entry="$(jq -n --argjson round "$round" --arg fixRecord "$fix_file" \
    --argjson verdicts "$verdicts" --argjson newBreakage "$breakage" --argjson outOfScope "$outofscope" '
    {
      round: $round,
      fixRecord: $fixRecord,
      addressed: [ $verdicts[] | select(.verdict == "addressed") | .id ],
      notAddressed: [ $verdicts[] | select(.verdict == "not-addressed") | .id ],
      newBreakage: $newBreakage,
      outOfScope: $outOfScope
    }')"
  new_doc="$(printf '%s' "$RV_REVIEW_DOC" | jq -c --argjson f "$findings" --argjson r "$round_entry" \
    '.findings = $f | .rounds = ((.rounds // []) + [$r])')"
  [ -n "$new_doc" ] || die 3 "verify-record: the review record update for $unit_id failed."
  write_atomic "$RV_REVIEW_FILE" "$new_doc"
  RV_REVIEW_DOC="$new_doc"

  step_expr='.lastStep = "fixed"'
  new_ledger="$(printf '%s' "$RV_LEDGER_DOC" | jq -c --arg id "$unit_id" \
    ".orders = (.orders | map(if .id == \$id then ($step_expr) else . end))")"
  [ -n "$new_ledger" ] || die 3 "verify-record: the ledger update for $unit_id failed."
  if [ -n "$halt_why" ]; then
    new_ledger="$(halt_order_in "$new_ledger" "$unit_id" "$halt_why")"
    [ -n "$new_ledger" ] || die 3 "verify-record: the halt on $unit_id could not be written."
  fi
  write_atomic "$RV_LEDGER_FILE" "$new_ledger"
  RV_LEDGER_DOC="$new_ledger"
}

# ------------------------------------------------------------------------------------------------
# close: the order is done, the ledger says what it produced, and every criterion this order serves
# is decided here, because a criterion split across orders is answered once, by the last of them.
# ------------------------------------------------------------------------------------------------

do_close() {
  [ "$#" -ge 2 ] || die 3 "close: a task folder and a unit id are required"
  [ "$#" -le 2 ] || die 3 "close: unrecognized extra argument: $3"
  local unit_id="$2" resolve_rc
  TASK_PATH="$(resolve_task_folder "$1" "close")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  IMPL_DIR="$TASK_PATH/implementation"

  rv_load_state "close" "$unit_id"
  rv_require_step "close" "$unit_id" "reviewed fixed"
  rv_load_review_record "close" "$unit_id"

  local open_count
  open_count="$(rv_open_actionable_count "$RV_REVIEW_DOC")"
  [ "$open_count" = "0" ] \
    || die 59 "close: $unit_id has $open_count open actionable finding(s). An order closes with nothing open."

  # Exit 60: a fix round that nobody verified is a round whose findings were marked addressed by
  # the fixer's own account, which this stage never takes as authority.
  local last_step rounds_used verified_round
  last_step="$(printf '%s' "$RV_ORDER_ENTRY" | jq -r '.lastStep // ""')"
  rounds_used="$(printf '%s' "$RV_ORDER_ENTRY" | jq -r '.roundsUsed // 0')"
  case "$rounds_used" in ''|*[!0-9]*) rounds_used=0 ;; esac
  if [ "$last_step" = "fixed" ]; then
    verified_round="$(printf '%s' "$RV_REVIEW_DOC" | jq -r '[ (.rounds // [])[] | .round ] | max // 0')"
    [ "$verified_round" = "$rounds_used" ] \
      || die 60 "close: $unit_id has used $rounds_used fix round(s) and the last one verified is $verified_round. A round closes only after verify-record reads it."
  fi

  rv_load_build_record "close" "$unit_id"
  rv_load_codepath "close"
  rv_load_range_repo "close" "$RV_UNIT_JSON"

  local started_at head_now
  rv_load_order_start "close" "$unit_id"
  started_at="$RV_ORDER_START"
  head_now="$(git -C "$RV_RANGE_REPO" rev-parse HEAD 2>/dev/null)"
  [ -n "$head_now" ] \
    || die 3 "close: could not capture the current commit (git rev-parse HEAD failed in $RV_RANGE_REPO)."

  # A range holds every commit between its ends. When another order's commit sits between two of
  # this order's attempts, the range starts after the last such commit, so it names none of that
  # order's work. The earlier commits of this order are printed, not recorded (gap row 222).
  local close_commits last_other earlier_own=""
  if [ -z "$RV_RANGE_SCOPE" ]; then
    close_commits="$(im_order_commits "$RV_RANGE_REPO" "$started_at" "$head_now" "$RV_UNIT_JSON" "$IMPL_DIR")"
    last_other="$(printf '%s\n' "$close_commits" | sed -n 's/^other //p' | tail -1)"
    if [ -n "$last_other" ]; then
      earlier_own="$(printf '%s\n' "$close_commits" | sed -n "/^other $last_other\$/q;s/^own //p" \
        | cut -c1-12 | tr '\n' ' ')"
      started_at="$last_other"
    fi
  fi

  # Exit 61 and exit 63. Close writes the commit range this order produced, and a range is a claim
  # about what is in the repository. So the tree has to be clean, and HEAD has to be the commit the
  # last record for this order was written at: the build record when no round ran, the last fix
  # record otherwise. Without both, the range names commits that do not hold the work, which is the
  # same gap the record steps close with exit 61.
  br_require_clean_tree "close" "$RV_RANGE_REPO" "" "" "" "" "$RV_RANGE_PATHS"
  local last_record last_commit
  if [ "$rounds_used" -gt 0 ] 2>/dev/null; then
    last_record="$IMPL_DIR/fix-$unit_id-$rounds_used.json"
  else
    last_record="$IMPL_DIR/build-$unit_id.json"
  fi
  [ -f "$last_record" ] \
    || die 3 "close: $last_record not found, though the ledger records $unit_id past that step."
  last_commit="$(jq -r '.commit // ""' "$last_record" 2>/dev/null)"
  [ -n "$last_commit" ] \
    || die 3 "close: $last_record holds no commit, though the step that wrote it records one."
  [ "$last_commit" = "$head_now" ] \
    || die 63 "close: $RV_RANGE_REPO is at $head_now, and the last record for $unit_id ($last_record) was written at $last_commit. The code moved after the record, so the range this would write names work nothing here judged."

  local new_ledger
  new_ledger="$(printf '%s' "$RV_LEDGER_DOC" | jq -c --arg id "$unit_id" \
    --arg range "$started_at..$head_now" '
    .orders = (.orders | map(if .id == $id then (.lastStep = "closed" | .commitRange = $range) else . end))')"
  [ -n "$new_ledger" ] || die 3 "close: the ledger update for $unit_id failed."

  # An order whose proof is gate or record froze no test, so the judgement of every machine
  # criterion it owns is written here, from the check that took the order-tests slot in the record
  # this close reads: the build record, or the last fix record. met is confirmed, and the derivation
  # below then confirms the criterion the way it does for any owner. Not met writes nothing, and
  # the row stays not-judged. A gate order is judged by `gate`, a third value: a model's row is
  # weaker evidence queued for a person and a person's row claims a reader, and the recipe's own
  # lines are neither (live-run row 65). A record order is judged by whoever judged its done-when
  # row, person or model, which the done-when check carries as judgedBy: somebody read the row,
  # and a model's reading stays queued for a person the way every model row is (nyc defect 17).
  # An observe order is judged by `model`, which the observed check carries the same way: a
  # model looked at the page, and completion puts the look to a person (live-run row 104).
  # A confirm order writes nothing here: its check reads deferred, never met, and the person
  # answers its criteria at review (gap row 196).
  local slot_check slot_verdict slot_judge slot_detail
  br_order_facts "$RV_UNIT_JSON"
  slot_check="$BR_ORDER_SLOT"
  # An order proved by its own tests has its criteria judged by the checkpoint rows it froze.
  [ "$slot_check" != "order-tests" ] || slot_check=""
  if [ -n "$slot_check" ]; then
    slot_verdict="$(jq -r --arg c "$slot_check" '[ (.checks // [])[] | select(.id == $c) ][0].verdict // ""' "$last_record" 2>/dev/null)"
    slot_detail="$(jq -r --arg c "$slot_check" '[ (.checks // [])[] | select(.id == $c) ][0].detail // ""' "$last_record" 2>/dev/null)"
    if [ "$slot_check" = "configuration-gate" ]; then
      slot_judge="gate"
    else
      slot_judge="$(jq -r --arg c "$slot_check" '[ (.checks // [])[] | select(.id == $c) ][0].judgedBy // ""' "$last_record" 2>/dev/null)"
    fi
    if [ "$slot_verdict" = "met" ] && [ -n "$slot_judge" ]; then
      new_ledger="$(printf '%s' "$new_ledger" | jq -c --arg unit "$unit_id" --arg judge "$slot_judge" --arg note "$slot_detail" \
        --argjson owned "$(printf '%s' "$RV_UNIT_JSON" | jq -c '.criteriaOwned // []')" \
        --argjson kinds "$(printf '%s' "$SNAPSHOT_DOC" | jq -c '[ (.alignment.criteria // [])[] | select(.verifiedBy == "machine") | .id ]')" '
        .criteria = ((.criteria // []) | map(
          if ((.id as $i | $owned | index($i)) != null) and ((.id as $i | $kinds | index($i)) != null)
          then . + {judgements: ((((.judgements // []) | map(select(.unit != $unit))))
                                 + [{unit: $unit, verdict: "confirmed", judgedBy: $judge, note: $note}])}
          else . end))')"
      [ -n "$new_ledger" ] || die 3 "close: the $slot_check judgement for $unit_id could not be written."
    fi
  fi

  # Every criterion this order serves or owns is decided now, and only now. A criterion design split
  # across several orders has no honest answer before the last of them closes, so confirmed needs
  # every serving order closed, a judgement from its owner, and every judgement left on it
  # confirmed. One rejected judgement decides it the other way, whichever order left it. The owner
  # is the one order whose tests observe the criterion, so its judgement is the one that is owed;
  # a serving order leaves one only when its tests claimed part of the clause, and leaves none when
  # it froze against its own doneWhen instead (live-run row 59). Two clauses are defensive, and
  # neither is reachable through the actions. The rejection cannot arrive, because `tests-freeze`
  # refuses a rejected row outright. An owner closed without leaving a judgement cannot arrive
  # either, because the freeze asks a test and a row of every owned machine criterion and an order
  # reaches `close` only through the freeze. Both are derived rather than assumed: a state nothing
  # can produce today is still a state to read correctly, and a hand-edited ledger can produce
  # either. A criterion a person verifies is left where it is, at not-judged. It carries a
  # checklist and no judgement, and completion is what confirms it (ideal/implementation.md, "A
  # criterion a person inspects has no tests"). The kind is read from the frozen contract, which is
  # the one producer of it; the frozen test record's own `kind` is a copy of that same field.
  local served_json serving_map_json kinds_json
  served_json="$(printf '%s' "$RV_UNIT_JSON" | jq -c '((.criteriaServed // []) + (.criteriaOwned // [])) | unique')"
  serving_map_json="$(printf '%s' "$SNAPSHOT_DOC" | jq -c \
    '[ .workOrders[]? | {id: .id, serves: (((.criteriaServed // []) + (.criteriaOwned // [])) | unique), owns: (.criteriaOwned // [])} ]')"
  kinds_json="$(printf '%s' "$SNAPSHOT_DOC" | jq -c '[ (.alignment.criteria // [])[] | {id: .id, verifiedBy: .verifiedBy} ]')"
  new_ledger="$(printf '%s' "$new_ledger" | jq -c \
    --argjson served "$served_json" --argjson serving "$serving_map_json" --argjson kinds "$kinds_json" '
    . as $l
    | .criteria = ((.criteria // []) | map(
        . as $c
        | if (($served | index($c.id)) == null) then $c
          elif (([ $kinds[] | select(.id == $c.id) ][0].verifiedBy) != "machine") then $c
          else
            ([ $serving[] | select((.serves | index($c.id)) != null) | .id ]) as $servers
            | ([ $serving[] | select((.owns | index($c.id)) != null) | .id ]) as $owners
            | ([ $l.orders[] | select((.id as $i | $servers | index($i)) != null) ]) as $entries
            | (($c.judgements // [])) as $js
            | if ($js | map(.verdict) | index("rejected")) != null then ($c + {rowState: "rejected"})
              elif ((($entries | map(.lastStep == "closed")) | all)
                     and ($owners | length) > 0
                     and (($owners - ([ $js[] | .unit ])) | length) == 0
                     and (($js | map(.verdict == "confirmed")) | all))
                then ($c + {rowState: "confirmed"})
              else ($c + {rowState: "not-judged"}) end
          end))')"
  [ -n "$new_ledger" ] || die 3 "close: deriving the row states for $unit_id failed."
  write_atomic "$RV_LEDGER_FILE" "$new_ledger"

  # Each fake a light build added is logged once the order is closed, so the log's own commit
  # lands after the range this close recorded (gap row 197).
  if task_is_light "$TASK_PATH"; then
    local fake_file="" fake_line
    while IFS= read -r fake_line; do
      case "$fake_line" in
        "+++ b/"*) fake_file="${fake_line#+++ b/}" ;;
        "+"*"$FAKE_MARKER"*)
          log_compromise "$TASK_PATH" implement \
            "a fake in $fake_file, from $unit_id: $(printf '%s' "${fake_line#*"$FAKE_MARKER"}" | sed 's/^ *//')" \
            "build the real code in place of the fake" ;;
      esac
    done <<CLOSE_FAKES
$(git -C "$RV_RANGE_REPO" diff -U0 --no-renames "$started_at" "$head_now" 2>/dev/null)
CLOSE_FAKES
  fi
  # The rounds skipped after a light order's one round, logged here for the same reason, and read
  # from the order's mark, because a person may have set the task interactive to rule. A finding
  # with a fix scope left pending or ruled is one the light cap left, unless a fixer reported it
  # out of its scope or the verifier placed it outside its file (gap row 296). A light round that
  # failed its own checks left a check finding, so it is logged here too (gap row 305).
  if [ "$(printf '%s' "$RV_ORDER_ENTRY" | jq '.lightRounds // false')" = "true" ]; then
    local skipped
    skipped="$(printf '%s' "$RV_REVIEW_DOC" | jq -r '[ .findings[]
      | select((.status == "pending" or .status == "ruled") and ((.fixScope // []) | length > 0)
               and .defectInFile != "no" and .departureCured != "no" and (has("scopeInsufficientInRound") | not)) | .id ] | join(", ")')"
    [ -z "$skipped" ] || light_log_fix_rounds "$unit_id" "$skipped"
  fi

  # The model-judged count is over the whole ledger, not this order alone: it is what a person
  # returning to a finished run reads to list every row no person ever looked at.
  im_print_summary "close" "$(printf '%s' "$new_ledger" | jq -c --arg id "$unit_id" --argjson served "$served_json" \
    --arg ledger "$RV_LEDGER_FILE" --arg earlier "${earlier_own% }" --argjson review "$RV_REVIEW_DOC" \
    --arg next "$(im_next_step "$new_ledger" "$SNAPSHOT_DOC" "$IMPL_DIR" "true" "false")" '
    ((.orders // []) | map(select(.id == $id)) | .[0]) as $o
    | {order: $id,
       state: ($o.lastStep // ""),
       commitRange: ($o.commitRange // "")}
    + (if $earlier == "" then {} else
        {earlierCommits: ($earlier + ": this order'"'"'s own, before another order'"'"'s commit, so outside commitRange")} end)
    + {attempts: ("\($o.attemptsUsed // 0) used"),
       rounds: ("\($o.roundsUsed // 0) used"),
       criterion: [ (.criteria // [])[] | select((.id as $i | $served | index($i)) != null)
                    | {id: .id, rowState: .rowState,
                       judgedBy: ("judgedBy=" + (([ (.judgements // [])[] | .judgedBy ] | unique) | if length == 0 then "nobody" else join(",") end))} ],
       rowsJudgedByModel: (([ (.criteria // [])[] | (.judgements // [])[] | select(.judgedBy == "model") ] | length)
                           + ([ (.orders // [])[] | select(.doneWhenJudgement.judgedBy == "model") ] | length)),
       pendingForReview: ([ ($review.findings // [])[] | select(.status == "pending") | .id ]
                          + (if $review | has("deviationPending") then ["departure"] else [] end)),
       ledger: $ledger,
       next: $next}')"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# finish, grant-attempt, restart: the three actions that act on the task rather than on one order.
#
# `fn_` is this section's own helper prefix. The three read the ledger without a unit id, so they
# cannot use rv_load_state, which reads one order and refuses when that order is halted. Two of
# these three exist precisely to act on a halted order.
# ------------------------------------------------------------------------------------------------

# The ledger and the frozen snapshot for a task. $1 the action's own name. Sets FN_LEDGER_FILE,
# FN_LEDGER_DOC and SNAPSHOT_DOC. Same three facts rv_load_state separates, with the same numbers:
# neither file is exit 20, one without the other is exit 3.
FN_LEDGER_FILE=""; FN_LEDGER_DOC=""
fn_load_task_state() {
  local who="$1"
  require_started_build "$who"
  FN_LEDGER_FILE="$STARTED_LEDGER_FILE"
  FN_LEDGER_DOC="$STARTED_LEDGER_DOC"
}

# Exit 68. The grant, the restart and the clearing of a halt are a person's judgement, so an
# autonomous run refuses. The mode read is the task's own for this stage, not the ledger's copy,
# so a person who sets the task interactive after a halt runs the action at once.
# $1 the action's own name, $2 what the caller would have been deciding.
fn_require_interactive() {
  local who="$1" what="$2"
  [ "$(task_run_mode "$TASK_PATH" implement)" = "autonomous" ] || return 0
  die 68 "$who: this task's implement stage is autonomous, and $what is a person's judgement. Nothing is written. Run task set-run-mode interactive on this task, then this action again, or let the halt stand."
}

# finish: the implementation stage is done for this task. The task is not. It goes to the review
# stage next, and finished.json is what that stage receives.
do_finish() {
  [ "$#" -ge 1 ] || die 3 "finish: a task folder is required"
  local task_arg="$1" values="" resolve_rc accept_warnings=""
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --accept-warnings)
        [ "$#" -ge 2 ] || die 3 "finish: --accept-warnings needs the person's reason for accepting the runner warnings"
        [ -n "$2" ] || die 3 "finish: --accept-warnings was given an empty reason."
        accept_warnings="$2"; shift 2 ;;
      --value)
        [ "$#" -ge 2 ] || die 3 "finish: --value needs <name>=<value>"
        case "$2" in *=*) ;; *) die 3 "finish: --value takes <name>=<value>, got: $2" ;; esac
        pc_refuse_forged_value "finish" "$2"
        values="$values$(printf '%s' "$2" | sed 's/=/\t/')
"
        shift 2 ;;
      *) die 3 "finish: unrecognized extra argument: $1" ;;
    esac
  done
  TASK_PATH="$(resolve_task_folder "$task_arg" "finish")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  IMPL_DIR="$TASK_PATH/implementation"

  fn_load_task_state "finish"
  [ -z "$accept_warnings" ] || fn_require_interactive "finish" "accepting a suite that failed on runner warnings alone"

  # --- exit 66: every order closed, and every machine-verified criterion confirmed ----------------
  local open_orders unconfirmed
  open_orders="$(printf '%s' "$FN_LEDGER_DOC" | jq -r '
      [ (.orders // [])[] | select(.lastStep != "closed")
        | .id + " (" + (.lastStep // "not started") + (if (.haltedBecause // "") == "" then "" else ", halted: " + .haltedBecause end) + ")" ]
      | join("; ")')"
  [ -z "$open_orders" ] \
    || die 66 "finish: these orders are not closed: $open_orders. Every order closes before implementation finishes."

  # A halt survives a close. `start` writes a drift halt onto every order the change touches,
  # whatever step each had reached, so an order closed before the design moved carries one
  # afterwards. Reading lastStep alone would finish a task whose design has moved under it, and hand
  # the review stage a commit range for a design that is gone. `restart` is what follows such a halt.
  local halted_orders
  halted_orders="$(printf '%s' "$FN_LEDGER_DOC" | jq -r '
      [ (.orders // [])[] | select((.haltedBecause // "") != "") | .id + ": " + .haltedBecause ]
      | join("; ")')"
  [ -z "$halted_orders" ] \
    || die 66 "finish: these orders are halted, closed or not: $halted_orders. Implementation does not finish while a reason to stop stands on an order."
  # A criterion that is not confirmed stops the stage, and three different facts land here. The
  # refusal names which, and which action answers it: `restart` wants a drift halt, `grant-attempt`
  # answers a spent counter, `clear-halt` the rest, so a reader told only "not confirmed" has
  # nothing to do next and no way to learn what. A criterion an order proved by confirm puts to the
  # person, confirmCriteria in scripts/lib/proof.sh, is not asked here: its task has no automated
  # tests, and the person answers it at review from the checklist rows below (gap row 196).
  unconfirmed="$(jq -nr --argjson ledger "$FN_LEDGER_DOC" --argjson snap "$SNAPSHOT_DOC" "$BR_ORDER_FACTS_JQ"'
      ([ ($snap.workOrders // [])[] | confirmCriteria[] ]) as $confirmed
      | ([ ($snap.alignment.criteria // [])[] | select(.verifiedBy == "machine") | .id
           | select(. as $i | $confirmed | index($i) | not) ]) as $machine
      | ([ ($snap.workOrders // [])[] | (.criteriaServed // [])[] , (.criteriaOwned // [])[] ]) as $served
      | [ ($ledger.criteria // [])[] | select((.id as $i | $machine | index($i)) != null)
          | select(.rowState != "confirmed")
          | . as $c
          | if ($c.rowState == "rejected")
              then ($c.id + " (rejected: a row checker turned this down. The row goes back to the test author, who runs tests-freeze on that order again once the test is repaired; clear-halt first when the order halted on it)")
            elif (($served | index($c.id)) == null)
              then ($c.id + " (no work order serves or owns it, so nothing will ever judge it. Design left this criterion with no order behind it: close design again with one, then restart)")
            else ($c.id + " (" + $c.rowState + ": the orders serving it have not all closed yet, so close them)")
            end ]
      | join("; ")')"
  [ -z "$unconfirmed" ] \
    || die 66 "finish: these machine-verified criteria are not confirmed: $unconfirmed. A criterion a machine verifies is confirmed by the checkpoint over its own rows, and implementation does not finish without it."

  # --- exit 61: the range below is a claim about the repository, so the tree has to be clean ------
  rv_load_codepath "finish"
  br_require_clean_tree "finish" "$RV_CODEPATH"
  local head_now started_from
  head_now="$(git -C "$RV_CODEPATH" rev-parse HEAD 2>/dev/null)"
  [ -n "$head_now" ] \
    || die 3 "finish: could not capture the current commit (git rev-parse HEAD failed in $RV_CODEPATH)."
  started_from="$(printf '%s' "$FN_LEDGER_DOC" | jq -r '.startedFrom // ""')"
  [ -n "$started_from" ] \
    || die 3 "finish: $FN_LEDGER_FILE holds no startedFrom, though start writes it."

  # --- exit 86: the suite, once, at the final commit (nyc defect 18) -------------------------------
  # The two record steps leave a suite row the recipe costs end-of-task unrun and record it
  # deferred. It runs here once, through the same check function and the same baseline
  # subtraction they use, over the whole task range: the baseline was taken at startedFrom and
  # this run is at HEAD. The recipe paths are the ones preconditions recorded, so no framework
  # is forgotten. The output goes to a sidecar beside the record, never inline: a suite prints
  # more than an argument or a reader can carry. A task whose every order is proved by its
  # record, or confirmed by a person, ran no test and took no suite baseline. So did a task with
  # no automated tests whose other orders are gates. The suite is then recorded not-needed and
  # never run, the same reading preconditions makes of the snapshot (BR_HARNESS_JQ).
  local pre_file recipe_line test_recipes="" suite_file suite_json suite_verdict sidecar="" harness_needed
  harness_needed="$(printf '%s' "$SNAPSHOT_DOC" | jq -r "$BR_HARNESS_JQ harnessNeeded")"
  pre_file="$IMPL_DIR/preconditions.json"
  if [ "$harness_needed" = "no" ]; then
    :
  elif [ -f "$pre_file" ]; then
    while IFS= read -r recipe_line; do
      [ -n "$recipe_line" ] || continue
      cr_recipe_pair "finish" "frameworks[].recipePath in $pre_file" "${recipe_line%%	*}=${recipe_line#*	}"
      test_recipes="$test_recipes$CR_PAIR
"
    done <<FN_RECIPES
$(jq -r '[ (.frameworks // [])[] | select(.lookup == "resolved" and (.recipePath // "") != "")
           | .framework + "\t" + .recipePath ] | join("\n")' "$pre_file" 2>/dev/null)
FN_RECIPES
  fi
  # shellcheck disable=SC2034 # read by the sourced library
  CR_WHO="finish"
  # shellcheck disable=SC2034 # read by the sourced library
  CR_TEST_RECIPES="$test_recipes"
  # shellcheck disable=SC2034 # read by the sourced library
  CR_CHECK_RECIPES=""
  cr_resolve
  BRC_WHO="finish"
  BRC_CODEPATH="$RV_CODEPATH"
  BRC_RECIPES="$CR_DOC"
  BRC_BASELINE_FILE="$IMPL_DIR/baseline.json"
  BRC_VALUES="$values"
  BRC_END_OF_TASK=true
  suite_file="$(mktemp)" || die 3 "finish: could not create a temporary file"
  if [ "$harness_needed" = "no" ]; then
    jq -nc '{id: "suite-regression", verdict: "not-needed",
             detail: "the suite was not run: every order in the snapshot is proved by its record or confirmed by a person, or is a configuration gate on a task with no automated tests, so no test exists and no suite baseline was taken."}' >"$suite_file"
  else
    br_test_check "suite-regression" "suite" "suite" >"$suite_file"
  fi
  [ -s "$suite_file" ] || { rm -f "$suite_file"; die 3 "finish: the suite check produced nothing."; }
  if [ "$(jq -r 'has("output")' "$suite_file")" = "true" ]; then
    sidecar="finished-suite.txt"
    jq -r '.output' "$suite_file" >"$IMPL_DIR/$sidecar" \
      || { rm -f "$suite_file"; die 3 "finish: could not write the suite output to $IMPL_DIR/$sidecar"; }
  fi
  suite_json="$(jq -c --arg f "$sidecar" \
    'del(.id, .output) + (if $f == "" then {} else {outputFile: $f} end)' "$suite_file")"
  rm -f "$suite_file"
  [ -n "$suite_json" ] || die 3 "finish: could not assemble the suite result."
  suite_verdict="$(printf '%s' "$suite_json" | jq -r '.verdict')"
  case "$suite_verdict" in
    met|undeclared|not-needed)
      [ -z "$accept_warnings" ] \
        || die 3 "finish: --accept-warnings was given, and the suite reads $suite_verdict at $head_now, not warned. There are no runner warnings to accept. Nothing was recorded."
      ;;
    unmet)
      # The new lines go to standard error as their own block, the way the clean-tree refusal
      # lists its paths, so the message stays one line a reader can act on.
      if [ "$(printf '%s' "$suite_json" | jq -r '.newLineCount // 0')" != "0" ]; then
        printf 'finish: the suite lines new since the baseline (first %s of %s) are:\n%s\n' \
          "$(printf '%s' "$suite_json" | jq -r '.newLines | length')" \
          "$(printf '%s' "$suite_json" | jq -r '.newLineCount')" \
          "$(printf '%s' "$suite_json" | jq -r '.newLines[]')" >&2
      fi
      die 86 "finish: the suite is unmet at $head_now: $(printf '%s' "$suite_json" | jq -r '.detail') The whole output is at $IMPL_DIR/$sidecar. Nothing was recorded. A fix commit on the branch and a second finish is the route."
      ;;
    warned)
      # No test failed, so a fix commit on the branch is not the route. Passing on its own would
      # decide for the project that its runner's exit status does not count. That is a person's
      # call, so only --accept-warnings passes it, and the record names the person and the reason.
      local not_warned
      not_warned="$(printf '%s' "$suite_json" | jq -r '[ (.runs // [])[]
        | select(.verdict != "warned" and .verdict != "met" and .verdict != "undeclared" and .verdict != "not-needed")
        | .framework + "=" + .verdict ] | join(", ")')"
      [ -z "$accept_warnings" ] || [ -z "$not_warned" ] \
        || die 86 "finish: --accept-warnings accepts runner warnings only, and these frameworks read otherwise at $head_now: $not_warned. $(printf '%s' "$suite_json" | jq -r '.detail') Nothing was recorded."
      if [ -n "$accept_warnings" ]; then
        suite_json="$(printf '%s' "$suite_json" | jq -c --arg because "$accept_warnings" \
          '. + {warningsAccepted: {because: $because, judgedBy: "person"}}')"
      else
        printf 'finish: the runner warning lines (first %s) are:\n%s\n' \
          "$(printf '%s' "$suite_json" | jq -r '.warningLines | length')" \
          "$(printf '%s' "$suite_json" | jq -r '.warningLines[]')" >&2
        die 86 "finish: the suite reads warned at $head_now ($(printf '%s' "$suite_json" | jq -r '[ (.runs // [])[] | .framework + "=" + .verdict ] | join(", ")')): $(printf '%s' "$suite_json" | jq -r '.detail') The whole output is at $IMPL_DIR/$sidecar. Nothing was recorded. finish does not pass on runner warnings by itself, because the project's own configuration makes them fail the run. A person picks one of three routes. Accept the warnings: run finish again with --accept-warnings <the person's reason>, interactive only. Change the suite row's command in the project's copy of the test-execution recipe, so these warnings do not fail the run. Or repair the project configuration that raises them, in a change outside this task."
      fi
      ;;
    *)
      die 86 "finish: the suite could not be decided at $head_now: $(printf '%s' "$suite_json" | jq -r '.detail')${sidecar:+ The whole output is at $IMPL_DIR/$sidecar.} Nothing was recorded. Repair what the detail names, then run finish again."
      ;;
  esac

  # --- the checklists a person still has to work through, copied from the frozen records ----------
  # They are copied rather than pointed at, because the review stage reads this one file and the
  # frozen records are per order. A criterion two orders serve carries one entry per order, the same shape
  # the frozen records themselves keep.
  local order_ids order_count oi one_id one_tests checklists_json='[]' deferred_json='[]' one_review
  local pending_json='[]'
  order_ids="$(printf '%s' "$FN_LEDGER_DOC" | jq -c '[ (.orders // [])[] | .id ]')"
  order_count="$(printf '%s' "$order_ids" | jq 'length')"
  oi=0
  while [ "$oi" -lt "$order_count" ]; do
    one_id="$(printf '%s' "$order_ids" | jq -r --argjson i "$oi" '.[$i]')"
    if [ -f "$IMPL_DIR/tests-$one_id.json" ]; then
      one_tests="$(jq -c '.' "$IMPL_DIR/tests-$one_id.json" 2>/dev/null)"
      [ -n "$one_tests" ] \
        || die 3 "finish: $IMPL_DIR/tests-$one_id.json exists but could not be read as JSON. Repair or remove it by hand before running this again."
      checklists_json="$(jq -cn --argjson have "$checklists_json" --argjson doc "$one_tests" --arg unit "$one_id" '
          $have + [ ($doc.rows // [])[] | select(.kind == "person")
                    | {criterion: .criterion, unit: $unit, checklist: (.checklist // "")} ]')"
    fi
    if [ -f "$IMPL_DIR/review-$one_id.json" ]; then
      one_review="$(jq -c '.' "$IMPL_DIR/review-$one_id.json" 2>/dev/null)"
      [ -n "$one_review" ] \
        || die 3 "finish: $IMPL_DIR/review-$one_id.json exists but could not be read as JSON. Repair or remove it by hand before running this again."
      deferred_json="$(jq -cn --argjson have "$deferred_json" --argjson doc "$one_review" --arg unit "$one_id" '
          $have + [ ($doc.findings // [])[] | select(.ruling == "deferred")
                    | {unit: $unit, finding: .id, severity: .severity, linkedTo: (.linkedTo // ""),
                       evidence: (.evidence // ""), reason: (.rulingReason // "")} ]')"
      # What an unattended run left for the person, which review puts to them (gap row 279).
      pending_json="$(jq -cn --argjson have "$pending_json" --argjson doc "$one_review" --arg unit "$one_id" '
          $have + [ ($doc.findings // [])[] | select(.status == "pending")
                    | {unit: $unit, kind: "ruling", finding: .id, severity: .severity, text: (.pendingBecause // .evidence // ""),
                       because: (if has("pendingBecause") then "a verifier answered and a person decides"
                                 elif ((.fixScope // []) | length) == 0 then "its fix scope is empty"
                                 else "a light task allows one fix round, and it is spent" end)} ]
                + [ $doc.deviationPending // empty
                    | {unit: $unit, kind: "departure", text: (.departure + ", in " + .file)} ]')"
    fi
    oi=$((oi + 1))
  done
  # A finish after a failed review carries no decision the person already answered there: a
  # `decision-` check with an `answer` in review.json or an archived pass (gap row 279).
  local answered_json
  answered_json="$(find "$TASK_PATH/review" -maxdepth 1 -type f -name 'review*.json' -exec cat {} + 2>/dev/null \
    | jq -cs '[ .[] | (.checks // [])[] | select((.id | startswith("decision-")) and has("answer")) | .id ] | unique' 2>/dev/null)"
  [ -n "$answered_json" ] || answered_json='[]'
  pending_json="$(printf '%s' "$pending_json" | jq -c --argjson answered "$answered_json" '
    [ .[] | select(("decision-" + .unit + "-" + (.finding // "departure")) as $id | $answered | index($id) | not) ]')"
  # An order proved by confirm froze no row, so its done-when rows are the checklist. One row per
  # sentence, under each criterion confirmCriteria names for the order, and the person answers
  # that criterion at review's close (gap row 196).
  checklists_json="$(printf '%s' "$SNAPSHOT_DOC" | jq -c --argjson have "$checklists_json" "$BR_ORDER_FACTS_JQ"'
      $have + [ (.workOrders // [])[] | . as $o
                | confirmCriteria[] as $cid | ($o.doneWhen // [])[]
                | {criterion: $cid, unit: $o.id, checklist: .} ]')"
  [ -n "$checklists_json" ] || die 3 "finish: could not add the done-when rows of the orders a person confirms."

  local task_id today record_json record_file
  task_id="$(jq -r '.id // empty' "$TASK_PATH/task.json" 2>/dev/null)"
  [ -n "$task_id" ] || die 3 "finish: $TASK_PATH/task.json has no usable id field"
  today="$(date -u +%Y-%m-%d)"
  record_file="$IMPL_DIR/finished.json"
  record_json="$(jq -n --arg takenAt "$today" --arg task "$task_id" \
    --arg range "$started_from..$head_now" \
    --argjson ledger "$FN_LEDGER_DOC" --argjson snap "$SNAPSHOT_DOC" \
    --argjson checklists "$checklists_json" --argjson deferred "$deferred_json" \
    --argjson pending "$pending_json" --argjson suite "$suite_json" --arg pluginVersion "$(plugin_version)" '
    ([ ($snap.alignment.criteria // [])[] | {id: .id, verifiedBy: .verifiedBy} ]) as $kinds
    | {
      schemaVersion: 1,
      pluginVersion: $pluginVersion,
      takenAt: $takenAt,
      task: $task,
      commitRange: $range,
      suite: $suite,
      orders: [ ($ledger.orders // [])[] | {id: .id, commitRange: (.commitRange // ""), roundsUsed: (.roundsUsed // 0)}
                + (if ((.repairs // []) | length) > 0 then {closedRanges: [ .repairs[] | .closedRange // empty ]} else {} end) ],
      criteria: [ ($ledger.criteria // [])[] | . as $c
                  | {id: $c.id,
                     verifiedBy: (([ $kinds[] | select(.id == $c.id) ][0].verifiedBy) // ""),
                     rowState: $c.rowState,
                     judgedBy: ([ ($c.judgements // [])[] | .judgedBy ] | unique)} ],
      checklists: $checklists,
      deferred: $deferred,
      pendingDecisions: $pending,
      rowsJudgedByModel: (([ ($ledger.criteria // [])[] | (.judgements // [])[] | select(.judgedBy == "model") ] | length)
                          + ([ ($ledger.orders // [])[] | select(.doneWhenJudgement.judgedBy == "model") ] | length))
    }')"
  [ -n "$record_json" ] || die 3 "finish: could not assemble the finished record for $task_id."
  write_atomic "$record_file" "$record_json"
  # The stage boundary: the task folder is committed, with the order count and the range the
  # record just fixed as the reason. The code repository is not touched; its range is the claim.
  commit_stage_close "$TASK_PATH" implementation "Finish implementation for $task_id" \
    "$(printf '%s' "$record_json" | jq -r '"\(.orders | length | if . == 1 then "1 order" else "\(.) orders" end) finished over \(.commitRange)"')"

  # The summary. The checklists, the deferred findings and every criterion's row are in the record,
  # which the review stage reads from the path named here.
  im_print_summary "finish" "$(printf '%s' "$record_json" | jq -c --arg record "$record_file" --arg impl "$IMPL_DIR" '
    {task: .task,
     commitRange: .commitRange,
     suite: (.suite.verdict + (if .suite.outputFile == null then "" else ", output at " + $impl + "/" + .suite.outputFile end)),
     order: ([ .orders[] | {id, commitRange, rounds: ("rounds=" + (.roundsUsed | tostring))} ]),
     criteria: ((.criteria | group_by(.rowState) | map("\(.[0].rowState)=\(length)") | join(" ")) | if . == "" then "none" else . end),
     checklists: (.checklists | length),
     deferred: ([ .deferred[] | .unit + "/" + .finding ]),
     pendingDecisions: ([ .pendingDecisions[] | .unit + "/" + (.finding // .kind) ]),
     rowsJudgedByModel: .rowsJudgedByModel,
     record: $record,
     next: "none: implementation is finished, and the review stage reads the record"}')"
  echo "FINISH: implementation is finished for this task; the review stage reads $record_file" >&2
  exit 0
}

do_grant_attempt() {
  local task_arg="" unit_id="" reason=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --reason)
        [ "$#" -ge 2 ] || die 3 "grant-attempt: --reason needs the reason this order gets another attempt"
        [ -n "$2" ] || die 3 "grant-attempt: --reason was given an empty reason."
        halt_refuse_separator "grant-attempt" "--reason" "$2"
        reason="$2"; shift 2 ;;
      -*) die 3 "grant-attempt: unrecognized argument: $1" ;;
      *)
        if [ -z "$task_arg" ]; then
          task_arg="$1"
        elif [ -z "$unit_id" ]; then
          unit_id="$1"
        else
          die 3 "grant-attempt: unrecognized extra argument: $1"
        fi
        shift ;;
    esac
  done
  [ -n "$task_arg" ] || die 3 "grant-attempt: a task folder is required"
  [ -n "$unit_id" ]  || die 3 "grant-attempt: a unit id is required"
  [ -n "$reason" ]   || die 3 "grant-attempt: --reason is required. A grant with no reason is a cap nobody can audit."

  local resolve_rc
  TASK_PATH="$(resolve_task_folder "$task_arg" "grant-attempt")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  IMPL_DIR="$TASK_PATH/implementation"

  fn_load_task_state "grant-attempt"
  fn_require_interactive "grant-attempt" "another attempt on one order"

  local unit_present order_entry
  unit_present="$(printf '%s' "$SNAPSHOT_DOC" | jq -r --arg u "$unit_id" '[ .workOrders[]? | select(.id == $u) ] | length')"
  [ "$unit_present" = "0" ] && die 22 "grant-attempt: $unit_id is not in the frozen copy."
  order_entry="$(printf '%s' "$FN_LEDGER_DOC" | jq -c --arg id "$unit_id" \
    '(.orders // []) | map(select(.id == $id)) | .[0] // null')"
  [ "$order_entry" != "null" ] \
    || die 3 "grant-attempt: $unit_id has no entry in $FN_LEDGER_FILE, though start opens one entry per snapshot work order."

  # Exit 67, twice over. A closed order has nothing left to attempt, so raising its allowance would
  # record a grant against work that is already judged and closed.
  local last_step
  last_step="$(printf '%s' "$order_entry" | jq -r '.lastStep // ""')"
  [ "$last_step" != "closed" ] \
    || die 67 "grant-attempt: $unit_id is closed, so there is no attempt left to grant. Nothing is written."

  # A grant answers a spent attempt counter, or a run budget since raised in task.json. A halt can hold several
  # reasons, newest first, so this looks at every segment rather than the front of the text. The
  # grant then removes that one segment. Any other reason stays, and the order stays halted with it,
  # because clearing a reason a grant does not answer would hide it behind an attempt nobody needed.
  local halt halt_spent halt_rest
  halt="$(printf '%s' "$order_entry" | jq -r '.haltedBecause // ""')"
  halt_spent="$(halt_segments_matching "$halt" '["attempts spent","budget spent"]' keep)"
  halt_rest="$(halt_segments_matching "$halt" '["attempts spent","budget spent"]' drop)"
  if [ -n "$halt" ] && [ -z "$halt_spent" ]; then
    die 67 "grant-attempt: $unit_id is halted for something a grant does not answer: $halt. Nothing is written."
  fi

  local allowed_before allowed_after today expr new_ledger
  allowed_before="$(attempts_allowed_for "$order_entry")"
  allowed_after=$((allowed_before + 1))
  today="$(date -u +%Y-%m-%d)"
  # attemptsUsed is never touched. The count of what a builder has already spent is a fact about the
  # past, and a cap that can be lowered by editing that count is not a cap at all.
  expr='.attemptsAllowed = $allowedAfter
        | .grants = ((.grants // []) + [{reason: $reason, grantedAt: $today, allowedAfter: $allowedAfter}])'
  if [ -n "$halt_spent" ] && [ -z "$halt_rest" ]; then
    expr="$expr | del(.haltedBecause)"
  elif [ -n "$halt_spent" ]; then
    expr="$expr | .haltedBecause = \$rest"
  fi
  new_ledger="$(printf '%s' "$FN_LEDGER_DOC" | jq -c --arg id "$unit_id" --arg reason "$reason" \
    --arg today "$today" --argjson allowedAfter "$allowed_after" --arg rest "$halt_rest" \
    ".orders = (.orders | map(if .id == \$id then ($expr) else . end))")"
  [ -n "$new_ledger" ] || die 3 "grant-attempt: the ledger update for $unit_id failed."
  write_atomic "$FN_LEDGER_FILE" "$new_ledger"

  local ga_cleared ga_halt
  ga_cleared="none: the order was not halted"
  ga_halt="none"
  if [ -n "$halt_spent" ] && [ -z "$halt_rest" ]; then
    ga_cleared="$halt_spent"
  elif [ -n "$halt_spent" ]; then
    ga_cleared="$halt_spent"
    ga_halt="$halt_rest"
    echo "GRANT-ATTEMPT: $unit_id stays halted, because this reason still holds: $halt_rest" >&2
  fi
  im_print_summary "grant-attempt" "$(printf '%s' "$new_ledger" | jq -c --arg id "$unit_id" \
    --arg allowed "$allowed_after (was $allowed_before)" --arg cleared "$ga_cleared" --arg halt "$ga_halt" \
    --arg ledger "$FN_LEDGER_FILE" \
    --arg next "$(im_next_step "$new_ledger" "$SNAPSHOT_DOC" "$IMPL_DIR" "true" "false")" '
    ((.orders // []) | map(select(.id == $id)) | .[0]) as $o
    | {order: $id,
       attemptsAllowed: $allowed,
       attemptsUsed: ($o.attemptsUsed // 0),
       state: ($o.lastStep // "not started"),
       haltCleared: $cleared,
       halt: $halt,
       grants: (($o.grants // []) | length),
       ledger: $ledger,
       next: $next}')"
  exit 0
}

# clear-halt: the one action for every halt the grant and the restart do not answer (nyc defect
# 20). A rejected row, a finding on a non-goal, a fixer's scope, a finding ruled load-bearing, a
# dirty tree and spent fix rounds each stop an order for a person to act on: repair the test,
# rule on the finding, commit the tree. None of that is this script's to do, so the person does it
# and then says so here, with the reason recorded beside the halt it cleared. The order resumes at
# the step its ledger entry records; nothing here moves it. A halt the grant or the restart
# answers refuses (exit 85), so the counter and the snapshot keep their one clearing path each.
do_clear_halt() {
  local task_arg="" unit_id="" because=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --because)
        [ "$#" -ge 2 ] || die 3 "clear-halt: --because needs what the person did about the halt"
        [ -n "$2" ] || die 3 "clear-halt: --because was given an empty reason."
        halt_refuse_separator "clear-halt" "--because" "$2"
        because="$2"; shift 2 ;;
      -*) die 3 "clear-halt: unrecognized argument: $1" ;;
      *)
        if [ -z "$task_arg" ]; then
          task_arg="$1"
        elif [ -z "$unit_id" ]; then
          unit_id="$1"
        else
          die 3 "clear-halt: unrecognized extra argument: $1"
        fi
        shift ;;
    esac
  done
  [ -n "$task_arg" ] || die 3 "clear-halt: a task folder is required"
  [ -n "$unit_id" ]  || die 3 "clear-halt: a unit id is required"
  [ -n "$because" ]  || die 3 "clear-halt: --because is required. A halt cleared with no reason is a stop nobody can audit."

  local resolve_rc
  TASK_PATH="$(resolve_task_folder "$task_arg" "clear-halt")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  IMPL_DIR="$TASK_PATH/implementation"

  fn_load_task_state "clear-halt"
  fn_require_interactive "clear-halt" "clearing a halt on one order"

  local unit_present order_entry
  unit_present="$(printf '%s' "$SNAPSHOT_DOC" | jq -r --arg u "$unit_id" '[ .workOrders[]? | select(.id == $u) ] | length')"
  [ "$unit_present" = "0" ] && die 22 "clear-halt: $unit_id is not in the frozen copy."
  order_entry="$(printf '%s' "$FN_LEDGER_DOC" | jq -c --arg id "$unit_id" \
    '(.orders // []) | map(select(.id == $id)) | .[0] // null')"
  [ "$order_entry" != "null" ] \
    || die 3 "clear-halt: $unit_id has no entry in $FN_LEDGER_FILE, though start opens one entry per snapshot work order."

  local last_step halt
  last_step="$(printf '%s' "$order_entry" | jq -r '.lastStep // ""')"
  [ "$last_step" != "closed" ] \
    || die 67 "clear-halt: $unit_id is closed, so there is nothing to resume. Nothing is written."
  halt="$(printf '%s' "$order_entry" | jq -r '.haltedBecause // ""')"
  [ -n "$halt" ] || die 3 "clear-halt: $unit_id is not halted. Nothing is written."

  # Every segment is read, the way the grant and the restart read theirs, so a halt that holds
  # one of their reasons anywhere in it goes to that action first.
  local other_action
  other_action="$(printf '%s' "$halt" | jq -Rr '
      split("; earlier: ")
      | if map(select(startswith("attempts spent") or startswith("budget spent"))) | length > 0 then "grant-attempt"
        elif map(select(startswith("design drift"))) | length > 0 then "restart"
        elif map(select(startswith("test wrong"))) | length > 0 then "retake-tests"
        else "" end')"
  # A drift halt names a second route as well. `start` is the one action that computes drift, so
  # it is also the one that clears a halt the design no longer earns; a second computation here
  # would be a second producer for one fact.
  local drift_route=""
  [ "$other_action" != "restart" ] \
    || drift_route=" Or run start again: it clears a halt about this order's own design file once the design no longer differs from the snapshot."
  case "$halt" in
    *"$RR_DEPARTURE_PREFIX"*|*"$RR_REVIEWER_PREFIX"*)
      drift_route=" Or a person keeps the departure: run review-record again with --accept-deviation <their reason>, in references/review.md." ;;
  esac
  [ -z "$other_action" ] \
    || die 85 "clear-halt: $unit_id is halted for something $other_action answers: $halt. Run $other_action instead.$drift_route Nothing is written."

  local today new_ledger
  today="$(date -u +%Y-%m-%d)"
  new_ledger="$(printf '%s' "$FN_LEDGER_DOC" | jq -c --arg id "$unit_id" --arg reason "$halt" \
    --arg today "$today" --arg because "$because" '
    .orders = (.orders | map(if .id == $id then del(.haltedBecause) else . end))
    | .haltsCleared = ((.haltsCleared // []) + [{id: $id, reason: $reason, clearedAt: $today, because: $because}])')"
  [ -n "$new_ledger" ] || die 3 "clear-halt: the ledger update for $unit_id failed."
  write_atomic "$FN_LEDGER_FILE" "$new_ledger"

  local ch_precon
  ch_precon=false
  [ -f "$IMPL_DIR/preconditions.json" ] && jq empty "$IMPL_DIR/preconditions.json" 2>/dev/null && ch_precon=true
  im_print_summary "clear-halt" "$(printf '%s' "$new_ledger" | jq -c --arg id "$unit_id" \
    --arg cleared "$halt" --arg ledger "$FN_LEDGER_FILE" \
    --arg next "$(im_next_step "$new_ledger" "$SNAPSHOT_DOC" "$IMPL_DIR" "$ch_precon" "false")" '
    ((.orders // []) | map(select(.id == $id)) | .[0]) as $o
    | {order: $id,
       haltCleared: $cleared,
       resumesAt: ($o.lastStep // "not started"),
       haltsCleared: ((.haltsCleared // []) | length),
       ledger: $ledger,
       next: $next}')"
  exit 0
}

# retake-tests: the route for a frozen test a person ruled wrong after the build (live-run row
# 110). The fixer may not touch the test, and `tests-freeze` refuses once the order left
# tests-frozen (exit 76), because a re-freeze would leave a stale build record and a spent counter
# behind. So this moves the build, review, fix and verify records aside, into
# implementation/retaken-<order>-<n>/, and sets the step back to tests-frozen; the freeze record
# and the tests brief stay, since the freeze after this overwrites the record with retakenFrom.
# The attempt counter stays: the attempts were real, against the old test, and a spent one is
# the grant's to answer at the next build-brief. The fix rounds go back to zero: they counted
# the review record that moved, and the review after the rebuild starts its own. Allowed only
# while the halt begins `test wrong:`, the reason `verify-record` writes for that ruling (exit 99 otherwise).
do_retake_tests() {
  [ "$#" -ge 2 ] || die 3 "retake-tests: a task folder and a unit id are required"
  [ "$#" -le 2 ] || die 3 "retake-tests: unrecognized extra argument: $3"
  local unit_id="$2" resolve_rc
  TASK_PATH="$(resolve_task_folder "$1" "retake-tests")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  IMPL_DIR="$TASK_PATH/implementation"

  fn_load_task_state "retake-tests"

  local unit_present order_entry
  unit_present="$(printf '%s' "$SNAPSHOT_DOC" | jq -r --arg u "$unit_id" '[ .workOrders[]? | select(.id == $u) ] | length')"
  [ "$unit_present" = "0" ] && die 22 "retake-tests: $unit_id is not in the frozen copy."
  order_entry="$(printf '%s' "$FN_LEDGER_DOC" | jq -c --arg id "$unit_id" \
    '(.orders // []) | map(select(.id == $id)) | .[0] // null')"
  [ "$order_entry" != "null" ] \
    || die 3 "retake-tests: $unit_id has no entry in $FN_LEDGER_FILE, though start opens one entry per snapshot work order."

  local halt finding
  halt="$(printf '%s' "$order_entry" | jq -r '.haltedBecause // ""')"
  case "$halt" in
    "test wrong: "*) ;;
    "") die 99 "retake-tests: $unit_id is not halted. A retake follows a test-wrong ruling at verify-record, and nothing else. Nothing is written." ;;
    *) die 99 "retake-tests: $unit_id is halted for something a retake does not answer: $halt. A retake follows a test-wrong ruling at verify-record, and nothing else. Nothing is written." ;;
  esac
  finding="${halt#test wrong: }"
  finding="${finding%%:*}"

  local tests_file freeze_commit
  tests_file="$IMPL_DIR/tests-$unit_id.json"
  [ -f "$tests_file" ] \
    || die 3 "retake-tests: $tests_file not found, though $unit_id was built. Nothing is written."
  freeze_commit="$(jq -r '.commit // ""' "$tests_file" 2>/dev/null)"
  [ -n "$freeze_commit" ] \
    || die 3 "retake-tests: $tests_file holds no commit, though tests-freeze writes one. Nothing is written."

  local n target
  n=1
  while [ -e "$IMPL_DIR/retaken-$unit_id-$n" ]; do n=$((n + 1)); done
  target="$IMPL_DIR/retaken-$unit_id-$n"

  local today new_ledger
  today="$(date -u +%Y-%m-%d)"
  new_ledger="$(printf '%s' "$FN_LEDGER_DOC" | jq -c --arg id "$unit_id" --arg reason "$halt" \
    --arg today "$today" --arg finding "$finding" --arg target "$target" --arg commit "$freeze_commit" '
    .orders = (.orders | map(if .id == $id then
        (del(.haltedBecause) | .lastStep = "tests-frozen" | .roundsUsed = 0
         | .retakes = ((.retakes // []) + [{finding: $finding, at: $today, movedTo: $target, freezeCommit: $commit}]))
      else . end))
    | .haltsCleared = ((.haltsCleared // []) + [{id: $id, reason: $reason, clearedAt: $today,
        because: ("retake-tests: the records moved to " + $target + ", and the tests are retaken for " + $finding)}])')"
  [ -n "$new_ledger" ] || die 3 "retake-tests: the ledger update for $unit_id failed."

  mkdir -p "$target" || die 3 "retake-tests: could not create $target"
  # The files among the names restart moves, less the two the tests step wrote: the freeze
  # record, which the next freeze overwrites, and the tests brief, which the next tests-brief
  # overwrites. A folder stays, because a retake keeps the unchanged tests' red runs.
  local moved moved_count
  moved_count=0
  while IFS= read -r moved; do
    [ -n "$moved" ] || continue
    case "$moved" in
      "$tests_file"|"$IMPL_DIR/brief-$unit_id-tests.json") continue ;;
    esac
    mv "$moved" "$target/" || die 3 "retake-tests: could not move $moved to $target"
    moved_count=$((moved_count + 1))
  done < <(find "$IMPL_DIR" -mindepth 1 -maxdepth 1 -type f \( -name "*-$unit_id.*" -o -name "*-$unit_id-*" \) 2>/dev/null)
  write_atomic "$FN_LEDGER_FILE" "$new_ledger"

  im_print_summary "retake-tests" "$(printf '%s' "$new_ledger" | jq -c --arg id "$unit_id" \
    --arg finding "$finding" --arg cleared "$halt" --arg target "$target" --argjson moved "$moved_count" \
    --arg ledger "$FN_LEDGER_FILE" '
    ((.orders // []) | map(select(.id == $id)) | .[0]) as $o
    | {order: $id,
       finding: $finding,
       haltCleared: $cleared,
       movedTo: $target,
       moved: "\($moved) records",
       resumesAt: ($o.lastStep // "not started"),
       attempts: "\($o.attemptsUsed // 0) used, the counter stays",
       rounds: "0 used, the review record moved",
       retakes: (($o.retakes // []) | length),
       ledger: $ledger,
       next: "tests \($id): the author corrects the test the finding names, the checker reads the affected rows, then tests-freeze"}')"
  exit 0
}

# rs_on_branch <codepath> <commit> <table>: prints the commit when HEAD holds it. Otherwise, after a
# rebase, prints the commit on this branch that is its rebased copy, or `?` and why none is. Prints
# nothing when HEAD does not hold it and <table> is empty: no rebase happened, so the commit is
# simply gone, as a reset leaves it. <table> is rs_order_commits' list of the span's commits.
# A rebase gives every commit a new id, and the records keep the old ones. The copy keeps the
# change, so its stable patch id matches, and it keeps the author, the author date and the subject.
# Both must match. A patch id alone is not enough: a revert of the copy and a revert of that revert
# carry the same patch id, as can another order's identical change. Neither keeps the author date
# and the subject. Of several matches, the oldest is taken, and that is the one tie left: the same
# change by the same author in the same second, which nothing in the records can tell apart.
# When the author, date and subject match and the patch id does not, the rebase changed the diff,
# most often by resolving a conflict. The copy is then named but not taken: its code is no longer
# what the order built, so a person decides. The old object stays readable while the reflog holds
# it, thirty days by default. The subject alone is no link: the build and fix steps write none of
# their own, so many commits share one.
rs_on_branch() {
  local pid who
  if git -C "$1" merge-base --is-ancestor "$2" HEAD >/dev/null 2>&1; then printf '%s' "$2"; return 0; fi
  [ -n "$3" ] || return 0
  who="$(git -C "$1" log -1 --format='%at %ae %s' "$2" 2>/dev/null)"
  if [ -z "$who" ]; then
    printf '?%s' "the old commit is gone from the repository, so nothing links it to this branch"
    return 0
  fi
  pid="$(git -C "$1" show --no-color "$2" 2>/dev/null | git patch-id --stable 2>/dev/null | cut -d' ' -f1)"
  printf '%s' "$3" | jq -r --arg pid "$pid" --arg who "$who" '
    ([ .[] | select(.who == $who) ]) as $same
    | ([ $same[] | select(.pid == $pid) ][0].commit) as $copy
    | if $pid != "" and $copy != null then $copy
      elif ($same | length) > 0 then "?its diff changed in the rebase; " + ($same[0].commit[0:7]) + " carries its author, date and subject"
      else "?no commit on this branch carries its change with its author, date and subject, so the rebase dropped it or rewrote it" end'
}

# rs_rebase_table <codepath> <span> <ledger>: the table rs_on_branch reads, or nothing when the
# ledger holds no startedFromBefore. `start --rebased-onto` keeps each rewritten start there, so a
# ledger holding one is a branch whose ids may have moved since the records were written. The
# table lists the span's commits oldest first, each with its stable patch id and its author, date
# and subject. A commit with no diff has no patch id and is listed with an empty one.
rs_rebase_table() {
  [ "$(printf '%s' "$3" | jq '(.startedFromBefore // []) | length' 2>/dev/null)" -gt 0 ] 2>/dev/null || return 0
  git -C "$1" log --reverse --no-color -p "$2" 2>/dev/null | git patch-id --stable 2>/dev/null \
    | jq -Rsc --arg who "$(git -C "$1" log --reverse --format='%H %at %ae %s' "$2" 2>/dev/null)" '
      ([ split("\n")[] | select(length > 0) | split(" ") | {key: .[1], value: .[0]} ] | from_entries) as $pid
      | [ $who | split("\n")[] | select(length > 0)
          | {commit: .[0:40], pid: ($pid[.[0:40]] // ""), who: .[41:]} ]'
}

# rs_reverted <codepath> <span> [<table>]: the full ids, one per line, of every commit in <span>
# that a later commit there reverts, and of that reverting commit. The pair leaves the tree as it
# was, so neither is code the tree holds. A revert is read by the line `git revert` writes, "This
# reverts commit <id>.", whoever ran it: `restart` runs it, and a person may. A revert that is
# itself reverted puts the change back, so its pair does not count. After a rebase the line names
# the old id, so a target HEAD does not hold is found again through rs_on_branch and <table>.
rs_reverted() {
  local r t on pairs=""
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    t="$(git -C "$1" log -1 --format=%B "$r" 2>/dev/null | sed -n 's/^This reverts commit \([0-9a-f][0-9a-f]*\)\.$/\1/p' | head -1)"
    if [ -n "$t" ] && ! git -C "$1" merge-base --is-ancestor "$t" HEAD >/dev/null 2>&1; then
      on="$(rs_on_branch "$1" "$t" "${3:-}")"
      case "$on" in ""|"?"*) t="" ;; *) t="$on" ;; esac
    fi
    [ -z "$t" ] || pairs="$pairs$r $t
"
  done <<RS_REVERTS
$(git -C "$1" log --format=%H --grep='^This reverts commit ' "$2" 2>/dev/null)
RS_REVERTS
  printf '%s' "$pairs" | jq -Rrs '[ split("\n")[] | select(length > 0) | split(" ") ] as $p
    | ($p | map(.[1])) as $t | $p[] | select(.[0] as $r | $t | index($r) | not) | .[0], .[1]'
}

# The commits one order's records name that HEAD still holds, as a JSON array of
# {order, kind, commit, range}. $1 the task folder, $2 the code repository, $3 the order, $4 the
# ledger document.
# The freeze record's `commit` is HEAD at the freeze, whether or not the freeze committed: a gate
# order commits nothing, and a test already in HEAD makes no commit either. So the commit is the
# order's only when its subject is the one the freeze writes for this order.
# One record holds one commit, and the freeze after a retake overwrites it. So each `retakes`
# entry's `freezeCommit`, the freeze that retake superseded, is read as a freeze commit too, and
# the same subject test decides it. `restart` keeps every freeze these name and opens its span at
# the first of them, so the build before a retake is reverted too (live-run row 147). A build record holds
# the last attempt's range; a fix record each round's. A record whose commits git no longer has
# names nothing (live-run row 94). An earlier attempt is in no record, so a build record's
# commits are read from `startedFrom` to its commit, and im_order_commits keeps this order's own.
# Another order's commit is never listed, so no restart reverts it (gap row 222).
# A build and fix record does not stay at the top of the implementation folder. `retake-tests`
# moves it to `retaken-<order>-<n>/` and an earlier restart moves it to
# `implementation-<date>-<commit>/`, and the commits it names stay on the branch either way. So
# both are read, and an order's own commits are never counted as later ones (live-run row 144).
# A record can be moved, cleared or written in a shape an older version wrote. The branch cannot.
# So the freezes are read from the branch, by the subject `tests-freeze` writes above, over the
# range the ledger's `startedFrom` opens. That range bounds the search to this task, because two
# tasks on one repository both hold an order called wo1. The records still offer their freeze
# commits, for the one case the range cannot cover: `start --rebased-onto` rewrites `startedFrom`,
# and a freeze made before the rewrite then sits outside it.
# The build and fix steps write no subject of their own. `agents/implementer.md` asks for "a
# one-line message naming this unit" and `agents/fixer.md` for one "naming this round", so the
# words are the model's and no check may rest on them. Those two kinds stay record-read, and the
# folders a record may sit in are found by their own names. That is the plugin's own naming and
# not a guess: `retake-tests` writes `retaken-<order>-<n>/` and `restart` writes
# `implementation-<date>-<commit>/`.
# Without this the live task restarted on beta.22 answered one commit against four on the branch:
# the superseded freeze was in no record at all, and the build and fix records sat in a retake
# folder the restart's own ledger reset had stopped naming (live-run row 182).
rs_order_commits() {
  local task="$1" codepath="$2" one_id="$3" ledger="$4" impl="$1/implementation"
  local out='[]' c old range file kind dir files started span table="" lost="" unit_json
  unit_json="$(jq -c --arg id "$one_id" '[ (.workOrders // [])[] | select(.id == $id) ][0] // {id: $id}' \
    "$impl/snapshot.json" 2>/dev/null)"
  [ -n "$unit_json" ] || unit_json="$(jq -nc --arg id "$one_id" '{id: $id}')"
  # `git log --grep` reads the whole message, so it only narrows the candidates; the subject test
  # below decides. HEAD alone when the ledger holds no usable startedFrom, which no ledger this
  # stage writes does: the field is required, and the wider search still answers this order.
  started="$(printf '%s' "$ledger" | jq -r '.startedFrom // empty' 2>/dev/null)"
  span=HEAD
  if [ -n "$started" ] && git -C "$codepath" merge-base --is-ancestor "$started" HEAD >/dev/null 2>&1; then
    span="$started..HEAD"
  fi
  table="$(rs_rebase_table "$codepath" "$span" "$ledger")"
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    c="$(rs_on_branch "$codepath" "$c" "$table")"
    case "$c" in ""|"?"*) continue ;; esac
    case "$(git -C "$codepath" log -1 --format=%s "$c" 2>/dev/null)" in
      "Freeze the tests of $one_id through the implement skill:"*) ;;
      *) continue ;;
    esac
    out="$(printf '%s' "$out" | jq -c --arg id "$one_id" --arg c "$c" '
      if any(.[]; .commit == $c) then . else . + [{order: $id, kind: "freeze", commit: $c, range: $c}] end')"
  done <<RS_FREEZES
$(git -C "$codepath" log --reverse --format=%H --fixed-strings \
  --grep="Freeze the tests of $one_id through the implement skill:" "$span" 2>/dev/null
jq -r '.commit // empty' "$impl/tests-$one_id.json" 2>/dev/null
find "$task" -mindepth 2 -maxdepth 2 -path "*/implementation-*/tests-$one_id.json" \
  -exec jq -r '.commit // empty' {} ';' 2>/dev/null
printf '%s' "$ledger" | jq -r --arg id "$one_id" \
  '([ (.orders // [])[] | select(.id == $id) ][0].retakes // [])[] | .freezeCommit // empty' 2>/dev/null)
RS_FREEZES
  # Every folder a build or fix record of this order can sit in: the top of the implementation
  # folder, the retake folders under it, the folders an earlier restart wrote, and the retake
  # folders inside those. Found by name, and the ledger's `movedTo` is read too because it is the
  # one place a retake folder a person renamed is still named. A folder or a record a person
  # removed holds nothing, which is not fatal.
  files="$impl/build-$one_id.json
$(find "$impl" -mindepth 1 -maxdepth 1 -name "fix-$one_id-*.json" 2>/dev/null | sort)"
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    files="$files
$dir/build-$one_id.json
$(find "$dir" -mindepth 1 -maxdepth 1 -name "fix-$one_id-*.json" 2>/dev/null | sort)"
  done <<RS_RETAKEN
$(printf '%s' "$ledger" | jq -r --arg id "$one_id" \
  '([ (.orders // [])[] | select(.id == $id) ][0].retakes // [])[] | .movedTo // empty' 2>/dev/null
find "$impl" -mindepth 1 -maxdepth 1 -type d -name "retaken-$one_id-*" 2>/dev/null | sort
find "$task" -mindepth 1 -maxdepth 1 -type d -name "implementation-*" 2>/dev/null | sort
find "$task" -mindepth 2 -maxdepth 2 -type d -path "*/implementation-*/retaken-$one_id-*" 2>/dev/null | sort)
RS_RETAKEN
  while IFS= read -r file; do
    [ -f "$file" ] || continue
    range="$(jq -r 'select(.startedAt != null and .commit != null) | .startedAt + ".." + .commit' "$file" 2>/dev/null)"
    [ -n "$range" ] || continue
    case "$file" in */build-*) kind=build ;; *) kind=fix ;; esac
    while IFS= read -r c; do
      [ -n "$c" ] || continue
      old="$c"
      c="$(rs_on_branch "$codepath" "$c" "$table")"
      case "$c" in
        "") continue ;;
        "?"*) lost="$lost$kind	$old	${c#?}
"; continue ;;
      esac
      # A fix record's range names its commit, so it outranks a build record that claims the same
      # commit only by reading the span through im_order_commits.
      out="$(printf '%s' "$out" | jq -c --arg id "$one_id" --arg kind "$kind" --arg c "$c" --arg range "$range" '
        if any(.[]; .commit == $c) then
          (if $kind == "fix" then map(if .commit == $c and .kind == "build" then .kind = "fix" | .range = $range else . end) else . end)
        else . + [{order: $id, kind: $kind, commit: $c, range: $range}] end')"
    done <<RS_RANGE
$(if [ "$kind" = "build" ] && [ "$span" != HEAD ]; then
    im_order_commits "$codepath" "$started" "${range#*..}" "$unit_json" "$(dirname "$file")" | sed -n 's/^own //p'
  else
    git -C "$codepath" rev-list --reverse "$range" 2>/dev/null
  fi)
RS_RANGE
  done <<RS_FILES
$files
RS_FILES
  # A restart from before restart reverted (gap row 252) left this order's commits on the branch
  # when the person answered carry. Its own `restarted.json` names them under `commits`, with the
  # kind, which is the one place the freeze commit of that build survives. A restart now writes
  # `reverted` instead, so this reads only those older records.
  while IFS= read -r file; do
    [ -f "$file" ] || continue
    while IFS= read -r c; do
      [ -n "$c" ] || continue
      old="$c"
      c="$(rs_on_branch "$codepath" "$c" "$table")"
      case "$c" in
        "") continue ;;
        "?"*)
          kind="$(jq -r --arg old "$old" '[ (.commits // [])[] | select(.commit == $old) ][0].kind // "build"' "$file")"
          [ "$kind" = "freeze" ] || lost="$lost$kind	$old	${c#?}
"
          continue ;;
      esac
      out="$(jq -c --arg old "$old" --arg c "$c" --argjson have "$out" '
        ([ (.commits // [])[] | select(.commit == $old) ] | .[0]) as $e
        | if $e == null or ($have | any(.[]; .commit == $c)) then $have else $have + [$e | .commit = $c] end' "$file")"
    done <<RS_PRIOR
$(jq -r --arg id "$one_id" '(.commits // [])[] | select(.order == $id) | .commit' "$file" 2>/dev/null)
RS_PRIOR
  done <<RS_ARCHIVES
$(find "$task" -mindepth 2 -maxdepth 2 -path "*/implementation-*/restarted.json" 2>/dev/null | sort)
RS_ARCHIVES
  # A commit reverted on this branch, by `restart` or by a person, is code the tree no longer holds
  # (gap row 252).
  if [ "$(printf '%s' "$out" | jq 'length')" -gt 0 ]; then
    out="$(jq -cn --argjson have "$out" --arg gone "$(rs_reverted "$codepath" "$span" "$table")" \
      '($gone | split("\n")) as $g | [ $have[] | select(.commit as $c | $g | index($c) | not) ]')"
  fi
  # The blocks above read the records wherever they sit, and a restart moves them, so one order's
  # commits came out in one order before a restart and another after. They are sorted into the
  # order the branch holds them, oldest first, so `restart` and `start` print one list and a
  # person can check it against git log.
  if [ "$(printf '%s' "$out" | jq 'length')" -gt 0 ]; then
    out="$(jq -cn --argjson have "$out" --argjson order "$(git -C "$codepath" rev-list --reverse --topo-order HEAD 2>/dev/null \
      | grep -F -x -f <(printf '%s' "$out" | jq -r '.[].commit') \
      | jq -R -s 'split("\n") | map(select(length > 0))')" \
      '[ $order[] as $c | $have[] | select(.commit == $c) ]')"
  fi
  # A commit the records name that a rebase left with no copy here comes last, marked `missing`
  # with the reason, so every reader can say what it could not find. `restart` skips these.
  if [ -n "$lost" ]; then
    out="$(printf '%s' "$lost" | jq -Rsc --arg id "$one_id" --argjson have "$out" '
      $have + ([ split("\n")[] | select(length > 0) | split("\t")
                 | {order: $id, kind: .[0], commit: .[1], range: .[1], missing: .[2]} ]
               | unique_by(.commit)
               | map(. as $l | select(($have | any(.[]; .commit == $l.commit)) | not)))')"
  fi
  printf '%s' "$out"
}

# The build and fix commits HEAD still holds of every order a restart or a retake sent back to the
# tests step, as rs_order_commits shapes them, or [] when there is none. $1 the task folder, $2 the
# code repository, $3 an order id to keep alone, or empty for every order, $4 the ledger document.
# `start` prints them as the partialBuild line, `tests-brief` carries them under treeHolds, and
# `tests-freeze` checks a commit: reason against them. One list for all three, so the line offers
# exactly what the freeze accepts.
#
# Which orders. Every restart record names the orders it halted, and every one is read, not the
# newest alone: a later restart of another order leaves an earlier one's commits on the branch. An
# order restarted twice is asked for once, because rs_order_commits already reads every folder and
# record either restart wrote. A retake needs no restart: the ledger entry's `retakes` names it. Its
# corrected test can arrive green on the order's own build as surely as after a restart, so it takes
# the same route.
#
# Which commits. A build or a fix commit only, since those are what a commit: reason may cite. A
# freeze holds tests, and no reader of this list acts on one: the test author reads no source, and
# `restart` leaves every freeze commit in the tree.
#
# When. An order rebuilt since it was sent back is left out. `restart` resets the entry to not
# started and `retake-tests` to tests-frozen, so a build step on the entry came later. Rebuilt means
# code-written or any step after it, closed included. A freeze alone is not a rebuild. The ledger
# decides and not the commit order, because a rebase rewrites every id and the ledger survives it.
# An order the ledger does not hold, or a ledger nothing could read, keeps its line.
rs_carried_commits_in_head() {
  local task="$1" codepath="$2" only="$3" ledger="$4" one out='[]'
  while IFS= read -r one; do
    [ -n "$one" ] || continue
    case "$(printf '%s' "$ledger" | jq -r --arg id "$one" \
      '[ (.orders // [])[] | select(.id == $id) ][0].lastStep // "none"' 2>/dev/null)" in
      ""|none|tests-frozen) ;;
      *) continue ;;
    esac
    out="$(jq -cn --argjson have "$out" \
      --argjson more "$(rs_order_commits "$task" "$codepath" "$one" "$ledger")" \
      '$have + [ $more[] | select(.kind != "freeze") ]')"
  done <<RS_ORDERS
$({ find "$task" -mindepth 2 -maxdepth 2 -path "*/implementation-*/restarted.json" \
    -exec jq -r '(.ordersHaltedForDrift // [])[]' {} ';'
  printf '%s' "$ledger" | jq -r '(.orders // [])[] | select((.retakes // []) | length > 0) | .id'
} 2>/dev/null | { if [ -n "$only" ]; then grep -Fx -- "$only"; else cat; fi; } | LC_ALL=C sort -u)
RS_ORDERS
  printf '%s' "$out"
}

do_restart() {
  local task_arg="" reason=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --reason)
        [ "$#" -ge 2 ] || die 3 "restart: --reason needs the reason this build starts again"
        [ -n "$2" ] || die 3 "restart: --reason was given an empty reason."
        halt_refuse_separator "restart" "--reason" "$2"
        reason="$2"; shift 2 ;;
      -*) die 3 "restart: unrecognized argument: $1" ;;
      *)
        if [ -z "$task_arg" ]; then
          task_arg="$1"
        else
          die 3 "restart: unrecognized extra argument: $1"
        fi
        shift ;;
    esac
  done
  [ -n "$task_arg" ] || die 3 "restart: a task folder is required"
  [ -n "$reason" ]   || die 3 "restart: --reason is required. A restart with no reason leaves the next reader guessing what design changed."

  local resolve_rc
  TASK_PATH="$(resolve_task_folder "$task_arg" "restart")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  IMPL_DIR="$TASK_PATH/implementation"

  fn_load_task_state "restart"
  fn_require_interactive "restart" "restarting a build against a changed design"

  # Exit 69. Every drift halt `start` writes begins with "design drift: ", so this reads the halt
  # reasons rather than re-deriving the drift itself: the drift was already worked out, order by
  # order, by the run that halted them. A halt written later puts its own reason first and the drift
  # after "; earlier: ", so this tests every segment and never only the front of the text.
  local drifted
  drifted="$(printf '%s' "$FN_LEDGER_DOC" | jq -r '
      [ (.orders // [])[]
        | select(((.haltedBecause // "") | split("; earlier: ")) | map(startswith("design drift: ")) | any)
        | .id ] | join(", ")')"
  [ -n "$drifted" ] \
    || die 69 "restart: no order in $FN_LEDGER_FILE is halted for design drift, so there is nothing to restart from. Run start again to check the live design against the frozen copy."

  rv_load_codepath "restart"
  br_require_clean_tree "restart" "$RV_CODEPATH"

  # Only the halted orders start over. Their records move aside, their ledger entries go back to
  # not started, and the snapshot takes their live copies, which design must have closed on: the
  # same rule a new run applies to the whole design. Every other order keeps its freeze, its build
  # records and its place in the ledger, because nothing it was built from changed (live-run row
  # 72). An order gone from the live design has no copy to take: its records move aside the same
  # way, and it leaves the snapshot and the ledger, because a frozen copy the live design no
  # longer holds declares owned files and dependencies nothing will build (live-run row 82).
  ALIGNMENT_FILE="$TASK_PATH/alignment.json"
  DESIGN_DIR="$TASK_PATH/design"
  CLOSED_FILE="$TASK_PATH/design-closed.json"
  local drifted_ids_json live_alignment_json live_workorders_json live_hash removed_ids_json retaken_ids_json removed retaken
  drifted_ids_json="$(printf '%s' "$drifted" | jq -Rc 'split(", ")')"
  live_alignment_json="$(jq -c '.' "$ALIGNMENT_FILE" 2>/dev/null)"
  [ -n "$live_alignment_json" ] || die 3 "restart: $ALIGNMENT_FILE could not be read as JSON."
  live_workorders_json="$(gather_workorders_json "$DESIGN_DIR")"
  [ -z "$READ_FAILED" ] || die 3 "restart: $READ_FAILED is under design/ but could not be read as JSON."
  live_hash="$(records_hash_for "$TASK_PATH")" \
    || die 3 "restart: could not compute a hash over the live alignment.json and design/*.json."
  [ "$(design_closed_state)" = "ok" ] && [ "$(design_closed_hash)" = "$live_hash" ] \
    || die 13 "restart: the halted orders would be taken fresh from the live design, but $CLOSED_FILE does not record a close over the live alignment.json and design/*.json. Close design again, then run restart."
  removed_ids_json="$(jq -nc --argjson ids "$drifted_ids_json" --argjson live "$live_workorders_json" \
    '($live | map(.id)) as $l | [ $ids[] | . as $d | select(($l | index($d)) == null) ]')"
  retaken_ids_json="$(jq -nc --argjson ids "$drifted_ids_json" --argjson gone "$removed_ids_json" \
    '[ $ids[] | . as $d | select(($gone | index($d)) == null) ]')"
  removed="$(printf '%s' "$removed_ids_json" | jq -r 'join(", ")')"
  retaken="$(printf '%s' "$retaken_ids_json" | jq -r 'join(", ")')"

  local head_short today target
  head_short="$(git -C "$RV_CODEPATH" rev-parse --short HEAD 2>/dev/null)"
  [ -n "$head_short" ] \
    || die 3 "restart: could not capture the current commit (git rev-parse HEAD failed in $RV_CODEPATH)."
  today="$(date -u +%Y-%m-%d)"
  target="$TASK_PATH/implementation-$today-$head_short"
  [ ! -e "$target" ] \
    || die 3 "restart: $target already exists. A second restart on the same day at the same commit would write over the first one's records; move or remove it by hand first."

  # The records move aside, and the code a halted order committed must leave the tree too, or its
  # next test author writes against it and its rebuild finds nothing to do (gap row 252). A record
  # names only the attempts that reached build-record, so the branch is read. Every commit after
  # the order's first freeze that changes its owned files is the order's, recorded or not. Without
  # a freeze, the span opens at the ledger's startedFrom. The freeze commits stay: they hold the
  # tests, which the next test author rewrites. A commit a record names that changes no owned file
  # is the order's as well. im_commit_claim decides, the rule review-brief and close read too, so
  # a change to a shared file is the order's unless another order's record holds it (gap row 287).
  # A commit that is the order's and changes a file it does not own would take other work with it, so the restart stops before it changes anything and names the files.
  # Otherwise the script reverts each one, newest first, one revert commit each. A revert keeps the
  # history, and AIDA's own command hook refuses the hard reset that would drop it.
  local revert_json='[]' mixed="" stale="" one_id unit taken rec freezes from gone c paths p claim outside merge s l
  for one_id in $(printf '%s' "$drifted_ids_json" | jq -r '.[]'); do
    unit="$(printf '%s' "$SNAPSHOT_DOC" | jq -c --arg id "$one_id" '[ (.workOrders // [])[] | select(.id == $id) ][0] // {}')"
    taken="$(im_taken_commits "$RV_CODEPATH" "$one_id")"
    rec="$(rs_order_commits "$TASK_PATH" "$RV_CODEPATH" "$one_id" "$FN_LEDGER_DOC" | jq -r '.[] | select(has("missing") | not) | .kind + " " + .commit')"
    freezes="$(printf '%s' "$rec" | sed -n 's/^freeze //p')"
    # A test file a superseded freeze created, that no later freeze touched, is a test a person
    # ruled wrong left at an old path. Restart reverts nothing for it, and names it.
    for s in $(printf '%s' "$FN_LEDGER_DOC" | jq -r --arg id "$one_id" \
        '([ (.orders // [])[] | select(.id == $id) ][0].retakes // [])[] | .freezeCommit // empty'); do
      printf '%s\n' "$freezes" | grep -Fqx "$s" || continue
      while IFS= read -r p; do
        [ -n "$p" ] && git -C "$RV_CODEPATH" cat-file -e "HEAD:$p" 2>/dev/null || continue
        while IFS= read -r l; do
          [ -n "$l" ] && [ "$l" != "$s" ] && git -C "$RV_CODEPATH" merge-base --is-ancestor "$s" "$l" 2>/dev/null \
            && git -C "$RV_CODEPATH" diff-tree --no-commit-id --name-only -r --no-renames "$l" | grep -Fqx "$p" \
            && continue 2
        done <<RS_LATER
$freezes
RS_LATER
        stale="${stale}staleTest: $p (from superseded freeze $(git -C "$RV_CODEPATH" rev-parse --short "$s"))
"
      done <<RS_ADDED
$(git -C "$RV_CODEPATH" diff-tree --no-commit-id --name-only -r --no-renames --diff-filter=A "$s" 2>/dev/null)
RS_ADDED
    done
    from="$(git -C "$RV_CODEPATH" rev-list --reverse --topo-order HEAD 2>/dev/null | grep -F -x -f <(
      jq -r '.commit // empty' "$IMPL_DIR/tests-$one_id.json" 2>/dev/null
      printf '%s' "$FN_LEDGER_DOC" | jq -r --arg id "$one_id" \
        '([ (.orders // [])[] | select(.id == $id) ][0].retakes // [])[] | .freezeCommit // empty') | head -1)"
    [ -n "$from" ] || from="$(printf '%s' "$FN_LEDGER_DOC" | jq -r '.startedFrom // empty')"
    git -C "$RV_CODEPATH" merge-base --is-ancestor "$from" HEAD >/dev/null 2>&1 \
      || die 3 "restart: $one_id has no freeze commit and no startedFrom on this branch, so the commits made for it cannot be told apart."
    gone="$(rs_reverted "$RV_CODEPATH" "$from..HEAD" "$(rs_rebase_table "$RV_CODEPATH" "$from..HEAD" "$FN_LEDGER_DOC")")"
    for c in $(git -C "$RV_CODEPATH" rev-list --reverse --first-parent "$from..HEAD" 2>/dev/null); do
      printf '%s\n%s\n' "$gone" "$freezes" | grep -Fqx "$c" && continue
      # A merge is read by what it brought to the first parent. A revert of a merge needs a
      # person to choose the parent, so a merge that touches an owned file stops the restart.
      merge=""
      if git -C "$RV_CODEPATH" rev-parse --verify --quiet "$c^2" >/dev/null 2>&1; then
        merge=" merge"
        paths="$(git -C "$RV_CODEPATH" diff-tree --no-commit-id --name-only -r --no-renames "$c^1" "$c" 2>/dev/null)"
      else
        paths="$(git -C "$RV_CODEPATH" diff-tree --no-commit-id --name-only -r --no-renames "$c" 2>/dev/null)"
      fi
      # A commit this order's own record names is its own, so no other order's record is asked.
      if printf '%s\n' "$rec" | grep -Fqx -e "build $c" -e "fix $c"; then
        claim="$(im_commit_claim "$paths" "$unit" "$c" "")"
      else
        claim="$(im_commit_claim "$paths" "$unit" "$c" "$taken")"
        [ "$claim" != "none" ] || continue
      fi
      case "$claim" in
        own) outside="" ;;
        none) outside=" $(printf '%s' "$paths" | tr '\n' ' ' | sed 's/ $//')" ;;
        *) outside="${claim#mixed}" ;;
      esac
      if [ -z "$outside" ] && [ -z "$merge" ]; then
        revert_json="$(printf '%s' "$revert_json" | jq -c --arg id "$one_id" --arg c "$c" \
          'if any(.[]; .commit == $c) then . else . + [{order: $id, commit: $c}] end')"
      else
        mixed="$mixed; $(git -C "$RV_CODEPATH" rev-parse --short "$c") ($one_id)$(if [ -n "$merge" ]; then printf ' is a merge that changes its files'; fi)$(if [ -n "$outside" ]; then printf ' also changes%s' "$outside"; fi)"
      fi
    done
  done
  [ -z "$mixed" ] \
    || die 113 "restart: these commits change the halted order's files and files it does not own, so a revert would undo other work too: ${mixed#; }. Nothing was reverted or moved. A person splits or reverts them, then runs restart again."
  # Newest first, so each revert applies to the tree its commit left.
  revert_json="$(jq -cn --argjson have "$revert_json" --argjson order "$(git -C "$RV_CODEPATH" rev-list --topo-order HEAD 2>/dev/null \
    | grep -F -x -f <(printf '%s' "$revert_json" | jq -r '.[].commit') | jq -R -s 'split("\n") | map(select(length > 0))')" \
    '[ $order[] as $c | $have[] | select(.commit == $c) ]')"

  local new_snapshot new_hash new_ledger
  # The removed orders leave the document before the helper runs, so the one hash it re-derives
  # covers the live copies taken in and the frozen copies dropped together.
  new_snapshot="$(snapshot_with_live_orders "$(printf '%s' "$SNAPSHOT_DOC" | jq -c --argjson gone "$removed_ids_json" \
      '.workOrders = [ .workOrders[] | . as $o | select(($gone | index($o.id)) == null) ]')" "$retaken_ids_json" "$live_workorders_json" "$live_alignment_json")" \
    || die 3 "restart: could not re-derive a hash for the snapshot with the live copies taken in (see stderr above)"
  new_hash="$(printf '%s' "$new_snapshot" | jq -r '.hash')"
  # A halted order's entry goes back to what start opens it as, or leaves the list when the design
  # removed it. The judgements its freeze wrote go too, and every criterion it serves goes back to
  # not judged, since close confirms a row only once every serving order is closed.
  new_ledger="$(printf '%s' "$FN_LEDGER_DOC" | jq -c --argjson ids "$drifted_ids_json" --argjson snap "$SNAPSHOT_DOC" \
    --argjson retaken "$retaken_ids_json" --argjson gone "$removed_ids_json" \
    --arg from "$(printf '%s' "$FN_LEDGER_DOC" | jq -r '.snapshotHash')" --arg to "$new_hash" --arg at "$today" '
    ([ ($snap.workOrders // [])[] | . as $o | select(($ids | index($o.id)) != null)
       | ((.criteriaServed // []) + (.criteriaOwned // []))[] ] | unique) as $touched
    | .snapshotHash = $to
    | .orders = (.orders | map(. as $o | select(($gone | index($o.id)) == null)) | map(. as $o | if (($ids | index($o.id)) != null)
        then {id: $o.id, lastStep: null, attemptsUsed: 0, roundsUsed: 0} else $o end))
    | .criteria = (.criteria | map(. as $c
        | if (($touched | index($c.id)) == null) then $c
          else ($c | .rowState = "not-judged"
                | if has("judgements") then .judgements = [ .judgements[] | . as $j | select(($ids | index($j.unit)) == null) ] else . end)
          end))
    | .resnapshots = ((.resnapshots // []) + [ $retaken[] | {id: ., from: $from, to: $to, at: $at} ])')"
  [ -n "$new_ledger" ] || die 3 "restart: the ledger update failed."

  # A revert that stops on a conflict is taken back, so the tree is clean again. The reverts before
  # it stay committed, and a second restart skips them, because rs_reverted reads them.
  local reverted_json='[]' said
  for c in $(printf '%s' "$revert_json" | jq -r '.[].commit'); do
    said="$(git -C "$RV_CODEPATH" revert --no-edit "$c" 2>&1)" || {
      git -C "$RV_CODEPATH" revert --abort >/dev/null 2>&1
      die 3 "restart: git revert of $(git -C "$RV_CODEPATH" rev-parse --short "$c") failed, and was taken back: $said. The reverts before it are committed, and no record moved. A person resolves it, then runs restart again."
    }
    reverted_json="$(printf '%s' "$reverted_json" | jq -c --argjson e "$(printf '%s' "$revert_json" | jq -c --arg c "$c" '.[] | select(.commit == $c)')" \
      --arg r "$(git -C "$RV_CODEPATH" rev-parse HEAD)" '. + [$e + {revert: $r}]')"
  done

  mkdir -p "$target" || die 3 "restart: could not create $target"
  # The reason is written beside the records moved aside, because they are what it explains.
  local restart_json
  restart_json="$(jq -n --arg restartedAt "$today" --arg reason "$reason" --arg head "$head_short" \
    --argjson drifted "$drifted_ids_json" --argjson removed "$removed_ids_json" \
    --argjson reverted "$reverted_json" \
    '{schemaVersion: 1, restartedAt: $restartedAt, reason: $reason, headCommit: $head,
      ordersHaltedForDrift: $drifted, ordersRemoved: $removed, reverted: $reverted}')"
  write_atomic "$target/restarted.json" "$restart_json"
  # Every per-order file is <kind>-<id>.<ext> or <kind>-<id>-<rest>: the frozen tests, the red
  # runs, the briefs, the build, review, fix and verify records, the diffs, the reports and the
  # interface record. find, not a glob: zsh stops on a glob with no match. A folder whose name
  # carries the id is the order's too, such as the test author's <id>-red-runs/, so a red run of a
  # test that no longer exists leaves with its order (gap row 229).
  local moved
  for one_id in $(printf '%s' "$drifted_ids_json" | jq -r '.[]'); do
    while IFS= read -r moved; do
      [ -n "$moved" ] || continue
      mv "$moved" "$target/" || die 3 "restart: could not move $moved to $target"
    done < <(find "$IMPL_DIR" -mindepth 1 -maxdepth 1 \( -type f -o -type d \) \
      \( -name "*-$one_id.*" -o -name "*-$one_id-*" -o -name "$one_id-*" -o -name "*-$one_id" \) 2>/dev/null)
  done
  write_atomic "$IMPL_DIR/snapshot.json" "$new_snapshot"
  write_atomic "$FN_LEDGER_FILE" "$new_ledger"

  echo "RESTART: records of $drifted moved to $target; every other order keeps its records."
  [ -z "$removed" ] \
    || echo "RESTART: the design removed $removed; each leaves the snapshot and the ledger and is not taken fresh."
  [ -z "$retaken" ] \
    || echo "RESTART: $retaken start over from the live design."
  if [ "$reverted_json" = "[]" ]; then
    echo "reverted: none, no commit of a halted order is in the tree"
  else
    printf '%s' "$reverted_json" | jq -r '.[] | "reverted: " + .commit[0:7] + " " + .order + " by " + .revert[0:7]'
  fi
  printf '%s' "$stale"
  echo "RESTART: run start on this task to continue."
  printf '%s\n' "$target"
  exit 0
}

# unattributed: the commits since the build started that no order's records account for, one
# line each, "unattributed: <commit> <subject>", or "unattributed: none". Read only. Review's
# serves check prints them, because their files can match an order's ownedFiles while no order's
# review read them (gap row 287). An order accounts for a commit its records name (rs_order_commits),
# one inside its closed commitRange, and one a restart reverted, with its revert. A commit that
# changes only files AIDA itself writes, the compromises log and the files `task environment up`
# recorded, is AIDA's own.
do_unattributed() {
  [ "$#" -eq 1 ] || die 3 "unattributed: one task folder is required"
  local resolve_rc
  TASK_PATH="$(resolve_task_folder "$1" "unattributed")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  IMPL_DIR="$TASK_PATH/implementation"
  fn_load_task_state "unattributed"
  rv_load_codepath "unattributed"
  local started known one c p ours found=""
  started="$(printf '%s' "$FN_LEDGER_DOC" | jq -r '.startedFrom // ""')"
  [ -n "$started" ] || die 3 "unattributed: $FN_LEDGER_FILE holds no startedFrom, though start writes it."
  known="$(
    for one in $(printf '%s' "$FN_LEDGER_DOC" | jq -r '(.orders // [])[].id'); do
      rs_order_commits "$TASK_PATH" "$RV_CODEPATH" "$one" "$FN_LEDGER_DOC" | jq -r '.[] | select(has("missing") | not) | .commit'
    done
    printf '%s' "$FN_LEDGER_DOC" | jq -r '(.orders // [])[] | select(.lastStep == "closed") | .commitRange // empty' \
      | while IFS= read -r one; do [ -z "$one" ] || git -C "$RV_CODEPATH" rev-list "$one" 2>/dev/null; done
    find "$TASK_PATH" -mindepth 2 -maxdepth 2 -path "*/implementation-*/restarted.json" \
      -exec jq -r '(.reverted // [])[] | .commit, .revert' {} ';' 2>/dev/null)"
  for c in $(git -C "$RV_CODEPATH" rev-list --reverse "$started..HEAD" 2>/dev/null); do
    printf '%s\n' "$known" | grep -Fqx -- "$c" && continue
    ours=true
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      [ "$p" = "$COMPROMISES_FILE" ] || task_env_recipe_change "$TASK_PATH" "$p" "$RV_CODEPATH" "$c" || ours=false
    done <<UA_PATHS
$(git -C "$RV_CODEPATH" diff-tree --no-commit-id --name-only -r --no-renames "$c" 2>/dev/null)
UA_PATHS
    [ "$ours" = "false" ] || continue
    found=yes
    echo "unattributed: $(git -C "$RV_CODEPATH" log -1 --format='%h %s' "$c")"
  done
  [ -n "$found" ] || echo "unattributed: none"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# dispatch-open, dispatch-close: open and clear <task_folder>/implementation/dispatch.json
# (scripts/dispatch-schema.json), the one record hooks/deny-prior-source.sh and
# hooks/deny-frozen-test-writes.sh read to tell a dispatched role apart from a person working
# their own repository. The build of one task is serial, so a task has at most one active
# dispatch. dispatch-open refuses to overwrite one already there (exit 37). dispatch-close
# removes it, safe to call when none is open. Two tasks of one project each hold their own.
# ------------------------------------------------------------------------------------------------

# im_scan_leftovers <code path> <work orders json>: the files a stopped role left in the tree (gap
# row 217). Sets LO_LEFTOVERS_JSON, one {path, status, orders} per path git reports changed or
# untracked, with the orders whose owned files hold it. Sets LO_TRACKED to the changes that cannot
# move aside: a change other than an untracked or a modified file. A gitignored file is not read.
# COMPROMISES.md is AIDA's own file, so it is not named. `-uall` names each file in a new folder,
# because only a file meets an owned-file entry. `-z` leaves a name unquoted. git_status_of passes
# neither flag, so this reads git directly. `start` and `dispatch-open` both call it.
LO_TEXT_JQ='.[] | .path + " (" + (if (.orders | length) > 0 then (.orders | join(", ")) else "no order owns it" end) + ")"'
im_scan_leftovers() {
  local lo_status lo_line lo_xy lo_rel lo_owners lo_id lo_glob lo_tab lo_orders_tsv lo_skip=false
  LO_LEFTOVERS_JSON='[]'; LO_TRACKED=""
  lo_tab="$(printf '\t')"
  lo_orders_tsv="$(printf '%s' "$2" | jq -r '.[] | .id as $id | (.ownedFiles // [])[] | $id + "\t" + .' 2>/dev/null)"
  lo_status="$(git -C "$1" status --porcelain -z --untracked-files=all 2>/dev/null | tr '\0' '\n')"
  while IFS= read -r lo_line; do
    # A rename or a copy carries its source name as the next field. It refuses as it is.
    if [ "$lo_skip" = "true" ]; then lo_skip=false; continue; fi
    [ -n "$lo_line" ] || continue
    lo_xy="$(printf '%s' "$lo_line" | cut -c1-2)"
    lo_rel="${lo_line#???}"
    case "$lo_xy" in R*|C*|?R|?C) lo_skip=true ;; esac
    [ "$lo_rel" != "$COMPROMISES_FILE" ] || continue
    lo_owners=""
    while IFS="$lo_tab" read -r lo_id lo_glob; do
      [ -n "$lo_id" ] && tf_path_matches_catalog_glob "$lo_rel" "$lo_glob" || continue
      case ",$lo_owners," in *",$lo_id,"*) ;; *) lo_owners="${lo_owners:+$lo_owners,}$lo_id" ;; esac
    done <<LO_ORDERS
$lo_orders_tsv
LO_ORDERS
    case "$lo_xy" in '??'|' M'|'M '|'MM') ;; *) LO_TRACKED="$LO_TRACKED$lo_rel ($lo_xy), " ;; esac
    LO_LEFTOVERS_JSON="$(printf '%s' "$LO_LEFTOVERS_JSON" | jq -c --arg p "$lo_rel" --arg xy "$lo_xy" --arg o "$lo_owners" \
      '. + [{path: $p, status: $xy, orders: ($o | split(",") | map(select(length > 0)))}]')"
  done <<LO_STATUS
$lo_status
LO_STATUS
}

# Prints the test tree path $1 lies in, or nothing when $1 is not a test-tree file. $2 holds the
# test globs, one per line. A directory a glob names literally, `tests` in `**/tests/**/*Test.php`,
# makes the tree the path up to its last such segment, because the author writes base classes and
# fixtures there too (live-run row 67). A glob with no literal directory, Go's `**/*_test.go`,
# makes the tree the directory of a file the glob matches.
im_test_tree_root() {
  local p="${1%/}" g seg pre cand root=""
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    while IFS= read -r seg; do
      case "$seg" in *'*'*|*'?'*|*'['*|'') continue ;; esac
      case "/$p/" in
        */"$seg"/*)
          pre="/$p/"; pre="${pre%/"$seg"/*}"; pre="${pre#/}"
          cand="${pre:+$pre/}$seg"
          [ "${#cand}" -le "${#root}" ] || root="$cand" ;;
      esac
    done <<TT_SEGS
$(printf '%s' "${g%/*}" | tr '/' '\n')
TT_SEGS
  done <<TT_GLOBS
$2
TT_GLOBS
  if [ -z "$root" ]; then
    while IFS= read -r g; do
      [ -n "$g" ] || continue
      tf_path_matches_catalog_glob "$p" "$g" && { root="$(dirname "$p")"; break; }
    done <<TT_GLOBS
$2
TT_GLOBS
  fi
  printf '%s' "$root"
}

# Exit 102. br_order_needs decides which roles a proof kind needs, and this reads its answer. A
# role the kind does not need would judge nothing. Examples are a test author on an order that
# freezes no test, and a row-checker on one with no row. $1 the bare role, $2 the order id.
# SNAPSHOT_DOC is loaded.
im_refuse_unneeded_role() {
  case " $BR_KIND_ROLES " in *" $1 "*) ;; *) return 0 ;; esac
  br_order_needs "$(printf '%s' "$SNAPSHOT_DOC" | jq -c --arg u "$2" '[ .workOrders[] | select(.id == $u) ][0]')"
  case " $BR_ORDER_ROLES " in
    *" $1 "*) ;;
    *) die 102 "dispatch-open: $2 is proved by its $(printf '%s' "$SNAPSHOT_DOC" | jq -r --arg u "$2" '[ .workOrders[] | select(.id == $u) ][0].proof // "tests"'), so it needs only these roles: $BR_ORDER_ROLES. A $1 here would have nothing to judge. Read the roles on the order's line in \`read\`." ;;
  esac
}

do_dispatch_open() {
  local task_arg="" role="" unit_id="" deny_raw="" allow_raw="" test_glob_raw="" resume=false
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --resume) resume=true; shift ;;
      --deny-read)
        [ "$#" -ge 2 ] || die 3 "dispatch-open: --deny-read needs a path relative to codePath"
        deny_raw="$deny_raw$2
"
        shift 2 ;;
      --allow-write)
        [ "$#" -ge 2 ] || die 3 "dispatch-open: --allow-write needs a path relative to codePath"
        allow_raw="$allow_raw$2
"
        shift 2 ;;
      --test-glob)
        [ "$#" -ge 2 ] || die 3 "dispatch-open: --test-glob needs a glob from the implement recipe"
        test_glob_raw="$test_glob_raw$2
"
        shift 2 ;;
      -*) die 3 "dispatch-open: unrecognized argument: $1" ;;
      *)
        if [ -z "$task_arg" ]; then
          task_arg="$1"
        elif [ -z "$role" ]; then
          role="$1"
        elif [ -z "$unit_id" ]; then
          unit_id="$1"
        else
          die 3 "dispatch-open: unrecognized extra argument: $1"
        fi
        shift ;;
    esac
  done
  [ -n "$task_arg" ] || die 3 "dispatch-open: a task folder is required"
  [ -n "$role" ]     || die 3 "dispatch-open: a role is required"

  # A role must name an agent this plugin ships. The agents/ folder is that list, read here rather
  # than copied into this file, because a copy goes stale the first time a role is added. Nothing
  # else validates the name: a misspelled role opens a record no agent's payload can ever match,
  # and both hooks then allow everything in silence (ideal/agents.md, rule 3). The runtime reports
  # an agent type in two forms, `<plugin>:<role>` and the bare name, so both are accepted and only
  # the part after the last colon is compared.
  local role_bare agents_dir known_list
  role_bare="${role##*:}"
  agents_dir="$PLUGIN_ROOT/agents"
  known_list="$(md_basenames_in "$agents_dir")"
  [ -n "$known_list" ] \
    || die 46 "dispatch-open: no agent definitions were found in $agents_dir, so no role name can be checked. This plugin's own files are incomplete; nothing about the task is wrong."
  case " $known_list" in
    *" $role_bare "*) ;;
    *) die 46 "dispatch-open: $role names no agent this plugin ships, so a dispatch under it would run with no permission applied. The roles that exist are: $known_list" ;;
  esac
  [ -n "$unit_id" ]  || die 3 "dispatch-open: a unit id is required"
  # The schema pattern is ^wo[1-9][0-9]*$, and a looser glob here opened a record under an id no
  # other record in this stage uses. A `case` glob cannot say "digits to the end", so the digits
  # are checked on their own.
  case "$unit_id" in
    wo[1-9]) ;;
    wo[1-9]*)
      case "${unit_id#wo}" in
        *[!0-9]*) die 3 "dispatch-open: a unit id looks like wo1, wo2, ...; got: $unit_id" ;;
      esac
      ;;
    *) die 3 "dispatch-open: a unit id looks like wo1, wo2, ...; got: $unit_id" ;;
  esac

  local resolve_rc
  TASK_PATH="$(resolve_task_folder "$task_arg" "dispatch-open")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"

  local task_id
  task_id="$(jq -r '.id // empty' "$TASK_PATH/task.json" 2>/dev/null)"
  [ -n "$task_id" ] || die 3 "dispatch-open: $TASK_PATH/task.json has no usable id field"

  local codepath
  rv_load_codepath "dispatch-open"
  codepath="$RV_CODEPATH"

  # The test author's one denial is that it cannot read production source, and production source is
  # what every work order declares it owns. The list is derived here, from the frozen snapshot,
  # rather than typed on the command line: a denial assembled per dispatch is a judgement made in
  # the moment, which is what the withheld list exists to stop, and an empty denyRead makes the
  # read hook allow every path. Every order's owned files are denied, this unit's included: the
  # test author may not read the source it is writing tests for either (ideal/agents.md,
  # test-author). Reading its own tests back is untouched, because a test file is not an owned file.
  # Both building roles take their path lists from the frozen snapshot, so both need the unit to be
  # in it. A unit that is not says so in those words: without this check a mistyped id reports as an
  # order that declares no owned file, which sends a reader to design to fix something that is fine.
  if [ "$role_bare" = "test-author" ] || [ "$role_bare" = "row-checker" ] \
     || [ "$role_bare" = "implementer" ] || [ "$role_bare" = "fixer" ]; then
    IMPL_DIR="$TASK_PATH/implementation"
    tt_load_snapshot "dispatch-open"
    local unit_present
    unit_present="$(printf '%s' "$SNAPSHOT_DOC" | jq -r --arg u "$unit_id" \
      '[ .workOrders[]? | select(.id == $u) ] | length')"
    [ "$unit_present" = "0" ] \
      && die 22 "dispatch-open: $unit_id is not a work order in $IMPL_DIR/snapshot.json. The snapshot is what the build is frozen against, so an order added to design after start is not in it."
    im_refuse_unneeded_role "$role_bare" "$unit_id"
    # The row-checker's whole job is reading the named tests, and design lists an order's tests under
    # ownedFiles. Without the globs the derivation below cannot tell an owned test from owned source,
    # so it denied the checker the very files it was dispatched to read (live-run row 106). The
    # checkpoint runs before the freeze, so no frozen record holds the globs yet; the call carries
    # them, the same values tests-freeze takes. An order with no test row puts only its routed
    # absence clauses to the checker (gap row 273), and those name no test file.
    if [ "$role_bare" = "row-checker" ] && [ -z "$test_glob_raw" ] \
       && { [ "$BR_ORDER_SLOT" = "order-tests" ] || [ "$BR_ORDER_SLOT" = "done-when" ]; }; then
      die 3 "dispatch-open: row-checker needs --test-glob <glob>, one per pattern the implement recipe declares. The checker reads the named tests, and the globs decide which owned files stay readable; without them every owned test file is denied."
    fi
    # The implementer builds from the brief, so it is refused wherever build-brief would refuse on
    # the order's records. No record opens for a build that has no brief (gap rows 267 and 281).
    # The fixer needs a fix brief, which a review writes after a build record.
    [ "$role_bare" != "implementer" ] || im_require_build_ready "dispatch-open" "$unit_id" 114 \
      "$(printf '%s' "$SNAPSHOT_DOC" | jq -c --arg u "$unit_id" '[ .workOrders[] | select(.id == $u) ][0]')"
  fi

  # The reviewer reads the brief review-brief writes, or verify-brief after a fix round. Without it
  # the record opens with no reportPath, and dispatch-close has nothing to check (gap row 267).
  local rv_brief="" rv_step
  if [ "$role_bare" = "reviewer" ]; then
    rv_step="$(jq -r --arg id "$unit_id" '[ (.orders // [])[] | select(.id == $id) ][0]
        | if .lastStep == "fixed" then "verify-\(.roundsUsed // 0)" else "review" end' \
      "$TASK_PATH/implementation/ledger.json" 2>/dev/null)"
    [ -n "$rv_step" ] || rv_step="review"
    rv_brief="$TASK_PATH/implementation/brief-$unit_id-$rv_step.json"
    [ -f "$rv_brief" ] \
      || die 115 "dispatch-open: $rv_brief not found, so a reviewer of $unit_id has no brief. Run ${rv_step%%-*}-brief on $unit_id first. Nothing was dispatched."
  fi

  # The row-checker takes the test author's derivation exactly. It reads a criterion's verify clause
  # and the test named against it, and answers whether the one observes the other. Reading the
  # implementation would let it answer from the code rather than from the test, which is the whole
  # failure the checkpoint exists to catch (ideal/implementation.md, "The trace matrix and its
  # checkpoint").
  if [ "$role_bare" = "test-author" ] || [ "$role_bare" = "row-checker" ]; then
    local owned_json owned_count kept="" f g is_test seg
    # An owned file that matches a test-file glob is a test, not production source: design lists
    # an order's tests under ownedFiles so the overlap check sees them, and denying them here
    # denied the test author the one file it was dispatched to write (live-run row 58). The globs
    # are the implement recipe's own, the ones tests-freeze pins, so a framework whose tests sit
    # beside the source (Go) keeps every source file denied; an allowed directory would not. A
    # glob was written for the delete guard and names test cases only; the author also writes
    # base classes, traits and fixtures under the same test tree (live-run row 67). So an owned
    # file under a directory the glob names literally, such as `tests` in `**/tests/**/*Test.php`,
    # is a test-tree file too. A glob with no literal directory, Go's `**/*_test.go`, adds none.
    # A path an order reuses is production source that no order owns, and the brief carries its
    # interface so the author never needs the file (live-run row 69). It joins the owned files here
    # and is denied below even where a test glob matches it, so the hook catches an accidental read.
    owned_json="$(printf '%s' "$SNAPSHOT_DOC" | jq -c \
      '[.workOrders[]?.ownedFiles[]?] + [.workOrders[]?.reuses[]?.path] | unique')"
    if [ -n "$test_glob_raw" ]; then
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        [ -n "$(im_test_tree_root "$f" "$test_glob_raw")" ] || kept="$kept$f
"
      done <<TG_OWNED
$(printf '%s' "$owned_json" | jq -r '.[]')
TG_OWNED
      owned_json="$(printf '%s' "$kept" | jq -R -s 'split("\n") | map(select(length>0))')"
    fi
    owned_count="$(printf '%s' "$owned_json" | jq 'length' 2>/dev/null)"
    [ -n "$owned_count" ] || owned_count=0
    [ "$owned_count" -gt 0 ] 2>/dev/null \
      || die 47 "dispatch-open: no work order in $IMPL_DIR/snapshot.json declares an owned file outside the test globs, so a $role_bare would be dispatched with nothing denied and could read every file in the repository. Design has to name what each order owns before the tests for it are written."
    # The freeze refuses a test in a file the order does not own (gap row 249). Refused here, before
    # the author spends its run, when the order owns no file a test glob matches and no directory.
    if [ "$role_bare" = "test-author" ] && [ -n "$test_glob_raw" ]; then
      is_test=false
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in */) is_test=true; break ;; esac
        [ ! -d "$codepath/$f" ] || { is_test=true; break; }
        while IFS= read -r g; do
          [ -n "$g" ] || continue
          tf_path_matches_catalog_glob "$f" "$g" && { is_test=true; break; }
        done <<TG_GLOBS
$test_glob_raw
TG_GLOBS
        [ "$is_test" = false ] || break
      done <<TG_OWN
$(printf '%s' "$SNAPSHOT_DOC" | jq -r --arg u "$unit_id" '.workOrders[]? | select(.id == $u) | .ownedFiles[]?')
TG_OWN
      [ "$is_test" = true ] \
        || die 47 "dispatch-open: $unit_id owns no file a test glob matches, and no directory, so the freeze would refuse every test its author writes. Design adds the order's test file with add-owned-file and closes again. Nothing was dispatched."
    fi
    # The test-glob filter keeps only this order's own test files readable. A reused file under the
    # test tree, such as a shared kernel base class, shows its shape as surely as source does, and
    # another order's test shows the same shape by its calls (gap rows 248, 249). So every reuse
    # path and every other order's owned file is denied whatever the globs say. An entry that is
    # or holds one of this order's own test files stays readable, or the hook would deny that too.
    local own_tests_json
    own_tests_json="$(printf '%s' "$SNAPSHOT_DOC" | jq -c --arg u "$unit_id" --argjson kept "$owned_json" \
      '[ .workOrders[]? | select(.id == $u) | .ownedFiles[]? ] - $kept')"
    owned_json="$(printf '%s' "$SNAPSHOT_DOC" | jq -c --arg u "$unit_id" --argjson kept "$owned_json" \
      --argjson own "$own_tests_json" '
      ([ .workOrders[]? | select(.id != $u) | .ownedFiles[]? ] + [ .workOrders[]?.reuses[]?.path ])
      | map(select(. as $d | ($d | rtrimstr("/")) as $r
          | all($own[]; . != $d and . != $r and (startswith($r + "/") | not))))
      | . + $kept | unique')"
    # A test no order owns shows a reuse's shape by its calls as well (live task
    # event-archive-lookahead, four earlier kernel tests). So every file git tracked at the commit
    # the build started from, in a test tree an order owns or reuses from, is denied too. Only those
    # trees: a repository that commits its framework's core and contrib holds thousands of tests,
    # which carry no project reuse's shape and are the fair place to look up a framework base
    # class. This order's own test files stay readable, and so do the support files its frozen
    # record holds: after a rejected row the author repairs its own committed base class. A file
    # the author writes is untracked, and stays readable.
    local base roots="" r tracked tracked_json='[]' own_support
    if [ -n "$test_glob_raw" ]; then
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        r="$(im_test_tree_root "$f" "$test_glob_raw")"
        [ -z "$r" ] || roots="$roots$r
"
      done <<TG_ROOTS
$(printf '%s' "$SNAPSHOT_DOC" | jq -r '.workOrders[]? | (.ownedFiles // [])[], ((.reuses // [])[].path)')
TG_ROOTS
    fi
    if [ -n "$roots" ]; then
      base="$(jq -r '.startedFrom // empty' "$IMPL_DIR/ledger.json" 2>/dev/null)"
      [ -n "$base" ] || die 3 "dispatch-open: $IMPL_DIR/ledger.json holds no startedFrom, so the tests tracked at the build's start could not be listed. Run start again."
      tracked="$(printf '%s' "$roots" | sort -u | while IFS= read -r r; do
          [ -n "$r" ] || continue
          git -C "$codepath" ls-tree -r --name-only "$base" -- "$r" || exit 1
        done)" \
        || die 3 "dispatch-open: git ls-tree failed on $base in $codepath, so the tracked test files could not be listed."
      tracked_json="$(printf '%s\n' "$tracked" | while IFS= read -r f; do
          [ -n "$f" ] || continue
          [ -z "$(im_test_tree_root "$f" "$test_glob_raw")" ] || printf '%s\n' "$f"
        done | jq -R -s -c 'split("\n") | map(select(length > 0)) | unique')"
      own_support="$(jq -c '[ (.support // [])[].path ]' "$IMPL_DIR/tests-$unit_id.json" 2>/dev/null)"
      [ -n "$own_support" ] || own_support='[]'
      owned_json="$(jq -nc --argjson d "$owned_json" --argjson t "$tracked_json" \
        --argjson own "$own_tests_json" --argjson sup "$own_support" '
        $d + ($t | map(select(. as $f | ($sup | index($f)) == null
            and all($own[]; (. | rtrimstr("/")) as $o
              | $f != $o and ($f | startswith($o + "/") | not))))) | unique')"
    fi
    # The row checker reads the tests its rows name. A criterion this order serves is proved by
    # its owner, so that test sits in another order's frozen file and stays readable to it.
    if [ "$role_bare" = "row-checker" ]; then
      local served_json named_json
      served_json="$(printf '%s' "$SNAPSHOT_DOC" | jq -c --arg u "$unit_id" \
        '[ .workOrders[]? | select(.id == $u) | ((.criteriaServed // []) + (.criteriaOwned // []))[] ] | unique')"
      named_json="$(find "$IMPL_DIR" -maxdepth 1 -name 'tests-wo*.json' ! -name "tests-$unit_id.json" -exec cat {} + 2>/dev/null \
        | jq -s -c --argjson c "$served_json" \
          '[ .[] | (.rows // [])[] | select(.criterion as $k | $c | index($k)) | (.tests // [])[].path ] | unique')"
      [ -n "$named_json" ] || named_json='[]'
      owned_json="$(jq -nc --argjson d "$owned_json" --argjson n "$named_json" '$d - $n')"
      # The task folder holds copies of production code and other roles' judgements: diffs, build
      # and fix records, review and verify records, every brief, every report, and the files a
      # restart set aside. The hook resolves an absolute entry as it is. The checker's own inputs,
      # interfaces-<unit>.json and the frozen test records, match none of these names.
      owned_json="$(find "$IMPL_DIR" -maxdepth 1 \( -name 'diff-*' -o -name 'build-*' -o -name 'fix-*' \
          -o -name 'review-*' -o -name 'verify-*' -o -name 'brief-*' -o -name '*answers-*' -o -name 'set-aside' \) 2>/dev/null \
        | jq -R -s -c --argjson d "$owned_json" '$d + (split("\n") | map(select(length > 0))) | unique')"
    fi
    deny_raw="$deny_raw$(printf '%s' "$owned_json" | jq -r '.[]')
"
  fi

  # The implementer is the mirror of the test author. It writes this unit's own files and may not
  # read another unit's, because what a unit exposes is its interface record and never its code
  # (ideal/agents.md, implementer). Both lists come from the snapshot for the same reason the test
  # author's does: assembled per dispatch they would be a judgement made in the moment.
  # An empty denial is a real state here and is not refused: a task with one work order has no
  # other unit to withhold, which is different from a test author having nothing to withhold.
  # The fixer takes this same derivation (decision 8 of step five). A fix round writes the same
  # order's files for the same reason a build attempt does, and the fix scope in the brief is
  # narrower still. The hook holds the fixer to the list too (live-run row 116). The owned-files
  # check after the round only spends the round, and the write it would have caught is already
  # committed. The one widening is the round's `allowedFiles`, a person's grant recorded on
  # the fix brief, read below.
  if [ "$role_bare" = "implementer" ] || [ "$role_bare" = "fixer" ]; then
    local mine_json others_json mine_count
    mine_json="$(printf '%s' "$SNAPSHOT_DOC" | jq -c --arg u "$unit_id" \
      '[ .workOrders[]? | select(.id == $u) | .ownedFiles[]? ] | unique')"
    mine_count="$(printf '%s' "$mine_json" | jq 'length' 2>/dev/null)"
    [ -n "$mine_count" ] || mine_count=0
    [ "$mine_count" -gt 0 ] 2>/dev/null \
      || die 47 "dispatch-open: $unit_id declares no owned file in $IMPL_DIR/snapshot.json, so a $role_bare would be dispatched with nowhere it is meant to write. Design has to name what this order owns before its code is written."
    # A file this order shares is another order's too, and this order still reads it (gap row 287).
    others_json="$(printf '%s' "$SNAPSHOT_DOC" | jq -c --arg u "$unit_id" --argjson m "$mine_json" \
      '[ .workOrders[]? | select(.id != $u) | .ownedFiles[]? ] - $m | unique')"
    deny_raw="$deny_raw$(printf '%s' "$others_json" | jq -r '.[]')
"
    allow_raw="$allow_raw$(printf '%s' "$mine_json" | jq -r '.[]')
"
  fi

  # --- 78: the run's ceiling, when task.json sets one ----------------------------------------------
  # The attempt and round caps bound one order; `budget` bounds the run. The spend is recomputed
  # from the ledger every time and stored nowhere, so nothing a builder writes can reset it. A
  # dispatch is the test author, one attempt, the reviewer, or the fixer and verifier of one round.
  local budget_json
  budget_json="$(jq -c '.budget // empty' "$TASK_PATH/task.json" 2>/dev/null)"
  if [ -n "$budget_json" ] && [ -f "$TASK_PATH/implementation/ledger.json" ]; then
    local bg_ledger bg_spent bg_why
    bg_ledger="$(jq -c '.' "$TASK_PATH/implementation/ledger.json" 2>/dev/null)"
    [ -n "$bg_ledger" ] || die 3 "dispatch-open: $TASK_PATH/implementation/ledger.json could not be read as JSON, and the run's budget is measured from it. Repair or remove it by hand."
    bg_spent="$(printf '%s' "$bg_ledger" | jq -c '
      {dispatches: ([ (.orders // [])[]
          | (if .lastStep == null then 0 else 1 end) + (.attemptsUsed // 0)
            + (if .lastStep == "reviewed" or .lastStep == "fixed" or .lastStep == "closed" then 1 else 0 end)
            + 2 * (.roundsUsed // 0) ] | add // 0),
       minutes: (if has("startedAt") then ((now - (.startedAt | fromdateiso8601)) / 60 | floor) else null end)}')"
    bg_why="$(jq -nr --argjson b "$budget_json" --argjson s "$bg_spent" '
      if ($b.dispatches != null and $s.dispatches >= $b.dispatches) then "budget spent: \($s.dispatches) of \($b.dispatches) dispatches"
      elif ($b.minutes != null and $s.minutes == null) then "unmeasured"
      elif ($b.minutes != null and $s.minutes >= $b.minutes) then "budget spent: \($s.minutes) of \($b.minutes) minutes"
      else "" end')"
    [ "$bg_why" != "unmeasured" ] \
      || die 3 "dispatch-open: task.json sets budget.minutes, and the ledger holds no startedAt to measure from. start writes it; run start again."
    if [ -n "$bg_why" ]; then
      bg_ledger="$(halt_order_in "$bg_ledger" "$unit_id" "$bg_why")"
      [ -n "$bg_ledger" ] || die 3 "dispatch-open: the halt on $unit_id could not be written."
      write_atomic "$TASK_PATH/implementation/ledger.json" "$bg_ledger"
      die 78 "dispatch-open: $unit_id is halted, $bg_why. The run's ceiling is task.json's budget. A person raises it with 'task set-budget <task-id> --dispatches <n>', or --minutes <n>, and then grant-attempt clears the halt. Nothing was dispatched."
    fi
  fi

  # One record per task, under its own implementation folder (live-run row 139). The build of one
  # task is serial, so a task has at most one open dispatch. A second task of the same project
  # opens its own. A record carries the time it opened, so one left by a role that never returned
  # can be told from a live one. The refusal prints its age once it is over a day old.
  local dispatch_file="$TASK_PATH/implementation/dispatch.json"
  if [ -f "$dispatch_file" ]; then
    jq empty "$dispatch_file" 2>/dev/null \
      || die 3 "dispatch-open: $dispatch_file exists but could not be read as JSON. Repair or remove it by hand before running this again."
    local held_role held_unit held_age
    held_role="$(jq -r '.role // "?"' "$dispatch_file" 2>/dev/null)"
    held_unit="$(jq -r '.unit // "?"' "$dispatch_file" 2>/dev/null)"
    held_age="$(jq -r '
      (.openedAt // "") as $at
      | if $at == "" then ""
        else ((now - ($at | fromdateiso8601)) / 3600 | floor) as $h
          | if $h < 24 then "" else " It was opened at \($at), \($h) hours ago, so its role may never have returned." end
        end' "$dispatch_file" 2>/dev/null)"
    die 37 "dispatch-open: $dispatch_file is already open, for role $held_role on unit $held_unit.$held_age Run dispatch-close first."
  fi

  # A fresh role must not meet the files another role left (gap row 228, row 217's check). Three
  # dispatches start beside files on purpose. A row-checker reads the author's uncommitted tests. A
  # test author sent back for a rejected row repairs its predecessor's tests. A resume reopens the
  # record for the same agent, whose own files they are.
  if [ "$resume" = false ] && [ "$role_bare" != "row-checker" ] \
     && ! { [ "$role_bare" = "test-author" ] && [ "$(jq -r --arg id "$unit_id" \
       '[ (.orders // [])[] | select(.id == $id) | has("rowsRejected") ][0] // false' \
       "$TASK_PATH/implementation/ledger.json" 2>/dev/null)" = "true" ]; }; then
    im_scan_leftovers "$codepath" "$(jq -c '.workOrders // []' "$TASK_PATH/implementation/snapshot.json" 2>/dev/null || printf '[]')"
    [ "$LO_LEFTOVERS_JSON" = "[]" ] \
      || die 104 "dispatch-open: uncommitted files in $codepath: $(printf '%s' "$LO_LEFTOVERS_JSON" | jq -r "[ $LO_TEXT_JQ ] | join(\", \")"). A role stopped mid-run may have left them, and a fresh $role_bare would work beside them. To keep a file, commit it. To set them aside, run start with --leftovers set-aside. To resume the agent that left them, run dispatch-open again with --resume. Nothing was dispatched."
  fi

  local deny_json allow_json
  deny_json="$(printf '%s' "$deny_raw" | jq -R -s 'split("\n") | map(select(length>0))')"
  allow_json="$(printf '%s' "$allow_raw" | jq -R -s 'split("\n") | map(select(length>0))')"

  # The implementer's own list goes under `ownedFiles` too, and not under allowWrite: allowWrite
  # takes hand-passed paths and no hook applies it, while this key is derived alone and the write
  # hook refuses the implementer a write under codePath outside it (live-run row 92). The fixer's
  # record carries the same key: the order's list plus the `allowedFiles` of the round's fix
  # brief. So the hook refuses it a write outside the scope a person allowed (live-run row 116).
  # A fixer with no fix brief for the round has nothing to be held to, so that refuses.
  local record_json owned_extra='{}' fx_round fx_brief fx_allowed forms_file
  if [ "$role_bare" = "implementer" ]; then
    # The runtime reads maxTurns from agents/implementer.md alone, and the Agent tool takes no turn
    # cap per call. So an order whose diff budget starts with `large` gets its larger turn budget
    # as a second resume at the cap, which dispatch-close counts (gap row 301).
    owned_extra="$(printf '%s' "$SNAPSHOT_DOC" | jq -c --argjson m "$mine_json" --arg u "$unit_id" '
      {ownedFiles: $m,
       resumesAllowed: (if ([ .workOrders[]? | select(.id == $u) | .diffBudget // "" ][0] // ""
                            | test("^\\s*large\\b"; "i")) then 2 else 1 end)}')"
  elif [ "$role_bare" = "fixer" ]; then
    fx_round="$(jq -r --arg id "$unit_id" '(.orders // [])[] | select(.id == $id) | (.roundsUsed // 0) + 1' \
      "$TASK_PATH/implementation/ledger.json" 2>/dev/null)"
    [ -n "$fx_round" ] || fx_round=1
    fx_brief="$IMPL_DIR/brief-$unit_id-fix-$fx_round.json"
    fx_allowed="$(jq -c '.allowedFiles // []' "$fx_brief" 2>/dev/null)"
    [ -n "$fx_allowed" ] \
      || die 3 "dispatch-open: no fix brief for round $fx_round of $unit_id at $fx_brief. Run fix-brief first: the fixer's record takes the paths it allowed."
    owned_extra="$(jq -nc --argjson m "$mine_json" --argjson a "$fx_allowed" '{ownedFiles: ($m + $a | unique)}')"
  elif [ "$role_bare" = "test-author" ]; then
    # A runtime shows the shape of production code as surely as a read of its source, and the
    # live author took every signature it lacked that way (gap row 231). The forms are data, so
    # the read hook names no language.
    forms_file="$PLUGIN_ROOT/scripts/introspection-forms.txt"
    owned_extra="$(grep -v -e '^#' -e '^[[:space:]]*$' "$forms_file" 2>/dev/null \
      | jq -R -s -c '{denyCommand: (split("\n") | map(select(length > 0)))}')"
    [ "$(printf '%s' "$owned_extra" | jq '.denyCommand | length' 2>/dev/null)" -gt 0 ] 2>/dev/null \
      || die 3 "dispatch-open: $forms_file holds no form or could not be read. This plugin's own files are incomplete; nothing about the task is wrong."
  fi
  # The file the role's brief pins, which dispatch-close checks (gap rows 228 and 250): the
  # reviewer's findings or verdicts, the fixer's and the test author's report. The last two end
  # theirs with IM_REPORT_DONE, so their record carries that line too. A fresh dispatch removes an
  # earlier report of theirs, so a complete one from before cannot close this one. A resume keeps it.
  local report_brief="" report_path="" report_extra='{}'
  case "$role_bare" in
    fixer) report_brief="$fx_brief" ;;
    test-author) report_brief="$TASK_PATH/implementation/brief-$unit_id-tests.json" ;;
    reviewer) report_brief="$rv_brief" ;;
  esac
  if [ "$role_bare" = "reviewer" ]; then
    report_path="$(jq -r '.findingsPath // .verdictsPath // ""' "$report_brief" 2>/dev/null)"
  elif [ -n "$report_brief" ]; then
    report_path="$(jq -r '.reportPath // ""' "$report_brief" 2>/dev/null)"
  fi
  if [ -n "$report_path" ]; then
    case "$role_bare" in
      fixer|test-author)
        report_extra="$(jq -nc --arg p "$report_path" --arg l "$IM_REPORT_DONE" '{reportPath: $p, completionLine: $l}')"
        [ "$resume" = true ] || rm -f "$report_path" || die 3 "dispatch-open: could not remove the earlier report $report_path" ;;
      *) report_extra="$(jq -nc --arg p "$report_path" '{reportPath: $p}')" ;;
    esac
  fi
  record_json="$(jq -n --arg role "$role" --arg task "$task_id" --arg unit "$unit_id" \
    --arg codePath "$codepath" --argjson denyRead "$deny_json" --argjson allowWrite "$allow_json" \
    --arg openedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson extra "$owned_extra" --argjson report "$report_extra" \
    '{schemaVersion: 1, role: $role, task: $task, unit: $unit, codePath: $codePath,
      openedAt: $openedAt, denyRead: $denyRead, allowWrite: $allowWrite} + $extra + $report')"
  # A reopened record carries one resume already, so a return with no report spends one less.
  [ "$resume" = false ] || record_json="$(printf '%s' "$record_json" | jq -c '.resumedAt = .openedAt')"

  # The checker is denied every reused path and every other order's files, as the author is. The
  # author gets their interface text in the tests brief, so the checker gets that text too (gap
  # row 257). Only those two keys: the rest of the brief holds the person's words, earlier notes and
  # review evidence, and a Read returns the whole file. An order with no tests brief has no file,
  # and an earlier one is removed so a stale copy is never read.
  local interfaces_file="" interfaces_json
  if [ "$role_bare" = "row-checker" ]; then
    interfaces_file="$IMPL_DIR/interfaces-$unit_id.json"
    if [ -f "$IMPL_DIR/brief-$unit_id-tests.json" ]; then
      interfaces_json="$(jq -c '{reuses: (.reuses // []), dependencyInterfaces: (.dependencyInterfaces // [])}' \
        "$IMPL_DIR/brief-$unit_id-tests.json" 2>/dev/null)" \
        || die 3 "dispatch-open: $IMPL_DIR/brief-$unit_id-tests.json could not be read as JSON, so the checker's interface file was not written."
      write_atomic "$interfaces_file" "$interfaces_json"
    else
      rm -f "$interfaces_file" || die 3 "dispatch-open: could not remove the earlier $interfaces_file"
      interfaces_file=""
    fi
  fi

  write_atomic "$dispatch_file" "$record_json"
  echo "DISPATCH-OPEN: written (role $role, task $task_id, unit $unit_id)"
  echo "DISPATCH-OPEN: the role works in the worktree $codepath. Put it in the dispatch message: the role starts each shell command with cd $codepath &&, and writes nothing in the main checkout."
  [ -z "$interfaces_file" ] \
    || echo "DISPATCH-OPEN: interfaces: $interfaces_file. Put it in the dispatch message as a path: the role reads the interface text of what a test calls there."
  local deny_count main
  main="$(main_checkout "$(project_code_path_value "$RV_PROJECT_FOLDER")" "$(cd "$codepath" && pwd -P)")"
  deny_count="$(printf '%s' "$deny_json" | jq 'length' 2>/dev/null)"
  [ -n "$deny_count" ] || deny_count=0
  if [ "$deny_count" -gt 0 ] 2>/dev/null; then
    echo "DISPATCH-OPEN: reads denied to this role, resolved against $codepath${main:+ and against the main checkout $main}:"
    printf '%s' "$deny_json" | jq -r '.[] | "  " + .'
  else
    echo "DISPATCH-OPEN: this dispatch denies no read. Every path under $codepath stays readable."
  fi
  printf '%s' "$owned_extra" | jq -r 'select(has("denyCommand"))
    | "DISPATCH-OPEN: shell forms denied to this role: " + (.denyCommand | join(", "))'
  printf '%s\n' "$dispatch_file"
  exit 0
}

# `step <name>` prints one of this skill's own step files on standard output.
#
# The skill reads its step files through this action rather than with Read. The documentation
# mirror scopes ${CLAUDE_PLUGIN_ROOT} substitution in `allowed-tools` to Bash rules, so a Read rule
# naming that variable never matches, and every step-file read raises a permission prompt on the
# one file that carries the step's own rules. An unattended run has nobody to answer it. The Bash
# rule on this script already matches, so the read goes through that instead.
#
# A name is one name and never a path. A slash would turn this into a reader for any file the
# script can open, and it exists to hand over the six step files and nothing else.
do_step() {
  local names
  names="$(md_basenames_in "$STEPS_DIR")"
  [ "$#" -ge 1 ] || die 3 "step: a step name is required. The steps are: $names"
  [ "$#" -le 1 ] || die 3 "step: unrecognized extra argument: $2"
  case "$1" in
    */*|.|..|'') die 3 "step: a step name is one name and never a path; got: $1. The steps are: $names" ;;
  esac
  [ -f "$STEPS_DIR/$1.md" ] \
    || die 3 "step: this skill ships no step file named $1. The steps are: $names"
  cat "$STEPS_DIR/$1.md" || die 3 "step: $STEPS_DIR/$1.md could not be read."
  exit 0
}

do_dispatch_close() {
  [ "$#" -ge 1 ] || die 3 "dispatch-close: a task folder is required"
  local task_path="$1" no_report=false
  if [ "$#" -ge 2 ]; then
    [ "$2" = "--no-report" ] || die 3 "dispatch-close: unrecognized extra argument: $2"
    [ "$#" -le 2 ] || die 3 "dispatch-close: unrecognized extra argument: $3"
    no_report=true
  fi
  local resolve_rc
  TASK_PATH="$(resolve_task_folder "$task_path" "dispatch-close")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"

  # The record lives under the task's own folder, so a close can only reach this task's record
  # and another task's stays open (live-run row 139).
  local dispatch_file="$TASK_PATH/implementation/dispatch.json"
  # dispatch-open stores the file the role's brief pins under `reportPath` (gap rows 228 and 250).
  # One block checks it for every role that has one. A missing file, or one no newer than the
  # record, is a previous run's or none. A fixer and a test author also end theirs with
  # `completionLine` as their last act, after at least one line of report. A fixer's must be no
  # older than the last commit in the code path, because it commits and then writes the line. A
  # test author's is read by the line alone. The reviewer's file refuses at 111. The other two take
  # the --no-report path unasked, so a cut-off role never closes as finished. A record from before
  # the key existed names no file, and nothing is checked.
  local cut_off="" rp_path rp_line rp_cause="" rp_last rp_head
  if [ "$no_report" = false ] && [ -f "$dispatch_file" ]; then
    rp_path="$(jq -r '.reportPath // ""' "$dispatch_file" 2>/dev/null)"
    rp_line="$(jq -r '.completionLine // ""' "$dispatch_file" 2>/dev/null)"
    if [ -z "$rp_path" ]; then
      :
    elif [ ! -f "$rp_path" ] || [ ! "$rp_path" -nt "$dispatch_file" ]; then
      rp_cause="$rp_path is missing or older than its dispatch record"
    elif [ -n "$rp_line" ]; then
      rp_last="$(grep -v '^[[:space:]]*$' "$rp_path" | tail -n 1 | sed 's/[[:space:]]*$//')"
      if [ "$rp_last" != "$rp_line" ]; then
        rp_cause="$rp_path does not end with the line '$rp_line'"
      elif [ "$(grep -v '^[[:space:]]*$' "$rp_path" | grep -c -v -x -F -e "$rp_line")" -eq 0 ]; then
        rp_cause="$rp_path holds nothing but the line '$rp_line'"
      elif [ "$(jq -r '.role // "" | split(":") | last' "$dispatch_file")" = "fixer" ]; then
        rp_head="$(git -C "$(jq -r '.codePath // ""' "$dispatch_file")" log -1 --format=%ct 2>/dev/null)"
        [ -z "$rp_head" ] || [ "$(im_mtime "$rp_path")" -ge "$rp_head" ] \
          || rp_cause="$rp_path is older than the last commit in its code path, so the line was written before the fixer's commit"
      fi
    fi
    if [ -n "$rp_cause" ] && [ -z "$rp_line" ]; then
      die 111 "dispatch-close: the $(jq -r '.role // "" | split(":") | last' "$dispatch_file") on $(jq -r '.unit // ""' "$dispatch_file") returned, and $rp_cause. The record stays open. If it stopped at its turn limit, run dispatch-close again with --no-report."
    fi
    [ -z "$rp_cause" ] || { cut_off="$rp_cause"; no_report=true; }
  fi
  # A role with no report is resumed by message, not dispatched fresh: its brief is unchanged and its
  # work is unfinished, and a fresh role meets its half-written files (gap row 228). The record
  # stays open so both hooks keep applying while it finishes.
  if [ "$no_report" = true ]; then
    [ -f "$dispatch_file" ] \
      || die 3 "dispatch-close: --no-report needs an open dispatch record, and $dispatch_file is absent. If the role's record was already closed, run dispatch-open with the same role and unit and --resume, then resume the same agent by message. If that agent cannot be reached, as from another session, run dispatch-open without --resume and dispatch the role fresh."
    local nr_role nr_unit nr_cap nr_ledger nr_used nr_allowed nr_after="after one resume" nr_dirty=""
    nr_role="$(jq -r '.role // ""' "$dispatch_file" 2>/dev/null)"
    nr_unit="$(jq -r '.unit // ""' "$dispatch_file" 2>/dev/null)"
    [ -n "$nr_role" ] && [ -n "$nr_unit" ] \
      || die 3 "dispatch-close: $dispatch_file names no role or unit. Repair or remove it by hand."
    # A record from before `resumes` counts the one resume its `resumedAt` marks. A count that is
    # not a whole number, such as one edited by hand, reads as the default.
    nr_used="$(jq -r '.resumes // (if has("resumedAt") then 1 else 0 end)
      | if type == "number" and . >= 0 and . == floor then . else 1 end' "$dispatch_file")"
    nr_allowed="$(jq -r '.resumesAllowed
      | if type == "number" and . >= 1 and . == floor then . else 1 end' "$dispatch_file")"
    [ "$nr_allowed" -eq 1 ] || nr_after="after $nr_allowed resumes"
    # An implementer commits each numbered part, so what it left uncommitted is the work a stop
    # puts at risk (gap row 301). The count is named, never refused: the runtime stopped the role.
    if [ "${nr_role##*:}" = "implementer" ]; then
      nr_dirty="$(git -C "$(jq -r '.codePath // ""' "$dispatch_file")" status --porcelain 2>/dev/null | grep -c .)"
      nr_dirty=" It left $nr_dirty uncommitted files in $(jq -r '.codePath // ""' "$dispatch_file")."
    fi
    if [ "$nr_used" -lt "$nr_allowed" ]; then
      write_atomic "$dispatch_file" "$(jq -c --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson n "$((nr_used + 1))" \
        '.resumedAt = $at | .resumes = $n' "$dispatch_file")"
      [ -z "$cut_off" ] \
        || die 112 "dispatch-close: $nr_role on $nr_unit returned, and $cut_off, so it stopped before it finished, most likely at its turn limit. The record stays open for resume $((nr_used + 1)) of $nr_allowed. Resume the same $nr_role agent by message: finish the work and end the report with '$IM_REPORT_DONE'. Then run dispatch-close again."
      echo "DISPATCH-CLOSE: $nr_role on $nr_unit returned no report; the record stays open for resume $((nr_used + 1)) of $nr_allowed.$nr_dirty"
      echo "next: resume the same $nr_role agent by message: finish the work and write the report. Then run dispatch-close again, with --no-report if it returns none."
      exit 0
    fi
    nr_cap="$(sed -n 's/^maxTurns: *//p' "$PLUGIN_ROOT/agents/${nr_role##*:}.md" 2>/dev/null | head -1)"
    nr_ledger="$(jq -c '.' "$TASK_PATH/implementation/ledger.json" 2>/dev/null)"
    [ -n "$nr_ledger" ] || die 3 "dispatch-close: $TASK_PATH/implementation/ledger.json could not be read as JSON, so the halt on $nr_unit could not be written."
    local nr_times="twice" nr_last="second" nr_what
    [ "$nr_allowed" -eq 1 ] || { nr_times="$((nr_allowed + 1)) times"; nr_last="last"; }
    nr_what="returned no report $nr_times"
    [ -z "$cut_off" ] || nr_what="stopped before it finished $nr_times, the $nr_last time because $cut_off"
    nr_ledger="$(halt_order_in "$nr_ledger" "$nr_unit" \
      "turn cap: ${nr_role##*:} $nr_what, $nr_after; its cap is ${nr_cap:-unknown} turns")"
    [ -n "$nr_ledger" ] || die 3 "dispatch-close: the halt on $nr_unit could not be written."
    write_atomic "$TASK_PATH/implementation/ledger.json" "$nr_ledger"
    rm -f "$dispatch_file" || die 3 "dispatch-close: could not remove $dispatch_file"
    die 110 "dispatch-close: $nr_unit is halted. $nr_role $nr_what, $nr_after. Its cap is ${nr_cap:-unknown} turns, in agents/${nr_role##*:}.md.$nr_dirty A person reads what it left, runs clear-halt, then start to keep or set aside its files, then dispatches again."
  fi
  if [ -f "$dispatch_file" ]; then
    rm -f "$dispatch_file" || die 3 "dispatch-close: could not remove $dispatch_file"
    echo "DISPATCH-CLOSE: removed $dispatch_file"
  else
    echo "DISPATCH-CLOSE: nothing was open"
  fi
  exit 0
}

# ------------------------------------------------------------------------------------------------
# Dispatch
# ------------------------------------------------------------------------------------------------

ACTION="${1:-}"
if [ "$ACTION" = "-h" ] || [ "$ACTION" = "--help" ]; then
  usage
  exit 0
fi
[ -n "$ACTION" ] || { usage; die 3 "no action given"; }
shift

case "$ACTION" in
  read)  do_read  "$@" ;;
  start) do_start "$@" ;;
  preconditions) do_preconditions "$@" ;;
  recipe-refresh) do_recipe_refresh "$@" ;;
  tests-brief)  do_tests_brief  "$@" ;;
  tests-freeze) do_tests_freeze "$@" ;;
  build-brief)  do_build_brief  "$@" ;;
  build-record) do_build_record "$@" ;;
  build-recheck) do_build_recheck "$@" ;;
  review-brief)   do_review_brief   "$@" ;;
  review-record)  do_review_record  "$@" ;;
  fix-brief)      do_fix_brief      "$@" ;;
  fix-record)     do_fix_record     "$@" ;;
  verify-brief)   do_verify_brief   "$@" ;;
  verify-record)  do_verify_record  "$@" ;;
  close)          do_close          "$@" ;;
  finish)         do_finish         "$@" ;;
  grant-attempt)  do_grant_attempt  "$@" ;;
  restart)        do_restart        "$@" ;;
  unattributed)   do_unattributed   "$@" ;;
  clear-halt)     do_clear_halt     "$@" ;;
  retake-tests)   do_retake_tests   "$@" ;;
  dispatch-open)  do_dispatch_open  "$@" ;;
  dispatch-close) do_dispatch_close "$@" ;;
  step)           do_step           "$@" ;;
  *) usage; die 3 "unknown action: $ACTION" ;;
esac
