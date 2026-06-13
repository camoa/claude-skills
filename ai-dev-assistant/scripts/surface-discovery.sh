#!/usr/bin/env bash
# surface-discovery.sh — enumerate visual-regression coverage candidates from
# project context (ai-dev-assistant v4.13.0, Task C).
#
# Usage: surface-discovery.sh <codePath> [--drush-path <cmd>]
#
#   <codePath>      absolute path to the Drupal project root
#   --drush-path    drush invocation override (default: `ddev drush` when a
#                   .ddev/config.yaml is present and `ddev` is on PATH, else
#                   `drush`). Pass `none` to disable all drush-backed discovery.
#
# Output: a JSON object on stdout with two grouped candidate lists:
#   {"frontend": [ {id,url,source,priority}, ... ],
#    "admin":    [ {id,url,source,priority}, ... ]}
#
# Every discovery method is best-effort: any failure yields an empty list for
# that source, never a script error. The calling command (Claude) formats this
# JSON into a user-facing prompt — front-end default-ON, admin default-OFF — and
# the user edits/confirms before anything is written to registry.yml.
#
# Exit code: 0 always (recoverable issues just yield fewer candidates).
#
# This script does NOT parse or write registry.yml. It only reads project
# config files and (best-effort) queries drush.

set -uo pipefail

CODE_PATH="${1:-}"
DRUSH_CMD=""

emit() {
  jq -nc --argjson fe "$1" --argjson ad "$2" '{frontend: $fe, admin: $ad}'
  exit 0
}

if [ -z "$CODE_PATH" ] || [ ! -d "$CODE_PATH" ]; then
  emit '[]' '[]'
fi
shift || true

while [ "$#" -gt 0 ]; do
  case "$1" in
    --drush-path)
      if [ "$#" -ge 2 ] && [ -n "${2:-}" ]; then
        # $DRUSH_CMD must stay unquoted at the call site (it may be two words,
        # e.g. `ddev drush`) — so restrict it to a safe charset: no shell
        # metacharacters can reach the command line.
        if ! printf '%s' "$2" | grep -qE '^[A-Za-z0-9 _./-]+$'; then
          echo "surface-discovery: --drush-path contains disallowed characters" >&2
          emit '[]' '[]'
        fi
        DRUSH_CMD="$2"; shift 2
      else shift; fi
      ;;
    *) shift ;;
  esac
done

# Resolve the drush command.
if [ -z "$DRUSH_CMD" ]; then
  if [ -f "$CODE_PATH/.ddev/config.yaml" ] && command -v ddev >/dev/null 2>&1; then
    DRUSH_CMD="ddev drush"
  elif command -v drush >/dev/null 2>&1; then
    DRUSH_CMD="drush"
  else
    DRUSH_CMD="none"
  fi
fi

# Resolve the docroot for config-file scans.
DOCROOT="$CODE_PATH/web"
[ -d "$DOCROOT" ] || DOCROOT="$CODE_PATH"

FRONTEND='[]'
ADMIN='[]'

add_frontend() {
  # $1 id, $2 url, $3 source, $4 priority
  FRONTEND=$(jq -c --arg id "$1" --arg u "$2" --arg s "$3" --argjson p "$4" \
    'if any(.[]; .id == $id) then . else . + [{id:$id,url:$u,source:$s,priority:$p}] end' \
    <<<"$FRONTEND")
}
add_admin() {
  ADMIN=$(jq -c --arg id "$1" --arg u "$2" --arg s "$3" --argjson p "$4" \
    'if any(.[]; .id == $id) then . else . + [{id:$id,url:$u,source:$s,priority:$p}] end' \
    <<<"$ADMIN")
}

# Sanitize an arbitrary string to a kebab-case surface id.
kebab() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

# ─── Front-end: home is always the primary surface ──────────────────────────

add_frontend "home" "/" "builtin" 1

# ─── Front-end: View page-display routes from config ─────────────────────────
# A page display in a views config file carries a `path:` key. Scan both the
# active config-sync directory and any module-shipped default views.
while IFS= read -r vf; do
  [ -z "$vf" ] && continue
  vname=$(basename "$vf" .yml)
  vname="${vname#views.view.}"
  # Collect every `path:` value in the file (a view may have several page
  # displays). Indented, scalar — e.g. `      path: blog`.
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    # strip leading slash for the id, keep a leading slash on the url
    pid=$(kebab "view-${vname}-${p}")
    purl="/${p#/}"
    [ -n "$pid" ] && add_frontend "$pid" "$purl" "view:$vname" 2
  done < <(grep -oE '^[[:space:]]+path:[[:space:]]*[^[:space:]#]+' "$vf" 2>/dev/null \
             | sed -E 's/^[[:space:]]+path:[[:space:]]*//' | sort -u)
done < <( {
  find "$CODE_PATH/config" -path '*sync*' -name 'views.view.*.yml' 2>/dev/null
  find "$DOCROOT/modules/custom" -path '*config*' -name 'views.view.*.yml' 2>/dev/null
} | sort -u | head -100)

# ─── Front-end: one sample URL per content type (best-effort drush) ──────────
if [ "$DRUSH_CMD" != "none" ]; then
  CT_ROWS=$( (cd "$CODE_PATH" && $DRUSH_CMD sqlq \
    "SELECT type, MIN(nid) FROM node GROUP BY type" 2>/dev/null) || true )
  while IFS=$' \t' read -r ctype cnid; do
    [ -z "$ctype" ] && continue
    case "$cnid" in ''|*[!0-9]*) continue ;; esac
    cid=$(kebab "content-$ctype")
    [ -n "$cid" ] && add_frontend "$cid" "/node/$cnid" "content-type:$ctype" 3
  done <<<"$CT_ROWS"
fi

# ─── Admin: a small, stable, opt-in set ──────────────────────────────────────

add_admin "admin-content"    "/admin/content"    "builtin" 1
add_admin "admin-structure"  "/admin/structure"  "builtin" 2
add_admin "admin-appearance" "/admin/appearance" "builtin" 3

emit "$FRONTEND" "$ADMIN"
