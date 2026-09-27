#!/usr/bin/env bash
# The plugin root: the variable when the platform sets it (hooks), else this file's own place.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd -P)}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
# deny-destructive-commands.sh. A PreToolUse hook on Bash, Write, Edit and MultiEdit: refuses
# commands that throw work away or publish it, before they run. The list is version 5's, from
# block-dangerous-commands.sh. Any `git push`, a force push, a hard reset, `git clean`,
# `git branch -D`, `git checkout .` and `git restore .`. A recursive delete of root, the home
# directory, or the working tree. Plain `git push` stays refused because version 6 never
# publishes: completion writes the pull request body and a person pushes. `gh repo sync`, and a
# `gh api` call that changes a `git/refs` path, publish too, so they are refused as well.
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
# - A verb this hook cannot read: a `$` or a backtick where the verb goes. It refuses and says so.
# - A git alias, set by `git config` in any scope or by an inline `-c alias.*=`, whose value is a
#   refused command. The value is read as `git <value>` through the same rules.
# - A command that runs a file: `bash`, `sh`, `zsh`, `dash`, `ksh`, `source` or `.` with a path,
#   or a command word with a slash that names an executable file. The first 256 KiB of the file
#   go through the same rules, three files deep. A file with a NUL byte is a binary, and is not
#   read. A file the hook cannot find or read is allowed.
# - A write to this plugin's own hooks folder. A Write, Edit or MultiEdit whose path falls under
#   it is refused. A Bash command is refused when a segment names the folder together with `>`,
#   `>>`, `tee`, `sed -i`, `cp`, `mv`, `rm`, `chmod` or `ln`. The folder is named as the real path,
#   as `$CLAUDE_PLUGIN_ROOT/hooks`, or as `hooks/` from the plugin root. Without this, an agent
#   could edit the guard away.
#
# False positives. A heredoc body that goes to `cat` or `tee`, or to `git commit -F -`, is not
# read, unless the same command line also starts a shell or runs a file. A refused phrase anywhere
# else is refused, for example inside `git commit -m "..."` or `echo "..."`. Closing that needs the
# shell grammar.
#
# Out of reach:
# - A command word from a variable or a substitution, such as `$g push` or `$(which git) push`.
# - A script generated at run time and run in the same call, other than through a heredoc body.
# - An encoded string, such as base64 piped to a shell.
# - Another language's subprocess call, such as Python or Node running git.
# - An alias whose value is only part of a refused command, completed by the arguments later.
# - A git option this hook does not list, and a wrapper option that takes a value, such as
#   `sudo -u <user>` before a script path.
# - A path to the hooks folder through a symlink, a variable other than CLAUDE_PLUGIN_ROOT, or
#   a relative path from outside the plugin root.
#
# FAIL-OPEN. No jq, empty or unreadable stdin, a payload with no command: allow, silent. A library
# that cannot be read switches off only the rules that need it. A refusal that failed closed would
# refuse every Bash call in the session on a transient fault. That is worse than the command it
# guards against.
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

