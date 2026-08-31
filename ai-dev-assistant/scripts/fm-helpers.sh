#!/usr/bin/env bash
# fm-helpers.sh — shared helpers for task.md frontmatter handling.
# Sourced by other scripts in this directory. NOT executed directly.
#
# Portability: works in bash 4+ and zsh 5+. Avoid shell-specific syntax.
# Requirements: python3 with yaml module, jq. Both standard on modern Linux.

# --- extract one field's body from a markdown H2/H3 section -------------------------------------
# MOVED here from scripts/ledger-index.sh (was ledger-index.sh:87-100). ledger-index.sh now sources
# this file instead of keeping its own copy — one section extractor, not two files drifting apart.
#
# Reads from a file, returns the text under <heading> up to the next heading of the same or higher
# level. Pure text handling; the value is passed to jq --arg by the caller, never interpolated.
section_body(){ # section_body <file> <heading-regex>
  local f="$1" h="$2"
  [ -f "$f" ] || return 0
  awk -v pat="$h" '
    BEGIN { grab = 0 }
    /^#{1,6} / {
      if (grab) exit
      if (tolower($0) ~ tolower(pat)) { grab = 1; next }
    }
    grab { print }
  ' "$f" 2>/dev/null | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | sed '/^$/d' | head -40
}

first_para(){ printf '%s' "$1" | awk 'NF { print; next } { exit }' | tr '\n' ' ' | sed -e 's/[[:space:]]\+/ /g' -e 's/^ //' -e 's/ $//'; }

# heading_present <file> <heading-regex>
# True (exit 0) when <file> contains a markdown heading (any level, `#{1,6} `) whose text matches
# <heading-regex> case-insensitively. Companion to section_body: section_body cannot tell "no such
# heading" apart from "heading present, body empty" — both return "". This is what tells them apart.
heading_present(){
  local f="$1" pat="$2" hit
  [ -f "$f" ] || return 1
  hit=$(awk -v pat="$pat" '
    /^#{1,6} / { if (tolower($0) ~ tolower(pat)) { print "1"; exit } }
  ' "$f" 2>/dev/null)
  [ "$hit" = "1" ]
}

# stub_verdict <task_md_file>
# Goal-scoped stub detector. Reads ONLY the `## Goal` section, never the whole file — a file-wide
# phrase match calls a 330-word authored task a stub because /scope seeds `## Goal` but leaves the
# Acceptance Criteria placeholder `_to be defined_` behind (see architecture.md section 2 of
# stub_marker_overwrites_authored_task). Prints ONE JSON object to stdout and always exits 0 —
# callers read `.verdict`, never the exit code.
#
#   verdict     stub | authored | undetermined
#   decided_by  placeholder | empty_goal   (why stub)
#               no_goal_section | unreadable   (why undetermined)
#               content_present   (why authored — not enumerated in architecture.md, chosen for
#               consistency with the others; no assertion in the spec depends on this value)
#   matched     the placeholder phrase found, when decided_by is "placeholder"; [] otherwise
#
# The three phrases are one per known writer, confirmed in source: `To be authored via`
# (commands/scope.md), `_to be defined_` (commands/scope.md), `(stub — populate when ready)`
# (write_stub_task_md below). A fourth writer added without its phrase here fails a genuine stub as
# `authored` rather than silently matching it — there is no registry a new writer's phrase joins
# automatically, so a writer that skips this list is a real gap, not a design choice.
stub_verdict(){
  local f="$1"
  local goal_pat='^##+ goal'
  local goal_body phrase

  if [ ! -f "$f" ] || [ ! -r "$f" ]; then
    jq -nc --arg path "$f" \
      '{verdict:"undetermined", blocks:false, decided_by:"unreadable", matched:[], path:$path}'
    return 0
  fi

  if ! heading_present "$f" "$goal_pat"; then
    jq -nc --arg path "$f" \
      '{verdict:"undetermined", blocks:false, decided_by:"no_goal_section", matched:[], path:$path}'
    return 0
  fi

  goal_body="$(first_para "$(section_body "$f" "$goal_pat")")"

  if [ -z "$goal_body" ]; then
    jq -nc --arg path "$f" \
      '{verdict:"stub", blocks:false, decided_by:"empty_goal", matched:[], path:$path}'
    return 0
  fi

  for phrase in 'To be authored via' '_to be defined_' '(stub — populate when ready)'; do
    case "$goal_body" in
      *"$phrase"*)
        jq -nc --arg path "$f" --arg p "$phrase" \
          '{verdict:"stub", blocks:false, decided_by:"placeholder", matched:[$p], path:$path}'
        return 0
        ;;
    esac
  done

  jq -nc --arg path "$f" \
    '{verdict:"authored", blocks:false, decided_by:"content_present", matched:[], path:$path}'
  return 0
}

