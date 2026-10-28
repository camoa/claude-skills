#!/usr/bin/env bash
# project-task-spec.sh: the task, project, surfaces, tool, next and playbooks actions after the
# control audit. A tree is made when a task starts, so a split or a follow-up writes no tree, and
# prune removes a tree nobody started. A repeat write, a site, a viewport and a missing tool are
# not stops. A usage fault exits 3. Each case sources the helper in a subshell, so it starts from
# fresh records.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"
TASK_ACTIONS="$PLUGIN/skills/task/scripts/task-actions.sh"
PROJECT_ACTIONS="$PLUGIN/skills/project/scripts/project-actions.sh"
COMPLETION="$PLUGIN/skills/completion/scripts/completion-actions.sh"
SURFACES="$PLUGIN/skills/surfaces/scripts/surfaces-actions.sh"
TOOL="$PLUGIN/skills/tool/scripts/tool-actions.sh"
NEXT="$PLUGIN/skills/next/scripts/next-actions.sh"
PLAYBOOK="$PLUGIN/skills/playbooks/scripts/playbook-actions.sh"

tree_of() { jq -r '.worktree.path // "none"' "$PROJECT/tasks/$1/task.json" 2>/dev/null || echo gone; }
on_disk() { [ -e "$1" ] && echo yes || echo no; }

# split_case: t1 splits into a, b and c, while the folder c's tree would take is held by task x.
# The exit, whether a was written, and the trees a and c record.
split_case() (
  source "$HERE/records.bash"
  task_records branch
  mkdir -p "$ROOT/code.worktrees/code-c" "$PROJECT/tasks/x"
  jq -n --arg p "$ROOT/code.worktrees/code-c" \
    '{schemaVersion: 1, id: "x", state: "new", parent: null, children: [], worktree: {path: $p, branch: "feature/x"}}' \
    >"$PROJECT/tasks/x/task.json"
  run "$TASK_ACTIONS" split --project "$PROJECT" t1 --child a --goal "do a" --child b --goal "do b" --child c --goal "do c"
  printf '%s|%s|%s|%s\n' "$RC" "$(on_disk "$PROJECT/tasks/a/task.json")" "$(tree_of a)" "$(tree_of c)"
)
expect "a split writes every child and no tree, so a child's tree never leaves a split half written" "$(split_case)" '0|yes|none|none'

# follow_up_case: completion creates the task for follow-up finding f1 of t1. Its tree.
follow_up_case() (
  source "$HERE/records.bash"
  task_records branch
  mkdir -p "$TASK/review"
  jq -n '{verdict: "passed", findings: [{id: "f1", disposition: "follow-up", severity: "low", lens: "dry",
      file: "a.php", lines: "1", evidence: "a repeat"}]}' >"$TASK/review/review.json"
  run "$COMPLETION" follow-ups "$TASK" --create f1
  printf '%s|%s\n' "$RC" "$(tree_of t1-f1)"
)
expect "a follow-up task gets no tree when completion creates it" "$(follow_up_case)" '0|none'

# start_case: a task in state new that records no tree starts, from the tree of t1, which is open
# and holds a commit the trunk does not. Whether its tree is on disk, and whether it holds the trunk.
start_case() (
  source "$HERE/records.bash"
  task_records branch
  printf 'b\n' >"$WT/a.php"; git -C "$WT" commit -qam "t1 work"
  mkdir -p "$PROJECT/tasks/n1"
  jq -n '{schemaVersion: 1, id: "n1", state: "new", parent: null, children: []}' >"$PROJECT/tasks/n1/task.json"
  run "$TASK_ACTIONS" start --project "$PROJECT" n1 -- "begin"
  local tree; tree="$(tree_of n1)"
  printf '%s|%s|%s\n' "$RC" "$(on_disk "$tree")" \
    "$([ "$(git -C "$tree" rev-parse HEAD 2>/dev/null)" = "$(git -C "$CODE" rev-parse HEAD)" ] && echo trunk || echo other)"
)
expect "start makes the tree of a task that records none, from the trunk" "$(start_case)" '0|yes|trunk'

# create_trunk_case: create runs in the tree of t1, which is open and holds a commit the trunk does
# not. Whether the new tree holds the trunk.
create_trunk_case() (
  source "$HERE/records.bash"
  task_records branch
  printf 'b\n' >"$WT/a.php"; git -C "$WT" commit -qam "t1 work"
  run "$TASK_ACTIONS" create --project "$PROJECT" --name n1 -- "more work"
  [ "$(git -C "$(tree_of n1)" rev-parse HEAD 2>/dev/null)" = "$(git -C "$CODE" rev-parse HEAD)" ] && echo trunk || echo other
)
expect "a tree made inside an open task's tree is cut from the trunk" "$(create_trunk_case)" 'trunk'

