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
#   write_atomic <target> <content>       writes through a temporary file beside the target
#   plugin_version                        prints the version from the plugin's own plugin.json,
#                                         or unknown when that file cannot be read
#   task_run_mode <folder> <stage>        prints autonomous when the task's mode is autonomous and
#                                         covers the stage, or is light, else interactive
#   task_is_light <folder>                true when the task's mode is light
#   log_compromise <folder> <stage> <skipped> <normal>
#                                         adds one row to COMPROMISES.md in the task's tree and
#                                         commits that file alone
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
#   sidecar_set_aside <path>              moves a malformed sidecar aside, dated, and says where
#   task_tree_from_git <folder> <code> <action>
#                                         prints the registered worktree carrying the task's
#                                         branch, and repairs worktree.path when git disagrees
#   task_worktree <folder> <action>       prints the task's worktree path, making the tree first
#                                         when task.json does not record one
#   task_stage <folder> <review-word>     prints the stage the task stands at, from its records
#   active_tree_for <codePath> <dir>      prints <dir>'s git top level when it is a worktree of
#                                         the <codePath> repository, else <codePath>
#   playbooks_record_path <folder>        prints the path of the playbook record research loads
#   playbooks_path_json <folder>          prints that path as a JSON string, or null when absent
#
# task_worktree and resolve_task_folder both take resolve_project_folder, project_code_path_value
# and is_git_repo from scripts/lib/recipes.sh. Two callers, scope and design, do not source that
# file, so resolve_task_folder sources it when the function is absent, the way task_worktree
# sources playbooks.sh for pb_slug. Every caller resolves inside a command substitution, so that
# source lands in a subshell and clobbers nothing. The refusal takes die79 from the caller.

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
  [ "$top" != "$wt" ] || { printf '%s' "$p"; return 0; }
  # A recorded tree gone from disk, that git places nowhere else, is not refused: the action that
  # makes it again names it.
  [ -d "$wt" ] || { printf '%s' "$p"; return 0; }
  [ "$(active_tree_for "$code" "$wt")" = "$wt" ] \
    || die79 "$who: task.json records the worktree $wt, and git does not list it as a worktree of $code. Nothing written there reaches the branch. Remove that folder, and the next action that needs the code makes the tree again."
  # The route named is the one that works where this call ran. EnterWorktree takes a worktree of
  # this window's own repository on first entry, and from a worktree session only a target under
  # .claude/worktrees/ (the mirror's tools reference). A task tree is a sibling of the checkout,
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
# string. The record then still says a version was asked for and not found. This is the one jq
# call on plugin.json in the plugin.
plugin_version() {
  local version
  version="$(jq -r '.version // empty' "${PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null)"
  [ -n "$version" ] || version="unknown"
  printf '%s' "$version"
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

# One row of the compromises log, COMPROMISES.md at the top of the task's tree (gap row 197). The
# code that decides a skip calls this, so the log never rests on a model's memory. The file ships
# with the code, because a later normal task takes it as its scope. A row already in the file is
# not written again, so a step run twice logs once. The file alone is committed, because a stage
# refuses a tree that is not clean. A commit that fails is said on stderr and does not stop the
# stage. $1 the task folder, $2 the stage, $3 what was skipped, $4 what a normal run would do.
log_compromise() {
  local tree file row
  tree="$(jq -r '.worktree.path // empty' "$1/task.json" 2>/dev/null)"
  [ -n "$tree" ] && [ -d "$tree" ] || tree="$(
    command -v resolve_project_folder >/dev/null 2>&1 || . "${PLUGIN_ROOT}/scripts/lib/recipes.sh"
    task_worktree "$1" "log-compromise")" || return 0
  file="$tree/COMPROMISES.md"
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
  { git -C "$tree" add -- COMPROMISES.md && git -C "$tree" commit -q -m "Log a light-run compromise: $2" -- COMPROMISES.md; } >/dev/null 2>&1 \
    || printf 'task-helpers: %s was written and not committed. Commit it before the next step.\n' "$file" >&2
  printf 'compromise: %s: %s\n' "$2" "$3"
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

# Reads the sidecar the distiller wrote for one stage, records/<stage>-distill.json
# (agents/distiller.md), and prints `standsAlone:` and one `gap:` line per gap. The check never
# blocks, so both values exit 0. schema-check.sh is sourced here because no stage script sources
# it on its own. $1 the canonical task folder, $2 the stage.
distill_read() {
  local task_folder="$1" stage="$2" sidecar schema result faults
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
  echo "standsAlone: $(jq -r '.standsAlone' "$sidecar")"
  jq -r '.gaps[] | "gap: " + .' "$sidecar"
}

# The playbook record research loads, `<task_folder>/records/playbooks.json`. One spelling for
# every reader: the four implementation briefs, the architecture review brief and check 16's floor.
# The JSON form is null rather than a path when the file is absent, so a role never opens a file
# to learn that nothing was loaded. $1 the task folder. Calls no die function.
playbooks_record_path() {
  printf '%s/records/playbooks.json' "$1"
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
# close (scope-actions.sh, exit 2); alignment.json is written by init, at the stage's start.
# This is the one copy of that rule; the session-start hook and the next skill's report both
# print what it says. $1 the task folder, $2 the review word next-actions.sh derives from
# review/review.json (passed, failed, unfinished or none). Calls no die function.
task_stage() {
  local task_folder="$1" review="$2"
  if [ ! -f "$task_folder/records/scope-distill.json" ]; then
    echo "scope"
  elif [ "$(jq -r '.exitCode // 1' "$task_folder/records/research-check.json" 2>/dev/null)" != "0" ]; then
    echo "research"
  elif [ ! -f "$task_folder/design-closed.json" ]; then
    echo "design"
  elif [ ! -f "$task_folder/implementation/finished.json" ]; then
    echo "implementation"
  elif [ "$review" != "passed" ] && [ "$review" != "failed" ]; then
    echo "review"
  else
    echo "completion"
  fi
}

# The task's own git worktree (ideal/task.md, "A worktree per task, always"), a sibling of the
# code path named <slug of the code folder>-<id>: a tree nested under the code path is invisible
# to a tool that registers projects by folder, and DDEV hands it to the parent project. The
# folder name becomes a hostname label, so the basename goes through pb_slug, the one slug
# rule. A dot or an underscore in it becomes a hyphen, as the id rule demands. Prints the
# path task.json records. When the field is absent it makes the tree and writes the field first; that
# is the one producer, and running it again is the repair for a task made before the field
# existed. A recorded tree gone from disk is made again from its branch, after a prune, because
# git refuses a path it still registers; a branch gone too starts from HEAD again. The recorded
# path is not trusted as an address: a path that is not beside this machine's code path is
# computed again by the rule above, and the tree is made and recorded there. That is the repair
# for a task carried to a second machine, which records the first machine's path. The base is
# HEAD of the directory this action was started from when that directory is inside the code
# repository, so a follow-up made from its parent's tree stacks on the parent's work; otherwise
# it is the code path's HEAD. Uncommitted changes in the code path are not in a tree cut from a
# commit, so their count is said once, on stderr, and nothing asks.
# $1 the canonical task folder, $2 the action's own name. Dies through die3.
task_worktree() {
  local task_folder="$1" who="$2" task_json="$1/task.json" wt branch project code base_dir base said dirty id
  local found rule parent base_branch
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
  rule="$(dirname -- "$code")/$(pb_slug "$(basename -- "$code")")-$id"
  if [ -n "$wt" ]; then
    # The tree may have moved rather than gone. git answers that, through the one reader.
    found="$(task_tree_from_git "$task_folder" "$code" "$who")"
    if [ -n "$found" ]; then printf '%s' "$found"; return 0; fi
    # A recorded path is usable here when its folder is the code path's own folder, which is what
    # the rule computes. Another machine's home fails that test, and so does a folder this machine
    # does not have. Then the producer runs again: the path is computed, made, and recorded.
    parent="$(cd "$(dirname -- "$wt")" 2>/dev/null && pwd -P)" || parent=""
    if [ "$parent" != "$(dirname -- "$rule")" ]; then
      printf '%s: task.json records the worktree %s, which is not beside the code path %s here. The tree is made at %s instead.\n' \
        "$who" "$wt" "$code" "$rule" >&2
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
  git -C "$code" worktree prune 2>/dev/null
  # What the tree is cut from, written whenever this call cuts the branch, over any base the record
  # held. A detached HEAD is `commit:<sha>`: git forbids `:` in a branch name, so the two never
  # meet. A tree made again from a branch that exists keeps the base the record held.
  base_branch=""
  if git -C "$code" rev-parse -q --verify "refs/heads/$branch" >/dev/null 2>&1; then
    said="$(git -C "$code" worktree add "$wt" "$branch" 2>&1)" || die3 "$who: git worktree add failed: $said"
  else
    base_branch="$(git -C "$base_dir" symbolic-ref -q --short HEAD 2>/dev/null)" || base_branch="commit:$base"
    said="$(git -C "$code" worktree add -b "$branch" "$wt" "$base" 2>&1)" || die3 "$who: git worktree add failed: $said"
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
