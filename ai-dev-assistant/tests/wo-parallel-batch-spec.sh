#!/usr/bin/env bash
# TDD spec for scripts/wo-parallel-batch.sh — the deterministic disjoint-file batch scheduler.
# Verifies: disjoint dirs co-batch; same-file / same-dir-glob / nested-dir overlaps defer the
# later WO (conflicts_with the earlier); segment-aware non-overlap (src vs src-other) co-batches;
# a no-files WO is solo-only (never batched with others) + warns; terminal (HALT) WOs are excluded
# from the ready set; a blocked WO with an unfinished dep is excluded; a blocked WO with all deps
# done is eligible; --max caps the batch; empty dir ⇒ [] exit 0; missing dir ⇒ exit 2; deterministic
# ascending wo-id order; and the read-only posture (jq-built, no HALT-write/gh/git-reset/set-status).
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"; ROOT="$(dirname "$HERE")"
export CLAUDE_PLUGIN_ROOT="$ROOT"
SUT="$ROOT/scripts/wo-parallel-batch.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

krun() { OUT="$(bash "$SUT" "$@" 2>/dev/null)"; RC=$?; }
fail_check() { FAIL=$((FAIL+1)); echo "FAIL $1: $2"; [ -n "${OUT:-}" ] && echo "  out: $OUT"; }
pass_check() { PASS=$((PASS+1)); }
mkwo() { local d="$TMP/$1"; mkdir -p "$d"; echo "$d"; }

# mkwo_file: write a WO. $1=dir $2=wo_id $3=status $4=blocked_by_csv("" for none) then $5...=files.
mkwo_file() {
  local d="$1" id="$2" status="$3" bb="$4"; shift 4
  local f="$d/$id-x.md" p dep items=""
  {
    printf -- '---\n'
    printf 'id: %s\n' "$id"
    printf 'status: %s\n' "$status"
    if [ -n "$bb" ]; then
      local deps; IFS=',' read -ra deps <<< "$bb"
      for dep in "${deps[@]}"; do items="$items local:demo#$dep,"; done
      printf 'blocked_by: [%s ]\n' "${items%,}"
    else
      printf 'blocked_by: []\n'
    fi
    printf 'title: t\n---\n\n'
    if [ "$#" -gt 0 ]; then
      printf '## Files to touch\n\n'
      for p in "$@"; do printf -- '- `%s`\n' "$p"; done
      printf '\n'
    fi
    printf '## Done =\n- ok\n'
  } > "$f"
}
halt_marker() { jq -nc --arg wo "$2" '{wo_id:$wo, reason:"x", at:"2026-01-01T00:00:00Z"}' > "$1/$2.HALT"; }

jhas_batch()  { jq -e --arg w "$1" 'any(.batch[];   .wo_id==$w)' <<<"$OUT" >/dev/null 2>&1; }
jhas_defer()  { jq -e --arg w "$1" 'any(.deferred[];.wo_id==$w)' <<<"$OUT" >/dev/null 2>&1; }
jdefer_reason(){ jq -r --arg w "$1" '.deferred[]|select(.wo_id==$w)|.reason' <<<"$OUT" 2>/dev/null; }
jdefer_confl() { jq -rc --arg w "$1" '.deferred[]|select(.wo_id==$w)|.conflicts_with' <<<"$OUT" 2>/dev/null; }

# ---------------------------------------------------------------------------
# T1: two WOs in disjoint dirs → BOTH in batch.
D="$(mkwo t1)"
mkwo_file "$D" wo-01 ready "" "src/a/foo.php"
mkwo_file "$D" wo-02 ready "" "src/b/bar.php"
krun "$D"
if [ "$RC" -eq 0 ] && [ "$(jq -r '.batch|length' <<<"$OUT")" = "2" ] \
  && jhas_batch wo-01 && jhas_batch wo-02 \
  && [ "$(jq -r '.ready_total' <<<"$OUT")" = "2" ]; then
  pass_check "T1 disjoint dirs co-batch"
