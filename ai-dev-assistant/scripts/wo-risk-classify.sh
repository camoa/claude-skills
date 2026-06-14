#!/usr/bin/env bash
# wo-risk-classify.sh (C4) — classify ONE work-order's realized diff into a risk tier.
#
# Owner: gate_integration (sibling ②). Read-once spec: architecture/kernels.md (AR-C corrected).
# A PURE function of its inputs — the work-order-critique skill (C2) does the WO I/O and passes the
# frozen-field values in; this kernel never parses the WO file. Deterministic + fail-closed so it is
# testable headless (tests/wo-risk-classify-spec.sh) with zero model context.
#
# Usage:
#   wo-risk-classify.sh [<wo-file>] --files-from <changed-files.txt> \
#                       [--gate-floor <csv>] [--verified true|false] [--collapsed-scc true|false]
#
#   <wo-file>      the work-order file (optional positional). verified/gate_floor/collapsed_scc are read
#                  from its frontmatter via `wo-compile.sh frontmatter` — ①'s deterministic, anchor-
#                  rejecting parser (H1). The MODEL never transcribes these trust-bearing fields.
#   --files-from   newline-delimited list of the WO's realized changed files
#                  (git diff checkpoint_before..checkpoint_after --name-only). REQUIRED.
#   --gate-floor   comma-separated gate_floor OVERRIDE (else read from <wo-file>). Missing both => high.
#   --verified     `verified` OVERRIDE (else from <wo-file>). DEFAULTS false (fail-closed) when absent.
#   --collapsed-scc `collapsed_scc` OVERRIDE (else from <wo-file>). Defaults false.
#
# Tiering (AR-C; precedence high > medium > low):
#   unresolved (empty/missing file list OR change-impact-classify warnings) => HIGH (fail-closed).
#   HIGH  when ANY of: a security-glob matches a realized-diff file
#                    | gate_floor ⊋ base (a recipe ADDED a gate beyond the base set)
#                    | collapsed_scc == true | unresolved.
#         (`security ∈ gate_floor` is NOT a trigger — it is invariantly true in the base set.)
#         (F1 fix 2026-06-12: `verified != true` is NO LONGER a trigger — grounding-verification status is
#          orthogonal to change RISK. An unverified/override'd WO is controlled by its coverage_override +
#          the flagged PR + human-merge, not by escalating the tier to opus+red-team. Risk follows change
#          IMPACT. `verified`/`--verified` is still read but no longer drives the tier.)
#   MEDIUM when any changed file's extension is an executable_extensions match (and not HIGH).
#   LOW   otherwise (non-executable only; determinable; no security signal).
#
# Rules data: ${CLAUDE_PLUGIN_ROOT}/references/risk-tiering-rules.json (script-relative fallback).
# Output: single JSON object to stdout. ALWAYS exit 0 (issues surface in fields/warnings); non-zero
# only on a bash-level failure that prevents emitting JSON.

set -uo pipefail

# --- locate plugin root + rules (same derivation as change-impact-classify.sh) -------------
PLUGIN_ROOT="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
RULES="${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/references/risk-tiering-rules.json"
[ -f "$RULES" ] || RULES="$PLUGIN_ROOT/references/risk-tiering-rules.json"
CLASSIFY="${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/scripts/change-impact-classify.sh"
[ -f "$CLASSIFY" ] || CLASSIFY="$PLUGIN_ROOT/scripts/change-impact-classify.sh"

emit() {
  # $1 tier, $2 trigger, $3 executable(bool), $4 unresolved(bool),
  # $5 diff_signature(json array), $6 gates_recommended(json array), $7 reason
  jq -nc \
    --arg tier "$1" --arg trig "$2" \
    --argjson exec "$3" --argjson unres "$4" \
    --argjson sig "${5:-[]}" --argjson gates "${6:-[]}" \
    --arg reason "$7" \
    '{schema_version:"1.0", risk_tier:$tier, trigger:$trig,
      executable_change:$exec, unresolved:$unres,
      diff_signature:$sig, gates_recommended:$gates, reason:$reason}'
  exit 0
}

