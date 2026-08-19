#!/usr/bin/env bash
# baseline-manager.sh — bootstrap / regenerate visual-regression baselines
# (ai-dev-assistant v4.13.0, Task C).
#
# Usage:
#   baseline-manager.sh --bootstrap              --registry <path> --codepath <path> [opts]
#   baseline-manager.sh --update-baselines <why> --registry <path> --codepath <path> [opts]
#
#   opts: [--exact-surface <id>] [--grep <pattern>] [--confirmed]
#         [--triggered-by <value>]
#
# TWO-STAGE CONFIRM MODEL (Task C D-impl-8)
# -----------------------------------------
# Framework shell scripts are non-interactive. The "user must confirm every
# baseline write" invariant is enforced structurally:
#
#   PLAN mode    (no --confirmed) — prints the EXACT surfaces/viewports that
#                WOULD be (re)captured as JSON, writes nothing, exits 0.
#   EXECUTE mode (--confirmed)    — runs Playwright with `--update-snapshots`
#                and appends baseline-history.jsonl.
#
# The calling command (/setup-visual-regression, /validate:visual-regression)
# runs PLAN mode first, shows the user the plan + the literal [y]/[n] prompt,
# and only on [y] re-invokes with --confirmed. No baseline can be written
# without an explicit user [y] — the script cannot be coaxed past PLAN mode
# without the flag the command sets only after the prompt.
#
# SCOPING: --exact-surface vs --grep
# ----------------------------------
# --exact-surface <id> scopes to exactly ONE surface, and PLAN and EXECUTE
# honour it identically: PLAN keeps the single spec stem equal to <id>, EXECUTE
# derives its Playwright --grep from that same <id>. Prefer it.
#
# --grep <pattern> is the older interface and is asymmetric by nature: PLAN
# matches the pattern against the spec-file STEM, while Playwright matches it
# against the joined test TITLE PATH
# (`tests/visual/couple.spec.ts:27:7 › couple visual regression › …`). A pattern
# such as `couple` therefore sweeps up `couples-list` in both stages while
# `blanket` stays false, so the blanket warning never fires. It is still
# accepted, but whenever a --grep pattern plans more than one surface the
# output carries a `grep_overmatch` warning naming every surface matched, so
# the breadth is visible before the operator confirms. `couple\b` scopes both
# stages correctly; `^couple$` plans one surface and then yields Playwright
# "No tests found".
#
# Either flag makes the run selective — blanket updates require a run with
# neither, flagged `blanket: true`.
#
# Playwright runs HOST-SIDE. The DDEV site is reached via DDEV_PRIMARY_URL.
#
# VIEWPORTS: the registry passed via --registry is AUTHORITATIVE. Its top-level
# `viewports:` block is the same list /setup-visual-regression wrote the
# Playwright projects from, so it states the matrix independently of how the
# config happens to express it. playwright.config.ts is scanned only as a
# fallback, because a config that builds its projects programmatically
# (`VIEWPORTS.map(vp => ({ name: `visual-chromium-${vp.name}` }))`) behaves
# identically to a literal one and yields zero regex matches — which used to
# leave `viewports: []` and abort EXECUTE. When the fallback is used the output
# says so (`viewports_source`, plus a warning); when neither source yields a
# viewport the failure names both. The --registry path also locates
# baseline-history.jsonl (a sibling of the registry) and is echoed into
# the output.
#
# OUTCOME, NOT INTENT (baseline-history.jsonl)
# -------------------------------------------
# baseline-history.jsonl is the only durable provenance record this gate has,
# so an entry records what HAPPENED, not what was planned. EXECUTE checksums
# every baseline PNG under tests/visual/ before and after the Playwright run
# and writes `surfaces_updated` from the files whose checksum actually moved,
# alongside `playwright_exit` and an `updated` boolean. A run Playwright
# rejected outright ("Error: No tests found", exit 1, zero bytes written) is
# therefore distinguishable in the log from a rebaseline that wrote — which is
# the whole discipline that keeps a stored-baseline gate auditable.
#
# A plan matching ZERO surfaces is an error, not a no-op: a rebaseline that
# reports success having written nothing is exactly the false green this script
# exists to prevent. An invalid --grep pattern is reported as invalid,
# separately from a valid pattern that matched nothing.
#
# Playwright's console output goes to a log file, never to stdout: stdout
# carries this script's JSON result object and nothing else, so `jq` can parse
# it. On a non-zero exit the tail of that log is surfaced as a warning.
#
# Exit codes: 0 success (plan or execute) · 1 the --update-snapshots run failed
#             · 2 validation / setup error (a plan of zero surfaces included).

