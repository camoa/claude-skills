#!/usr/bin/env bash
# implement-actions.sh: the deterministic half of the implement skill (ideal/implementation.md).
#
# The skill body holds the conversation: whether to tell a person about a refusal, whether to act
# on a drifted order, what to say once the report comes back. This script never asks a question
# and never judges whether a criterion is really met. It performs the first step of the
# implementation stage: freezing the contract and the work orders design left into a snapshot,
# opening the ledger that will track every order's progress, and refusing before writing anything
# when the task is not ready. It then performs the second step: establishing whether the code
# repository can run a test at all, against the conditions each framework's recipe declares. It
# then performs the two halves of the third step: `tests-brief` assembles exactly what a model
# writing one unit's tests may see, from the frozen snapshot, and `tests-freeze` verifies what that
# model wrote and freezes it. The script never writes a test and never judges one; the model that
# writes a test chooses the level, writes the file, and runs it. It then performs the two halves of
# the fourth step: `build-brief` assembles exactly what a model writing one unit's code may see, and
# `build-record` verifies what came back and moves the attempt counter. `build-record` runs four of
# the eight deciding checks named in docs/implementation.md ("The deciding checks run before
# anything judges"): every test of this order passes, no test outside the baseline fails, the
# realized diff touches only files this order owns, and every frozen test file is unchanged. The
# other four (coding standards, static analysis, security, the interface record) belong to a later
# step. The script never writes code and never judges whether a criterion is met; it only decides
# whether this attempt stayed inside the bounds a script can check without reading anyone's prose.
# `dispatch-open` and `dispatch-close` open and clear the one record, <project path>/dispatch.json,
# that the two permission hooks (hooks/deny-prior-source.sh, hooks/deny-frozen-test-writes.sh) read
# to tell a dispatched role apart from a person working their own repository. Neither hook is this
# script's own concern past that one file; this script only opens and closes the record.
# The critique and repair steps after step four are not built yet; only `read`, `start`,
# `preconditions`, `tests-brief`, `tests-freeze`, `build-brief`, `build-record`, `dispatch-open` and
# `dispatch-close` exist.
#
# Usage:
#   implement-actions.sh read  <task_folder>
#   implement-actions.sh start <task_folder>
#   implement-actions.sh preconditions <task_folder> [--recipe <framework>=<path>]...
#                                                    [--lookup-failed <framework>=<reason>]...
#                                                    [--value <name>=<value>]...
#   implement-actions.sh tests-brief  <task_folder> <unit_id>
#   implement-actions.sh tests-freeze <task_folder> <unit_id> \
#                            [--test <path>::<test name>=<criterion id>[,<criterion id>...]]...
#                            [--red <test name>=<path to a file holding what the run printed>]...
#                            [--test-glob <glob>]...
#                            [--checklist <criterion id>=<verification text>]...
#                            [--green-on-arrival <test name>=<reason>]...
#   implement-actions.sh build-brief  <task_folder> <unit_id>
#   implement-actions.sh build-record <task_folder> <unit_id> \
#                            --interface <path to the record the builder wrote> \
#                            --report <path to the builder's report> \
#                            --started-at <commit the attempt began from> \
#                            [--suite <argv token>...] \
#                            [--order-tests <argv token>...] \
#                            [--nothing-ran <literal substring>]
#   implement-actions.sh dispatch-open <task_folder> <role> <unit_id> \
#                            [--deny-read <path relative to codePath>]... \
#                            [--allow-write <path relative to codePath>]...
#
# `dispatch-open` checks <role> against the agent definitions this plugin ships and refuses a name
# that matches none of them. For the two roles that build, it also derives the path lists itself
# from the frozen snapshot, so neither is a list a caller assembles per dispatch: a test author is
# denied every order's owned files, and an implementer is denied every order's but its own and is
# allowed its own. `--deny-read` adds to what was derived; it is how a path outside codePath is
# denied, such as the recipe each role may not open.
#   implement-actions.sh dispatch-close <task_folder>
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
#
# This script never runs a schema comparison against snapshot-schema.json or ledger-schema.json
# itself. Every field it writes is built from those two schemas' own field lists by construction;
# a stale or hand-edited file already on disk before this script's first call on it is a fact this
# script reports (present-but-unreadable, or a hash mismatch), not one it repairs.
#
# Freezing, and what a freeze is for (ideal/implementation.md, "Freezing, and what a freeze is
# for"). Design close records a hash over the contract and every work order at
# <task_folder>/design-closed.json (design-closed-schema.json). A new run here re-derives that
# same hash from the live files and refuses when the two disagree, because design changed after it
# closed and was never closed again. That refusal replaces the "late state" version 5 could only
# report: version 5 named a capture taken after work had already started as `status: "late"` and
# left a person to notice it, above a comment that a late re-capture would launder exactly the
# edit it exists to expose. Version 6 refuses outright, before a snapshot is ever written, and the
# message says to close design again. Once a snapshot exists, this script never reads
# design-closed.json again: a resumed run instead re-derives a hash from the LIVE files and
# compares it against the SNAPSHOT's own recorded hash, which is the separate, ongoing drift check
# described below. That is deliberate. The design-closed hash proves what design closed on; the
# snapshot is what the build is frozen against, and only the snapshot governs a resumed run.
#
# Version 5's freeze mechanism has four properties. Version 6 takes three: the one-shot capture,
# which refuses to overwrite; the check that re-derives from disk rather than believing a recorded
# value, applied both to the live files (the drift check, on a resumed run) and to the snapshot's
# own stored content (a resumed run also checks the snapshot agrees with itself); and the second
# snapshot, which is review's own and belongs to that later part. The fourth, the named "late"
# state, is the one version 6 does not need: the design-closed hash turns "late" into a refusal at
# the moment it would happen, so there is nothing left to name after the fact.
#
# What `start` does, in order, and why:
#
#   1. Resolve the task folder, and confirm its contract exists and can be read.
#   2. Refuse unless scripts/check-design.sh reports design closed cleanly, on the LIVE
#      design/*.json files, never a stale copy.
#   3. Read the live alignment.json and every live design/*.json, and re-derive one hash over
#      them together (scripts/lib/records-hash.sh). Every later step that reads "the live hash"
#      reads this one value; it is computed once per call, never twice.
#   4. Resolve the task's own project (two folders up: <task_folder> is
#      <projectPath>/tasks/<task-id>) and confirm its codePath is a git repository. AIDA commits
#      its own records in the project folder's own repository; codePath is the code repository
#      the build itself lands in, and that is the repository this step and the two steps below
#      both read.
#   5. Confirm codePath is currently on a named branch. A detached HEAD refuses, whether or not
#      the trunk branch can be derived: a commit made there belongs to no branch, which this build
#      must never risk.
#   6. Derive codePath's trunk branch from `refs/remotes/origin/HEAD`, never store it, and refuse
#      when the branch currently checked out there is the trunk. When it cannot be derived (no
#      `origin` remote, or origin's HEAD is unset), that is reported as a check that could not
#      look, never as a pass and never as a refusal.
#   7. Read runMode from task.json. Absent means interactive (task-schema.json, `runMode`). The
#      field's only other legal value is "autonomous"; a task.json that spells out "interactive"
#      by hand is refused, because the schema never writes that word there.
#   8. Look at <task_folder>/implementation/snapshot.json. Absent: a new run. Present and
#      readable: a resumed run. Present and unreadable: a third fact, and a refusal.
#   9. New run only: refuse unless <task_folder>/design-closed.json exists and its own recorded
#      hash equals the live hash from step 3 (a missing record means design has never closed; a
#      disagreeing hash means it closed once and something changed since, without closing again).
#      Refuse separately when design left no work orders at all. Then copy alignment.json and
#      every design/*.json (in id order) into a snapshot, using the live hash from step 3, and
#      write it. Every refusal here runs before this write.
#  10. Resumed run only: re-derive a hash from the snapshot's own copied alignment and work
#      orders and refuse if it disagrees with the snapshot's own stored hash: the snapshot file
#      was edited after it was written. Otherwise compare the live hash from step 3 against the
#      same stored hash. A difference is worked out order by order: only a work order whose own
#      design file actually changed is drifted, and only a drifted order's ledger entry is halted
#      at the end of this run. A contract that changed with no work order affected halts nothing
#      and is reported. A new run has nothing to compare against and reports that plainly, never
#      as "nothing changed".
#  11. From here on, every read of the criteria and the work orders is from the snapshot, never
#      the live files.
#  12. Derive a build order from dependsOn. Refuse on a dependency cycle (naming the orders in
#      it) or on two orders sharing a declared owned-file path (naming both). This overlap check
#      compares declared path strings for equality only, the same bound check-design.sh's own
#      overlap check carries: two globs that would collide at build time without sharing one
#      identical declared entry are not caught here, which is a documented bound, not a defect.
#      It also duplicates a check the design check already owns; it is kept here as a second
#      reading on the resumed path, where check-design.sh is not re-run.
#  13. Capture codePath's current HEAD, the commit the build starts from.
#  14. Open <task_folder>/implementation/ledger.json, or reopen it. Opening writes one entry per
#      snapshot work order (lastStep null, both counters zero) and one per snapshot criterion
#      (not-judged). Reopening compares its own stored snapshotHash against the snapshot file's
#      own hash field and refuses on a mismatch; it never resets a counter and never rewrites a
#      completed step, and its only change on a drifted resume is adding haltedBecause to the
#      orders step 10 found drifted.
#  15. Print one report: what was read, which orders are ready to build, which order is in
#      flight and at what step, what drifted, and what the trunk check could establish.
#
# The refusals in steps 1 through 9 all run before step 9's own write, so a run refused there
# leaves nothing on disk. A refusal from steps 12 or 14 can follow a write earlier in the same
# `start` call (the snapshot from step 9, most often): that write is never half-formed, because
# write_atomic below always produces a complete file or none, and it is never wrong to have on
# disk, because it is exactly what the next `start` call on this task would compute again.
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
#      where codePath exists but is not a git repository.
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
#  20  `preconditions` was asked to run on a task whose build has never started: no snapshot and
#      no ledger. Run `start` first.
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
#  43  `build-record` was given a --started-at that is not a commit in the code repository.
#  44  `build-record` found the interface record file named by --interface missing or empty while
#      the given unit declares a non-empty interface. A file present for a unit that declares no
#      interface is read and recorded without complaint; nothing here judges its content.
#  45  `build-record` found <task_folder>/implementation/build-<unit_id>.json already recorded at
#      the same commit and the same attempt number this call would write. The message names both,
#      because a caller who calls this twice for one attempt is not shown a stale success silently.
#
#  46  `dispatch-open` was given a role that names no agent under ${CLAUDE_PLUGIN_ROOT}/agents, or
#      found that folder empty. A role nothing checks opens a record no agent's own `agent_type`
#      can match, and both hooks then allow every read and every write in silence, so this refuses
#      rather than writing a record that looks like a permission and is not one.
#  47  `dispatch-open` was asked to open a test-author dispatch on a snapshot whose work orders
#      declare no owned file between them. That role's denied reads are derived from those files,
#      so an empty set means the one denial the role exists for would apply to nothing.
#
# Portability: bash 3.2+ and zsh. No mapfile, no associative arrays, no GNU-only flag, no awk, no
# regular-expression interval quantifier anywhere (foundations.md, Honesty). sha256sum exists on
# Linux and `shasum -a 256` on macOS; scripts/lib/records-hash.sh tries both. An id's own shape,
# where one is checked, uses a `case` glob, never a regular expression.
#
# Four zsh traps have each cost a round of debugging in this file. They are listed here because
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
RECORDS_HASH_LIB="${PLUGIN_ROOT}/scripts/lib/records-hash.sh"

command -v jq >/dev/null 2>&1 || { printf 'implement-actions: jq is required and was not found on PATH\n' >&2; exit 3; }

die1() { printf 'implement-actions: %s\n' "$1" >&2; exit 1; }
die2() { printf 'implement-actions: %s\n' "$1" >&2; exit 2; }
die3() { printf 'implement-actions: %s\n' "$1" >&2; exit 3; }
die4() { printf 'implement-actions: %s\n' "$1" >&2; exit 4; }
die5() { printf 'implement-actions: %s\n' "$1" >&2; exit 5; }
die6() { printf 'implement-actions: %s\n' "$1" >&2; exit 6; }
die7() { printf 'implement-actions: %s\n' "$1" >&2; exit 7; }
die8() { printf 'implement-actions: %s\n' "$1" >&2; exit 8; }
die9() { printf 'implement-actions: %s\n' "$1" >&2; exit 9; }
die10() { printf 'implement-actions: %s\n' "$1" >&2; exit 10; }
die11() { printf 'implement-actions: %s\n' "$1" >&2; exit 11; }
die12() { printf 'implement-actions: %s\n' "$1" >&2; exit 12; }
die13() { printf 'implement-actions: %s\n' "$1" >&2; exit 13; }
die14() { printf 'implement-actions: %s\n' "$1" >&2; exit 14; }
die15() { printf 'implement-actions: %s\n' "$1" >&2; exit 15; }
die16() { printf 'implement-actions: %s\n' "$1" >&2; exit 16; }
die17() { printf 'implement-actions: %s\n' "$1" >&2; exit 17; }
die18() { printf 'implement-actions: %s\n' "$1" >&2; exit 18; }
die20() { printf 'implement-actions: %s\n' "$1" >&2; exit 20; }
die21() { printf 'implement-actions: %s\n' "$1" >&2; exit 21; }
die22() { printf 'implement-actions: %s\n' "$1" >&2; exit 22; }
die23() { printf 'implement-actions: %s\n' "$1" >&2; exit 23; }
die24() { printf 'implement-actions: %s\n' "$1" >&2; exit 24; }
die25() { printf 'implement-actions: %s\n' "$1" >&2; exit 25; }
die26() { printf 'implement-actions: %s\n' "$1" >&2; exit 26; }
die27() { printf 'implement-actions: %s\n' "$1" >&2; exit 27; }
die28() { printf 'implement-actions: %s\n' "$1" >&2; exit 28; }
die29() { printf 'implement-actions: %s\n' "$1" >&2; exit 29; }
die30() { printf 'implement-actions: %s\n' "$1" >&2; exit 30; }
die31() { printf 'implement-actions: %s\n' "$1" >&2; exit 31; }
die32() { printf 'implement-actions: %s\n' "$1" >&2; exit 32; }
die33() { printf 'implement-actions: %s\n' "$1" >&2; exit 33; }
die34() { printf 'implement-actions: %s\n' "$1" >&2; exit 34; }
die35() { printf 'implement-actions: %s\n' "$1" >&2; exit 35; }
die36() { printf 'implement-actions: %s\n' "$1" >&2; exit 36; }
die37() { printf 'implement-actions: %s\n' "$1" >&2; exit 37; }
die38() { printf 'implement-actions: %s\n' "$1" >&2; exit 38; }
die39() { printf 'implement-actions: %s\n' "$1" >&2; exit 39; }
die40() { printf 'implement-actions: %s\n' "$1" >&2; exit 40; }
die41() { printf 'implement-actions: %s\n' "$1" >&2; exit 41; }
die42() { printf 'implement-actions: %s\n' "$1" >&2; exit 42; }
die43() { printf 'implement-actions: %s\n' "$1" >&2; exit 43; }
die44() { printf 'implement-actions: %s\n' "$1" >&2; exit 44; }
die45() { printf 'implement-actions: %s\n' "$1" >&2; exit 45; }
die46() { printf 'implement-actions: %s\n' "$1" >&2; exit 46; }
die47() { printf 'implement-actions: %s\n' "$1" >&2; exit 47; }

