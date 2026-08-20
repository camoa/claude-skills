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
#   --css-root          directory to scan for CSS @media queries (Path 2, and the
#                       Path 1 cross-check). Defaults to <codePath>.
#
# Three-path waterfall (research/breakpoint-derivation.md):
#   Path 1 — apply --breakpoints-from (recipe-supplied list). A framework recipe
#            drives this; without it the kernel skips straight to Path 2.
#            The CSS scan still runs, as a CROSS-CHECK only: a hand-maintained
#            breakpoints file drifts freely from the compiled stylesheet and
#            nothing forces the two to agree, so any width the CSS tests but the
#            file does not declare (and the reverse) is named on stderr. The
#            declared list still wins — the cross-check warns, never overrides.
#   Path 2 — infer from CSS @media queries under --css-root (framework-neutral).
#   Path 3 — ask the user — NOT done here (interactive); the command falls through.
#
# Output: a JSON array on stdout, suitable for registry.yml `viewports:`. Each
# entry: {name, width, height, _source} and, from Path 2, `_rule_count`.
# Underscore-prefixed keys are private annotations for the calling command's
# display label — the command strips them before writing the registry.
# A human-readable account of what the scan saw goes to stderr, never stdout.
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

# Most viewports Path 2 will propose. More than this and a suite spends its
# budget re-capturing near-identical layouts.
MAX_VIEWPORTS=4
# Most CSS files read. The cap exists so a vendor-heavy tree does not turn the
# scan into a full-repo read.
MAX_CSS_FILES=200
# Widths outside this band are not viewports anyone captures at.
MIN_USABLE_WIDTH=320
MAX_USABLE_WIDTH=2560
# Widths this close together are the same layout decision expressed twice.
CLUSTER_PX=50

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

SCAN_DIR="${CSS_ROOT:-$CODE_PATH}"

# Canonical height per width band (research/breakpoint-derivation.md).
height_for_width() {
  local w="$1"
  if   [ "$w" -le 480 ];  then echo 812
  elif [ "$w" -le 1024 ]; then echo 1024
  elif [ "$w" -le 1440 ]; then echo 900
  else echo 1080; fi
}

