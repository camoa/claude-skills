#!/usr/bin/env bash
# derive-viewport-matrix.sh — derive a visual-regression viewport matrix from
# framework-neutral inputs (ai-dev-assistant v4.13.0, Task C).
#
# Usage: derive-viewport-matrix.sh <codePath> [--breakpoints-from <json>] [--css-root <dir>]
#
#   <codePath>          absolute path to the project root (default --css-root scan dir)
#   --breakpoints-from  JSON file holding a framework's already-parsed breakpoints:
#                       [ {name, width [, height]}, ... ]. The framework's process
#                       recipe RECONSTRUCTS this on the fly from its own native
#                       breakpoint source each run (e.g. one framework's recipe
#                       parses its design-system breakpoint file; another reads
#                       its utility-CSS config).
#                       The kernel ships NO framework-specific parser of its own — it
#                       only applies the neutral canonical-height band, dedup, and JSON
#                       shaping so the recipe never reimplements that logic.
#   --css-root          directory to scan for CSS @media queries (Path 2).
#                       Defaults to <codePath> (framework-neutral).
#
# Three-path waterfall (research/breakpoint-derivation.md):
#   Path 1 — apply --breakpoints-from (recipe-supplied list). A framework recipe
#            drives this; without it the kernel skips straight to Path 2.
#   Path 2 — infer from CSS @media (min-width|max-width) queries under --css-root
#            (framework-neutral).
#   Path 3 — ask the user — NOT done here (interactive); the command falls through.
#
# Output: a JSON array on stdout, suitable for registry.yml `viewports:`. Each
# entry: {name, width, height, _source}. `_source` is a private annotation for
# the calling command's display label — the command strips it before writing
# the registry.
#
# Exit codes:
#   0 — viewports derived (Path 1 or Path 2). `_source` says which.
#   2 — a --breakpoints-from file was given but unreadable / not a JSON array /
#       yielded no usable entries.
#   3 — nothing derivable (no breakpoints input AND no usable CSS @media). stdout
#       is `[]`; the command falls through to Path 3 (ask the user).
#   (exit 1 is reserved/unused — Path 1 absence simply continues to Path 2.)
#
# This kernel carries ZERO framework knowledge: it never auto-detects a theme,
# a docroot, or a native breakpoint file format. Those belong to the framework's
# process recipe, which feeds the result in via --breakpoints-from.

set -uo pipefail

CODE_PATH="${1:-}"
BREAKPOINTS_FROM=""
CSS_ROOT=""

if [ -z "$CODE_PATH" ]; then
  echo "derive-viewport-matrix: codePath required" >&2
  echo "[]"
  exit 3
fi
shift || true

while [ "$#" -gt 0 ]; do
  case "$1" in
    --breakpoints-from)
      if [ "$#" -ge 2 ] && [ -n "${2:-}" ]; then BREAKPOINTS_FROM="$2"; shift 2
      else echo "derive-viewport-matrix: --breakpoints-from requires a value" >&2; shift; fi
      ;;
    --css-root)
      if [ "$#" -ge 2 ] && [ -n "${2:-}" ]; then CSS_ROOT="$2"; shift 2
      else echo "derive-viewport-matrix: --css-root requires a value" >&2; shift; fi
      ;;
    *) shift ;;
  esac
done