[ -f "$RECORDS_HASH_LIB" ] || die3 "cannot find the records-hash library at $RECORDS_HASH_LIB"
# shellcheck source=/dev/null
source "$RECORDS_HASH_LIB" || die3 "the records-hash library failed to load: $RECORDS_HASH_LIB"

# How many times `build-brief` will hand one order to a builder before refusing (exit 41). Two, not
# version 5's three: nothing in version 5 justifies three beyond a clamp guarding a corrupted
# counter, never the cap itself. A constant here rather than a project or task field, because
# nothing yet gives it a producer of its own; a later stage may compute it instead.
BUILD_ATTEMPTS_ALLOWED=2

usage() {
  cat <<'EOF' >&2
usage: implement-actions.sh read  <task_folder>
       implement-actions.sh start <task_folder>
       implement-actions.sh preconditions <task_folder>
                            [--recipe <framework>=<path>]...
                            [--lookup-failed <framework>=<no-recipe|listing-unreachable|fetch-failed>]...
                            [--value <name>=<value>]...
       implement-actions.sh tests-brief  <task_folder> <unit_id>
       implement-actions.sh tests-freeze <task_folder> <unit_id>
                            [--test <path>::<test name>=<criterion id>[,<criterion id>...]]...
                            [--red <test name>=<path to a file holding what the run printed>]...
                            [--test-glob <glob>]...
                            [--checklist <criterion id>=<verification text>]...
                            [--green-on-arrival <test name>=<reason>]...
       implement-actions.sh build-brief  <task_folder> <unit_id>
       implement-actions.sh build-record <task_folder> <unit_id>
                            --interface <path to the record the builder wrote>
                            --report <path to the builder's report>
                            --started-at <commit the attempt began from>
                            [--suite <argv token>...]
                            [--order-tests <argv token>...]
                            [--nothing-ran <literal substring>]
       implement-actions.sh dispatch-open <task_folder> <role> <unit_id>
                            [--deny-read <path relative to codePath>]...
                            [--allow-write <path relative to codePath>]...
       implement-actions.sh dispatch-close <task_folder>
EOF
}

# ------------------------------------------------------------------------------------------------
# Small helpers, ported from research-actions.sh and design-actions.sh, which state the reasoning
# for each in their own headers.
# ------------------------------------------------------------------------------------------------

resolve_task_folder() {
  local arg="$1" who="$2" p
  [ -n "$arg" ] || die3 "$who: a task folder is required"
  p="$(cd "$arg" 2>/dev/null && pwd -P)" || die1 "$who: task folder not found: $arg"
  [ -f "$p/task.json" ] || die1 "$who: $p has no task.json; this is not a task folder"
  printf '%s' "$p"
}

# The temporary file is created beside the target, in the same directory, so mv is a rename
# within one filesystem and a failure partway never leaves a half-written file at $target.
write_atomic() {
  local target="$1" content="$2" dir tmp
  dir="$(dirname -- "$target")"
  tmp="$(mktemp "${dir}/.$(basename -- "$target").XXXXXX")" \
    || die3 "could not create a temporary file in $dir"
  printf '%s\n' "$content" > "$tmp" || { rm -f "$tmp"; die3 "could not write $tmp"; }
  mv -f "$tmp" "$target" || { rm -f "$tmp"; die3 "could not write $target"; }
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

# Resolves the project folder for a task folder shaped <projectPath>/tasks/<task-id>, per
# task-actions.sh's own task_dir_for. Prints the project path and returns 0, or prints nothing and
# returns 1, when two folders up holds no project.json. Never dies: callers decide the failure's
# meaning, since `read` reports it and `start` refuses on it.
resolve_project_folder() {
  local task_path="$1" p
  p="$(cd "$task_path/../.." 2>/dev/null && pwd -P)" || return 1
  [ -f "$p/project.json" ] || return 1
  printf '%s' "$p"
}

# Prints one of: missing, unreadable, ok, for the project.json under $1. Never dies: a caller
# decides the meaning. "unreadable" means not valid JSON; a well-formed file with no codePath
# field is "ok" with an empty value from project_code_path_value, a different fact the caller
# checks next. Missing and unreadable are never folded into the same word here.
project_code_path_state() {
  local f="$1/project.json"
  [ -f "$f" ] || { printf 'missing'; return; }
  [ -r "$f" ] || { printf 'unreadable'; return; }
  jq empty "$f" 2>/dev/null || { printf 'unreadable'; return; }
  printf 'ok'
}

# The codePath recorded in a project.json already known to be valid JSON, or empty when the field
# is absent or blank. Never dies. Call only after project_code_path_state prints "ok".
project_code_path_value() {
  jq -r '.codePath // empty' "$1/project.json" 2>/dev/null
}

is_git_repo() {
  command -v git >/dev/null 2>&1 || return 1
  git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1
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
# read: the current state, never a failure just because nothing has run yet.
# ------------------------------------------------------------------------------------------------

do_read() {
  [ "$#" -ge 1 ] || die3 "read: a task folder is required"
  [ "$#" -le 1 ] || die3 "read: unrecognized extra argument: $2"
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
          criteriaByRowState: ((.criteria // []) | group_by(.rowState) | map({key: .[0].rowState, value: length}) | from_entries)
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

  jq -n \
    --arg taskPath "$TASK_PATH" \
    --arg alignmentFile "$ALIGNMENT_FILE" \
    --arg alignmentState "$astate" \
    --arg designDir "$DESIGN_DIR" \
    --argjson designStarted "$design_started" \
    --argjson designFileCount "$design_file_count" \
    --arg projectPath "$project_path" \
    --arg projectNote "$project_note" \
    --arg codePath "$code_path" \
    --argjson gitChecked "$git_checked" \
    --argjson gitIsRepo "$git_is_repo" \
    --arg gitBranch "$git_branch" \
    --argjson trunkDerived "$trunk_derived" \
    --arg trunkBranch "$trunk_branch" \
    --arg trunkNote "$trunk_note" \
    --arg runMode "$run_mode" \
    --arg implementationDir "$IMPL_DIR" \
    --argjson snapshotExists "$snap_exists" \
    --argjson snapshotReadable "$snap_readable" \
    --arg snapshotNote "$snap_note" \
    --argjson snapshot "$snap_summary" \
    --argjson ledgerExists "$ledger_exists" \
    --argjson ledgerReadable "$ledger_readable" \
    --arg ledgerNote "$ledger_note" \
    --argjson ledger "$ledger_summary" \
    --argjson preconditionsExists "$precon_exists" \
    --argjson preconditionsReadable "$precon_readable" \
    --arg preconditionsNote "$precon_note" \
    '{
      taskPath: $taskPath,
      alignmentFile: $alignmentFile, alignmentState: $alignmentState,
      designDir: $designDir, designStarted: $designStarted, designFileCount: $designFileCount,
      project: { path: (if $projectPath == "" then null else $projectPath end),
                 codePath: (if $codePath == "" then null else $codePath end),
                 note: (if $projectNote == "" then null else $projectNote end) },
      git: { checked: $gitChecked, isRepo: $gitIsRepo,
             currentBranch: (if $gitBranch == "" then null else $gitBranch end),
             trunk: { derived: $trunkDerived,
                      branch: (if $trunkBranch == "" then null else $trunkBranch end),
                      note: $trunkNote } },
      runMode: $runMode,
      implementationDir: $implementationDir,
      snapshot: { exists: $snapshotExists, readable: $snapshotReadable, note: $snapshotNote, summary: $snapshot },
      ledger: { exists: $ledgerExists, readable: $ledgerReadable, note: $ledgerNote, summary: $ledger },
      preconditions: { exists: $preconditionsExists, readable: $preconditionsReadable, note: $preconditionsNote }
    }'
  exit 0
}

# ------------------------------------------------------------------------------------------------
# start: the first step of implementation. See this script's own header for the full sequence.
# ------------------------------------------------------------------------------------------------

do_start() {
  [ "$#" -ge 1 ] || die3 "start: a task folder is required"
  [ "$#" -le 1 ] || die3 "start: unrecognized extra argument: $2"
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
      die2 "start: $ALIGNMENT_FILE not found. Run the scope skill on this task before implementation can freeze a contract to build from."
      ;;
    unreadable)
      die10 "start: $ALIGNMENT_FILE exists but cannot be read as a contract (not valid JSON, not an object, or missing a required field). Fix it, or re-run the scope skill on this task, before implementation can freeze a contract to build from."
      ;;
  esac

  # --- step 2: design must have closed cleanly, on the live files -------------------------------
  [ -f "$CHECK_DESIGN_SCRIPT" ] || die3 "start: cannot find check-design.sh at $CHECK_DESIGN_SCRIPT"
  local design_stderr_file design_report_json design_rc design_stderr_text
  design_stderr_file="$(mktemp)" || die3 "start: could not create a temporary file"
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
      die4 "start: design has not closed cleanly. Finish design first. Open: $open_summary"
      ;;
    3)
      die3 "start: check-design.sh could not run: $design_stderr_text"
      ;;
    *)
      die3 "start: check-design.sh exited with an unexpected code $design_rc"
      ;;
  esac

  # --- step 3: read the live records once, and re-derive one hash over them together -------------
  local live_alignment_json live_workorders_json live_hash
  live_alignment_json="$(jq -c '.' "$ALIGNMENT_FILE" 2>/dev/null)"
  [ -n "$live_alignment_json" ] || die3 "start: $ALIGNMENT_FILE could not be re-read as JSON immediately after passing its own check"

  live_workorders_json="$(gather_workorders_json "$DESIGN_DIR")"
  if [ -n "$READ_FAILED" ]; then
    die3 "start: $READ_FAILED is under design/ but could not be read as JSON, even though check-design.sh just reported design closed cleanly"
  fi

  local live_hash_stderr_file live_hash_rc live_hash_stderr_text
  live_hash_stderr_file="$(mktemp)" || die3 "start: could not create a temporary file"
  live_hash="$(records_hash_for "$TASK_PATH" 2>"$live_hash_stderr_file")"
  live_hash_rc=$?
  live_hash_stderr_text="$(cat "$live_hash_stderr_file" 2>/dev/null)"
  rm -f "$live_hash_stderr_file"
  [ "$live_hash_rc" -eq 0 ] && [ -n "$live_hash" ] \
    || die3 "start: could not compute a hash over the live alignment.json and design/*.json: $live_hash_stderr_text"

  # --- step 4: the task's own project must point at a git repository ----------------------------
  local project_path code_path
  project_path="$(resolve_project_folder "$TASK_PATH")" \
    || die3 "start: could not resolve a project folder two levels up from $TASK_PATH, or it has no project.json"

  case "$(project_code_path_state "$project_path")" in
    missing)
      die3 "start: $project_path/project.json not found, though it was found moments ago. This is a bug, not an authoring mistake."
      ;;
    unreadable)
      die14 "start: $project_path/project.json exists but is not valid JSON, so its codePath cannot be read."
      ;;
    ok)
      code_path="$(project_code_path_value "$project_path")"
      [ -n "$code_path" ] || die3 "start: $project_path/project.json is valid JSON but has no usable codePath field."
      ;;
  esac

  command -v git >/dev/null 2>&1 || die3 "start: git is required and was not found on PATH"
  [ -d "$code_path" ] \
    || die15 "start: $project_path/project.json names codePath $code_path, which does not exist on disk."
  is_git_repo "$code_path" \
    || die5 "start: this task's project code at $code_path is not a git repository. Implementation builds in place there and needs a real repository to commit into."

  # --- step 5: codePath must be on a named branch, never a detached HEAD ------------------------
  local current_branch
  current_branch="$(git -C "$code_path" symbolic-ref --short -q HEAD 2>/dev/null)"
  [ -n "$current_branch" ] \
    || die16 "start: $code_path is not currently on a named branch (a detached HEAD, or the branch could not be read for another reason). A commit made there belongs to no branch, and this build must not risk that. Check out a real branch first."

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
    die6 "start: $code_path is currently on $trunk_branch, which is derived as its trunk branch. The build must not land there. Check out a branch other than $trunk_branch first."
  fi

  # --- step 7: the run mode is the task's own, never a flag on this call -------------------------
  local run_mode_raw run_mode
  run_mode_raw="$(jq -r 'if type == "object" and has("runMode") then (.runMode | tostring) else "__aida_absent__" end' "$TASK_PATH/task.json" 2>/dev/null)"
  case "$run_mode_raw" in
    __aida_absent__) run_mode="interactive" ;;
    autonomous) run_mode="autonomous" ;;
    interactive)
      die3 "start: $TASK_PATH/task.json declares runMode \"interactive\". The schema allows only \"autonomous\" there; absence already means interactive. Remove the field, or set it to \"autonomous\", by hand."
      ;;
    *)
      die3 "start: $TASK_PATH/task.json has an unusable runMode ('$run_mode_raw'); expected it absent or 'autonomous'."
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
      die3 "start: $SNAPSHOT_FILE exists but could not be read as JSON. This is a third fact, distinct from absent or readable, and is a refusal: repair or remove it by hand before running this again."
    fi
  fi

  local run_kind snapshot_hash_on_disk snapshot_alignment_json snapshot_workorders_json
  local drifted_orders_json='[]' contract_changed=false new_live_order_ids_json='[]'
  local drift_checked=false

  if [ "$snapshot_present" = "false" ]; then
    # ---- new run: design must be formally closed on exactly these live files --------------------
    run_kind="new"

    case "$(design_closed_state)" in
      missing)
        die11 "start: $CLOSED_FILE not found. Design has never closed. Run the design skill's close action on this task before implementation can freeze anything."
        ;;
      unreadable)
        die12 "start: $CLOSED_FILE exists but cannot be read as a close record (not valid JSON, not an object, or its hash field is missing or malformed). Close design again."
        ;;
    esac
    local closed_hash
    closed_hash="$(design_closed_hash)"
    [ "$closed_hash" = "$live_hash" ] \
      || die13 "start: $CLOSED_FILE recorded a hash over the contract and the work orders design closed on, and it disagrees with a hash just re-derived from the live alignment.json and design/*.json. Design changed after it closed. Close design again before implementation can freeze it."

    local wo_count
    wo_count="$(printf '%s' "$live_workorders_json" | jq 'length')"
    [ "$wo_count" -gt 0 ] \
      || die7 "start: design/ under $TASK_PATH has no work orders. There is nothing for implementation to build. (A contract with no criteria closes design with none; add criteria and redesign, or this task has nothing to implement.)"

    [ ! -e "$LEDGER_FILE" ] \
      || die3 "start: $LEDGER_FILE already exists but $SNAPSHOT_FILE does not. A ledger with no snapshot beside it is not a supported state; remove $LEDGER_FILE by hand if this task is meant to start fresh, or restore the snapshot it was opened against."

    [ ! -e "$SNAPSHOT_FILE" ] \
      || die3 "start: $SNAPSHOT_FILE appeared between this script's own presence check and its own write. Another start call on this task finished first and won that race; this call lost it normally. Re-run read to see what the winner produced."

    mkdir -p "$IMPL_DIR" || die3 "start: could not create $IMPL_DIR"

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
    [ -n "$snapshot_hash_on_disk" ] || die3 "start: $SNAPSHOT_FILE has no usable hash field"

    local self_hash
    self_hash="$(snapshot_self_hash "$snapshot_alignment_json" "$snapshot_workorders_json")" \
      || die3 "start: could not re-derive a hash from $SNAPSHOT_FILE's own alignment and workOrders fields (see stderr above)"
    [ "$self_hash" = "$snapshot_hash_on_disk" ] \
      || die17 "start: $SNAPSHOT_FILE's own hash field ($snapshot_hash_on_disk) disagrees with a hash re-derived from its own alignment and workOrders fields ($self_hash). The snapshot file was edited after it was written; restore it from git history, or remove it and accept that the frozen state is lost. Never edit it by hand."

    if [ "$live_hash" != "$snapshot_hash_on_disk" ]; then
      contract_changed="$(jq -n --argjson a "$snapshot_alignment_json" --argjson b "$live_alignment_json" \
        'if $a == $b then false else true end')"
      drifted_orders_json="$(jq -n --argjson snap "$snapshot_workorders_json" --argjson live "$live_workorders_json" '
          ($live | map({(.id): .}) | add // {}) as $liveMap
          | [ $snap[] | . as $s
              | ($liveMap[$s.id]) as $l
              | if ($l == null) then
                  {id: $s.id, reason: ("the design file for " + $s.id + " no longer exists, or could not be read, since the snapshot was taken")}
                elif ($l != $s) then
                  {id: $s.id, reason: ("the design file for " + $s.id + " has changed since the snapshot was taken")}
                else
                  empty
                end
            ]
        ')"
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
    die8 "start: the build order could not be derived from the frozen work orders: $msg"
  fi

  # --- step 11: capture the commit the build starts from -------------------------------------------
  local started_from started_from_rc
  started_from="$(git -C "$code_path" rev-parse HEAD 2>/dev/null)"
  started_from_rc=$?
  [ "$started_from_rc" -eq 0 ] && [ -n "$started_from" ] \
    || die3 "start: could not capture the current commit (git rev-parse HEAD failed in $code_path). An empty repository with no commit yet has nothing to roll back to."

  # --- step 12: open the ledger, or reopen it -------------------------------------------------------
  local ledger_present ledger_doc opened_as
  ledger_present=false
  ledger_doc=""
  if [ -f "$LEDGER_FILE" ]; then
    if [ -r "$LEDGER_FILE" ] && ledger_doc="$(jq -c '.' "$LEDGER_FILE" 2>/dev/null)" && [ -n "$ledger_doc" ]; then
      ledger_present=true
    else
      die3 "start: $LEDGER_FILE exists but could not be read as JSON. Repair or remove it by hand before running this again."
    fi
  fi

  local final_orders_json final_criteria_json ledger_started_from ledger_run_mode
  if [ "$ledger_present" = "true" ]; then
    opened_as="reopened"
    local stored_snapshot_hash
    stored_snapshot_hash="$(printf '%s' "$ledger_doc" | jq -r '.snapshotHash // empty')"
    [ "$stored_snapshot_hash" = "$snapshot_hash_on_disk" ] \
      || die9 "start: $LEDGER_FILE was opened against a different snapshot (its snapshotHash is $stored_snapshot_hash) than the one now on disk (hash $snapshot_hash_on_disk). A ledger and a snapshot that do not belong together are never read as a pair; investigate before proceeding."

    ledger_started_from="$(ledger_required_string "$ledger_doc" "startedFrom")" \
      || die3 "start: $LEDGER_FILE is damaged (see stderr above). Repair or remove it by hand before running this again."
    ledger_run_mode="$(ledger_required_string "$ledger_doc" "runMode")" \
      || die3 "start: $LEDGER_FILE is damaged (see stderr above). Repair or remove it by hand before running this again."

    final_orders_json="$(printf '%s' "$ledger_doc" | jq -c --argjson drifted "$drifted_orders_json" '
        .orders | map(
          . as $o
          | (([ $drifted[] | select(.id == $o.id) | .reason ])[0]) as $r
          | if $r != null then ($o + {haltedBecause: $r}) else $o end
        )
      ')"
    final_criteria_json="$(printf '%s' "$ledger_doc" | jq -c '.criteria')"
  else
    opened_as="opened"
    ledger_started_from="$started_from"
    ledger_run_mode="$run_mode"

    local base_orders_json
    base_orders_json="$(printf '%s' "$snapshot_workorders_json" | jq -c '[ .[] | {id: .id, lastStep: null, attemptsUsed: 0, roundsUsed: 0} ]')"
    final_orders_json="$(jq -n --argjson orders "$base_orders_json" --argjson drifted "$drifted_orders_json" '
        $orders | map(
          . as $o
          | (([ $drifted[] | select(.id == $o.id) | .reason ])[0]) as $r
          | if $r != null then ($o + {haltedBecause: $r}) else $o end
        )
      ')"
    final_criteria_json="$(printf '%s' "$snapshot_criteria_json" | jq -c '[ .[] | {id: .id, rowState: "not-judged"} ]')"
  fi

  mkdir -p "$IMPL_DIR" || die3 "start: could not create $IMPL_DIR"
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

  echo "RUN: ${run_kind} (ledger ${opened_as})"
  jq -n \
    --arg taskPath "$TASK_PATH" --arg codePath "$code_path" \
    --arg runMode "$run_mode" --arg runKind "$run_kind" \
    --argjson trunkDerived "$trunk_derived" --arg trunkBranch "$trunk_branch" --arg trunkNote "$trunk_note" \
    --arg currentBranch "$current_branch" \
    --arg snapshotFile "$SNAPSHOT_FILE" --arg snapshotHash "$snapshot_hash_on_disk" \
    --argjson workOrderCount "$(printf '%s' "$snapshot_workorders_json" | jq 'length')" \
    --argjson criteriaCount "$(printf '%s' "$snapshot_criteria_json" | jq 'length')" \
    --argjson driftChecked "$drift_checked" \
    --argjson contractChanged "$contract_changed_json" \
    --argjson driftedOrders "$drifted_orders_json" \
    --argjson newLiveOrderIds "$new_live_order_ids_json" \
    --arg ledgerFile "$LEDGER_FILE" --arg ledgerOpenedAs "$opened_as" --arg startedFrom "$started_from" \
    --argjson readyToBuild "$ready_ids_json" --argjson halted "$halted_json" --argjson inFlight "$in_flight_json" \
    '{
      taskPath: $taskPath, codePath: $codePath,
      runMode: $runMode, runKind: $runKind,
      trunkCheck: { derived: $trunkDerived,
                    branch: (if $trunkBranch == "" then null else $trunkBranch end),
                    currentBranch: $currentBranch,
                    note: $trunkNote },
      snapshot: { file: $snapshotFile, hash: $snapshotHash, workOrderCount: $workOrderCount, criteriaCount: $criteriaCount },
      drift: { checked: $driftChecked, contractChanged: $contractChanged, driftedOrders: $driftedOrders, newLiveOrdersNotInSnapshot: $newLiveOrderIds },
      ledger: { file: $ledgerFile, openedAs: $ledgerOpenedAs, startedFrom: $startedFrom, halted: $halted, inFlight: $inFlight },
      readyToBuild: $readyToBuild
    }'
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
# analysis and the security tool have no recipe naming a tool for any of them yet, so all three are
# recorded `undeclared` with a reason saying so, never guessed from the project and never invented.
# The scope, the union of every work order's own `ownedFiles` from the snapshot, is recorded too,
# even though nothing here reads it yet: it is what the three undeclared tools will scope to once a
# recipe names one, and it is deliberately not what the suite scopes to, because at this point the
# orders' own tests do not exist and no framework declares a command mapping paths to the tests
# that cover them. The baseline never changes this run's own verdict or its exit code: a suite that
# is already red here is a fact worth recording, not a reason to refuse.
# ------------------------------------------------------------------------------------------------

