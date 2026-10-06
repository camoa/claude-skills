#!/usr/bin/env bash
# task-helpers.sh: the four helpers every stage script needs before it can touch a task folder.
#
# scope-actions.sh, research-actions.sh and design-actions.sh each carried their own copy of these
# four. One implementation, not three copies drifting apart, the same reason schema-check.sh exists.
#
# The caller defines die1, die2, die3, die4 and die79 before it sources this file, each with its own
# script name in the message, so a refusal still says which script refused, and PLUGIN_ROOT, so
# this library can find the task script. Those are the only things this library takes from its
# caller rather than owning.
#
# Public functions:
#
#   resolve_task_folder <path> <action>   prints the canonical task folder, or dies
#   looks_like_flag <value>               true when the value is another option, not data
#   is_blank <value>                      true when the value is empty or only whitespace
#   parse_finding_ref <action> <ref> <research folder>
#                                         sets FINDING_REF_SEARCH and FINDING_REF_N from
#                                         <search>#<n>, counted from 1; 1 when no such search
#   write_atomic <target> <content>       writes through a temporary file beside the target
#   plugin_version                        prints the version from the plugin's own plugin.json,
#                                         or unknown when that file cannot be read
#   version_at_least <have> <want>        true when <have> is <want> or later
#   warn_newer_installed                  one stderr line when a newer copy of this plugin sits
#                                         beside PLUGIN_ROOT; runs once when this file is sourced
#   warn_session_version                  one stderr line when the session loaded another version
#                                         of this plugin; runs once when this file is sourced
#   task_run_mode <folder> <stage>        prints autonomous when the task's mode is autonomous and
#                                         covers the stage, or is light, else interactive
#   task_is_light <folder>                true when the task's mode is light
#   log_compromise <folder> <stage> <skipped> <normal>
#                                         adds one row to COMPROMISES.md in the task folder
#   task_env_recipe_change <folder> <path> <tree> <commit>
#                                         true when `environment up` recorded the path and the
#                                         commit still holds that content
#   task_env_rerun_step <folder> <files>  the next step when `environment up` ran before it
#                                         recorded the recipe's files and one of them is unmatched
#   task_fork_point <folder> <tree>       prints the commit the task's branch forked from its
#                                         base, or nothing when the record holds no base
#   task_env_restore_commit <folder> <tree> [worktree]
#                                         prints the latest commit on the files `up` changed that
#                                         are back at their fork point content, a tab and those
#                                         files; true when one of them is a file the fork point
#                                         has. `worktree` also reads the working files
#   automated_tests <folder>              prints yes, no or not-asked: the contract's answer to
#                                         whether the task has automated tests
#   mark_task_in_progress <folder> <why> <stage>
#                                         moves the task to in_progress once, before a first write
#   commit_task_change <project> <subject> <why> <principle> <ruled out> <task> <stage> [<folder>...]
#                                         commits tasks/<task> in the project folder, and the
#                                         folders named after it, five-field shape
#   commit_stage_close <folder> <stage> <subject> <why>
#                                         the stage-boundary commit of one task folder; says so
#                                         on stderr and returns when it cannot commit
#   distill_read <folder> <stage>         reads the stage's distill sidecar and prints its verdict
#   distill_deferred <stage>              prints the line a light task's scope or research distill shows
#   distill_stamp <folder> <stage>        writes the stage's stamp: the sidecar and records hashes
#   sidecar_set_aside <path>              moves a malformed sidecar aside, dated, and says where
#   task_tree_from_git <folder> <code> <action>
#                                         prints the registered worktree carrying the task's
#                                         branch, and repairs worktree.path when git disagrees
#   task_worktree_group <codePath> <action>
#                                         prints the folder that holds the repository's task trees
#   task_worktree <folder> <action>       prints the task's worktree path, making the tree first
#                                         when task.json does not record one
#   task_stage <folder> <review-word>     prints the stage the task stands at, from its records
#   task_review_outdated <folder>         true, and prints both ranges, when the review covers
#                                         a commit range the finished build no longer ends at
#   active_tree_for <codePath> <dir>      prints <dir>'s git top level when it is a worktree of
#                                         the <codePath> repository, else <codePath>
#   playbooks_record_path <folder>        prints the path of the playbook record research loads
#   playbooks_path_json <folder>          prints that path as a JSON string, or null when absent
#   playbooks_person_path                 prints the path of the person's own playbook file
#   DENIES_JQ                             a jq definition, `denies`, true when a string carries
#                                         a negation word
#   REASONING_JQ                          jq definitions: `struckMark`, and `liveReasoning`,
#                                         a work order's reasoning with no struck paragraph
#   CITES_JQ                              a jq definition, `citations($known)`, the findings
#                                         a finding's text cites
#   IFACE_PATH_JQ                         a jq definition, `ifacePath`, a backticked interface
#                                         token as a repository path, or empty
#
# Every script that sources this file runs warn_newer_installed and warn_session_version. These
# never source it, so they never warn: next's legacy-tasks.sh, the scripts in scripts/ other than
# check-design.sh and check-research.sh, and every hook but session-start.sh, which discards the
# line. tool-actions.sh sources it in `require` alone.
# project-actions.sh sources it in check-machine alone.
#
# task_worktree and resolve_task_folder both take resolve_project_folder, project_code_path_value
# and is_git_repo from scripts/lib/recipes.sh. Two callers, scope and design, do not source that
# file, so resolve_task_folder sources it when the function is absent, the way task_worktree
# sources playbooks.sh for pb_slug. Every caller resolves inside a command substitution, so that
# source lands in a subshell and clobbers nothing. The refusal takes die79 from the caller.

# Whether a done-when clause carries a negation word. Three readers ask it: design's check, the
# tests brief and the freeze's --absence refusal. So they read one clause alike (gap row 209). The
# word list is closed, so it reads the same clause the same way every time. A word ending in n't
# after a letter is a negation too, so "doesn't" and "won't" deny and a bare "n't" does not.
# U+2018, U+2019 and U+02BC read as a straight apostrophe first, because a clause pasted from a
# document or typed on a phone carries one of them. A negation word is not an absence: "the form
# shows no legacy field" denies and is a behaviour. Each reader treats this as a floor.
# shellcheck disable=SC2034 # read by the sourcing script
DENIES_JQ='
  def denies: ascii_downcase | gsub("[\u2018\u2019\u02bc]"; "\u0027")
    | [scan("[a-z0-9]+(?:\u0027[a-z]+)?")]
    | any(.[]; . as $w
          | ((["no", "not", "never", "neither", "nor", "none", "nothing", "without", "cannot"]
              | index($w)) != null)
            or ($w | test("[a-z]n\u0027t$")));'