set -uo pipefail

MODE=""
REASON=""
REGISTRY_PATH=""
CODE_PATH=""
GREP_PATTERN=""
EXACT_SURFACE=""
CONFIRMED=false
TRIGGERED_BY=""

# Known baseline-recreation triggers (advisory — unknown reasons warn, not block).
KNOWN_TRIGGERS="intentional-ui-change prod-db-refresh upstream-design-update dependency-update framework-update fixture-change bootstrap"

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
    --exact-surface)
      if [ "$#" -ge 2 ] && [ -n "${2:-}" ]; then EXACT_SURFACE="$2"; shift 2
      else err "--exact-surface requires a value"; exit 2; fi
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
if [ -n "$EXACT_SURFACE" ] && [ -n "$GREP_PATTERN" ]; then
  err "--exact-surface and --grep are mutually exclusive — --exact-surface scopes to one surface, --grep to a pattern"; exit 2
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
{ [ -n "$GREP_PATTERN" ] || [ -n "$EXACT_SURFACE" ]; } && BLANKET=false

# ─── plan: which surfaces would be (re)captured ──────────────────────────────
# Surface stems = tests/visual/*.spec.ts basenames. --exact-surface keeps the
# one stem equal to <id>; --grep keeps stems matching the pattern as an
# extended regex (see the --grep asymmetry note in the header).
#
# Validate the pattern ONCE, against empty input, before it is used to filter
# anything. grep exits 0 on a match, 1 on no match, and >1 on an error such as
# an unparseable regex — the old filter discarded that status, so an INVALID
# pattern skipped every stem and read exactly like a pattern that legitimately
# matched nothing. The two cases get different messages. (Input comes from a
# redirect, never a pipe: a writer feeding `grep -q` gets SIGPIPE when grep
# stops at the first match, which pipefail then reports as 141.)
if [ -n "$GREP_PATTERN" ]; then
  GREP_PROBE_RC=0
  grep -qE -- "$GREP_PATTERN" </dev/null >/dev/null 2>&1 || GREP_PROBE_RC=$?
  if [ "$GREP_PROBE_RC" -gt 1 ]; then
    err "--grep '$GREP_PATTERN': not a valid extended regular expression (grep exit $GREP_PROBE_RC)"
    exit 2
  fi
fi

SURFACES_PLANNED='[]'
while IFS= read -r spec; do
  [ -z "$spec" ] && continue
  stem=$(basename "$spec" .spec.ts)
  if [ -n "$EXACT_SURFACE" ]; then
    [ "$stem" = "$EXACT_SURFACE" ] || continue
  elif [ -n "$GREP_PATTERN" ]; then
    STEM_RC=0
    grep -qE -- "$GREP_PATTERN" <<<"$stem" >/dev/null 2>&1 || STEM_RC=$?
    if [ "$STEM_RC" -gt 1 ]; then
      err "--grep '$GREP_PATTERN': grep failed on stem '$stem' (exit $STEM_RC)"
      exit 2
    fi
    [ "$STEM_RC" -eq 0 ] || continue
  fi
  SURFACES_PLANNED=$(jq -c --arg s "$stem" '. + [$s]' <<<"$SURFACES_PLANNED")
done < <(find "$CODE_PATH/tests/visual" -maxdepth 1 -type f -name '*.spec.ts' 2>/dev/null | sort)

