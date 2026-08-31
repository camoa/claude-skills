#!/usr/bin/env bash
# wo-critique-aggregate.sh (C5) — the fail-closed per-WO critique verdict kernel.
#
# Owner: gate_integration (sibling ②). Spec: architecture/kernels.md (AR-E). Reads the critics'
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
#   { "lens":..., "verdict":"pass|concern|critical|unresolved", "schema_version":<num, optional>,
#     "findings":[ {"severity":"concern|critical","text":...,"where":[{"file":...}],
#                     "remedy":...,"reachable_by":...,"id":...,"extends":...,
#                     "measured":null|{...}} ] }         # findings MUST be objects
# `text`, `extends` and `measured` are the critic's contract, not this kernel's: nothing here
# reads them. When schema_version >= 2.0, this kernel DOES read and enforce where[]/remedy/id
# (plus reachable_by when the file's lens is security) on every critical/concern finding — see
# shape_check() below. One malformed finding forces effective=unresolved for the WHOLE file, never
# just that finding (D3). No schema_version => pre-contract, read exactly as before this kernel
# existed; shape_check:"not_run" is recorded either way, so a skipped check never reads as clean.
# Shape and rules: agents/wo-critic.md.
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

# shape check of one critic file (D1-D5) — gated on schema_version >= 2.0; absent/unparseable/<2.0
# => not_run (pre-contract, read as today). On critical/concern findings only: where[] must be a
# non-empty array whose elements all carry `file`; remedy and id must be non-empty; reachable_by
# must be non-empty when the file's lens is security. First violation wins; index + rule recorded.
shape_check() {
  jq -c '
    def n: (. // "" | tostring | ascii_downcase | gsub("^\\s+|\\s+$";""));
    # Type-checked, not null-checked: anything that is not a non-blank string is blank. A required
    # field of the wrong type (a number, an object, an array, a bool) used to satisfy this by not
    # being null or the empty string; now only an actual non-whitespace string does.
    def blank: (type != "string") or ((.|gsub("^\\s+|\\s+$";""))=="");
    def where_bad:
      (.where) as $w
      | ($w==null) or ($w|type!="array") or (($w|length)==0)
        or ([ $w[] | (type!="object") or (.file|blank) ] | any);
    if type != "object" then {status:"not_run", reason:"critic file not an object (pre-contract)"}
    else
      (.schema_version) as $sv
      | (if $sv==null then null
         elif ($sv|type)=="number" then $sv
         # A plain `tonumber?` handles "2", "2.0" and whitespace-padded forms, but yields EMPTY
         # (not null) on a semver-shaped string like "2.0.1" — the most likely thing a critic
         # writes when it means "newer than 2.0". Take the component before the first "." and
         # parse THAT as the major version: "2.0.1" -> "2" -> 2, "2.1" -> "2" -> 2, "2abc" (no
         # dot, whole string) and "v2.0" (before-dot segment "v2") both still fail to parse and
         # stay pre-contract, same as today. `// null` turns the empty tonumber? result into a
         # value the branch below can read — without it $SHAPE comes back as "" and the
         # `--argjson shape` below aborts the entire aggregate with exit 2 and no envelope at all.
         elif ($sv|type)=="string" then
           (($sv|split(".")[0]|gsub("^\\s+|\\s+$";"")|tonumber?) // null)
         else null end) as $svn
      | (.lens // "" | n) as $lens
      | if $svn == null then
          {status:"not_run", reason:(if $sv==null then "schema_version absent (pre-contract)"
             else "schema_version "+($sv|tostring)+" unparseable (pre-contract)" end)}
        elif $svn < 2 then
          {status:"not_run", reason:("schema_version "+($sv|tostring)+" < 2.0 (pre-contract)")}
        else
          # A `findings` key that IS PRESENT and is not an array is a shape failure, not silently
          # read as "no findings". Absent or null `findings` is not a failure — that is simply no
          # findings to check. Once the container is known to be an array, an element that is not
          # itself an object is likewise a failure, not a skip: both used to fall through to an
          # empty $bad list and record shape_check:"pass" on a file the check structurally could
          # not read.
          (if (.findings != null) and ((.findings|type) != "array") then
             {status:"fail", reason:"findings is not an array"}
           else
             ([ ((.findings // []) | if type=="array" then . else [] end) | to_entries[]
                | (.key) as $i | (.value) as $f
                | if ($f|type) != "object" then {idx:$i, detail:"finding is not an object"}
                  else
                    # Which severities the where[]/remedy/reachable_by rules bind. This MUST use
                    # the same synonym set as `srank` above, not the two canonical literals.
                    # `srank` already ranks `high`, `major`, `blocker`, `rce`, `sqli` and `severe`
                    # as critical, and `medium`, `minor`, `low` and `warn` as concern. A gate
                    # matching only the two literals let every one of those through with no
                    # where[], no remedy and no id, recorded as `shape_check:"pass"` while still
                    # ranking critical and blocking the build. Two tests for one idea, in one
                    # file, disagreeing. `id`, unlike the other three, is required on every
                    # finding regardless of severity (D1, and every authority doc that names it) —
                    # so it is checked outside the $bound gate below.
                    (((.value.severity // "")|n) as $sev
                     | ($sev=="critical" or $sev=="concern"
                        or ($sev|test("crit|rce|sqli|severe|blocker|major|^high$"))
                        or ($sev|test("concern|medium|minor|^low$|warn"))) as $bound
                     | if $bound and ($f|where_bad) then {idx:$i, detail:"where[] missing/empty/not-an-array, or an element lacks file"}
                       elif $bound and ($f.remedy|blank) then {idx:$i, detail:"remedy missing or empty"}
                       elif $bound and ($lens=="security") and ($f.reachable_by|blank) then {idx:$i, detail:"lens=security and reachable_by missing or empty"}
                       elif ($f.id|blank) then {idx:$i, detail:"id missing or empty"}
                       else empty end)
                  end
              ]) as $bad
             | if ($bad|length) > 0 then {status:"fail", reason:("finding["+($bad[0].idx|tostring)+"]: "+$bad[0].detail)}
               else {status:"pass", reason:null} end
           end)
        end
    end
  ' "$1" 2>/dev/null || echo '{"status":"fail","reason":"shape check errored reading this critic file"}'
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
        '$a + [{lens:"?",verdict:"unresolved",effective:"unresolved",findings:[],note:("unreadable:"+$f),shape_check:"not_run",shape_check_reason:"file unreadable"}]')"
    else
      EFF="$(effective "$cf")"
      SHAPE="$(shape_check "$cf")"
      # GUARD THE CONSUMER, not each producer path. `shape_check` emits nothing at all for more
      # inputs than are obvious: a whitespace-only file, two concatenated JSON documents, a jq that
      # errors mid-expression. An empty $SHAPE then aborts BOTH --argjson calls below, the script
      # exits 2, and NO ENVELOPE IS WRITTEN. Every caller reads .blocking off an empty file, gets
      # nothing, writes no HALT, and the build proceeds — so a genuine `critical` from a sibling
      # critic is silently lost. Measured: main returns blocking:true on the same fixtures, this
      # path returned nothing.
      #
      # A per-cause fix was tried first and was wrong. `schema_version:"abc"` was patched at the
      # source and this whole class stayed open, because the defect is that an empty producer output
      # reaches a consumer that cannot survive one. Anything unreadable here is `not_run` with a
      # reason, which is recorded and never reads as clean.
      # Slurp, so EXACTLY ONE object is the passing condition. A per-document test is not enough:
      # two concatenated JSON documents make jq emit two objects, each of which tests fine on its
      # own, and `--argjson` still rejects the pair. That was the first version of this guard and it
      # let the same crash through.
      SHAPE="$(printf '%s' "$SHAPE" | jq -s -c '
        if (length==1 and (.[0]|type)=="object" and (.[0]|has("status")))
        then .[0]
        else {status:"not_run", reason:"shape check produced no single readable result"} end
      ' 2>/dev/null)"
      [ -n "$SHAPE" ] || SHAPE='{"status":"not_run","reason":"shape check produced no readable result"}'
      SHAPE_STATUS="$(printf '%s' "$SHAPE" | jq -r '.status' 2>/dev/null)"
      [ -n "$SHAPE_STATUS" ] || SHAPE_STATUS="not_run"
      # `effective` has the identical exposure: two documents in, two verdicts out, and EFF becomes
      # a two-line string that every comparison below silently fails to match. Collapse it the same
      # way, fail-closed to unresolved rather than to a verdict nobody computed.
      case "$EFF" in
        pass|concern|unresolved|critical) ;;
        *) EFF="unresolved" ;;
      esac
      if [ "$SHAPE_STATUS" = "fail" ]; then
        # D3: a malformed finding forces the file to (at least) unresolved — floor, not override,
        # so a finding already ranked critical never gets weakened by its own shape failure.
        EFF="$(jq -nr --arg e "$EFF" \
          'def rank(v): {"pass":0,"concern":1,"unresolved":2,"critical":3}[v] // 2;
           ([rank($e), rank("unresolved")] | max) as $r
           | {"0":"pass","1":"concern","2":"unresolved","3":"critical"}[$r|tostring]')"
      fi
      # coerce a non-object value to a safe stub so the merge can never crash (CRIT-2)
      CRITICS="$(jq -nc --argjson a "$CRITICS" --arg eff "$EFF" --argjson shape "$SHAPE" --slurpfile c "$cf" \
        '$a + [ (($c[0] // {}) | if type=="object" then . else {raw:(tostring)} end) + {effective:$eff}
                + {shape_check:$shape.status} + (if $shape.reason then {shape_check_reason:$shape.reason} else {} end) ]' 2>/dev/null \
        || jq -nc --argjson a "$CRITICS" --arg eff "$EFF" --argjson shape "$SHAPE" \
             '$a + [{lens:"?",verdict:"unresolved",effective:$eff,findings:[],shape_check:$shape.status}
                    + (if $shape.reason then {shape_check_reason:$shape.reason} else {} end)]')"
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