# ─── CSS @media scan ──────────────────────────────────────────────────────────
# Shared by Path 2 (which derives the matrix from it) and by Path 1 (which only
# cross-checks against it). Emits one `<kind> <width_px> <rule_count>` line per
# observed width, ascending, where <kind> is:
#
#   min — a `min-width` / `width >= x` condition. A LAYOUT breakpoint: the point
#         at which the page is told to lay itself out differently.
#   max — a `max-width` / `width <= x` condition. Usually NOT a layout
#         breakpoint; it is far more often a content- or container-sizing
#         ceiling. Reported so the operator can see it, never fed to the matrix.
#
# Pooling the two was a real defect: container `max-width` values entered the
# breakpoint pool as equals with layout `min-width` values.
#
# <rule_count> is how many `@media` rules test that width. It is the whole point
# of the report: on one measured theme 1024px carried 39 rules and 1536px carried
# 4, and treating them as equals over-tests one end and under-tests the other.
#
# Units: px, rem and em are all read. A theme expressing every breakpoint in rem
# was invisible to the px-only scan this replaces. rem and em in a media
# condition both resolve against the ROOT font size, assumed here to be the 16px
# initial value — which is what a browser uses for `em` in a media query
# regardless of any author rule. ASSUMPTION: a theme that changes the root font
# size (`html { font-size: 62.5% }` and friends) converts differently, and this
# scan will be wrong about it. That is out of scope for a stylesheet-text scan;
# supply --breakpoints-from for such a theme rather than trusting these numbers.
#
# Both media condition spellings are read: the classic `(min-width: 768px)` and
# the range syntax `(width >= 768px)` / `(768px <= width)`, which are the same
# statement and are both live in shipped CSS.
css_scan() {
  local dir="$1"
  [ -d "$dir" ] || return 0

  # The sort is load-bearing, not cosmetic. `find` gives no ordering guarantee,
  # and on a machine where `find` resolves to a parallel implementation (bfs)
  # three runs of the previous unsorted, capped-with-head selection took three
  # DIFFERENT 200-file subsets of the same tree — so the derived viewport matrix,
  # and every baseline named after it, changed run to run for no reason anyone
  # could see. Sorting before capping makes the cap fall in the same place every
  # time, on every machine.
  local list
  list=$(find "$dir" -type f -name '*.css' -not -path '*/node_modules/*' 2>/dev/null \
    | LC_ALL=C sort \
    | awk -v cap="$MAX_CSS_FILES" 'NR <= cap')
  [ -n "$list" ] || return 0

  printf '%s\n' "$list" \
    | while IFS= read -r f; do [ -n "$f" ] && cat "$f"; done \
    | awk '
        # Strip /* */ comments first, carrying the open state across lines. This
        # has to happen BEFORE the record split below, because a commented-out
        # rule contains the "{" that split would break it on — and a breakpoint
        # someone deliberately commented out would otherwise be counted.
        {
          line = $0; out = ""
          while (1) {
            if (inc) {
              p = index(line, "*/")
              if (p == 0) { line = ""; break }
              line = substr(line, p + 2); inc = 0
            } else {
              p = index(line, "/*")
              if (p == 0) { out = out line; break }
              out = out substr(line, 1, p - 1)
              line = substr(line, p + 2); inc = 1
            }
          }
          print out
        }
      ' \
    | awk '
        function px_of(tok,   num, mult) {
          match(tok, /[0-9]+(\.[0-9]+)?/)
          num = substr(tok, RSTART, RLENGTH) + 0
          # "rem" contains "em", so test px first, then rem, then em.
          mult = (tok ~ /px/) ? 1 : 16
          return int(num * mult + 0.5)
        }
        function harvest(text, pattern, kind,   t, tok, nxt) {
          t = text
          while (match(t, pattern)) {
            # Take the token AND the cursor before calling px_of: its own
            # match() overwrites RSTART/RLENGTH, and reading them afterwards
            # advances the cursor to the wrong place and re-counts the rule.
            tok = substr(t, RSTART, RLENGTH)
            nxt = RSTART + RLENGTH
            t = substr(t, nxt)
            print kind, px_of(tok)
          }
        }
        # RS="{" makes every record end where a block opens, so the media
        # condition is the tail of the record. Records stay small even on a
        # minified stylesheet.
        BEGIN {
          RS = "{"
          NUM  = "[0-9]+(\\.[0-9]+)?"
          UNIT = "(px|rem|em)"
        }
        {
          rec = $0
          gsub(/[ \t\r\n]+/, " ", rec)
          last = ""
          t = rec
          while (match(t, /@media/)) {
            t = substr(t, RSTART)
            last = t
            t = substr(t, 7)
          }
          if (last == "") next
          # Patterns are STRINGS, not /regex/ literals: awk evaluates a regex
          # literal in an argument position as a match against $0 and passes the
          # 0-or-1 result, so every scan silently found nothing.
          harvest(last, "min-width[ ]*:[ ]*" NUM UNIT,      "min")
          harvest(last, "max-width[ ]*:[ ]*" NUM UNIT,      "max")
          harvest(last, "width[ ]*(>=|>)[ ]*" NUM UNIT,     "min")
          harvest(last, "width[ ]*(<=|<)[ ]*" NUM UNIT,     "max")
          harvest(last, NUM UNIT "[ ]*(<=|<)[ ]*width",     "min")
          harvest(last, NUM UNIT "[ ]*(>=|>)[ ]*width",     "max")
        }
      ' \
    | awk -v lo="$MIN_USABLE_WIDTH" -v hi="$MAX_USABLE_WIDTH" '
        ($1 == "min" || $1 == "max") && $2 >= lo && $2 <= hi { n[$1 " " $2]++ }
        END { for (k in n) print k, n[k] }
      ' \
    | sort -k1,1 -k2,2n
}

# Collapse widths within CLUSTER_PX of each other. The representative is the
# OBSERVED width in the cluster carrying the most @media rules (ties go to the
# smaller width), and the cluster's rule counts add up behind it. It is never a
# computed centre: the previous version emitted the middle value of the cluster,
# which is a width that no @media rule in the stylesheet tests, so the suite
# captured at a size the theme has no opinion about.
cluster_widths() {
  awk -v span="$CLUSTER_PX" '
    NR == 1 { last = $1; best_w = $1; best_c = $2; sum = $2; next }
    {
      if ($1 - last <= span) {
        last = $1; sum += $2
        if ($2 > best_c) { best_w = $1; best_c = $2 }
      } else {
        print best_w, sum
        last = $1; best_w = $1; best_c = $2; sum = $2
      }
    }
    END { if (NR > 0) print best_w, sum }
  '
}

