#!/usr/bin/env bash
# surfaces.sh: the one reader of the surface file, `.visual-review/surfaces.json` in the tree
# setup ran in (scripts/surfaces-schema.json). The surfaces skill writes the file and review runs
# it, and both source this, so the writer is proved by the reader review uses (ideal/surfaces.md).
#
#   sf_load_surfaces <file>          sets SF_STATE (absent, missing, unreadable, ok) and
#                                    SF_SURFACES, a JSON array of {id, url, kinds, enabled, masks},
#                                    empty unless ok
#   sf_surface_path <registryPath> <tree>   prints the surface file's absolute path: <registryPath>
#                                    joined to <tree> when it is relative, or <registryPath> as it
#                                    is when a record written before row 32 of
#                                    audit/14-live-run-gaps.md holds an absolute one
#
# Missing and unreadable stay two words, because they send a reader to two different repairs. A
# file whose rows lack a string id, a kinds array or a boolean enabled reads unreadable, and the
# caller records unknown rather than reading it as a project with no surfaces.
# Portability: bash 3.2+ and zsh. This file is a library. Source it; do not run it.
if [ -n "${ZSH_VERSION:-}" ]; then
  case "${ZSH_EVAL_CONTEXT:-}" in
    *:file) : ;;
    *) printf 'surfaces.sh: this is a library, meant to be sourced, not run directly.\n' >&2; exit 1 ;;
  esac
elif [ -n "${BASH_VERSION:-}" ] && [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  printf 'surfaces.sh: this is a library, meant to be sourced, not run directly.\n' >&2
  exit 1
fi

SF_STATE="absent"; SF_SURFACES="[]"
sf_load_surfaces() {
  local surface_file="$1" rows
  SF_STATE="absent"; SF_SURFACES='[]'
  [ -n "$surface_file" ] || return 0
  if [ ! -f "$surface_file" ]; then
    SF_STATE="missing"
    return 0
  fi
  rows="$(jq -c '
    if (.surfaces | type) == "array"
       and all(.surfaces[]; (.id | type) == "string" and (.kinds | type) == "array" and (.enabled | type) == "boolean")
    then [ .surfaces[] | {id, url: (.url // ""), kinds, enabled, masks: (.masks // [])} ] else empty end' \
    "$surface_file" 2>/dev/null)"
  if [ -z "$rows" ]; then
    SF_STATE="unreadable"
    return 0
  fi
  # shellcheck disable=SC2034 # read by the sourcing script, with SF_SURFACES
  SF_STATE="ok"
  # shellcheck disable=SC2034 # read by the sourcing script
  SF_SURFACES="$rows"
}

# $1 the project record's `surfaces.registryPath`, may be empty. $2 the tree the caller runs in.
# Calls no die function; an empty $1 prints empty, and sf_load_surfaces then reads it as absent.
# The join itself is resolve_against, from scripts/lib/paths.sh, which the caller sources.
sf_surface_path() {
  [ -n "$1" ] && resolve_against "$1" "$2"
  return 0
}
