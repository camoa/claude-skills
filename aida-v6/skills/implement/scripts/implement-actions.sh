#!/usr/bin/env bash
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
# `dispatch-open` and `dispatch-close` open and clear the one record, <project path>/dispatch.json,
# that the two permission hooks (hooks/deny-prior-source.sh, hooks/deny-frozen-test-writes.sh) read
# to tell a dispatched role apart from a person working their own repository.
#
# Two steps halt an order rather than refuse. A halt is the run continuing correctly, so it exits 0,
# writes the reason into the ledger and says so on standard error. The one exception is an
# unattended run reaching the fix cap with findings still open: a ruling is a person's judgement, so
# that one refuses with its own code and halts the order in the same call (exit 56).
#
# Usage:
#   implement-actions.sh read  <task_folder>
#   implement-actions.sh start <task_folder>
#   implement-actions.sh preconditions <task_folder> [--recipe <framework>=<path>]...
#                                                    [--check-recipe <framework>=<path>]...
#                                                    [--lookup-failed <framework>=<reason>]...
#                                                    [--value <name>=<value>]...
#   implement-actions.sh tests-brief  <task_folder> <unit_id>
#   implement-actions.sh tests-freeze <task_folder> <unit_id> \
#                            [--test <path>::<test name>=<criterion id>[,<criterion id>...]]...
#                            [--red <test name>=<path to a file holding what the run printed>]...
#                            [--test-glob <glob>]...
#                            [--checklist <criterion id>=<verification text>]...
#                            [--row <criterion id>=<confirmed|rejected>::<person|model>::<note>]...
#                            [--green-on-arrival <test name>=<reason>]...
#   implement-actions.sh build-brief  <task_folder> <unit_id>
#   implement-actions.sh build-record <task_folder> <unit_id> \
#                            --interface <path to the record the builder wrote> \
#                            --report <path to the builder's report> \
#                            --started-at <commit the attempt began from> \
#                            [--test-recipe <framework>=<path>]... \
#                            [--check-recipe <framework>=<path>]... \
#                            [--value <name>=<value>]... \
#                            [--nothing-ran <literal substring>]
#   implement-actions.sh review-brief  <task_folder> <unit_id>
#   implement-actions.sh review-record <task_folder> <unit_id> --findings <path>
#   implement-actions.sh fix-brief     <task_folder> <unit_id>
#   implement-actions.sh fix-record    <task_folder> <unit_id> \
#                            --report <path to the fixer's report> \
#                            --started-at <commit the round began from> \
#                            [--test-recipe <framework>=<path>]... \
#                            [--check-recipe <framework>=<path>]... \
#                            [--value <name>=<value>]... \
#                            [--nothing-ran <literal substring>] \
#                            [--scope-insufficient <finding id>=<reason>]...
#   implement-actions.sh verify-brief  <task_folder> <unit_id>
#   implement-actions.sh verify-record <task_folder> <unit_id> --verdicts <path> \
#                            [--ruling <finding id>=<wrong|deferred|load-bearing>::<reason>]...
#   implement-actions.sh close <task_folder> <unit_id>
#   implement-actions.sh finish <task_folder>
#   implement-actions.sh grant-attempt <task_folder> <unit_id> --reason <text>
#   implement-actions.sh restart <task_folder> --reason <text>
#   implement-actions.sh dispatch-open <task_folder> <role> <unit_id> \
#                            [--deny-read <path relative to codePath>]... \
#                            [--allow-write <path relative to codePath>]...
#
# `dispatch-open` checks <role> against the agent definitions this plugin ships and refuses a name
# that matches none of them. For the four roles that read or write the code, it also derives the
# path lists itself from the frozen snapshot, so none is a list a caller assembles per dispatch: a
# test author is denied every order's owned files, a row-checker takes that same derivation because
# it must answer from the test and never from the implementation, and an implementer is denied every
# order's but its own and is allowed its own. A fixer takes the implementer's derivation exactly, because a fix round
# writes the same order's files for the same reason (decision 8 of step five). `--deny-read` adds to what was derived; it is how a path outside codePath is
# denied, such as the recipe each role may not open.
#   implement-actions.sh dispatch-close <task_folder>
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
# <task_folder>/implementation/ and print its path, which the dispatch then names:
# brief-<unit_id>-tests.json, brief-<unit_id>-build.json, brief-<unit_id>-review.json,
# brief-<unit_id>-fix-<round>.json and brief-<unit_id>-verify-<round>.json. `read`, `start` and
# every record action end with a `next:` line, derived from the ledger the way SKILL.md's routing
# table reads it. The two exceptions to the summary rule are the bodies a person or a caller has to
# read verbatim: `tests-freeze`'s checklist rows, and `step`'s own step file. `restart` prints the
# archive path alone, and `dispatch-open` the denied paths and the record path.
#
# `preconditions` never resolves a recipe itself. The skill body asks the guides navigator for the
# one belonging to this point and this framework, or reads a source the project configured itself,
# and hands over a path. A framework whose lookup failed is passed with the reason it failed, and
# the three reasons stay apart: no-recipe, listing-unreachable, fetch-failed. Only the first says
# anything about the framework.
#
# There is no --run-mode flag on this script, deliberately. The mode is the task's own, read from
# <task_folder>/task.json at `start` (task-schema.json, `runMode`), not something a caller passes
# for one invocation the way research-actions.sh and design-actions.sh accept it for their own
# conversational choices. Nothing here has a conversational choice to make yet.
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
#                                                        write_atomic and mark_task_in_progress,
#                                                        the same ones every other stage reads.
#   ${CLAUDE_PLUGIN_ROOT}/scripts/lib/records-hash.sh   sourced. Its records_hash_for is the only
#                                                        place this script computes a hash over a
#                                                        contract and its work orders, the same
#                                                        computation design-actions.sh's own
#                                                        `close` calls to write design-closed.json.
#                                                        Both always agree on the same number for
#                                                        the same files, because both call the
#                                                        same function; this script never carries
#                                                        a second copy of that formula.
#   ${CLAUDE_PLUGIN_ROOT}/scripts/snapshot-schema.json   the shape `start` writes to snapshot.json
#   ${CLAUDE_PLUGIN_ROOT}/scripts/ledger-schema.json     the shape `start` writes to ledger.json
#   ${CLAUDE_PLUGIN_ROOT}/scripts/dispatch-schema.json   the shape `dispatch-open` writes to
#                                                        <project path>/dispatch.json
#   ${CLAUDE_PLUGIN_ROOT}/scripts/finished-schema.json   the shape `finish` writes to
#                                                        <task_folder>/implementation/finished.json
#
# This script never runs a schema comparison against snapshot-schema.json or ledger-schema.json
# itself. Every field it writes is built from those two schemas' own field lists by construction;
# a stale or hand-edited file already on disk before this script's first call on it is a fact this
# script reports (present-but-unreadable, or a hash mismatch), not one it repairs.
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
#      task.json declaring a runMode value
#      this schema never writes, a ledger.json missing a required field or holding one of the
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
#      without closing again. Close design again.
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
#      reported, never counted as met.
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
#  28  `tests-freeze` was given a --test whose test name does not carry, at its own end, the
#      criterion id (or ids, chained from the right) it claims.
#  29  `tests-freeze` found a criterion the unit serves or owns whose verifiedBy is machine with no
#      --test row naming it.
#  30  `tests-freeze` found a criterion the unit serves or owns whose verifiedBy is person with no
#      --checklist row.
#  31  `tests-freeze` was given a --test naming a criterion the unit does not serve or own.
#  32  `tests-freeze` was given a --red whose file is missing or empty, or that names a test with
#      no --test row.
#  33  `tests-freeze` found a test with no --red at all.
#  34  `tests-freeze` was given a --green-on-arrival. Not a defect in the script: it stops the step
#      and says the test proves nothing, which is the escalation this stage requires.
#  35  `tests-freeze` found <task_folder>/implementation/tests-<unit_id>.json already recorded at a
#      commit other than the one this run is at. The message names both commits.
#  36  `tests-freeze` was given a --test whose path, once resolved against codePath, names
#      something outside codePath altogether. The message names the path and the code root. Every
#      path this step records is relative to codePath (baseline.json's own `scope` field is
#      relative for the same reason: a frozen path must survive the checkout moving), so a path
#      that cannot be made relative to it at all cannot be recorded either.
#  37  `dispatch-open` found <project path>/dispatch.json already open. The build is serial, so a
#      project has at most one active dispatch; the message names the role, task and unit that
#      already hold it. `dispatch-close` clears it.
#  38  `build-brief` was given a unit id that is not in the frozen snapshot. The same fact exit 22
#      already names for `tests-brief` and `tests-freeze`; `build-brief` shares the number rather
#      than minting a second one for the same meaning.
#  39  `build-brief` found no <task_folder>/implementation/tests-<unit_id>.json for this unit. Step
#      three (`tests-brief` and `tests-freeze`) has not run for it yet.
#  40  `build-brief` found an order in the given unit's dependsOn with no completion record in the
#      ledger (its lastStep is not "closed"), so that order's interface record does not exist yet.
#      The same fact exit 23 names for `tests-brief`, kept apart because the two actions read the
#      dependency for two different reasons: `tests-brief` needs the interface to write tests
#      against it, `build-brief` needs it to hand to the model writing the code.
#  41  `build-brief` found the given unit's attempt counter already at its allowed limit. Nothing is
#      handed over; the order is exhausted.
#  42  `build-brief` ran before `start`, so <task_folder>/implementation/snapshot.json does not
#      exist. A different number from exit 25, which `tests-brief` and `tests-freeze` share for the
#      same fact: `build-brief` gets its own so a caller can tell which step never started without
#      inspecting the message text.
#  43  `build-record` or `fix-record` was given a --started-at that is not a commit in the code
#      repository.
#  44  `build-record` found the interface record file named by --interface missing or empty while
#      the given unit declares a non-empty interface. A file present for a unit that declares no
#      interface is read and recorded without complaint; nothing here judges its content.
#  45  a record for this attempt or this round already exists, so the call would write it twice.
#      `build-record` found build-<unit_id>.json already recorded at the same commit and the same
#      attempt number; `fix-record` found fix-<unit_id>-<round>.json already recorded at the same
#      commit; `verify-brief` found the round already verified in review-<unit_id>.json, so there is
#      nothing left to hand a verifier. The message names both values, because a caller who calls
#      this twice for one attempt or one round is not shown a stale success silently.
#      `verify-record` on a round already verified reports the verification on record instead.
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
#      role would be dispatched with nowhere it is meant to write.
#
# The step-five exit codes. Six actions share these, and each number carries one meaning across all
# six rather than one number per action per fact.
#  48  the ledger records this order at a step the action cannot follow. `review-brief` and
#      `review-record` follow `checks-passed`; `fix-brief` and `fix-record` follow `reviewed` or
#      `fixed`; `verify-brief` and `verify-record` follow `fixed`; `close` follows `reviewed` or
#      `fixed`. The message names the step found and the steps allowed.
#  49  the order is halted, so the step refuses. Every step-five action refuses on it, and the
#      message carries the halt's own recorded reason.
#  50  a review record already exists for this order, and an order gets one review, ever
#      (ideal/implementation.md, 'One review per order'). `review-brief` refuses to hand over a
#      second brief and `review-record` refuses to write a second record.
#  51  `review-record` found the code repository is not where the build record left it: HEAD moved,
#      or the working tree is dirty. The reviewer holds Write for one purpose, its own findings
#      file under the task folder, and this is the check that enforces it. A probe test left inside
#      the reviewed code is a refusal here, never a finding later.
#  52  a findings or verdict file named on the command line is missing, is empty, or does not hold
#      the shape the action reads. The message names the entry and what was wrong with it. A file
#      this script half understands is worse than no file at all.
#  53  `fix-brief` or `fix-record` found no open actionable finding for this order, so there is
#      nothing for a fixer to do. `verify-brief` shares it: nothing open means nothing to verify.
#  54  `fix-brief` or `fix-record` found this order's fix rounds already spent (roundsUsed at
#      FIX_ROUNDS_ALLOWED). Every open finding needs a ruling now, not another round. The mirror of
#      exit 41 for the build attempts.
#  55  `verify-record` was given a --ruling on an unattended run. A ruling is a person's judgement,
#      and an unattended run has none to offer (decision 12).
#  56  `verify-record` reached the round cap on an unattended run with findings still open. The
#      order is halted with them named, and the verification itself is recorded first, so a refusal
#      never throws away the verdicts it already read.
#  57  `verify-record` reached the round cap with an open finding no --ruling names. Each one needs
#      a ruling and a reason before the order may close.
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
#      commit and run the step again. `close`, `finish` and `restart` refuse on the same fact and
#      share this number, because a commit range is a claim about a repository and a dirty tree
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
#  64  `tests-freeze`'s own `--row` flags and this order's criteria do not correspond: a
#      machine-verified criterion the order serves or owns with no row, a row naming a criterion the
#      order neither serves nor owns, a row naming a criterion a person verifies, or two rows naming
#      one criterion. The message names which. A row set this script half understands would put a
#      judgement on the wrong criterion, which nothing later could tell from a real one.
#  65  `tests-freeze` was given a `--row` that answers rejected. Not a defect in the script: the
#      freeze stops, writes no test record, and the row goes back to the test author, the same way
#      exit 34 stops the step on a test that was green on arrival. Unattended, a row the checker
#      itself rejected halts the order first, because a refusal nobody is there to read leaves the
#      order in flight with no reason on it. A row a person rejected never halts anything: the
#      person is already there.
#  66  `finish` found implementation is not finished for this task: an order that is not closed, an
#      order carrying a halt whether or not it closed, or a machine-verified criterion whose row
#      state is not confirmed. The message names every one of them.
#  67  `grant-attempt` was asked for an attempt it cannot grant: the order is already closed, so
#      there is nothing left to attempt, or it is halted for something other than a spent attempt
#      counter. A grant answers a spent counter and answers nothing else, so the message names what
#      it found and nothing is written. One number, because both are the same fact: this order is
#      not waiting on another attempt.
#  68  `grant-attempt` or `restart` was called on an autonomous run. Both are a person's judgement,
#      and an unattended run has none to offer. The same number for both, because it is one fact.
#  69  `restart` found no order halted for design drift. There is nothing to restart from, and a
#      restart that moved the implementation folder anyway would throw away a build that is fine.
#  70  `tests-freeze` was given a `--row` whose judge does not match the run. An autonomous run has
#      no person to judge a row, so `person` there is a claim nobody made; an interactive run has a
#      person, so `model` there records weaker evidence than the run actually had. The residue the
#      record keeps is only worth keeping when it is true, so both refuse and nothing is written.
#
# The codes the paper test added. Each one is a fact nothing refused before.
#  71  `build-record` or `fix-record` was given a `--started-at` that cannot be the commit the work
#      began from: it is the commit HEAD is at now, so the diff would be empty and every check would
#      answer about nothing, or it is not an ancestor of HEAD, so the range between the two is not
#      this order's own work. Exit 43 stays the separate fact that the value is not a commit at all.
#  72  two frameworks each declare a command for one check row, and nothing here may choose between
#      two answers to one question. The message names both frameworks and the row.
#  73  the check recipe resolved for a framework now is not the one the baseline was taken with: its
#      sha256 differs. Every tool check compares its own result against that baseline, so a changed
#      recipe compares one tool's output against another tool's baseline. Take the baseline again.
#  74  `tests-freeze` was asked to freeze an order that serves and owns no criterion at all. Every
#      guard in that step reads a per-criterion list, so an order with none passes all of them and
#      freezes a reference that proves nothing.
#  75  `dispatch-close` was given a task folder that is not the one the open record names. The
#      record lives at the project root and two tasks in one project is a supported state, so a
#      second task's close would clear the first task's live permission record. The message names
#      the record's own task and the folder given.
#  76  `tests-freeze` was asked to re-freeze an order that has already left the frozen state. A
#      re-freeze rewinds the step and leaves the spent attempt counter and the stale build record
#      where they are, so the order would rebuild with no attempts and a record for tests that no
#      longer exist.
#  77  `preconditions` read a valid project.json that records no framework, so no recipe can be
#      chosen for it. Exit 14 stays the separate fact that the file is not valid JSON at all.
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

command -v jq >/dev/null 2>&1 || { printf 'implement-actions: jq is required and was not found on PATH\n' >&2; exit 3; }

die() { printf 'implement-actions: %s\n' "$2" >&2; exit "$1"; }
# One refusal function, one exit code as its first argument. The exit-code table above is the
# only place a number gets a meaning, and nothing here mints one that table does not carry.

# task-helpers.sh takes these two from its caller, so a refusal still says which script refused.
die1() { die 1 "$1"; }
die3() { die 3 "$1"; }

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