# A work order's reasoning is paragraphs separated by a blank line. Design marks a paragraph
# struck with a prefix, so the record keeps the old rule and a person sees it marked. A
# brief carries only the live paragraphs, so a builder never reads two rules (gap row 215).
# Design's update writes the mark and the briefs read it, so both take it from here.
# shellcheck disable=SC2034 # read by the sourcing script
REASONING_JQ='
  def struckMark: "[struck] ";
  def liveReasoning: (.reasoning // "") | split("\n\n")
    | map(select(startswith(struckMark) | not)) | join("\n\n");'

# The findings a finding's text cites, any case: `<search>#<n>`, or `<search>[.json|.md]
# finding <n>`, or `findings <n> and <n>` (gap rows 235 and 236). Research's drop and its check
# read citations alike, so they take them from here. `citations($known)` yields {search, n} per
# number. A bare name before `finding` counts only when $known, the task's search names, holds
# it, so "see finding 2" in prose is not read as a search called "see".
# shellcheck disable=SC2034 # read by the sourcing script
CITES_JQ='
  def citations($known):
    [ scan("(?i)(?<![a-z0-9-])([a-z0-9]+(?:-[a-z0-9]+)*)(\\.json|\\.md)?(?:#([0-9]+)|\\s+findings?\\s+([0-9]+(?:\\s+and\\s+[0-9]+)*))") ]
    | .[] | (.[0] | ascii_downcase) as $s
    | select(.[1] != null or .[2] != null or (($known | index($s)) != null))
    | (if .[2] != null then .[2] else (.[3] | scan("[0-9]+")) end)
    | {search: $s, n: tonumber};'

# A backticked token from an order's interface, read as a repository path (gap row 253). Design's
# check compares it with the order's owned and known paths, and build-recheck asks git whether it
# exists, so both read a token alike. A leading ./ goes, and so does everything from the first
# colon, so `src/Foo.php::bar()` and `src/Foo.php:12` read as src/Foo.php. What is left is a path
# when it holds a slash, and is neither absolute nor a URL. Anything else yields empty.
# shellcheck disable=SC2034 # read by the sourcing script
IFACE_PATH_JQ='
  def ifacePath: select(test("\\s|://") | not) | ltrimstr("./") | sub(":.*$"; "")
    | select(test("/") and (startswith("/") | not));'

# Where git lists this task's tree, and the record repaired when git disagrees. $1 the canonical
# task folder, $2 the resolved code path, $3 the action's own name. Prints the registered worktree
# that carries the task's branch and is on disk, and nothing when git lists no such tree. The main
# checkout is skipped: a branch checked out there is not this task's tree. One reader answers
# "where is this task's tree", and the refusal below and the producer both ask it, so they never
# disagree. worktree.path has one producer, so git's answer is written to that one field again,
# and one line says so. Calls no die function.
task_tree_from_git() {
  local folder="$1" code="$2" who="$3" branch wt found cand line
  branch="$(jq -r '.worktree.branch // empty' "$folder/task.json" 2>/dev/null)"
  [ -n "$branch" ] || return 0
  found=""
  cand=""
  while IFS= read -r line; do
    if [ "${line#worktree }" != "$line" ]; then cand="${line#worktree }"; fi
    if [ "$line" = "branch refs/heads/$branch" ] && [ "$cand" != "$code" ]; then found="$cand"; fi
  done <<GIT_WORKTREES
$(git -C "$code" worktree list --porcelain 2>/dev/null)
GIT_WORKTREES
  # A path git still registers and disk no longer holds is not where the tree is.
  [ -n "$found" ] && [ -d "$found" ] || return 0
  wt="$(jq -r '.worktree.path // empty' "$folder/task.json" 2>/dev/null)"
  if [ "$found" != "$wt" ]; then
    write_atomic "$folder/task.json" "$(jq --arg wp "$found" '.worktree.path = $wp' "$folder/task.json")"
    printf '%s: git lists this task tree at %s, and task.json recorded %s. The record now says %s.\n' \
      "$who" "$found" "$wt" "$found" >&2
  fi
  printf '%s' "$found"
}

# The task folder must already exist and already hold a task.json (ideal/scope.md, "Scope runs
# against a task that already exists": a stage finds a task or says it cannot, it never scaffolds
# one). Prints the canonical path on success.
resolve_task_folder() {
  local arg="$1" who="$2" p wt project code here top found
  [ -n "$arg" ] || die3 "$who: a task folder is required"
  p="$(cd "$arg" 2>/dev/null && pwd -P)" || die1 "$who: task folder not found: $arg"
  [ -f "$p/task.json" ] || die1 "$who: $p has no task.json; this is not a task folder"
  # Every stage action but read runs inside the task's own worktree, or a folder under it
  # (ideal/task.md, "Two windows"). A task with no field yet is not refused here: the action that
  # makes the tree names it, and the next action refuses.
  [ "$who" != "read" ] || { printf '%s' "$p"; return 0; }
  wt="$(jq -r '.worktree.path // empty' "$p/task.json" 2>/dev/null)"
  [ -n "$wt" ] || { printf '%s' "$p"; return 0; }
  # Git says where this window is, not a string prefix on the recorded path. A tree moved with
  # `git worktree move` is still this task's tree, and a folder git no longer registers is not.
  # active_tree_for answers both, and it needs the project's own code path to answer at all.
  if ! command -v resolve_project_folder >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    source "${PLUGIN_ROOT}/scripts/lib/recipes.sh" \
      || die3 "$who: the library failed to load: recipes.sh"
  fi
  project="$(resolve_project_folder "$p")" || project=""
  code=""
  [ -z "$project" ] || code="$(project_code_path_value "$project")"
  here="$(pwd -P)/"
  # Without a code path on disk git cannot be asked at all, so the string test this helper used
  # before is the evidence left. Standing in the tree still passes, so a prefixed call works.
  if [ -z "$code" ] || [ ! -d "$code" ]; then
    [ -d "$wt" ] && [ "${here#"$wt"/}" = "$here" ] \
      && die79 "$who: this task builds in its worktree $wt, and this window is at ${here%/}. Start the call with: cd $wt &&"
    printf '%s' "$p"
    return 0
  fi
  code="$(cd "$code" && pwd -P)"
  top="$(active_tree_for "$code" "${here%/}")"
  # Which registered tree carries this task's branch. active_tree_for answers about the current
  # directory alone, and a tree moved while the window stands elsewhere is invisible to it.
  found="$(task_tree_from_git "$p" "$code" "$who")"
  [ -z "$found" ] || wt="$found"
  if [ "$top" = "$wt" ]; then
    task_tree_turn "$p" "$wt" "$who"
    printf '%s' "$p"; return 0
  fi
  # A recorded tree gone from disk, that git places nowhere else, is not refused: the action that
  # makes it again names it.
  [ -d "$wt" ] || { printf '%s' "$p"; return 0; }
  [ "$(active_tree_for "$code" "$wt")" = "$wt" ] \
    || die79 "$who: task.json records the worktree $wt, and git does not list it as a worktree of $code. Nothing written there reaches the branch. Remove that folder, and the next action that needs the code makes the tree again."
  # The route named is the one that works where this call ran. EnterWorktree takes a worktree of
  # this window's own repository on first entry, and from a worktree session only a target under
  # .claude/worktrees/ (the mirror's tools reference). A task tree is outside the checkout,
  # so entry is offered from the checkout alone. The prefix works from anywhere.
  if [ "$top" = "$code" ] && [ "${here#"$code"/}" != "$here" ]; then
    die79 "$who: this task builds in its worktree $wt, and this window is at ${here%/}. Enter the tree with EnterWorktree, or start the call with: cd $wt &&"
  fi
  if [ "$top" = "$code" ]; then
    die79 "$who: this task builds in its worktree $wt, and this window is at ${here%/}, outside the code repository $code. Entry refuses from there, so start the call with: cd $wt &&"
  fi
  die79 "$who: this task builds in its worktree $wt, and this window is in another worktree, $top. Entry reaches only trees under .claude/worktrees/ from there, so start the call with: cd $wt &&"
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

# A research finding is named `<search>#<n>`: its search's file under research/, and its place
# in that file's findings, counted from 1 as research-render.sh numbers it. Research's serve and
# drop and design's account take this one form, so a person meets one number (gap row 235).
# $1 the action, $2 the reference, $3 the research folder. Sets FINDING_REF_SEARCH and
# FINDING_REF_N. Dies 3 on a reference not in that form. Returns 1 when research holds no file
# for the search, before the number is read, so each caller refuses that with its own exit code.
# Whether the finding exists is the caller's question.
parse_finding_ref() {
  local who="$1" ref="$2" dir="$3" search n
  search="${ref%#*}"; n="${ref##*#}"
  case "$ref" in *'#'*) ;; *) die3 "$who: --finding must be <search>#<n>, got '${ref:-<nothing>}'" ;; esac
  case "$search" in ''|*[!a-z0-9-]*|-*|*-) die3 "$who: --finding must be <search>#<n>, got '$ref'" ;; esac
  FINDING_REF_SEARCH="$search"
  [ -f "$dir/$search.json" ] || return 1
  case "$n" in ''|0*|*[!0-9]*) die3 "$who: --finding must be <search>#<n>, numbered from 1 as research/$search.md shows it, got '$ref'. $search#1 is: $(jq -r '(.findings // [])[0].text // "" | split("\n")[0]' "$dir/$search.json" 2>/dev/null)" ;; esac
  FINDING_REF_N="$n"
}

