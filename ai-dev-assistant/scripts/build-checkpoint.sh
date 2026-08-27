#!/usr/bin/env bash
# build-checkpoint.sh — a before/after boundary for work that has not been committed.
#
# Usage:
#   build-checkpoint.sh capture --repo <path> --label <name>   → JSON: {sha, ...}
#   build-checkpoint.sh list    --repo <path>                  → JSON: {checkpoints, unresolvable_count}
#   build-checkpoint.sh clear   --repo <path> [--label <name>] → JSON: {removed: [...]}
#
# Why this exists. The work-order critique hands each critic a `<before>..<after>` git rev
# range, and gets those two shas for free because a work-order is a discrete build atom:
# `git rev-parse HEAD` before dispatch, the builder's returned handle after. An in-session
# build has neither. The code lives in the working tree, uncommitted, often untracked, and
# HEAD does not move between one component and the next — so there is no range, and the
# critic that per-component critique depends on cannot be told what to look at.
#
# Committing per component would produce a range. It is also not ours to require: how a
# repository uses version control belongs to whoever owns the repository, and a build gate
# that silently writes commits into someone's branch has overstepped.
#
# So a checkpoint is a commit OBJECT with no branch. `git write-tree` against a temporary
# index produces a tree; `git commit-tree` wraps it; the sha is a perfectly ordinary commit
# for `git diff <a>..<b>` and for every read-only thing a critic does. What it is not is
# reachable from any branch: HEAD does not move, no branch advances, and the real index and
# working tree are untouched, so `git log`, `git status`, `git stash list` and `git branch`
# show nothing new. `git log --all` DOES list them, because `--all` walks every ref
# including this namespace. They are hidden from the ordinary views, not from a deliberate
# look.
#
# The object is anchored under TWO refs, and it needs both.
#
# `refs/worktree/aida/build-checkpoints/<label>` is the checkpoint's identity. That namespace
# is per-checkout, which is the whole point: everything else under `refs/` is shared by every
# checkout of a repository, and two agents building different tasks in two worktrees would
# otherwise write the same default label, overwrite each other, and delete each other's
# boundary on clear.
#
# But per-checkout refs are not reachability roots for a `git gc` run from a DIFFERENT
# checkout, so per-worktree isolation costs the very protection the anchor exists for.
# Measured on git 2.43: `gc --prune=now` from a sibling checkout deletes the object and leaves
# the ref, after which `list` reports a checkpoint whose commit no longer exists and the
# critic's rev range is a git fatal. So each object also gets a keep-ref at
# `refs/aida/build-checkpoints-keep/<sha>`, which IS shared and therefore visible to gc
# everywhere. Naming it by sha rather than by label is what makes sharing safe: two checkouts
# can only collide on that name by having produced byte-identical trees, in which case they
# are the same object and sharing it is correct.
#
# Both namespaces sit outside `refs/heads` and `refs/tags`, so they are invisible to
# `git branch`, `git tag` and a plain `git log`. `clear` removes both. They are the only
# things this script writes into the repository, and the calling command's Output section has
# to say so.
#
# `refs/worktree/` rather than a plain `refs/` prefix, because everything else under `refs/`
# is one store shared by every checkout of a repository, and `refs/worktree/` is the one
# namespace git keeps per checkout (git 2.7 and later). Under a shared prefix, two worktrees
# building different tasks both wrote `.../main.before` — `main` being the documented default
# label for a flat architecture — the second silently replaced the first, and a `clear` from
# either emptied the other's namespace: a critic would have been handed a before/after range
# belonging to another task. Two agents on two PRs in one repository is the ordinary working
# pattern here, not an edge of it, so per-checkout isolation has to be what the mechanism
# provides rather than something a caller remembers to ask for. Under `refs/worktree/` each
# checkout writes, lists and clears only its own, and `clear` with no label is safe again
# because the namespace it empties is already this checkout's alone.
#
# Untracked files ARE included (git add -A semantics: everything not ignored). They have to
# be — a new module is entirely untracked until someone stages it, and a checkpoint that
# skipped them would hand the critic an empty diff for exactly the component most worth
# critiquing. The cost is that an unrelated untracked file rides along, so `untracked[]`
# names the untracked ones, letting a caller see what came in rather than discover it later.
# It is not a full manifest of the checkpoint: a file the person has staged is in the tree
# too and is correctly absent from `untracked[]`, because it is not untracked.
#
# Exit codes: 0 ok · 2 invalid arguments · 4 not a usable git repository, or a checkpoint
#             that could not be removed · 5 jq is missing or not runnable

