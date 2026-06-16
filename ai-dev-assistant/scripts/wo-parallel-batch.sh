#!/usr/bin/env bash
# wo-parallel-batch.sh — the deterministic, zero-model scheduling kernel for the parallel
# work-order conductor. From a work-orders/ dir it computes the READY set and selects a MAXIMAL
# DISJOINT-FILE BATCH: the largest prefix (greedy, ascending wo-id) of ready work-orders whose
# declared file-sets are provably disjoint, so they can build CONCURRENTLY in separate worktrees
# without a code-merge conflict. Safety > parallelism: when disjointness cannot be PROVEN, the WO
# is deferred — never speculatively batched.
#
# READ-ONLY. It NEVER writes/renames a *.HALT marker, never touches a run.json, never changes a WO
# status, never calls git / gh / merge / PR / the status-write subcommand. It only reads + emits JSON.
#
# Inputs it reuses (no re-invention):
#   - status + terminal: delegated to `wo-reconcile-table.sh <dir>` — the authority kernel that
#     encodes the EXACT terminal rule (wo-NN.HALT present OR run.json halted==true). Re-deriving it
#     here would risk drift from that single source of truth, so we shell out for {wo_id,status,
#     terminal} and parse only the two extra things the table does not carry (blocked_by edges +
#     the `## Files to touch` body section).
#   - file extraction: the `## Files to touch` markdown-section parse mirrors the established
#     worktree-signals.sh awk idiom (backticked path preferred, else first token of a `- `/`* ` item).
#
# Usage:  wo-parallel-batch.sh <work-orders-dir> [--max N]   (default N = 8)
#
# Ready rule (mirrors the work-order-loop): a WO is ELIGIBLE iff it is NOT terminal AND
#   ( status == ready ) OR ( status == needs_rework ) OR
#   ( status == blocked AND EVERY blocked_by dep is a WO whose status == done ).
# A blocked WO with a dep that is missing/not-done is NOT eligible (fail-closed).
#
# Disjoint-file batch (greedy, ascending wo-id, CONSERVATIVE overlap):
#   Each declared entry is reduced to its LITERAL PREFIX (the substring before the first glob
#   metachar * ? [ ). Two entries OVERLAP if: exact (raw) equality, OR either literal-prefix is
#   empty (a leading glob ⇒ matches everything), OR the prefixes are equal, OR one prefix is a
#   path-ancestor of the other (segment-aware: `src` is an ancestor of `src/foo/bar.php`, but NOT
#   of `src-other`). When in doubt ⇒ overlap. A WO that declares NO files cannot be proven disjoint
#   ⇒ it overlaps everything: it may only run SOLO (added solely to an empty batch), else deferred;
#   a warning is always emitted for it.
#
# Output: one compact JSON object to stdout:
#   { schema_version:"1.0", work_orders_dir, ready_total, max,
#     batch:[{wo_id, files:[...]}], deferred:[{wo_id, conflicts_with:[...], reason}], warnings:[...] }
#   reason ∈ file_overlap | no_files_declared | batch_full.
# One compact stderr line: `wo-parallel-batch ready=<n> batch=<n> deferred=<n> max=<n>`.
# Exit 0 normally (empty ready set ⇒ empty batch). Exit 2 on a missing/nonexistent <work-orders-dir>.

set -uo pipefail

# --- locate plugin root + sibling kernel ------------------------------------
PLUGIN_ROOT="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
RECONCILE="${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/scripts/wo-reconcile-table.sh"
[ -f "$RECONCILE" ] || RECONCILE="$PLUGIN_ROOT/scripts/wo-reconcile-table.sh"

# --- arg parsing ------------------------------------------------------------
DIR=""; MAX="8"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --max) MAX="${2:-8}"; shift 2 || shift ;;
    --*)   shift ;;
    *)     [ -z "$DIR" ] && DIR="$1"; shift ;;
  esac
done
# normalize --max: non-negative integer, else fall back to 8 (never crash on garbage input).
case "$MAX" in (*[!0-9]*|'') MAX="8" ;; esac

