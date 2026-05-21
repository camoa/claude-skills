#!/usr/bin/env bash
# baseline-manager.sh — bootstrap / regenerate visual-regression baselines
# (drupal-dev-framework v4.13.0, Task C).
#
# Usage:
#   baseline-manager.sh --bootstrap              --registry <path> --codepath <path> [opts]
#   baseline-manager.sh --update-baselines <why> --registry <path> --codepath <path> [opts]
#
#   opts: [--grep <pattern>] [--confirmed] [--triggered-by <value>]
#
# TWO-STAGE CONFIRM MODEL (Task C D-impl-8)
# -----------------------------------------
# Framework shell scripts are non-interactive. The "user must confirm every
# baseline write" invariant is enforced structurally:
#
#   PLAN mode    (no --confirmed) — prints the EXACT surfaces/viewports that
#                WOULD be (re)captured as JSON, writes nothing, exits 0.
#   EXECUTE mode (--confirmed)    — runs `npx playwright test --update-snapshots`
#                and appends baseline-history.jsonl.
#
# The calling command (/setup-visual-regression, /validate:visual-regression)
# runs PLAN mode first, shows the user the plan + the literal [y]/[n] prompt,
# and only on [y] re-invokes with --confirmed. No baseline can be written
# without an explicit user [y] — the script cannot be coaxed past PLAN mode
# without the flag the command sets only after the prompt.
#
# --grep scopes the update to confirmed surfaces (selective regeneration —
# blanket updates require an explicit no-grep run, flagged `blanket: true`).
#
# Playwright runs HOST-SIDE. The DDEV site is reached via DDEV_PRIMARY_URL.
#
# This script does NOT parse registry.yml — it scans tests/visual/*.spec.ts
# and playwright.config.ts. The --registry path locates baseline-history.jsonl
# (a sibling of the registry) and is echoed into the output.
#
# Exit codes: 0 success (plan or execute) · 1 the --update-snapshots run failed
#             · 2 validation / setup error.

set -uo pipefail

MODE=""
REASON=""
REGISTRY_PATH=""
CODE_PATH=""
GREP_PATTERN=""
CONFIRMED=false
TRIGGERED_BY=""

# Known baseline-recreation triggers (advisory — unknown reasons warn, not block).
KNOWN_TRIGGERS="intentional-ui-change prod-db-refresh upstream-theme-update contrib-update core-update fixture-change bootstrap"

err() { echo "baseline-manager: $1" >&2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --bootstrap) MODE="bootstrap"; shift ;;
    --update-baselines)
      MODE="update"
      if [ "$#" -ge 2 ] && [ -n "${2:-}" ] && [ "${2#--}" = "$2" ]; then
        REASON="$2"; shift 2
      else
        err "--update-baselines requires a <reason> argument"; exit 2
      fi
      ;;
    --registry)
      if [ "$#" -ge 2 ] && [ -n "${2:-}" ]; then REGISTRY_PATH="$2"; shift 2
      else err "--registry requires a value"; exit 2; fi
      ;;
    --codepath)
      if [ "$#" -ge 2 ] && [ -n "${2:-}" ]; then CODE_PATH="$2"; shift 2
      else err "--codepath requires a value"; exit 2; fi
      ;;
    --grep)
      if [ "$#" -ge 2 ] && [ -n "${2:-}" ]; then GREP_PATTERN="$2"; shift 2
      else err "--grep requires a value"; exit 2; fi
      ;;
    --triggered-by)
      if [ "$#" -ge 2 ] && [ -n "${2:-}" ]; then TRIGGERED_BY="$2"; shift 2
      else err "--triggered-by requires a value"; exit 2; fi
      ;;
    --confirmed) CONFIRMED=true; shift ;;
    *) err "unknown argument: $1"; exit 2 ;;
  esac
done

if [ -z "$MODE" ]; then
  err "one of --bootstrap | --update-baselines <reason> is required"; exit 2
fi
if [ -z "$REGISTRY_PATH" ] || [ -z "$CODE_PATH" ]; then
  err "--registry and --codepath are required"; exit 2
fi
if [ ! -d "$CODE_PATH" ]; then
  err "codePath does not exist: $CODE_PATH"; exit 2
fi
if [ ! -d "$CODE_PATH/tests/visual" ]; then
  err "tests/visual/ not found — run /setup-visual-regression first"; exit 2
fi
if ! command -v npx >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  err "npx and jq are required in PATH"; exit 2
fi

[ "$MODE" = "bootstrap" ] && REASON="bootstrap"

WARNINGS='[]'
add_warning() { WARNINGS=$(jq -c --arg w "$1" '. + [$w]' <<<"$WARNINGS"); }

# Advisory catalog check on the reason.
case " $KNOWN_TRIGGERS " in
  *" $REASON "*) ;;
  *) add_warning "unknown_trigger: '$REASON' is not in the known-trigger catalog (accepted as a freeform reason)" ;;
esac

# triggered_by default by mode.
if [ -z "$TRIGGERED_BY" ]; then
  if [ "$MODE" = "bootstrap" ]; then TRIGGERED_BY="setup:bootstrap"
  else TRIGGERED_BY="validate-visual-regression:--update-baselines"; fi
fi

