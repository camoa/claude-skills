#!/usr/bin/env bash
# TDD spec for scripts/wo-pr-open.sh (K4) — fused check-and-open choke point.
# Tests run with NO network and NO real gh.  All external calls go through env-hook stubs.
# Mirrors the harness idiom of wo-ship-gate-spec.sh.
set -uo pipefail

HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
KERNEL="$ROOT/scripts/wo-pr-open.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

# ─── Stub: merge-gate OK (merge_ok=true, auto_merge_allowed=true) ─────────────
MG_STUB_OK="$TMP/mg-ok.sh"
cat > "$MG_STUB_OK" <<'STUB'
#!/usr/bin/env bash
echo '{"merge_ok":true,"auto_merge_allowed":true,"ship_ok":true,"review_verdict":"pass","per_wo_review_failures":[],"overrides_used":[],"missing_run_state":[],"halts":[],"blocking":[],"reason":"merge_ok"}'
exit 0
STUB
chmod +x "$MG_STUB_OK"

# ─── Stub: merge-gate FAIL (merge_ok=false, exit 1) ───────────────────────────
MG_STUB_FAIL="$TMP/mg-fail.sh"
cat > "$MG_STUB_FAIL" <<'STUB'
#!/usr/bin/env bash
echo '{"merge_ok":false,"auto_merge_allowed":false,"ship_ok":false,"review_verdict":"fail","per_wo_review_failures":[],"overrides_used":[],"missing_run_state":[],"halts":["wo-01.HALT"],"blocking":[],"reason":"ship_not_ok:halts"}'
exit 1
STUB
chmod +x "$MG_STUB_FAIL"

# ─── Stub: merge-gate OK but auto_merge_allowed=false ─────────────────────────
MG_STUB_NO_AUTO="$TMP/mg-no-auto.sh"
cat > "$MG_STUB_NO_AUTO" <<'STUB'
#!/usr/bin/env bash
echo '{"merge_ok":true,"auto_merge_allowed":false,"ship_ok":true,"review_verdict":"pass","per_wo_review_failures":[],"overrides_used":["wo-01"],"missing_run_state":[],"halts":[],"blocking":[],"reason":"merge_ok"}'
exit 0
STUB
chmod +x "$MG_STUB_NO_AUTO"

# ─── Stub: gh recorder (writes argv + GH_TOKEN to log, emits fake PR URL) ────
GH_STUB="$TMP/gh-stub.sh"
cat > "$GH_STUB" <<'STUB'
#!/usr/bin/env bash
LOG="${WO_GH_STUB_LOG:-/tmp/gh-stub.log}"
printf 'ARGV: %s\n' "$*"           >> "$LOG"
printf 'GH_TOKEN_ENV: %s\n' "${GH_TOKEN:-}" >> "$LOG"
echo "https://github.com/fake/repo/pull/42"
exit 0
STUB
chmod +x "$GH_STUB"

# ─── Stub: gh recorder that REJECTS --label (simulates label not in repo) ─────
# Exits 1 when --label is in argv; on success logs ARGV + body-file content.
# pr list/view subcommands return empty (no existing PR) so the LOW-fix retry path proceeds.
GH_STUB_LABEL_FAIL="$TMP/gh-stub-label-fail.sh"
cat > "$GH_STUB_LABEL_FAIL" <<'STUB'
#!/usr/bin/env bash
LOG="${WO_GH_STUB_LOG:-/tmp/gh-stub.log}"
# PR-check subcommands: return empty = no existing PR (retry should proceed).
if [ "${2:-}" = "list" ] || [ "${2:-}" = "view" ]; then
  exit 0
fi
# pr create path
printf 'ARGV: %s\n' "$*" >> "$LOG"
# Simulate: label not found in repo
for arg in "$@"; do
  if [ "$arg" = "--label" ]; then
    printf "GraphQL: Label 'needs-grounding-review' not found\n" >&2
    exit 1
  fi
