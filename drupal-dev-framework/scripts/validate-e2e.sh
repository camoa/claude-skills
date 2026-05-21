#!/usr/bin/env bash
# validate-e2e.sh — run ATK behavioral E2E tests via Playwright.
#
# Usage: validate-e2e.sh <codePath> [--task <name>] [--smoke-only] [--surfaces-json '<json>']
#
#   <codePath>: absolute path to the Drupal project root
#   --task <name>: task name (informational; used in output JSON)
#   --smoke-only: add --grep "@smoke" to Playwright (fast subset)
#   --surfaces-json '<json>': JSON array of surface ids with gate:e2e (passed by Claude
#                             from registry.yml — this script does NOT parse YAML)
#
# YAML boundary: registry.yml is parsed by the calling command (validate-e2e.md,
# executed by Claude). Claude reads the YAML, filters gate:e2e surfaces, and passes
# the id list as --surfaces-json. This shell script handles only structured args.
#
# Playwright runs HOST-SIDE. Never wrap npx in ddev exec.
# The browser reaches the DDEV site via DDEV_PRIMARY_URL / PLAYWRIGHT_BASE_URL.
#
# Output: single JSON object to stdout (see schema below).
# Exit codes:
#   0 — pass or warning (all tests passed, or preflight warnings only)
#   1 — fail (one or more tests failed)
#   2 — invalid arguments or missing pre-requisites

set -uo pipefail

# ─── argument parsing ────────────────────────────────────────────────────────

CODE_PATH="${1:?codePath required}"
TASK_NAME=""
SMOKE_ONLY=0
SURFACES_JSON="[]"

shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)
      TASK_NAME="${2:?--task requires a value}"
      shift
      ;;
    --smoke-only)
      SMOKE_ONLY=1
      ;;
    --surfaces-json)
      SURFACES_JSON="${2:?--surfaces-json requires a value}"
      shift
      ;;
    *)
      echo "validate-e2e: unknown flag: $1" >&2
      echo "  usage: validate-e2e.sh <codePath> [--task <name>] [--smoke-only] [--surfaces-json '<json>']" >&2
      exit 2
      ;;
  esac
  shift
done

# ─── pre-flight ──────────────────────────────────────────────────────────────

if [[ ! -d "$CODE_PATH" ]]; then
  echo "validate-e2e: codePath does not exist: $CODE_PATH" >&2
  exit 2
fi

if ! command -v npx >/dev/null 2>&1; then
  echo "validate-e2e: npx not found in PATH" >&2
  exit 2
fi

# ─── ATK pre-flight ──────────────────────────────────────────────────────────

PREFLIGHT_WARNINGS=()

if command -v ddev >/dev/null 2>&1 && [[ -f "$CODE_PATH/.ddev/config.yaml" ]]; then
  PF_OUTPUT=$(cd "$CODE_PATH" && ddev drush atk:preflight 2>&1) || {
    echo "validate-e2e: ddev drush atk:preflight failed:" >&2
    echo "$PF_OUTPUT" >&2
    # Emit structured error JSON and exit 1
    PAYLOAD=$(printf '{"schema_version":"1.0","gate_type":"e2e","verdict":"fail","total_tests":0,"passed":0,"failed":0,"skipped":0,"report_path":"","failed_tests":[],"preflight_warnings":["atk_preflight_failed: %s"]}' \
      "$(echo "$PF_OUTPUT" | head -1 | tr '"' "'")")
    echo "$PAYLOAD"
    exit 1
  }
else
  PREFLIGHT_WARNINGS+=("ddev_not_available: skipping atk:preflight")
fi

# ─── build --grep pattern ────────────────────────────────────────────────────

GREP_PATTERN=""

# Build surface id grep: "@<id1>|@<id2>|..."
SURFACE_COUNT=$(echo "$SURFACES_JSON" | jq 'length' 2>/dev/null || echo 0)
if [[ "$SURFACE_COUNT" -gt 0 ]]; then
  SURFACE_GREP=$(echo "$SURFACES_JSON" | jq -r '[.[] | "@" + .] | join("|")' 2>/dev/null || echo "")
  if [[ -n "$SURFACE_GREP" ]]; then
    GREP_PATTERN="$SURFACE_GREP"
  fi
fi