set -uo pipefail

# jq renders every report this script produces, so it is a hard dependency rather than a
# nicety, and it is probed once here rather than discovered halfway through. Discovered
# halfway through is what used to happen: with `set -uo pipefail` and no `-e`, a jq that
# died during capture took the report with it and left the checkpoint ref already anchored,
# so the run exited 127 with nothing on stdout, no diagnostic, and a ref in someone's
# repository that the caller had no sha to clear by. Probed by running it, not by
# `command -v`, because a jq on PATH that cannot run is the same problem wearing a name.
jq --version >/dev/null 2>&1 || {
  echo "build-checkpoint: jq is required and could not be run; install jq and try again" >&2
  exit 5
}

SUB="${1:-}"; shift || true
REPO=""; LABEL=""
# `shift 2` against a one-argument tail does NOT shift: bash refuses and returns non-zero,
# and with no `set -e` that return is discarded, so `$#` stays 1 and this loop spins forever
# without ever exiting. A trailing `--label` carrying no value did exactly that. Require the
# value rather than defaulting it away.
need_value() {
  [ "$#" -ge 2 ] || { echo "build-checkpoint: $1 requires a value" >&2; exit 2; }
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)  need_value "$@"; REPO="$2";  shift 2 ;;
    --label) need_value "$@"; LABEL="$2"; shift 2 ;;
    *) echo "build-checkpoint: unknown argument: $1" >&2; exit 2 ;;
  esac
done

case "$SUB" in
  capture|list|clear) ;;
  *) echo "build-checkpoint: usage: build-checkpoint.sh capture|list|clear --repo <path> [--label <name>]" >&2; exit 2 ;;
esac

[ -n "$REPO" ] || { echo "build-checkpoint: --repo is required" >&2; exit 2; }
[ -d "$REPO" ] || { echo "build-checkpoint: --repo is not a directory: $REPO" >&2; exit 4; }

if ! git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  echo "build-checkpoint: not a git repository: $REPO" >&2
  exit 4
fi

NS="refs/worktree/aida/build-checkpoints"
KEEP_NS="refs/aida/build-checkpoints-keep"

# A label becomes part of a ref name. Refuse anything git would reject or that could escape
# the namespace, rather than letting git fail somewhere less legible.
check_label() {
  [ -n "$LABEL" ] || { echo "build-checkpoint: --label is required for $SUB" >&2; exit 2; }
  case "$LABEL" in
    *[!A-Za-z0-9._-]*|.*|*.lock|-*)
      echo "build-checkpoint: --label must be letters, digits, dot, underscore or hyphen, and may not start with a dot or hyphen (got \"$LABEL\")" >&2
      exit 2
      ;;
  esac
  # The rules above are ours. The ref grammar is git's, and it holds more rules than are
  # worth restating from memory here: `a..b` and `a.` both pass the character rules and are
  # then refused by git at update-ref, after a checkpoint commit object has already been
  # created and is left dangling, and with the refusal reported as exit 4 "not a usable git
  # repository" for what is plainly a bad argument. Ask git instead of keeping a list.
  if ! git -C "$REPO" check-ref-format "$NS/$LABEL" >/dev/null 2>&1; then
    echo "build-checkpoint: git will not accept \"$LABEL\" as a ref name component" >&2
    exit 2
  fi
}

