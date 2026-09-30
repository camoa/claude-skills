#!/usr/bin/env bash
# The plugin root: the variable when the platform sets it (hooks), else this file's own place.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd -P)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
# deny-destructive-commands.sh. A PreToolUse hook on Bash, Write, Edit and MultiEdit: refuses
# commands that throw work away or publish it, before they run. The list is version 5's, from
# block-dangerous-commands.sh. Any `git push`, a force push, a hard reset, `git clean`,
# `git branch -D`, and a checkout or restore of the whole working tree. A recursive delete of
# root, the home directory, the working directory, or a folder above them. Plain `git push` stays
# refused because version 6 never publishes: completion writes the pull request body and a person
# pushes. `gh repo sync`, `gh pr merge`, and a `gh api` call that changes a ref or a file on a
# branch publish too, so they are refused as well.
#
# The owner's goal: a deterministic way to keep a rogue agent from forcing dangerous work. It is
# best effort, because it reads text, not the shell grammar. One step makes the text that every
# rule reads. It joins continued lines and removes every `'`, `"` and `\`. Then `git "push"`,
# `git pu''sh`, `git p\ush` and the text of `sh -c '...'` read as plain commands. It collapses
# runs of spaces and tabs.
#
# What it catches, on that text:
# - Global options between `git` and its verb: `-C <path>`, `-c <k=v>`, `--git-dir`,
#   `--work-tree`, `--no-pager`, `--bare`, `-P` and git's other top-level options, for every rule.
# - A wrapper or a path before `git`: `env`, `command`, `nohup`, `sudo`, `xargs`, `exec`,
#   `/usr/bin/git`. Any character that cannot be part of a word may come before `git`.
# - A flag in any order, in a cluster, or as the unique prefix git accepts, such as `--har` for
#   `--hard` and `--forc` for `--force`.
# - Every form of force push, also with the push gate open: a flag cluster holding `f`, a `+`
#   refspec, `--mirror`, `--delete`, `-d`, and a `:ref` refspec.
# - A verb this hook cannot read: a `$`, a `{` or a backtick in the verb word. A command word from
#   a variable or a substitution, followed by push, a hard reset, clean or a forced branch delete.
#   It refuses both and says so.
# - A git alias set in the same command, by `git config` in any scope or by an inline
#   `-c alias.*=`. It is refused when its value is a refused command, or starts with push or
#   clean, or is a bare reset. An alias set earlier is not read.
# - A command that runs a file: `bash`, `sh`, `zsh`, `dash`, `ksh`, `source` or `.` with a path,
#   or a command word with a slash that names an executable file. The first 256 KiB of the file
#   go through the same rules, three files deep. A file with a NUL byte is a binary, and is not
#   read. A file the hook cannot find or read is allowed.
# - A write to the guard: this plugin's hooks folder and the two libraries this hook sources. A
#   Write, Edit or MultiEdit under them is refused. A Bash command is refused when it names one of
#   them with `>`, `>>`, `>|`, `tee`, `sed -i`, `perl -i`, `mv`, `rm`, `chmod` or `truncate`. For
#   `cp`, `ln` and `install` the last word must name it, and for `dd` the `of=` word. The path
#   counts when it is the real path, the path under `$CLAUDE_PLUGIN_ROOT`, or a relative path from
#   the plugin root. When the plugin root cannot be resolved, any path that ends with those file
#   names is refused. The limit: a symlink, another variable, or a relative path from another
#   folder gets past it.
# - A Write, Edit or MultiEdit to a `.claude` settings file whose new text holds `disableAllHooks`.
#
# False positives. A heredoc body that goes to `cat` or `tee`, or to `git commit -F -`, is not
# read. The exception is a command line that also starts a shell or runs a file. Two rules find a
# command word: a command word from a variable, and a recursive delete. They read a quoted string
# that opens and closes on one line as part of one word. So the message in `detail="$d $fw: ..."`
# is not a command (live-run row 254). A string that spans lines is read as commands. On a line
# that holds `eval`, a `-c` flag or `<<<`, every string after it is read as commands, because a
# shell runs it. The other rules read quoted text as commands. A refused phrase
# anywhere else is refused, for example inside `git commit -m "..."` or `echo "..."`. Closing that
# needs the shell grammar.
#
# Out of reach:
# - A script generated at run time and run in the same call, other than through a heredoc body.
# - An encoded string, such as base64 piped to a shell.
# - Another language's subprocess call, such as Python or Node running git.
# - An alias set before this command, and then used.
# - A command word from a variable followed by a verb this hook does not list.
# - A `cd` earlier in the same command line, which changes what a relative delete target names.
# - A delete target from a variable other than `$HOME` and `$PWD`.
# - A git option this hook does not list, and a wrapper option that takes a value, such as
#   `sudo -u <user>` before a script path.
# - A GraphQL query read from a file, and a settings file written through Bash.
#
# FAIL-OPEN. No jq, empty or unreadable stdin, a payload with no command: allow, silent. A library
# that cannot be read switches off only the rules that need it. The guard protection is the one
# exception: it falls back to file names. A refusal that failed closed would refuse every Bash call
# in the session on a transient fault. That is worse than the command it guards against.
#
# Override: AIDA_ALLOW_DANGEROUS=1 in the hook's own environment, which is the shell that launched
# this session, allows everything for that session.
#
# The plain push alone has a gate a person opens on their own machine: one file,
# /etc/claude/allow-push, owned by root. Only sudo can create it, so the model cannot open the
# gate from a tool call. Open: `sudo mkdir -p /etc/claude && sudo touch /etc/claude/allow-push`.
# Close: `sudo rm /etc/claude/allow-push`. A force push stays refused with the gate open.
#
# Deny is the documented JSON form (permissionDecision: deny, permissionDecisionReason shown to
# the model), on exit 0, the same as hooks/deny-frozen-test-writes.sh.
set -uo pipefail

