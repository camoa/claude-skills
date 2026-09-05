#!/usr/bin/env bash
# registry.sh — the one store mapping a directory to a project (02-decisions.md D9, D10).
#
# Version 5 kept three separate stores for this: a registry keyed on code path, a session cache
# keyed on a hash of whatever directory a command last ran in, and a file recording which
# directories declined a project. The session cache is dropped outright (D9: "the working folder
# is not registered" — a session resolves fresh from codePath every time, nothing is cached
# across sessions). The other two merge into the single file this library operates on.
#
# Store: $AIDA_REGISTRY_PATH, default ~/.claude/aida/registry.json (build-contract.md §2). Not
# inside the plugin's own data directory — nothing durable belongs there (01-decisions.md P1-D6),
# and this path is named for the plugin's eventual released identity so it needs no move at the
# release rename (build-contract.md §2, flagged there as unsettled; followed as written here).
#
#   { "version": 1,
#     "projects": [ {codePath, projectPath, created, lastAccessed} ],
#     "declinedOffers": [ {directory, declinedAt} ] }
#
# This library does not ship the store file. The first write creates it; a read against a missing
# store answers as if it were empty, the same way project-for-cwd.sh in version 5 treated a
# missing registry as "unregistered" rather than an error. A store that exists but will not parse
# is a different outcome: it is corrupt, not empty, and treating it as empty would let the next
# write replace it with a fresh skeleton and lose every registered project. So a read against a
# corrupt store reports the fact to stderr and fails, and every write function refuses to proceed
# past a read that failed.
#
# Public functions — the four the build contract names for this library (build-contract.md §6):
#
#   registry_resolve_by_directory <dir>
#     Deepest matching codePath wins (D9): among every registered project whose codePath is <dir>
#     itself or an ancestor of it, the one with the longest codePath. Prints that project entry as
#     one JSON object on stdout and exits 0; prints nothing and exits 1 when no project matches.
#
#   registry_add_project <codePath> <projectPath>
#     Adds one entry with created and lastAccessed set to today (UTC date, YYYY-MM-DD). Exits 1
#     without writing when codePath is already registered — version 5's live registry held two
#     entries for one project under different names, and one became unreachable by lookup; this
#     refuses the duplicate instead of creating a second entry for a path already tracked.
#
#   registry_record_declined_offer <directory>
#     Records that <directory> was offered a project and said no. Answering again for the same
#     directory replaces the row rather than appending a second one, so the last answer is the
#     answer. Always exits 0.
#
#   registry_touch_last_accessed <projectPath>
#     Sets lastAccessed to today for the project at <projectPath>. Exits 1 without writing when no
#     project is registered at that path.
#
# What this library does NOT do, because no decision names it and it is not one of the four
# functions above: it does not look up a project by name for "switch", and it does not check
# whether a directory already has a declined-offer row. Both are real needs of the project skill's
# report and switch actions (build-contract.md §4) that the four named functions do not cover on
# their own; whatever builds that skill composes them from the raw store (readable with
# registry__current, below) or extends this library.
#
# A miss returns non-zero and prints nothing to stdout; every function that can fail for a
# reason a caller should see prints one line to stderr first. Every write replaces the whole file
# in one step (write to a temp file, then `mv`), so a reader never sees a half-written store — the
# pattern version 5's project-offer-write.sh used, kept here because it holds up.
#
# Portability: bash 3.2+, matching this marketplace's other sourced library
# (dev-guides-navigator/scripts/dev-guides-store.sh). No mapfile, no associative arrays.
#
# This file is a library. Source it; do not run it.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  printf 'registry.sh: this is a library, meant to be sourced, not run directly.\n' >&2
  exit 1
fi

set -uo pipefail  # not -e: a sourced file must not exit the caller's shell on a miss it should
                   # instead report through a return code, e.g. no match in resolve-by-directory.

REGISTRY_PATH="${AIDA_REGISTRY_PATH:-$HOME/.claude/aida/registry.json}"
REGISTRY_EMPTY='{"version":1,"projects":[],"declinedOffers":[]}'

# ---------------------------------------------------------------------------------------------
# Internal helpers (prefixed registry__, not part of the four public functions above)
# ---------------------------------------------------------------------------------------------

registry__require_jq() {
  command -v jq >/dev/null 2>&1 && return 0
  printf 'registry.sh: jq is required and was not found on PATH.\n' >&2
  return 1
}

# Canonicalize a path so a trailing slash, a relative path, or "." compares equal to the absolute
# form already stored. Falls back to a textual resolution when the directory does not exist yet
# (a codePath named for a not-yet-created directory is still a legitimate value, per D2).
registry__canon() {
  local input="$1" resolved parent base
  resolved="$(cd "$input" 2>/dev/null && pwd -P)" || resolved=""
  if [ -z "$resolved" ]; then
    # "$input" does not exist yet. `realpath -m` is GNU-only (missing on BSD and macOS
    # realpath); check-project.sh's header notes the same portability limit and avoids it the
    # same way: cd into the closest existing ancestor and read pwd, then append what is left.
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
# overwrite this file" and refuse to proceed on the second.
registry__current() {
  if [ ! -e "$REGISTRY_PATH" ]; then
    printf '%s' "$REGISTRY_EMPTY"
    return 0
  fi
  if [ -r "$REGISTRY_PATH" ] && jq empty "$REGISTRY_PATH" >/dev/null 2>&1; then
    cat "$REGISTRY_PATH"
    return 0
  fi
  printf 'registry.sh: %s exists but could not be read as JSON. Refusing to write until this is fixed.\n' "$REGISTRY_PATH" >&2
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
  # No RETURN trap here: this library is sourced into whatever shell runs the skill, and RETURN
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
  new="$(printf '%s' "$current" | jq --arg c "$codepath" --arg p "$projectpath" --arg t "$now" '
    .version = 1
    | .projects += [{codePath: $c, projectPath: $p, created: $t, lastAccessed: $t}]
  ')" || return 1
  printf '%s' "$new" | registry__write
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