# verify_preserved <before-file> <after-file>
# Read-back for a write that claims to preserve everything it did not mean to change. Captures every
# heading in <before-file> that had CONTENT, and confirms each still exists in <after-file> with a
# non-empty body. Exits non-zero and NAMES every section that vanished or was left with an empty
# body — a truncated or half-written copy is not a preserved pass. Modelled on the cmp -s read-back
# in scripts/review-record-archive.sh:81.
#
# Headings with no content in <before-file> (e.g. an H1 title line with nothing under it before the
# next heading) are not checked — there is nothing to preserve there, and checking them anyway would
# fail a byte-identical copy.
verify_preserved(){
  local before="$1" after="$2"
  [ -f "$before" ] && [ -f "$after" ] || { echo "verify_preserved: both files must exist" >&2; return 2; }

  local heading pat body_before body_after dropped=""
  while IFS= read -r heading; do
    [ -n "$heading" ] || continue
    pat=$(printf '%s' "$heading" | sed -e 's/[][\.^$*+?(){}|\\]/\\&/g')
    pat="^#{1,6}[[:space:]]*${pat}[[:space:]]*\$"

    body_before="$(section_body "$before" "$pat")"
    [ -n "$(printf '%s' "$body_before" | tr -d '[:space:]')" ] || continue

    if ! heading_present "$after" "$pat"; then
      dropped="${dropped}${dropped:+, }$heading"
      continue
    fi
    body_after="$(section_body "$after" "$pat")"
    [ -n "$(printf '%s' "$body_after" | tr -d '[:space:]')" ] || dropped="${dropped}${dropped:+, }$heading"
  done < <(grep -E '^#{1,6}[[:space:]]' "$before" 2>/dev/null | sed -E 's/^#{1,6}[[:space:]]*//' | sed -e 's/[[:space:]]*$//')

  if [ -n "$dropped" ]; then
    echo "verify_preserved: section(s) dropped or emptied: $dropped" >&2
    return 1
  fi
  return 0
}

