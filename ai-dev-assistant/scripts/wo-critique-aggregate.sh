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
#       [--component-files-from <path>]
#
# Critic file (written by the wo-critic agent via Write): an OBJECT
#   { "lens":..., "verdict":"pass|concern|critical|unresolved", "schema_version":<num, optional>,
#     "findings":[ {"severity":"concern|critical","text":...,"where":[{"file":...}],
#                     "remedy":...,"reachable_by":...,"id":...,"extends":...,
#                     "measured":null|{...}} ] }         # findings MUST be objects
# `text` and `measured` are the critic's contract, not this kernel's: nothing here reads them.
# `extends` IS read — see the under-enumeration pass below.
# When schema_version >= 2.0, this kernel DOES read and enforce where[]/remedy/id
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
#
# Range check (--component-files-from) — a build finding is a defect in the SLICE'S OWN code.
#   The same set comparison as scripts/repair-scope-check.sh, turned around: there, a repair's
#   touched files against the sites a finding named; here, a finding's sites against the range the
#   critics were handed (`<component>.files.txt`, one path per line). A finding EVERY one of whose
#   where[] sites falls outside that range is marked `out_of_range:true`, is dropped from the
#   `effective` computation (so it cannot make `blocking` true and cannot open a repair round), and
#   is collected into the envelope's top-level `out_of_range[]` so the review phase still reads it.
#   Comparison is LITERAL — no normalisation, no basename matching — same as repair-scope-check.sh.
#   A finding with no readable where[] is NOT out of range: it cannot be judged, and shape_check
#   already refuses those at critical/concern. So is any where[] entry whose `file` is not a string.
#   THE FLAG ABSENT IS ITS OWN VALUE. `range_check.status` is `not_run` with a reason whenever no
#   comparison was made — flag absent, file unreadable, or list empty — and `out_of_range:[]` then
#   means "nobody looked", not "every finding was in range". A false all-clear is worse than silence.
#   The file's own top-level `verdict` is dropped only when EVERY finding it carries is out of range
#   and it carries at least one, AND the verdict is a rankable summary of those findings that claims
#   no more than they did. agents/wo-critic.md defines the verdict as the max over the
#   findings ("the kernel takes the worst severity across your findings and lifts your whole verdict
#   to it"), so a verdict summarising nothing in range summarises nothing. Two verdicts are not that
#   summary and survive the drop. `unresolved` means the critic could not investigate — the same
#   file says so at :218-219, "which is a different thing and still blocks" — and `severity` is
#   concern|critical only, so the file verdict is the only field that signal can live in; dropping it
#   converts "I could not settle this" into a clean pass, which was measured happening before this
#   condition existed. An unrecognised verdict ranks the same way, fail-closed. And a verdict ranking
#   ABOVE every suppressed finding is claiming something the range check never judged, so it stands.
#   One in-range finding, or no findings at all, and the verdict stands untouched: a verdict names no site of its own, so it
#   is not a thing this kernel can judge against a range on its own.
#
# Design change — a finding whose only fix is to build it a different way is not this build's.
#   Same routing as the range check above, different trigger, and the trigger is the CRITIC'S, not
#   this kernel's: a finding carrying `design_change: true` is dropped from the `effective`
#   computation (so it cannot make `blocking` true and cannot open a repair round) and is collected
#   into the envelope's top-level `design_change[]` for the review phase. The kernel cannot compute
#   this one. Whether a remedy can be applied without swapping the mechanism the component's design
#   names is a reading of the design, and only the party holding the design can do it — which is why
#   the dispatch hands the critic the design body (`references/gate-hardening-prompts.md`,
#   `critic-dispatch`). agents/wo-critic.md defines when a critic sets the flag.
#   ONLY THE JSON LITERAL `true` COUNTS. A string "true", a 1, a null, an absent key: none of them
#   suppress, so every unrecognised value fails toward opening the round. That is the same direction
#   as every other read here, and it matters more than usual because this flag is critic-authored.
#   It grants the critic no authority it did not already have: a critic that wants a component not to
#   block writes `verdict: "pass"` and files nothing, which is cheaper than marking a finding.
#   The verdict-drop rule below is shared with the range check and reads BOTH: a file's own verdict is
#   a max over its findings, so a verdict summarising only suppressed findings — out of range,
#   design-change, or a mix — summarises nothing that survived. The three conditions are unchanged.
#   `design_change[]` carries `remedy` as well as the sites, which `out_of_range[]` does not: the
#   remedy IS the trigger here, so a reviewer deciding whether the design or the finding gives way
#   cannot read the record without it.
#
# Under-enumeration (D7) — `extends` is a declared link, and it is READ here.
#   A finding carrying a non-blank `extends` naming the `id` of another finding ANYWHERE in this
#   aggregation appends its where[] sites to that finding (deduplicated, order preserved) and sets
#   `under_enumerated:true` on the REFERENCED finding; the extending finding records
#   `extends_resolved:true`. An `extends` naming an id that exists nowhere, or naming its own id,
#   records `extends_resolved:false` with a reason naming the id — never silently dropped, never
#   read as resolved. THIS RECORDS THE LINK, IT DOES NOT CONTROL THE LOOP: the pass runs AFTER every
#   `effective` is computed, so an extending finding contributes to severity exactly as before.
#   Single pass, no transitive chains: a finding's appended sites are the ORIGINAL where[] of each
#   finding extending it, so f3->f2->f1 gives f1 f2's sites and not f3's. An id carried by more than
#   one finding appends to every finding carrying it; keeping ids unique is the critic's job.