# The hooks folder, as its real path and as the path the platform gave. An empty HOOKS_DIR
# switches the self-protection rule off.
HOOKS_DIR=""; HOOKS_GIVEN=""; AT_ROOT=false
if [ "$HAVE_PATHS" = true ]; then
  HOOKS_DIR="$(cd "$PLUGIN_ROOT/hooks" 2>/dev/null && pwd -P)"
  case "$PLUGIN_ROOT" in /*) HOOKS_GIVEN="$(normalize_abs "$PLUGIN_ROOT/hooks")" ;; esac
  [ "$(cd "$CWD" 2>/dev/null && pwd -P)" = "$(cd "$PLUGIN_ROOT" 2>/dev/null && pwd -P)" ] && AT_ROOT=true
fi

case "$TOOL" in
  Write|Edit|MultiEdit)
    TARGET="$(jq -r '.tool_input.file_path // empty' <<<"$INPUT" 2>/dev/null)"
    [ -n "$TARGET" ] && [ -n "$HOOKS_DIR" ] || { echo '{}'; exit 0; }
    case "$TARGET" in \~/*) TARGET="$HOME/${TARGET#\~/}" ;; esac
    ABS="$(normalize_abs "$(resolve_against "$TARGET" "$CWD")")"
    # The target may not exist yet, so its parent gives the real path.
    PARENT="$(cd "$(dirname -- "$ABS")" 2>/dev/null && pwd -P)"
    for p in "$ABS" "${PARENT:+$PARENT/$(basename -- "$ABS")}"; do
      [ -n "$p" ] || continue
      if is_under "$p" "$HOOKS_DIR" || { [ -n "$HOOKS_GIVEN" ] && is_under "$p" "$HOOKS_GIVEN"; }; then
        deny "writes to $p, in this plugin's hooks folder, which holds this guard"
      fi
    done
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
# A heredoc opening line whose body goes to a file or to a commit message, never to a shell.
HD_TO_FILE='^[[:space:]]*(cat|tee)[[:space:]][^|]*$|^[[:space:]]*git[[:space:]][^|]*commit[[:space:]][^|]*(-F[[:space:]]*-|--file[=[:space:]]-)([[:space:]]|$)|\$\(cat[[:space:]]*<<'
BSNL=$'\\\n'
MAX_BYTES=262144
MAX_DEPTH=3

hit() { printf '%s' "$1" | grep -Eq -e "$2"; }
normalise() { printf '%s' "$1" | tr -d "'\"\\\\" | tr -s ' \t' ' '; }

# Reads normalised text $1 one command segment at a time. Sets RUNS to the files the segments
# run, one per line. A file run as a command word must be executable, so it carries an `x:`
# prefix. Sets SHELLISH to true when a segment starts a shell, `eval`, or a command word with a
# slash.
scan_runs() {
  local seg i j n c
  RUNS=""; SHELLISH=false
  while IFS= read -r seg; do
    set -f; read_words "$seg"; set +f
    # shellcheck disable=SC2154 # w is filled by read_words, scripts/lib/command-text.sh
    n=${#w[@]}; i=0
    while [ "$i" -lt "$n" ]; do
      case "${w[$i]}" in
        env|command|nohup|sudo|xargs|exec|time|nice|then|do|else|elif|'!'|-*|*=*) i=$((i + 1)) ;;
        *) break ;;
      esac
    done
    [ "$i" -lt "$n" ] || continue
    c="${w[$i]}"
    case "$c" in
      bash|sh|zsh|dash|ksh|source|.|eval)
        SHELLISH=true
        [ "$c" != eval ] || continue
        # Options come before the file. -o takes a value; a -c cluster means inline text, which
        # the rules already read.
        j=$((i + 1))
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
$(printf '%s\n' "$1" | sed -e 's/[;&|(){}`]/\n/g')
SEGMENTS
}

# True when a segment of normalised text $1 names the hooks folder together with a writing command.
self_write() {
  local seg p names redirect word after_sed
  [ -n "$HOOKS_DIR" ] || return 1
  while IFS= read -r seg; do
    names=false; redirect=false
    # shellcheck disable=SC2016 # the variable forms are matched as literal text
    for p in "$HOOKS_DIR" "$HOOKS_GIVEN" '$CLAUDE_PLUGIN_ROOT/hooks' '${CLAUDE_PLUGIN_ROOT}/hooks'; do
      [ -n "$p" ] || continue
      case "$seg" in *"$p"*) names=true ;; esac
      case "$seg" in *">$p"*|*"> $p"*) redirect=true ;; esac
    done
    if [ "$AT_ROOT" = true ]; then
      case " $seg " in *" hooks/"*|*" ./hooks/"*|*" hooks "*) names=true ;; esac
      case "$seg" in *">hooks"*|*"> hooks"*|*">./hooks"*|*"> ./hooks"*) names=true; redirect=true ;; esac
    fi
    [ "$names" = true ] || continue
    [ "$redirect" = false ] || return 0
    set -f; read_words "$seg"; set +f
    after_sed=false
    for word in "${w[@]}"; do
      case "$word" in
        tee|cp|mv|rm|chmod|ln) return 0 ;;
        sed) after_sed=true ;;
        -i*|--in-place*) [ "$after_sed" = false ] || return 0 ;;
      esac
    done
  done <<SEGMENTS
$(printf '%s\n' "$1" | sed -e 's/[;&|]/\n/g')
SEGMENTS
  return 1
}

# The command rules, on normalised text $1. Sets REASON and returns 0 on the first rule that hits.
rules() {
  local t="$1" line
  hit "$t" "${GIT}push$ARGS +(-f|--force)" && { REASON="is a force push"; return 0; }
  if ! push_gate_open; then
    hit "$t" "${GIT}push$END" && { REASON="is a git push, and version 6 never publishes: a person pushes. To let this session push, the person opens the gate: sudo mkdir -p /etc/claude && sudo touch /etc/claude/allow-push"; return 0; }
  fi
  hit "$t" "${GIT}[\$\`]" && { REASON="puts a variable or a command substitution where the git verb goes, so this hook cannot read the verb"; return 0; }
  hit "$t" "${GIT}reset$ARGS +--hard" && { REASON="is a hard reset"; return 0; }
  hit "$t" "${GIT}clean$ARGS +(-[a-zA-Z]*[fxX]|--force)" && { REASON="runs git clean, which deletes untracked files"; return 0; }
  hit "$t" "${GIT}branch$ARGS +-D$END" && { REASON="force-deletes a branch"; return 0; }
  hit "$t" "${GIT}(checkout|restore)( --)? \.$END" && { REASON="discards every uncommitted change in the working tree"; return 0; }
  # A target is matched as a whole argument, so `rm -rf ./build` passes.
  hit "$t" 'rm -f?[rR]f? (/|/\*|~|~/|\.|\./|\*)( |$|;|&|\|)' && { REASON="deletes root, the home directory, or the working tree recursively"; return 0; }
  hit "$t" "${GH}repo +sync$END" && { REASON="runs gh repo sync, which publishes to a remote branch"; return 0; }
  # gh api sends a POST by default once a field is given.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if printf '%s' "$line" | grep -Eiq -e '(-X|--method)( +|=)?(POST|PATCH|PUT|DELETE)' \
      || { ! hit "$line" '(-X|--method)' && hit "$line" ' (-f|-F|--field|--raw-field|--input)( |=)'; }; then
      REASON="calls the GitHub API to change a git ref"; return 0
    fi
  done <<GHAPI
$(printf '%s\n' "$t" | grep -E -e "${GH}api( |$)" | grep -F 'git/refs')
GHAPI
  if [ "$HAVE_TEXT" = true ] && self_write "$t"; then
    REASON="writes to this plugin's hooks folder, which holds this guard"; return 0
  fi
  return 1
}

# Checks command text $1, read $2 files deep. Sets REASON and returns 0 when it is refused.
check_text() {
  local text="$1" depth="$2" stripped n line val f p runs need_x
  text="${text//"$BSNL"/}"
  if [ "$HAVE_TEXT" = true ]; then
    stripped="$(strip_heredocs "$text" "$HD_TO_FILE")"
    scan_runs "$(normalise "$stripped")"
    [ "$SHELLISH" = true ] || text="$stripped"
  fi
  n="$(normalise "$text")"
  rules "$n" && return 0
  [ "$depth" -lt "$MAX_DEPTH" ] || return 1
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    val="$(printf '%s' "$line" | sed -E 's/.*alias\.[^ =]+[ =]//')"
    check_text "$(printf 'git %s' "$val")" $((depth + 1)) && { REASON="sets a git alias whose command $REASON"; return 0; }
  done <<ALIASES
$(printf '%s\n' "$n" | grep -E -e "${GIT}.*alias\.[^ =]+[ =]")
ALIASES
  [ "$HAVE_TEXT" = true ] && [ "$HAVE_PATHS" = true ] || return 1
  scan_runs "$n"
  runs="$RUNS"
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
