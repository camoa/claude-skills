#!/usr/bin/env bash
# Fixture mq: the owned-files write guard reads only the places a write lands
# (gap row 407, dev_guides_site item 44). On 6.0.19 the Bash door of deny-frozen-test-writes.sh
# read a `sed` script, a `dirname` argument and a variable's name as write paths under the
# worktree, and resolved a relative redirect after `cd <task folder>` against the worktree too. The
# rows:
#   replay   content-loss-repair's wo2 implementer, wo3 round-two fixer and wo1 round-one fixer,
#            records built from briefs that hold only the fields this fixture reads. Five
#            refused live commands, one a sed script holding `;`, from a notes folder: allowed.
#   still    real writes outside the owned files, through `>`, `>>`, `sed -i`, cp, tee, a known
#            variable, an unknown one, a reassigned one, `$(dirname ...)`, and after a quoted
#            `;`: refused. A frozen
#            test through `sed -i`: refused. `sed -E -i -e`, which 6.0.19 never judged: refused.
#            Rule one still reads the codePath resolution after any cd. A cd in a subshell, popd
#            and `cd -` leave the directory unknown. A name set again by for, if, declare, read or
#            +=, a sed w command, an env prefix, a glued redirect, `>|` and `dd of=`: refused.
#   allowed  `sed -i` and `mkdir -p "$(dirname ...)"` of the owned file, with `2>&1 | head` or
#            `>/dev/null` after it; rm and cp with `2>/dev/null`; `awk '$1>5'`: allowed.
# Runs under bash 3.2 and zsh, from $HOME, with CLAUDE_PLUGIN_ROOT unset.
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
ROOT="$(cd "$ROOT" && pwd -P)"
export AIDA_REGISTRY_PATH="$ROOT/aida/registry.json"
export AIDA_PROJECTS_HOME="$ROOT/aida/projects"
export AIDA_SETTINGS_PATH="$ROOT/aida/settings.json"
LOG="$ROOT/log.txt"
SH=bash; [ -n "${ZSH_VERSION:-}" ] && SH=zsh
WRITE_HOOK="$PLUGIN/hooks/deny-frozen-test-writes.sh"

CODE="$ROOT/dev-guides-site"
WT="$ROOT/dev-guides-site.worktrees/dev-guides-site-content-loss-repair"
PROJ="$ROOT/aida/projects/dev_guides_site"
TASK="$PROJ/tasks/content-loss-repair"
IMPL="$TASK/implementation"
NOTES="$ROOT/claude_code_projects/dev-guides-drupal"
mkdir -p "$CODE" "$WT/scripts/api" "$WT/tests" "$IMPL" "$TASK/deliverables" "$NOTES"

# The three briefs, cut to the worktree and the owned files or fix scope the records are built from.
jq -n --arg wt "$WT" '{worktree: $wt, unit: {ownedFiles: ["scripts/api/propose_loss_repair.py"]}}' >"$IMPL/brief-wo2-build.json"
jq -n --arg wt "$WT" --arg t "$TASK" '{worktree: $wt, fixScope: [($t + "/deliverables/content-loss-repair-listing.md")]}' \
  >"$IMPL/brief-wo3-fix-2.json"
jq -n --arg wt "$WT" '{worktree: $wt, fixScope: ["scripts/api/content_loss.py"]}' >"$IMPL/brief-wo1-fix-1.json"
jq -nc --arg c "$CODE" '{codePath: $c}' >"$PROJ/project.json"
jq -nc --arg c "$CODE" --arg p "$PROJ" \
  '{version: 1, projects: [{codePath: $c, path: $p, name: "dev_guides_site", lastAccessed: "2026-10-23", state: "active"}],
    declinedOffers: [], directoryChoices: []}' >"$AIDA_REGISTRY_PATH"
# wo1's frozen test, so rule one is on for every row.
printf '%s\n' '{"rows":[{"tests":[{"path":"tests/test_loss.py"}]}]}' >"$IMPL/tests-wo1.json"

