#!/usr/bin/env bash
# Fixture gj: a dispatched role works in the task's worktree and cannot touch the
# main checkout (gap row 230). Builds a project and one task with two person-verified orders, on
# the setup of run-dm-fixture.sh. Then it checks that dispatch-open prints the worktree, that each
# brief a role reads names it, and that both hooks, while a dispatch is open, refuse the role a
# denied read and any write in the main checkout, allow the same in the worktree per the existing
# rules, and allow everything once the dispatch is closed. Build gr (gap row 243) adds the forms
# that named the main checkout without a plain read or write verb: git with -C, --git-dir or
# --work-tree, git show <rev>:<path>, git cat-file, git diff and git log -p, and cp, rsync,
# install, mv and tar out of it or into it. Each is refused in the main checkout and passes in
# the worktree, whose path starts with the main checkout's. git show <rev>:<denied>, git
# cat-file and git grep are refused in the worktree too, as a direct read there is. Runs under bash, which CI runs on Linux,
# from $HOME, with CLAUDE_PLUGIN_ROOT unset.
# fix_report <unit>: the report the newest fix brief of that unit pins, the one path fix-record
# takes (gap row 250), or a file under $ROOT when no brief pins one.
fix_report() {
  local b p=""
  b="$(ls -t "$TASK"/implementation/brief-"$1"-fix-*.json 2>/dev/null | head -n 1)"
  [ -z "$b" ] || p="$(jq -r '.reportPath // empty' "$b")"
  printf '%s' "${p:-$ROOT/fix-report-$1.md}"
}
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
PROJECT="$ROOT/aida/projects/gjfx"
TASK="$PROJECT/tasks/t1"
IMPL="$TASK/implementation"
WT="$ROOT/code.worktrees/code-t1"
RECIPES="$ROOT/recipes"
SCOPE="$PLUGIN/skills/scope/scripts/scope-actions.sh"
RESEARCH="$PLUGIN/skills/research/scripts/research-actions.sh"
DESIGN="$PLUGIN/skills/design/scripts/design-actions.sh"
IMPLEMENT="$PLUGIN/skills/implement/scripts/implement-actions.sh"
TASKS="$PLUGIN/skills/task/scripts/task-actions.sh"
LOG="$ROOT/log.txt"

# Every stage action runs from the task's worktree (exit 79 otherwise), under the shell this
# runner runs under. Output goes to the log.
SH=bash; [ -n "${ZSH_VERSION:-}" ] && SH=zsh
in_wt() { (cd "$WT" && env -u CLAUDE_PLUGIN_ROOT "$SH" "$@") >>"$LOG" 2>&1; }
must() { in_wt "$@" || { printf 'setup failed: %s\n' "$*"; tail -5 "$LOG"; exit 1; }; }
# try <out> <cmd>...: runs the action from the worktree, output to <out>, and prints the exit code.
try() {
  local out="$1"; shift
  (cd "$WT" && env -u CLAUDE_PLUGIN_ROOT "$SH" "$@") >"$out" 2>&1
  printf '%s' "$?"
}

make_code_repo() {
  mkdir -p "$CODE" && cd "$CODE" || exit 1
  git init -q -b main && git config user.email fx@example.invalid && git config user.name fx
  for f in a b; do printf '%s\n' "$f" >"$f.php"; done
  git add -A && git commit -qm init && git checkout -q -b work
  cd "$HOME" || exit 1
}

make_project_and_task() {
  env -u CLAUDE_PLUGIN_ROOT "$SH" "$PLUGIN/skills/project/scripts/project-actions.sh" create \
    --name gjfx --path "$CODE" --projects-home "$AIDA_PROJECTS_HOME" --framework fake >>"$LOG" 2>&1 || exit 1
  env -u CLAUDE_PLUGIN_ROOT "$SH" "$TASKS" create \
    --project "$PROJECT" --name t1 -- change some files >>"$LOG" 2>&1 || exit 1
}