# --exact-surface names one surface: an id with no spec file is a setup error,
# not an empty plan, so say which id and stop before EXECUTE can be reached.
if [ -n "$EXACT_SURFACE" ] && [ "$(jq 'length' <<<"$SURFACES_PLANNED")" -eq 0 ]; then
  err "--exact-surface '$EXACT_SURFACE': no $CODE_PATH/tests/visual/$EXACT_SURFACE.spec.ts"
  exit 2
fi

# Planning zero surfaces is an error, not an empty no-op. EXECUTE used to emit
# updated:false with playwright_exit:0 and exit 0 here — a rebaseline reporting
# success having written nothing. Name the pattern that matched no surface, or
# say the suite is empty when there was no pattern at all, and stop in BOTH
# stages so the operator never confirms a run that cannot write.
if [ "$(jq 'length' <<<"$SURFACES_PLANNED")" -eq 0 ]; then
  if [ -n "$GREP_PATTERN" ]; then
    err "--grep '$GREP_PATTERN' is a valid pattern but matched no surface in $CODE_PATH/tests/visual — nothing would be rebaselined"
  else
    err "no *.spec.ts surfaces in $CODE_PATH/tests/visual — nothing to rebaseline (run /setup-visual-regression first)"
  fi
  exit 2
fi

# A --grep pattern that plans more than one surface is the asymmetry the header
# describes: `blanket` stays false, so the blanket "this updates ALL baselines"
# warning never fires even though several surfaces are being rebaselined. Name
# every surface matched so the breadth is visible before the operator confirms.
if [ -n "$GREP_PATTERN" ] && [ "$(jq 'length' <<<"$SURFACES_PLANNED")" -gt 1 ]; then
  add_warning "grep_overmatch: --grep '$GREP_PATTERN' matched $(jq 'length' <<<"$SURFACES_PLANNED") surfaces ($(jq -r 'join(", ")' <<<"$SURFACES_PLANNED")) — all of them will be rebaselined; use --exact-surface <id> to scope to one"
fi

# ─── viewport matrix: registry first, playwright.config.ts as fallback ───────
# The registry's top-level `viewports:` block is authoritative. Parsed with
# python3 + PyYAML, the same reader scripts/fm-helpers.sh uses for task
# frontmatter — no new dependency, and python3 being absent degrades to the
# fallback rather than failing.
PW_CONFIG="$CODE_PATH/playwright.config.ts"
VIEWPORTS='[]'
VIEWPORTS_SOURCE="none"

read_registry_viewports() {
  [ -f "$REGISTRY_PATH" ] || { echo '[]'; return 0; }
  command -v python3 >/dev/null 2>&1 || { echo '[]'; return 0; }
  python3 -c '
import sys, json
try:
    import yaml
except ImportError:
    print("[]"); sys.exit(0)
try:
    with open(sys.argv[1]) as fh:
        data = yaml.safe_load(fh.read())
except Exception:
    print("[]"); sys.exit(0)
names = []
vps = data.get("viewports") if isinstance(data, dict) else None
if isinstance(vps, dict):
    vps = list(vps.keys())
if isinstance(vps, list):
    for entry in vps:
        name = entry.get("name") if isinstance(entry, dict) else entry
        if isinstance(name, str) and name.strip() and name.strip() not in names:
            names.append(name.strip())
print(json.dumps(names))
' "$REGISTRY_PATH" 2>/dev/null || echo '[]'
}

REGISTRY_VIEWPORTS=$(read_registry_viewports)
jq -e 'type == "array"' <<<"$REGISTRY_VIEWPORTS" >/dev/null 2>&1 || REGISTRY_VIEWPORTS='[]'

if [ "$(jq 'length' <<<"$REGISTRY_VIEWPORTS")" -gt 0 ]; then
  VIEWPORTS="$REGISTRY_VIEWPORTS"
  VIEWPORTS_SOURCE="registry"