# Writes $2 (assumed already-valid JSON text) to $1 through a temporary file in the target's own
# directory, then renames over the target. The rename stays inside one filesystem, and a failure
# partway through never leaves a half-written file at $1.
#
# This refuses content with nothing in it, and leaves the target the bytes it had. Almost every
# caller builds $2 in a jq command substitution. A jq that cannot read its input exits non-zero
# and prints nothing, so the substitution yields an empty string. Without this test the rename
# puts an empty file over a record the task still needs, and the caller still exits 0. The test
# lives here, once, rather than at each call site, so a caller added later cannot reproduce the
# defect by hand (live-run row 173).
write_atomic() {
  local target="$1" content="$2" dir tmp
  is_blank "$content" && die3 "refused to write $target: the content had nothing in it. Nothing was written"
  dir="$(dirname -- "$target")"
  tmp="$(mktemp "${dir}/.$(basename -- "$target").XXXXXX")" \
    || die3 "could not create a temporary file in $dir"
  printf '%s\n' "$content" > "$tmp" || { rm -f "$tmp"; die3 "could not write $tmp"; }
  mv -f "$tmp" "$target" || { rm -f "$tmp"; die3 "could not write $target"; }
}

# The plugin version, from .claude-plugin/plugin.json under the caller's PLUGIN_ROOT. Every stage
# close record carries it, so a task that spans a plugin update shows which rules wrote which
# record. Live-run row 134 had critics dispatched by beta.15 and the close written by beta.21,
# and nothing on disk said so. Nothing reads the field back; it is for a person or a later
# reader. A file that is missing, unreadable or malformed prints `unknown`, never an empty
# string. The record then still says a version was asked for and not found. warn_newer_installed
# reads the same field in its one scan of this folder and its siblings.
plugin_version() {
  local version
  version="$(jq -r '.version // empty' "${PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null)"
  [ -n "$version" ] || version="unknown"
  printf '%s' "$version"
}

# True when $1, a dotted version, is $2 or later. Three fields, compared as numbers, because
# `sort -V` is not on every build. A field that is not a number counts as zero, so two
# prereleases of one version compare equal.
version_at_least() {
  local have="$1" want="$2" hp wp i
  i=1
  while [ "$i" -le 3 ]; do
    hp="$(printf '%s' "$have" | cut -d. -f"$i")"
    wp="$(printf '%s' "$want" | cut -d. -f"$i")"
    case "$hp" in ''|*[!0-9]*) hp=0 ;; esac
    case "$wp" in ''|*[!0-9]*) wp=0 ;; esac
    [ "$hp" -gt "$wp" ] && return 0
    [ "$hp" -lt "$wp" ] && return 1
    i=$((i + 1))
  done
  return 0
}