set -uo pipefail

WO=""; TIER="high"; MODE="none"; EXPECTED=0; CDIR=""; EVALUATED="false"
DIFF_EMPTY="false"; REQUIRED="false"; RUN_AT=""; NOT_DISPATCHED="[]"; ND_INVALID=0
CFILES=""; CF_BADVALUE=0
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
    --not-dispatched) # <lens>:<reason>, repeatable: a lens the caller chose not to run, and why.
      # Only `correctness` with a non-empty reason is accepted (the no-body rule). Anything else,
      # a malformed value included, is recorded with accepted:false and COUNTED AS A MISSING CRITIC:
      # the kernel always emits an envelope, so a withheld lens can never read as a clean run.
      ND_RAW="${2:-}"; case "$ND_RAW" in --*) ND_RAW="" ;; esac; ND_L="$(printf '%s' "${ND_RAW%%:*}" | tr -d '[:space:]')"; ND_R="$(printf '%s' "${ND_RAW#*:}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      ND_OK="false"; [[ "$ND_RAW" == *:* ]] && [ "$ND_L" = "correctness" ] && [ -n "$ND_R" ] && ND_OK="true"
      [ "$ND_OK" = "true" ] || ND_INVALID=$((ND_INVALID + 1))
      NOT_DISPATCHED=$(jq -c --arg l "$ND_L" --arg r "$ND_R" --argjson ok "$ND_OK" '. + [{lens:$l,reason:$r,accepted:$ok}]' <<<"$NOT_DISPATCHED")
      [ -n "$ND_RAW" ] && shift 2 || shift ;;
    --component-files-from) # the component's realized range, one path per line (<component>.files.txt)
      # A value that is itself a flag is rejected rather than consumed, and the flag is left for the
      # loop to parse — the guard repair-scope-check.sh's require_value() applies, minus the exit:
      # this kernel's contract is that it ALWAYS emits an envelope, so a bad value becomes not_run.
      CFILES="${2:-}"; case "$CFILES" in --*) CFILES=""; CF_BADVALUE=1 ;; esac
      [ -n "$CFILES" ] && shift 2 || shift ;;
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

