#!/usr/bin/env bash
# maintainer-mode-detect.sh — deterministic dev-guides maintainer-mode detector.
#
# Emits a single JSON object to stdout: {"maintainer_mode": true|false, "dg_src": "<path>"}.
# maintainer_mode is true IFF a dev-guides SOURCE repo is detected by the full 4-part signature
# (the canonical signature is owned by the navigator's
#  dev-guides-navigator/skills/dev-guides-navigator/references/create-on-miss.md — keep them in sync).
#
# A SOURCE repo (not just any MkDocs site, not a consumer's content store) carries ALL of:
#   - mkdocs.yml
#   - scripts/generate_llms.py
#   - docs/agentic-recipes/            (directory)
#   - at least one .claude/agents/guide-* agent
# A partial signature is NOT a match → consumer mode (false), so the lifecycle's create-on-miss
# offers and recipe-gap proposals never fire for ordinary consumers (unchanged behavior).
#
# Resolution order for the candidate root (first full-signature match wins):
#   1. $DEV_GUIDES_SRC   (explicit override)
#   2. $PWD              (the session may already be in the repo)
#   3. ~/workspace/dev-guides   (the conventional checkout)
#
# This is a pure read-only filesystem probe — no model context, no network, no writes. Lifecycle
# commands call it so an interactive create-on-miss offer can surface at the COMMAND level (where a
# prompt actually reaches the user), instead of being swallowed in a nested data-delegation.
#
# Usage: maintainer-mode-detect.sh
# Exit: always 0 (the JSON carries the verdict; absence of a repo is "consumer mode", not an error).

set -uo pipefail

emit() { # $1 maintainer_mode(true|false)  $2 dg_src
  jq -nc --argjson m "$1" --arg s "$2" '{maintainer_mode: $m, dg_src: $s}'
}

is_source_repo() { # $1 dir → 0 if the full 4-part signature is present
  local d="$1"
  [ -n "$d" ] || return 1
  [ -f "$d/mkdocs.yml" ] || return 1
  [ -f "$d/scripts/generate_llms.py" ] || return 1
  [ -d "$d/docs/agentic-recipes" ] || return 1
  ls "$d/.claude/agents/"guide-* >/dev/null 2>&1 || return 1
  return 0
}

candidates=()
[ -n "${DEV_GUIDES_SRC:-}" ] && candidates+=("$DEV_GUIDES_SRC")
candidates+=("$PWD" "$HOME/workspace/dev-guides")

for d in "${candidates[@]}"; do
  if is_source_repo "$d"; then
    # normalise to an absolute path so the handoff message names a stable root
    abs="$(cd "$d" 2>/dev/null && pwd)" || abs="$d"
    emit true "$abs"
    exit 0
  fi
done

emit false ""
exit 0