# c1 is a person's to verify, c2 a test's, so wo2 takes a test author; the distill sidecar is an agent's record, so the
# fixture writes it.
scope_task() {
  must "$SCOPE" init "$TASK"
  must "$SCOPE" set-goal "$TASK" --goal "change files" --expected-result "files changed"
  must "$SCOPE" add "$TASK" --text "a.php changes" --verification "look" --verified-by person
  must "$SCOPE" add "$TASK" --text "b.php changes" --verification "tests/BTest.sh" --verified-by machine
  mkdir -p "$TASK/records"
  printf '{"schemaVersion":1,"stage":"scope","standsAlone":true,"decisions":["change files"],"gaps":[]}\n' \
    >"$TASK/records/scope-distill.json"
  must "$SCOPE" approve "$TASK"
}

research_task() {
  must "$RESEARCH" start "$TASK"
  must "$RESEARCH" record "$TASK" --search prior --searched-for "prior art" --text "none" \
    --source "the tree" --criteria-served c1,c2
  must "$RESEARCH" check "$TASK"
}

# design_order <woId> <criterion> <title> <path>: one order owning the path.
# `p`, never `path`: zsh ties a variable named path to PATH, and a local one empties it.
design_order() {
  local id="$1" crit="$2" title="$3" p="$4"
  must "$DESIGN" create "$TASK" --title "$title" --criteria-served "$crit" --criteria-owned "$crit" \
    --reasoning "the brief says so" --diff-budget small --interface none
  must "$DESIGN" add-owned-file "$TASK" --id "$id" --path "$p"
  must "$DESIGN" add-done-when "$TASK" --id "$id" --text "$title"
}

design_task() {
  must "$DESIGN" start "$TASK"
  design_order wo1 c1 "change a" a.php
  design_order wo2 c2 "change b" b.php
  must "$DESIGN" add-test "$TASK" --id wo2 --level unit --description "BTest checks b"
  must "$DESIGN" account "$TASK" --id wo1 --finding prior#1
  must "$DESIGN" --run-mode interactive close "$TASK" --no-recipe
}

write_recipes() {
  mkdir -p "$RECIPES"
  cat >"$RECIPES/test-execution.md" <<'EOR'
---
name: fake_test_execution
capability: test-execution
recipe_class: process
framework: fake
---

## Preconditions

```yaml
preconditions: []
```

## Test commands

```yaml
test_commands:
  - id: suite
    argv: ["true"]
    cost: every-attempt
  - id: file
    argv: ["true", "{paths}"]
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
    absent: >-
      No mutation tool.
```

```yaml
failure_signal:
  assertion: >-
    Exit 1.
```
EOR
  cat >"$RECIPES/checks.md" <<'EOR'
---
name: fake_review_checks
capability: review
recipe_class: process
framework: fake
---

## Check commands

```yaml
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
```

## Surface commands

```yaml
surface_commands:
  - id: e2e-preflight
    absent: >-
      None.
  - id: e2e
    absent: >-
      None.
  - id: visual-regression
    absent: >-
      None.
  - id: visual-regression-accept
    absent: >-
      None.
  - id: visual-parity
    absent: >-
      None.
  - id: visual-parity-accept
    absent: >-
      None.
```
EOR
}

# freeze_order <unit> <criterion> <checklist text>: the person-verified row, frozen.
freeze_order() {
  must "$IMPLEMENT" tests-freeze "$TASK" "$1" --test-recipe "fake=$RECIPES/test-execution.md" \
    --checklist "$2=$3"
}

implement_to_freeze() {
  must "$IMPLEMENT" start "$TASK"
  must "$IMPLEMENT" preconditions "$TASK" \
    --recipe "fake=$RECIPES/test-execution.md" --check-recipe "fake=$RECIPES/checks.md"
  freeze_order wo1 c1 look

}


