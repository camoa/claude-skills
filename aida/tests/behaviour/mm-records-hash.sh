#!/usr/bin/env bash
# Fixture mm: a task whose work orders pass 128 KiB still closes design and starts
# implementation (gap row 402). Linux caps one argument at 128 KiB, and records-hash.sh passed
# every work order to jq as one --argjson argument, so design close refused ("could not compute
# the records hash") and implement start refused ("Argument list too long"). The rows:
#   same     a small contract with one order, and with three (wo1, wo2, wo10): each hashes to the
#            value the code before row 402 gave, so no hash a design close recorded breaks.
#   big      thirteen orders of about 16 KB each, about 210 KB: the hash is 64 hex characters,
#            design closes, start takes the snapshot, a second start resumes on it, and after one
#            order changes and design closes again, start takes that order fresh. No output names
#            the limit.
#   review   one built order, its frozen orders padded to 140 KB after finish, and a stub mutmut
#            on PATH: review checks exits 0, the stub runs, and the mutation row reads met.
# Runs under bash, which CI runs on Linux, from $HOME, with CLAUDE_PLUGIN_ROOT unset. Setup is copied from
# run-kk-fixture.sh.
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
SCOPE="$PLUGIN/skills/scope/scripts/scope-actions.sh"
RESEARCH="$PLUGIN/skills/research/scripts/research-actions.sh"
DESIGN="$PLUGIN/skills/design/scripts/design-actions.sh"
IMPLEMENT="$PLUGIN/skills/implement/scripts/implement-actions.sh"
LOG="$ROOT/log.txt"
TASK=""
WT=""
PROJECT=""

SH=bash; [ -n "${ZSH_VERSION:-}" ] && SH=zsh
in_wt() { (cd "$WT" && env -u CLAUDE_PLUGIN_ROOT "$SH" "$@") >>"$LOG" 2>&1; }
must() { in_wt "$@" || { printf 'setup failed: %s\n' "$*"; tail -5 "$LOG"; exit 1; }; }
# try <out> <cmd>...: runs the action from the worktree, output to <out>, and prints the exit code.
try() {
  local out="$1"; shift
  (cd "$WT" && env -u CLAUDE_PLUGIN_ROOT "$SH" "$@") >"$out" 2>&1
  printf '%s' "$?"
}
# hash_of <folder>: the records hash of a task folder, through the plugin's own library.
hash_of() {
  env -u CLAUDE_PLUGIN_ROOT "$SH" -c '. "$1/scripts/lib/records-hash.sh" && records_hash_for "$2"' _ "$PLUGIN" "$1" 2>&1
}
# limit_named <file>: yes when the output names the argument limit.
limit_named() { grep -qi 'argument list too long' "$1" && echo yes || echo no; }

# make_project <name> <code path>: registers a project on that code.
make_project() {
  env -u CLAUDE_PLUGIN_ROOT "$SH" "$PLUGIN/skills/project/scripts/project-actions.sh" create \
    --name "$1" --path "$2" --projects-home "$AIDA_PROJECTS_HOME" --framework fake >>"$LOG" 2>&1 || exit 1
  PROJECT="$AIDA_PROJECTS_HOME/$1"
}

# use_task <name>: creates the task and points TASK and WT at it.
use_task() {
  env -u CLAUDE_PLUGIN_ROOT "$SH" "$PLUGIN/skills/task/scripts/task-actions.sh" create \
    --project "$PROJECT" --name "$1" -- change some files >>"$LOG" 2>&1 || exit 1
  TASK="$PROJECT/tasks/$1"
  WT="$(jq -r '.worktree.path' "$TASK/task.json")"
  [ -d "$WT" ] || { printf 'setup failed: no worktree for %s\n' "$1"; exit 1; }
}