pc_trim() { printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }

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

# True when the file at $1 holds the literal string $2 anywhere in it. The needle is quoted inside
# the pattern, so nothing in it is read as a glob.
pc_output_holds() {
  local haystack
  haystack="$(cat "$1" 2>/dev/null)"
  case "$haystack" in
    *"$2"*) return 0 ;;
  esac
  return 1
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
  ' >>"$out" || die3 "preconditions: could not record the entry $PC_ID"
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
# ------------------------------------------------------------------------------------------------

# The count of leading whitespace characters in $1. Used only to tell a folded scalar's own
# continuation lines (indented further than the key that opened them) from the line that ends it
# (indented the same or less). A bracket-expression glob against a parameter expansion, never a
# regular expression, so it stays inside this file's own portability rule.
tc_indent() {
  local line="$1" lead
  lead="${line%%[^[:space:]]*}"
  printf '%s' "${#lead}"
}

# The entry being read, held between lines, the same reason PC_* is held between lines above.
TC_ID=""; TC_ARGV_RAW=""; TC_COST=""; TC_ABSENT=0; TC_NEAREST_RAW=""

# Appends one JSON object to $1 for the held row and clears it, so a second call with nothing held
# writes nothing. `argv` and `nearest` are read as JSON, through jq, never split by hand; a value
# that is present but does not parse as an array of strings is not dropped, it is named in
# `unreadable`, because a malformed row in a recipe is a defect worth reporting, not a reason to
# report fewer rows than the recipe wrote. `absent` is a boolean fact, true whenever the row
# carried an `absent:` key at all; its own folded prose is never read here, only its presence.
tc_flush_entry() {
  local out="$1"
  [ -n "$TC_ID" ] || return 0
  local argv_json='null' cost="$TC_COST" nearest_json='null' unreadable='[]' parsed
  if [ -n "$TC_ARGV_RAW" ]; then
    parsed="$(printf '%s' "$TC_ARGV_RAW" | jq -e -c 'if (type == "array") and (all(.[]; type == "string")) then . else empty end' 2>/dev/null)"
    if [ -n "$parsed" ]; then
      argv_json="$parsed"
    else
      unreadable="$(printf '%s' "$unreadable" | jq -c '. + ["argv"]')"
    fi
  fi
  if [ -n "$TC_NEAREST_RAW" ]; then
    parsed="$(printf '%s' "$TC_NEAREST_RAW" | jq -e -c 'if (type == "array") and (all(.[]; type == "string")) then . else empty end' 2>/dev/null)"
    if [ -n "$parsed" ]; then
      nearest_json="$parsed"
    else
      unreadable="$(printf '%s' "$unreadable" | jq -c '. + ["nearest"]')"
    fi
  fi
  jq -n --arg id "$TC_ID" --argjson argv "$argv_json" --arg cost "$cost" \
        --argjson absent "$([ "$TC_ABSENT" = "1" ] && printf true || printf false)" \
        --argjson nearest "$nearest_json" --argjson unreadable "$unreadable" '
    {id: $id}
    + (if $argv       == null  then {} else {argv: $argv} end)
    + (if $cost       == ""    then {} else {cost: $cost} end)
    + (if $absent     == false then {} else {absent: true} end)
    + (if $nearest    == null  then {} else {nearest: $nearest} end)
    + (if ($unreadable | length) == 0 then {} else {unreadable: $unreadable} end)
  ' >>"$out" || die3 "preconditions: could not record the test-command row $TC_ID"
  TC_ID=""; TC_ARGV_RAW=""; TC_COST=""; TC_ABSENT=0; TC_NEAREST_RAW=""
}