# commit_change <file> <text>: one commit in the worktree changing the file. SEQ keeps every
# write different, so each call makes a commit.
SEQ=0
commit_change() {
  SEQ=$((SEQ + 1))
  (cd "$WT" && printf '%s %s\n' "$2" "$SEQ" >"$1" && git add "$1" && git commit -qm "$2")
}

# build_order <unit> <file>: one commit changing the file, then the attempt recorded from the
# worktree's previous commit to its head. The ledger then reads checks-passed for the order.
build_order() {
  local unit="$1" file="$2" from
  commit_change "$file" "$unit built"
  from="$(git -C "$WT" rev-parse HEAD~1)"
  printf 'none\n' >"$ROOT/iface.md"; printf 'report\nStop: none\nDeviation: none\n' >"$ROOT/report.md"
  must "$IMPLEMENT" build-record "$TASK" "$unit" \
    --interface "$ROOT/iface.md" --report "$ROOT/report.md" --started-at "$from" \
    --test-recipe "fake=$RECIPES/test-execution.md"
}


WRITE_HOOK="$PLUGIN/hooks/deny-frozen-test-writes.sh"
READ_HOOK="$PLUGIN/hooks/deny-prior-source.sh"
# hook_answer <hook> <cwd> <agent type, or '' for the main session> <tool> <command or path>: deny,
# not-enforced or allow for one payload. Bash takes a command, the other tools a file_path. A role's
# payload carries agent_id as well as agent_type, as Claude Code sends it inside a subagent.
# HOOK_HOME, when set, is the hook's $HOME, so a `~/` operand can name the main checkout.
hook_answer() {
  local out payload
  if [ "$4" = "Bash" ]; then
    payload="$(jq -nc --arg c "$2" --arg k "$5" '{tool_name: "Bash", cwd: $c, tool_input: {command: $k}}')"
  else
    payload="$(jq -nc --arg c "$2" --arg t "$4" --arg p "$5" '{tool_name: $t, cwd: $c, tool_input: {file_path: $p, content: "x"}}')"
  fi
  [ -z "$3" ] || payload="$(printf '%s' "$payload" | jq -c --arg a "$3" '.agent_type = $a | .agent_id = "a1"')"
  out="$(printf '%s' "$payload" | env -u CLAUDE_PLUGIN_ROOT HOME="${HOOK_HOME:-$HOME}" "$SH" "$1" 2>>"$LOG")"
  printf '%s\n' "$out" >>"$LOG"
  case "$out" in
    *'"permissionDecision":"deny"'*) printf 'deny' ;;
    *'"systemMessage"'*) printf 'not-enforced' ;;
    *) printf 'allow' ;;
  esac
}
# last_reason_has <text>: 1 when the hook's last output line carries the text, else 0.
last_reason_has() { tail -1 "$LOG" | grep -c -e "$1"; }
line_of() { sed -n "s/^$1: //p" "$2"; }

make_code_repo
make_project_and_task
scope_task
research_task
design_task
write_recipes
implement_to_freeze
WTP="$(jq -r '.worktree.path' "$TASK/task.json")"
CODEP="$(cd "$CODE" && pwd -P)"

echo "--- the briefs and dispatch-open name the worktree"
expect "tests-brief exits 0" "$(try "$ROOT/out-tb.txt" "$IMPLEMENT" tests-brief "$TASK" wo2)" "0"
expect "the tests brief carries the worktree" "$(jq -r '.worktree' "$IMPL/brief-wo2-tests.json")" "$WTP"
expect "the worktree is the tests brief's last key" "$(jq -r 'keys_unsorted | last' "$IMPL/brief-wo2-tests.json")" "worktree"
expect "tests-brief prints the worktree" "$(line_of worktree "$ROOT/out-tb.txt")" "$WTP"
must "$IMPLEMENT" build-brief "$TASK" wo1
expect "the build brief carries the worktree" "$(jq -r '.worktree' "$IMPL/brief-wo1-build.json")" "$WTP"
expect "dispatch-open exits 0" "$(try "$ROOT/out-open.txt" "$IMPLEMENT" dispatch-open "$TASK" implementer wo1)" "0"
expect "dispatch-open prints the worktree" \
  "$(grep -c "^DISPATCH-OPEN: the role works in the worktree $WTP\." "$ROOT/out-open.txt")" "1"