echo "--- same: small designs hash as they did before row 402"
# golden <folder> <order id>...: a contract and one small work order per id.
golden() {
  local d="$1" o; shift
  mkdir -p "$d/design"
  printf '{"goal":"change a","criteria":[{"id":"c1","text":"a.php changes","author":"owner"}],"nonGoals":[]}\n' >"$d/alignment.json"
  for o in "$@"; do
    printf '{"id":"%s","title":"change %s","criteriaServed":["c1"],"ownedFiles":["%s.php"],"doneWhen":["%s changed"]}\n' \
      "$o" "$o" "$o" "$o" >"$d/design/$o.json"
  done
}
# The values are what records-hash.sh printed at 7b6b29ab^, before row 402, and still prints.
golden "$ROOT/same/one" wo1
golden "$ROOT/same/many" wo1 wo2 wo10
expect "same: one order hashes as before" "$(hash_of "$ROOT/same/one")" \
  "0a5f1b25801a121525a60a75e9c3f25172b3ee07ede6a24f828c19b8cbd1c99c"
expect "same: three orders hash as before" "$(hash_of "$ROOT/same/many")" \
  "d9f1d81cf0b57b649755fc0fd35d1713fc46e8516d75a9cc912d059840cef06b"

echo "--- big: about 210 KB of work orders"
CODE="$ROOT/code"
mkdir -p "$CODE" && cd "$CODE" || exit 1
git init -q -b main && git config user.email fx@example.invalid && git config user.name fx
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13; do printf 'a\n' >"a$i.php"; done
git add -A && git commit -qm init && git checkout -q -b work
cd "$HOME" || exit 1
make_project mmfx "$CODE"
use_task t1
must "$SCOPE" init "$TASK"
must "$SCOPE" set-goal "$TASK" --goal "change files" --expected-result "files changed"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13; do
  must "$SCOPE" add "$TASK" --text "a$i.php changes" --verification "look" --verified-by person
done
mkdir -p "$TASK/records"
printf '{"schemaVersion":1,"stage":"scope","standsAlone":true,"decisions":["change files"],"gaps":[]}\n' \
  >"$TASK/records/scope-distill.json"
must "$SCOPE" approve "$TASK"
must "$RESEARCH" start "$TASK"
must "$RESEARCH" record "$TASK" --search prior --searched-for "prior art" --text "none" \
  --source "the tree" --criteria-served c1,c2,c3,c4,c5,c6,c7,c8,c9,c10,c11,c12,c13
must "$RESEARCH" check "$TASK"
must "$DESIGN" start "$TASK"
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13; do
  must "$DESIGN" create "$TASK" --title "change a$i" --criteria-served "c$i" --criteria-owned "c$i" \
    --reasoning "the brief says so" --diff-budget small --interface none --proof gate
  must "$DESIGN" add-owned-file "$TASK" --id "wo$i" --path "a$i.php"
  must "$DESIGN" add-done-when "$TASK" --id "wo$i" --text "change a$i"
  must "$DESIGN" account "$TASK" --id "wo$i" --finding prior#1
done
# The fixture writes the long reasoning, as a designer's long reuse notes would: 16 KB an order.
PAD="$(printf '%016384d' 0 | tr 0 r)"
for f in "$TASK"/design/wo*.json; do
  doc="$(jq --arg r "$PAD" '.reasoning = $r' "$f")" && printf '%s\n' "$doc" >"$f"
done
SIZE="$(for f in "$TASK"/design/wo*.json; do jq -c . "$f"; done | wc -c | tr -d ' ')"
expect "the work orders pass 200 KB" "$([ "$SIZE" -gt 204800 ] && echo yes || echo "no: $SIZE")" "yes"
expect "the hash is 64 hex characters" "$(hash_of "$TASK" | grep -c '^[0-9a-f]\{64\}$')" "1"
rc="$(try "$ROOT/close-big.txt" "$DESIGN" --run-mode interactive close "$TASK" --no-recipe)"
expect "design closes" "$rc" "0"
expect "close names no limit" "$(limit_named "$ROOT/close-big.txt")" "no"
expect "the close record holds that hash" "$(jq -r .hash "$TASK/design-closed.json" 2>&1)" "$(hash_of "$TASK")"
rc="$(try "$ROOT/start-big.txt" "$IMPLEMENT" start "$TASK")"
expect "start takes the snapshot" "$rc-$(jq '.workOrders | length' "$TASK/implementation/snapshot.json" 2>&1)" "0-13"
expect "start names no limit" "$(limit_named "$ROOT/start-big.txt")" "no"
rc="$(try "$ROOT/resume-big.txt" "$IMPLEMENT" start "$TASK")"
expect "a second start resumes" "$rc" "0"
expect "the resume names no limit" "$(limit_named "$ROOT/resume-big.txt")" "no"
doc="$(jq '.reasoning = "changed"' "$TASK/design/wo2.json")" && printf '%s\n' "$doc" >"$TASK/design/wo2.json"
rc="$(try "$ROOT/reclose-big.txt" "$DESIGN" --run-mode interactive close "$TASK" --no-recipe)"
expect "design closes again" "$rc" "0"
rc="$(try "$ROOT/drift-big.txt" "$IMPLEMENT" start "$TASK")"
expect "a start after wo2 changed takes wo2 fresh" \
  "$rc-$(jq -r '.workOrders[] | select(.id == "wo2") | .reasoning' "$TASK/implementation/snapshot.json" 2>&1)" "0-changed"
