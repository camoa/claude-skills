#!/usr/bin/env bash
# TDD spec for scripts/wo-critique-aggregate.sh (C5) — architecture/kernels.md (AR-E).
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
export CLAUDE_PLUGIN_ROOT="$ROOT"
KERNEL="$ROOT/scripts/wo-critique-aggregate.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
WO="wo-01"

newdir() { local d; d="$(mktemp -d "$TMP/cd.XXXX")"; echo "$d"; }
critic() { # $1 dir $2 k $3 verdict [$4 finding-severity]
  if [ -n "${4:-}" ]; then
    jq -nc --arg v "$3" --arg fs "$4" '{lens:"skeptic",verdict:$v,findings:[{severity:$fs,text:"x"}]}' > "$1/${WO}.critic-$2.json"
  else
    jq -nc --arg v "$3" '{lens:"skeptic",verdict:$v,findings:[]}' > "$1/${WO}.critic-$2.json"
  fi
}
assert() { # $1 label $2 want_overall $3 want_blocking $4.. args
  local label="$1" eo="$2" eb="$3"; shift 3
  local out o b
  out="$(bash "$KERNEL" "$@")"
  o="$(jq -r '.overall' <<<"$out")"; b="$(jq -r '.blocking' <<<"$out")"
  if [ "$o" = "$eo" ] && [ "$b" = "$eb" ]; then PASS=$((PASS+1))
  else FAIL=$((FAIL+1)); echo "FAIL $label: overall=$o blocking=$b (want $eo/$eb)"; echo "  $out"; fi
}

# T1 high/team/3 pass => pass / false
d="$(newdir)"; critic "$d" 1 pass; critic "$d" 2 pass; critic "$d" 3 pass
assert "T1 all pass"        pass    false --wo $WO --tier high --mode team --expected 3 --critics-dir "$d" --evaluated true
# T2 one critical => critical / true
d="$(newdir)"; critic "$d" 1 pass; critic "$d" 2 critical; critic "$d" 3 pass
assert "T2 one critical"    critical true  --wo $WO --tier high --mode fanout --expected 3 --critics-dir "$d" --evaluated true
# T3 medium one concern => concern / false
d="$(newdir)"; critic "$d" 1 concern; critic "$d" 2 pass
assert "T3 medium concern"  concern false --wo $WO --tier medium --mode fanout --expected 2 --critics-dir "$d" --evaluated true
# T4 high expected3 present2 (1 missing) => critical / true
d="$(newdir)"; critic "$d" 1 pass; critic "$d" 2 pass
assert "T4 high missing"    critical true  --wo $WO --tier high --mode fanout --expected 3 --critics-dir "$d" --evaluated true
# T5 low expected1 present0 NOT required => concern / false
d="$(newdir)"
assert "T5 low dead notreq" concern false --wo $WO --tier low --mode fanout --expected 1 --critics-dir "$d" --evaluated true
# T6 evaluated false low not required => not_evaluated / false
d="$(newdir)"
assert "T6 not_eval off"    not_evaluated false --wo $WO --tier low --mode none --expected 1 --critics-dir "$d" --evaluated false
# T7 evaluated false high required => not_evaluated / true
d="$(newdir)"
assert "T7 not_eval req"    not_evaluated true  --wo $WO --tier high --mode none --expected 1 --critics-dir "$d" --evaluated false --required
# T8 team-fallback-to-fanout high all pass => pass / true (degraded high)
d="$(newdir)"; critic "$d" 1 pass
assert "T8 degraded high"   pass    true  --wo $WO --tier high --mode team-fallback-to-fanout --expected 1 --critics-dir "$d" --evaluated true
# T9 diff-empty + meets-ac critical => critical / true
d="$(newdir)"; critic "$d" 1 critical
assert "T9 diff-empty"      critical true  --wo $WO --tier high --mode fanout --expected 1 --critics-dir "$d" --evaluated true --diff-empty
# T9b diff-empty + all pass => still critical / true (unconditional)
d="$(newdir)"; critic "$d" 1 pass
assert "T9b diff-empty pass" critical true --wo $WO --tier medium --mode fanout --expected 1 --critics-dir "$d" --evaluated true --diff-empty
# T10 critics-dir empty high evaluated true expected3 => critical / true
d="$(newdir)"
assert "T10 empty dir high" critical true  --wo $WO --tier high --mode fanout --expected 3 --critics-dir "$d" --evaluated true
# T11 malformed critic => unresolved => high critical / true
d="$(newdir)"; echo '{ not json' > "$d/${WO}.critic-1.json"
assert "T11 malformed"      critical true  --wo $WO --tier high --mode fanout --expected 1 --critics-dir "$d" --evaluated true
# F8 pass verdict + critical finding => effective critical => critical / true
d="$(newdir)"; critic "$d" 1 pass critical
assert "F8 finding overrides" critical true --wo $WO --tier high --mode fanout --expected 1 --critics-dir "$d" --evaluated true
# Extra: low required, dead critic => blocking (required+unresolved any tier)
d="$(newdir)"
assert "Tx low req dead"    concern true  --wo $WO --tier low --mode fanout --expected 1 --critics-dir "$d" --evaluated true --required