# --- arg parsing -------------------------------------------------------------
# <wo-file> (optional positional): the trust-bearing fields verified/gate_floor/collapsed_scc are read
# from it via ①'s deterministic, anchor-rejecting parser (H1) — the MODEL never transcribes them.
# Explicit --gate-floor/--verified/--collapsed-scc OVERRIDE (documented override; used by the tests).
WO_FILE=""; FILES_FROM=""; GATE_FLOOR=""; VERIFIED=""; COLLAPSED=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --files-from)    FILES_FROM="${2:-}"; shift 2 || shift ;;
    --gate-floor)    GATE_FLOOR="${2:-}"; shift 2 || shift ;;
    --verified)      VERIFIED="${2:-}";   shift 2 || shift ;;
    --collapsed-scc) COLLAPSED="${2:-}";  shift 2 || shift ;;
    --*)             shift ;;
    *)               [ -z "$WO_FILE" ] && WO_FILE="$1"; shift ;;
  esac
done

# Read trust-bearing fields from the WO file via the SAFE parser (H1); flags already set override.
COMPILE="${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/scripts/wo-compile.sh"
[ -f "$COMPILE" ] || COMPILE="$PLUGIN_ROOT/scripts/wo-compile.sh"
if [ -n "$WO_FILE" ] && [ -f "$COMPILE" ]; then
  FM="$(bash "$COMPILE" frontmatter "$WO_FILE" 2>/dev/null || echo '{}')"
  if printf '%s' "$FM" | jq -e 'type=="object" and (has("__error__")|not)' >/dev/null 2>&1; then
    [ -z "$GATE_FLOOR" ] && GATE_FLOOR="$(printf '%s' "$FM" | jq -r '(.gate_floor // []) | join(",")'      2>/dev/null || echo '')"
    [ -z "$VERIFIED"   ] && VERIFIED="$(printf '%s'   "$FM" | jq -r '(.verified // false)     | tostring'  2>/dev/null || echo '')"
    [ -z "$COLLAPSED"  ] && COLLAPSED="$(printf '%s'  "$FM" | jq -r '(.collapsed_scc // false) | tostring'  2>/dev/null || echo '')"
  fi
fi
# fail-closed defaults: verified absent => false (=> high); collapsed absent => false
[ -n "$VERIFIED" ]  || VERIFIED="false"
[ -n "$COLLAPSED" ] || COLLAPSED="false"

# --- fail-closed preconditions: undeterminable inputs => HIGH ----------------
if [ ! -f "$RULES" ]; then
  emit "high" "unresolved:rules_missing" "false" "true" "[]" "[]" "risk-tiering-rules.json not found"
fi
if [ -z "$FILES_FROM" ] || [ ! -f "$FILES_FROM" ]; then
  emit "high" "unresolved:files_missing" "false" "true" "[]" "[]" "changed-files list missing"
fi
if [ -z "$GATE_FLOOR" ]; then
  emit "high" "unresolved:gate_floor_missing" "false" "true" "[]" "[]" "gate_floor not supplied"
fi

# --- delegate to change-impact-classify.sh for signature/gates/warnings (DRY) -
SIG_JSON="[]"; GATES_JSON="[]"; CLS_WARN_N=0; FILES_CLASSIFIED=0
if [ -f "$CLASSIFY" ]; then
  CLS="$(bash "$CLASSIFY" "" --files-from "$FILES_FROM" 2>/dev/null || echo '{}')"
  SIG_JSON="$(printf '%s' "$CLS"   | jq -c '.diff_signature // []'    2>/dev/null || echo '[]')"
  GATES_JSON="$(printf '%s' "$CLS" | jq -c '.gates_recommended // []' 2>/dev/null || echo '[]')"
  CLS_WARN_N="$(printf '%s' "$CLS" | jq -r '(.warnings // []) | length' 2>/dev/null || echo 0)"
  FILES_CLASSIFIED="$(printf '%s' "$CLS" | jq -r '.files_classified // 0' 2>/dev/null || echo 0)"
