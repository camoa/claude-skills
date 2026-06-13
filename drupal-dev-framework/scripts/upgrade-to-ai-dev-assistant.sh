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
#   3. (Opt-in, --permissions) Re-point stale `Skill(drupal-dev-framework:*)`
#      permission allowlist entries in each registered project's
#      `settings.json` / `settings.local.json` to `Skill(ai-dev-assistant:*)`.
#      Off by default: without --permissions the script only reports how many
#      stale entries it found, so you re-approve them once on first use instead.
#   4. Report safe-to-uninstall.
#
# Usage:
#   upgrade-to-ai-dev-assistant.sh                 # perform the migration
#   upgrade-to-ai-dev-assistant.sh --dry-run       # show what would change, write nothing
#   upgrade-to-ai-dev-assistant.sh --permissions   # also re-point stale Skill() perms
#   (flags combine, e.g. --dry-run --permissions)
#
set -euo pipefail

DRY_RUN=0
REWRITE_PERMS=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --permissions) REWRITE_PERMS=1 ;;
    *) printf 'unknown flag: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

OLD_NAME="drupal-dev-framework"
NEW_NAME="ai-dev-assistant"
OLD_STORE="$HOME/.claude/$OLD_NAME"
NEW_STORE="$HOME/.claude/$NEW_NAME"

say() { printf '%s\n' "$*"; }

# count Skill(OLD_NAME:...) permission tokens in a file (0 if absent/unreadable)
count_perm_tokens() {
  grep -o "Skill($OLD_NAME:" "$1" 2>/dev/null | wc -l | tr -d ' '
}

say "== ai-dev-assistant upgrade =="
if [ "$DRY_RUN" -eq 1 ]; then
  say "(dry run — no changes will be written)"
fi
if [ "$REWRITE_PERMS" -eq 1 ]; then
  say "(--permissions — will re-point stale Skill($OLD_NAME:*) allowlist entries)"
fi
say ""

# --- locate the registry: old store first, else an already-moved new store ---
REGISTRY=""
if [ -f "$OLD_STORE/active_projects.json" ]; then
  REGISTRY="$OLD_STORE/active_projects.json"
elif [ -f "$NEW_STORE/active_projects.json" ]; then
  REGISTRY="$NEW_STORE/active_projects.json"
fi

# --- candidate install dirs: both codePath and memory path for every project ---
# The remembrance hook (and permission grants) may live at either location.
DIRS=()
if [ -n "$REGISTRY" ]; then
  while IFS= read -r d; do
    [ -n "$d" ] && DIRS+=("$d")
  done < <(jq -r '.projects[]? | (.codePath // empty), (.path // empty)' "$REGISTRY" 2>/dev/null | sort -u)
fi

# --- per-project remembrance-hook re-stamp -----------------------------------
restamped=0
if [ -n "$REGISTRY" ]; then
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

# --- (opt-in) stale Skill() permission re-point ------------------------------
# Scoped precisely to the `Skill(OLD_NAME:` token so it never touches a
# `Bash(...)` cache-path grant or any unrelated allowlist content.
perm_files=0
perm_tokens=0
pending_files=0
pending_tokens=0
if [ -n "$REGISTRY" ]; then
  for d in "${DIRS[@]:-}"; do
    [ -n "$d" ] || continue
    for fn in settings.json settings.local.json; do
      pf="$d/.claude/$fn"
      [ -f "$pf" ] || continue
      n=$(count_perm_tokens "$pf")
      [ "$n" -gt 0 ] || continue

      if [ "$REWRITE_PERMS" -eq 1 ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
          say "permissions: [dry-run] re-point $n Skill($OLD_NAME:*) token(s) in $fn ($d)"
        else
          tmp="$pf.tmp.$$"
          sed "s#Skill($OLD_NAME:#Skill($NEW_NAME:#g" "$pf" > "$tmp"
          if jq -e . "$tmp" >/dev/null 2>&1; then
            mv "$tmp" "$pf"
            say "permissions: re-pointed $n Skill() token(s) in $fn ($d)"
          else
            rm -f "$tmp"
            say "permissions: ! $fn rewrite produced invalid JSON — left untouched ($d)"
            continue
          fi
        fi
        perm_files=$((perm_files + 1))
        perm_tokens=$((perm_tokens + n))
      else
        pending_files=$((pending_files + 1))
        pending_tokens=$((pending_tokens + n))
      fi
    done
  done
fi

if [ "$REWRITE_PERMS" -eq 0 ] && [ "$pending_tokens" -gt 0 ]; then
  say "Found $pending_tokens stale Skill($OLD_NAME:*) permission token(s) across $pending_files file(s)."
  say "These are harmless: each is a pre-approved grant for a skill that no longer exists,"
  say "so the new $NEW_NAME: command simply re-prompts for permission once on first use."
  say "Re-run with --permissions to re-point them automatically (opt-in)."
  say ""
elif [ "$REWRITE_PERMS" -eq 1 ]; then
  say ""
fi

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
if [ "$REWRITE_PERMS" -eq 1 ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    say "Permission tokens to re-point: $perm_tokens across $perm_files file(s)"
  else
    say "Permission tokens re-pointed: $perm_tokens across $perm_files file(s)"
  fi
fi
if [ "$DRY_RUN" -eq 1 ]; then
  say ""
  say "This was a DRY RUN. Re-run without --dry-run to apply."
else
  say ""
  say "You can now uninstall the drupal-dev-framework plugin and use ai-dev-assistant."
fi
