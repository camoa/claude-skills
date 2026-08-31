#!/usr/bin/env bash
# repair-scope-check.sh — the deterministic decision kernel for D6 of the finding-contract design
# (../../projects/ai_dev_assistant/.../finding_contract/design/finding-contract.md). Replaces
# `beyond_remedy`/`repair_growth`: instead of dispatching an agent to judge whether a repair stayed
# on topic, compare two sets of paths. A repair touching a file the finding never named is out of
# scope. No model judgment, no diff computed here — the caller supplies both sets.
#
# Inputs:
#   --finding-sites <json array of strings>  REQUIRED. The paths a finding's where[] named (D1).
#                    Pass `[]`, never omit the flag, when a finding recorded no sites — that is the
#                    absent case this kernel exists to answer honestly (see cannot_judge below).
#   --touched-files <json array of strings>  REQUIRED. The paths a repair actually touched.
#                    scripts/review-change-set.sh already computes this (its `.files` field); this
#                    kernel does not recompute a diff. Pass that output straight through.
#   --allow         <glob>                   OPTIONAL, repeatable. A touched path matching ANY
#                    --allow pattern is not counted against scope even when unnamed (e.g. a spec a
#                    repair is expected to update alongside the fix). Matched with bash's own `case`
#                    pattern matching — no filesystem globbing, no directory listing.
#   --touched-files-source <determined|undetermined>  OPTIONAL, default determined. `undetermined`
#                    means the caller could not establish what the repair touched (its diff read
#                    failed, was empty for a reason unrelated to the repair, or was never run) and
#                    forces cannot_judge regardless of what --touched-files holds — see cannot_judge
#                    below for why an empty array cannot carry this meaning on its own.
#
# Output (single JSON object to stdout):
#   { "action": "in_scope|out_of_scope|cannot_judge", "blocks": false, "decided_by": "sets|none",
#     "unnamed": [<path>, ...] }
#     action     in_scope/out_of_scope = every/not-every touched file is named or --allow-covered.
#                cannot_judge = --finding-sites was empty, OR --touched-files-source was
#                undetermined. Nothing to compare against, so this is UNMEASURED, not "fine" —
#                folding an absent site list, or an unreadable touched set, into in_scope is the
#                exact defect this repo keeps re-finding (mechanism-disposition.sh's
#                `not_searched`, proportionality-check.sh's `cannot_judge`, criterion-provenance.sh's
#                `unrecorded`). Absence must never read as an answer.
#     blocks     always false. SURFACES, never halts — a brake that fires on most repairs (most
#                touch a helper or test alongside the named site) gets bypassed, not satisfied.
#     decided_by sets | none: sets when a comparison was made, none when one could not be.
#     unnamed    every touched path neither named nor --allow-covered. Always emitted, even empty.
#
# What this cannot see: a set comparison cannot tell a touched file that was NECESSARY to the fix
# (a shared helper, a broken test) from one that is genuinely off-topic — it sees paths, never
# intent, so out_of_scope is a prompt to look, not a verdict the repair is wrong. And it inherits
# whatever the critic enumerated in where[]: a finding that under-names its own sites (D7) makes
# THIS check produce a false out_of_scope for a file the finding should have named itself. Path
# comparison is LITERAL — no normalisation, no symlink resolution, no basename matching. Two files
# with the same basename in different directories are different files here.
#
# The caller's obligation: an empty --touched-files is read as "the repair touched nothing", which
# is a real, in_scope-worthy fact — NOT as "I do not know what it touched". A caller whose diff read
# failed, returned nothing usable, or never ran (review-change-set.sh erroring, being skipped, or
# blind to untracked files in its working tree) must pass --touched-files-source undetermined and
# must never pass `[]` to mean "I could not tell". Passing `[]` for that case is what produced a
# false in_scope on this exact question before this flag existed.
#
# Exit: 0 with JSON on valid input (cannot_judge included); 2 on a bad/missing arg (fail-closed, no
# JSON verdict).

set -uo pipefail

# A value that itself looks like a flag is rejected rather than silently consumed — the same guard
# criterion-provenance.sh uses, for the same reason: `--finding-sites --allow` must not read
# "--allow" as the finding-sites value and shift the real --allow away.
require_value() {
  case "$2" in
    --*) echo "repair-scope-check: $1 needs a value, got a flag instead: $2" >&2; exit 2 ;;
  esac
}

