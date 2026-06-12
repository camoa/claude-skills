#!/usr/bin/env bash
# Hermetic spec for scripts/wo-oracle-check.sh
# No real git invoked — feeds name-status fixtures + WO-file fixtures.
# Run: bash tests/wo-oracle-check-spec.sh
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"
ROOT="$(dirname "$HERE")"
KERNEL="$ROOT/scripts/wo-oracle-check.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
DIFF_N=0

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

# WO with oracle_update exempting: baseline, phpstan-baseline
cat > "$TMP/wo-exempt-baseline.md" <<'WOEOF'
---
id: local:test#wo-01
kind: work-order
schema_version: '1.0'
title: Test WO with oracle_update
status: ready
oracle_update:
  classes: [baseline, phpstan-baseline]
  reason: "updating visual baselines after intentional redesign"
  by: "carlos"
---
# Test WO — oracle_update: baseline + phpstan-baseline
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
  reason: "intentional redesign"
  by: "carlos"
---
# Test WO — quoted inline classes
WOEOF

# M2b: single-quoted class names — must still match
cat > "$TMP/wo-exempt-squoted.md" <<'WOEOF'
---
id: local:test#wo-03b
oracle_update:
  classes: ['baseline', 'phpstan-baseline']
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
    - 'phpstan-baseline'
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
# Assert helpers
# ============================================================

# assert_verdict label want_tamper want_halt_reason kernel_args...
# want_tamper: true | false
# want_halt_reason: null | oracle_tamper
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
# Passes if ANY signal in signals[] matches type+change+severity (order-independent).
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

# ============================================================
# TC-01: Clean diff (no watched paths) => tamper=false, signals=[], halt_reason=null
# ============================================================
diff_clean="$(mk_diff "M" "src/some/file.php")"
assert_verdict    "TC-01a clean tamper=false"   false null "$WO" --diff-from "$diff_clean"
assert_no_signals "TC-01b clean no signals"             "$WO" --diff-from "$diff_clean"

# ============================================================
# TC-02: baseline_write — A on .png => halt, tamper=true, change=A
# ============================================================
diff="$(mk_diff "A" "tests/visual/homepage.spec.ts-snapshots/screenshot.png")"
assert_verdict       "TC-02a baseline_write A tamper=true" true oracle_tamper "$WO" --diff-from "$diff"
assert_signal        "TC-02b baseline_write A signal"      baseline_write halt baseline "$WO" --diff-from "$diff"
assert_signal_change "TC-02c baseline_write A change=A"    A "$WO" --diff-from "$diff"

# ============================================================
# TC-03: baseline_write — M on .meta.json => halt, tamper=true, change=M
# ============================================================
diff="$(mk_diff "M" "tests/visual/homepage.spec.ts-snapshots/test.meta.json")"
assert_verdict       "TC-03a baseline_write M tamper=true" true oracle_tamper "$WO" --diff-from "$diff"
assert_signal        "TC-03b baseline_write M signal"      baseline_write halt baseline "$WO" --diff-from "$diff"
assert_signal_change "TC-03c baseline_write M change=M"    M "$WO" --diff-from "$diff"

# ============================================================
# TC-04: baseline_write — D on .png => NO signal (D not in watched changes)
# ============================================================
diff="$(mk_diff "D" "tests/visual/homepage.spec.ts-snapshots/screenshot.png")"
assert_verdict    "TC-04a baseline_write D no tamper" false null "$WO" --diff-from "$diff"
assert_no_signals "TC-04b baseline_write D no signal"       "$WO" --diff-from "$diff"

# ============================================================
# TC-05: vr_spec_delete — D on tests/visual/*.spec.ts => halt, tamper=true, change=D
# ============================================================
diff="$(mk_diff "D" "tests/visual/homepage.spec.ts")"
assert_verdict       "TC-05a vr_spec_delete D tamper=true" true oracle_tamper "$WO" --diff-from "$diff"
assert_signal        "TC-05b vr_spec_delete D signal"      vr_spec_delete halt test-delete "$WO" --diff-from "$diff"
assert_signal_change "TC-05c vr_spec_delete D change=D"    D "$WO" --diff-from "$diff"

