#!/usr/bin/env bash
# The plugin root: the variable when the platform sets it (hooks), else this file's own place.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd -P)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
# deny-destructive-commands.sh. A PreToolUse hook on Bash, Write, Edit and MultiEdit. It reads a
# command that throws work away or publishes it, before the command runs. It also guards its own
# files. The list is version 5's, from block-dangerous-commands.sh.
#
# Two decisions. A write to the guard is refused: this plugin's hooks folder, the two libraries
# this hook sources, and `disableAllHooks` in a `.claude` settings file. Those files enforce the
# frozen tests, the owned files and the person's answer, so a write to them turns those stops off.
# Every other rule asks. Claude Code then shows the person its permission prompt, and the command
# runs only on a yes. The prompt shows in default, acceptEdits, plan and auto mode, and in auto mode
# the classifier cannot approve it. The docs list no prompt for a hook's ask in bypassPermissions,
# and dontAsk denies every call that would prompt. So in those two modes, and in a payload with no
# permission_mode, the command is refused. hooks/deny-frozen-test-writes.sh reads the modes the
# same way in ask_person.
#
# A dispatched role, a payload with agent_id, is refused and never asked. The refusal also sets
# `continue: false`, so the role stops. A builder told to stop on a refusal deleted the refused
# folder one file at a time (gap row 444). A role has no reason to run these commands, and the
# person reads why it stopped.
#
# The commands it asks about. Any `git push`. A hard reset, `git clean`, `git branch -D`, and a
# checkout or restore of the whole working tree. A recursive delete of root, the home directory,
# the working directory, or a folder above them. A recursive delete of the session scratchpad, a
# folder above it, or a glob directly under it: the orchestrator and every agent keep files there
# (live-run row 317). The platform's `scratchpad_dir` names it, and without it this rule is off. A
# folder of an agent's own under the scratchpad passes. `gh repo sync`, `gh pr merge`,
# `gh release create` and `gh release delete`, and a `gh api` call that changes a ref or a file on
# a branch. Version 6 never publishes: completion
# writes the pull request body and a person pushes.
#
# It reads text, not the shell grammar, so it reads the literal forms only. One step makes the
# text that every rule reads. It joins continued lines and removes every `'`, `"` and `\`. Then
# `git "push"`, `git pu''sh`, `git p\ush` and the text of `sh -c '...'` read as plain commands. It
# collapses runs of spaces and tabs.
#
# What it catches, on that text:
# - Global options between `git` and its verb: `-C <path>`, `-c <k=v>`, `--git-dir`,
#   `--work-tree`, `--no-pager`, `--bare`, `-P` and git's other top-level options, for every rule.
# - A wrapper or a path before the command word: `env`, `command`, `nohup`, `sudo -u <user>`,
#   `xargs`, `exec`, `nice -n <n>`, `timeout <duration>`, a subshell's `(`, a group's `{`,
#   `/usr/bin/git`. Any character that cannot be part of a word may come before `git`.
# - A flag in any order, in a cluster, or as the unique prefix git accepts, such as `--har` for
#   `--hard`.
# - A recursive delete that starts the text of `bash -c '...'`, or of another shell's `-c`.
# - A write to the guard. A Write, Edit or MultiEdit under the guard paths is refused. A Bash
#   command is refused when it names one of them with `>`, `>>`, `>|`, `tee`, `sed -i`, `perl -i`,
#   `mv`, `rm`, `chmod` or `truncate`. For `cp`, `ln` and `install` the last word must name it, and
#   for `dd` the `of=` word. The path counts when it is the real path, the path under
#   `$CLAUDE_PLUGIN_ROOT`, or a relative path from the plugin root. When the plugin root cannot be
#   resolved, any path that ends with those file names is refused. The limit: a symlink, another
#   variable, or a relative path from another folder gets past it.
# - A Write, Edit or MultiEdit to a `.claude` settings file whose new text holds `disableAllHooks`.
#
# False positives. A heredoc body that goes to `cat` or `tee`, or to `git commit -F -`, is not
# read, also after `;` or `&&` on its line. The exception is a command line that also starts a
# shell. The recursive delete rule reads a quoted string that opens and closes on one line as one
# word. So the message in `detail="$d $fw: ..."` is not a command (live-run row 254). The push rule
# reads such a string as one word too, except the value of an assignment, which a later `$cmd`
# runs. So `--reasoning "... git push ..."` is not a command (live-run row 377). A string that
# spans lines is read as commands. On a line that holds `eval`, a shell's `-c` flag or `<<<`, every
# string after it is read as commands, because a shell runs it. A `-c` of grep, rg or git is not a
# shell's. The delete rule reads quoted text as commands, so a phrase inside `echo "..."` asks.
# Closing that needs the shell grammar.
#
# Out of reach:
# - A command word from a variable or a substitution, and a git verb this hook cannot read.
# - A git alias, set in the same command or before it.
# - A file the command runs, such as `bash <script>`, and a script generated at run time.
# - An encoded string, such as base64 piped to a shell.
# - A quoted push that a command runs as a shell line with no `-c` flag, such as `watch` or `ssh`.
# - Another language's subprocess call, such as Python or Node running git.
# - A `cd` earlier in the same command line, which changes what a relative delete target names.
# - A delete target from a variable other than `$HOME` and `$PWD`.
# - A git option this hook does not list.
# - A GraphQL query read from a file, and a settings file written through Bash.
# The first three had readers until 6.1.0. They refused at random (live-run rows 254, 321, 330 and
# 331), and they read only what an evasion writes, never an accident.
#
# FAIL-OPEN. No jq, empty or unreadable stdin, a payload with no command: allow, silent. A library
# that cannot be read switches off only the rules that need it. The guard protection is the one
# exception: it falls back to file names. A refusal that failed closed would refuse every Bash call
# in the session on a transient fault. That is worse than the command it guards against.
#
# Override: AIDA_ALLOW_DANGEROUS=1 in the hook's own environment, which is the shell that launched
# this session, allows everything for that session. It is the route for an unattended run that
# must run one of these commands.
#
# Deny and ask are the documented JSON forms (permissionDecision and permissionDecisionReason), on
# exit 0, the same as hooks/deny-frozen-test-writes.sh. A deny reason goes to the model, and an
# ask reason goes to the person.
set -uo pipefail

