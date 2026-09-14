#!/usr/bin/env bash
# surfaces-actions.sh: the deterministic half of the surfaces skill (ideal/surfaces.md). Sets up
# end to end and visual regression for the project that owns the current directory, so review has
# something to run. Setup is not a stage: it takes no task folder, the way the tool skill does. It
# writes into the tree the current directory runs in, a task's worktree or, with none active, the
# code path (active_tree_for in scripts/lib/task-helpers.sh).
#
#   surfaces-actions.sh [--run-mode <interactive|autonomous>] read
#   surfaces-actions.sh [--run-mode ...] show     <kind> <recipe flags>
#   surfaces-actions.sh [--run-mode ...] install  <kind> <recipe flags> [--viewport <name>=<w>x<h>]...
#   surfaces-actions.sh [--run-mode ...] register <id> --url <url> --kind <kind>... [--mask <css>]... [--enable]
#   surfaces-actions.sh [--run-mode ...] baseline [<id>]... --check-recipe <framework>=<path>...
#                                                 [--value <name>=<value>]... [--confirmed]
#   surfaces-actions.sh decline <kind>
#   surfaces-actions.sh step <name>
#
# The recipe flags are `--recipe <framework>=<path>` or `--lookup-failed <framework>=<word>`, one
# per framework the project records, the flags review's `checks` takes. A kind is `e2e` or
# `visual-regression`, the review recipe's own surface row ids. The surface file is
# `.visual-review/surfaces.json` in the resolved tree (scripts/surfaces-schema.json), read by
# scripts/lib/surfaces.sh, the reader review uses. The project record's `surfaces.registryPath`
# holds that same relative path, and this script is its one producer. Every action prints
# `key: value` lines and paths; a recipe command's own output goes to <project>/records/, never to
# stdout.
#
# Exit codes, each with the meaning the tool and review scripts give it:
#   0  did what was asked, including `install` printing not-applicable when no framework has a recipe
#   1  no project owns this directory
#   3  could not do its job: a bad argument, a refused command, a differing file, a recipe with no
#      block, a lookup nobody completed, an id registered with different fields, an absent accept row
#   4  a recipe command ran and failed; its own output, in the file, is the answer
#  61  the tree is dirty, so an install or baseline commit would sweep other work in
#  62  `register` or `baseline` before `install` wrote the surface file
#  70  a person's answer was passed with nobody present
#  72  two frameworks each carry a recipe for one kind, or two accept rows for one baseline
#
# Portability: bash 3.2+ and zsh. No mapfile, no associative arrays, no variable as a case pattern.

set -uo pipefail
if [ -n "${ZSH_VERSION:-}" ]; then SCRIPT_SOURCE="$0"; else SCRIPT_SOURCE="${BASH_SOURCE[0]}"; fi
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd -- "$(dirname -- "$SCRIPT_SOURCE")/../../.." >/dev/null 2>&1 && pwd -P)}"
STEPS_DIR="${PLUGIN_ROOT}/skills/surfaces/references"
command -v jq >/dev/null 2>&1 || { printf 'surfaces-actions: jq is required and was not found on PATH\n' >&2; exit 3; }
die() { printf 'surfaces-actions: %s\n' "$2" >&2; exit "$1"; }
die3() { die 3 "$1"; }  # write_atomic in task-helpers.sh refuses through this name
for lib_name in registry task-helpers records-hash recipes paths surfaces; do
  # shellcheck source=/dev/null
  . "${PLUGIN_ROOT}/scripts/lib/${lib_name}.sh" || die 3 "the library failed to load: ${lib_name}.sh"
done

RUN_MODE="interactive"
if [ "${1:-}" = "--run-mode" ]; then [ $# -ge 2 ] || die 3 "--run-mode needs a value"; RUN_MODE="$2"; shift 2; fi
case "$RUN_MODE" in interactive|autonomous) ;; *) die 3 "run mode must be interactive or autonomous, got $RUN_MODE" ;; esac
ACTION="${1:-}"; [ -n "$ACTION" ] || die 3 "needs an action: read, show, install, register, baseline, decline or step"
shift
TAB="$(printf '\t')"

# Exit 70. $1 the flag, $2 what it says a person did.
require_person() {
  [ "$RUN_MODE" = "autonomous" ] || return 0
  die 70 "$ACTION: $1 says $2, and this run is autonomous. No person is here to answer, so nothing is written."
}

