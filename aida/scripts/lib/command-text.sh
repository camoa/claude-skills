#!/usr/bin/env bash
# command-text.sh: reading a shell command as text, before it runs.
#
# Both Bash doors, hooks/deny-frozen-test-writes.sh and hooks/deny-prior-source.sh, read the
# payload's command alike: heredoc bodies dropped, then one segment at a time split into
# words. The two functions lived in the write hook until 2026-09-20 (live-run row 101), when the
# read hook gained its own door and needed them. A hook is a script, not a library, so they moved
# here and both hooks source this file. hooks/deny-destructive-commands.sh sources it too.
#
# Public functions:
#
#   strip_heredocs <command> [<pattern>]
#                              prints the command with every heredoc body dropped, or with only
#                              the bodies whose opening line matches the extended regex pattern
#   read_words <line>          fills array w with the whitespace-separated words of the line
#   split_segments <command>   prints the command with one segment per line, split outside quotes
#
# Public value:
#
#   BSNL                       a backslash then a newline, the line continuation a door removes
#                              before it reads a command

# shellcheck disable=SC2034 # read by the sourcing hooks
BSNL=$'\\\n'

# Drops every heredoc body from command $1 before a door reads it. The line holding `<<WORD`,
# `<<-WORD`, `<<'WORD'` or `<<"WORD"` is kept, with its operator and word, so a redirect on it is
# still read. The lines after it, up to and including the line that is exactly WORD, are dropped.
# For `<<-` the shell strips leading tabs from the closing line, so the compare does too. A heredoc
# body is never a write position. Read as commands, it is where PHP's `>=` and YAML's `>-` became
# a refused write (live-run row 95). A heredoc with no closing line drops to the end. A herestring,
# `<<<`, is not a heredoc and is left alone. With pattern $2, a body whose opening line does not
# match it is kept and read. hooks/deny-destructive-commands.sh drops only a body that goes to a
# file or to a commit message. bash 3.2 and zsh, no mapfile.
strip_heredocs() {
  local line word="" dash=false close q="'\"" tab=$'\t' pattern="${2:-}"
  printf '%s\n' "$1" | while IFS= read -r line; do
    if [ -n "$word" ]; then
      close="$line"
      [ "$dash" = true ] && close="${line#"${line%%[!"$tab"]*}"}"
      [ "$close" = "$word" ] && word=""
      continue
    fi
    printf '%s\n' "$line"
    case "$line" in
      *'<<<'*) ;;
      *'<<'*)
        [ -z "$pattern" ] || grep -Eq -e "$pattern" <<<"$line" || continue
        word="$(printf '%s' "$line" | sed -n "s/.*<<-\{0,1\}[[:space:]]*[$q]\{0,1\}\([^[:space:]$q;|&)<]*\).*/\1/p")"
        dash=false; case "$line" in *'<<-'*) dash=true ;; esac ;;
    esac
  done
}

# Reads whitespace-separated words from $1 into array w. bash's read takes -a for an array
# target; zsh's own read refuses -a ("bad option") and takes -A instead. The caller sets
# KSH_ARRAYS under zsh so w is indexed from 0 the bash way. bash splits the unquoted expansion
# instead of a herestring, which costs a temporary file per call: the destructive-command hook
# calls this for every segment of a file a command runs (live-run row 255). Every caller turns
# globbing off first, and IFS is the default, so the words are the same.
read_words() {
  if [ -n "${ZSH_VERSION:-}" ]; then
    read -r -A w <<<"$1"
  else
    # shellcheck disable=SC2034,SC2206 # read by the sourcing hook; the split is the point
    w=($1)
  fi
}

# Prints command $1 with one segment per line: a line break at each `;`, `|`, `&&` and `||` that
# stands outside quotes, except the `|` of the redirect `>|`. So `sed -i 's/a/b/; s/c/d/' f` stays
# one segment (gap row 407). A quote state ends with its line, so an apostrophe in a comment hides
# no later line. A backslash escapes the next character, except inside single quotes; a `$'...'`
# string takes backslash escapes.
# hooks/deny-destructive-commands.sh joins quoted strings with its own quoted_words instead, because
# it must still run when this file cannot be read.
split_segments() {
  printf '%s\n' "$1" | LC_ALL=C awk '{
    out = ""; q = ""; e = 0; n = length($0)
    for (i = 1; i <= n; i++) {
      c = substr($0, i, 1)
      if (c == "\\" && (q != "\047" || e)) { out = out substr($0, i, 2); i++; continue }
      if (q != "") { if (c == q) q = ""; out = out c; continue }
      if (c == "\047" || c == "\"") { q = c; e = (c == "\047" && substr($0, i - 1, 1) == "$"); out = out c; continue }
      if (c == ";" || (c == "|" && substr($0, i - 1, 1) != ">") || (c == "&" && substr($0, i + 1, 1) == "&")) {
        print out; out = ""
        if (c != ";" && substr($0, i + 1, 1) == c) i++
        continue
      }
      out = out c
    }
    print out
  }'
}
