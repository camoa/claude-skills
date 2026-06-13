#!/usr/bin/env bash
# derive-viewport-matrix.sh — derive a visual-regression viewport matrix from
# project context (ai-dev-assistant v4.13.0, Task C).
#
# Usage: derive-viewport-matrix.sh <codePath> [--theme-name <name>]
#
#   <codePath>      absolute path to the Drupal project root
#   --theme-name    override custom-theme auto-detection
#
# Three-path waterfall (research/breakpoint-derivation.md):
#   Path 1 — parse <theme>.breakpoints.yml (custom theme, or radix contrib fallback)
#   Path 2 — infer from CSS @media (min-width|max-width) queries
#   Path 3 — ask the user — NOT done here (interactive); the command falls through
#
# Output: a JSON array on stdout, suitable for registry.yml `viewports:`. Each
# entry: {name, width, height, _source}. `_source` is a private annotation for
# the calling command's display label — the command strips it before writing
# the registry.
#
# Exit codes:
#   0 — viewports derived (Path 1 or Path 2). `_source` says which.
#   2 — a breakpoints.yml file was found but could not be parsed.
#   3 — nothing derivable (no breakpoints file AND no usable CSS @media). stdout
#       is `[]`; the command falls through to Path 3 (ask the user).
#   (exit 1 is reserved/unused — Path 1 failure simply continues to Path 2.)
#
# This script parses THEME.breakpoints.yml and CSS — NOT registry.yml. The
# registry is read by Claude (the command), per Task C D-impl-1.

set -uo pipefail

CODE_PATH="${1:-}"
THEME_NAME=""

if [ -z "$CODE_PATH" ]; then
  echo "derive-viewport-matrix: codePath required" >&2
  echo "[]"
  exit 3
fi
shift || true

while [ "$#" -gt 0 ]; do
  case "$1" in
    --theme-name)
      if [ "$#" -ge 2 ] && [ -n "${2:-}" ]; then THEME_NAME="$2"; shift 2
      else echo "derive-viewport-matrix: --theme-name requires a value" >&2; shift; fi
      ;;
    *) shift ;;
  esac
done

if [ ! -d "$CODE_PATH" ]; then
  echo "derive-viewport-matrix: codePath does not exist: $CODE_PATH" >&2
  echo "[]"
  exit 3
fi

# Resolve the docroot — Drupal may keep themes under web/ or at the root.
DOCROOT="$CODE_PATH/web"
[ -d "$DOCROOT/themes" ] || DOCROOT="$CODE_PATH"
CUSTOM_DIR="$DOCROOT/themes/custom"

# Canonical height per width band (research/breakpoint-derivation.md).
height_for_width() {
  local w="$1"
  if   [ "$w" -le 480 ];  then echo 812
  elif [ "$w" -le 1024 ]; then echo 1024
  elif [ "$w" -le 1440 ]; then echo 900
  else echo 1080; fi
}

# ─── Path 1: THEME.breakpoints.yml ───────────────────────────────────────────

BREAKPOINTS_FILE=""
SOURCE_LABEL=""

if [ -n "$THEME_NAME" ]; then
  CAND="$CUSTOM_DIR/$THEME_NAME/$THEME_NAME.breakpoints.yml"
  [ -f "$CAND" ] && { BREAKPOINTS_FILE="$CAND"; SOURCE_LABEL="breakpoints.yml"; }
