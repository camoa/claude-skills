#!/usr/bin/env bash
# builder-lines.sh: the builder's stop and deviation lines, read from its answers file.
#
# build-record reads them to decide exits 105 and 106. hooks/require-stop-lines.sh reads them when
# the implementer returns, because a builder once wrote both lines in its returned text and not in
# the file (gap row 304). The returned text is not recorded anywhere a script can read, so the hook
# sends the builder back to its file before it returns. Both read one parser and one rule.
#
# Public functions:
#
#   br_marked_lines <file> <key>        each line that starts with the key, such as stop
#   br_none_with_text <file>            each stop or deviation line that is none plus more text
#   br_deviations <file>                each deviation the file names, other than none
#   br_lines_fault <answers> [<iface>]  prints why build-record refuses at 106, or nothing
#
# Takes nothing from its caller and refuses nothing. Portability: bash 3.2+ and zsh.

# Prints each line of a builder's file that starts with one key, such as `stop`, in any case.
# Markdown emphasis and a list marker are dropped first, so `- **Stop:** none` counts. A heading
# never counts, so a `# stop:` comment in a code block is not the stop line. $1 the file, $2 the key.
# A value of none with a trailing full stop prints as none alone.
br_marked_lines() {
  sed -e 's/\*//g' -e 's/^[[:space:]]*//' -e 's/^-[[:space:]]*//' "$1" 2>/dev/null \
    | grep -i "^$2:" \
    | sed -e 's/^\([^:]*:\)[[:space:]]*\([Nn][Oo][Nn][Ee]\)[[:space:]]*[.]\{0,1\}[[:space:]]*$/\1 \2/'
}

# Prints each stop or deviation line whose value is none followed by more text. The live builder
# wrote "Deviation: none. The three changes are named by design paragraph (17)" (gap row 298).
# Such a line is neither none nor a deviation, and no script can tell which the text means, so
# build-record refuses it. "nonexistent" does not start the value with the word none. $1 the file.
br_none_with_text() {
  { br_marked_lines "$1" stop; br_marked_lines "$1" deviation; } \
    | grep -i '^[^:]*:[[:space:]]*none[^[:alnum:]]'
}

# Prints each deviation a builder's file names, other than none: its deviation lines, and every
# heading whose text starts with "Deviation". The live builder wrote a section headed "Deviation
# from the module's DI convention" (gap row 221). $1 the file.
br_deviations() {
  { br_marked_lines "$1" deviation
    grep -i '^[[:space:]]*#[#]*[[:space:]]*[*]*deviation' "$1" 2>/dev/null \
      | sed -e 's/\*//g' -e 's/^[[:space:]]*#[#]*[[:space:]]*//'
  } | grep -v -i '^deviations*:[[:space:]]*none[[:space:]]*$'
}

# Prints the sentence that says why the lines are unusable, and returns 1 for a none line with
# text, 2 for a stop count other than one, 3 for a deviation count other than one under
# `Stop: none`. Prints nothing and returns 0 when the lines can be read. A deviation named in
# either file stands for the deviation line. $1 the answers file, $2 the interface record, if any.
br_lines_fault() {
  local f line count
  for f in "$1" "${2:-}"; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    line="$(br_none_with_text "$f" | head -n 1)"
    [ -z "$line" ] || {
      printf "%s holds the line '%s'. A stop or deviation line reads none alone, or names its cause, so this line is neither." "$f" "$line"
      return 1
    }
  done
  count="$(br_marked_lines "$1" stop | grep -c '.')"
  [ "$count" = "1" ] || {
    printf "%s holds %s stop lines, and it must hold exactly one: 'Stop: none', or 'Stop: <cause>: <reason>'." "$1" "$count"
    return 2
  }
  br_marked_lines "$1" stop | grep -q -i '^stop: none$' || return 0
  [ -z "$(br_deviations "$1")" ] || return 0
  [ -z "${2:-}" ] || [ ! -f "$2" ] || [ -z "$(br_deviations "$2")" ] || return 0
  count="$(br_marked_lines "$1" deviation | grep -c '.')"
  [ "$count" = "1" ] || {
    printf "%s holds %s deviation lines, and it must hold exactly one: 'Deviation: none', or 'Deviation: <what>: <why>'." "$1" "$count"
    return 3
  }
}