if [ "$ACTION" = "step" ]; then
  names="$(md_basenames_in "$STEPS_DIR")"
  [ "$#" -eq 1 ] || die 3 "step: one step name is required. The steps are: $names"
  case "$1" in */*|.|..|'') die 3 "step: a step name is one name and never a path; got: $1" ;; esac
  [ -f "$STEPS_DIR/$1.md" ] || die 3 "step: this skill ships no step file named $1. The steps are: $names"
  cat "$STEPS_DIR/$1.md"; exit 0
fi

# ---------------------------------------------------------------- the project
MATCH="$(registry_resolve_by_directory "$(pwd -P)" 2>/dev/null || true)"
PROJECT_DIR="$(printf '%s' "$MATCH" | jq -r '.path // empty' 2>/dev/null)"
[ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ] || die 1 "no project owns $(pwd -P)"
PROJECT_FILE="$PROJECT_DIR/project.json"
[ "$(json_file_state "$PROJECT_FILE")" = "ok" ] || die 3 "$PROJECT_FILE is missing or unreadable"
CODE_PATH="$(project_code_path_value "$PROJECT_DIR")"
[ -n "$CODE_PATH" ] && [ -d "$CODE_PATH" ] || die 3 "$PROJECT_FILE records no codePath on disk"
TREE="$(active_tree_for "$CODE_PATH" "$(pwd -P)")"
FRAMEWORKS="$(jq -r '.frameworks // [] | .[]' "$PROJECT_FILE")"
SURFACE_REL=".visual-review/surfaces.json"
SURFACE_FILE="$TREE/$SURFACE_REL"
RECORDS_DIR="$PROJECT_DIR/records"

# The project record's `surfaces` field, initialised on the first write. $1 a jq filter over it.
write_project_field() {
  local doc
  doc="$(jq -c --arg sf "$SURFACE_REL" '.surfaces = ((.surfaces // {registryPath: null, e2e: {enabled: false, declined: false}, visualRegression: {enabled: false, declined: false}}) | '"$1"')' "$PROJECT_FILE")" \
    || die 3 "$ACTION: could not update the surfaces field"
  write_atomic "$PROJECT_FILE" "$doc"
}

# Loads the surface file and refuses every state but ok: missing is a step out of order (62).
require_surface_file() {
  sf_load_surfaces "$SURFACE_FILE"
  case "$SF_STATE" in
    ok) ;;
    missing) die 62 "$ACTION: there is no surface file at $SURFACE_FILE. Run install first." ;;
    *) die 3 "$ACTION: $SURFACE_FILE is $SF_STATE" ;;
  esac
}

# Commits everything install or baseline wrote in $TREE, printing `committed: <sha>`; prints
# `committed: none, $1` when the tree was already clean, so nothing of this call's own is in it.
# $1 what to say wrote nothing, $2 the commit message. Dies through $ACTION's own name.
sa_commit_if_changed() {
  if [ -z "$(git -C "$TREE" status --porcelain)" ]; then
    printf 'committed: none, %s\n' "$1"
  else
    git -C "$TREE" add -A && git -C "$TREE" commit -q -m "$2" \
      || die 3 "$ACTION: the commit failed"
    printf 'committed: %s\n' "$(git -C "$TREE" rev-parse --short HEAD)"
  fi
}

# ----------------------------------------------------------------- the recipe
# One recipe per kind, or a lookup that failed, per framework. Sets RECIPE and RECIPE_FW, or ends
# the action: no recipe anywhere is not-applicable (exit 0), a lookup nobody completed is unknown
# (exit 3), and two recipes are two answers to one question (exit 72). The words are the ones
# cr_lookup_failure_pair accepts, and nothing here reads a fourth.
RECIPE=""; RECIPE_FW=""; VIEWPORTS_ARG=""; VIEWPORTS_JSON="[]"; VALUES=""; KIND=""; KEY=""

# Maps a kind word to the project record's key, or dies at 3 naming both kinds. Sets KEY. $1 the kind.
kind_key() {
  case "$1" in
    e2e)                KEY="e2e" ;;
    visual-regression)  KEY="visualRegression" ;;
    *) die 3 "$ACTION: the kind is e2e or visual-regression, got: ${1:-nothing}" ;;
  esac
}

resolve_recipe() {
  local recipes="" failures="" fw pair reason unknown=""
  while [ "$#" -gt 0 ]; do
    [ "$#" -ge 2 ] || die 3 "$ACTION: $1 needs a value"
    case "$1" in
      --recipe)        cr_recipe_pair "$ACTION" --recipe "$2"; recipes="$recipes$CR_PAIR
" ;;
      --lookup-failed) cr_lookup_failure_pair "$ACTION" --lookup-failed "$2"; failures="$failures$CR_PAIR
" ;;
      --viewport)      VIEWPORTS_ARG="$VIEWPORTS_ARG$2
" ;;
      *) die 3 "$ACTION: unrecognized argument: $1" ;;
    esac
    shift 2
  done
  while IFS= read -r fw; do
    [ -n "$fw" ] || continue
    pair="$(cr_lookup "$recipes" "$fw")"; reason="$(cr_lookup "$failures" "$fw")"
    [ -n "$pair" ] || [ -n "$reason" ] || die 3 "$ACTION: nothing was said about the framework $fw. Pass --recipe $fw=<path> or --lookup-failed $fw=<word>."
    if [ -n "$pair" ]; then
      [ -z "$RECIPE" ] || die 72 "$ACTION: $RECIPE_FW and $fw each carry a $KIND recipe, and nothing here may choose between two answers to one question."
      RECIPE="$pair"; RECIPE_FW="$fw"
    fi
    case "$reason" in listing-unreachable|fetch-failed) unknown="$unknown $fw=$reason" ;; esac
  done <<SA_FRAMEWORKS
$FRAMEWORKS
SA_FRAMEWORKS
  [ -n "$RECIPE" ] && return 0
  if [ -n "$unknown" ]; then
    printf '%s: unknown%s\n' "$ACTION" "$unknown"
    die 3 "$ACTION: nobody looked for a $KIND recipe:$unknown. Nothing was written."
  fi
  printf '%s: not-applicable\n' "$ACTION"
  printf 'SURFACES: no framework of this project has a %s recipe, so there is no %s setup here.\n' "$KIND" "$KIND" >&2
  exit 0
}

# The `## Viewports` block of the recipe, or the --viewport list, into VIEWPORTS_JSON. A global,
# because a refusal inside a `$(...)` capture would exit that subshell alone.
load_viewports() {
  local out one
  if [ -z "$VIEWPORTS_ARG" ]; then
    out="$(fenced_blocks_under "$RECIPE" Viewports json | jq -c 'if type == "array" then . else empty end' 2>/dev/null)"
    VIEWPORTS_JSON="${out:-[]}"; return 0
  fi
  require_person "--viewport" "a person chose the viewports"
  out='[]'
  while IFS= read -r one; do
    [ -n "$one" ] || continue
    out="$(jq -nc --argjson have "$out" --arg one "$one" '$have + [($one | capture("^(?<name>[^=]+)=(?<w>[0-9]+)x(?<h>[0-9]+)$")
      | {name, width: (.w | tonumber), height: (.h | tonumber)})]' 2>/dev/null)" || die 3 "$ACTION: --viewport takes <name>=<w>x<h>, got: $one"
  done <<SA_VIEWPORTS
$VIEWPORTS_ARG
SA_VIEWPORTS
  VIEWPORTS_JSON="$out"
}

# --------------------------------------------------------- show and install
do_show_or_install() {
  local steps files_dir list n rel target kept=0 written=0 line before doc
  KIND="${1:-}"
  kind_key "$KIND"
  shift; resolve_recipe "$@"
  steps="$(sh_blocks_under "$RECIPE" Install)"
  files_dir="$(mktemp -d)" || die 3 "$ACTION: could not create a temporary folder"
  list="$(recipe_files_into "$RECIPE" Files "$files_dir")"
  printf 'RECIPE: %s\nFRAMEWORK: %s\n' "$RECIPE" "$RECIPE_FW"
  if [ "$ACTION" = "show" ]; then
    printf 'INSTALL:\n'; printf '%s\n' "${steps:-no block tagged sh, so install refuses this recipe}" | sed 's/^/  /'
    printf 'FILES:\n'; printf '%s\n' "$list" | cut -f2 | sed 's/^./  &/'
    printf 'VIEWPORTS: %s\n' "$(fenced_blocks_under "$RECIPE" Viewports json | jq -c '.' 2>/dev/null)"
    printf 'SEED:\n'; fenced_blocks_under "$RECIPE" Surfaces json | jq -r '.[] | "  \(.id) url=\(.url) kinds=\(.kinds | join(","))"' 2>/dev/null
    printf 'DISCOVERY:\n'; sed -n '/^## Discovery$/,/^## /p' "$RECIPE" | sed '1d; /^## /d; /^$/d; s/^/  /'
    rm -rf "$files_dir"; exit 0
  fi
  [ -n "$steps" ] || die 3 "install: $RECIPE has no block tagged sh under Install"
  # Every file is checked before any command runs, so a differing file stops the install whole.
  while IFS="$TAB" read -r n rel; do
    [ -n "$n" ] || continue
    case "$rel" in /*|*../*|*/..) die 3 "install: $RECIPE names a file outside the tree: $rel" ;; esac
    target="$TREE/$rel"
    [ ! -f "$target" ] || cmp -s "$files_dir/$n" "$target" \
      || die 3 "install: $target exists with different content from the $rel block in $RECIPE. Nothing is overwritten; move the file aside or change the recipe."
  done <<SA_FILES