# start_findings_case: a task whose record has no parent field starts. The check names the field.
start_findings_case() (
  source "$HERE/records.bash"
  task_records branch
  mkdir -p "$PROJECT/tasks/n1"
  jq -n --arg w "$WT" '{schemaVersion: 1, id: "n1", state: "new", children: [], worktree: {path: $w, branch: "feature/t1"}}' \
    >"$PROJECT/tasks/n1/task.json"
  run "$TASK_ACTIONS" start --project "$PROJECT" n1 -- "begin"
  printf '%s|%s\n' "$RC" "$(jq -r .state "$PROJECT/tasks/n1/task.json")"
)
expect "start exits 0 when the task check reports a finding" "$(start_findings_case)" '0|in_progress'

# prune_case <setup>: task n1 in state new, with a tree cut from t1's branch, which holds a commit
# the trunk does not, as completion cut follow-up trees before. Then <setup> runs in the tree: none,
# dirty or commit. Prints prune's exit, whether the tree is on disk, whether its branch is, and the
# tree n1 records.
prune_case() (
  source "$HERE/records.bash"
  task_records branch
  printf 'b\n' >"$WT/a.php"; git -C "$WT" commit -qam "t1 work"
  local tree="$ROOT/code.worktrees/code-n1"
  git -C "$CODE" worktree add -q -b feature/n1 "$tree" feature/t1
  mkdir -p "$PROJECT/tasks/n1"
  jq -n --arg p "$tree" '{schemaVersion: 1, id: "n1", state: "new", parent: null, children: [],
      worktree: {path: $p, branch: "feature/n1", base: "feature/t1"}}' >"$PROJECT/tasks/n1/task.json"
  case "$1" in
    dirty) printf 'x\n' >"$tree/new.txt" ;;
    commit) printf 'c\n' >"$tree/a.php"; git -C "$tree" commit -qam "n1 work" ;;
  esac
  run "$TASK_ACTIONS" prune --project "$PROJECT" n1
  printf '%s|%s|%s|%s\n' "$RC" "$(on_disk "$tree")" \
    "$(git -C "$CODE" rev-parse -q --verify refs/heads/feature/n1 >/dev/null && echo yes || echo no)" "$(tree_of n1)"
)
expect "prune removes the tree and the branch of a task nobody started" "$(prune_case none)" '0|no|no|none'
expect "prune keeps a never-started tree with an uncommitted file" "$(prune_case dirty | cut -d'|' -f1-2)" '3|yes'
expect "prune keeps a never-started tree whose branch has a commit" "$(prune_case commit | cut -d'|' -f1-2)" '3|yes'

# prune_list_case: the listing names a never-started task's tree.
prune_list_case() (
  source "$HERE/records.bash"
  task_records branch
  run "$TASK_ACTIONS" create --project "$PROJECT" --name n1 -- "a follow-up"
  run "$TASK_ACTIONS" prune --project "$PROJECT"
  grep -c '^id: n1 ' "$OUT"
)
expect "prune lists the tree of a task nobody started" "$(prune_list_case)" '1'

# repeat_case: the same recipe declined twice. The second exit, and how many times the field holds it.
repeat_case() (
  source "$HERE/records.bash"
  task_records branch
  run "$TASK_ACTIONS" decline-recipe --project "$PROJECT" t1 fake
  run "$TASK_ACTIONS" decline-recipe --project "$PROJECT" t1 fake
  printf '%s|%s\n' "$RC" "$(jq '[.recipesDeclined[] | select(. == "fake")] | length' "$TASK/task.json")"
)
expect "a repeated answer exits 0 and writes nothing again" "$(repeat_case)" '0|1'

# prune_none_case: prune named a task that records no tree.
prune_none_case() (
  source "$HERE/records.bash"
  task_records branch
  mkdir -p "$PROJECT/tasks/n1"
  jq -n '{schemaVersion: 1, id: "n1", state: "complete", parent: null, children: []}' >"$PROJECT/tasks/n1/task.json"
  run "$TASK_ACTIONS" prune --project "$PROJECT" n1
  printf '%s\n' "$RC"
)
expect "prune of a task with no tree exits 0" "$(prune_none_case)" '0'