# Keep at most MAX_VIEWPORTS widths, chosen ACROSS the range: the smallest and
# largest observed widths are always kept, and the remaining slots go to the
# widths carrying the most @media rules. Taking the first N of an ascending sort
# dropped every desktop width by construction, whatever else the scan got right.
select_widths() {
  awk -v k="$MAX_VIEWPORTS" '
    { w[NR] = $1; c[NR] = $2; n = NR }
    END {
      if (n <= k) { for (i = 1; i <= n; i++) print w[i], c[i]; exit }
      sel[1] = 1; sel[n] = 1; picked = 2
      while (picked < k) {
        best = 0
        for (i = 1; i <= n; i++) {
          if (i in sel) continue
          if (best == 0 || c[i] > c[best] || (c[i] == c[best] && w[i] < w[best])) best = i
        }
        if (best == 0) break
        sel[best] = 1; picked++
      }
      for (i = 1; i <= n; i++) if (i in sel) print w[i], c[i]
    }
  '
}

plural_rules() {
  if [ "$1" = "1" ]; then echo "1 rule"; else echo "$1 rules"; fi
}

SCAN_RAW=$(css_scan "$SCAN_DIR")
CSS_MIN=$(printf '%s\n' "$SCAN_RAW" | awk '$1 == "min" { print $2, $3 }' | sort -n)
CSS_MAX=$(printf '%s\n' "$SCAN_RAW" | awk '$1 == "max" { print $2, $3 }' | sort -n)

