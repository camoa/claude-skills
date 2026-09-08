#!/usr/bin/env bash
# implement-actions.sh: the deterministic half of the implement skill (ideal/implementation.md).
#
# The skill body holds the conversation: whether to tell a person about a refusal, whether to act
# on a drifted order, what to say once the report comes back. This script never asks a question
# and never judges whether a criterion is really met. It performs the first step of the
# implementation stage: freezing the contract and the work orders design left into a snapshot,
# opening the ledger that will track every order's progress, and refusing before writing anything
# when the task is not ready. Building a work order is not built yet; only `read` and `start`
# exist.
#
# Usage:
#   implement-actions.sh read  <task_folder>
#   implement-actions.sh start <task_folder>
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
#      ledger.json present but unreadable, or a design/*.json file that check-design.sh itself did
#      not refuse on but this script still could not parse), task.json declaring a runMode value
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
#
# Portability: bash 3.2+ and zsh. No mapfile, no associative arrays, no GNU-only flag, no awk, no
# regular-expression interval quantifier anywhere (foundations.md, Honesty). sha256sum exists on
# Linux and `shasum -a 256` on macOS; scripts/lib/records-hash.sh tries both. An id's own shape,
# where one is checked, uses a `case` glob, never a regular expression.

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

[ -f "$RECORDS_HASH_LIB" ] || die3 "cannot find the records-hash library at $RECORDS_HASH_LIB"
# shellcheck source=/dev/null
source "$RECORDS_HASH_LIB" || die3 "the records-hash library failed to load: $RECORDS_HASH_LIB"

usage() {
  cat <<'EOF' >&2
usage: implement-actions.sh read  <task_folder>
       implement-actions.sh start <task_folder>
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
      ledger: { exists: $ledgerExists, readable: $ledgerReadable, note: $ledgerNote, summary: $ledger }
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
  *) usage; die3 "unknown action: $ACTION" ;;
esac