expect "and says denied reads hold in the main checkout too" \
  "$(grep -c "resolved against $WTP and against the main checkout $CODEP" "$ROOT/out-open.txt")" "1"

echo "--- an open dispatch: the role in the main checkout"
expect "Bash cat of a denied file, from the main checkout, is refused" \
  "$(hook_answer "$READ_HOOK" "$CODEP" implementer Bash "cat b.php")" "deny"
expect "the reason names the main checkout and the worktree" \
  "$(last_reason_has "main checkout $CODEP.*worktree $WTP")" "1"
expect "Read of the denied file in the main checkout is refused" \
  "$(hook_answer "$READ_HOOK" "$CODEP" implementer Read "$CODEP/b.php")" "deny"
expect "Grep with no path from the main checkout is refused" \
  "$(hook_answer "$READ_HOOK" "$CODEP" implementer Grep "")" "deny"
expect "Read of an owned file in the main checkout is allowed" \
  "$(hook_answer "$READ_HOOK" "$CODEP" implementer Read "$CODEP/a.php")" "allow"
expect "Write in the main checkout is refused" \
  "$(hook_answer "$WRITE_HOOK" "$CODEP" implementer Write "$CODEP/a.php")" "deny"
expect "the reason names the worktree" "$(last_reason_has "Work in the worktree $WTP")" "1"
expect "a Bash redirect in the main checkout is refused" \
  "$(hook_answer "$WRITE_HOOK" "$CODEP" implementer Bash "printf x > a.php")" "deny"
expect "a Bash cd into the worktree, then a redirect, is allowed" \
  "$(hook_answer "$WRITE_HOOK" "$CODEP" implementer Bash "cd $WTP && printf x > a.php")" "allow"
expect "a Bash cd into the worktree, then a denied cat, is refused" \
  "$(hook_answer "$READ_HOOK" "$CODEP" implementer Bash "cd $WTP && cat b.php")" "deny"
expect "the main session writes a file no order froze in the main checkout" \
  "$(hook_answer "$WRITE_HOOK" "$CODEP" "" Write "$CODEP/a.php")" "allow"

echo "--- an open dispatch: the role in the worktree"
expect "Read of the denied file in the worktree is refused, as before" \
  "$(hook_answer "$READ_HOOK" "$WTP" implementer Read "$WTP/b.php")" "deny"
expect "Read of the denied file in the main checkout, from the worktree, is refused" \
  "$(hook_answer "$READ_HOOK" "$WTP" implementer Read "$CODEP/b.php")" "deny"
expect "Read of an owned file in the worktree is allowed" \
  "$(hook_answer "$READ_HOOK" "$WTP" implementer Read "$WTP/a.php")" "allow"
expect "Write of an owned file in the worktree is allowed" \
  "$(hook_answer "$WRITE_HOOK" "$WTP" implementer Write "$WTP/a.php")" "allow"
expect "Write of an unowned file in the worktree is refused, as before" \
  "$(hook_answer "$WRITE_HOOK" "$WTP" implementer Write "$WTP/b.php")" "deny"
expect "Write in the main checkout, from the worktree, is refused" \
  "$(hook_answer "$WRITE_HOOK" "$WTP" implementer Write "$CODEP/a.php")" "deny"
expect "a Bash redirect into the main checkout, from the worktree, is refused" \
  "$(hook_answer "$WRITE_HOOK" "$WTP" implementer Bash "printf x > $CODEP/a.php")" "deny"
expect "cd ~/ into the main checkout, then a redirect, from the worktree, is refused" \
  "$(HOOK_HOME="$ROOT" hook_answer "$WRITE_HOOK" "$WTP" implementer Bash "cd ~/code && printf x > a.php")" "deny"