expect "the ledger records the resnapshot" \
  "$(jq -c '[ (.resnapshots // [])[] | .id ]' "$TASK/implementation/ledger.json" 2>&1)" '["wo2"]'
expect "the drift start names no limit" "$(limit_named "$ROOT/drift-big.txt")" "no"

echo "--- review: the mutation row reads the frozen orders, over 128 KiB"
# Setup is copied from run-mk-fixture.sh: one order owns three files, a stub mutmut on PATH.
FW=python-cli
RCODE="$ROOT/rcode"
mkdir -p "$RCODE/tests" && cd "$RCODE" || exit 1
git init -q -b main && git config user.email fx@example.invalid && git config user.name fx
printf 'a\n' >a.py && printf 'a\n' >b.py && printf 'a\n' >tests/test_a.py && git add -A && git commit -qm init && git checkout -q -b work
cd "$HOME" || exit 1
mkdir -p "$ROOT/bin" "$ROOT/recipes"
printf '#!/bin/sh\n: >"%s"\nprintf "1/1  \\360\\237\\216\\211 1 \\360\\237\\231\\201 0\\n"\nexit 0\n' "$ROOT/mutmut-ran" >"$ROOT/bin/mutmut"
chmod +x "$ROOT/bin/mutmut"
cat >"$ROOT/recipes/test-execution.md" <<EOF
---
name: python_cli_test_execution
capability: test-execution
recipe_class: process
framework: $FW
---

## Preconditions