else
  # Fallback — scrape literal `name: 'visual-chromium-…'` strings out of the
  # config. This finds nothing in a config that builds its projects
  # programmatically, which is exactly why the registry is tried first.
  if [ -f "$PW_CONFIG" ]; then
    while IFS= read -r vp; do
      [ -z "$vp" ] && continue
      VIEWPORTS=$(jq -c --arg v "$vp" '. + [$v]' <<<"$VIEWPORTS")
    done < <(grep -oE "name:[[:space:]]*['\"]visual-chromium-[A-Za-z0-9_-]+['\"]" "$PW_CONFIG" 2>/dev/null \
              | grep -oE 'visual-chromium-[A-Za-z0-9_-]+' | sed 's/^visual-chromium-//' | sort -u)
  fi
  if [ "$(jq 'length' <<<"$VIEWPORTS")" -gt 0 ]; then
    VIEWPORTS_SOURCE="playwright-config"
    add_warning "viewports_from_config_fallback: $REGISTRY_PATH declared no top-level viewports: — fell back to scraping visual-chromium-* project names out of playwright.config.ts"
  fi
fi

HISTORY_PATH="$(dirname "$REGISTRY_PATH")/baseline-history.jsonl"

emit_plan() {
  jq -nc \
    --arg mode "$MODE" --arg reason "$REASON" --arg gp "$GREP_PATTERN" \
    --arg es "$EXACT_SURFACE" --argjson blanket "$BLANKET" \
    --argjson sp "$SURFACES_PLANNED" \
    --argjson vp "$VIEWPORTS" --arg vs "$VIEWPORTS_SOURCE" --arg hp "$HISTORY_PATH" \
    --arg tb "$TRIGGERED_BY" --argjson w "$WARNINGS" '
    { stage: "plan", mode: $mode, reason: $reason,
      grep_pattern: $gp,
      exact_surface: (if $es == "" then null else $es end),
      blanket: $blanket,
      surfaces_planned: $sp, viewports: $vp, viewports_source: $vs,
      history_path: $hp, triggered_by: $tb, warnings: $w }'
}

# PLAN MODE — no --confirmed: print the plan, write nothing.
if [ "$CONFIRMED" != true ]; then
  emit_plan
  exit 0
fi

# ─── EXECUTE MODE ────────────────────────────────────────────────────────────
# (A plan of zero surfaces already exited 2 above — EXECUTE is never reached
# with nothing to do.)

# --project flags, one per viewport in the matrix resolved above. Project names
# follow the setup convention visual-chromium-<viewport>, so the same matrix
# scopes the run whichever source it came from.
PROJ_ARGS=()
while IFS= read -r p; do
  [ -z "$p" ] && continue
  PROJ_ARGS+=("--project" "visual-chromium-$p")
done < <(jq -r '.[]' <<<"$VIEWPORTS")

# Refuse to run unscoped: with no viewports, a bare
# `playwright test --update-snapshots` with no --project flag would regenerate
# snapshots for ALL projects — including the e2e-chromium suite. Abort instead, naming both
# sources so the message points at the real cause.
if [ "${#PROJ_ARGS[@]}" -eq 0 ]; then
  add_warning "no_visual_projects: no viewports from either source — $REGISTRY_PATH has no top-level viewports: block, and $PW_CONFIG has no visual-chromium-* project names to scrape (a config that builds its projects programmatically cannot be scraped; declare viewports: in the registry). Refusing to run --update-snapshots unscoped"
  jq -nc --argjson w "$WARNINGS" '{stage:"execute",updated:false,playwright_exit:0,warnings:$w}'
  exit 2
fi

PW_ARGS=(test --update-snapshots "${PROJ_ARGS[@]}")
if [ -n "$EXACT_SURFACE" ]; then
  # Playwright matches --grep against the joined title path
  # (`tests/visual/couple.spec.ts:27:7 › couple visual regression › …`), not the
  # stem — `^couple$` matches nothing there. Anchor on the spec filename
  # instead, preceded by start-of-string or a non-identifier character, so
  # `hero` cannot also select `home-hero.spec.ts`.
  ESCAPED_SURFACE=$(printf '%s' "$EXACT_SURFACE" | sed 's/[]\.^$*+?()[{}|\\\/]/\\&/g')
  PW_ARGS+=(--grep "(^|[^A-Za-z0-9_-])${ESCAPED_SURFACE}\\.spec\\.ts")
