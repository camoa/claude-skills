#!/usr/bin/env bash
# TDD spec for scripts/wo-review-snapshot.sh (C6) — architecture/kernels.md.
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
export CLAUDE_PLUGIN_ROOT="$ROOT"
KERNEL="$ROOT/scripts/wo-review-snapshot.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); }
no() { FAIL=$((FAIL+1)); echo "FAIL $1"; }

mktask() { # $1 name  $2 with_review(bool)  $3 n_envelopes
  local t="$TMP/$1"; mkdir -p "$t/validations/latest"
  local i=0
  for g in solid security tdd; do
    [ "$i" -ge "$3" ] && break
    jq -nc --arg g "$g" '{schema_version:"1.0",gate:$g,verdict:"pass"}' > "$t/validations/latest/$g.json"; i=$((i+1))
  done
  if [ "$2" = "true" ]; then
    jq -nc --arg t "$t" '{schema_version:"1.2",gate_type:"review",fired_at:"x",task_folder:$t,
      gate_specific:{overall_verdict:"pass",gates_run:[
        {name:"solid",verdict:"pass",envelope_path:($t+"/validations/latest/solid.json")}]}}' > "$t/_review.json"
  fi
  echo "$t"
}

# T1 — review + 3 envelopes => ok:true, gates:3, review_ref written
T="$(mktask t1 true 3)"
OUT="$(bash "$KERNEL" "$T" wo-01)"; RC=$?
[ "$RC" -eq 0 ] && [ "$(jq -r '.ok' <<<"$OUT")" = "true" ] && [ "$(jq -r '.gates' <<<"$OUT")" = "3" ] \
  && [ -f "$T/work-orders/wo-01._review.json" ] && ok || no "T1 snapshot ok/gates/review_ref"
# T3 — envelope_path rewritten latest/ => wo-01/
NEWPATH="$(jq -r '.gate_specific.gates_run[0].envelope_path' "$T/work-orders/wo-01._review.json")"
[[ "$NEWPATH" == */validations/wo-01/solid.json ]] && ok || no "T3 envelope_path rewrite (got $NEWPATH)"
# snapshot dir has the 3 envelopes
[ "$(ls "$T/validations/wo-01" | wc -l)" -eq 3 ] && ok || no "T1b snapshot dir has 3"

# T2 — missing _review.json => non-zero, ok:false, no review_ref
T="$(mktask t2 false 0)"
OUT="$(bash "$KERNEL" "$T" wo-01 2>/dev/null)"; RC=$?
[ "$RC" -ne 0 ] && [ "$(jq -r '.ok' <<<"$OUT")" = "false" ] && [ ! -f "$T/work-orders/wo-01._review.json" ] \
  && ok || no "T2 missing review => fail-closed"

# T4 — review present, latest/ empty => ok:true gates:0
T="$(mktask t4 true 0)"
OUT="$(bash "$KERNEL" "$T" wo-02)"; RC=$?
[ "$RC" -eq 0 ] && [ "$(jq -r '.gates' <<<"$OUT")" = "0" ] && [ -f "$T/work-orders/wo-02._review.json" ] \
  && ok || no "T4 empty latest => ok gates:0"

# T5 — wo-id with shell metacharacters => rejected, no review_ref
T="$(mktask t5 true 1)"
OUT="$(bash "$KERNEL" "$T" 'wo;rm -rf x' 2>/dev/null)"; RC=$?
[ "$RC" -eq 2 ] && [ "$(jq -r '.reason' <<<"$OUT")" = "bad_wo_id" ] && ok || no "T5 metachar wo-id rejected"
# L11 — newline-containing wo-id must be rejected (line-oriented grep bypass)
T="$(mktask l11 true 1)"
OUT="$(bash "$KERNEL" "$T" "$(printf 'wo-01\nrm -rf x')" 2>/dev/null)"; RC=$?
[ "$RC" -eq 2 ] && [ ! -f "$T/work-orders/wo-01._review.json" ] && ok || no "L11 newline wo-id rejected"

echo "----"; echo "wo-review-snapshot-spec: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
