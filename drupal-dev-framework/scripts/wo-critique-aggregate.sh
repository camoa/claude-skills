#!/usr/bin/env bash
# wo-critique-aggregate.sh (C5) — the fail-closed per-WO critique verdict kernel.
#
# Owner: gate_integration (sibling ②). Spec: architecture/kernels.md §2 (AR-E). Reads the critics'
# verdict files FROM DISK (never a transcript). Fail-closed against MALFORMED / LABEL-DRIFTED critic
# data: it never trusts the critic's shape or labels more than the safety mandate allows. ALL verdict
# math lives here, not in the skill prose. Deterministic + testable (tests/wo-critique-aggregate-spec.sh).
#
# Usage:
#   wo-critique-aggregate.sh --wo <id> --tier <low|medium|high>
#       --mode <team|fanout|team-fallback-to-fanout|none> --expected <int>
#       --critics-dir <dir> --evaluated <true|false> [--diff-empty] [--required] [--run-at <iso>]
#
# Critic file (written by the wo-critic agent via Write): an OBJECT
#   { "lens":..., "verdict":"pass|concern|critical|unresolved",
#     "findings":[ {"severity":"concern|critical","text":...} ] }    # findings MUST be objects
#
# Fail-closed rules (AR-E + red-team CRIT-1/CRIT-2/HIGH-5/MED-7/MED-8):
#   effective(critic): non-object/empty/unparseable file => unresolved; UNKNOWN verdict => unresolved;
#     severity is normalized (lowercase+trim) + synonym-mapped, UNKNOWN severity => unresolved (NOT pass);
#     a non-object finding => unresolved. effective = max(verdict, worst finding severity).
#   missing = max(0, expected - present); each missing => unresolved. evaluated+present==0 on high/medium
#     => unresolved (min-critic). overall: diff_empty=>critical; elif !evaluated=>not_evaluated;
#     elif any critical=>critical; elif any unresolved=>(high?critical:concern); elif any concern=>concern;
#     else pass. blocking = critical | (not_evaluated&required) | (required&unresolved) | (degraded&high).
#   ALWAYS emits a JSON envelope and exits 0 (the verdict is in `blocking`).

set -uo pipefail

WO=""; TIER="high"; MODE="none"; EXPECTED=0; CDIR=""; EVALUATED="false"
DIFF_EMPTY="false"; REQUIRED="false"; RUN_AT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --wo) WO="${2:-}"; shift 2 || shift ;;
    --tier) TIER="${2:-high}"; shift 2 || shift ;;
    --mode) MODE="${2:-none}"; shift 2 || shift ;;
    --expected) EXPECTED="${2:-0}"; shift 2 || shift ;;
    --critics-dir) CDIR="${2:-}"; shift 2 || shift ;;
    --evaluated) EVALUATED="${2:-false}"; shift 2 || shift ;;
    --diff-empty) DIFF_EMPTY="true"; shift ;;
    --required) REQUIRED="true"; shift ;;
    --run-at) RUN_AT="${2:-}"; shift 2 || shift ;;
    *) shift ;;
  esac
done
# normalize / validate args (MED-7) — fail-closed
case "$TIER" in low|medium|high) ;; *) TIER="high" ;; esac
case "$EVALUATED" in true) ;; false) ;; *) EVALUATED="false" ;; esac        # garbage => false => not_evaluated
case "$EXPECTED" in ''|*[!0-9]*) EXPECTED=0 ;; esac                          # non-int => 0
case "$MODE" in team|fanout|team-fallback-to-fanout|none) ;; *) MODE="fanout" ;; esac
[ -n "$RUN_AT" ] || RUN_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"