# A plugin update keeps the old version's folder in the plugin cache, one folder per version
# under one parent. A skill loaded before the update still names the old folder's scripts, and
# they still run (gap row 238). So every script that sources this file says so, once, when a
# sibling folder holds this plugin at a later version. A sibling counts only when its plugin.json
# carries this plugin's name, so a marketplace clone, whose siblings are other plugins, stays
# quiet. It warns and never refuses: the old scripts still work, and the person decides when to
# reload. stderr, because stdout of several actions is read as data. Nothing is written.
#
# One jq call reads every plugin.json and compares inside jq, because a call per folder cost about
# half a second per script start on a cache of 23 versions. The files are read as raw lines and
# parsed per file, so one malformed file drops out alone. The key is the first three dotted fields
# as numbers, a field that is not a number counting as zero, as version_at_least reads them. The
# export marks the scan done, warned or not, so a script another script started does not scan
# again.
#
# Claude Code leaves `.orphaned_at` in a cache folder it no longer uses. The mirror does not
# document that file, so this rests on observed behaviour. A sibling carrying it is not installed
# and is skipped, so a downgrade does not warn. The running folder counts either way. If the
# marker is renamed, orphaned folders count again, and the scan warns more, not less.
warn_newer_installed() {
  local dir found
  [ -z "${AIDA_NEWER_CHECKED:-}" ] || return 0
  export AIDA_NEWER_CHECKED=1
  set -- "${PLUGIN_ROOT}/.claude-plugin/plugin.json"
  for dir in "$(dirname -- "$PLUGIN_ROOT")"/*/; do
    # The running folder is already $1; named twice, its lines would join into two objects.
    [ "${dir}.claude-plugin/plugin.json" != "$1" ] && [ -f "${dir}.claude-plugin/plugin.json" ] \
      && [ ! -e "${dir}.orphaned_at" ] && set -- "$@" "${dir}.claude-plugin/plugin.json"
  done
  found="$(jq -nrR --arg own "$1" '
    def key: (split(".")[0:3] | map(tonumber? // 0)) + [0, 0, 0] | .[0:3];
    [inputs | {f: input_filename, l: .}] | group_by(.f)
    | map({f: .[0].f, j: (map(.l) | join("\n") | fromjson?)} | select(.j | type == "object"))
    | (map(select(.f == $own))[0].j // {}) as $me
    | select(($me.name | type) == "string" and ($me.version | type) == "string")
    | [.[].j | select(.name == $me.name and (.version | type) == "string") | .version]
    | max_by(key) as $top
    | select(($top | key) > ($me.version | key))
    | "AIDA \($top) is installed, and this script runs from \($me.version). Run /reload-plugins, load the skill again, then restart the current step on \($top)."
  ' "$@" 2>/dev/null)"
  [ -z "$found" ] || printf '%s\n' "$found" >&2
  return 0
}

# The other direction (gap row 311): this script is not the version the session loaded. The
# session keeps the agents and hooks it loaded at start, so a role can lack a tool this step needs,
# and the first sign is a record that never appears. A script run through Bash cannot see the
# session's plugin root (the mirror's plugins reference, "Environment variables"). The
# session-start hook exports the loaded version as AIDA_SESSION_PLUGIN_VERSION, which this reads.
# Unset, nothing is known and nothing is said. /reload-plugins reloads agents and hooks but does
# not run that hook again, so after a reload the export is stale and the line says "may". A new
# session clears both. The export marks the check done; check-machine sets it first, because it
# reports the same change itself.
warn_session_version() {
  local own
  [ -z "${AIDA_SESSION_CHECKED:-}" ] || return 0
  export AIDA_SESSION_CHECKED=1
  [ -n "${AIDA_SESSION_PLUGIN_VERSION:-}" ] || return 0
  own="$(plugin_version)"
  [ "$own" != "unknown" ] && [ "$own" != "$AIDA_SESSION_PLUGIN_VERSION" ] || return 0
  printf 'This session started on AIDA %s, and this script runs from %s. The agents and hooks loaded at start may still be %s. A new session loads %s for both; then restart the current step.\n' \
    "$AIDA_SESSION_PLUGIN_VERSION" "$own" "$AIDA_SESSION_PLUGIN_VERSION" "$own" >&2
  return 0
}

# The run mode of one stage, from task.json (task-schema.json, runMode and runModeStages). The
# mode is autonomous for a stage when the task's runMode is autonomous and runModeStages is absent
# or names that stage; every other case is interactive, the safe assumption (foundations.md, Run
# mode). This is the one reader of those two fields: a stage that read runMode alone would run a
# stage the person kept for themselves without asking. An unreadable file answers interactive.
# A light task reads autonomous for every stage, so it runs on the autonomous machinery (gap row
# 197). What light skips on top of that is behind task_is_light.
#
# A name in runModeStages that is not one of the six matches no stage, so the mode reads
# interactive for it for ever. That is the safe direction, and it discards what a person asked
# for, so this names the value on stderr every time it reads one. The task check refuses such a
# task, and it runs from `task start` alone, which a task already in progress never reaches. This
# is the reader every stage goes through, so it is where the word is said. Nothing dies here: a
# stage stopping mid-task over a field whose only effect is to ask a person more often would cost
# more than the defect.
# $1 the canonical task folder, $2 the stage name as the skills spell it.
task_run_mode() {
  local read_out answer unknown
  read_out="$(jq -r --arg stage "$2" '
      (if (.runMode // "") == "light" then "autonomous"
       elif (.runMode // "") != "autonomous" then "interactive"
       elif ((.runModeStages // []) | length) == 0 then "autonomous"
       elif (.runModeStages | index($stage)) != null then "autonomous"
       else "interactive" end),
      ([ (.runModeStages // [])[] | tostring ] | map(. as $named
         | select((["scope","research","design","implement","review","completion"] | index($named)) == null))
       | join(", "))' "$1/task.json" 2>/dev/null)"
  answer="$(printf '%s\n' "$read_out" | sed -n 1p)"
  unknown="$(printf '%s\n' "$read_out" | sed -n 2p)"
  [ -z "$unknown" ] \
    || printf 'task-helpers: %s/task.json names a run-mode stage that matches no stage: %s. The six are scope, research, design, implement, review and completion. A name outside them reads interactive for ever. Repair it with `task set-run-mode`.\n' "$1" "$unknown" >&2
  if [ "$answer" = "autonomous" ]; then printf 'autonomous'; else printf 'interactive'; fi
}

# True when the task's runMode is light (task-schema.json, runMode). Every light rule is behind
# this one test, so an interactive or autonomous task never reaches one. $1 the task folder.
task_is_light() {
  [ "$(jq -r '.runMode // ""' "$1/task.json" 2>/dev/null)" = "light" ]
}

# The one overlap rule for owned files, read by check-design.sh and by implementation's `start`.
# Input: the work orders as a JSON array. Output: one {ids, path} per entry two orders both
# declare, compared as declared strings. An entry both orders list in sharedFiles is not an
# overlap, because each order only adds to that file (gap row 287).
OWNED_OVERLAP_JQ='
  [ range(0; length) as $i | range($i + 1; length) as $j
    | .[$i] as $a | .[$j] as $b
    | ($a.ownedFiles // [])[] as $p
    | select(($b.ownedFiles // []) | index($p) != null)
    | select(((($a.sharedFiles // []) | index($p) != null) and (($b.sharedFiles // []) | index($p) != null)) | not)
    | {ids: [$a.id, $b.id], path: $p} ]'

# One row of the compromises log, COMPROMISES.md in the task folder (gap row 197). The code that
# decides a skip calls this, so the log never rests on a model's memory. The log is AIDA's record,
# so it never enters the code repository (gap row 334): the stage close commits the task folder.
# A later normal task takes the log as its scope. A row already in the file is not written again,
# so a step run twice logs once. A write that fails is said on stderr and does not stop the stage.
# $1 the task folder, $2 the stage, $3 what was skipped, $4 what a normal run would do.
# COMPROMISES_FILE is the file's one name.
COMPROMISES_FILE="COMPROMISES.md"
log_compromise() {
  local file="$1/$COMPROMISES_FILE" row
  row="| $(basename -- "$1") | $2 | $(printf '%s' "$3" | sed 's/|/\\|/g') | $(printf '%s' "$4" | sed 's/|/\\|/g') |"
  [ -f "$file" ] && grep -qxF -- "$row" "$file" && return 0
  if [ ! -f "$file" ]; then
    printf '%s\n' "# Compromises" "" \
      "A light run skipped each step below, or built a fake in its place. A later normal task takes" \
      "this list as its scope. A fake is marked in the code with AIDA-FAKE." "" \
      "| Task | Stage | Skipped | A normal run would |" "|---|---|---|---|" >"$file" \
      || { printf 'task-helpers: could not write %s\n' "$file" >&2; return 0; }
  fi
  printf '%s\n' "$row" >>"$file"
  printf 'compromise: %s: %s\n' "$2" "$3"
}

# True when $2, a changed path, is one `task environment up` recorded in worktree.recipeChanges of
# the task folder $1, and the commit $4 in the tree $3 still holds the content up recorded (gap
# row 256). Those are the recipe's `## Files` and the files its `## Preconditions` names, such as
# one where the recipe demands a person delete a line. No order owns them, so the owned-files
# checks in implementation and review set them aside. A later edit changes the content, so it is
# judged.
task_env_recipe_change() {
  local blob
  blob="$(jq -r --arg p "$2" '[ (.worktree.recipeChanges // [])[] | select(.path == $p) | .blob ][0] // empty' "$1/task.json" 2>/dev/null)"
  [ -n "$blob" ] && [ "$(git -C "$3" rev-parse -q --verify "$4:$2" 2>/dev/null)" = "$blob" ]
}

# The next step an owned-files check adds when it reads unmet on a task whose site came up before
# `up` wrote worktree.recipeChanges, so nothing was set aside. Prints nothing otherwise, and
# nothing when no unmatched file is one `up` would record: a file of the recipe's `## Files`, or a
# name its `## Preconditions` prose puts in backticks. Rerunning cannot clear any other file (gap
# row 269). Running `up` again writes the field and commits nothing for files already committed.
# $1 the task folder, $2 the unmatched files joined by ", ".
task_env_rerun_step() {
  local recipe dir names="" one rest="$2, "
  recipe="$(jq -r 'if .worktree.recipeChanges == null then .environment.recipe // empty else empty end' "$1/task.json" 2>/dev/null)"
  [ -n "$recipe" ] || return 0
  # A recipe that is gone names no file, so any unmatched file may be one `up` would record.
  if [ -f "$recipe" ]; then
    dir="$(mktemp -d)" || return 0
    names="$(recipe_files_into "$recipe" Files "$dir" | cut -f2; recipe_precondition_names "$recipe")"
    rm -rf "$dir"
  fi
  while [ -n "${rest#, }" ]; do
    one="${rest%%, *}"; rest="${rest#*, }"
    [ -n "$one" ] || continue
    [ ! -f "$recipe" ] || printf '%s\n' "$names" | grep -qxF -- "$one" || continue
    jq -r '" The site of this task came up before `task environment up` recorded the files its recipe changed, so none of them was set aside. Run `task environment \(.id) up` again to record them, then run this step again."' "$1/task.json" 2>/dev/null
    return 0
  done
}

# The commit the branch in the tree $2 forked from worktree.base of the task folder $1. Prints
# nothing when the record holds no base.
task_fork_point() {
  local base
  base="$(jq -r '.worktree.base // empty' "$1/task.json" 2>/dev/null)"
  [ -z "$base" ] || git -C "$2" merge-base "${base#commit:}" HEAD 2>/dev/null
}

# Whether the tree $2 has put back what `task environment up` changed for the task folder $1 (gap
# row 262). The changed files are those in worktree.recipeChanges whose recorded content differs
# from the fork point. A changed file is back when HEAD holds it at its fork point content, or
# lacks it where the fork point does. With $3 `worktree`, a working file at that content is back
# too: a person may put a line back without a commit, and a site command reads the working file.
# The content decides, never a commit subject, so a restore a person made under any subject
# counts. Prints the short id of the latest commit on the files that are back, a tab, and those
# files joined by ", ". Prints nothing when none is back or the record holds no base.
# Returns 0 only when a file that is back is one the fork point has. Such a file is where a
# recipe's demanded change lives, as a DDEV worktree's `.ddev/config.yaml` without its `name:`.
# Back at the fork point, it names the main checkout's project again, so a site command there can
# reach the main checkout's site. A file the fork point lacks, such as a `## Files` script, names
# no site, and a branch may drop one.
task_env_restore_commit() {
  local folder="$1" tree="$2" mode="${3:-}" fork one blob base_blob here tab trunk=no
  tab="$(printf '\t')"
  fork="$(task_fork_point "$folder" "$tree")"
  [ -n "$fork" ] || return 1
  set --
  while IFS="$tab" read -r one blob; do
    [ -n "$one" ] || continue
    base_blob="$(git -C "$tree" rev-parse -q --verify "$fork:$one" 2>/dev/null)"
    [ "$blob" != "$base_blob" ] || continue
    if [ "$(git -C "$tree" rev-parse -q --verify "HEAD:$one" 2>/dev/null)" != "$base_blob" ]; then
      [ "$mode" = worktree ] || continue
      here=""
      [ ! -f "$tree/$one" ] || here="$(git -C "$tree" hash-object -- "$one")"
      [ "$here" = "$base_blob" ] || continue
    fi
    [ -z "$base_blob" ] || trunk=yes
    set -- "$@" "$one"
  done <<TH_ROWS
$(jq -r '(.worktree.recipeChanges // [])[] | .path + "\t" + .blob' "$folder/task.json" 2>/dev/null)
TH_ROWS
  [ "$#" -gt 0 ] || return 1
  printf '%s\t' "$(git -C "$tree" log -1 --format=%h -- "$@" 2>/dev/null)"
  printf '%s\n' "$@" | paste -sd, - | sed 's/,/, /g' | tr -d '\n'
  [ "$trunk" = yes ]
}

# The contract's answer to whether this task has automated tests (alignment-schema.json,
# automatedTests). Prints `no` only when the field is false. `not-asked` when it is absent or the
# contract cannot be read, which every reader takes as a task with tests. Scope, research and
# design each read the answer, so the reading lives here once. $1 the canonical task folder.
automated_tests() {
  local answer
  answer="$(jq -r 'if has("automatedTests") | not then "not-asked" elif .automatedTests then "yes" else "no" end' \
    "$1/alignment.json" 2>/dev/null)"
  [ -n "$answer" ] || answer="not-asked"
  printf '%s' "$answer"
}

# The orders implementation has started, as a JSON array of ids. Started means a ledger step
# reached or an attempt spent, a frozen test record, or a build record. Design's `remove` and
# implementation's `start` both read it. $1 the canonical task folder.
started_orders_json() {
  local impl="$1/implementation" ids f
  ids="$(jq -c '[ (.orders // [])[] | select(.lastStep != null or (.attemptsUsed // 0) > 0) | .id ]' "$impl/ledger.json" 2>/dev/null)"
  [ -n "$ids" ] || ids='[]'
  # find, not a glob: zsh refuses a glob that matches nothing.
  while IFS= read -r f; do
    f="$(basename -- "$f" .json)"
    ids="$(printf '%s' "$ids" | jq -c --arg id "${f#*-}" 'if index($id) == null then . + [$id] else . end')"
  done < <(find "$impl" -mindepth 1 -maxdepth 1 -type f \( -name 'tests-wo*.json' -o -name 'build-wo*.json' \) 2>/dev/null)
  printf '%s' "$ids"
}

# Moves the task to in_progress the first time a stage writes into it (skills/task/SKILL.md,
# `start`: a task becomes in progress the moment a stage first writes an artifact into it). It
# reads the state first, so a task already in progress costs no process and prints nothing. Any
# other state goes through task-actions.sh start, which refuses a completed task, commits, and
# runs the task check. The run mode passed is the task's own, for the calling stage, through
# task_run_mode, the one source every stage reads it from. The task script's own output is shown
# only when it refuses: the check it runs writes its report to records/check-task.json either way.
# One line passes through, `environment:`, so the stage that called this sees the site offer
# the task skill makes at start (skills/task/SKILL.md, `start`), whoever called it.
# $1 the canonical task folder, $2 why, in a few words, $3 the calling stage. Dies through die3
# on a refusal, so a stage never writes into a task that is not in progress.
mark_task_in_progress() {
  local task_folder="$1" why="$2" stage="$3" state run_mode said
  state="$(jq -r '.state // ""' "$task_folder/task.json" 2>/dev/null)"
  [ "$state" != "in_progress" ] || return 0
  run_mode="$(task_run_mode "$task_folder" "$stage")"
  said="$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "${PLUGIN_ROOT}/skills/task/scripts/task-actions.sh" \
      --run-mode "$run_mode" start --project "$(dirname -- "$(dirname -- "$task_folder")")" \
      "$(basename -- "$task_folder")" -- "$why" 2>&1)" \
    || { printf '%s\n' "$said" >&2; die3 "task start refused for $task_folder, so nothing was written. Repair the task first"; }
  echo "task-state: $state -> in_progress"
  printf '%s\n' "$said" | grep '^environment:'
  return 0
}

# One call to the shared commit, restricted to the task's own folder, tasks/<task>, plus any
# folder named after the seven fields. A task change never sweeps up a project file edit, or
# another task's uncommitted file, left beside it (live run, row 120: `tasks` whole took another
# window's pending file). Moved here from task-actions.sh so the stage closes commit the same
# way the task actions do. project-commit.sh is sourced here because only task-actions.sh
# sourced it on its own; it takes die3 and PLUGIN_ROOT from the same caller.
commit_task_change() {
  local project="$1" subject="$2" why="$3" principle="$4" ruled_out="$5" task="$6" stage="$7"
  shift 7
  # shellcheck source=/dev/null
  source "${PLUGIN_ROOT}/scripts/lib/project-commit.sh" || die3 "the project-commit library failed to load"
  commit_project "$project" "$subject" "$why" "$principle" "$ruled_out" "$task" "$stage" "tasks/$task" "$@"
}

# The stage-boundary commit (foundations.md, History: "AIDA commits at stage boundaries, and the
# commit message is the record"). Mid-stage edits stay uncommitted; the close commits the task
# folder once, with the stage's own result as the reason. $1 the canonical task folder, $2 the
# stage, $3 the subject, $4 the why, read from the record the close just wrote and never invented.
# The project folder is two levels up, where mark_task_in_progress sends the task script. A
# folder that is not a repository, or a commit that fails, leaves the record written and says so
# once on stderr, the way playbook-actions.sh reports its capture; the close still exits 0. The
# subshell turns a refusal inside the commit into that same line rather than ending the close.
# The id names the folder the commit stages, so an unreadable id commits nothing rather than
# staging tasks/ whole.
commit_stage_close() {
  local task_folder="$1" stage="$2" subject="$3" why="$4" project id
  project="$(dirname -- "$(dirname -- "$task_folder")")"
  id="$(jq -r '.id // empty' "$task_folder/task.json" 2>/dev/null)"
  [ -n "$id" ] || { printf 'the %s record was written but not committed: %s/task.json has no readable id. Commit %s by hand.\n' "$stage" "$task_folder" "$task_folder" >&2; return 0; }
  ( commit_task_change "$project" "$subject" "$why" "" "" "$id" "$stage" ) \
    || printf 'the %s record was written but not committed. Commit %s/tasks/%s by hand.\n' "$stage" "$project" "$id" >&2
}

# A malformed sidecar is moved aside to <name>.malformed-<date>.json beside it before the exit 4
# that names the fault (live-run row 80). Never deleted: a reader can still see what the agent
# wrote. The next dispatch writes a fresh file at the original path instead of finding the
# broken one. Prints `setAside:` with the new path. $1 the sidecar path.
sidecar_set_aside() {
  local sidecar="$1" aside
  aside="${sidecar%.json}.malformed-$(date -u +%Y-%m-%dT%H%M%SZ).json"
  mv -- "$sidecar" "$aside"
  echo "setAside: $aside"
}

# The one reading of decidedWithoutAPerson, DECIDED_JQ (gap row 232).
# shellcheck source=/dev/null
source "${PLUGIN_ROOT}/scripts/lib/decided.sh"

# The records the distiller reads for one stage, the set distill-schema.json's `stage` names, as
# paths in the task folder, sorted. Run it from inside the task folder. $1 the stage.
distill_records() {
  case "$1" in
    scope)    printf 'alignment.json\n' ;;
    research) find research -maxdepth 1 -type f -name '*.json' 2>/dev/null; printf 'records/research-check.json\n' ;;
    design)   find design -maxdepth 1 -type f -name '*.json' 2>/dev/null; printf 'design-closed.json\n' ;;
  esac | sort
}

# The sha256 of stdin. records-hash.sh is sourced here for the sha256 tool, the way distill_read
# sources schema-check.sh.
distill_sha256() {
  # shellcheck source=/dev/null
  source "${PLUGIN_ROOT}/scripts/lib/records-hash.sh" || die3 "distill: the records-hash library failed to load"
  records_hash__resolve_sha256_cmd || die3 "distill: neither sha256sum nor 'shasum -a 256' was found on PATH"
  "${RECORDS_HASH_SHA256_CMD[@]}" | cut -d' ' -f1
}

# The sha256 over the records distill_records names: each present file's path, then its bytes.
# $1 the task folder, $2 the stage.
distill_records_hash() {
  (cd "$1" && distill_records "$2" | while IFS= read -r rel; do
    [ -f "$rel" ] || continue
    printf '%s\n' "$rel"
    cat -- "$rel"
  done) | distill_sha256
}

# Whether records/<stage>-distill.json was written before the last change to the records it read
# (gap row 233). Prints yes or no, and no when there is no sidecar. The first read that finds a
# sidecar current writes records/<stage>-distill.stamp beside it: the sidecar's own sha256 and the
# records hash, one JSON object. The distiller never reads or writes the stamp. While the sidecar
# still matches its stamp, the records hash decides. A sidecar with no stamp, or one the distiller
# rewrote since, even with the same bytes, compares file times, because the distiller writes after
# it reads. A stage action
# that writes its records before distill_read calls this first and passes the answer on. $1 the
# task folder, $2 the stage.
distill_stale() {
  local task_folder="$1" stage="$2" sidecar stamp stamped hash newer
  sidecar="$task_folder/records/$stage-distill.json"
  stamp="$task_folder/records/$stage-distill.stamp"
  [ -f "$sidecar" ] || { echo no; return 0; }
  if [ -f "$stamp" ]; then
    stamped="$(jq -r '.sidecar // empty' "$stamp" 2>/dev/null)"
    hash="$(distill_sha256 <"$sidecar")" || exit $?
    if [ -n "$stamped" ] && [ "$stamped" = "$hash" ] && ! [ "$sidecar" -nt "$stamp" ]; then
      hash="$(distill_records_hash "$task_folder" "$stage")" || exit $?
      if [ "$(jq -r '.records // empty' "$stamp" 2>/dev/null)" = "$hash" ]; then echo no; else echo yes; fi
      return 0
    fi
  fi
  newer="$(cd "$task_folder" && distill_records "$stage" | while IFS= read -r rel; do
    [ -f "$rel" ] && [ "$rel" -nt "records/$stage-distill.json" ] && echo "$rel"
  done)"
  if [ -n "$newer" ]; then echo yes; else echo no; fi
}

# Writes records/<stage>-distill.stamp: the sidecar's sha256 and the records hash. distill_read
# calls it on a current sidecar. Review's close calls it for scope, when scope read current before
# the close wrote its verdicts into the contract. $1 the task folder, $2 the stage.
distill_stamp() {
  local task_folder="$1" stage="$2" sidecar_hash records_hash
  sidecar_hash="$(distill_sha256 <"$task_folder/records/$stage-distill.json")" || exit $?
  records_hash="$(distill_records_hash "$task_folder" "$stage")" || exit $?
  write_atomic "$task_folder/records/$stage-distill.stamp" \
    "$(jq -n --arg s "$sidecar_hash" --arg r "$records_hash" '{sidecar: $s, records: $r}')"
}

# Reads the sidecar the distiller wrote for one stage, records/<stage>-distill.json
# (agents/distiller.md), and prints `standsAlone:` and one `gap:` line per gap. The check never
# blocks, so every value exits 0. schema-check.sh is sourced here because no stage script sources
# it on its own. A stale sidecar prints `standsAlone: stale` and a `stale:` line naming the
# dispatch that refreshes it, and none of its gaps. A current one gets its stamp, as distill_stale
# says. $1 the canonical task folder, $2 the stage, $3 optional, the answer distill_stale gave
# before the caller wrote its records.
distill_read() {
  local task_folder="$1" stage="$2" stale="${3:-}" sidecar schema result faults
  sidecar="$task_folder/records/$stage-distill.json"
  schema="${PLUGIN_ROOT}/scripts/distill-schema.json"
  [ -f "$sidecar" ] || die2 "distill: no sidecar at $sidecar. Dispatch the distiller first"
  # shellcheck source=/dev/null
  source "${PLUGIN_ROOT}/scripts/lib/schema-check.sh" || die3 "distill: the schema-check library failed to load"
  result="$(schema_check_compare "$schema" "$sidecar")" \
    || { sidecar_set_aside "$sidecar"; die4 "distill: $sidecar could not be read as JSON"; }
  faults="$(printf '%s' "$result" | jq -r '(.missing + .unreadable) | map(.field) | join(" ")')"
  [ -z "$faults" ] || { sidecar_set_aside "$sidecar"; die4 "distill: $sidecar does not match $schema: $faults"; }
  if [ "$(jq -r '(.standsAlone == false) != ((.gaps | length) > 0)' "$sidecar")" = "true" ]; then
    sidecar_set_aside "$sidecar"
    die4 "distill: $sidecar has standsAlone and gaps that disagree. False needs a gap, and a gap needs false"
  fi
  [ -n "$stale" ] || stale="$(distill_stale "$task_folder" "$stage")" || exit $?
  if [ "$stale" = "yes" ]; then
    echo "standsAlone: stale"
    echo "stale: $sidecar was written before the last change to the $stage records, so its gaps are not current. Dispatch the distiller for stage $stage again. It writes the sidecar also when its judgement is unchanged, because only a new write clears this. Then run this call again"
    return 0
  fi
  distill_stamp "$task_folder" "$stage"
  echo "standsAlone: $(jq -r '.standsAlone' "$sidecar")"
  jq -r '.gaps[] | "gap: " + .' "$sidecar"
}

# A light task dispatches no distiller at the scope close or the research close. The design close
# dispatches one over all three stages, so the run pays for one dispatch, and a contract edit
# before design closes costs no repeat (gap row 292). Scope's and research's distill print this
# line in place of distill_read. $1 the stage.
distill_deferred() {
  echo "distill: deferred to the design close, light run. Dispatch no distiller for $1"
}

# The playbook record research loads, `<task_folder>/records/playbooks.json`. One spelling for
# every reader: the four implementation briefs, the architecture review brief and check 16's floor.
# The JSON form is null rather than a path when the file is absent, so a role never opens a file
# to learn that nothing was loaded. $1 the task folder. Calls no die function.
playbooks_record_path() {
  printf '%s/records/playbooks.json' "$1"
}
# The person's own playbook file, one per machine. The load reads it, and check 16's floor asks
# whether it is there. Calls no die function.
playbooks_person_path() {
  printf '%s/.claude/aida/playbook.md' "$HOME"
}
playbooks_path_json() {
  local record
  record="$(playbooks_record_path "$1")"
  if [ -f "$record" ]; then jq -n --arg p "$record" '$p'; else printf 'null'; fi
}

# The stage a task stands at, one of scope, research, design, implementation, review, completion.
# Derived from the records in the task folder every time, never stored: each stage writes one
# record when it closes, and the stage is the first whose record is absent. Scope's is the
# distill sidecar, records/scope-distill.json, which approve and distill both need before they
# close (scope-actions.sh, exit 2); alignment.json is written by init, at the stage's start. A
# light task has no scope sidecar until design closes, so its scope closes on the pluginVersion
# that only the scope close writes into alignment.json.
# This is the one copy of that rule; the session-start hook and the next skill's report both
# print what it says. $1 the task folder, $2 the review word next-actions.sh derives from
# review/review.json (passed, failed, unfinished or none). Calls no die function.
task_stage() {
  local task_folder="$1" review="$2"
  if [ ! -f "$task_folder/records/scope-distill.json" ] && { ! task_is_light "$task_folder" \
      || [ -z "$(jq -r '.pluginVersion // empty' "$task_folder/alignment.json" 2>/dev/null)" ]; }; then
    echo "scope"
  elif [ "$(jq -r '.exitCode // 1' "$task_folder/records/research-check.json" 2>/dev/null)" != "0" ]; then
    echo "research"
  elif [ ! -f "$task_folder/design-closed.json" ]; then
    echo "design"
  elif [ ! -f "$task_folder/implementation/finished.json" ]; then
    echo "implementation"
  elif [ "$review" != "passed" ] && [ "$review" != "failed" ] || task_review_outdated "$task_folder" >/dev/null; then
    echo "review"
  else
    echo "completion"
  fi
}

# A review judged the commit range finished.json held when it ran. A later finish, after a fix or
# an order design added, ends the build at another commit, and that verdict covers none of the
# new commits (gap row 335). So a review whose reviewedRange differs from the finished commitRange,
# or has no finished record beside it, counts as no review. task_stage and completion ask here.
# $1 the task folder. Prints both ranges and returns 0 when outdated; prints nothing and returns 1
# otherwise, and when there is no review record. Calls no die function.
task_review_outdated() {
  local reviewed built
  reviewed="$(jq -r '.reviewedRange // empty' "$1/review/review.json" 2>/dev/null)"
  [ -n "$reviewed" ] || return 1
  built="$(jq -r '.commitRange // empty' "$1/implementation/finished.json" 2>/dev/null)"
  [ "$reviewed" != "$built" ] || return 1
  printf 'the review covers %s, and the finished build is %s' "$reviewed" "${built:-not recorded}"
}

# A chain made with --in-tree shares one tree, and the branch checked out there says which task
# builds in it now (gap row 302). Refuses through die3 when the tree $2 holds a branch other than
# the one the task folder $1 records. A detached HEAD names no task, so it is not refused. $3 the
# action's own name.
task_tree_turn() {
  local held branch
  held="$(git -C "$2" symbolic-ref -q --short HEAD 2>/dev/null)"
  branch="$(jq -r '.worktree.branch // empty' "$1/task.json" 2>/dev/null)"
  [ -z "$held" ] || [ -z "$branch" ] || [ "$held" = "$branch" ] \
    || die3 "$3: the worktree $2 holds the branch $held, and this task builds on $branch. Another task of its chain builds in this tree now. Nothing was written. Commit the work there, then run: git -C $2 switch $branch"
}

# The ids of the other tasks of the project $1 whose record names the tree $2, one per line. $3 is
# the caller's own id, left out. A tree is named twice when two old ids slug to one folder, or when
# a later task took it over with --in-tree (gap row 302). Calls no die function.
task_tree_others() {
  find "$1/tasks" -name task.json -exec jq -r --arg p "$2" --arg id "$3" \
    'select(.worktree.path == $p and .id != $id) | .id' {} + 2>/dev/null
}

# True when the task this task builds on has a closed review, a verdict of passed or failed, or
# reads complete. Its review and completion run in its tree, so --in-tree takes that tree over only
# then (gap row 302). $1 the task folder.
task_after_reviewed() {
  local pred
  pred="$(dirname -- "$1")/$(jq -r '.after // empty' "$1/task.json" 2>/dev/null)"
  case "$(jq -r '.verdict // empty' "$pred/review/review.json" 2>/dev/null)" in passed|failed) return 0 ;; esac
  [ "$(jq -r '.state // empty' "$pred/task.json" 2>/dev/null)" = "complete" ]
}

# The task this task builds on, from task.json's `after`, and whether that task's build is
# finished (gap row 291). Prints nothing when the field is absent. Otherwise prints `<id> finished`
# when the other task holds a readable implementation/finished.json or reads complete, a person
# having closed it, `<id> missing` when the project holds no such task, and `<id> unfinished`
# else. start, task_worktree and the next report all ask here. $1 the task folder. Calls no die
# function.
task_after_state() {
  local after pred
  after="$(jq -r '.after // empty' "$1/task.json" 2>/dev/null)"
  [ -n "$after" ] || return 0
  pred="$(dirname -- "$1")/$after"
  if [ ! -f "$pred/task.json" ]; then
    printf '%s missing' "$after"
  elif jq empty "$pred/implementation/finished.json" >/dev/null 2>&1 \
      || [ "$(jq -r '.state // empty' "$pred/task.json" 2>/dev/null)" = "complete" ]; then
    printf '%s finished' "$after"
  else
    printf '%s unfinished' "$after"
  fi
}

# The folder that holds every task tree of one repository: <parent of code>/<slug of the code
# folder>.worktrees. It sits beside the code path, so the trees do not lie loose among the other
# folders there (gap row 260). task_worktree makes a tree in it, and prune removes it when empty.
# $1 the code path, $2 the action's own name. Dies through die3.
task_worktree_group() {
  local code
  code="$(cd "$1" && pwd -P)" || die3 "$2: the code path is not on disk: $1"
  # shellcheck source=/dev/null
  command -v pb_slug >/dev/null 2>&1 || source "${PLUGIN_ROOT}/scripts/lib/playbooks.sh" \
    || die3 "$2: the library failed to load: playbooks.sh"
  printf '%s/%s.worktrees' "$(dirname -- "$code")" "$(pb_slug "$(basename -- "$code")")"
}

# The task's own git worktree (ideal/task.md, "A worktree per task, always"), in the group folder
# above, named <slug of the code folder>-<id>: a tree nested under the code path is invisible to a
# tool that registers projects by folder, and DDEV hands it to the parent project. The folder name
# becomes a hostname label, so the basename and the id go through pb_slug, the one slug rule. The
# name keeps the code folder because DDEV names a site after its folder, and a site name must be
# unique on the machine. A dot or an underscore in either becomes a hyphen, as the id rule demands:
# an id made before that rule may still hold one (gap row 251). The branch keeps the id. Prints the
# path task.json records. When the field is absent it makes the tree and writes the field first;
# that is the one producer, and running it again is the repair for a task made before the field
# existed. A recorded tree gone from disk is made again from its branch, after a prune, because git
# refuses a path it still registers; a branch gone too starts from HEAD again. A recorded path gone
# from disk is not trusted as an address: it is computed again by the rule above, and the tree is
# made and recorded there. That is the repair for a task carried to a second machine, and for a
# folder named before the id was slugged. A recorded tree on disk is kept. The base is HEAD of the
# directory this action was started from when that directory is inside the code repository, so a
# follow-up made from its parent's tree stacks on the parent's work; otherwise it is the code path's
# HEAD. A task whose record names `after` is cut from that task's branch instead, or with `inTree`
# takes over that task's tree. Uncommitted changes in the code path are not in a tree cut from a commit, so their count is
# said once, on stderr, and nothing asks.
# $1 the canonical task folder, $2 the action's own name. Dies through die3.
task_worktree() {
  local task_folder="$1" who="$2" task_json="$1/task.json" wt branch project code base_dir base said dirty id
  local found rule group base_branch after after_branch after_base pred
  wt="$(jq -r '.worktree.path // empty' "$task_json" 2>/dev/null)"
  if [ -n "$wt" ] && [ -d "$wt" ]; then printf '%s' "$wt"; return 0; fi
  project="$(resolve_project_folder "$task_folder")" \
    || die3 "$who: could not resolve a project folder two levels up from $task_folder, or it has no project.json"
  code="$(project_code_path_value "$project")"
  [ -n "$code" ] && [ -d "$code" ] || die3 "$who: the project's codePath is not on disk: ${code:-none recorded}"
  is_git_repo "$code" || die3 "$who: the project's codePath is not a git repository: $code"
  code="$(cd "$code" && pwd -P)"
  branch="$(jq -r '.worktree.branch // empty' "$task_json" 2>/dev/null)"
  id="$(jq -r '.id' "$task_json")"
  # shellcheck source=/dev/null
  command -v pb_slug >/dev/null 2>&1 || source "${PLUGIN_ROOT}/scripts/lib/playbooks.sh" \
    || die3 "$who: the library failed to load: playbooks.sh"
  # The path rule, run here rather than read from the record, because the record is an address on
  # the machine that wrote it. One copy serves both branches below.
  group="$(task_worktree_group "$code" "$who")" || exit 3
  rule="$group/$(pb_slug "$(basename -- "$code")")-$(pb_slug "$id")"
  # A task made with `after` is cut from that task's branch, and only once its build is finished:
  # cut earlier, the branch holds none of that build (gap row 291). A complete task whose branch is
  # gone was merged and pruned, so its work is on trunk and the rule below serves. Checked before
  # anything is printed or made.
  after_branch=""
  after="$(task_after_state "$task_folder")"
  if [ -n "$after" ] && ! git -C "$code" rev-parse -q --verify "refs/heads/${branch:-feature/$id}" >/dev/null 2>&1; then
    [ "${after##* }" = "finished" ] \
      || die3 "$who: task $id builds on task ${after% *}, whose build is ${after##* }. Its tree is cut from that task's branch once that build is finished."
    pred="$(dirname -- "$task_folder")/${after% *}/task.json"
    after_branch="$(jq -r '.worktree.branch // empty' "$pred" 2>/dev/null)"
    if [ -z "$after_branch" ] \
        || ! after_base="$(git -C "$code" rev-parse -q --verify "refs/heads/$after_branch^{commit}" 2>/dev/null)"; then
      [ "$(jq -r '.state // empty' "$pred" 2>/dev/null)" = "complete" ] \
        || die3 "$who: task $id builds on task ${after% *}. That task records no branch, or its branch is not in $code. Nothing was made."
      after_branch=""
    fi
  fi
  # A task made with --in-tree takes over that task's tree, on a new branch from its tip, so a chain
  # pays one checkout and one dependency sync (gap row 302). The tree goes only once that task's
  # review has closed, and only when it is clean and still holds that task's branch. So no work and
  # no other task's turn is carried over. The earlier task keeps its record, and the tree check
  # refuses it while this branch is checked out.
  if [ -n "$after_branch" ] && [ "$(jq -r '.inTree // false' "$task_json" 2>/dev/null)" = true ]; then
    found=""
    if task_after_reviewed "$task_folder"; then
      found="$(task_tree_from_git "$(dirname -- "$pred")" "$code" "$who")"
    else
      printf '%s: the tree of task %s is not shared, because its review has not closed and runs in that tree. A new tree is cut from %s\n' "$who" "${after% *}" "$after_branch" >&2
    fi
    if [ -n "$found" ]; then
      [ -z "$(git -C "$found" status --porcelain 2>/dev/null)" ] \
        || die3 "$who: task $id takes over the worktree $found of task ${after% *}, and that tree has uncommitted changes. Nothing was made. Commit them on $after_branch, then run this again."
      said="$(git -C "$found" switch -q -c "feature/$id" 2>&1)" \
        || die3 "$who: git could not make the branch feature/$id in $found: $said"
      write_atomic "$task_json" "$(jq --arg p "$found" --arg b "feature/$id" --arg base "$after_branch" \
        '.worktree = ((.worktree // {}) + {path: $p, branch: $b, base: $base})' "$task_json")"
      printf 'worktree: %s, taken over from task %s\n' "$found" "${after% *}" >&2
      printf '%s' "$found"
      return 0
    fi
    ! task_after_reviewed "$task_folder" \
      || printf '%s: no tree on disk holds the branch of task %s, so a new tree is cut from %s\n' "$who" "${after% *}" "$after_branch" >&2
  fi
  if [ -n "$wt" ]; then
    # The tree may have moved rather than gone. git answers that, through the one reader.
    found="$(task_tree_from_git "$task_folder" "$code" "$who")"
    if [ -n "$found" ]; then printf '%s' "$found"; return 0; fi
    # A recorded path gone from disk is not kept. It may be another machine's home, or a folder
    # named from an id before the slug (gap row 251). The producer runs again: the path is
    # computed, made, and recorded.
    if [ "$wt" != "$rule" ]; then
      printf '%s: task.json records the worktree %s, which is not on disk here. The tree is made at %s instead.\n' \
        "$who" "$wt" "$rule" >&2
      wt="$rule"
    fi
    printf '%s: the worktree %s is gone from disk and is made again from %s\n' "$who" "$wt" "$branch" >&2
  else
    wt="$rule"
    branch="feature/$id"
    printf 'worktree: %s\n' "$wt" >&2
  fi
  base_dir="$code"
  said="$(git rev-parse --git-common-dir 2>/dev/null)"
  if [ -n "$said" ] && [ "$(cd "$said" && pwd -P)" = "$(cd "$code" && cd "$(git rev-parse --git-common-dir)" && pwd -P)" ]; then
    base_dir="$(pwd -P)"
  fi
  base="$(git -C "$base_dir" rev-parse HEAD 2>/dev/null)" || die3 "$who: $base_dir has no commit to cut a worktree from"
  dirty="$(git -C "$code" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  [ "$dirty" -eq 0 ] || printf '%s: %s uncommitted change(s) in %s are not in the worktree\n' "$who" "$dirty" "$code" >&2
  # Two old ids such as a_b and a-b slug to one folder. The tree there is the other task's.
  if [ -e "$wt" ]; then
    found="$(task_tree_others "$project" "$wt" "$id" | head -1)"
    [ -z "$found" ] \
      || die3 "$who: task $id names its worktree $wt, and task $found already holds that folder. The two ids slug to one folder name. Nothing was made. A person moves one of the trees and records its path in that task's task.json."
  fi
  git -C "$code" worktree prune 2>/dev/null
  mkdir -p "$group" || die3 "$who: could not make the folder $group. Make it by hand, or let this user write to $(dirname -- "$group"), and run the action again"
  # What the tree is cut from, written whenever this call cuts the branch, over any base the record
  # held. A detached HEAD is `commit:<sha>`: git forbids `:` in a branch name, so the two never
  # meet. A tree made again from a branch that exists keeps the base the record held.
  base_branch=""
  if git -C "$code" rev-parse -q --verify "refs/heads/$branch" >/dev/null 2>&1; then
    said="$(git -C "$code" worktree add "$wt" "$branch" 2>&1)" \
      || { rmdir "$group" 2>/dev/null; die3 "$who: git worktree add failed: $said"; }
  else
    if [ -n "$after_branch" ]; then
      base="$after_base"; base_branch="$after_branch"
    else
      base_branch="$(git -C "$base_dir" symbolic-ref -q --short HEAD 2>/dev/null)" || base_branch="commit:$base"
    fi
    said="$(git -C "$code" worktree add -b "$branch" "$wt" "$base" 2>&1)" \
      || { rmdir "$group" 2>/dev/null; die3 "$who: git worktree add failed: $said"; }
  fi
  wt="$(cd "$wt" && pwd -P)"
  write_atomic "$task_json" "$(jq --arg p "$wt" --arg b "$branch" --arg base "$base_branch" \
    '.worktree = ((.worktree // {}) + {path: $p, branch: $b} + (if $base == "" then {} else {base: $base} end))' "$task_json")"
  printf '%s' "$wt"
}

# Which tree a script with no task folder to read should write into (ideal/surfaces.md, "Setup
# runs in the tree the task runs in"). $1 the project's code path. $2 a directory, usually
# $(pwd -P). Prints $2's own git top level when that is a worktree of $1's repository, wherever
# it sits: its git common dir resolves to $1's. So setup started from inside a task's worktree
# lands there. Prints $1 otherwise, including when $2 is not in a git work tree at all. Calls no
# die function.
active_tree_for() {
  local code="$1" dir="$2" top common
  code="$(cd "$code" && pwd -P)"
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || { printf '%s' "$code"; return 0; }
  top="$(cd "$top" && pwd -P)"
  common="$(cd "$top" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
  if [ "$common" = "$(cd "$code" && cd "$(git rev-parse --git-common-dir)" && pwd -P)" ]; then
    printf '%s' "$top"
  else
    printf '%s' "$code"
  fi
}

warn_newer_installed
warn_session_version
