#!/usr/bin/env bash
# Fixture ks: scope's approve relabels every designer criterion to owner, and
# implement's drift compare no longer reads that relabel as a changed criterion (gap row 355,
# vibe-config finding 5). Three orders: wo1 serves c1, wo2 serves c2 and depends on wo1, wo3
# serves c3. Scope closes with distill, so c1 to c3 stay designer in the snapshot. wo1 and wo2
# are marked closed in the ledger by hand: a real close needs an implementer and a reviewer,
# which a fixture cannot run. The rows:
#   approve  a person adds c4 as owner and runs approve, which promotes c1 to c3; design adds
#            wo4 for c4 and closes: start exits 0, halts nothing, wo1 and wo2 stay closed, wo4
#            is taken in, and the snapshot takes the owner labels.
#   text     the same relabel with c1's text changed too: attended, wo1 names the change to c1
#            and stops nothing, and wo2 is not touched (6.1.0 batch 3b).
# Runs under bash, which CI runs on Linux, from $HOME, with CLAUDE_PLUGIN_ROOT unset. Setup is copied from
# run-jj-fixture.sh.
PLUGIN="${PLUGIN:-$(cd "$(dirname "$0")/../.." && pwd)}"
set -u

PASS=0; TOTAL=0
# expect <what> <actual> <wanted>: prints ok or BAD with both values, and counts.
expect() {
  TOTAL=$((TOTAL + 1))
  if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); printf 'ok: %s\n' "$1"
  else printf 'BAD: %s\n  actual: %s\n  wanted: %s\n' "$1" "$2" "$3"; fi
}

ROOT="$(mktemp -d)" || exit 1
trap 'rm -rf "$ROOT"' EXIT
export AIDA_REGISTRY_PATH="$ROOT/aida/registry.json"
export AIDA_PROJECTS_HOME="$ROOT/aida/projects"
export AIDA_SETTINGS_PATH="$ROOT/aida/settings.json"
CODE="$ROOT/code"
PROJECT="$ROOT/aida/projects/ksfx"
SCOPE="$PLUGIN/skills/scope/scripts/scope-actions.sh"
RESEARCH="$PLUGIN/skills/research/scripts/research-actions.sh"
DESIGN="$PLUGIN/skills/design/scripts/design-actions.sh"
IMPLEMENT="$PLUGIN/skills/implement/scripts/implement-actions.sh"
LOG="$ROOT/log.txt"
TASK=""
WT=""

SH=bash; [ -n "${ZSH_VERSION:-}" ] && SH=zsh
in_wt() { (cd "$WT" && env -u CLAUDE_PLUGIN_ROOT "$SH" "$@") >>"$LOG" 2>&1; }
must() { in_wt "$@" || { printf 'setup failed: %s\n' "$*"; tail -5 "$LOG"; exit 1; }; }

make_code_repo() {
  mkdir -p "$CODE" && cd "$CODE" || exit 1
  git init -q -b main && git config user.email fx@example.invalid && git config user.name fx
  for f in a b c d e; do printf '%s\n' "$f" >"$f.php"; done
  git add -A && git commit -qm init && git checkout -q -b work
  cd "$HOME" || exit 1
}

make_project() {
  env -u CLAUDE_PLUGIN_ROOT "$SH" "$PLUGIN/skills/project/scripts/project-actions.sh" create \
    --name ksfx --path "$CODE" --projects-home "$AIDA_PROJECTS_HOME" --framework fake >>"$LOG" 2>&1 || exit 1
}

# use_task <name>: creates the task and points TASK and WT at it.
use_task() {
  env -u CLAUDE_PLUGIN_ROOT "$SH" "$PLUGIN/skills/task/scripts/task-actions.sh" create \
    --project "$PROJECT" --name "$1" -- change some files >>"$LOG" 2>&1 || exit 1
  TASK="$PROJECT/tasks/$1"
  WT="$(jq -r '.worktree.path' "$TASK/task.json")"
  [ -d "$WT" ] || { printf 'setup failed: no worktree for %s\n' "$1"; exit 1; }
}

# Closes with distill rather than approve, so every criterion is still designer at the snapshot.
scope_task() {
  must "$SCOPE" init "$TASK"
  must "$SCOPE" set-goal "$TASK" --goal "change files" --expected-result "files changed"
  must "$SCOPE" add "$TASK" --text "a.php changes" --verification "look" --verified-by person
  must "$SCOPE" add "$TASK" --text "c.php changes" --verification "look" --verified-by person
  must "$SCOPE" add "$TASK" --text "d.php changes" --verification "look" --verified-by person
  mkdir -p "$TASK/records"
  printf '{"schemaVersion":1,"stage":"scope","standsAlone":true,"decisions":["change files"],"gaps":[]}\n' \
    >"$TASK/records/scope-distill.json"
  must "$SCOPE" distill "$TASK"
}

research_task() {
  must "$RESEARCH" start "$TASK"
  must "$RESEARCH" record "$TASK" --search prior --searched-for "prior art" --text "none" \
    --source "the tree" --criteria-served c1,c2,c3
  must "$RESEARCH" check "$TASK"
}