# ============================================================
# TC-06: vr_spec_delete — A on tests/visual/*.spec.ts => NO signal (only D watched)
# ============================================================
diff="$(mk_diff "A" "tests/visual/homepage.spec.ts")"
assert_verdict    "TC-06a vr_spec_delete A no tamper" false null "$WO" --diff-from "$diff"
assert_no_signals "TC-06b vr_spec_delete A no signal"       "$WO" --diff-from "$diff"

# ============================================================
# TC-07: test_delete — D on tests/**/*Test.php => halt, tamper=true
# ============================================================
diff="$(mk_diff "D" "tests/Unit/SomeTest.php")"
assert_verdict "TC-07a test_delete php D tamper=true" true oracle_tamper "$WO" --diff-from "$diff"
assert_signal  "TC-07b test_delete php D signal"      test_delete halt test-delete "$WO" --diff-from "$diff"

# TC-07b: nested path (tests/src/Unit/SomeTest.php) — tests ** across multiple segments
diff="$(mk_diff "D" "tests/src/Unit/SomeTest.php")"
assert_verdict "TC-07c test_delete nested php D" true oracle_tamper "$WO" --diff-from "$diff"
assert_signal  "TC-07d test_delete nested php D signal" test_delete halt test-delete "$WO" --diff-from "$diff"

# ============================================================
# TC-08: test_delete — D on tests/e2e/**/*.spec.ts => halt
# ============================================================
diff="$(mk_diff "D" "tests/e2e/navigation.spec.ts")"
assert_verdict "TC-08a test_delete e2e D tamper=true"  true oracle_tamper "$WO" --diff-from "$diff"
assert_signal  "TC-08b test_delete e2e D signal"       test_delete halt test-delete "$WO" --diff-from "$diff"

# TC-08b: nested e2e path
diff="$(mk_diff "D" "tests/e2e/auth/login.spec.ts")"
assert_verdict "TC-08c test_delete e2e nested D" true oracle_tamper "$WO" --diff-from "$diff"
assert_signal  "TC-08d test_delete e2e nested D signal" test_delete halt test-delete "$WO" --diff-from "$diff"

# ============================================================
# TC-09: test_delete — D on tests/atk/**/*.spec.ts => halt
# ============================================================
diff="$(mk_diff "D" "tests/atk/user-login.spec.ts")"
assert_verdict "TC-09a test_delete atk D tamper=true" true oracle_tamper "$WO" --diff-from "$diff"
assert_signal  "TC-09b test_delete atk D signal"      test_delete halt test-delete "$WO" --diff-from "$diff"

# ============================================================
# TC-10: test_delete — A on *Test.php => NO signal (only D watched)
# ============================================================
diff="$(mk_diff "A" "tests/Unit/SomeTest.php")"
assert_verdict    "TC-10a test_delete A no tamper" false null "$WO" --diff-from "$diff"
assert_no_signals "TC-10b test_delete A no signal"       "$WO" --diff-from "$diff"

# ============================================================
# TC-11: phpstan_baseline — A => halt, tamper=true
# ============================================================
diff="$(mk_diff "A" "phpstan-baseline.neon")"
assert_verdict "TC-11a phpstan_baseline A tamper=true" true oracle_tamper "$WO" --diff-from "$diff"
assert_signal  "TC-11b phpstan_baseline A signal"      phpstan_baseline halt phpstan-baseline "$WO" --diff-from "$diff"

# ============================================================
# TC-12: phpstan_baseline — M => halt, tamper=true
# ============================================================
diff="$(mk_diff "M" "phpstan-baseline.neon")"
assert_verdict "TC-12a phpstan_baseline M tamper=true" true oracle_tamper "$WO" --diff-from "$diff"
assert_signal  "TC-12b phpstan_baseline M signal"      phpstan_baseline halt phpstan-baseline "$WO" --diff-from "$diff"

# ============================================================
# TC-13: phpstan_baseline — D => NO signal (only A,M watched)
# ============================================================
diff="$(mk_diff "D" "phpstan-baseline.neon")"
assert_verdict    "TC-13a phpstan_baseline D no tamper" false null "$WO" --diff-from "$diff"
assert_no_signals "TC-13b phpstan_baseline D no signal"       "$WO" --diff-from "$diff"

