# Where output goes

Every command in this marketplace writes somewhere. Before this page there
was no rule, so four plugins picked four different places. This is the rule
for new work, and a record of where each plugin writes today.

## The rule

1. **Tied to a task** goes in the task folder, under
   `implementation_process/in_progress/<task>/`. Phase artifacts, gate
   results, audit files.
2. **The result of a check** goes in `.reports/` at the root of the code
   being checked. One file per tool, named after the tool.
3. **Something the person asked to be made** goes in
   `outputs/<type>/<YYYY-MM-DD>-<name>/`. Decks, images, pages.
4. **Nothing else is written to disk.** If a command only reports, it
   prints and exits. Do not leave a file behind that nobody asked for.
5. **Never write outside the project** without saying so in the command's
   Output section first.

## What each plugin writes today

| Plugin | Writes | Where |
|---|---|---|
| ai-dev-assistant | phase artifacts, gate results | `implementation_process/in_progress/<task>/`, gate JSON under `<task>/validations/latest/` and `<task>/validations/history.jsonl` |
| code-quality-tools | tool reports, review write-up | `.reports/*.json`, `.reports/*.md`, `REVIEW.md` |
| code-paper-test | trace report | `<target_dir>/paper-test-team-report.md` and `.json` |
| brand-content-design | finished content | `outputs/<type>/<YYYY-MM-DD>-<name>/` |
| plugin-creation-tools | nothing, prints only | terminal |
| drupal-ai-contrib | evidence artifacts | the contribution working folder |
| drupal-htmx | nothing, prints only | terminal |
| dev-guides-navigator | cached guide bodies | the shared content store, outside the project |

Rule 3 and rule 2 are already what `brand-content-design` and
`code-quality-tools` do. `code-paper-test` writes beside the file it
traced, which predates this page.

## Saying so in the command

Every command that produces anything carries an `## Output` section naming
what it writes and where. If a command writes nothing, the section says
so. A person should not have to run a command to find out what it leaves
behind.

## Result format

Anything a machine reads is JSON and carries `status`, `findings`, and
`timestamp`. See
`ai-dev-assistant/references/validation-gate-result.md` and
`code-paper-test/skills/paper-test/references/json-output-schema.md`.
