#!/usr/bin/env bash
# Hermetic spec for scripts/wo-oracle-check.sh
# No real git invoked — feeds name-status fixtures + WO-file fixtures + a CALLER-PROVIDED
# oracle-file rule list (--oracle-files). The kernel hardcodes NO framework knowledge, so the
# fixtures use GENERIC oracle files (snapshots/*.snap, specs/*.spec, analysis-baseline.txt, …),
# NOT framework-assumed ones — the same kernel serves any framework whose recipe declares its files.
# Run: bash tests/wo-oracle-check-spec.sh
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"
ROOT="$(dirname "$HERE")"
KERNEL="$ROOT/scripts/wo-oracle-check.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
DIFF_N=0

# ============================================================
# Caller-provided oracle-file rule list (generic — the safety property is that the CALLER
# reconstructs this from the first-party recipe each run and hands it to the kernel).
#   halt rules:  snapshot_write (A,M baseline), spec_delete (D test-delete),
#                analysis_baseline (A,M analysis-baseline)
#   flag rules:  analysis_config (M analysis-baseline), registry_shrink (M baseline),
#                coverage_threshold (M coverage-threshold)
# ============================================================
cat > "$TMP/oracle-files.json" <<'OFEOF'
[
  { "type": "snapshot_write",     "globs": ["snapshots/**/*.snap", "snapshots/**/*.meta.json"], "changes": ["A","M"], "oracle_class": "baseline",            "severity": "halt" },
  { "type": "spec_delete",        "globs": ["specs/**/*.spec"],                                  "changes": ["D"],     "oracle_class": "test-delete",         "severity": "halt" },
  { "type": "analysis_baseline",  "globs": ["analysis-baseline.txt"],                           "changes": ["A","M"], "oracle_class": "analysis-baseline",   "severity": "halt" },
  { "type": "analysis_config",    "globs": ["analysis.config", "analysis.config.dist"],         "changes": ["M"],     "oracle_class": "analysis-baseline",   "severity": "flag" },
  { "type": "registry_shrink",    "globs": [".review/registry.yml"],                            "changes": ["M"],     "oracle_class": "baseline",            "severity": "flag" },
  { "type": "coverage_threshold", "globs": ["coverage.config", "coverage.xml"],                 "changes": ["M"],     "oracle_class": "coverage-threshold",  "severity": "flag" }
]
OFEOF
OF="$TMP/oracle-files.json"

# Empty rule list (a project that declared NO oracle files) — the honest "no oracle configured" state.
echo '[]' > "$TMP/oracle-files-empty.json"
OF_EMPTY="$TMP/oracle-files-empty.json"

# ============================================================
# Fixture WO files (safe YAML frontmatter; never eval'd)
# ============================================================

# Minimal WO with NO oracle_update
cat > "$TMP/wo-no-exempt.md" <<'WOEOF'
---
id: local:test#wo-00
kind: work-order
schema_version: '1.0'
title: Test WO no exemption
status: ready
gate_floor: [tdd, solid, dry, security, guides]
verified: false
---
# Test WO — no oracle_update block
WOEOF

# WO with oracle_update exempting: baseline, analysis-baseline
cat > "$TMP/wo-exempt-baseline.md" <<'WOEOF'
---
id: local:test#wo-01
kind: work-order
schema_version: '1.0'
title: Test WO with oracle_update
status: ready
oracle_update:
  classes: [baseline, analysis-baseline]
  reason: "updating baselines after intentional change"
  by: "carlos"
---
# Test WO — oracle_update: baseline + analysis-baseline
WOEOF

# WO with oracle_update exempting: test-delete
cat > "$TMP/wo-exempt-test-delete.md" <<'WOEOF'
---
id: local:test#wo-02
kind: work-order
schema_version: '1.0'
title: Test WO with test-delete exempt
status: ready
oracle_update:
  classes: [test-delete]
  reason: "removing deprecated integration tests"
  by: "carlos"
---
WOEOF

# M2: oracle_update with QUOTED class names (double quotes) — must still match
cat > "$TMP/wo-exempt-quoted.md" <<'WOEOF'
---
id: local:test#wo-03
kind: work-order
schema_version: '1.0'
title: Test WO with quoted classes
status: ready
oracle_update:
  classes: ["baseline", "test-delete"]
  reason: "intentional change"
  by: "carlos"
---
# Test WO — quoted inline classes
WOEOF

# M2b: single-quoted class names — must still match
cat > "$TMP/wo-exempt-squoted.md" <<'WOEOF'
---
id: local:test#wo-03b
oracle_update:
  classes: ['baseline', 'analysis-baseline']
  reason: "x"
  by: "carlos"
---
WOEOF

