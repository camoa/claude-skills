#!/usr/bin/env bash
# The plugin root: the variable when the platform sets it, else this file's own place.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd -P)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
# The two steps of a test cleanup that a script decides: which files each reader gets, and what
# the readers' reports add up to. The readers and the person decide the rest.
#
#   cleanup-actions.sh where
#   cleanup-actions.sh groups [--max-lines <n>] --glob <glob>...
#   cleanup-actions.sh summary <run folder>
#
# where    prints `project:` with the project folder, then one `framework:` line per framework the
#          project declares, for the recipe lookup.
# groups   lists the files git tracks in this window's repository that a glob matches, and splits
#          them into groups: one per folder, and a folder past --max-lines lines (default 4000)
#          splits, so one reader can hold its group. It writes <run folder>/groups.json, a new run
#          folder under <project>/test-cleanup/, and prints `run:`, `code:` and one `group:` line
#          per group. A glob follows the catalog's rules: `**` is any run of folders, and a glob
#          with no / matches a file name in any folder.
# summary  reads <run folder>/reports/<group>.json for every group, checks each one, and writes
#          <run folder>/summary.md: the tests per category, per group, and each group's causes.
#          It writes nothing while one report is missing or malformed, and names that group.
#
# Exit codes:
#   0  did what was asked
#   1  no project owns this directory
#   2  no tracked file matches the globs
#   3  the script could not do its job, or a report is missing or malformed

set -u

die() { printf 'cleanup-actions: %s\n' "$2" >&2; exit "$1"; }

# shellcheck source=../../../scripts/lib/registry.sh
. "${PLUGIN_ROOT}/scripts/lib/registry.sh"
# shellcheck source=../../../scripts/lib/recipes.sh
. "${PLUGIN_ROOT}/scripts/lib/recipes.sh"

# The rubric's categories, from agents/test-reader.md. A report counts every test under one.
CATEGORIES='["keep","whole-flow","text","duplicate","pinning","variants","replay"]'

ACTION="${1:-}"
[ -n "$ACTION" ] || die 3 "name an action: where, groups or summary"
shift

MATCH="$(registry_resolve_by_directory "$(pwd -P)" 2>/dev/null || true)"
PROJECT_DIR=""
[ -n "$MATCH" ] && PROJECT_DIR="$(printf '%s' "$MATCH" | jq -r '.path // empty')"
[ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ] || die 1 "no project owns $(pwd -P)"

case "$ACTION" in
  where)
    printf 'project: %s\n' "$PROJECT_DIR"
    jq -r '.frameworks // [] | .[] | "framework: \(.)"' "$PROJECT_DIR/project.json" 2>/dev/null \
      || die 3 "where: $PROJECT_DIR/project.json is missing or unreadable"
    ;;

  groups)
    MAX_LINES=4000; GLOBS=""
    while [ $# -gt 0 ]; do
      [ $# -ge 2 ] || die 3 "groups: $1 needs a value"
      case "$1" in
        --glob) GLOBS="$GLOBS$2
" ;;
        --max-lines)
          case "$2" in ''|*[!0-9]*) die 3 "groups: --max-lines takes a number, got: $2" ;; esac
          MAX_LINES="$2" ;;
        *) die 3 "groups: unrecognized argument: $1" ;;
      esac
      shift 2
    done
    [ -n "$GLOBS" ] || die 3 "groups: pass at least one --glob, from the test-authoring recipe"
    CODE="$(git -C "$(pwd -P)" rev-parse --show-toplevel 2>/dev/null)" \
      || die 3 "groups: $(pwd -P) is not inside a git repository"

    LIST="$(mktemp)" || die 3 "groups: could not create a temporary file"
    trap 'rm -f "$LIST"' EXIT
    while IFS= read -r file; do
      while IFS= read -r glob; do
        [ -n "$glob" ] || continue
        if tf_path_matches_catalog_glob "$file" "$glob"; then
          printf '%s\t%s\n' "$file" "$(wc -l <"$CODE/$file" | tr -d ' ')" >>"$LIST"
          break
        fi
      done <<GLOBS_IN
$GLOBS
GLOBS_IN
    done <<FILES_IN