# Smoke-only appends @smoke
if [[ "$SMOKE_ONLY" -eq 1 ]]; then
  if [[ -n "$GREP_PATTERN" ]]; then
    GREP_PATTERN="${GREP_PATTERN}|@smoke"
  else
    GREP_PATTERN="@smoke"
  fi
fi

# ─── Playwright invocation ────────────────────────────────────────────────────

REPORT_DIR="tests/e2e/.playwright-results"
REPORT_PATH="${REPORT_DIR}/index.html"

PW_ARGS=(
  "--project" "e2e-chromium"
  "--reporter" "html"
  "--output" "$REPORT_DIR"
)

if [[ -n "$GREP_PATTERN" ]]; then
  PW_ARGS+=("--grep" "$GREP_PATTERN")
fi

PW_EXIT=0
PW_OUTPUT=""
PW_OUTPUT=$(cd "$CODE_PATH" && npx playwright test "${PW_ARGS[@]}" 2>&1) || PW_EXIT=$?

# ─── parse Playwright output for counts ──────────────────────────────────────

# Playwright summary line format (example): "39 passed, 3 failed, 0 skipped"
TOTAL=0; PASSED=0; FAILED=0; SKIPPED=0

SUMMARY_LINE=$(echo "$PW_OUTPUT" | grep -E '[0-9]+ passed' | tail -1 || echo "")
if [[ -n "$SUMMARY_LINE" ]]; then
  PASSED=$(echo "$SUMMARY_LINE" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' || echo 0)
  FAILED=$(echo "$SUMMARY_LINE" | grep -oE '[0-9]+ failed' | grep -oE '[0-9]+' || echo 0)
  SKIPPED=$(echo "$SUMMARY_LINE" | grep -oE '[0-9]+ skipped' | grep -oE '[0-9]+' || echo 0)
  TOTAL=$(( PASSED + FAILED + SKIPPED ))
fi

# Determine verdict
if [[ "$PW_EXIT" -ne 0 ]] || [[ "$FAILED" -gt 0 ]]; then
  VERDICT="fail"
elif [[ ${#PREFLIGHT_WARNINGS[@]} -gt 0 ]]; then
  VERDICT="warning"
else
  VERDICT="pass"
fi

# ─── build failed_tests list ─────────────────────────────────────────────────

FAILED_TESTS_JSON="[]"
if [[ "$FAILED" -gt 0 ]]; then
  # Extract failed test lines from Playwright output heuristically
  # (Playwright outputs "  × <title> [...]" lines for failures)
  FAILED_TESTS_JSON=$(echo "$PW_OUTPUT" \
    | grep -E '^\s+×' \
    | sed 's/^\s*×\s*//' \
    | head -20 \
    | jq -Rn '[inputs | {"title": ., "file": ""}]' 2>/dev/null || echo "[]")
fi

# ─── build preflight_warnings JSON ───────────────────────────────────────────

PW_JSON_ARRAY="[]"
if [[ ${#PREFLIGHT_WARNINGS[@]} -gt 0 ]]; then
  PW_JSON_ARRAY=$(printf '%s\n' "${PREFLIGHT_WARNINGS[@]}" | jq -Rn '[inputs]' 2>/dev/null || echo "[]")
fi

# ─── emit result JSON ────────────────────────────────────────────────────────

jq -n \
  --arg sv "1.0" \
  --arg gt "e2e" \
  --arg verdict "$VERDICT" \
  --argjson total "$TOTAL" \
  --argjson passed "$PASSED" \
  --argjson failed "$FAILED" \
  --argjson skipped "$SKIPPED" \
  --arg report_path "$REPORT_PATH" \
  --argjson failed_tests "$FAILED_TESTS_JSON" \
  --argjson preflight_warnings "$PW_JSON_ARRAY" \
  '{
    schema_version: $sv,
    gate_type: $gt,
    verdict: $verdict,
    total_tests: $total,
    passed: $passed,
    failed: $failed,
    skipped: $skipped,
    report_path: $report_path,
    failed_tests: $failed_tests,
    preflight_warnings: $preflight_warnings
  }'

# Exit 0 on pass/warning; exit 1 on fail
if [[ "$VERDICT" = "fail" ]]; then
  exit 1
fi
exit 0
