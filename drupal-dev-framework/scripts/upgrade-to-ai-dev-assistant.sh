#!/usr/bin/env bash
#
# upgrade-to-ai-dev-assistant.sh
# One-time FORCED migration from the deprecated `drupal-dev-framework` plugin
# to `ai-dev-assistant`. No back-compat: the old name is not tolerated in
# steady state — this rewrites every old-name wiring point to the new name.
#
# What it does (idempotent, safe to re-run):
#   1. Per registered project: if the project still carries old-name
#      session-remembrance wiring, move the baked hook dir
#      `<proj>/.claude/drupal-dev-framework/` -> `<proj>/.claude/ai-dev-assistant/`
#      and rewrite the two hook command strings in `<proj>/.claude/settings.json`.
#   2. Move the global store `~/.claude/drupal-dev-framework/` ->
#      `~/.claude/ai-dev-assistant/` (registry + sessions + logs).
#   3. Report safe-to-uninstall.
#
# Usage:
#   upgrade-to-ai-dev-assistant.sh            # perform the migration
#   upgrade-to-ai-dev-assistant.sh --dry-run  # show what would change, write nothing
#
set -euo pipefail

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

OLD_NAME="drupal-dev-framework"
NEW_NAME="ai-dev-assistant"
OLD_STORE="$HOME/.claude/$OLD_NAME"
NEW_STORE="$HOME/.claude/$NEW_NAME"

say() { printf '%s\n' "$*"; }

say "== ai-dev-assistant upgrade =="
if [ "$DRY_RUN" -eq 1 ]; then
  say "(dry run — no changes will be written)"
fi
say ""

# --- locate the registry: old store first, else an already-moved new store ---
REGISTRY=""
if [ -f "$OLD_STORE/active_projects.json" ]; then
  REGISTRY="$OLD_STORE/active_projects.json"
elif [ -f "$NEW_STORE/active_projects.json" ]; then
  REGISTRY="$NEW_STORE/active_projects.json"
fi

# --- per-project remembrance-hook re-stamp -----------------------------------
restamped=0
if [ -n "$REGISTRY" ]; then
  # Candidate install dirs: both codePath and memory path for every project.
  # The remembrance hook may have been installed at either location.
  DIRS=()
  while IFS= read -r d; do
    [ -n "$d" ] && DIRS+=("$d")
  done < <(jq -r '.projects[]? | (.codePath // empty), (.path // empty)' "$REGISTRY" 2>/dev/null | sort -u)

  for d in "${DIRS[@]:-}"; do
    [ -n "$d" ] || continue
    settings="$d/.claude/settings.json"
    oldhookdir="$d/.claude/$OLD_NAME"
    newhookdir="$d/.claude/$NEW_NAME"

    has_old_dir=0
    has_old_ref=0
    [ -d "$oldhookdir" ] && has_old_dir=1
    if [ -f "$settings" ] && grep -q "\.claude/$OLD_NAME/" "$settings" 2>/dev/null; then
      has_old_ref=1
    fi
    if [ "$has_old_dir" -eq 0 ] && [ "$has_old_ref" -eq 0 ]; then
      continue
    fi

    say "project dir: $d"

    # (a) move the baked hook dir (primer + save-session.sh copy)
    if [ "$has_old_dir" -eq 1 ]; then
      if [ -e "$newhookdir" ]; then
        say "  ! $newhookdir already exists — old dir left in place; resolve by hand"
      elif [ "$DRY_RUN" -eq 1 ]; then
        say "  [dry-run] mv .claude/$OLD_NAME/ -> .claude/$NEW_NAME/"
      else
        mv "$oldhookdir" "$newhookdir"
        say "  moved .claude/$OLD_NAME/ -> .claude/$NEW_NAME/"
      fi
    fi

    # (b) rewrite the hook command path strings in settings.json
    if [ "$has_old_ref" -eq 1 ]; then
      if [ "$DRY_RUN" -eq 1 ]; then
        say "  [dry-run] rewrite .claude/$OLD_NAME/ -> .claude/$NEW_NAME/ in settings.json"
      else
        tmp="$settings.tmp.$$"
        sed "s#\.claude/$OLD_NAME/#.claude/$NEW_NAME/#g" "$settings" > "$tmp"
        if jq -e . "$tmp" >/dev/null 2>&1; then
          mv "$tmp" "$settings"
          say "  rewrote hook paths in settings.json"
        else
          rm -f "$tmp"
          say "  ! settings.json rewrite produced invalid JSON — left untouched"
        fi
      fi
    fi

    restamped=$((restamped + 1))
  done
else
  say "No registry found at either store path — nothing to re-stamp."
fi
say ""

# --- global store move (done last so the registry read above is unaffected) --
if [ -d "$OLD_STORE" ] && [ ! -e "$NEW_STORE" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    say "[dry-run] mv $OLD_STORE -> $NEW_STORE"
  else
    mv "$OLD_STORE" "$NEW_STORE"
    say "moved global store -> $NEW_STORE"
  fi
elif [ -d "$OLD_STORE" ] && [ -e "$NEW_STORE" ]; then
  say "! both stores exist — global store NOT moved automatically."
  say "  Merge $OLD_STORE into $NEW_STORE by hand, then remove the old one."
elif [ ! -d "$OLD_STORE" ] && [ -e "$NEW_STORE" ]; then
  say "global store already at $NEW_STORE (nothing to move)."
else
  say "no global store found at $OLD_STORE (nothing to move)."
fi
say ""

say "== upgrade complete =="
say "Projects re-stamped: $restamped"
if [ "$DRY_RUN" -eq 1 ]; then
  say ""
  say "This was a DRY RUN. Re-run without --dry-run to apply."
else
  say ""
  say "You can now uninstall the drupal-dev-framework plugin and use ai-dev-assistant."
fi
