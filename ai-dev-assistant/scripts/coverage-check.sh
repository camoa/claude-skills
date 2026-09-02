#!/usr/bin/env bash
# coverage-check.sh — every criterion is covered, every acceptance item reaches a criterion.
#
# Usage: coverage-check.sh <task_folder>
#        coverage-check.sh --parse-items <dir>      # TSV of every item under <dir>/*.md, for measurement
#
# Reads the contract through scripts/contract-resolve.sh (ids only) and every architecture/*.md
# under the task folder; the hub (architecture.md) is never read for items. Under each file's
# `## Acceptance criteria` heading (case-insensitive, outside code fences, up to the next H2) every
# checkbox line is an item carrying exactly one marker: `— serves: c<n>` or `— supports: <component>`.
#
# Reachability: an item serving an id in the contract reaches; an item supporting a component reaches
# when that component has a reaching item; the closure is a fixpoint, so a supports: cycle that never
# meets a serves: edge reaches nothing and every member is `unreached`, a self-edge included.
# Backward: an unticked criterion no item serves is `uncovered`; ticked ones are reported apart.
#
# `architecture/main.md` is skipped by name: it is the pre-v5.44 hub location, never a component. Fenced
# blocks (closed by the same delimiter character), HTML comments and indented code after a blank line
# are not parsed. A component whose heading lists nothing is `not_declared` too.
# stdout, one JSON object on exit 0:
#   { schema_version, status: pass | fail | not_applicable | not_run, passes: bool, reason,
#     source, criteria_count, items_count, components[], not_declared[], ticked[],
#     unreached: [{component, item, why}], uncovered: [id] }
# Two absent values: `not_run` (no ids, or no component files) is "nobody could look", printed on
# stderr, passes:false. `not_applicable` (ids exist, all ticked) is "looked, nothing applies", passes.
# Exit 2, nothing on stdout: the task folder is not a directory, a component file is unreadable or
# its basename is not [A-Za-z0-9._-], or a parser step failed.
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"
command -v jq >/dev/null 2>&1 || exit 2

# TSV: component \t kind(serves|supports|none|both) \t value \t item-text
parse_items() { # $1 dir
  local f name
  for f in "$1"/*.md; do
    [ -f "$f" ] || continue
    name="$(basename "$f" .md)"
    [ "$name" = "main" ] && continue   # the pre-v5.44 hub location; a hub is never a component
    case "$name" in *[!A-Za-z0-9._-]*) echo "coverage-check: component basename not [A-Za-z0-9._-]: $f" >&2; return 2 ;; esac
    [ -r "$f" ] || { echo "coverage-check: cannot read $f" >&2; return 2; }
    COMP="$name" awk '
      function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
      BEGIN { comp = ENVIRON["COMP"] }
      function emit(t,   ps, pp, kind, val, text, tail, ms, mp) {
        if (t == "") return
        nitems++
        text = t; t = ""
        ms = " — serves: "; mp = " — supports: "
        ps = index(text, ms); pp = index(text, mp)
        if (ps > 0 && pp > 0) { kind = "both"; val = ""; text = trim(substr(text, 1, (ps < pp ? ps : pp) - 1)) }
        else if (ps > 0) { kind = "serves"; tail = trim(substr(text, ps + length(ms))); val = tail; sub(/[[:space:]].*$/, "", val); text = trim(substr(text, 1, ps - 1)) }
        else if (pp > 0) { kind = "supports"; tail = trim(substr(text, pp + length(mp))); val = tail; sub(/[[:space:]].*$/, "", val); text = trim(substr(text, 1, pp - 1)) }
        else { kind = "none"; val = "" }
        printf "%s\t%s\t%s\t%s\n", comp, kind, val, text
      }
      /^[[:space:]]*(```|~~~)/ { c = substr(trim($0), 1, 1)
                  if (fence == "") fence = c; else if (fence == c) fence = ""
                  if (item != "") { emit(item); item = "" } ; next }
      fence != "" { next }
      /<!--/ && !/-->/ { comment = 1; if (item != "") { emit(item); item = "" } ; next }
      comment { if (/-->/) comment = 0; next }
      /<!--.*-->/ { next }
      /^[[:space:]]*$/ { blank = 1; if (item != "") { emit(item); item = "" } ; next }
      blank && /^(    |\t)/ { next }
      { blank = 0 }
      /^##[^#]/ { if (item != "") { emit(item); item = "" }
                  h = $0; sub(/^##[[:space:]]*/, "", h); h = tolower(trim(h))
                  insec = (h ~ /^acceptance criteria/) ? 1 : 0; if (insec) declared = 1; next }
      !insec { next }
      /^[[:space:]]*-[[:space:]]+\[[[:space:] xX]\][[:space:]]+/ { if (item != "") emit(item)
                  item = $0; sub(/^[[:space:]]*-[[:space:]]+\[[[:space:] xX]\][[:space:]]+/, "", item); next }
      /^[[:space:]]*-[[:space:]]+/ { if (item != "") { emit(item); item = "" } ; next }
      /[^[:space:]]/ { if (item != "") item = item " " trim($0); next }
      { if (item != "") { emit(item); item = "" } }
      END { if (item != "") emit(item); if (!declared || nitems == 0) printf "%s\tnot_declared\t\t\n", comp }
    ' < "$f" || return 2
  done
}

