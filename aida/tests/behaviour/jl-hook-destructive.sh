#!/usr/bin/env bash
# Fixture jl: hooks/deny-destructive-commands.sh gives one verdict on one command,
# every run (gap row 321). Its match helper piped printf into `grep -q` under pipefail, so on a
# long text a real match could read as no match by timing alone. And the rules read comments, so a
# backticked `git status` in a script comment read as a verb the hook cannot read.
#   race    each command runs RUNS times (default 20) and every verdict must match: a force push
#           before 200 KiB of text, a `gh api` POST on one long line, and `bash <script>` for the
#           two plugin scripts whose verdict flipped (implement-actions.sh, recipes.sh).
#   allow   a comment that holds a backticked git verb.
#   refuse  a real refused command beside a `#` the shell does not read as a comment: in a
#           `$'...'` string, in a backtick pair, in `${...}`, mid-word, in quotes, at the start of a
#           continued line, after a comment that ends with a backslash, and the four cases of the
#           fix round's check.
# Runs under bash 3.2 and zsh, from $HOME, with CLAUDE_PLUGIN_ROOT unset.
PLUGIN="${PLUGIN:-$(cd "$(dirname "$0")/../.." && pwd)}"
RUNS="${RUNS:-20}"
set -u

PASS=0; TOTAL=0
# expect <what> <actual> <wanted>: prints ok or BAD with both values, and counts.
expect() {
  TOTAL=$((TOTAL + 1))
  if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); printf 'ok: %s\n' "$1"
  else printf 'BAD: %s\n  actual: %s\n  wanted: %s\n' "$1" "$2" "$3"; fi
}

ROOT="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$ROOT"' EXIT
HOOK="$PLUGIN/hooks/deny-destructive-commands.sh"

# decide <command>: prints refuse or allow.
decide() {
  local out
  out="$(jq -nc --arg c "$1" --arg d "$PLUGIN" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' \
    | (cd "$HOME" && env -u AIDA_ALLOW_DANGEROUS -u CLAUDE_PLUGIN_ROOT bash "$HOOK" 2>/dev/null) \
    | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
  [ "$out" = deny ] && echo refuse || echo allow
}

# tally <command>: prints "refuse N allow M" over RUNS runs.
tally() {
  local k=0 r=0 a=0
  while [ "$k" -lt "$RUNS" ]; do
    if [ "$(decide "$1")" = refuse ]; then r=$((r + 1)); else a=$((a + 1)); fi
    k=$((k + 1))
  done
  printf 'refuse %s allow %s' "$r" "$a"
}

# A command line holds at most 128 KiB, so the long texts are files the command runs.
{ echo 'git push --force'; awk 'BEGIN { for (i = 0; i < 6000; i++) print "echo filler line " i " of text" }'; } >"$ROOT/push.sh"
{ printf 'gh api repos/o/r/git/refs -X POST'; awk 'BEGIN { for (i = 0; i < 12000; i++) printf " filler%s", i; print "" }'; } >"$ROOT/api.sh"
expect "race: a force push before 200 KiB of text" "$(tally "bash $ROOT/push.sh")" "refuse $RUNS allow 0"
expect "race: a gh api POST on one long line" "$(tally "bash $ROOT/api.sh")" "refuse $RUNS allow 0"
expect "race: bash implement-actions.sh" "$(tally "bash $PLUGIN/skills/implement/scripts/implement-actions.sh")" "refuse 0 allow $RUNS"
expect "race: bash recipes.sh" "$(tally "bash $PLUGIN/scripts/lib/recipes.sh")" "refuse 0 allow $RUNS"

expect "allow: a backticked git verb in a comment" "$(decide 'echo ok # see `git status` and `git rev-parse`')" allow
expect "allow: a whole-line comment" "$(decide '# the `git rev-parse` value
echo ok')" allow
SCRIPT="$ROOT/notes.sh"
printf '#!/usr/bin/env bash\n# reads `git status`, then `git rev-parse`\necho ok\n' >"$SCRIPT"
expect "allow: a script whose comments name git verbs" "$(decide "bash $SCRIPT")" allow

expect "refuse: a substitution in the verb" "$(decide 'git pu`echo sh`')" refuse
expect "refuse: a hash inside \$'...'" "$(decide "echo \$'a\\' #'; git push --force")" refuse
expect "refuse: a hash inside a backtick pair" "$(decide 'x=`echo a # b` ; git push --force')" refuse
expect "refuse: a hash inside \${...}" "$(decide 'y=${z:- #}; git push --force')" refuse
expect "refuse: a hash mid-word" "$(decide 'echo a#b; git push --force')" refuse
expect "refuse: a hash in double quotes" "$(decide 'echo "a # b"; git push --force')" refuse
expect "refuse: a hash at the start of a continued line" "$(decide 'echo a\
#b; git push --force')" refuse
expect "refuse: a comment that ends with a backslash" "$(decide 'echo a # x \
git push --force')" refuse
expect "refuse: a backtick pair across lines" "$(decide 'x=`echo a
# b` ; git push --force')" refuse
expect "refuse: a \$'...' string across lines" "$(decide "x=\$'a\\'
#'; git push --force")" refuse
# A fresh check's cases (fix round): the comment reader takes code for a comment, so the rules
# other than the unreadable verb read the comments too.
expect "refuse: a hash in double quotes in backticks" "$(decide 'echo "`echo " #"`"; git push --force')" refuse
expect "refuse: a hash after a subshell in \$(...)" "$(decide 'echo "$( (echo a); echo " #" )"; git push --force')" refuse
expect "refuse: a quote after a shift read as a heredoc" "$(decide "echo \$((1<<2))
echo 'x
2
# ' ; git push --force")" refuse
expect "refuse: a hash after a nested brace in \${...}" "$(decide 'echo ${x:-{a} #}; git push --force')" refuse
printf '#!/usr/bin/env bash\n# a comment\ngit reset --hard\n' >"$ROOT/bad.sh"
expect "refuse: a script with a hard reset under a comment" "$(decide "bash $ROOT/bad.sh")" refuse

printf 'passed %s of %s\n' "$PASS" "$TOTAL"
[ "$PASS" = "$TOTAL" ]