expect "cd -P into the main checkout, then a redirect, is refused" \
  "$(hook_answer "$WRITE_HOOK" "$WTP" implementer Bash "cd -P $CODEP && printf x > a.php")" "deny"
expect "pushd into the main checkout, then a redirect, is refused" \
  "$(hook_answer "$WRITE_HOOK" "$WTP" implementer Bash "pushd $CODEP && printf x > a.php")" "deny"
expect "pushd -L into the main checkout, then a denied cat, names the main checkout" \
  "$(hook_answer "$READ_HOOK" "$WTP" implementer Bash "pushd -L $CODEP && cat b.php")" "deny"
expect "the reason names the main checkout" "$(last_reason_has "in the main checkout $CODEP. This role works in the task's worktree $WTP: start each shell command with cd $WTP &&")" "1"
expect "another agent type in the main checkout is told the rule was not applied" \
  "$(hook_answer "$WRITE_HOOK" "$CODEP" reviewer Write "$CODEP/a.php")" "not-enforced"

echo "--- an open dispatch: git reads of the main checkout (gap row 243)"
expect "the worktree path starts with the main checkout's path" \
  "$(case "$WTP" in "$CODEP"?*) echo yes ;; *) echo no ;; esac)" "yes"
expect "git show HEAD:<denied>, from the main checkout, is refused" \
  "$(hook_answer "$READ_HOOK" "$CODEP" implementer Bash "git show HEAD:b.php")" "deny"
expect "the reason names the main checkout" "$(last_reason_has "in the main checkout $CODEP. This role works in the task's worktree $WTP")" "1"
expect "git show HEAD:<owned>, from the main checkout, is allowed" \
  "$(hook_answer "$READ_HOOK" "$CODEP" implementer Bash "git show HEAD:a.php")" "allow"
expect "git show HEAD:<denied>, from the worktree, is refused" \
  "$(hook_answer "$READ_HOOK" "$WTP" implementer Bash "git show HEAD:b.php")" "deny"
expect "git show HEAD:<owned>, from the worktree, is allowed" \
  "$(hook_answer "$READ_HOOK" "$WTP" implementer Bash "git show HEAD:a.php")" "allow"
expect "git cat-file -p HEAD:<denied>, from the worktree, is refused" \
  "$(hook_answer "$READ_HOOK" "$WTP" implementer Bash "git cat-file -p HEAD:b.php")" "deny"
expect "git grep, from the worktree, is refused" \
  "$(hook_answer "$READ_HOOK" "$WTP" implementer Bash "git grep function")" "deny"
expect "git grep, from the main checkout, is refused" \
  "$(hook_answer "$READ_HOOK" "$CODEP" implementer Bash "git grep function")" "deny"
expect "git log -p, from the worktree, is allowed" \
  "$(hook_answer "$READ_HOOK" "$WTP" implementer Bash "git log -p")" "allow"
expect "git -C <main checkout> show HEAD:<denied>, from the worktree, is refused" \
  "$(hook_answer "$READ_HOOK" "$WTP" implementer Bash "git -C $CODEP show HEAD:b.php")" "deny"
expect "git -C <worktree> show HEAD:<denied>, from the main checkout, is refused" \
  "$(hook_answer "$READ_HOOK" "$CODEP" implementer Bash "git -C $WTP show HEAD:b.php")" "deny"
expect "git -C <worktree> show HEAD:<owned>, from the main checkout, is allowed" \
  "$(hook_answer "$READ_HOOK" "$CODEP" implementer Bash "git -C $WTP show HEAD:a.php")" "allow"
expect "git --git-dir=<main checkout>/.git show HEAD:<denied> is refused" \
  "$(hook_answer "$READ_HOOK" "$WTP" implementer Bash "git --git-dir=$CODEP/.git show HEAD:b.php")" "deny"
expect "git cat-file -p HEAD:<denied>, from the main checkout, is refused" \
  "$(hook_answer "$READ_HOOK" "$CODEP" implementer Bash "git cat-file -p HEAD:b.php")" "deny"