report_scan() {
  [ -n "$CSS_MIN" ] || return 0
  echo "derive-viewport-matrix: CSS @media rules test these layout widths (min-width):" >&2
  while IFS=' ' read -r w c; do
    [ -n "$w" ] || continue
    printf '  %spx — %s\n' "$w" "$(plural_rules "$c")" >&2
  done <<EOF
$CSS_MIN
EOF
  if [ -n "$CSS_MAX" ]; then
    echo "derive-viewport-matrix: max-width conditions seen (content/container ceilings, NOT used as breakpoints):" >&2
    while IFS=' ' read -r w c; do
      [ -n "$w" ] || continue
      printf '  %spx — %s\n' "$w" "$(plural_rules "$c")" >&2
    done <<EOF
$CSS_MAX
EOF
  fi
}

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
  BP_ERR="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/dvm-bp-$$.err")"
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
      # Guard the ENTRY TYPE first. `.name` on a non-object (a bare string in the
      # array, say) raises "Cannot index string with name", which aborts the whole
      # filter — so one malformed entry used to discard every valid one, and the
      # `|| echo []` below hid both the error and the loss.
      | select(type == "object")
      | select((.name | type) == "string" and (.width | type) == "number")
      | (.width | floor) as $w
      | { name: .name,
          width: $w,
          height: ((if (.height | type) == "number" then (.height | floor) else ($w | hb) end)),
          _source: "breakpoints" }
    ]
    # dedup by width, first occurrence wins, input order preserved
    | reduce .[] as $v ([]; if any(.[]; .width == $v.width) then . else . + [$v] end)
  ' "$BREAKPOINTS_FROM" 2>"$BP_ERR" || echo '[]')
  if [ -s "$BP_ERR" ]; then
    # Do not discard the reason. A filter that aborts here returns an empty matrix
    # and the caller cannot tell that from "the file declared no breakpoints".
    printf 'derive-viewport-matrix: --breakpoints-from parse reported: %s\n' \
      "$(tr '\n' ' ' < "$BP_ERR")" >&2
  fi
  rm -f "$BP_ERR"

  if [ "$(jq 'length' <<<"$RESULT" 2>/dev/null || echo 0)" -gt 0 ]; then
    # Cross-check the declared set against what the stylesheets actually test.
    # Advisory only: the declared list is still what gets used.
    if [ -n "$CSS_MIN" ]; then
      DECLARED=$(jq -r '.[].width' <<<"$RESULT" 2>/dev/null)
      # A width converted from rem can land a pixel off a hand-written one, so
      # allow 1px of slack before calling two numbers a disagreement.
      MISSING=$(awk 'NR == FNR { d[FNR] = $1; nd = FNR; next }
                     {
                       for (i = 1; i <= nd; i++) if ($1 - d[i] <= 1 && d[i] - $1 <= 1) next
                       printf "%spx (%s rule%s)\n", $1, $2, ($2 == 1 ? "" : "s")
                     }' <(printf '%s\n' "$DECLARED") <(printf '%s\n' "$CSS_MIN"))
      UNTESTED=$(awk 'NR == FNR { c[FNR] = $1; nc = FNR; next }
                      {
                        for (i = 1; i <= nc; i++) if ($1 - c[i] <= 1 && c[i] - $1 <= 1) next
                        printf "%spx\n", $1
                      }' <(printf '%s\n' "$CSS_MIN") <(printf '%s\n' "$DECLARED"))
      if [ -n "$MISSING" ] || [ -n "$UNTESTED" ]; then
        echo "derive-viewport-matrix: the breakpoints file and the CSS disagree." >&2
        echo "  Nothing keeps a hand-maintained breakpoints file in step with a compiled stylesheet, so treat the file as a claim, not a fact." >&2
        if [ -n "$MISSING" ]; then
          echo "  Tested by @media rules but absent from the breakpoints file:" >&2
          printf '%s\n' "$MISSING" | sed 's|^|    |' >&2
        fi
        if [ -n "$UNTESTED" ]; then
          echo "  Declared in the breakpoints file but no @media rule tests it:" >&2
          printf '%s\n' "$UNTESTED" | sed 's|^|    |' >&2
        fi
        echo "  Using the declared set. Reconcile the two before trusting the baselines." >&2
      fi
    fi
    echo "$RESULT"
    exit 0
  fi
  echo "derive-viewport-matrix: --breakpoints-from yielded no usable entries: $BREAKPOINTS_FROM" >&2
  echo "[]"
  exit 2
fi

# ─── Path 2: CSS @media scan (framework-neutral) ──────────────────────────────

report_scan

if [ -z "$CSS_MIN" ]; then
  if [ -n "$CSS_MAX" ]; then
    echo "derive-viewport-matrix: the CSS has max-width conditions but no min-width ones, so it states no layout breakpoint to capture at" >&2
  else
    echo "derive-viewport-matrix: no breakpoints input and no usable CSS @media queries found" >&2
  fi
  echo "[]"
  exit 3
fi

WIDTHS=()
COUNTS=()
# (portable read loop — `mapfile` is bash 4+; macOS ships bash 3.2)
while IFS=' ' read -r w c; do
  [ -n "$w" ] && { WIDTHS+=("$w"); COUNTS+=("$c"); }
done < <(printf '%s\n' "$CSS_MIN" | cluster_widths | select_widths)

RESULT='[]'
CHOSEN=""
idx=0
while [ "$idx" -lt "${#WIDTHS[@]}" ]; do
  w="${WIDTHS[$idx]}"
  c="${COUNTS[$idx]}"
  # The name is DERIVED FROM THE WIDTH and says so. These names key project
  # names and baseline filenames downstream, and the fixed `mobile tablet
  # desktop wide` list this replaces matched neither the theme's own breakpoint
  # names nor any registry — it just asserted four categories the CSS never
  # mentioned. A name that comes from a breakpoints file (Path 1) is kept as
  # written; a name invented here is the width and nothing else.
  name="w${w}"
  height=$(height_for_width "$w")
  RESULT=$(jq -c \
    --arg n "$name" --argjson w "$w" --argjson h "$height" --argjson r "$c" \
    '. + [{name: $n, width: $w, height: $h, _rule_count: $r, _source: "css-media"}]' <<<"$RESULT")
  CHOSEN="$CHOSEN $name(${c})"
  idx=$((idx + 1))
done

if [ "$(jq 'length' <<<"$RESULT")" -eq 0 ]; then
  echo "[]"
  exit 3
fi

echo "derive-viewport-matrix: proposing${CHOSEN} — name(rule count), smallest and largest widths always kept, the rest by where the @media rules concentrate" >&2
echo "$RESULT"
exit 0