[ "${AIDA_ALLOW_DANGEROUS:-}" != "1" ] || { echo '{}'; exit 0; }
command -v jq >/dev/null 2>&1 || { echo '{}'; exit 0; }
INPUT="$(cat 2>/dev/null)" || { echo '{}'; exit 0; }
TOOL="$(jq -r '.tool_name // empty' <<<"$INPUT" 2>/dev/null)"
CWD="$(jq -r '.cwd // empty' <<<"$INPUT" 2>/dev/null)"
[ -n "$CWD" ] || CWD="$(pwd -P)"
CWD_REAL="$(cd "$CWD" 2>/dev/null && pwd -P)"
SCRATCH="$(jq -r '.scratchpad_dir // empty' <<<"$INPUT" 2>/dev/null)"
case "$SCRATCH" in /*) ;; *) SCRATCH="" ;; esac
SCRATCH_REAL="$(cd "$SCRATCH" 2>/dev/null && pwd -P)"
SCRATCH_HIT=false
# agent_id is present only inside a subagent, the test hooks/deny-frozen-test-writes.sh uses.
AGENT_ID="$(jq -r '.agent_id // empty' <<<"$INPUT" 2>/dev/null)"
MODE="$(jq -r '.permission_mode // empty' <<<"$INPUT" 2>/dev/null)"

deny() {
  local r="deny-destructive-commands: refused, because the command $1."
  if [ -n "$AGENT_ID" ]; then
    r="$r A dispatched role stops here. Report the command to the person, and do not reach its result another way."
  else
    r="$r Run it yourself if you mean it. AIDA_ALLOW_DANGEROUS=1 in the shell that launched this session turns this hook off."
  fi
  jq -nc --arg r "$r" --arg role "$AGENT_ID" '
    {hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}
    + (if $role == "" then {} else {continue: false, stopReason: $r} end)'
  exit 0
}

# The decision for a command that throws work away or publishes it. $1 the reason.
ask() {
  [ -z "$AGENT_ID" ] || deny "$1"
  case "$MODE" in
    default|acceptEdits|plan|auto)
      jq -nc --arg r "deny-destructive-commands: the command $1. Approve only if you mean it." \
        '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
      exit 0 ;;
  esac
  deny "$1, and this session cannot show a prompt: its permission mode is ${MODE:-not given}"
}

HAVE_PATHS=false; HAVE_TEXT=false
# shellcheck source=/dev/null
source "$PLUGIN_ROOT/scripts/lib/paths.sh" 2>/dev/null && HAVE_PATHS=true
# shellcheck source=/dev/null
source "$PLUGIN_ROOT/scripts/lib/command-text.sh" 2>/dev/null && HAVE_TEXT=true

# The guard's files, relative to the plugin root: this hook's folder and the libraries it sources.
GUARD_NAMES="hooks
scripts/lib/paths.sh
scripts/lib/command-text.sh"
# The file names the protection falls back to when the plugin root cannot be resolved.
GUARD_SUFFIXES="hooks/hooks.json
hooks/deny-destructive-commands.sh
scripts/lib/paths.sh
scripts/lib/command-text.sh"
# GUARD holds each guard path as an absolute path, real and as given. FORMS adds the forms a
# command line names them by. AT_ROOT is true when the working directory is the plugin root.
GUARD=""; FORMS=""; AT_ROOT=false
ROOT_REAL="$(cd "$PLUGIN_ROOT" 2>/dev/null && pwd -P)"
if [ "$HAVE_PATHS" = true ] && [ -n "$ROOT_REAL" ]; then
  while IFS= read -r name; do
    GUARD="$GUARD$ROOT_REAL/$name
"
    case "$PLUGIN_ROOT" in /*) GUARD="$GUARD$(normalize_abs "$PLUGIN_ROOT/$name")
" ;; esac
    # shellcheck disable=SC2016 # the variable forms are matched as literal text
    FORMS="$FORMS"'$CLAUDE_PLUGIN_ROOT/'"$name"'
${CLAUDE_PLUGIN_ROOT}/'"$name"'
'
  done <<NAMES
$GUARD_NAMES
NAMES
  FORMS="$GUARD$FORMS"
  [ "$CWD_REAL" = "$ROOT_REAL" ] && AT_ROOT=true
else
  FORMS="$GUARD_SUFFIXES"
fi
# The forms and the names as arrays, read once, so names_guard starts no subshell for each word.
FORM_LIST=(); NAME_LIST=()
while IFS= read -r f; do [ -z "$f" ] || FORM_LIST+=("$f"); done <<<"$FORMS"
while IFS= read -r f; do [ -z "$f" ] || NAME_LIST+=("$f"); done <<<"$GUARD_NAMES"

# True when absolute path $1 is a guard path, or ends with a guard file name when GUARD is empty.
is_guard() {
  local g
  if [ -n "$GUARD" ]; then
    while IFS= read -r g; do
      [ -n "$g" ] && is_under "$1" "$g" && return 0
    done <<GUARDS
$GUARD
GUARDS
    return 1
  fi
  while IFS= read -r g; do
    case "$1" in */"$g"|"$g") return 0 ;; esac
  done <<GUARDS