# ============================================================
# TC-14: phpstan_config — M phpstan.neon => flag signal, tamper=false
# ============================================================
diff="$(mk_diff "M" "phpstan.neon")"
assert_verdict "TC-14a phpstan_config neon M tamper=false" false null "$WO" --diff-from "$diff"
assert_signal  "TC-14b phpstan_config neon M signal"       phpstan_config flag phpstan-baseline "$WO" --diff-from "$diff"

# ============================================================
# TC-15: phpstan_config — M phpstan.neon.dist => flag
# ============================================================
diff="$(mk_diff "M" "phpstan.neon.dist")"
assert_verdict "TC-15a phpstan_config neon.dist M tamper=false" false null "$WO" --diff-from "$diff"
assert_signal  "TC-15b phpstan_config neon.dist M signal"       phpstan_config flag phpstan-baseline "$WO" --diff-from "$diff"

# ============================================================
# TC-16: phpstan_config — A phpstan.neon => NO signal (only M watched)
# ============================================================
diff="$(mk_diff "A" "phpstan.neon")"
assert_verdict    "TC-16a phpstan_config A no tamper" false null "$WO" --diff-from "$diff"
assert_no_signals "TC-16b phpstan_config A no signal"       "$WO" --diff-from "$diff"

# ============================================================
# TC-17: registry_shrink — M => flag signal, tamper=false
# ============================================================
diff="$(mk_diff "M" ".visual-review/registry.yml")"
assert_verdict "TC-17a registry_shrink M tamper=false" false null "$WO" --diff-from "$diff"
assert_signal  "TC-17b registry_shrink M signal"       registry_shrink flag baseline "$WO" --diff-from "$diff"

# ============================================================
# TC-18: registry_shrink — A => NO signal (only M watched)
# ============================================================
diff="$(mk_diff "A" ".visual-review/registry.yml")"
assert_verdict    "TC-18a registry_shrink A no tamper" false null "$WO" --diff-from "$diff"
assert_no_signals "TC-18b registry_shrink A no signal"       "$WO" --diff-from "$diff"

# ============================================================
# TC-19: coverage_threshold — M jest.config.js => flag
# ============================================================
diff="$(mk_diff "M" "jest.config.js")"
assert_verdict "TC-19a coverage_threshold jest.config.js M tamper=false" false null "$WO" --diff-from "$diff"
assert_signal  "TC-19b coverage_threshold jest.config.js M signal"       coverage_threshold flag coverage-threshold "$WO" --diff-from "$diff"

# TC-19b: jest.config.ts
diff="$(mk_diff "M" "jest.config.ts")"
assert_verdict "TC-19c coverage_threshold jest.config.ts M tamper=false" false null "$WO" --diff-from "$diff"
assert_signal  "TC-19d coverage_threshold jest.config.ts M signal"       coverage_threshold flag coverage-threshold "$WO" --diff-from "$diff"

# ============================================================
# TC-20: coverage_threshold — M phpunit.xml => flag
# ============================================================
diff="$(mk_diff "M" "phpunit.xml")"
assert_verdict "TC-20a coverage_threshold phpunit.xml M tamper=false" false null "$WO" --diff-from "$diff"
assert_signal  "TC-20b coverage_threshold phpunit.xml M signal"       coverage_threshold flag coverage-threshold "$WO" --diff-from "$diff"

# ============================================================
# TC-21: coverage_threshold — M phpunit.xml.dist => flag
# ============================================================
diff="$(mk_diff "M" "phpunit.xml.dist")"
assert_verdict "TC-21a coverage_threshold phpunit.xml.dist M tamper=false" false null "$WO" --diff-from "$diff"
assert_signal  "TC-21b coverage_threshold phpunit.xml.dist M signal"       coverage_threshold flag coverage-threshold "$WO" --diff-from "$diff"

