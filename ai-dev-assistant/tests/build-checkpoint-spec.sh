#!/usr/bin/env bash
# build-checkpoint-spec.sh — a boundary you can diff must cost the repository nothing.
#
# The defect this defends against is not "the checkpoint is wrong". It is "the checkpoint
# was taken and the person's repository is no longer the way they left it". Per-component
# critique needs a `<before>..<after>` range for work that has not been committed, and the
# obvious ways to manufacture one all take something from the owner of the repo: a real
# commit moves HEAD and writes into their branch, `git stash` unwinds their working tree,
# and staging into the real index quietly consumes the staging they had deliberately built
# for a commit they were about to write. Any of those is a gate overstepping. A build tool
# that costs someone their staged work has done more damage than the critique was worth.
#
# So the property asserted hardest here is invisibility. Around every capture: HEAD does not
# move, the staged set is neither consumed nor extended, `git status --porcelain` comes back
# byte-identical, no branch appears, no stash appears, and the reachable history does not
# grow. Those run against a repo deliberately holding all five states at once — a committed
# file, a tracked-and-modified file, a file the USER staged, an untracked file, and an
# ignored file — because a mechanism that disturbs a repository usually disturbs exactly one
# of those and leaves the rest looking fine.
#
# The second defect is the mirror image: a checkpoint so careful it captures nothing useful.
# A new module is entirely untracked until someone stages it, so a checkpoint restricted to
# tracked files hands the critic an empty diff for the component most worth critiquing. The
# range assertions below therefore require a NEWLY CREATED UNTRACKED file to show up as an
# addition, and require the ignored file never to.
#
# Third: labels become ref names. `../escape`, a leading dot, a leading hyphen and an
# embedded space all have to be refused before git is asked, with nothing left behind. The
# assertion that matters there is not the exit code of any one label, though: it is that
# after every rejection the set of refs OUTSIDE the checkpoint namespace is the one the repo
# started with. `../escape` alone passed against a script whose separator ban had been
# removed, because the leading-dot rule caught it first and the character class was never
# consulted — an assertion that named a property it did not test.
#
# Fourth: two checkouts of one repository must not share a namespace. Every prefix under
# `refs/` except `refs/worktree/` is one store shared by every worktree, so a bare
# `refs/aida/...` had a linked worktree overwriting the main checkout's `main.before` and a
# `clear` from either emptying the other's. That is reproduced here with a real
# `git worktree add` rather than two clones, because two clones would pass under either
# namespace and prove nothing.
#
# Fifth, and the shape the rest of the file shares: a report that cannot be wrong about
# itself. `clear` naming refs it failed to delete, `head_unchanged` naming a comparison
# nobody performed, and `untracked[]` handing back git's quoted rendering instead of paths
# are all the same defect — an output that reads as evidence and is not.

set -eu
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="${PLUGIN_ROOT}/scripts/build-checkpoint.sh"

