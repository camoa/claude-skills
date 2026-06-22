#!/usr/bin/env bash
# visual-parity-gate.sh — run the committed tests/parity/ suite and emit a
# per-surface result fragment (ai-dev-assistant v4.14.0, Task D).
#
# Usage:
#   visual-parity-gate.sh <registry_path> <codePath> \
#       [--ci] [--all-viewports] [--project-pattern <prefix>]
#
#   <registry_path>     path to .visual-review/registry.yml — informational;
#                       echoed into the output. This script does NOT parse YAML
#                       (the suite itself is the source of truth for which
#                       surfaces run — same contract as visual-regression-gate.sh).
#   <codePath>          project root; the suite is <codePath>/tests/parity/
#   --ci                non-interactive mode — recorded in the output; no
#                       behavioural change here (this script never prompts).
#   --all-viewports     run every parity-chromium-* project. Default: run only
#                       the default-viewport project (parity-chromium-desktop if
#                       present, else the first discovered) — task.md single-
#                       viewport default for fast iteration.
#   --project-pattern   Playwright project-name prefix to run. Default
#                       `parity-chromium-`.
#
# Extracted from /validate:visual-parity so the comparison run is one reusable
# unit (Library-First). Playwright runs HOST-SIDE — the DDEV site is reached
# over HTTP via DDEV_PRIMARY_URL / PLAYWRIGHT_BASE_URL. Each generated parity
# spec calls runParityCheck() from tests/parity/parity-compare.mjs, which writes
# <surface>-<viewport>.parity.json into PARITY_RUN_DIR; this script merges those.
#
# Per-surface verdict (this script is the single authority — the spec assertion
# is only for the npx exit code):
#   skipped              — the .parity.json has skipped:true
#   fail                 — content_floor_failed  OR  pixel_diff_ratio >= the surface's
#                          EFFECTIVE max_diff_ratio  OR  css_diff non-empty
#   pass                 — otherwise
# The effective max_diff_ratio is the per-surface value parity-compare.mjs resolved (D4,
# its own .max_diff_ratio) else the global PARITY_MAX_DIFF_RATIO — the gate reads the
# fragment's value so its verdict matches the spec assertion exactly (paper-test F1).
#
# Output: a single JSON object on stdout:
#   { "surfaces": [ {id, viewport, reference_type, verdict, pixel_diff_ratio,
#                    max_diff_ratio, css_diff_mode, css_diff_count, css_diff[],
#                    content_floor_failed, content_floor_violations[], diff_path,
#                    skipped, skip_reason, notes[]}, ... ],
#     "summary": {surfaces_run, passed, failed, skipped},
#     "registry_path", "project_pattern", "ci_mode", "all_viewports",
#     "run_dir", "max_diff_ratio", "playwright_exit", "warnings": [ ... ] }
#
# Exit codes: 0 pass/skipped · 1 fail (>=1 surface failed) · 2 setup error.

set -uo pipefail

REGISTRY_PATH="${1:-}"
CODE_PATH="${2:-}"
CI_MODE=false
ALL_VIEWPORTS=false
PROJECT_PREFIX="parity-chromium-"

if [ -z "$REGISTRY_PATH" ] || [ -z "$CODE_PATH" ]; then
  echo "visual-parity-gate: <registry_path> and <codePath> required" >&2
  exit 2
fi
shift 2 || true
while [ "$#" -gt 0 ]; do
  case "$1" in
    --ci) CI_MODE=true; shift ;;
    --all-viewports) ALL_VIEWPORTS=true; shift ;;
    --project-pattern)
      if [ "$#" -ge 2 ] && [ -n "${2:-}" ]; then PROJECT_PREFIX="$2"; shift 2
      else shift; fi
      ;;
    *) shift ;;
  esac
done

if [ ! -d "$CODE_PATH" ]; then
  echo "visual-parity-gate: codePath does not exist: $CODE_PATH" >&2
  exit 2
fi
if [ ! -d "$CODE_PATH/tests/parity" ]; then
  echo "visual-parity-gate: tests/parity/ not found — run /setup-visual-parity first" >&2
  exit 2
fi
if ! command -v npx >/dev/null 2>&1; then
  echo "visual-parity-gate: npx not found in PATH" >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "visual-parity-gate: jq not found in PATH" >&2
  exit 2
fi

PW_CONFIG="$CODE_PATH/playwright.config.ts"
if [ ! -f "$PW_CONFIG" ]; then
  echo "visual-parity-gate: playwright.config.ts not found at codePath" >&2
  exit 2
fi