# open_record <role> <unit> <owned files as a JSON array>: the one open dispatch record, codePath
# the worktree the briefs name.
open_record() {
  jq -nc --arg r "aida:$1" --arg u "$2" --argjson o "$3" --arg c "$(jq -r .worktree "$IMPL/brief-wo2-build.json")" \
    '{schemaVersion: 1, role: $r, task: "content-loss-repair", unit: $u, codePath: $c,
      openedAt: "2026-10-23T00:00:00Z", denyRead: [], allowWrite: [], ownedFiles: $o}' >"$IMPL/dispatch.json"
}
# answer <role> <cwd> <command>: deny, not-enforced, allow (a bare {} or nothing), or the text.
answer() {
  local out
  out="$(jq -nc --arg a "aida:$1" --arg c "$2" --arg k "$3" '{tool_name: "Bash", agent_type: $a, cwd: $c, tool_input: {command: $k}}' \
    | env -u CLAUDE_PLUGIN_ROOT "$SH" "$WRITE_HOOK" 2>>"$LOG")"
  printf '%s\n' "$out" >>"$LOG"
  case "$out" in
    *'"permissionDecision":"deny"'*) printf 'deny' ;;
    *'"systemMessage"'*) printf 'not-enforced' ;;
    '{}'|'') printf 'allow' ;;
    *) printf '%s' "$out" ;;
  esac
}
# live <template>: the live command with its paths put back as this fixture's folders.
live() {
  printf '%s' "$1" | sed -e "s#@WT@#$WT#g" -e "s#@PROJ@#$PROJ#g" -e "s#@IMPL@#$IMPL#g"
}

# ---- replay -----------------------------------------------------------------------------------
open_record fixer wo3 "$(jq -c .fixScope "$IMPL/brief-wo3-fix-2.json")"
expect "replay: the wo3 fixer's scope is the listing in the task folder" \
  "$(jq -r '.ownedFiles[0]' "$IMPL/dispatch.json")" "$TASK/deliverables/content-loss-repair-listing.md"
CMD_SED="$(live "cat > @IMPL@/answers-wo3-fix2.md <<'EOF'
# wo3 fix round 2 answers
5. Files and blocks: line 37 only.
EOF
F=@PROJ@/tasks/content-loss-repair/deliverables/content-loss-repair-listing.md
sed -i \"37s#open('proposal-state.json')#open('@PROJ@/tasks/content-loss-repair/deliverables/proposal-state.json')#\" \$F
git -C @PROJ@ diff --stat -- \$F; sed -n 37p \$F")"
expect "replay: the wo3 fixer's sed -i on the listing is allowed" "$(answer fixer "$NOTES" "$CMD_SED")" "allow"

open_record implementer wo2 "$(jq -c .unit.ownedFiles "$IMPL/brief-wo2-build.json")"
CMD_DIRNAME="$(live "cd @WT@ && set -a && . keys/agent-client.env && set +a && B=https://dev-guides-site-content-loss-repair.ddev.site; SF=@PROJ@/tasks/content-loss-repair/deliverables/proposal-state.json; mkdir -p \$(dirname \$SF)
Q=\"select (select count(*) from node_revision)\"
echo before; ddev drush sqlq \"\$Q\" 2>&1|tail -1
python3 scripts/api/propose_loss_repair.py js/passkeys --base-url \$B --insecure --state-file \$SF; echo exit \$?
python3 scripts/api/propose_loss_repair.py js/passkeys --base-url \$B --insecure --state-file \$SF >/dev/null; echo after3")"
expect "replay: the wo2 implementer's mkdir -p \$(dirname \$SF) is allowed" "$(answer implementer "$NOTES" "$CMD_DIRNAME")" "allow"
SED_SCRIPT="'s/^def survives(api, row, replaced):/def survives(api, row):/; s/survives(api, row, due)/survives(api, row)/'"
expect "replay: the wo2 implementer's sed -i with a ; in its script is allowed" \
  "$(answer implementer "$NOTES" "cd $WT && git show 9d1f357:scripts/api/propose_loss_repair.py > scripts/api/propose_loss_repair.py && sed -i $SED_SCRIPT scripts/api/propose_loss_repair.py")" "allow"
CMD_INTERFACE="$(live "cd @IMPL@ && cat > interface-wo2.md <<'E'
# Interface of wo2

