#!/usr/bin/env bash
# project-actions.sh: the deterministic half of the project skill.
#
# The skill body decides what to say and what to ask; this script never asks a question. Every
# fact it needs arrives already resolved, as an argument. It writes project.json, writes the
# notes file, keeps the project's own git repository, and keeps the registry in step, then hands
# off to the shared check for the read-back and the report. This mirrors ideal/project.md's own
# split: "It proposes and you confirm" is the skill body's job; producing the files from what was
# confirmed is this script's job.
#
# Depends on, both shipped by other builders of this same part and never edited here:
#   ${CLAUDE_PLUGIN_ROOT}/scripts/lib/registry.sh        (sourced, never executed)
#   ${CLAUDE_PLUGIN_ROOT}/scripts/check-project.sh        (the project check)
#   ${CLAUDE_PLUGIN_ROOT}/scripts/check-commit-shape.sh   (the commit-message shape check)
#   ${CLAUDE_PLUGIN_ROOT}/templates/project-commit.md     (the five-field shape those two check)
#
# Usage: any action this script does not recognize, including none, prints the usage function
# below and exits 3. That function is the only copy.
#
# read-projects-base prints the projects-folder base chosen the first time a project was ever
# created ($AIDA_SETTINGS_PATH, default ~/.claude/aida/settings.json, key "projectsBase"), or
# prints nothing and exits 1 when no project has ever been created. ideal/project.md, "Starting a
# new project": this value is not a question after the first project, so the skill body asks it
# only when this prints nothing, and passes whatever it decided to `create --projects-home`.
# `create` then records that value the first time, and only the first time: a later `create`
# passing a different `--projects-home` is a one-off choice for that one project, never a change
# to the standing default.
#
# Pass --run-mode autonomous as the first argument of any action to have the check that runs at
# the end record that no person was present. Absent, or any other value, means interactive, the
# safe default (foundations.md, Run mode). It is an argument rather than an environment variable
# prefix because Claude Code matches a Bash permission rule against the whole command line and
# strips only a fixed list of known-safe variable prefixes, so a command written as
# AIDA_RUN_MODE=autonomous script.sh does not match a rule naming script.sh and asks for approval
# every time. AIDA_RUN_MODE is still read as a fallback, for a caller that is not the skill.
#
# What reaches stdout is what reaches the orchestrator's context. A project is named by one
# `project:` line carrying its name, state, code path and folder, never by its registry row or
# its project file. The check's own report follows where the skill shows it to the person.
#
# A reader that cannot read fails loudly here too: every action that cannot do its job prints
# why to stderr and exits 3. A miss that is a real, expected outcome, such as switch finding
# nothing, exits 1 and prints nothing to stdout, never confused with 3.

set -uo pipefail  # not -e: several branches test a command's exit code on purpose.

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT is not set}"
REGISTRY_LIB="${PLUGIN_ROOT}/scripts/lib/registry.sh"
CHECK_SCRIPT="${PLUGIN_ROOT}/scripts/check-project.sh"
COMMIT_SHAPE_SCRIPT="${PLUGIN_ROOT}/scripts/check-commit-shape.sh"
REGISTRY_FILE="${AIDA_REGISTRY_PATH:-$HOME/.claude/aida/registry.json}"
PROJECTS_HOME_DEFAULT="${AIDA_PROJECTS_HOME:-$HOME/.claude/aida/projects}"
SETTINGS_FILE="${AIDA_SETTINGS_PATH:-$HOME/.claude/aida/settings.json}"