$list
SA_FILES
  br_require_clean_tree install "$TREE"
  load_viewports
  [ "$RUN_MODE" = "interactive" ] && { printf 'ABOUT TO RUN, from %s:\n' "$RECIPE"; printf '%s\n' "$steps" | sed 's/^/  /'; }
  mkdir -p "$RECORDS_DIR" "$TREE/.visual-review" || die 3 "install: could not create the records folder"
  OUTFILE="$RECORDS_DIR/surfaces-$KIND-install.txt"; : >"$OUTFILE"
  cd "$TREE" || die 3 "install: could not enter $TREE"
  while IFS= read -r line; do
    [ -n "${line// /}" ] || continue
    before="$(wc -l <"$OUTFILE" | tr -d '[:space:]')"
    run_recipe_line install "$RECIPE" "$line" "$OUTFILE" && continue
    printf 'install: step failed: %s\n' "$line" >&2
    recipe_output_summary 4 "$OUTFILE" "$((before + 1))"; exit 4
  done <<SA_STEPS
$steps
SA_STEPS
  while IFS="$TAB" read -r n rel; do
    [ -n "$n" ] || continue
    target="$TREE/$rel"
    if [ -f "$target" ]; then kept=$((kept + 1)); continue; fi
    mkdir -p "$(dirname -- "$target")" && cp "$files_dir/$n" "$target" || die 3 "install: could not write $target"
    written=$((written + 1)); printf 'file: %s\n' "$target"
  done <<SA_FILES
