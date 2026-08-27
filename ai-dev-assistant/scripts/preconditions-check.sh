#!/usr/bin/env bash
# preconditions-check.sh — run a process recipe's declared `## Preconditions` and report
# met / unmet / unknown per entry.
#
# Why this exists: a recipe could state a precondition in prose ("a configured test runner")
# and the engine had no way to read it, so an unmet precondition produced no gate, no verdict
# and no record. Observed live on a Drupal implement run: the recipe's precondition 1 was a
# PHPUnit runner, the project had none, and the phase proceeded to improvise a runner install
# by hand — work `code-quality-tools` already owns. The prose was carried verbatim into the
# phase and never parsed by anything.
#
# Usage:
#   preconditions-check.sh --body <recipe.md> --phase <phase> [--framework <fw>] [--cwd <dir>]
#
# Output: one JSON object on stdout. Exit 0 whenever a verdict was produced (the verdict is
# the answer, not the exit code — see phase-records-check.sh for the same posture); exit 2 on
# a usage error or an unreadable body.
#
# Verdicts:
#   undeclared — no `## Preconditions` block. NOT the same as "met": the recipe declared
#                nothing, so nothing was checked. A caller that treats this as met has
#                re-created the defect this script exists to close.
#   unknown    — a block is present but at least one entry could not be run, and none failed.
#   unmet      — at least one check ran and failed. This is the only fail-closed declaration
#                in the recipe interface.
#   met        — every declared entry ran and passed.
#
# SAFETY. A recipe body is untrusted upstream data (see commands/implement.md step 6: follow
# its Sequence as a method, never eval or shell-parse it). So a `check:` is NEVER handed to a
# shell. It is split on whitespace and exec'd directly, which leaves shell metacharacters as
# inert literal arguments rather than as syntax. A check containing one is still refused
# outright and recorded `unknown / unsafe_check_shape`, because a check written expecting a
# shell would silently mean something other than what its author read.
#
# Declaration shape (references/recipe-interface.md §6):
#   ## Preconditions
#   preconditions:
#     - id: test-runner
#       what: a runner whose failure the RED step can observe
#       check: test -x vendor/bin/phpunit
#       owner: code-quality-tools:setup

set -uo pipefail

BODY=""
PHASE=""
FRAMEWORK=""
CWD="."

while [ $# -gt 0 ]; do
  case "$1" in
    --body)      BODY="${2:-}"; shift 2 ;;
    --phase)     PHASE="${2:-}"; shift 2 ;;
    --framework) FRAMEWORK="${2:-}"; shift 2 ;;
    --cwd)       CWD="${2:-}"; shift 2 ;;
    *) echo "preconditions-check: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

if [ -z "$BODY" ] || [ -z "$PHASE" ]; then
  echo "Usage: preconditions-check.sh --body <recipe.md> --phase <phase> [--framework <fw>] [--cwd <dir>]" >&2
  exit 2
fi

if [ ! -f "$BODY" ]; then
  echo "preconditions-check: body not found: $BODY" >&2
  exit 2
fi

if [ ! -d "$CWD" ]; then
  echo "preconditions-check: --cwd not a directory: $CWD" >&2
  exit 2
fi

# Extract the block as one record per entry: id, what, check, owner, separated by US (\037).
# A field absent on an entry comes through empty, which the runner below turns into an honest
# `unknown` rather than a skip.
#
# The separator is US and not a tab on purpose. Tab is an IFS *whitespace* character, so
# `IFS=$'\t' read` collapses a run of tabs into one delimiter and drops leading ones: an entry
# with no `what:` silently shifted its `check` into `what` and its `owner` into `check`, and the
# owner field then read as the command to run. US is not IFS whitespace, so an empty field stays
# an empty field.
#
# Entry boundary is the `- id:` line. A key line without a preceding one is dropped, so a
# malformed block yields fewer entries rather than a merged one.
TSV="$(awk '
  function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
  function unquote(s) {
    if (s ~ /^".*"$/) { s = substr(s, 2, length(s) - 2) }
    else if (s ~ /^'"'"'.*'"'"'$/) { s = substr(s, 2, length(s) - 2) }
    return s
  }
  function flush() {
    if (have) { printf "%s\037%s\037%s\037%s\n", id, what, chk, owner }
    have = 0; id = ""; what = ""; chk = ""; owner = ""
  }
  BEGIN { inblock = 0; have = 0 }
  /^##[[:space:]]+Preconditions[[:space:]]*$/ { inblock = 1; next }
  inblock && /^##[[:space:]]/ { flush(); inblock = 0 }
  inblock {
    line = $0
    if (match(line, /^[[:space:]]*-[[:space:]]+id:[[:space:]]*/)) {
      flush()
      have = 1
      id = unquote(trim(substr(line, RLENGTH + 1)))
      next
    }
    if (have && match(line, /^[[:space:]]*what:[[:space:]]*/))  { what  = unquote(trim(substr(line, RLENGTH + 1))); next }
    if (have && match(line, /^[[:space:]]*check:[[:space:]]*/)) { chk   = unquote(trim(substr(line, RLENGTH + 1))); next }
    if (have && match(line, /^[[:space:]]*owner:[[:space:]]*/)) { owner = unquote(trim(substr(line, RLENGTH + 1))); next }
  }
  END { flush() }