RUN_MODE="${AIDA_RUN_MODE:-interactive}"
if [ "${1:-}" = "--run-mode" ]; then
  [ $# -ge 2 ] || { printf 'project-actions: --run-mode needs a value\n' >&2; exit 3; }
  RUN_MODE="$2"
  shift 2
fi

check_flags=()
if [ "$RUN_MODE" = "autonomous" ]; then
  check_flags=(--autonomous)
fi

die3() {
  printf 'project-actions: %s\n' "$1" >&2
  exit 3
}

usage() {
  cat <<'EOF' >&2
usage: project-actions.sh create --name <name> --path <codePath> [--projects-home <dir>]
                                  [--framework <fw>]...
       project-actions.sh report
       project-actions.sh switch <name-or-codePath>
       project-actions.sh list [active|complete|archived]...
       project-actions.sh state <name-or-codePath> <active|complete|archived> -- <why...>
       project-actions.sh set-code-path <name-or-codePath> <newCodePath>
       project-actions.sh set-worktree-default <name-or-codePath> <true|false>
       project-actions.sh unregister <name-or-codePath>
       project-actions.sh [--run-mode <interactive|autonomous>] task-rule <name-or-codePath> [--decline] -- <why...>
       project-actions.sh task-rule-remove <name-or-codePath>
       project-actions.sh uninstall <name-or-codePath>
       project-actions.sh record-declined <directory>
       project-actions.sh rebuild-registry [projectsHome]
       project-actions.sh read-projects-base
EOF
}

require_jq() { command -v jq >/dev/null 2>&1 || die3 "jq is required and was not found on PATH"; }
require_jq

# shellcheck source=/dev/null
source "$REGISTRY_LIB"

# ------------------------------------------------------------------------------------------------
# Small, portable helpers shared by more than one action below.
# ------------------------------------------------------------------------------------------------

# One canonicaliser, the library's. This file used to carry its own copy, and when the library's
# was fixed for a symlinked ancestor the copy was not, so one real folder canonicalised two ways
# depending on which script wrote it.
canon_path() {
  registry__canon "$1"
}

strip_slash() { local p="$1"; [ "$p" = "/" ] && printf '/' || printf '%s' "${p%/}"; }

# The projects-folder base is not a fact any frozen schema carries: it is a standing preference
# about where new project folders go, asked once ever and reused after (ideal/project.md,
# "Starting a new project"), not a per-project value. It lives in its own small file, separate
# from the registry, so registry-schema.json's frozen shape never has to carry it.
settings__current() {
  if [ ! -e "$SETTINGS_FILE" ]; then printf '{}'; return 0; fi
  if [ -r "$SETTINGS_FILE" ] && jq empty "$SETTINGS_FILE" >/dev/null 2>&1; then
    cat "$SETTINGS_FILE"
    return 0
  fi
  printf 'project-actions: %s exists but could not be read as JSON.\n' "$SETTINGS_FILE" >&2
  return 1
}

settings__write() {
  local dir tmp
  dir="$(dirname -- "$SETTINGS_FILE")"
  mkdir -p -- "$dir" || return 1
  tmp="$(mktemp "${SETTINGS_FILE}.XXXXXX")" || return 1
  if ! cat > "$tmp"; then rm -f -- "$tmp"; return 1; fi
  mv -f -- "$tmp" "$SETTINGS_FILE"
}

settings_get_projects_base() {
  local cur v
  cur="$(settings__current)" || return 1
  v="$(printf '%s' "$cur" | jq -r '.projectsBase // empty')"
  [ -n "$v" ] || return 1
  printf '%s' "$v"
}

# Writes the base only when none is recorded yet, so the first project ever created decides the
# default and every later one reuses it silently, never asked again.
settings_set_projects_base_if_unset() {
  local base="$1" cur
  cur="$(settings__current)" || return 1
  if printf '%s' "$cur" | jq -e '(.projectsBase // "") | length > 0' >/dev/null 2>&1; then
    return 0
  fi
  printf '%s' "$cur" | jq --arg b "$base" '.projectsBase = $b' | settings__write
}

# Looks a target up by its exact name or its exact codePath (never by ancestry, that is
# registry_resolve_by_directory's job, a different question). Prints the matching registry row as
# one JSON object and exits 0, or prints nothing and exits 1. Reads the store file directly: an
# exact-match lookup by either address is not one of registry.sh's own public functions, and
# composing it from the raw store is what that library's own header asks a caller to do.
resolve_target() {
  local target="$1" canon
  [ -r "$REGISTRY_FILE" ] || return 1
  canon="$(canon_path "$target")"
  jq -c --arg n "$target" --arg c "$canon" '
    [.projects[]? | select(.name == $n or (.codePath // "" | sub("/+$"; "")) == $c)] | first // empty
  ' "$REGISTRY_FILE" 2>/dev/null | grep -q . && \
  jq -c --arg n "$target" --arg c "$canon" '
    [.projects[]? | select(.name == $n or (.codePath // "" | sub("/+$"; "")) == $c)] | first
  ' "$REGISTRY_FILE" 2>/dev/null
}

# Renders the five-field commit shape from templates/project-commit.md, checks its own shape
# before use (never trust an unrendered corner case to slip past silently), then commits it as
# the project folder's own git identity. AIDA commits its own files in the project folder and
# never in the code repository. Every git call below is "-C <path>", and codePath is
# never passed to git as a working directory anywhere in this file.
commit_project() {
  local project_path="$1" subject="$2" why="$3" principle="$4" ruled_out="$5" task="$6" stage="$7"
  local msg_file
  msg_file="$(mktemp)" || die3 "cannot create a temp file for the commit message"
  {
    printf '%s\n' "$subject"
    printf '\n'
    printf 'Why: %s\n' "$why"
    printf 'Principle: %s\n' "$principle"
    printf 'Ruled out: %s\n' "$ruled_out"
    printf 'Task/stage: %s/%s\n' "$task" "$stage"
  } > "$msg_file"

  if [ -x "$COMMIT_SHAPE_SCRIPT" ] || [ -f "$COMMIT_SHAPE_SCRIPT" ]; then
    if ! bash "$COMMIT_SHAPE_SCRIPT" "$msg_file" >/dev/null 2>&1; then
      rm -f "$msg_file"
      die3 "the rendered commit message did not pass its own shape check. This is a defect in project-actions.sh, not in the project being committed"
    fi
  fi

  git -C "$project_path" add -A
  if git -C "$project_path" diff --cached --quiet 2>/dev/null; then
    rm -f "$msg_file"
    return 0
  fi
  git -C "$project_path" \
    -c user.email="aida@localhost" -c user.name="aida" \
    commit -q -F "$msg_file"
  local rc=$?
  rm -f "$msg_file"
  return $rc
}

# Writes one top-level field into a project's own project.json, through a temporary file, so a
# failure partway never leaves a half-written file. $1 the project folder, $2 what to say when the
# write fails, $3 onward the jq arguments and the expression.
write_project_field() {
  local project_path="$1" what="$2" file tmp
  shift 2
  file="$project_path/project.json"
  tmp="$(mktemp)" || die3 "cannot create a temp file"
  jq "$@" "$file" > "$tmp" && mv "$tmp" "$file" || { rm -f "$tmp"; die3 "$what"; }
}

run_check() {
  local project_path="$1"
  "$CHECK_SCRIPT" "$project_path" "${check_flags[@]}"
  return $?
}

# The one summary printer: one line per registry row. $1 the row, $2 an optional trailing note.
project_line() {
  printf '%s' "$1" | jq -r --arg extra "${2:-}" '
    "project: " + (.name // "?") + " state=" + (.state // "?")
      + " code-path=" + (.codePath // "?") + " path=" + (.path // "?")
      + (if $extra == "" then "" else " " + $extra end)'
}

# ------------------------------------------------------------------------------------------------
# create
# ------------------------------------------------------------------------------------------------

do_create() {
  local name="" code_path="" frameworks=() projects_home="$PROJECTS_HOME_DEFAULT"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --name) name="${2:?--name needs a value}"; shift 2 ;;
      --path) code_path="${2:?--path needs a value}"; shift 2 ;;
      --projects-home) projects_home="${2:?--projects-home needs a value}"; shift 2 ;;
      --framework) frameworks+=("${2:?--framework needs a value}"); shift 2 ;;
      *) die3 "create: unrecognized argument: $1" ;;
    esac
  done

  [ -n "$name" ] || die3 "create: --name is required"
  [ -n "$code_path" ] || die3 "create: --path is required"
  [ "${#frameworks[@]}" -ge 1 ] || die3 "create: at least one --framework is required"

  case "$name" in
    [a-z]*) : ;;
    *) die3 "create: name '$name' must start with a lowercase letter" ;;
  esac
  case "$name" in
    *[!a-z0-9_]*) die3 "create: name '$name' must contain only lowercase letters, digits and underscores" ;;
  esac

  code_path="$(canon_path "$code_path")"

  # The library's own reader, not a raw read of REGISTRY_FILE: registry__current tells a missing
  # store (fine, nothing registered yet) apart from a corrupt one (refuses and fails loudly), so
  # a store that will not parse stops creation here, before the folder, the git init or the first
  # commit, rather than surfacing only when registry_add_project makes the same read again at the
  # end (foundations.md, Honesty: a reader that cannot read fails loudly).
  local registry_snapshot
  registry_snapshot="$(registry__current)" || die3 "the registry could not be read; nothing was written. See the error above."

  if printf '%s' "$registry_snapshot" | jq -e --arg c "$code_path" \
      'any(.projects[]?; (.codePath // "" | sub("/+$"; "")) == $c)' >/dev/null 2>&1; then
    die3 "a project is already registered for $code_path. Nothing was written."
  fi
  if printf '%s' "$registry_snapshot" | jq -e --arg n "$name" \
      'any(.projects[]?; .name == $n)' >/dev/null 2>&1; then
    die3 "the name '$name' is already registered. Choose a different name."
  fi

  [ -d "$code_path" ] || printf 'project-actions: %s does not exist yet; it will when the code is written there.\n' "$code_path" >&2

  mkdir -p "$projects_home" || die3 "cannot create $projects_home"
  local project_path
  project_path="$(canon_path "$projects_home/$name")"
  [ ! -e "$project_path" ] || die3 "the project folder $project_path already exists. Pick a different name or remove that folder first."

  # The project folder and the code path are never the same folder (ideal/project.md, "What a
  # project is"). Both sides are canonicalised before they are compared. Comparing a concatenated
  # string against a canonicalised one let a trailing slash on the base slip past this guard, and
  # then AIDA's own project folder was the code folder and it committed the user's CLAUDE.md into
  # its own history.
  if [ "$project_path" = "$code_path" ]; then
    die3 "the code path and the project folder resolve to the same place ($code_path). Pick a code path outside $projects_home."
  fi

  mkdir -p "$project_path/records" || die3 "cannot create $project_path"

  local fw_json code_path_json
  fw_json="$(printf '%s\n' "${frameworks[@]}" | jq -R . | jq -s .)"
  code_path_json="$(printf '%s' "$code_path" | jq -R .)"

  # Sources, process recipes, playbook subscriptions, both optional harnesses, the memory hook and
  # the task rule all start empty or null: ideal/project.md, "Sources" and "Starting a new
  # project", declares every one of them lazily, the first time a later stage needs it. None of
  # them is asked here, and none is pre-populated with a default entry.
  jq -n \
    --argjson codePath "$code_path_json" \
    --arg name "$name" \
    --argjson frameworks "$fw_json" \
    '{
      schemaVersion: 1,
      codePath: $codePath,
      name: $name,
      frameworks: $frameworks,
      state: "active",
      processRecipes: [],
      sources: [],
      playbookSubscriptions: {},
      worktreeByDefault: false,
      visualRegression: null,
      e2e: null,
      memoryHook: {installed: false, version: null},
      taskRule: null
    }' > "$project_path/project.json" || die3 "could not write $project_path/project.json"

  cat > "$project_path/project_state.md" <<EOF
# ${name}

**Code path:** ${code_path}
**Frameworks:** $(printf '%s, ' "${frameworks[@]}" | sed 's/, $//')

Notes for a person go here. Nothing on this page is read by a script.
EOF

  # A whitelist, not a blacklist: everything is ignored until named back in. records/ is named
  # back in for .json only by the line above it, so it is re-ignored on its own line below.
  # the check overwrites records/check-project.json on every run, and a file that changes on
  # every check is a derived value, never something to commit (foundations.md, State). The
  # unanchored pattern covers a task's own records folder too: a task check writes one per task,
  # and without it every check put a derived file into permanent history.
  cat > "$project_path/.gitignore" <<'EOF'
*
!*/
!.gitignore
!*.md
!*.json
!*.txt
/records/
records/
EOF

  git -C "$project_path" init -q || die3 "git init failed in $project_path"
  if ! commit_project "$project_path" \
      "Create project for ${code_path}" \
      "A new project needs its own git history from the first write, so later stage boundaries have somewhere to land." \
      "" \
      "" \
      "project" "creation"; then
    die3 "the first commit in $project_path failed"
  fi

  if ! registry_add_project "$code_path" "$project_path" "$name"; then
    printf 'project-actions: the project folder was created at %s, but the registry entry was not\n' "$project_path" >&2
    printf 'written; see the message above. A session in %s will not find it until that is\n' "$code_path" >&2
    printf 'fixed by hand.\n' >&2
    exit 3
  fi

  settings_set_projects_base_if_unset "$projects_home" \
    || printf 'project-actions: the project was created, but its projects-home base could not be recorded as the standing default. This has no effect on this project; it only means the next creation may be asked again.\n' >&2

  echo "CREATED: ${project_path}"
  run_check "$project_path"
  local check_rc=$?

  # Exit 5 is the check's own safety refusal (a system root, the home directory, or anything
  # above it). A refused project is never left half-registered: the folder and the registry row
  # this action just wrote are both removed, and the refusal is the only thing reported.
  if [ "$check_rc" -eq 5 ]; then
    registry_remove_project "$project_path" >/dev/null 2>&1
    rm -rf -- "$project_path"
    printf 'project-actions: %s names a refused location. Nothing was kept: the project folder and\n' "$code_path" >&2
    printf 'its registry entry were both removed. See the safety report above for the exact reason.\n' >&2
    exit 5
  fi

  return "$check_rc"
}