# M3: oracle_update with BLOCK-STYLE YAML list — must parse `- item` lines
cat > "$TMP/wo-exempt-block.md" <<'WOEOF'
---
id: local:test#wo-04
kind: work-order
status: ready
oracle_update:
  classes:
    - baseline
    - test-delete
  reason: "block-style list update"
  by: "carlos"
---
# Test WO — block-style classes
WOEOF

# M3b: block-style with QUOTED items — both robustness features combined
cat > "$TMP/wo-exempt-block-quoted.md" <<'WOEOF'
---
id: local:test#wo-04b
oracle_update:
  classes:
    - "baseline"
    - 'analysis-baseline'
  reason: "x"
  by: "y"
---
WOEOF

# L1: UNTERMINATED frontmatter (no closing ---) carrying an oracle_update.
# Per L1 the exemption must NOT be honored (no closing --- => no frontmatter).
cat > "$TMP/wo-unterminated.md" <<'WOEOF'
---
id: local:test#wo-05
oracle_update:
  classes: [baseline, test-delete]
  reason: "looks legit but frontmatter never closes"
  by: "attacker"

# This file has NO closing --- delimiter. The body just continues.
Some prose here that should never be parsed as frontmatter.
WOEOF

# L1b: oracle_update appears ONLY in the body (after a terminated, empty frontmatter)
cat > "$TMP/wo-body-oracle.md" <<'WOEOF'
---
id: local:test#wo-06
status: ready
---
# Body

A malicious note trying to look like config:
oracle_update:
  classes: [baseline, test-delete]
WOEOF

WO="$TMP/wo-no-exempt.md"
WO_EX="$TMP/wo-exempt-baseline.md"
WO_EX_TD="$TMP/wo-exempt-test-delete.md"
WO_QUOTED="$TMP/wo-exempt-quoted.md"
WO_SQUOTED="$TMP/wo-exempt-squoted.md"
WO_BLOCK="$TMP/wo-exempt-block.md"
WO_BLOCK_QUOTED="$TMP/wo-exempt-block-quoted.md"
WO_UNTERM="$TMP/wo-unterminated.md"
WO_BODY="$TMP/wo-body-oracle.md"

# ============================================================
# Helpers to create diff fixtures
# ============================================================

# mk_diff STATUS path — writes name-status fixture, prints path
mk_diff() {
  DIFF_N=$((DIFF_N + 1))
  printf '%s\t%s\n' "$1" "$2" > "$TMP/d${DIFF_N}.txt"
  echo "$TMP/d${DIFF_N}.txt"
}

# mk_rename old new — writes rename fixture (R100), prints path
mk_rename() {
  DIFF_N=$((DIFF_N + 1))
  printf 'R100\t%s\t%s\n' "$1" "$2" > "$TMP/d${DIFF_N}.txt"
  echo "$TMP/d${DIFF_N}.txt"
}

# mk_copy old new — writes copy fixture (C100), prints path
mk_copy() {
  DIFF_N=$((DIFF_N + 1))
  printf 'C100\t%s\t%s\n' "$1" "$2" > "$TMP/d${DIFF_N}.txt"
  echo "$TMP/d${DIFF_N}.txt"
}

# mk_line raw — writes a single raw name-status line verbatim, prints path
mk_line() {
  DIFF_N=$((DIFF_N + 1))
  printf '%s\n' "$1" > "$TMP/d${DIFF_N}.txt"
  echo "$TMP/d${DIFF_N}.txt"
}

# mk_multi — writes a multi-line diff fixture and prints path
mk_multi() {
  DIFF_N=$((DIFF_N + 1))
  printf '%s\n' "$@" > "$TMP/d${DIFF_N}.txt"
  echo "$TMP/d${DIFF_N}.txt"
}

# ============================================================
# Assert helpers — every kernel invocation passes --oracle-files $OF unless the case
# is specifically testing the empty / absent list.
# ============================================================