else fail_check "T1 disjoint dirs" "rc=$RC"; fi

# ---------------------------------------------------------------------------
# T2: two WOs touching the SAME file → second deferred, conflicts_with [wo-01].
D="$(mkwo t2)"
mkwo_file "$D" wo-01 ready "" "src/a/foo.php"
mkwo_file "$D" wo-02 ready "" "src/a/foo.php"
krun "$D"
if jhas_batch wo-01 && jhas_defer wo-02 \
  && [ "$(jdefer_reason wo-02)" = "file_overlap" ] \
  && [ "$(jdefer_confl wo-02)" = '["wo-01"]' ]; then
  pass_check "T2 same file: second deferred conflicts_with first"
else fail_check "T2 same file" "out=$OUT"; fi

# ---------------------------------------------------------------------------
# T3: same-directory glob overlap → conflict.
D="$(mkwo t3)"
mkwo_file "$D" wo-01 ready "" 'src/a/*.php'
mkwo_file "$D" wo-02 ready "" 'src/a/foo.php'
krun "$D"
if jhas_batch wo-01 && jhas_defer wo-02 && [ "$(jdefer_reason wo-02)" = "file_overlap" ]; then
  pass_check "T3 same-dir glob overlap → conflict"
else fail_check "T3 glob overlap" "out=$OUT"; fi

# ---------------------------------------------------------------------------
# T4: nested dir (src/ vs src/foo/bar.php) → conflict.
D="$(mkwo t4)"
mkwo_file "$D" wo-01 ready "" 'src/'
mkwo_file "$D" wo-02 ready "" 'src/foo/bar.php'
krun "$D"
if jhas_batch wo-01 && jhas_defer wo-02 && [ "$(jdefer_reason wo-02)" = "file_overlap" ]; then
  pass_check "T4 nested dir → conflict"
else fail_check "T4 nested dir" "out=$OUT"; fi

# ---------------------------------------------------------------------------
# T4b: segment-aware NON-overlap (src vs src-other/x.php) → BOTH batch (no false positive).
D="$(mkwo t4b)"
mkwo_file "$D" wo-01 ready "" 'src/foo.php'
mkwo_file "$D" wo-02 ready "" 'src-other/x.php'
krun "$D"
if [ "$(jq -r '.batch|length' <<<"$OUT")" = "2" ] && jhas_batch wo-01 && jhas_batch wo-02; then
  pass_check "T4b segment-aware: src vs src-other co-batch (no false overlap)"
else fail_check "T4b segment-aware non-overlap" "out=$OUT"; fi

# ---------------------------------------------------------------------------
# T5: a no-files WO with others → solo-only (NEVER batched with others), warning emitted.
#     wo-02 declares no files; wo-01 + wo-03 disjoint ⇒ they batch, wo-02 deferred.
D="$(mkwo t5)"
mkwo_file "$D" wo-01 ready "" "src/a/foo.php"
mkwo_file "$D" wo-02 ready ""           # no files
mkwo_file "$D" wo-03 ready "" "src/b/bar.php"
krun "$D"
if jhas_batch wo-01 && jhas_batch wo-03 && ! jhas_batch wo-02 \
  && jhas_defer wo-02 && [ "$(jdefer_reason wo-02)" = "no_files_declared" ] \
  && [ "$(jq -r '.warnings|length' <<<"$OUT")" -ge 1 ] \
  && jq -e '.warnings|any(test("wo-02"))' <<<"$OUT" >/dev/null; then
  pass_check "T5 no-files WO: solo-only, deferred among others, warning emitted"
else fail_check "T5 no-files WO with others" "out=$OUT"; fi