[ "${AIDA_ALLOW_DANGEROUS:-}" != "1" ] || { echo '{}'; exit 0; }
command -v jq >/dev/null 2>&1 || { echo '{}'; exit 0; }
INPUT="$(cat 2>/dev/null)" || { echo '{}'; exit 0; }
TOOL="$(jq -r '.tool_name // empty' <<<"$INPUT" 2>/dev/null)"
CWD="$(jq -r '.cwd // empty' <<<"$INPUT" 2>/dev/null)"
[ -n "$CWD" ] || CWD="$(pwd -P)"
CWD_REAL="$(cd "$CWD" 2>/dev/null && pwd -P)"

deny() {
  jq -nc --arg r "deny-destructive-commands: refused, because the command $1. Run it yourself if you mean it. AIDA_ALLOW_DANGEROUS=1 in the shell that launched this session turns this hook off." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
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

# The gate is open when the flag exists and root owns it. GNU stat and BSD stat spell the owner
# flag differently, so both are tried.
PUSH_GATE="/etc/claude/allow-push"
push_gate_open() {
  local owner
  [ -f "$PUSH_GATE" ] || return 1
  owner="$(stat -c %u "$PUSH_GATE" 2>/dev/null || stat -f %u "$PUSH_GATE" 2>/dev/null)"
  [ "$owner" = "0" ]
}

# `git` as a word or at the end of a path, then any of git's top-level options, then the verb. An
# option that takes a value takes the next word or an `=` value.
GIT_OPT='-[Cc] +[^ ;&|]+|--(git-dir|work-tree|namespace|exec-path|super-prefix|config-env|attr-source)(=| +)[^ ;&|]+|--(no-pager|paginate|bare|no-replace-objects|no-lazy-fetch|no-optional-locks|no-advice|literal-pathspecs|glob-pathspecs|noglob-pathspecs|icase-pathspecs|exec-path)|-[pP]'
GIT="(^|[^A-Za-z0-9_.-])git( +($GIT_OPT))* +"
GH="(^|[^A-Za-z0-9_.-])gh +"
ARGS='( +[^ ;&|]+)*'
END='( |$|[;&|)`])'
# git accepts a unique prefix of a long option, so each is matched from its shortest unique form.
HARD='--h(a(r(d)?)?)?'
FORCE='--fo(r(c(e[^ ;&|]*)?)?)?'
DELETE='--de(l(e(t(e)?)?)?)?'
MIRROR='--mi(r(r(o(r)?)?)?)?'
# A heredoc opening line whose body goes to a file or to a commit message, never to a shell.
HD_TO_FILE='^[[:space:]]*(cat|tee)[[:space:]][^|]*$|^[[:space:]]*git[[:space:]][^|]*commit[[:space:]][^|]*(-F[[:space:]]*-|--file[=[:space:]]-)([[:space:]]|$)|\$\(cat[[:space:]]*<<'
BSNL=$'\\\n'
MAX_BYTES=262144
MAX_DEPTH=3

hit() { printf '%s' "$1" | grep -Eq -e "$2"; }
normalise() { printf '%s' "$1" | tr -d "'\"\\\\" | tr -s ' \t' ' '; }
# Prints text $1 with one command segment per line. tr, not sed, so BSD and GNU agree.
segments() { printf '%s\n' "$1" | tr ';&|' '\n\n\n'; }
# Prints raw text $1 with some quoted strings joined. A joined string has each space, tab, `;`, `&`
# and `|` replaced by \037. Then read_words keeps it in one word, and segments does not split it.
# Only a string that opens and closes on one line is joined. The quote state carries across lines,
# so the text after a string that spans lines is read where the shell closes it. A comment and a
# heredoc body change no quote state. On a line that holds `eval`, a `-c` flag or `<<<`, no later
# string is joined, because a shell runs its text. The shell runs the text of each `$(...)` and
# each backtick pair outside single quotes, also inside a double-quoted string. So that text
# follows its line again, as lines of its own.
quoted_words() {
  printf '%s\n' "$1" | LC_ALL=C awk '
    function close_at(s, k, c,   d, depth) {
      depth = 0
      while (k <= length(s)) {
        d = substr(s, k, 1)
        if (c == "\"" && d == "\\") { k += 2; continue }
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
      line = $0; n = length(line)
      if (hd != "") { t = line; sub(/^\t+/, "", t); if (t == hd) hd = ""; print line subs(line); next }
      out = ""; i = 1; pend = ""; code = n
      if (q != "") {
        j = close_at(line, 1, q)
        if (j == 0) { print line subs(line); next }
        out = substr(line, 1, j); i = j + 1; q = ""
      }
      while (i <= n) {
        c = substr(line, i, 1)
        if (c == "\\") { out = out substr(line, i, 2); i += 2; continue }
        if (c == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[ \t;&|(]/)) { out = out substr(line, i); code = i - 1; break }
        if (substr(line, i, 3) == "<<<") { out = out "<<<"; i += 3; continue }
        if (substr(line, i, 2) == "<<") {
          m = substr(line, i + 2); match(m, /^-?[ \t]*["\047]?[^ \t"\047;&|)<>]*["\047]?/)
          w = substr(m, 1, RLENGTH); out = out "<<" w; i += 2 + RLENGTH
          gsub(/^-|[ \t"\047]/, "", w); if (pend == "") pend = w
          continue
        }
        if (c == "\047" || c == "\"") {
          j = close_at(line, i + 1, c)
          if (j == 0) { out = out substr(line, i); q = c; break }
          s = substr(line, i, j - i + 1)
          if (substr(line, 1, i - 1) !~ /(^|[^A-Za-z0-9_])(eval|-[A-Za-z]*c)([ \t]|$)|<<</) gsub(/[ \t;&|]/, "\037", s)
          out = out s; i = j + 1; continue
        }
        out = out c; i++
      }
      print out subs(substr(line, 1, code))
      hd = pend
    }'
}

# Sets I to the index in w of the first word after the wrappers, options and assignments that can
# come before a command word. I equals the word count when there is none.
# shellcheck disable=SC2154 # w is filled by read_words, scripts/lib/command-text.sh
skip_wrappers() {
  I=0
  while [ "$I" -lt "${#w[@]}" ]; do
    case "${w[$I]}" in
      env|command|nohup|sudo|xargs|exec|time|nice|then|do|else|elif|'!'|-*|*=*) I=$((I + 1)) ;;
      *) return 0 ;;
    esac
  done
}

# Reads normalised text $1 one command segment at a time. Sets RUNS to the files the segments
# run, one per line. A file run as a command word must be executable, so it carries an `x:`
# prefix. Sets SHELLISH to true when a segment starts a shell, `eval`, or a command word with a
# slash. Each loop in this file first drops, with one grep, the segments that cannot hit its rule.
# A bash loop over every segment of a 256 KiB file took most of a minute (live-run row 255).
scan_runs() {
  local seg j n c
  RUNS=""; SHELLISH=false
  while IFS= read -r seg; do
    set -f; read_words "$seg"; set +f
    # shellcheck disable=SC2154 # w is filled by read_words, scripts/lib/command-text.sh
    n=${#w[@]}
    skip_wrappers
    [ "$I" -lt "$n" ] || continue
    c="${w[$I]}"
    case "$c" in
      bash|sh|zsh|dash|ksh|source|.|eval)
        SHELLISH=true
        [ "$c" != eval ] || continue
        # Options come before the file. -o takes a value; a -c cluster means inline text, which
        # the rules already read.
        j=$((I + 1))
        while [ "$j" -lt "$n" ]; do
          case "${w[$j]}" in
            -o|+o) j=$((j + 2)) ;;
            --*) j=$((j + 1)) ;;
            -*c*) j=$n ;;
            -*) j=$((j + 1)) ;;
            *) break ;;
          esac
        done
        [ "$j" -ge "$n" ] || RUNS="$RUNS${w[$j]}
