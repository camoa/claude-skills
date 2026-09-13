#!/usr/bin/env bash
# The plugin root: the variable when the platform sets it (hooks), else this file's own place.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
# playbook-actions.sh: the deterministic half of the playbooks skill (ideal/playbooks.md).
#
# Usage:
#   playbook-actions.sh load    <task_folder>
#   playbook-actions.sh capture <projectPath> --domain <H2> --title <t> --what <w> --rationale <r>
#                               --when <when> [--example-file <path>]
#   playbook-actions.sh list    [<projectPath>]
#
# `load` reads the person's file, the project's file and the catalog record the playbook-loader
# agent wrote, writes records/playbooks.json and renders records/playbooks.md. It fetches nothing.
# `capture` appends one play to the project's file and commits the project folder. `list` prints
# one line per play. Every action prints `key: value` summary lines and paths, never a play body.
#
# Exit codes: 0 did what was asked; 1 capture refused a duplicate slug; 3 the script could not do
# its job, including a task folder that does not resolve; 79 load was run outside the task's
# worktree, the shared helper's own number.
#
# Depends on, shipped by other builders and never edited here: scripts/lib/task-helpers.sh
# (resolve_task_folder, write_atomic), scripts/lib/recipes.sh (resolve_project_folder,
# json_file_state), scripts/lib/schema-check.sh, scripts/lib/playbooks.sh,
# scripts/lib/project-commit.sh (commit_project), and scripts/playbooks-schema.json.
#
# Portability: bash 3.2+ and zsh. No mapfile, no associative arrays, no variable as a case pattern.

set -uo pipefail  # not -e: several branches test a command's exit code on purpose.

command -v jq >/dev/null 2>&1 || { printf 'playbook-actions: jq is required and was not found on PATH\n' >&2; exit 3; }

die() { printf 'playbook-actions: %s\n' "$2" >&2; exit "$1"; }
die1() { die 3 "$1"; }  # the brief: a task folder that does not resolve exits 3
die3() { die 3 "$1"; }
die79() { die 79 "$1"; }

for lib_name in task-helpers recipes schema-check playbooks project-commit; do
  # shellcheck source=/dev/null
  source "${PLUGIN_ROOT}/scripts/lib/${lib_name}.sh" || die 3 "the library failed to load: ${lib_name}.sh"
done
SCHEMA="${PLUGIN_ROOT}/scripts/playbooks-schema.json"
PERSON_FILE="$HOME/.claude/aida/playbook.md"

usage() {
  cat <<'EOF' >&2
usage: playbook-actions.sh load    <task_folder>
       playbook-actions.sh capture <projectPath> --domain <H2> --title <t> --what <w> --rationale <r>
                                   --when <when> [--example-file <path>]
       playbook-actions.sh list    [<projectPath>]
EOF
  exit 3
}

# One file as a source: prints `{source, state, plays}` and the play array as two JSON lines.
# $1 the source name, $2 the file. Absent and empty are two states, never one (ideal/playbooks.md).
pb_read_source() {
  local name="$1" file="$2" plays
  if [ ! -f "$file" ]; then
    printf '{"source":"%s","state":"absent","plays":0}\n[]\n' "$name"; return
  fi
  plays="$(pb_parse_file "$file" | jq -c --arg s "$name" 'map(.source = $s | .id = $s + ":" + .id)')" \
    || die 3 "could not parse $file"
  printf '%s' "$plays" | jq -c --arg s "$name" '{source: $s, state: (if length == 0 then "empty" else "loaded" end), plays: length}'
  printf '%s\n' "$plays"
}