# ------------------------------------------------------------------------------------------------
# report: the four cases of "picking up work"
# ------------------------------------------------------------------------------------------------

do_report() {
  local cwd match
  cwd="$(pwd -P)"

  if match="$(registry_resolve_by_directory "$cwd")"; then
    echo "CASE: 1"
    project_line "$match"
    local project_path
    project_path="$(printf '%s' "$match" | jq -r '.path')"
    registry_touch_last_accessed "$project_path"
    run_check "$project_path"
    return $?
  fi

  local choice_name choice_row
  choice_row="$(registry_read_directory_choice "$cwd" 2>/dev/null)"
  if [ -n "$choice_row" ]; then
    choice_name="$(printf '%s' "$choice_row" | jq -r '.project')"
    match="$(jq -c --arg n "$choice_name" '[.projects[]? | select(.name == $n)] | first // empty' "$REGISTRY_FILE" 2>/dev/null)"
    if [ -n "$match" ] && [ "$match" != "null" ]; then
      echo "CASE: 2"
      project_line "$match"
      local project_path
      project_path="$(printf '%s' "$match" | jq -r '.path')"
      registry_touch_last_accessed "$project_path"
      run_check "$project_path"
      return $?
    fi
  fi

  echo "CASE: 4"
  local declined_row
  declined_row="$(registry_read_declined_offer "$cwd" 2>/dev/null)"
  if [ -n "$declined_row" ]; then
    echo "DECLINED: true"
  else
    echo "DECLINED: false"
  fi
  echo "PROJECTS:"
  # Offered as work: complete stops being offered and archived is not in the list unless asked
  # for (ideal/project.md, "New"). registry_list_projects filters to this when a state is named.
  local row
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    project_line "$row"
  done < <(registry_list_projects active)
  return 1
}

