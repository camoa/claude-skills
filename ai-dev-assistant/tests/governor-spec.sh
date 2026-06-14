#!/usr/bin/env bash
# TDD spec for scripts/governor.sh (K1) — the ${WO_BUDGET_CMD} backend.
# Test table T1–T12 per architecture/kernels.md (safety_governor ④).
# No network, no agents, no real classifier. Hermetic rules fixture via CLAUDE_PLUGIN_ROOT.
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
SUT="$ROOT/scripts/governor.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

# ── Hermetic rules fixture (controls the weights the governor reads) ──────────
# tier_model_map: low/medium→sonnet, high/security→opus.  model_weight_map: sonnet=1, opus=2, _default=2.
PLUGIN="$TMP/plugin"; mkdir -p "$PLUGIN/references"
cat > "$PLUGIN/references/risk-tiering-rules.json" <<'JSON'
{
  "schema_version": "1.0",
  "tier_model_map": { "low":"sonnet", "medium":"sonnet", "high":"opus", "security":"opus" },
  "model_weight_map": { "sonnet":1, "opus":2, "_default":2 }
}
JSON
export CLAUDE_PLUGIN_ROOT="$PLUGIN"

# krun: run the governor with the given VAR=val env pairs; capture OUT (stdout), ERR (stderr), RC.
krun() { OUT="$(env "$@" bash "$SUT" 2>"$TMP/err")"; RC=$?; ERR="$(cat "$TMP/err")"; }

fail_check() { FAIL=$((FAIL+1)); echo "FAIL $1: $2"; [ -n "${OUT:-}" ] && echo "  out: $OUT"; }
pass_check() { PASS=$((PASS+1)); }

# ── fixture builders ─────────────────────────────────────────────────────────
mktask() { local t="$TMP/$1"; mkdir -p "$t/work-orders"; echo "$t"; }
seed_run() {  # $1=task  $2=wo  $3=attempts
  jq -nc --arg wo "$2" --argjson a "$3" \
    '{wo:$wo, attempts:$a, checkpoint_before:"sha", dispatched_at:"2026-01-01T00:00:00Z",
      halted:false, halt_reason:null, override_used:null, build_returned:null, checkpoint_after:null}' \
    > "$1/work-orders/$2.run.json"
}
seed_run_raw() { printf '%s' "$3" > "$1/work-orders/$2.run.json"; }  # $3 = raw body (malformed)
seed_critique() {  # $1=task  $2=wo  $3=risk_tier
  jq -nc --arg wo "$2" --arg t "$3" \
    '{schema_version:"1.0", wo_id:$wo, risk_tier:$t, overall:"pass", blocking:false}' \
    > "$1/work-orders/$2._critique.json"
}

# ──────────────────────────────────────────────────────────────────────────────
# T1: WDC < MAX (2 sonnet WOs, attempts 1, critiqued) → exit 0, reason ok
#     each WO: 1 × (weight(sonnet=1) + has_critique(1)×CRITIQUE_WEIGHT(2)) = 3 ; total WDC = 6
T="$(mktask t1)"
seed_run "$T" wo-01 1; seed_critique "$T" wo-01 low
seed_run "$T" wo-02 1; seed_critique "$T" wo-02 medium
krun WO_TASK_FOLDER="$T" WO_BUDGET_MAX=10
wdc="$(jq -r '.wdc' <<<"$OUT" 2>/dev/null || echo err)"
reason="$(jq -r '.reason' <<<"$OUT" 2>/dev/null || echo err)"
if [ "$RC" -eq 0 ] && [ "$wdc" = "6" ] && [ "$reason" = "ok" ]; then pass_check
else fail_check "T1" "rc=$RC wdc=$wdc (want 6) reason=$reason (want ok)"; fi

# ──────────────────────────────────────────────────────────────────────────────
# T2: WDC > MAX → exit≠0, reason budget_exceeded
T="$(mktask t2)"
seed_run "$T" wo-01 1; seed_critique "$T" wo-01 low      # WDC = 3
krun WO_TASK_FOLDER="$T" WO_BUDGET_MAX=2
reason="$(jq -r '.reason' <<<"$OUT" 2>/dev/null || echo err)"
if [ "$RC" -ne 0 ] && [ "$reason" = "budget_exceeded" ]; then pass_check
else fail_check "T2" "rc=$RC reason=$reason (want budget_exceeded)"; fi