case "$SUB" in

capture)
  check_label

  # Capturing under a label that already holds a checkpoint destroys the boundary it
  # replaces. The rung's contract is a <before>/<after> PAIR of labels, so a component that
  # was interrupted and restarted overwrites its own opening boundary and the caller then
  # compares two "after" trees without anything having told it so. Refusing the reuse would
  # be worse, because restarting a component is legitimate, so the replacement is reported
  # instead of being invisible: `replaced` carries the sha that was there.
  PREV=$(git -C "$REPO" rev-parse --verify "$NS/$LABEL" 2>/dev/null) || PREV=""
  [ -z "$PREV" ] \
    || echo "build-checkpoint: label \"$LABEL\" already pointed at $PREV; that boundary is being replaced" >&2

  # A temporary index, so the person's staged work is neither read as intent nor disturbed.
  #
  # The path must not exist yet: git reads an existing index file and an empty one is not a
  # valid index, so handing it `mktemp`'s zero-byte file makes `git add` fail outright.
  TMPDIR_CP=$(mktemp -d) || { echo "build-checkpoint: cannot create a temporary directory" >&2; exit 4; }
  trap 'rm -rf "$TMPDIR_CP"' EXIT
  TMPIDX="$TMPDIR_CP/index"

  if ! GIT_INDEX_FILE="$TMPIDX" git -C "$REPO" add -A 2>/dev/null; then
    echo "build-checkpoint: could not stage the working tree into a temporary index" >&2
    exit 4
  fi

  TREE=$(GIT_INDEX_FILE="$TMPIDX" git -C "$REPO" write-tree 2>/dev/null) || TREE=""
  [ -n "$TREE" ] || { echo "build-checkpoint: could not write a tree object" >&2; exit 4; }

  # An unborn HEAD is a legitimate state (a repository with no commits yet), so the parent
  # is optional rather than assumed.
  PARENT=$(git -C "$REPO" rev-parse --verify HEAD 2>/dev/null) || PARENT=""
  if [ -n "$PARENT" ]; then
    SHA=$(git -C "$REPO" commit-tree "$TREE" -p "$PARENT" -m "aida build checkpoint: $LABEL" 2>/dev/null) || SHA=""
  else
    SHA=$(git -C "$REPO" commit-tree "$TREE" -m "aida build checkpoint: $LABEL" 2>/dev/null) || SHA=""
  fi
  [ -n "$SHA" ] || { echo "build-checkpoint: could not create a checkpoint commit object" >&2; exit 4; }

  # The shared, sha-named keep-ref goes first: an identity ref anchoring an object that a
  # sibling checkout's gc can still collect is the failure this pair exists to prevent.
  git -C "$REPO" update-ref "$KEEP_NS/$SHA" "$SHA" 2>/dev/null \
    || { echo "build-checkpoint: could not anchor the checkpoint object under $KEEP_NS/$SHA" >&2; exit 4; }

  git -C "$REPO" update-ref "$NS/$LABEL" "$SHA" 2>/dev/null \
    || { echo "build-checkpoint: could not anchor the checkpoint under $NS/$LABEL" >&2; exit 4; }

  # `-z`, because without it git returns its C-quoted form for any name that is not plain
  # ASCII: surrounding double quotes and backslash escapes included, and a `jq -R` of that
  # line takes the representation literally. A file named we"ird.txt came back as the JSON
  # string "we\"ird.txt" with git's own quotes inside the value, and a name holding a
  # newline came back split or mangled. Either way a caller matching untracked[] against
  # real paths misses exactly the files the list exists to name. NUL is the one byte a
  # filename cannot contain, so splitting on it is the only split that cannot be wrong, and
  # passing each name to jq as an argument keeps it a value rather than a line of text.
  UNTRACKED_PATHS=()
  while IFS= read -r -d '' u; do
    [ -n "$u" ] || continue
    UNTRACKED_PATHS+=("$u")
  done < <(git -C "$REPO" ls-files --others --exclude-standard -z 2>/dev/null)
  if [ "${#UNTRACKED_PATHS[@]}" -eq 0 ]; then
    UNTRACKED='[]'
  else
    UNTRACKED=$(jq -n '$ARGS.positional' --args "${UNTRACKED_PATHS[@]}") || UNTRACKED=""
  fi

  # The claim in `head_unchanged` has to be a comparison, or it is only HEAD wearing a name
  # that flatters it. Re-reading HEAD and emitting it says nothing: were a future change to
  # move HEAD, the field would carry the new value and still be called unchanged. So HEAD as
  # it stood before the write is compared against HEAD as it stands after, and a mismatch is
  # a failed capture rather than a mislabelled field, because leaving HEAD alone is the whole
  # of what this mechanism promises the owner of the repository. The ref goes with it: a
  # boundary that cannot claim non-disturbance is not one to leave anchored.
  HEAD_AFTER=$(git -C "$REPO" rev-parse --verify HEAD 2>/dev/null) || HEAD_AFTER=""
  if [ "$HEAD_AFTER" != "$PARENT" ]; then
    git -C "$REPO" update-ref -d "$NS/$LABEL" 2>/dev/null
    git -C "$REPO" update-ref -d "$KEEP_NS/$SHA" 2>/dev/null
    echo "build-checkpoint: HEAD moved during the capture ($PARENT -> $HEAD_AFTER); the checkpoint was removed rather than reported as an undisturbed boundary" >&2
    exit 4
  fi

  # Rendered into a variable and checked before anything is printed, so that a capture
  # produces both the ref and the report or neither of them. Printing last meant a failure
  # in this step left the ref anchored with its sha unreported.
  REPORT=""
  [ -n "$UNTRACKED" ] && \
  REPORT=$(jq -n --arg sha "$SHA" --arg tree "$TREE" --arg label "$LABEL" --arg ref "$NS/$LABEL" \
        --arg head "$HEAD_AFTER" --arg prev "$PREV" --argjson untracked "$UNTRACKED" \
    '{sha: $sha, tree: $tree, label: $label, ref: $ref,
      head_unchanged: (if $head == "" then null else $head end),
      replaced: (if $prev == "" then null else $prev end),
      untracked: $untracked,
      untracked_count: ($untracked | length)}') || REPORT=""
  if [ -z "$REPORT" ]; then
    git -C "$REPO" update-ref -d "$NS/$LABEL" 2>/dev/null
    git -C "$REPO" update-ref -d "$KEEP_NS/$SHA" 2>/dev/null
    echo "build-checkpoint: could not render the capture report; the checkpoint refs were removed rather than left anchored with no sha to clear them by" >&2
    exit 5
  fi
  printf '%s\n' "$REPORT"
  ;;