# ------------------------------------------------------------------------------------------------
# switch
# ------------------------------------------------------------------------------------------------

do_switch() {
  local target="${1:?switch: a name or a code path is required}" match project_path cwd
  match="$(resolve_target "$target")"
  [ -n "$match" ] || { echo "NOT FOUND: ${target}" >&2; return 1; }

  project_path="$(printf '%s' "$match" | jq -r '.path')"
  cwd="$(pwd -P)"

  # ideal/project.md, "Picking up work": a remembered choice exists for a directory that no
  # code path already answers for. Standing inside some other project's own code and switching
  # by hand is a fact about this conversation only. Persisting it would make the switch outlive
  # the session and later read as the "surprising failure" case 3 exists to prevent.
  if registry_resolve_by_directory "$cwd" >/dev/null 2>&1; then
    echo "NOTE: this directory already belongs to another project by its own code path. This switch applies to this conversation only and is not remembered."
  else
    registry_record_directory_choice "$cwd" "$(printf '%s' "$match" | jq -r '.name')"
  fi

  registry_touch_last_accessed "$project_path"
  echo "PROJECT: ${project_path}"
  project_line "$match"
  echo "project-file: ${project_path}/project.json"
  run_check "$project_path"
}

# ------------------------------------------------------------------------------------------------
# list
# ------------------------------------------------------------------------------------------------