# ──────────────────────────────────────────────────────────────────────────────
# T3: a WO with attempts>0, NO _critique.json → counts at weight 2 (fail-strict, not 1)
#     contribution = attempts(1) × (weight 2 + has_critique 0) = 2.  Assert WDC=2 not 1.
T="$(mktask t3)"
seed_run "$T" wo-01 1     # no critique file
krun WO_TASK_FOLDER="$T" WO_BUDGET_MAX=10
wdc="$(jq -r '.wdc' <<<"$OUT" 2>/dev/null || echo err)"
if [ "$RC" -eq 0 ] && [ "$wdc" = "2" ]; then pass_check
else fail_check "T3" "rc=$RC wdc=$wdc (want 2, fail-strict weight 2)"; fi

# ──────────────────────────────────────────────────────────────────────────────
# T4: WO_BUDGET_MAX unset → exit≠0, reason misconfigured (fail-closed)
T="$(mktask t4)"; seed_run "$T" wo-01 1
krun WO_TASK_FOLDER="$T"
reason="$(jq -r '.reason' <<<"$OUT" 2>/dev/null || echo err)"
if [ "$RC" -ne 0 ] && [ "$reason" = "misconfigured" ]; then pass_check
else fail_check "T4" "rc=$RC reason=$reason (want misconfigured)"; fi

# ──────────────────────────────────────────────────────────────────────────────
# T5: WO_TASK_FOLDER unset/unreadable → exit≠0, reason misconfigured
krun WO_BUDGET_MAX=10   # WO_TASK_FOLDER unset entirely
reason="$(jq -r '.reason' <<<"$OUT" 2>/dev/null || echo err)"
RC1=$RC; reason1=$reason
krun WO_TASK_FOLDER="$TMP/does-not-exist" WO_BUDGET_MAX=10
reason2="$(jq -r '.reason' <<<"$OUT" 2>/dev/null || echo err)"; RC2=$RC
if [ "$RC1" -ne 0 ] && [ "$reason1" = "misconfigured" ] \
   && [ "$RC2" -ne 0 ] && [ "$reason2" = "misconfigured" ]; then pass_check
else fail_check "T5" "unset: rc=$RC1 reason=$reason1 ; missing: rc=$RC2 reason=$reason2"; fi

# ──────────────────────────────────────────────────────────────────────────────
# T6: now-started ≥ HARD → exit≠0, reason budget_timeout_hard (WDC under budget so only timeout trips)
T="$(mktask t6)"; seed_run "$T" wo-01 1; seed_critique "$T" wo-01 low
START=$(( $(date +%s) - 2000 ))
krun WO_TASK_FOLDER="$T" WO_BUDGET_MAX=100 WO_RUN_STARTED_AT="$START" WO_BUDGET_HARD_SECS=1800
reason="$(jq -r '.reason' <<<"$OUT" 2>/dev/null || echo err)"
if [ "$RC" -ne 0 ] && [ "$reason" = "budget_timeout_hard" ]; then pass_check
else fail_check "T6" "rc=$RC reason=$reason (want budget_timeout_hard)"; fi

# ──────────────────────────────────────────────────────────────────────────────
# T7: SOFT ≤ now-started < HARD → exit 0, reason ok, + soft-timeout log on stderr
T="$(mktask t7)"; seed_run "$T" wo-01 1; seed_critique "$T" wo-01 low
START=$(( $(date +%s) - 1300 ))
krun WO_TASK_FOLDER="$T" WO_BUDGET_MAX=100 WO_RUN_STARTED_AT="$START" \
     WO_BUDGET_SOFT_SECS=1200 WO_BUDGET_HARD_SECS=1800
reason="$(jq -r '.reason' <<<"$OUT" 2>/dev/null || echo err)"
if [ "$RC" -eq 0 ] && [ "$reason" = "ok" ] && echo "$ERR" | grep -qi 'soft'; then pass_check
else fail_check "T7" "rc=$RC reason=$reason soft_in_stderr=$(echo "$ERR" | grep -ci soft)"; fi