" ;;
      */*) SHELLISH=true; RUNS="${RUNS}x:$c
" ;;
    esac
  done <<SEGMENTS
$(printf '%s\n' "$1" | tr ';&|(){}`' '\n\n\n\n\n\n\n\n' | grep -E -e '/|sh|source|eval|(^| )\.( |$)')
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

# True when recursive-delete target $1 is root, home, the working directory, or above them.
deletes_home_or_cwd() {
  local r="$1" abs real base
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
  r="${r%/\*}"
  case "$r" in *'$'*|*'`'*|*'*'*|*'?'*|'') return 1 ;; esac
  abs="$(normalize_abs "$(resolve_against "$r" "$CWD")")"
  real="$(cd "$abs" 2>/dev/null && pwd -P)"
  for base in "$HOME" "$CWD" "$CWD_REAL" "$(cd "$HOME" 2>/dev/null && pwd -P)"; do
    [ -n "$base" ] || continue
    base="$(normalize_abs "$base")"
    is_under "$base" "$abs" && return 0
    [ -z "$real" ] || ! is_under "$base" "$real" || return 0
  done
  return 1
}

# True when a segment of normalised text $1 is a recursive rm of a target deletes_home_or_cwd names.
recursive_delete() {
  local seg word recursive targets done_opts t
  while IFS= read -r seg; do
    set -f; read_words "$seg"; set +f
    skip_wrappers
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

# True when a segment of normalised text $1 has a command word from a variable or a substitution,
# followed by a refused verb. Sets VAR_VERB to the verb.
variable_command() {
  local seg rest
  while IFS= read -r seg; do
    set -f; read_words "$seg"; set +f
    skip_wrappers
    [ "$I" -lt "${#w[@]}" ] || continue
    case "${w[$I]}" in '$'*) ;; *) continue ;; esac
    rest=" ${w[*]:$((I + 1))}"
    VAR_VERB=""
    if hit "$rest" " push$ARGS +(-[a-zA-Z]*f[a-zA-Z]*|$FORCE)( |$)"; then VAR_VERB="push"
    elif ! push_gate_open && hit "$rest" " push( |$)"; then VAR_VERB="push"
    elif hit "$rest" " reset$ARGS +$HARD( |$)"; then VAR_VERB="reset --hard"
    elif hit "$rest" " clean( |$)"; then VAR_VERB="clean"
    elif hit "$rest" " branch$ARGS +-D( |$)" || hit "$rest" " branch$ARGS +(-d|$DELETE)$ARGS +(-f|--force)( |$)"; then VAR_VERB="branch -D"
    fi
    [ -z "$VAR_VERB" ] || return 0
  done <<SEGMENTS
$(segments "$1" | grep -E -e '\$' | grep -E -e 'push|reset|clean|branch')
SEGMENTS
  return 1
}

# The command rules, on normalised text $1, and on $2, the same text normalised after quoted_words.
# Sets REASON and returns 0 on the first rule that hits.
rules() {
  local t="$1" q="$2" line
  hit "$t" "${GIT}push$ARGS +(-[a-zA-Z]*[fd][a-zA-Z]*|$FORCE|$MIRROR|$DELETE|\+[^ ;&|]+|:[^ ;&|]+)$END" \
    && { REASON="is a force push, a mirror push, or a delete of a remote branch"; return 0; }
  if ! push_gate_open; then
    hit "$t" "${GIT}push$END" && { REASON="is a git push, and version 6 never publishes: a person pushes. To let this session push, the person opens the gate: sudo mkdir -p /etc/claude && sudo touch /etc/claude/allow-push"; return 0; }
  fi
  hit "$t" "${GIT}([\$\`]|[^- ;&|][^ ;&|]*[\$\`{])" && { REASON="puts a variable, a brace or a command substitution in the git verb, so this hook cannot read the verb"; return 0; }
  if [ "$HAVE_TEXT" = true ] && variable_command "$q"; then
    REASON="takes its command word from a variable or a substitution, followed by $VAR_VERB, so this hook cannot read the command"; return 0
  fi
  hit "$t" "${GIT}reset$ARGS +$HARD$END" && { REASON="is a hard reset"; return 0; }
  hit "$t" "${GIT}clean$ARGS +(-[a-zA-Z]*[fxX]|--f(o(r(c(e)?)?)?)?$END)" && { REASON="runs git clean, which deletes untracked files"; return 0; }
  hit "$t" "${GIT}branch$ARGS +(-[a-zA-Z]*D[a-zA-Z]*|-df|-fd)$END" \
    || hit "$t" "${GIT}branch$ARGS +(-d|$DELETE)$ARGS +(-f|--force)$END" \
    || hit "$t" "${GIT}branch$ARGS +(-f|--force)$ARGS +(-d|$DELETE)$END" \
    && { REASON="force-deletes a branch"; return 0; }
  hit "$t" "${GIT}checkout$ARGS +(\.|\./|:/|-[a-zA-Z]*f[a-zA-Z]*|--force)$END" \
    && { REASON="discards uncommitted changes in the working tree"; return 0; }
  # restore of the whole tree with --staged alone only unstages, so it passes.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if ! hit "$line" ' (-S[a-zA-Z]*|--staged)( |$)' || hit "$line" ' (-[a-zA-Z]*W[a-zA-Z]*|--worktree)( |$)'; then
      REASON="discards uncommitted changes in the working tree"; return 0
    fi
  done <<RESTORE
$(printf '%s\n' "$t" | grep -E -e "${GIT}restore$ARGS +(\.|\./|:/)$END")
RESTORE
  if [ "$HAVE_TEXT" = true ] && recursive_delete "$q"; then
    REASON="deletes root, the home directory, the working directory, or a folder above them, recursively"; return 0
  fi
  hit "$t" "${GH}repo +sync$END" && { REASON="runs gh repo sync, which publishes to a remote branch"; return 0; }
  hit "$t" "${GH}pr +merge$END" && { REASON="runs gh pr merge, which publishes to the base branch"; return 0; }
  # gh api sends a POST by default once a field is given.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if printf '%s' "$line" | grep -Eiq -e '(-X|--method)( +|=)?(POST|PATCH|PUT|DELETE)' \
      || { ! hit "$line" '(-X|--method)' && hit "$line" ' (-f|-F|--field|--raw-field|--input)( |=)'; }; then
      REASON="calls the GitHub API to change a git ref or a file on a branch"; return 0
    fi
  done <<GHAPI
$(printf '%s\n' "$t" | grep -E -e "${GH}api( |$)" | grep -E -e 'git/refs|/contents/')
GHAPI
  if hit "$t" "${GH}api +graphql" && hit "$t" 'updateRef|createCommitOnBranch|mergePullRequest|deleteRef'; then
    REASON="sends a GitHub GraphQL mutation that changes a branch or merges a pull request"; return 0
  fi
  if [ "$HAVE_TEXT" = true ] && guard_write "$t"; then
    REASON="writes to this guard: this plugin's hooks folder or a library the hook sources"; return 0
  fi
  return 1
}

# Checks command text $1, read $2 files deep. Sets REASON and returns 0 when it is refused.
check_text() {
  local text="$1" depth="$2" stripped n n0="" line val f p runs runs0="" need_x
  text="${text//"$BSNL"/}"
  if [ "$HAVE_TEXT" = true ]; then
    stripped="$(strip_heredocs "$text" "$HD_TO_FILE")"
    n0="$(normalise "$stripped")"
    scan_runs "$n0"
    runs0="$RUNS"
    [ "$SHELLISH" = true ] || text="$stripped"
  fi
  n="$(normalise "$text")"
  rules "$n" "$(normalise "$(quoted_words "$text")")" && return 0
  [ "$depth" -lt "$MAX_DEPTH" ] || return 1
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    val="$(printf '%s' "$line" | sed -E 's/.*alias\.[^ =]+[ =]//; s/ +$//')"
    # A value the later arguments complete: push or clean with any flag, or reset with none.
    case "$val" in
      push|push\ *|clean|clean\ *|reset) REASON="sets a git alias to $val, which later arguments can turn into a refused command"; return 0 ;;
    esac
    check_text "$(printf 'git %s' "$val")" $((depth + 1)) && { REASON="sets a git alias whose command $REASON"; return 0; }
  done <<ALIASES
$(printf '%s\n' "$n" | grep -E -e "${GIT}.*alias\.[^ =]+[ =]")
ALIASES
  [ "$HAVE_TEXT" = true ] && [ "$HAVE_PATHS" = true ] || return 1
  # The first scan read the same text when no heredoc body was kept, so its result stands.
  if [ "$n" = "$n0" ]; then runs="$runs0"; else scan_runs "$n"; runs="$RUNS"; fi
  while IFS= read -r f; do
    need_x=false
    case "$f" in x:*) need_x=true; f="${f#x:}" ;; esac
    case "$f" in ''|*'$'*|*'*'*|*'?'*) continue ;; \~/*) f="$HOME/${f#\~/}" ;; esac
    p="$(normalize_abs "$(resolve_against "$f" "$CWD")")"
    [ -f "$p" ] && [ -r "$p" ] || continue
    [ "$need_x" = false ] || [ -x "$p" ] || continue
    [ "$(head -c "$MAX_BYTES" "$p" | wc -c)" = "$(head -c "$MAX_BYTES" "$p" | LC_ALL=C tr -d '\000' | wc -c)" ] || continue
    if check_text "$(head -c "$MAX_BYTES" "$p")" $((depth + 1)); then
      REASON="runs the file $p, which holds a command that $REASON"; return 0
    fi
  done <<RUNS
$runs
RUNS
  return 1
}

REASON=""
check_text "$CMD" 0 && deny "$REASON"

echo '{}'
exit 0