do_list() {
  local rows
  rows="$(registry_list_projects "$@")" || return 1
  [ -n "$rows" ] || { echo "PROJECTS: (none registered)"; return 0; }
  local row cp exists
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    cp="$(printf '%s' "$row" | jq -r '.codePath')"
    if [ -d "$cp" ]; then exists="true"; else exists="false"; fi
    project_line "$row" "exists=$exists"
  done < <(printf '%s\n' "$rows")
}

# ------------------------------------------------------------------------------------------------
# state: ending a project, reversibly
# ------------------------------------------------------------------------------------------------

do_state() {
  local target="${1:?state: a name or a code path is required}"
  local new_state="${2:?state: active, complete or archived is required}"
  shift 2
  [ "${1:-}" = "--" ] && shift
  local why="$*"
  [ -n "$why" ] || why="(no reason given)"

  case "$new_state" in
    active|complete|archived) : ;;
    *) die3 "state: must be active, complete or archived, got: $new_state" ;;
  esac

  local match project_path old_state
  match="$(resolve_target "$target")"
  [ -n "$match" ] || { echo "NOT FOUND: ${target}" >&2; return 1; }
  project_path="$(printf '%s' "$match" | jq -r '.path')"
  old_state="$(jq -r '.state' "$project_path/project.json" 2>/dev/null)"

  if [ "$old_state" = "$new_state" ]; then
    echo "UNCHANGED: ${project_path} is already ${new_state}."
  else
    local tmp
    write_project_field "$project_path" "could not update state in $project_path/project.json" \
      --arg s "$new_state" '.state = $s'

    registry_set_state "$project_path" "$new_state" \
      || printf 'project-actions: project.json now says %s, but the registry row could not be updated. The check below will report the mismatch.\n' "$new_state" >&2

    commit_project "$project_path" \
      "Move to ${new_state}" \
      "$why" \
      "" \
      "" \
      "project" "$new_state" \
      || printf 'project-actions: the state change was written but not committed. Commit it by hand.\n' >&2

    echo "STATE: ${old_state} -> ${new_state}"
  fi

  # ideal/project.md, "Ending a project": closing says what is still open rather than refusing
  # or pretending. No task system is built into any part of this plugin yet, so the honest
  # answer is that this check cannot be run, not that nothing is open.
  if [ -d "$project_path/tasks" ]; then
    local open_count
    open_count="$(find "$project_path/tasks" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
    echo "OPEN TASKS: ${open_count} folder(s) under ${project_path}/tasks"
  else
    echo "OPEN TASKS: unknown. No task system has been built yet in this project, so nothing here can be listed as open or closed."
  fi

  run_check "$project_path"
}

# ------------------------------------------------------------------------------------------------
# set-code-path: changing the code path detects and proposes a candidate the same way creation
# does, not only at creation (ideal/project.md, "What stands, from version 5"). The skill body
# does the proposing and confirming; this does the write, the registry sync, and the same
# undo-on-refusal that create already performs.
# ------------------------------------------------------------------------------------------------