# Reads the `## Test commands` section of the recipe at $1, appending one JSON object per row to
# $2. Prints the section's own state: `undeclared` when the heading is absent (no key either,
# because there is nowhere for one to be), `unparseable` when the heading is there but
# `test_commands:` never opens under it (the same shape a misspelled key leaves), or `ok` when the
# key is there, however many rows it holds. Never runs a check and never substitutes a placeholder;
# this function only reads what the recipe wrote.
tc_parse_recipe() {
  local recipe_file="$1" out="$2"
  local section_file block_file line trimmed indent skip_indent

  section_file="$out.tcsection"
  sed -n '/^##[[:space:]]*Test commands[[:space:]]*$/,/^##[[:space:]]/p' "$recipe_file" >"$section_file" 2>/dev/null
  if [ ! -s "$section_file" ]; then
    rm -f "$section_file"
    printf 'undeclared'
    return 0
  fi

  if ! grep -q '^test_commands:' "$section_file"; then
    rm -f "$section_file"
    printf 'unparseable'
    return 0
  fi

  block_file="$out.tcblock"
  sed -n '/^test_commands:/,$p' "$section_file" | sed '1d' >"$block_file"
  rm -f "$section_file"

  TC_ID=""; TC_ARGV_RAW=""; TC_COST=""; TC_ABSENT=0; TC_NEAREST_RAW=""
  skip_indent=-1
  while IFS= read -r line; do
    trimmed="$(pc_trim "$line")"
    # A folded scalar (`trap:`, `id_form:`, or `absent:`'s own text) continues on every following
    # line indented further than the key that opened it. Those lines are prose for a person and a
    # model reading the recipe itself; they are skipped here, never parsed as a new field or a new
    # row. A blank line inside or around the block stays in skip mode rather than ending it, since
    # a folded scalar may carry a paragraph break.
    if [ "$skip_indent" -ge 0 ]; then
      [ -n "$trimmed" ] || continue
      indent="$(tc_indent "$line")"
      if [ "$indent" -gt "$skip_indent" ]; then continue; fi
      skip_indent=-1
    fi
    [ -n "$trimmed" ] || continue
    case "$trimmed" in
      '##'*) break ;;
    esac
    case "$trimmed" in
      '- id:'*)   tc_flush_entry "$out"; TC_ID="$(pc_trim "${trimmed#- id:}")" ;;
      'argv:'*)   TC_ARGV_RAW="$(pc_trim "${trimmed#argv:}")" ;;
      'cost:'*)   TC_COST="$(pc_trim "${trimmed#cost:}")" ;;
      'nearest:'*) TC_NEAREST_RAW="$(pc_trim "${trimmed#nearest:}")" ;;
      'absent:'*)
        TC_ABSENT=1
        case "$trimmed" in *'>-') skip_indent="$(tc_indent "$line")" ;; esac
        ;;
      'trap:'*)
        case "$trimmed" in *'>-') skip_indent="$(tc_indent "$line")" ;; esac
        ;;
      'id_form:'*)
        case "$trimmed" in *'>-') skip_indent="$(tc_indent "$line")" ;; esac
        ;;
    esac
  done <"$block_file"
  tc_flush_entry "$out"
  rm -f "$block_file"

  printf 'ok'
}

# The value a caller's --value flags supplied for placeholder $2, read from $1, the same
# tab-separated multi-line shape --recipe and --lookup-failed already build. Prints nothing and
# returns 1 when no --value named it, so a caller can tell "supplied, empty" from "never supplied";
# tc_run_smoke below only ever calls this after already confirming the name is present.
tc_value_for() {
  printf '%s' "$1" | grep "^$2	" | head -n 1 | cut -f2-
}

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
        if printf '%s' "$values" | grep -q "^$name	"; then
          tok="$(tc_value_for "$values" "$name")"
        else
          printf 'UNRESOLVED\t%s' "$name"
          return 0
        fi
        ;;
    esac
    set -- "$@" "$tok"
    i=$((i + 1))
  done
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
      row_json="$(printf '%s' "$fw_obj" | jq -c '[ .testCommands.rows[] | select(.id == "suite") ][0] // null')"
      if [ "$row_json" = "null" ]; then
        verdict="unknown"
        reason="this framework's recipe carries no test-commands row with id suite"
      elif [ "$(printf '%s' "$row_json" | jq -r '.absent // false')" = "true" ]; then
        verdict="unknown"
        reason="this framework's recipe declares its suite row absent; there is nothing whole to run"
      elif printf '%s' "$row_json" | jq -e '(.unreadable // []) | index("argv")' >/dev/null 2>&1; then
        verdict="unknown"
        reason="the suite row's argv did not parse as a JSON array of strings"
      else
        argv_json="$(printf '%s' "$row_json" | jq -c '.argv // empty')"
        if [ -z "$argv_json" ] || [ "$argv_json" = "null" ]; then
          verdict="unknown"
          reason="this framework's suite row declares no argv to run"
        else
          out_file="$(dirname -- "$out")/.baseline-suite-run.$$"
          result="$(tc_run_smoke "$argv_json" "$codepath" "$out_file" "$values")"
          kind="$(printf '%s' "$result" | cut -f1)"
          payload="$(printf '%s' "$result" | cut -f2-)"
          if [ "$kind" = "UNRESOLVED" ]; then
            verdict="unknown"
            reason="the token {$payload} in the suite command has no supplied value; pass --value $payload=<value>"
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
    fi
    jq -n --arg framework "$fw" --arg verdict "$verdict" --arg reason "$reason" \
          --arg output "$output" --argjson truncated "$truncated" --argjson exitCode "$exit_code_json" '
      {framework: $framework, verdict: $verdict}
      + (if $reason   == ""   then {} else {reason: $reason} end)
      + (if $exitCode == null then {} else {exitCode: $exitCode} end)
      + (if $output   == ""   then {} else {output: $output} end)
      + (if $truncated == true then {truncated: true} else {} end)
    ' >>"$out" || die3 "preconditions: could not record the baseline suite result for framework $fw"
    i=$((i + 1))
  done
}

# The step. Every framework the project declares must be answered for, because the build runs in
# one repository that is all of them at once.
do_preconditions() {
  local task_folder="" project_folder codepath project_state
  local recipes="" failures="" values="" arg fw val
  local frameworks fw_count entries_file fw_json_file tc_rows_file
  local lookup recipe_path section_state fw_verdict entries_json run_verdict
  local tc_state tc_rows_json
  local smoke_verdict smoke_reason smoke_output smoke_truncated smoke_exit_code_json
  local smoke_row_json smoke_argv_json smoke_out_file smoke_result smoke_kind smoke_payload
  local smoke_raw_len smoke_json
  local record_file record_json today
  local baseline_status baseline_note baseline_commit_report baseline_summary_json
  local ledger_doc ledger_started_from
  local snapshot_doc scope_json suite_json_file suite_json baseline_json existing_commit

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --recipe)
        [ "$#" -ge 2 ] || die3 "preconditions: --recipe needs <framework>=<path>"
        case "$2" in *=*) ;; *) die3 "preconditions: --recipe takes <framework>=<path>, got: $2" ;; esac
        recipes="$recipes$(printf '%s' "$2" | sed 's/=/\t/')
"
        shift 2 ;;
      --lookup-failed)
        [ "$#" -ge 2 ] || die3 "preconditions: --lookup-failed needs <framework>=<reason>"
        case "$2" in *=*) ;; *) die3 "preconditions: --lookup-failed takes <framework>=<reason>, got: $2" ;; esac
        val="${2#*=}"
        case "$val" in
          no-recipe|listing-unreachable|fetch-failed) ;;
          *) die3 "preconditions: a lookup failure is no-recipe, listing-unreachable or fetch-failed, not: $val" ;;
        esac
        failures="$failures$(printf '%s' "$2" | sed 's/=/\t/')
"
        shift 2 ;;
      --value)
        [ "$#" -ge 2 ] || die3 "preconditions: --value needs <name>=<value>"
        case "$2" in *=*) ;; *) die3 "preconditions: --value takes <name>=<value>, got: $2" ;; esac
        values="$values$(printf '%s' "$2" | sed 's/=/\t/')