fi

# --- read changed files (trusted as DATA only — matched via [[ ]], never eval'd) -
mapfile -t FILES < <(grep -v '^[[:space:]]*$' "$FILES_FROM" 2>/dev/null || true)
N_FILES="${#FILES[@]}"

# unresolved: empty diff OR the classifier reported any warning
UNRESOLVED="false"; UNRES_REASON=""
if [ "$N_FILES" -eq 0 ] || [ "$FILES_CLASSIFIED" = "0" ]; then UNRESOLVED="true"; UNRES_REASON="empty_diff"; fi
if [ "$CLS_WARN_N" != "0" ]; then UNRESOLVED="true"; UNRES_REASON="classifier_warning"; fi

# --- load rules into bash --------------------------------------------------
mapfile -t SEC_GLOBS  < <(jq -r '.security_globs[]'        "$RULES" 2>/dev/null || true)
mapfile -t EXEC_EXTS  < <(jq -r '.executable_extensions[]' "$RULES" 2>/dev/null || true)
mapfile -t BASE_FLOOR < <(jq -r '.base_gate_floor[]'       "$RULES" 2>/dev/null || true)

is_exec_ext() { local e; for e in "${EXEC_EXTS[@]}"; do [ "$1" = "$e" ] && return 0; done; return 1; }
in_base()     { local g; for g in "${BASE_FLOOR[@]}"; do [ "$1" = "$g" ] && return 0; done; return 1; }

# --- scan files for security-glob + executable signals ----------------------
SECURITY_MATCH="false"; EXEC_CHANGE="false"
for f in "${FILES[@]}"; do
  f="${f%$'\r'}"; [ -z "$f" ] && continue
  for g in "${SEC_GLOBS[@]}"; do
    # shellcheck disable=SC2053  -- intentional glob match; * spans '/'
    if [[ "$f" == $g ]]; then SECURITY_MATCH="true"; break; fi
  done
  ext=""; case "$f" in *.*) ext="${f##*.}";; esac
  ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"
  [ -n "$ext" ] && is_exec_ext "$ext" && EXEC_CHANGE="true"
done

# --- gate_floor ⊋ base ------------------------------------------------------
GATE_SUPER="false"
IFS=',' read -r -a GF <<< "$GATE_FLOOR"
for g in "${GF[@]}"; do
  g="$(printf '%s' "$g" | tr -d '[:space:]')"; [ -z "$g" ] && continue
  in_base "$g" || GATE_SUPER="true"
done

# --- decide tier (fail-closed; precedence high > medium > low) ---------------
TIER="low"; TRIGGER="none"; REASON="non-executable; determinable; no security signal"
if   [ "$UNRESOLVED" = "true" ];     then TIER="high"; TRIGGER="unresolved:$UNRES_REASON"; REASON="undeterminable diff => fail-closed high"
elif [ "$SECURITY_MATCH" = "true" ]; then TIER="high"; TRIGGER="security_glob";   REASON="realized diff matches a security-sensitive path"
elif [ "$GATE_SUPER" = "true" ];     then TIER="high"; TRIGGER="recipe_added_gate"; REASON="gate_floor superset of base (recipe-flagged)"
elif [ "$COLLAPSED" = "true" ];      then TIER="high"; TRIGGER="collapsed_scc";   REASON="WO merged a strongly-connected component"
elif [ "$EXEC_CHANGE" = "true" ];    then TIER="medium"; TRIGGER="executable_change"; REASON="executable-code change => >= medium with security lens"
fi

emit "$TIER" "$TRIGGER" "$EXEC_CHANGE" "$UNRESOLVED" "$SIG_JSON" "$GATES_JSON" "$REASON"
