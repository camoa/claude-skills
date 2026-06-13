#!/usr/bin/env bash
# fm-helpers.sh — shared helpers for task.md frontmatter handling.
# Sourced by other scripts in this directory. NOT executed directly.
#
# Portability: works in bash 4+ and zsh 5+. Avoid shell-specific syntax.
# Requirements: python3 with yaml module, jq. Both standard on modern Linux.

# fm_read <task_folder>
# Parse frontmatter on <task_folder>/task.md. Always prints a single JSON line
# to stdout and exits 0, regardless of input. Warnings surface via warnings[].
fm_read() {
  local task_dir="$1"
  local folder_name
  folder_name=$(basename "$task_dir")

  if [ ! -d "$task_dir" ]; then
    jq -nc --arg id "local:$folder_name" --arg dir "$task_dir" \
      '{id: $id, kind: "flat", parent: null, children: [], blocks: [], blocked_by: [], external_ids: {}, status: "draft", folder: $dir, warnings: [{code: "folder_missing", detail: "task folder does not exist"}]}'
    return 0
  fi

  local task_md="$task_dir/task.md"
  if [ ! -f "$task_md" ]; then
    jq -nc --arg id "local:$folder_name" --arg dir "$task_dir" \
      '{id: $id, kind: "flat", parent: null, children: [], blocks: [], blocked_by: [], external_ids: {}, status: "draft", folder: $dir, warnings: [{code: "task_md_missing", detail: "task.md not found in folder"}]}'
    return 0
  fi

  local fm
  fm=$(awk 'NR==1 && /^---[[:space:]]*$/ {fm=1; next} fm && /^---[[:space:]]*$/ {exit} fm {print}' "$task_md")

  if [ -z "$fm" ]; then
    jq -nc --arg id "local:$folder_name" --arg dir "$task_dir" \
      '{id: $id, kind: "flat", parent: null, children: [], blocks: [], blocked_by: [], external_ids: {}, status: "draft", folder: $dir, warnings: []}'
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
      '{id: $id, kind: "flat", parent: null, children: [], blocks: [], blocked_by: [], external_ids: {}, status: "draft", folder: $dir, warnings: [{code: "parser_unavailable", detail: "python3 missing or failed"}]}'
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
        status: ($d.status // "draft"),
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
        status: "draft",
        folder: $dir,
        warnings: [{code: "malformed_yaml", detail: .error}]
      }
    end' <<<"$parsed"
}

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

**Created:** $(date -I)
**Parent epic:** $parent

## Goal
(stub — populate when ready)

## Phase Status
- [ ] Phase 1: Research
- [ ] Phase 2: Architecture
- [ ] Phase 3: Implementation
- [ ] Phase 4: Review (_review.json)

## Notes
Stub scaffolded by \`/ai-dev-assistant:migrate-to-epic\` on $(date -I).
EOF
}