do_set_code_path() {
  local target="${1:?set-code-path: a name or a code path is required}"
  local new_path="${2:?set-code-path: a new code path is required}"
  local match project_path old_path
  match="$(resolve_target "$target")"
  [ -n "$match" ] || { echo "NOT FOUND: ${target}" >&2; return 1; }
  project_path="$(printf '%s' "$match" | jq -r '.path')"
  old_path="$(printf '%s' "$match" | jq -r '.codePath')"

  new_path="$(canon_path "$new_path")"

  if [ "$(strip_slash "$new_path")" = "$(strip_slash "$old_path")" ]; then
    echo "UNCHANGED: ${project_path} already has this code path."
    run_check "$project_path"
    return $?
  fi

  local registry_snapshot
  registry_snapshot="$(registry__current)" || die3 "the registry could not be read; nothing was changed. See the error above."
  if printf '%s' "$registry_snapshot" | jq -e --arg c "$new_path" --arg p "$(strip_slash "$project_path")" \
      'any(.projects[]?; (.codePath // "" | sub("/+$"; "")) == $c and (.path // "" | sub("/+$"; "")) != $p)' \
      >/dev/null 2>&1; then
    die3 "a project is already registered for $new_path. Nothing was changed."
  fi

  local tmp
  write_project_field "$project_path" "could not update codePath in $project_path/project.json" \
    --arg c "$new_path" '.codePath = $c'

  local new_registry
  new_registry="$(printf '%s' "$registry_snapshot" | jq --arg p "$(strip_slash "$project_path")" --arg c "$new_path" '
    (.projects[] | select((.path // "" | sub("/+$"; "")) == $p) | .codePath) = $c
  ')" || die3 "could not compute the updated registry"
  printf '%s' "$new_registry" | registry__write \
    || printf 'project-actions: project.json now points at %s, but the registry copy could not be\n  updated. The check below will report the mismatch.\n' "$new_path" >&2

  commit_project "$project_path" \
    "Set code path to ${new_path}" \
    "requested" \
    "" \
    "" \
    "project" "code-path" \
    || printf 'project-actions: the code-path change was written but not committed.\n' >&2

  run_check "$project_path"
  local check_rc=$?

  # Exit 5 is the check's own safety refusal, the same one create undoes. A refused code path is
  # never kept here either: both copies are restored to what they were before this call.
  if [ "$check_rc" -eq 5 ]; then
    local tmp2 restore_registry
    write_project_field "$project_path" "could not restore the previous codePath in $project_path/project.json" \
      --arg c "$old_path" '.codePath = $c'

    restore_registry="$(registry__current)" && restore_registry="$(printf '%s' "$restore_registry" | jq --arg p "$(strip_slash "$project_path")" --arg c "$old_path" '
      (.projects[] | select((.path // "" | sub("/+$"; "")) == $p) | .codePath) = $c
    ')" && printf '%s' "$restore_registry" | registry__write

    commit_project "$project_path" \
      "Restore code path after a refused change" \
      "the proposed code path named a refused location; see the safety report" \
      "" \
      "" \
      "project" "code-path" \
      || printf 'project-actions: the restore was written but not committed.\n' >&2

    printf 'project-actions: %s names a refused location. The code path was restored to %s.\n' "$new_path" "$old_path" >&2
    printf 'See the safety report above for the exact reason.\n' >&2
    return 5
  fi

  return "$check_rc"
}

# ------------------------------------------------------------------------------------------------
# set-worktree-default: whether a task builds in a worktree without being asked. Settable at
# creation and, like the task rule, at any later time too.
# ------------------------------------------------------------------------------------------------

do_set_worktree_default() {
  local target="${1:?set-worktree-default: a name or a code path is required}"
  local value="${2:?set-worktree-default: true or false is required}"
  case "$value" in
    true|false) : ;;
    *) die3 "set-worktree-default: must be true or false, got: $value" ;;
  esac

  local match project_path
  match="$(resolve_target "$target")"
  [ -n "$match" ] || { echo "NOT FOUND: ${target}" >&2; return 1; }
  project_path="$(printf '%s' "$match" | jq -r '.path')"

  local tmp
  write_project_field "$project_path" "could not update worktreeByDefault in $project_path/project.json" \
    --argjson w "$value" '.worktreeByDefault = $w'

  commit_project "$project_path" \
    "Set worktreeByDefault to ${value}" \
    "requested" \
    "" \
    "" \
    "project" "worktree-default" \
    || printf 'project-actions: worktreeByDefault was written but not committed.\n' >&2

  run_check "$project_path"
}

# ------------------------------------------------------------------------------------------------
# unregister: drops the row, leaves both folders untouched
# ------------------------------------------------------------------------------------------------

do_unregister() {
  local target="${1:?unregister: a name or a code path is required}" match project_path code_path
  match="$(resolve_target "$target")"
  [ -n "$match" ] || { echo "NOT FOUND: ${target}" >&2; return 1; }
  project_path="$(printf '%s' "$match" | jq -r '.path')"
  code_path="$(printf '%s' "$match" | jq -r '.codePath')"

  registry_remove_project "$project_path" || die3 "could not remove the registry row for $project_path"

  echo "UNREGISTERED: $(printf '%s' "$match" | jq -r '.name')"
  echo "PROJECT FOLDER (not removed): ${project_path}"
  echo "CODE PATH (not touched): ${code_path}"
}

# ------------------------------------------------------------------------------------------------
# task-rule: the marker-delimited block, ported from version 5's task-rule-install.sh
# ------------------------------------------------------------------------------------------------

TASK_RULE_BEGIN="<!-- task-rule:begin -->"
TASK_RULE_END="<!-- task-rule:end -->"

task_rule_block() {
  local project_name="$1"
  cat <<EOF
${TASK_RULE_BEGIN}
## Development work here goes through a task

This repository is tracked as the "${project_name}" project. Work that produces findings or
decisions someone will need later belongs in a task, so what is learned survives the session
that learned it.

Before starting work, say in one line where it goes. Either open a task, or say plainly that
this one is too small to track, and wait for a yes before doing it.

Judge the work, not the diff. A two-line edit that forces a version choice, a rebuild, or a
restart of something everything else depends on is a task. A typo or a question is not.

The rule is not that everything becomes a task. It is that the choice is made out loud, not
by default. Deciding silently that something is too small is the same as never having
considered it.
${TASK_RULE_END}
EOF
}

do_task_rule() {
  local target="${1:?task-rule: a name or a code path is required}"
  shift
  local declining="false"
  [ "${1:-}" = "--decline" ] && { declining="true"; shift; }
  [ "${1:-}" = "--" ] && shift
  local why="$*"
  [ -n "$why" ] || why="requested"

  local match code_path project_path project_name claude_md present tmp
  match="$(resolve_target "$target")"
  [ -n "$match" ] || { echo "NOT FOUND: ${target}" >&2; return 1; }
  project_path="$(printf '%s' "$match" | jq -r '.path')"
  project_name="$(printf '%s' "$match" | jq -r '.name')"
  # The project file is authoritative and the registry is an index (ideal/project.md, "What a
  # project is"). This writes into a repository the person owns, so it reads the code path from
  # the file rather than from the index copy, which can be stale.
  code_path="$(jq -r '.codePath // empty' "$project_path/project.json" 2>/dev/null)"

  # A decline is recorded and nothing is written, so the offer is never made again. It needs no
  # code path and no repository, because it writes into neither. Version 5 records the same answer
  # at creation, which is why a person is asked once rather than every session.
  if [ "$declining" = "true" ]; then
    # Recording a decline while the block is actually installed would leave the file saying no and
    # the repository saying yes. Removing it is a separate, explicit action.
    claude_md="${code_path%/}/CLAUDE.md"
    if [ -n "$code_path" ] && [ "$code_path" != "null" ] && [ -f "$claude_md" ] \
       && grep -qF "$TASK_RULE_BEGIN" "$claude_md" 2>/dev/null; then
      echo "REFUSED: the task rule is already installed in ${claude_md}. Use --remove to take it out." >&2
      return 1
    fi
    write_project_field "$project_path" "could not record the declined task rule in $project_path/project.json" \
      '.taskRule = {offered: true, accepted: false}'
    commit_project "$project_path" \
      "Record the task rule as offered and declined" \
      "$why" \
      "" \
      "" \
      "project" "task-rule" \
      || printf 'project-actions: the task-rule field was written but not committed.\n' >&2
    echo "DECLINED: the task rule was offered for ${project_name} and will not be offered again."
    run_check "$project_path"
    return 0
  fi

  # ideal/project.md, "Starting a new project": everything opted into can be set at any time, but
  # the task rule needs a repository to write into. There is no repository without a code path.
  [ -n "$code_path" ] && [ "$code_path" != "null" ] || {
    echo "REFUSED: no code path is set for ${project_name}. There is no repository to write the task rule into." >&2
    return 1
  }
  [ -d "$code_path" ] || {
    echo "REFUSED: ${code_path} does not exist yet. The task rule needs a real repository to write into." >&2
    return 1
  }

  claude_md="${code_path%/}/CLAUDE.md"
  present="false"
  [ -f "$claude_md" ] && grep -qF "$TASK_RULE_BEGIN" "$claude_md" 2>/dev/null && present="true"

  # Ported from version 5's task-rule-install.sh: check writability before writing, and report a
  # distinct failure rather than printing WRITTEN or REFRESHED regardless of what happened.
  if [ ! -f "$claude_md" ]; then
    : > "$claude_md" || {
      echo "REFUSED: ${claude_md} could not be created. Check permissions on ${code_path}." >&2
      return 1
    }
  fi
  [ -w "$claude_md" ] || {
    echo "REFUSED: ${claude_md} is not writable. The task rule was not written." >&2
    return 1
  }

  if [ "$present" = "true" ]; then
    local block_file
    tmp="$(mktemp)"
    block_file="$(mktemp)"
    task_rule_block "$project_name" > "$block_file"
    awk -v b="$TASK_RULE_BEGIN" -v e="$TASK_RULE_END" -v bf="$block_file" '
      index($0,b){ while ((getline line < bf) > 0) print line; close(bf); skip=1; next }
      index($0,e){ skip=0; next }
      !skip{print}
    ' "$claude_md" > "$tmp" && mv "$tmp" "$claude_md" || {
      rm -f "$tmp" "$block_file"
      echo "REFUSED: rewriting ${claude_md} failed. The task rule was not refreshed." >&2
      return 1
    }
    rm -f "$block_file"
    echo "REFRESHED: ${claude_md}"
  else
    {
      [ -s "$claude_md" ] && printf '\n'
      task_rule_block "$project_name"
    } >> "$claude_md" || {
      echo "REFUSED: appending to ${claude_md} failed. The task rule was not written." >&2
      return 1
    }
    echo "WRITTEN: ${claude_md}"
  fi

  write_project_field "$project_path" "could not update taskRule in $project_path/project.json" \
    '.taskRule = {offered: true, accepted: true}'

  commit_project "$project_path" \
    "Record the task rule as installed" \
    "$why" \
    "" \
    "" \
    "project" "task-rule" \
    || printf 'project-actions: the task-rule field was written but not committed.\n' >&2

  run_check "$project_path"
}

do_task_rule_remove() {
  local target="${1:?task-rule-remove: a name or a code path is required}" match code_path project_path
  match="$(resolve_target "$target")"
  [ -n "$match" ] || { echo "NOT FOUND: ${target}" >&2; return 1; }
  code_path="$(printf '%s' "$match" | jq -r '.codePath')"
  project_path="$(printf '%s' "$match" | jq -r '.path')"

  local claude_md="${code_path%/}/CLAUDE.md"
  if [ -f "$claude_md" ] && grep -qF "$TASK_RULE_BEGIN" "$claude_md" 2>/dev/null; then
    local tmp
    tmp="$(mktemp)"
    awk -v b="$TASK_RULE_BEGIN" -v e="$TASK_RULE_END" '
      { lines[NR] = $0 }
      END {
        for (i = 1; i <= NR; i++) {
          if (index(lines[i], b)) bi = i
          if (index(lines[i], e)) ei = i
        }
        if (bi == 0) { for (i = 1; i <= NR; i++) print lines[i]; exit }
        if (ei == 0) ei = bi
        start = bi
        if (bi > 1 && lines[bi-1] == "") start = bi - 1
        for (i = 1; i < start; i++) print lines[i]
        for (i = ei + 1; i <= NR; i++) print lines[i]
      }
    ' "$claude_md" > "$tmp" && mv "$tmp" "$claude_md" || {
      rm -f "$tmp"
      echo "REFUSED: rewriting ${claude_md} failed. The task rule was not removed." >&2
      return 1
    }
    echo "REMOVED: ${claude_md}"
  else
    echo "ABSENT: no task-rule block was found in ${claude_md}"
  fi

  local tmp2
  write_project_field "$project_path" "could not update taskRule in $project_path/project.json" \
    '.taskRule = (if .taskRule == null then null else (.taskRule + {accepted: false}) end)'

  commit_project "$project_path" "Remove the task rule" "requested" "" "" "project" "task-rule" \
    || printf 'project-actions: the task-rule removal was written but not committed.\n' >&2

  run_check "$project_path"
}

# ------------------------------------------------------------------------------------------------
# uninstall: cleaning up AIDA's own instructions, and nothing else
# ------------------------------------------------------------------------------------------------

do_uninstall() {
  local target="${1:?uninstall: a name or a code path is required}" match project_path
  match="$(resolve_target "$target")"
  [ -n "$match" ] || { echo "NOT FOUND: ${target}" >&2; return 1; }
  project_path="$(printf '%s' "$match" | jq -r '.path')"

  local task_rule_state
  task_rule_state="$(jq -r '.taskRule' "$project_path/project.json" 2>/dev/null)"
  if [ "$task_rule_state" != "null" ] && [ -n "$task_rule_state" ]; then
    do_task_rule_remove "$target"
  else
    echo "TASK RULE: not offered for this project; nothing to remove."
  fi

  local hook_installed
  hook_installed="$(jq -r '.memoryHook.installed' "$project_path/project.json" 2>/dev/null)"
  if [ "$hook_installed" = "true" ]; then
    echo "MEMORY HOOK: recorded as installed, but no installer exists yet in this build to say"
    echo "  where its primer, its script copy, or its two settings entries live. Nothing was"
    echo "  removed; this cannot be done safely until that installer is built."
  else
    echo "MEMORY HOOK: not installed for this project; nothing to remove."
  fi

  echo "UNINSTALL COMPLETE for $(printf '%s' "$match" | jq -r '.name')."
}

# ------------------------------------------------------------------------------------------------
# record-declined
# ------------------------------------------------------------------------------------------------

do_record_declined() {
  local directory="${1:?record-declined: a directory is required}"
  registry_record_declined_offer "$directory"
}

# ------------------------------------------------------------------------------------------------
# rebuild-registry: the registry is derivable, and this is the real operation ideal/project.md names
# ------------------------------------------------------------------------------------------------

do_rebuild_registry() {
  registry_rebuild "$@"
}

do_read_projects_base() {
  settings_get_projects_base
}

# ------------------------------------------------------------------------------------------------
# Dispatch
# ------------------------------------------------------------------------------------------------

action="${1:-}"
[ -n "$action" ] && shift || true

case "$action" in
  create) do_create "$@" ;;
  report) do_report ;;
  switch) do_switch "$@" ;;
  list) do_list "$@" ;;
  state) do_state "$@" ;;
  set-code-path) do_set_code_path "$@" ;;
  set-worktree-default) do_set_worktree_default "$@" ;;
  unregister) do_unregister "$@" ;;
  task-rule) do_task_rule "$@" ;;
  task-rule-remove) do_task_rule_remove "$@" ;;
  uninstall) do_uninstall "$@" ;;
  record-declined) do_record_declined "$@" ;;
  rebuild-registry) do_rebuild_registry "$@" ;;
  read-projects-base) do_read_projects_base ;;
  *) usage; exit 3 ;;
esac