list)
  ROWS=$(git -C "$REPO" for-each-ref --format='%(refname)%09%(objectname)' "$NS" 2>/dev/null || true)
  if [ -z "$ROWS" ]; then
    jq -n '{checkpoints: [], unresolvable_count: 0}'
  else
    # Resolve every sha before reporting it. A ref can outlive its object: per-worktree refs
    # are not reachability roots for a gc run from a sibling checkout, and while the shared
    # keep-ref closes that case, nothing stops someone deleting a ref by hand. A list that
    # names a checkpoint whose commit is gone hands the caller a rev range that turns into a
    # git fatal, which is the same failure arriving one step later and further from its cause.
    CHECKED=""
    while IFS="$(printf '\t')" read -r refname refsha; do
      [ -n "$refname" ] || continue
      if git -C "$REPO" cat-file -e "${refsha}^{commit}" 2>/dev/null; then
        CHECKED="${CHECKED}${refname}	${refsha}	resolvable
"
      else
        CHECKED="${CHECKED}${refname}	${refsha}	unresolvable
"
      fi
    done <<< "$ROWS"
    printf '%s' "$CHECKED" \
      | jq -R --arg ns "$NS" 'split("\t") | {label: (.[0] | ltrimstr($ns + "/")), ref: .[0], sha: .[1], object: .[2]}' \
      | jq -s '{checkpoints: ., unresolvable_count: (map(select(.object == "unresolvable")) | length)}'
  fi
  ;;

