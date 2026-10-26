#!/usr/bin/env bash
# claude-settings.sh: the Claude Code settings that stop AIDA's hooks or its web search (gap row 434).
#
# A hook cannot report that hooks are off, because a blocked hook never runs. So the scripts a
# person already runs read the settings files instead: the machine check, the project check, and
# implement's preconditions. Each sources this file, so each finding is detected in one place.
#
# What it reads, from the mirror's settings reference and its managed settings page:
#   - The managed tier. The server-managed cache, ${CLAUDE_CONFIG_DIR:-~/.claude}/remote-settings.json,
#     ranks first: when it holds a policy key, the files below are skipped ("first-wins"). Otherwise
#     managed-settings.json, then every *.json in managed-settings.d/ in alphabetical order. A later
#     file replaces a single value, and lists combine. The directory is /etc/claude-code on Linux and
#     WSL, /Library/Application Support/ClaudeCode on macOS, and C:\Program Files\ClaudeCode on
#     Windows. AIDA_MANAGED_SETTINGS_DIR replaces it, for a fixture. An MDM profile or a registry
#     value is not a file, so it is not read, and docs/start/install.md names that limit.
#   - The user file ${CLAUDE_CONFIG_DIR:-~/.claude}/settings.json, then <dir>/.claude/settings.json,
#     then the local file. Claude Code reads the local file at the repository root, and in a
#     worktree at the main checkout's root. It stays in <dir> outside a repository, or when the root
#     is the home directory. A local file an older version left in <dir> is read too, below the
#     root's. A later file wins for a single value.
#
# Three findings:
#   - allowManagedHooksOnly true in the managed tier, and managed enabledPlugins does not set AIDA's
#     own plugin@marketplace id to true. The id comes from the install record, never from this file.
#   - disableAllHooks true. In the managed tier it stops every hook. Elsewhere, after precedence, it
#     stops plugin hooks unless managed enabledPlugins force-enables AIDA.
#   - a permissions.deny rule that removes WebFetch or WebSearch, in any file, since a deny at any
#     level holds. A bare tool name and a tool glob such as `*` remove the tool. `WebFetch(domain:*)`
#     keeps the tool and refuses every fetch.
#
# Public:
#
#   ccs_findings <dir>
#     Prints one compact JSON object per finding, {kind, setting, file, stops, still, unchecked,
#     fix}, and nothing on a clean machine. kind is hooks or web. still and unchecked are empty for
#     a web finding.
#
#   ccs_print <dir> [<kind>]
#     Prints each finding as up to five advisory lines, and nothing on a clean machine. A kind keeps
#     the findings of that kind only: research names the web findings alone.
#
# Portability: bash 3.2+ and zsh. This file is a library. Source it; do not run it.
if [ -n "${ZSH_VERSION:-}" ]; then
  case "${ZSH_EVAL_CONTEXT:-}" in
    *:file) : ;;
    *)
      printf 'claude-settings.sh: this is a library, meant to be sourced, not run directly.\n' >&2
      exit 1
      ;;
  esac
elif [ -n "${BASH_VERSION:-}" ] && [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  printf 'claude-settings.sh: this is a library, meant to be sourced, not run directly.\n' >&2
  exit 1
fi

ccs__managed_dir() {
  if [ -n "${AIDA_MANAGED_SETTINGS_DIR:-}" ]; then
    printf '%s' "$AIDA_MANAGED_SETTINGS_DIR"
    return 0
  fi
  case "$(uname -s 2>/dev/null)" in
    Darwin) printf '%s' "/Library/Application Support/ClaudeCode" ;;
    MINGW*|MSYS*|CYGWIN*) cygpath -u 'C:\Program Files\ClaudeCode' 2>/dev/null ;;
    *) printf '%s' "/etc/claude-code" ;;
  esac
}

# AIDA's plugin@marketplace id: the install record's key whose installPath is this plugin's root.
ccs__plugin_id() {
  local record root real
  record="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json"
  root="${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT:-}}"
  real="$(cd "$root" 2>/dev/null && pwd -P)"
  jq -r --arg a "$root" --arg b "$real" \
    '[ (.plugins // {}) | to_entries[] | select(any(.value[]?; .installPath == $a or .installPath == $b)) | .key ][0] // ""' \
    "$record" 2>/dev/null
}

# One {file, scope, doc} line per readable settings file, highest-ranked managed source first, then
# user, project and local, in the order the precedence rules read them.
ccs__sources() {
  local dir="$1" cfg mdir f root
  cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  mdir="$(ccs__managed_dir)"
  ccs__one "$cfg/remote-settings.json" remote
  ccs__one "$mdir/managed-settings.json" managed
  LC_ALL=C ls "$mdir/managed-settings.d" 2>/dev/null | while IFS= read -r f; do
    case "$f" in *.json) ccs__one "$mdir/managed-settings.d/$f" managed ;; esac
  done
  ccs__one "$cfg/settings.json" user
  ccs__one "$dir/.claude/settings.json" project
  root="$(ccs__local_root "$dir")"
  [ "$root" = "$(cd "$dir" 2>/dev/null && pwd -P)" ] || [ "$root" = "$dir" ] || ccs__one "$dir/.claude/settings.local.json" local
  ccs__one "$root/.claude/settings.local.json" local
}