"
        shift 2 ;;
      -*) die3 "preconditions: unrecognized argument: $1" ;;
      *)
        [ -z "$task_folder" ] || die3 "preconditions: more than one task folder given"
        task_folder="$1"; shift ;;
    esac
  done

  task_folder="$(resolve_task_folder "$task_folder" "preconditions")"

  # This step belongs to a run, so a run must have opened. Writing a record for a build that never
  # started would leave a file nothing can be read against.
  [ -f "$task_folder/implementation/snapshot.json" ] && [ -f "$task_folder/implementation/ledger.json" ] \
    || die20 "preconditions: this task has no started build; run \`start\` first"

  project_folder="$(resolve_project_folder "$task_folder")" \
    || die3 "preconditions: the task folder is not inside a project, so no framework is known"
  project_state="$(project_code_path_state "$project_folder")"
  case "$project_state" in
    unreadable) die14 "preconditions: $project_folder/project.json is not valid JSON" ;;
    missing)    die3  "preconditions: $project_folder has no project.json" ;;
  esac
  codepath="$(project_code_path_value "$project_folder")"
  [ -n "$codepath" ] || die3 "preconditions: project.json records no codePath, so no check has anywhere to run"
  [ -d "$codepath" ] || die15 "preconditions: the recorded codePath does not exist on disk: $codepath"

  frameworks="$(jq -r '.frameworks // [] | .[]' "$project_folder/project.json" 2>/dev/null)"
  [ -n "$frameworks" ] || die14 "preconditions: project.json records no frameworks, so no recipe can be chosen"

  entries_file="$task_folder/implementation/.preconditions-entries.$$"
  tc_rows_file="$task_folder/implementation/.preconditions-testcommands.$$"
  fw_json_file="$task_folder/implementation/.preconditions-frameworks.$$"
  : >"$fw_json_file"
  run_verdict="met"

  # A framework the caller answered for neither way is a caller that did not look. Guessing here
  # would turn a lookup nobody ran into a recipe that declared nothing.
  printf '%s\n' "$frameworks" | while IFS= read -r fw; do
    [ -n "$fw" ] || continue
    recipe_path="$(printf '%s' "$recipes" | grep "^$fw	" | head -n 1 | cut -f2-)"
    lookup=""
    if [ -n "$recipe_path" ]; then
      lookup="resolved"
    else
      lookup="$(printf '%s' "$failures" | grep "^$fw	" | head -n 1 | cut -f2-)"
      [ -n "$lookup" ] || die18 "preconditions: nothing was said about the recipe for framework $fw; pass --recipe or --lookup-failed"
    fi

    : >"$entries_file"
    : >"$tc_rows_file"
    if [ "$lookup" = "resolved" ]; then
      [ -f "$recipe_path" ] || die3 "preconditions: the recipe handed over for $fw is not a file: $recipe_path"
      section_state="$(pc_parse_recipe "$recipe_path" "$entries_file" "$codepath")"
      case "$section_state" in
        undeclared)     fw_verdict="undeclared" ;;
        declared-empty) fw_verdict="undeclared" ;;
        unparseable)    fw_verdict="unknown" ;;
        *)              fw_verdict="met" ;;
      esac
      # The test-commands block never affects a verdict; it is read here only because it lives in
      # the same recipe file this framework already resolved, and the record already has a place
      # for the rest of what that recipe declared.
      tc_state="$(tc_parse_recipe "$recipe_path" "$tc_rows_file")"
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
    ' >>"$fw_json_file" || die3 "preconditions: could not record the result for framework $fw"
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
  ' "$fw_json_file")" || die3 "preconditions: could not assemble the record"
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
      LEDGER_FILE="$task_folder/implementation/ledger.json"
      ledger_doc="$(jq -c '.' "$LEDGER_FILE" 2>/dev/null)"
      [ -n "$ledger_doc" ] \
        || die3 "preconditions: $LEDGER_FILE exists but could not be read as JSON, though \`start\` already wrote it. Repair or remove it by hand before running this again."
      ledger_started_from="$(ledger_required_string "$ledger_doc" "startedFrom")" \
        || die3 "preconditions: $LEDGER_FILE is damaged (see stderr above). Repair or remove it by hand before running this again."
      baseline_commit_report="$ledger_started_from"

      case "$(bl_state)" in
        missing)
          snapshot_doc="$(jq -c '.' "$task_folder/implementation/snapshot.json" 2>/dev/null)"
          [ -n "$snapshot_doc" ] \
            || die3 "preconditions: $task_folder/implementation/snapshot.json exists but could not be read as JSON, though \`start\` already wrote it. Repair or remove it by hand before running this again."
          scope_json="$(printf '%s' "$snapshot_doc" | jq -c '[ (.workOrders // [])[] | (.ownedFiles // [])[] ] | unique')"

          suite_json_file="$task_folder/implementation/.baseline-suite.$$"
          : >"$suite_json_file"
          bl_run_suite "$record_json" "$codepath" "$values" "$suite_json_file"
          suite_json="$(jq -s '.' "$suite_json_file" 2>/dev/null)" || suite_json="[]"
          rm -f "$suite_json_file"

          baseline_json="$(jq -n \
            --arg takenAt "$today" --arg commit "$ledger_started_from" \
            --argjson scope "$scope_json" --argjson suite "$suite_json" \
            --arg csReason "no recipe names a coding-standards tool for this framework, at this point in the process" \
            --arg saReason "no recipe names a static-analysis tool for this framework, at this point in the process" \
            --arg secReason "no recipe names a security tool for this framework, at this point in the process" \
            '{
              schemaVersion: 1, takenAt: $takenAt, commit: $commit, scope: $scope, suite: $suite,
              codingStandards: {verdict: "undeclared", reason: $csReason},
              staticAnalysis:  {verdict: "undeclared", reason: $saReason},
              security:        {verdict: "undeclared", reason: $secReason}
            }')" || die3 "preconditions: could not assemble the baseline record"
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
            die21 "preconditions: $BASELINE_FILE already holds a baseline taken at commit $existing_commit, but this run's own ledger started from a different commit, $ledger_started_from. A baseline is taken once, at the commit the build started from, and never retaken after that: retaking it here would measure the wrong repository state. Investigate before proceeding; remove $BASELINE_FILE by hand only if this task's baseline is meant to start over."
          fi
          ;;
        unreadable)
          die3 "preconditions: $BASELINE_FILE exists but could not be read as a baseline record (not valid JSON, not an object, or its commit field is missing or malformed). Repair or remove it by hand before running this again."
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

  jq -n --arg verdict "$run_verdict" --arg record "$record_file" --argjson report "$record_json" \
        --arg baselineFile "$BASELINE_FILE" --arg baselineStatus "$baseline_status" \
        --arg baselineNote "$baseline_note" --arg baselineCommit "$baseline_commit_report" \
        --argjson baselineSummary "$baseline_summary_json" '
    {
      verdict: $verdict,
      record: $record,
      frameworks: ($report.frameworks | map({
        framework: .framework,
        lookup: .lookup,
        verdict: .verdict,
        unmet:   [.entries[] | select(.verdict == "unmet")   | {id, what, owner}],
        unknown: [.entries[] | select(.verdict == "unknown") | {id, what, owner, reason}],
        testCommands: {
          state: .testCommands.state,
          unreadable: [ .testCommands.rows[] | select((.unreadable // []) | length > 0) | {id, unreadable} ]
        },
        smoke: .smoke
      })),
      baseline: {
        file: $baselineFile,
        status: $baselineStatus,
        note: $baselineNote,
        commit: (if $baselineCommit == "" then null else $baselineCommit end),
        summary: $baselineSummary
      }
    }'

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
# list), and CRITERIA_JSON (the full frozen criterion record for each). Exits directly (die22 or
# die3) rather than returning a code, because every caller of this helper treats both problems as
# fatal and would only turn around and exit itself.
UNIT_JSON=""; CRITERIA_IDS_JSON="[]"; CRITERIA_JSON="[]"
tt_load_unit_and_criteria() {
  local snapshot_doc="$1" unit_id="$2" who="$3"
  UNIT_JSON="$(printf '%s' "$snapshot_doc" | jq -c --arg id "$unit_id" \
    '(.workOrders // []) | map(select(.id == $id)) | .[0] // null')"
  [ "$UNIT_JSON" != "null" ] || die22 "$who: $unit_id is not in the frozen copy."

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
      || die3 "$who: $unit_id names criterion $id, which is not in the frozen contract."
    CRITERIA_JSON="$(printf '%s' "$CRITERIA_JSON" | jq -c --argjson c "$one" '. + [$c]')"
    j=$((j + 1))
  done
}

# Reads the frozen snapshot beside <task_folder>/implementation, dying (die25 missing, die3
# unreadable) when it is not ready. Sets SNAPSHOT_DOC. Shared by tests-brief and tests-freeze,
# which both refuse for the same reason on the same missing file.
SNAPSHOT_DOC=""
tt_load_snapshot() {
  local who="$1"
  local snapshot_file="$IMPL_DIR/snapshot.json"
  [ -f "$snapshot_file" ] \
    || die25 "$who: $snapshot_file not found. This step ran before start, so there is no frozen copy. Run start on this task first."
  SNAPSHOT_DOC="$(jq -c '.' "$snapshot_file" 2>/dev/null)"
  [ -n "$SNAPSHOT_DOC" ] \
    || die3 "$who: $snapshot_file exists but could not be read as JSON, though start already wrote it. Repair or remove it by hand before running this again."
}

do_tests_brief() {
  [ "$#" -ge 2 ] || die3 "tests-brief: a task folder and a unit id are required"
  [ "$#" -le 2 ] || die3 "tests-brief: unrecognized extra argument: $3"
  local resolve_rc unit_id="$2"
  TASK_PATH="$(resolve_task_folder "$1" "tests-brief")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  IMPL_DIR="$TASK_PATH/implementation"

  tt_load_snapshot "tests-brief"
  local ledger_file="$IMPL_DIR/ledger.json"
  [ -f "$ledger_file" ] \
    || die3 "tests-brief: $ledger_file not found, though $IMPL_DIR/snapshot.json exists. A snapshot with no ledger beside it is not a supported state; run start again."
  local ledger_doc
  ledger_doc="$(jq -c '.' "$ledger_file" 2>/dev/null)"
  [ -n "$ledger_doc" ] \
    || die3 "tests-brief: $ledger_file exists but could not be read as JSON. Repair or remove it by hand before running this again."

  tt_load_unit_and_criteria "$SNAPSHOT_DOC" "$unit_id" "tests-brief"

  # --- exit 23: every dependency needs a completion record before its interface is handed over ----
  local depends_json dep_count i dep_id dep_entry dep_step dependency_interfaces_json='[]'
  depends_json="$(printf '%s' "$UNIT_JSON" | jq -c '.dependsOn // []')"
  dep_count="$(printf '%s' "$depends_json" | jq 'length')"
  i=0
  while [ "$i" -lt "$dep_count" ]; do
    dep_id="$(printf '%s' "$depends_json" | jq -r --argjson i "$i" '.[$i]')"
    dep_entry="$(printf '%s' "$ledger_doc" | jq -c --arg id "$dep_id" \
      '(.orders // []) | map(select(.id == $id)) | .[0] // null')"
    [ "$dep_entry" != "null" ] \
      || die3 "tests-brief: $unit_id depends on $dep_id, which has no entry in $ledger_file, though start opens one entry per snapshot work order."
    dep_step="$(printf '%s' "$dep_entry" | jq -r '.lastStep // "not started"')"
    if [ "$dep_step" = "closed" ]; then
      local dep_interface
      dep_interface="$(printf '%s' "$SNAPSHOT_DOC" | jq -r --arg id "$dep_id" \
        '(.workOrders // []) | map(select(.id == $id)) | .[0].interface // ""')"
      dependency_interfaces_json="$(printf '%s' "$dependency_interfaces_json" | jq -c \
        --arg id "$dep_id" --arg iface "$dep_interface" '. + [{id: $id, interface: $iface}]')"
    else
      die23 "tests-brief: $unit_id depends on $dep_id, which has no completion record ($ledger_file records its last step as $dep_step), so its interface record does not exist yet."
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
      || die24 "tests-brief: $unit_id owns $owned_machine_unmet, whose verifiedBy is machine, and declares no test in its own tests field."
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

  jq -n --argjson unit "$unit_out" --argjson criteria "$criteria_out" \
        --argjson nonGoals "$non_goals_out" --argjson dependencyInterfaces "$dependency_interfaces_json" \
    '{unit: $unit, criteria: $criteria, nonGoals: $nonGoals, dependencyInterfaces: $dependencyInterfaces}'
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
      *) die3 "tests-freeze: --test value has no '::' separating the path from the test name: $line" ;;
    esac
    p="${line%%::*}"
    rest="${line#*::}"
    case "$rest" in
      *"="*) : ;;
      *) die3 "tests-freeze: --test value has no '=' separating the test name from its criteria: $line" ;;
    esac
    name="${rest%%=*}"
    csv="${rest#*=}"
    [ -n "$p" ]    || die3 "tests-freeze: --test value has an empty path: $line"
    [ -n "$name" ] || die3 "tests-freeze: --test value has an empty test name: $line"
    [ -n "$csv" ]  || die3 "tests-freeze: --test value names no criterion: $line"
    ids_json="$(printf '%s' "$csv" | tr ',' '\n' | jq -R -s 'split("\n") | map(select(length>0))')"
    jq -n --arg path "$p" --arg name "$name" --argjson criteria "$ids_json" \
      '{path: $path, name: $name, criteria: $criteria}' >>"$out" \
      || die3 "tests-freeze: could not record the --test row for $name"
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
      *) die3 "tests-freeze: --red value has no '=' separating the test name from the file path: $line" ;;
    esac
    name="${line%%=*}"
    p="${line#*=}"
    [ -n "$name" ] || die3 "tests-freeze: --red value has an empty test name: $line"
    [ -n "$p" ]    || die3 "tests-freeze: --red value has an empty file path: $line"
    jq -n --arg name "$name" --arg path "$p" '{name: $name, path: $path}' >>"$out" \
      || die3 "tests-freeze: could not record the --red row for $name"
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
      *) die3 "tests-freeze: --checklist value has no '=' separating the criterion id from the verification text: $line" ;;
    esac
    id="${line%%=*}"
    text="${line#*=}"
    [ -n "$id" ]   || die3 "tests-freeze: --checklist value has an empty criterion id: $line"
    [ -n "$text" ] || die3 "tests-freeze: --checklist value has empty verification text: $line"
    jq -n --arg id "$id" --arg text "$text" '{id: $id, text: $text}' >>"$out" \
      || die3 "tests-freeze: could not record the --checklist row for $id"
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
      *) die3 "tests-freeze: --green-on-arrival value has no '=' separating the test name from the reason: $line" ;;
    esac
    name="${line%%=*}"
    reason="${line#*=}"
    [ -n "$name" ]   || die3 "tests-freeze: --green-on-arrival value has an empty test name: $line"
    [ -n "$reason" ] || die3 "tests-freeze: --green-on-arrival value has an empty reason: $line"
    jq -n --arg name "$name" --arg reason "$reason" '{name: $name, reason: $reason}' >>"$out" \
      || die3 "tests-freeze: could not record the --green-on-arrival row for $name"
  done <<TF_EOF
$raw
TF_EOF
}

# The sha256 of file $1, lowercase hex, through the same tool records-hash.sh already resolved into
# RECORDS_HASH_SHA256_CMD: one place decides which of sha256sum or `shasum -a 256` exists, and nothing
# here carries a second copy of that decision.
tf_sha256_of() {
  "${RECORDS_HASH_SHA256_CMD[@]}" <"$1" 2>/dev/null | cut -d' ' -f1
}

# True when path $1 matches the case glob $2. bash always treats an unquoted variable used as a
# case pattern as a glob; zsh, by default, does not, and matches it as the literal text instead
# (Honesty: this script runs under both). GLOB_SUBST restores the glob reading, scoped to the
# subshell this runs in only, the same discipline pc_run_check already applies to SH_WORD_SPLIT, so
# it never changes how the rest of the script's own case statements behave.
tf_path_matches_glob() {
  (
    if [ -n "${ZSH_VERSION:-}" ]; then
      setopt GLOB_SUBST 2>/dev/null
    fi
    case "$1" in
      $2) exit 0 ;;
      *)  exit 1 ;;
    esac
  )
}

# The text of $1 up to its first "/", or all of $1 when it holds none.
tf_first_segment() {
  case "$1" in
    */*) printf '%s' "${1%%/*}" ;;
    *)   printf '%s' "$1" ;;
  esac
}

# The text of $1 after its first "/", or empty when it holds none. Paired with tf_first_segment to
# peel a "/"-joined string apart one segment at a time without ever word-splitting an unquoted
# expansion, the same reasoning tf_name_carries already states for its own comma list.
tf_rest_segments() {
  case "$1" in
    */*) printf '%s' "${1#*/}" ;;
    *)   printf '%s' "" ;;
  esac
}

# True when path (a "/"-joined list of segments, $1) matches glob (the same shape, $2) under the
# catalog's own `**` semantics (drupal/standards-and-tests.md: a leading `**/` is an optional path
# prefix, added so the same pattern also covers a test tree at the repository root). Plain `case`
# cannot express this on its own: there, `**` is nothing more than one `*`, and a lone `*` there
# crosses `/` freely, both wrong for what the catalog declares. So a `**` segment is handled here,
# once, before either string ever reaches a `case`: it may consume zero path segments or, when at
# least one remains, one more and try again, which is why this recurses rather than looping. Every
# other segment consumes exactly one path segment and is matched against it, alone, through
# tf_path_matches_glob, which is where a bounded `*` (one that cannot cross `/`, because there is
# none left inside a single segment) is exactly the semantics `case` already gives for free.
tf_segments_match() {
  # Never named "path": zsh ties that exact name to $PATH as a special array (Honesty: this script
  # runs under zsh too), and that tie, combined with this file's own KSH_ARRAYS and nounset, made a
  # bare `[ -z "$path" ]` on this variable report "parameter not set" even immediately after it was
  # plainly assigned. "walk" is the segments still left to match; every other local name here is
  # checked against zsh's own special-parameter list before use.
  local walk glob gseg grest wseg wrest
  walk="$1"
  glob="$2"
  if [ -z "$glob" ]; then
    [ -z "$walk" ]
    return $?
  fi
  gseg="$(tf_first_segment "$glob")"
  grest="$(tf_rest_segments "$glob")"
  if [ "$gseg" = "**" ]; then
    tf_segments_match "$walk" "$grest" && return 0
    [ -n "$walk" ] || return 1
    wrest="$(tf_rest_segments "$walk")"
    tf_segments_match "$wrest" "$glob"
    return $?
  fi
  [ -n "$walk" ] || return 1
  wseg="$(tf_first_segment "$walk")"
  wrest="$(tf_rest_segments "$walk")"
  tf_path_matches_glob "$wseg" "$gseg" || return 1
  tf_segments_match "$wrest" "$grest"
}

# True when path $1 matches catalog glob $2, stripping a leading or trailing "/" from each first so
# an incidental one never creates a spurious empty segment before the two are compared segment by
# segment through tf_segments_match. Parameter kept out of a variable named "path" for the same
# zsh-special-parameter reason tf_segments_match states.
tf_path_matches_catalog_glob() {
  local walk glob
  walk="$1"
  glob="$2"
  case "$walk" in /*) walk="${walk#/}" ;; esac
  case "$walk" in */) walk="${walk%/}" ;; esac
  case "$glob" in /*) glob="${glob#/}" ;; esac
  case "$glob" in */) glob="${glob%/}" ;; esac
  tf_segments_match "$walk" "$glob"
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
  local task_arg="" unit_id="" test_raw="" red_raw="" glob_raw="" checklist_raw="" goa_raw=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --test)
        [ "$#" -ge 2 ] || die3 "tests-freeze: --test needs <path>::<test name>=<criterion id>[,<criterion id>...]"
        test_raw="$test_raw$2
"
        shift 2 ;;
      --red)
        [ "$#" -ge 2 ] || die3 "tests-freeze: --red needs <test name>=<path to a file holding what the run printed>"
        red_raw="$red_raw$2
"
        shift 2 ;;
      --test-glob)
        [ "$#" -ge 2 ] || die3 "tests-freeze: --test-glob needs <glob>"
        glob_raw="$glob_raw$2
"
        shift 2 ;;
      --checklist)
        [ "$#" -ge 2 ] || die3 "tests-freeze: --checklist needs <criterion id>=<verification text>"
        checklist_raw="$checklist_raw$2
"
        shift 2 ;;
      --green-on-arrival)
        [ "$#" -ge 2 ] || die3 "tests-freeze: --green-on-arrival needs <test name>=<reason>"
        goa_raw="$goa_raw$2