# --- the component's range (c5) ---------------------------------------------
# RANGE is `null` when no comparison can be made, and the JSON array of paths when one can. Every
# not_run branch carries a reason, because `out_of_range:[]` with no reason beside it reads exactly
# like "every finding was in range" — the false all-clear this repo has shipped three times.
RANGE='null'; RANGE_STATUS="not_run"; RANGE_REASON="--component-files-from absent: no range to compare against"
if [ "$CF_BADVALUE" -eq 1 ] && [ -z "$CFILES" ]; then
  RANGE_REASON="--component-files-from was given a flag, not a path"
elif [ -n "$CFILES" ]; then
  if [ ! -f "$CFILES" ] || [ ! -r "$CFILES" ]; then
    RANGE_REASON="component file list unreadable: $CFILES"
  else
    R="$(jq -R -s -c '[ split("\n")[] | gsub("^\\s+|\\s+$";"") | select(length > 0) ]' < "$CFILES" 2>/dev/null)"
    if [ -z "$R" ] || [ "$(jq 'length' <<<"$R" 2>/dev/null)" = "0" ]; then
      # An empty range would put EVERY sited finding outside it and suppress the lot. That is a
      # component that changed nothing (--diff-empty's case), not a licence to drop every finding.
      RANGE_REASON="component file list is empty: $CFILES"
    else
      RANGE="$R"; RANGE_STATUS="ran"; RANGE_REASON=""
    fi
  fi
fi

# The out-of-range test for ONE finding, as a jq definition, shared verbatim by effective() and the
# merge below so the severity that is dropped and the finding that is marked can never disagree.
# $range null (no comparison made) makes this false everywhere: nothing is suppressed when nobody
# looked. `all` over a guarded non-empty array, so a where[] entry that is not an object, or whose
# `file` is not a string, makes the whole finding NOT out of range — unjudgeable is not outside.
# `.file` is bound to $p BEFORE the `$range | index(...)`: inside index() the input is $range, so
# a bare `index(.file)` indexes the range array with a string and errors the whole filter out.
#
# `dsg` is the critic-authored sibling: the JSON literal `true` and nothing else, so a string, a
# number, a null and an absent key all fail toward opening the round. `suppressed` is what the
# verdict math reads; `oor` stays separate because the merge below marks `out_of_range:true` on the
# findings THIS KERNEL judged, and a design-change finding was marked by the critic already.
SUPPRESS_DEF='def oor:
    ($range != null)
    and ((.where|type) == "array") and ((.where|length) > 0)
    and ([ .where[]
           | if (type == "object") and ((.file|type) == "string")
             then (.file as $p | ($range | index($p)) == null)
             else false end ] | all);
  def dsg: (.design_change == true);
  def suppressed: (oor or dsg);'