# The folder that holds the local file: the main checkout's root, or <dir> itself outside a
# repository or where that root is the home directory.
ccs__local_root() {
  local common root
  common="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  root="$(cd "$common/.." 2>/dev/null && pwd -P)"
  if [ -z "$common" ] || [ -z "$root" ] || [ "$root" = "$(cd "$HOME" 2>/dev/null && pwd -P)" ]; then
    printf '%s' "$1"
  else
    printf '%s' "$root"
  fi
}

ccs__one() {
  [ -f "$1" ] || return 0
  jq -c --arg f "$1" --arg s "$2" 'select(type == "object") | {file: $f, scope: $s, doc: .}' "$1" 2>/dev/null
}

ccs_findings() {
  local dir="$1" id
  id="$(ccs__plugin_id)"
  ccs__sources "$dir" | jq -sc --arg id "$id" '
    def policy: (keys - ["wslInheritsWindowsSettings", "managedSourcesBehavior"]) | length > 0;
    def last_with($k): [ .[] | select(.doc | has($k)) ] | last;
    ([ .[] | select(.scope == "remote" and (.doc | policy)) ]) as $remote
    | (if ($remote | length) > 0 then $remote else [ .[] | select(.scope == "managed") ] end) as $managed
    | [ .[] | select(.scope == "user" or .scope == "project" or .scope == "local") ] as $mine
    | ($id != "" and ([ $managed[] | select((.doc.enabledPlugins // {}) | has($id)) ] | last | .doc.enabledPlugins[$id]) == true) as $forced
    | (if $id == "" then "AIDA (the install record names no plugin@marketplace id for this copy)" else $id end) as $name
    | {kind: "hooks", stops: "AIDA'"'"'s hooks do not run. No hook refuses an edit to a frozen test, a write outside an order'"'"'s owned files, or a destructive command.",
       still: "build-record checks the frozen tests'"'"' hashes, the owned files and the builder'"'"'s stop lines, after each build.",
       unchecked: "While hooks are off, nothing checks destructive commands, reads of denied source, or writes to the main checkout. Nothing checks a forged person-answer.json or a compact with unsaved work."} as $hooks
    | ($managed | last_with("allowManagedHooksOnly")) as $amho
    | ($managed | last_with("disableAllHooks")) as $mdah
    | ($mine | last_with("disableAllHooks")) as $udah
    | (if $amho != null and $amho.doc.allowManagedHooksOnly == true and ($forced | not) then
         $hooks + {setting: ("allowManagedHooksOnly is true, and managed enabledPlugins does not force-enable " + $name),
                   file: $amho.file,
                   fix: ("The admin adds \"" + (if $id == "" then "<plugin>@<marketplace>" else $id end) + "\": true to enabledPlugins in managed settings.")}
       else empty end),
      (if $mdah != null then
         (if $mdah.doc.disableAllHooks == true then
            $hooks + {setting: "disableAllHooks is true in managed settings, which stops every hook", file: $mdah.file,
                      fix: "The admin removes disableAllHooks from that file. Force-enabling AIDA does not help here."}
          else empty end)
       elif $udah != null and $udah.doc.disableAllHooks == true and ($forced | not) then
         $hooks + {setting: "disableAllHooks is true", file: $udah.file,
                   fix: "Remove disableAllHooks from that file, or set it to false."}
       else empty end),
      (($managed + $mine)[] as $s
       | ($s.doc.permissions.deny // [])[] as $rule
       | ($rule | capture("^(?<n>[^(]+)(\\((?<p>.*)\\))?$") // {n: $rule, p: null}) as $r
       | ("^" + ($r.n | gsub("(?<c>[.+?^$|{}\\[\\]\\\\])"; "\\\(.c)") | gsub("\\*"; ".*")) + "$") as $re
       | ["WebFetch", "WebSearch"][] as $tool
       | select(($tool | test($re)) and ($r.p == null or ($tool == "WebFetch" and $r.p == "domain:*")))
       | (["WebFetch", "WebSearch"] - [$tool])[0] as $other
       | {kind: "web",
          setting: ("permissions.deny holds \"" + $rule + "\", which "
                    + (if $r.p == null then "removes " + $tool else "refuses every " + $tool + " request" end)),
          file: $s.file,
          stops: ("The outward searcher that research, design and review dispatch cannot use " + $tool
                  + ". It keeps " + $other + ", unless another line here names it."),
          still: "", unchecked: "",
          fix: (if $s.scope == "remote" or $s.scope == "managed" then "Only the admin can remove a managed rule."
                else "Remove the rule from that file." end)})
    ' 2>/dev/null
}

ccs_print() {
  ccs_findings "$1" | jq -r --arg kind "${2:-}" 'select($kind == "" or .kind == $kind) |
    "Claude Code setting: " + .setting + ", in " + .file + ".",
    "  What stops: " + .stops,
    (if .still == "" then empty else "  Still checked: " + .still end),
    (if .unchecked == "" then empty else "  Not checked: " + .unchecked end),
    "  Repair: " + .fix'
}
