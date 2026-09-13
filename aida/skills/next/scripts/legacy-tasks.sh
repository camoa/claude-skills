#!/usr/bin/env bash
# legacy-tasks.sh: lists tasks still sitting in version 5's folders.
#
# TRANSITIONAL. This file exists only until the last version 5 task has been opened and moved into
# the project's tasks folder. Removing it is deleting this file and the one line in
# next-actions.sh that sources it, plus the two calls in its report. Nothing else refers to it.
#
# ideal/task.md: "While any old task remains, /next lists the new folder and both old folders, so
# nothing is invisible during the transition. When the old folders are empty they go. That listing
# is transitional, so it lives in its own file with one call site."
#
# It reads only. It never moves a task and never writes. Moving one is repair, and repair happens
# when a person opens the task, not when a list is drawn.
#
# It needs sort_key from next-actions.sh, so it is sourced by that file and never on its own.

# Legacy tasks: version 5's implementation_process/in_progress and completed. A top-level folder
# with its own subfolders is a split task (an epic); each subfolder is a listed leaf, one level
# deep, matching the two-level nesting version 5 already enforced. A top-level folder with no
# subfolders is itself the leaf.
# ------------------------------------------------------------------------------------------------

emit_legacy_leaves() {
  local project_path="$1" base_dir="$2" legacy_state="$3"
  [ -d "$base_dir" ] || return 0
  local top top_name has_children child key line
  while IFS= read -r top; do
    [ -n "$top" ] || continue
    top_name="$(basename -- "$top")"
    has_children=0
    while IFS= read -r child; do
      [ -n "$child" ] || continue
      has_children=1
      key="$(sort_key "$project_path" "$child")"
      line="$(jq -nc --arg k "$(basename -- "$child")" --arg e "$top_name" --arg s "$legacy_state" --arg p "$child" \
        '{kind:"legacy", id:$k, epic:$e, legacyState:$s, path:$p}')"
      printf '%s\t%s\n' "$key" "$line"
    done < <(find "$top" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
    if [ "$has_children" -eq 0 ]; then
      key="$(sort_key "$project_path" "$top")"
      line="$(jq -nc --arg k "$top_name" --arg s "$legacy_state" --arg p "$top" \
        '{kind:"legacy", id:$k, epic:null, legacyState:$s, path:$p}')"
      printf '%s\t%s\n' "$key" "$line"
    fi
  done < <(find "$base_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
}

gather_legacy_open() {
  emit_legacy_leaves "$1" "$1/implementation_process/in_progress" "in_progress"
}

gather_legacy_complete() {
  emit_legacy_leaves "$1" "$1/implementation_process/completed" "complete"
}