FINDING_SITES=""; TOUCHED_FILES=""; ALLOW=(); TOUCHED_SOURCE="determined"
while [ $# -gt 0 ]; do
  case "$1" in
    --finding-sites) [ "$#" -ge 2 ] || { echo "repair-scope-check: --finding-sites needs a value" >&2; exit 2; }; require_value --finding-sites "$2"; FINDING_SITES="$2"; shift 2 ;;
    --touched-files) [ "$#" -ge 2 ] || { echo "repair-scope-check: --touched-files needs a value" >&2; exit 2; }; require_value --touched-files "$2"; TOUCHED_FILES="$2"; shift 2 ;;
    --allow) [ "$#" -ge 2 ] || { echo "repair-scope-check: --allow needs a value" >&2; exit 2; }; require_value --allow "$2"; ALLOW+=("$2"); shift 2 ;;
    --touched-files-source) [ "$#" -ge 2 ] || { echo "repair-scope-check: --touched-files-source needs a value" >&2; exit 2; }; require_value --touched-files-source "$2"; TOUCHED_SOURCE="$2"; shift 2 ;;
    *) echo "repair-scope-check: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[ -n "$FINDING_SITES" ] || { echo "repair-scope-check: --finding-sites is required" >&2; exit 2; }
[ -n "$TOUCHED_FILES" ] || { echo "repair-scope-check: --touched-files is required" >&2; exit 2; }
case "$TOUCHED_SOURCE" in
  determined|undetermined) ;;
  *) echo "repair-scope-check: --touched-files-source must be determined|undetermined" >&2; exit 2 ;;
esac

validate_array() { jq -e 'type == "array" and (all(.[]; type == "string"))' >/dev/null 2>&1 <<<"$1"; }
validate_array "$FINDING_SITES" || { echo "repair-scope-check: --finding-sites must be a JSON array of strings" >&2; exit 2; }
validate_array "$TOUCHED_FILES" || { echo "repair-scope-check: --touched-files must be a JSON array of strings" >&2; exit 2; }

emit() { jq -nc --arg a "$1" --arg d "$2" --argjson u "$3" '{action:$a, blocks:false, decided_by:$d, unnamed:$u}'; }

# --- the matrix (deterministic) ---
if [ "$(jq 'length' <<<"$FINDING_SITES")" -eq 0 ]; then
  # No sites were named. Nothing to compare against — see the header note on why this must never
  # collapse into in_scope.
  emit cannot_judge none '[]'
  exit 0
fi

if [ "$TOUCHED_SOURCE" = "undetermined" ]; then
  # The caller could not establish what the repair touched. An empty --touched-files here would
  # read identically to "the repair touched nothing", which is not the same fact — see the header's
  # "caller's obligation" note. Refuse to answer rather than let that ambiguity resolve to in_scope.
  emit cannot_judge none '[]'
  exit 0
fi

# Literal set difference: touched paths absent from finding-sites, by exact string match.
CANDIDATE=$(jq -c --argjson s "$FINDING_SITES" '[.[] | select(. as $f | ($s | index($f)) == null)]' <<<"$TOUCHED_FILES")

UNNAMED='[]'
if [ "$(jq 'length' <<<"$CANDIDATE")" -gt 0 ]; then
  if [ "${#ALLOW[@]}" -eq 0 ]; then
    UNNAMED="$CANDIDATE"
  else
    REST=()
    while IFS= read -r path; do
      COVERED=0
      for pattern in "${ALLOW[@]}"; do
        # shellcheck disable=SC2254
        # $pattern is UNQUOTED on purpose. `--allow` takes a glob, so `tests/*` has to match every
        # path under tests/. Quoting it would match only a file literally named `tests/*`, which
        # would silently disable the flag rather than fail loudly.
        case "$path" in $pattern) COVERED=1; break ;; esac
      done
      [ "$COVERED" -eq 1 ] || REST+=("$path")
    done < <(jq -r '.[]' <<<"$CANDIDATE")
    if [ "${#REST[@]}" -gt 0 ]; then
      UNNAMED=$(printf '%s\n' "${REST[@]}" | jq -R -s -c 'split("\n") | map(select(length > 0))')
    fi
  fi
fi

if [ "$(jq 'length' <<<"$UNNAMED")" -eq 0 ]; then
  emit in_scope sets '[]'
else
  emit out_of_scope sets "$UNNAMED"
fi
exit 0