expect "git diff, from the main checkout, is refused" \
  "$(hook_answer "$READ_HOOK" "$CODEP" implementer Bash "git diff")" "deny"
expect "git diff, from the worktree, is allowed" \
  "$(hook_answer "$READ_HOOK" "$WTP" implementer Bash "git diff")" "allow"
expect "git --work-tree=<main checkout> diff, from the worktree, is refused" \
  "$(hook_answer "$READ_HOOK" "$WTP" implementer Bash "git --work-tree=$CODEP diff")" "deny"
expect "git log -p, from the main checkout, is refused" \
  "$(hook_answer "$READ_HOOK" "$CODEP" implementer Bash "git log -p")" "deny"
expect "git log --oneline, from the main checkout, is allowed" \
  "$(hook_answer "$READ_HOOK" "$CODEP" implementer Bash "git log --oneline")" "allow"
expect "git status, from the main checkout, is allowed" \
  "$(hook_answer "$READ_HOOK" "$CODEP" implementer Bash "git status")" "allow"

echo "--- an open dispatch: copies out of the main checkout (gap row 243)"
expect "cp <main checkout>/<denied> out, from the worktree, is refused" \
  "$(hook_answer "$READ_HOOK" "$WTP" implementer Bash "cp $CODEP/b.php $ROOT/b.php")" "deny"
expect "cp <denied> out, from the main checkout, is refused" \
  "$(hook_answer "$READ_HOOK" "$CODEP" implementer Bash "cp b.php $ROOT/b.php")" "deny"
expect "cp <worktree>/<denied> out is allowed" \
  "$(hook_answer "$READ_HOOK" "$CODEP" implementer Bash "cp $WTP/b.php $ROOT/b.php")" "allow"
expect "cp -r of the main checkout's folder is refused" \
  "$(hook_answer "$READ_HOOK" "$WTP" implementer Bash "cp -r $CODEP $ROOT/copy")" "deny"
expect "cp -t <dir> <main checkout>/<denied> is refused" \
  "$(hook_answer "$READ_HOOK" "$WTP" implementer Bash "cp -t $ROOT $CODEP/b.php")" "deny"
expect "rsync of the main checkout's folder is refused" \
  "$(hook_answer "$READ_HOOK" "$WTP" implementer Bash "rsync -a $CODEP/ $ROOT/copy/")" "deny"
expect "install <main checkout>/<denied> is refused" \
  "$(hook_answer "$READ_HOOK" "$WTP" implementer Bash "install $CODEP/b.php $ROOT/b.php")" "deny"
expect "mv <main checkout>/<denied> out is refused" \
  "$(hook_answer "$READ_HOOK" "$WTP" implementer Bash "mv $CODEP/b.php $ROOT/b.php")" "deny"
expect "tar -czf of the main checkout's denied file, through -C, is refused" \
  "$(hook_answer "$READ_HOOK" "$WTP" implementer Bash "tar -czf $ROOT/s.tgz -C $CODEP b.php")" "deny"
expect "tar czf of the main checkout's folder is refused" \
  "$(hook_answer "$READ_HOOK" "$WTP" implementer Bash "tar czf $ROOT/s.tgz $CODEP")" "deny"
expect "tar -czf of the worktree's folder is allowed" \
  "$(hook_answer "$READ_HOOK" "$WTP" implementer Bash "tar -czf $ROOT/s.tgz $WTP")" "allow"
expect "cp -r of the worktree's folder is allowed" \
  "$(hook_answer "$READ_HOOK" "$CODEP" implementer Bash "cp -r $WTP $ROOT/copy")" "allow"

echo "--- an open dispatch: git and copies writing the main checkout (gap row 243)"
expect "git -C <main checkout> commit, from the worktree, is refused" \
  "$(hook_answer "$WRITE_HOOK" "$WTP" implementer Bash "git -C $CODEP commit -m x")" "deny"