"
        shift 2 ;;
      -*) die3 "tests-freeze: unrecognized argument: $1" ;;
      *)
        if [ -z "$task_arg" ]; then
          task_arg="$1"
        elif [ -z "$unit_id" ]; then
          unit_id="$1"
        else
          die3 "tests-freeze: unrecognized extra argument: $1"
        fi
        shift ;;
    esac
  done
  [ -n "$task_arg" ] || die3 "tests-freeze: a task folder is required"
  [ -n "$unit_id" ]  || die3 "tests-freeze: a unit id is required"

  local resolve_rc
  TASK_PATH="$(resolve_task_folder "$task_arg" "tests-freeze")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  IMPL_DIR="$TASK_PATH/implementation"

  tt_load_snapshot "tests-freeze"
  tt_load_unit_and_criteria "$SNAPSHOT_DOC" "$unit_id" "tests-freeze"

  # --- turn every raw --flag value into JSON, through temporary files beside the implementation dir
  local tests_tmp reds_tmp checklists_tmp goa_tmp
  tests_tmp="$IMPL_DIR/.tests-freeze-tests.$$"
  reds_tmp="$IMPL_DIR/.tests-freeze-reds.$$"
  checklists_tmp="$IMPL_DIR/.tests-freeze-checklists.$$"
  goa_tmp="$IMPL_DIR/.tests-freeze-goa.$$"
  : >"$tests_tmp"; : >"$reds_tmp"; : >"$checklists_tmp"; : >"$goa_tmp"
  tf_parse_tests      "$test_raw"      "$tests_tmp"
  tf_parse_reds       "$red_raw"       "$reds_tmp"
  tf_parse_checklists "$checklist_raw" "$checklists_tmp"
  tf_parse_goa        "$goa_raw"       "$goa_tmp"

  local tests_json reds_json checklists_json goa_json test_globs_json
  tests_json="$(jq -s '.' "$tests_tmp")"
  reds_json="$(jq -s '.' "$reds_tmp")"
  checklists_json="$(jq -s '.' "$checklists_tmp")"
  goa_json="$(jq -s '.' "$goa_tmp")"
  rm -f "$tests_tmp" "$reds_tmp" "$checklists_tmp" "$goa_tmp"
  test_globs_json="$(printf '%s' "$glob_raw" | jq -R -s 'split("\n") | map(select(length>0))')"

  # --- the task's own project, resolved the same way start and preconditions already resolve it --
  local project_folder codepath
  project_folder="$(resolve_project_folder "$TASK_PATH")" \
    || die3 "tests-freeze: could not resolve a project folder two levels up from $TASK_PATH, or it has no project.json"
  case "$(project_code_path_state "$project_folder")" in
    unreadable) die14 "tests-freeze: $project_folder/project.json exists but is not valid JSON, so its codePath cannot be read." ;;
    missing)    die3  "tests-freeze: $project_folder/project.json not found, though it was found moments ago." ;;
  esac
  codepath="$(project_code_path_value "$project_folder")"
  [ -n "$codepath" ] || die3 "tests-freeze: $project_folder/project.json is valid JSON but has no usable codePath field."
  [ -d "$codepath" ] || die15 "tests-freeze: the recorded codePath does not exist on disk: $codepath"
  command -v git >/dev/null 2>&1 || die3 "tests-freeze: git is required and was not found on PATH"
  is_git_repo "$codepath" \
    || die5 "tests-freeze: this task's project code at $codepath is not a git repository."
  local current_commit
  current_commit="$(git -C "$codepath" rev-parse HEAD 2>/dev/null)"
  [ -n "$current_commit" ] \
    || die3 "tests-freeze: could not capture the current commit (git rev-parse HEAD failed in $codepath)."

  # --- 36: every --test path must resolve inside codePath, and is stored relative to it -----------
  local codepath_canon
  codepath_canon="$(cd "$codepath" 2>/dev/null && pwd -P)"
  [ -n "$codepath_canon" ] \
    || die3 "tests-freeze: could not resolve $codepath to a canonical path, though it was already checked to be a directory."

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
      || die3 "tests-freeze: could not record the resolved path for $raw_path"
    nk=$((nk + 1))
  done
  [ -z "$outside_paths" ] \
    || die36 "tests-freeze: these --test paths are outside the code root $codepath_canon: ${outside_paths%, }"
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
    || die26 "tests-freeze: these --test paths do not exist on disk: ${missing_paths%, }"

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
    || die27 "tests-freeze: these --test paths (relative to $codepath_canon) match none of the given --test-glob patterns: ${unmatched_paths%, }"

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
    || die28 "tests-freeze: these test names do not carry, at the end, the criterion id they claim: ${bad_carry%, }"

  # --- 29: every machine-verified criterion the unit serves or owns needs a --test row -------------
  local missing_machine
  missing_machine="$(jq -nr --argjson criteria "$CRITERIA_JSON" --argjson tests "$tests_json" '
      ($tests | map(.criteria) | add // []) as $named
      | [ $criteria[] | select(.verifiedBy == "machine") | .id as $cid
          | select(($named | index($cid)) == null) | $cid ]
      | join(", ")
    ')"
  [ -z "$missing_machine" ] \
    || die29 "tests-freeze: these machine-verified criteria have no --test row naming them: $missing_machine"

  # --- 30: every person-verified criterion the unit serves or owns needs a --checklist row ---------
  local missing_person
  missing_person="$(jq -nr --argjson criteria "$CRITERIA_JSON" --argjson checklists "$checklists_json" '
      ($checklists | map(.id)) as $named
      | [ $criteria[] | select(.verifiedBy == "person") | .id as $cid
          | select(($named | index($cid)) == null) | $cid ]
      | join(", ")
    ')"
  [ -z "$missing_person" ] \
    || die30 "tests-freeze: these person-verified criteria have no --checklist row: $missing_person"

  # --- 31: a --test must never name a criterion the unit does not serve or own ---------------------
  local bad_criteria
  bad_criteria="$(jq -nr --argjson allowed "$CRITERIA_IDS_JSON" --argjson tests "$tests_json" '
      ($tests | map(.criteria) | add // []) as $named
      | [ $named[] as $cid | select(($allowed | index($cid)) == null) | $cid ] | unique | join(", ")
    ')"
  [ -z "$bad_criteria" ] \
    || die31 "tests-freeze: a --test names criteria $unit_id does not serve or own: $bad_criteria"

  # --- 32: a --red file must exist, hold something, and name a test that has a --test row ----------
  local bad_red_names
  bad_red_names="$(jq -nr --argjson tests "$tests_json" --argjson reds "$reds_json" '
      ($tests | map(.name)) as $known
      | [ $reds[] | .name as $n | select(($known | index($n)) == null) | $n ] | unique | join(", ")
    ')"
  [ -z "$bad_red_names" ] \
    || die32 "tests-freeze: these --red rows name a test with no --test row: $bad_red_names"

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
    || die32 "tests-freeze: these --red files are missing or empty: ${bad_red_files%, }"

  # --- 33: every declared test needs a --red -------------------------------------------------------
  local missing_red
  missing_red="$(jq -nr --argjson tests "$tests_json" --argjson reds "$reds_json" '
      ($reds | map(.name)) as $named
      | [ $tests[] | .name as $n | select(($named | index($n)) == null) | $n ] | unique | join(", ")
    ')"
  [ -z "$missing_red" ] \
    || die33 "tests-freeze: these tests have no --red at all: $missing_red"

  # --- 34: a green-on-arrival stops the step outright -----------------------------------------------
  if [ "$(printf '%s' "$goa_json" | jq 'length')" -gt 0 ]; then
    local goa_text
    goa_text="$(printf '%s' "$goa_json" | jq -r 'map(.name + ": " + .reason) | join("; ")')"
    die34 "tests-freeze: reported green on arrival, which proves nothing: $goa_text. Fix the test or the code until it fails for the right reason, then run tests-freeze again."
  fi

  # --- 35: a record already exists for this unit at a different commit -----------------------------
  local record_file existing_doc existing_commit
  record_file="$IMPL_DIR/tests-$unit_id.json"
  if [ -f "$record_file" ]; then
    existing_doc="$(jq -c '.' "$record_file" 2>/dev/null)"
    [ -n "$existing_doc" ] \
      || die3 "tests-freeze: $record_file exists but could not be read as JSON. Repair or remove it by hand before running this again."
    existing_commit="$(printf '%s' "$existing_doc" | jq -r '.commit // empty')"
    [ -n "$existing_commit" ] \
      || die3 "tests-freeze: $record_file exists but has no usable commit field."
    [ "$existing_commit" = "$current_commit" ] \
      || die35 "tests-freeze: $record_file was already frozen at commit $existing_commit, and this run is at a different commit, $current_commit. A record is taken once per commit; investigate before proceeding."
  fi

  # --- every check passed: build the rows, one per criterion the unit serves or owns ---------------
  local need_sha
  need_sha="$(printf '%s' "$CRITERIA_JSON" | jq -r 'map(select(.verifiedBy == "machine")) | length > 0')"
  if [ "$need_sha" = "true" ]; then
    records_hash__resolve_sha256_cmd \
      || die3 "tests-freeze: neither sha256sum nor 'shasum -a 256' was found on PATH"
  fi

  local rows_tmp crit_count ci cid ckind
  rows_tmp="$IMPL_DIR/.tests-freeze-rows.$$"
  : >"$rows_tmp"
  crit_count="$(printf '%s' "$CRITERIA_JSON" | jq 'length')"
  ci=0
  while [ "$ci" -lt "$crit_count" ]; do
    cid="$(printf '%s' "$CRITERIA_JSON" | jq -r --argjson ci "$ci" '.[$ci].id')"
    ckind="$(printf '%s' "$CRITERIA_JSON" | jq -r --argjson ci "$ci" '.[$ci].verifiedBy')"
    if [ "$ckind" = "machine" ]; then
      local names_json ntests tj tpath trelpath tname tsha tredpath tredtext tests_out_tmp tests_out_json
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
        [ -n "$tsha" ] || die3 "tests-freeze: could not compute a sha256 for $tpath"
        tredpath="$(printf '%s' "$reds_json" | jq -r --arg n "$tname" '[ .[] | select(.name == $n) ][0].path // empty')"
        tredtext="$(cat "$tredpath" 2>/dev/null)"
        # The record stores the path relative to codePath, never the absolute form: a frozen path
        # must still mean the same file once the checkout moves (see exit 36's own reasoning).
        jq -n --arg path "$trelpath" --arg name "$tname" --arg sha "$tsha" --arg red "$tredtext" \
          '{path: $path, name: $name, sha256: $sha, red: $red}' >>"$tests_out_tmp" \
          || die3 "tests-freeze: could not record the test row for $tname"
        tj=$((tj + 1))
      done
      tests_out_json="$(jq -s '.' "$tests_out_tmp")"
      rm -f "$tests_out_tmp"
      jq -n --arg cid "$cid" --argjson tests "$tests_out_json" \
        '{criterion: $cid, kind: "machine", tests: $tests}' >>"$rows_tmp" \
        || die3 "tests-freeze: could not record the row for $cid"
    else
      local checklist_text
      checklist_text="$(printf '%s' "$checklists_json" | jq -r --arg id "$cid" \
        '[ .[] | select(.id == $id) ][0].text // empty')"
      jq -n --arg cid "$cid" --arg text "$checklist_text" \
        '{criterion: $cid, kind: "person", checklist: $text}' >>"$rows_tmp" \
        || die3 "tests-freeze: could not record the row for $cid"
    fi
    ci=$((ci + 1))
  done
  local rows_json
  rows_json="$(jq -s '.' "$rows_tmp")"
  rm -f "$rows_tmp"

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
  echo "TESTS-FREEZE: written (commit $current_commit)"
  printf '%s\n' "$record_file"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# Step four: build-brief and build-record. The model writes the code; this script never does.
# `build-brief` assembles exactly what that model may see, from the frozen snapshot, the frozen
# test record for one unit, and the ledger. `build-record` verifies what came back: it runs four of
# the eight deciding checks docs/implementation.md names ("The deciding checks run before anything
# judges") and moves the attempt counter. The other four (coding standards, static analysis,
# security, the interface record) belong to a later step; this one never claims to have run them.
#
# `bb_` and `br_` are this section's own helper prefixes, kept apart from `pc_`, `tc_`, `tf_` and
# `tt_` above, which each belong to a different step. `build-record` still reuses `tf_` directly
# rather than carrying a second copy: `tf_path_matches_catalog_glob` for the owned-files check, and
# `tf_sha256_of` (with `records_hash__resolve_sha256_cmd`) for the frozen-tests check, because both
# are exactly the same computation `tests-freeze` already made, and a second matcher or a second
# hash function would be a second producer for one fact.
# ------------------------------------------------------------------------------------------------

# The frozen work order $2 from frozen snapshot $1. Sets BB_UNIT_JSON. Dies (die38) when the unit is
# not in the frozen copy, rather than returning a code: every caller of this helper treats that as
# fatal and would only turn around and exit itself. Kept apart from tt_load_unit_and_criteria, which
# dies on the same fact with die22, because build-brief's own refusal list names this fact as exit
# 38 rather than sharing tests-brief and tests-freeze's number (see exit 38's own comment above).
BB_UNIT_JSON=""
bb_load_unit() {
  local snapshot_doc="$1" unit_id="$2"
  BB_UNIT_JSON="$(printf '%s' "$snapshot_doc" | jq -c --arg id "$unit_id" \
    '(.workOrders // []) | map(select(.id == $id)) | .[0] // null')"
  [ "$BB_UNIT_JSON" != "null" ] || die38 "build-brief: $unit_id is not in the frozen copy."
}

do_build_brief() {
  [ "$#" -ge 2 ] || die3 "build-brief: a task folder and a unit id are required"
  [ "$#" -le 2 ] || die3 "build-brief: unrecognized extra argument: $3"
  local unit_id="$2"
  local resolve_rc
  TASK_PATH="$(resolve_task_folder "$1" "build-brief")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  IMPL_DIR="$TASK_PATH/implementation"

  # --- exit 42: this step ran before start, so there is no frozen copy to read from ---------------
  local snapshot_file="$IMPL_DIR/snapshot.json"
  [ -f "$snapshot_file" ] \
    || die42 "build-brief: $snapshot_file not found. This step ran before start, so there is no frozen copy. Run start on this task first."
  local snapshot_doc
  snapshot_doc="$(jq -c '.' "$snapshot_file" 2>/dev/null)"
  [ -n "$snapshot_doc" ] \
    || die3 "build-brief: $snapshot_file exists but could not be read as JSON, though start already wrote it. Repair or remove it by hand before running this again."

  # --- exit 38: the unit itself must be in the frozen copy -----------------------------------------
  bb_load_unit "$snapshot_doc" "$unit_id"

  # --- exit 39: step three (tests-brief, tests-freeze) must already have run for this unit ---------
  local tests_file="$IMPL_DIR/tests-$unit_id.json"
  [ -f "$tests_file" ] \
    || die39 "build-brief: $tests_file not found. Step three has not run for $unit_id yet; run tests-brief and tests-freeze on it first."
  local tests_doc
  tests_doc="$(jq -c '.' "$tests_file" 2>/dev/null)"
  [ -n "$tests_doc" ] \
    || die3 "build-brief: $tests_file exists but could not be read as JSON. Repair or remove it by hand before running this again."

  # --- the ledger: needed for the dependency check and the attempt count ---------------------------
  local ledger_file="$IMPL_DIR/ledger.json"
  [ -f "$ledger_file" ] \
    || die3 "build-brief: $ledger_file not found, though $IMPL_DIR/snapshot.json exists. A snapshot with no ledger beside it is not a supported state; run start again."
  local ledger_doc
  ledger_doc="$(jq -c '.' "$ledger_file" 2>/dev/null)"
  [ -n "$ledger_doc" ] \
    || die3 "build-brief: $ledger_file exists but could not be read as JSON. Repair or remove it by hand before running this again."

  # --- exit 40: every dependency needs a completion record before its interface is handed over ------
  local depends_json dep_count i dep_id dep_entry dep_step dependency_interfaces_json='[]'
  depends_json="$(printf '%s' "$BB_UNIT_JSON" | jq -c '.dependsOn // []')"
  dep_count="$(printf '%s' "$depends_json" | jq 'length')"
  i=0
  while [ "$i" -lt "$dep_count" ]; do
    dep_id="$(printf '%s' "$depends_json" | jq -r --argjson i "$i" '.[$i]')"
    dep_entry="$(printf '%s' "$ledger_doc" | jq -c --arg id "$dep_id" \
      '(.orders // []) | map(select(.id == $id)) | .[0] // null')"
    [ "$dep_entry" != "null" ] \
      || die3 "build-brief: $unit_id depends on $dep_id, which has no entry in $ledger_file, though start opens one entry per snapshot work order."
    dep_step="$(printf '%s' "$dep_entry" | jq -r '.lastStep // "not started"')"
    if [ "$dep_step" = "closed" ]; then
      local dep_interface
      dep_interface="$(printf '%s' "$snapshot_doc" | jq -r --arg id "$dep_id" \
        '(.workOrders // []) | map(select(.id == $id)) | .[0].interface // ""')"
      dependency_interfaces_json="$(printf '%s' "$dependency_interfaces_json" | jq -c \
        --arg id "$dep_id" --arg iface "$dep_interface" '. + [{id: $id, interface: $iface}]')"
    else
      die40 "build-brief: $unit_id depends on $dep_id, which has no completion record ($ledger_file records its last step as $dep_step), so its interface record does not exist yet."
    fi
    i=$((i + 1))
  done

  # --- exit 41: the attempt counter for this unit must still have room -----------------------------
  local order_entry attempts_used
  order_entry="$(printf '%s' "$ledger_doc" | jq -c --arg id "$unit_id" \
    '(.orders // []) | map(select(.id == $id)) | .[0] // null')"
  [ "$order_entry" != "null" ] \
    || die3 "build-brief: $unit_id has no entry in $ledger_file, though start opens one entry per snapshot work order."
  attempts_used="$(printf '%s' "$order_entry" | jq -r '.attemptsUsed // 0')"
  case "$attempts_used" in ''|*[!0-9]*) attempts_used=0 ;; esac
  [ "$attempts_used" -lt "$BUILD_ATTEMPTS_ALLOWED" ] \
    || die41 "build-brief: $unit_id has already used $attempts_used of $BUILD_ATTEMPTS_ALLOWED allowed attempts. Nothing more is handed over."

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

  jq -n --argjson unit "$unit_out" --argjson tests "$tests_out" \
        --argjson dependencyInterfaces "$dependency_interfaces_json" \
        --argjson attemptsUsed "$attempts_used" --argjson attemptsAllowed "$BUILD_ATTEMPTS_ALLOWED" \
    '{unit: $unit, tests: $tests, dependencyInterfaces: $dependencyInterfaces,
      attemptsUsed: $attemptsUsed, attemptsAllowed: $attemptsAllowed}'
  exit 0
}

