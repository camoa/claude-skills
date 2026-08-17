#!/usr/bin/env bash
# Checks that every command file says what it writes and where.
#
# OUTPUTS.md and CLAUDE.md both state the rule: every command carries an
# "## Output" section naming what it leaves behind, and a command that writes
# nothing says so. Until this script there was nothing holding anyone to it,
# so the rule was a sentence in a document rather than a property of the repo.
#
# The rule enforced here, stated exactly:
#
#   Every git-tracked file matching */commands/*.md contains a line that is
#   exactly "## Output", outside any fenced code block, followed by at least
#   one non-blank line before the next "## " heading or the end of the file.
#
# Exact heading, not a prefix. "## Output Format" is a different section: it
# shows the shape of a printed report, which is not the same question as what
# the command leaves on disk. Eleven files had "## Output Format" and no
# "## Output", and one of them (migrate-tasks) moves task folders around on
# disk while documenting only its terminal output. Accepting the prefix would
# have passed all eleven, which is the failure this check exists to prevent.
# Three drupal-htmx files spelled it "## Expected Output"; those were
# normalised to the one spelling rather than accepted as a second one, so
# there is a single string to grep for.
#
# Outside a code fence, because command files quote their own printed reports
# in fenced blocks and those quoted reports contain h2 headings. A "## Output"
# inside a fence is an example of what the command prints, not the section
# this rule asks for, and counting it would be a false pass.
#
# The non-blank-body requirement is there because a bare heading satisfies the
# letter of the rule while telling a reader nothing.
#
# There are NO exemptions. Deprecated plugins are not exempt: what a
# deprecated command does to your filesystem is exactly the thing you want
# written down before you run it. The 44 symlinked command files in
# drupal-dev-framework are not exempt either — awk reads through a symlink, so
# they are satisfied by the section in the file they point at, which is
# deduplication rather than an exception.
#
# Written for bash 3.2 so it behaves the same on macOS and CI.

set -uo pipefail

export LC_ALL=C

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

HEADING='## Output'

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  IN_GIT=1
else
  IN_GIT=0
fi

LIST=$(mktemp)
GONE=$(mktemp)
trap 'rm -f "$LIST" "$GONE"' EXIT

# Mirrors discover() in scripts/lint-shell.sh and scripts/run-tests.sh on
# purpose. Inside a git work tree the list comes from `git ls-files`, so
# ignored and untracked paths are excluded by construction: .worktrees/ and
# .claude/worktrees/ hold whole stale copies of this repo, and a plain `find`
# would scan those copies too and report their command files as failures.
# Outside a work tree (an extracted tarball) it falls back to `find` with the
# same directories pruned.
#
# Consequence worth knowing, same as the other two: a brand-new command file
# is not checked until it is `git add`ed. On CI every file is tracked.
#
# Paths are NUL-separated so a name containing a newline survives discovery.
# `sort -z` is GNU-only, so nothing here pipes through sort.
#
# Unreadable paths go to $GONE rather than to stderr, so a warning printed by
# git itself cannot be mistaken for one.
discover() {
  if [ "$IN_GIT" -eq 1 ]; then
    git ls-files -z
  else
    find . \
      \( -path ./.git -o -path ./.claude -o -path ./.worktrees \) -prune -o \
      -type f -print0
  fi | while IFS= read -r -d '' p; do
    p="${p#./}"
    case "$p" in
      */commands/*.md) ;;
      *) continue ;;
    esac
    # `git ls-files` still lists a tracked file deleted from the work tree,
    # and a symlink can dangle. Either would otherwise be reported as a
    # missing section, which is a confusing way to say "this file is gone".
    if [ ! -r "$p" ]; then
      printf '%s\n' "$p" >> "$GONE"
      continue
    fi
    printf '%s\0' "$p"
  done
}

# Classifies one file. Prints exactly one of:
#   ok
#   empty
#   missing <nearest near-miss heading, or "-">
#
# One awk pass per file, reading the file directly. Nothing is piped into
# anything that exits early: under `pipefail` a reader that stops at the first
# match kills the writer with SIGPIPE and the pipeline reports 141, which
# surfaces as an intermittent failure on long files only.
classify() {
  awk -v want="$HEADING" '
    # Fence state first, so everything below only ever sees prose. Both ``` and
    # ~~~ open a fence; an info string may follow the opener.
    /^[ \t]*(```|~~~)/ { fence = !fence; next }
    fence { next }

    # The exact heading. Handled before the near-miss rule below so an exact
    # match can never also register as a near miss.
    $0 == want { have = 1; insec = 1; next }

    # Any other h2 ends the section being measured.
    /^## / {
      if (insec) insec = 0
      if (near == "" && $0 ~ /^## (Output|Expected[ \t]+Output)/) near = $0
      next
    }

    insec && $0 ~ /[^ \t]/ { body = 1 }

    END {
      if (!have) { print "missing " (near == "" ? "-" : near); exit }
      if (!body) { print "empty"; exit }
      print "ok"
    }
  ' "$1"
}

discover > "$LIST"

if [ -s "$GONE" ]; then
  printf 'outputs: FAILED, a tracked command file cannot be read:\n' >&2
  sed 's/^/  /' "$GONE" >&2
  printf 'outputs: a dangling symlink, or tracked but deleted from the work\n' >&2
  printf 'outputs: tree. Restore it or "git rm" it. A file that is not there\n' >&2
  printf 'outputs: cannot be checked, and skipping it is not a pass.\n' >&2
  exit 1
fi

TOTAL=0
LINKS=0
BAD=0
BADLIST=""

note_bad() {
  BAD=$((BAD + 1))
  BADLIST="${BADLIST}  FAIL  ${1}"$'\n'
  BADLIST="${BADLIST}          ${2}"$'\n'
}

while IFS= read -r -d '' f; do
  [ -n "$f" ] || continue
  TOTAL=$((TOTAL + 1))
  if [ -L "$f" ]; then
    LINKS=$((LINKS + 1))
  fi

  verdict=$(classify "$f")
  case "$verdict" in
    ok)
      ;;
    empty)
      note_bad "$f" "has \"${HEADING}\" but nothing under it"
      ;;
    "missing -")
      note_bad "$f" "no \"${HEADING}\" section"
      ;;
    missing\ *)
      note_bad "$f" "has \"${verdict#missing }\", which is not \"${HEADING}\""
      ;;
    *)
      note_bad "$f" "could not be classified (awk said: \"${verdict}\")"
      ;;
  esac
done < "$LIST"

if [ "$TOTAL" -eq 0 ]; then
  printf 'outputs: FAILED, no command files were found.\n' >&2
  printf 'outputs: nothing was checked, so nothing passed. This check expects\n' >&2
  printf 'outputs: tracked files matching */commands/*.md.\n' >&2
  exit 1
fi

printf 'outputs: %s command file(s) checked (%s of them symlinks to another command)\n' \
  "$TOTAL" "$LINKS"

if [ "$BAD" -gt 0 ]; then
  printf '%s' "$BADLIST" >&2
  printf 'outputs: %s command file(s) do not say what they write.\n' "$BAD" >&2
  printf 'outputs: add a "%s" section naming what the command leaves behind\n' "$HEADING" >&2
  printf 'outputs: and where. If it writes nothing, say so. See OUTPUTS.md.\n' >&2
  exit 1
fi

printf 'outputs: every command says what it writes\n'
exit 0
