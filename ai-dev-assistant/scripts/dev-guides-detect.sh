#!/usr/bin/env bash
# dev-guides-detect.sh — deterministic Stage-1 dev-guides detection.
#
# Usage: dev-guides-detect.sh <task_folder> --phase <research|design|implement|complete>
#
# Stage 1 of the framework's two-stage guide detection. It is deterministic and
# ALWAYS emits two things, regardless of task content:
#
#   1. A phase-aware methodology floor — plugin methodology guides EVERY task at
#      this phase should load, with NO keyword gating. This is the anti-bypass
#      floor: Stage 2 (the guides-matcher agent) can add to it and rank it but
#      can never zero it out. Preserves the v4.0.0 "no bypass-by-declaration"
#      guarantee.
#        research             → tdd-workflow, solid, dry-patterns
#        design and later     → + library-first
#        implement / complete → + quality-gates
#
#   2. Catalog candidates — dev-guides topics whose distinctive terms appear in
#      the task's accumulated artifact prose. Matched against the cached
#      dev-guides-navigator catalog: the `content` field of dev-guides-cache.json
#      (the full llms.txt markdown). The cache is located by the dasherized-cwd
#      derivation documented in dev-guides-navigator's references/cache-format.md,
#      with a ~/.claude/projects/*/memory/ glob fallback.
#
# The previous hardcoded 5-row keyword table is gone — it produced spurious
# matches ("quality" → quality-gates, "test" → tdd-workflow) and could be
# silently zeroed. The phase-aware floor replaces it deterministically.
#
# Output (consumed by phase commands; feeds the `dev-guides-load` audit
# per references/gate-audit-schema.md):
#   {
#     "phase": "research|design|implement|complete",
#     "methodology_floor": ["plugin:tdd-workflow", ...],
#     "catalog_candidates": [
#       {"slug":"nextjs/routing","title":"Routing","description":"...","triggered_by":["routing"]}
#     ],
#     "scanned_files": [".../task.md", ".../alignment.md"],
#     "warnings": []
#   }
#
# Cache missing or has no `.content` → catalog_candidates: [] +
# warnings: ["catalog_cache_missing"]. The floor still emits; the caller's
# preflight suggests running /dev-guides-navigator to populate the cache.

set -uo pipefail

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
TASK_FOLDER=""
PHASE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --phase) PHASE="${2:-}"; shift 2 ;;
    --phase=*) PHASE="${1#*=}"; shift ;;
    -*) echo "dev-guides-detect.sh: unknown flag '$1'" >&2; exit 2 ;;
    *) [ -n "$TASK_FOLDER" ] || TASK_FOLDER="$1"; shift ;;
  esac
done

if [ -z "$TASK_FOLDER" ]; then
  echo "usage: dev-guides-detect.sh <task_folder> --phase <research|design|implement|complete>" >&2
  exit 2
fi
case "$PHASE" in
  research|design|implement|complete) : ;;
  "") echo "dev-guides-detect.sh: --phase is required" >&2; exit 2 ;;
  *) echo "dev-guides-detect.sh: invalid --phase '$PHASE' (research|design|implement|complete)" >&2; exit 2 ;;
esac

# ---------------------------------------------------------------------------
# 1. Methodology floor — phase-aware, no keyword gating
# ---------------------------------------------------------------------------
FLOOR=("plugin:tdd-workflow" "plugin:solid" "plugin:dry-patterns")
case "$PHASE" in
  design) FLOOR+=("plugin:library-first") ;;
  implement|complete) FLOOR+=("plugin:library-first" "plugin:quality-gates") ;;
esac

# ---------------------------------------------------------------------------
# 2. Gather artifact prose
# ---------------------------------------------------------------------------
SCANNED_FILES=()
SCANNED_CONTENT=""
for f in task.md alignment.md research.md architecture.md implementation.md; do
  PF="$TASK_FOLDER/$f"
  if [[ -f "$PF" ]]; then
    SCANNED_FILES+=("$PF")
    if [[ "$f" == "task.md" ]]; then
      # Strip the YAML frontmatter block before scanning — its keys (e.g.
      # `blocks:`, a task-dependency field) are not prose and collide with
      # catalog topic terms (a `…/blocks` catalog topic).
      SCANNED_CONTENT+=$'\n'"$(awk '
        NR==1 && /^---[[:space:]]*$/ { fm=1; next }
        fm && /^---[[:space:]]*$/    { fm=0; next }
        !fm                          { print }
      ' "$PF")"
    else
      SCANNED_CONTENT+=$'\n'"$(cat "$PF")"
    fi
  fi