elif [ -n "$GREP_PATTERN" ]; then
  PW_ARGS+=(--grep "$GREP_PATTERN")
fi

# ─── observe what actually gets written ──────────────────────────────────────
# Playwright's exit code says the RUN succeeded; it does not say which baseline
# images changed. Checksum every PNG under tests/visual/ before and after, and
# read `surfaces_updated` off the files whose checksum moved. Portable digest —
# shasum ships with macOS, sha256sum with coreutils; without either, the
# observation degrades to "unknown" and says so rather than guessing.
SUM_CMD=()
if command -v shasum >/dev/null 2>&1; then SUM_CMD=(shasum -a 256)
elif command -v sha256sum >/dev/null 2>&1; then SUM_CMD=(sha256sum)
fi

# <outfile> ← "<checksum> <path>" per baseline PNG. `find -printf` and `stat -c`
# are GNU-only, so neither is used.
checksum_pngs() {
  : > "$1"
  [ "${#SUM_CMD[@]}" -gt 0 ] || return 0
  while IFS= read -r png; do
    [ -z "$png" ] && continue
    sum=$("${SUM_CMD[@]}" "$png" 2>/dev/null | awk '{print $1}')
    [ -n "$sum" ] && printf '%s %s\n' "$sum" "$png" >> "$1"
  done < <(find "$CODE_PATH/tests/visual" -type f -name '*.png' 2>/dev/null | sort)
}

# A snapshot PNG lives in <stem>.spec.ts-snapshots/, so the surface is the
# parent directory name with the suffixes stripped. Anything laid out
# differently falls back to the image's own basename.
stem_for_png() {
  d=$(basename "$(dirname "$1")")
  d=${d%-snapshots}
  d=${d%.spec.ts}
  if [ -n "$d" ] && [ "$d" != "visual" ]; then printf '%s\n' "$d"
  else basename "$1" .png; fi
}

PNG_BEFORE="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/bm-before-$$.txt")"
PNG_AFTER="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/bm-after-$$.txt")"
checksum_pngs "$PNG_BEFORE"

# ─── run ─────────────────────────────────────────────────────────────────────
# Playwright's console output must NEVER reach stdout: stdout is this script's
# JSON result object, and console text in front of it makes the whole thing
# unparseable by jq. Both streams go to a log file, and PLAYWRIGHT_JSON_OUTPUT_NAME
# routes the json reporter to its own file, the same handling
# scripts/visual-regression-gate.sh uses on its Playwright call.
PW_LOG="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/bm-pwlog-$$.txt")"
PW_JSON_FILE="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/bm-pwjson-$$.json")"
PW_EXIT=0
( cd "$CODE_PATH" \
  && PLAYWRIGHT_HTML_OPEN=never PLAYWRIGHT_JSON_OUTPUT_NAME="$PW_JSON_FILE" \
     npx playwright "${PW_ARGS[@]}" --reporter=json >"$PW_LOG" 2>&1 ) || PW_EXIT=$?

# On failure the reason ("Error: No tests found" being the common one) is in the
# log and nowhere else, so carry it into the result rather than dropping it.
if [ "$PW_EXIT" -ne 0 ]; then
  PW_TAIL=$(grep -v '^[[:space:]]*$' "$PW_LOG" 2>/dev/null | tail -n 5 | tr '\n' ' ')
  add_warning "playwright_failed: exit $PW_EXIT — ${PW_TAIL:-no output captured}"
fi

checksum_pngs "$PNG_AFTER"