$GUARD_SUFFIXES
GUARDS
  return 1
}

case "$TOOL" in
  Write|Edit|MultiEdit)
    TARGET="$(jq -r '.tool_input.file_path // empty' <<<"$INPUT" 2>/dev/null)"
    [ -n "$TARGET" ] || { echo '{}'; exit 0; }
    case "$TARGET" in \~/*) TARGET="$HOME/${TARGET#\~/}" ;; esac
    CANDIDATES="$TARGET"
    if [ "$HAVE_PATHS" = true ]; then
      ABS="$(normalize_abs "$(resolve_against "$TARGET" "$CWD")")"
      # The target may not exist yet, so its parent gives the real path.
      PARENT="$(cd "$(dirname -- "$ABS")" 2>/dev/null && pwd -P)"
      CANDIDATES="$ABS
${PARENT:+$PARENT/$(basename -- "$ABS")}"
    fi
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      is_guard "$p" && deny "writes to $p, which is part of this guard"
    done <<CANDS
$CANDIDATES
CANDS
    case "$TARGET" in
      */.claude/settings.json|*/.claude/settings.local.json|.claude/settings.json|.claude/settings.local.json)
        NEW="$(jq -r '[.tool_input.content, .tool_input.new_string, (.tool_input.edits[]?.new_string)] | map(select(type == "string")) | join("\n")' <<<"$INPUT" 2>/dev/null)"
        case "$NEW" in *disableAllHooks*) deny "sets disableAllHooks in a Claude Code settings file, which turns this guard off" ;; esac ;;
    esac
    echo '{}'; exit 0 ;;
  Bash) ;;
  *) echo '{}'; exit 0 ;;
esac

CMD="$(jq -r '.tool_input.command // empty' <<<"$INPUT" 2>/dev/null)"
[ -n "$CMD" ] || { echo '{}'; exit 0; }

