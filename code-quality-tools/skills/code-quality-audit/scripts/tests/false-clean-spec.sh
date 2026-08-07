#!/usr/bin/env bash
# false-clean-spec.sh — Hermetic tests for checks that report clean without running,
# and for secret-report safety. No DDEV, no network, no PHP. Temp dirs only.
#
# Run: bash scripts/tests/false-clean-spec.sh
# Exit 0 = all pass; exit 1 = failures (details printed).
#
# Covers the four defects taken from gaps-code-quality-tools-2026-08-06.md:
#   A  (item 1) phpstan findings counted from .totals.file_errors, not .totals.errors.
#               .totals.errors counts global/config errors; a run finding 211 real
#               defects has errors=0 and file_errors=211, so the old field reports clean.
#   B  (item 8) every gitleaks invocation redacts, so no matched secret value is written
#               to a report at all.
#   C  (item 8) the report directory is gitignored at creation, idempotently, and only
#               when the target is actually a git working tree.
#   D  (item 9) gitleaks exit status is USED: 1 (found leaks) is distinguished from
#               >=2 (failed to run), and a failure is recorded as a skipped tool rather
#               than a silent zero.
#   E  (item 3) the overall verdict is never "pass" when no gate produced a result.
#
# Where an assertion can be proved by executing the real code, it is: the phpstan
# expression is extracted from the script and evaluated, and setup_report_dir /
# resolve_overall_status are sourced and called.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${SCRIPT_DIR}/.."
SOLID="${ROOT}/drupal/solid-check.sh"
SEC="${ROOT}/drupal/security-check.sh"
ENVSH="${ROOT}/core/detect-environment.sh"
FULL="${ROOT}/core/full-audit.sh"

for f in "$SOLID" "$SEC" "$ENVSH" "$FULL"; do
  [[ -f "$f" ]] || { echo "FATAL: missing $f" >&2; exit 2; }
done