FAIL=0
fail_check() { printf 'FAIL: %s\n' "$1" >&2; FAIL=1; }
pass_check() { printf 'OK   %s\n' "$1"; }
# A check that could not be set up is neither a pass nor a failure, and it must not vanish
# quietly: an assertion that disappears without saying so is how a suite reports a smaller
# green than it looks. Two checks below stage a permission failure, which cannot be staged
# at all when the process ignores permission bits (running as root), so they say so.
skip_check() { printf 'SKIP %s\n' "$1"; printf 'SKIP %s\n' "$1" >&2; }
[ -f "$S" ] || { printf 'FAIL: %s missing\n' "$S" >&2; exit 1; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
NS="refs/worktree/aida/build-checkpoints"

# Run the script without letting a non-zero exit kill the spec, capturing stdout and rc.
run() { set +e; OUT=$(bash "$S" "$@" 2>/dev/null); RC=$?; set -e; }
rc_of() { set +e; bash "$S" "$@" >/dev/null 2>&1; RC=$?; set -e; }

# ------------------------------------------------------------------- the fixture repo
#
# Five states at once, so a mechanism that disturbs one of them cannot hide behind the
# other four looking untouched.

R="$T/repo"
mkdir -p "$R"
git -C "$R" init -q >/dev/null 2>&1
git -C "$R" config user.email spec@example.invalid
git -C "$R" config user.name "Spec Runner"
git -C "$R" config commit.gpgsign false
printf 'v1\n'          > "$R/tracked.txt"
printf 'ignored.txt\n' > "$R/.gitignore"
git -C "$R" add tracked.txt .gitignore
git -C "$R" commit -qm "initial" >/dev/null 2>&1

printf 'v2-working\n'  > "$R/tracked.txt"                       # tracked, modified, unstaged
printf 'staged body\n' > "$R/staged.txt"; git -C "$R" add staged.txt   # the USER's staging
printf 'untracked\n'   > "$R/untracked.txt"                     # untracked
printf 'secret\n'      > "$R/ignored.txt"                       # ignored

snap_head()     { git -C "$R" rev-parse --verify HEAD 2>/dev/null || printf 'unborn\n'; }
snap_staged()   { git -C "$R" diff --cached --name-status 2>/dev/null | sort; }
snap_status()   { git -C "$R" status --porcelain 2>/dev/null; }
snap_branches() { git -C "$R" branch --list 2>/dev/null | wc -l | tr -d ' '; }
snap_stash()    { git -C "$R" stash list 2>/dev/null | wc -l | tr -d ' '; }
snap_log()      { git -C "$R" rev-list --count HEAD 2>/dev/null || printf '0\n'; }

B_HEAD=$(snap_head); B_STAGED=$(snap_staged); B_STATUS=$(snap_status)
B_BRANCH=$(snap_branches); B_STASH=$(snap_stash); B_LOG=$(snap_log)

# Guard the fixture itself: if the user's staging were empty to begin with, "staging was not
# consumed" would pass against a script that consumed everything.
[ -n "$B_STAGED" ] \
  && pass_check "fixture: the repo really does hold a deliberately staged file to protect" \
  || fail_check "fixture is broken — nothing is staged, so the staging assertions prove nothing"

# --------------------------------------------------------------------------- capture one

run capture --repo "$R" --label before
CAP1="$OUT"
printf '%s' "$CAP1" | jq -e . >/dev/null 2>&1 \
  && pass_check "capture prints valid JSON" \
  || fail_check "capture output is not valid JSON: $CAP1"
SHA1=$(printf '%s' "$CAP1" | jq -r '.sha // ""')
TREE1=$(printf '%s' "$CAP1" | jq -r '.tree // ""')
# The tree is the thing the commit object wraps, and a caller that wants to compare two
# checkpoints for "did anything actually change" compares trees, not shas.
printf '%s' "$SHA1" | grep -Eq '^[0-9a-f]{40}$' \
  && pass_check "capture reports a real commit sha" \
  || fail_check "capture reported \"$SHA1\", not a 40-character object name"
printf '%s' "$TREE1" | grep -Eq '^[0-9a-f]{40}$' \
  && pass_check "capture reports the tree it wrapped" \
  || fail_check "capture reported tree \"$TREE1\", not a 40-character object name"

[ "$(snap_head)" = "$B_HEAD" ] \
  && pass_check "HEAD is exactly where it was before the capture" \
  || fail_check "HEAD moved: $B_HEAD -> $(snap_head)"
[ "$(snap_staged)" = "$B_STAGED" ] \
  && pass_check "the user's staged set is neither consumed nor extended" \
  || fail_check "the staged set changed. before: [$B_STAGED] after: [$(snap_staged)]"
[ "$(snap_status)" = "$B_STATUS" ] \
  && pass_check "git status --porcelain comes back byte-identical" \
  || fail_check "the working tree changed under the capture"
[ "$(snap_branches)" = "$B_BRANCH" ] \
  && pass_check "no branch appeared" \
  || fail_check "branch count went $B_BRANCH -> $(snap_branches)"
[ "$(snap_stash)" = "0" ] && [ "$B_STASH" = "0" ] \
  && pass_check "git stash list is still empty — the tree was never unwound to read it" \
  || fail_check "a stash entry appeared: $(snap_stash)"
[ "$(snap_log)" = "$B_LOG" ] \
  && pass_check "the reachable history did not grow — the checkpoint commit is off-branch" \
  || fail_check "rev-list --count HEAD went $B_LOG -> $(snap_log)"

# The commit object is real, and anchored where the header says it is.
git -C "$R" cat-file -e "$SHA1^{commit}" 2>/dev/null \
  && pass_check "the reported sha is a real commit object in the repo" \
  || fail_check "the reported sha is not a commit object: $SHA1"
[ "$(git -C "$R" rev-parse --verify "$NS/before" 2>/dev/null || true)" = "$SHA1" ] \
  && pass_check "the checkpoint is anchored under $NS/<label> so gc cannot take it" \
  || fail_check "$NS/before does not point at the reported sha"
[ "$(printf '%s' "$CAP1" | jq -r '.head_unchanged')" = "$B_HEAD" ] \
  && pass_check "head_unchanged reports the HEAD the repo actually still has" \
  || fail_check "head_unchanged is $(printf '%s' "$CAP1" | jq -r '.head_unchanged'), HEAD is $B_HEAD"

# ------------------------------------------------------- what the boundary actually holds

git -C "$R" diff --name-only "$B_HEAD".."$SHA1" 2>/dev/null | grep -qx 'untracked.txt' \
  && pass_check "an untracked file is inside the checkpoint — a new component is not skipped" \
  || fail_check "untracked.txt is missing from HEAD..checkpoint; untracked work was dropped"
git -C "$R" ls-tree -r --name-only "$SHA1" 2>/dev/null | grep -qx 'ignored.txt' \
  && fail_check "the .gitignore'd file was swept into the checkpoint tree" \
  || pass_check "the ignored file is not in the checkpoint tree"
git -C "$R" diff --name-only "$B_HEAD".."$SHA1" 2>/dev/null | grep -qx 'ignored.txt' \
  && fail_check "the ignored file shows up in the checkpoint diff" \
  || pass_check "the ignored file never appears in the checkpoint diff"

[ "$(printf '%s' "$CAP1" | jq -r '.untracked | sort | join(",")')" = "untracked.txt" ] \
  && pass_check "untracked[] names exactly what rode along" \
  || fail_check "untracked[] is [$(printf '%s' "$CAP1" | jq -r '.untracked | join(",")')], expected [untracked.txt]"
printf '%s' "$CAP1" | jq -e '.untracked_count == (.untracked | length)' >/dev/null 2>&1 \
  && pass_check "untracked_count agrees with the length of untracked[]" \
  || fail_check "untracked_count is $(printf '%s' "$CAP1" | jq -r '.untracked_count') but untracked[] holds $(printf '%s' "$CAP1" | jq -r '.untracked | length')"

# ---------------------------------------------------------- the range across two captures
#
# Between the two captures a component is created that has never been in the index. That is
# the case per-component critique exists for, and the one a tracked-files-only checkpoint
# reports as an empty diff.

printf 'v3-working\n' > "$R/tracked.txt"
mkdir -p "$R/newmodule"
printf '<?php // new component\n' > "$R/newmodule/service.php"
printf 'secret changed\n' > "$R/ignored.txt"

C_HEAD=$(snap_head); C_STAGED=$(snap_staged); C_STATUS=$(snap_status)

run capture --repo "$R" --label after
CAP2="$OUT"
SHA2=$(printf '%s' "$CAP2" | jq -r '.sha // ""')

[ "$(snap_head)" = "$C_HEAD" ] \
  && pass_check "HEAD still unmoved after a capture that swept in a brand-new directory" \
  || fail_check "HEAD moved during the second capture"
[ "$(snap_staged)" = "$C_STAGED" ] \
  && pass_check "the staged set survived the second capture too" \
  || fail_check "the second capture disturbed the staged set"
[ "$(snap_status)" = "$C_STATUS" ] \
  && pass_check "git status --porcelain is byte-identical across the second capture" \
  || fail_check "the second capture changed the working tree"

RANGE=$(git -C "$R" diff --name-status "$SHA1".."$SHA2" 2>/dev/null | tr '\t' ' ' | sort | tr '\n' '|')
[ "$RANGE" = "A newmodule/service.php|M tracked.txt|" ] \
  && pass_check "before..after is exactly the modified file plus the new untracked component" \
  || fail_check "before..after reported [$RANGE], expected [A newmodule/service.php|M tracked.txt|]"
printf '%s' "$RANGE" | grep -q 'ignored.txt' \
  && fail_check "a change to the ignored file leaked into the range" \
  || pass_check "changing the ignored file produces nothing in the range"

# ------------------------------------------------------------------------- determinism
#
# Same tree, same tree object. Different label, different commit — so a caller cannot
# confuse two boundaries for each other, and cannot confuse one for two.

run capture --repo "$R" --label det_a
DA="$OUT"
run capture --repo "$R" --label det_b
DB="$OUT"
[ "$(printf '%s' "$DA" | jq -r '.tree')" = "$(printf '%s' "$DB" | jq -r '.tree')" ] \
  && pass_check "two captures of an identical tree agree on .tree" \
  || fail_check "an unchanged tree produced two different tree objects"
[ "$(printf '%s' "$DA" | jq -r '.sha')" != "$(printf '%s' "$DB" | jq -r '.sha')" ] \
  && pass_check "the two boundaries are distinct commits despite the shared tree" \
  || fail_check "two differently-labelled captures collapsed onto the same sha"

# ------------------------------------------------------------------------ unborn HEAD
#
# A repository with no commits yet is a legitimate state, not an error.

U="$T/unborn"
mkdir -p "$U"
git -C "$U" init -q >/dev/null 2>&1
git -C "$U" config user.email spec@example.invalid
git -C "$U" config user.name "Spec Runner"
printf 'first\n' > "$U/only.txt"

run capture --repo "$U" --label fresh
UOUT="$OUT"
printf '%s' "$UOUT" | jq -e . >/dev/null 2>&1 \
  && pass_check "the unborn-HEAD capture prints valid JSON" \
  || fail_check "unborn-HEAD capture output is not valid JSON: $UOUT"
printf '%s' "$UOUT" | jq -e '.head_unchanged == null' >/dev/null 2>&1 \
  && pass_check "head_unchanged is null when there is no HEAD to be unchanged" \
  || fail_check "head_unchanged is $(printf '%s' "$UOUT" | jq -r '.head_unchanged // "absent"'), expected null"
USHA=$(printf '%s' "$UOUT" | jq -r '.sha // ""')
git -C "$U" ls-tree -r --name-only "$USHA" 2>/dev/null | grep -qx 'only.txt' \
  && pass_check "the unborn-HEAD checkpoint really holds the working tree" \
  || fail_check "the first-ever checkpoint captured an empty tree"
[ -z "$(git -C "$U" rev-parse --verify HEAD 2>/dev/null || true)" ] \
  && pass_check "capturing did not give the unborn repository a HEAD" \
  || fail_check "the capture created a commit on the branch of an empty repository"

# ------------------------------------------------------------------------------- list

E="$T/empty"
mkdir -p "$E"
git -C "$E" init -q >/dev/null 2>&1
run list --repo "$E"
printf '%s' "$OUT" | jq -e '.checkpoints == []' >/dev/null 2>&1 \
  && pass_check "a repo with no checkpoints lists an empty array" \
  || fail_check "list on a clean repo returned $OUT"

run list --repo "$R"
LOUT="$OUT"
printf '%s' "$LOUT" | jq -e . >/dev/null 2>&1 \
  && pass_check "list prints valid JSON" \
  || fail_check "list output is not valid JSON: $LOUT"
[ "$(printf '%s' "$LOUT" | jq -r '[.checkpoints[].label] | sort | join(",")')" = "after,before,det_a,det_b" ] \
  && pass_check "list returns every label captured, and only those" \
  || fail_check "list returned [$(printf '%s' "$LOUT" | jq -r '[.checkpoints[].label] | sort | join(",")')]"
[ "$(printf '%s' "$LOUT" | jq -r '.checkpoints[] | select(.label == "before") | .sha')" = "$SHA1" ] \
  && pass_check "the sha list reports is the sha capture returned" \
  || fail_check "list reports a different sha for label 'before' than capture did"

# ------------------------------------------------------------------------------ clear

run clear --repo "$R" --label before
COUT="$OUT"
printf '%s' "$COUT" | jq -e . >/dev/null 2>&1 \
  && pass_check "clear prints valid JSON" \
  || fail_check "clear output is not valid JSON: $COUT"
[ "$(printf '%s' "$COUT" | jq -r '.removed | join(",")')" = "before" ] \
  && pass_check "clear --label names the one label it removed" \
  || fail_check "clear --label before removed [$(printf '%s' "$COUT" | jq -r '.removed | join(",")')]"
printf '%s' "$COUT" | jq -e '.removed_count == (.removed | length)' >/dev/null 2>&1 \
  && pass_check "removed_count agrees with the length of removed[]" \
  || fail_check "removed_count disagrees with removed[]"
git -C "$R" rev-parse --verify "$NS/before" >/dev/null 2>&1 \
  && fail_check "the ref for the cleared label is still there" \
  || pass_check "the cleared label's ref is gone"
git -C "$R" rev-parse --verify "$NS/after" >/dev/null 2>&1 \
  && pass_check "clear --label left the other checkpoints alone" \
  || fail_check "clear --label before also removed unrelated checkpoints"

run clear --repo "$R" --label never_captured
[ "$(printf '%s' "$OUT" | jq -r '.removed | length')" = "0" ] \
  && pass_check "clearing a label that was never captured removes nothing" \
  || fail_check "clearing an absent label claimed to remove something"

run clear --repo "$R"
COUT="$OUT"
[ "$(printf '%s' "$COUT" | jq -r '.removed | sort | join(",")')" = "after,det_a,det_b" ] \
  && pass_check "bare clear removes every remaining checkpoint and names them all" \
  || fail_check "bare clear removed [$(printf '%s' "$COUT" | jq -r '.removed | sort | join(",")')], expected [after,det_a,det_b]"
printf '%s' "$COUT" | jq -e '.removed_count == (.removed | length)' >/dev/null 2>&1 \
  && pass_check "removed_count agrees with removed[] on the bare-clear path too" \
  || fail_check "bare clear's removed_count disagrees with its array"
run list --repo "$R"
printf '%s' "$OUT" | jq -e '.checkpoints == []' >/dev/null 2>&1 \
  && pass_check "nothing is left in the namespace after a bare clear" \
  || fail_check "list still shows checkpoints after clear"

run clear --repo "$R"
printf '%s' "$OUT" | jq -e '.removed == [] and .removed_count == 0' >/dev/null 2>&1 \
  && pass_check "clear on an already-clear repo returns an empty array" \
  || fail_check "the second clear returned $OUT"
[ "$RC" = "0" ] \
  && pass_check "clear is idempotent — a second run is success, not an error" \
  || fail_check "clear on an already-clear repo exited $RC"

# The whole point of clear is that nothing of ours is left in someone's repo.
[ -z "$(git -C "$R" for-each-ref --format='%(refname)' "$NS" 2>/dev/null || true)" ] \
  && pass_check "$NS holds nothing at all once cleared" \
  || fail_check "refs left behind under $NS after clear"
# And nothing was ever written to the shared prefix the namespace moved off, because a ref
# there is visible to, and clearable by, every other checkout of the repository.
[ -z "$(git -C "$R" for-each-ref --format='%(refname)' 'refs/aida' 2>/dev/null || true)" ] \
  && pass_check "nothing was written under the repository-wide refs/aida/ at any point" \
  || fail_check "a checkpoint landed under refs/aida/, which every worktree of this repo shares"
[ "$(snap_status)" = "$C_STATUS" ] \
  && pass_check "the whole capture/list/clear cycle left the working tree as it found it" \
  || fail_check "the working tree changed across the full cycle"

# ------------------------------------------------------------ a reused label is visible
#
# The rung's contract is a <before>/<after> PAIR. A component interrupted and restarted
# captures its opening boundary twice, and a silent overwrite destroys the boundary it is
# supposed to be one half of: the caller then diffs two "after" trees and nothing said so.

run capture --repo "$R" --label dup
D1="$OUT"; DUPSHA1=$(printf '%s' "$D1" | jq -r '.sha // ""')
printf '%s' "$D1" | jq -e 'has("replaced")' >/dev/null 2>&1 \
  && pass_check "capture always reports whether it replaced a boundary" \
  || fail_check "capture output has no 'replaced' field, so a reuse cannot be seen in it"
printf '%s' "$D1" | jq -e '.replaced == null' >/dev/null 2>&1 \
  && pass_check "a first capture under a fresh label replaced nothing" \
  || fail_check "a first capture claims to have replaced $(printf '%s' "$D1" | jq -r '.replaced')"

printf 'moved on\n' > "$R/tracked.txt"
run capture --repo "$R" --label dup
D2="$OUT"; DUPSHA2=$(printf '%s' "$D2" | jq -r '.sha // ""')
[ "$(printf '%s' "$D2" | jq -r '.replaced')" = "$DUPSHA1" ] \
  && pass_check "recapturing a label names the boundary sha it destroyed" \
  || fail_check "the second capture of 'dup' reported replaced=$(printf '%s' "$D2" | jq -r '.replaced'), expected $DUPSHA1"
[ "$(git -C "$R" rev-parse --verify "$NS/dup" 2>/dev/null || true)" = "$DUPSHA2" ] \
  && pass_check "the label ends up on the newer checkpoint, as the report says" \
  || fail_check "$NS/dup does not point at the second capture"
run clear --repo "$R"
printf 'v3-working\n' > "$R/tracked.txt"

# ------------------------------------------------------- clear reports what really went
#
# `update-ref -d` can fail, and the old shape discarded the failure and then built removed[]
# from the listing taken BEFORE the deletions. A clear that removed nothing named every
# label as removed and exited 0 — the one signal that could contradict "the rung removes
# them at end of phase" was reporting success.

CLR="$T/clearfail"
mkdir -p "$CLR"
git -C "$CLR" init -q >/dev/null 2>&1
git -C "$CLR" config user.email spec@example.invalid
git -C "$CLR" config user.name "Spec Runner"
git -C "$CLR" config commit.gpgsign false
printf 'x\n' > "$CLR/f.txt"
git -C "$CLR" add f.txt >/dev/null 2>&1
git -C "$CLR" commit -qm init >/dev/null 2>&1
run capture --repo "$CLR" --label stuck
REFDIR="$CLR/.git/refs/worktree/aida/build-checkpoints"
if [ ! -d "$REFDIR" ]; then
  skip_check "the checkpoint ref is not a loose ref here, so a failing deletion cannot be staged"
else
  chmod a-w "$REFDIR"
  if touch "$REFDIR/.probe" 2>/dev/null; then
    rm -f "$REFDIR/.probe"; chmod u+w "$REFDIR"
    skip_check "the ref directory is still writable after chmod a-w (running as root?), so a failing deletion cannot be staged"
  else
    run clear --repo "$CLR"
    CFOUT="$OUT"; CFRC="$RC"
    printf '%s' "$CFOUT" | jq -e '.removed == []' >/dev/null 2>&1 \
      && pass_check "a clear that deleted nothing reports nothing as removed" \
      || fail_check "clear claimed to remove [$(printf '%s' "$CFOUT" | jq -r '.removed | join(",")')] while the deletion failed"
    printf '%s' "$CFOUT" | jq -e '.failed | index("stuck") != null' >/dev/null 2>&1 \
      && pass_check "the ref it could not remove is named in failed[]" \
      || fail_check "failed[] is [$(printf '%s' "$CFOUT" | jq -r '.failed // [] | join(",")')], expected it to name 'stuck'"
    [ "$CFRC" != "0" ] \
      && pass_check "a clear that left refs behind does not exit 0" \
      || fail_check "clear exited 0 having removed nothing"
    chmod u+w "$REFDIR"
    git -C "$CLR" rev-parse --verify "$NS/stuck" >/dev/null 2>&1 \
      && pass_check "the fixture is honest: the ref really did survive the clear" \
      || fail_check "the ref was removed after all, so the failure path was never exercised"
  fi
fi

# ------------------------------------------------------- head_unchanged is a comparison
#
# Re-reading HEAD after the write and printing it under that name asserts nothing: were HEAD
# to move, the field would carry the new value and still be called unchanged. Staged here by
# standing in for git only long enough to move HEAD at the moment the checkpoint is anchored.

HM="$T/headmove"
mkdir -p "$HM"
git -C "$HM" init -q >/dev/null 2>&1
git -C "$HM" config user.email spec@example.invalid
git -C "$HM" config user.name "Spec Runner"
git -C "$HM" config commit.gpgsign false
printf 'one\n' > "$HM/f.txt"; git -C "$HM" add f.txt >/dev/null 2>&1; git -C "$HM" commit -qm one >/dev/null 2>&1
HM_OLD=$(git -C "$HM" rev-parse HEAD)
printf 'two\n' > "$HM/f.txt"; git -C "$HM" add f.txt >/dev/null 2>&1; git -C "$HM" commit -qm two >/dev/null 2>&1

REALGIT=$(command -v git)
mkdir -p "$T/fakebin"
cat > "$T/fakebin/git" <<FAKEGIT
#!/usr/bin/env bash
# Real git in every respect but one: when it sees the capture anchoring its checkpoint ref,
# it moves HEAD first. Nothing else is touched, so every other call the script makes behaves
# exactly as it would without this on PATH.
UPD=0; HIT=0
for a in "\$@"; do
  [ "\$a" = "update-ref" ] && UPD=1
  case "\$a" in $NS/*) HIT=1 ;; esac
done
if [ "\$UPD" = "1" ] && [ "\$HIT" = "1" ]; then
  "$REALGIT" -C "$HM" update-ref HEAD "$HM_OLD"
fi
exec "$REALGIT" "\$@"
FAKEGIT
chmod +x "$T/fakebin/git"

set +e
PATH="$T/fakebin:$PATH" bash "$S" capture --repo "$HM" --label moved >/dev/null 2>&1; RC=$?
set -e
[ "$RC" = "4" ] \
  && pass_check "a capture during which HEAD moved fails instead of calling the new value unchanged" \
  || fail_check "HEAD moved under the capture and it exited $RC, reporting the move as head_unchanged"
git -C "$HM" rev-parse --verify "$NS/moved" >/dev/null 2>&1 \
  && fail_check "a capture that could not claim non-disturbance still left its ref anchored" \
  || pass_check "the failed capture removed the ref it had written"

# ----------------------------------------------------------- untracked[] holds real paths
#
# `git ls-files --others` without `-z` returns git's C-quoted rendering for any name that is
# not plain ASCII: surrounding double quotes and backslash escapes included. A caller
# matching untracked[] against real paths misses exactly the files the list exists to name.

Q="$T/quoted"
mkdir -p "$Q"
git -C "$Q" init -q >/dev/null 2>&1
git -C "$Q" config user.email spec@example.invalid
git -C "$Q" config user.name "Spec Runner"
git -C "$Q" config commit.gpgsign false
printf 'x\n' > "$Q/we\"ird.txt"
printf 'x\n' > "$Q/naïve.txt"
printf 'x\n' > "$Q/$(printf 'new\nline.txt')"
run capture --repo "$Q" --label paths
QOUT="$OUT"
printf '%s' "$QOUT" | jq -e '(.untracked | sort) == ["naïve.txt","new\nline.txt","we\"ird.txt"]' >/dev/null 2>&1 \
  && pass_check "untracked[] holds the paths themselves, not git's quoted rendering of them" \
  || fail_check "untracked[] came back as $(printf '%s' "$QOUT" | jq -c '.untracked')"
printf '%s' "$QOUT" | jq -e '.untracked_count == 3' >/dev/null 2>&1 \
  && pass_check "a name holding a newline is one entry, not two" \
  || fail_check "untracked_count is $(printf '%s' "$QOUT" | jq -r '.untracked_count'), expected 3"

# ---------------------------------------------------------------------- jq is required
#
# Every report here is rendered by jq. Without an up-front probe a broken jq surfaced at the
# END of capture, after the ref was anchored: exit 127, nothing on stdout, no diagnostic, and
# a ref in the repository the caller had no sha to clear by.

mkdir -p "$T/nojqbin"
printf '#!/bin/sh\nexit 127\n' > "$T/nojqbin/jq"
chmod +x "$T/nojqbin/jq"
set +e
PATH="$T/nojqbin:$PATH" bash "$S" capture --repo "$R" --label nojq >/dev/null 2>&1; RC=$?
NOJQ_ERR=$(PATH="$T/nojqbin:$PATH" bash "$S" capture --repo "$R" --label nojq 2>&1 >/dev/null)
set -e
[ "$RC" = "5" ] \
  && pass_check "an unrunnable jq is refused up front with its own exit code" \
  || fail_check "a broken jq exited $RC, which a caller cannot tell from a real verdict"
[ -n "$NOJQ_ERR" ] \
  && pass_check "and says so, rather than failing silently" \
  || fail_check "a broken jq produced no diagnostic at all"
git -C "$R" rev-parse --verify "$NS/nojq" >/dev/null 2>&1 \
  && fail_check "a capture that could not report anchored a ref anyway" \
  || pass_check "a capture that cannot render its report leaves no ref behind"
# clear is the path where a missing probe is worst: every jq in it is the last command of a
# branch whose failure nothing reads, so a broken jq made clear print nothing and exit 0.
# A caller reading the exit code was told the repository had been left clean.
set +e
NOJQ_CLEAR=$(PATH="$T/nojqbin:$PATH" bash "$S" clear --repo "$R" 2>/dev/null); RC=$?
set -e
[ "$RC" = "5" ] && [ -z "$NOJQ_CLEAR" ] \
  && pass_check "clear under a broken jq fails loudly instead of printing nothing and exiting 0" \
  || fail_check "clear under a broken jq exited $RC printing [$NOJQ_CLEAR]"

# ------------------------------------------------- two checkouts of one repository
#
# Everything under `refs/` except `refs/worktree/` is ONE store shared by every worktree. A
# bare `refs/aida/build-checkpoints/<label>` therefore had a linked worktree overwriting the
# main checkout's boundary under the same label — and `main` is the documented default label
# for a flat architecture — with a `clear` from either emptying the other's namespace. A real
# `git worktree add`, because two clones would pass under either namespace.

WTBASE="$T/wtmain"
mkdir -p "$WTBASE"
git -C "$WTBASE" init -q >/dev/null 2>&1
git -C "$WTBASE" config user.email spec@example.invalid
git -C "$WTBASE" config user.name "Spec Runner"
git -C "$WTBASE" config commit.gpgsign false
printf 'base\n' > "$WTBASE/f.txt"
git -C "$WTBASE" add f.txt >/dev/null 2>&1
git -C "$WTBASE" commit -qm init >/dev/null 2>&1
git -C "$WTBASE" worktree add -q "$T/wtlinked" -b linked >/dev/null 2>&1
WTLINK="$T/wtlinked"

printf 'main side\n' > "$WTBASE/f.txt"
printf 'linked side\n' > "$WTLINK/f.txt"
run capture --repo "$WTBASE" --label main.before
WSHA_MAIN=$(printf '%s' "$OUT" | jq -r '.sha // ""')
run capture --repo "$WTLINK" --label main.before
WSHA_LINK=$(printf '%s' "$OUT" | jq -r '.sha // ""')

[ -n "$WSHA_MAIN" ] && [ "$WSHA_MAIN" != "$WSHA_LINK" ] \
  && pass_check "two checkouts capturing the same label produce two different checkpoints" \
  || fail_check "both checkouts reported the same sha, so one capture was the other"
[ "$(git -C "$WTBASE" rev-parse --verify "$NS/main.before" 2>/dev/null || true)" = "$WSHA_MAIN" ] \
  && pass_check "the main checkout's label still points at the main checkout's capture" \
  || fail_check "the linked worktree's capture overwrote the main checkout's label"
[ "$(git -C "$WTLINK" rev-parse --verify "$NS/main.before" 2>/dev/null || true)" = "$WSHA_LINK" ] \
  && pass_check "the linked worktree's label points at its own capture" \
  || fail_check "the linked worktree does not resolve its own label"

run list --repo "$WTBASE"
[ "$(printf '%s' "$OUT" | jq -r '[.checkpoints[].sha] | join(",")')" = "$WSHA_MAIN" ] \
  && pass_check "list in the main checkout shows its checkpoint and only its checkpoint" \
  || fail_check "the main checkout lists [$(printf '%s' "$OUT" | jq -r '[.checkpoints[].sha] | join(",")')]"
run list --repo "$WTLINK"
[ "$(printf '%s' "$OUT" | jq -r '[.checkpoints[].sha] | join(",")')" = "$WSHA_LINK" ] \
  && pass_check "and the linked worktree sees only its own" \
  || fail_check "the linked worktree lists [$(printf '%s' "$OUT" | jq -r '[.checkpoints[].sha] | join(",")')]"

run clear --repo "$WTLINK"
[ "$(printf '%s' "$OUT" | jq -r '.removed | join(",")')" = "main.before" ] \
  && pass_check "clearing the linked worktree removes the linked worktree's checkpoint" \
  || fail_check "the linked worktree's clear removed [$(printf '%s' "$OUT" | jq -r '.removed | join(",")')]"
[ "$(git -C "$WTBASE" rev-parse --verify "$NS/main.before" 2>/dev/null || true)" = "$WSHA_MAIN" ] \
  && pass_check "a clear in one checkout leaves the other checkout's boundary standing" \
  || fail_check "clearing the linked worktree emptied the main checkout's namespace too"
git -C "$WTBASE" cat-file -e "$WSHA_MAIN^{commit}" 2>/dev/null \
  && pass_check "and that boundary still resolves to a commit, so the range is still usable" \
  || fail_check "the surviving label points at an object that is gone"
[ -z "$(git -C "$WTLINK" rev-parse --verify "$NS/main.before" 2>/dev/null || true)" ] \
  && pass_check "the main checkout's checkpoint is not reachable through the other's namespace" \
  || fail_check "the linked worktree can still resolve a label it just cleared"
# The IDENTITY ref must never be shared: that is the collision this whole fixture is about.
# The sha-named keep-ref is shared on purpose, because gc in one checkout cannot see another
# checkout's per-worktree refs, and a name that is the object's own hash can only collide with
# an identical object. So the property is not "nothing shared" but "no LABEL shared".
[ -z "$(git -C "$WTBASE" for-each-ref --format='%(refname)' 'refs/aida/build-checkpoints' 2>/dev/null || true)" ] \
  && pass_check "no label-named checkpoint landed in the ref store both checkouts share" \
  || fail_check "a label-named checkpoint landed in the shared ref store, which is the collision"
for kr in $(git -C "$WTBASE" for-each-ref --format='%(refname)' 'refs/aida/build-checkpoints-keep' 2>/dev/null || true); do
  if [ "${kr##*/}" = "$(git -C "$WTBASE" rev-parse --verify "$kr" 2>/dev/null)" ]; then
    pass_check "the shared keep-ref is named by the object's own sha, so it cannot collide by label"
  else
    fail_check "a shared keep-ref is not named by its object's sha: $kr"
  fi
