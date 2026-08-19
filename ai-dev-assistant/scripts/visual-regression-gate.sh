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
  #
  # ORDER THE SURFACES WORST FIRST. Nothing used to rank them, so a reviewer
  # walking fifteen panels got them in whatever order they happened to appear and
  # started wherever the alphabet put them. Failures come first, ordered by how
  # much moved; then warnings; then passes. The eye starts where the damage is.
  #
  # report_dir ties this verdict to the report it was produced alongside. Without
  # it "the report from this run" is unenforceable, because the html reporter used
  # to write one shared directory that any later run replaced.
  jq -nc \
    --argjson s "$1" --argjson sm "$2" \
    --arg rp "$REGISTRY_PATH" --arg pp "$PROJECT_PREFIX" \
    --arg rd "${REPORT_DIR:-}" --arg rid "${REPORT_ID:-}" \
    --argjson ci "$CI_MODE" --argjson pe "${PW_EXIT:-0}" --argjson w "$WARNINGS" '
    def rank: if .verdict == "fail" then 0 elif .verdict == "warning" then 1 else 2 end;
    { surfaces: ($s | sort_by([rank, -((.diff_pixels // .diff_percent // 0)), .id])),
      summary: $sm, registry_path: $rp, report_dir: $rd, report_id: $rid,
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
  # EXIT NON-ZERO. This used to emit an all-zero summary and exit 0 — a run that
  # inspected no surface, reported as a clean run. The sibling baseline-manager
  # treats the identical condition as fatal, and it is the one that is right: a
  # gate with nothing to run has not passed, it has not run. A caller that reads
  # only the verdict would otherwise record a green visual gate for a project
  # whose visual projects were never configured.
  add_warning "no_visual_projects: playwright.config.ts has no ${PROJECT_PREFIX}* project entries"
  emit '[]' '{"surfaces_run":0,"passed":0,"failed":0,"skipped":0}'
  printf 'visual-regression-gate: no %s* projects in playwright.config.ts.\n' "$PROJECT_PREFIX" >&2
  printf '  Nothing to run, so nothing passed. Run /setup-visual-regression.\n' >&2
  exit 2
fi

# ─── base-URL preflight ──────────────────────────────────────────────────────
# Resolve the same chain playwright.config.ts resolves, and check the site answers
# BEFORE running the suite. Without this, an unreachable or wrong base URL fails
# once per surface with a connection error, and the operator reads N failures
# instead of one cause. `DDEV_PRIMARY_URL` is exported only inside a `ddev` shell
# and this gate runs host-side, so in practice it is the env override or the URL
# setup derived into the config.
BASE_URL="${PLAYWRIGHT_BASE_URL:-${DDEV_PRIMARY_URL:-}}"
if [ -z "$BASE_URL" ]; then
  BASE_URL=$(grep -oE "^const DERIVED_BASE_URL = '[^']*'" "$PW_CONFIG" 2>/dev/null \
    | sed -E "s/^const DERIVED_BASE_URL = '//; s/'$//")
fi
case "$BASE_URL" in http*) ;; *) BASE_URL='https://localhost' ;; esac

if command -v curl >/dev/null 2>&1; then
  if ! curl -ksSf -o /dev/null --max-time 15 "$BASE_URL" 2>/dev/null; then
    add_warning "base_url_unreachable: ${BASE_URL} did not answer. Set PLAYWRIGHT_BASE_URL, or re-run /setup-visual-regression to derive it."
    emit '[]' '{"surfaces_run":0,"passed":0,"failed":0,"skipped":0}'
    printf 'visual-regression-gate: base URL %s did not answer.\n' "$BASE_URL" >&2
    printf '  Every capture would fail against it. Set PLAYWRIGHT_BASE_URL, or\n' >&2
    printf '  re-run /setup-visual-regression to resolve the project URL.\n' >&2
    exit 2
  fi
else
  add_warning "base_url_unchecked: curl not available, so ${BASE_URL} was not preflighted"
fi

PROJ_ARGS=()
for p in "${PROJECTS[@]}"; do PROJ_ARGS+=("--project" "$p"); done

# Cap concurrency HERE as well as in playwright.config.ts. The config default is
# the right place to state the reason, but a project that edited its config would
# otherwise uncap the capture path silently. The framework is DDEV-first by
# declaration, so the backend is known to be one web container: measured on a
# 16-core host, the uncapped default failed 36 of 72 captures with no change to
# the site. Override with VR_WORKERS when the backend can actually serve more.
VR_WORKERS="${VR_WORKERS:-2}"
case "$VR_WORKERS" in
  ''|*[!0-9]*) VR_WORKERS=2 ;;
esac
[ "$VR_WORKERS" -lt 1 ] && VR_WORKERS=1

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
# RUN-SCOPED REPORT. The html reporter used to write the single shared
# `playwright-report/`, so any later Playwright run in the same checkout silently
# replaced it. Observed: a verifier ran one unrelated command and the served
# report went from 15 tests to 1, while the recorded verdict still said pass and
# the server still returned 200. "Walk every surface in the report from this run"
# has no meaning while the report is last-writer-wins global state.
REPORT_ID="${VR_RUN_ID:-$(date +%Y%m%d-%H%M%S)-$$}"
REPORT_DIR=".visual-review/reports/$REPORT_ID"
mkdir -p "$CODE_PATH/$REPORT_DIR" 2>/dev/null || true

PW_JSON_FILE="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/vr-gate-$$.json")"
( cd "$CODE_PATH" \
  && PLAYWRIGHT_HTML_OPEN=never PLAYWRIGHT_JSON_OUTPUT_NAME="$PW_JSON_FILE" \
     PLAYWRIGHT_HTML_OUTPUT_DIR="$REPORT_DIR" \
     npx playwright test "${PROJ_ARGS[@]}" --workers "$VR_WORKERS" \
       --reporter="json,html:$REPORT_DIR" >/dev/null 2>&1 ) || PW_EXIT=$?
PW_JSON="$(cat "$PW_JSON_FILE" 2>/dev/null || true)"
rm -f "$PW_JSON_FILE"

if ! jq -e . >/dev/null 2>&1 <<<"$PW_JSON"; then
  # EXIT NON-ZERO WHATEVER PLAYWRIGHT SAID. No parseable report means this gate
  # did not observe a single surface, so it cannot report a verdict either way.
  # The previous version exited 0 when Playwright itself exited 0, and its comment
  # claimed the degradation was "never a false pass" — true only for a consumer
  # that reads warnings[], and no consumer did. An unreadable report is a broken
  # run, not a quiet success.
  add_warning "playwright_no_json: the suite produced no parseable JSON report (exit $PW_EXIT)"
  emit '[]' '{"surfaces_run":0,"passed":0,"failed":0,"skipped":0}'
  printf 'visual-regression-gate: the suite produced no parseable JSON report (playwright exit %s).\n' "$PW_EXIT" >&2
  printf '  No surface was observed, so this run has no verdict.\n' >&2
  exit 2
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
  diff_pixels='null'
  diff_path='null'
  failure_kind='null'
  if [ "$verdict" = "fail" ]; then
    ERR_TEXT=$(jq -r '.errors[]? // ""' <<<"$row")

    # A full-page image is sized to the document, so a page that renders taller
    # fails on DIMENSION MISMATCH before any tolerance is consulted — and produces
    # no diff image. That is a correct verdict (the page changed length) but it
    # reads as an inscrutable error, and a reviewer hunts for a diff that does not
    # exist. Name it instead. Playwright phrases this as
    # "Expected an image WxH, but got WxH".
    DIMS=$(printf '%s' "$ERR_TEXT" \
      | grep -oE 'Expected an image [0-9]+px by [0-9]+px, received [0-9]+px by [0-9]+px' \
      | head -1)
    [ -z "$DIMS" ] && DIMS=$(printf '%s' "$ERR_TEXT" \
      | grep -oE 'Expected an image [0-9]+ by [0-9]+, received [0-9]+ by [0-9]+' \
      | head -1)

    if [ -n "$DIMS" ]; then
      failure_kind=$(jq -Rn --arg d "$DIMS" '"dimension_change: " + $d')
    else
      failure_kind='"pixel_diff"'

      # EXACT COUNT FIRST. Playwright's message carries both an absolute pixel
      # count and a ratio: "N pixels (ratio 0.NN of all image pixels) are
      # different". The count is exact; the ratio is printed to two decimals, so
      # multiplying it by 100 yields a figure that moves only in whole
      # percentage points. The old code then formatted that to four decimals —
      # four digits of precision it does not have. Against a small tolerance the
      # entire decision band collapsed onto 0 or 1, so the number offered to
      # triage a borderline failure was blind exactly where it mattered.
      max_pixels=$(printf '%s' "$ERR_TEXT" \
        | grep -oE '[0-9]+ pixels' \
        | grep -oE '[0-9]+' \
        | sort -rn | head -1)
      [ -n "$max_pixels" ] && diff_pixels="$max_pixels"

      max_ratio=$(printf '%s' "$ERR_TEXT" \
        | grep -oE 'ratio [0-9]+\.[0-9]+' \
        | grep -oE '[0-9]+\.[0-9]+' \
        | sort -rn | head -1)
      if [ -n "$max_ratio" ]; then
        # Two decimals in, two decimals out. No invented digits.
        diff_percent=$(awk -v r="$max_ratio" 'BEGIN { printf "%.2f", r * 100 }')
      fi

      # Playwright writes its diff image under test-results/ in a hash-mangled
      # directory. Find it rather than leaving the reviewer to glob for it: the
      # mandated prompt asks for this path, and an unfillable token becomes the
      # literal word "unknown" at the moment a human decides regression versus
      # intentional.
      found_diff=$(find "$CODE_PATH/test-results" -type f -name "*${sid}*diff.png" 2>/dev/null | head -1)
      [ -n "$found_diff" ] && diff_path=$(jq -Rn --arg p "$found_diff" '$p')
    fi
  fi

  RUN=$((RUN + 1))
  case "$verdict" in
    fail) FAILED=$((FAILED + 1)) ;;
    pass) PASSED=$((PASSED + 1)) ;;
    skipped) SKIPPED=$((SKIPPED + 1)) ;;
  esac

  SURFACES=$(jq -c \
    --arg id "$sid" --arg v "$verdict" --argjson dp "$diff_percent" --argjson fv "$FAILED_VPS" \
    --argjson fk "$failure_kind" --argjson dpx "$diff_pixels" --argjson dpath "$diff_path" '
    . + [{id:$id, verdict:$v, diff_percent:$dp, diff_pixels:$dpx, diff_path:$dpath,
          failure_kind:$fk, failed_viewports:$fv}]' <<<"$SURFACES")
done <<<"$SURFACE_ROWS"

SUMMARY=$(jq -nc --argjson r "$RUN" --argjson p "$PASSED" --argjson f "$FAILED" --argjson s "$SKIPPED" \
  '{surfaces_run:$r, passed:$p, failed:$f, skipped:$s}')

emit "$SURFACES" "$SUMMARY"

[ "$FAILED" -gt 0 ] && exit 1
exit 0