# repaired_case: repair names a version 5 folder that is gone, and tasks/ already holds that task.
repaired_case() (
  source "$HERE/records.bash"
  task_records branch
  run "$TASK_ACTIONS" repair --project "$PROJECT" "$PROJECT/implementation_process/in_progress/t1"
  printf '%s\n' "$RC"
)
expect "repair of a task already repaired exits 0" "$(repaired_case)" '0'

# na_case: not-applicable recorded with --run-mode autonomous. The exit and the recorded reason.
na_case() (
  source "$HERE/records.bash"
  task_records branch
  run "$TASK_ACTIONS" --run-mode autonomous environment --project "$PROJECT" t1 not-applicable -- "no site"
  printf '%s|%s\n' "$RC" "$(jq -r '.environment["not-applicable"] // "none"' "$TASK/task.json")"
)
expect "an unattended run records that a task needs no site" "$(na_case)" '0|no site'

# not_found_case: start names a task the project does not hold.
not_found_case() (
  source "$HERE/records.bash"
  task_records branch
  run "$TASK_ACTIONS" start --project "$PROJECT" nosuch -- "begin"
  printf '%s\n' "$RC"
)
expect "a task id the project does not hold is a usage refusal" "$(not_found_case)" '3'

# --- project ---

# no_repo_case: set-mutation on a project folder that is no git repository. The exit, and the value written.
no_repo_case() (
  source "$HERE/records.bash"
  task_records branch
  mv "$PROJECT/.git" "$ROOT/project-git"
  run "$PROJECT_ACTIONS" set-mutation p on
  printf '%s|%s\n' "$RC" "$(jq -r '.review.mutation // "none"' "$PROJECT/project.json")"
)
expect "a project write that landed exits 0 when the folder is no git repository" "$(no_repo_case)" '0|true'

# open_block_case: task-rule on a CLAUDE.md whose block opens and never closes. The exit, and
# whether the file changed.
open_block_case() (
  source "$HERE/records.bash"
  task_records branch
  printf 'mine\n<!-- task-rule:begin -->\nmore of mine\n' >"$CODE/CLAUDE.md"
  cp "$CODE/CLAUDE.md" "$ROOT/claude.before"
  run "$PROJECT_ACTIONS" task-rule p -- "asked"
  printf '%s|%s\n' "$RC" "$(cmp -s "$CODE/CLAUDE.md" "$ROOT/claude.before" && echo same || echo changed)"
)
expect "a task rule over an unclosed block warns and writes nothing" "$(open_block_case)" '0|same'

# undeclared_case: subscribe-playbook names a framework the project does not declare. The
# subscription written. The check that follows names the framework, and its exit is its own.
undeclared_case() (
  source "$HERE/records.bash"
  task_records branch
  run "$PROJECT_ACTIONS" subscribe-playbook p other other/best-practices/me
  jq -r '.playbookSubscriptions.other // [] | join(" ")' "$PROJECT/project.json"
)
expect "a playbook for an undeclared framework is written with a warning" "$(undeclared_case)" 'other/best-practices/me'

# project_usage_case <args>: the exit of a project call that cannot run as typed.
project_usage_case() (
  source "$HERE/records.bash"
  task_records branch
  run "$PROJECT_ACTIONS" "$@"
  printf '%s\n' "$RC"
)
expect "switch to a project nobody registered is a usage refusal" "$(project_usage_case switch nosuch)" '3'
expect "a project action missing its argument is a usage refusal" "$(project_usage_case state)" '3'

# --- surfaces ---

# surface_file: a surface file with no surface, committed on t1's branch in the worktree.
surface_file() {
  mkdir -p "$WT/.visual-review"
  jq -n '{schemaVersion: 1, viewports: [], surfaces: []}' >"$WT/.visual-review/surfaces.json"
  git -C "$WT" add .visual-review && git -C "$WT" commit -qm "surface file"
}

# enable_case: an unattended register enables a page surface. The exit, and what the file records.
enable_case() (
  source "$HERE/records.bash"
  task_records branch
  surface_file
  run "$SURFACES" --run-mode autonomous register home --url / --kind visual-regression --enable
  printf '%s|%s\n' "$RC" "$(jq -r '.surfaces[0].enabled // "none"' "$WT/.visual-review/surfaces.json")"
)
expect "an unattended register enables a surface" "$(enable_case)" '0|true'