done
# Multi-file detail: research/<topic>.md (split research, v4.10.0+) and
# architecture/<component>.md (split design). Scanned when present.
for d in research architecture; do
  if [[ -d "$TASK_FOLDER/$d" ]]; then
    for sub in "$TASK_FOLDER/$d"/*.md; do
      [[ -f "$sub" ]] || continue
      SCANNED_FILES+=("$sub")
      SCANNED_CONTENT+=$'\n'"$(cat "$sub")"
    done
  fi
done
LC_CONTENT=$(printf '%s' "$SCANNED_CONTENT" | tr '[:upper:]' '[:lower:]')

WARNINGS=()
[[ -n "$LC_CONTENT" ]] || WARNINGS+=("no_artifacts")

# ---------------------------------------------------------------------------
# 3. Locate the dev-guides-navigator catalog cache
#    (dasherized-cwd derivation; glob fallback mirrors the navigator pre-compact hook)
# ---------------------------------------------------------------------------
DASHED=$(printf '%s' "$PWD" | sed 's/[^a-zA-Z0-9]/-/g')
CACHE_FILE="$HOME/.claude/projects/${DASHED}/memory/dev-guides-cache.json"
if [[ ! -f "$CACHE_FILE" ]]; then
  for dir in "$HOME"/.claude/projects/*/memory/; do
    if [[ -f "${dir}dev-guides-cache.json" ]]; then
      CACHE_FILE="${dir}dev-guides-cache.json"
      break
    fi
  done
fi

CATALOG_CONTENT=""
if [[ -f "$CACHE_FILE" ]]; then
  CATALOG_CONTENT=$(jq -r '.content // empty' "$CACHE_FILE" 2>/dev/null || true)
fi
if [[ -z "$CATALOG_CONTENT" ]]; then
  WARNINGS+=("catalog_cache_missing")
fi

# ---------------------------------------------------------------------------
# 4. Match catalog topics against artifact prose
# ---------------------------------------------------------------------------
CAND_ARR=()
if [[ -n "$CATALOG_CONTENT" && -n "$LC_CONTENT" ]]; then
  while IFS= read -r line; do
    # Catalog topic lines look like:
    #   - [Title](https://camoa.github.io/dev-guides/<slug>/): N guides — description
    case "$line" in
      '- ['*'](http'*')'*) : ;;
      *) continue ;;
    esac
    title="${line#*[}"; title="${title%%]*}"
    url="${line#*](}"; url="${url%%)*}"
    case "$url" in
      *dev-guides/*) : ;;
      *) continue ;;
    esac
    slug="${url#*dev-guides/}"
    slug="${slug%/}"
    [[ -n "$slug" && "$slug" != http* ]] || continue
    desc="${line#*): }"
    case "$desc" in
      *' — '*) desc="${desc#* — }" ;;
    esac

    # Distinctive terms: the slug tail (hyphens→spaces) and the lowercased title.
    # Both are sanitized to [a-z0-9 ] (every other char → space, runs squeezed)
    # so a term is always safe to interpolate into a regex — catalog titles can
    # carry "." "(" ":" etc.
    tail="${slug##*/}"
    tail_spaced="${tail//-/ }"
    title_lc=$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]')

    matched_terms=()
    for raw_term in "$tail_spaced" "$title_lc"; do
      term=$(printf '%s' "$raw_term" | tr -c 'a-z0-9\n' ' ' | tr -s ' ')
      term="${term# }"; term="${term% }"
      [[ -n "$term" ]] || continue
      variants=("$term")
      if [[ "$term" != *" "* ]]; then
        # single token — also try its singular/plural so "view" matches "views"
        if [[ "$term" == *s && ${#term} -gt 3 ]]; then
          variants+=("${term%s}")
        else
          variants+=("${term}s")
        fi
      fi
      for v in "${variants[@]}"; do
        if printf '%s' "$LC_CONTENT" | grep -Eq "(^|[^a-z0-9])${v}([^a-z0-9]|\$)"; then
          matched_terms+=("$term")
          break
        fi
      done
    done

    if [[ ${#matched_terms[@]} -gt 0 ]]; then
      TERMS_JSON=$(printf '%s\n' "${matched_terms[@]}" | sort -u | jq -R . | jq -s -c .)
      CAND_ARR+=("$(jq -nc \
        --arg slug "$slug" --arg title "$title" --arg desc "$desc" --argjson tb "$TERMS_JSON" \
        '{slug: $slug, title: $title, description: $desc, triggered_by: $tb}')")
    fi
  done <<< "$CATALOG_CONTENT"
fi

# ---------------------------------------------------------------------------
# 5. Emit
# ---------------------------------------------------------------------------
FLOOR_JSON=$(printf '%s\n' "${FLOOR[@]}" | jq -R . | jq -s -c .)

if [[ ${#CAND_ARR[@]} -gt 0 ]]; then
  CANDIDATES_JSON=$(printf '%s\n' "${CAND_ARR[@]}" | jq -s -c '.')
else
  CANDIDATES_JSON='[]'
fi

if [[ ${#SCANNED_FILES[@]} -gt 0 ]]; then
  FILES_JSON=$(printf '%s\n' "${SCANNED_FILES[@]}" | jq -R . | jq -s -c .)
else
  FILES_JSON='[]'
fi

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  WARN_JSON=$(printf '%s\n' "${WARNINGS[@]}" | jq -R . | jq -s -c .)
else
  WARN_JSON='[]'
fi

jq -nc \
  --arg phase "$PHASE" \
  --argjson floor "$FLOOR_JSON" \
  --argjson candidates "$CANDIDATES_JSON" \
  --argjson files "$FILES_JSON" \
  --argjson warnings "$WARN_JSON" '
  {
    phase: $phase,
    methodology_floor: $floor,
    catalog_candidates: $candidates,
    scanned_files: $files,
    warnings: $warnings
  }'