done
# Success path — log body content for ⚠ assertion
prev=""
for arg in "$@"; do
  if [ "$prev" = "--body-file" ]; then
    printf 'BODY_CONTENT:\n' >> "$LOG"
    cat "$arg" >> "$LOG" 2>/dev/null || true
    break
  fi
  prev="$arg"
done
echo "https://github.com/fake/repo/pull/43"
exit 0
STUB
chmod +x "$GH_STUB_LABEL_FAIL"

# ─── Stub K4-A: non-label failure (e.g. auth) — every call exits 1 with non-label stderr ──
GH_STUB_K4A="$TMP/gh-stub-k4a.sh"
cat > "$GH_STUB_K4A" <<'STUB'
#!/usr/bin/env bash
LOG="${WO_GH_STUB_LOG:-/tmp/gh-stub.log}"
printf 'ARGV: %s\n' "$*" >> "$LOG"
printf 'HTTP 401 Unauthorized\n' >&2
exit 1
STUB
chmod +x "$GH_STUB_K4A"

# ─── Stub K4-B: label-related failure AFTER a PR was already created ──────────
# pr create → log CREATE marker, emit label-ish stderr, exit 1.
# pr list/view → return a URL (PR already exists — must block retry).
GH_STUB_K4B="$TMP/gh-stub-k4b.sh"
cat > "$GH_STUB_K4B" <<'STUB'
#!/usr/bin/env bash
LOG="${WO_GH_STUB_LOG:-/tmp/gh-stub.log}"
# Simulate: PR already exists in repo (was created before label application failed).
if [ "${2:-}" = "list" ] || [ "${2:-}" = "view" ]; then
  echo 'https://github.com/fake/repo/pull/99'
  exit 0
fi
# pr create — record the attempt and fail with label-ish stderr.
printf 'CREATE\n'  >> "$LOG"
printf 'ARGV: %s\n' "$*" >> "$LOG"
printf "GraphQL: Label 'needs-grounding-review' not found in repo\n" >&2
exit 1
STUB
chmod +x "$GH_STUB_K4B"

# ─── Helper: build a minimal task folder ──────────────────────────────────────
mktask() {  # $1: unique name  $2: "with_body" | "no_body"
  local t="$TMP/$1"; mkdir -p "$t"
  if [ "${2:-with_body}" = "with_body" ]; then
    cat > "$t/PR_BODY.md" <<'BODY'
# feat: add automated review pipeline

Adds K4 wo-pr-open.sh as the fused check-and-open choke point.

## Changes
- Kernel validates merge-gate before opening PR
- Token scoped to single-repo PAT via WO_MERGE_GH_TOKEN
BODY
  fi
  echo "$t"
}

pass() { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); echo "FAIL $1: $2"; }

# ──────────────────────────────────────────────────────────────────────────────
# T1: merge_ok=true, PR_BODY.md present, --print-cmd
#     printed output contains "pr create" and "PR_BODY.md"; NO "pr merge" anywhere
# ──────────────────────────────────────────────────────────────────────────────
T="$(mktask t1 with_body)"
out="$(WO_MERGE_GATE_CMD="$MG_STUB_OK" bash "$KERNEL" "$T" --print-cmd 2>/dev/null)"
rc=$?
if [ "$rc" -eq 0 ] \
   && echo "$out" | grep -q 'pr create' \
   && echo "$out" | grep -q 'PR_BODY.md' \
   && ! echo "$out" | grep -q 'pr merge'; then
  pass "T1"
else
  fail "T1" "rc=$rc; looking for [pr create], [PR_BODY.md], no [pr merge] in: $(echo "$out" | head -3)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# T2: merge_ok=false → REFUSE; opened=false, reason=merge_gate_failed; zero gh calls
# ──────────────────────────────────────────────────────────────────────────────
T="$(mktask t2 with_body)"
GH_LOG="$TMP/t2-gh.log"; rm -f "$GH_LOG"
out="$(WO_MERGE_GATE_CMD="$MG_STUB_FAIL" WO_GH_CMD="$GH_STUB" WO_GH_STUB_LOG="$GH_LOG" \
      bash "$KERNEL" "$T" 2>/dev/null)"
