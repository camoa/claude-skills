#!/usr/bin/env bash
# records-hash.sh: the one place that hashes a task's contract and its work orders together.
#
# Design closes by recording a hash over what it closed on (ideal/implementation.md, "Freezing,
# and what a freeze is for"). Implementation re-derives the same hash from the same records and
# refuses to start when the two disagree. Both facts must come from one computation, not two: a
# second implementation that drifted by one byte, one key order, or one date format would make the
# comparison meaningless while still looking like a check. This file is that one computation,
# extracted from implement-actions.sh's own `compute_snapshot_hash` and `gather_workorders_json` so
# design's `close` action can call the exact same code rather than a copy of it.
#
# Public function:
#
#   records_hash_for <task_folder>
#     Prints, to stdout, the sha256 (lowercase hex, 64 characters, no trailing newline) over the
#     canonical JSON of <task_folder>/alignment.json and every <task_folder>/design/*.json
#     together, the design files sorted by their own numeric work order id (wo1, wo2, ... wo10),
#     never by filename, so a lexicographic sort never puts wo10 before wo2. A task with no
#     design/ folder yet, or an empty one, hashes against an empty work-order list; that is a real
#     state, not an error.
#
#     Canonical form is `jq -cS`: compact, with every object's keys sorted, recursively, so the
#     hash depends only on content, never on the order a field happened to be written in or on
#     incidental whitespace.
#
#     Returns 0 and prints the hash on success. Returns 1 and prints nothing on stdout on any
#     failure, with exactly one message on stderr naming what could not be read and why: missing,
#     unreadable, and malformed are three different facts, and this function never reports one as
#     another. It never returns 0 with empty output.
#
# Depends on: jq, and one of sha256sum (Linux) or `shasum -a 256` (macOS), both on PATH. Neither
# is assumed; both are checked and the absence of both is one of the failures named above.
#
# Portability: bash 3.2+ and zsh. No mapfile, no associative arrays, no awk, no GNU-only flag, no
# regular-expression interval quantifier anywhere, the same rule every script in this plugin
# states for the same reason (foundations.md, Honesty).
#
# This file is a library. Source it; do not run it.
if [ -n "${ZSH_VERSION:-}" ]; then
  case "${ZSH_EVAL_CONTEXT:-}" in
    *:file) : ;;
    *)
      printf 'records-hash.sh: this is a library, meant to be sourced, not run directly.\n' >&2
      exit 1
      ;;
  esac
elif [ -n "${BASH_VERSION:-}" ] && [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  printf 'records-hash.sh: this is a library, meant to be sourced, not run directly.\n' >&2
  exit 1
fi

set -uo pipefail  # not -e: a sourced file must not exit the caller's shell on a miss it should
                  # instead report through a return code.

# Sets the global array RECORDS_HASH_SHA256_CMD to the sha256 tool as separate words (name and
# flag kept apart for an array, since an unquoted variable holding both words is split on
# whitespace under bash but not under zsh: implement-actions.sh's own resolve_sha256_cmd states the
# same reasoning). Returns 1 when neither tool is on PATH.
records_hash__resolve_sha256_cmd() {
  if command -v sha256sum >/dev/null 2>&1; then
    RECORDS_HASH_SHA256_CMD=(sha256sum)
  elif command -v shasum >/dev/null 2>&1; then
    RECORDS_HASH_SHA256_CMD=(shasum -a 256)
  else
    return 1
  fi
  return 0
}
RECORDS_HASH_SHA256_CMD=()

records_hash_for() {
  local task_folder="${1:-}"
  local alignment_file design_dir

  [ -n "$task_folder" ] || { printf 'records-hash: a task folder is required\n' >&2; return 1; }
  [ -d "$task_folder" ] || { printf 'records-hash: task folder not found: %s\n' "$task_folder" >&2; return 1; }

  command -v jq >/dev/null 2>&1 \
    || { printf 'records-hash: jq is required and was not found on PATH\n' >&2; return 1; }

  records_hash__resolve_sha256_cmd \
    || { printf 'records-hash: neither sha256sum nor '"'"'shasum -a 256'"'"' was found on PATH\n' >&2; return 1; }

  alignment_file="$task_folder/alignment.json"
  design_dir="$task_folder/design"

  local alignment_json
  if [ ! -f "$alignment_file" ]; then
    printf 'records-hash: %s not found\n' "$alignment_file" >&2
    return 1
  fi
  if [ ! -r "$alignment_file" ]; then
    printf 'records-hash: %s exists but is not readable\n' "$alignment_file" >&2
    return 1
  fi
  alignment_json="$(jq -c '.' "$alignment_file" 2>/dev/null)"
  if [ -z "$alignment_json" ]; then
    printf 'records-hash: %s exists but is not valid JSON\n' "$alignment_file" >&2
    return 1
  fi

  # Every design/*.json, each read once, in an arbitrary but stable order (find | sort, on
  # filename); the numeric work-order-id sort that actually matters happens once, below, over the
  # whole collected array, the same two-step shape gather_workorders_json uses.
  local entries='[]' f doc
  if [ -d "$design_dir" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if [ ! -r "$f" ]; then
        printf 'records-hash: %s exists but is not readable\n' "$f" >&2
        return 1
      fi
      doc="$(jq -c '.' "$f" 2>/dev/null)"
      if [ -z "$doc" ]; then
        printf 'records-hash: %s is under design/ but is not valid JSON\n' "$f" >&2
        return 1
      fi
      entries="$(printf '%s' "$entries" | jq --argjson d "$doc" '. + [$d]')"
    done < <(find "$design_dir" -mindepth 1 -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort)
  fi

  local workorders_json
  workorders_json="$(printf '%s' "$entries" | jq -c '
      sort_by(
        (.id // "wo0")
        | if test("^wo[1-9][0-9]*$") then (ltrimstr("wo") | tonumber) else 0 end
      )
    ')"
  [ -n "$workorders_json" ] \
    || { printf 'records-hash: could not order the work orders under %s\n' "$design_dir" >&2; return 1; }

  local combined hash
  combined="$(jq -cS -n --argjson alignment "$alignment_json" --argjson workOrders "$workorders_json" \
    '{alignment: $alignment, workOrders: $workOrders}')"
  [ -n "$combined" ] \
    || { printf 'records-hash: could not build the canonical form to hash for %s\n' "$task_folder" >&2; return 1; }

  hash="$(printf '%s' "$combined" | "${RECORDS_HASH_SHA256_CMD[@]}" | cut -d' ' -f1)"
  [ -n "$hash" ] \
    || { printf 'records-hash: could not compute the hash for %s\n' "$task_folder" >&2; return 1; }

  printf '%s' "$hash"
  return 0
}
