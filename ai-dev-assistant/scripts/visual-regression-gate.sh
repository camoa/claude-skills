#!/usr/bin/env bash
# visual-regression-gate.sh — run the committed tests/visual/ suite and emit a
# per-surface result fragment (ai-dev-assistant v4.13.0, Task C).
#
# Usage:
#   visual-regression-gate.sh <registry_path> <codePath> \
#       [--ci] [--project-pattern <prefix>]
#
#   <registry_path>     path to .visual-review/registry.yml — informational;
#                       echoed into the output. This script does NOT parse YAML
#                       (Task C D-impl-1) — the suite itself is the source of
#                       truth for which surfaces run.
#   <codePath>          project root; the suite is <codePath>/tests/visual/
#   --ci                non-interactive mode — recorded in the output; no
#                       behavioural change here (this script never prompts).
#   --project-pattern   Playwright project-name prefix to run. Default
#                       `visual-chromium-`. Exact project names are discovered
#                       from playwright.config.ts and passed as --project flags.
#
# Extracted from /validate:visual-regression so /validate:all can run the same
# logic (Library-First). Playwright runs HOST-SIDE — the DDEV site is reached
# over HTTP via DDEV_PRIMARY_URL / PLAYWRIGHT_BASE_URL.
#
# Output: a single JSON object on stdout:
#   { "surfaces": [ {id, verdict, diff_percent, failed_viewports[]}, ... ],
#     "summary": {surfaces_run, passed, failed, skipped},
#     "registry_path": "...", "project_pattern": "...", "ci_mode": bool,
#     "playwright_exit": <int>, "warnings": [ ... ] }
#
# Exit codes: 0 pass/skipped · 1 fail (≥1 surface failed) · 2 setup error.

set -uo pipefail

REGISTRY_PATH="${1:-}"
CODE_PATH="${2:-}"
CI_MODE=false
PROJECT_PREFIX="visual-chromium-"

if [ -z "$REGISTRY_PATH" ] || [ -z "$CODE_PATH" ]; then
  echo "visual-regression-gate: <registry_path> and <codePath> required" >&2
  exit 2
fi
shift 2 || true
while [ "$#" -gt 0 ]; do
  case "$1" in
    --ci) CI_MODE=true; shift ;;
    --project-pattern)
      if [ "$#" -ge 2 ] && [ -n "${2:-}" ]; then PROJECT_PREFIX="$2"; shift 2
      else shift; fi
      ;;
    *) shift ;;
  esac
done

if [ ! -d "$CODE_PATH" ]; then
  echo "visual-regression-gate: codePath does not exist: $CODE_PATH" >&2
  exit 2
fi
if [ ! -d "$CODE_PATH/tests/visual" ]; then
  echo "visual-regression-gate: tests/visual/ not found — run /setup-visual-regression first" >&2
  exit 2
fi
if ! command -v npx >/dev/null 2>&1; then
  echo "visual-regression-gate: npx not found in PATH" >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "visual-regression-gate: jq not found in PATH" >&2
  exit 2
fi

PW_CONFIG="$CODE_PATH/playwright.config.ts"
if [ ! -f "$PW_CONFIG" ]; then
  echo "visual-regression-gate: playwright.config.ts not found at codePath" >&2
  exit 2
fi

WARNINGS='[]'
add_warning() { WARNINGS=$(jq -c --arg w "$1" '. + [$w]' <<<"$WARNINGS"); }

emit() {
  # $1 surfaces, $2 summary
  jq -nc \
    --argjson s "$1" --argjson sm "$2" \
    --arg rp "$REGISTRY_PATH" --arg pp "$PROJECT_PREFIX" \
    --argjson ci "$CI_MODE" --argjson pe "${PW_EXIT:-0}" --argjson w "$WARNINGS" '
    { surfaces: $s, summary: $sm, registry_path: $rp,
      project_pattern: $pp, ci_mode: $ci, playwright_exit: $pe, warnings: $w }'
}

