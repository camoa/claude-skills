#!/usr/bin/env bash
# migrate-screenshots-to-codepath.sh — one-time migration of the v3.13.0
# `.screenshots/` store to the v4.13.0 codePath-native layout (Task C).
#
# Usage:
#   migrate-screenshots-to-codepath.sh <memory_project_folder> <codePath> \
#       [--viewports-json '<json>']
#
#   <memory_project_folder>  the project folder holding `.screenshots/`
#   <codePath>               the project root (migration target)
#   --viewports-json         optional JSON array of viewport descriptors
#                            ([{name,width,...},...]) — used to map a legacy
#                            WIDTHxHEIGHT viewport to a `visual-chromium-<name>`
#                            project segment by nearest-width match. Absent ⇒ a
#                            built-in size heuristic (phone/tablet/desktop).
#
# Per `.screenshots/<component>/<viewport>.png`:
#   1. target spec  : <codePath>/tests/visual/<component>.spec.ts
#   2. snapshot dir : <codePath>/tests/visual/<component>.spec.ts-snapshots/
#   3. baseline PNG : <component>-visual-chromium-<size>-linux.png
#   4. copy PNG  + sibling .meta.json (renamed to match)
#   5. in the copied meta: captured_by → "migrated-from-screenshots-store",
#      viewport → the <size> name (not WIDTHxHEIGHT)
#   6. write a stub spec if <component>.spec.ts does not already exist
#
# `.screenshots/` is NOT deleted — the report tells the user to delete it once
# satisfied.
#
# Output: a JSON migration report on stdout.
# Exit codes: 0 success · 1 nothing to migrate · 2 IO / argument error.

set -uo pipefail

MEMORY_PROJECT="${1:-}"
CODE_PATH="${2:-}"
VIEWPORTS_JSON="[]"

if [ -z "$MEMORY_PROJECT" ] || [ -z "$CODE_PATH" ]; then
  echo "migrate-screenshots-to-codepath: <memory_project_folder> and <codePath> required" >&2
  exit 2
fi
shift 2 || true
while [ "$#" -gt 0 ]; do
  case "$1" in
    --viewports-json)
      if [ "$#" -ge 2 ] && [ -n "${2:-}" ]; then VIEWPORTS_JSON="$2"; shift 2
      else shift; fi
      ;;
    *) shift ;;
  esac
done

if ! jq -e . >/dev/null 2>&1 <<<"$VIEWPORTS_JSON"; then
  VIEWPORTS_JSON="[]"
fi

STORE="$MEMORY_PROJECT/.screenshots"
if [ ! -d "$STORE" ]; then
  echo '{"migrated":[],"warnings":["no .screenshots/ store at the given memory project folder"]}'
  exit 1
fi
if [ ! -d "$CODE_PATH" ]; then
  echo "migrate-screenshots-to-codepath: codePath does not exist: $CODE_PATH" >&2
  exit 2
fi

# Path-escape guard — both inputs must be real directories (mirrors the
# realpath posture of project-state-read.sh).
STORE_REAL=$(realpath "$STORE" 2>/dev/null || echo "")
CODE_REAL=$(realpath "$CODE_PATH" 2>/dev/null || echo "")
if [ -z "$STORE_REAL" ] || [ -z "$CODE_REAL" ]; then
  echo "migrate-screenshots-to-codepath: could not resolve input paths" >&2
  exit 2
fi

VISUAL_DIR="$CODE_PATH/tests/visual"
mkdir -p "$VISUAL_DIR" || { echo "migrate-screenshots-to-codepath: cannot create $VISUAL_DIR" >&2; exit 2; }

# Map a legacy WIDTHxHEIGHT viewport to a visual-chromium project size segment.
size_for_width() {
  local w="$1"
  if [ "$(jq 'length' <<<"$VIEWPORTS_JSON")" -gt 0 ]; then
    # Nearest-width match against the supplied matrix.
    jq -r --argjson w "$w" '
      map(select(.width != null))
      | min_by((.width - $w) | if . < 0 then -. else . end)
      | .name // empty' <<<"$VIEWPORTS_JSON"
    return
  fi
  if   [ "$w" -lt 600 ];  then echo "phone"
  elif [ "$w" -lt 1100 ]; then echo "tablet"
  else echo "desktop"; fi
}

MIGRATED='[]'
WARNINGS='[]'
add_warning() { WARNINGS=$(jq -c --arg w "$1" '. + [$w]' <<<"$WARNINGS"); }

