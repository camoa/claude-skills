#!/usr/bin/env bash
# registry.sh: the one store mapping a directory to a project.
#
# The project file is the truth. This store is an index: it answers "which project owns this
# directory" and "show me my projects so I can choose" without opening every project file. One
# producer writes the project file and the matching registry row in the same operation. The
# project file wins any disagreement between the two; the check (a separate script) reports a
# mismatch rather than this library silently choosing one.
#
# Store: $AIDA_REGISTRY_PATH, default ~/.claude/aida/registry.json. Not inside the plugin's own
# data directory, since nothing durable belongs there, and this path is named for the product,
# never for the plugin's own package identity, which changes at release.
#
# Shape, matching scripts/registry-schema.json exactly, which is frozen and not edited here:
#
#   { "version": 1,
#     "projects": [ {codePath, projectPath, name, lastAccessed, state} ],
#     "declinedOffers": [ {directory, declinedAt} ],
#     "directoryChoices": [ {directory, project, chosenAt} ] }
#
# `projects` is the index proper: which project owns a registered code path, and the copy of the
# five values ideal/project.md names, "What a project holds": where the code is, where the project
# folder is, the name, when it was last used, and its lifecycle state.
#
# `declinedOffers` is "picking up work"'s memory of a question already answered: this directory was
# offered a project and said no. Recording the decline is the point; an unrecorded no is re-asked
# every session. Answering again for the same directory replaces its row rather than appending one.
#
# `directoryChoices` is "picking up work" case 2: the directory is not itself a registered code
# path, and it remembers the project last chosen from it. This is a different fact from ownership,
# not a weaker copy of it. When both a code-path match and a remembered choice exist and disagree,
# the registered code path wins; that tie-break is composed by the caller from the two reads this
# library provides, not decided in here.
#
# This library does not ship the store file. The first write creates it. A read against a missing
# store answers as if it were empty: a first-ever run is not an error. A store that exists but will
# not parse is a different fact. It is corrupt, not empty, and treating it as empty would let the
# next write replace it with a fresh skeleton and lose every registered project. So a read against a
# corrupt store reports the fact to stderr and fails, and every write function refuses to proceed
# past a read that failed. This is stricter than version 5's separate offer store, which answered
# "no offer recorded" on a corrupt file so the proposal would fire again rather than go silent.
# Version 5 could afford that because the offer store held nothing else. Here one file holds the
# project index too, and a reader that returns empty on a real failure is the exact defect
# foundations.md's Honesty section forbids, so a corrupt file fails loudly everywhere in this
# library, not only on write.
#
# Public functions:
#
#   registry_resolve_by_directory <dir>
#     Deepest matching codePath wins: among every registered project whose codePath is <dir> itself
#     or an ancestor of it, the one with the longest codePath, so a sibling named like a prefix
#     (/srv/site2 against /srv/site) never matches. Prints that project row as one JSON object on
#     stdout and exits 0; prints nothing and exits 1 when no project matches. Ported from version
#     5's scripts/project-for-cwd.sh, which carried this algorithm correctly.
#
#   registry_add_project <codePath> <projectPath> <name>
#     Adds one row with lastAccessed set to today (UTC date, YYYY-MM-DD) and state "active". Exits
#     1 without writing when codePath is already registered.
#
#   registry_touch_last_accessed <projectPath>
#     Sets lastAccessed to today for the project at <projectPath>. Exits 1 without writing when no
#     project is registered at that path. The caller runs this after every successful resolution,
#     which is what keeps "picking up work" case 4's list ordered by real use instead of by age.
#
#   registry_set_state <projectPath> <state>
#     Sets the lifecycle state (active, complete or archived) for the project at <projectPath>.
#     Exits 1 on an unrecognised state or when no project is registered at that path. Every
#     transition is reversible; this is the one function every transition runs through.
#
#   registry_remove_project <projectPath>
#     Drops the row for the project at <projectPath> and leaves both folders untouched. This is
#     unregistering, not a lifecycle state: the project stops resolving and stops listing, and
#     pointing at the same project folder again is how it comes back. Exits 1 when no project is
#     registered at that path.
#
#   registry_list_projects [state...]
#     Prints every project row as newline-delimited JSON, ordered by lastAccessed, most recent
#     first. With no state named, every row prints, whatever its state. Named states (any of
#     active, complete, archived) filter to only those rows. Deciding which states a given list
#     should offer, active only when offering fresh work, every state when a person asks to see
#     everything, is the caller's policy; this function only sorts and filters on request.
#
#   registry_record_declined_offer <directory>
#     Records that <directory> was offered a project and said no. Answering again for the same
#     directory replaces the row rather than appending a second one.
#
#   registry_read_declined_offer <directory>
#     Prints the declined-offer row that applies to <directory> and exits 0, or prints nothing and
#     exits 1 when none applies. Matches the deepest recorded directory that is <directory> itself
#     or an ancestor of it, the same boundary test registry_resolve_by_directory uses, so a decline
#     recorded at a parent directory is remembered from every directory under it. Ported from
#     version 5's scripts/project-offer-read.sh and scripts/project-offer-write.sh.
#
#   registry_record_directory_choice <directory> <project>
#     Records that <project> is the project last chosen from <directory>. Answering again for the
#     same directory replaces the row rather than appending a second one, the same replace-not-
#     append rule version 5's session-context-writer skill used for its own per-directory record.
#
#   registry_read_directory_choice <directory>
#     Prints the directoryChoices row for <directory> and exits 0, or prints nothing and exits 1
#     when none exists. Matches <directory> itself only: a directory choice is remembered for the
#     exact directory it was made from, unlike a code path, which extends to every subdirectory
#     underneath it.
#
#   registry_rebuild [projectsHome]
#     Rebuilds `projects` from scratch by walking every immediate subdirectory of <projectsHome>
#     (default $AIDA_PROJECTS_HOME, or ~/.claude/aida/projects) and reading each one's project.json.
#     A subdirectory with no project.json is skipped without comment, since not every folder there
#     need be a project. A project.json that exists but will not read as JSON, or is missing
#     codePath or name, is skipped with a line on stderr naming the folder and the reason, so a
#     bounded rebuild never drops a project silently. lastAccessed cannot be recovered from
#     project.json, which does not carry it: this rebuild uses the project folder's own last git
#     commit date as the closest available fact, and today's date when the folder carries no git
#     history yet. `declinedOffers` and `directoryChoices` are not derivable from project files at
#     all, so a rebuild always starts them empty; this is a real loss, stated here rather than
#     hidden, not a bug. Always replaces the whole store; refuses only when it cannot write.
#
# What this library does NOT do: it does not decide which of a matching code path and a remembered
# directory choice wins when both apply, and it does not decide which lifecycle states a given
# listing should offer. Both are read-time policy a caller composes from the primitives above.
#
# Every write replaces the whole file in one step: write to a temp file, then rename it into place,
# so a reader never sees a half-written store. Ported from version 5's project-offer-write.sh, which
# used the same pattern.
#
# Portability: bash 3.2+, tested under bash and zsh. No mapfile, no associative arrays, no glob left
# unguarded against a no-match expansion (zsh aborts a script on one by default; bash does not), no
# GNU-only find or date flag.
#
# This file is a library. Source it; do not run it.
#
# The sourced-or-run check reads differently per shell because there is no one variable both
# agree on. bash sets BASH_SOURCE, and referencing it under zsh, or under a caller's already-active
# `set -u`, is itself the failure this avoids: an unset-parameter error before the check completes.
# zsh sets ZSH_EVAL_CONTEXT instead, ending in ":file" only when this script was sourced.
if [ -n "${ZSH_VERSION:-}" ]; then
  case "${ZSH_EVAL_CONTEXT:-}" in
    *:file) : ;;
    *)
      printf 'registry.sh: this is a library, meant to be sourced, not run directly.\n' >&2
      exit 1
      ;;
  esac