# T5b: a no-files WO ALONE → runs SOLO (batch of itself) + warning.
D="$(mkwo t5b)"
mkwo_file "$D" wo-09 ready ""           # no files, only WO
krun "$D"
if [ "$(jq -r '.batch|length' <<<"$OUT")" = "1" ] && jhas_batch wo-09 \
  && [ "$(jq -r '.warnings|length' <<<"$OUT")" -ge 1 ]; then
  pass_check "T5b no-files WO alone: solo batch + warning"
else fail_check "T5b no-files WO alone" "out=$OUT"; fi

# ---------------------------------------------------------------------------
# T6: a TERMINAL WO (HALT marker) is EXCLUDED from the ready set (not batched, not deferred).
D="$(mkwo t6)"
mkwo_file "$D" wo-01 ready "" "src/a/foo.php"
mkwo_file "$D" wo-02 ready "" "src/b/bar.php"
halt_marker "$D" wo-02
krun "$D"
if [ "$(jq -r '.ready_total' <<<"$OUT")" = "1" ] && jhas_batch wo-01 \
  && ! jhas_batch wo-02 && ! jhas_defer wo-02; then
  pass_check "T6 terminal (HALT) WO excluded from ready set"
else fail_check "T6 terminal HALT excluded" "out=$OUT"; fi

# ---------------------------------------------------------------------------
# T7: a blocked WO with an UNFINISHED dep is excluded (dep wo-04 is ready, not done).
D="$(mkwo t7)"
mkwo_file "$D" wo-04 ready  "" "src/a/foo.php"
mkwo_file "$D" wo-05 blocked "wo-04" "src/b/bar.php"
krun "$D"
# wo-04 is ready (eligible, batched); wo-05 blocked-on-unfinished ⇒ NOT eligible.
if jhas_batch wo-04 && ! jhas_batch wo-05 && ! jhas_defer wo-05 \
  && [ "$(jq -r '.ready_total' <<<"$OUT")" = "1" ]; then
  pass_check "T7 blocked WO with unfinished dep excluded"
else fail_check "T7 blocked unfinished dep" "out=$OUT"; fi

# ---------------------------------------------------------------------------
# T8: a blocked WO with ALL deps done is eligible (dep wo-06 is done; done WOs are NOT themselves eligible).
D="$(mkwo t8)"
mkwo_file "$D" wo-06 done    "" "src/a/foo.php"
mkwo_file "$D" wo-07 blocked "wo-06" "src/b/bar.php"
krun "$D"
if jhas_batch wo-07 && ! jhas_batch wo-06 \
  && [ "$(jq -r '.ready_total' <<<"$OUT")" = "1" ]; then
  pass_check "T8 blocked WO with all deps done is eligible"
else fail_check "T8 blocked all-deps-done eligible" "out=$OUT"; fi

# ---------------------------------------------------------------------------
# T9: --max 1 → batch of exactly 1; the disjoint other deferred reason batch_full.
D="$(mkwo t9)"
mkwo_file "$D" wo-01 ready "" "src/a/foo.php"
mkwo_file "$D" wo-02 ready "" "src/b/bar.php"
krun "$D" --max 1
if [ "$(jq -r '.batch|length' <<<"$OUT")" = "1" ] && jhas_batch wo-01 \
  && jhas_defer wo-02 && [ "$(jdefer_reason wo-02)" = "batch_full" ] \
  && [ "$(jq -r '.max' <<<"$OUT")" = "1" ]; then
  pass_check "T9 --max 1: batch of exactly 1, other deferred batch_full"
else fail_check "T9 --max 1" "out=$OUT"; fi

# ---------------------------------------------------------------------------
# T10: empty dir → empty batch, exit 0, ready_total 0.
D="$(mkwo t10)"
krun "$D"
if [ "$RC" -eq 0 ] && [ "$(jq -r '.batch|length' <<<"$OUT")" = "0" ] \
  && [ "$(jq -r '.ready_total' <<<"$OUT")" = "0" ] \
  && [ "$(jq -r '.schema_version' <<<"$OUT")" = "1.0" ]; then
  pass_check "T10 empty dir: [] batch exit 0"