rc=$?
opened="$(jq -r '.opened'              <<<"$out" 2>/dev/null || echo err)"
reason="$(jq -r '.reason'              <<<"$out" 2>/dev/null || echo err)"
mg_present="$(jq -r '.merge_gate|type' <<<"$out" 2>/dev/null || echo err)"
if [ "$rc" -ne 0 ] \
   && [ "$opened" = "false" ] \
   && [ "$reason" = "merge_gate_failed" ] \
   && [ "$mg_present" = "object" ] \
   && [ ! -f "$GH_LOG" ]; then
  pass "T2"
else
  fail "T2" "rc=$rc opened=$opened reason=$reason mg_type=$mg_present gh_called=$([ -f "$GH_LOG" ] && echo yes || echo no)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# T3: merge_ok=true, PR_BODY.md absent → opened=false, reason=pr_body_absent
# ──────────────────────────────────────────────────────────────────────────────
T="$(mktask t3 no_body)"
out="$(WO_MERGE_GATE_CMD="$MG_STUB_OK" bash "$KERNEL" "$T" 2>/dev/null)"
rc=$?
opened="$(jq -r '.opened' <<<"$out" 2>/dev/null || echo err)"
reason="$(jq -r '.reason' <<<"$out" 2>/dev/null || echo err)"
if [ "$rc" -ne 0 ] && [ "$opened" = "false" ] && [ "$reason" = "pr_body_absent" ]; then
  pass "T3"
else
  fail "T3" "rc=$rc opened=$opened reason=$reason"
fi

# ──────────────────────────────────────────────────────────────────────────────
# T4: auto_merge_allowed=false → augmented body contains ⚠ DO NOT auto-merge line
#     Use --print-cmd so no real gh call needed; exit 0 because merge_ok=true
# ──────────────────────────────────────────────────────────────────────────────
T="$(mktask t4 with_body)"
out="$(WO_MERGE_GATE_CMD="$MG_STUB_NO_AUTO" bash "$KERNEL" "$T" --print-cmd 2>/dev/null)"
rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q 'DO NOT auto-merge'; then
  pass "T4"
else
  fail "T4" "rc=$rc; 'DO NOT auto-merge' not found in print-cmd output: $(echo "$out" | head -5)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# T5: WO_MERGE_GH_TOKEN set → stub sees that PAT as GH_TOKEN (not ambient); PAT not in stdout JSON
# ──────────────────────────────────────────────────────────────────────────────
T="$(mktask t5 with_body)"
GH_LOG="$TMP/t5-gh.log"; rm -f "$GH_LOG"
AMBIENT_TOK="ambient-gh-token-000"
FINE_TOK="fine-grained-pat-999"
out="$(GH_TOKEN="$AMBIENT_TOK" \
      WO_MERGE_GATE_CMD="$MG_STUB_OK" \
      WO_GH_CMD="$GH_STUB" \
      WO_GH_STUB_LOG="$GH_LOG" \
      WO_MERGE_GH_TOKEN="$FINE_TOK" \
      bash "$KERNEL" "$T" 2>/dev/null)"
rc=$?
stub_tok="$(grep '^GH_TOKEN_ENV:' "$GH_LOG" 2>/dev/null | head -1 | sed 's/^GH_TOKEN_ENV: //' || echo missing)"
pat_in_stdout="$(echo "$out" | grep -c "$FINE_TOK" || true)"
if [ "$rc" -eq 0 ] \
   && [ "$stub_tok" = "$FINE_TOK" ] \
   && [ "$pat_in_stdout" -eq 0 ]; then
  pass "T5"
else
  fail "T5" "rc=$rc stub_tok=[$stub_tok] (want [$FINE_TOK]) pat_in_stdout=$pat_in_stdout"
