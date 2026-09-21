#!/usr/bin/env bash
# command-text.sh: reading a shell command as text, before it runs.
#
# Both Bash doors, hooks/deny-frozen-test-writes.sh and hooks/deny-prior-source.sh, read the
# payload's command alike: heredoc bodies dropped, then one segment at a time split into
# words. The two functions lived in the write hook until 2026-09-20 (live-run row 101), when the
# read hook gained its own door and needed them. A hook is a script, not a library, so they moved
# here and both hooks source this file.
#
# Public functions:
#
#   strip_heredocs <command>   prints the command with every heredoc body dropped
#   read_words <line>          fills array w with the whitespace-separated words of the line

# Drops every heredoc body from command $1 before a door reads it. The line holding `<<WORD`,
# `<<-WORD`, `<<'WORD'` or `<<"WORD"` is kept, with its operator and word, so a redirect on it is
# still read. The lines after it, up to and including the line that is exactly WORD, are dropped.
# For `<<-` the shell strips leading tabs from the closing line, so the compare does too. A heredoc
# body is never a write position. Read as commands, it is where PHP's `>=` and YAML's `>-` became
# a refused write (live-run row 95). A heredoc with no closing line drops to the end. A herestring,
# `<<<`, is not a heredoc and is left alone. bash 3.2 and zsh, no mapfile.
strip_heredocs() {
  local line word="" dash=false close q="'\"" tab=$'\t'
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
        word="$(printf '%s' "$line" | sed -n "s/.*<<-\{0,1\}[[:space:]]*[$q]\{0,1\}\([^[:space:]$q;|&)<]*\).*/\1/p")"
        dash=false; case "$line" in *'<<-'*) dash=true ;; esac ;;
    esac
  done
}

# Reads whitespace-separated words from $1 into array w. bash's read takes -a for an array
# target; zsh's own read refuses -a ("bad option") and takes -A instead. The caller sets
# KSH_ARRAYS under zsh so w is indexed from 0 the bash way.
read_words() {
  if [ -n "${ZSH_VERSION:-}" ]; then
    read -r -A w <<<"$1"
  else
    # shellcheck disable=SC2034 # read by the sourcing hook
    read -r -a w <<<"$1"
  fi
}