else fail_check "T10 empty dir" "rc=$RC out=$OUT"; fi

# ---------------------------------------------------------------------------
# T11: missing dir arg → exit 2 + {error}.
krun
if [ "$RC" -eq 2 ] && [ -n "$(jq -r '.error' <<<"$OUT" 2>/dev/null)" ]; then
  pass_check "T11 missing dir arg: exit 2 + {error}"
else fail_check "T11 missing dir arg" "rc=$RC out=$OUT"; fi
# T11b: nonexistent dir → exit 2.
krun "$TMP/nope"
if [ "$RC" -eq 2 ] && [ "$(jq -r '.error' <<<"$OUT" 2>/dev/null)" = "work_orders_dir_missing" ]; then
  pass_check "T11b nonexistent dir: exit 2"
else fail_check "T11b nonexistent dir" "rc=$RC out=$OUT"; fi

# ---------------------------------------------------------------------------
# T12: deterministic ascending wo-id order — wo-02 precedes wo-10 in the batch (sort -V, not lexical).
D="$(mkwo t12)"
mkwo_file "$D" wo-10 ready "" "src/j/j.php"
mkwo_file "$D" wo-02 ready "" "src/b/b.php"
krun "$D"
ORDER="$(jq -rc '[.batch[].wo_id]' <<<"$OUT")"
if [ "$ORDER" = '["wo-02","wo-10"]' ]; then
  pass_check "T12 deterministic ascending wo-id order (wo-02 before wo-10)"
else fail_check "T12 deterministic order" "order=$ORDER"; fi

# ---------------------------------------------------------------------------
# T13: stderr line reports ready/batch/deferred/max.
D="$(mkwo t13)"
mkwo_file "$D" wo-01 ready "" "src/a/foo.php"
mkwo_file "$D" wo-02 ready "" "src/a/foo.php"
ERR="$(bash "$SUT" "$D" 2>&1 >/dev/null)"
if printf '%s' "$ERR" | grep -q 'wo-parallel-batch ready=2 batch=1 deferred=1 max=8'; then
  pass_check "T13 stderr line: ready=2 batch=1 deferred=1 max=8"
else fail_check "T13 stderr line" "err=$ERR"; fi

# ---------------------------------------------------------------------------
# T14 (structural): jq-built + grep-clean of WO mutations (read-only posture).
JQ_BUILD=0; HALT_WRITE=0; GH=0; GIT_RESET=0; SET_STATUS=0; RUNSTATE_WRITE=0
grep -Eq 'jq -n' "$SUT" && JQ_BUILD=1
grep -Eq '(>|>>|mv|cp|touch|tee)[^|]*\.HALT' "$SUT" && HALT_WRITE=1
grep -Eq '\bgh[[:space:]]+pr' "$SUT" && GH=1
grep -Eq 'git[[:space:]].*reset' "$SUT" && GIT_RESET=1
grep -Eq 'set-status' "$SUT" && SET_STATUS=1
grep -Eq 'wo-run-state\.sh[[:space:]]+(dispatch|collect|halt)' "$SUT" && RUNSTATE_WRITE=1
if [ "$JQ_BUILD" -eq 1 ] && [ "$HALT_WRITE" -eq 0 ] && [ "$GH" -eq 0 ] \
  && [ "$GIT_RESET" -eq 0 ] && [ "$SET_STATUS" -eq 0 ] && [ "$RUNSTATE_WRITE" -eq 0 ]; then
  pass_check "T14 structural: jq-built + no HALT-write/gh/git-reset/set-status/run-state-write"
else fail_check "T14 structural" "jq=$JQ_BUILD halt=$HALT_WRITE gh=$GH reset=$GIT_RESET status=$SET_STATUS runstate=$RUNSTATE_WRITE"; fi