# `git` as a word or at the end of a path, then any of git's top-level options, then the verb. An
# option that takes a value takes the next word or an `=` value.
GIT_OPT='-[Cc] +[^ ;&|]+|--(git-dir|work-tree|namespace|exec-path|super-prefix|config-env|attr-source)(=| +)[^ ;&|]+|--(no-pager|paginate|bare|no-replace-objects|no-lazy-fetch|no-optional-locks|no-advice|literal-pathspecs|glob-pathspecs|noglob-pathspecs|icase-pathspecs|exec-path)|-[pP]'
GIT="(^|[^A-Za-z0-9_.-])git( +($GIT_OPT))* +"
GH="(^|[^A-Za-z0-9_.-])gh +"
ARGS='( +[^ ;&|]+)*'
END='( |$|[;&|)`])'
# git accepts a unique prefix of a long option, so each is matched from its shortest unique form.
HARD='--h(a(r(d)?)?)?'
DELETE='--de(l(e(t(e)?)?)?)?'
# A heredoc opening line whose body goes to a file or to a commit message, never to a shell.
HD_TO_FILE='(^|[;&])[[:space:]]*(cat|tee)[[:space:]][^|;&]*<<[^|;&]*$|(^|[;&])[[:space:]]*git[[:space:]][^|;&]*commit[[:space:]][^|;&]*(-F[[:space:]]*-|--file[=[:space:]]-)[[:space:]][^|;&]*<<[^|;&]*$|\$\(cat[[:space:]]*<<'

