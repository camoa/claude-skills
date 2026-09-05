#!/usr/bin/env bash
# create-or-switch.sh — the two writing actions of the project skill.
#
# Usage:
#   create-or-switch.sh create <codePath> <framework>...
#   create-or-switch.sh switch <name-or-path>
#
# Set AIDA_RUN_MODE=autonomous in the environment before calling either action to have the
# check that runs at the end record that no person was present (forwarded as check-project.sh
# --autonomous). Unset, or any other value, means interactive — the safe default (decision 19).
#
# "report" is not one of this script's actions. Resolving the current directory against the
# registry is a one-line call to registry.sh once sourced, and the skill body makes that call
# directly rather than through a script that would otherwise do nothing but relay it.
#
# Depends on, both shipped by the other builders of this same contract:
#   ${CLAUDE_PLUGIN_ROOT}/scripts/lib/registry.sh   — a library, sourced here, never executed.
#                                                      Uses registry_add_project. Every other
#                                                      registry read in this script (switch's
#                                                      lookup) reads the store file directly
#                                                      instead, per registry.sh's own header
#                                                      comment: an exact-match lookup by either
#                                                      address is not one of its four public
#                                                      functions, and composing it from the raw
#                                                      store, whose shape the build contract
#                                                      fixes (§2), is what that comment asks
#                                                      whoever builds this skill to do.
#   ${CLAUDE_PLUGIN_ROOT}/scripts/check-project.sh  — the check. Never duplicated: this script
#                                                      writes project.json and the registry
#                                                      entry, then hands off to the check for
#                                                      the read-back and the report.
#
# Never writes the plugin's own name anywhere. Never asks a question: both actions here run
# only after the skill body has already resolved the code path and the framework list (create)
# or has a target string (switch). A script cannot ask; the skill body does that first.

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT is not set}"
REGISTRY_LIB="${PLUGIN_ROOT}/scripts/lib/registry.sh"
CHECK_SCRIPT="${PLUGIN_ROOT}/scripts/check-project.sh"
REGISTRY_FILE="${AIDA_REGISTRY_PATH:-$HOME/.claude/aida/registry.json}"
PROJECTS_HOME="${AIDA_PROJECTS_HOME:-$HOME/.claude/aida/projects}"

check_flags=()
if [ "${AIDA_RUN_MODE:-interactive}" = "autonomous" ]; then
  check_flags=(--autonomous)
fi

usage() {
  echo "usage: create-or-switch.sh create <codePath> <framework>..." >&2
  echo "       create-or-switch.sh switch <name-or-path>" >&2
  exit 3
}

require_jq() {
  command -v jq >/dev/null 2>&1 || { echo "jq is required and was not found on PATH" >&2; exit 3; }
}

# Same canonicalization registry.sh applies to every path it stores (registry__canon there),
# repeated here so project.json's own codePath always matches what the registry ends up
# holding for the same project — a relative path given on the command line must not become two
# different strings depending on which file it landed in.
canon_path() {
  local input="$1" resolved
  resolved="$(cd "$input" 2>/dev/null && pwd -P)" || resolved=""
  if [ -z "$resolved" ]; then
    resolved="$(realpath -m -- "$input" 2>/dev/null)" || resolved="$input"
  fi
  resolved="${resolved%/}"
  [ -n "$resolved" ] || resolved="/"
  printf '%s' "$resolved"
}

# Turns the code path's own last segment into a filesystem-safe folder name. The project has
# no name field of its own (that field has no reader anywhere and lives in the human document
# instead), so the folder needs a name derived from something that always exists: the code
# path. Not settled by any decision; recorded as a choice in the build report.
slugify() {
  local base
  base="$(basename "${1%/}")"
  base="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  [ -n "$base" ] && printf '%s' "$base" || printf 'project'
}

# Appends -2, -3, ... only when the plain slug already names a different project folder.
unique_project_path() {
  local slug="$1" candidate n=2
  candidate="${PROJECTS_HOME}/${slug}"
  while [ -e "$candidate" ]; do
    candidate="${PROJECTS_HOME}/${slug}-${n}"
    n=$((n + 1))
  done
  printf '%s' "$candidate"
}