# fm_read <task_folder>
# Parse frontmatter on <task_folder>/task.md. Always prints a single JSON line
# to stdout and exits 0, regardless of input. Warnings surface via warnings[].
fm_read() {
  local task_dir="$1"
  local folder_name
  folder_name=$(basename "$task_dir")

  if [ ! -d "$task_dir" ]; then
    jq -nc --arg id "local:$folder_name" --arg dir "$task_dir" \
      '{id: $id, kind: null, parent: null, children: [], blocks: [], blocked_by: [], external_ids: {}, status: null, mechanism_hints: [], run_mode: null, folder: $dir, warnings: [{code: "folder_missing", detail: "task folder does not exist"}]}'
    return 0
  fi

  local task_md="$task_dir/task.md"
  if [ ! -f "$task_md" ]; then
    jq -nc --arg id "local:$folder_name" --arg dir "$task_dir" \
      '{id: $id, kind: null, parent: null, children: [], blocks: [], blocked_by: [], external_ids: {}, status: null, mechanism_hints: [], run_mode: null, folder: $dir, warnings: [{code: "task_md_missing", detail: "task.md not found in folder"}]}'
    return 0
  fi

  local fm
  fm=$(awk 'NR==1 && /^---[[:space:]]*$/ {fm=1; next} fm && /^---[[:space:]]*$/ {exit} fm {print}' "$task_md")

  if [ -z "$fm" ]; then
    jq -nc --arg id "local:$folder_name" --arg dir "$task_dir" \
      '{id: $id, kind: "flat", parent: null, children: [], blocks: [], blocked_by: [], external_ids: {}, status: null, mechanism_hints: [], run_mode: null, folder: $dir, warnings: [{code: "frontmatter_absent", detail: "task.md has no frontmatter block; kind defaults to flat, status is unknown"}]}'
    return 0
  fi

  local parsed
  parsed=$(printf '%s' "$fm" | python3 -c '
import sys, json
try:
    import yaml
    data = yaml.safe_load(sys.stdin.read()) or {}
    print(json.dumps({"ok": True, "data": data}))
except ImportError:
    print(json.dumps({"ok": False, "error": "yaml module not available"}))
except Exception as e:
    print(json.dumps({"ok": False, "error": str(e)}))
' 2>/dev/null)

  if [ -z "$parsed" ]; then
    jq -nc --arg id "local:$folder_name" --arg dir "$task_dir" \
      '{id: $id, kind: null, parent: null, children: [], blocks: [], blocked_by: [], external_ids: {}, status: null, mechanism_hints: [], run_mode: null, folder: $dir, warnings: [{code: "parser_unavailable", detail: "python3 missing or failed"}]}'
    return 0
  fi

  jq -c --arg fn "$folder_name" --arg dir "$task_dir" '
    if .ok then
      .data as $d |
      {
        id: ($d.id // ("local:" + $fn)),
        kind: ($d.kind // "flat"),
        parent: ($d.parent // null),
        children: ($d.children // []),
        blocks: ($d.blocks // []),
        blocked_by: ($d.blocked_by // []),
        external_ids: ($d.external_ids // {}),
        status: ($d.status // null),
        mechanism_hints: ($d.mechanism_hints // []),
        run_mode: ($d.run_mode // null),
        folder: $dir,
        warnings: []
      }
    else
      {
        id: ("local:" + $fn),
        kind: "flat",
        parent: null,
        children: [],
        blocks: [],
        blocked_by: [],
        external_ids: {},
        status: null,
        mechanism_hints: [],
        run_mode: null,
        folder: $dir,
        warnings: [{code: "malformed_yaml", detail: .error}]
      }
    end' <<<"$parsed"
}

# `status` is null when nothing on disk said otherwise (v5.30.4+).
#
# It used to be the string "draft" in five places: four where the read had failed or the file
# carried no frontmatter, and once as the default for an absent key. A finished task and a
# never-started one came back identical, and the no-frontmatter path also returned
# `warnings: []`, so nothing anywhere in the object said a read had not happened. Observed on a
# task that had just passed review: `status: draft`, no warnings.
#
# `kind` follows the same rule but keeps "flat" where the file was read and declared no
# hierarchy, because that is a fact about the file rather than a fallback. Where nothing was
# read at all, kind is null too.

# write_epic_frontmatter <task_name> <current_status> [<child1> <child2> ...]
# Prints a canonical YAML frontmatter block (including --- delimiters) to stdout.
write_epic_frontmatter() {
  local task="$1"; shift
  local current_status="${1:-in_progress}"; shift
  local children_json="[]"
  if [ $# -gt 0 ]; then
    children_json=$(printf '%s\n' "$@" | jq -R '"local:" + .' | jq -sc .)
  fi
  jq -n --arg id "local:$task" --arg status "$current_status" --argjson children "$children_json" '
    {
      id: $id, kind: "epic", parent: null,
      children: $children, blocks: [], blocked_by: [],
      external_ids: {}, status: $status
    }' | python3 -c '
import sys, json, yaml
print("---")
print(yaml.safe_dump(json.load(sys.stdin), sort_keys=False).rstrip())
print("---")'
}

# write_subepic_frontmatter <task_name> <parent_name> <current_status> [<child1> <child2> ...]
# Used when promoting a subtask to a sub_epic (second and final nesting level).
# Sub-epics carry the same shape as epics but with kind=sub_epic and a non-null parent.
write_subepic_frontmatter() {
  local task="$1"; shift
  local parent="$1"; shift
  local current_status="${1:-in_progress}"; shift
  local children_json="[]"
  if [ $# -gt 0 ]; then
    children_json=$(printf '%s\n' "$@" | jq -R '"local:" + .' | jq -sc .)
  fi
  jq -n --arg id "local:$task" --arg parent_id "local:$parent" --arg status "$current_status" --argjson children "$children_json" '
    {
      id: $id, kind: "sub_epic", parent: $parent_id,
      children: $children, blocks: [], blocked_by: [],
      external_ids: {}, status: $status
    }' | python3 -c '
import sys, json, yaml
print("---")
print(yaml.safe_dump(json.load(sys.stdin), sort_keys=False).rstrip())
print("---")'
}

# write_subtask_frontmatter <child_name> <parent_name> [<current_status>]
write_subtask_frontmatter() {
  local child="$1"
  local parent="$2"
  local current_status="${3:-draft}"
  jq -n --arg id "local:$child" --arg parent_id "local:$parent" --arg status "$current_status" '
    {
      id: $id, kind: "subtask", parent: $parent_id,
      children: null, blocks: [], blocked_by: [],
      external_ids: {}, status: $status
    }' | python3 -c '
import sys, json, yaml
print("---")
print(yaml.safe_dump(json.load(sys.stdin), sort_keys=False).rstrip())
print("---")'
}

# apply_frontmatter <task_md_file> <frontmatter_block>
# Prepends the block to the file, or replaces an existing frontmatter block.
apply_frontmatter() {
  local file="$1"
  local new_fm="$2"
  local tmp="$file.tmp"
  local body="$file.body"

  if head -1 "$file" | grep -qE '^---[[:space:]]*$'; then
    awk '
      BEGIN { in_fm=0; seen_end=0 }
      NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
      in_fm && /^---[[:space:]]*$/ { in_fm=0; seen_end=1; next }
      !in_fm && seen_end { print }
      !in_fm && !seen_end { print }
    ' "$file" > "$body"
  else
    cp "$file" "$body"
  fi
  { printf '%s\n\n' "$new_fm"; cat "$body"; } > "$tmp"
  mv "$tmp" "$file"
  rm -f "$body"
}

# write_stub_task_md <file> <child_name> <parent_name>
# Emits a minimal subtask stub. The "## Notes" line carries the shared
# `Stub scaffolded by ` marker family (mirrors the /scope stub convention) so
# /research step 2 can detect the stub and overwrite it with the full Phase 1
# template rather than aborting on a pre-existing folder.
write_stub_task_md() {
  local file="$1"
  local child="$2"
  local parent="$3"
  local fm
  fm=$(write_subtask_frontmatter "$child" "$parent" "draft")
  cat > "$file" <<EOF
$fm

# $child

**Created:** $(date -u +%Y-%m-%d)
**Parent epic:** $parent

## Goal
(stub — populate when ready)

## Phase Status
- [ ] Phase 1: Research
- [ ] Phase 2: Architecture
- [ ] Phase 3: Implementation
- [ ] Phase 4: Review (_review.json)

## Notes
Stub scaffolded by \`/ai-dev-assistant:migrate-to-epic\` on $(date -u +%Y-%m-%d).
EOF
}