if [ "${1:-}" = "--parse-items" ]; then
  [ -d "${2:-}" ] || exit 2
  parse_items "$2" | awk -F'\t' '$2 != "not_declared"'
  exit "${PIPESTATUS[0]}"
fi

TASK="${1:?task folder required}"
[ -d "$TASK" ] || exit 2

emit() { # $1 status $2 passes $3 reason $4 source $5 payload-json(merged)
  jq -nc --arg st "$1" --argjson pa "$2" --arg r "$3" --arg src "$4" --argjson x "$5" '
    {schema_version:"1.0", status:$st, passes:$pa, reason:(if $r=="" then null else $r end),
     source:(if $src=="" then null else $src end)} + $x'
}

CR="$(bash "$HERE/contract-resolve.sh" "$TASK")" || exit 2
SRC="$(jq -r '.source // ""' <<<"$CR")"
if [ "$(jq -r .status <<<"$CR")" != "resolved" ]; then
  echo "coverage-check: not_run: no_ids — no criterion carries an — id: marker; run /scope on this task. Not a pass." >&2
  emit not_run false no_ids "" '{"criteria_count":0,"items_count":0,"components":[],"not_declared":[],"ticked":[],"unreached":[],"uncovered":[]}'; exit 0
fi
if ! ls "$TASK/architecture"/*.md >/dev/null 2>&1; then
  echo "coverage-check: not_run: no_components — no architecture/*.md under the task. Not a pass." >&2
  emit not_run false no_components "$SRC" "$(jq -c '{criteria_count:(.criteria|length),items_count:0,components:[],not_declared:[],ticked:[.criteria[]|select(.checked)|.id],unreached:[],uncovered:[]}' <<<"$CR")"; exit 0
fi

RAW="$(parse_items "$TASK/architecture")" || exit 2
ROWS="$(printf '%s' "$RAW" | jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t") | {component: .[0], kind: .[1], value: .[2], item: .[3]})')" || exit 2

jq -nc --argjson cr "$CR" --argjson rows "$ROWS" '
  ($cr.criteria | map(.id)) as $ids
  | ($cr.criteria | map(select(.checked) | .id)) as $ticked
  | ($cr.criteria | map(select(.checked | not) | .id)) as $open
  | ($rows | map(.component) | unique) as $components
  | ($rows | map(select(.kind == "not_declared")) | map(.component)) as $undeclared
  | ($rows | map(select(.kind != "not_declared"))) as $items
  # reaching components: fixpoint over supports: edges from components that serve a real id
  | ($items | map(select(.kind == "serves" and (.value | IN($ids[])))) | map(.component) | unique) as $r0
  | (
      { r: $r0, done: false }
      | until(.done;
          (.r) as $r
          | ($items | map(select(.kind == "supports" and (.value | IN($r[])))) | map(.component)) as $more
          | (($r + $more) | unique) as $next
          | { r: $next, done: ($next == $r) })
      | .r
    ) as $reaching
  | ($items | map(
      if .kind == "serves" and (.value | IN($ids[])) then empty
      elif .kind == "supports" and (.value | IN($reaching[])) and (.value != .component) then empty
      elif .kind == "serves" then {component, item, why: ("serves " + .value + ", not in the contract")}
      elif .kind == "supports" and (.value | IN($components[]) | not) then {component, item, why: ("supports " + .value + ", no such component")}
      elif .kind == "supports" and .value == .component then {component, item, why: "supports itself"}
      elif .kind == "supports" then {component, item, why: ("supports " + .value + ", which reaches no criterion")}
      elif .kind == "both" then {component, item, why: "two markers"}
      else {component, item, why: "no marker"} end)) as $unreached
  | ($items | map(select(.kind == "serves") | .value) | unique) as $served
  | ($open | map(select(IN($served[]) | not))) as $uncovered
  | ($open | length) as $nopen
  | {
      schema_version: "1.0",
      status: (if $nopen == 0 then "not_applicable" elif ($unreached | length) > 0 or ($uncovered | length) > 0 then "fail" else "pass" end),
      passes: (if $nopen == 0 then true else (($unreached | length) == 0 and ($uncovered | length) == 0) end),
      reason: (if $nopen == 0 then "all_ticked" else null end),
      source: $cr.source,
      criteria_count: ($ids | length), items_count: ($items | length),
      components: $components, not_declared: $undeclared, ticked: $ticked,
      unreached: $unreached, uncovered: $uncovered
    }' || exit 2
exit 0