expect "the reason names the worktree" "$(last_reason_has "Work in the worktree $WTP")" "1"
expect "git -C <worktree> commit, from the main checkout, is allowed" \
  "$(hook_answer "$WRITE_HOOK" "$CODEP" implementer Bash "git -C $WTP commit -m x")" "allow"
expect "git commit, from the main checkout, is refused" \
  "$(hook_answer "$WRITE_HOOK" "$CODEP" implementer Bash "git commit -m x")" "deny"
expect "git commit, from the worktree, is allowed" \
  "$(hook_answer "$WRITE_HOOK" "$WTP" implementer Bash "git commit -m x")" "allow"
expect "git --work-tree=<main checkout> checkout -- <owned> is refused" \
  "$(hook_answer "$WRITE_HOOK" "$WTP" implementer Bash "git --work-tree=$CODEP checkout -- a.php")" "deny"
expect "git --git-dir=<main checkout>/.git commit is refused" \
  "$(hook_answer "$WRITE_HOOK" "$WTP" implementer Bash "git --git-dir=$CODEP/.git commit -m x")" "deny"
expect "git status and git -C <worktree> log, from the worktree, are allowed" \
  "$(hook_answer "$WRITE_HOOK" "$WTP" implementer Bash "git status && git -C $WTP log -p")" "allow"
expect "git status, from the main checkout, is allowed" \
  "$(hook_answer "$WRITE_HOOK" "$CODEP" implementer Bash "git status")" "allow"
expect "cp into the main checkout is refused" \
  "$(hook_answer "$WRITE_HOOK" "$WTP" implementer Bash "cp $ROOT/x $CODEP/a.php")" "deny"
expect "cp -t <main checkout> is refused" \
  "$(hook_answer "$WRITE_HOOK" "$WTP" implementer Bash "cp -t $CODEP $ROOT/x")" "deny"
expect "cp -t <worktree> <unowned source>, from the worktree, is allowed" \
  "$(hook_answer "$WRITE_HOOK" "$WTP" implementer Bash "cp -t $WTP b.php")" "allow"
expect "cp into the worktree's owned file is allowed" \
  "$(hook_answer "$WRITE_HOOK" "$CODEP" implementer Bash "cp $ROOT/x $WTP/a.php")" "allow"
expect "rsync into the main checkout is refused" \
  "$(hook_answer "$WRITE_HOOK" "$WTP" implementer Bash "rsync -a $ROOT/x/ $CODEP/")" "deny"
expect "mv out of the main checkout removes its source, and is refused" \
  "$(hook_answer "$WRITE_HOOK" "$WTP" implementer Bash "mv $CODEP/a.php $ROOT/a.php")" "deny"
expect "tar -xzf -C <main checkout> is refused" \
  "$(hook_answer "$WRITE_HOOK" "$WTP" implementer Bash "tar -xzf $ROOT/s.tgz -C $CODEP")" "deny"
expect "tar xzf, from the main checkout, is refused" \
  "$(hook_answer "$WRITE_HOOK" "$CODEP" implementer Bash "tar xzf $ROOT/s.tgz")" "deny"
expect "tar -czf into the main checkout is refused" \
  "$(hook_answer "$WRITE_HOOK" "$WTP" implementer Bash "tar -czf $CODEP/s.tgz a.php")" "deny"
expect "tar -xzf -C <outside both trees>, from the worktree, is allowed" \
  "$(hook_answer "$WRITE_HOOK" "$WTP" implementer Bash "tar -xzf $ROOT/s.tgz -C $ROOT/out")" "allow"

printf 'Stop: none\nDeviation: none\n' >"$(jq -r .reportPath "$IMPL/brief-wo1-build.json")"
must "$IMPLEMENT" dispatch-close "$TASK"

echo "--- a record naming aida:implementer matches that type whole"
must "$IMPLEMENT" dispatch-open "$TASK" aida:implementer wo1
expect "aida:implementer in the main checkout is refused a write" \
  "$(hook_answer "$WRITE_HOOK" "$CODEP" aida:implementer Write "$CODEP/a.php")" "deny"