# Coarse pixel-diff threshold — same default as parity-compare.mjs; exported to
# the Playwright child AND used here to compute per-surface verdicts.
# Validate against the SAME predicate parity-compare.mjs's parseRatio() applies —
# a real number in the OPEN interval (0,1) — so the gate verdict and the spec
# assertion can never use different thresholds (paper-test F1).
MAX_DIFF_RATIO="${PARITY_MAX_DIFF_RATIO:-0.05}"
if ! printf '%s' "$MAX_DIFF_RATIO" | grep -qE '^[0-9]*\.?[0-9]+$' \
   || ! awk -v r="$MAX_DIFF_RATIO" 'BEGIN { exit !(r > 0 && r < 1) }'; then
  echo "visual-parity-gate: PARITY_MAX_DIFF_RATIO must be a ratio in (0,1), e.g. 0.05" >&2
  exit 2
fi

WARNINGS='[]'
add_warning() { WARNINGS=$(jq -c --arg w "$1" '. + [$w]' <<<"$WARNINGS"); }

emit() {
  # $1 surfaces, $2 summary
  jq -nc \
    --argjson s "$1" --argjson sm "$2" \
    --arg rp "$REGISTRY_PATH" --arg pp "$PROJECT_PREFIX" \
    --argjson ci "$CI_MODE" --argjson av "$ALL_VIEWPORTS" \
    --arg rd "${PARITY_RUN_DIR:-}" --arg mdr "$MAX_DIFF_RATIO" \
    --argjson pe "${PW_EXIT:-0}" --argjson w "$WARNINGS" '
    { surfaces: $s, summary: $sm, registry_path: $rp,
      project_pattern: $pp, ci_mode: $ci, all_viewports: $av,
      run_dir: $rd, max_diff_ratio: ($mdr | tonumber),
      playwright_exit: $pe, warnings: $w }'
}

# Validate --project-pattern before it is interpolated into a grep regex.
if ! printf '%s' "$PROJECT_PREFIX" | grep -qE '^[A-Za-z0-9_-]+$'; then
  echo "visual-parity-gate: --project-pattern must match ^[A-Za-z0-9_-]+\$" >&2
  exit 2
fi

# Discover the exact parity project names from playwright.config.ts.
PROJECTS=()
while IFS= read -r p; do
  [ -n "$p" ] && PROJECTS+=("$p")
done < <(grep -oE "name:[[:space:]]*['\"]${PROJECT_PREFIX}[A-Za-z0-9_-]+['\"]" "$PW_CONFIG" 2>/dev/null \
  | grep -oE "${PROJECT_PREFIX}[A-Za-z0-9_-]+" | sort -u)

if [ "${#PROJECTS[@]}" -eq 0 ]; then
  add_warning "no_parity_projects: playwright.config.ts has no ${PROJECT_PREFIX}* project entries"
  emit '[]' '{"surfaces_run":0,"passed":0,"failed":0,"skipped":0}'
  exit 0
fi

# Single-viewport default: pick parity-chromium-desktop if present, else the
# first. --all-viewports runs every discovered project.
RUN_PROJECTS=()
if [ "$ALL_VIEWPORTS" = true ]; then
  RUN_PROJECTS=("${PROJECTS[@]}")
else
  DEFAULT_PROJ=""
  for p in "${PROJECTS[@]}"; do
    [ "$p" = "${PROJECT_PREFIX}desktop" ] && DEFAULT_PROJ="$p"
  done
  if [ -z "$DEFAULT_PROJ" ]; then
    # No desktop viewport — PROJECTS is sort -u'd, so PROJECTS[0] is the
    # alphabetically-first project. Surface that choice rather than picking
    # silently (paper-test F5).
    DEFAULT_PROJ="${PROJECTS[0]}"
    add_warning "no_desktop_viewport: no ${PROJECT_PREFIX}desktop project — defaulting to '$DEFAULT_PROJ'; pass --all-viewports to run every viewport"
  fi
  RUN_PROJECTS=("$DEFAULT_PROJ")
fi

PROJ_ARGS=()
for p in "${RUN_PROJECTS[@]}"; do PROJ_ARGS+=("--project" "$p"); done

# ─── run directory ───────────────────────────────────────────────────────────
RUN_STAMP=$(date -u +%Y%m%dT%H%M%SZ)
export PARITY_RUN_DIR="$CODE_PATH/parity-results/$RUN_STAMP"
export PARITY_MAX_DIFF_RATIO="$MAX_DIFF_RATIO"
# JSONL trend stream (D6): a STABLE path under parity-results/ so the stream accumulates
# across runs — one timestamped line per surface/run. A trend reader uses the timestamps
# to chart a surface over time; a snapshot reader may dedupe by project|surfaceId
# (last-write-wins) for the latest state. It is under the gitignored parity-results/, so
# it is never committed.
export PARITY_STATS_PATH="$CODE_PATH/parity-results/parity-stats.jsonl"
# Confinement root for parity-compare.mjs file references (paper-test A2/A3) —
# explicit, not the implicit process CWD.
export PARITY_CODE_PATH="$CODE_PATH"
# PARITY_REFERENCE_BASE_URL (D7) is read by parity-compare.mjs straight from the
# environment — npx playwright test inherits it; the gate passes it through unchanged.
if ! mkdir -p "$PARITY_RUN_DIR"; then
  echo "visual-parity-gate: cannot create run dir $PARITY_RUN_DIR" >&2
  exit 2