done

# ------------------------------------------------------------------- label validation
#
# A label becomes a ref name. Each of these is a different way to leave the namespace or to
# hand git something it will mangle, and each must be refused before git is asked.

REFS_BEFORE=$(git -C "$R" for-each-ref --format='%(refname)' 'refs/' 2>/dev/null | wc -l | tr -d ' ')
# The property, not a proxy for it: whatever these labels do, no ref may appear anywhere
# outside the checkpoint namespace. `../escape` on its own does not test that — the
# leading-dot rule refuses it before the character class is ever consulted, so widening the
# class to admit `/` left the whole spec green while `x/../../heads/master` would then have
# reached `git update-ref`. The separator cases below and this before/after set are what
# actually defend it.
OUTSIDE_BEFORE=$(git -C "$R" for-each-ref --format='%(refname)' 'refs/' 2>/dev/null | grep -v "^$NS/" | sort || true)
[ -n "$OUTSIDE_BEFORE" ] \
  && pass_check "fixture: the repo holds refs outside the namespace, so the escape check has something to protect" \
  || fail_check "fixture is broken — no refs outside $NS, so an escape assertion would compare empty to empty"

rc_of capture --repo "$R" --label '../escape'
[ "$RC" = "2" ] && pass_check "a label that walks out of the namespace is rejected with 2" \
                || fail_check "'../escape' exited $RC, expected 2"
