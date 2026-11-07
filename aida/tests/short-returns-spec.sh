#!/usr/bin/env bash
# short-returns-spec.sh: what a task's start returns to the main conversation (gap row 505). The
# session start block names the project folder and ends with the reply rule. A scope write prints
# its changed line, and read prints the summary. Research's read prints each criterion's text. The
# stage manuals take the folder from the block and run report. Each case sources the helper in a
# subshell, so it starts from fresh records.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=records.bash
source "$HERE/records.bash"
SCOPE="$PLUGIN/skills/scope/scripts/scope-actions.sh"
RESEARCH="$PLUGIN/skills/research/scripts/research-actions.sh"
RULE="$PLUGIN/hooks/reply-rule.md"

# start_block [<payload>]: the session start block, run from the code path, with <payload> on stdin.
# No payload names no transcript, so the project's only task in progress is this session's.
start_block() {
  (cd "$CODE" && printf '%s' "${1:-}" | CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$PLUGIN/hooks/session-start.sh") 2>/dev/null
}

# folder_case [untied]: the folder lines the block prints for task t1 in progress. With untied, the
# payload names a transcript with no file, so the session works no task.
folder_case() (
  source "$HERE/records.bash"
  task_records branch
  local payload=""
  [ "${1:-}" != untied ] || payload="$(jq -nc --arg t "$ROOT/none.jsonl" '{transcript_path: $t}')"
  start_block "$payload" >"$OUT"
  printf '%s|%s\n' "$(grep -c "^project-folder: $PROJECT\$" "$OUT")" "$(grep -c "^task-folder: $TASK\$" "$OUT")"
)
expect "the start block names the project folder, and the tied task's folder" "$(folder_case)" '1|1'
expect "an untied task's folder is not printed, so a compaction does not tie it" "$(folder_case untied)" '1|0'

# rule_case: whether the start block ends with the reply rule file, byte for byte.
rule_case() (
  source "$HERE/records.bash"
  task_records branch
  start_block >"$OUT"
  [ -s "$RULE" ] || { echo no-rule; return; }
  tail -c "$(wc -c <"$RULE")" "$OUT" | cmp -s - "$RULE" && echo ends || echo differs
)
expect "the start block ends with the reply rule" "$(rule_case)" 'ends'

# The reply rule is AIDA's, so a directory no project owns does not get it.
expect "a directory no project owns gets no reply rule" \
  "$(cd "$ROOT" && CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$PLUGIN/hooks/session-start.sh" </dev/null 2>/dev/null | grep -c 'Reply short')" '0'

# scope_write_case: add's changed line, its rendered line and whether it printed the summary, then
# whether read prints the summary.
scope_write_case() (
  source "$HERE/records.bash"
  task_records branch
  run "$SCOPE" add "$TASK" --text "b.php exists" --verification "ls b.php" --verified-by machine --author designer
  local add
  add="$RC|$(grep -c '^ADDED: c2$' "$OUT")|$(grep -c '^rendered: ' "$OUT")|$(grep -c '^goal-set: ' "$OUT")"
  run "$SCOPE" read "$TASK"
  printf '%s|%s\n' "$add" "$(grep -c '^goal-set: yes$' "$OUT")"
)
expect "a scope write prints its changed line and rendered:, and read prints the summary" "$(scope_write_case)" '0|1|1|0|1'

# research_read_case: research read's criterion lines on a contract with a machine and a person
# criterion.
research_read_case() (
  source "$HERE/records.bash"
  task_records branch wo2
  edit "$TASK/alignment.json" '.criteria[1].verifiedBy = "person" | .nonGoals = [{id: "n1", text: "no new page"}]'
  run "$RESEARCH" read "$TASK"
  printf '%s|%s|%s|%s\n' "$(grep -c '^criterion: ' "$OUT")" "$(grep -c '^criterion: c1 machine a.php says b$' "$OUT")" \
    "$(grep -c '^criterion: c2 person b.php exists$' "$OUT")" "$(grep -c '^non-goal: n1 no new page$' "$OUT")"
)
expect "research read prints each criterion with its kind and text, and each non-goal's text" "$(research_read_case)" '2|1|1|1'

# Each stage manual's paragraph that names the project-folder: line also runs report, and names the
# project skill for a non-zero exit.
for s in task scope research; do
  expect "the $s manual takes the folder from the start block and runs report" \
    "$(awk -v RS= '/`project-folder:`/' "$PLUGIN/skills/$s/SKILL.md" | tr '\n' ' ' \
      | grep -c 'project-folder:.*project-actions.sh report.*non-zero.*project skill')" '1'
done

# The project manual's check sites show the lines the check printed. Only check-machine shows the
# whole output.
expect "the project manual's eight check sites point to the check's record" \
  "$(tr '\n' ' ' <"$PLUGIN/skills/project/SKILL.md" | grep -o 'The full record is at the `report:` path' | grep -c .)" '8'
expect "only check-machine still shows the whole output" \
  "$(awk -v RS= '/Show the whole output/' "$PLUGIN/skills/project/SKILL.md" | grep -c 'check-machine')|$(grep -c 'Show the whole output' "$PLUGIN/skills/project/SKILL.md")" '1|1'

finish