# --- usage error (the ONLY exit-2 path) -------------------------------------
USAGE_ERR=""
if   [ -z "$DIR" ];   then USAGE_ERR="missing_work_orders_dir"
elif [ ! -d "$DIR" ]; then USAGE_ERR="work_orders_dir_missing"
fi
if [ -n "$USAGE_ERR" ]; then
  jq -nc --arg e "$USAGE_ERR" '{error:$e}'
  printf 'wo-parallel-batch error=%s\n' "$USAGE_ERR" >&2
  exit 2
fi

# --- derive a WO's id the SAME way wo-reconcile-table.sh does ----------------
# (frontmatter `id` when it is the bare sidecar grammar wo-NN; else the leading wo-NN of filename.)
fm_scalar() {
  awk -v key="$2" '
    NR==1 && /^---[[:space:]]*$/ {in_fm=1; next}
    in_fm && /^---[[:space:]]*$/ {exit}
    in_fm && index($0, key":") == 1 {
      v = substr($0, length(key) + 2)
      sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
      sub(/^"/, "", v); sub(/"$/, "", v); sub(/^'\''/, "", v); sub(/'\''$/, "", v)
      print v; exit
    }
  ' "$1" 2>/dev/null
}
wo_id_of() {
  local f="$1" id_fm base
  id_fm="$(fm_scalar "$f" id)"
  if [[ "$id_fm" =~ ^wo-[0-9]+$ ]]; then printf '%s' "$id_fm"; return 0; fi
  base="$(basename "$f" .md)"
  if [[ "$base" =~ ^(wo-[0-9]+) ]]; then printf '%s' "${BASH_REMATCH[1]}"; else printf '%s' "$base"; fi
}

# --- extract blocked_by deps (normalized to the wo-NN discriminator) --------
# Handles the contract flow form `blocked_by: [local:task#wo-02, ...]` and a YAML block list.
extract_blocked_by() {
  awk '
    NR==1 && /^---[[:space:]]*$/ {fm=1; next}
    fm && /^---[[:space:]]*$/ {exit}
    fm && /^blocked_by:/ {
      grab=1; line=$0
      while (match(line, /wo-[0-9]+/)) { print substr(line,RSTART,RLENGTH); line=substr(line,RSTART+RLENGTH) }
      next
    }
    fm && grab==1 {
      if ($0 ~ /^[[:space:]]*-/) {
        line=$0
        while (match(line, /wo-[0-9]+/)) { print substr(line,RSTART,RLENGTH); line=substr(line,RSTART+RLENGTH) }
        next
      } else if ($0 ~ /^[^[:space:]]/) { grab=0 }
    }
  ' "$1" 2>/dev/null
}