rc_of capture --repo "$R" --label 'x/../../heads/master'
[ "$RC" = "2" ] && pass_check "a label that climbs back out through path separators is rejected with 2" \
                || fail_check "'x/../../heads/master' exited $RC, expected 2"
rc_of capture --repo "$R" --label 'nested/label'
[ "$RC" = "2" ] && pass_check "a separator is refused even where it would stay inside the namespace" \
                || fail_check "'nested/label' exited $RC, expected 2 — a label may not add a ref path component"
# Character-legal, ref-illegal. Both of these used to pass the character rules, create a
# checkpoint commit object, and only then be refused by git at update-ref — reported as exit
# 4 "not a usable git repository" for what is plainly a bad argument, with the object left
# dangling.
rc_of capture --repo "$R" --label 'a..b'
[ "$RC" = "2" ] && pass_check "a label git's own ref grammar refuses exits 2, not 4" \
                || fail_check "'a..b' exited $RC, expected 2"
rc_of capture --repo "$R" --label 'trailing.'
[ "$RC" = "2" ] && pass_check "a label ending in a dot is refused before git is asked to store it" \
                || fail_check "'trailing.' exited $RC, expected 2"
rc_of capture --repo "$R" --label '-dash'
[ "$RC" = "2" ] && pass_check "a label starting with a hyphen is rejected with 2" \
                || fail_check "'-dash' exited $RC, expected 2"
