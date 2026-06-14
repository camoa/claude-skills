#!/usr/bin/env bash
# validate-e2e.sh — run behavioral E2E tests via Playwright (framework-agnostic gate).
#
# Usage: validate-e2e.sh <codePath> [--task <name>] [--smoke-only]
#                        [--surfaces-json '<json>'] [--preflight-cmd '<cmd>']
#
#   <codePath>: absolute path to the project root
#   --task <name>: task name (informational; used in output JSON)
#   --smoke-only: add --grep "@smoke" to Playwright (fast subset)
#   --surfaces-json '<json>': JSON array of surface ids with gate:e2e (passed by Claude
#                             from registry.yml — this script does NOT parse YAML)
#   --preflight-cmd '<cmd>': OPTIONAL shell command run in <codePath> before the tests.
#                            A non-zero exit fails the gate; its output is captured.
#                            The gate is framework-agnostic — the command is supplied by
#                            the calling command from project config (whatever preflight
#                            the framework's recipe declares). Absent =
#                            no preflight runs.
#
# YAML boundary: registry.yml is parsed by the calling command (validate-e2e.md,
# executed by Claude). Claude reads the YAML, filters gate:e2e surfaces, resolves the
# preflight command, and passes them as structured args. This script parses no YAML.
#
# Playwright runs HOST-SIDE. The browser reaches the site under test via
# PLAYWRIGHT_BASE_URL (or the harness config's baseURL).
#
# Output: single JSON object to stdout (see schema below).
# Exit codes:
#   0 — pass or warning (all tests passed, or preflight warnings only)
#   1 — fail (one or more tests failed, or the preflight command failed)
#   2 — invalid arguments or missing pre-requisites

set -uo pipefail

# ─── argument parsing ────────────────────────────────────────────────────────

CODE_PATH="${1:?codePath required}"
TASK_NAME=""
SMOKE_ONLY=0
SURFACES_JSON="[]"
PREFLIGHT_CMD=""

shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)
      # Use default-empty then validate to produce exit 2 (not bash :? exit 1)
      TASK_NAME="${2:-}"
      if [[ -z "$TASK_NAME" ]]; then
        echo "validate-e2e: --task requires a value" >&2
        exit 2
      fi
      shift
      ;;
    --smoke-only)
      SMOKE_ONLY=1
      ;;
    --surfaces-json)
      SURFACES_JSON="${2:?--surfaces-json requires a value}"
      shift
      ;;
    --preflight-cmd)
      PREFLIGHT_CMD="${2:-}"
      if [[ -z "$PREFLIGHT_CMD" ]]; then
        echo "validate-e2e: --preflight-cmd requires a value" >&2
        exit 2
      fi
      shift
      ;;
    *)
      echo "validate-e2e: unknown flag: $1" >&2
      echo "  usage: validate-e2e.sh <codePath> [--task <name>] [--smoke-only] [--surfaces-json '<json>'] [--preflight-cmd '<cmd>']" >&2
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

if ! command -v jq >/dev/null 2>&1; then
  echo "validate-e2e: jq not found in PATH (required for JSON assembly)" >&2
  exit 2
fi

# ─── pre-flight (configurable, framework-agnostic) ───────────────────────────
#
# The gate runs whatever preflight command the calling command resolved from
# project config (whatever preflight the framework's recipe declares).
# No framework is assumed here. Absent command ⇒ no preflight, no warning.

PREFLIGHT_WARNINGS=()

if [[ -n "$PREFLIGHT_CMD" ]]; then
  PF_OUTPUT=$(cd "$CODE_PATH" && bash -c "$PREFLIGHT_CMD" 2>&1) || {
    echo "validate-e2e: preflight command failed: $PREFLIGHT_CMD" >&2
    echo "$PF_OUTPUT" >&2
    # Emit structured error JSON using jq -n to safely handle any chars (EC-F20)
    PF_FIRST_LINE=$(echo "$PF_OUTPUT" | head -1)
    jq -n \
      --arg msg "preflight_failed: $PF_FIRST_LINE" \
      '{"schema_version":"1.0","gate_type":"e2e","verdict":"fail","total_tests":0,
        "passed":0,"failed":0,"skipped":0,"report_path":"",
        "failed_tests":[],"preflight_warnings":[$msg]}'
    exit 1
  }
fi

# ─── build --grep pattern ────────────────────────────────────────────────────

GREP_PATTERN=""

# Build surface id grep: "@<id1>|@<id2>|..."
# RT-V1: validate each surface id against the allow-list before use in grep pattern
SURFACE_COUNT=$(echo "$SURFACES_JSON" | jq 'length' 2>/dev/null || echo 0)
if [[ "$SURFACE_COUNT" -gt 0 ]]; then
  SAFE_IDS="[]"
  while IFS= read -r sid; do
    if [[ "$sid" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
      SAFE_IDS=$(echo "$SAFE_IDS" | jq --arg id "$sid" '. + [$id]')
    else
      echo "validate-e2e: WARNING: surface id '$sid' contains non-allowed characters (expected ^[a-z0-9][a-z0-9-]*\$); skipping" >&2
    fi
  done < <(echo "$SURFACES_JSON" | jq -r '.[]' 2>/dev/null || true)
  SURFACE_GREP=$(echo "$SAFE_IDS" | jq -r '[.[] | "@" + .] | join("|")' 2>/dev/null || echo "")
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

# HP-F7: HTML report dir is set via PLAYWRIGHT_HTML_REPORT env (not --output).
# --output controls test-result attachments, not the HTML report directory.
PW_ARGS=(
  "--project" "e2e-chromium"
  "--reporter" "html"
)

if [[ -n "$GREP_PATTERN" ]]; then
  PW_ARGS+=("--grep" "$GREP_PATTERN")
fi

PW_EXIT=0
PW_OUTPUT=""
PW_OUTPUT=$(cd "$CODE_PATH" && PLAYWRIGHT_HTML_REPORT="$REPORT_DIR" npx playwright test "${PW_ARGS[@]}" 2>&1) || PW_EXIT=$?

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

# EC-F19: if no "passed" line but there is a skipped-only line (all tests skipped),
# parse the skipped count from that line so the audit is accurate.
if [[ "$TOTAL" -eq 0 ]] && [[ "$PW_EXIT" -eq 0 ]]; then
  SKIPPED_LINE=$(echo "$PW_OUTPUT" | grep -E '[0-9]+ skipped' | tail -1 || echo "")
  if [[ -n "$SKIPPED_LINE" ]]; then
    SKIPPED=$(echo "$SKIPPED_LINE" | grep -oE '[0-9]+ skipped' | grep -oE '[0-9]+' || echo 0)
    TOTAL="$SKIPPED"
  fi
fi

# Determine verdict
if [[ "$PW_EXIT" -ne 0 ]] || [[ "$FAILED" -gt 0 ]]; then
  VERDICT="fail"
elif [[ "$TOTAL" -eq 0 ]]; then
  # EC-F18 CRITICAL: zero tests ran → warning, not pass; gate must never silently pass
  VERDICT="warning"
  PREFLIGHT_WARNINGS+=("no_tests_ran: zero tests matched the filter or behavioral/ is empty")
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