# T14b (runtime): running the kernel leaves the work-orders dir byte-identical (no new files/HALT).
D="$(mkwo t14b)"
mkwo_file "$D" wo-01 ready "" "src/a/foo.php"
mkwo_file "$D" wo-02 ready ""
BEFORE="$(ls -1 "$D" | sort)"
krun "$D"
AFTER="$(ls -1 "$D" | sort)"
if [ "$RC" -eq 0 ] && [ "$BEFORE" = "$AFTER" ] && [ "$(find "$D" -name '*.HALT' | wc -l)" -eq 0 ]; then
  pass_check "T14b runtime read-only: dir listing unchanged, no new HALT"
else fail_check "T14b runtime read-only" "rc=$RC changed=$([[ "$BEFORE" != "$AFTER" ]] && echo yes || echo no)"; fi

# ---------------------------------------------------------------------------
# T15: path normalization — './src/a.php' vs 'src/a.php' are the SAME path → overlap (wo-02 deferred).
D="$(mkwo t15)"
mkwo_file "$D" wo-01 ready "" 'src/a.php'
mkwo_file "$D" wo-02 ready "" './src/a.php'
krun "$D"
if jhas_batch wo-01 && jhas_defer wo-02 && [ "$(jdefer_reason wo-02)" = "file_overlap" ]; then
  pass_check "T15 normalize: ./src/a.php == src/a.php → overlap, deferred"
else fail_check "T15 ./ normalization" "out=$OUT"; fi

# T15b: redundant /./ segment — 'src/./a.php' vs 'src/a.php' → overlap.
D="$(mkwo t15b)"
mkwo_file "$D" wo-01 ready "" 'src/a.php'
mkwo_file "$D" wo-02 ready "" 'src/./a.php'
krun "$D"
if jhas_batch wo-01 && jhas_defer wo-02 && [ "$(jdefer_reason wo-02)" = "file_overlap" ]; then
  pass_check "T15b normalize: src/./a.php == src/a.php → overlap, deferred"
else fail_check "T15b /./ normalization" "out=$OUT"; fi

# T16: doubled slash — 'src//a.php' vs 'src/a.php' → overlap.
D="$(mkwo t16)"
mkwo_file "$D" wo-01 ready "" 'src/a.php'
mkwo_file "$D" wo-02 ready "" 'src//a.php'
krun "$D"
if jhas_batch wo-01 && jhas_defer wo-02 && [ "$(jdefer_reason wo-02)" = "file_overlap" ]; then
  pass_check "T16 normalize: src//a.php == src/a.php → overlap, deferred"
else fail_check "T16 // normalization" "out=$OUT"; fi

# T17: brace-glob handled CONSERVATIVELY — 'src/{a,b}.php' literal prefix is 'src/', so it
#      overlaps a sibling 'src/c.php' (no false-disjoint via a too-long literal prefix).
D="$(mkwo t17)"
mkwo_file "$D" wo-01 ready "" 'src/c.php'
mkwo_file "$D" wo-02 ready "" 'src/{a,b}.php'
krun "$D"
if jhas_batch wo-01 && jhas_defer wo-02 && [ "$(jdefer_reason wo-02)" = "file_overlap" ]; then
  pass_check "T17 brace-glob conservative: src/{a,b}.php overlaps src/c.php → deferred"
else fail_check "T17 brace-glob conservative" "out=$OUT"; fi

# T17b: a brace-glob in a DISJOINT dir still co-batches (conservatism is not over-broad across dirs).
D="$(mkwo t17b)"
mkwo_file "$D" wo-01 ready "" 'lib/x.php'
mkwo_file "$D" wo-02 ready "" 'src/{a,b}.php'
krun "$D"
if [ "$(jq -r '.batch|length' <<<"$OUT")" = "2" ] && jhas_batch wo-01 && jhas_batch wo-02; then
  pass_check "T17b brace-glob in disjoint dir co-batches (lib vs src)"
else fail_check "T17b brace-glob disjoint" "out=$OUT"; fi

# ---------------------------------------------------------------------------
echo "----"
echo "wo-parallel-batch-spec: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