expect "implementer, bare, in the main checkout is refused a write" \
  "$(hook_answer "$WRITE_HOOK" "$CODEP" implementer Write "$CODEP/a.php")" "deny"
expect "other:implementer in the main checkout is told the rule was not applied" \
  "$(hook_answer "$WRITE_HOOK" "$CODEP" other:implementer Write "$CODEP/a.php")" "not-enforced"
expect "other:implementer is not refused the denied read there" \
  "$(hook_answer "$READ_HOOK" "$CODEP" other:implementer Read "$CODEP/b.php")" "not-enforced"
printf 'Stop: none\nDeviation: none\n' >"$(jq -r .reportPath "$IMPL/brief-wo1-build.json")"
must "$IMPLEMENT" dispatch-close "$TASK"

echo "--- no open dispatch: everything is allowed"
expect "the record is gone" "$([ -e "$IMPL/dispatch.json" ] && echo yes || echo no)" "no"
expect "Bash cat in the main checkout is allowed" \
  "$(hook_answer "$READ_HOOK" "$CODEP" implementer Bash "cat b.php")" "allow"
expect "Read in the main checkout is allowed" \
  "$(hook_answer "$READ_HOOK" "$CODEP" implementer Read "$CODEP/b.php")" "allow"
expect "Write in the main checkout is allowed" \
  "$(hook_answer "$WRITE_HOOK" "$CODEP" implementer Write "$CODEP/a.php")" "allow"
expect "a Bash redirect in the main checkout is allowed" \
  "$(hook_answer "$WRITE_HOOK" "$CODEP" implementer Bash "printf x > a.php")" "allow"
expect "git show HEAD:<denied> in the main checkout is allowed" \
  "$(hook_answer "$READ_HOOK" "$CODEP" implementer Bash "git show HEAD:b.php")" "allow"
expect "git -C <main checkout> commit is allowed" \
  "$(hook_answer "$WRITE_HOOK" "$WTP" implementer Bash "git -C $CODEP commit -m x")" "allow"

echo "--- the review, fix and verify briefs name the worktree"
build_order wo1 a.php
must "$IMPLEMENT" review-brief "$TASK" wo1
expect "the review brief carries the worktree" "$(jq -r '.worktree' "$IMPL/brief-wo1-review.json")" "$WTP"
printf '{ "findings": %s }\n' '[{"id":"f1","severity":"high","file":"a.php","lines":"1","linkedTo":"c1","evidence":"wrong start","fixScope":["a.php"]}]' \
  >"$ROOT/findings-wo1.json"
must "$IMPLEMENT" review-record "$TASK" wo1 --findings "$ROOT/findings-wo1.json"
expect "fix-brief exits 0" "$(try "$ROOT/out-fix.txt" "$IMPLEMENT" fix-brief "$TASK" wo1)" "0"
expect "the fix brief carries the worktree" "$(jq -r '.worktree' "$IMPL/brief-wo1-fix-1.json")" "$WTP"
expect "fix-brief prints the worktree" "$(line_of worktree "$ROOT/out-fix.txt")" "$WTP"
FROM="$(git -C "$WT" rev-parse HEAD)"
commit_change a.php "wo1 fixed"
printf 'fixed\n' >"$(fix_report wo1)"
must "$IMPLEMENT" fix-record "$TASK" wo1 --report "$(fix_report wo1)" --started-at "$FROM" \
  --test-recipe "fake=$RECIPES/test-execution.md"
must "$IMPLEMENT" verify-brief "$TASK" wo1
expect "the verify brief carries the worktree" "$(jq -r '.worktree' "$IMPL/brief-wo1-verify-1.json")" "$WTP"

printf 'passed %s of %s\n' "$PASS" "$TOTAL"
[ "$PASS" -eq "$TOTAL" ]
