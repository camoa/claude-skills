#!/usr/bin/env bash
# execute-bits-spec.sh: every shell script a skill or hook runs by path needs the execute bit, and
# git records it. Three scripts reached the live run as 100644 and exited 126 on their first call;
# the fixtures never saw it because they run scripts as `bash <script>`. Libraries under
# scripts/lib/ are sourced, never run, so they are not checked.
# The whole set runs from the marketplace repository root, camoa-skills/scripts/run-tests.sh, not
# from the plugin's own scripts/. It finds a spec through git ls-files, so an untracked spec
# never runs.
set -uo pipefail
if [ -n "${ZSH_VERSION:-}" ]; then SCRIPT_SOURCE="$0"; else SCRIPT_SOURCE="${BASH_SOURCE[0]}"; fi
PLUGIN="$(cd -- "$(dirname -- "$SCRIPT_SOURCE")/.." >/dev/null 2>&1 && pwd)"
FAIL=0
while IFS= read -r p; do
  [ -x "$PLUGIN/$p" ] || { printf 'not executable: %s\n' "$p"; FAIL=1; }
done <<SCRIPTS
$(cd "$PLUGIN" && find scripts skills hooks -name '*.sh' -not -path 'scripts/lib/*' | sort)
SCRIPTS
exit "$FAIL"
