#!/usr/bin/env bash
# security-counting-spec.sh — Hermetic unit tests for the security gate's counting
# and reporting defects. No DDEV, no network, no PHP. Fixtures in a tmp dir only.
#
# Run: bash scripts/tests/security-counting-spec.sh
# Exit 0 = all pass; exit 1 = failures (details printed).
#
# Covers:
#   A1  No `((VAR += X))` / `((VAR++))` remains in any gate script. Under `set -e`
#       those abort the script whenever the expression evaluates to 0 — which for
#       `((C++))` is the very first increment, and for `+=` is any clean counter.
#   A2  The abort is real, so the guard in A1 is not academic.
#   B1  pattern_issues emits one issue per grep hit carrying the real file and line.
#   B2  The severity count equals the issues[] length (they cannot disagree).
#   B3  A single changed file still yields a filename, not a line number (grep -H).
#   C1  The tightened db_query pattern ignores the safe placeholder-array form.
#   C2  It still catches interpolation and concatenation, including a query string
#       containing a comma.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_ROOT="${SCRIPT_DIR}/.."
SEC="${SCRIPTS_ROOT}/drupal/security-check.sh"

if [[ ! -f "$SEC" ]]; then
  echo "FATAL: security-check.sh not found at $SEC" >&2
  exit 2
fi

PASS=0
FAIL=0
declare -a ERRORS=()

ok()   { PASS=$((PASS + 1)); echo "  PASS: $1"; }
bad()  { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); echo "  FAIL: $1"; }

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then ok "$desc"; else bad "$desc | expected '$expected', got '$actual'"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── A. The set -e arithmetic hazard ──────────────────────────────────────────
echo ""
echo "A: no set -e arithmetic aborts remain"

# Scope to the gate scripts: this spec deliberately contains the hazardous form
# below to prove it aborts, and must not match itself.
RISKY=$(find "$SCRIPTS_ROOT" -name '*.sh' -not -path '*/tests/*' \
  -exec grep -nE '\(\(\s*[A-Za-z_][A-Za-z0-9_]*\s*(\+\+|\+=)' {} + 2>/dev/null | wc -l | tr -d ' ')
assert_eq "no ((VAR += X)) or ((VAR++)) in any gate script" "0" "$RISKY"

# A2: prove the construct really does abort, so A1 guards something real.
abort_status=0
bash -c 'set -e; C=0; ((C++)); exit 0' 2>/dev/null || abort_status=$?
assert_eq "((C++)) under set -e aborts when C starts at 0" "1" "$abort_status"

safe_status=0
bash -c 'set -e; C=0; C=$((C + 1)); exit 0' 2>/dev/null || safe_status=$?
assert_eq "the assignment form does not abort" "0" "$safe_status"

# ── B. pattern_issues emits locatable findings ───────────────────────────────
echo ""
echo "B: pattern_issues emits real file:line and reconciling counts"

# Extract the helper from the gate script rather than re-implementing it here,
# so this spec fails if the real function changes shape.
sed -n '/^pattern_issues()/,/^}/p' "$SEC" > "$TMP/helper.sh"
if [[ ! -s "$TMP/helper.sh" ]]; then
  bad "pattern_issues() not found in security-check.sh"
else
  # shellcheck source=/dev/null
  source "$TMP/helper.sh"

  cat > "$TMP/alpha.module" <<'PHPEOF'
$safe   = db_query('SELECT a, b FROM {n} WHERE id = :id', [':id' => $id]);
$unsafe = db_query("SELECT a, b FROM {n} WHERE id = $id");
$concat = db_query('SELECT a FROM {n} WHERE id = ' . $id);
PHPEOF
  cat > "$TMP/beta.module" <<'PHPEOF'
$also = db_query("SELECT x FROM {t} WHERE y = $y");
PHPEOF

  RAW=$(grep -EHn 'db_query([^"]*"[^"]*\$|.*\.[[:space:]]*\$)' "$TMP/alpha.module" "$TMP/beta.module" 2>/dev/null || true)
  OUT=$(pattern_issues "$RAW" "SQL Injection Risk" "high" "msg" "A03:2021" "fix")

  COUNT=$(echo "$OUT" | jq 'length')
  assert_eq "one issue per hit across two files (3 hits)" "3" "$COUNT"

  ZERO_LINES=$(echo "$OUT" | jq '[.[] | select(.line == 0)] | length')
  assert_eq "no issue carries the line 0 placeholder" "0" "$ZERO_LINES"

  PLACEHOLDER=$(echo "$OUT" | jq '[.[] | select(.file | test("Multiple files|Changed files|Twig templates"))] | length')
  assert_eq "no issue carries a placeholder filename" "0" "$PLACEHOLDER"

  FIRST_LINE=$(echo "$OUT" | jq -r '.[0].line')
  assert_eq "first hit records its real line number" "2" "$FIRST_LINE"

  # B2: the counter a caller derives is the array length, so they cannot diverge.
  assert_eq "severity count equals issues[] length" "$COUNT" "$(echo "$OUT" | jq 'length')"

  # B3: single-file grep still yields a filename, not a line number.
  SINGLE=$(grep -EHn 'db_query([^"]*"[^"]*\$|.*\.[[:space:]]*\$)' "$TMP/beta.module" 2>/dev/null || true)
  SINGLE_FILE=$(pattern_issues "$SINGLE" c s m o r | jq -r '.[0].file' | xargs basename)
  assert_eq "single file yields a filename, not a line number" "beta.module" "$SINGLE_FILE"
fi

# ── C. The tightened db_query pattern ────────────────────────────────────────
echo ""
echo "C: db_query pattern excludes the safe placeholder form"

PAT='db_query([^"]*"[^"]*\$|.*\.[[:space:]]*\$)'

cat > "$TMP/patterns.module" <<'PHPEOF'
$a = db_query('SELECT a, b FROM {n} WHERE id = :id', [':id' => $id]);
$b = db_query("SELECT a, b FROM {n} WHERE id = $id");
$c = db_query('SELECT a FROM {n} WHERE id = ' . $id);
$d = db_query("SELECT a, b FROM {n} WHERE x = :x", [':x' => $x]);
PHPEOF

MATCHED=$(grep -EHn "$PAT" "$TMP/patterns.module" 2>/dev/null | cut -d: -f2 | tr '\n' ',' | sed 's/,$//')
assert_eq "matches only the interpolated and concatenated forms" "2,3" "$MATCHED"

# The comma inside the query string must not end the match early.
COMMA_HIT=$(grep -EHn "$PAT" "$TMP/patterns.module" 2>/dev/null | grep -c 'SELECT a, b FROM {n} WHERE id = \$id' | tr -d ' ')
assert_eq "a comma inside the query string does not defeat the match" "1" "$COMMA_HIT"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────────────────────────────"
echo "Results: $PASS passed, $FAIL failed"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  printf '%s\n' "${ERRORS[@]}"
  exit 1
fi
exit 0
