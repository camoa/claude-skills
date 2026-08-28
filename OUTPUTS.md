# Where output goes

Every command in this marketplace writes somewhere. Before this page there
was no rule, so four plugins picked four different places. This is the rule
for new work, and a record of where each plugin writes today.

## The rule

1. **Tied to a task** goes in the task folder, under
   `implementation_process/in_progress/<task>/`. Phase artifacts, gate
   results, audit files.
2. **The result of a check** goes in a report directory that is *resolved*,
   not fixed, and that sits outside the audited repository by default. See
   "Where a report directory lands" below for the order. One file per tool,
   named after the tool.
3. **Something the person asked to be made** goes in
   `outputs/<type>/<YYYY-MM-DD>-<name>/`. Decks, images, pages.
4. **Configuration a setup command installs** goes where the tool being
   configured expects it, at the root of the project being configured, and
   only after the person agrees to it. This is not a report and does not
   belong in a report directory.
5. **Machine-level state** goes under `~/.claude/<plugin>/`. Session
   context, project registries, shared caches: things that outlive one
   project and are shared across all of them. Writing outside the project is
   legitimate for this category and only this category, and the command's
   Output section must name the path. Do not write outside the project for
   anything a project could own.
6. **Nothing else is written to disk.** If a command only reports, it prints
   and exits. Do not leave a file behind that nobody asked for.

## Where a report directory lands

`code-quality-tools/skills/code-quality-audit/scripts/core/report-dir.sh`
resolves it, and every script honours what it exports. First match wins:

1. `$REPORT_DIR` when the caller set it explicitly.
2. `<project>/audits/<YYYY-MM-DD>/` when the audited directory belongs to a
   registered ai-dev-assistant project.
3. `${XDG_STATE_HOME:-$HOME/.local/state}/code-quality-tools/<project>/<timestamp>/`
   otherwise.
4. `.reports/` **only** when `REPORT_DIR_IN_REPO=1` asks for it.

`.reports/` used to be the default and stopped being one in v3.9.6. Reports
quote audited source and name the files a secret scanner matched in, so they
are kept out of the audited repository unless someone asks for them there.
The scripts announce the directory they resolved when they start, so the
answer for any given run is in that run's output rather than in this page.

Note what case 2 means for rule 1: a report about a registered project lands
in `<project>/audits/<date>/`, which is a fourth destination. It is not the
task folder, not `.reports/`, and not `outputs/`. It is where
`/code-quality-tools:architecture-debate` and
`/code-quality-tools:security-debate` write by default, since both resolve
their directory through the same script.

## What each plugin writes today