$list
SA_FILES
  rm -rf "$files_dir"
  sf_load_surfaces "$SURFACE_FILE"
  case "$SF_STATE" in
    missing) doc="$(jq -nc --argjson v "$VIEWPORTS_JSON" '{schemaVersion: 1, viewports: $v, surfaces: []}')" ;;
    ok)      doc="$(jq -c --argjson v "$VIEWPORTS_JSON" --arg given "$VIEWPORTS_ARG" \
               'if $given != "" or ((.viewports // []) | length) == 0 then .viewports = $v else . end' "$SURFACE_FILE")" ;;
    *)       die 3 "install: $SURFACE_FILE is $SF_STATE, and the surface file is never overwritten" ;;
  esac
  write_atomic "$SURFACE_FILE" "$doc"
  write_project_field '.registryPath = $sf | .'"$KEY"'.enabled = true'
  printf 'INSTALLED: %s per %s\nfiles: %s written, %s kept\nsurface-file: %s\nproject-file: %s\n' \
    "$KIND" "$RECIPE" "$written" "$kept" "$SURFACE_FILE" "$PROJECT_FILE"
  sa_commit_if_changed "install wrote nothing new" "New $KIND surfaces setup, installed through the surfaces skill"
  recipe_output_summary 0 "$OUTFILE" 1
}

