#!/usr/bin/env bash
# Fixture es: gap row 176. The design close moves each finished critique file out
# of the task's ignored records/ folder into its design/ folder, records the new paths, and commits
# the record and the evidence together. Rows: three finished critiques move and are recorded by
# path; one commit carries design-closed.json and the three files, and git show produces each one;
# a second close keeps one copy of each and records them again; a close with no critique file is
# unchanged; an unfinished critique is left out of the record and its count. Gap row 190 later made
# the close move that unfinished file too, so run-ex-fixture.sh owns where it lands. Runs under bash,
# which CI runs on Linux, from $HOME, with CLAUDE_PLUGIN_ROOT unset. Setup copied from run-dv-fixture.sh.
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
PROJECT="$ROOT/aida/projects/esfx"
SCOPE="$PLUGIN/skills/scope/scripts/scope-actions.sh"
RESEARCH="$PLUGIN/skills/research/scripts/research-actions.sh"
DESIGN="$PLUGIN/skills/design/scripts/design-actions.sh"
LOG="$ROOT/log.txt"
TASK=""
WT=""
# The shell the plugin scripts run under: the one this runner runs under.
if [ -n "${ZSH_VERSION:-}" ]; then SH=zsh; else SH=bash; fi

# Every stage action runs from the task's worktree (exit 79 otherwise). Output goes to the log.
in_wt() { (cd "$WT" && env -u CLAUDE_PLUGIN_ROOT "$SH" "$@") >>"$LOG" 2>&1; }
must() { in_wt "$@" || { printf 'setup failed: %s\n' "$*"; tail -5 "$LOG"; exit 1; }; }
# try <out> <cmd...>: runs one call from the worktree, stdout to <out>, stderr to <out>.err,
# and prints the exit code.
try() {
  local out="$1"; shift
  (cd "$WT" && env -u CLAUDE_PLUGIN_ROOT "$SH" "$@") >"$out" 2>"$out.err"
  printf '%s' "$?"
}

make_code_repo() {
  mkdir -p "$CODE" && cd "$CODE" || exit 1
  git init -q -b main && git config user.email fx@example.invalid && git config user.name fx
  for f in a b c; do printf '%s\n' "$f" >"$f.php"; done
  git add -A && git commit -qm init && git checkout -q -b work
  cd "$HOME" || exit 1
}

make_project() {
  env -u CLAUDE_PLUGIN_ROOT "$SH" "$PLUGIN/skills/project/scripts/project-actions.sh" create \
    --name esfx --path "$CODE" --projects-home "$AIDA_PROJECTS_HOME" --framework fake >>"$LOG" 2>&1 || exit 1
}

# use_task <name>: creates the task and points TASK and WT at it.
use_task() {
  env -u CLAUDE_PLUGIN_ROOT "$SH" "$PLUGIN/skills/task/scripts/task-actions.sh" create \
    --project "$PROJECT" --name "$1" -- write a report >>"$LOG" 2>&1 || exit 1
  TASK="$PROJECT/tasks/$1"
  WT="$(jq -r '.worktree.path' "$TASK/task.json")"
  [ -d "$WT" ] || { printf 'setup failed: no worktree for %s\n' "$1"; exit 1; }
}

# One person-verified criterion; the distill sidecar is an agent's record, so the fixture writes it.
scope_task() {
  must "$SCOPE" init "$TASK"
  must "$SCOPE" set-goal "$TASK" --goal "write a report" --expected-result "a report exists"
  must "$SCOPE" add "$TASK" --text "the report exists" --verification "read it" --verified-by person
  mkdir -p "$TASK/records"
  printf '{"schemaVersion":1,"stage":"scope","standsAlone":true,"decisions":["write a report"],"gaps":[]}\n' \
    >"$TASK/records/scope-distill.json"
  must "$SCOPE" approve "$TASK"
}

research_task() {
  must "$RESEARCH" start "$TASK"
  must "$RESEARCH" record "$TASK" --search prior --searched-for "prior art" --text "none" \
    --source "the tree" --criteria-served c1
  must "$RESEARCH" check "$TASK"
}

design_task() {
  must "$DESIGN" start "$TASK"
  must "$DESIGN" create "$TASK" --title "write the report" --criteria-served c1 --criteria-owned c1 \
    --reasoning "the brief says so" --diff-budget small --interface none
  must "$DESIGN" add-done-when "$TASK" --id wo1 --text "the report reads well"
  must "$DESIGN" add-owned-file "$TASK" --id wo1 --path a.php
}