rc_of capture --repo "$R" --label '.hidden'
[ "$RC" = "2" ] && pass_check "a label starting with a dot is rejected with 2" \
                || fail_check "'.hidden' exited $RC, expected 2"
rc_of capture --repo "$R" --label 'has space'
[ "$RC" = "2" ] && pass_check "a label containing a space is rejected with 2" \
                || fail_check "'has space' exited $RC, expected 2"
rc_of capture --repo "$R" --label ''
[ "$RC" = "2" ] && pass_check "an empty --label is rejected with 2" \
                || fail_check "an empty label exited $RC, expected 2"
rc_of capture --repo "$R"
[ "$RC" = "2" ] && pass_check "capture with no --label at all is rejected with 2" \
                || fail_check "a missing --label exited $RC, expected 2"

[ "$(git -C "$R" for-each-ref --format='%(refname)' 'refs/' 2>/dev/null | wc -l | tr -d ' ')" = "$REFS_BEFORE" ] \
  && pass_check "a rejected label leaves no ref behind" \
  || fail_check "a rejected capture still wrote a ref"
[ "$(git -C "$R" for-each-ref --format='%(refname)' 'refs/' 2>/dev/null | grep -v "^$NS/" | sort || true)" = "$OUTSIDE_BEFORE" ] \
  && pass_check "and no ref landed anywhere outside $NS/" \
  || fail_check "a rejected label put a ref outside the checkpoint namespace"