# dirty_case: register in a tree that holds an untracked file of the person's. The exit, whether
# the surface file is committed, and whether the person's file is still untracked.
dirty_case() (
  source "$HERE/records.bash"
  task_records branch
  surface_file
  printf 'mine\n' >"$WT/notes.txt"
  run "$SURFACES" register home --url / --kind visual-regression
  printf '%s|%s|%s\n' "$RC" "$(git -C "$WT" diff --quiet HEAD -- .visual-review && echo committed || echo uncommitted)" \
    "$(git -C "$WT" status --porcelain -- notes.txt | cut -c1-2)"
)
expect "register commits the surface file alone in a tree with other work" "$(dirty_case)" '0|committed|??'

# no_file_case: unregister before any surface file exists.
no_file_case() (
  source "$HERE/records.bash"
  task_records branch
  run "$SURFACES" unregister home
  printf '%s\n' "$RC"
)
expect "a surfaces step before the surface file exists is a usage refusal" "$(no_file_case)" '3'

# elsewhere_case: a command surface writes a new surface file while the branch other holds one.
# The exit, and whether the new file was written.
elsewhere_case() (
  source "$HERE/records.bash"
  task_records branch
  git -C "$CODE" checkout -q -b other main
  mkdir -p "$CODE/.visual-review"
  jq -n '{schemaVersion: 1, viewports: [], surfaces: []}' >"$CODE/.visual-review/surfaces.json"
  git -C "$CODE" add .visual-review && git -C "$CODE" commit -qm "other surface file" && git -C "$CODE" checkout -q --detach main
  run "$SURFACES" register cli --command "true" --kind e2e --reason "the command line"
  printf '%s|%s\n' "$RC" "$(jq -r '.surfaces[0].id // "none"' "$WT/.visual-review/surfaces.json" 2>/dev/null || echo none)"
)
expect "a surface file another branch holds is a warning, and the new file is written" "$(elsewhere_case)" '0|cli'

# --- tool ---

# absent_case: require over a process recipe naming a tool whose check command is not installed.
# The exit, and the tool's line.
absent_case() (
  source "$HERE/records.bash"
  task_records branch
  printf -- '---\nrequires_tooling:\n  - gone\n---\n# process\n' >"$ROOT/process.md"
  printf '# gone\n\n## Run\n\n```sh\naida-test-no-such-command --version\n```\n' >"$ROOT/gone.md"
  run "$TOOL" --tooling "gone=$ROOT/gone.md" require "$ROOT/process.md"
  printf '%s|%s\n' "$RC" "$(grep -c '^TOOLING: gone absent' "$OUT")"
)
expect "require names an absent tool and exits 0" "$(absent_case)" '0|1'

# no_framework_case: a tool call in a project that records no framework.
no_framework_case() (
  source "$HERE/records.bash"
  task_records branch
  jq 'del(.frameworks)' "$PROJECT/project.json" >"$ROOT/p.json" && mv "$ROOT/p.json" "$PROJECT/project.json"
  run "$TOOL" show phpunit
  printf '%s\n' "$RC"
)
expect "a tool call in a project with no framework is a usage refusal" "$(no_framework_case)" '3'

# --- playbooks and next ---

# schema_case: load over a catalog record whose source carries a state the schema does not list,
# with a home folder that holds no playbook of the person's. The exit, whether the record was written, and how many warnings the task records for the step.
schema_case() (
  source "$HERE/records.bash"
  task_records branch
  mkdir -p "$TASK/records"
  jq -n '{sources: [{source: "catalog:fake/best-practices/me", state: "bogus", plays: 0}], plays: []}' \
    >"$TASK/records/playbooks-catalog.json"
  HOME="$ROOT/home" run "$PLAYBOOK" load "$TASK"
  printf '%s|%s|%s\n' "$RC" "$(on_disk "$TASK/records/playbooks.json")" \
    "$(jq '[ (.warnings // [])[] | select(.step == "playbooks load") ] | length' "$TASK/task.json")"
)
expect "a playbook record off the schema is written with a warning" "$(schema_case)" '0|yes|1'

# capture_case: the same play captured twice. The second exit.
capture_case() (
  source "$HERE/records.bash"
  task_records branch
  run "$PLAYBOOK" capture "$PROJECT" --domain Code --title "One rule" --what w --rationale r --when always
  run "$PLAYBOOK" capture "$PROJECT" --domain Code --title "One rule" --what w --rationale r --when always
  printf '%s\n' "$RC"
)
expect "a play captured twice is refused at 3" "$(capture_case)" '3'

# bad_id_case: next opens a target that is a path.
bad_id_case() (
  source "$HERE/records.bash"
  task_records branch
  run "$NEXT" open ../t1
  printf '%s\n' "$RC"
)
expect "next refuses a path as a task id at 3" "$(bad_id_case)" '3'

finish