' "$BODY")"

DECLARED=false
if grep -qE '^##[[:space:]]+Preconditions[[:space:]]*$' "$BODY"; then
  DECLARED=true
fi

# Written with C=$((C + 1)) rather than ((C++)): under `set -e` the latter returns 1 when the
# result is 0 and aborts the script. That exact form killed a security gate on healthy
# projects once already.
MET=0
UNMET=0
UNKNOWN=0
TOTAL=0
ENTRIES="[]"

run_check() {
  # Emits: <status>\t<reason>\t<exit_code>
  local chk="$1"

  if [ -z "$chk" ]; then
    printf 'unknown\tno_check_declared\t\n'
    return 0
  fi

  case "$chk" in
    *';'*|*'|'*|*'&'*|*'$'*|*'`'*|*'>'*|*'<'*|*$'\n'*)
      printf 'unknown\tunsafe_check_shape\t\n'
      return 0
      ;;
  esac

  local -a argv=()
  read -r -a argv <<< "$chk"
  if [ "${#argv[@]}" -eq 0 ]; then
    printf 'unknown\tno_check_declared\t\n'
    return 0
  fi

  local rc=0
  if command -v timeout >/dev/null 2>&1; then
    ( cd "$CWD" && timeout "${PRECONDITIONS_CHECK_TIMEOUT:-30}" "${argv[@]}" ) >/dev/null 2>&1 || rc=$?
  else
    ( cd "$CWD" && "${argv[@]}" ) >/dev/null 2>&1 || rc=$?
  fi

  # 127 is "the checker itself is not installed", which says nothing about the precondition.
  # Reporting that as unmet would send the operator to fix the wrong thing.
  if [ "$rc" -eq 127 ]; then
    printf 'unknown\tcheck_command_not_found\t%s\n' "$rc"
  elif [ "$rc" -eq 0 ]; then
    printf 'met\t\t0\n'
  else
    printf 'unmet\tcheck_failed\t%s\n' "$rc"
  fi
}

while IFS=$'\037' read -r id what chk owner; do
  [ -n "$id$what$chk$owner" ] || continue
  TOTAL=$((TOTAL + 1))

  result="$(run_check "$chk")"
  status="$(printf '%s' "$result" | cut -f1)"
  reason="$(printf '%s' "$result" | cut -f2)"
  ec="$(printf '%s' "$result" | cut -f3)"

  case "$status" in
    met)     MET=$((MET + 1)) ;;
    unmet)   UNMET=$((UNMET + 1)) ;;
    *)       UNKNOWN=$((UNKNOWN + 1)) ;;
  esac

  ENTRIES="$(printf '%s' "$ENTRIES" | jq \
    --arg id "$id" --arg what "$what" --arg check "$chk" --arg owner "$owner" \
    --arg status "$status" --arg reason "$reason" --arg ec "$ec" \
    '. + [{
        id: $id,
        what: (if $what == "" then null else $what end),
        check: (if $check == "" then null else $check end),
        owner: (if $owner == "" then null else $owner end),
        status: $status,
        reason: (if $reason == "" then null else $reason end),
        exit_code: (if $ec == "" then null else ($ec | tonumber) end)
      }]')"
done <<< "$TSV"

if [ "$DECLARED" != true ]; then
  VERDICT="undeclared"
elif [ "$TOTAL" -eq 0 ]; then
  # A heading with nothing parseable under it is not a recipe that declared no preconditions.
  VERDICT="unknown"
elif [ "$UNMET" -gt 0 ]; then
  VERDICT="unmet"
elif [ "$UNKNOWN" -gt 0 ]; then
  VERDICT="unknown"
else
  VERDICT="met"
fi

jq -n \
  --arg phase "$PHASE" \
  --arg framework "$FRAMEWORK" \
  --arg verdict "$VERDICT" \
  --argjson declared "$DECLARED" \
  --argjson entries "$ENTRIES" \
  --argjson met "$MET" --argjson unmet "$UNMET" --argjson unknown "$UNKNOWN" --argjson total "$TOTAL" \
  '{
     schema_version: "1.0",
     phase: $phase,
     framework: (if $framework == "" then null else $framework end),
     declared: $declared,
     verdict: $verdict,
     preconditions: $entries,
     summary: { total: $total, met: $met, unmet: $unmet, unknown: $unknown }
   }'