BLANKET=true
[ -n "$GREP_PATTERN" ] && BLANKET=false

# ─── plan: which surfaces would be (re)captured ──────────────────────────────
# Surface stems = tests/visual/*.spec.ts basenames. With --grep, keep stems
# matching the pattern as an extended regex.
SURFACES_PLANNED='[]'
while IFS= read -r spec; do
  [ -z "$spec" ] && continue
  stem=$(basename "$spec" .spec.ts)
  if [ -n "$GREP_PATTERN" ]; then
    echo "$stem" | grep -qE "$GREP_PATTERN" 2>/dev/null || continue
  fi
  SURFACES_PLANNED=$(jq -c --arg s "$stem" '. + [$s]' <<<"$SURFACES_PLANNED")
done < <(find "$CODE_PATH/tests/visual" -maxdepth 1 -type f -name '*.spec.ts' 2>/dev/null | sort)

# Viewport names from playwright.config.ts visual projects.
PW_CONFIG="$CODE_PATH/playwright.config.ts"
VIEWPORTS='[]'
if [ -f "$PW_CONFIG" ]; then
  while IFS= read -r vp; do
    [ -z "$vp" ] && continue
    VIEWPORTS=$(jq -c --arg v "$vp" '. + [$v]' <<<"$VIEWPORTS")
  done < <(grep -oE "name:[[:space:]]*['\"]visual-chromium-[a-z0-9-]+['\"]" "$PW_CONFIG" 2>/dev/null \
            | grep -oE 'visual-chromium-[a-z0-9-]+' | sed 's/^visual-chromium-//' | sort -u)
fi

HISTORY_PATH="$(dirname "$REGISTRY_PATH")/baseline-history.jsonl"

emit_plan() {
  jq -nc \
    --arg mode "$MODE" --arg reason "$REASON" --arg gp "$GREP_PATTERN" \
    --argjson blanket "$BLANKET" --argjson sp "$SURFACES_PLANNED" \
    --argjson vp "$VIEWPORTS" --arg hp "$HISTORY_PATH" \
    --arg tb "$TRIGGERED_BY" --argjson w "$WARNINGS" '
    { stage: "plan", mode: $mode, reason: $reason,
      grep_pattern: $gp, blanket: $blanket,
      surfaces_planned: $sp, viewports: $vp,
      history_path: $hp, triggered_by: $tb, warnings: $w }'
}

# PLAN MODE — no --confirmed: print the plan, write nothing.
if [ "$CONFIRMED" != true ]; then
  emit_plan
  exit 0
fi

# ─── EXECUTE MODE ────────────────────────────────────────────────────────────

if [ "$(jq 'length' <<<"$SURFACES_PLANNED")" -eq 0 ]; then
  add_warning "no_surfaces: no spec files matched — nothing to update"
  jq -nc --argjson w "$WARNINGS" '{stage:"execute",updated:false,playwright_exit:0,warnings:$w}'
  exit 0
fi

# Discover visual project names for --project flags.
PROJ_ARGS=()
while IFS= read -r p; do
  [ -z "$p" ] && continue
  PROJ_ARGS+=("--project" "$p")
done < <(grep -oE "name:[[:space:]]*['\"]visual-chromium-[a-z0-9-]+['\"]" "$PW_CONFIG" 2>/dev/null \
          | grep -oE 'visual-chromium-[a-z0-9-]+' | sort -u)

PW_ARGS=(test --update-snapshots)
[ "${#PROJ_ARGS[@]}" -gt 0 ] && PW_ARGS+=("${PROJ_ARGS[@]}")
[ -n "$GREP_PATTERN" ] && PW_ARGS+=(--grep "$GREP_PATTERN")

PW_EXIT=0
(cd "$CODE_PATH" && npx playwright "${PW_ARGS[@]}") || PW_EXIT=$?

# Append the history record (append-only; create parent dir if needed).
mkdir -p "$(dirname "$HISTORY_PATH")" 2>/dev/null || true
NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
HISTORY_ENTRY=$(jq -nc \
  --arg ts "$NOW_ISO" --arg trigger "$REASON" \
  --argjson surfaces "$SURFACES_PLANNED" --argjson viewports "$VIEWPORTS" \
  --arg tb "$TRIGGERED_BY" --arg gp "$GREP_PATTERN" '
  { timestamp: $ts, trigger: $trigger, surfaces: $surfaces,
    viewports: $viewports, triggered_by: $tb,
    grep_pattern: (if $gp == "" then null else $gp end) }')
if ! echo "$HISTORY_ENTRY" >> "$HISTORY_PATH" 2>/dev/null; then
  add_warning "history_append_failed: could not append to $HISTORY_PATH"
fi

jq -nc \
  --argjson pe "$PW_EXIT" --argjson sp "$SURFACES_PLANNED" \
  --argjson blanket "$BLANKET" --arg hp "$HISTORY_PATH" \
  --argjson he "$HISTORY_ENTRY" --argjson w "$WARNINGS" '
  { stage: "execute",
    updated: ($pe == 0),
    playwright_exit: $pe,
    surfaces_updated: $sp,
    blanket: $blanket,
    history_path: $hp,
    history_entry: $he,
    warnings: $w }'

[ "$PW_EXIT" -ne 0 ] && exit 1
exit 0