\`scripts/api/propose_loss_repair.py\` is a command and a module.
E")"
expect "replay: the wo2 implementer's heredoc into its interface record is allowed" \
  "$(answer implementer "$NOTES" "$CMD_INTERFACE")" "allow"

open_record fixer wo1 "$(jq -c .fixScope "$IMPL/brief-wo1-fix-1.json")"
CMD_ANSWERS="$(live "cd @WT@/scripts/api; python3 -I - <<'EOF'
import sys; sys.path.insert(0,'.')
EOF
cd ../..; git add -A; git commit -qm \"content-loss-repair wo1 fix round 1: f1 f2

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>\"; git log --oneline | head -1
cd @IMPL@; cat >> answers-wo1-fix1.md <<'EOF'

Report: complete
EOF")"
expect "replay: the wo1 fixer's append to its answers file is allowed" "$(answer fixer "$NOTES" "$CMD_ANSWERS")" "allow"

# ---- still: real writes outside the owned files ------------------------------------------------
open_record implementer wo2 "$(jq -c .unit.ownedFiles "$IMPL/brief-wo2-build.json")"
OTHER=scripts/api/content_loss.py
OWN=scripts/api/propose_loss_repair.py
for c in "echo x > $OTHER" "echo x >> $OTHER" "sed -i 's/a/b/' $OTHER" "sed -i \"s/a b/c d/\" $OTHER" \
         "sed -E -i -e 's/a/b/' $OTHER" "sed --in-place=.bak --expression='s/a/b/' $OTHER" \
         "cp /tmp/x $OTHER" "tee $OTHER < /dev/null" "F=$OTHER; printf x > \$F" "printf x > \$UNSET/x.py" \
         "F=scripts/api/propose_loss_repair.py; F=$OTHER; printf x >> \$F" "mkdir -p \"\$(dirname scripts/other/x.py)\"" \
         "sed -i 's/a/b/' tests/test_loss.py" "sed -i $SED_SCRIPT $OTHER" "echo \"a; b\"; echo x > $OTHER" \
         "(cd /tmp && ls) && echo x > tests/test_loss.py" "pushd /tmp && popd && echo x > tests/test_loss.py" \
         "cd /tmp; cd -; echo x > $OTHER" "cd $IMPL && echo x > tests/test_loss.py" \
         "F=$OWN; for F in $OTHER; do printf x > \$F; done" "F=$OWN; if true; then F=$OTHER; fi; printf x > \$F" \
         "F=$OWN; declare F=$OTHER; printf x > \$F" "F=$OWN; read F <<<x; printf x > \$F" "F=$OWN; F+=.bak; printf x > \$F" \
         "sed -i 's/a/b/w scripts/x' $OWN" "sed -n '1w scripts/x' $OWN" "LC_ALL=C sed -i 's/a/b/' $OTHER" \
         "echo x>$OTHER" "echo x>>$OTHER" "echo x >| $OTHER" "dd if=/dev/zero of=$OTHER count=1"; do
  expect "still: cd <worktree> && $c is refused" "$(answer implementer "$NOTES" "cd $WT && $c")" "deny"
done
expect "still: echo x > $OTHER from the worktree, no cd, is refused" "$(answer implementer "$WT" "echo x > $OTHER")" "deny"
expect "still: an absolute redirect into the worktree after cd <task folder> is refused" \
  "$(answer implementer "$NOTES" "cd $IMPL && cat > $WT/$OTHER <<'E'
x
E")" "deny"
expect "still: the refusal names the file and the token it was read from" \
  "$(tail -1 "$LOG" | grep -c "$WT/$OTHER (read from the token '$WT/$OTHER' after '>')" | tr -d ' ')" "1"

# ---- allowed ------------------------------------------------------------------------------------
for c in "sed -i 's/a/b/' $OWN 2>&1 | head" "sed -i 's/a/b/' $OWN >/dev/null" "rm -f /tmp/mq-x 2>/dev/null" \
         "cp /tmp/x $OWN 2>/dev/null" "awk '\$1>5' $OWN" "echo \"a>b\""; do
  expect "allowed: cd <worktree> && $c" "$(answer implementer "$NOTES" "cd $WT && $c")" "allow"
done
expect "allowed: sed -i of the owned file" "$(answer implementer "$NOTES" "cd $WT && sed -i 's/a b/c/' $OWN")" "allow"
expect "allowed: mkdir -p \"\$(dirname <owned file>)\"" \
  "$(answer implementer "$NOTES" "cd $WT && F=$OWN && mkdir -p \"\$(dirname \"\$F\")\" && printf x > \$F")" "allow"

printf 'passed %s of %s\n' "$PASS" "$TOTAL"
[ "$PASS" -eq "$TOTAL" ]