# A here-string, not a pipe: under pipefail, grep -q quitting early can kill printf, and a match
# then reads as none. A large here-string needs a writable temp folder. When grep cannot run, the
# count is empty, so the text reads as a match.
hit() { [ "$(grep -Ec -e "$2" <<<"$1")" != 0 ]; }
normalise() { printf '%s' "$1" | tr -d "'\"\\\\" | tr -s ' \t' ' '; }
# Prints text $1 with one command segment per line. tr, not sed, so BSD and GNU agree.
segments() { printf '%s\n' "$1" | tr ';&|' '\n\n\n'; }
# Prints raw text $1 with some quoted strings joined. A joined string has each space, tab, `;`, `&`
# and `|` replaced by \037. Then read_words keeps it in one word, and segments does not split it.
# Only a string that opens and closes on one line is joined. The quote state carries across lines,
# so the text after a string that spans lines is read where the shell closes it. A comment and a
# heredoc body change no quote state. On a line that holds `eval`, `<<<`, or a `-c` flag after a
# shell word (sh, bash, zsh, dash, ksh, su, a path to one), no later string is joined, because a
# shell runs its text. The shell runs the text of each `$(...)` and
# each backtick pair outside single quotes, also inside a double-quoted string. So that text
# follows its line again, as lines of its own. A `#` starts a comment at the start of a word,
# outside a string, a backtick pair and `${...}`, and no substitution is read from it. A `$'...'`
# string takes backslash escapes. A comment ends at its line, also after a backslash.
# With $2 set to args, a string that is the value of an assignment is not joined, because a later
# `$cmd` runs the text of `cmd="git push"`.
quoted_words() {
  printf '%s\n' "$1" | LC_ALL=C awk -v asg="${2:+1}" '
    function close_at(s, k, c, e,   d, depth) {
      depth = 0
      while (k <= length(s)) {
        d = substr(s, k, 1)
        if ((c == "\"" || e) && d == "\\") { k += 2; continue }
        if (c == "\"" && substr(s, k, 2) == "$(") { depth++; k += 2; continue }
        if (depth > 0 && d == ")") { depth--; k++; continue }
        if (d == c && depth == 0) return k
        k++
      }
      return 0
    }
    function subs(s,   r, i, d, depth, st, sq, dq, bt, inner) {
      r = ""; depth = 0; sq = 0; dq = 0; bt = 0
      for (i = 1; i <= length(s); i++) {
        d = substr(s, i, 1)
        if (d == "\\" && !sq) { i++; continue }
        if (depth == 0 && !bt && !dq && d == "\047") { sq = !sq; continue }
        if (sq) continue
        if (depth == 0 && !bt && d == "\"") { dq = !dq; continue }
        if (!bt && substr(s, i, 2) == "$(") { if (depth == 0) st = i + 2; depth++; i++; continue }
        if (depth > 0 && d == "(") { depth++; continue }
        if (depth > 0 && d == ")") {
          if (--depth == 0) { inner = substr(s, st, i - st); r = r "\n" inner subs(inner) }
          continue
        }
        if (depth == 0 && d == "`") {
          if (bt) { inner = substr(s, st, i - st); r = r "\n" inner subs(inner) } else st = i + 1
          bt = !bt
        }
      }
      return r
    }
    {
      line = $0; n = length(line); pc = cont; cont = 0; dol = 0
      if (hd != "") { t = line; sub(/^\t+/, "", t); if (t == hd) hd = ""; print line subs(line); next }
      out = ""; i = 1; pend = ""; code = n
      if (q != "") {
        j = close_at(line, 1, q, qe)
        if (j == 0) { print line subs(line); next }
        out = substr(line, 1, j); i = j + 1; q = ""
      }
      while (i <= n) {
        c = substr(line, i, 1)
        if (c == "\\") { cont = (i == n); out = out substr(line, i, 2); i += 2; continue }
        if (c == "#" && !bt && !br && (i == 1 ? !pc : substr(line, i - 1, 1) ~ /[ \t;&|(]/)) {
          out = out substr(line, i); code = i - 1; break
        }
        if (substr(line, i, 3) == "<<<") { out = out "<<<"; i += 3; continue }
        if (substr(line, i, 2) == "<<") {
          m = substr(line, i + 2); match(m, /^-?[ \t]*["\047]?[^ \t"\047;&|)<>]*["\047]?/)
          w = substr(m, 1, RLENGTH); out = out "<<" w; i += 2 + RLENGTH
          gsub(/^-|[ \t"\047]/, "", w); if (pend == "") pend = w
          continue
        }
        if (c == "\047" || c == "\"") {
          e = (c == "\047" && dol == i - 1)
          j = close_at(line, i + 1, c, e)
          if (j == 0) { out = out substr(line, i); q = c; qe = e; break }
          s = substr(line, i, j - i + 1)
          pre = substr(line, 1, i - 1)
          if (pre !~ /(^|[^A-Za-z0-9_.-])(eval|((ba|z|da|k)?sh|su)([ \t]+-[^ \t]+)*[ \t]+-[A-Za-z]*c)([ \t]|$)|<<</ && !(asg && pre ~ /(^|[ \t;&|(])[A-Za-z_][A-Za-z0-9_]*\+?=[^ \t;&|]*$/)) gsub(/[ \t;&|]/, "\037", s)
          out = out s; i = j + 1; continue
        }
        if (c == "`") bt = !bt
        else if (c == "$") { dol = i; if (substr(line, i + 1, 1) == "{") br++ }
        else if (c == "}" && br) br--
        out = out c; i++
      }
      print out subs(substr(line, 1, code))
      hd = pend
    }'
}

# Sets I to the index in w of the first word after the wrappers, options and assignments that can
# come before a command word. I equals the word count when there is none. A wrapper option that
# takes a value skips that value too: nice -n, sudo -u, -g and -C, timeout -s and -k, and
# timeout's duration. A `(` or `{` that opens a subshell or a group is dropped, also from the front
# of the command word.
# shellcheck disable=SC2154 # w is filled by read_words, scripts/lib/command-text.sh
skip_wrappers() {
  local wrap=""
  I=0
  while [ "$I" -lt "${#w[@]}" ]; do
    case "${w[$I]}" in
      '('|'{') I=$((I + 1)) ;;
      '('*|'{'*) w[I]="${w[$I]#[({]}" ;;
      env|command|nohup|sudo|xargs|exec|time|nice|timeout|then|do|else|elif|'!') wrap="${w[$I]}"; I=$((I + 1)) ;;
      -*)
        case "$wrap:${w[$I]}" in
          nice:-n|sudo:-u|sudo:-g|sudo:-C|timeout:-s|timeout:-k|timeout:--signal|timeout:--kill-after) I=$((I + 2)) ;;
          *) I=$((I + 1)) ;;
        esac ;;
      *=*) I=$((I + 1)) ;;
      [0-9]*) [ "$wrap" = timeout ] || return 0; wrap=""; I=$((I + 1)) ;;
      *) return 0 ;;
    esac
  done
}

# Sets SHELL_WORD to true when a segment of normalised text $1 starts a shell or `eval`. `su`, and
# `sudo` with `-s`, `-i`, `--shell` or `--login`, start one too. A quoted string or a heredoc body
# on that line can then be commands, so it is read as commands. Each loop in this file first drops,
# with one grep, the segments that cannot hit its rule. A bash loop over every segment of a long
# command took most of a minute (live-run row 255).
starts_shell() {
  local seg k sudo c
  SHELL_WORD=false
  while IFS= read -r seg; do
    set -f; read_words "$seg"; set +f
    skip_wrappers
    sudo=false; k=0
    while [ "$k" -lt "$I" ]; do
      case "${w[$k]}" in
        sudo) sudo=true ;;
        --shell|--login|-[si]*|-[!-]*[si]*) [ "$sudo" = false ] || { SHELL_WORD=true; return 0; } ;;
      esac
      k=$((k + 1))
    done
    case "${w[$I]:-}" in */*) c="${w[$I]##*/}" ;; *) c="${w[$I]:-}" ;; esac
    case "$c" in bash|sh|zsh|dash|ksh|source|.|eval|su) SHELL_WORD=true; return 0 ;; esac
  done <<SEGMENTS
