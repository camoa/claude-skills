#!/usr/bin/env bash
# TDD spec for scripts/wo-ship-gate.sh (AR-B) — the ②-owned fail-closed ship verdict.
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
export CLAUDE_PLUGIN_ROOT="$ROOT"
KERNEL="$ROOT/scripts/wo-ship-gate.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

mktask() { # $1 name  $2 review_verdict|none
  local t="$TMP/$1"; mkdir -p "$t/work-orders"
  [ "$2" != "none" ] && jq -nc --arg v "$2" '{schema_version:"1.2",gate_type:"review",gate_specific:{overall_verdict:$v}}' > "$t/_review.json"
  echo "$t"
}
crit()  { jq -nc --argjson b "$2" '{schema_version:"1.0",wo_id:"wo-01",blocking:$b,overall:(if $b then "critical" else "pass" end)}' > "$1/work-orders/wo-01._critique.json"; }
assert() { # $1 label $2 want_ship $3 want_exit $4 task
  local out s rc
  out="$(bash "$KERNEL" "$4" 2>/dev/null)"; rc=$?
  s="$(jq -r '.ship_ok' <<<"$out")"
  if [ "$s" = "$2" ] && [ "$rc" -eq "$3" ]; then PASS=$((PASS+1))
  else FAIL=$((FAIL+1)); echo "FAIL $1: ship_ok=$s rc=$rc (want $2/$3)"; echo "  $out"; fi
}

T="$(mktask s1 pass)";                          assert "S1 pass clean"        true  0 "$T"
T="$(mktask s2 pass)"; : > "$T/work-orders/wo-01.HALT"; assert "S2 halt marker"  false 1 "$T"
T="$(mktask s3 pass)"; crit "$T" true;          assert "S3 blocking critique"  false 1 "$T"
T="$(mktask s4 pass)"; crit "$T" false;         assert "S4 non-blocking crit"   true  0 "$T"
T="$(mktask s5 fail)";                          assert "S5 review fail"        false 1 "$T"
T="$(mktask s6 none)";                          assert "S6 review missing"     false 1 "$T"
T="$(mktask s7 pass)"; echo '{ bad' > "$T/work-orders/wo-01._critique.json"; assert "S7 malformed crit" false 1 "$T"

# ===== red-team fail-closed regression rows (HIGH-3 / HIGH-4 / MED-9) =====
# HIGH-3: blocking present-but-not-literally-false-bool, or overall:critical => blocker
for b in 'null' '"false"' '0' '"yes"'; do
  T="$(mktask h3 pass)"; jq -nc "{overall:\"critical\",blocking:$b}" > "$T/work-orders/wo-01._critique.json"
  assert "H3 blocking=$b" false 1 "$T"
done
# HIGH-3b: blocking:false but overall:critical (inconsistent) => blocker (cross-check overall)
T="$(mktask h3b pass)"; jq -nc '{overall:"critical",blocking:false}' > "$T/work-orders/wo-01._critique.json"; assert "H3b inconsistent" false 1 "$T"
# HIGH-4: empty / whitespace / 0-byte critique => blocker (jq empty passed it before)
T="$(mktask h4 pass)";  printf '   \n' > "$T/work-orders/wo-01._critique.json"; assert "H4 whitespace crit" false 1 "$T"
T="$(mktask h4b pass)"; : > "$T/work-orders/wo-01._critique.json";              assert "H4b 0-byte crit"   false 1 "$T"
# non-object critique => blocker
T="$(mktask nob pass)"; printf '42' > "$T/work-orders/wo-01._critique.json";    assert "non-object crit"   false 1 "$T"
# MED-9: a dispatched WO file with NO critique => uncritiqued => not ship
T="$(mktask m9 pass)";  echo '# wo' > "$T/work-orders/wo-01-slug.md";           assert "M9 uncritiqued WO" false 1 "$T"
# MED-9b: WO file WITH a clean critique => ship
T="$(mktask m9b pass)"; echo '# wo' > "$T/work-orders/wo-01-slug.md"; jq -nc '{overall:"pass",blocking:false}' > "$T/work-orders/wo-01._critique.json"; assert "M9b WO+clean crit" true 0 "$T"

echo "----"; echo "wo-ship-gate-spec: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