# write_critique <lens> <n>: a finished critique file, n findings, under records/.
write_critique() {
  printf '# Design critique: %s\n\n| severity | order | what |\n|---|---|---|\n| concern | wo1 | something |\n\nfindings: %s\n' "$1" "$2" \
    >"$TASK/records/design-critique-$1.md"
}
# write_unfinished <lens>: a critique file with no findings line, the shape a critic that stopped
# part way leaves behind.
write_unfinished() {
  printf '# Design critique: %s\n\n| severity | order | what |\n|---|---|---|\n' "$1" \
    >"$TASK/records/design-critique-$1.md"
}
# files_in <folder>: the critique basenames in one folder of the task, one per line, sorted.
files_in() {
  find "$TASK/$1" -mindepth 1 -maxdepth 1 -type f -name 'design-critique-*.md' 2>/dev/null \
    | sed 's|.*/||' | sort | tr '\n' ' ' | sed 's/ $//'
}
# recorded_files: critique.files of the closed record, basenames, space separated.
recorded_files() {
  jq -r '(.critique.files // []) | map(sub(".*/"; "")) | join(" ")' "$TASK/design-closed.json"
}
# recorded_dirs: the folder each recorded path sits in, deduplicated.
recorded_dirs() {
  jq -r '(.critique.files // []) | map(sub("/[^/]*$"; "") | sub(".*/"; "")) | unique | join(" ")' \
    "$TASK/design-closed.json"
}
# in_head <relative path>: `yes` when git holds the path at HEAD of the project repository.
in_head() {
  git -C "$PROJECT" show "HEAD:$1" >/dev/null 2>&1 && printf 'yes' || printf 'no'
}
# head_files: the paths the last commit carried, sorted, space separated.
head_files() {
  git -C "$PROJECT" show --name-only --format= HEAD | sed '/^$/d' | sort | tr '\n' ' ' | sed 's/ $//'
}

make_code_repo
make_project
use_task t1
scope_task
research_task
design_task

echo "--- row 176: three finished critiques move into design/ and are recorded there"
write_critique contract 3
write_critique reuse 1
write_critique buildability 2
must "$DESIGN" account "$TASK" --id wo1 --finding prior#1
rc="$(try "$ROOT/out-close.txt" "$DESIGN" --run-mode interactive close "$TASK" --no-recipe \
  --critique-outcome "4 findings changed an order, 2 left with a reason")"
expect "close exits 0" "$rc" "0"
expect "the three files are in design/" "$(files_in design)" \
  "design-critique-buildability.md design-critique-contract.md design-critique-reuse.md"
expect "records/ holds no critique file" "$(files_in records)" ""
expect "the record names the three files" "$(recorded_files)" \
  "design-critique-buildability.md design-critique-contract.md design-critique-reuse.md"
expect "every recorded path is under design/" "$(recorded_dirs)" "design"
expect "the count is the sum of the three" "$(jq -r '.critique.findings' "$TASK/design-closed.json")" "6"
expect "the outcome is recorded" "$(jq -r '.critique.outcome' "$TASK/design-closed.json")" \
  "4 findings changed an order, 2 left with a reason"

echo "--- row 176: one commit carries the record and the three files"
expect "the commit carries both" "$(head_files)" \
  "tasks/t1/design-closed.json tasks/t1/design/design-critique-buildability.md tasks/t1/design/design-critique-contract.md tasks/t1/design/design-critique-reuse.md tasks/t1/design/wo1.json tasks/t1/design/wo1.md"
expect "git show produces the contract critique" "$(in_head tasks/t1/design/design-critique-contract.md)" "yes"
expect "git show produces the reuse critique" "$(in_head tasks/t1/design/design-critique-reuse.md)" "yes"
expect "git show produces the buildability critique" "$(in_head tasks/t1/design/design-critique-buildability.md)" "yes"
expect "the committed file is what the critic wrote" \
  "$(git -C "$PROJECT" show HEAD:tasks/t1/design/design-critique-contract.md | tail -1)" "findings: 3"

echo "--- row 176: a second close keeps the files once each and records them again"
must "$DESIGN" account "$TASK" --id wo1 --finding prior#1
rc="$(try "$ROOT/out-close2.txt" "$DESIGN" --run-mode interactive close "$TASK" --no-recipe \
  --critique-outcome "nothing further")"
expect "the second close exits 0" "$rc" "0"
expect "design/ still holds one of each" "$(files_in design)" \
  "design-critique-buildability.md design-critique-contract.md design-critique-reuse.md"
expect "the record still names what is on disk" "$(recorded_files)" \
  "design-critique-buildability.md design-critique-contract.md design-critique-reuse.md"
expect "the count is unchanged" "$(jq -r '.critique.findings' "$TASK/design-closed.json")" "6"
expect "the new outcome is recorded" "$(jq -r '.critique.outcome' "$TASK/design-closed.json")" "nothing further"

echo "--- row 176: a re-critique after the move replaces the file it names"
write_critique contract 5
must "$DESIGN" account "$TASK" --id wo1 --finding prior#1
rc="$(try "$ROOT/out-close3.txt" "$DESIGN" --run-mode autonomous close "$TASK" --no-recipe)"
expect "the close exits 0" "$rc" "0"
expect "design/ still holds one of each" "$(files_in design)" \
  "design-critique-buildability.md design-critique-contract.md design-critique-reuse.md"