$(printf '%s\n' "$1" | tr ';&|(){}`' '\n\n\n\n\n\n\n\n' | grep -E -e 'sh|su|source|eval|(^| )\.( |$)')
SEGMENTS
}

# True when word $1 names a guard path.
names_guard() {
  local f
  [ -n "$1" ] || return 1
  for f in "${FORM_LIST[@]}"; do
    case "$1" in *"$f"*) return 0 ;; esac
  done
  if [ "$AT_ROOT" = true ]; then
    for f in "${NAME_LIST[@]}"; do
      case "$1" in "$f"|"$f"/*|./"$f"|./"$f"/*) return 0 ;; esac
    done
  fi
  return 1
}

# True when a segment of normalised text $1 writes to a guard path.
guard_write() {
  local seg word k named anywhere t sed perl dd copy sed_i perl_i
  while IFS= read -r seg; do
    set -f; read_words "$seg"; set +f
    [ "${#w[@]}" -gt 0 ] || continue
    named=false; anywhere=false; sed=false; perl=false; dd=false; copy=false; sed_i=false; perl_i=false
    for word in "${w[@]}"; do
      case "$word" in
        tee|mv|rm|chmod|truncate) anywhere=true ;;
        sed) sed=true ;;
        perl) perl=true ;;
        dd) dd=true ;;
        cp|ln|install) copy=true ;;
      esac
      case "$word" in -i*|--in-place*) sed_i=true ;; esac
      case "$word" in -*i*) perl_i=true ;; esac
    done
    [ "$sed$sed_i" != truetrue ] || anywhere=true
    [ "$perl$perl_i" != truetrue ] || anywhere=true
    # A segment with no write verb and no `>` cannot write, so its words are not looked up.
    case "$anywhere$dd$copy:$seg" in falsefalsefalse:*'>'*) ;; falsefalsefalse:*) continue ;; esac
    k=0
    while [ "$k" -lt "${#w[@]}" ]; do
      word="${w[$k]}"
      [ "$anywhere" = false ] || ! names_guard "$word" || named=true
      case "$word" in of=*) [ "$dd" = false ] || ! names_guard "${word#of=}" || return 0 ;; esac
      case "$word" in
        *'>'*)
          t="${word##*>}"
          [ -n "$t" ] || t="${w[$((k + 1))]:-}"
          ! names_guard "$t" || return 0 ;;
      esac
      k=$((k + 1))
    done
    [ "$named" = true ] && [ "$anywhere" = true ] && return 0
    # cp, ln and install write only their last word, so reading a guard file passes.
    [ "$copy" = true ] && names_guard "${w[$((${#w[@]} - 1))]}" && return 0
  done <<SEGMENTS
$(segments "${1//'>|'/>}" | grep -E -e 'tee|mv|rm|chmod|truncate|sed|perl|dd|cp|ln|install|>')
SEGMENTS
  return 1
}

# True when recursive-delete target $1 is root, home, the working directory, the scratchpad, or
# above them, or a glob directly under the scratchpad. Sets SCRATCH_HIT to true when the scratchpad
# is what it names.
deletes_home_or_cwd() {
  local r="$1" abs real base dir
  SCRATCH_HIT=false
  case "$r" in
    /|/\*|\~|\~/|\~/\*|.|./|./\*|\*|..|../) return 0 ;;
    '$HOME'|'$HOME/'|'$HOME/*'|'${HOME}'|'${HOME}/'|'$PWD'|'$PWD/'|'$(pwd)'|'$(pwd)/') return 0 ;;
  esac
  [ "$HAVE_PATHS" = true ] || return 1
  case "$r" in
    \~|\~/*) r="$HOME${r#\~}" ;;
    '${HOME}'*) r="$HOME${r#\$\{HOME\}}" ;;
    '$HOME'*) r="$HOME${r#\$HOME}" ;;
    '$PWD'*) r="$CWD${r#\$PWD}" ;;
    '$(pwd)'*) r="$CWD${r#\$(pwd)}" ;;
  esac
  if [ -n "$SCRATCH" ]; then
    case "${r##*/}" in
      *[\*\?\[]*)
        case "$r" in */*) dir="${r%/*}" ;; *) dir=. ;; esac
        dir="$(normalize_abs "$(resolve_against "${dir:-/}" "$CWD")")"
        [ "$dir" = "$(normalize_abs "$SCRATCH")" ] && { SCRATCH_HIT=true; return 0; }
        [ -z "$SCRATCH_REAL" ] || [ "$(cd "$dir" 2>/dev/null && pwd -P)" != "$SCRATCH_REAL" ] || { SCRATCH_HIT=true; return 0; } ;;
    esac
  fi
  r="${r%/\*}"
  case "$r" in *'$'*|*'`'*|*'*'*|*'?'*|'') return 1 ;; esac
  abs="$(normalize_abs "$(resolve_against "$r" "$CWD")")"
  real="$(cd "$abs" 2>/dev/null && pwd -P)"
  for base in "$HOME" "$CWD" "$CWD_REAL" "$(cd "$HOME" 2>/dev/null && pwd -P)" "$SCRATCH" "$SCRATCH_REAL"; do
    [ -n "$base" ] || continue
    # The scratchpad's two forms come last, so a hit from here on names the scratchpad.
    [ "$base" != "$SCRATCH" ] && [ "$base" != "$SCRATCH_REAL" ] || SCRATCH_HIT=true
    base="$(normalize_abs "$base")"
    is_under "$base" "$abs" && return 0
    [ -z "$real" ] || ! is_under "$base" "$real" || return 0
  done
  return 1
}

# True when a segment of normalised text $1 is a recursive rm of a target deletes_home_or_cwd names.
# On a line that starts a shell (starts_shell), any `rm` word may be a command word, since the shell
# runs the text around it: `su -c`, `sh -c`, `eval`, or a string piped to a shell.
recursive_delete() {
  local seg word recursive targets done_opts t j
  while IFS= read -r seg; do
    # `<<<` joined to its word, as in `bash <<<'rm ...'`, is split off.
    seg="${seg//<<</<<< }"
    set -f; read_words "$seg"; set +f
    skip_wrappers
    if [ "$SHELL_WORD" = true ]; then
      j=$I
      while [ "$j" -lt "${#w[@]}" ]; do
        case "${w[$j]}" in rm|*/rm) I=$j; break ;; esac
        j=$((j + 1))
      done
    fi
    [ "$I" -lt "${#w[@]}" ] || continue
    case "${w[$I]}" in rm|*/rm) ;; *) continue ;; esac
    recursive=false; targets=""; done_opts=false
    for word in "${w[@]:$((I + 1))}"; do
      if [ "$done_opts" = false ]; then
        case "$word" in
          --) done_opts=true; continue ;;
          --recursive) recursive=true; continue ;;
          --*) continue ;;
          -*[rR]*) recursive=true; continue ;;
          -*) continue ;;
        esac
      fi
      # The `)` that closes a subshell is not part of the target; `$(pwd)` keeps its own.
      while case "$word" in *'$(pwd)'|*'$(pwd)/') false ;; *')') true ;; *) false ;; esac; do
        word="${word%)}"
      done
      targets="$targets$word
