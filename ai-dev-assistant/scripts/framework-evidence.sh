#!/usr/bin/env bash
# framework-evidence.sh: gather the facts a model needs to say what a codebase is built with.
#
# Usage: framework-evidence.sh <codePath> [--max-depth N] [--max-entries N]
#
# This script does NOT identify frameworks and holds no list of them. It reports what is there:
# the top-level entries, an extension histogram over a bounded walk, and the root-level files
# small enough to be worth reading. The identification is the model's, from these facts plus
# whatever it chooses to read.
#
# WHY IT IS SHAPED THIS WAY. Until v5.32.0 this plugin identified frameworks with a hand-written
# block per framework, so the set it could recognize was a property of a plugin release. dev-guides
# published complete recipe families for `go` and `php-cli` and detection returned [] on both.
# Moving that list into a table, or into a declared signal block in each recipe, would not have
# fixed it: a project would still be unrecognizable until someone somewhere wrote its entry. A
# model reading a repository needs no entry, which is why identification moved to the model and
# this script stopped interpreting anything.
#
# Output: one JSON object on stdout. Exit 0 unless the arguments are unusable.
#
# No writes. No network. No side effects.

set -uo pipefail

CODE_PATH=""
MAX_DEPTH=3
MAX_ENTRIES=400

while [ $# -gt 0 ]; do
  case "$1" in
    --max-depth)   MAX_DEPTH="${2:-3}"; shift 2 ;;
    --max-entries) MAX_ENTRIES="${2:-400}"; shift 2 ;;
    *) [ -z "$CODE_PATH" ] && CODE_PATH="$1"; shift ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  printf '{"schema_version":"1.0","status":"unknown","reason":"jq_missing"}\n'
  exit 0
fi

if [ -z "$CODE_PATH" ] || [ ! -d "$CODE_PATH" ]; then
  jq -n --arg p "${CODE_PATH:-}" \
    '{schema_version:"1.0", status:"unknown", reason:"code_path_missing_or_not_a_directory",
      code_path:$p, top_level:[], extensions:[], readable_manifests:[]}'
  exit 0
fi

# Directories that are someone else's code. Excluding them is not framework knowledge: it is the
# difference between an extension histogram of this project and one of its dependencies.
PRUNE=( -name .git -o -name node_modules -o -name vendor -o -name .ddev -o -name dist -o -name build -o -name .next -o -name target )

TOP=$(cd "$CODE_PATH" && ls -A 2>/dev/null | head -n "$MAX_ENTRIES" \
  | jq -R -s -c 'split("\n") | map(select(length > 0))')
[ -z "$TOP" ] && TOP='[]'

# Extension histogram, most frequent first. A count is a fact; what it means is not this script's
# call. Files with no dot in the basename are counted under "" and dropped.
EXTS=$(cd "$CODE_PATH" && find . -maxdepth "$MAX_DEPTH" \( "${PRUNE[@]}" \) -prune -o -type f -print 2>/dev/null \
  | awk -F/ '{ n=$NF; if (n ~ /\./) { sub(/^.*\./, "", n); print tolower(n) } }' \
  | sort | uniq -c | sort -rn | head -25 \
  | awk '{ printf "%s\t%s\n", $2, $1 }' \
  | jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t") | {ext: .[0], count: (.[1] | tonumber)})')
[ -z "$EXTS" ] && EXTS='[]'

# Root-level regular files under 256 KiB, so the caller knows what it can cheaply Read. No
# opinion about which of them matters. A manifest, a README and a lockfile all list the same.
MANIFESTS=$(cd "$CODE_PATH" && find . -maxdepth 1 -type f -size -256k 2>/dev/null \
  | sed 's|^\./||' | sort | head -n "$MAX_ENTRIES" \
  | jq -R -s -c 'split("\n") | map(select(length > 0))')
[ -z "$MANIFESTS" ] && MANIFESTS='[]'

# A nested docroot is the one structural fact worth reporting, because it changes where every
# other path resolves and a caller that assumes the repo root gets every subsequent path wrong.
NESTED=$(cd "$CODE_PATH" && for d in */; do
  d="${d%/}"
  case "$d" in .git|node_modules|vendor) continue ;; esac
  if [ -f "$d/composer.json" ] || [ -f "$d/package.json" ] || [ -f "$d/go.mod" ] || [ -f "$d/pyproject.toml" ]; then
    printf '%s\n' "$d"
  fi
done | head -20 | jq -R -s -c 'split("\n") | map(select(length > 0))')
[ -z "$NESTED" ] && NESTED='[]'

jq -n --arg p "$CODE_PATH" --argjson t "$TOP" --argjson e "$EXTS" \
      --argjson m "$MANIFESTS" --argjson n "$NESTED" --argjson md "$MAX_DEPTH" \
  '{schema_version:"1.0",
    status:"read",
    code_path:$p,
    scanned_depth:$md,
    top_level:$t,
    extensions:$e,
    readable_root_files:$m,
    nested_project_dirs:$n,
    note:"Facts only. This script identifies nothing and holds no framework list; the caller reads what it needs and names the stack."}'