PASS=0; FAIL=0
declare -a ERRORS=()
ok()  { PASS=$((PASS + 1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL + 1)); ERRORS+=("FAIL: $1"); echo "  FAIL: $1"; }
assert_eq() {
  local desc="$1" want="$2" got="$3"
  if [[ "$want" == "$got" ]]; then ok "$desc"; else bad "$desc | want '$want', got '$got'"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── A. phpstan finding count (item 1) ────────────────────────────────────────
echo ""
echo "A: phpstan findings counted from the field that holds them"

cat > "$TMP/phpstan.json" <<'JSON'
{"totals":{"errors":0,"file_errors":211},"files":{"src/A.php":{"errors":211}}}
JSON

# Prove the two fields genuinely differ on realistic output, so this is not cosmetic.
assert_eq "fixture: .totals.errors is 0 while .totals.file_errors is 211" \
  "0|211" \
  "$(jq -r '.totals.errors' "$TMP/phpstan.json")|$(jq -r '.totals.file_errors' "$TMP/phpstan.json")"

# Execute the REAL expression from the script rather than a copy of it.
COUNT_LINES=$(grep -n 'PHPSTAN_ERRORS=\$(jq' "$SOLID" || true)
if [[ -z "$COUNT_LINES" ]]; then
  bad "found the PHPSTAN_ERRORS assignment in solid-check.sh"
else
  n=0
  while IFS= read -r line; do
    n=$((n + 1))
    expr_line="${line#*:}"
    # Point the real assignment at the fixture and run it.
    runnable="PHPSTAN_JSON='$TMP/phpstan.json'; ${expr_line}; echo \"\$PHPSTAN_ERRORS\""
    got=$(bash -c "$runnable" 2>/dev/null | tail -1)
    assert_eq "solid-check.sh assignment #$n reports 211 findings, not 0" "211" "$got"
  done <<< "$COUNT_LINES"
fi

# The old field may still appear, but never as the finding count.
STALE=$(grep -c "PHPSTAN_ERRORS=\$(jq '\.totals\.errors" "$SOLID" || true)
assert_eq "no PHPSTAN_ERRORS assignment still reads .totals.errors" "0" "$STALE"

# ── B. gitleaks redaction (item 8) ───────────────────────────────────────────
echo ""
echo "B: gitleaks never writes unredacted secret values"

INVOCATIONS=$(grep -nE '^[[:space:]]*gitleaks (detect|git|dir)' "$SEC" || true)
if [[ -z "$INVOCATIONS" ]]; then
  bad "found at least one gitleaks invocation in security-check.sh"
else
  missing=0
  while IFS= read -r line; do
    echo "$line" | grep -q -- '--redact' || missing=$((missing + 1))
  done <<< "$INVOCATIONS"
  assert_eq "every gitleaks invocation carries --redact" "0" "$missing"
fi

# ── C. report directory is not committable (item 8) ──────────────────────────
echo ""
echo "C: the report directory cannot be committed by accident"

# Source only the function under test, not the whole script (it runs a main()).
sed -n '/^setup_report_dir()/,/^}/p' "$ENVSH" > "$TMP/setup_report_dir.sh"
if [[ ! -s "$TMP/setup_report_dir.sh" ]]; then
  bad "extracted setup_report_dir() from detect-environment.sh"
else
  # C1 + C2: inside a git repo, the directory ends up ignored, idempotently.
  REPO="$TMP/repo"; mkdir -p "$REPO"; git -C "$REPO" init -q 2>/dev/null
  (
    cd "$REPO" || exit 1
    # shellcheck source=/dev/null
    GREEN=''; NC=''; YELLOW=''; RED=''
    source "$TMP/setup_report_dir.sh"
    setup_report_dir >/dev/null 2>&1
    setup_report_dir >/dev/null 2>&1   # second run must not duplicate
  )
  if git -C "$REPO" check-ignore -q .reports 2>/dev/null; then
    ok "report directory is gitignored after creation"
  else
    bad "report directory is gitignored after creation"
  fi
  ENTRIES=$(grep -c '^\.reports/\?$' "$REPO/.gitignore" 2>/dev/null || echo 0)
  assert_eq "gitignore entry written exactly once across two runs" "1" "$ENTRIES"

  # C3: outside a git repo, touch nothing.
  PLAIN="$TMP/plain"; mkdir -p "$PLAIN"
  (
    cd "$PLAIN" || exit 1
    GREEN=''; NC=''; YELLOW=''; RED=''
    # shellcheck source=/dev/null
    source "$TMP/setup_report_dir.sh"
    setup_report_dir >/dev/null 2>&1
  )
  if [[ -f "$PLAIN/.gitignore" ]]; then
    bad "no .gitignore created outside a git working tree"
  else
    ok "no .gitignore created outside a git working tree"
  fi
fi

# ── D. gitleaks failure is not a silent zero (item 9) ────────────────────────
echo ""
echo "D: a gitleaks that fails to run is reported, not counted as clean"

# Range ends at the top-level `else` on purpose: that else is the tool-ABSENT branch,
# which already records a skip. Including it would make the assertion below pass for
# the wrong reason. We are testing the ran-but-failed path only.
BLOCK=$(sed -n '/GITLEAKS_EXIT=\$?/,/^else/p' "$SEC")
USES=$(echo "$BLOCK" | grep -c 'GITLEAKS_EXIT' || true)
if [[ "$USES" -ge 2 ]]; then
  ok "GITLEAKS_EXIT is read after being assigned"
else
  bad "GITLEAKS_EXIT is read after being assigned (assigned only, never used)"
fi

if echo "$BLOCK" | grep -q 'SKIPPED_TOOLS+=("gitleaks")'; then
  ok "a failed gitleaks is recorded in SKIPPED_TOOLS"
else
  bad "a failed gitleaks is recorded in SKIPPED_TOOLS"
fi

# ── E. verdict is never pass when nothing ran (item 3) ───────────────────────
echo ""
echo "E: overall verdict is not 'pass' when no gate produced a result"

sed -n '/^resolve_overall_status()/,/^}/p' "$FULL" > "$TMP/resolve.sh"
if [[ ! -s "$TMP/resolve.sh" ]]; then
  bad "extracted resolve_overall_status() from full-audit.sh"
else
  # shellcheck source=/dev/null
  source "$TMP/resolve.sh"
  assert_eq "all five gates unknown -> not pass" "unknown" \
    "$(resolve_overall_status pass unknown unknown unknown unknown unknown)"
  assert_eq "one gate passed -> pass" "pass" \
    "$(resolve_overall_status pass pass unknown unknown unknown unknown)"
  assert_eq "a failing gate still yields fail" "fail" \
    "$(resolve_overall_status fail pass unknown unknown unknown unknown)"
  assert_eq "skipped counts as not-run" "unknown" \
    "$(resolve_overall_status pass skipped skipped skipped skipped skipped)"
fi

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