"
    done
    [ "$recursive" = true ] || continue
    while IFS= read -r t; do
      [ -n "$t" ] && deletes_home_or_cwd "$t" && return 0
    done <<TARGETS
$targets
TARGETS
  done <<SEGMENTS
$(segments "$1" | grep -e rm)
SEGMENTS
  return 1
}

# The rules that ask. The delete rule reads $1, the normalised text after quoted_words. The git and
# gh rules read $2, the text after quoted_words args, so a quoted argument that names git, such as
# a reason text or a grep pattern, is not read as a command (live-run row 377). On a line that
# starts a shell, both are the plain normalised text, because `echo "git push" | bash` runs the
# string. Sets REASON and returns 0 on the first rule that hits.
rules() {
  local q="$1" a="$2" line
  hit "$a" "${GIT}push$END" && { REASON="is a git push, and version 6 never publishes: a person pushes"; return 0; }
  hit "$a" "${GIT}reset$ARGS +$HARD$END" && { REASON="is a hard reset"; return 0; }
  hit "$a" "${GIT}clean$ARGS +(-[a-zA-Z]*[fxX]|--f(o(r(c(e)?)?)?)?$END)" && { REASON="runs git clean, which deletes untracked files"; return 0; }
  hit "$a" "${GIT}branch$ARGS +(-[a-zA-Z]*D[a-zA-Z]*|-df|-fd)$END" \
    || hit "$a" "${GIT}branch$ARGS +(-d|$DELETE)$ARGS +(-f|--force)$END" \
    || hit "$a" "${GIT}branch$ARGS +(-f|--force)$ARGS +(-d|$DELETE)$END" \
    && { REASON="force-deletes a branch"; return 0; }
  hit "$a" "${GIT}checkout$ARGS +(\.|\./|:/|-[a-zA-Z]*f[a-zA-Z]*|--force)$END" \
    && { REASON="discards uncommitted changes in the working tree"; return 0; }
  # restore of the whole tree with --staged alone only unstages, so it passes.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if ! hit "$line" ' (-S[a-zA-Z]*|--staged)( |$)' || hit "$line" ' (-[a-zA-Z]*W[a-zA-Z]*|--worktree)( |$)'; then
      REASON="discards uncommitted changes in the working tree"; return 0
    fi
  done <<RESTORE
$(printf '%s\n' "$a" | grep -E -e "${GIT}restore$ARGS +(\.|\./|:/)$END")
RESTORE
  if [ "$HAVE_TEXT" = true ] && recursive_delete "$q"; then
    if [ "$SCRATCH_HIT" = true ]; then
      REASON="deletes the session scratchpad, a folder above it, or a glob directly under it, recursively. Make one folder of your own under the scratchpad, and delete only that folder by its full name"
    else
      REASON="deletes root, the home directory, the working directory, or a folder above them, recursively"
    fi
    return 0
  fi
  hit "$a" "${GH}repo +sync$END" && { REASON="runs gh repo sync, which publishes to a remote branch"; return 0; }
  hit "$a" "${GH}pr +merge$END" && { REASON="runs gh pr merge, which publishes to the base branch"; return 0; }
  hit "$a" "${GH}release +(create|delete)$END" && { REASON="runs gh release create or delete, which publishes or removes a release"; return 0; }
  # gh api sends a POST by default once a field is given.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if grep -Eiq -e '(-X|--method)( +|=)?(POST|PATCH|PUT|DELETE)' <<<"$line" \
      || { ! hit "$line" '(-X|--method)' && hit "$line" ' (-f|-F|--field|--raw-field|--input)( |=)'; }; then
      REASON="calls the GitHub API to change a git ref or a file on a branch"; return 0
    fi
  done <<GHAPI
$(printf '%s\n' "$a" | grep -E -e "${GH}api( |$)" | grep -E -e 'git/refs|/contents/')
GHAPI
  if hit "$a" "${GH}api +graphql" && hit "$a" 'updateRef|createCommitOnBranch|mergePullRequest|deleteRef'; then
    REASON="sends a GitHub GraphQL mutation that changes a branch or merges a pull request"; return 0
  fi
  return 1
}

