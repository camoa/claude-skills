#!/usr/bin/env bash
# bash32-spec.sh: every shell file of the plugin parses under bash 3.2, the bash macOS ships. A
# newer bash reads some text that 3.2 does not: an apostrophe in a comment inside "$( )" ends the
# file early for 3.2, so the whole design check failed to parse there (live-run row 474).
#
# It needs a bash 3.2 binary. AIDA_BASH32 names one; else the bash:3.2 Docker image runs, when
# docker and that image are both present. It never pulls the image. With neither, it prints a skip
# line and passes, because a check with no 3.2 to run cannot fail on anything.
#
# What it cannot see: bash -n under 3.2 does not parse the body of a "$( )" until it runs. So a
# bare case pattern inside "$( )" parses here and breaks at run time, as does an empty array
# under set -u. Running the specs under bash 3.2 finds those.
# The whole set runs from the marketplace repository root, camoa-skills/scripts/run-tests.sh, not
# from the plugin's own scripts/. It finds a spec through git ls-files, so an untracked spec
# never runs.
set -uo pipefail
if [ -n "${ZSH_VERSION:-}" ]; then SCRIPT_SOURCE="$0"; else SCRIPT_SOURCE="${BASH_SOURCE[0]}"; fi
PLUGIN="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")/.." >/dev/null 2>&1 && pwd)"

# Runs under the bash 3.2 binary itself, from the plugin folder, so $BASH names that binary.
# shellcheck disable=SC2016 # expanded by the bash 3.2 that runs it
CHECK='case "$BASH_VERSION" in 3.2*) ;; *) printf "not bash 3.2: %s is %s\n" "$BASH" "$BASH_VERSION"; exit 1 ;; esac
printf "bash %s\n" "$BASH_VERSION"
find . -type f \( -name "*.sh" -o -name "*.bash" \) | sort | {
  fail=0; n=0
  while IFS= read -r f; do
    n=$((n + 1))
    "$BASH" -n "$f" || { printf "does not parse under bash 3.2: %s\n" "$f"; fail=1; }
  done
  printf "parsed %s files\n" "$n"
  exit "$fail"
}'

if [ -n "${AIDA_BASH32:-}" ]; then
  (cd "$PLUGIN" && "$AIDA_BASH32" -c "$CHECK")
elif command -v docker >/dev/null 2>&1 && docker image inspect bash:3.2 >/dev/null 2>&1; then
  docker run --rm -v "$PLUGIN:/plugin:ro" -w /plugin bash:3.2 bash -c "$CHECK"
else
  printf 'skip: no bash 3.2 here. Set AIDA_BASH32 to a bash 3.2 binary, or load the bash:3.2 Docker image.\n'
fi