elif [ -d "$CUSTOM_DIR" ]; then
  # Auto-detect: use the sole custom theme that ships a breakpoints file.
  FOUND=()
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    tn=$(basename "$d")
    [ -f "$d/$tn.breakpoints.yml" ] && FOUND+=("$d/$tn.breakpoints.yml")
  done < <(find "$CUSTOM_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
  if [ "${#FOUND[@]}" -eq 1 ]; then
    BREAKPOINTS_FILE="${FOUND[0]}"
    SOURCE_LABEL="breakpoints.yml"
  fi
fi

# Radix sub-theme fallback.
if [ -z "$BREAKPOINTS_FILE" ]; then
  RADIX="$DOCROOT/themes/contrib/radix/radix.breakpoints.yml"
  [ -f "$RADIX" ] && { BREAKPOINTS_FILE="$RADIX"; SOURCE_LABEL="breakpoints.yml"; }
fi

if [ -n "$BREAKPOINTS_FILE" ]; then
  # awk emits one TAB-separated line per breakpoint: weight<TAB>minwidth<TAB>name<TAB>fullkey
  # name = the segment of the breakpoint key after the last dot (mytheme.mobile → mobile).
  BP_LINES=$(awk '
    function flush() { if (cur != "") print w "\t" mw "\t" nm "\t" cur }
    /^[A-Za-z_][A-Za-z0-9_.-]*:[[:space:]]*$/ {
      flush()
      cur = $0; sub(/:[[:space:]]*$/, "", cur)
      n = split(cur, parts, ".")
      nm = parts[n]
      w = 999; mw = "none"
      next
    }
    /^[[:space:]]+weight:[[:space:]]*/ {
      line = $0; sub(/^[[:space:]]+weight:[[:space:]]*/, "", line)
      w = line + 0
      next
    }
    /^[[:space:]]+mediaQuery:[[:space:]]*/ {
      line = $0
      if (match(line, /min-width:[[:space:]]*[0-9]+/)) {
        seg = substr(line, RSTART, RLENGTH)
        sub(/min-width:[[:space:]]*/, "", seg)
        mw = seg + 0
      }
      next
    }
    END { flush() }
  ' "$BREAKPOINTS_FILE" 2>/dev/null)

  if [ -z "$BP_LINES" ]; then
    echo "derive-viewport-matrix: $BREAKPOINTS_FILE has no parseable breakpoints" >&2
    echo "[]"
    exit 2
  fi

  # Build the JSON array, sorted by weight, skipping breakpoints with no
  # min-width, deduplicating by resolved width.
  RESULT='[]'
  SEEN_WIDTHS=" "
  while IFS=$'\t' read -r weight mw name fullkey; do
    [ -z "$name" ] && continue
    [ "$mw" = "none" ] && continue
    if [ "$mw" -eq 0 ] 2>/dev/null; then
      width=375
    else
      width="$mw"
    fi
    case "$SEEN_WIDTHS" in *" $width "*) continue ;; esac
    SEEN_WIDTHS="$SEEN_WIDTHS$width "
    height=$(height_for_width "$width")
    RESULT=$(jq -c \
      --arg n "$name" --argjson w "$width" --argjson h "$height" \
      --arg s "$SOURCE_LABEL:$fullkey" \
      '. + [{name: $n, width: $w, height: $h, _source: $s}]' <<<"$RESULT")
  done < <(printf '%s\n' "$BP_LINES" | sort -n -k1,1)

  if [ "$(jq 'length' <<<"$RESULT")" -gt 0 ]; then
    echo "$RESULT"
    exit 0
  fi
  # All breakpoints lacked a min-width — fall through to Path 2.
fi

# ─── Path 2: CSS @media scan ─────────────────────────────────────────────────

CSS_WIDTHS=""
if [ -d "$CUSTOM_DIR" ]; then
  CSS_WIDTHS=$(find "$CUSTOM_DIR" -name '*.css' -not -path '*/node_modules/*' 2>/dev/null \
    | head -200 \
    | xargs grep -hoE '(min-width|max-width)[[:space:]]*:[[:space:]]*[0-9]+px' 2>/dev/null \
    | grep -oE '[0-9]+' \
    | awk '$1 >= 320 && $1 <= 2560' \
    | sort -n | uniq)
fi

if [ -z "$CSS_WIDTHS" ]; then
  echo "derive-viewport-matrix: no breakpoints.yml and no usable CSS @media queries found" >&2
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