# -------------------------------------------------------------------- register
do_register() {
  local id="${1:-}" url="" kinds='[]' masks='[]' enabled=false row have doc
  [ -n "$id" ] || die 3 "register: a surface id is required"
  case "$id" in *[!a-z0-9-]*|-*|*-|*--*) die 3 "register: a surface id is kebab case, got: $id" ;; esac
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --enable) require_person "--enable" "a person confirmed this surface"; enabled=true; shift; continue ;;
      --url|--kind|--mask) [ "$#" -ge 2 ] || die 3 "register: $1 needs a value" ;;
      *) die 3 "register: unrecognized argument: $1" ;;
    esac
    case "$1" in
      --url)  url="$2" ;;
      --kind) case "$2" in e2e|visual-regression|visual-parity) ;; *) die 3 "register: a kind is e2e, visual-regression or visual-parity, got: $2" ;; esac
              kinds="$(printf '%s' "$kinds" | jq -c --arg k "$2" '. + [$k] | unique')" ;;
      --mask) masks="$(printf '%s' "$masks" | jq -c --arg m "$2" '. + [$m]')" ;;
    esac
    shift 2
  done
  [ -n "$url" ] || die 3 "register: --url is required"
  [ "$kinds" != "[]" ] || die 3 "register: at least one --kind is required"
  require_surface_file
  row="$(jq -nc --arg id "$id" --arg url "$url" --argjson kinds "$kinds" --argjson enabled "$enabled" --argjson masks "$masks" \
    '{id: $id, url: $url, kinds: $kinds, enabled: $enabled, masks: $masks}')"
  have="$(printf '%s' "$SF_SURFACES" | jq -c --arg id "$id" '[ .[] | select(.id == $id) ][0] // empty')"
  if [ -n "$have" ]; then
    [ "$have" = "$row" ] && { printf 'surface: %s unchanged\n' "$id"; exit 0; }
    die 3 "register: $id is already registered with different fields. Registered: $have. Given: $row. A duplicate id makes the file invalid, so edit the file or choose another id."
  fi
  doc="$(jq -c --argjson row "$row" '.surfaces += [$row]' "$SURFACE_FILE")" || die 3 "register: could not read $SURFACE_FILE"
  write_atomic "$SURFACE_FILE" "$doc"
  printf 'surface: %s enabled=%s kinds=%s\nsurface-file: %s\n' "$id" "$enabled" "$(printf '%s' "$kinds" | jq -r 'join(",")')" "$SURFACE_FILE"
}

# -------------------------------------------------------------------- baseline
do_baseline() {
  local ids="" confirmed=false rows_file fw rp accept count names result rc one
  rows_file="$(mktemp)" || die 3 "baseline: could not create a temporary file"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --check-recipe) [ "$#" -ge 2 ] || die 3 "baseline: --check-recipe needs <framework>=<path>"
                      cr_recipe_pair baseline --check-recipe "$2"; fw="${CR_PAIR%%"$TAB"*}"; rp="${CR_PAIR#*"$TAB"}"
                      : >"$rows_file.one"; cc_parse_recipe "$rp" "Surface commands" "surface_commands" "$rows_file.one"
                      jq -c --arg fw "$fw" '. + {framework: $fw}' "$rows_file.one" >>"$rows_file" 2>/dev/null; rm -f "$rows_file.one"; shift 2 ;;
      --value)        [ "$#" -ge 2 ] || die 3 "baseline: --value needs <name>=<value>"; pc_refuse_forged_value baseline "$2"
                      VALUES="$VALUES$(printf '%s' "$2" | sed 's/=/\t/')
"; shift 2 ;;
      --confirmed)    confirmed=true; shift ;;
      -*) die 3 "baseline: unrecognized argument: $1" ;;
      *) ids="$ids $1"; shift ;;
    esac
  done
  accept="$(jq -sc '[ .[] | select(.id == "visual-regression-accept" and has("argv")) ]' "$rows_file")"; rm -f "$rows_file"
  count="$(printf '%s' "$accept" | jq 'length')"
  [ "$count" -le 1 ] || die 72 "baseline: $(printf '%s' "$accept" | jq -r '[ .[].framework ] | join(" and ")') each declare a visual-regression-accept row."
  [ "$count" -eq 1 ] || die 3 "baseline: no review recipe given carries a visual-regression-accept row with a command, so there is no command that writes a baseline. Pass --check-recipe <framework>=<path>."
  require_surface_file
  [ -n "$(pc_trim "$ids")" ] || ids="$(printf '%s' "$SF_SURFACES" | jq -r '[ .[] | select(.enabled and (.kinds | index("visual-regression"))) | .id ] | join(" ")')"
  ids="$(pc_trim "$ids")"
  [ -n "$ids" ] || die 3 "baseline: no enabled visual-regression surface is registered, so there is nothing to baseline"
  names="$(jq -r '[ .viewports[].name ] | join(",")' "$SURFACE_FILE")"
  # Walked as a here-document rather than `for id in $ids`, because zsh does not split an unquoted expansion.
  while IFS= read -r one; do
    [ -n "$one" ] || continue
    printf '%s' "$SF_SURFACES" | jq -e --arg id "$one" '[ .[] | select(.id == $id and (.kinds | index("visual-regression"))) ] | length == 1' >/dev/null \
      || die 3 "baseline: $one is not a registered visual-regression surface in $SURFACE_FILE"
    printf 'baseline: %s viewports=%s\n' "$one" "$names"
  done <<SA_IDS