# design_order <woId> <criterion> <dependsOn or -> <title> <path>: one gate order owning the path.
design_order() {
  local id="$1" crit="$2" deps="$3" title="$4" p="$5"
  if [ "$deps" = "-" ]; then
    must "$DESIGN" create "$TASK" --title "$title" --criteria-served "$crit" --criteria-owned "$crit" \
      --reasoning "the brief says so" --diff-budget small --interface none --proof gate
  else
    must "$DESIGN" create "$TASK" --title "$title" --criteria-served "$crit" --criteria-owned "$crit" \
      --depends-on "$deps" --reasoning "the brief says so" --diff-budget small --interface none --proof gate
  fi
  must "$DESIGN" add-owned-file "$TASK" --id "$id" --path "$p"
  must "$DESIGN" add-done-when "$TASK" --id "$id" --text "$title"
}

close_design() { must "$DESIGN" account "$TASK" --id wo1 --finding prior#1; must "$DESIGN" --run-mode interactive close "$TASK" --no-recipe; }

# resumed_start <out>: runs start again, output to <out>, and prints the exit code.
resumed_start() {
  (cd "$WT" && env -u CLAUDE_PLUGIN_ROOT "$SH" "$IMPLEMENT" start "$TASK") >"$1" 2>"$1.err"
  printf '%s' "$?"
}
line() { grep "^$2:" "$1" | head -1; }
# Since 6.1.0 batch 3b a criterion reason ends with " (live text <id> <hash>)"; the readers drop it.
ledger_halt() { jq -r --arg id "$1" '.orders[] | select(.id == $id) | (.stopped // []) | if length == 0 then "none" else map(.reason | sub(" [(]live text [^)]*[)]$"; "")) | join("; ") end' "$TASK/implementation/ledger.json"; }
# ledger_changed <unit>: the reasons of an attended change mid-build, which stop nothing (6.1.0 batch 3b).
ledger_changed() { jq -r --arg id "$1" '.orders[] | select(.id == $id) | (.changed // []) | if length == 0 then "none" else map(.reason | sub(" [(]live text [^)]*[)]$"; "")) | join("; ") end' "$TASK/implementation/ledger.json"; }
ledger_step() { jq -r --arg id "$1" '.orders[] | select(.id == $id) | .lastStep // "null"' "$TASK/implementation/ledger.json"; }
# set_ledger <jq args>: edits the ledger by hand, the way a fixture stands in for an earlier run.
set_ledger() {
  local l="$TASK/implementation/ledger.json" doc
  doc="$(jq "$@" "$l")" && printf '%s\n' "$doc" >"$l"
}
close_orders() { set_ledger '.orders = (.orders | map(if .id == "wo1" or .id == "wo2" then (.lastStep = "closed" | .commitRange = "aaaaaaa..bbbbbbb") else . end))'; }

# build_task <name>: scoped, researched, designed, started, with wo1 and wo2 closed.
build_task() {
  use_task "$1"
  scope_task
  research_task
  must "$DESIGN" start "$TASK"
  design_order wo1 c1 - "change a" a.php
  design_order wo2 c2 wo1 "change c" c.php
  design_order wo3 c3 - "change d" d.php
  close_design
  must "$IMPLEMENT" start "$TASK"
  close_orders
}

# add_and_approve: the contract change finding 5 describes, one added criterion and an approve.
add_and_approve() {
  must "$SCOPE" add "$TASK" --text "e.php changes" --verification "look" --verified-by person --author owner
  must "$SCOPE" approve "$TASK"
  design_order wo4 c4 - "change e" e.php
  close_design
}

make_code_repo
make_project

echo "--- approve: one added criterion, and approve promotes the others"
build_task t1
expect "the snapshot holds c1 as designer" "$(jq -r '.alignment.criteria[0].author' "$TASK/implementation/snapshot.json")" "designer"
add_and_approve
expect "approve promoted c1 to owner" "$(jq -r '.criteria[0].author' "$TASK/alignment.json")" "owner"
rc="$(resumed_start "$ROOT/start-1.txt")"
expect "start exits 0" "$rc" "0"
expect "wo1 is not halted" "$(ledger_halt wo1)" "none"
expect "wo2 is not halted" "$(ledger_halt wo2)" "none"
expect "wo1 stays closed" "$(ledger_step wo1)" "closed"
expect "wo2 stays closed" "$(ledger_step wo2)" "closed"
expect "nothing is stopped" "$(line "$ROOT/start-1.txt" stopped)" "stopped: none"
expect "wo4 is taken in" "$(jq -r '[.workOrders[].id] | join(" ")' "$TASK/implementation/snapshot.json")" "wo1 wo2 wo3 wo4"
expect "the snapshot takes the owner labels" "$(jq -r '[.alignment.criteria[].author] | unique | join(" ")' "$TASK/implementation/snapshot.json")" "owner"

echo "--- text: the relabel with a changed criterion text"
build_task t2
must "$SCOPE" update "$TASK" --id c1 --text "a.php changes twice"
add_and_approve
rc="$(resumed_start "$ROOT/start-2.txt")"
expect "start exits 0" "$rc" "0"
expect "a changed criterion text is still named on wo1, attended" "$(ledger_changed wo1)" \
  "design drift: the live text of criterion c1, which wo1 serves, differs from the frozen copy the snapshot keeps"
expect "wo2 is neither stopped nor changed" "$(ledger_halt wo2) $(ledger_changed wo2)" "none none"

printf 'passed %s of %s\n' "$PASS" "$TOTAL"
[ "$PASS" -eq "$TOTAL" ]