# effective verdict of one critic file — fail-closed against label/shape drift (CRIT-1/HIGH-5).
# $2 is the range (a JSON array, or `null` when no range check ran).
effective() {
  jq -er --argjson range "$2" "$SUPPRESS_DEF"'
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
    else
      # `(.findings // [])[]` is kept EXACTLY as it was: a `findings` value that is not an array
      # errors here, jq exits non-zero and the `||` below returns unresolved. That fail-closed path
      # predates the range check and a rewrite to a type-guarded form would quietly turn it into a
      # pass. Bind it once, so the same list feeds the ranks and the out-of-range count.
      [ (.findings // [])[] ] as $fs
      | [ $fs[] | if type=="object" then (if suppressed then empty else srank(.severity) end) else 2 end ] as $ranks
      | [ $fs[] | select((type=="object") and suppressed) ] as $supfs
      | ($supfs | length) as $nsup
      | (if $nsup > 0 then ([ $supfs[] | srank(.severity) ] | max) else -1 end) as $supmax
      | vrank(.verdict) as $v
      # The verdict is dropped only when it summarises nothing that survived suppression, and only
      # as far as the suppressed findings themselves went. Three conditions, all required: every
      # finding suppressed (out of range, design-change, or a mix) and at least one finding; the
      # verdict is a rankable summary (rank 2 is `unresolved` or an unrecognised label, neither of
      # which is a max over findings); and it ranks no higher than the worst finding that was
      # actually suppressed. See the header notes on why each one is there. Reading BOTH triggers
      # here is what stops a design-change route that records a flag and opens the round anyway:
      # a critic files `verdict: "critical"` alongside a critical finding, so a rule that dropped
      # the finding and kept the verdict would leave `blocking` exactly where it was.
      | (if ($fs|length) > 0 and $nsup == ($fs|length) and $v != 2 and $v <= $supmax
         then [] else [ $v ] end) as $vr
      | ($vr + $ranks) | if length == 0 then 0 else max end
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
      EFF="$(effective "$cf" "$RANGE")"
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
      # coerce a non-object value to a safe stub so the merge can never crash (CRIT-2), and mark
      # each out-of-range finding on the copy the envelope carries. The per-critic file on disk is
      # never touched (wo-critique-aggregate-spec.sh T-cc3 asserts the bytes).
      CRITICS="$(jq -nc --argjson a "$CRITICS" --arg eff "$EFF" --argjson shape "$SHAPE" --argjson range "$RANGE" --slurpfile c "$cf" \
        "$SUPPRESS_DEF"'$a + [ (($c[0] // {}) | if type=="object" then . else {raw:(tostring)} end)
                | (if (.findings|type) == "array"
                   then .findings |= map(if (type == "object") and oor then . + {out_of_range:true} else . end)
                   else . end)
                | . + {effective:$eff}
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

# clean returns: verdict pass with nothing in findings[]. Credited HERE, from fields the critic already
# writes; the per-critic file gets no key for it (agents/wo-critic.md says why). Consumer: the epic's
# empty-return rate, read per critique off this envelope.
# Read off `effective`, the ranking the loop just computed, so the count agrees with the envelope: a
# malformed findings value ranks unresolved and is not clean, and cannot zero a sibling's credit.
CLEAN_RETURNS="$(jq -r '[.[] | select(.effective=="pass" and ((.findings // []) | type=="array" and length==0))] | length' <<<"$CRITICS" 2>/dev/null)"; [ -n "$CLEAN_RETURNS" ] || CLEAN_RETURNS=0
# --- out_of_range[] (c5): handed to review rather than discarded -------------
# Derived BEFORE the under-enumeration pass, so what is recorded here is what was judged: an
# `extends` append can add sites to a finding after the fact, and this record must not drift.
# `[]` alone means nothing — read it beside range_check.status, which says whether anyone looked.
OUT_OF_RANGE="$(jq -c '[ .[] | (.lens // null) as $l
  | ((.findings // []) | if type=="array" then .[] else empty end)
  | select((type == "object") and (.out_of_range == true))
  | {lens:$l, id:(.id // null), severity:(.severity // null), where:(.where // [])} ]' <<<"$CRITICS" 2>/dev/null)"
[ -n "$OUT_OF_RANGE" ] || OUT_OF_RANGE='[]'

# --- design_change[]: handed to review rather than repaired here ------------
# Derived at the same point and for the same reason as `out_of_range[]` above: before the
# under-enumeration pass, so what is recorded is what was judged. `remedy` rides along because the
# remedy is this route's whole trigger — the finding is here BECAUSE its remedy cannot be applied
# without swapping the mechanism the design names, and a reviewer weighing the design against the
# finding cannot do it from the sites alone. `[]` means no critic marked one; it does not mean no
# critic was given the design to mark it against. Nothing this kernel can see says which, so it
# claims neither: the dispatch is what guarantees the critic held the design, and
# tests/build-critique-wiring-spec.sh is what checks the dispatch.
DESIGN_CHANGE="$(jq -c '[ .[] | (.lens // null) as $l
  | ((.findings // []) | if type=="array" then .[] else empty end)
  | select((type == "object") and (.design_change == true))
  | {lens:$l, id:(.id // null), severity:(.severity // null), where:(.where // []),
     remedy:(.remedy // null), text:(.text // null)} ]' <<<"$CRITICS" 2>/dev/null)"
[ -n "$DESIGN_CHANGE" ] || DESIGN_CHANGE='[]'

# --- under-enumeration (c3, D7): `extends` is read here ----------------------
# Runs AFTER every `effective` is computed and after clean_returns is counted: this pass records a
# link, it does not control the loop, and it must not move a verdict. It adds keys to findings in
# the envelope only; it never adds or removes a finding, and never touches a file on disk.
CRITICS_PRE="$CRITICS"
CRITICS="$(jq -c '
  def blank: (type != "string") or ((.|gsub("^\\s+|\\s+$";"")) == "");
  def warr: (.where // []) | if type == "array" then . else [] end;
  [ .[] | (.findings // []) | if type == "array" then .[] else empty end | select(type == "object") ] as $all
  | [ $all[] | select((.id|blank) | not) | .id ] as $ids
  # One pass, from the ORIGINAL where[] of each extender: a link to an id nobody carries, and a link
  # to the extender'"'"'s own id, are both excluded here and recorded as failures on the extender below.
  | [ $all[] | select((.extends|blank) | not) | select(.extends != .id)
      | . as $x | select(($ids | index($x.extends)) != null) | {ext: .extends, w: warr} ] as $links
  | map(if (.findings|type) == "array" then
          .findings |= map(
            if type == "object" then
              . as $f
              | (if ($f.id|blank) then [] else [ $links[] | select(.ext == $f.id) ] end) as $inc
              | (if ($inc|length) > 0
                 then . + {under_enumerated: true,
                           where: (reduce ([ $inc[].w[] ] | .[]) as $e (warr;
                                     if index($e) then . else . + [$e] end))}
                 else . end)
              | (if ($f.extends|blank) then .
                 elif $f.extends == $f.id
                   then . + {extends_resolved: false,
                             extends_reason: ("extends names its own id \"" + ($f.extends|tostring) + "\"")}
                 elif ($ids | index($f.extends)) != null
                   then . + {extends_resolved: true}
                 else . + {extends_resolved: false,
                           extends_reason: ("extends names an unknown id \"" + ($f.extends|tostring) + "\"")}
                 end)
            else . end)
        else . end)' <<<"$CRITICS_PRE" 2>/dev/null)"
# Fall back to the UN-annotated critics, never to `[]`: this pass adds a record, and a pass that
# errored must not be able to empty the critics list and turn a critical run into a clean one.
[ -n "$CRITICS" ] || CRITICS="$CRITICS_PRE"

MISSING=$(( EXPECTED - PRESENT )); [ "$MISSING" -lt 0 ] && MISSING=0
MISSING=$(( MISSING + ND_INVALID ))                      # a withheld lens the rule does not cover is missing
[ "$MISSING" -gt 0 ] && HAS_UNRES="true"
# a lens withheld with zero critics present is unresolved at every tier, low included: nobody looked
[ "$NOT_DISPATCHED" != "[]" ] && [ "$PRESENT" -eq 0 ] && HAS_UNRES="true"
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
  --argjson not_dispatched "$NOT_DISPATCHED" --argjson clean "$CLEAN_RETURNS" \
  --arg rstatus "$RANGE_STATUS" --arg rreason "$RANGE_REASON" --argjson oor "$OUT_OF_RANGE" \
  --argjson dsg "$DESIGN_CHANGE" \
  '{schema_version:"1.0", wo_id:$wo, risk_tier:$tier, run_at:$at, mode:$mode,
    evaluated:$evaluated, required:$required, expected_critics:$expected, clean_returns:$clean, present:$present,
    missing:$missing, critics:$critics, overall:$overall, blocking:$blocking,
    degraded:$degraded, diff_empty:$diff_empty, halt_reason:$halt_reason,
    not_dispatched:$not_dispatched,
    range_check:{status:$rstatus, decided_by:(if $rstatus=="ran" then "sets" else "none" end),
                 reason:(if $rreason=="" then null else $rreason end)},
    out_of_range:$oor, design_change:$dsg}'