# Runs $1, a newline-separated list of argv tokens (one repeated --flag occurrence per line, never
# a string split on whitespace), as arguments from inside $2, after cd'ing there. This is a third
# runner alongside pc_run_check and tc_run_smoke, needed because this call site's own tokens already
# arrive pre-split as separate argv elements (the caller passes --suite or --order-tests once per
# token), so there is nothing here to split and no shell to split it unsafely: `set --` is rebuilt
# one already-whole token at a time from the heredoc, never through `set -- $value` or a `for` over
# an unquoted expansion, so this needs neither pc_run_check's SH_WORD_SPLIT nor GLOB_SUBST. Standard
# output and standard error are captured together in $3, the same as tc_run_smoke, because a
# --nothing-ran marker may land on either stream and the caller records the output verbatim either
# way. Prints the exit status on stdout; never dies.
br_run_argv() {
  local raw="$1" dir="$2" outfile="$3"
  (
    cd "$dir" || exit 127
    set --
    while IFS= read -r tok; do
      set -- "$@" "$tok"
    done <<BR_TOKENS
$raw
BR_TOKENS
    exec "$@"
  ) >"$outfile" 2>&1
  printf '%s' "$?"
}

do_build_record() {
  local task_arg="" unit_id="" interface_path="" report_path="" started_at=""
  local suite_raw="" order_tests_raw="" nothing_ran=""
  local have_suite=false have_order_tests=false have_nothing_ran=false
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --interface)
        [ "$#" -ge 2 ] || die3 "build-record: --interface needs a path to the record the builder wrote"
        interface_path="$2"; shift 2 ;;
      --report)
        [ "$#" -ge 2 ] || die3 "build-record: --report needs a path to the builder's report"
        report_path="$2"; shift 2 ;;
      --started-at)
        [ "$#" -ge 2 ] || die3 "build-record: --started-at needs a commit"
        started_at="$2"; shift 2 ;;
      --suite)
        [ "$#" -ge 2 ] || die3 "build-record: --suite needs an argv token"
        have_suite=true
        suite_raw="$suite_raw$2
"
        shift 2 ;;
      --order-tests)
        [ "$#" -ge 2 ] || die3 "build-record: --order-tests needs an argv token"
        have_order_tests=true
        order_tests_raw="$order_tests_raw$2
"
        shift 2 ;;
      --nothing-ran)
        [ "$#" -ge 2 ] || die3 "build-record: --nothing-ran needs a literal substring"
        have_nothing_ran=true
        nothing_ran="$2"
        shift 2 ;;
      -*) die3 "build-record: unrecognized argument: $1" ;;
      *)
        if [ -z "$task_arg" ]; then
          task_arg="$1"
        elif [ -z "$unit_id" ]; then
          unit_id="$1"
        else
          die3 "build-record: unrecognized extra argument: $1"
        fi
        shift ;;
    esac
  done
  [ -n "$task_arg" ]        || die3 "build-record: a task folder is required"
  [ -n "$unit_id" ]         || die3 "build-record: a unit id is required"
  [ -n "$interface_path" ]  || die3 "build-record: --interface is required"
  [ -n "$report_path" ]     || die3 "build-record: --report is required"
  [ -n "$started_at" ]      || die3 "build-record: --started-at is required"

  local resolve_rc
  TASK_PATH="$(resolve_task_folder "$task_arg" "build-record")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"
  IMPL_DIR="$TASK_PATH/implementation"

  tt_load_snapshot "build-record"
  tt_load_unit_and_criteria "$SNAPSHOT_DOC" "$unit_id" "build-record"

  local tests_file="$IMPL_DIR/tests-$unit_id.json" tests_doc
  [ -f "$tests_file" ] \
    || die3 "build-record: $tests_file not found, though a build attempt implies tests-brief and tests-freeze already ran for $unit_id. Run tests-freeze on it first."
  tests_doc="$(jq -c '.' "$tests_file" 2>/dev/null)"
  [ -n "$tests_doc" ] \
    || die3 "build-record: $tests_file exists but could not be read as JSON. Repair or remove it by hand before running this again."

  local ledger_file="$IMPL_DIR/ledger.json" ledger_doc
  [ -f "$ledger_file" ] \
    || die3 "build-record: $ledger_file not found, though $IMPL_DIR/snapshot.json exists. A snapshot with no ledger beside it is not a supported state; run start again."
  ledger_doc="$(jq -c '.' "$ledger_file" 2>/dev/null)"
  [ -n "$ledger_doc" ] \
    || die3 "build-record: $ledger_file exists but could not be read as JSON. Repair or remove it by hand before running this again."
  local order_entry attempts_used_before attempt_number
  order_entry="$(printf '%s' "$ledger_doc" | jq -c --arg id "$unit_id" \
    '(.orders // []) | map(select(.id == $id)) | .[0] // null')"
  [ "$order_entry" != "null" ] \
    || die3 "build-record: $unit_id has no entry in $ledger_file, though start opens one entry per snapshot work order."
  attempts_used_before="$(printf '%s' "$order_entry" | jq -r '.attemptsUsed // 0')"
  case "$attempts_used_before" in ''|*[!0-9]*) attempts_used_before=0 ;; esac
  attempt_number=$((attempts_used_before + 1))

  # --- the task's own project, resolved the same way every earlier step already resolves it --------
  local project_folder codepath
  project_folder="$(resolve_project_folder "$TASK_PATH")" \
    || die3 "build-record: could not resolve a project folder two levels up from $TASK_PATH, or it has no project.json"
  case "$(project_code_path_state "$project_folder")" in
    unreadable) die14 "build-record: $project_folder/project.json exists but is not valid JSON, so its codePath cannot be read." ;;
    missing)    die3  "build-record: $project_folder/project.json not found, though it was found moments ago." ;;
  esac
  codepath="$(project_code_path_value "$project_folder")"
  [ -n "$codepath" ] || die3 "build-record: $project_folder/project.json is valid JSON but has no usable codePath field."
  [ -d "$codepath" ] || die15 "build-record: the recorded codePath does not exist on disk: $codepath"
  command -v git >/dev/null 2>&1 || die3 "build-record: git is required and was not found on PATH"
  is_git_repo "$codepath" \
    || die5 "build-record: this task's project code at $codepath is not a git repository."

  # --- exit 43: --started-at must be a real commit in this repository ------------------------------
  local started_at_full current_commit
  started_at_full="$(git -C "$codepath" rev-parse --verify --quiet "${started_at}^{commit}" 2>/dev/null)"
  [ -n "$started_at_full" ] \
    || die43 "build-record: --started-at ($started_at) is not a commit in the code repository at $codepath."
  current_commit="$(git -C "$codepath" rev-parse HEAD 2>/dev/null)"
  [ -n "$current_commit" ] \
    || die3 "build-record: could not capture the current commit (git rev-parse HEAD failed in $codepath)."

  # --- exit 45: refuse a duplicate of an attempt already recorded, before anything else runs -------
  local record_file="$IMPL_DIR/build-$unit_id.json"
  if [ -f "$record_file" ]; then
    local existing_doc existing_commit existing_attempt
    existing_doc="$(jq -c '.' "$record_file" 2>/dev/null)"
    [ -n "$existing_doc" ] \
      || die3 "build-record: $record_file exists but could not be read as JSON. Repair or remove it by hand before running this again."
    existing_commit="$(printf '%s' "$existing_doc" | jq -r '.commit // empty')"
    existing_attempt="$(printf '%s' "$existing_doc" | jq -r '.attempt // empty')"
    if [ "$existing_commit" = "$current_commit" ] && [ "$existing_attempt" = "$attempt_number" ]; then
      die45 "build-record: $record_file already holds attempt $attempt_number at commit $current_commit. Nothing has changed since that record was written."
    fi
  fi

  # --- exit 44: the interface record is required only when the unit declares a non-empty interface -
  local unit_interface_declared interface_text=""
  unit_interface_declared="$(printf '%s' "$UNIT_JSON" | jq -r '.interface // ""')"
  if [ -n "$unit_interface_declared" ]; then
    [ -s "$interface_path" ] \
      || die44 "build-record: $unit_id declares a non-empty interface, and the interface record at $interface_path is missing or empty."
  fi
  [ -f "$interface_path" ] && interface_text="$(cat "$interface_path" 2>/dev/null)"

  records_hash__resolve_sha256_cmd \
    || die3 "build-record: neither sha256sum nor 'shasum -a 256' was found on PATH"

  # --- check one: every test of this order passes ---------------------------------------------------
  local check1_id="order-tests" check1_verdict="" check1_detail="" check1_exit_json="null" check1_output=""
  if [ "$have_order_tests" = "false" ]; then
    check1_verdict="undeclared"
    check1_detail="no --order-tests command was given, so whether this order's own tests pass was not checked."
  else
    local out1 rc1
    out1="$(mktemp)" || die3 "build-record: could not create a temporary file"
    rc1="$(br_run_argv "$order_tests_raw" "$codepath" "$out1")"
    check1_exit_json="$rc1"
    check1_output="$(cat "$out1" 2>/dev/null)"
    if [ "$have_nothing_ran" = "true" ] && pc_output_holds "$out1" "$nothing_ran"; then
      check1_verdict="unknown"
      check1_detail="the order-tests command's output holds the nothing-ran marker ('$nothing_ran'); an exit status cannot decide a green run when nothing was selected."
    elif [ "$rc1" = "0" ]; then
      check1_verdict="met"
      check1_detail="the order-tests command exited 0."
    else
      check1_verdict="unmet"
      check1_detail="the order-tests command exited $rc1."
    fi
    rm -f "$out1"
  fi

  # --- check two: no test outside the baseline fails -------------------------------------------------
  local check2_id="suite-regression" check2_verdict="" check2_detail="" check2_exit_json="null" check2_output=""
  if [ "$have_suite" = "false" ]; then
    check2_verdict="undeclared"
    check2_detail="no --suite command was given, so whether this order broke anything outside itself was not checked."
  else
    local out2 rc2
    out2="$(mktemp)" || die3 "build-record: could not create a temporary file"
    rc2="$(br_run_argv "$suite_raw" "$codepath" "$out2")"
    check2_exit_json="$rc2"
    check2_output="$(cat "$out2" 2>/dev/null)"
    if [ "$have_nothing_ran" = "true" ] && pc_output_holds "$out2" "$nothing_ran"; then
      check2_verdict="unknown"
      check2_detail="the suite command's output holds the nothing-ran marker ('$nothing_ran'); an exit status cannot decide a green run when nothing was selected."
    elif [ "$rc2" = "0" ]; then
      check2_verdict="met"
      check2_detail="the whole suite exited 0; nothing outside this order failed."
    else
      # The baseline records one verdict per framework, taken whole, not which test failed
      # (baseline-schema.json, suite[].verdict); that is the finest grain step two's own record
      # holds. A suite failing now, with the baseline already unmet, is not the same fact as a
      # suite that is clean: this cannot tell an old failure from an old failure plus a new one
      # this order introduced, so it says so rather than reading a red baseline as a pass. Only a
      # baseline whose every framework was met, with the suite failing now, is decidable, because
      # then every failure is new. A test-level comparison is a documented bound this stage does
      # not close, the same kind of bound the ownedFiles overlap check already accepts elsewhere
      # in this file; the bound is honest about what it cannot decide rather than defaulting to met.
      local baseline_file="$IMPL_DIR/baseline.json" baseline_doc baseline_unmet_frameworks
      if [ -f "$baseline_file" ] && baseline_doc="$(jq -c '.' "$baseline_file" 2>/dev/null)" && [ -n "$baseline_doc" ]; then
        baseline_unmet_frameworks="$(printf '%s' "$baseline_doc" | jq -r \
          '[ (.suite // [])[] | select(.verdict == "unmet") | .framework ] | join(", ")')"
        if [ -n "$baseline_unmet_frameworks" ]; then
          check2_verdict="unknown"
          check2_detail="the suite exited $rc2, and the baseline recorded $baseline_unmet_frameworks unmet at the commit the build started from. The baseline records one verdict per framework rather than which tests failed, so this cannot tell an old failure from an old failure plus a new one."
        else
          check2_verdict="unmet"
          check2_detail="the suite exited $rc2, and the baseline recorded every framework met at the commit the build started from; this order introduced the failure."
        fi
      else
        check2_verdict="unknown"
        check2_detail="the suite exited $rc2, and $baseline_file could not be read to tell whether this failure predates this order."
      fi
    fi
    rm -f "$out2"
  fi

  # --- check three: the realized diff touches only the files this order owns -------------------------
  local check3_id="owned-files" check3_verdict="" check3_detail=""
  local diff_output owned_files_json owned_count unmatched="" p matched gi g
  diff_output="$(git -C "$codepath" diff --name-only "$started_at_full" "$current_commit" 2>/dev/null)"
  owned_files_json="$(printf '%s' "$UNIT_JSON" | jq -c '.ownedFiles // []')"
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
    check3_verdict="unmet"
    check3_detail="these changed files match none of $unit_id's own ownedFiles: ${unmatched%, }"
  else
    check3_verdict="met"
    check3_detail="every file changed between $started_at_full and $current_commit matches this order's own ownedFiles."
  fi

  # --- check four: every frozen test file is unchanged -------------------------------------------------
  local check4_id="frozen-tests" check4_verdict="" check4_detail=""
  local frozen_paths frozen_count fi fpath fsha current_sha changed_tests=""
  frozen_paths="$(printf '%s' "$tests_doc" | jq -c \
    '[ (.rows // [])[] | select(.kind == "machine") | (.tests // [])[] | {path, sha256} ] | unique_by(.path)')"
  frozen_count="$(printf '%s' "$frozen_paths" | jq 'length')"
  fi=0
  while [ "$fi" -lt "$frozen_count" ]; do
    fpath="$(printf '%s' "$frozen_paths" | jq -r --argjson fi "$fi" '.[$fi].path')"
    fsha="$(printf '%s' "$frozen_paths" | jq -r --argjson fi "$fi" '.[$fi].sha256')"
    if [ -f "$codepath/$fpath" ]; then
      current_sha="$(tf_sha256_of "$codepath/$fpath")"
    else
      current_sha=""
    fi
    [ "$current_sha" = "$fsha" ] || changed_tests="$changed_tests$fpath, "
    fi=$((fi + 1))
  done
  if [ -n "$changed_tests" ]; then
    check4_verdict="unmet"
    check4_detail="these frozen test files no longer match the hash tests-freeze recorded: ${changed_tests%, }"
  else
    check4_verdict="met"
    check4_detail="every frozen test file for $unit_id is unchanged."
  fi

  # --- assemble and write the record -----------------------------------------------------------------
  local checks_json
  checks_json="$(jq -n \
    --arg id1 "$check1_id" --arg v1 "$check1_verdict" --arg d1 "$check1_detail" \
    --argjson e1 "$check1_exit_json" --arg o1 "$check1_output" \
    --arg id2 "$check2_id" --arg v2 "$check2_verdict" --arg d2 "$check2_detail" \
    --argjson e2 "$check2_exit_json" --arg o2 "$check2_output" \
    --arg id3 "$check3_id" --arg v3 "$check3_verdict" --arg d3 "$check3_detail" \
    --arg id4 "$check4_id" --arg v4 "$check4_verdict" --arg d4 "$check4_detail" \
    '[
      {id: $id1, verdict: $v1, detail: $d1} + (if $e1 == null then {} else {exitCode: $e1, output: $o1} end),
      {id: $id2, verdict: $v2, detail: $d2} + (if $e2 == null then {} else {exitCode: $e2, output: $o2} end),
      {id: $id3, verdict: $v3, detail: $d3},
      {id: $id4, verdict: $v4, detail: $d4}
    ]')"

  local today record_json
  today="$(date -u +%Y-%m-%d)"
  record_json="$(jq -n \
    --arg takenAt "$today" --arg unit "$unit_id" --arg startedAt "$started_at_full" \
    --arg commit "$current_commit" --argjson attempt "$attempt_number" \
    --arg interfaceRecord "$interface_text" --arg reportPath "$report_path" \
    --argjson checks "$checks_json" \
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
      decidingChecks: { total: 8, ranHere: [ $checks[0].id, $checks[1].id, $checks[2].id, $checks[3].id ] }
    }')"

  write_atomic "$record_file" "$record_json"

  local new_ledger_doc
  new_ledger_doc="$(printf '%s' "$ledger_doc" | jq -c --arg id "$unit_id" \
    '.orders = (.orders | map(if .id == $id then .attemptsUsed = (.attemptsUsed + 1) else . end))')"
  write_atomic "$ledger_file" "$new_ledger_doc"

  printf '%s\n' "$record_json"
  exit 0
}

