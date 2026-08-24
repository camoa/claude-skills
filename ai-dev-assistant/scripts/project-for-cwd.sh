#!/usr/bin/env bash
# project-for-cwd.sh — which registered project owns this directory?
#
# The framework used the current directory for exactly one thing: hashing a session filename. Nothing
# compared it to any project's code path, so a session opened in an unregistered codebase was greeted
# with a count of every project the user has ever made and told to pick one. This answers the question
# that was never asked.
#
# Usage: project-for-cwd.sh [dir]     (dir defaults to $PWD)
#
# Emits ONE JSON object to stdout and exits 0 on every recoverable state:
#   { registered, dir, project, project_path, code_path, match, registry_present, warnings[] }
#
# match: exact   — the directory IS a project's code path
#        below   — the directory is inside a project's code path (a subdir of the codebase)
#        none    — no registered project owns it
#
# Deepest code path wins, so a project nested inside another resolves to the nearer one.
set -uo pipefail

DIR="${1:-$PWD}"
REGISTRY="${AIDA_REGISTRY:-$HOME/.claude/ai-dev-assistant/active_projects.json}"
WARNINGS='[]'
add_warn(){ WARNINGS=$(jq -c --arg w "$1" '. + [$w]' <<<"$WARNINGS" 2>/dev/null || printf '[]'); }

if ! command -v jq >/dev/null 2>&1; then
  printf '{"registered":false,"match":"none","registry_present":false,"warnings":["jq_missing"]}\n'
  exit 0
fi

emit(){ # emit <registered> <match> <project|""> <project_path|""> <code_path|""> <registry_present>
  jq -n --argjson reg "$1" --arg match "$2" --arg name "$3" --arg ppath "$4" \
        --arg cpath "$5" --argjson present "$6" --arg dir "$DIR" --argjson warnings "$WARNINGS" \
    '{schema_version:"1.0",
      registered:$reg, dir:$dir, match:$match,
      project:(if $name=="" then null else $name end),
      project_path:(if $ppath=="" then null else $ppath end),
      code_path:(if $cpath=="" then null else $cpath end),
      registry_present:$present, warnings:$warnings}'
  exit 0
}

# Resolve to a real path so /a/b/../b and symlinked homes compare equal.
RESOLVED="$(cd "$DIR" 2>/dev/null && pwd -P)" || RESOLVED=""
if [ -z "$RESOLVED" ]; then
  add_warn "dir_unreadable"
  emit false none "" "" "" false
fi
DIR="$RESOLVED"

if [ ! -r "$REGISTRY" ]; then
  # No registry is not an error: it is a first-ever run. Unregistered is the honest answer.
  emit false none "" "" "" false
fi
if ! jq empty "$REGISTRY" >/dev/null 2>&1; then
  add_warn "registry_malformed"
  emit false none "" "" "" true
fi

# Longest matching codePath wins. A trailing slash on either side must not change the answer, and a
# sibling named like a prefix (/srv/site2 against /srv/site) must NOT match — hence the explicit
# boundary test rather than a bare prefix compare.
MATCH="$(jq -r --arg d "$DIR" '
  [ .projects[]?
    | select((.codePath // "") != "")
    | . as $p
    | ($p.codePath | sub("/+$"; "")) as $c
    | select($d == $c or ($d | startswith($c + "/")))
    | {name: $p.name, path: $p.path, code: $c, len: ($c | length),
       kind: (if $d == $c then "exact" else "below" end)} ]
  | sort_by(.len) | last // empty' "$REGISTRY" 2>/dev/null)" || MATCH=""

if [ -z "$MATCH" ] || [ "$MATCH" = "null" ]; then
  emit false none "" "" "" true
fi

NAME="$(jq -r '.name // ""'  <<<"$MATCH")"
PPATH="$(jq -r '.path // ""' <<<"$MATCH")"
CPATH="$(jq -r '.code // ""' <<<"$MATCH")"
KIND="$(jq -r '.kind // "none"' <<<"$MATCH")"
[ -d "$PPATH" ] || add_warn "project_folder_missing"
emit true "$KIND" "$NAME" "$PPATH" "$CPATH" true