# Validate --project-pattern before it is interpolated into a grep regex —
# restrict to plain identifier chars so no regex metacharacters reach grep.
if ! printf '%s' "$PROJECT_PREFIX" | grep -qE '^[A-Za-z0-9_-]+$'; then
  echo "visual-regression-gate: --project-pattern must match ^[A-Za-z0-9_-]+\$" >&2
  exit 2
fi

# Discover the exact visual project names from playwright.config.ts. Playwright
# --project matches exact names; deriving them from the config is version-safe.
# The `[A-Za-z0-9_-]+` tail also matches authenticated projects of the form
# `visual-chromium-<vp>-<ctx>` (the `-<ctx>` suffix is plain identifier chars), so
# authed surfaces are discovered with no change. Their `visual-setup-<ctx>`
# dependency project does NOT match the `visual-chromium-` prefix, so it is not
# passed via --project here; Playwright still runs it automatically because the
# authed project lists it in `dependencies`. Both behaviours are intentional.
# (portable read loop — `mapfile` is bash 4+; macOS ships bash 3.2)
PROJECTS=()
while IFS= read -r p; do
  [ -n "$p" ] && PROJECTS+=("$p")
done < <(grep -oE "name:[[:space:]]*['\"]${PROJECT_PREFIX}[A-Za-z0-9_-]+['\"]" "$PW_CONFIG" 2>/dev/null \
  | grep -oE "${PROJECT_PREFIX}[A-Za-z0-9_-]+" | sort -u)

if [ "${#PROJECTS[@]}" -eq 0 ]; then
  add_warning "no_visual_projects: playwright.config.ts has no ${PROJECT_PREFIX}* project entries"
  emit '[]' '{"surfaces_run":0,"passed":0,"failed":0,"skipped":0}'
  exit 0
fi

PROJ_ARGS=()
for p in "${PROJECTS[@]}"; do PROJ_ARGS+=("--project" "$p"); done

# ─── run the suite ───────────────────────────────────────────────────────────

PW_EXIT=0
# Run BOTH the json reporter (this gate parses it) AND the html reporter, so
# `npx playwright show-report` / `--show-diffs` has a CURRENT report whose
# image-diff Slider the reviewer can open at the Step 9 classification pause. A
# CLI `--reporter` REPLACES the config reporter (it does not merge), so the html
# reporter added to playwright.config is NOT enough on this path — we must
# request it here too. `PLAYWRIGHT_JSON_OUTPUT_NAME` routes the JSON to a file so
# the html reporter's stdout never corrupts the parse; `PLAYWRIGHT_HTML_OPEN=never`
# stops the html reporter auto-launching a browser on the failing-screenshot case.
# (PLAYWRIGHT_JSON_OUTPUT_NAME is honored on all supported @playwright/test; on a
# version old enough to ignore it the JSON would go to the /dev/null'd stdout and
# this file stays empty — which degrades fail-safe to the playwright_no_json branch
# below, never a false pass.)
PW_JSON_FILE="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/vr-gate-$$.json")"
( cd "$CODE_PATH" \
  && PLAYWRIGHT_HTML_OPEN=never PLAYWRIGHT_JSON_OUTPUT_NAME="$PW_JSON_FILE" \
     npx playwright test "${PROJ_ARGS[@]}" --reporter=json,html >/dev/null 2>&1 ) || PW_EXIT=$?
PW_JSON="$(cat "$PW_JSON_FILE" 2>/dev/null || true)"
rm -f "$PW_JSON_FILE"

if ! jq -e . >/dev/null 2>&1 <<<"$PW_JSON"; then
  add_warning "playwright_no_json: the suite produced no parseable JSON report (exit $PW_EXIT)"
  emit '[]' '{"surfaces_run":0,"passed":0,"failed":0,"skipped":0}'
  # A non-zero exit with no JSON is a setup/run failure, not a clean pass.
  [ "$PW_EXIT" -ne 0 ] && exit 2
  exit 0
fi