clear)
  # `update-ref -d` can fail: a read-only ref store, a packed-refs the process cannot
  # rewrite, another writer holding the lock. The earlier shape discarded that failure with
  # `|| true` and then built removed[] out of the listing taken BEFORE the deletions, so a
  # clear that removed nothing named every label as removed and exited 0. That matters more
  # than a wrong count: this report is the only signal that could contradict "the rung
  # removes them at end of phase", and it was reporting success for the case where refs were
  # left in someone's repository. So each deletion is checked, the ref is re-read to confirm
  # it is really gone, and removed[] names only what went. What did not go is named in
  # failed[] and makes the run exit non-zero, because a caller that reads only the exit code
  # still has to learn that the repository was not left clean.
  REMOVED_LABELS=()
  FAILED_LABELS=()
  drop_ref() {
    # $1 the full refname, $2 the label to report it under.
    #
    # The object's shared keep-ref goes with it. Read the sha BEFORE deleting the identity
    # ref, because afterwards there is nothing left to say which object this checkout was
    # holding. Leaving keep-refs behind would accumulate one unreachable-object anchor per
    # component per build, in a namespace nothing else ever prunes.
    local sha
    sha=$(git -C "$REPO" rev-parse --verify "$1" 2>/dev/null) || sha=""
    if git -C "$REPO" update-ref -d "$1" 2>/dev/null \
       && ! git -C "$REPO" rev-parse --verify "$1" >/dev/null 2>&1; then
      REMOVED_LABELS+=("$2")
      [ -n "$sha" ] && git -C "$REPO" update-ref -d "$KEEP_NS/$sha" 2>/dev/null || true
    else
      FAILED_LABELS+=("$2")
    fi
  }

  if [ -n "$LABEL" ]; then
    check_label
    if git -C "$REPO" rev-parse --verify "$NS/$LABEL" >/dev/null 2>&1; then
      drop_ref "$NS/$LABEL" "$LABEL"
    fi
  else
    # A here-string rather than a pipe, so the loop runs in this shell and the arrays it
    # fills survive it.
    ALL=$(git -C "$REPO" for-each-ref --format='%(refname)' "$NS" 2>/dev/null || true)
    if [ -n "$ALL" ]; then
      while IFS= read -r r; do
        [ -n "$r" ] || continue
        drop_ref "$r" "${r#"$NS"/}"
      done <<< "$ALL"
    fi
  fi

  if [ "${#REMOVED_LABELS[@]}" -eq 0 ]; then
    REMOVED='[]'
  else
    REMOVED=$(jq -n '$ARGS.positional' --args "${REMOVED_LABELS[@]}")
  fi
  if [ "${#FAILED_LABELS[@]}" -eq 0 ]; then
    FAILED='[]'
  else
    FAILED=$(jq -n '$ARGS.positional' --args "${FAILED_LABELS[@]}")
  fi
  jq -n --argjson r "$REMOVED" --argjson f "$FAILED" \
    '{removed: $r, removed_count: ($r | length),
      failed: $f, failed_count: ($f | length)}'
  if [ "${#FAILED_LABELS[@]}" -ne 0 ]; then
    echo "build-checkpoint: ${#FAILED_LABELS[@]} checkpoint ref(s) could not be removed and are still in $REPO" >&2
    exit 4
  fi
  ;;

esac