# ─── Path 1: recipe-supplied breakpoints (--breakpoints-from) ─────────────────
# A framework recipe parsed its own native breakpoint source into a neutral
# [ {name, width [, height]}, ... ] list. The kernel applies the canonical
# height band, dedups by resolved width (first occurrence wins, input order
# preserved), and shapes the registry JSON. No framework-specific parsing here.
if [ -n "$BREAKPOINTS_FROM" ]; then
  if [ ! -f "$BREAKPOINTS_FROM" ]; then
    echo "derive-viewport-matrix: --breakpoints-from file not found: $BREAKPOINTS_FROM" >&2
    echo "[]"
    exit 2
  fi
  if ! jq -e 'type == "array"' "$BREAKPOINTS_FROM" >/dev/null 2>&1; then
    echo "derive-viewport-matrix: --breakpoints-from is not a JSON array: $BREAKPOINTS_FROM" >&2
    echo "[]"
    exit 2
  fi
  RESULT=$(jq -c '
    def hb: if   . <= 480  then 812
            elif . <= 1024 then 1024
            elif . <= 1440 then 900
            else 1080 end;
    [ .[]
      | select((.name | type) == "string" and (.width | type) == "number")
      | (.width | floor) as $w
      | { name: .name,
          width: $w,
          height: ((if (.height | type) == "number" then (.height | floor) else ($w | hb) end)),
          _source: "breakpoints" }
    ]
    # dedup by width, first occurrence wins, input order preserved
    | reduce .[] as $v ([]; if any(.[]; .width == $v.width) then . else . + [$v] end)
  ' "$BREAKPOINTS_FROM" 2>/dev/null || echo '[]')

  if [ "$(jq 'length' <<<"$RESULT" 2>/dev/null || echo 0)" -gt 0 ]; then
    echo "$RESULT"
    exit 0
  fi
  echo "derive-viewport-matrix: --breakpoints-from yielded no usable entries: $BREAKPOINTS_FROM" >&2
  echo "[]"
  exit 2
fi

# ─── Path 2: CSS @media scan (framework-neutral) ──────────────────────────────

# Canonical height per width band (research/breakpoint-derivation.md).
height_for_width() {
  local w="$1"
  if   [ "$w" -le 480 ];  then echo 812
  elif [ "$w" -le 1024 ]; then echo 1024
  elif [ "$w" -le 1440 ]; then echo 900
  else echo 1080; fi
}

# Scan root is --css-root when given, else the project root (framework-neutral).
SCAN_DIR="${CSS_ROOT:-$CODE_PATH}"
CSS_WIDTHS=""
if [ -d "$SCAN_DIR" ]; then
  CSS_WIDTHS=$(find "$SCAN_DIR" -name '*.css' -not -path '*/node_modules/*' 2>/dev/null \
    | head -200 \
    | xargs grep -hoE '(min-width|max-width)[[:space:]]*:[[:space:]]*[0-9]+px' 2>/dev/null \
    | grep -oE '[0-9]+' \
    | awk '$1 >= 320 && $1 <= 2560' \
    | sort -n | uniq)
fi

if [ -z "$CSS_WIDTHS" ]; then
  echo "derive-viewport-matrix: no breakpoints input and no usable CSS @media queries found" >&2
  echo "[]"
  exit 3
fi

# Cluster values within 50px — collapse a run of near-equal widths to its median.
CLUSTERED=$(printf '%s\n' "$CSS_WIDTHS" | awk '
  NR == 1 { lo = $1; hi = $1; vals[1] = $1; n = 1; next }
  {
    if ($1 - hi <= 50) { hi = $1; vals[++n] = $1 }
    else {
      print vals[int((n+1)/2)]
      lo = $1; hi = $1; n = 1; delete vals; vals[1] = $1
    }
  }
  END { if (n > 0) print vals[int((n+1)/2)] }
')

# Keep at most 4 clusters; name them by ascending size.
# (portable read loop — `mapfile` is bash 4+; macOS ships bash 3.2)
WIDTHS=()
while IFS= read -r w; do
  [ -n "$w" ] && WIDTHS+=("$w")
done < <(printf '%s\n' "$CLUSTERED" | sort -n | uniq | head -4)
NAMES=(mobile tablet desktop wide)
RESULT='[]'
idx=0
for w in "${WIDTHS[@]}"; do
  [ -z "$w" ] && continue
  name="${NAMES[$idx]:-vp$w}"
  height=$(height_for_width "$w")
  RESULT=$(jq -c \
    --arg n "$name" --argjson w "$w" --argjson h "$height" \
    '. + [{name: $n, width: $w, height: $h, _source: "css-media"}]' <<<"$RESULT")
  idx=$((idx + 1))
done

if [ "$(jq 'length' <<<"$RESULT")" -eq 0 ]; then
  echo "[]"
  exit 3
fi

echo "$RESULT"
exit 0