# A flag given as the last argument with no value must not hang. The parser does `shift 2`
# on a single remaining argument, which bash refuses, leaving $# unchanged — so the loop
# never advances. Guarded by timeout so a hang is a failure rather than a stuck spec.
set +e
timeout 5 bash "$S" capture --repo "$R" --label >/dev/null 2>&1; RC=$?
set -e
[ "$RC" != "124" ] \
  && pass_check "a value-less trailing --label terminates instead of spinning" \
  || fail_check "a value-less trailing --label hangs forever: 'shift 2' cannot advance a one-argument tail"

# --------------------------------------------------------------- repository and usage

NOTGIT="$T/plain"
mkdir -p "$NOTGIT"
rc_of capture --repo "$NOTGIT" --label x
[ "$RC" = "4" ] && pass_check "a directory that is not a git repository exits 4" \
                || fail_check "a non-git directory exited $RC, expected 4"
rc_of capture --repo "$T/does-not-exist" --label x
[ "$RC" = "4" ] && pass_check "a --repo that does not exist exits 4" \
                || fail_check "a nonexistent --repo exited $RC, expected 4"
rc_of frobnicate --repo "$R"
[ "$RC" = "2" ] && pass_check "an unknown subcommand exits 2" \
                || fail_check "an unknown subcommand exited $RC, expected 2"