# Per-file (= per-surface) status + error rollup. Each top-level suite is a
# spec file; recurse() descends through describe blocks.
SURFACE_ROWS=$(jq -c '
  [ .suites[]
    | { file: (.file // .title),
        results: [ recurse(.suites[]?) | .specs[]? | .tests[]?
                   | { project: .projectName, status: (.results[]?.status) } ],
        errors:  [ recurse(.suites[]?) | .specs[]? | .tests[]?
                   | .results[]? | .errors[]? | .message ] } ]
  | .[]' <<<"$PW_JSON" 2>/dev/null || true)

SURFACES='[]'
RUN=0; PASSED=0; FAILED=0; SKIPPED=0

while IFS= read -r row; do
  [ -z "$row" ] && continue
  file=$(jq -r '.file // ""' <<<"$row")
  [ -z "$file" ] && continue
  sid=$(basename "$file")
  sid="${sid%.spec.ts}"

  # Collect per-result status; determine the surface verdict.
  # (portable read loop — `mapfile` is bash 4+; macOS ships bash 3.2)
  STATUSES=()
  while IFS= read -r st_line; do
    [ -n "$st_line" ] && STATUSES+=("$st_line")
  done < <(jq -r '.results[]?.status // empty' <<<"$row")
  verdict="skipped"
  if [ "${#STATUSES[@]}" -gt 0 ]; then
    any_fail=0; any_pass=0
    for st in "${STATUSES[@]}"; do
      case "$st" in
        failed|timedOut|interrupted) any_fail=1 ;;
        passed) any_pass=1 ;;
      esac
    done
    if [ "$any_fail" -eq 1 ]; then verdict="fail"
    elif [ "$any_pass" -eq 1 ]; then verdict="pass"
    else verdict="skipped"; fi
  fi

  # Failed viewports — project names of failing results, prefix stripped.
  # NOTE (authed VR, cosmetic): for an authenticated project named
  # `visual-chromium-<vp>-<ctx>`, stripping only the `visual-chromium-` prefix
  # yields `<vp>-<ctx>` here (not the bare `<vp>`). This is accepted as-is — it
  # still uniquely identifies the failing project/viewport+context pair and does
  # not affect the verdict. Do not "fix" by splitting on `-`: viewport names may
  # themselves contain hyphens, so there is no safe split. No logic change.
  FAILED_VPS=$(jq -c --arg pre "$PROJECT_PREFIX" '
    [ .results[]
      | select(.status == "failed" or .status == "timedOut" or .status == "interrupted")
      | .project | sub("^" + $pre; "") ] | unique' <<<"$row")

  # Best-effort diff_percent — Playwright screenshot errors carry
  # "(ratio 0.NN of all image pixels)". Take the max ratio for the surface.
  diff_percent='null'
  if [ "$verdict" = "fail" ]; then
    max_ratio=$(jq -r '.errors[]? // ""' <<<"$row" \
      | grep -oE 'ratio [0-9]+\.[0-9]+' \
      | grep -oE '[0-9]+\.[0-9]+' \
      | sort -rn | head -1)
    if [ -n "$max_ratio" ]; then
      diff_percent=$(awk -v r="$max_ratio" 'BEGIN { printf "%.4f", r * 100 }')
    fi
  fi

  RUN=$((RUN + 1))
  case "$verdict" in
    fail) FAILED=$((FAILED + 1)) ;;
    pass) PASSED=$((PASSED + 1)) ;;
    skipped) SKIPPED=$((SKIPPED + 1)) ;;
  esac

  SURFACES=$(jq -c \
    --arg id "$sid" --arg v "$verdict" --argjson dp "$diff_percent" --argjson fv "$FAILED_VPS" '
    . + [{id:$id, verdict:$v, diff_percent:$dp, failed_viewports:$fv}]' <<<"$SURFACES")
done <<<"$SURFACE_ROWS"

SUMMARY=$(jq -nc --argjson r "$RUN" --argjson p "$PASSED" --argjson f "$FAILED" --argjson s "$SKIPPED" \
  '{surfaces_run:$r, passed:$p, failed:$f, skipped:$s}')

emit "$SURFACES" "$SUMMARY"

[ "$FAILED" -gt 0 ] && exit 1
exit 0