fi

# ──────────────────────────────────────────────────────────────────────────────
# T6: no token set → still opens PR via ambient gh auth; v1-gap note on stderr
# ──────────────────────────────────────────────────────────────────────────────
T="$(mktask t6 with_body)"
GH_LOG="$TMP/t6-gh.log"; STDERR_FILE="$TMP/t6-stderr.txt"
rm -f "$GH_LOG" "$STDERR_FILE"
out="$(GH_TOKEN="" \
      WO_MERGE_GATE_CMD="$MG_STUB_OK" \
      WO_GH_CMD="$GH_STUB" \
      WO_GH_STUB_LOG="$GH_LOG" \
      bash "$KERNEL" "$T" 2>"$STDERR_FILE")"
rc=$?
opened="$(jq -r '.opened' <<<"$out" 2>/dev/null || echo err)"
err_out="$(cat "$STDERR_FILE" 2>/dev/null || echo '')"
if [ "$rc" -eq 0 ] \
   && [ "$opened" = "true" ] \
   && echo "$err_out" | grep -qi 'v1'; then
  pass "T6"
else
  fail "T6" "rc=$rc opened=$opened; v1 in stderr=$(echo "$err_out" | grep -ci 'v1' || true)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# T7: --base/--head with shell metachar → inert (separate argv items, never eval'd)
#     rc=0 proves 'exit 99' in --base value did NOT execute; stub log shows literal value
# ──────────────────────────────────────────────────────────────────────────────
T="$(mktask t7 with_body)"
GH_LOG="$TMP/t7-gh.log"; rm -f "$GH_LOG"
BASE_META='main; exit 99'
HEAD_META='feature/topic-branch'
out="$(WO_MERGE_GATE_CMD="$MG_STUB_OK" \
      WO_GH_CMD="$GH_STUB" \
      WO_GH_STUB_LOG="$GH_LOG" \
      bash "$KERNEL" "$T" --base "$BASE_META" --head "$HEAD_META" 2>/dev/null)"
rc=$?
stub_argv="$(grep '^ARGV:' "$GH_LOG" 2>/dev/null | head -1 || echo '')"
# rc=0 means 'exit 99' in the base metachar was NOT eval'd; stub log must show the literal value
if [ "$rc" -eq 0 ] && echo "$stub_argv" | grep -qF "$BASE_META"; then
  pass "T7"
else
  fail "T7" "rc=$rc (99=injection executed, 0=inert); stub argv contains base literally=$(echo "$stub_argv" | grep -cF "$BASE_META" || true)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# T9 (MED-1 EXECUTE): auto_merge_allowed=false + gh stub that EXITS NON-ZERO on --label
#     ⇒ kernel retries WITHOUT --label ⇒ opened:true; body-file still contains ⚠ line
# ──────────────────────────────────────────────────────────────────────────────
T="$(mktask t9 with_body)"
GH_LOG="$TMP/t9-gh.log"; rm -f "$GH_LOG"
out="$(WO_MERGE_GATE_CMD="$MG_STUB_NO_AUTO" \
      WO_GH_CMD="$GH_STUB_LABEL_FAIL" \
      WO_GH_STUB_LOG="$GH_LOG" \
      bash "$KERNEL" "$T" 2>/dev/null)"
rc=$?
opened="$(jq -r '.opened' <<<"$out" 2>/dev/null || echo err)"
auto_ma="$(jq -r '.auto_merge_allowed' <<<"$out" 2>/dev/null || echo err)"
# Stub logs body content on successful (no-label) retry; check ⚠ is present
body_has_warn="$(grep -c '⚠' "$GH_LOG" 2>/dev/null || true)"
if [ "$rc" -eq 0 ] \
   && [ "$opened" = "true" ] \
   && [ "$auto_ma" = "false" ] \
   && [ "${body_has_warn:-0}" -gt 0 ]; then
  pass "T9"