# Surfaces whose baseline images actually moved: checksum changed, file added,
# or file removed. Paths may contain spaces, so split on the FIRST space only —
# the checksum never contains one.
SURFACES_UPDATED='[]'
CHANGED_PNGS=0
if [ "${#SUM_CMD[@]}" -gt 0 ]; then
  while IFS= read -r changed; do
    [ -z "$changed" ] && continue
    CHANGED_PNGS=$((CHANGED_PNGS + 1))
    st=$(stem_for_png "$changed")
    [ -z "$st" ] && continue
    SURFACES_UPDATED=$(jq -c --arg s "$st" 'if index($s) then . else . + [$s] end' <<<"$SURFACES_UPDATED")
  done < <(awk '
    NR==FNR { p = substr($0, index($0, " ") + 1); b[p] = $1; next }
    { p = substr($0, index($0, " ") + 1); a[p] = $1
      if (!(p in b) || b[p] != $1) print p }
    END { for (p in b) if (!(p in a)) print p }
  ' "$PNG_BEFORE" "$PNG_AFTER" 2>/dev/null | sort)
else
  add_warning "no_checksum_tool: neither shasum nor sha256sum is in PATH — surfaces_updated could not be observed and is reported empty"
fi
rm -f "$PNG_BEFORE" "$PNG_AFTER" "$PW_LOG" "$PW_JSON_FILE"

# `updated` is an OBSERVATION, not a restatement of the exit code: a clean exit
# that moved no image did not rebaseline anything.
UPDATED=false
[ "$PW_EXIT" -eq 0 ] && [ "$CHANGED_PNGS" -gt 0 ] && UPDATED=true
if [ "$PW_EXIT" -eq 0 ] && [ "$CHANGED_PNGS" -eq 0 ] && [ "${#SUM_CMD[@]}" -gt 0 ]; then
  add_warning "no_baseline_changed: Playwright exited 0 but no baseline PNG under $CODE_PATH/tests/visual changed — nothing was rebaselined"
fi

# Append the history record (append-only; create parent dir if needed). The
# entry carries the OUTCOME — playwright_exit, updated, and the surfaces
# observed to change — beside the plan that was attempted, so a failed run is
# never indistinguishable from a successful rebaseline in the provenance log.
mkdir -p "$(dirname "$HISTORY_PATH")" 2>/dev/null || true
NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
HISTORY_ENTRY=$(jq -nc \
  --arg ts "$NOW_ISO" --arg trigger "$REASON" \
  --argjson planned "$SURFACES_PLANNED" --argjson updated_s "$SURFACES_UPDATED" \
  --argjson pe "$PW_EXIT" --argjson upd "$UPDATED" --argjson cp "$CHANGED_PNGS" \
  --argjson viewports "$VIEWPORTS" \
  --arg tb "$TRIGGERED_BY" --arg gp "$GREP_PATTERN" \
  --arg es "$EXACT_SURFACE" --arg vs "$VIEWPORTS_SOURCE" '
  { timestamp: $ts, trigger: $trigger,
    playwright_exit: $pe, updated: $upd,
    surfaces_planned: $planned, surfaces_updated: $updated_s,
    baseline_images_changed: $cp,
    viewports: $viewports, viewports_source: $vs, triggered_by: $tb,
    exact_surface: (if $es == "" then null else $es end),
    grep_pattern: (if $gp == "" then null else $gp end) }')
if ! echo "$HISTORY_ENTRY" >> "$HISTORY_PATH" 2>/dev/null; then
  add_warning "history_append_failed: could not append to $HISTORY_PATH"
fi

jq -nc \
  --argjson pe "$PW_EXIT" --argjson sp "$SURFACES_PLANNED" \
  --argjson su "$SURFACES_UPDATED" --argjson upd "$UPDATED" \
  --argjson cp "$CHANGED_PNGS" \
  --argjson blanket "$BLANKET" --arg hp "$HISTORY_PATH" \
  --arg es "$EXACT_SURFACE" --argjson vp "$VIEWPORTS" --arg vs "$VIEWPORTS_SOURCE" \
  --argjson he "$HISTORY_ENTRY" --argjson w "$WARNINGS" '
  { stage: "execute",
    updated: $upd,
    playwright_exit: $pe,
    surfaces_planned: $sp,
    surfaces_updated: $su,
    baseline_images_changed: $cp,
    exact_surface: (if $es == "" then null else $es end),
    viewports: $vp,
    viewports_source: $vs,
    blanket: $blanket,
    history_path: $hp,
    history_entry: $he,
    warnings: $w }'

[ "$PW_EXIT" -ne 0 ] && exit 1
exit 0