# --- extract the `## Files to touch` body section ---------------------------
# Mirrors worktree-signals.sh: for each `- `/`* ` list item, prefer the first backticked path,
# else the first whitespace-delimited token. Stops at the next `## ` header.
extract_files() {
  awk '
    /^##[[:space:]]+Files to touch[[:space:]]*$/ {inb=1; next}
    inb && /^##[[:space:]]/ {inb=0}
    inb && /^[[:space:]]*[-*][[:space:]]+/ {
      line=$0
      sub(/^[[:space:]]*[-*][[:space:]]+/, "", line)
      if (match(line, /`[^`]+`/)) {
        print substr(line, RSTART+1, RLENGTH-2)
      } else {
        gsub(/^[[:space:]]+/, "", line)
        n=split(line, a, /[[:space:]]+/)
        if (n>=1 && a[1] != "") print a[1]
      }
    }
  ' "$1" 2>/dev/null
}

# --- conservative overlap primitives ----------------------------------------
normalize_path() {   # canonicalize $1 so syntactic variants of the SAME path compare equal:
  # strip CR, strip leading `./` (repeatable), collapse `//`→`/`, drop `/./` segments,
  # strip a single trailing `/`. Pure-string (no filesystem touch); keeps the kernel READ-ONLY.
  local s="${1%$'\r'}"
  while [ "${s#./}" != "$s" ]; do s="${s#./}"; done          # leading ./ (one or many)
  while [ "${s//\/\//\/}" != "$s" ]; do s="${s//\/\//\/}"; done   # // → /
  while [ "${s//\/.\//\/}" != "$s" ]; do s="${s//\/.\//\/}"; done # /./ → /
  [ "$s" != "/" ] && s="${s%/}"                              # trailing / (but keep bare "/")
  printf '%s' "$s"
}
literal_prefix() {   # echo the substring of $1 before the first glob metachar * ? [ {
  local s="$1" out="" i ch
  for ((i=0; i<${#s}; i++)); do
    ch="${s:i:1}"
    case "$ch" in '*'|'?'|'['|'{') break ;; esac     # `{` ⇒ brace-glob: prefix stops here (conservative)
    out+="$ch"
  done
  printf '%s' "$out"
}
paths_overlap() {    # 0 (overlap) / 1 (provably disjoint) for raw entries $1 $2
  local a b pa pb
  a="$(normalize_path "$1")"; b="$(normalize_path "$2")"   # normalize BEFORE any comparison
  [ "$a" = "$b" ] && return 0                       # exact equality (post-normalization)
  pa="$(literal_prefix "$a")"; pb="$(literal_prefix "$b")"
  pa="${pa%/}"; pb="${pb%/}"                         # strip a single trailing slash
  [ -z "$pa" ] && return 0                           # leading glob ⇒ matches everything
  [ -z "$pb" ] && return 0
  [ "$pa" = "$pb" ] && return 0                       # same literal prefix
  case "$pb" in "$pa"/*) return 0 ;; esac             # pa ancestor of pb (segment-aware)
  case "$pa" in "$pb"/*) return 0 ;; esac             # pb ancestor of pa
  return 1
}

# --- pull status + terminal from the authority kernel -----------------------
TABLE='[]'
[ -f "$RECONCILE" ] && TABLE="$(bash "$RECONCILE" "$DIR" 2>/dev/null || echo '[]')"
printf '%s' "$TABLE" | jq -e 'type=="array"' >/dev/null 2>&1 || TABLE='[]'

declare -A ST_STATUS ST_TERMINAL
while IFS=$'\t' read -r wid wstatus wterm; do
  [ -n "$wid" ] || continue
  ST_STATUS["$wid"]="$wstatus"
  ST_TERMINAL["$wid"]="$wterm"
done < <(printf '%s' "$TABLE" | jq -r '.[] | [.wo_id, .status, (.terminal|tostring)] | @tsv' 2>/dev/null)

# --- map wo_id -> file path, blocked_by, declared files ---------------------
declare -A WO_PATH WO_BLOCKED_BY WO_FILES
ALL_IDS=()
while IFS= read -r f; do
  [ -f "$f" ] || continue
  wid="$(wo_id_of "$f")"
  WO_PATH["$wid"]="$f"
  ALL_IDS+=("$wid")
  bb="$(extract_blocked_by "$f" | grep -v '^[[:space:]]*$' | sort -u || true)"
  WO_BLOCKED_BY["$wid"]="$bb"
  ff="$(extract_files "$f" | grep -v '^[[:space:]]*$' || true)"
  WO_FILES["$wid"]="$ff"
done < <(find "$DIR" -maxdepth 1 -name 'wo-*.md' -type f 2>/dev/null | sort)

# --- compute the ELIGIBLE (ready) set ---------------------------------------
is_eligible() {  # $1 = wo_id
  local wid="$1" status term dep
  status="${ST_STATUS[$wid]:-${WO_STATUS_FALLBACK:-unknown}}"
  term="${ST_TERMINAL[$wid]:-false}"
  [ "$term" = "true" ] && return 1                    # terminal ⇒ never eligible
  case "$status" in
    ready|needs_rework) return 0 ;;
    blocked)
      local deps="${WO_BLOCKED_BY[$wid]:-}"
      [ -z "$deps" ] && return 1                       # blocked w/ no resolvable deps ⇒ not eligible
      while IFS= read -r dep; do
        [ -n "$dep" ] || continue
        [ "${ST_STATUS[$dep]:-missing}" = "done" ] || return 1   # any dep not done ⇒ not eligible
      done <<< "$deps"
      return 0 ;;
    *) return 1 ;;
  esac
}

ELIGIBLE=()
while IFS= read -r wid; do
  [ -n "$wid" ] || continue
  is_eligible "$wid" && ELIGIBLE+=("$wid")
done < <(printf '%s\n' "${ALL_IDS[@]+"${ALL_IDS[@]}"}" | grep -v '^[[:space:]]*$' | sort -V -u)
READY_TOTAL="${#ELIGIBLE[@]}"

# --- greedy disjoint-file batch selection -----------------------------------
BATCH_F="$(mktemp)"; DEFER_F="$(mktemp)"; WARN_F="$(mktemp)"
trap 'rm -f "$BATCH_F" "$DEFER_F" "$WARN_F"' EXIT
: > "$BATCH_F"; : > "$DEFER_F"; : > "$WARN_F"

BATCH_IDS=(); BATCH_FILES=()       # parallel arrays: id + newline-joined declared files

add_warn()  { jq -nc --arg w "$1" '$w' >> "$WARN_F"; }
add_batch() { # $1 wo_id, $2 files (newline string, may be empty)
  BATCH_IDS+=("$1"); BATCH_FILES+=("$2")
  local -a arr=(); [ -n "$2" ] && mapfile -t arr <<< "$2"
  jq -nc --arg wo "$1" '$ARGS.positional as $f | {wo_id:$wo, files:$f}' \
    --args ${arr[@]+"${arr[@]}"} >> "$BATCH_F"
}
add_defer() { # $1 wo_id, $2 reason, rest = conflicts_with ids
  local wo="$1" reason="$2"; shift 2
  jq -nc --arg wo "$wo" --arg r "$reason" \
    '$ARGS.positional as $c | {wo_id:$wo, conflicts_with:$c, reason:$r}' \
    --args "$@" >> "$DEFER_F"
}

for wid in ${ELIGIBLE[@]+"${ELIGIBLE[@]}"}; do
  files="${WO_FILES[$wid]:-}"

  # cap reached ⇒ defer everything still pending (deterministic, no overlap needed).
  if [ "${#BATCH_IDS[@]}" -ge "$MAX" ]; then
    add_defer "$wid" "batch_full"
    continue
  fi

  # no declared files ⇒ overlaps everything; solo-only.
  if [ -z "$files" ]; then
    add_warn "$wid declares no files in '## Files to touch'; can only run solo"
    if [ "${#BATCH_IDS[@]}" -eq 0 ]; then
      add_batch "$wid" ""
    else
      add_defer "$wid" "no_files_declared" ${BATCH_IDS[@]+"${BATCH_IDS[@]}"}
    fi
    continue
  fi

  # normal WO: collect every current batch member whose file-set overlaps.
  local_cand=(); mapfile -t local_cand <<< "$files"
  CONFLICTS=()
  i=0
  while [ "$i" -lt "${#BATCH_IDS[@]}" ]; do
    mfiles="${BATCH_FILES[$i]}"
    if [ -z "$mfiles" ]; then
      CONFLICTS+=("${BATCH_IDS[$i]}")               # solo no-files member overlaps everything
    else
      mapfile -t local_mem <<< "$mfiles"
      hit=0
      for c in "${local_cand[@]}"; do
        for m in "${local_mem[@]}"; do
          if paths_overlap "$c" "$m"; then hit=1; break; fi
        done
        [ "$hit" -eq 1 ] && break
      done
      [ "$hit" -eq 1 ] && CONFLICTS+=("${BATCH_IDS[$i]}")
    fi
    i=$((i+1))
  done

  if [ "${#CONFLICTS[@]}" -eq 0 ]; then
    add_batch "$wid" "$files"
  else
    add_defer "$wid" "file_overlap" "${CONFLICTS[@]}"
  fi
done

# --- emit the consolidated JSON ---------------------------------------------
jq -nc \
  --arg dir "$DIR" --argjson ready "$READY_TOTAL" --argjson max "$MAX" \
  --slurpfile batch "$BATCH_F" --slurpfile deferred "$DEFER_F" --slurpfile warnings "$WARN_F" \
  '{schema_version:"1.0", work_orders_dir:$dir, ready_total:$ready, max:$max,
    batch:$batch, deferred:$deferred, warnings:$warnings}'

BATCH_N="${#BATCH_IDS[@]}"
DEFER_N="$(jq -s 'length' "$DEFER_F" 2>/dev/null || echo 0)"
printf 'wo-parallel-batch ready=%s batch=%s deferred=%s max=%s\n' \
  "$READY_TOTAL" "$BATCH_N" "$DEFER_N" "$MAX" >&2
exit 0