while IFS= read -r comp_dir; do
  [ -z "$comp_dir" ] && continue
  component=$(basename "$comp_dir")
  # The component name is a directory name from the (possibly hand-edited)
  # legacy store. It flows into file paths and the generated spec — reject
  # anything that is not the kebab-case surface-id form, exactly as
  # screenshot-store-write.sh does for the legacy writer. This blocks path
  # traversal (`../`) and stray metacharacters.
  if ! printf '%s' "$component" | grep -qE '^[a-z0-9][a-z0-9-]*$'; then
    add_warning "$component: component name is not kebab-case (^[a-z0-9][a-z0-9-]*\$); skipped"
    continue
  fi
  spec_file="$VISUAL_DIR/$component.spec.ts"
  snap_dir="$VISUAL_DIR/$component.spec.ts-snapshots"
  comp_viewports='[]'
  spec_created=false

  while IFS= read -r png; do
    [ -z "$png" ] && continue
    vp_base=$(basename "$png" .png)
    case "$vp_base" in *.previous|*.candidate) continue ;; esac
    # vp_base is WIDTHxHEIGHT
    case "$vp_base" in
      *x*) width="${vp_base%x*}" ;;
      *) add_warning "$component/$vp_base: viewport not in WIDTHxHEIGHT form; skipped"; continue ;;
    esac
    case "$width" in ''|*[!0-9]*) add_warning "$component/$vp_base: non-numeric width; skipped"; continue ;; esac

    size=$(size_for_width "$width")
    [ -z "$size" ] && size="desktop"
    base="$component-visual-chromium-$size-linux"
    mkdir -p "$snap_dir" || { add_warning "$component: cannot create snapshot dir"; continue; }

    # Collision guard: two legacy viewports can map to the same size bucket
    # (e.g. 370x800 and 400x850 both → phone). Never silently overwrite —
    # keep the first, warn on the rest.
    if [ -e "$snap_dir/$base.png" ]; then
      add_warning "$component/$vp_base: maps to size '$size' already migrated this run; skipped (no overwrite)"
      continue
    fi

    if ! cp "$png" "$snap_dir/$base.png" 2>/dev/null; then
      add_warning "$component/$vp_base: PNG copy failed"
      continue
    fi

    meta_src="$comp_dir/$vp_base.meta.json"
    if [ -f "$meta_src" ] && jq -e . >/dev/null 2>&1 <"$meta_src"; then
      jq -c --arg vp "$size" \
        '.captured_by = "migrated-from-screenshots-store" | .viewport = $vp' \
        "$meta_src" > "$snap_dir/$base.meta.json" 2>/dev/null \
        || add_warning "$component/$vp_base: meta rewrite failed; PNG copied without provenance"
    else
      add_warning "$component/$vp_base: no valid .meta.json found; PNG copied without provenance"
    fi

    comp_viewports=$(jq -c --arg v "$vp_base" --arg s "$size" \
      '. + [{legacy: $v, viewport: $s}]' <<<"$comp_viewports")
  done < <(find "$comp_dir" -maxdepth 1 -type f -name '*.png' 2>/dev/null | sort)

  # Skip components that produced no migrated viewport.
  [ "$(jq 'length' <<<"$comp_viewports")" -eq 0 ] && continue

  # Stub spec — only when the surface has no spec file yet.
  if [ ! -f "$spec_file" ]; then
    cat > "$spec_file" <<STUB
// Stub generated by migrate-screenshots-to-codepath.sh — review migrated baseline.
// TODO: verify the URL for this surface in .visual-review/registry.yml.
// Framework-neutral native capture. If your project's process recipe supplies an
// accessibility-aware capture helper, re-run /setup-visual-regression so the
// recipe's __SCREENSHOT_CAPTURE__ replaces the native call below.
import { test, expect } from '@playwright/test';

test.describe('$component visual regression', () => {
  test('visual regression', async ({ page }) => {
    await page.goto('/'); // TODO: update URL
    await expect(page).toHaveScreenshot('$component.png');
  });
});
STUB
    spec_created=true
  fi

  MIGRATED=$(jq -c \
    --arg c "$component" --argjson sc "$spec_created" \
    --arg td "$snap_dir" --argjson vps "$comp_viewports" \
    '. + [{component:$c, viewports:$vps, spec_created:$sc, target_dir:$td}]' \
    <<<"$MIGRATED")
done < <(find "$STORE" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

if [ "$(jq 'length' <<<"$MIGRATED")" -eq 0 ]; then
  jq -nc --argjson w "$WARNINGS" '{migrated: [], warnings: ($w + ["no migratable components found in .screenshots/"])}'
  exit 1
fi

jq -nc --argjson m "$MIGRATED" --argjson w "$WARNINGS" '{migrated: $m, warnings: $w}'
exit 0