rc_of capture --label x
[ "$RC" = "2" ] && pass_check "a missing --repo exits 2" \
                || fail_check "a missing --repo exited $RC, expected 2"
rc_of capture --repo "$R" --label x --wat
[ "$RC" = "2" ] && pass_check "an unrecognised argument exits 2 rather than being ignored" \
                || fail_check "an unknown argument exited $RC, expected 2"

# ------------------------------------------- gc from a sibling checkout must not take it
#
# The finding this defends against: moving to `refs/worktree/` bought per-checkout isolation
# and silently lost gc protection between checkouts, because a checkout's per-worktree refs
# are not reachability roots for a gc run somewhere else. Measured on git 2.43, before the
# shared keep-ref existed: `gc --prune=now` from the main checkout deleted an object captured
# in a linked worktree, `list` still reported the checkpoint, and the critic's rev range was a
# git fatal. Three shipped documents asserted this could not happen, and the assertion whose
# message said so never ran gc. This one runs gc.

GCR="$T/gcrepo"
mkdir -p "$GCR"
git -C "$GCR" init -q .
git -C "$GCR" config user.email spec@example.com
git -C "$GCR" config user.name "Spec"
git -C "$GCR" commit -q --allow-empty -m init
git -C "$GCR" worktree add -q "$T/gcwt" -b gcwt 2>/dev/null
printf 'new module\n' > "$T/gcwt/module.txt"