| Plugin | Writes | Where |
|---|---|---|
| ai-dev-assistant | phase artifacts, gate results, session state, and build checkpoints in the code repository | `implementation_process/in_progress/<task>/`, gate JSON under `<task>/validations/latest/` and `<task>/validations/history.jsonl`; session context at `~/.claude/ai-dev-assistant/sessions/<key>.json` and the project registry at `~/.claude/ai-dev-assistant/active_projects.json`. `/implement` also writes `_build-critique.json`, one verdict file per critic under `<task>/build-critique/`, and a frozen copy of the task's contract (`alignment.md`, `architecture.md`, `architecture/*.md`) at `<task>/build-critique/_contract-baseline/`, and git refs under `refs/worktree/aida/build-checkpoints/` and `refs/aida/build-checkpoints-keep/` in the code repository at `codePath` |
| code-quality-tools | tool reports, review write-up, and the config its setup wizard installs | the resolved report directory (above), `REVIEW.md`; setup writes `.code-quality.json`, and on your confirmation `grumphp.yml` or `.husky/pre-commit`, `.github/workflows/quality.yml` and `quality-pr.yml`, and git hooks under `.git/hooks/` |
| code-paper-test | trace report plus one analysis file per teammate | `<target_dir>/paper-test-team-report.md`, plus `happy-path-analysis.md`, `edge-case-analysis.md` and `red-team-analysis.md` beside the traced code. `--json` adds a `.json` beside each of those four |
| brand-content-design | a project tree, brand files, templates, and finished content | `/brand-init` creates `<project>/` in the current directory with `input/`, `assets/`, `templates/`, `presentations/`, `carousels/` and `html-pages/`. Finished content lands in that project, at `presentations/<YYYY-MM-DD>-<name>/`, `carousels/<YYYY-MM-DD>-<name>/`, `infographics/<YYYY-MM-DD>-<name>/`, and `html-pages/` (under the design system's name from `/html-page`, under a dated folder from `/html-page-quick`). Not `outputs/<type>/<date>-<name>/`: that path survives only in the plugin's own `references/output-specs.md` and no command writes it. Templates and design systems go under `templates/<type>/<name>/`; `/brand-extract`, `/brand-assets` and `/brand-palette` rewrite `brand-philosophy.md`, and `/brand-extract` downloads Google Fonts into `assets/fonts/`. `/presentation` and `/template-presentation` also upload to Google Drive under `brand-content/<brand>/` and, on a re-render, default to trashing the previous Drive folder |
| plugin-creation-tools | nothing by default; `--fix` edits the plugin it validated | terminal. With `--fix`: the validated plugin's manifest, hooks, skills, agents and command bodies rewritten in place, and one line appended to its `.claude-plugin/.validate-fixes.log` |
| drupal-ai-contrib | no evidence files; a staleness ledger outside the project, and CI config only where you confirm it | terminal for `issue`, `verify`, `review` and `pipeline`. The captured gate output is pasted into the report, never saved, and the three read-only worker skills carry `disallowed-tools: Edit, Write`. Two files sit outside the project, under `${CLAUDE_PLUGIN_DATA}` (`~/.claude/plugins/data/<plugin-id>/`, falling back to `$TMPDIR` when unset): `reverify/<key>.log`, appended by a PostToolUse hook, and `review/<key>.mark`, stamped by `review`. `setup` writes into the project you point it at, on your confirmation: `.gitlab-ci.yml`, `phpcs.xml.dist`, `phpstan.neon`, `phpunit.xml.dist`, `.cspell-project-words.txt`, `require-dev` entries in `composer.json`, plus whatever DDEV and `composer install` leave in the tree. `issue` and `submit` do git work in it: a fork remote, an issue branch, a push, and the merge request on drupal.org |
| drupal-htmx | nothing, except the migration command, which rewrites your source | terminal for `htmx`, `htmx-analyze`, `htmx-pattern` and `htmx-validate`. `/drupal-htmx:htmx-migrate` edits the files you point it at in place and writes no report, so run it on a clean tree |
| dev-guides-navigator | cached guide and recipe bodies | the shared store at `~/.claude/dev-guides-store/` (override with `DEV_GUIDES_STORE_DIR`), plus a pinned entry in the project's `dev-guides.lock.json` |
| drupal-dev-framework | nothing of its own; it is a migration shell | moves `~/.claude/drupal-dev-framework/` to `~/.claude/ai-dev-assistant/`, moves `<project>/.claude/drupal-dev-framework/` in every registered project, and rewrites those projects' `settings.json` in place. Its largest footprint of any plugin here, and all of it outside the current directory |

No plugin writes `outputs/<type>/<date>-<name>/`. `brand-content-design`, the
one this page said matched rule 3 exactly, writes a dated folder per content
type inside the brand project instead, so rule 3 currently has no
implementation.
`code-paper-test` writes beside the file it traced, which predates this page.
`code-quality-tools` no longer writes to `.reports/` by default, which is why
rule 2 is written as a resolution rather than a path. `drupal-htmx` and
`plugin-creation-tools` both read as print-only until you pass the one flag
or run the one command that rewrites your files, so the row says which.

## Writes that no rule covers

Recorded because they are real, not because they are endorsed. Changing
either is a decision for the repo owner, not a documentation fix.

- When the report directory is a *relative* path, which now means either
  `REPORT_DIR_IN_REPO=1` or a relative `$REPORT_DIR` somebody set,
  `report-dir.sh` appends it to **the audited repository's** `.gitignore`.
  That is a write into a tree this marketplace does not own. It only ever
  appends, never writes through a symlink, skips a path git already ignores,
  and never aborts the audit if it cannot. An absolute `$REPORT_DIR` that
  points inside the tree gets a printed warning instead of an entry, because
  a gitignore pattern is repo-relative and rewriting an absolute path into
  one is not safe to guess.
- `/code-quality-tools:security-debate` saves the dev-guides content it
  fetches as `security-context.md` inside the report directory, so its
  teammates can read it. Rule 5 would put fetched guide content in the
  navigator's shared store.
- `drupal-ai-contrib` keeps its two staleness files under
  `${CLAUDE_PLUGIN_DATA}`, which is `~/.claude/plugins/data/<plugin-id>/`
  and not the `~/.claude/<plugin>/` rule 5 names, and falls back to
  `$TMPDIR` when the variable is unset. The ledger half is appended by a
  `PostToolUse` hook on any `Edit` or `Write` of a matching source
  extension, so it grows in any project, with no command of this plugin
  ever run and no command's Output section naming the path.
- `ai-dev-assistant`'s `/implement` writes git refs into the repository at
  `codePath`, under `refs/worktree/aida/build-checkpoints/` and `refs/aida/build-checkpoints-keep/`. That is a write into a tree
  this marketplace does not own, and no rule covers it. The build-critique rung
  needs a `<before>..<after>` range for work that is uncommitted and usually
  untracked, so `scripts/build-checkpoint.sh` writes commit objects on no branch
  and anchors them under that namespace so garbage collection cannot take them
  mid-build. HEAD, the index, the working tree, `git branch`, `git status` and
  `git stash` are untouched, and a plain `git log` does not show them, though
  `git log --all` does. The command removes the namespace at end of phase;
  `build-checkpoint.sh list --repo <codePath>` shows what an interrupted run left
  behind, and `clear` removes it.
- `brand-content-design` writes into its own installed plugin directory:
  the three infographic commands run `npm install` in
  `skills/infographic-generator/`, leaving a `node_modules/` that a plugin
  update wipes. `scripts/icons.py` separately caches converted icon PNGs in
  `$TMPDIR/brand-content-design-icons/`.
- `brand-content-design` uploads to Google Drive, under
  `brand-content/<brand>/`. Re-rendering a presentation or a presentation
  template defaults to trashing the previous Drive folder, which is a
  destructive write to a place outside the machine, recoverable from Drive
  Trash for 30 days. The command asks first and offers a versioned sibling
  instead.

## Saying so in the command

Every command that produces anything carries an `## Output` section naming
what it writes and where. If a command writes nothing, the section says
so. A person should not have to run a command to find out what it leaves
behind.

`make outputs` enforces that, so it is a property of the repo rather than
an instruction here. It fails on any tracked `*/commands/*.md` without a
line reading exactly `## Output` and some text under it. The heading is
matched exactly: `## Output Format` describes the shape of a printed
report, which is a different question, and does not count. What no check
can tell you is whether a section is accurate, only that someone wrote
one. This page was itself wrong about five of the rows above and silent
about a sixth, while every one of those plugins carried a section.

## Result format

Anything a machine reads is JSON and carries `status`, `findings`, and
`timestamp`. See
`ai-dev-assistant/references/validation-gate-result.md` and
`code-paper-test/skills/paper-test/references/json-output-schema.md`.

The ai-dev-assistant envelope also carries `verdict`, `messages` and
`run_at`, and documents the two sets as equal. Read that file's "How much of
that is actually enforced" note before relying on the equality: no code
builds those envelopes, so it is a convention the docs hold to and the
runtime does not.