# effective verdict of one critic file — fail-closed against label/shape drift (CRIT-1/HIGH-5).
effective() {
  jq -er '
    def n: (. // "" | tostring | ascii_downcase | gsub("^\\s+|\\s+$";""));
    def vrank(v): {"pass":0,"concern":1,"unresolved":2,"critical":3}[(v|n)] // 2;     # unknown verdict => unresolved
    def srank(s):
      (s|n) as $x
      | {"pass":0,"concern":1,"critical":3}[$x]
        // (if   ($x|test("crit|rce|sqli|severe|blocker|major|^high$")) then 3
            elif ($x|test("concern|medium|minor|^low$|warn"))           then 1
            elif ($x=="pass" or $x=="ok")                               then 0
            else 2 end);                              # missing/empty/unknown severity => unresolved (fail-closed)
    if type != "object" then 2
    else ([ vrank(.verdict) ]
          + [ (.findings // [])[] | if type=="object" then srank(.severity) else 2 end ]) | max
    end
    | {"0":"pass","1":"concern","2":"unresolved","3":"critical"}[tostring]
  ' "$1" 2>/dev/null || echo "unresolved"
}

PRESENT=0; HAS_CRIT="false"; HAS_UNRES="false"; HAS_CONCERN="false"; CRITICS='[]'
if [ -n "$CDIR" ] && [ -d "$CDIR" ]; then
  shopt -s nullglob
  for cf in "$CDIR/${WO}".critic-*.json; do
    PRESENT=$((PRESENT+1))
    if [ ! -s "$cf" ] || ! jq empty "$cf" >/dev/null 2>&1; then
      # empty / 0-byte / unparseable => unresolved (fail-closed, HIGH-5) — before effective()
      EFF="unresolved"
      CRITICS="$(jq -nc --argjson a "$CRITICS" --arg f "$(basename "$cf")" \
        '$a + [{lens:"?",verdict:"unresolved",effective:"unresolved",findings:[],note:("unreadable:"+$f)}]')"
    else
      EFF="$(effective "$cf")"
      # coerce a non-object value to a safe stub so the merge can never crash (CRIT-2)
      CRITICS="$(jq -nc --argjson a "$CRITICS" --arg eff "$EFF" --slurpfile c "$cf" \
        '$a + [ (($c[0] // {}) | if type=="object" then . else {raw:(tostring)} end) + {effective:$eff} ]' 2>/dev/null \
        || jq -nc --argjson a "$CRITICS" --arg eff "$EFF" '$a + [{lens:"?",verdict:"unresolved",effective:$eff,findings:[]}]')"
    fi
    case "$EFF" in
      critical)   HAS_CRIT="true" ;;
      unresolved) HAS_UNRES="true" ;;
      concern)    HAS_CONCERN="true" ;;
    esac
  done
  shopt -u nullglob
fi

MISSING=$(( EXPECTED - PRESENT )); [ "$MISSING" -lt 0 ] && MISSING=0
[ "$MISSING" -gt 0 ] && HAS_UNRES="true"
# min-critic: an EVALUATED high/medium WO with zero critics is fail-closed unresolved (MED-8)
if [ "$EVALUATED" = "true" ] && [ "$PRESENT" -eq 0 ]; then
  case "$TIER" in high|medium) HAS_UNRES="true" ;; esac
fi

# --- overall ---------------------------------------------------------------
if   [ "$DIFF_EMPTY" = "true" ];  then OVERALL="critical"
elif [ "$EVALUATED" != "true" ];  then OVERALL="not_evaluated"
elif [ "$HAS_CRIT" = "true" ];    then OVERALL="critical"
elif [ "$HAS_UNRES" = "true" ];   then [ "$TIER" = "high" ] && OVERALL="critical" || OVERALL="concern"
elif [ "$HAS_CONCERN" = "true" ]; then OVERALL="concern"
else OVERALL="pass"; fi

DEGRADED="false"; [ "$MODE" = "team-fallback-to-fanout" ] && DEGRADED="true"

# --- blocking (fail-closed) ------------------------------------------------
BLOCKING="false"
if   [ "$OVERALL" = "critical" ]; then BLOCKING="true"
elif [ "$OVERALL" = "not_evaluated" ] && [ "$REQUIRED" = "true" ]; then BLOCKING="true"
elif [ "$REQUIRED" = "true" ] && [ "$HAS_UNRES" = "true" ]; then BLOCKING="true"
elif [ "$DEGRADED" = "true" ] && [ "$TIER" = "high" ]; then BLOCKING="true"
fi

# --- halt_reason (M2 — kernel-emitted; the skill copies it onto the HALT marker) -
HALT='null'
if [ "$BLOCKING" = "true" ]; then
  if   [ "$DIFF_EMPTY" = "true" ];                               then HALT='"diff_empty"'
  elif [ "$OVERALL" = "critical" ];                              then HALT='"critique_critical"'
  elif [ "$OVERALL" = "not_evaluated" ];                         then HALT='"not_evaluated_required"'
  elif [ "$DEGRADED" = "true" ] && [ "$TIER" = "high" ];         then HALT='"degraded_high"'
  else                                                                HALT='"required_unresolved"'
  fi
fi

jq -nc \
  --arg wo "$WO" --arg tier "$TIER" --arg mode "$MODE" --arg at "$RUN_AT" \
  --argjson evaluated "$EVALUATED" --argjson expected "$EXPECTED" --argjson present "$PRESENT" \
  --argjson missing "$MISSING" --argjson critics "$CRITICS" \
  --arg overall "$OVERALL" --argjson blocking "$BLOCKING" --argjson degraded "$DEGRADED" \
  --argjson diff_empty "$DIFF_EMPTY" --argjson required "$REQUIRED" --argjson halt_reason "$HALT" \
  '{schema_version:"1.0", wo_id:$wo, risk_tier:$tier, run_at:$at, mode:$mode,
    evaluated:$evaluated, required:$required, expected_critics:$expected, present:$present,
    missing:$missing, critics:$critics, overall:$overall, blocking:$blocking,
    degraded:$degraded, diff_empty:$diff_empty, halt_reason:$halt_reason}'