else
  fail "T9" "rc=$rc opened=$opened auto_ma=$auto_ma body_has_warn=${body_has_warn:-0}"
fi

# ──────────────────────────────────────────────────────────────────────────────
# T10 (MED-1 EXECUTE happy-path): auto_merge_allowed=false + gh stub that ACCEPTS --label
#      ⇒ opened:true; ARGV log contains --label needs-grounding-review
# ──────────────────────────────────────────────────────────────────────────────
T="$(mktask t10 with_body)"
GH_LOG="$TMP/t10-gh.log"; rm -f "$GH_LOG"
out="$(WO_MERGE_GATE_CMD="$MG_STUB_NO_AUTO" \
      WO_GH_CMD="$GH_STUB" \
      WO_GH_STUB_LOG="$GH_LOG" \
      bash "$KERNEL" "$T" 2>/dev/null)"
rc=$?
opened="$(jq -r '.opened' <<<"$out" 2>/dev/null || echo err)"
argv_line="$(grep '^ARGV:' "$GH_LOG" 2>/dev/null | head -1 || echo '')"
if [ "$rc" -eq 0 ] \
   && [ "$opened" = "true" ] \
   && echo "$argv_line" | grep -q -- '--label'; then
  pass "T10"
else
  fail "T10" "rc=$rc opened=$opened label_in_argv=$(echo "$argv_line" | grep -c -- '--label' || true); argv: $argv_line"
fi

# ──────────────────────────────────────────────────────────────────────────────
# T11 (MED-2 EXECUTE): PR_BODY.md has NO "# " heading
#      ⇒ --title in gh argv must be NON-EMPTY (fallback, never empty)
# ──────────────────────────────────────────────────────────────────────────────
T="$(mktask t11 with_body)"
# Overwrite PR_BODY.md with a file that has no H1 line
cat > "$T/PR_BODY.md" <<'BODY'
No heading at the top.

## Details
This body deliberately omits an H1 to trigger MED-2.
BODY
GH_LOG="$TMP/t11-gh.log"; rm -f "$GH_LOG"
out="$(WO_MERGE_GATE_CMD="$MG_STUB_OK" \
      WO_GH_CMD="$GH_STUB" \
      WO_GH_STUB_LOG="$GH_LOG" \
      bash "$KERNEL" "$T" 2>/dev/null)"
rc=$?
opened="$(jq -r '.opened' <<<"$out" 2>/dev/null || echo err)"
argv_line="$(grep '^ARGV:' "$GH_LOG" 2>/dev/null | head -1 || echo '')"
# Fallback title must contain 'Work-order run:' (the defined fallback prefix)
if [ "$rc" -eq 0 ] \
   && [ "$opened" = "true" ] \
   && echo "$argv_line" | grep -qF 'Work-order run:'; then
  pass "T11"
else
  fail "T11" "rc=$rc opened=$opened; fallback title not found in argv: $argv_line"
fi

# ──────────────────────────────────────────────────────────────────────────────
# K4-A (LOW fix — fatal non-label failure not masked):
#   gh stub exits non-zero with NON-label stderr (HTTP 401) on every call.
#   With LABEL_ARGS present (auto_merge_allowed=false) the old code would retry;
#   the new code must NOT retry — only ONE gh call, opened:false, gh_failed, exit≠0.
# ──────────────────────────────────────────────────────────────────────────────
T="$(mktask k4a with_body)"
GH_LOG="$TMP/k4a-gh.log"; rm -f "$GH_LOG"
out="$(WO_MERGE_GATE_CMD="$MG_STUB_NO_AUTO" \
      WO_GH_CMD="$GH_STUB_K4A" \
      WO_GH_STUB_LOG="$GH_LOG" \
      bash "$KERNEL" "$T" 2>/dev/null)"