do_load() {
  local task_path project catalog record result faults person project_src
  task_path="$(resolve_task_folder "${1:-}" load)" || exit $?
  project="$(resolve_project_folder "$task_path")" \
    || die 3 "load: could not resolve a project folder two levels up from $task_path, or it has no project.json"
  catalog="$task_path/records/playbooks-catalog.json"
  case "$(json_file_state "$catalog")" in
    unreadable) die 3 "load: $catalog exists but is not valid JSON. The playbook-loader agent writes it; dispatch it again" ;;
    missing) catalog="" ;;
  esac
  person="$(pb_read_source person "$PERSON_FILE")"
  project_src="$(pb_read_source project "$project/playbook.md")"
  record="$(jq -n --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --argjson ps "$(printf '%s' "$person" | sed -n 1p)" --argjson pp "$(printf '%s' "$person" | sed -n 2p)" \
      --argjson js "$(printf '%s' "$project_src" | sed -n 1p)" --argjson jp "$(printf '%s' "$project_src" | sed -n 2p)" \
      --argjson cat "$( [ -n "$catalog" ] && cat "$catalog" || echo '{"sources":[],"plays":[]}')" '
    {schemaVersion: 1, loadedAt: $at,
     sources: ([$ps, $js] + ($cat.sources // [])),
     plays: ($pp + $jp + ($cat.plays // []))}')"
  result="$(schema_check_compare "$SCHEMA" <(printf '%s\n' "$record"))" || die 3 "load: the record could not be compared with $SCHEMA"
  faults="$(printf '%s' "$result" | jq -r '(.missing + .unreadable) | map(.field) | join(" ")')"
  [ -z "$faults" ] || die 3 "load: the record does not match $SCHEMA: $faults. This is a defect in playbook-actions.sh"
  mkdir -p "$task_path/records"
  write_atomic "$task_path/records/playbooks.json" "$record"
  printf '%s' "$record" | jq -r '
    "# Playbooks\n\nRendered from records/playbooks.json by `playbooks load`; edit the source file, not this one.\n",
    (.sources[] | "- " + .source + ": " + .state + (if .state == "loaded" then ", " + (.plays | tostring) + " plays" else "" end)),
    (. as $r | $r.sources[].source as $s | [$r.plays[] | select(.source == $s)] | select(length > 0)
      | "\n## " + $s, (.[] | "\n### " + .title + " (`" + .id + "`)\n\n**What:** " + .what + "\n**Rationale:** " + .rationale
        + "\n**When it applies:** " + .when + (if .example == "" then "" else "\n**Example:**\n\n" + .example end)
        + (if .guide == null then "" else "\n\nGuide: " + .guide end)))' > "$task_path/records/playbooks.md" \
    || die 3 "load: could not write $task_path/records/playbooks.md"
  echo "record: $task_path/records/playbooks.json"
  echo "rendered: $task_path/records/playbooks.md"
  printf '%s' "$record" | jq -r '(.sources[] | "source: " + .source + " " + .state + " " + (.plays | tostring)), "plays: " + (.plays | length | tostring)'
}

do_capture() {
  local project="${1:-}" domain="" title="" what="" rationale="" when="" example_file="" file id play
  [ -d "$project" ] || die 3 "capture: not a folder: ${project:-none given}"
  shift
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] && ! looks_like_flag "$2" || die 3 "capture: $1 needs a value"
    case "$1" in
      --domain) domain="$2" ;; --title) title="$2" ;; --what) what="$2" ;;
      --rationale) rationale="$2" ;; --when) when="$2" ;; --example-file) example_file="$2" ;;
      *) usage ;;
    esac
    shift 2
  done
  for v in "$domain" "$title" "$what" "$rationale" "$when"; do
    is_blank "$v" && die 3 "capture: --domain, --title, --what, --rationale and --when are all required"
  done
  [ -z "$example_file" ] || [ -f "$example_file" ] || die 3 "capture: example file not found: $example_file"
  file="$project/playbook.md"
  id="$(pb_slug "$title")"
  [ -n "$id" ] || die 3 "capture: the title leaves no slug: $title"
  if [ -f "$file" ] && pb_parse_file "$file" 2>/dev/null | jq -e --arg id "$id" 'any(.[]; .id == $id)' >/dev/null; then
    die 1 "capture: $file already holds a play with the id $id"
  fi
  play="$(mktemp)" || die 3 "cannot create a temp file"
  { printf '### %s\n\n**What:** %s\n**Rationale:** %s\n**When it applies:** %s\n' "$title" "$what" "$rationale" "$when"
    [ -z "$example_file" ] || { printf '**Example:**\n\n'; cat "$example_file"; }
  } > "$play"
  [ -f "$file" ] || printf '# Playbook\n' > "$file"
  # Appends the play as the last thing under its domain: before the next `## `, or at the end of
  # the file, after a new `## <domain>` heading when the file has none.
  awk -v d="$domain" -v play="$play" '
    function put() { if (!blank) print ""; while ((getline l < play) > 0) print l; done = 1 }
    /^## / { if (found && !done) { put(); print "" } if (substr($0, 4) == d) found = 1 }
    { print; blank = ($0 == "") }
    END { if (!found) { if (!blank) print ""; print "## " d; blank = 0 } if (!done) put() }
  ' "$file" > "$play.out" && mv "$play.out" "$file" || { rm -f "$play" "$play.out"; die 3 "capture: could not write $file"; }
  rm -f "$play"
  commit_project "$project" "Capture the play $id" "captured" "" "" "project" "playbook" || printf 'playbook-actions: the play was written but not committed.\n' >&2
  echo "written: $file"
  echo "play: project:$id"
}

# $1 the source name, $2 the file. One `<id>  <title>` line per play, or `<source>: none`.
pb_list_file() {
  [ -f "$2" ] || { echo "$1: none"; return; }
  pb_parse_file "$2" 2>/dev/null | jq -r --arg s "$1" '.[] | $s + ":" + .id + "  " + .title'
}

do_list() {
  local project="${1:-}" newest=""
  pb_list_file person "$PERSON_FILE"
  [ -n "$project" ] || { echo "project: none"; echo "catalog: none"; return 0; }
  [ -d "$project" ] || die 3 "list: not a folder: $project"
  pb_list_file project "$project/playbook.md"
  [ -d "$project/tasks" ] && newest="$(find "$project/tasks" -mindepth 3 -maxdepth 3 -path '*/records/playbooks.json' -exec ls -t {} + 2>/dev/null | head -1)"
  [ -n "$newest" ] && jq -r '.plays[] | select(.source != "person" and .source != "project") | .id + "  " + .title' "$newest" | grep . || echo "catalog: none"
}

action="${1:-}"
[ -n "$action" ] && shift || true
case "$action" in
  load) do_load "$@" ;;
  capture) do_capture "$@" ;;
  list) do_list "$@" ;;
  *) usage ;;
esac