$(printf '%s' "$ids" | tr ' ' '\n')
SA_IDS
  if [ "$confirmed" = false ]; then printf 'confirm: run again with --confirmed to write these baselines\n'; exit 0; fi
  [ "$RUN_MODE" = "interactive" ] || { printf 'baselines: none\n'; require_person "--confirmed" "a person confirmed the baselines"; }
  br_require_clean_tree baseline "$TREE"
  VALUES="surfaces$TAB$(printf '%s' "$ids" | tr ' ' '|')
$VALUES"
  [ -z "$(cr_lookup "$VALUES" base-url)" ] || { PLAYWRIGHT_BASE_URL="$(cr_lookup "$VALUES" base-url)"; export PLAYWRIGHT_BASE_URL; }
  mkdir -p "$RECORDS_DIR" || die 3 "baseline: could not create $RECORDS_DIR"
  OUTFILE="$RECORDS_DIR/surfaces-baseline.txt"
  result="$(br_run_resolved "$(printf '%s' "$accept" | jq -c '.[0].argv')" "$TREE" "$OUTFILE" '[]' "$VALUES")"
  case "$result" in
    RAN*) rc="${result#*"$TAB"}" ;;
    UNRESOLVED*) die 3 "baseline: the token {${result#*"$TAB"}} in the accept row has no value; pass --value ${result#*"$TAB"}=<value>" ;;
    *) die 3 "baseline: the accept row holds no token to run" ;;
  esac
  [ "$rc" = "0" ] || { recipe_output_summary 4 "$OUTFILE" 1; exit 4; }
  # Review refuses a dirty tree, and the message is the record of why these baselines changed.
  sa_commit_if_changed "the accept row wrote nothing" "New visual regression baselines for $ids, confirmed by a person through the surfaces skill"
  printf 'baselines: %s\n' "$ids"
  recipe_output_summary 0 "$OUTFILE" 1
}

# --------------------------------------------------------------------- decline
# A person declined one kind's setup. Takes a kind the way install does, since the two kinds are
# separate capabilities: a person may take one and refuse the other.
do_decline() {
  local kind="${1:-}"
  kind_key "$kind"
  require_person decline "a person declined the setup"
  write_project_field '.'"$KEY"'.declined = true'
  printf 'declined: %s\nproject-file: %s\n' "$kind" "$PROJECT_FILE"
}

# ------------------------------------------------------------------------ read
do_read() {
  printf 'project: %s\ncode-path: %s\n' "$PROJECT_DIR" "$TREE"
  printf 'surfaces-field: %s\n' "$(jq -r 'if .surfaces == null then "none" else "e2e=\(if .surfaces.e2e.enabled then "on" elif .surfaces.e2e.declined then "declined" else "off" end) visual-regression=\(if .surfaces.visualRegression.enabled then "on" elif .surfaces.visualRegression.declined then "declined" else "off" end)" end' "$PROJECT_FILE")"
  sf_load_surfaces "$SURFACE_FILE"
  printf 'surface-file: %s (%s)\n' "$SURFACE_FILE" "$SF_STATE"
  [ "$SF_STATE" != "ok" ] || printf '%s' "$SF_SURFACES" | jq -r '.[] | "surface: \(.id) kinds=\(.kinds | join(",")) enabled=\(.enabled) url=\(.url) masks=\(.masks | length)"'
  # A version 5 project holds a YAML registry beside the file. It is named, left in place, and its
  # ids and URLs are candidates for discovery.
  [ ! -f "$TREE/.visual-review/registry.yml" ] || printf 'registry-v5: %s\n' "$TREE/.visual-review/registry.yml"
}

case "$ACTION" in
  read)         do_read ;;
  show|install) do_show_or_install "$@" ;;
  register)     do_register "$@" ;;
  baseline)     do_baseline "$@" ;;
  decline)      do_decline "$@" ;;
  *)            die 3 "unknown action $ACTION, expected read, show, install, register, baseline, decline or step" ;;
esac
