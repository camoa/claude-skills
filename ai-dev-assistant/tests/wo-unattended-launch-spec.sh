#!/usr/bin/env bash
# TDD spec for scripts/wo-unattended-launch.sh (K2) — the unattended launch wrapper.
# Test table T1–T5 per architecture/kernels.md (safety_governor ④).
# --print-cmd makes every test network-free + claude-free: it scrubs/wires the env, dumps the
# REAL post-scrub environment the child `claude` would inherit, and execs NOTHING.
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
SUT="$ROOT/scripts/wo-unattended-launch.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

fail_check() { FAIL=$((FAIL+1)); echo "FAIL $1: $2"; [ -n "${OUT:-}" ] && echo "  out: $(echo "$OUT" | head -5)"; }
pass_check() { PASS=$((PASS+1)); }

mktask() { local t="$TMP/$1"; mkdir -p "$t/work-orders"; echo "$t"; }

# ──────────────────────────────────────────────────────────────────────────────
# T1: --print-cmd with GH_TOKEN/GITHUB_TOKEN set in caller env
#     → dumped env has NO GH_TOKEN / GITHUB_TOKEN line (scrubbed); HOME = the sandbox dir
T="$(mktask t1)"; SBX="$TMP/sbx1"
OUT="$(GH_TOKEN=broad-aaa GITHUB_TOKEN=broad-bbb HOME=/original/home \
       bash "$SUT" "$T" --budget-max 50 --sandbox-home "$SBX" --print-cmd 2>/dev/null)"; RC=$?
has_ghtok="$(echo "$OUT" | grep -cE '^GH_TOKEN=' || true)"
has_ghub="$(echo "$OUT" | grep -cE '^GITHUB_TOKEN=' || true)"
home_line="$(echo "$OUT" | grep -E '^HOME=' | head -1)"
if [ "$RC" -eq 0 ] && [ "$has_ghtok" -eq 0 ] && [ "$has_ghub" -eq 0 ] \
   && [ "$home_line" = "HOME=$SBX" ]; then pass_check
else fail_check "T1" "rc=$RC ghtok=$has_ghtok ghub=$has_ghub home=[$home_line] (want HOME=$SBX)"; fi

# ──────────────────────────────────────────────────────────────────────────────
# T2: --print-cmd --pat-file /run/pat
#     → env has WO_MERGE_PAT_FILE=/run/pat ; NO WO_MERGE_GH_TOKEN ; no broad token VALUE anywhere
T="$(mktask t2)"
OUT="$(GH_TOKEN=secret-value-xyz bash "$SUT" "$T" --budget-max 50 --pat-file /run/pat --print-cmd 2>/dev/null)"; RC=$?
patfile_line="$(echo "$OUT" | grep -E '^WO_MERGE_PAT_FILE=' | head -1)"
has_merge_tok="$(echo "$OUT" | grep -cE '^WO_MERGE_GH_TOKEN=' || true)"
has_value="$(echo "$OUT" | grep -c 'secret-value-xyz' || true)"
if [ "$RC" -eq 0 ] && [ "$patfile_line" = "WO_MERGE_PAT_FILE=/run/pat" ] \
   && [ "$has_merge_tok" -eq 0 ] && [ "$has_value" -eq 0 ]; then pass_check
else fail_check "T2" "rc=$RC patfile=[$patfile_line] merge_tok=$has_merge_tok token_value_leaked=$has_value"; fi

# ──────────────────────────────────────────────────────────────────────────────
# T3: governor wiring — env has WO_BUDGET_CMD=…/governor.sh, WO_BUDGET_MAX, WO_RUN_STARTED_AT(epoch), WO_TASK_FOLDER
T="$(mktask t3)"
OUT="$(bash "$SUT" "$T" --budget-max 42 --print-cmd 2>/dev/null)"; RC=$?
cmd_line="$(echo "$OUT"   | grep -E '^WO_BUDGET_CMD=' | head -1)"
max_line="$(echo "$OUT"   | grep -E '^WO_BUDGET_MAX=' | head -1)"
started="$(echo "$OUT"    | grep -E '^WO_RUN_STARTED_AT=' | head -1 | sed 's/^WO_RUN_STARTED_AT=//')"
task_line="$(echo "$OUT"  | grep -E '^WO_TASK_FOLDER=' | head -1)"
if [ "$RC" -eq 0 ] \
   && echo "$cmd_line" | grep -q '/scripts/governor.sh$' \
   && [ "$max_line" = "WO_BUDGET_MAX=42" ] \
   && [[ "$started" =~ ^[0-9]+$ ]] \
   && [ "$task_line" = "WO_TASK_FOLDER=$T" ]; then pass_check
else fail_check "T3" "rc=$RC cmd=[$cmd_line] max=[$max_line] started=[$started] task=[$task_line]"; fi

# ──────────────────────────────────────────────────────────────────────────────
# T4: --budget-max missing → exit≠0 (fail-closed; never launch an ungoverned run)
T="$(mktask t4)"
OUT="$(bash "$SUT" "$T" --print-cmd 2>/dev/null)"; RC=$?
if [ "$RC" -ne 0 ]; then pass_check
else fail_check "T4" "rc=$RC (want non-zero; ungoverned launch must be refused)"; fi

# ──────────────────────────────────────────────────────────────────────────────
# T5: metachar in --task-folder / --pat-file → inert (argv items / data, never eval'd)
T="$(mktask 't5; touch '"$TMP"'/PWNED5')"
META_PAT='/run/pat; touch '"$TMP"'/PWNED5b'
OUT="$(bash "$SUT" "$T" --budget-max 50 --pat-file "$META_PAT" --print-cmd 2>/dev/null)"; RC=$?
patfile_line="$(echo "$OUT" | grep -E '^WO_MERGE_PAT_FILE=' | head -1 | sed 's/^WO_MERGE_PAT_FILE=//')"
if [ "$RC" -eq 0 ] && [ ! -e "$TMP/PWNED5" ] && [ ! -e "$TMP/PWNED5b" ] \
   && [ "$patfile_line" = "$META_PAT" ]; then pass_check
else fail_check "T5" "rc=$RC pwned=$([ -e "$TMP/PWNED5" ]||[ -e "$TMP/PWNED5b" ] && echo YES || echo no) patfile=[$patfile_line]"; fi

# ──────────────────────────────────────────────────────────────────────────────
# T6 (LOW fix): --print-cmd must NOT dump unrelated caller secrets (AWS keys, ANTHROPIC_API_KEY, …) —
#     only the launch-relevant keys (WO_*, HOME, and proof the broad tokens are scrubbed).
T="$(mktask t6)"
OUT="$(MY_UNRELATED_SECRET=top-secret-xyz AWS_SECRET_ACCESS_KEY=aws-leak-123 \
       bash "$SUT" "$T" --budget-max 50 --print-cmd 2>/dev/null)"; RC=$?
leak1="$(echo "$OUT" | grep -c 'top-secret-xyz' || true)"
leak2="$(echo "$OUT" | grep -c 'aws-leak-123' || true)"
wired="$(echo "$OUT" | grep -cE '^WO_BUDGET_CMD=' || true)"
if [ "$RC" -eq 0 ] && [ "$leak1" -eq 0 ] && [ "$leak2" -eq 0 ] && [ "$wired" -ge 1 ]; then pass_check
else fail_check "T6" "rc=$RC unrelated_secret_leaked=$((leak1+leak2)) (want 0) wired_keys_present=$wired"; fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo "----"
echo "wo-unattended-launch-spec: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