fi

# ─── run the suite ───────────────────────────────────────────────────────────
PW_EXIT=0
PW_JSON=$(cd "$CODE_PATH" && npx playwright test "${PROJ_ARGS[@]}" --reporter=json 2>/dev/null) || PW_EXIT=$?

# ─── merge the per-surface .parity.json fragments the specs wrote ─────────────
SURFACES='[]'
RUN=0; PASSED=0; FAILED=0; SKIPPED=0

shopt -s nullglob
RESULT_FILES=("$PARITY_RUN_DIR"/*.parity.json)
shopt -u nullglob

if [ "${#RESULT_FILES[@]}" -eq 0 ]; then
  # No fragments. Either the registry has no parity surfaces (clean skip) or the
  # suite crashed before any spec wrote its result.
  if [ "$PW_EXIT" -ne 0 ]; then
    add_warning "parity_specs_produced_no_results: the suite exited $PW_EXIT and wrote no .parity.json fragments"
    emit '[]' '{"surfaces_run":0,"passed":0,"failed":0,"skipped":0}'
    exit 2
  fi
  emit '[]' '{"surfaces_run":0,"passed":0,"failed":0,"skipped":0}'
  exit 0
fi

for rf in "${RESULT_FILES[@]}"; do
  if ! jq -e . >/dev/null 2>&1 <"$rf"; then
    add_warning "unparseable_fragment: $(basename "$rf")"
    continue
  fi
  # Minimal-shape assertion (paper-test F3): a fragment with no non-empty
  # .surface is structurally incomplete — never count it as a passing surface.
  if [ -z "$(jq -r '.surface // "" | select(type == "string")' <"$rf" 2>/dev/null)" ]; then
    add_warning "incomplete_fragment: $(basename "$rf") — missing or empty .surface"
    continue
  fi
  # The EFFECTIVE per-surface threshold (D4) is whatever parity-compare.mjs resolved and
  # wrote into the fragment as .max_diff_ratio (per-surface override else the global). The
  # gate reads it back so its verdict uses the IDENTICAL number the spec asserted on
  # (paper-test F1) — it never re-derives the per-surface value. A pre-D4 fragment with no
  # .max_diff_ratio falls back to the global $mdr. Content-floor failures (D8) fail too.
  row=$(jq -c --argjson mdr "$MAX_DIFF_RATIO" '
    {
      id:              (.surface // ""),
      viewport:        (.viewport // ""),
      reference_type:  (.reference_type // ""),
      pixel_diff_ratio: .pixel_diff_ratio,
      max_diff_ratio:  (.max_diff_ratio // $mdr),
      css_diff_mode:   (.css_diff_mode // "build-only"),
      css_diff:        (.css_diff // []),
      css_diff_count:  ((.css_diff // []) | length),
      content_floor_failed: (.content_floor_failed // false),
      content_floor_violations: (.content_floor_violations // []),
      diff_path:       (.pixel_diff_path // null),
      skipped:         (.skipped // false),
      skip_reason:     (.skip_reason // null),
      notes:           (.notes // [])
    }
    | .verdict = (
        if .skipped then "skipped"
        elif (.content_floor_failed == true) then "fail"
        elif ((.pixel_diff_ratio != null) and (.pixel_diff_ratio >= .max_diff_ratio)) then "fail"
        elif (.css_diff_count > 0) then "fail"
        else "pass" end )
  ' <"$rf")
  [ -z "$row" ] && continue

  verdict=$(jq -r '.verdict' <<<"$row")
  RUN=$((RUN + 1))
  case "$verdict" in
    fail)    FAILED=$((FAILED + 1)) ;;
    skipped) SKIPPED=$((SKIPPED + 1)) ;;
    *)       PASSED=$((PASSED + 1)) ;;
  esac
  SURFACES=$(jq -c --argjson r "$row" '. + [$r]' <<<"$SURFACES")
done

SUMMARY=$(jq -nc --argjson r "$RUN" --argjson p "$PASSED" --argjson f "$FAILED" --argjson s "$SKIPPED" \
  '{surfaces_run:$r, passed:$p, failed:$f, skipped:$s}')

emit "$SURFACES" "$SUMMARY"

[ "$FAILED" -gt 0 ] && exit 1
exit 0