# ──────────────────────────────────────────────────────────────────────────────
# T8: idempotency — same disk state, called twice → identical WDC both calls
T="$(mktask t8)"; seed_run "$T" wo-01 2; seed_critique "$T" wo-01 high
krun WO_TASK_FOLDER="$T" WO_BUDGET_MAX=100; wdc_a="$(jq -r '.wdc' <<<"$OUT" 2>/dev/null || echo a)"
krun WO_TASK_FOLDER="$T" WO_BUDGET_MAX=100; wdc_b="$(jq -r '.wdc' <<<"$OUT" 2>/dev/null || echo b)"
# high→opus→weight2 ; attempts 2 ; has_critique 1 ; 2×(2+2)=8
if [ "$wdc_a" = "8" ] && [ "$wdc_b" = "8" ]; then pass_check
else fail_check "T8" "wdc_a=$wdc_a wdc_b=$wdc_b (want 8 both; idempotent recompute)"; fi

# ──────────────────────────────────────────────────────────────────────────────
# T9: malformed wo-NN.run.json → that WO counted fail-strict (weight 2, attempts≥1), NOT dropped
#     contribution = 1 × (2 + has_critique 0) = 2
T="$(mktask t9)"; seed_run_raw "$T" wo-01 '{not valid json'
krun WO_TASK_FOLDER="$T" WO_BUDGET_MAX=100
wdc="$(jq -r '.wdc' <<<"$OUT" 2>/dev/null || echo err)"
if [ "$RC" -eq 0 ] && [ "$wdc" = "2" ]; then pass_check
else fail_check "T9" "rc=$RC wdc=$wdc (want 2; malformed counted fail-strict, not dropped)"; fi

# ──────────────────────────────────────────────────────────────────────────────
# T10: attempts is a string/float in run.json → fail-strict (not undercounted, treated ≥1 @ weight 2)
T="$(mktask t10)"; seed_run_raw "$T" wo-01 '{"wo":"wo-01","attempts":"3.5"}'
krun WO_TASK_FOLDER="$T" WO_BUDGET_MAX=100
wdc="$(jq -r '.wdc' <<<"$OUT" 2>/dev/null || echo err)"
# non-integer attempts → fail-strict: attempts treated as 1, weight 2 → 1×2 = 2 (never 0, never 3.5×1)
if [ "$RC" -eq 0 ] && [ "$wdc" = "2" ]; then pass_check
else fail_check "T10" "rc=$RC wdc=$wdc (want 2; non-int attempts fail-strict)"; fi

# ──────────────────────────────────────────────────────────────────────────────
# T11: metachar in WO_TASK_FOLDER → inert (paths quoted; jq --arg); no command execution
T="$(mktask 't11; touch '"$TMP"'/PWNED')"; seed_run "$T" wo-01 1; seed_critique "$T" wo-01 low
krun WO_TASK_FOLDER="$T" WO_BUDGET_MAX=100
reason="$(jq -r '.reason' <<<"$OUT" 2>/dev/null || echo err)"
if [ "$RC" -eq 0 ] && [ "$reason" = "ok" ] && [ ! -e "$TMP/PWNED" ]; then pass_check
else fail_check "T11" "rc=$RC reason=$reason pwned=$([ -e "$TMP/PWNED" ] && echo YES || echo no)"; fi

# ──────────────────────────────────────────────────────────────────────────────
# T12: governor writes NOTHING (no .budget or any new file) — recompute-only (D1/D-RT-3)
T="$(mktask t12)"; seed_run "$T" wo-01 1; seed_critique "$T" wo-01 low
before="$(find "$T" -type f | sort)"
krun WO_TASK_FOLDER="$T" WO_BUDGET_MAX=100
after="$(find "$T" -type f | sort)"
if [ "$RC" -eq 0 ] && [ "$before" = "$after" ]; then pass_check
else fail_check "T12" "governor wrote files: $(diff <(echo "$before") <(echo "$after") | grep '^>' )"; fi

# ──────────────────────────────────────────────────────────────────────────────
# T13 (compact line): stderr carries `budget_governor ok=<b> wdc=<n> max=<n> reason=<r>`
T="$(mktask t13)"; seed_run "$T" wo-01 1; seed_critique "$T" wo-01 low
krun WO_TASK_FOLDER="$T" WO_BUDGET_MAX=100
if echo "$ERR" | grep -qE '^budget_governor ok=(true|false) wdc=[0-9]+ max=[0-9]+ reason='; then pass_check
else fail_check "T13" "compact line missing/malformed on stderr: $ERR"; fi

