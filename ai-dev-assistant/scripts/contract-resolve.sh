#!/usr/bin/env bash
# contract-resolve.sh — the criteria a design is checked against, found by their `— id:` marker.
#
# Usage: contract-resolve.sh <task_folder>
#
# Resolution order, the first file carrying at least one id wins and is recorded as `source`:
#   1. <task>/alignment.md, Task-Level section only, through alignment-read.sh   → source: alignment
#   2. <task>/task.md, any checkbox line outside a code fence carrying `— id: c<n>`, under any
#      heading or none                                                           → source: task
# There is no fallthrough to an epic's contract: a child resolved against it would be checked
# against its siblings' criteria, a wrong answer that looks right. A child with no ids of its own
# is `not_run` with `reason: no_ids`, and the message names /scope, which is where ids come from.
#
# stdout, always one JSON object on exit 0:
#   { schema_version, status: "resolved" | "not_run", source: "alignment" | "task" | null,
#     path, reason: null | "no_ids", message, criteria: [ {id, text, checked} ] }
# `not_run` also carries `reason: duplicate_ids` (an id naming two criteria cannot be resolved against),
# `id_unrecognized` (a task.md marker whose value is not c<n>, the tail named) and `unterminated_fence`
# (a fence opener with no closer hides everything after it; a truncated read is never a contract).
# Exit 2, nothing on stdout: the task folder is not a directory, neither task.md nor alignment.md
# exists, or a file is unreadable.
# `not_run` is "nobody could look", printed by name; it is not a pass and not an empty contract.
set -uo pipefail
HERE="$(dirname "$(readlink -f "$0")")"
TASK="${1:?task folder required}"
[ -d "$TASK" ] || exit 2
[ -f "$TASK/task.md" ] || [ -f "$TASK/alignment.md" ] || exit 2
command -v jq >/dev/null 2>&1 || exit 2

emit() { # $1 status $2 source-or-null $3 path-or-null $4 reason-or-null $5 message $6 criteria-json
  jq -nc --arg st "$1" --arg src "$2" --arg p "$3" --arg r "$4" --arg m "$5" --argjson c "$6" '
    {schema_version:"1.0", status:$st,
     source:(if $src=="" then null else $src end), path:(if $p=="" then null else $p end),
     reason:(if $r=="" then null else $r end), message:$m, criteria:$c}'
}

# 1. alignment.md, Task-Level, ids only
if [ -f "$TASK/alignment.md" ]; then
  A="$("$HERE/alignment-read.sh" "$TASK" 2>/dev/null)" || exit 2
  CRIT="$(jq -c '[.sections.task_level.success_criteria[]? | select(.id != null) | {id, text, checked}]' <<<"$A")" || exit 2
  if [ "$(jq 'length' <<<"$CRIT")" -gt 0 ]; then
    UNMARKED="$(jq '[.sections.task_level.success_criteria[]? | select(.id == null)] | length' <<<"$A")"
    WARN="$(jq -c '[.warnings[]? | select(.code | startswith("criterion_id"))]' <<<"$A")"
    DUPS="$(jq -c '[.[].id] | group_by(.) | map(select(length > 1) | .[0])' <<<"$CRIT")"
    if [ "$(jq 'length' <<<"$DUPS")" -gt 0 ]; then
      emit not_run alignment "$TASK/alignment.md" duplicate_ids "an id names more than one criterion, so nothing can be resolved against it: $(jq -r 'join(", ")' <<<"$DUPS")" '[]'; exit 0
    fi
    emit resolved alignment "$TASK/alignment.md" "" "criteria resolved from alignment.md (Task-Level)$( [ "$UNMARKED" -gt 0 ] && printf '; %s Task-Level criteria carry no id and are invisible to coverage' "$UNMARKED")" "$CRIT" \
      | jq -c --argjson u "$UNMARKED" --argjson w "$WARN" '. + {unmarked: $u, warnings: $w}'; exit 0
  fi
fi

# 2. task.md, checkbox lines outside fences, wrapped lines joined, `— id: c<n>` as the selector
if [ -f "$TASK/task.md" ]; then
  [ -r "$TASK/task.md" ] || exit 2
  ROWS="$(awk '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    function flush(   t, p, tail, id, sp, checked) {
      if (item == "") return
      t = item; item = ""
      if (t !~ /^[[:space:]]*-[[:space:]]+\[[[:space:] xX]\][[:space:]]+/) return
      checked = (t ~ /^[[:space:]]*-[[:space:]]+\[[xX]\]/) ? "true" : "false"
      sub(/^[[:space:]]*-[[:space:]]+\[[[:space:] xX]\][[:space:]]+/, "", t)
      p = 0; sp = 0
      while ((sp = index(substr(t, p + 1), " — id: ")) > 0) p = p + sp   # last marker
      if (p == 0) return
      tail = trim(substr(t, p + length(" — id: ")))
      id = tail; sub(/[[:space:]].*$/, "", id)
      if (id !~ /^c[1-9][0-9]*$/) { printf "bad\t%s\t\n", id; return }
      printf "%s\t%s\t%s\n", checked, id, trim(substr(t, 1, p - 1))
    }
    /^[[:space:]]*(```|~~~)/ { fence = !fence; flush(); next }
    fence { next }
    /^[[:space:]]*#{1,6}[[:space:]]/ { flush(); next }
    /^[[:space:]]*-[[:space:]]+/ { flush(); item = $0; next }
    /[^[:space:]]/ { if (item != "") item = item " " trim($0); next }
    { flush() }
    END { flush(); if (fence) printf "fence\t\t\n" }
  ' < "$TASK/task.md")"
  if grep -q '^fence' <<<"$ROWS"; then
    emit not_run task "$TASK/task.md" unterminated_fence "a code fence opens and never closes, so every criterion after it is hidden; a truncated read is not a contract" '[]'; exit 0
  fi
  BAD="$(awk -F'\t' '$1 == "bad" {print $2}' <<<"$ROWS" | paste -sd, -)"
  if [ -n "$BAD" ]; then
    emit not_run task "$TASK/task.md" id_unrecognized "an — id: marker carries a value that is not c<n>: $BAD" '[]'; exit 0
  fi
  CRIT="$(printf '%s' "$ROWS" | jq -R -s -c '
    split("\n") | map(select(length > 0) | split("\t") | {id: .[1], text: .[2], checked: (.[0] == "true")})')"
  DUPS="$(jq -c '[.[].id] | group_by(.) | map(select(length > 1) | .[0])' <<<"$CRIT")"
  if [ "$(jq 'length' <<<"$DUPS")" -gt 0 ]; then
    emit not_run task "$TASK/task.md" duplicate_ids "an id names more than one criterion, so nothing can be resolved against it: $(jq -r 'join(", ")' <<<"$DUPS")" '[]'; exit 0
  fi
  if [ "$(jq 'length' <<<"$CRIT")" -gt 0 ]; then
    emit resolved task "$TASK/task.md" "" "criteria resolved from task.md by their — id: marker" "$CRIT"; exit 0
  fi
fi

# 3. nobody could look
emit not_run "" "" no_ids "no Task-Level criterion in alignment.md and no checkbox line in task.md carries an — id: marker; run /scope on this task (a task scoped before ids existed is expected here, and this is not a pass)" '[]'
exit 0