expect "records/ is empty again" "$(files_in records)" ""
expect "the count uses the new file" "$(jq -r '.critique.findings' "$TASK/design-closed.json")" "8"

echo "--- row 176: an unfinished critique is skipped, uncounted and left in records/"
use_task t2
scope_task
research_task
design_task
write_critique contract 2
write_unfinished reuse
must "$DESIGN" account "$TASK" --id wo1 --finding prior#1
rc="$(try "$ROOT/out-close-part.txt" "$DESIGN" --run-mode interactive close "$TASK" --no-recipe \
  --critique-outcome "2 findings left with a reason")"
expect "close exits 0" "$rc" "0"
expect "only the finished file moved under its own name" "$(files_in design)" "design-critique-contract.md"
expect "records/ holds no critique file" "$(files_in records)" ""
expect "the record names the finished file alone" "$(recorded_files)" "design-critique-contract.md"
expect "the count is the finished file's own" "$(jq -r '.critique.findings' "$TASK/design-closed.json")" "2"
expect "the close names the unfinished file on stderr" \
  "$(grep -c 'design-critique-reuse.md has no findings line' "$ROOT/out-close-part.txt.err")" "1"
expect "no records/ path for it is committed" "$(in_head tasks/t2/records/design-critique-reuse.md)" "no"
expect "the finished file is committed" "$(in_head tasks/t2/design/design-critique-contract.md)" "yes"

echo "--- row 176: a close with no critique file is unchanged"
use_task t3
scope_task
research_task
design_task
must "$DESIGN" account "$TASK" --id wo1 --finding prior#1
rc="$(try "$ROOT/out-close-none.txt" "$DESIGN" --run-mode interactive close "$TASK" --no-recipe)"
expect "close exits 0" "$rc" "0"
expect "the record has no critique object" "$(jq -r 'has("critique")' "$TASK/design-closed.json")" "false"
expect "design/ holds no critique file" "$(files_in design)" ""
expect "nothing prints for the outcome" "$(grep -c '^critiqueOutcome' "$ROOT/out-close-none.txt")" "0"
must "$DESIGN" account "$TASK" --id wo1 --finding prior#1
rc="$(try "$ROOT/out-close-flag.txt" "$DESIGN" --run-mode interactive close "$TASK" --no-recipe \
  --critique-outcome "x")"
expect "an outcome with no critique file refuses at exit 3" "$rc" "3"
expect "the refusal names both folders" \
  "$(grep -c "records or $TASK/design to record it beside" "$ROOT/out-close-flag.txt.err")" "1"

echo "--- row 176: a destination that is not a file refuses, and the close writes nothing"
use_task t4
scope_task
research_task
design_task
write_critique contract 3
write_critique reuse 1
mkdir -p "$TASK/design/design-critique-reuse.md"
must "$DESIGN" account "$TASK" --id wo1 --finding prior#1
rc="$(try "$ROOT/out-close-dir.txt" "$DESIGN" --run-mode interactive close "$TASK" --no-recipe \
  --critique-outcome "4 findings changed an order")"
expect "close refuses at exit 3" "$rc" "3"
expect "the refusal names the path" \
  "$(grep -c "$TASK/design/design-critique-reuse.md is not a file" "$ROOT/out-close-dir.txt.err")" "1"
expect "no record was written" "$([ -f "$TASK/design-closed.json" ] && printf yes || printf no)" "no"
expect "the reuse critique is still in records/" \
  "$(find "$TASK/records" -maxdepth 1 -type f -name 'design-critique-reuse.md' | wc -l | tr -d '[:space:]')" "1"
expect "the directory is untouched" \
  "$([ -d "$TASK/design/design-critique-reuse.md" ] && printf yes || printf no)" "yes"
expect "nothing moved into the directory" \
  "$(find "$TASK/design/design-critique-reuse.md" -mindepth 1 | wc -l | tr -d '[:space:]')" "0"
rmdir "$TASK/design/design-critique-reuse.md"
must "$DESIGN" account "$TASK" --id wo1 --finding prior#1
rc="$(try "$ROOT/out-close-after.txt" "$DESIGN" --run-mode interactive close "$TASK" --no-recipe \
  --critique-outcome "4 findings changed an order")"
expect "the close after the repair exits 0" "$rc" "0"
expect "both files are in design/" "$(files_in design)" \
  "design-critique-contract.md design-critique-reuse.md"
expect "the record names both and counts both" \
  "$(jq -r '[(.critique.files | length | tostring), (.critique.findings | tostring)] | join(" ")' "$TASK/design-closed.json")" "2 4"

printf 'passed %s of %s\n' "$PASS" "$TOTAL"
[ "$PASS" -eq "$TOTAL" ] || exit 1