# ===== red-team fail-closed regression rows (CRIT-1 / CRIT-2 / HIGH-5 / MED-7 / MED-8) =====
# CRIT-1: unknown/synonym/case/string/missing severity must NOT default to pass
d="$(newdir)"; critic "$d" 1 pass high;     assert "C1 synonym high"   critical true --wo $WO --tier high --mode fanout --expected 1 --critics-dir "$d" --evaluated true
d="$(newdir)"; critic "$d" 1 pass Critical; assert "C1 case Critical"  critical true --wo $WO --tier high --mode fanout --expected 1 --critics-dir "$d" --evaluated true
d="$(newdir)"; critic "$d" 1 pass blocker;  assert "C1 blocker"        critical true --wo $WO --tier high --mode fanout --expected 1 --critics-dir "$d" --evaluated true
d="$(newdir)"; critic "$d" 1 concern high;  assert "C1 concern+high"   critical true --wo $WO --tier high --mode fanout --expected 1 --critics-dir "$d" --evaluated true
d="$(newdir)"; jq -nc '{lens:"x",verdict:"pass",findings:["CRITICAL: rce"]}' > "$d/${WO}.critic-1.json"
                                            assert "C1 string finding" critical true --wo $WO --tier high --mode fanout --expected 1 --critics-dir "$d" --evaluated true
d="$(newdir)"; jq -nc '{lens:"x",verdict:"pass",findings:[{text:"creds"}]}' > "$d/${WO}.critic-1.json"
                                            assert "C1 no-severity"    critical true --wo $WO --tier high --mode fanout --expected 1 --critics-dir "$d" --evaluated true
# CRIT-2: non-object critic file must not crash; fail-closed unresolved => high critical
for v in '42' '[1,2,3]' '"s"' 'true'; do
  d="$(newdir)"; printf '%s' "$v" > "$d/${WO}.critic-1.json"
  assert "C2 non-object $v" critical true --wo $WO --tier high --mode fanout --expected 1 --critics-dir "$d" --evaluated true
done
# HIGH-5: empty (0-byte) critic file => unresolved => high critical (NOT pass)
d="$(newdir)"; : > "$d/${WO}.critic-1.json"
assert "H5 empty critic"    critical true --wo $WO --tier high --mode fanout --expected 1 --critics-dir "$d" --evaluated true
# MED-8: high + evaluated + expected 0 (no critics) => critical (min-critic)
d="$(newdir)"
assert "M8 high expected0"  critical true --wo $WO --tier high --mode fanout --expected 0 --critics-dir "$d" --evaluated true
# control: a genuinely clean pass must still pass (no over-blocking regression)
d="$(newdir)"; critic "$d" 1 pass; critic "$d" 2 pass
assert "ctrl clean pass"    pass false    --wo $WO --tier high --mode fanout --expected 2 --critics-dir "$d" --evaluated true
# MED-7: malformed --evaluated / --expected must still emit JSON (never crash to empty stdout)
d="$(newdir)"; critic "$d" 1 pass
out="$(bash "$KERNEL" --wo $WO --tier high --mode fanout --expected 1 --critics-dir "$d" --evaluated yes)"
{ [ -n "$out" ] && [ "$(jq -r '.overall' <<<"$out")" = "not_evaluated" ]; } && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL M7 bad --evaluated (got: $out)"; }
out="$(bash "$KERNEL" --wo $WO --tier high --mode fanout --expected 3x --critics-dir "$d" --evaluated true)"
[ -n "$out" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL M7 bad --expected (empty stdout)"; }
# M2: blocking critical => halt_reason critique_critical ; clean pass => null
d="$(newdir)"; critic "$d" 1 critical
hr="$(bash "$KERNEL" --wo $WO --tier high --mode fanout --expected 1 --critics-dir "$d" --evaluated true | jq -r '.halt_reason')"
[ "$hr" = "critique_critical" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL M2 halt_reason (got $hr)"; }

echo "----"; echo "wo-critique-aggregate-spec: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