\`\`\`yaml
preconditions: []
\`\`\`

## Test commands

\`\`\`yaml
test_commands:
  - id: suite
    argv: ["true"]
    cost: end-of-task
  - id: file
    argv: ["sh", "{paths}"]
    cost: every-attempt
  - id: test
    absent: >-
      No single-test form.
  - id: changed
    absent: >-
      No changed form.
  - id: smoke
    argv: ["true"]
    cost: every-attempt
  - id: mutation
    argv: ["mutmut", "run", "{paths}"]
    cost: end-of-task
\`\`\`

\`\`\`yaml
failure_signal:
  assertion: >-
    Exit 1.
\`\`\`
EOF
cat >"$ROOT/recipes/checks.md" <<EOF
---
name: python_cli_review_checks
capability: review
recipe_class: process
framework: $FW
---

## Check commands

\`\`\`yaml
check_commands:
  - id: coding-standards
    argv: ["true", "{paths}"]
  - id: static-analysis
    absent: >-
      None.
  - id: security
    absent: >-
      None.
  - id: duplication
    absent: >-
      None.
  - id: design-metrics
    absent: >-
      None.
\`\`\`
EOF
TREC="$FW=$ROOT/recipes/test-execution.md"
CREC="$FW=$ROOT/recipes/checks.md"
env -u CLAUDE_PLUGIN_ROOT "$SH" "$PLUGIN/skills/project/scripts/project-actions.sh" create \
  --name mmrev --path "$RCODE" --projects-home "$AIDA_PROJECTS_HOME" --framework "$FW" >>"$LOG" 2>&1 || exit 1
PROJECT="$AIDA_PROJECTS_HOME/mmrev"
use_task t3
printf 'none\n' >"$ROOT/iface.md"; printf 'report\nStop: none\nDeviation: none\n' >"$ROOT/report.md"
printf '{ "findings": [] }\n' >"$ROOT/findings.json"
must "$SCOPE" init "$TASK"
must "$SCOPE" set-goal "$TASK" --goal "change a" --expected-result "a changed"
must "$SCOPE" add "$TASK" --text "a.py changes" --verification "tests/test_a.py" --verified-by machine
mkdir -p "$TASK/records"
printf '{"schemaVersion":1,"stage":"scope","standsAlone":true,"decisions":["change a"],"gaps":[]}\n' \
  >"$TASK/records/scope-distill.json"
must "$SCOPE" approve "$TASK"
must "$RESEARCH" start "$TASK"
must "$RESEARCH" record "$TASK" --search prior --searched-for "prior art" --text "none" \
  --source "the tree" --criteria-served c1
must "$RESEARCH" check "$TASK"
must "$PLUGIN/skills/playbooks/scripts/playbook-actions.sh" load "$TASK"
must "$DESIGN" start "$TASK"
must "$DESIGN" create "$TASK" --title "change a" --criteria-served c1 --criteria-owned c1 \
  --reasoning "the brief says so" --diff-budget small --interface none
must "$DESIGN" add-owned-file "$TASK" --id wo1 --path a.py
must "$DESIGN" add-owned-file "$TASK" --id wo1 --path b.py
must "$DESIGN" add-owned-file "$TASK" --id wo1 --path tests/test_a.py
must "$DESIGN" add-done-when "$TASK" --id wo1 --text "a changes"
must "$DESIGN" add-test "$TASK" --id wo1 --level unit --description "test_a checks a"
must "$DESIGN" account "$TASK" --id wo1 --finding prior#1
must "$DESIGN" --run-mode interactive close "$TASK" --no-recipe
must "$IMPLEMENT" start "$TASK"
must "$IMPLEMENT" preconditions "$TASK" --recipe "$TREC" --check-recipe "$CREC"
mkdir -p "$WT/tests"
printf 'grep -q done a.py || exit 1\n' >"$WT/tests/test_a.py"
must "$IMPLEMENT" tests-freeze "$TASK" wo1 --test-recipe "$TREC" --test-glob 'tests/test_*.py' \
  --test "tests/test_a.py::checks_c1=c1" --locks-in "checks_c1=tests/test_a.py names a" --row "c1=confirmed::model::ok"
FREEZE="$(git -C "$WT" rev-parse HEAD)"
printf 'done\n' >"$WT/a.py"; printf 'done\n' >"$WT/b.py"
git -C "$WT" add -A && git -C "$WT" commit -qm "wo1 attempt" >/dev/null 2>&1
must "$IMPLEMENT" build-record "$TASK" wo1 --interface "$ROOT/iface.md" --report "$ROOT/report.md" \
  --started-at "$FREEZE" --test-recipe "$TREC" --check-recipe "$CREC"
must "$IMPLEMENT" review-record "$TASK" wo1 --findings "$ROOT/findings.json"
must "$IMPLEMENT" close "$TASK" wo1
must "$IMPLEMENT" finish "$TASK"
# The fixture stands in for a long design: the frozen orders gain 140 KB of reasoning.
S="$TASK/implementation/snapshot.json"
printf '%0143360d' 0 | tr 0 r >"$ROOT/pad.txt"
doc="$(jq --rawfile r "$ROOT/pad.txt" '.workOrders[0].reasoning = $r' "$S")" && printf '%s\n' "$doc" >"$S"
expect "the frozen orders pass 128 KiB" \
  "$([ "$(jq -c '.workOrders' "$S" | wc -c | tr -d ' ')" -gt 131072 ] && echo yes || echo no)" "yes"
rc="$( (cd "$WT" && PATH="$ROOT/bin:$PATH" env -u CLAUDE_PLUGIN_ROOT "$SH" "$PLUGIN/skills/review/scripts/review-actions.sh" \
  checks "$TASK" --recipe "$TREC" --check-recipe "$CREC") >"$ROOT/review.txt" 2>&1; printf '%s' "$?")"
expect "review checks exits 0, the stub ran, the mutation row reads met" \
  "$rc $([ -e "$ROOT/mutmut-ran" ] && echo ran || echo not-run) $(jq -r '.mutation.verdict' "$TASK/review/review.json" 2>&1)" "0 ran met"
expect "review names no limit" "$(limit_named "$ROOT/review.txt")" "no"

printf 'passed %s of %s\n' "$PASS" "$TOTAL"
[ "$PASS" -eq "$TOTAL" ]