# ──────────────────────────────────────────────────────────────────────────────
# T14 (HIGH-1 overflow guard): an implausibly-huge attempts value must NOT overflow WDC negative.
#   It is clamped to ATTEMPTS_CEIL (=100000) and force-counted fail-strict (weight 2), so WDC stays
#   positive and a low MAX trips budget_exceeded (fail-CLOSED), never a negative-WDC pass.
#   high critique present ⇒ 100000 × (weight 2 + has_critique 1 × CRITIQUE_WEIGHT 2) = 400000.
T="$(mktask t14)"; seed_run "$T" wo-01 9000000000000000; seed_critique "$T" wo-01 high
krun WO_TASK_FOLDER="$T" WO_BUDGET_MAX=10
wdc="$(jq -r '.wdc' <<<"$OUT" 2>/dev/null || echo err)"
reason="$(jq -r '.reason' <<<"$OUT" 2>/dev/null || echo err)"
if [ "$RC" -ne 0 ] && [ "$wdc" = "400000" ] && [ "$reason" = "budget_exceeded" ]; then pass_check
else fail_check "T14" "rc=$RC wdc=$wdc (want 400000, clamped — NOT negative) reason=$reason"; fi

# T14b: the red-team's exact overflow scenario (many huge WOs) → WDC stays ≥0, fail-closed.
T="$(mktask t14b)"
for i in $(seq -w 1 60); do seed_run "$T" "wo-$i" 9000000000000000; seed_critique "$T" "wo-$i" high; done
krun WO_TASK_FOLDER="$T" WO_BUDGET_MAX=10
wdc="$(jq -r '.wdc' <<<"$OUT" 2>/dev/null || echo err)"
reason="$(jq -r '.reason' <<<"$OUT" 2>/dev/null || echo err)"
if [ "$RC" -ne 0 ] && [[ "$wdc" =~ ^[0-9]+$ ]] && [ "$wdc" -gt 0 ] && [ "$reason" = "budget_exceeded" ]; then pass_check
else fail_check "T14b" "rc=$RC wdc=$wdc (want positive int) reason=$reason (want budget_exceeded; no overflow)"; fi

# T15 (MED-1): non-integer timeout / critique-weight env knobs ⇒ misconfigured (fail-closed),
#   never a silently-disabled hard cap.
T="$(mktask t15)"; seed_run "$T" wo-01 1; seed_critique "$T" wo-01 low
START=$(( $(date +%s) - 999999 ))
fails15=0
krun WO_TASK_FOLDER="$T" WO_BUDGET_MAX=100 WO_RUN_STARTED_AT="$START" WO_BUDGET_HARD_SECS=abc
[ "$RC" -ne 0 ] && [ "$(jq -r '.reason' <<<"$OUT" 2>/dev/null)" = "misconfigured" ] || fails15=$((fails15+1))
krun WO_TASK_FOLDER="$T" WO_BUDGET_MAX=100 WO_BUDGET_SOFT_SECS=12.5
[ "$RC" -ne 0 ] && [ "$(jq -r '.reason' <<<"$OUT" 2>/dev/null)" = "misconfigured" ] || fails15=$((fails15+1))
krun WO_TASK_FOLDER="$T" WO_BUDGET_MAX=100 WO_CRITIQUE_WEIGHT=abc
[ "$RC" -ne 0 ] && [ "$(jq -r '.reason' <<<"$OUT" 2>/dev/null)" = "misconfigured" ] || fails15=$((fails15+1))
if [ "$fails15" -eq 0 ]; then pass_check
else fail_check "T15" "$fails15/3 bad-env knobs did NOT fail-closed misconfigured"; fi

# T16 (MED-2): attempts:0 with a critique present (build provably ran) ⇒ attempts floored to ≥1,
#   so the WO is NOT zero-counted. high critique ⇒ 1 × (2 + 1×2) = 4.
T="$(mktask t16)"; seed_run "$T" wo-01 0; seed_critique "$T" wo-01 high
krun WO_TASK_FOLDER="$T" WO_BUDGET_MAX=100
wdc="$(jq -r '.wdc' <<<"$OUT" 2>/dev/null || echo err)"
if [ "$RC" -eq 0 ] && [ "$wdc" = "4" ]; then pass_check
else fail_check "T16" "rc=$RC wdc=$wdc (want 4; attempts:0+critique must floor to ≥1, not zero-count)"; fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo "----"
echo "governor-spec: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