GC_SHA=$(bash "$S" capture --repo "$T/gcwt" --label gc1 2>/dev/null | jq -r '.sha // ""')
if [ -n "$GC_SHA" ]; then
  git -C "$GCR" gc --prune=now --quiet 2>/dev/null || true

  git -C "$GCR" cat-file -e "${GC_SHA}^{commit}" 2>/dev/null \
    && pass_check "a gc --prune=now from a sibling checkout does not destroy the checkpoint object" \
    || fail_check "the object was collected by a sibling checkout's gc; the anchor does not anchor"

  [ "$(bash "$S" list --repo "$T/gcwt" 2>/dev/null | jq -r '.checkpoints[0].object')" = "resolvable" ] \
    && pass_check "list confirms the object still resolves after that gc" \
    || fail_check "list reports the checkpoint as unresolvable after a sibling gc"

  git -C "$T/gcwt" diff --name-only "$GC_SHA"..HEAD >/dev/null 2>&1 \
    && pass_check "the rev range a critic would run is still usable after that gc" \
    || fail_check "the rev range is a git fatal after a sibling gc"

  # The mechanism, asserted directly: a shared sha-named keep-ref is what gc can see.
  git -C "$GCR" rev-parse --verify "refs/aida/build-checkpoints-keep/$GC_SHA" >/dev/null 2>&1 \
    && pass_check "capture anchors the object in a shared, sha-named keep namespace" \
    || fail_check "no shared keep-ref for the captured object; only the per-worktree ref exists"

  # Isolation must survive the addition. The keep-ref is shared on purpose; the identity ref
  # is not, and one checkout clearing must not strand another's checkpoint.
  bash "$S" capture --repo "$GCR" --label gc1 >/dev/null 2>&1
  bash "$S" clear --repo "$GCR" >/dev/null 2>&1
  [ "$(bash "$S" list --repo "$T/gcwt" 2>/dev/null | jq -r '.checkpoints[0].object')" = "resolvable" ] \
    && pass_check "one checkout clearing leaves a sibling's checkpoint resolvable, not just listed" \
    || fail_check "clearing in one checkout stranded or destroyed a sibling's checkpoint"

  bash "$S" clear --repo "$T/gcwt" >/dev/null 2>&1
  [ "$(git -C "$GCR" for-each-ref --format='%(refname)' refs/aida/build-checkpoints-keep | wc -l)" = "0" ] \
    && pass_check "clear releases the shared keep-ref too, leaving no anchor behind" \
    || fail_check "keep-refs survive clear, accumulating one unreachable-object anchor per build"
else
  fail_check "could not capture in a linked worktree, so the gc property was never tested"
fi

# --------------------------------------- list reports an object that is gone, rather than
# ---------------------------------------- naming a checkpoint the caller cannot use
#
# Staged as the original bug minus its fix: capture in a LINKED WORKTREE, delete the shared
# keep-ref, then gc from the MAIN checkout, which cannot see the worktree's per-worktree ref
# and therefore collects the object while the ref survives. A single checkout cannot stage
# this, because there its own identity ref is a reachability root, which is why an earlier
# version of this assertion never ran and could not fail.

DEADR="$T/deadrepo"
mkdir -p "$DEADR"
git -C "$DEADR" init -q .
git -C "$DEADR" config user.email spec@example.com
git -C "$DEADR" config user.name "Spec"
git -C "$DEADR" commit -q --allow-empty -m init
git -C "$DEADR" worktree add -q "$T/deadwt" -b deadwt 2>/dev/null
printf 'x\n' > "$T/deadwt/x.txt"
DEAD_SHA=$(bash "$S" capture --repo "$T/deadwt" --label dead 2>/dev/null | jq -r '.sha // ""')
git -C "$DEADR" update-ref -d "refs/aida/build-checkpoints-keep/$DEAD_SHA" 2>/dev/null || true
git -C "$DEADR" reflog expire --expire=now --all 2>/dev/null || true
git -C "$DEADR" gc --prune=now --quiet 2>/dev/null || true

if [ -n "$DEAD_SHA" ] && ! git -C "$DEADR" cat-file -e "${DEAD_SHA}^{commit}" 2>/dev/null; then
  DL=$(bash "$S" list --repo "$T/deadwt" 2>/dev/null)
  [ "$(printf '%s' "$DL" | jq -r '.checkpoints[0].object')" = "unresolvable" ] \
    && pass_check "a ref that outlived its object is reported unresolvable, not as a usable checkpoint" \
    || fail_check "list named a checkpoint whose commit is gone without saying so"
  [ "$(printf '%s' "$DL" | jq -r '.unresolvable_count')" = "1" ] \
    && pass_check "unresolvable_count counts it, so a caller reading one field still learns" \
    || fail_check "unresolvable_count did not count a dangling checkpoint"
else
  fail_check "could not stage a dangling ref, so the unresolvable path was never tested"
fi

if [ "$FAIL" = "0" ]; then printf '\nbuild-checkpoint-spec: all checks passed\n'; else printf '\nbuild-checkpoint-spec: FAILURES\n' >&2; fi
exit "$FAIL"