$(git -C "$CODE" ls-files | LC_ALL=C sort)
FILES_IN
    [ -s "$LIST" ] || die 2 "groups: no file git tracks matches: $(printf '%s' "$GLOBS" | paste -sd' ' -)"

    mkdir -p "$PROJECT_DIR/test-cleanup" || die 3 "groups: could not create $PROJECT_DIR/test-cleanup"
    RUN="$(mktemp -d "$PROJECT_DIR/test-cleanup/run-$(date -u +%Y%m%d-%H%M%S)-XXXX")" \
      || die 3 "groups: could not create a run folder"
    # A new group starts at a new folder, or when the next file would take it past the limit.
    awk -F '\t' -v max="$MAX_LINES" '
      function dir(p) { if (p !~ /\//) return "."; sub(/\/[^\/]*$/, "", p); return p }
      { d = dir($1)
        if (n == 0 || d != cur || (lines > 0 && lines + $2 > max)) { n++; cur = d; lines = 0 }
        lines += $2; print n "\t" $1 "\t" $2 }' "$LIST" \
      | jq -R -s '
          split("\n") | map(select(length > 0) | split("\t"))
          | group_by(.[0] | tonumber)
          | map({id: ("g" + .[0][0]), files: map(.[1]), lines: (map(.[2] | tonumber) | add)})' \
      >"$RUN/groups.json" || die 3 "groups: could not write $RUN/groups.json"
    printf 'run: %s\n' "$RUN"
    printf 'code: %s\n' "$CODE"
    jq -r '.[] | "group: \(.id) \(.files | length) files, \(.lines) lines"' "$RUN/groups.json"
    ;;

  summary)
    RUN="${1:-}"
    [ -n "$RUN" ] && [ -r "$RUN/groups.json" ] || die 3 "summary: pass a run folder holding groups.json"
    BAD=""; REPORTS=()
    while IFS= read -r gid; do
      report="$RUN/reports/$gid.json"; REPORTS+=("$report")
      if [ ! -r "$report" ]; then BAD="$BAD $gid (no report)"; continue; fi
      why="$(jq -r --arg g "$gid" --argjson cats "$CATEGORIES" '
        if .group != $g then "it names another group"
        elif (.tests | type) != "number" then "tests is not a number"
        elif ((.counts | type) != "object") or ([.counts | keys[] | select(. as $k | $cats | index($k) | not)] | length > 0)
          then "counts holds a category outside the rubric"
        elif ([.counts[] | select(type != "number" or . < 0)] | length > 0) then "a count is not a number"
        elif ([.counts[]] | add // 0) != .tests then "the counts add up to \([.counts[]] | add // 0), not to its \(.tests) tests"
        elif ([(.proposals // [])[] | select((.action | IN("delete","merge","shrink") | not) or ((.category | IN($cats[1:][])) | not))] | length > 0)
          then "a proposal has an action or a category outside the rubric"
        else empty end' "$report" 2>/dev/null)" || why="it is not valid JSON"
      [ -z "$why" ] || BAD="$BAD $gid ($why)"
    done < <(jq -r '.[].id' "$RUN/groups.json")
    [ -z "$BAD" ] || die 3 "summary: dispatch the reader again for these groups, and run summary again:$BAD"

    jq -n -r --argjson cats "$CATEGORIES" --arg run "$RUN" \
      --slurpfile groups "$RUN/groups.json" '
      [inputs] as $reports
      | ($reports | map(.tests) | add) as $total
      | "# Test cleanup summary", "",
        "Run: `\($run)`. Groups read: \($reports | length). Tests read: \($total).", "",
        "| Category | Tests | Share |", "|---|---|---|",
        ($cats[] as $c | ($reports | map(.counts[$c] // 0) | add) as $n
          | "| \($c) | \($n) | \(if $total > 0 then ($n * 100 / $total | floor) else 0 end)% |"),
        "", "## Per group", "",
        "| Group | Files | Tests | Keep | Proposals |", "|---|---|---|---|---|",
        ($reports[] as $r | ($groups[0][] | select(.id == $r.group)) as $g
          | "| \($r.group) | \($g.files | length) | \($r.tests) | \($r.counts.keep // 0) | \(($r.proposals // []) | length) |"),
        "", "## Causes", "",
        ($reports[] as $r | ($r.causes // [])[] | "- \($r.group): \(.)")' \
      "${REPORTS[@]}" \
      >"$RUN/summary.md" || { rm -f "$RUN/summary.md"; die 3 "summary: could not write $RUN/summary.md"; }
    printf 'summary: %s\n' "$RUN/summary.md"
    ;;

  *) die 3 "unknown action: $ACTION. The actions are where, groups and summary." ;;
esac