# ============================================================
# TC-22: coverage_threshold — A phpunit.xml => NO signal (only M watched)
# ============================================================
diff="$(mk_diff "A" "phpunit.xml")"
assert_verdict    "TC-22a coverage_threshold A no tamper" false null "$WO" --diff-from "$diff"
assert_no_signals "TC-22b coverage_threshold A no signal"       "$WO" --diff-from "$diff"

# ============================================================
# TC-23: oracle_update exemption — in-class halt (baseline) => flag, allowed=true, tamper=false
# WO has oracle_update.classes: [baseline, phpstan-baseline]
# ============================================================
diff="$(mk_diff "A" "tests/visual/page.spec.ts-snapshots/screen.png")"
assert_verdict         "TC-23a exempt baseline in-class tamper=false" false null "$WO_EX" --diff-from "$diff"
assert_signal          "TC-23b exempt baseline in-class severity=flag" baseline_write flag baseline "$WO_EX" --diff-from "$diff"
assert_allowed_by_scope "TC-23c exempt baseline in-class allowed=true" true "$WO_EX" --diff-from "$diff"

# ============================================================
# TC-24: oracle_update exemption — out-of-class halt (test-delete) stays halt, tamper=true
# WO has oracle_update.classes: [baseline, phpstan-baseline] — test-delete is NOT in scope
# ============================================================
diff="$(mk_diff "D" "tests/visual/homepage.spec.ts")"
assert_verdict         "TC-24a exempt out-of-class tamper=true"    true oracle_tamper "$WO_EX" --diff-from "$diff"
assert_allowed_by_scope "TC-24b exempt out-of-class allowed=false" false "$WO_EX" --diff-from "$diff"
assert_signal          "TC-24c exempt out-of-class severity=halt"  vr_spec_delete halt test-delete "$WO_EX" --diff-from "$diff"

# ============================================================
# TC-25: absent oracle_update — nothing exempt (phpstan_baseline stays halt)
# ============================================================
diff="$(mk_diff "A" "phpstan-baseline.neon")"
assert_verdict         "TC-25a absent oracle_update tamper=true"    true oracle_tamper "$WO" --diff-from "$diff"
assert_allowed_by_scope "TC-25b absent oracle_update allowed=false" false "$WO" --diff-from "$diff"

# ============================================================
# TC-26: oracle_update exemption — test-delete in-class => flag, allowed=true, tamper=false
# WO has oracle_update.classes: [test-delete]
# ============================================================
diff="$(mk_diff "D" "tests/Unit/SomeTest.php")"
assert_verdict         "TC-26a exempt test-delete in-class tamper=false" false null "$WO_EX_TD" --diff-from "$diff"
assert_signal          "TC-26b exempt test-delete in-class severity=flag" test_delete flag test-delete "$WO_EX_TD" --diff-from "$diff"
assert_allowed_by_scope "TC-26c exempt test-delete allowed=true" true "$WO_EX_TD" --diff-from "$diff"

# ============================================================
# TC-27: Rename line (R100) — OLD path D against D-rows; here OLD is phpstan-baseline.neon
# which is NOT a D-row (only A,M watched) => no D signal; NEW path A is the baseline => halt.
# ============================================================
diff="$(mk_rename "old/phpstan-baseline.neon" "phpstan-baseline.neon")"
assert_verdict "TC-27a rename new=phpstan_baseline tamper=true" true oracle_tamper "$WO" --diff-from "$diff"
assert_has_signal "TC-27b rename new phpstan_baseline A" phpstan_baseline A halt "$WO" --diff-from "$diff"

# TC-27c: rename of a non-watched file => no signal (neither old-D nor new-A matches)
diff="$(mk_rename "old/src/Foo.php" "src/Bar.php")"
assert_verdict    "TC-27c rename non-watched no tamper" false null "$WO" --diff-from "$diff"
assert_no_signals "TC-27d rename non-watched no signal"       "$WO" --diff-from "$diff"

# ============================================================
# TC-28: Multiple signals in one diff (a halt + a flag) => tamper=true
# ============================================================
diff="$(mk_multi \
  "A	tests/visual/p.spec.ts-snapshots/s.png" \
  "M	phpunit.xml")"
assert_verdict "TC-28a multi halt+flag tamper=true" true oracle_tamper "$WO" --diff-from "$diff"

