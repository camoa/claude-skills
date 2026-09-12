#!/usr/bin/env bash
# task-helpers.sh: the four helpers every stage script needs before it can touch a task folder.
#
# scope-actions.sh, research-actions.sh and design-actions.sh each carried their own copy of these
# four. One implementation, not three copies drifting apart, the same reason schema-check.sh exists.
#
# The caller defines die1 and die3 before it sources this file, each with its own script name in
# the message, so a refusal still says which script refused. That is the one thing this library
# takes from its caller rather than owning.
#
# Public functions:
#
#   resolve_task_folder <path> <action>   prints the canonical task folder, or dies
#   looks_like_flag <value>               true when the value is another option, not data
#   is_blank <value>                      true when the value is empty or only whitespace
#   write_atomic <target> <content>       writes through a temporary file beside the target

# The task folder must already exist and already hold a task.json (ideal/scope.md, "Scope runs
# against a task that already exists": a stage finds a task or says it cannot, it never scaffolds
# one). Prints the canonical path on success.
resolve_task_folder() {
  local arg="$1" who="$2" p
  [ -n "$arg" ] || die3 "$who: a task folder is required"
  p="$(cd "$arg" 2>/dev/null && pwd -P)" || die1 "$who: task folder not found: $arg"
  [ -f "$p/task.json" ] || die1 "$who: $p has no task.json; this is not a task folder"
  printf '%s' "$p"
}

# True (exit 0) when $1 looks like another option rather than real data for the option that wanted
# it. An argument whose value is another flag was once accepted for every text field, so every
# flag that takes a value asks this first.
looks_like_flag() {
  case "$1" in
    --*) return 0 ;;
    *) return 1 ;;
  esac
}

# True (exit 0) when $1 is empty, or holds only whitespace. This is a value with no characters in
# it at all, never a judgement about what the value says.
is_blank() {
  case "$1" in
    *[![:space:]]*) return 1 ;;
  esac
  return 0
}

# Writes $2 (assumed already-valid JSON text) to $1 through a temporary file in the target's own
# directory, then renames over the target. The rename stays inside one filesystem, and a failure
# partway through never leaves a half-written file at $1.
write_atomic() {
  local target="$1" content="$2" dir tmp
  dir="$(dirname -- "$target")"
  tmp="$(mktemp "${dir}/.$(basename -- "$target").XXXXXX")" \
    || die3 "could not create a temporary file in $dir"
  printf '%s\n' "$content" > "$tmp" || { rm -f "$tmp"; die3 "could not write $tmp"; }
  mv -f "$tmp" "$target" || { rm -f "$tmp"; die3 "could not write $target"; }
}