# assert_verdict label want_tamper want_halt_reason kernel_args...
assert_verdict() {
  local label="$1" e_tamper="$2" e_halt="$3"; shift 3
  local out tamper halt
  out="$(bash "$KERNEL" "$@" 2>/dev/null)"
  tamper="$(printf '%s' "$out" | jq -r '.tamper_detected')"
  halt="$(printf '%s' "$out" | jq -r '.halt_reason // "null"')"
  if [ "$tamper" = "$e_tamper" ] && [ "$halt" = "$e_halt" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL %s: tamper=%s halt=%s (want tamper=%s halt=%s)\n' \
      "$label" "$tamper" "$halt" "$e_tamper" "$e_halt"
    printf '     out: %s\n' "$out"
  fi
}

# assert_no_signals label kernel_args...
assert_no_signals() {
  local label="$1"; shift
  local out count
  out="$(bash "$KERNEL" "$@" 2>/dev/null)"
  count="$(printf '%s' "$out" | jq '.signals | length')"
  if [ "$count" = "0" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL %s: expected 0 signals, got %s\n' "$label" "$count"
    printf '     out: %s\n' "$out"
  fi
}

# assert_signal label want_type want_severity want_oracle_class kernel_args...
assert_signal() {
  local label="$1" e_type="$2" e_sev="$3" e_class="$4"; shift 4
  local out type sev cls
  out="$(bash "$KERNEL" "$@" 2>/dev/null)"
  type="$(printf '%s' "$out" | jq -r '.signals[0].type // "null"')"
  sev="$(printf '%s' "$out" | jq -r '.signals[0].severity // "null"')"
  cls="$(printf '%s' "$out" | jq -r '.signals[0].oracle_class // "null"')"
  if [ "$type" = "$e_type" ] && [ "$sev" = "$e_sev" ] && [ "$cls" = "$e_class" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL %s: type=%s sev=%s class=%s (want %s / %s / %s)\n' \
      "$label" "$type" "$sev" "$cls" "$e_type" "$e_sev" "$e_class"
    printf '     out: %s\n' "$out"
  fi
}

# assert_signal_count label want_count kernel_args...
assert_signal_count() {
  local label="$1" e_count="$2"; shift 2
  local out count
  out="$(bash "$KERNEL" "$@" 2>/dev/null)"
  count="$(printf '%s' "$out" | jq '.signals | length')"
  if [ "$count" = "$e_count" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL %s: signal count=%s (want %s)\n' "$label" "$count" "$e_count"
    printf '     out: %s\n' "$out"
  fi
}

# assert_has_signal label want_type want_change want_severity kernel_args...
assert_has_signal() {
  local label="$1" e_type="$2" e_change="$3" e_sev="$4"; shift 4
  local out found
  out="$(bash "$KERNEL" "$@" 2>/dev/null)"
  found="$(printf '%s' "$out" | jq --arg t "$e_type" --arg c "$e_change" --arg s "$e_sev" \
    '[.signals[] | select(.type==$t and .change==$c and .severity==$s)] | length')"
  if [ "$found" != "0" ] && [ -n "$found" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL %s: no signal type=%s change=%s sev=%s\n' "$label" "$e_type" "$e_change" "$e_sev"
    printf '     out: %s\n' "$out"
  fi
}

# assert_allowed_by_scope label want_allowed kernel_args...
assert_allowed_by_scope() {
  local label="$1" e_allowed="$2"; shift 2
  local out allowed
  out="$(bash "$KERNEL" "$@" 2>/dev/null)"
  allowed="$(printf '%s' "$out" | jq -r '.signals[0].allowed_by_scope')"
  if [ "$allowed" = "$e_allowed" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL %s: allowed_by_scope=%s (want %s)\n' "$label" "$allowed" "$e_allowed"
    printf '     out: %s\n' "$out"
  fi
}

# assert_signal_change label want_change kernel_args...
assert_signal_change() {
  local label="$1" e_change="$2"; shift 2
  local out change
  out="$(bash "$KERNEL" "$@" 2>/dev/null)"
  change="$(printf '%s' "$out" | jq -r '.signals[0].change // "null"')"
  if [ "$change" = "$e_change" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL %s: change=%s (want %s)\n' "$label" "$change" "$e_change"
    printf '     out: %s\n' "$out"
  fi
}

# assert_oracle_configured label want_bool kernel_args...
assert_oracle_configured() {
  local label="$1" e_oc="$2"; shift 2
  local out oc
  out="$(bash "$KERNEL" "$@" 2>/dev/null)"
  oc="$(printf '%s' "$out" | jq -r '.oracle_configured')"
  if [ "$oc" = "$e_oc" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL %s: oracle_configured=%s (want %s)\n' "$label" "$oc" "$e_oc"
    printf '     out: %s\n' "$out"
  fi
}

# ============================================================
# NO-ORACLE — the honest "no oracle configured" state.
#   (a) --oracle-files omitted entirely  (b) an empty [] rule list
# Both: oracle_configured=false, NO signals, tamper=false — never a silent pass that pretends
# a gate ran, and never a crash. Even a path that WOULD be a halt under a rule list is silent
# here because no rule was provided.
# ============================================================
diff="$(mk_diff "A" "analysis-baseline.txt")"
assert_oracle_configured "NO-ORACLE-01a flag absent => oracle_configured=false" false "$WO" --diff-from "$diff"
assert_verdict           "NO-ORACLE-01b flag absent => tamper=false"            false null "$WO" --diff-from "$diff"
assert_no_signals        "NO-ORACLE-01c flag absent => no signals"                    "$WO" --diff-from "$diff"
assert_oracle_configured "NO-ORACLE-02a empty [] => oracle_configured=false" false "$WO" --diff-from "$diff" --oracle-files "$OF_EMPTY"
assert_verdict           "NO-ORACLE-02b empty [] => tamper=false"            false null "$WO" --diff-from "$diff" --oracle-files "$OF_EMPTY"
assert_no_signals        "NO-ORACLE-02c empty [] => no signals"                    "$WO" --diff-from "$diff" --oracle-files "$OF_EMPTY"
# a provided list flips oracle_configured to true
assert_oracle_configured "NO-ORACLE-03 provided list => oracle_configured=true" true "$WO" --diff-from "$diff" --oracle-files "$OF"

# ============================================================
# TC-01: Clean diff (no watched paths) => tamper=false, signals=[], halt_reason=null
# ============================================================
diff_clean="$(mk_diff "M" "src/some/file.ext")"
assert_verdict    "TC-01a clean tamper=false"   false null "$WO" --diff-from "$diff_clean" --oracle-files "$OF"
assert_no_signals "TC-01b clean no signals"             "$WO" --diff-from "$diff_clean" --oracle-files "$OF"

# ============================================================
# TC-02: snapshot_write — A on .snap => halt, tamper=true, change=A
# ============================================================
diff="$(mk_diff "A" "snapshots/homepage/screenshot.snap")"
assert_verdict       "TC-02a snapshot_write A tamper=true" true oracle_tamper "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_signal        "TC-02b snapshot_write A signal"      snapshot_write halt baseline "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_signal_change "TC-02c snapshot_write A change=A"    A "$WO" --diff-from "$diff" --oracle-files "$OF"

# ============================================================
# TC-03: snapshot_write — M on .meta.json => halt, tamper=true, change=M
# ============================================================
diff="$(mk_diff "M" "snapshots/homepage/test.meta.json")"
assert_verdict       "TC-03a snapshot_write M tamper=true" true oracle_tamper "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_signal        "TC-03b snapshot_write M signal"      snapshot_write halt baseline "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_signal_change "TC-03c snapshot_write M change=M"    M "$WO" --diff-from "$diff" --oracle-files "$OF"

# ============================================================
# TC-04: snapshot_write — D on .snap => NO signal (D not in watched changes)
# ============================================================
diff="$(mk_diff "D" "snapshots/homepage/screenshot.snap")"
assert_verdict    "TC-04a snapshot_write D no tamper" false null "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_no_signals "TC-04b snapshot_write D no signal"       "$WO" --diff-from "$diff" --oracle-files "$OF"

# ============================================================
# TC-05: spec_delete — D on specs/**/*.spec => halt, tamper=true, change=D
# ============================================================
diff="$(mk_diff "D" "specs/homepage.spec")"
assert_verdict       "TC-05a spec_delete D tamper=true" true oracle_tamper "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_signal        "TC-05b spec_delete D signal"      spec_delete halt test-delete "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_signal_change "TC-05c spec_delete D change=D"    D "$WO" --diff-from "$diff" --oracle-files "$OF"

# ============================================================
# TC-06: spec_delete — A on specs/**/*.spec => NO signal (only D watched)
# ============================================================
diff="$(mk_diff "A" "specs/homepage.spec")"
assert_verdict    "TC-06a spec_delete A no tamper" false null "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_no_signals "TC-06b spec_delete A no signal"       "$WO" --diff-from "$diff" --oracle-files "$OF"

# TC-06c: nested spec path (** across multiple segments)
diff="$(mk_diff "D" "specs/auth/login.spec")"
assert_verdict "TC-06d spec_delete nested D" true oracle_tamper "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_signal  "TC-06e spec_delete nested D signal" spec_delete halt test-delete "$WO" --diff-from "$diff" --oracle-files "$OF"

# ============================================================
# TC-11: analysis_baseline — A => halt, tamper=true
# ============================================================
diff="$(mk_diff "A" "analysis-baseline.txt")"
assert_verdict "TC-11a analysis_baseline A tamper=true" true oracle_tamper "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_signal  "TC-11b analysis_baseline A signal"      analysis_baseline halt analysis-baseline "$WO" --diff-from "$diff" --oracle-files "$OF"

# ============================================================
# TC-12: analysis_baseline — M => halt, tamper=true
# ============================================================
diff="$(mk_diff "M" "analysis-baseline.txt")"
assert_verdict "TC-12a analysis_baseline M tamper=true" true oracle_tamper "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_signal  "TC-12b analysis_baseline M signal"      analysis_baseline halt analysis-baseline "$WO" --diff-from "$diff" --oracle-files "$OF"

# ============================================================
# TC-13: analysis_baseline — D => NO signal (only A,M watched)
# ============================================================
diff="$(mk_diff "D" "analysis-baseline.txt")"
assert_verdict    "TC-13a analysis_baseline D no tamper" false null "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_no_signals "TC-13b analysis_baseline D no signal"       "$WO" --diff-from "$diff" --oracle-files "$OF"

# ============================================================
# TC-14: analysis_config — M analysis.config => flag signal, tamper=false
# ============================================================
diff="$(mk_diff "M" "analysis.config")"
assert_verdict "TC-14a analysis_config M tamper=false" false null "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_signal  "TC-14b analysis_config M signal"       analysis_config flag analysis-baseline "$WO" --diff-from "$diff" --oracle-files "$OF"

# TC-15: analysis_config — M analysis.config.dist => flag
diff="$(mk_diff "M" "analysis.config.dist")"
assert_verdict "TC-15a analysis_config dist M tamper=false" false null "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_signal  "TC-15b analysis_config dist M signal"       analysis_config flag analysis-baseline "$WO" --diff-from "$diff" --oracle-files "$OF"

# TC-16: analysis_config — A => NO signal (only M watched)
diff="$(mk_diff "A" "analysis.config")"
assert_verdict    "TC-16a analysis_config A no tamper" false null "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_no_signals "TC-16b analysis_config A no signal"       "$WO" --diff-from "$diff" --oracle-files "$OF"

# ============================================================
# TC-17: registry_shrink — M => flag signal, tamper=false
# ============================================================
diff="$(mk_diff "M" ".review/registry.yml")"
assert_verdict "TC-17a registry_shrink M tamper=false" false null "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_signal  "TC-17b registry_shrink M signal"       registry_shrink flag baseline "$WO" --diff-from "$diff" --oracle-files "$OF"

# TC-18: registry_shrink — A => NO signal (only M watched)
diff="$(mk_diff "A" ".review/registry.yml")"
assert_verdict    "TC-18a registry_shrink A no tamper" false null "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_no_signals "TC-18b registry_shrink A no signal"       "$WO" --diff-from "$diff" --oracle-files "$OF"

# ============================================================
# TC-19/20/21: coverage_threshold — M => flag
# ============================================================
diff="$(mk_diff "M" "coverage.config")"
assert_verdict "TC-19a coverage_threshold config M tamper=false" false null "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_signal  "TC-19b coverage_threshold config M signal"       coverage_threshold flag coverage-threshold "$WO" --diff-from "$diff" --oracle-files "$OF"
diff="$(mk_diff "M" "coverage.xml")"
assert_verdict "TC-20a coverage_threshold xml M tamper=false" false null "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_signal  "TC-20b coverage_threshold xml M signal"       coverage_threshold flag coverage-threshold "$WO" --diff-from "$diff" --oracle-files "$OF"
# TC-22: coverage_threshold — A => NO signal (only M watched)
diff="$(mk_diff "A" "coverage.xml")"
assert_verdict    "TC-22a coverage_threshold A no tamper" false null "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_no_signals "TC-22b coverage_threshold A no signal"       "$WO" --diff-from "$diff" --oracle-files "$OF"

# ============================================================
# TC-23: oracle_update exemption — in-class halt (baseline) => flag, allowed=true, tamper=false
# WO has oracle_update.classes: [baseline, analysis-baseline]
# ============================================================
diff="$(mk_diff "A" "snapshots/page/screen.snap")"
assert_verdict         "TC-23a exempt baseline in-class tamper=false" false null "$WO_EX" --diff-from "$diff" --oracle-files "$OF"
assert_signal          "TC-23b exempt baseline in-class severity=flag" snapshot_write flag baseline "$WO_EX" --diff-from "$diff" --oracle-files "$OF"
assert_allowed_by_scope "TC-23c exempt baseline in-class allowed=true" true "$WO_EX" --diff-from "$diff" --oracle-files "$OF"

# ============================================================
# TC-24: oracle_update exemption — out-of-class halt (test-delete) stays halt, tamper=true
# WO has oracle_update.classes: [baseline, analysis-baseline] — test-delete NOT in scope
# ============================================================
diff="$(mk_diff "D" "specs/homepage.spec")"
assert_verdict         "TC-24a exempt out-of-class tamper=true"    true oracle_tamper "$WO_EX" --diff-from "$diff" --oracle-files "$OF"
assert_allowed_by_scope "TC-24b exempt out-of-class allowed=false" false "$WO_EX" --diff-from "$diff" --oracle-files "$OF"
assert_signal          "TC-24c exempt out-of-class severity=halt"  spec_delete halt test-delete "$WO_EX" --diff-from "$diff" --oracle-files "$OF"

# ============================================================
# TC-25: absent oracle_update — nothing exempt (analysis_baseline stays halt)
# ============================================================
diff="$(mk_diff "A" "analysis-baseline.txt")"
assert_verdict         "TC-25a absent oracle_update tamper=true"    true oracle_tamper "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_allowed_by_scope "TC-25b absent oracle_update allowed=false" false "$WO" --diff-from "$diff" --oracle-files "$OF"

# ============================================================
# TC-26: oracle_update exemption — test-delete in-class => flag, allowed=true, tamper=false
# WO has oracle_update.classes: [test-delete]
# ============================================================
diff="$(mk_diff "D" "specs/SomeTest.spec")"
assert_verdict         "TC-26a exempt test-delete in-class tamper=false" false null "$WO_EX_TD" --diff-from "$diff" --oracle-files "$OF"
assert_signal          "TC-26b exempt test-delete in-class severity=flag" spec_delete flag test-delete "$WO_EX_TD" --diff-from "$diff" --oracle-files "$OF"
assert_allowed_by_scope "TC-26c exempt test-delete allowed=true" true "$WO_EX_TD" --diff-from "$diff" --oracle-files "$OF"

# ============================================================
# TC-27: Rename (R100) — OLD path D against D-rows; here OLD is analysis-baseline.txt which is
# NOT a D-row (only A,M watched) => no D signal; NEW path A is the baseline => halt.
# ============================================================
diff="$(mk_rename "old/analysis-baseline.txt" "analysis-baseline.txt")"
assert_verdict "TC-27a rename new=analysis_baseline tamper=true" true oracle_tamper "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_has_signal "TC-27b rename new analysis_baseline A" analysis_baseline A halt "$WO" --diff-from "$diff" --oracle-files "$OF"

# TC-27c: rename of a non-watched file => no signal
diff="$(mk_rename "old/src/Foo.ext" "src/Bar.ext")"
assert_verdict    "TC-27c rename non-watched no tamper" false null "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_no_signals "TC-27d rename non-watched no signal"       "$WO" --diff-from "$diff" --oracle-files "$OF"

# ============================================================
# TC-28: Multiple signals in one diff (a halt + a flag) => tamper=true
# ============================================================
diff="$(mk_multi \
  "A	snapshots/p/s.snap" \
  "M	coverage.xml")"
assert_verdict "TC-28a multi halt+flag tamper=true" true oracle_tamper "$WO" --diff-from "$diff" --oracle-files "$OF"

# ============================================================
# TC-29: flag-only signals do NOT set tamper_detected
# ============================================================
diff="$(mk_diff "M" "analysis.config")"
assert_verdict "TC-29 flag-only tamper=false" false null "$WO" --diff-from "$diff" --oracle-files "$OF"

# ============================================================
# TC-30: schema_version is "1.0" in the JSON output
# ============================================================
diff="$(mk_diff "M" "src/SomeClass.ext")"
out30="$(bash "$KERNEL" "$WO" --diff-from "$diff" --oracle-files "$OF" 2>/dev/null)"
sv30="$(printf '%s' "$out30" | jq -r '.schema_version')"
if [ "$sv30" = "1.0" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  printf 'FAIL TC-30 schema_version: got "%s" (want "1.0")\n' "$sv30"
fi

# ============================================================
# TC-31: analysis_baseline in-class exemption (oracle_update has analysis-baseline)
# ============================================================
diff="$(mk_diff "M" "analysis-baseline.txt")"
assert_verdict         "TC-31a analysis_baseline exempt tamper=false" false null "$WO_EX" --diff-from "$diff" --oracle-files "$OF"
assert_signal          "TC-31b analysis_baseline exempt severity=flag" analysis_baseline flag analysis-baseline "$WO_EX" --diff-from "$diff" --oracle-files "$OF"
assert_allowed_by_scope "TC-31c analysis_baseline exempt allowed=true" true "$WO_EX" --diff-from "$diff" --oracle-files "$OF"

# ============================================================
# ===== RED-TEAM CORRECTION COVERAGE (C1 / M1 / M2 / M3 / L1 / L2) =====
# ============================================================

# ============================================================
# C1 — RENAME-EVASION: git mv a spec OUT of specs/ must be caught as a spec_delete on the OLD
# path (change:"D", halt), tamper=true.
# ============================================================
diff="$(mk_rename "specs/CriticalTest.spec" "disabled/CriticalTest.spec")"
assert_verdict    "C1-01a rename spec out-of-specs tamper=true" true oracle_tamper "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_has_signal "C1-01b rename old=spec_delete D halt" spec_delete D halt "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_signal     "C1-01c rename signals[0]=spec_delete (old path first)" spec_delete halt test-delete "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_signal_change "C1-01d rename signals[0].change=D" D "$WO" --diff-from "$diff" --oracle-files "$OF"

# C1 — rename that INTRODUCES a snapshot on the NEW path => snapshot_write A halt
diff="$(mk_rename "stash/screen.snap" "snapshots/home/screen.snap")"
assert_verdict    "C1-05a rename introduces snapshot tamper=true" true oracle_tamper "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_has_signal "C1-05b rename new=snapshot_write A halt" snapshot_write A halt "$WO" --diff-from "$diff" --oracle-files "$OF"

# C1 — rename of a spec OUT, new path not watched => exactly ONE signal.
diff="$(mk_rename "specs/CriticalTest.spec" "disabled/CriticalTest.spec")"
assert_signal_count "C1-06 rename spec-out single signal" 1 "$WO" --diff-from "$diff" --oracle-files "$OF"

# C1 — bare R (no score) handled the same: old->D, new->A
diff="$(mk_line "R	specs/CriticalTest.spec	disabled/CriticalTest.spec")"
assert_verdict    "C1-07a bare R rename tamper=true" true oracle_tamper "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_has_signal "C1-07b bare R old=spec_delete D halt" spec_delete D halt "$WO" --diff-from "$diff" --oracle-files "$OF"

# ============================================================
# M1 — COPY (C###): the NEW path is classified as A; the OLD path is untouched (no D).
# ============================================================
diff="$(mk_copy "templates/screen.snap" "snapshots/home/screen.snap")"
assert_verdict    "M1-01a copy introduces snapshot tamper=true" true oracle_tamper "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_has_signal "M1-01b copy new=snapshot_write A halt" snapshot_write A halt "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_signal_count "M1-01c copy single signal (old untouched)" 1 "$WO" --diff-from "$diff" --oracle-files "$OF"

# M1 — copy of a spec FILE: old path is NOT a delete (copy keeps original) => no spec_delete.
diff="$(mk_copy "specs/CriticalTest.spec" "disabled/CriticalTest.spec")"
assert_verdict    "M1-02a copy spec no delete tamper=false" false null "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_no_signals "M1-02b copy spec no signal"                    "$WO" --diff-from "$diff" --oracle-files "$OF"

# M1 — bare C (no score) handled the same: new->A only
diff="$(mk_line "C	templates/screen.snap	snapshots/home/screen.snap")"
assert_verdict    "M1-03a bare C copy tamper=true" true oracle_tamper "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_has_signal "M1-03b bare C new=snapshot_write A halt" snapshot_write A halt "$WO" --diff-from "$diff" --oracle-files "$OF"

# ============================================================
# M2 — QUOTED class names in oracle_update must still match (no false-HALT).
# WO_QUOTED has classes: ["baseline","test-delete"]
# ============================================================
diff="$(mk_diff "A" "snapshots/page/s.snap")"
assert_verdict          "M2-01a quoted baseline exempt tamper=false" false null "$WO_QUOTED" --diff-from "$diff" --oracle-files "$OF"
assert_allowed_by_scope "M2-01b quoted baseline allowed=true" true "$WO_QUOTED" --diff-from "$diff" --oracle-files "$OF"
diff="$(mk_diff "D" "specs/SomeTest.spec")"
assert_verdict          "M2-02a quoted test-delete exempt tamper=false" false null "$WO_QUOTED" --diff-from "$diff" --oracle-files "$OF"
assert_allowed_by_scope "M2-02b quoted test-delete allowed=true" true "$WO_QUOTED" --diff-from "$diff" --oracle-files "$OF"
# single-quoted variant (WO_SQUOTED has [baseline, analysis-baseline])
diff="$(mk_diff "M" "analysis-baseline.txt")"
assert_verdict          "M2-03a single-quoted analysis exempt tamper=false" false null "$WO_SQUOTED" --diff-from "$diff" --oracle-files "$OF"
assert_allowed_by_scope "M2-03b single-quoted analysis allowed=true" true "$WO_SQUOTED" --diff-from "$diff" --oracle-files "$OF"

# ============================================================
# M3 — BLOCK-STYLE YAML list in oracle_update must parse (no false-HALT).
# WO_BLOCK has classes:\n  - baseline\n  - test-delete
# ============================================================
diff="$(mk_diff "A" "snapshots/page/s.snap")"
assert_verdict          "M3-01a block baseline exempt tamper=false" false null "$WO_BLOCK" --diff-from "$diff" --oracle-files "$OF"
assert_allowed_by_scope "M3-01b block baseline allowed=true" true "$WO_BLOCK" --diff-from "$diff" --oracle-files "$OF"
diff="$(mk_diff "D" "specs/SomeTest.spec")"
assert_verdict          "M3-02a block test-delete exempt tamper=false" false null "$WO_BLOCK" --diff-from "$diff" --oracle-files "$OF"
assert_allowed_by_scope "M3-02b block test-delete allowed=true" true "$WO_BLOCK" --diff-from "$diff" --oracle-files "$OF"
# block-style item NOT in the list stays HALT (out-of-class): analysis-baseline not in WO_BLOCK
diff="$(mk_diff "A" "analysis-baseline.txt")"
assert_verdict          "M3-03a block out-of-class analysis tamper=true" true oracle_tamper "$WO_BLOCK" --diff-from "$diff" --oracle-files "$OF"
assert_allowed_by_scope "M3-03b block out-of-class allowed=false" false "$WO_BLOCK" --diff-from "$diff" --oracle-files "$OF"
# block-style WITH quoted items (combined M2+M3); WO_BLOCK_QUOTED has [baseline, analysis-baseline]
diff="$(mk_diff "A" "snapshots/page/s.snap")"
assert_verdict          "M3-04a block-quoted baseline exempt tamper=false" false null "$WO_BLOCK_QUOTED" --diff-from "$diff" --oracle-files "$OF"
assert_allowed_by_scope "M3-04b block-quoted baseline allowed=true" true "$WO_BLOCK_QUOTED" --diff-from "$diff" --oracle-files "$OF"

# ============================================================
# L1 — UNTERMINATED frontmatter (no closing ---) => exemption NOT honored.
# ============================================================
diff="$(mk_diff "A" "snapshots/page/s.snap")"
assert_verdict          "L1-01a unterminated fm exemption NOT honored tamper=true" true oracle_tamper "$WO_UNTERM" --diff-from "$diff" --oracle-files "$OF"
assert_allowed_by_scope "L1-01b unterminated fm allowed=false" false "$WO_UNTERM" --diff-from "$diff" --oracle-files "$OF"

# L1b — oracle_update only in the BODY (terminated empty frontmatter) => NOT honored.
diff="$(mk_diff "A" "snapshots/page/s.snap")"
assert_verdict          "L1-02a body oracle_update NOT honored tamper=true" true oracle_tamper "$WO_BODY" --diff-from "$diff" --oracle-files "$OF"
assert_allowed_by_scope "L1-02b body oracle_update allowed=false" false "$WO_BODY" --diff-from "$diff" --oracle-files "$OF"

# ============================================================
# L2 — NESTED baseline (snapshots/.../dark/x.snap) must still match (** glob), halt.
# Also confirm the flat case still matches (regression guard for the ** widening).
# ============================================================
diff="$(mk_diff "A" "snapshots/home/dark/screen.snap")"
assert_verdict "L2-01a nested snapshot tamper=true" true oracle_tamper "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_signal  "L2-01b nested snapshot signal" snapshot_write halt baseline "$WO" --diff-from "$diff" --oracle-files "$OF"
diff="$(mk_diff "M" "snapshots/home/mobile/x.meta.json")"
assert_verdict "L2-02a nested meta tamper=true" true oracle_tamper "$WO" --diff-from "$diff" --oracle-files "$OF"
assert_signal  "L2-02b nested meta signal" snapshot_write halt baseline "$WO" --diff-from "$diff" --oracle-files "$OF"
# flat case STILL matches after ** widening (regression)
diff="$(mk_diff "A" "snapshots/home/flat.snap")"
assert_verdict "L2-03 flat snapshot still matches tamper=true" true oracle_tamper "$WO" --diff-from "$diff" --oracle-files "$OF"
# deeply nested
diff="$(mk_diff "A" "snapshots/home/a/b/c/deep.snap")"
assert_verdict "L2-04 deeply nested snapshot tamper=true" true oracle_tamper "$WO" --diff-from "$diff" --oracle-files "$OF"

# ============================================================
# IN-01: malformed --oracle-files (not a JSON array) => exit 2 (never fail-open on garbage)
# ============================================================
echo '{"not":"an array"}' > "$TMP/bad-oracle.json"
bash "$KERNEL" "$WO" --diff-from "$diff_clean" --oracle-files "$TMP/bad-oracle.json" >/dev/null 2>&1
if [ "$?" -eq 2 ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  printf 'FAIL IN-01: non-array --oracle-files did not exit 2\n'
fi

# IN-02: --oracle-files given but file missing => exit 2
bash "$KERNEL" "$WO" --diff-from "$diff_clean" --oracle-files "$TMP/does-not-exist.json" >/dev/null 2>&1
if [ "$?" -eq 2 ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  printf 'FAIL IN-02: missing --oracle-files file did not exit 2\n'
fi

echo "----"
echo "wo-oracle-check-spec: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