rc=$?
opened_k4a="$(jq -r '.opened' <<<"$out" 2>/dev/null || echo err)"
reason_k4a="$(jq -r '.reason' <<<"$out" 2>/dev/null || echo err)"
call_count_k4a="$(grep -c '^ARGV:' "$GH_LOG" 2>/dev/null || echo 0)"
if [ "$rc" -ne 0 ] \
   && [ "$opened_k4a" = "false" ] \
   && echo "$reason_k4a" | grep -q 'gh_failed' \
   && [ "$call_count_k4a" -eq 1 ]; then
  pass "K4-A"
else
  fail "K4-A" "rc=$rc opened=$opened_k4a reason=$reason_k4a gh_calls=$call_count_k4a (want 1; non-label error must not trigger retry)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# K4-B (LOW fix — no duplicate PR):
#   gh stub: pr create → logs CREATE + emits label-ish stderr, exits 1.
#            pr view  → returns existing PR URL (simulate: PR was created before label failed).
#   The kernel must detect the existing PR and skip the retry.
#   Assert: exactly ONE pr create call in the log (no second create = no duplicate).
# ──────────────────────────────────────────────────────────────────────────────
T="$(mktask k4b with_body)"
GH_LOG="$TMP/k4b-gh.log"; rm -f "$GH_LOG"
out="$(WO_MERGE_GATE_CMD="$MG_STUB_NO_AUTO" \
      WO_GH_CMD="$GH_STUB_K4B" \
      WO_GH_STUB_LOG="$GH_LOG" \
      bash "$KERNEL" "$T" 2>/dev/null)"
rc=$?
create_count_k4b="$(grep -c '^CREATE$' "$GH_LOG" 2>/dev/null || echo 0)"
opened_k4b="$(jq -r '.opened' <<<"$out" 2>/dev/null || echo err)"
if [ "$rc" -ne 0 ] \
   && [ "$opened_k4b" = "false" ] \
   && [ "$create_count_k4b" -eq 1 ]; then
  pass "K4-B"
else
  fail "K4-B" "rc=$rc opened=$opened_k4b create_calls=$create_count_k4b (want 1; existing PR must block retry)"
fi

# ══════════════════════════════════════════════════════════════════════════════
# K3 ④-touch (safety_governor): out-of-band PAT read from WO_MERGE_PAT_FILE at call
# time. File WINS over WO_MERGE_GH_TOKEN; -s guards an empty file (→ env fallback);
# absent/unreadable → env fallback (current behavior). Token still redacted in stdout.
# (kernels.md T9–T12, renamed PAT-1..PAT-4 to avoid the existing T9/T10/T11.)
# ══════════════════════════════════════════════════════════════════════════════

# ── PAT-1 (kernels T9): WO_MERGE_PAT_FILE set + readable → gh gets file contents (file WINS over env);
#                        the PAT value is NOT leaked into stdout JSON.
T="$(mktask pat1 with_body)"
GH_LOG="$TMP/pat1.log"; rm -f "$GH_LOG"
PATF="$TMP/pat1.token"; printf 'file-pat-AAA' > "$PATF"
out="$(WO_MERGE_GATE_CMD="$MG_STUB_OK" WO_GH_CMD="$GH_STUB" WO_GH_STUB_LOG="$GH_LOG" \
      WO_MERGE_GH_TOKEN="env-pat-BBB" WO_MERGE_PAT_FILE="$PATF" \
      bash "$KERNEL" "$T" 2>/dev/null)"
rc=$?
stub_tok="$(grep '^GH_TOKEN_ENV:' "$GH_LOG" 2>/dev/null | head -1 | sed 's/^GH_TOKEN_ENV: //' || echo missing)"
leaked="$(echo "$out" | grep -c 'file-pat-AAA' || true)"
if [ "$rc" -eq 0 ] && [ "$stub_tok" = "file-pat-AAA" ] && [ "$leaked" -eq 0 ]; then
  pass "PAT-1"
else
  fail "PAT-1" "rc=$rc stub_tok=[$stub_tok] (want file-pat-AAA; file must WIN over env) value_leaked=$leaked"
fi