elif [ -n "${BASH_VERSION:-}" ] && [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  printf 'registry.sh: this is a library, meant to be sourced, not run directly.\n' >&2
  exit 1
fi

set -uo pipefail  # not -e: a sourced file must not exit the caller's shell on a miss it should
                   # instead report through a return code, e.g. no match in resolve-by-directory.

REGISTRY_PATH="${AIDA_REGISTRY_PATH:-$HOME/.claude/aida/registry.json}"
REGISTRY_EMPTY='{"version":1,"projects":[],"declinedOffers":[],"directoryChoices":[]}'

# ---------------------------------------------------------------------------------------------
# Internal helpers (prefixed registry__, not part of the public functions above)
# ---------------------------------------------------------------------------------------------

registry__require_jq() {
  command -v jq >/dev/null 2>&1 && return 0
  printf 'registry.sh: jq is required and was not found on PATH.\n' >&2
  return 1
}

# Canonicalize a path so a trailing slash, a relative path, or "." compares equal to the absolute
# form already stored. Falls back to a textual resolution when the directory does not exist yet
# (a codePath named for a not-yet-created directory is still a legitimate value).
registry__canon() {
  local input="$1" resolved parent base
  resolved="$(cd "$input" 2>/dev/null && pwd -P)" || resolved=""
  if [ -z "$resolved" ]; then
    # "$input" does not exist yet. `realpath -m` is GNU-only, missing on BSD and macOS realpath,
    # so this resolves the closest existing ancestor with `cd` and `pwd` and appends what is left.
    case "$input" in
      /*) : ;;
      *) input="$(pwd -P)/$input" ;;
    esac
    parent="$(dirname -- "$input")"
    base="$(basename -- "$input")"
    resolved="$(cd "$parent" 2>/dev/null && pwd -P)" || resolved="$parent"
    resolved="$resolved/$base"
  fi
  resolved="${resolved%/}"
  [ -n "$resolved" ] || resolved="/"
  printf '%s' "$resolved"
}

# Emits the store's current content. Never writes.
#
# A missing store answers as the empty skeleton, the same fallback version 5's readers used for a
# first-ever run: exits 0.
#
# A store that exists but is not readable or will not parse as JSON is corrupt, not empty. It
# prints one line to stderr and exits 1 with nothing on stdout, so a caller that builds a write
# from this output can tell "nothing registered yet" apart from "something is wrong, do not
# overwrite this file" and refuse to proceed on the second. Every public function in this file
# reads through here, so a corrupt store fails the same way for every one of them, not only writes.
registry__current() {
  if [ ! -e "$REGISTRY_PATH" ]; then
    printf '%s' "$REGISTRY_EMPTY"
    return 0
  fi
  if [ -r "$REGISTRY_PATH" ] && jq empty "$REGISTRY_PATH" >/dev/null 2>&1; then
    cat "$REGISTRY_PATH"
    return 0
  fi
  printf 'registry.sh: %s exists but could not be read as JSON. Refusing to proceed until this is fixed.\n' "$REGISTRY_PATH" >&2
  return 1
}

# Replaces the store with the content given on stdin. Creates the parent directory and the file
# itself on first use. Writes to a temp file beside the target and renames it into place, so a
# concurrent reader sees either the old content or the new, never a partial write.
registry__write() {
  local dir tmp
  dir="$(dirname -- "$REGISTRY_PATH")"
  mkdir -p -- "$dir" || { printf 'registry.sh: cannot create %s\n' "$dir" >&2; return 1; }
  tmp="$(mktemp "${REGISTRY_PATH}.XXXXXX")" || {
    printf 'registry.sh: cannot create a temp file beside %s\n' "$REGISTRY_PATH" >&2
    return 1
  }
  # No RETURN trap here: this library is sourced into whatever shell runs the caller, and RETURN
  # is a bash-only trap event. zsh accepts the word but never fires it, so the temp file would
  # never be cleaned up on an early return. Each exit path below removes it explicitly instead.
  if ! cat > "$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi
  if ! mv -f -- "$tmp" "$REGISTRY_PATH"; then
    rm -f -- "$tmp"
    return 1
  fi
}

# ---------------------------------------------------------------------------------------------
# Public functions
# ---------------------------------------------------------------------------------------------

registry_resolve_by_directory() {
  registry__require_jq || return 1
  local dir="${1:?registry_resolve_by_directory: a directory is required}" match
  dir="$(registry__canon "$dir")"

  match="$(registry__current | jq -c --arg d "$dir" '
    [ .projects[]?
      | select((.codePath // "") != "")
      | . as $p
      | ($p.codePath | sub("/+$"; "")) as $c
      | select($d == $c or ($d | startswith($c + "/")))
      | $p + {_matchLen: ($c | length)}
    ]
    | sort_by(._matchLen) | last // empty | del(._matchLen)
  ' 2>/dev/null)" || return 1

  [ -n "$match" ] || return 1
  printf '%s\n' "$match"
}

registry_add_project() {
  registry__require_jq || return 1
  local codepath="${1:?registry_add_project: a codePath is required}"
  local projectpath="${2:?registry_add_project: a projectPath is required}"
  local name="${3:?registry_add_project: a name is required}"
  codepath="$(registry__canon "$codepath")"
  projectpath="$(registry__canon "$projectpath")"

  local current
  current="$(registry__current)" || return 1

  if printf '%s' "$current" | jq -e --arg c "$codepath" \
      'any(.projects[]?; (.codePath // "" | sub("/+$"; "")) == $c)' >/dev/null 2>&1; then
    printf 'registry_add_project: codePath is already registered: %s\n' "$codepath" >&2
    return 1
  fi

  local now new
  now="$(date -u +%Y-%m-%d)"
  new="$(printf '%s' "$current" | jq --arg c "$codepath" --arg p "$projectpath" --arg n "$name" --arg t "$now" '
    .version = 1
    | .projects += [{codePath: $c, projectPath: $p, name: $n, lastAccessed: $t, state: "active"}]
  ')" || return 1
  printf '%s' "$new" | registry__write
}

registry_touch_last_accessed() {
  registry__require_jq || return 1
  local projectpath="${1:?registry_touch_last_accessed: a projectPath is required}"
  projectpath="$(registry__canon "$projectpath")"

  local current
  current="$(registry__current)" || return 1

  if ! printf '%s' "$current" | jq -e --arg p "$projectpath" \
      'any(.projects[]?; (.projectPath // "" | sub("/+$"; "")) == $p)' >/dev/null 2>&1; then
    printf 'registry_touch_last_accessed: no project registered at: %s\n' "$projectpath" >&2
    return 1
  fi

  local now new
  now="$(date -u +%Y-%m-%d)"
  new="$(printf '%s' "$current" | jq --arg p "$projectpath" --arg t "$now" '
    (.projects[] | select((.projectPath // "" | sub("/+$"; "")) == $p) | .lastAccessed) = $t
  ')" || return 1
  printf '%s' "$new" | registry__write
}

registry_set_state() {
  registry__require_jq || return 1
  local projectpath="${1:?registry_set_state: a projectPath is required}"
  local state="${2:?registry_set_state: a state is required}"
  case "$state" in
    active|complete|archived) ;;
    *)
      printf 'registry_set_state: state must be active, complete or archived, got: %s\n' "$state" >&2
      return 1
      ;;
  esac
  projectpath="$(registry__canon "$projectpath")"

  local current
  current="$(registry__current)" || return 1

  if ! printf '%s' "$current" | jq -e --arg p "$projectpath" \
      'any(.projects[]?; (.projectPath // "" | sub("/+$"; "")) == $p)' >/dev/null 2>&1; then
    printf 'registry_set_state: no project registered at: %s\n' "$projectpath" >&2
    return 1
  fi

  local new
  new="$(printf '%s' "$current" | jq --arg p "$projectpath" --arg s "$state" '
    (.projects[] | select((.projectPath // "" | sub("/+$"; "")) == $p) | .state) = $s
  ')" || return 1
  printf '%s' "$new" | registry__write
}

registry_remove_project() {
  registry__require_jq || return 1
  local projectpath="${1:?registry_remove_project: a projectPath is required}"
  projectpath="$(registry__canon "$projectpath")"

  local current
  current="$(registry__current)" || return 1

  if ! printf '%s' "$current" | jq -e --arg p "$projectpath" \
      'any(.projects[]?; (.projectPath // "" | sub("/+$"; "")) == $p)' >/dev/null 2>&1; then
    printf 'registry_remove_project: no project registered at: %s\n' "$projectpath" >&2
    return 1
  fi

  local new
  new="$(printf '%s' "$current" | jq --arg p "$projectpath" '
    .projects = [ (.projects // [])[] | select((.projectPath // "" | sub("/+$"; "")) != $p) ]
  ')" || return 1
  printf '%s' "$new" | registry__write
}

registry_list_projects() {
  registry__require_jq || return 1
  local current
  current="$(registry__current)" || return 1

  if [ "$#" -eq 0 ]; then
    printf '%s' "$current" | jq -c '(.projects // []) | sort_by(.lastAccessed) | reverse | .[]'
    return $?
  fi

  local states_json
  states_json="$(printf '%s\n' "$@" | jq -R . | jq -sc .)" || return 1
  printf '%s' "$current" | jq -c --argjson states "$states_json" '
    (.projects // [])
    | map(select(.state as $s | $states | index($s) != null))
    | sort_by(.lastAccessed) | reverse | .[]
  '
}

registry_record_declined_offer() {
  registry__require_jq || return 1
  local directory="${1:?registry_record_declined_offer: a directory is required}"
  directory="$(registry__canon "$directory")"

  local current
  current="$(registry__current)" || return 1

  local now new
  now="$(date -u +%Y-%m-%d)"
  new="$(printf '%s' "$current" | jq --arg d "$directory" --arg t "$now" '
    .version = 1
    | .declinedOffers = (
        [ (.declinedOffers // [])[] | select((.directory // "" | sub("/+$"; "")) != $d) ]
        + [{directory: $d, declinedAt: $t}]
      )
  ')" || return 1
  printf '%s' "$new" | registry__write
}

registry_read_declined_offer() {
  registry__require_jq || return 1
  local dir="${1:?registry_read_declined_offer: a directory is required}" match
  dir="$(registry__canon "$dir")"

  match="$(registry__current | jq -c --arg d "$dir" '
    [ (.declinedOffers // [])[]?
      | select((.directory // "") != "")
      | . as $r
      | ($r.directory | sub("/+$"; "")) as $c
      | select($d == $c or ($d | startswith($c + "/")))
      | $r + {_matchLen: ($c | length)}
    ]
    | sort_by(._matchLen) | last // empty | del(._matchLen)
  ' 2>/dev/null)" || return 1

  [ -n "$match" ] || return 1
  printf '%s\n' "$match"
}

registry_record_directory_choice() {
  registry__require_jq || return 1
  local directory="${1:?registry_record_directory_choice: a directory is required}"
  local project="${2:?registry_record_directory_choice: a project name is required}"
  directory="$(registry__canon "$directory")"

  local current
  current="$(registry__current)" || return 1

  local now new
  now="$(date -u +%Y-%m-%d)"
  new="$(printf '%s' "$current" | jq --arg d "$directory" --arg p "$project" --arg t "$now" '
    .version = 1
    | .directoryChoices = (
        [ (.directoryChoices // [])[] | select((.directory // "" | sub("/+$"; "")) != $d) ]
        + [{directory: $d, project: $p, chosenAt: $t}]
      )
  ')" || return 1
  printf '%s' "$new" | registry__write
}

registry_read_directory_choice() {
  registry__require_jq || return 1
  local directory="${1:?registry_read_directory_choice: a directory is required}" match
  directory="$(registry__canon "$directory")"

  match="$(registry__current | jq -c --arg d "$directory" '
    (.directoryChoices // [])[]? | select((.directory // "" | sub("/+$"; "")) == $d)
  ' 2>/dev/null)" || return 1

  [ -n "$match" ] || return 1
  printf '%s\n' "$match"
}

registry_rebuild() {
  registry__require_jq || return 1
  local projects_home="${1:-${AIDA_PROJECTS_HOME:-$HOME/.claude/aida/projects}}"

  if [ -e "$projects_home" ] && [ ! -d "$projects_home" ]; then
    printf 'registry_rebuild: not a directory: %s\n' "$projects_home" >&2
    return 1
  fi

  local projects_json='[]' warned=0 listing
  listing=""
  if [ -d "$projects_home" ]; then
    listing="$(find "$projects_home" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)"
  fi

  # A herestring, not a pipe, so the loop body runs in this shell and projects_json survives past
  # the loop: piping "find | while read" into bash puts the loop in a subshell, and every update
  # to projects_json inside it would be lost the moment the loop ends.
  local entry proj_file row proj_path last
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    proj_file="$entry/project.json"
    [ -e "$proj_file" ] || continue

    if [ ! -r "$proj_file" ] || ! jq empty "$proj_file" >/dev/null 2>&1; then
      printf 'registry_rebuild: skipping %s, project.json is missing or unreadable as JSON.\n' "$entry" >&2
      warned=1
      continue
    fi

    row="$(jq -c 'select((.codePath // "") != "" and (.name // "") != "") | {codePath, name, state: (.state // "active")}' "$proj_file" 2>/dev/null)"
    if [ -z "$row" ]; then
      printf 'registry_rebuild: skipping %s, project.json has no codePath or no name.\n' "$entry" >&2
      warned=1
      continue
    fi

    proj_path="$(registry__canon "$entry")"
    last="$(git -C "$entry" log -1 --format=%cd --date=short -- . 2>/dev/null)"
    [ -n "$last" ] || last="$(date -u +%Y-%m-%d)"
    row="$(printf '%s' "$row" | jq -c --arg p "$proj_path" --arg t "$last" '. + {projectPath: $p, lastAccessed: $t}')"
    projects_json="$(printf '%s' "$projects_json" | jq -c --argjson r "$row" '. + [$r]')"
  done <<< "$listing"

  local new
  new="$(jq -n --argjson projects "$projects_json" \
    '{version: 1, projects: $projects, declinedOffers: [], directoryChoices: []}')" || return 1
  printf '%s' "$new" | registry__write || return 1

  if [ "$warned" -eq 1 ]; then
    printf 'registry_rebuild: rebuilt with warnings. Some project folders were skipped; see above.\n' >&2
  fi
  return 0
}