# ------------------------------------------------------------------------------------------------
# dispatch-open, dispatch-close: open and clear <project path>/dispatch.json
# (scripts/dispatch-schema.json), the one record hooks/deny-prior-source.sh and
# hooks/deny-frozen-test-writes.sh read to tell a dispatched role apart from a person working
# their own repository. The build is serial, so a project has at most one active dispatch;
# dispatch-open refuses to overwrite one already there (die37), and dispatch-close removes it,
# safe to call when none is open.
# ------------------------------------------------------------------------------------------------

do_dispatch_open() {
  local task_arg="" role="" unit_id="" deny_raw="" allow_raw=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --deny-read)
        [ "$#" -ge 2 ] || die3 "dispatch-open: --deny-read needs a path relative to codePath"
        deny_raw="$deny_raw$2
"
        shift 2 ;;
      --allow-write)
        [ "$#" -ge 2 ] || die3 "dispatch-open: --allow-write needs a path relative to codePath"
        allow_raw="$allow_raw$2
"
        shift 2 ;;
      -*) die3 "dispatch-open: unrecognized argument: $1" ;;
      *)
        if [ -z "$task_arg" ]; then
          task_arg="$1"
        elif [ -z "$role" ]; then
          role="$1"
        elif [ -z "$unit_id" ]; then
          unit_id="$1"
        else
          die3 "dispatch-open: unrecognized extra argument: $1"
        fi
        shift ;;
    esac
  done
  [ -n "$task_arg" ] || die3 "dispatch-open: a task folder is required"
  [ -n "$role" ]     || die3 "dispatch-open: a role is required"

  # A role must name an agent this plugin ships. The agents/ folder is that list, read here rather
  # than copied into this file, because a copy goes stale the first time a role is added. Nothing
  # else validates the name: a misspelled role opens a record no agent's payload can ever match,
  # and both hooks then allow everything in silence (ideal/agents.md, rule 3). The runtime reports
  # an agent type in two forms, `<plugin>:<role>` and the bare name, so both are accepted and only
  # the part after the last colon is compared.
  local role_bare agents_dir known_list
  role_bare="${role##*:}"
  agents_dir="$PLUGIN_ROOT/agents"
  known_list="$(find "$agents_dir" -maxdepth 1 -type f -name '*.md' 2>/dev/null \
    | sed 's#.*/##; s#\.md$##' | sort | tr '\n' ' ')"
  [ -n "$known_list" ] \
    || die46 "dispatch-open: no agent definitions were found in $agents_dir, so no role name can be checked. This plugin's own files are incomplete; nothing about the task is wrong."
  case " $known_list" in
    *" $role_bare "*) ;;
    *) die46 "dispatch-open: $role names no agent this plugin ships, so a dispatch under it would run with no permission applied. The roles that exist are: $known_list" ;;
  esac
  [ -n "$unit_id" ]  || die3 "dispatch-open: a unit id is required"
  case "$unit_id" in
    wo[1-9]*) ;;
    *) die3 "dispatch-open: a unit id looks like wo1, wo2, ...; got: $unit_id" ;;
  esac

  local resolve_rc
  TASK_PATH="$(resolve_task_folder "$task_arg" "dispatch-open")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"

  local task_id
  task_id="$(jq -r '.id // empty' "$TASK_PATH/task.json" 2>/dev/null)"
  [ -n "$task_id" ] || die3 "dispatch-open: $TASK_PATH/task.json has no usable id field"

  local project_folder codepath
  project_folder="$(resolve_project_folder "$TASK_PATH")" \
    || die3 "dispatch-open: could not resolve a project folder two levels up from $TASK_PATH, or it has no project.json"
  case "$(project_code_path_state "$project_folder")" in
    unreadable) die14 "dispatch-open: $project_folder/project.json exists but is not valid JSON" ;;
    missing)    die3  "dispatch-open: $project_folder/project.json not found, though it was found moments ago" ;;
  esac
  codepath="$(project_code_path_value "$project_folder")"
  [ -n "$codepath" ] || die3 "dispatch-open: $project_folder/project.json is valid JSON but has no usable codePath field"
  [ -d "$codepath" ] || die15 "dispatch-open: the recorded codePath does not exist on disk: $codepath"

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
  if [ "$role_bare" = "test-author" ] || [ "$role_bare" = "implementer" ]; then
    IMPL_DIR="$TASK_PATH/implementation"
    tt_load_snapshot "dispatch-open"
    local unit_present
    unit_present="$(printf '%s' "$SNAPSHOT_DOC" | jq -r --arg u "$unit_id" \
      '[ .workOrders[]? | select(.id == $u) ] | length')"
    [ "$unit_present" = "0" ] \
      && die22 "dispatch-open: $unit_id is not a work order in $IMPL_DIR/snapshot.json. The snapshot is what the build is frozen against, so an order added to design after start is not in it."
  fi

  if [ "$role_bare" = "test-author" ]; then
    local owned_json owned_count
    owned_json="$(printf '%s' "$SNAPSHOT_DOC" | jq -c '[.workOrders[]?.ownedFiles[]?] | unique')"
    owned_count="$(printf '%s' "$owned_json" | jq 'length' 2>/dev/null)"
    [ -n "$owned_count" ] || owned_count=0
    [ "$owned_count" -gt 0 ] 2>/dev/null \
      || die47 "dispatch-open: no work order in $IMPL_DIR/snapshot.json declares an owned file, so a test author would be dispatched with nothing denied and could read every file in the repository. Design has to name what each order owns before the tests for it are written."
    deny_raw="$deny_raw$(printf '%s' "$owned_json" | jq -r '.[]')
"
  fi

  # The implementer is the mirror of the test author. It writes this unit's own files and may not
  # read another unit's, because what a unit exposes is its interface record and never its code
  # (ideal/agents.md, implementer). Both lists come from the snapshot for the same reason the test
  # author's does: assembled per dispatch they would be a judgement made in the moment.
  # An empty denial is a real state here and is not refused: a task with one work order has no
  # other unit to withhold, which is different from a test author having nothing to withhold.
  if [ "$role_bare" = "implementer" ]; then
    local mine_json others_json mine_count
    mine_json="$(printf '%s' "$SNAPSHOT_DOC" | jq -c --arg u "$unit_id" \
      '[ .workOrders[]? | select(.id == $u) | .ownedFiles[]? ] | unique')"
    mine_count="$(printf '%s' "$mine_json" | jq 'length' 2>/dev/null)"
    [ -n "$mine_count" ] || mine_count=0
    [ "$mine_count" -gt 0 ] 2>/dev/null \
      || die47 "dispatch-open: $unit_id declares no owned file in $IMPL_DIR/snapshot.json, so an implementer would be dispatched with nowhere it is meant to write. Design has to name what this order owns before its code is written."
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
      || die3 "dispatch-open: $dispatch_file exists but could not be read as JSON. Repair or remove it by hand before running this again."
    local held_role held_task held_unit
    held_role="$(jq -r '.role // "?"' "$dispatch_file" 2>/dev/null)"
    held_task="$(jq -r '.task // "?"' "$dispatch_file" 2>/dev/null)"
    held_unit="$(jq -r '.unit // "?"' "$dispatch_file" 2>/dev/null)"
    die37 "dispatch-open: $dispatch_file is already open, for role $held_role on task $held_task, unit $held_unit. Run dispatch-close first."
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

do_dispatch_close() {
  [ "$#" -ge 1 ] || die3 "dispatch-close: a task folder is required"
  [ "$#" -le 1 ] || die3 "dispatch-close: unrecognized extra argument: $2"
  local task_path="$1"
  local resolve_rc
  TASK_PATH="$(resolve_task_folder "$task_path" "dispatch-close")"
  resolve_rc=$?
  [ "$resolve_rc" -eq 0 ] || exit "$resolve_rc"

  local project_folder
  project_folder="$(resolve_project_folder "$TASK_PATH")" \
    || die3 "dispatch-close: could not resolve a project folder two levels up from $TASK_PATH, or it has no project.json"

  local dispatch_file="$project_folder/dispatch.json"
  if [ -f "$dispatch_file" ]; then
    rm -f "$dispatch_file" || die3 "dispatch-close: could not remove $dispatch_file"
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
[ -n "$ACTION" ] || { usage; die3 "no action given"; }
shift

case "$ACTION" in
  read)  do_read  "$@" ;;
  start) do_start "$@" ;;
  preconditions) do_preconditions "$@" ;;
  tests-brief)  do_tests_brief  "$@" ;;
  tests-freeze) do_tests_freeze "$@" ;;
  build-brief)  do_build_brief  "$@" ;;
  build-record) do_build_record "$@" ;;
  dispatch-open)  do_dispatch_open  "$@" ;;
  dispatch-close) do_dispatch_close "$@" ;;
  *) usage; die3 "unknown action: $ACTION" ;;
esac