# Ignore everything, then name the text types back in one by one (decision 7). A file type
# nobody has named yet stays ignored, and the check reports it rather than letting it vanish.
write_gitignore() {
  cat > "$1/.gitignore" <<'EOF'
# Whitelist, not a blacklist: everything is ignored until named back in below.
*
!*/
!.gitignore
!*.md
!*.json
!*.txt
EOF
}

do_create() {
  local code_path
  code_path="$(canon_path "$1")"; shift
  [ "$#" -ge 1 ] || { echo "MISSING: frameworks" >&2; exit 10; }
  local frameworks=("$@")
  require_jq

  [ -d "$code_path" ] || echo "NOTE: ${code_path} does not exist yet; it will when the code is written there." >&2

  mkdir -p "$PROJECTS_HOME"
  local slug project_path
  slug="$(slugify "$code_path")"
  project_path="$(unique_project_path "$slug")"
  mkdir -p "$project_path/records"

  local fw_json code_path_json
  fw_json="$(printf '%s\n' "${frameworks[@]}" | jq -R . | jq -s .)"
  code_path_json="$(printf '%s' "$code_path" | jq -R .)"

  # Defaults are the build contract's field list exactly (§1). Every field past codePath and
  # frameworks starts empty; each is filled in by the stage that first needs it, never by this
  # script. precedence starts at 1, the schema's own minimum for that field.
  jq -n \
    --argjson codePath "$code_path_json" \
    --argjson frameworks "$fw_json" \
    '{
      schemaVersion: 1,
      codePath: $codePath,
      frameworks: $frameworks,
      processRecipes: [],
      sources: [
        {location: "hosted-catalog", provides: ["guides", "playbooks", "processRecipes"], precedence: 1}
      ],
      sourceOverrides: {},
      worktreeByDefault: false,
      visualRegression: null,
      e2e: null,
      memoryHook: {installed: false, version: null},
      agenticRecipes: [],
      taskRule: null
    }' > "$project_path/project.json"

  cat > "$project_path/project_state.md" <<EOF
# Project

**Code path:** ${code_path}
**Frameworks:** $(printf '%s, ' "${frameworks[@]}" | sed 's/, $//')

Notes for a person go here. Nothing on this page is read by a script.
EOF

  write_gitignore "$project_path"

  git -C "$project_path" init -q
  git -C "$project_path" add .gitignore project.json project_state.md
  git -C "$project_path" \
    -c user.email="aida@localhost" -c user.name="aida" \
    commit -q -m "Create project for ${code_path}"

  # shellcheck source=/dev/null
  source "$REGISTRY_LIB"
  if ! registry_add_project "$code_path" "$project_path"; then
    echo "The project folder was created at ${project_path}, but the registry entry was not" >&2
    echo "written — see the message above. A session in ${code_path} will not find it until" >&2
    echo "that is fixed by hand." >&2
    exit 3
  fi

  echo "CREATED: ${project_path}"
  "$CHECK_SCRIPT" "$project_path" "${check_flags[@]}"
}

do_switch() {
  local target="$1"
  require_jq

  if [ ! -r "$REGISTRY_FILE" ]; then
    echo "NOT FOUND: ${target} (no registry yet)" >&2
    exit 1
  fi

  # Exact match only, against either address a registry entry carries. Not the ancestor match
  # "report" uses: standing inside a project's code is one way to be recognized, and switching
  # to it by an address you already know is another, so the two lookups differ on purpose.
  local project_path
  project_path="$(jq -r --arg t "$target" '
    [.projects[]? | select(.codePath == $t or .projectPath == $t)] | first | .projectPath // empty
  ' "$REGISTRY_FILE")"

  [ -n "$project_path" ] || { echo "NOT FOUND: ${target}" >&2; exit 1; }
  [ -f "$project_path/project.json" ] || { echo "NOT FOUND: ${project_path}/project.json" >&2; exit 3; }

  echo "PROJECT: ${project_path}"
  cat "$project_path/project.json"
  "$CHECK_SCRIPT" "$project_path" "${check_flags[@]}"
}

action="${1:-}"
[ -n "$action" ] && shift || true

case "$action" in
  create)
    [ "$#" -ge 1 ] || { echo "MISSING: codePath" >&2; exit 10; }
    do_create "$@"
    ;;
  switch)
    [ "$#" -eq 1 ] || usage
    do_switch "$1"
    ;;
  *)
    usage
    ;;
esac