usage() {
  cat <<'EOF' >&2
usage: implement-actions.sh read  <task_folder>
       implement-actions.sh start <task_folder>
       implement-actions.sh preconditions <task_folder>
                            [--recipe <framework>=<path>]...
                            [--check-recipe <framework>=<path>]...
                            [--lookup-failed <framework>=<no-recipe|listing-unreachable|fetch-failed>]...
                            [--value <name>=<value>]...
       implement-actions.sh tests-brief  <task_folder> <unit_id>
       implement-actions.sh tests-freeze <task_folder> <unit_id>
                            [--test <path>::<test name>=<criterion id>[,<criterion id>...]]...
                            [--red <test name>=<path to a file holding what the run printed>]...
                            [--test-glob <glob>]...
                            [--checklist <criterion id>=<verification text>]...
                            [--row <criterion id>=<confirmed|rejected>::<person|model>::<note>]...
                            [--green-on-arrival <test name>=<reason>]...
       implement-actions.sh build-brief  <task_folder> <unit_id>
       implement-actions.sh build-record <task_folder> <unit_id>
                            --interface <path to the record the builder wrote>
                            --report <path to the builder's report>
                            --started-at <commit the attempt began from>
                            [--test-recipe <framework>=<path>]...
                            [--check-recipe <framework>=<path>]...
                            [--value <name>=<value>]...
                            [--nothing-ran <literal substring>]
       implement-actions.sh review-brief  <task_folder> <unit_id>
       implement-actions.sh review-record <task_folder> <unit_id> --findings <path>
       implement-actions.sh fix-brief     <task_folder> <unit_id>
       implement-actions.sh fix-record    <task_folder> <unit_id>
                            --report <path to the fixer's report>
                            --started-at <commit the round began from>
                            [--test-recipe <framework>=<path>]...
                            [--check-recipe <framework>=<path>]...
                            [--value <name>=<value>]...
                            [--nothing-ran <literal substring>]
                            [--scope-insufficient <finding id>=<reason>]...
       implement-actions.sh verify-brief  <task_folder> <unit_id>
       implement-actions.sh verify-record <task_folder> <unit_id> --verdicts <path>
                            [--ruling <finding id>=<wrong|deferred|load-bearing>::<reason>]...
       implement-actions.sh close <task_folder> <unit_id>
       implement-actions.sh finish <task_folder>
       implement-actions.sh grant-attempt <task_folder> <unit_id> --reason <text>
       implement-actions.sh restart <task_folder> --reason <text>
       implement-actions.sh dispatch-open <task_folder> <role> <unit_id>
                            [--deny-read <path relative to codePath>]...
                            [--allow-write <path relative to codePath>]...
       implement-actions.sh dispatch-close <task_folder>
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
HALT_MERGE_JQ='def halt_merge($old; $new):
  (($old // "") | if . == "" then [] else split("; earlier: ") end) as $segments
  | ([$new] + ($segments | map(select(. != $new)))) | join("; earlier: ");
'

# Every segment of halt reason $1, one per line. Empty prints nothing.
halt_segments() {
  printf '%s' "$1" | jq -r 'if . == "" then empty else split("; earlier: ")[] end' 2>/dev/null
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
im_next_step() {
  local ledger="$1" snapshot="$2" impl="$3" precon="$4" finished="$5"
  if [ -z "$ledger" ] || [ -z "$snapshot" ]; then
    printf 'start'
    return 0
  fi
  if [ "$finished" = "true" ]; then
    printf 'none: implementation is finished, and the review stage is next'
    return 0
  fi
  # How many actionable findings each reviewed order still has open, read once per order here so
  # the jq below decides fix-or-close without opening a file itself.
  local opens ids count i id file n
  opens='{}'
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
    i=$((i + 1))
  done
  printf '%s' "$ledger" | jq -r --argjson opens "$opens" --argjson snap "$snapshot" \
    --argjson allowed "$BUILD_ATTEMPTS_ALLOWED" --argjson precon "$precon" '
    (.orders // []) as $orders
    | ([ $orders[] | select(.lastStep == "closed") | .id ]) as $closed
    | ([ $orders[] | select((.haltedBecause // "") == "") ]) as $live
    | (($snap.workOrders // []) | map({(.id): (.dependsOn // [])}) | add // {}) as $deps
    | ([ $live[] | select(.lastStep == "checks-passed" or .lastStep == "reviewed" or .lastStep == "fixed") ] | .[0]) as $rv
    | ([ $live[] | select(.lastStep == "tests-frozen"
                          or (.lastStep == "code-written" and ((.attemptsUsed // 0) < (.attemptsAllowed // $allowed)))) ] | .[0]) as $bd
    | ([ $live[] | select(.lastStep == null) | select((($deps[.id] // []) - $closed) | length == 0) ] | .[0]) as $ts
    | ([ $orders[] | select((.haltedBecause // "") | contains("design drift")) ] | .[0]) as $drift
    | ([ $orders[] | select((.haltedBecause // "") | contains("attempts spent")) ] | .[0]) as $spent
    | ([ $orders[] | select((.haltedBecause // "") != "") ] | length) as $halted
    | if ($precon | not) and ($rv != null or $bd != null or $ts != null) then "preconditions"
      elif $rv != null then
        (if $rv.lastStep == "checks-passed" then "review \($rv.id): review the order"
         elif (($opens[$rv.id] // 0) > 0) then "review \($rv.id): fix, then verify"
         else "review \($rv.id): close the order" end)
      elif $bd != null then "build \($bd.id)"
      elif $ts != null then "tests \($ts.id)"
      elif (($orders | length) > 0 and ($closed | length) == ($orders | length) and $halted == 0) then "finish"
      elif $drift != null then "finish: offer the restart, \($drift.id) is halted for design drift"
      elif $spent != null then "finish: offer the grant, \($spent.id) is halted with its attempts spent"
      elif $halted > 0 then "none: every order that is not closed is halted for a reason neither a grant nor a restart answers"
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
        code_path="$(project_code_path_value "$project_path")"
        [ -n "$code_path" ] || project_note="$project_path/project.json is valid JSON but has no usable codePath field"
        ;;
    esac
  else
    project_path=""
    project_note="could not resolve a project folder two levels up from the task folder, or it has no project.json"
  fi

  local git_checked git_is_repo git_branch trunk_derived trunk_branch trunk_note
  git_checked=false
  git_is_repo=false
  git_branch=""
  trunk_derived=false
  trunk_branch=""
  trunk_note="not checked"
  if [ -n "$code_path" ]; then
    git_checked=true
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
  run_mode="$(jq -r '.runMode // "interactive"' "$TASK_PATH/task.json" 2>/dev/null)"
  [ -n "$run_mode" ] || run_mode="interactive"

  local snap_exists snap_readable snap_note snap_summary
  snap_exists=false; snap_readable=false; snap_note="not started"; snap_summary='null'
  if [ -f "$SNAPSHOT_FILE" ]; then
    snap_exists=true
    if [ -r "$SNAPSHOT_FILE" ] && jq empty "$SNAPSHOT_FILE" 2>/dev/null; then
      snap_readable=true
      snap_note="ok"
      snap_summary="$(jq -c '{schemaVersion, takenAt, hash, workOrderCount: ((.workOrders // []) | length)}' "$SNAPSHOT_FILE" 2>/dev/null)"
      [ -n "$snap_summary" ] || snap_summary='null'
    else
      snap_note="present but could not be read as JSON"
    fi
  fi

  local ledger_exists ledger_readable ledger_note ledger_summary
  ledger_exists=false; ledger_readable=false; ledger_note="not started"; ledger_summary='null'
  if [ -f "$LEDGER_FILE" ]; then
    ledger_exists=true
    if [ -r "$LEDGER_FILE" ] && jq empty "$LEDGER_FILE" 2>/dev/null; then
      ledger_readable=true
      ledger_note="ok"
      ledger_summary="$(jq -c '{
          schemaVersion, startedFrom, runMode, snapshotHash,
          orderCount: ((.orders // []) | length),
          ordersByLastStep: ((.orders // []) | group_by(.lastStep // "null") | map({key: (.[0].lastStep // "null"), value: length}) | from_entries),
          criteriaCount: ((.criteria // []) | length),
          criteriaByRowState: ((.criteria // []) | group_by(.rowState) | map({key: .[0].rowState, value: length}) | from_entries),
          orderStates: [ (.orders // [])[] | {id: .id, lastStep: .lastStep, haltedBecause: (.haltedBecause // null)} ],
          rowsJudgedByModel: ([ (.criteria // [])[] | (.judgements // [])[] | select(.judgedBy == "model") ] | length),
          rowsJudgedByModelCriteria: ([ (.criteria // [])[] | select((.judgements // []) | map(.judgedBy == "model") | any) | .id ])
        }' "$LEDGER_FILE" 2>/dev/null)"
      [ -n "$ledger_summary" ] || ledger_summary='null'
    else
      ledger_note="present but could not be read as JSON"
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
  local reviews_json order_ids order_count oi one_id one_file one_exists one_open one_note
  reviews_json='[]'
  if [ "$ledger_readable" = "true" ]; then
    order_ids="$(jq -c '[ (.orders // [])[] | .id ]' "$LEDGER_FILE" 2>/dev/null)"
    [ -n "$order_ids" ] || order_ids='[]'
    order_count="$(printf '%s' "$order_ids" | jq 'length')"
    oi=0
    while [ "$oi" -lt "$order_count" ]; do
      one_id="$(printf '%s' "$order_ids" | jq -r --argjson i "$oi" '.[$i]')"
      one_file="$IMPL_DIR/review-$one_id.json"
      one_exists=false; one_open=0; one_note="no review record"
      if [ -f "$one_file" ]; then
        one_exists=true
        if jq empty "$one_file" 2>/dev/null; then
          one_open="$(jq '[ (.findings // [])[] | select(.actionable == true and .status == "open") ] | length' "$one_file" 2>/dev/null)"
          case "$one_open" in ''|*[!0-9]*) one_open=0 ;; esac
          one_note="ok"
        else
          one_note="present but could not be read as JSON"
        fi
      fi
      reviews_json="$(printf '%s' "$reviews_json" | jq -c --arg unit "$one_id" \
        --argjson exists "$one_exists" --argjson open "$one_open" --arg note "$one_note" \
        '. + [{unit: $unit, reviewRecordExists: $exists, openActionableFindings: $open, note: $note}]')"
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
    orders_json="$(jq -c --argjson reviews "$reviews_json" '
      ($reviews | map({(.unit): .}) | add // {}) as $rv
      | [ (.orders // [])[] | . as $o
          | {id: .id,
             step: (.lastStep // "not started"),
             halt: ("halt: " + (.haltedBecause // "none")),
             attempts: ("attempts=" + ((.attemptsUsed // 0) | tostring)),
             rounds: ("rounds=" + ((.roundsUsed // 0) | tostring)),
             review: (if ($rv[$o.id].reviewRecordExists // false) then "review: open=\($rv[$o.id].openActionableFindings)" else "review: none" end)} ]' \
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
    --arg runMode "$run_mode, from task.json" \
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
  [ "$#" -ge 1 ] || die 3 "start: a task folder is required"
  [ "$#" -le 1 ] || die 3 "start: unrecognized extra argument: $2"
  local task_path="$1"

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
            ((.graph.orphanSupportOrders // [])[] | "order " + . + " owns nothing and reaches no owner"),
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
  local run_mode_raw run_mode
  run_mode_raw="$(jq -r 'if type == "object" and has("runMode") then (.runMode | tostring) else "__aida_absent__" end' "$TASK_PATH/task.json" 2>/dev/null)"
  case "$run_mode_raw" in
    __aida_absent__) run_mode="interactive" ;;
    autonomous) run_mode="autonomous" ;;
    interactive)
      die 3 "start: $TASK_PATH/task.json declares runMode \"interactive\". The schema allows only \"autonomous\" there; absence already means interactive. Remove the field, or set it to \"autonomous\", by hand."
      ;;
    *)
      die 3 "start: $TASK_PATH/task.json has an unusable runMode ('$run_mode_raw'); expected it absent or 'autonomous'."
      ;;
  esac

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
  local dependent_halts_json='[]' drift_halts_json='[]'
  local drift_checked=false

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

    mark_task_in_progress "$TASK_PATH" "implementation started"
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
                  {id: $s.id, reason: ("design drift: the design file for " + $s.id + " no longer exists, or could not be read, since the snapshot was taken")}
                elif ($l != $s) then
                  {id: $s.id, reason: ("design drift: the design file for " + $s.id + " has changed since the snapshot was taken")}
                else
                  empty
                end
            ]
        ')"
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
              | ([ $r[] | select(($bad | index(.)) != null) ]) as $hits
              | select(($hits | length) > 0)
              | {id: $x, reason: ("design drift: " + $x + " depends on " + ($hits | join(", ")) + ", directly or through another order, and that design file changed since the snapshot was taken")}
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
  local cycles_json overlap_json
  cycles_json="$(jq -c -n --argjson orders "$snapshot_workorders_json" '
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
  overlap_json="$(jq -c -n --argjson orders "$snapshot_workorders_json" '
      [ range(0; ($orders | length)) as $i
        | range($i + 1; ($orders | length)) as $j
        | ($orders[$i]) as $a | ($orders[$j]) as $b
        | (($a.ownedFiles // []) as $af | ($b.ownedFiles // []) as $bf
            | [ $af[] as $p | select($bf | index($p) != null) | $p ]) as $shared
        | $shared[] as $path
        | {ids: [$a.id, $b.id], path: $path}
      ]
    ')"
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

  local final_orders_json final_criteria_json ledger_started_from ledger_run_mode
  if [ "$ledger_present" = "true" ]; then
    opened_as="reopened"
    local stored_snapshot_hash
    stored_snapshot_hash="$(printf '%s' "$ledger_doc" | jq -r '.snapshotHash // empty')"
    [ "$stored_snapshot_hash" = "$snapshot_hash_on_disk" ] \
      || die 9 "start: $LEDGER_FILE was opened against a different snapshot (its snapshotHash is $stored_snapshot_hash) than the one now on disk (hash $snapshot_hash_on_disk). A ledger and a snapshot that do not belong together are never read as a pair; investigate before proceeding."

    ledger_started_from="$(ledger_required_string "$ledger_doc" "startedFrom")" \
      || die 3 "start: $LEDGER_FILE is damaged (see stderr above). Repair or remove it by hand before running this again."
    ledger_run_mode="$(ledger_required_string "$ledger_doc" "runMode")" \
      || die 3 "start: $LEDGER_FILE is damaged (see stderr above). Repair or remove it by hand before running this again."

    # A drift halt never writes over a reason the order already carries. The old text is kept after
    # the new one, joined by "; earlier: ", so nothing loses a reason; and a start run repeated on
    # the same drift adds nothing, because the reason it would write is already at the front.
    final_orders_json="$(printf '%s' "$ledger_doc" | jq -c --argjson drifted "$drift_halts_json" "$HALT_MERGE_JQ"'
        .orders | map(
          . as $o
          | (([ $drifted[] | select(.id == $o.id) | .reason ])[0]) as $r
          | if $r == null then $o else ($o + {haltedBecause: halt_merge($o.haltedBecause; $r)}) end
        )
      ')"
    final_criteria_json="$(printf '%s' "$ledger_doc" | jq -c '.criteria')"
  else
    opened_as="opened"
    ledger_started_from="$started_from"
    ledger_run_mode="$run_mode"

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

  mkdir -p "$IMPL_DIR" || die 3 "start: could not create $IMPL_DIR"
  local ledger_json_out
  ledger_json_out="$(jq -n \
    --arg startedFrom "$ledger_started_from" --arg runMode "$ledger_run_mode" \
    --arg snapshotHash "$snapshot_hash_on_disk" \
    --argjson orders "$final_orders_json" --argjson criteria "$final_criteria_json" \
    '{schemaVersion: 1, startedFrom: $startedFrom, runMode: $runMode, snapshotHash: $snapshotHash,
      orders: $orders, criteria: $criteria}')"
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
  local run_state all_closed_count order_total
  order_total="$(printf '%s' "$final_orders_json" | jq 'length')"
  all_closed_count="$(printf '%s' "$final_orders_json" | jq '[ .[] | select(.lastStep == "closed") ] | length')"
  if [ "$(printf '%s' "$ready_ids_json" | jq 'length')" -gt 0 ]; then
    run_state="orders are ready to build"
  elif [ "$(printf '%s' "$in_flight_json" | jq 'length')" -gt 0 ]; then
    run_state="an order is in flight; continue it at the step the ledger records"
  elif [ "$(printf '%s' "$halted_json" | jq 'length')" -gt 0 ]; then
    run_state="every order that is not closed is halted; read the halt reasons and use grant-attempt or restart"
  elif [ "$order_total" -gt 0 ] && [ "$all_closed_count" -eq "$order_total" ]; then
    run_state="every order is closed; run finish on this task"
  else
    run_state="no order is ready, none is in flight and none is halted. Every remaining order waits on a dependency that is not closed, so nothing can start; read the order states below."
  fi
  # The ledger is the authority on the run mode, and every later step reads it there
  # (ledger-schema.json). A task.json edited between runs would otherwise give a resumed run a
  # report saying interactive while every refusal, halt and row check applied the autonomous rule.
  local reported_run_mode run_mode_source
  reported_run_mode="$run_mode"
  run_mode_source="task.json"
  if [ "$opened_as" = "reopened" ]; then
    reported_run_mode="$ledger_run_mode"
    run_mode_source="the ledger, which is the authority every later step reads"
  fi
  # The report, as summary lines. The snapshot and the ledger stay in their files, named by path;
  # the orders that drifted, halted and are ready are named by id, and `next` is the same answer
  # `read` gives from the same ledger. The preconditions record cannot exist before the first
  # start, and a resumed run reads whether it is there the way `read` does.
  local st_precon st_finished st_ledger_now st_next
  st_precon=false
  st_finished=false
  [ -f "$IMPL_DIR/preconditions.json" ] && jq empty "$IMPL_DIR/preconditions.json" 2>/dev/null && st_precon=true
  [ -f "$IMPL_DIR/finished.json" ] && jq empty "$IMPL_DIR/finished.json" 2>/dev/null && st_finished=true
  st_ledger_now="$(jq -c '.' "$LEDGER_FILE" 2>/dev/null)"
  st_next="$(im_next_step "$st_ledger_now" "$(jq -nc --argjson w "$snapshot_workorders_json" '{workOrders: $w}')" "$IMPL_DIR" "$st_precon" "$st_finished")"
  im_print_summary "start" "$(jq -n \
    --arg task "$TASK_PATH" --arg codePath "$code_path" \
    --arg run "${run_kind}, ledger ${opened_as}" \
    --arg runMode "${reported_run_mode}, from ${run_mode_source}" \
    --arg branch "$current_branch" \
    --arg trunk "$(if [ "$trunk_derived" = "true" ]; then printf '%s | ' "$trunk_branch"; fi)$trunk_note" \
    --arg snapshot "$SNAPSHOT_FILE" \
    --arg snapshotHash "$snapshot_hash_on_disk | workOrders=$(printf '%s' "$snapshot_workorders_json" | jq 'length') | criteria=$(printf '%s' "$snapshot_criteria_json" | jq 'length')" \
    --arg ledger "$LEDGER_FILE" --arg startedFrom "$started_from" \
    --arg drift "$(if [ "$drift_checked" = "true" ]; then printf 'checked | contractChanged=%s' "$contract_changed_json"; else printf 'not checked: a first run has no earlier snapshot to compare against'; fi)" \
    --argjson drifted "$(printf '%s' "$drifted_orders_json" | jq -c '[ .[] | .id ]')" \
    --argjson haltedDependents "$(printf '%s' "$dependent_halts_json" | jq -c '[ .[] | .id ]')" \
    --argjson newLiveOrders "$new_live_order_ids_json" \
    --argjson halted "$(printf '%s' "$halted_json" | jq -c '[ .[] | {id, haltedBecause} ]')" \
    --argjson inFlight "$(printf '%s' "$in_flight_json" | jq -c '[ .[] | {id, lastStep, attempts: ("attempts=" + (.attemptsUsed | tostring)), rounds: ("rounds=" + (.roundsUsed | tostring))} ]')" \
    --argjson ready "$ready_ids_json" \
    --arg state "$run_state" --arg next "$st_next" '
    {task: $task, codePath: $codePath, run: $run, runMode: $runMode, branch: $branch, trunk: $trunk,
     snapshot: $snapshot, snapshotHash: $snapshotHash, ledger: $ledger, startedFrom: $startedFrom,
     drift: $drift, drifted: $drifted, haltedDependents: $haltedDependents, newLiveOrders: $newLiveOrders,
     halted: $halted, inFlight: $inFlight, ready: $ready, state: $state, next: $next}')"
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
# `{runner}`, is never read here as a fallback: the caller supplies it or the run says so. The
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
# directory anyway.
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
  ) >"$outfile" 2>/dev/null
  printf '%s' "$?"
}

# Strips one layer of matching outer quotes. A recipe writes its expected string quoted, so the
# value can carry quotes of its own, and the outer pair belongs to the document rather than to the
# string being looked for.
pc_unquote() {
  case "$1" in
    "'"*"'") printf '%s' "$1" | sed "s/^'//; s/'$//" ;;
    '"'*'"') printf '%s' "$1" | sed 's/^"//; s/"$//' ;;
    *)       printf '%s' "$1" ;;
  esac
}

# The entry being read, held between lines. Bash 3.2 has no nameref, so the parse loop and its
# flush share these rather than passing a record around.
PC_ID=""; PC_WHAT=""; PC_CHECK=""; PC_OWNER=""; PC_EXPECT=""; PC_ANY=0

# Runs the held entry's check and appends one JSON object to $1. Clears the entry afterwards, so a
# second call with nothing held writes nothing.
pc_flush_entry() {
  local out="$1" codepath="$2"
  local verdict reason rc exitjson
  [ -n "$PC_ID" ] || return 0
  PC_ANY=1
  verdict=""; reason=""; exitjson="null"
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
    rm -f "$out.stdout"
  fi
  jq -n --arg id "$PC_ID" --arg what "$PC_WHAT" --arg owner "$PC_OWNER" --arg check "$PC_CHECK" \
        --arg expect "$PC_EXPECT" \
        --arg verdict "$verdict" --arg reason "$reason" --argjson exitCode "$exitjson" '
    {id: $id, what: (if $what == "" then $id else $what end), verdict: $verdict}
    + (if $check    == ""   then {} else {check: ([$check | splits("[ \t]+")] | map(select(length > 0)))} end)
    + (if $expect   == ""   then {} else {expect: $expect} end)
    + (if $owner    == ""   then {} else {owner: $owner} end)
    + (if $reason   == ""   then {} else {reason: $reason} end)
    + (if $exitCode == null then {} else {exitCode: $exitCode} end)
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
# error together, exactly as the command wrote them, for the caller to trim and record.
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
  ) >"$outfile" 2>&1
  printf 'RAN\t%s' "$?"
}

# ------------------------------------------------------------------------------------------------
# The baseline: what was already broken at the commit the build starts from. Taken once, at the
# end of `preconditions`, only when that run's own verdict permits the build to continue.
# ------------------------------------------------------------------------------------------------

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
  local out_file result kind payload verdict reason exit_code_json output truncated raw_len
  count="$(printf '%s' "$record_json" | jq '.frameworks | length' 2>/dev/null)"
  case "$count" in ''|*[!0-9]*) count=0 ;; esac
  i=0
  while [ "$i" -lt "$count" ]; do
    fw_obj="$(printf '%s' "$record_json" | jq -c --argjson i "$i" '.frameworks[$i]' 2>/dev/null)"
    fw="$(printf '%s' "$fw_obj" | jq -r '.framework')"
    tc_state="$(printf '%s' "$fw_obj" | jq -r '.testCommands.state')"
    verdict=""; reason=""; exit_code_json="null"; output=""; truncated=false
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
        out_file="$(dirname -- "$out")/.baseline-suite-run.$$"
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
        rm -f "$out_file"
      fi
    fi
    jq -n --arg framework "$fw" --arg verdict "$verdict" --arg reason "$reason" \
          --arg output "$output" --argjson truncated "$truncated" --argjson exitCode "$exit_code_json" '
      {framework: $framework, verdict: $verdict}
      + (if $reason   == ""   then {} else {reason: $reason} end)
      + (if $exitCode == null then {} else {exitCode: $exitCode} end)
      + (if $output   == ""   then {} else {output: $output} end)
      + (if $truncated == true then {truncated: true} else {} end)
    ' >>"$out" || die 3 "preconditions: could not record the baseline suite result for framework $fw"
    i=$((i + 1))
  done
}

# Runs one baseline tool command over the baseline scope and prints the field object baseline.json
# holds for it. $1 the check id, $2 a word for the message, $3 the code repository, $4 the scope as
# a JSON array of paths, $5 a file to capture output in. The command, its signal and its extensions
# come from the resolved recipe in CR_DOC, never from a flag a caller typed.
#
# The baseline has nothing earlier to compare itself against, so the rule is the suite own: met on
# exit 0, unknown when the command could not be run at all with a reason saying so, unmet on any
# other exit it actually returned. A row the recipe declares absent stays undeclared and carries
# the recipe own reason. The exit code and the output are kept met or not, because a baseline is a
# record of the whole state and not only of what pointed at a defect.
bl_tool_result() {
  local check_id="$1" label="$2" codepath="$3" paths_json="$4" outfile="$5"
  local row argv_json signal exts_json absent_declared missing_why
  local verdict reason exit_json output truncated rc raw_len
  local has_paths scoped_json scoped_count errfile stdout_len result kind payload
  verdict=""; reason=""; exit_json="null"; output=""; truncated=false

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
  printf '%s' "$argv_json" | jq -e 'any(.[]; . == "{paths}" or . == "{file}")' >/dev/null 2>&1 && has_paths=true
  scoped_json="$paths_json"
  if [ -n "$exts_json" ]; then
    scoped_json="$(br_filter_extensions "$paths_json" "$exts_json")"
  fi
  scoped_count="$(printf '%s' "$scoped_json" | jq 'length')"

  if [ "$has_paths" = "true" ] && [ "$(printf '%s' "$paths_json" | jq 'length')" -eq 0 ]; then
    # A tool handed no path at all reads that as its own default scope, so it would answer about the
    # whole repository while this record claims it answered about the scope. That is a wrong verdict,
    # not a missing one.
    verdict="unknown"
    reason="the $label command holds a path placeholder, and no work order declares an owned file, so the command would run over no path at all"
  elif [ "$has_paths" = "true" ] && [ -n "$exts_json" ] && [ "$scoped_count" -eq 0 ]; then
    verdict="undeclared"
    reason="the $label command reads only $(printf '%s' "$exts_json" | jq -r 'join(", ")'), and the scope holds no file with one of those extensions, so the row does not apply"
  else
    stdout_len=0
    errfile=""
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
    rm -f "$outfile"
  fi
  jq -n --arg verdict "$verdict" --arg reason "$reason" --arg output "$output" \
        --argjson truncated "$truncated" --argjson exitCode "$exit_json" \
        --arg signal "$signal" --arg exts "${exts_json:-}" '
    {verdict: $verdict}
    + (if $reason   == ""   then {} else {reason: $reason} end)
    + (if $exitCode == null then {} else {exitCode: $exitCode} end)
    + (if $output   == ""   then {} else {output: $output} end)
    + (if $truncated == true then {truncated: true} else {} end)
    + (if $signal == "" then {} else {signal: $signal} end)
    + (if $exts   == "" then {} else {extensions: ($exts | fromjson)} end)
  '
}

# The step. Every framework the project declares must be answered for, because the build runs in
# one repository that is all of them at once.
do_preconditions() {
  local task_folder="" project_folder codepath
  local recipes="" failures="" values="" check_recipes="" arg fw val
  local tool_out_file cs_json sa_json sec_json
  local frameworks fw_count entries_file fw_json_file tc_rows_file
  local lookup recipe_path section_state fw_verdict entries_json run_verdict
  local tc_state tc_rows_json
  local smoke_verdict smoke_reason smoke_output smoke_truncated smoke_exit_code_json
  local smoke_row_json smoke_argv_json smoke_out_file smoke_result smoke_kind smoke_payload
  local smoke_raw_len smoke_json
  local record_file record_json today
  local baseline_status baseline_note baseline_commit_report baseline_summary_json
  local ledger_doc ledger_started_from check_recipes_json order_tests_absent
  local snapshot_doc scope_json suite_json_file suite_json baseline_json existing_commit

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

  # Every commanded check the build runs later comes from a recipe, resolved once here so a
  # framework that can never answer is named now rather than at the first build-record. An order
  # whose own tests nothing runs never reaches checks-passed, so a framework declaring both rows
  # that run a named set of tests absent stops the run here, with the framework named.
  PC_VALUES="$values"
  CR_WHO="preconditions"
  CR_TEST_RECIPES="$recipes"
  CR_CHECK_RECIPES="$check_recipes"
  cr_resolve
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

    : >"$entries_file"
    : >"$tc_rows_file"
    if [ "$lookup" = "resolved" ]; then
      [ -f "$recipe_path" ] || die 3 "preconditions: the recipe handed over for $fw is not a file: $recipe_path"
      section_state="$(pc_parse_recipe "$recipe_path" "$entries_file" "$codepath")"
      case "$section_state" in
        undeclared)     fw_verdict="undeclared" ;;
        declared-empty) fw_verdict="undeclared" ;;
        unparseable)    fw_verdict="unknown" ;;
        *)              fw_verdict="met" ;;
      esac
      # The test-commands block never affects a verdict; it is read here only because it lives in
      # the same recipe file this framework already resolved, and the record already has a place
      # for the rest of what that recipe declared. cr_resolve above already parsed it, so this
      # reads that result rather than opening the same file a second time.
      tc_state="$(printf '%s' "$CR_DOC" | jq -r --arg f "$fw" \
        '[ (.frameworks // [])[] | select(.framework == $f) ][0].testCommandsState // "not-given"')"
      printf '%s' "$CR_DOC" | jq -c --arg f "$fw" \
        '[ (.frameworks // [])[] | select(.framework == $f) ][0].testCommandsRows // [] | .[]' >"$tc_rows_file"
    else
      # Nobody looked. That is a different fact from a recipe that looked and declared nothing.
      section_state="not-looked"
      fw_verdict="unknown"
      tc_state="not-looked"
    fi

    entries_json="$(jq -s '.' "$entries_file" 2>/dev/null)" || entries_json="[]"
    tc_rows_json="$(jq -s '.' "$tc_rows_file" 2>/dev/null)" || tc_rows_json="[]"
    if [ "$section_state" = "ok" ]; then
      fw_verdict="$(jq -r '
        def rank: if . == "met" then 0 elif . == "undeclared" then 1 elif . == "unknown" then 2 else 3 end;
        (map(.verdict) + ["met"]) | max_by(rank)
      ' <<EOF
$entries_json
EOF
)"
    fi

    # The smoke row is run, never merely recorded, and only once this framework's own conditions
    # have already answered `met` or `undeclared`. Running it any earlier would only fail for a
    # reason a condition already named.
    smoke_verdict=""; smoke_reason=""; smoke_output=""; smoke_truncated=false
    smoke_exit_code_json="null"
    case "$fw_verdict" in
      met|undeclared)
        if [ "$tc_state" = "undeclared" ]; then
          # No `## Test commands` heading at all is the recipe declaring nothing about a smoke
          # command, the same fact `undeclared` already names at the framework's own conditions.
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
          --argjson exitCode "$smoke_exit_code_json" '
      {verdict: $verdict}
      + (if $reason == "" then {} else {reason: $reason} end)
      + (if $output == "" then {} else {output: $output} end)
      + (if $truncated == true then {truncated: true} else {} end)
      + (if $exitCode == null then {} else {exitCode: $exitCode} end)
    ')"

    jq -n --arg framework "$fw" --arg lookup "$lookup" --arg recipePath "$recipe_path" \
          --arg verdict "$fw_verdict" --argjson entries "$entries_json" \
          --arg tcState "$tc_state" --argjson tcRows "$tc_rows_json" --argjson smoke "$smoke_json" '
      {framework: $framework, lookup: $lookup, verdict: $verdict, entries: $entries,
       testCommands: {state: $tcState, rows: $tcRows}, smoke: $smoke}
      + (if $recipePath == "" then {} else {recipePath: $recipePath} end)
    ' >>"$fw_json_file" || die 3 "preconditions: could not record the result for framework $fw"
  done || exit $?

  rm -f "$entries_file" "$tc_rows_file"

  # The worst of every framework's own verdict AND its own smoke run's verdict: the run's answer
  # is never met while a framework's smoke command is unmet or unknown, the same way it is never
  # met while a condition is.
  run_verdict="$(jq -s -r '
    def rank: if . == "met" then 0 elif . == "undeclared" then 1 elif . == "unknown" then 2 else 3 end;
    ([ .[] | .verdict, .smoke.verdict ] + ["met"]) | max_by(rank)
  ' "$fw_json_file")"

  today="$(date -u +%Y-%m-%d)"
  record_json="$(jq -s --arg takenAt "$today" --arg verdict "$run_verdict" '
    {schemaVersion: 1, takenAt: $takenAt, verdict: $verdict, frameworks: .}
  ' "$fw_json_file")" || die 3 "preconditions: could not assemble the record"
  rm -f "$fw_json_file"

  record_file="$task_folder/implementation/preconditions.json"
  write_atomic "$record_file" "$record_json"

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
    met|undeclared)
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
          bl_run_suite "$record_json" "$codepath" "$values" "$suite_json_file"
          suite_json="$(jq -s '.' "$suite_json_file" 2>/dev/null)" || suite_json="[]"
          rm -f "$suite_json_file"

          # The three tools run over the baseline scope, the same union of every order's ownedFiles
          # recorded above. A caller that passed no flag for one of them leaves it undeclared, with
          # the reason this record has always carried.
          tool_out_file="$task_folder/implementation/.baseline-tool.$$"
          cs_json="$(bl_tool_result "coding-standards" "coding-standards" "$codepath" "$scope_json" "$tool_out_file")"
          sa_json="$(bl_tool_result "static-analysis" "static-analysis" "$codepath" "$scope_json" "$tool_out_file")"
          sec_json="$(bl_tool_result "security" "security" "$codepath" "$scope_json" "$tool_out_file")"
          rm -f "$tool_out_file"

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
            die 21 "preconditions: $BASELINE_FILE already holds a baseline taken at commit $existing_commit, but this run's own ledger started from a different commit, $ledger_started_from. A baseline is taken once, at the commit the build started from, and never retaken after that: retaking it here would measure the wrong repository state. Investigate before proceeding; remove $BASELINE_FILE by hand only if this task's baseline is meant to start over."
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
  local pc_next
  pc_next="$(im_next_step "$STARTED_LEDGER_DOC" "$SNAPSHOT_DOC" "$task_folder/implementation" "true" "false")"
  case "$run_verdict" in
    met|undeclared) ;;
    *) pc_next="none: the preconditions verdict is $run_verdict, so the build does not go on; read the record" ;;
  esac
  im_print_summary "preconditions" "$(jq -n --arg verdict "$run_verdict" --arg record "$record_file" \
        --argjson report "$record_json" \
        --arg baselineFile "$BASELINE_FILE" --arg baselineStatus "$baseline_status" \
        --arg baselineNote "$baseline_note" --arg baselineCommit "$baseline_commit_report" \
        --argjson baselineSummary "$baseline_summary_json" --arg next "$pc_next" '
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
        smoke: ("smoke=" + .smoke.verdict + (if (.smoke.reason // "") == "" then "" else " (" + .smoke.reason + ")" end)) } ],
     baseline: ($baselineStatus + " | " + $baselineNote),
     baselineFile: (if $baselineStatus == "not-attempted" then "none" else $baselineFile end),
     baselineCommit: (if $baselineCommit == "" then "none" else $baselineCommit end),
     baselineSuite: (if $baselineSummary == null then "none"
                     else ([ $baselineSummary.suite[] | .framework + "=" + .verdict ] | if length == 0 then "none" else join(" ") end) end),
     baselineTools: (if $baselineSummary == null then "none"
                     else "codingStandards=" + $baselineSummary.codingStandards.verdict
                          + " staticAnalysis=" + $baselineSummary.staticAnalysis.verdict
                          + " security=" + $baselineSummary.security.verdict end),
     next: $next}')"

  # `met` and `undeclared` both go on. A recipe that says this framework needs nothing before a
  # test runs, or nothing before a smoke command proves one, has answered, and refusing on it
  # would mean no project on that framework ever builds. The two never share a value in the
  # record, and the report names which one happened, which is the whole of what "undeclared is
  # not met" protects: a caller must not report a recipe that declared nothing as a set of
  # conditions that passed.
  case "$run_verdict" in
    met|undeclared) ;;
    *) exit 19 ;;
  esac
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

tt_load_snapshot() {
  local who="$1"
  local snapshot_file="$IMPL_DIR/snapshot.json"
  [ -f "$snapshot_file" ] \
    || die 25 "$who: $snapshot_file not found. This step ran before start, so there is no frozen copy. Run start on this task first."
  SNAPSHOT_DOC="$(jq -c '.' "$snapshot_file" 2>/dev/null)"
  [ -n "$SNAPSHOT_DOC" ] \
    || die 3 "$who: $snapshot_file exists but could not be read as JSON, though start already wrote it. Repair or remove it by hand before running this again."
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
  local dep_record_file dep_record_text
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
    else
      die 23 "tests-brief: $unit_id depends on $dep_id, which has no completion record ($ledger_file records its last step as $dep_step), so its interface record does not exist yet."
    fi
    i=$((i + 1))
  done

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

  # --- assemble the brief: exactly these four keys, and nothing else ------------------------------
  local non_goal_ids_json non_goals_out unit_out
  non_goal_ids_json="$(printf '%s' "$UNIT_JSON" | jq -c '.nonGoals // []')"
  non_goals_out="$(printf '%s' "$SNAPSHOT_DOC" | jq -c --argjson ids "$non_goal_ids_json" \
    '(.alignment.nonGoals // []) | map(select(.id as $i | $ids | index($i) != null))')"
  local criteria_out
  criteria_out="$(printf '%s' "$CRITERIA_JSON" | jq -c \
    '[ .[] | {id, text, verification, verifiedBy} ]')"
  unit_out="$(printf '%s' "$UNIT_JSON" | jq -c \
    '{id, title, tests: (.tests // []), doneWhen: (.doneWhen // []), interface: (.interface // ""), diffBudget: (.diffBudget // "")}')"

  # The brief is a file the dispatch names, never text printed through this conversation. It
  # carries the criteria, the non-goals and every dependency's interface record, and printing it
  # would spend the orchestrator's own context on words only the test author reads.
  local brief_file brief_json
  brief_file="$IMPL_DIR/brief-$unit_id-tests.json"
  brief_json="$(jq -n --argjson unit "$unit_out" --argjson criteria "$criteria_out" \
        --argjson nonGoals "$non_goals_out" --argjson dependencyInterfaces "$dependency_interfaces_json" \
    '{unit: $unit, criteria: $criteria, nonGoals: $nonGoals, dependencyInterfaces: $dependencyInterfaces}')"
  [ -n "$brief_json" ] || die 3 "tests-brief: could not assemble the brief for $unit_id."
  write_atomic "$brief_file" "$brief_json"
  im_print_summary "tests-brief" "$(printf '%s' "$brief_json" | jq -c --arg brief "$brief_file" '
    {order: .unit.id,
     brief: $brief,
     criteria: ([ .criteria[] | .id + " (" + .verifiedBy + ")" ]),
     nonGoals: (.nonGoals | length),
     declaredTests: (.unit.tests | length),
     dependencyInterfaces: ([ .dependencyInterfaces[] | .id + (if has("interfaceRecord") then " (record)" else " (declared only)" end) ]),
     next: "dispatch test-author with the brief path and the test-authoring recipe path, then tests-freeze"}')"
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
# `{name, reason}` JSON object per line to file $2.
tf_parse_goa() {
  local raw="$1" out="$2" line name reason
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      *"="*) : ;;
      *) die 3 "tests-freeze: --green-on-arrival value has no '=' separating the test name from the reason: $line" ;;
    esac
    name="${line%%=*}"
    reason="${line#*=}"
    [ -n "$name" ]   || die 3 "tests-freeze: --green-on-arrival value has an empty test name: $line"
    [ -n "$reason" ] || die 3 "tests-freeze: --green-on-arrival value has an empty reason: $line"
    jq -n --arg name "$name" --arg reason "$reason" '{name: $name, reason: $reason}' >>"$out" \
      || die 3 "tests-freeze: could not record the --green-on-arrival row for $name"
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

do_tests_freeze() {
  local task_arg="" unit_id="" test_raw="" red_raw="" glob_raw="" checklist_raw="" goa_raw="" row_raw=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --test)
        [ "$#" -ge 2 ] || die 3 "tests-freeze: --test needs <path>::<test name>=<criterion id>[,<criterion id>...]"
        test_raw="$test_raw$2
"
        shift 2 ;;
      --red)
        [ "$#" -ge 2 ] || die 3 "tests-freeze: --red needs <test name>=<path to a file holding what the run printed>"
        red_raw="$red_raw$2
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
        [ "$#" -ge 2 ] || die 3 "tests-freeze: --row needs <criterion id>=<confirmed|rejected>::<person|model>::<note>"
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

  # --- 74: an order that serves and owns no criterion ---------------------------------------------
  # Every guard below iterates a per-criterion list, so an order with none passes all of them and
  # freezes a record with no test and no glob in it. The reference then proves nothing, and the
  # frozen-tests check later hashes nothing and answers met.
  [ "$(printf '%s' "$CRITERIA_IDS_JSON" | jq 'length')" -gt 0 ] \
    || die 74 "tests-freeze: $unit_id serves and owns no criterion, so there is nothing for a test to prove and nothing for this step to freeze. Design left this order with no criteriaServed and no criteriaOwned; repair the work order and close design again."

  # --- 76: a re-freeze after the order has already left the frozen state ---------------------------
  # A re-freeze rewinds lastStep and leaves attemptsUsed and the build record where they are, so the
  # order would rebuild with a spent counter and a record for tests that no longer exist.
  local tf_prior_step tf_prior_ledger
  if [ -f "$IMPL_DIR/ledger.json" ]; then
    tf_prior_ledger="$(jq -c '.' "$IMPL_DIR/ledger.json" 2>/dev/null)"
    if [ -n "$tf_prior_ledger" ]; then
      tf_prior_step="$(printf '%s' "$tf_prior_ledger" | jq -r --arg id "$unit_id" \
        '[ (.orders // [])[] | select(.id == $id) ][0].lastStep // ""')"
      case "$tf_prior_step" in
        ""|null|tests-frozen) ;;
        *) die 76 "tests-freeze: $unit_id is at step $tf_prior_step, so it has already left tests-frozen. A second freeze rewinds the step and leaves the spent attempt counter and the stale build record where they are. Use restart when the design moved; otherwise this order goes forward, not back." ;;
      esac
    fi
  fi

  # --- turn every raw --flag value into JSON, through temporary files beside the implementation dir
  local tests_tmp reds_tmp checklists_tmp goa_tmp rows_meta_tmp
  tests_tmp="$IMPL_DIR/.tests-freeze-tests.$$"
  reds_tmp="$IMPL_DIR/.tests-freeze-reds.$$"
  checklists_tmp="$IMPL_DIR/.tests-freeze-checklists.$$"
  goa_tmp="$IMPL_DIR/.tests-freeze-goa.$$"
  rows_meta_tmp="$IMPL_DIR/.tests-freeze-rowmeta.$$"
  : >"$tests_tmp"; : >"$reds_tmp"; : >"$checklists_tmp"; : >"$goa_tmp"; : >"$rows_meta_tmp"
  tf_parse_tests      "$test_raw"      "$tests_tmp"
  tf_parse_reds       "$red_raw"       "$reds_tmp"
  tf_parse_checklists "$checklist_raw" "$checklists_tmp"
  tf_parse_goa        "$goa_raw"       "$goa_tmp"
  tf_parse_rows       "$row_raw"       "$rows_meta_tmp"

  local tests_json reds_json checklists_json goa_json test_globs_json rows_meta_json
  tests_json="$(jq -s '.' "$tests_tmp")"
  reds_json="$(jq -s '.' "$reds_tmp")"
  checklists_json="$(jq -s '.' "$checklists_tmp")"
  goa_json="$(jq -s '.' "$goa_tmp")"
  rows_meta_json="$(jq -s '.' "$rows_meta_tmp")"
  rm -f "$tests_tmp" "$reds_tmp" "$checklists_tmp" "$goa_tmp" "$rows_meta_tmp"
  test_globs_json="$(printf '%s' "$glob_raw" | jq -R -s 'split("\n") | map(select(length>0))')"

  # --- the task's own project, resolved the same way start and preconditions already resolve it --
  local project_folder codepath
  rv_load_codepath "tests-freeze"
  project_folder="$RV_PROJECT_FOLDER"
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

  # --- 28: a test name must carry, at its own end, the criterion id(s) it claims -------------------
  local test_rows_count ti name id_list bad_carry=""
  test_rows_count="$(printf '%s' "$tests_json" | jq 'length')"
  ti=0
  while [ "$ti" -lt "$test_rows_count" ]; do
    name="$(printf '%s' "$tests_json" | jq -r --argjson ti "$ti" '.[$ti].name')"
    id_list="$(printf '%s' "$tests_json" | jq -r --argjson ti "$ti" '.[$ti].criteria | join(",")')"
    tf_name_carries "$name" "$id_list" || bad_carry="$bad_carry$name (claims $id_list), "
    ti=$((ti + 1))
  done
  [ -z "$bad_carry" ] \
    || die 28 "tests-freeze: these test names do not carry, at the end, the criterion id they claim: ${bad_carry%, }"

  # --- 29: every machine-verified criterion the unit serves or owns needs a --test row -------------
  local missing_machine
  missing_machine="$(jq -nr --argjson criteria "$CRITERIA_JSON" --argjson tests "$tests_json" '
      ($tests | map(.criteria) | add // []) as $named
      | [ $criteria[] | select(.verifiedBy == "machine") | .id as $cid
          | select(($named | index($cid)) == null) | $cid ]
      | join(", ")
    ')"
  [ -z "$missing_machine" ] \
    || die 29 "tests-freeze: these machine-verified criteria have no --test row naming them: $missing_machine"

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
  # A ledger that is present and unreadable refuses here rather than further down. The mode decides
  # which judge a row may carry, so reading it as interactive because the file would not parse would
  # refuse an autonomous run with a sentence about a run it is not on. A ledger that is absent is a
  # different fact, left to the steps below, which refuse on it by name.
  local tf_ledger_file tf_ledger_doc tf_run_mode
  tf_ledger_file="$IMPL_DIR/ledger.json"
  tf_ledger_doc=""
  if [ -f "$tf_ledger_file" ]; then
    tf_ledger_doc="$(jq -c '.' "$tf_ledger_file" 2>/dev/null)"
    [ -n "$tf_ledger_doc" ] \
      || die 3 "tests-freeze: $tf_ledger_file exists but could not be read as JSON. This step reads the run's own mode from it, and every row below is judged against that mode. Repair or remove it by hand before running this again."
  fi
  tf_run_mode="interactive"
  [ -n "$tf_ledger_doc" ] && tf_run_mode="$(printf '%s' "$tf_ledger_doc" | jq -r '.runMode // "interactive"')"

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

  # --- 70: the judge of a row must match the run this task is on -----------------------------------
  local wrong_judge
  if [ "$tf_run_mode" = "autonomous" ]; then
    wrong_judge="$(printf '%s' "$rows_meta_json" | jq -r '
        [ .[] | select(.judgedBy == "person") | .criterion ] | join(", ")')"
    [ -z "$wrong_judge" ] \
      || die 70 "tests-freeze: these rows say a person judged them, and this run is autonomous: $wrong_judge. No person is here to read a row, and a row recorded as a person's is one nobody can list again later. Nothing is written."
  else
    wrong_judge="$(printf '%s' "$rows_meta_json" | jq -r '
        [ .[] | select(.judgedBy == "model") | .criterion ] | join(", ")')"
    [ -z "$wrong_judge" ] \
      || die 70 "tests-freeze: these rows say a model judged them, and this run is interactive: $wrong_judge. A person is here, and their reading is the stronger evidence, so the record must not say a checker stood in for them. Nothing is written."
  fi

  # --- 64: the --row set and this order's criteria must correspond, in all four ways ---------------
  # A machine-verified criterion this order serves or owns needs exactly one row: the checkpoint
  # asks, per order, whether these tests observe the part of the verify clause this order is
  # responsible for. A person-verified criterion never gets one, because it carries a checklist and
  # completion is what confirms it (ideal/implementation.md, "A criterion a person inspects has no
  # tests").
  local rows_missing rows_unknown rows_person rows_twice
  rows_missing="$(jq -nr --argjson criteria "$CRITERIA_JSON" --argjson rows "$rows_meta_json" '
      ($rows | map(.criterion)) as $named
      | [ $criteria[] | select(.verifiedBy == "machine") | .id as $cid
          | select(($named | index($cid)) == null) | $cid ]
      | join(", ")
    ')"
  [ -z "$rows_missing" ] \
    || die 64 "tests-freeze: these machine-verified criteria have no --row: $rows_missing. Every row of the trace matrix is judged before the tests are frozen."
  rows_unknown="$(jq -nr --argjson allowed "$CRITERIA_IDS_JSON" --argjson rows "$rows_meta_json" '
      [ $rows[] | .criterion as $cid | select(($allowed | index($cid)) == null) | $cid ]
      | unique | join(", ")
    ')"
  [ -z "$rows_unknown" ] \
    || die 64 "tests-freeze: a --row names criteria $unit_id does not serve or own: $rows_unknown"
  rows_person="$(jq -nr --argjson criteria "$CRITERIA_JSON" --argjson rows "$rows_meta_json" '
      ($criteria | map(select(.verifiedBy == "person") | .id)) as $people
      | [ $rows[] | .criterion as $cid | select(($people | index($cid)) != null) | $cid ]
      | unique | join(", ")
    ')"
  [ -z "$rows_person" ] \
    || die 64 "tests-freeze: a --row names $rows_person, which a person verifies. Such a criterion carries a checklist and never a judgement; completion confirms it."
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
        echo "TESTS-FREEZE: $unit_id is halted. $tf_why" >&2
      fi
    fi
    die 65 "tests-freeze: a --row answers rejected, so nothing is frozen: $rejected_rows. Send the row back to the test author, and run tests-freeze again once the test observes what the criterion asks."
  fi

  # --- 32: a --red file must exist, hold something, and name a test that has a --test row ----------
  local bad_red_names
  bad_red_names="$(jq -nr --argjson tests "$tests_json" --argjson reds "$reds_json" '
      ($tests | map(.name)) as $known
      | [ $reds[] | .name as $n | select(($known | index($n)) == null) | $n ] | unique | join(", ")
    ')"
  [ -z "$bad_red_names" ] \
    || die 32 "tests-freeze: these --red rows name a test with no --test row: $bad_red_names"

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

  # --- 33: every declared test needs a --red -------------------------------------------------------
  local missing_red
  missing_red="$(jq -nr --argjson tests "$tests_json" --argjson reds "$reds_json" '
      ($reds | map(.name)) as $named
      | [ $tests[] | .name as $n | select(($named | index($n)) == null) | $n ] | unique | join(", ")
    ')"
  [ -z "$missing_red" ] \
    || die 33 "tests-freeze: these tests have no --red at all: $missing_red"

  # --- 34: a green-on-arrival stops the step outright -----------------------------------------------
  if [ "$(printf '%s' "$goa_json" | jq 'length')" -gt 0 ]; then
    local goa_text
    goa_text="$(printf '%s' "$goa_json" | jq -r 'map(.name + ": " + .reason) | join("; ")')"
    die 34 "tests-freeze: reported green on arrival, which proves nothing: $goa_text. Fix the test or the code until it fails for the right reason, then run tests-freeze again."
  fi

  # --- 35: a record already exists for this unit at a different commit -----------------------------
  local record_file existing_doc existing_commit
  record_file="$IMPL_DIR/tests-$unit_id.json"
  if [ -f "$record_file" ]; then
    existing_doc="$(jq -c '.' "$record_file" 2>/dev/null)"
    [ -n "$existing_doc" ] \
      || die 3 "tests-freeze: $record_file exists but could not be read as JSON. Repair or remove it by hand before running this again."
    existing_commit="$(printf '%s' "$existing_doc" | jq -r '.commit // empty')"
    [ -n "$existing_commit" ] \
      || die 3 "tests-freeze: $record_file exists but has no usable commit field."
    [ "$existing_commit" = "$current_commit" ] \
      || die 35 "tests-freeze: $record_file was already frozen at commit $existing_commit, and this run is at a different commit, $current_commit. A record is taken once per commit; investigate before proceeding."
  fi

  # --- every check passed: build the rows, one per criterion the unit serves or owns ---------------
  local need_sha
  need_sha="$(printf '%s' "$CRITERIA_JSON" | jq -r 'map(select(.verifiedBy == "machine")) | length > 0')"
  if [ "$need_sha" = "true" ]; then
    records_hash__resolve_sha256_cmd \
      || die 3 "tests-freeze: neither sha256sum nor 'shasum -a 256' was found on PATH"
  fi

  # Every name the loop below uses is declared here, never inside it. zsh prints a parameter when
  # `local` names one that already exists in the same scope, so a `local` inside a loop body puts
  # the previous round's value on standard output from the second round on, which corrupts this
  # action's own output for any order serving two criteria (trap 5 in this file's own header).
  local rows_tmp crit_count ci cid ckind
  local names_json ntests tj tpath trelpath tname tsha tredpath tredtext tests_out_tmp tests_out_json
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
        # The record stores the path relative to codePath, never the absolute form: a frozen path
        # must still mean the same file once the checkout moves (see exit 36's own reasoning).
        jq -n --arg path "$trelpath" --arg name "$tname" --arg sha "$tsha" --arg red "$tredtext" \
          '{path: $path, name: $name, sha256: $sha, red: $red}' >>"$tests_out_tmp" \
          || die 3 "tests-freeze: could not record the test row for $tname"
        tj=$((tj + 1))
      done
      tests_out_json="$(jq -s '.' "$tests_out_tmp")"
      rm -f "$tests_out_tmp"
      jq -n --arg cid "$cid" --argjson tests "$tests_out_json" \
        '{criterion: $cid, kind: "machine", tests: $tests}' >>"$rows_tmp" \
        || die 3 "tests-freeze: could not record the row for $cid"
    else
      checklist_text="$(printf '%s' "$checklists_json" | jq -r --arg id "$cid" \
        '[ .[] | select(.id == $id) ][0].text // empty')"
      jq -n --arg cid "$cid" --arg text "$checklist_text" \
        '{criterion: $cid, kind: "person", checklist: $text}' >>"$rows_tmp" \
        || die 3 "tests-freeze: could not record the row for $cid"
    fi
    ci=$((ci + 1))
  done
  local rows_json
  rows_json="$(jq -s '.' "$rows_tmp")"
  rm -f "$rows_tmp"

  # --- the checkpoint's verdict goes into the ledger, one judgement per order per criterion --------
  # Written before the record below, and on both paths through it, because a second freeze at the
  # same commit with the same tests writes no record and must still carry the judgement a person or
  # a checker just made. A judgement this order already left is replaced rather than added to: one
  # order judges one criterion once, and two entries under one unit would count that row twice.
  local judgement_count ledger_file_now ledger_doc_now ledger_with_judgements
  judgement_count="$(printf '%s' "$rows_meta_json" | jq 'length')"
  if [ "$judgement_count" -gt 0 ]; then
    ledger_file_now="$IMPL_DIR/ledger.json"
    [ -f "$ledger_file_now" ] \
      || die 3 "tests-freeze: $ledger_file_now is missing, though start writes it. Run start again."
    ledger_doc_now="$(jq -c '.' "$ledger_file_now" 2>/dev/null)"
    [ -n "$ledger_doc_now" ] \
      || die 3 "tests-freeze: $ledger_file_now exists but could not be read as JSON. Repair or remove it by hand before running this again."
    ledger_with_judgements="$(printf '%s' "$ledger_doc_now" | jq -c \
      --arg unit "$unit_id" --argjson rows "$rows_meta_json" '
      .criteria = ((.criteria // []) | map(
        . as $c
        | ([ $rows[] | select(.criterion == $c.id) ][0]) as $r
        | if $r == null then $c
          else ($c + {judgements: (
                  (($c.judgements // []) | map(select(.unit != $unit)))
                  + [{unit: $unit, verdict: $r.verdict, judgedBy: $r.judgedBy, note: $r.note}])})
          end))')"
    [ -n "$ledger_with_judgements" ] \
      || die 3 "tests-freeze: the ledger update for $unit_id's judgements failed."
    write_atomic "$ledger_file_now" "$ledger_with_judgements"
  fi

  local today record_json
  today="$(date -u +%Y-%m-%d)"
  record_json="$(jq -n --arg takenAt "$today" --arg unit "$unit_id" --arg commit "$current_commit" \
    --argjson testGlobs "$test_globs_json" --argjson rows "$rows_json" \
    '{schemaVersion: 1, takenAt: $takenAt, unit: $unit, commit: $commit, testGlobs: $testGlobs, rows: $rows}')"

  if [ -f "$record_file" ]; then
    local existing_no_date new_no_date
    existing_no_date="$(jq -cS 'del(.takenAt)' "$record_file" 2>/dev/null)"
    new_no_date="$(printf '%s' "$record_json" | jq -cS 'del(.takenAt)')"
    if [ "$existing_no_date" = "$new_no_date" ]; then
      echo "TESTS-FREEZE: unchanged (already frozen at commit $current_commit with the same tests)"
      printf '%s\n' "$record_file"
      exit 0
    fi
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

  # --- exit 39: step three (tests-brief, tests-freeze) must already have run for this unit ---------
  local tests_file="$IMPL_DIR/tests-$unit_id.json"
  [ -f "$tests_file" ] \
    || die 39 "build-brief: $tests_file not found. Step three has not run for $unit_id yet; run tests-brief and tests-freeze on it first."
  local tests_doc
  tests_doc="$(jq -c '.' "$tests_file" 2>/dev/null)"
  [ -n "$tests_doc" ] \
    || die 3 "build-brief: $tests_file exists but could not be read as JSON. Repair or remove it by hand before running this again."

  # --- the ledger: needed for the dependency check and the attempt count ---------------------------
  local ledger_file="$IMPL_DIR/ledger.json"
  [ -f "$ledger_file" ] \
    || die 3 "build-brief: $ledger_file not found, though $IMPL_DIR/snapshot.json exists. A snapshot with no ledger beside it is not a supported state; run start again."
  local ledger_doc
  ledger_doc="$(jq -c '.' "$ledger_file" 2>/dev/null)"
  [ -n "$ledger_doc" ] \
    || die 3 "build-brief: $ledger_file exists but could not be read as JSON. Repair or remove it by hand before running this again."

  # --- exit 40: every dependency needs a completion record before its interface is handed over ------
  # dep_interface is declared here, never inside the loop, for the reason tests-brief states above
  # and this file's own header records as trap 5.
  local depends_json dep_count i dep_id dep_entry dep_step dep_interface dependency_interfaces_json='[]'
  local dep_record_file dep_record_text
  depends_json="$(printf '%s' "$BB_UNIT_JSON" | jq -c '.dependsOn // []')"
  dep_count="$(printf '%s' "$depends_json" | jq 'length')"
  i=0
  while [ "$i" -lt "$dep_count" ]; do
    dep_id="$(printf '%s' "$depends_json" | jq -r --argjson i "$i" '.[$i]')"
    dep_entry="$(printf '%s' "$ledger_doc" | jq -c --arg id "$dep_id" \
      '(.orders // []) | map(select(.id == $id)) | .[0] // null')"
    [ "$dep_entry" != "null" ] \
      || die 3 "build-brief: $unit_id depends on $dep_id, which has no entry in $ledger_file, though start opens one entry per snapshot work order."
    dep_step="$(printf '%s' "$dep_entry" | jq -r '.lastStep // "not started"')"
    if [ "$dep_step" = "closed" ]; then
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
    else
      die 40 "build-brief: $unit_id depends on $dep_id, which has no completion record ($ledger_file records its last step as $dep_step), so its interface record does not exist yet."
    fi
    i=$((i + 1))
  done

  # --- exit 41: the attempt counter for this unit must still have room -----------------------------
  local order_entry attempts_used
  order_entry="$(printf '%s' "$ledger_doc" | jq -c --arg id "$unit_id" \
    '(.orders // []) | map(select(.id == $id)) | .[0] // null')"
  [ "$order_entry" != "null" ] \
    || die 3 "build-brief: $unit_id has no entry in $ledger_file, though start opens one entry per snapshot work order."
  attempts_used="$(printf '%s' "$order_entry" | jq -r '.attemptsUsed // 0')"
  case "$attempts_used" in ''|*[!0-9]*) attempts_used=0 ;; esac
  local attempts_allowed
  attempts_allowed="$(attempts_allowed_for "$order_entry")"
  [ "$attempts_used" -lt "$attempts_allowed" ] \
    || die 41 "build-brief: $unit_id has already used $attempts_used of $attempts_allowed allowed attempts. Nothing more is handed over."

  # --- assemble the brief: exactly these five keys, and nothing else -------------------------------
  local unit_out tests_out
  unit_out="$(printf '%s' "$BB_UNIT_JSON" | jq -c \
    '{id, title, ownedFiles: (.ownedFiles // []), interface: (.interface // ""),
      doneWhen: (.doneWhen // []), diffBudget: (.diffBudget // ""), reasoning: (.reasoning // "")}')"
  # One entry per (row, test): a test naming several criteria appears once in each criterion's own
  # row in the frozen record, and this keeps that same shape rather than collapsing it.
  tests_out="$(printf '%s' "$tests_doc" | jq -c \
    '[ (.rows // [])[] | select(.kind == "machine") | .criterion as $c | (.tests // [])[]
       | {path, name, criterion: $c} ]')"

  # The caller needs the commit this attempt begins from, for --started-at when it records. It was
  # told to run `git rev-parse HEAD` itself, which needs a grant the skill does not carry.
  local bb_project bb_codepath bb_head
  bb_head=""
  bb_project="$(resolve_project_folder "$TASK_PATH" 2>/dev/null)" || bb_project=""
  if [ -n "$bb_project" ]; then
    bb_codepath="$(project_code_path_value "$bb_project")"
    if [ -n "$bb_codepath" ] && [ -d "$bb_codepath" ]; then
      bb_head="$(git -C "$bb_codepath" rev-parse HEAD 2>/dev/null)"
    fi
  fi
  # The report has one named path per attempt, so a later attempt never writes over the answers a
  # reviewer already compared a diff against. The brief is one file per order, rewritten on each
  # attempt: only its counters and its report path change between two attempts.
  local brief_file brief_json
  brief_file="$IMPL_DIR/brief-$unit_id-build.json"
  brief_json="$(jq -n --argjson unit "$unit_out" --argjson tests "$tests_out" --arg headNow "$bb_head" \
        --argjson dependencyInterfaces "$dependency_interfaces_json" \
        --arg reportPath "$IMPL_DIR/report-$unit_id-attempt$((attempts_used + 1)).md" \
        --argjson attemptsUsed "$attempts_used" --argjson attemptsAllowed "$attempts_allowed" \
    '{unit: $unit, tests: $tests, headNow: $headNow, dependencyInterfaces: $dependencyInterfaces,
      reportPath: $reportPath,
      attemptsUsed: $attemptsUsed, attemptsAllowed: $attemptsAllowed}')"
  [ -n "$brief_json" ] || die 3 "build-brief: could not assemble the brief for $unit_id."
  write_atomic "$brief_file" "$brief_json"
  # headNow is printed because the caller passes it back as --started-at, and the report path
  # because the dispatch names it. Everything else the implementer reads from the file.
  im_print_summary "build-brief" "$(printf '%s' "$brief_json" | jq -c --arg brief "$brief_file" '
    {order: .unit.id,
     brief: $brief,
     reportPath: .reportPath,
     headNow: (if .headNow == "" then "none: the code repository commit could not be read" else .headNow end),
     attempts: "\(.attemptsUsed) of \(.attemptsAllowed) used",
     ownedFiles: (.unit.ownedFiles | length),
     frozenTests: (.tests | length),
     dependencyInterfaces: ([ .dependencyInterfaces[] | .id + (if has("interfaceRecord") then " (record)" else " (declared only)" end) ]),
     next: "dispatch implementer with the brief path and the implement recipe path, then build-record"}')"
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
#   BRC_UNIT_JSON       the frozen work order
#   BRC_TESTS_DOC       the frozen test record for this order
#   BRC_BASELINE_FILE   where step two wrote the baseline
#   BRC_RECIPES         the resolved recipe document cr_resolve wrote (CR_DOC): one entry per
#                       framework with its suite and selected-tests commands, and one entry per
#                       tool row with its argv, its signal and its extensions. Every command this
#                       function runs comes from here, never from a flag a caller typed
#   BRC_SELECTED_JSON   the paths a `{paths}` or `{file}` token in the selected-tests row expands
#                       to: this order's own frozen test files, relative to codePath
#   BRC_VALUES          the tab-separated `--value` list every other placeholder is read from
#   BRC_NOTHING_RAN, BRC_HAVE_NOTHING_RAN   the caller's own marker for a green run that selected
#                       nothing, used only where the framework's recipe declares none of its own
# ------------------------------------------------------------------------------------------------
BRC_WHO=""; BRC_CODEPATH=""; BRC_STARTED_AT=""; BRC_CURRENT=""
BRC_UNIT_JSON=""; BRC_TESTS_DOC=""; BRC_BASELINE_FILE=""
BRC_RECIPES='{"frameworks":[],"tools":[]}'; BRC_SELECTED_JSON="[]"; BRC_VALUES=""
BRC_NOTHING_RAN=""; BRC_HAVE_NOTHING_RAN=false

# One tool check: coding standards, static analysis, or the security tool. $1 the check id, $2 the
# baseline field holding the same tool's own verdict, $3 a word for the message. The command itself
# comes from the resolved recipe in BRC_RECIPES, never from a flag: a caller retyping a recipe row
# drops a key, and a dropped `signal` key turns a tool that cannot fail by exit status into a check
# that always passes. Prints the check object.
#
# Exit 0 is met. Any other exit is compared against the baseline for that tool, the same rule
# suite-regression already applies: a baseline that was met makes this unmet, because this order
# introduced the finding; a baseline that was unmet, unknown or undeclared makes this unknown,
# naming which, because nothing here can tell an old finding from an old one plus a new one.
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
  local verdict detail exit_json output expanded outfile errfile rc has_paths
  local owned_json owned_count scoped_json scoped_count stdout_len failed how
  local baseline_doc baseline_verdict result kind payload
  verdict=""; detail=""; exit_json="null"; output=""

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
  printf '%s' "$argv_json" | jq -e 'any(.[]; . == "{paths}" or . == "{file}")' >/dev/null 2>&1 && has_paths=true
  owned_json="$(printf '%s' "$BRC_UNIT_JSON" | jq -c '.ownedFiles // []')"
  owned_count="$(printf '%s' "$owned_json" | jq 'length')"
  scoped_json="$owned_json"
  if [ -n "$exts_json" ]; then
    scoped_json="$(br_filter_extensions "$owned_json" "$exts_json")"
  fi
  scoped_count="$(printf '%s' "$scoped_json" | jq 'length')"

  if [ "$has_paths" = "true" ] && [ "$owned_count" -eq 0 ]; then
    # A tool handed no path at all reads that as its own default scope, so it would answer about
    # the whole repository under this order's name. That is a wrong verdict, not a missing one.
    verdict="unknown"
    detail="the $label command holds a path placeholder, and this order declares no ownedFiles, so the command would run over no path at all."
  elif [ "$has_paths" = "true" ] && [ -n "$exts_json" ] && [ "$scoped_count" -eq 0 ]; then
    # The order owns files, and none of them is a file this tool reads. The row did not apply here.
    verdict="undeclared"
    detail="the $label command reads only $(printf '%s' "$exts_json" | jq -r 'join(", ")'), and this order owns no file with one of those extensions, so the row does not apply to it."
  else
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
        output="$(cat "$outfile" "$errfile" 2>/dev/null)"
      else
        output="$(cat "$outfile" 2>/dev/null)"
      fi
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
          baseline_verdict=""
          if [ -f "$BRC_BASELINE_FILE" ]; then
            baseline_doc="$(jq -c '.' "$BRC_BASELINE_FILE" 2>/dev/null)"
            if [ -n "$baseline_doc" ]; then
              baseline_verdict="$(printf '%s' "$baseline_doc" | jq -r --arg f "$field" '.[$f].verdict // ""')"
            fi
          fi
          case "$baseline_verdict" in
            met)
              verdict="unmet"
              detail="the $label command $how, and the baseline recorded this tool met at the commit the build started from; this order introduced the finding."
              ;;
            unmet|unknown|undeclared)
              verdict="unknown"
              detail="the $label command $how, and the baseline recorded this tool $baseline_verdict at the commit the build started from, so this cannot tell an old finding from an old one plus a new one."
              ;;
            *)
              verdict="unknown"
              detail="the $label command $how, and $BRC_BASELINE_FILE could not be read for this tool's own baseline verdict, so this cannot tell an old finding from a new one."
              ;;
          esac
        fi
      fi
    fi
    rm -f "$outfile"
    [ -z "$errfile" ] || rm -f "$errfile"
  fi
  jq -n --arg id "$check_id" --arg verdict "$verdict" --arg detail "$detail" \
        --argjson exitCode "$exit_json" --arg output "$output" \
        --arg signal "$signal" --arg exts "${exts_json:-}" \
        --arg framework "$(printf '%s' "$row" | jq -r '.framework // ""')" '
    {id: $id, verdict: $verdict, detail: $detail}
    + (if $framework == "" then {} else {framework: $framework} end)
    + (if $exitCode == null then {} else {exitCode: $exitCode, output: $output} end)
    + (if $signal == "" then {} else {signal: $signal} end)
    + (if $exts   == "" then {} else {extensions: ($exts | fromjson)} end)
  '
}

# One commanded test check: order-tests or suite-regression. $1 the check id, $2 the field of each
# framework entry holding the command (`orderTests` or `suite`), $3 a word for the message. The
# command comes from the recipe, and it runs once per framework the task resolved one for, because
# the build runs in one repository that is all of them at once. Prints the check object.
#
# suite-regression compares a failure against the baseline suite; order-tests does not, because a
# test this order owns did not exist when the baseline was taken.
br_test_check() {
  local check_id="$1" field="$2" label="$3"
  local fw_count fwi fw_obj fw cmd argv_json paths_json result kind payload
  local runs='[]' verdicts='[]' verdict detail outfile rc marker_json markers_len mi marker
  local nothing_ran_hit run_detail baseline_doc baseline_unmet_frameworks

  fw_count="$(printf '%s' "$BRC_RECIPES" | jq '(.frameworks // []) | length')"
  case "$fw_count" in ''|*[!0-9]*) fw_count=0 ;; esac
  paths_json='[]'
  [ "$field" = "orderTests" ] && paths_json="$BRC_SELECTED_JSON"

  fwi=0
  while [ "$fwi" -lt "$fw_count" ]; do
    fw_obj="$(printf '%s' "$BRC_RECIPES" | jq -c --argjson i "$fwi" '.frameworks[$i]')"
    fw="$(printf '%s' "$fw_obj" | jq -r '.framework')"
    cmd="$(printf '%s' "$fw_obj" | jq -c --arg f "$field" '.[$f] // {}')"
    verdict=""; detail=""; rc=""
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
    else
      argv_json="$(printf '%s' "$cmd" | jq -c '.argv')"
      outfile="$(mktemp)" || die 3 "$BRC_WHO: could not create a temporary file"
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
        run_detail="$(cat "$outfile" 2>/dev/null)"
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
          # The baseline records one verdict per framework, taken whole, not which test failed
          # (baseline-schema.json, suite[].verdict); that is the finest grain step two's own record
          # holds. A suite failing now, with the baseline already unmet, is not the same fact as a
          # suite that is clean: this cannot tell an old failure from an old failure plus a new one
          # this order introduced, so it says so rather than reading a red baseline as a pass.
          baseline_doc=""
          if [ -f "$BRC_BASELINE_FILE" ]; then
            baseline_doc="$(jq -c '.' "$BRC_BASELINE_FILE" 2>/dev/null)"
          fi
          if [ -n "$baseline_doc" ]; then
            baseline_unmet_frameworks="$(printf '%s' "$baseline_doc" | jq -r \
              '[ (.suite // [])[] | select(.verdict == "unmet") | .framework ] | join(", ")')"
            if [ -n "$baseline_unmet_frameworks" ]; then
              verdict="unknown"
              detail="the suite exited $rc on $fw, and the baseline recorded $baseline_unmet_frameworks unmet at the commit the build started from. The baseline records one verdict per framework rather than which tests failed, so this cannot tell an old failure from an old failure plus a new one."
            else
              verdict="unmet"
              detail="the suite exited $rc on $fw, and the baseline recorded every framework met at the commit the build started from; this order introduced the failure."
            fi
          else
            verdict="unknown"
            detail="the suite exited $rc on $fw, and $BRC_BASELINE_FILE could not be read to tell whether this failure predates this order."
          fi
        fi
        runs="$(jq -nc --argjson runs "$runs" --arg fw "$fw" --arg v "$verdict" \
          --arg d "$detail" --argjson rc "$rc" --arg out "$run_detail" \
          '$runs + [{framework: $fw, verdict: $v, detail: $d, exitCode: $rc, output: $out}]')"
      fi
      rm -f "$outfile"
    fi
    if [ -z "$rc" ]; then
      runs="$(jq -nc --argjson runs "$runs" --arg fw "$fw" --arg v "$verdict" --arg d "$detail" \
        '$runs + [{framework: $fw, verdict: $v, detail: $d}]')"
    fi
    verdicts="$(jq -nc --argjson v "$verdicts" --arg x "$verdict" '$v + [$x]')"
    fwi=$((fwi + 1))
  done

  if [ "$fw_count" -eq 0 ]; then
    jq -n --arg id "$check_id" --arg detail "no framework recipe was resolved for this task, so $label was not checked." \
      '{id: $id, verdict: "undeclared", detail: $detail}'
    return 0
  fi

  verdict="$(br_worst_verdict "$verdicts")"
  jq -n --arg id "$check_id" --arg verdict "$verdict" --argjson runs "$runs" '
    {id: $id, verdict: $verdict,
     detail: ([ $runs[] | (.framework + ": " + .detail) ] | join(" ")),
     runs: [ $runs[] | {framework, verdict} ]}
    + (if ([ $runs[] | select(has("exitCode")) ] | length) == 0 then {}
       else {exitCode: ([ $runs[] | select(has("exitCode")) | (.exitCode | tonumber) ] | max),
             output:   ([ $runs[] | select(has("output")) | .output ] | join("\n"))} end)
  '
}

# The seven, in the fixed order this stage records them: order-tests, suite-regression,
# coding-standards, static-analysis, security, owned-files, frozen-tests. Prints the JSON array.
br_seven_checks() {
  local parts_file
  parts_file="$(mktemp)" || die 3 "$BRC_WHO: could not create a temporary file"

  br_test_check "order-tests"      "orderTests" "order-tests" >>"$parts_file"
  br_test_check "suite-regression" "suite"      "suite"       >>"$parts_file"
  br_tool_check "coding-standards" "codingStandards" "coding-standards" >>"$parts_file"
  br_tool_check "static-analysis"  "staticAnalysis"  "static-analysis"  >>"$parts_file"
  br_tool_check "security"         "security"        "security"         >>"$parts_file"

  # --- the realized diff touches only the files this order owns ------------------------------------
  local ofc_verdict ofc_detail
  local diff_output owned_files_json owned_count unmatched="" p matched gi g
  # --no-renames: git reads a delete plus an add as one rename by default, and a rename shows only
  # the new path, so a deleted file this order does not own would never appear here.
  diff_output="$(git -C "$BRC_CODEPATH" diff --no-renames --name-only "$BRC_STARTED_AT" "$BRC_CURRENT" 2>/dev/null)"
  owned_files_json="$(printf '%s' "$BRC_UNIT_JSON" | jq -c '.ownedFiles // []')"
  owned_count="$(printf '%s' "$owned_files_json" | jq 'length')"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    matched=false
    gi=0
    while [ "$gi" -lt "$owned_count" ]; do
      g="$(printf '%s' "$owned_files_json" | jq -r --argjson gi "$gi" '.[$gi]')"
      tf_path_matches_catalog_glob "$p" "$g" && matched=true
      [ "$matched" = "true" ] && break
      gi=$((gi + 1))
    done
    [ "$matched" = "true" ] || unmatched="$unmatched$p, "
  done <<BR_DIFF
$diff_output
BR_DIFF
  if [ -n "$unmatched" ]; then
    ofc_verdict="unmet"
    ofc_detail="these changed files match none of $(printf '%s' "$BRC_UNIT_JSON" | jq -r '.id')'s own ownedFiles: ${unmatched%, }"
  else
    ofc_verdict="met"
    ofc_detail="every file changed between $BRC_STARTED_AT and $BRC_CURRENT matches this order's own ownedFiles."
  fi
  jq -n --arg verdict "$ofc_verdict" --arg detail "$ofc_detail" \
    '{id: "owned-files", verdict: $verdict, detail: $detail}' >>"$parts_file"

  # --- every frozen test file is unchanged ---------------------------------------------------------
  records_hash__resolve_sha256_cmd \
    || die 3 "$BRC_WHO: neither sha256sum nor 'shasum -a 256' was found on PATH"
  local ftc_verdict ftc_detail
  local frozen_paths frozen_count fidx frozen_file fsha current_sha changed_tests=""
  frozen_paths="$(printf '%s' "$BRC_TESTS_DOC" | jq -c \
    '[ (.rows // [])[] | select(.kind == "machine") | (.tests // [])[] | {path, sha256} ] | unique_by(.path)')"
  frozen_count="$(printf '%s' "$frozen_paths" | jq 'length')"
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
    ftc_detail="these frozen test files no longer match the hash tests-freeze recorded: ${changed_tests%, }"
  else
    ftc_verdict="met"
    ftc_detail="every frozen test file for $(printf '%s' "$BRC_UNIT_JSON" | jq -r '.id') is unchanged."
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
# closes, and it is recorded and printed for the same reason.
br_executed_count() {
  printf '%s' "$1" | jq -r '
    [ .[] | select(has("exitCode") or .id == "owned-files" or .id == "frozen-tests") ] | length'
}

# Whether the checks in $1 let the order pass. $2 is the id whose unknown does not stop the attempt
# (interface-record at build-record, nothing at fix-record). Prints true or false.
#
# Two rules, and the second is the floor. Every check must answer met or undeclared, with the one
# exempt unknown allowed. And order-tests must have answered met: that check is the only one that
# says this order's own code does what its tests ask, so undeclared or unknown there is an order
# nothing executed. Undeclared on every other check still continues, which is the rule step two
# already applies to a precondition a recipe declared nothing for.
br_checks_pass() {
  printf '%s' "$1" | jq -r --arg exempt "$2" '
    (all(.[]; .verdict == "met" or .verdict == "undeclared"
              or (.verdict == "unknown" and $exempt != "" and .id == $exempt)))
    and (any(.[]; .id == "order-tests" and .verdict == "met"))'
}

# The first check that stopped the order in $1, in the recorded order, with $2 the exempt id as
# above. Prints "<id>: <verdict>, <detail>", or "none: " when nothing stopped it.
br_first_stopper() {
  printf '%s' "$1" | jq -r --arg exempt "$2" '
    [ .[] | select(.verdict == "unmet"
                   or (.verdict == "unknown" and ($exempt == "" or .id != $exempt))
                   or (.id == "order-tests" and .verdict != "met")) ]
    | .[0] // {id:"none",verdict:"",detail:""}
    | "\(.id): \(.verdict)" + (if .detail == "" then "" else ", " + .detail end)'
}

# Check eight, the interface record, and the countable half of it only. $1 the interface this order
# declares in the frozen snapshot, $2 the text the builder wrote. Prints the check object.
#
# Every backtick-quoted token in the declaration must appear verbatim in the record. Any missing
# token is unmet, naming them. All present is met. A declaration naming no element in backticks has
# nothing countable in it, so this answers unknown and the reviewer reads both texts instead. That
# unknown is the one unknown in this stage that does not spend an attempt (ideal/implementation.md).
# `build-record` runs this check; `fix-record` never does.
br_interface_check() {
  local declared="$1" record="$2"
  local tokens_json token_count missing_json missing_count verdict detail
  tokens_json="$(jq -n --arg s "$declared" '
    [ $s | scan("`[^`]*`") | ltrimstr("`") | rtrimstr("`") | select(length > 0) ]
    | reduce .[] as $x ([]; if index($x) then . else . + [$x] end)
  ' 2>/dev/null)"
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
    missing_count="$(printf '%s' "$missing_json" | jq 'length')"
    if [ "$missing_count" -eq 0 ]; then
      verdict="met"
      detail="every element the declaration names in backticks ($token_count of them) appears verbatim in the interface record."
    else
      verdict="unmet"
      detail="these elements the declaration names in backticks do not appear in the interface record: $(printf '%s' "$missing_json" | jq -r 'join(", ")')"
    fi
  fi
  jq -n --arg verdict "$verdict" --arg detail "$detail" \
    '{id: "interface-record", verdict: $verdict, detail: $detail}'
}

do_build_record() {
  local task_arg="" unit_id="" interface_path="" report_path="" started_at=""
  local nothing_ran="" have_nothing_ran=false
  local test_recipes="" check_recipes="" values=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --interface)
        [ "$#" -ge 2 ] || die 3 "build-record: --interface needs a path to the record the builder wrote"
        [ -n "$2" ] || die 3 "build-record: --interface was given an empty path."
        interface_path="$2"; shift 2 ;;
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
  [ -n "$interface_path" ]  || die 3 "build-record: --interface is required"
  [ -n "$report_path" ]     || die 3 "build-record: --report is required"
  [ -s "$report_path" ]     || die 3 "build-record: --report names no file, or an empty one: $report_path"
  [ -n "$started_at" ]      || die 3 "build-record: --started-at is required"

  local resolve_rc
  TASK_PATH="$(resolve_task_folder "$task_arg" "build-record")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  IMPL_DIR="$TASK_PATH/implementation"

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

  # --- the task's own project, through the one reader every step-five action already uses ---------
  local codepath
  rv_load_codepath "build-record"
  codepath="$RV_CODEPATH"

  # --- exit 43: --started-at must be a real commit in this repository ------------------------------
  local started_at_full current_commit
  started_at_full="$(git -C "$codepath" rev-parse --verify --quiet "${started_at}^{commit}" 2>/dev/null)"
  [ -n "$started_at_full" ] \
    || die 43 "build-record: --started-at ($started_at) is not a commit in the code repository at $codepath."
  current_commit="$(git -C "$codepath" rev-parse HEAD 2>/dev/null)"
  [ -n "$current_commit" ] \
    || die 3 "build-record: could not capture the current commit (git rev-parse HEAD failed in $codepath)."
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
  local unit_interface_declared interface_text=""
  unit_interface_declared="$(printf '%s' "$UNIT_JSON" | jq -r '.interface // ""')"
  if [ -n "$unit_interface_declared" ]; then
    [ -s "$interface_path" ] \
      || die 44 "build-record: $unit_id declares a non-empty interface, and the interface record at $interface_path is missing or empty."
  fi
  [ -f "$interface_path" ] && interface_text="$(cat "$interface_path" 2>/dev/null)"

  local ledger_run_mode
  ledger_run_mode="$(printf '%s' "$ledger_doc" | jq -r '.runMode // "interactive"')"
  br_require_clean_tree "build-record" "$codepath" "$unit_id" "$ledger_run_mode" "$ledger_file" "$ledger_doc"

  # --- the eight deciding checks ---------------------------------------------------------------------
  # Seven of them are computable by the same function a fix round calls, so the two steps can never
  # drift into checking different things. The eighth, the interface record, is this step's own: a fix
  # round does not rewrite that record, so it is never re-run there.
  BRC_WHO="build-record"
  BRC_CODEPATH="$codepath"
  BRC_STARTED_AT="$started_at_full"
  BRC_CURRENT="$current_commit"
  BRC_UNIT_JSON="$UNIT_JSON"
  BRC_TESTS_DOC="$tests_doc"
  BRC_BASELINE_FILE="$IMPL_DIR/baseline.json"
  # Every commanded check runs a command the recipe declares, resolved here rather than retyped by
  # the caller. The selected-tests row runs this order's own frozen test files.
  local selected_tests_json
  selected_tests_json="$(printf '%s' "$tests_doc" | jq -c \
    '[ (.rows // [])[] | select(.kind == "machine") | (.tests // [])[] | .path ] | unique')"
  CR_WHO="build-record"
  CR_TEST_RECIPES="$test_recipes"
  CR_CHECK_RECIPES="$check_recipes"
  cr_resolve
  cr_require_baseline_recipes "build-record" "$IMPL_DIR/baseline.json"

  BRC_RECIPES="$CR_DOC"
  BRC_SELECTED_JSON="$selected_tests_json"
  BRC_VALUES="$values"
  BRC_NOTHING_RAN="$nothing_ran"
  BRC_HAVE_NOTHING_RAN="$have_nothing_ran"

  local seven_file seven_json interface_check_json checks_json
  seven_file="$(mktemp)" || die 3 "build-record: could not create a temporary file"
  br_seven_checks >"$seven_file"
  seven_json="$(cat "$seven_file" 2>/dev/null)"
  rm -f "$seven_file"
  [ -n "$seven_json" ] || die 3 "build-record: the seven computable checks produced nothing for $unit_id."

  interface_check_json="$(br_interface_check "$unit_interface_declared" "$interface_text")"
  [ -n "$interface_check_json" ] \
    || die 3 "build-record: the interface-record check produced nothing for $unit_id."

  checks_json="$(jq -n --argjson seven "$seven_json" --argjson eighth "$interface_check_json" \
    '$seven + [$eighth]')"

  local today record_json executed_count
  executed_count="$(br_executed_count "$checks_json")"
  case "$executed_count" in ''|*[!0-9]*) executed_count=0 ;; esac
  today="$(date -u +%Y-%m-%d)"
  record_json="$(jq -n \
    --arg takenAt "$today" --arg unit "$unit_id" --arg startedAt "$started_at_full" \
    --arg commit "$current_commit" --argjson attempt "$attempt_number" \
    --arg interfaceRecord "$interface_text" --arg reportPath "$report_path" \
    --argjson checks "$checks_json" --argjson executed "$executed_count" \
    '{
      schemaVersion: 1,
      takenAt: $takenAt,
      unit: $unit,
      startedAt: $startedAt,
      commit: $commit,
      attempt: $attempt,
      interfaceRecord: $interfaceRecord,
      reportPath: $reportPath,
      checks: $checks,
      executed: $executed,
      decidingChecks: { total: 8, ranHere: [ $checks[] | .id ] }
    }')"

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
    --arg halt "${halt_why:-none}" --arg record "$record_file" --arg next "$br_next" '
    {order: .unit,
     attempt: $attempts,
     range: "\(.startedAt)..\(.commit)",
     check: ([ .checks[] | {id, verdict, detail: (.detail // "")} ]),
     executed: "\(.executed) of 8 ran a command, a diff or a hash",
     state: $state,
     halt: $halt,
     record: $record,
     next: $next}')"
  if [ "$all_met" != "true" ] && [ "$attempt_number" -ge "$attempts_allowed" ]; then
    echo "BUILD-RECORD: $unit_id is halted. Attempts spent: $attempt_number of $attempts_allowed. The last was stopped by $first_stopper" >&2
  fi
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

  RV_RUN_MODE="$(printf '%s' "$RV_LEDGER_DOC" | jq -r '.runMode // "interactive"')"
  [ -n "$RV_RUN_MODE" ] || RV_RUN_MODE="interactive"

  # Exit 49: a halted order refuses every step after the halt. The reason is the halt's own words,
  # so a reader never has to open the ledger to learn why the step stopped.
  local halted
  halted="$(printf '%s' "$RV_ORDER_ENTRY" | jq -r '.haltedBecause // ""')"
  [ -z "$halted" ] \
    || die 49 "$who: $unit_id is halted, so this step refuses. The ledger records the reason: $halted"
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
# either "review" or "round<N>".
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

  # The diff moves as a file the reviewer opens, never pasted through the orchestrator
  # (ideal/implementation.md, "What a review is given, and what it is refused").
  local started_at commit diff_path
  started_at="$(printf '%s' "$RV_BUILD_DOC" | jq -r '.startedAt // ""')"
  commit="$(printf '%s' "$RV_BUILD_DOC" | jq -r '.commit // ""')"
  [ -n "$started_at" ] && [ -n "$commit" ] \
    || die 3 "review-brief: $IMPL_DIR/build-$unit_id.json holds no startedAt or no commit, though build-record writes both."
  diff_path="$IMPL_DIR/diff-$unit_id.patch"
  git -C "$RV_CODEPATH" diff "$started_at" "$commit" > "$diff_path" 2>/dev/null \
    || die 3 "review-brief: could not write the diff from $started_at to $commit into $diff_path."

  local criteria_json nongoals_json checks_json tests_json
  criteria_json="$(printf '%s' "$SNAPSHOT_DOC" | jq -c --argjson unit "$RV_UNIT_JSON" '
    ((($unit.criteriaServed // []) + ($unit.criteriaOwned // []))
      | reduce .[] as $x ([]; if index($x) then . else . + [$x] end)) as $ids
    | [ $ids[] as $id | (.alignment.criteria // [])[] | select(.id == $id)
        | {id, text, verification, verifiedBy} ]')"
  nongoals_json="$(printf '%s' "$SNAPSHOT_DOC" | jq -c '[ (.alignment.nonGoals // [])[] | {id, text} ]')"
  checks_json="$(printf '%s' "$RV_BUILD_DOC" | jq -c '.checks // []')"
  tests_json="$(rv_frozen_test_paths_json "$unit_id")"

  # The brief is a file the dispatch names, never text printed through this conversation. It
  # carries the contract, the order, the eight check results with what each tool printed, and both
  # interface texts; the reviewer reads it from the path.
  local brief_file brief_json
  brief_file="$IMPL_DIR/brief-$unit_id-review.json"
  brief_json="$(jq -n \
    --arg unit "$unit_id" \
    --argjson criteria "$criteria_json" \
    --argjson nonGoals "$nongoals_json" \
    --argjson order "$RV_UNIT_JSON" \
    --arg diffPath "$diff_path" \
    --argjson frozenTests "$tests_json" \
    --arg reportPath "$(printf '%s' "$RV_BUILD_DOC" | jq -r '.reportPath // ""')" \
    --argjson checks "$checks_json" \
    --arg interfaceDeclared "$(printf '%s' "$RV_UNIT_JSON" | jq -r '.interface // ""')" \
    --arg interfaceRecord "$(printf '%s' "$RV_BUILD_DOC" | jq -r '.interfaceRecord // ""')" \
    --arg findingsPath "$IMPL_DIR/review-$unit_id-findings.json" \
    --arg startedAt "$started_at" --arg commit "$commit" \
    '{
      unit: $unit,
      mode: "review",
      criteria: $criteria,
      nonGoals: $nonGoals,
      order: $order,
      diffPath: $diffPath,
      startedAt: $startedAt,
      commit: $commit,
      frozenTests: $frozenTests,
      reportPath: $reportPath,
      checks: $checks,
      interface: { declared: $interfaceDeclared, record: $interfaceRecord },
      findingsPath: $findingsPath
    }')"
  [ -n "$brief_json" ] || die 3 "review-brief: could not assemble the brief for $unit_id."
  write_atomic "$brief_file" "$brief_json"
  # The check verdicts are printed one per line because review.md routes on interface-record's;
  # the detail and the tool output stay in the brief and the build record.
  im_print_summary "review-brief" "$(printf '%s' "$brief_json" | jq -c --arg brief "$brief_file" '
    {order: .unit,
     brief: $brief,
     diff: .diffPath,
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

do_review_record() {
  local task_arg="" unit_id="" findings_path=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --findings)
        [ "$#" -ge 2 ] || die 3 "review-record: --findings needs a path to the file the reviewer wrote"
        findings_path="$2"; shift 2 ;;
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

  rv_load_state "review-record" "$unit_id"

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
    rr_head="$(git -C "$RV_CODEPATH" rev-parse HEAD 2>/dev/null)"
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

  # Exit 51, decision 6. The reviewer holds Write for one reason: its findings file, at the path
  # the brief gave, under the task folder. This is the check that enforces it. A probe test left
  # in the reviewed code is a refusal here, not a finding later.
  local recorded_commit current_commit dirty
  recorded_commit="$(printf '%s' "$RV_BUILD_DOC" | jq -r '.commit // ""')"
  current_commit="$(git -C "$RV_CODEPATH" rev-parse HEAD 2>/dev/null)"
  [ -n "$current_commit" ] \
    || die 3 "review-record: could not capture the current commit (git rev-parse HEAD failed in $RV_CODEPATH)."
  [ "$recorded_commit" = "$current_commit" ] \
    || die 51 "review-record: $RV_CODEPATH is at $current_commit, and the build record for $unit_id was taken at $recorded_commit. The code moved while the review ran, so these findings are about code that is no longer there."
  dirty="$(git -C "$RV_CODEPATH" status --porcelain 2>/dev/null)"
  [ -z "$dirty" ] \
    || die 51 "review-record: the working tree at $RV_CODEPATH is dirty, and the review may write nothing but its own findings file. What changed: $(printf '%s' "$dirty" | tr '\n' ' ')"

  local raw_findings alignment count i one built findings_json
  rv_read_findings_array "$findings_path" "findings" "review-record"
  raw_findings="$RV_FINDINGS_ARRAY"
  alignment="$(printf '%s' "$SNAPSHOT_DOC" | jq -c '.alignment // {}')"
  findings_json='[]'
  count="$(printf '%s' "$raw_findings" | jq 'length')"
  i=0
  while [ "$i" -lt "$count" ]; do
    one="$(printf '%s' "$raw_findings" | jq -c --argjson i "$i" '.[$i]')"
    built="$(rv_finding_record "$one" "$alignment" "review")"
    findings_json="$(printf '%s' "$findings_json" | jq -c --argjson f "$built" '. + [$f]')"
    i=$((i + 1))
  done

  local today record_json
  today="$(date -u +%Y-%m-%d)"
  record_json="$(jq -n --arg takenAt "$today" --arg unit "$unit_id" --arg commit "$current_commit" \
    --arg findingsPath "$findings_path" --argjson findings "$findings_json" '
    {
      schemaVersion: 1,
      takenAt: $takenAt,
      unit: $unit,
      reviewedAt: $commit,
      findingsPath: $findingsPath,
      findings: $findings,
      rounds: []
    }')"
  write_atomic "$review_file" "$record_json"

  # Decision 11. Unattended, a finding that hits a non-goal halts the order with the non-goal
  # named (ideal/implementation.md, the unattended-answers table). Interactive, it is actionable
  # like any other finding and the skill puts it to the person.
  local nongoal_hits step_expr
  nongoal_hits="$(rv_nongoal_hits "$findings_json" "$alignment")"
  local new_ledger halt_why=""
  if [ "$RV_RUN_MODE" = "autonomous" ] && [ -n "$nongoal_hits" ]; then
    halt_why="a finding hits a non-goal and nobody is present to rule on it: $nongoal_hits"
  fi
  step_expr='.lastStep = "reviewed"'
  new_ledger="$(printf '%s' "$RV_LEDGER_DOC" | jq -c --arg id "$unit_id" \
    ".orders = (.orders | map(if .id == \$id then ($step_expr) else . end))")"
  [ -n "$new_ledger" ] || die 3 "review-record: the ledger update for $unit_id failed."
  # One function writes every halt, so this reason never erases a reason the order already carried.
  if [ -n "$halt_why" ]; then
    new_ledger="$(halt_order_in "$new_ledger" "$unit_id" "$halt_why")"
    [ -n "$new_ledger" ] || die 3 "review-record: the halt on $unit_id could not be written."
  fi
  write_atomic "$RV_LEDGER_FILE" "$new_ledger"

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
     halt: $halt,
     record: $record,
     next: $next}')"
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
  [ "$#" -ge 2 ] || die 3 "fix-brief: a task folder and a unit id are required"
  [ "$#" -le 2 ] || die 3 "fix-brief: unrecognized extra argument: $3"
  local unit_id="$2" resolve_rc
  TASK_PATH="$(resolve_task_folder "$1" "fix-brief")"
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

  local open_json scope_json tests_json
  open_json="$(printf '%s' "$RV_REVIEW_DOC" | jq -c '
    [ (.findings // [])[] | select(.actionable == true and .status == "open") ]
    | sort_by(if .severity == "high" then 0 elif .severity == "medium" then 1 else 2 end)
    | map({id, severity, file, lines, linkedTo, evidence, fixScope, origin})')"
  scope_json="$(printf '%s' "$open_json" | jq -c '[ .[] | (.fixScope // [])[] ] | unique')"
  tests_json="$(rv_frozen_test_paths_json "$unit_id")"

  rv_load_codepath "fix-brief"
  local fb_head brief_file brief_json
  fb_head="$(git -C "$RV_CODEPATH" rev-parse HEAD 2>/dev/null)"
  # One brief per round, because each round's open findings differ from the last round's and the
  # record of what a fixer was given is worth keeping beside its report.
  brief_file="$IMPL_DIR/brief-$unit_id-fix-$((rounds_used + 1)).json"
  brief_json="$(jq -n --arg unit "$unit_id" --argjson findings "$open_json" --argjson fixScope "$scope_json" \
    --argjson frozenTests "$tests_json" --arg headNow "$fb_head" \
    --arg reportPath "$IMPL_DIR/report-$unit_id-fix$((rounds_used + 1)).md" \
    --arg diffBudget "$(printf '%s' "$RV_UNIT_JSON" | jq -r '.diffBudget // ""')" \
    --argjson roundsUsed "$rounds_used" --argjson roundsAllowed "$FIX_ROUNDS_ALLOWED" \
    --argjson round "$((rounds_used + 1))" '
    {
      unit: $unit,
      round: $round,
      roundsUsed: $roundsUsed,
      roundsAllowed: $roundsAllowed,
      findings: $findings,
      fixScope: $fixScope,
      frozenTests: $frozenTests,
      headNow: $headNow,
      diffBudget: $diffBudget,
      reportPath: $reportPath
    }')"
  [ -n "$brief_json" ] || die 3 "fix-brief: could not assemble the brief for $unit_id."
  write_atomic "$brief_file" "$brief_json"
  # A finding is named by id, severity and the id it cites. Its evidence stays in the brief.
  im_print_summary "fix-brief" "$(printf '%s' "$brief_json" | jq -c --arg brief "$brief_file" '
    {order: .unit,
     round: "\(.round) of \(.roundsAllowed)",
     brief: $brief,
     reportPath: .reportPath,
     headNow: (if .headNow == "" then "none: the code repository commit could not be read" else .headNow end),
     finding: ([ .findings[] | {id, severity, linkedTo: ("cites " + (.linkedTo // "nothing")), file} ]),
     fixScope: .fixScope,
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
  local test_recipes="" check_recipes="" values="" scope_raw=""
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

  local started_at_full current_commit
  started_at_full="$(git -C "$RV_CODEPATH" rev-parse --verify --quiet "${started_at}^{commit}" 2>/dev/null)"
  [ -n "$started_at_full" ] \
    || die 43 "fix-record: --started-at ($started_at) is not a commit in the code repository at $RV_CODEPATH."
  current_commit="$(git -C "$RV_CODEPATH" rev-parse HEAD 2>/dev/null)"
  [ -n "$current_commit" ] \
    || die 3 "fix-record: could not capture the current commit (git rev-parse HEAD failed in $RV_CODEPATH)."
  br_require_real_base "fix-record" "$RV_CODEPATH" "$started_at" "$started_at_full" "$current_commit"

  # Exit 45, twice over. One round per commit: a second call at the commit a record already names
  # would spend a round on code nobody changed. The round number moves with the ledger, so the
  # duplicate is not always the same file: a caller who runs this twice writes round 1 and then
  # round 2, both at one commit. So this looks at the round it is about to write and at the round
  # before it, and refuses on either.
  local record_file="$IMPL_DIR/fix-$unit_id-$round_number.json"
  local prev_file existing_doc existing_commit
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
          '.orders = (.orders | map(if .id == $id then (.roundsUsed = (.roundsUsed + 1) | .lastStep = "fixed") else . end))')"
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

  br_require_clean_tree "fix-record" "$RV_CODEPATH" "$unit_id" "$RV_RUN_MODE" "$RV_LEDGER_FILE" "$RV_LEDGER_DOC"

  BRC_WHO="fix-record"
  BRC_CODEPATH="$RV_CODEPATH"
  BRC_STARTED_AT="$started_at_full"
  BRC_CURRENT="$current_commit"
  BRC_UNIT_JSON="$RV_UNIT_JSON"
  BRC_TESTS_DOC="$tests_doc"
  BRC_BASELINE_FILE="$IMPL_DIR/baseline.json"
  local selected_tests_json
  selected_tests_json="$(printf '%s' "$tests_doc" | jq -c \
    '[ (.rows // [])[] | select(.kind == "machine") | (.tests // [])[] | .path ] | unique')"
  CR_WHO="fix-record"
  CR_TEST_RECIPES="$test_recipes"
  CR_CHECK_RECIPES="$check_recipes"
  cr_resolve
  cr_require_baseline_recipes "fix-record" "$IMPL_DIR/baseline.json"

  BRC_RECIPES="$CR_DOC"
  BRC_SELECTED_JSON="$selected_tests_json"
  BRC_VALUES="$values"
  BRC_NOTHING_RAN="$nothing_ran"
  BRC_HAVE_NOTHING_RAN="$have_nothing_ran"

  local seven_file checks_json
  seven_file="$(mktemp)" || die 3 "fix-record: could not create a temporary file"
  br_seven_checks >"$seven_file"
  checks_json="$(cat "$seven_file" 2>/dev/null)"
  rm -f "$seven_file"
  [ -n "$checks_json" ] || die 3 "fix-record: the seven computable checks produced nothing for $unit_id."

  local diff_path
  diff_path="$IMPL_DIR/diff-$unit_id-fix$round_number.patch"
  git -C "$RV_CODEPATH" diff "$started_at_full" "$current_commit" > "$diff_path" 2>/dev/null \
    || die 3 "fix-record: could not write the fix diff from $started_at_full to $current_commit into $diff_path."

  local today record_json executed_count
  executed_count="$(br_executed_count "$checks_json")"
  case "$executed_count" in ''|*[!0-9]*) executed_count=0 ;; esac
  today="$(date -u +%Y-%m-%d)"
  record_json="$(jq -n --arg takenAt "$today" --arg unit "$unit_id" --arg startedAt "$started_at_full" \
    --arg commit "$current_commit" --argjson round "$round_number" --arg reportPath "$report_path" \
    --arg diffPath "$diff_path" --argjson checks "$checks_json" --argjson executed "$executed_count" '
    {
      schemaVersion: 1,
      takenAt: $takenAt,
      unit: $unit,
      startedAt: $startedAt,
      commit: $commit,
      round: $round,
      reportPath: $reportPath,
      diffPath: $diffPath,
      checks: $checks,
      executed: $executed,
      decidingChecks: { total: 8, ranHere: [ $checks[] | .id ] }
    }')"
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
  local all_met first_stopper step_expr halt_why=""
  all_met="$(br_checks_pass "$checks_json" "")"
  first_stopper="$(br_first_stopper "$checks_json" "")"
  if [ "$RV_RUN_MODE" = "autonomous" ] && [ -n "$scope_list" ]; then
    halt_why="a fixer reported its scope too small and nobody is present to rule on it: ${scope_list%, }"
  fi
  if [ "$all_met" != "true" ] && [ "$round_number" -ge "$FIX_ROUNDS_ALLOWED" ]; then
    if [ -n "$halt_why" ]; then
      halt_why="$halt_why. The fix rounds are also spent: $round_number of $FIX_ROUNDS_ALLOWED, and the last was stopped by $first_stopper"
    else
      halt_why="fix rounds spent: $round_number of $FIX_ROUNDS_ALLOWED, and the last was stopped by $first_stopper"
    fi
  fi
  step_expr='.roundsUsed = (.roundsUsed + 1) | .lastStep = "fixed"'
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
  local open_json brief_file brief_json
  open_json="$(printf '%s' "$RV_REVIEW_DOC" | jq -c '
    [ (.findings // [])[] | select(.actionable == true and .status == "open") ]
    | sort_by(if .severity == "high" then 0 elif .severity == "medium" then 1 else 2 end)
    | map({id, severity, file, lines, linkedTo, evidence, fixScope, origin}
          + (if has("scopeInsufficientInRound") then {scopeInsufficientInRound, scopeInsufficientBecause} else {} end))')"
  [ "$(printf '%s' "$open_json" | jq 'length')" -gt 0 ] 2>/dev/null \
    || die 53 "verify-brief: $unit_id has no open actionable finding, so there is nothing to verify."
  brief_file="$IMPL_DIR/brief-$unit_id-verify-$rounds_used.json"
  brief_json="$(jq -n --arg unit "$unit_id" --argjson round "$rounds_used" --argjson findings "$open_json" \
    --argjson fix "$fix_doc" --arg fixRecord "$fix_file" \
    --arg verdictsPath "$IMPL_DIR/verify-$unit_id-$rounds_used.json" '
    {unit: $unit,
     mode: "verify",
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
        [ "$#" -ge 2 ] || die 3 "verify-record: --ruling needs <finding id>=<wrong|deferred|load-bearing>::<reason>"
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
  [ -n "$verdicts_path" ] || die 3 "verify-record: --verdicts is required"

  local resolve_rc
  TASK_PATH="$(resolve_task_folder "$task_arg" "verify-record")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  IMPL_DIR="$TASK_PATH/implementation"

  rv_load_state "verify-record" "$unit_id"
  rv_require_step "verify-record" "$unit_id" "fixed"
  rv_load_review_record "verify-record" "$unit_id"

  local rounds_used
  rounds_used="$(printf '%s' "$RV_ORDER_ENTRY" | jq -r '.roundsUsed // 0')"
  case "$rounds_used" in ''|*[!0-9]*) rounds_used=0 ;; esac
  [ "$rounds_used" -gt 0 ] 2>/dev/null \
    || die 3 "verify-record: $unit_id records no fix round, though the ledger records it as fixed."

  # Exit 45: a round is verified once. A second verification of the same round would record a
  # second set of verdicts over findings the first set already closed.
  local already
  already="$(printf '%s' "$RV_REVIEW_DOC" | jq -r --argjson r "$rounds_used" \
    '[ (.rounds // [])[] | select(.round == $r) ] | length')"
  if [ "$already" != "0" ]; then
    # The verification is already on the record. rv_write_verification writes the review record and
    # then the ledger, so a crash between the two leaves this state with the ledger unmoved. There
    # is nothing left to verify and nothing to write twice, so this reports the record it found.
    rv_print_verification "$rounds_used" "verified: round $rounds_used was already on the record, so nothing was verified twice" "none"
    echo "VERIFY-RECORD: round $rounds_used of $unit_id is already verified in $RV_REVIEW_FILE. Nothing was verified twice." >&2
    exit 0
  fi

  local fix_file
  fix_file="$IMPL_DIR/fix-$unit_id-$rounds_used.json"
  [ -f "$fix_file" ] \
    || die 3 "verify-record: $fix_file not found, though the ledger records round $rounds_used of $unit_id. Run fix-record on it again."

  # Exit 55: a ruling is a person's judgement. An unattended run has none to offer, so it refuses
  # the flag outright rather than recording a model's own word as a person's (decision 12).
  if [ -n "$rulings_raw" ] && [ "$RV_RUN_MODE" = "autonomous" ]; then
    die 55 "verify-record: this run is unattended, and a ruling is a person's judgement. Nothing here may rule on an open finding."
  fi

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
    rv_read_findings_array "$verdicts_path" "newBreakage" "verify-record"
    breakage_rows="$RV_FINDINGS_ARRAY"
  fi

  # Exit 58: the verdict list and the open findings have to correspond, both ways. Every open
  # actionable finding needs one verdict, and a verdict about anything else is a verifier reading
  # a list this order does not hold.
  local open_ids verdict_ids missing extra vcount vi vrow vid vverdict
  open_ids="$(printf '%s' "$RV_REVIEW_DOC" | jq -c \
    '[ (.findings // [])[] | select(.actionable == true and .status == "open") | .id ]')"
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
        elif $row.verdict == "addressed" then
          $f + { status: "addressed", addressedInRound: $r,
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

  # Decision 11 again, and for the same reason: a new finding that hits a non-goal is the same
  # fact as one the review raised, and an unattended run has nobody to rule on either.
  local nongoal_hits
  nongoal_hits="$(rv_nongoal_hits "$(printf '%s' "$updated_findings" | jq -c --argjson ids "$breakage_ids" '[ .[] | select(.id as $i | $ids | index($i)) ]')" "$alignment")"

  # Decision 12: the rulings. A ruling's own syntax is read here, before anything asks whether a
  # ruling is allowed yet, so a malformed one is refused for what is wrong with it whatever the
  # round. Refusing it for its timing instead sends the caller to fix the round rather than the
  # text. What the ruling may do, and whether it may be given at all, is decided below.
  local open_now ruling_halt="" rulings_json="[]"
  open_now="$(printf '%s' "$updated_findings" | jq '[ .[] | select(.actionable == true and .status == "open") ] | length')"
  local rline rid rrest rverdict rreason
  while IFS= read -r rline; do
    [ -n "$rline" ] || continue
    case "$rline" in
      *=*::*) ;;
      *) die 3 "verify-record: --ruling takes <finding id>=<wrong|deferred|load-bearing>::<reason>; got: $rline" ;;
    esac
    rid="${rline%%=*}"
    rrest="${rline#*=}"
    rverdict="${rrest%%::*}"
    rreason="${rrest#*::}"
    rv_is_finding_id "$rid" \
      || die 3 "verify-record: --ruling names '$rid'. A finding id is f and then digits, with no leading zero."
    case "$rverdict" in
      wrong|deferred|load-bearing) ;;
      *) die 3 "verify-record: the ruling for $rid is '$rverdict'. The three words are wrong, deferred and load-bearing." ;;
    esac
    [ -n "$rreason" ] || die 3 "verify-record: the ruling for $rid carries no reason. A ruling with no reason is not a ruling."
    rulings_json="$(printf '%s' "$rulings_json" | jq -c --arg id "$rid" --arg ruling "$rverdict" \
      --arg reason "$rreason" '. + [{id: $id, ruling: $ruling, reason: $reason}]')"
  done <<RV_RULINGS
$rulings_raw
RV_RULINGS

  if [ -n "$rulings_raw" ] && [ "$rounds_used" -lt "$FIX_ROUNDS_ALLOWED" ]; then
    die 3 "verify-record: a ruling is taken only after the last allowed round. $unit_id has used $rounds_used of $FIX_ROUNDS_ALLOWED, so another round is still available."
  fi
  # A ruling with nothing left to rule on is refused rather than dropped. A caller who wrote one
  # believes a finding is still open, and silence would let that belief stand.
  if [ -n "$rulings_raw" ] && [ "$open_now" = "0" ]; then
    die 3 "verify-record: a --ruling was given and $unit_id has no open actionable finding left to rule on."
  fi
  if [ "$rounds_used" -ge "$FIX_ROUNDS_ALLOWED" ] && [ "$open_now" -gt 0 ] 2>/dev/null; then
    if [ "$RV_RUN_MODE" = "autonomous" ]; then
      local open_list
      open_list="$(printf '%s' "$updated_findings" | jq -r '[ .[] | select(.actionable == true and .status == "open") | .id ] | join(", ")')"
      rv_write_verification "$unit_id" "$updated_findings" "$rounds_used" "$verdict_rows" "$breakage_ids" "$outofscope_json" "$fix_file" \
        "a fix round cap reached with findings still open, and nobody is present to rule on them: $open_list"
      echo "VERIFY-RECORD: $unit_id is halted. The fix rounds are spent and these findings are still open: $open_list" >&2
      die 56 "verify-record: this run is unattended, the fix rounds are spent, and these findings are still open: $open_list."
    fi
    local rcount ri unruled is_open
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
      [ "$rverdict" = "load-bearing" ] \
        && ruling_halt="$rid is ruled real and load-bearing: $rreason"
      ri=$((ri + 1))
    done
    unruled="$(printf '%s' "$updated_findings" | jq -r \
      '[ .[] | select(.actionable == true and .status == "open") | .id ] | join(", ")')"
    [ -z "$unruled" ] \
      || die 57 "verify-record: the fix rounds are spent and these findings have no ruling: $unruled. Each one needs --ruling <id>=<wrong|deferred|load-bearing>::<reason>."
  fi

  local halt_why=""
  if [ "$RV_RUN_MODE" = "autonomous" ] && [ -n "$nongoal_hits" ]; then
    halt_why="a finding hits a non-goal and nobody is present to rule on it: $nongoal_hits"
  elif [ -n "$ruling_halt" ]; then
    halt_why="$ruling_halt"
  fi
  rv_write_verification "$unit_id" "$updated_findings" "$rounds_used" "$verdict_rows" "$breakage_ids" "$outofscope_json" "$fix_file" "$halt_why"

  rv_print_verification "$rounds_used" "verified" "${halt_why:-none}"
  [ -z "$halt_why" ] || echo "VERIFY-RECORD: $unit_id is halted. $halt_why" >&2
  exit 0
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

  local started_at head_now
  started_at="$(printf '%s' "$RV_BUILD_DOC" | jq -r '.startedAt // ""')"
  [ -n "$started_at" ] \
    || die 3 "close: $IMPL_DIR/build-$unit_id.json holds no startedAt, though build-record writes it."
  head_now="$(git -C "$RV_CODEPATH" rev-parse HEAD 2>/dev/null)"
  [ -n "$head_now" ] \
    || die 3 "close: could not capture the current commit (git rev-parse HEAD failed in $RV_CODEPATH)."

  # Exit 61 and exit 63. Close writes the commit range this order produced, and a range is a claim
  # about what is in the repository. So the tree has to be clean, and HEAD has to be the commit the
  # last record for this order was written at: the build record when no round ran, the last fix
  # record otherwise. Without both, the range names commits that do not hold the work, which is the
  # same gap the record steps close with exit 61.
  br_require_clean_tree "close" "$RV_CODEPATH"
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
    || die 63 "close: $RV_CODEPATH is at $head_now, and the last record for $unit_id ($last_record) was written at $last_commit. The code moved after the record, so the range this would write names work nothing here judged."

  local new_ledger
  new_ledger="$(printf '%s' "$RV_LEDGER_DOC" | jq -c --arg id "$unit_id" \
    --arg range "$started_at..$head_now" '
    .orders = (.orders | map(if .id == $id then (.lastStep = "closed" | .commitRange = $range) else . end))')"
  [ -n "$new_ledger" ] || die 3 "close: the ledger update for $unit_id failed."

  # Every criterion this order serves or owns is decided now, and only now. A criterion design split
  # across several orders has no honest answer before the last of them closes, so confirmed needs
  # every serving order closed, a judgement from every one of them, and every one of those
  # judgements confirmed. One rejected judgement decides it the other way, whichever order left it.
  # Two of the three clauses are defensive, and neither is reachable through the actions. The
  # rejection cannot arrive, because `tests-freeze` refuses a rejected row outright. A serving order
  # closed without leaving a judgement cannot arrive either, because the freeze refuses a machine
  # criterion with no row and an order reaches `close` only through the freeze. Both are derived
  # rather than assumed: a state nothing can produce today is still a state to read correctly, and a
  # hand-edited ledger can produce either. A criterion a person verifies is left where it is, at not-judged. It carries a
  # checklist and no judgement, and completion is what confirms it (ideal/implementation.md, "A
  # criterion a person inspects has no tests"). The kind is read from the frozen contract, which is
  # the one producer of it; the frozen test record's own `kind` is a copy of that same field.
  local served_json serving_map_json kinds_json
  served_json="$(printf '%s' "$RV_UNIT_JSON" | jq -c '((.criteriaServed // []) + (.criteriaOwned // [])) | unique')"
  serving_map_json="$(printf '%s' "$SNAPSHOT_DOC" | jq -c \
    '[ .workOrders[]? | {id: .id, serves: (((.criteriaServed // []) + (.criteriaOwned // [])) | unique)} ]')"
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
            | ([ $l.orders[] | select((.id as $i | $servers | index($i)) != null) ]) as $entries
            | (($c.judgements // [])) as $js
            | if ($js | map(.verdict) | index("rejected")) != null then ($c + {rowState: "rejected"})
              elif ((($entries | map(.lastStep == "closed")) | all)
                     and (($servers - ([ $js[] | .unit ])) | length) == 0
                     and (($js | map(.verdict == "confirmed")) | all))
                then ($c + {rowState: "confirmed"})
              else ($c + {rowState: "not-judged"}) end
          end))')"
  [ -n "$new_ledger" ] || die 3 "close: deriving the row states for $unit_id failed."
  write_atomic "$RV_LEDGER_FILE" "$new_ledger"

  # The model-judged count is over the whole ledger, not this order alone: it is what a person
  # returning to a finished run reads to list every row no person ever looked at.
  im_print_summary "close" "$(printf '%s' "$new_ledger" | jq -c --arg id "$unit_id" --argjson served "$served_json" \
    --arg ledger "$RV_LEDGER_FILE" \
    --arg next "$(im_next_step "$new_ledger" "$SNAPSHOT_DOC" "$IMPL_DIR" "true" "false")" '
    ((.orders // []) | map(select(.id == $id)) | .[0]) as $o
    | {order: $id,
       state: ($o.lastStep // ""),
       commitRange: ($o.commitRange // ""),
       attempts: ("\($o.attemptsUsed // 0) used"),
       rounds: ("\($o.roundsUsed // 0) used"),
       criterion: [ (.criteria // [])[] | select((.id as $i | $served | index($i)) != null)
                    | {id: .id, rowState: .rowState,
                       judgedBy: ("judgedBy=" + (([ (.judgements // [])[] | .judgedBy ] | unique) | if length == 0 then "nobody" else join(",") end))} ],
       rowsJudgedByModel: ([ (.criteria // [])[] | (.judgements // [])[] | select(.judgedBy == "model") ] | length),
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

# Exit 68. Both the grant and the restart are a person's judgement, so an autonomous run refuses.
# $1 the action's own name, $2 what the caller would have been deciding.
fn_require_interactive() {
  local who="$1" what="$2"
  [ "$(printf '%s' "$FN_LEDGER_DOC" | jq -r '.runMode // "interactive"')" = "autonomous" ] || return 0
  die 68 "$who: this run is autonomous, and $what is a person's judgement. Nothing is written. Run this action again with a person present, or let the halt stand."
}

# finish: the implementation stage is done for this task. The task is not. It goes to the review
# stage next, and finished.json is what that stage receives.
do_finish() {
  [ "$#" -ge 1 ] || die 3 "finish: a task folder is required"
  [ "$#" -le 1 ] || die 3 "finish: unrecognized extra argument: $2"
  local resolve_rc
  TASK_PATH="$(resolve_task_folder "$1" "finish")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  IMPL_DIR="$TASK_PATH/implementation"

  fn_load_task_state "finish"

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
  # refusal names which, and which action answers it, because two of the three no action in this
  # script clears: `restart` wants a drift halt and `grant-attempt` answers a spent counter, so a
  # reader told only "not confirmed" has nothing to do next and no way to learn what.
  unconfirmed="$(jq -nr --argjson ledger "$FN_LEDGER_DOC" --argjson snap "$SNAPSHOT_DOC" '
      ([ ($snap.alignment.criteria // [])[] | select(.verifiedBy == "machine") | .id ]) as $machine
      | ([ ($snap.workOrders // [])[] | (.criteriaServed // [])[] , (.criteriaOwned // [])[] ]) as $served
      | [ ($ledger.criteria // [])[] | select((.id as $i | $machine | index($i)) != null)
          | select(.rowState != "confirmed")
          | . as $c
          | if ($c.rowState == "rejected")
              then ($c.id + " (rejected: a row checker turned this down. The row goes back to the test author, who runs tests-freeze on that order again once the test is repaired)")
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

  # --- the checklists a person still has to work through, copied from the frozen records ----------
  # They are copied rather than pointed at, because the review stage reads this one file and the
  # frozen records are per order. A criterion two orders serve carries one entry per order, the same shape
  # the frozen records themselves keep.
  local order_ids order_count oi one_id one_tests checklists_json='[]' deferred_json='[]' one_review
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
    fi
    oi=$((oi + 1))
  done

  local task_id today record_json record_file
  task_id="$(jq -r '.id // empty' "$TASK_PATH/task.json" 2>/dev/null)"
  [ -n "$task_id" ] || die 3 "finish: $TASK_PATH/task.json has no usable id field"
  today="$(date -u +%Y-%m-%d)"
  record_file="$IMPL_DIR/finished.json"
  record_json="$(jq -n --arg takenAt "$today" --arg task "$task_id" \
    --arg range "$started_from..$head_now" \
    --argjson ledger "$FN_LEDGER_DOC" --argjson snap "$SNAPSHOT_DOC" \
    --argjson checklists "$checklists_json" --argjson deferred "$deferred_json" '
    ([ ($snap.alignment.criteria // [])[] | {id: .id, verifiedBy: .verifiedBy} ]) as $kinds
    | {
      schemaVersion: 1,
      takenAt: $takenAt,
      task: $task,
      commitRange: $range,
      orders: [ ($ledger.orders // [])[] | {id: .id, commitRange: (.commitRange // ""), roundsUsed: (.roundsUsed // 0)} ],
      criteria: [ ($ledger.criteria // [])[] | . as $c
                  | {id: $c.id,
                     verifiedBy: (([ $kinds[] | select(.id == $c.id) ][0].verifiedBy) // ""),
                     rowState: $c.rowState,
                     judgedBy: ([ ($c.judgements // [])[] | .judgedBy ] | unique)} ],
      checklists: $checklists,
      deferred: $deferred,
      rowsJudgedByModel: ([ ($ledger.criteria // [])[] | (.judgements // [])[] | select(.judgedBy == "model") ] | length)
    }')"
  [ -n "$record_json" ] || die 3 "finish: could not assemble the finished record for $task_id."
  write_atomic "$record_file" "$record_json"

  # The summary. The checklists, the deferred findings and every criterion's row are in the record,
  # which the review stage reads from the path named here.
  im_print_summary "finish" "$(printf '%s' "$record_json" | jq -c --arg record "$record_file" '
    {task: .task,
     commitRange: .commitRange,
     order: ([ .orders[] | {id, commitRange, rounds: ("rounds=" + (.roundsUsed | tostring))} ]),
     criteria: ((.criteria | group_by(.rowState) | map("\(.[0].rowState)=\(length)") | join(" ")) | if . == "" then "none" else . end),
     checklists: (.checklists | length),
     deferred: ([ .deferred[] | .unit + "/" + .finding ]),
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

  # A grant answers one reason and only one: the attempt counter is spent. A halt can hold several
  # reasons, newest first, so this looks at every segment rather than the front of the text. The
  # grant then removes that one segment. Any other reason stays, and the order stays halted with it,
  # because clearing a reason a grant does not answer would hide it behind an attempt nobody needed.
  local halt halt_spent halt_rest
  halt="$(printf '%s' "$order_entry" | jq -r '.haltedBecause // ""')"
  halt_spent="$(printf '%s' "$halt" | jq -Rr '
      if . == "" then empty else (split("; earlier: ") | map(select(startswith("attempts spent"))) | join("; earlier: ")) end')"
  halt_rest="$(printf '%s' "$halt" | jq -Rr '
      if . == "" then empty else (split("; earlier: ") | map(select(startswith("attempts spent") | not)) | join("; earlier: ")) end')"
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

  local head_short today target
  head_short="$(git -C "$RV_CODEPATH" rev-parse --short HEAD 2>/dev/null)"
  [ -n "$head_short" ] \
    || die 3 "restart: could not capture the current commit (git rev-parse HEAD failed in $RV_CODEPATH)."
  today="$(date -u +%Y-%m-%d)"
  target="$TASK_PATH/implementation-$today-$head_short"
  [ ! -e "$target" ] \
    || die 3 "restart: $target already exists. A second restart on the same day at the same commit would write over the first one's records; move or remove it by hand first."

  # The reason is written inside the folder being moved aside, because that folder is what it
  # explains. Nothing reads this file yet; a person does.
  local restart_json
  restart_json="$(jq -n --arg restartedAt "$today" --arg reason "$reason" --arg head "$head_short" \
    --arg drifted "$drifted" \
    '{schemaVersion: 1, restartedAt: $restartedAt, reason: $reason, headCommit: $head,
      ordersHaltedForDrift: ($drifted | split(", "))}')"
  write_atomic "$IMPL_DIR/restarted.json" "$restart_json"

  mv "$IMPL_DIR" "$target" || die 3 "restart: could not move $IMPL_DIR to $target"

  echo "RESTART: $IMPL_DIR moved aside. Orders halted for drift: $drifted"
  echo "RESTART: run start on this task to take a fresh snapshot from the live design."
  printf '%s\n' "$target"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# dispatch-open, dispatch-close: open and clear <project path>/dispatch.json
# (scripts/dispatch-schema.json), the one record hooks/deny-prior-source.sh and
# hooks/deny-frozen-test-writes.sh read to tell a dispatched role apart from a person working
# their own repository. The build is serial, so a project has at most one active dispatch;
# dispatch-open refuses to overwrite one already there (exit 37), and dispatch-close removes it,
# safe to call when none is open.
# ------------------------------------------------------------------------------------------------

do_dispatch_open() {
  local task_arg="" role="" unit_id="" deny_raw="" allow_raw=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
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

  local project_folder codepath
  rv_load_codepath "dispatch-open"
  project_folder="$RV_PROJECT_FOLDER"
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
  fi

  # The row-checker takes the test author's derivation exactly. It reads a criterion's verify clause
  # and the test named against it, and answers whether the one observes the other. Reading the
  # implementation would let it answer from the code rather than from the test, which is the whole
  # failure the checkpoint exists to catch (ideal/implementation.md, "The trace matrix and its
  # checkpoint").
  if [ "$role_bare" = "test-author" ] || [ "$role_bare" = "row-checker" ]; then
    local owned_json owned_count
    owned_json="$(printf '%s' "$SNAPSHOT_DOC" | jq -c '[.workOrders[]?.ownedFiles[]?] | unique')"
    owned_count="$(printf '%s' "$owned_json" | jq 'length' 2>/dev/null)"
    [ -n "$owned_count" ] || owned_count=0
    [ "$owned_count" -gt 0 ] 2>/dev/null \
      || die 47 "dispatch-open: no work order in $IMPL_DIR/snapshot.json declares an owned file, so a $role_bare would be dispatched with nothing denied and could read every file in the repository. Design has to name what each order owns before the tests for it are written."
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
  # narrower still. A write outside the scope is caught by the owned-files check after the round,
  # never by a hook, so nothing here is loosened to let a fixer reach further.
  if [ "$role_bare" = "implementer" ] || [ "$role_bare" = "fixer" ]; then
    local mine_json others_json mine_count
    mine_json="$(printf '%s' "$SNAPSHOT_DOC" | jq -c --arg u "$unit_id" \
      '[ .workOrders[]? | select(.id == $u) | .ownedFiles[]? ] | unique')"
    mine_count="$(printf '%s' "$mine_json" | jq 'length' 2>/dev/null)"
    [ -n "$mine_count" ] || mine_count=0
    [ "$mine_count" -gt 0 ] 2>/dev/null \
      || die 47 "dispatch-open: $unit_id declares no owned file in $IMPL_DIR/snapshot.json, so a $role_bare would be dispatched with nowhere it is meant to write. Design has to name what this order owns before its code is written."
    others_json="$(printf '%s' "$SNAPSHOT_DOC" | jq -c --arg u "$unit_id" \
      '[ .workOrders[]? | select(.id != $u) | .ownedFiles[]? ] | unique')"
    deny_raw="$deny_raw$(printf '%s' "$others_json" | jq -r '.[]')
"
    allow_raw="$allow_raw$(printf '%s' "$mine_json" | jq -r '.[]')
"
  fi

  local dispatch_file="$project_folder/dispatch.json"
  if [ -f "$dispatch_file" ]; then
    jq empty "$dispatch_file" 2>/dev/null \
      || die 3 "dispatch-open: $dispatch_file exists but could not be read as JSON. Repair or remove it by hand before running this again."
    local held_role held_task held_unit
    held_role="$(jq -r '.role // "?"' "$dispatch_file" 2>/dev/null)"
    held_task="$(jq -r '.task // "?"' "$dispatch_file" 2>/dev/null)"
    held_unit="$(jq -r '.unit // "?"' "$dispatch_file" 2>/dev/null)"
    die 37 "dispatch-open: $dispatch_file is already open, for role $held_role on task $held_task, unit $held_unit. Run dispatch-close first."
  fi

  local deny_json allow_json
  deny_json="$(printf '%s' "$deny_raw" | jq -R -s 'split("\n") | map(select(length>0))')"
  allow_json="$(printf '%s' "$allow_raw" | jq -R -s 'split("\n") | map(select(length>0))')"

  local record_json
  record_json="$(jq -n --arg role "$role" --arg task "$task_id" --arg unit "$unit_id" \
    --arg codePath "$codepath" --argjson denyRead "$deny_json" --argjson allowWrite "$allow_json" \
    '{schemaVersion: 1, role: $role, task: $task, unit: $unit, codePath: $codePath,
      denyRead: $denyRead, allowWrite: $allowWrite}')"

  write_atomic "$dispatch_file" "$record_json"
  echo "DISPATCH-OPEN: written (role $role, task $task_id, unit $unit_id)"
  local deny_count
  deny_count="$(printf '%s' "$deny_json" | jq 'length' 2>/dev/null)"
  [ -n "$deny_count" ] || deny_count=0
  if [ "$deny_count" -gt 0 ] 2>/dev/null; then
    echo "DISPATCH-OPEN: reads denied to this role, resolved against $codepath:"
    printf '%s' "$deny_json" | jq -r '.[] | "  " + .'
  else
    echo "DISPATCH-OPEN: this dispatch denies no read. Every path under $codepath stays readable."
  fi
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
  [ "$#" -le 1 ] || die 3 "dispatch-close: unrecognized extra argument: $2"
  local task_path="$1"
  local resolve_rc
  TASK_PATH="$(resolve_task_folder "$task_path" "dispatch-close")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"

  local project_folder
  project_folder="$(resolve_project_folder "$TASK_PATH")" \
    || die 3 "dispatch-close: could not resolve a project folder two levels up from $TASK_PATH, or it has no project.json"

  local dispatch_file="$project_folder/dispatch.json"
  if [ -f "$dispatch_file" ]; then
    # The record lives at the project root while `read` and `start` are per task, and two tasks in
    # one project is a supported state. A second task closing the first task record would leave
    # both hooks on the no-record branch, allowing every read and every write to a frozen test for
    # the rest of that role run, and the message reporting it reaches the running role and nobody
    # else. So the record says whose it is, and a close that does not match refuses.
    local open_doc open_task this_task
    open_doc="$(jq -c '.' "$dispatch_file" 2>/dev/null)"
    if [ -n "$open_doc" ]; then
      open_task="$(printf '%s' "$open_doc" | jq -r '.task // ""')"
      this_task="$(basename -- "$TASK_PATH")"
      if [ -n "$open_task" ] && [ "$open_task" != "$this_task" ]; then
        die 75 "dispatch-close: $dispatch_file was opened for task $open_task, and this call names task $this_task. A close belongs to the task that opened the record; clearing another task record would leave its role with every permission the record withheld."
      fi
    fi
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
  tests-brief)  do_tests_brief  "$@" ;;
  tests-freeze) do_tests_freeze "$@" ;;
  build-brief)  do_build_brief  "$@" ;;
  build-record) do_build_record "$@" ;;
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
  dispatch-open)  do_dispatch_open  "$@" ;;
  dispatch-close) do_dispatch_close "$@" ;;
  step)           do_step           "$@" ;;
  *) usage; die 3 "unknown action: $ACTION" ;;
esac