# ── PAT-2 (kernels T10): WO_MERGE_PAT_FILE set but absent/unreadable → falls back to WO_MERGE_GH_TOKEN.
T="$(mktask pat2 with_body)"
GH_LOG="$TMP/pat2.log"; rm -f "$GH_LOG"
out="$(WO_MERGE_GATE_CMD="$MG_STUB_OK" WO_GH_CMD="$GH_STUB" WO_GH_STUB_LOG="$GH_LOG" \
      WO_MERGE_GH_TOKEN="env-pat-CCC" WO_MERGE_PAT_FILE="$TMP/no-such-pat-file" \
      bash "$KERNEL" "$T" 2>/dev/null)"
rc=$?
stub_tok="$(grep '^GH_TOKEN_ENV:' "$GH_LOG" 2>/dev/null | head -1 | sed 's/^GH_TOKEN_ENV: //' || echo missing)"
if [ "$rc" -eq 0 ] && [ "$stub_tok" = "env-pat-CCC" ]; then
  pass "PAT-2"
else
  fail "PAT-2" "rc=$rc stub_tok=[$stub_tok] (want env fallback env-pat-CCC when file absent)"
fi

# ── PAT-3 (-s empty-file guard): WO_MERGE_PAT_FILE present but 0-byte → falls back to env (not an empty token).
T="$(mktask pat3 with_body)"
GH_LOG="$TMP/pat3.log"; rm -f "$GH_LOG"
EMPTYF="$TMP/pat3.empty"; : > "$EMPTYF"
out="$(WO_MERGE_GATE_CMD="$MG_STUB_OK" WO_GH_CMD="$GH_STUB" WO_GH_STUB_LOG="$GH_LOG" \
      WO_MERGE_GH_TOKEN="env-pat-DDD" WO_MERGE_PAT_FILE="$EMPTYF" \
      bash "$KERNEL" "$T" 2>/dev/null)"
rc=$?
stub_tok="$(grep '^GH_TOKEN_ENV:' "$GH_LOG" 2>/dev/null | head -1 | sed 's/^GH_TOKEN_ENV: //' || echo missing)"
if [ "$rc" -eq 0 ] && [ "$stub_tok" = "env-pat-DDD" ]; then
  pass "PAT-3"
else
  fail "PAT-3" "rc=$rc stub_tok=[$stub_tok] (want env fallback; -s must reject empty file)"
fi

# ── PAT-4 (kernels T11): neither file nor env → ambient gh auth (v1 gap), unchanged.
T="$(mktask pat4 with_body)"
GH_LOG="$TMP/pat4.log"; rm -f "$GH_LOG"
out="$(GH_TOKEN="" WO_MERGE_GATE_CMD="$MG_STUB_OK" WO_GH_CMD="$GH_STUB" WO_GH_STUB_LOG="$GH_LOG" \
      bash "$KERNEL" "$T" 2>/dev/null)"
rc=$?
opened="$(jq -r '.opened' <<<"$out" 2>/dev/null || echo err)"
stub_tok="$(grep '^GH_TOKEN_ENV:' "$GH_LOG" 2>/dev/null | head -1 | sed 's/^GH_TOKEN_ENV: //' || echo missing)"
if [ "$rc" -eq 0 ] && [ "$opened" = "true" ] && [ -z "$stub_tok" ]; then
  pass "PAT-4"
else
  fail "PAT-4" "rc=$rc opened=$opened stub_tok=[$stub_tok] (want empty; ambient auth unchanged)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# T8: grep kernel source — ZERO occurrences of "pr merge" (AC4: ③ never merges)
# ──────────────────────────────────────────────────────────────────────────────
if grep -q 'pr merge' "$KERNEL" 2>/dev/null; then
  count="$(grep -c 'pr merge' "$KERNEL" 2>/dev/null; true)"
  fail "T8" "found $count occurrence(s) of 'pr merge' in $KERNEL — AC4 violated"
else
  pass "T8"
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo "----"
echo "wo-pr-open-spec: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