# Checks command text $1: refuses a write to the guard, and asks about a rule's command.
check_text() {
  local text="$1" stripped n a q
  # BSNL comes from scripts/lib/command-text.sh. The default keeps the join when that file cannot
  # be read. It is set unquoted, because inside double quotes $'...' is not expanded.
  local bsnl=${BSNL:-$'\\\n'}
  text="${text//"$bsnl"/}"
  # Without the library no segment is read, so no line is known to start no shell.
  SHELL_WORD=true
  if [ "$HAVE_TEXT" = true ]; then
    stripped="$(strip_heredocs "$text" "$HD_TO_FILE")"
    starts_shell "$(normalise "$stripped")"
    [ "$SHELL_WORD" = true ] || text="$stripped"
  fi
  n="$(normalise "$text")"
  if [ "$HAVE_TEXT" = true ] && guard_write "$n"; then
    deny "writes to this guard: this plugin's hooks folder or a library the hook sources"
  fi
  # The joined text is read only when git or gh appears, which saves its pass on most calls. A
  # joined option value, as in `git -C "a b" push`, can make a command that the plain text misses.
  a="$n"
  [ "$SHELL_WORD" = true ] || ! hit "$n" "(^|[^A-Za-z0-9_.-])(git|gh) " || a="$(normalise "$(quoted_words "$text" args)")"
  # On a line that starts a shell, a quoted string may be a command, so the delete rule reads the
  # plain text, as the push rule does.
  q="$n"
  [ "$SHELL_WORD" = true ] || q="$(normalise "$(quoted_words "$text")")"
  REASON=""
  rules "$q" "$a" && ask "$REASON"
}

check_text "$CMD"

echo '{}'
exit 0