# ============================================================
# TC-29: flag-only signals do NOT set tamper_detected
# (phpstan_config M is flag; even with no oracle_update, tamper stays false)
# ============================================================
diff="$(mk_diff "M" "phpstan.neon")"
assert_verdict "TC-29 flag-only tamper=false" false null "$WO" --diff-from "$diff"

# ============================================================
# TC-30: schema_version is "1.0" in the JSON output
# ============================================================
diff="$(mk_diff "M" "src/SomeClass.php")"
out30="$(bash "$KERNEL" "$WO" --diff-from "$diff" 2>/dev/null)"
sv30="$(printf '%s' "$out30" | jq -r '.schema_version')"
if [ "$sv30" = "1.0" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  printf 'FAIL TC-30 schema_version: got "%s" (want "1.0")\n' "$sv30"
fi

# ============================================================
# TC-31: phpstan_baseline in-class exemption (oracle_update has phpstan-baseline)
# ============================================================
diff="$(mk_diff "M" "phpstan-baseline.neon")"
assert_verdict         "TC-31a phpstan_baseline exempt tamper=false" false null "$WO_EX" --diff-from "$diff"
assert_signal          "TC-31b phpstan_baseline exempt severity=flag" phpstan_baseline flag phpstan-baseline "$WO_EX" --diff-from "$diff"
assert_allowed_by_scope "TC-31c phpstan_baseline exempt allowed=true" true "$WO_EX" --diff-from "$diff"

# ============================================================
# ===== RED-TEAM CORRECTION COVERAGE (C1 / M1 / M2 / M3 / L1 / L2) =====
# ============================================================

# ============================================================
# C1 — RENAME-EVASION (the ship-blocker): git mv a *Test.php OUT of tests/ must
# be caught as a test_delete on the OLD path (change:"D", halt), tamper=true.
# `git mv tests/Unit/CriticalTest.php disabled/CriticalTest.php`
# ============================================================
diff="$(mk_rename "tests/Unit/CriticalTest.php" "disabled/CriticalTest.php")"
assert_verdict    "C1-01a rename test out-of-tests tamper=true" true oracle_tamper "$WO" --diff-from "$diff"
assert_has_signal "C1-01b rename old=test_delete D halt" test_delete D halt "$WO" --diff-from "$diff"
assert_signal     "C1-01c rename signals[0]=test_delete (old path first)" test_delete halt test-delete "$WO" --diff-from "$diff"
assert_signal_change "C1-01d rename signals[0].change=D" D "$WO" --diff-from "$diff"

# C1 — vr_spec_delete via rename out of tests/visual/
diff="$(mk_rename "tests/visual/home.spec.ts" "archive/home.spec.ts")"
assert_verdict    "C1-02a rename vr spec out tamper=true" true oracle_tamper "$WO" --diff-from "$diff"
assert_has_signal "C1-02b rename old=vr_spec_delete D halt" vr_spec_delete D halt "$WO" --diff-from "$diff"

# C1 — e2e spec deletion via rename out of tests/e2e/
diff="$(mk_rename "tests/e2e/login.spec.ts" "disabled/login.spec.ts")"
assert_verdict    "C1-03a rename e2e spec out tamper=true" true oracle_tamper "$WO" --diff-from "$diff"
assert_has_signal "C1-03b rename old=test_delete (e2e) D halt" test_delete D halt "$WO" --diff-from "$diff"

# C1 — atk spec deletion via rename out of tests/atk/
diff="$(mk_rename "tests/atk/checkout.spec.ts" "old/checkout.spec.ts")"
assert_verdict    "C1-04a rename atk spec out tamper=true" true oracle_tamper "$WO" --diff-from "$diff"
assert_has_signal "C1-04b rename old=test_delete (atk) D halt" test_delete D halt "$WO" --diff-from "$diff"

# C1 — rename that INTRODUCES a baseline png on the NEW path => baseline_write A halt
diff="$(mk_rename "stash/screen.png" "tests/visual/home.spec.ts-snapshots/screen.png")"
assert_verdict    "C1-05a rename introduces baseline tamper=true" true oracle_tamper "$WO" --diff-from "$diff"
assert_has_signal "C1-05b rename new=baseline_write A halt" baseline_write A halt "$WO" --diff-from "$diff"

# C1 — rename of a test BOTH out of tests/ AND landing as nothing watched on new:
# old=test_delete (D), new=disabled/... no A-row => exactly ONE signal.
diff="$(mk_rename "tests/Unit/CriticalTest.php" "disabled/CriticalTest.php")"
assert_signal_count "C1-06 rename test-out single signal" 1 "$WO" --diff-from "$diff"

# C1 — bare R (no score) handled the same: old->D, new->A
diff="$(mk_line "R	tests/Unit/CriticalTest.php	disabled/CriticalTest.php")"
assert_verdict    "C1-07a bare R rename tamper=true" true oracle_tamper "$WO" --diff-from "$diff"
assert_has_signal "C1-07b bare R old=test_delete D halt" test_delete D halt "$WO" --diff-from "$diff"

# ============================================================
# M1 — COPY (C###): the NEW path is classified as A; the OLD path is untouched (no D).
# A copy that INTRODUCES a baseline png => baseline_write A halt, tamper=true.
# ============================================================
diff="$(mk_copy "templates/screen.png" "tests/visual/home.spec.ts-snapshots/screen.png")"
assert_verdict    "M1-01a copy introduces baseline tamper=true" true oracle_tamper "$WO" --diff-from "$diff"
assert_has_signal "M1-01b copy new=baseline_write A halt" baseline_write A halt "$WO" --diff-from "$diff"
assert_signal_count "M1-01c copy single signal (old untouched)" 1 "$WO" --diff-from "$diff"

# M1 — copy of a test FILE: old path is NOT a delete (copy keeps original) => no test_delete.
# new=disabled/... is not under a watched A-row => NO signal at all, tamper=false.
diff="$(mk_copy "tests/Unit/CriticalTest.php" "disabled/CriticalTest.php")"
assert_verdict    "M1-02a copy test no delete tamper=false" false null "$WO" --diff-from "$diff"
assert_no_signals "M1-02b copy test no signal"                    "$WO" --diff-from "$diff"

# M1 — bare C (no score) handled the same: new->A only
diff="$(mk_line "C	templates/screen.png	tests/visual/home.spec.ts-snapshots/screen.png")"
assert_verdict    "M1-03a bare C copy tamper=true" true oracle_tamper "$WO" --diff-from "$diff"
assert_has_signal "M1-03b bare C new=baseline_write A halt" baseline_write A halt "$WO" --diff-from "$diff"

# ============================================================
# M2 — QUOTED class names in oracle_update must still match (no false-HALT).
# WO_QUOTED has classes: ["baseline","test-delete"]
# ============================================================
diff="$(mk_diff "A" "tests/visual/page.spec.ts-snapshots/s.png")"
assert_verdict          "M2-01a quoted baseline exempt tamper=false" false null "$WO_QUOTED" --diff-from "$diff"
assert_allowed_by_scope "M2-01b quoted baseline allowed=true" true "$WO_QUOTED" --diff-from "$diff"
# test-delete is also in the quoted list => exempt
diff="$(mk_diff "D" "tests/Unit/SomeTest.php")"
assert_verdict          "M2-02a quoted test-delete exempt tamper=false" false null "$WO_QUOTED" --diff-from "$diff"
assert_allowed_by_scope "M2-02b quoted test-delete allowed=true" true "$WO_QUOTED" --diff-from "$diff"
# single-quoted variant
diff="$(mk_diff "M" "phpstan-baseline.neon")"
assert_verdict          "M2-03a single-quoted phpstan exempt tamper=false" false null "$WO_SQUOTED" --diff-from "$diff"
assert_allowed_by_scope "M2-03b single-quoted phpstan allowed=true" true "$WO_SQUOTED" --diff-from "$diff"

# ============================================================
# M3 — BLOCK-STYLE YAML list in oracle_update must parse (no false-HALT).
# WO_BLOCK has classes:\n  - baseline\n  - test-delete
# ============================================================
diff="$(mk_diff "A" "tests/visual/page.spec.ts-snapshots/s.png")"
assert_verdict          "M3-01a block baseline exempt tamper=false" false null "$WO_BLOCK" --diff-from "$diff"
assert_allowed_by_scope "M3-01b block baseline allowed=true" true "$WO_BLOCK" --diff-from "$diff"
diff="$(mk_diff "D" "tests/Unit/SomeTest.php")"
assert_verdict          "M3-02a block test-delete exempt tamper=false" false null "$WO_BLOCK" --diff-from "$diff"
assert_allowed_by_scope "M3-02b block test-delete allowed=true" true "$WO_BLOCK" --diff-from "$diff"
# block-style item NOT in the list stays HALT (out-of-class): phpstan-baseline not in WO_BLOCK
diff="$(mk_diff "A" "phpstan-baseline.neon")"
assert_verdict          "M3-03a block out-of-class phpstan tamper=true" true oracle_tamper "$WO_BLOCK" --diff-from "$diff"
assert_allowed_by_scope "M3-03b block out-of-class allowed=false" false "$WO_BLOCK" --diff-from "$diff"
# block-style WITH quoted items (combined M2+M3)
diff="$(mk_diff "A" "tests/visual/page.spec.ts-snapshots/s.png")"
assert_verdict          "M3-04a block-quoted baseline exempt tamper=false" false null "$WO_BLOCK_QUOTED" --diff-from "$diff"
assert_allowed_by_scope "M3-04b block-quoted baseline allowed=true" true "$WO_BLOCK_QUOTED" --diff-from "$diff"

# ============================================================
# L1 — UNTERMINATED frontmatter (no closing ---) => exemption NOT honored.
# WO_UNTERM has an oracle_update with [baseline,test-delete] but the frontmatter
# never closes, so it is NOT frontmatter => baseline write stays HALT, tamper=true.
# ============================================================
diff="$(mk_diff "A" "tests/visual/page.spec.ts-snapshots/s.png")"
assert_verdict          "L1-01a unterminated fm exemption NOT honored tamper=true" true oracle_tamper "$WO_UNTERM" --diff-from "$diff"
assert_allowed_by_scope "L1-01b unterminated fm allowed=false" false "$WO_UNTERM" --diff-from "$diff"

# L1b — oracle_update only in the BODY (terminated empty frontmatter) => NOT honored.
diff="$(mk_diff "A" "tests/visual/page.spec.ts-snapshots/s.png")"
assert_verdict          "L1-02a body oracle_update NOT honored tamper=true" true oracle_tamper "$WO_BODY" --diff-from "$diff"
assert_allowed_by_scope "L1-02b body oracle_update allowed=false" false "$WO_BODY" --diff-from "$diff"

# ============================================================
# L2 — NESTED baseline (…-snapshots/dark/x.png) must still match (** glob), halt.
# Also confirm the flat case still matches (regression guard for the ** widening).
# ============================================================
diff="$(mk_diff "A" "tests/visual/home.spec.ts-snapshots/dark/screen.png")"
assert_verdict "L2-01a nested baseline png tamper=true" true oracle_tamper "$WO" --diff-from "$diff"
assert_signal  "L2-01b nested baseline png signal" baseline_write halt baseline "$WO" --diff-from "$diff"
# nested meta.json
diff="$(mk_diff "M" "tests/visual/home.spec.ts-snapshots/mobile/x.meta.json")"
assert_verdict "L2-02a nested baseline meta tamper=true" true oracle_tamper "$WO" --diff-from "$diff"
assert_signal  "L2-02b nested baseline meta signal" baseline_write halt baseline "$WO" --diff-from "$diff"
# flat case STILL matches after ** widening (regression)
diff="$(mk_diff "A" "tests/visual/home.spec.ts-snapshots/flat.png")"
assert_verdict "L2-03 flat baseline still matches tamper=true" true oracle_tamper "$WO" --diff-from "$diff"
# deeply nested
diff="$(mk_diff "A" "tests/visual/home.spec.ts-snapshots/a/b/c/deep.png")"
assert_verdict "L2-04 deeply nested baseline tamper=true" true oracle_tamper "$WO" --diff-from "$diff"

echo "----"
echo "wo-oracle-check-spec: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
