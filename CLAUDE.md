# claude-skills

Run repo tasks through `make`. Do not call test files, the linter, or the
validator directly.

| Job | Command |
|---|---|
| Run all tests | `make test` |
| Run one plugin's tests | `make test-<plugin>` |
| Check shell scripts | `make lint` |
| Rewrite the lint baseline | `make lint-baseline` |
| Check plugin structure | `make validate` |
| Check plugin manifests | `make manifests` |
| Check every command says what it writes | `make outputs` |
| Regenerate setup.md's tool inventory | `make setup-doc` |
| Check that inventory against the catalog | `make setup-doc-check` |
| Regenerate the tool version table | `make tool-versions` |
| Check documented claims against their authority | `make claims` |
| Everything, same as the PR check | `make ci` |

Before opening a PR: `make ci`. It runs all seven checks even when one
fails, so one run shows every problem. CI runs the same seven the same way.

## What each check can fail on

- `make lint` compares shellcheck against `scripts/lint-baseline.txt`, a
  committed list of `<path>:<CODE>` pairs. A pair that is not in the
  baseline fails. A baseline pair that no longer occurs is reported as
  fixed and passes. Regenerating is deliberate: `make lint-baseline`, then
  commit the diff. The baseline keys on file and code, never line number,
  so unrelated edits do not disturb it. It also means a file going from
  one instance of a code to five does not fail.
- `make validate` fails on validator errors; validator warnings print
  without failing. It checks the catalog as well as each plugin folder.
- Neither `lint` nor `validate` can pass without doing work. Zero scripts
  found, zero plugins found, or a missing baseline all fail. When
  shellcheck or the `claude` CLI is missing they skip locally and say so,
  but fail outright when `CI` is set, so a CI step never goes green
  without checking anything.
- `make validate` does not catch a plugin folder missing from the catalog,
  and treats a version disagreement with the catalog as a warning only.
  `make manifests` is the check that fails on both.
- `make outputs` fails on any tracked `*/commands/*.md` that does not carry
  a line reading exactly `## Output`, outside a code fence, with at least
  one non-blank line under it. The heading is matched exactly: `## Output
  Format` is a different section, describing the shape of a printed report
  rather than what the command leaves on disk, and it does not satisfy the
  rule. There are no exemptions, deprecated commands included, since what
  a command does to your filesystem is the thing you want written down
  before you run it. Zero command files found fails. What it cannot check
  is whether the section is *true*; it checks that the claim exists.

- `make setup-doc-check` regenerates the region between
  `<!-- BEGIN GENERATED: tool-catalog -->` and the matching end marker in
  `code-quality-tools/commands/setup.md` from
  `skills/code-quality-audit/schema/tool-catalog.json`, and fails on two
  separate things: the committed region differing from what the catalog
  generates (printing the diff), and the region no longer matching the
  sha256 recorded on its own end marker. It also fails when the catalog is
  empty, a marker is missing, the checksum is absent or malformed, or
  `setup.md` is untracked — a check that found nothing to check has not
  passed. Its one non-generated assertion is that `full-audit.sh` and
  `SKILL.md` still route to `install-tools.sh`, reported as `unchecked`
  rather than passing when either file cannot be read.
- `make setup-doc` rewrites that region. It **refuses** and exits non-zero
  when the committed region does not match its checksum, because that means
  a hand edit is about to be destroyed. `scripts/gen-setup-doc.sh --force`
  is the deliberate override; no `make` target calls it.

- `make claims` is the only check that compares a documented claim against
  the thing it describes, rather than two internal files against each other.
  Five rules, each deriving its authority from a file that already exists,
  all scoped to tracked files under `code-quality-tools/`:
  **R1** an install documented anywhere — a fenced block, a CI template, a
  remediation string a gate echoes — carries the constraint
  `schema/tool-catalog.json` pins. A `*` there means the catalog states no
  opinion and omitting a constraint agrees with it.
  **R2** no bare month-year stamp such as `(December 2025)`; dated claims
  read `checked YYYY-MM-DD`, one per row. Age is REPORTED, never failed: an
  age threshold fails a green tree with no commit behind it.
  **R3** no `deprecated` or `unmaintained` beside a package name — neither
  is a state Composer has. `abandoned` IS a Composer field, so it is allowed
  on a line that also carries the date somebody read the flag. Two subjects:
  a `vendor/package` token anywhere on the line, and a BARE tool name with
  the judgement attached to it (at most four filler words apart, either
  order). The bare half exists because the four sites this rule was written
  for all wrote `drupal-check` with no vendor prefix, so a rule reading only
  slashed tokens passed every one of them. Recognised names are derived from
  `schema/tool-catalog.json` and `schema/upstream-versions.json`, never
  registered; a scoped npm name and a name under four characters contribute
  nothing, which is what keeps `react` and `cli` out of a rule that reads
  prose.
  **R4a** no `--level` on a command line the plugin ships to be run, because
  it silently overrides a placed `phpstan.neon`; **R4b** every other level
  literal equals the one `templates/drupal/phpstan.neon` ships.
  **R5** the generated version table in `references/tool-comparison.md`
  matches `schema/tool-catalog.json` and `schema/upstream-versions.json`,
  and every catalogued Drupal package has an upstream record.
  `CHANGELOG.md` and specs are exempt from all five: a changelog records
  what was believed then, and a spec must be able to name the value it
  asserts.
  It **exits 4, not 1**, when any rule compared nothing, so a caller can
  tell "I found a problem" from "I could not look". A missing catalog, a
  missing template or an empty tree all reach it.
  It is offline and deterministic. `scripts/check-claims.sh --upstream`
  re-reads Packagist and compares the recorded version, PHP requirement and
  abandoned flag against what upstream publishes now; it is a deliberate
  refresh a person runs, like `make lint-baseline`, and neither `make` nor
  CI ever calls it. What `make claims` cannot tell you offline is whether a
  recorded upstream value is still true — that is what the per-row `checked`
  date is for.
- `make tool-versions` rewrites the generated version table, with the same
  refusal-on-hand-edit contract as `make setup-doc`. Both generators source
  `scripts/lib/generated-region.sh`, so there is one marker-and-checksum
  mechanism rather than two copies of it.

Only `make test`, `make lint`, `make outputs` and `make claims` scan files,
and all four only look at git-tracked ones. A brand-new script, test,
command or reference file is not picked up until it is `git add`ed.

New test: put it where that plugin already keeps its tests. `make test`
picks it up.

## Before `make test` works

- **bash 4 or newer.** macOS ships bash 3.2 and some tests fail on it for
  that reason alone. `brew install bash`.
- **PyYAML.** `ai-dev-assistant/scripts/fm-helpers.sh` reads task
  frontmatter with it. Without it the reader returns nulls and the tests
  that depend on it fail. `pip install pyyaml`.
- **gitleaks.** `code-quality-tools`' secret-scanning spec gates whole
  sections on `command -v gitleaks`. Without the binary those sections do
  not run, and the spec still exits 0 and still prints a passing total, so
  nothing tells you they were skipped. Measured on this tree: **742
  assertions with gitleaks, 458 without. 284 silently disappear, and both
  runs report "0 failed".** Everything about secret detection, history
  scanning and redaction is in the missing 284. `brew install gitleaks`.
- **pytest**, plus `brand-content-design/scripts/slides/requirements.txt`.
  Without pytest the ten modules under
  `brand-content-design/scripts/slides/tests` are reported as one skip.
  pytest alone is not enough: those modules import `slides.auth`, which
  imports `googleapiclient` at import time, so collection fails without the
  requirements too. `pip install pytest -r
  brand-content-design/scripts/slides/requirements.txt`.
- **`node_modules` for the infographic generator.** Without it
  `brand-content-design/skills/infographic-generator/test.js` is reported as
  one skip. `npm ci` in that folder. Its `svgToPng` launches puppeteer, so
  the install also has to fetch a browser, which is what makes it slow the
  first time.
- **shellcheck**, for `make lint` only. `brew install shellcheck`. The
  version matters: `scripts/lint-baseline.txt` names the version that
  produced it on its first line, and `make lint` says so when yours
  differs. CI pins the same version in `.github/workflows/ci.yml`.
- **git history.** Some tests compare a file against its version on
  `main`, so a shallow clone fails them.

None of these dependencies fail loudly on their own. The pytest and
`node_modules` cases at least print a `skip` line and raise the skip count.
The gitleaks case does not: it reports zero failures with 284 fewer
assertions and says nothing. A green `make test` on a machine missing
gitleaks is a smaller green than it looks.

## Writing output

Read `OUTPUTS.md` before adding anything that writes a file.

- Tied to a task: the task folder.
- The result of a check: a report directory that is resolved rather than
  fixed, out of the audited repository by default. Not `.reports/`, which
  stopped being the default in v3.9.6 and is now opt-in. `OUTPUTS.md` gives
  the resolution order.
- Something the person asked to be made: `outputs/<type>/<date>-<name>/`.
- Configuration a setup command installs: where the tool expects it, in the
  project being configured, on the person's confirmation.
- State shared across projects: `~/.claude/<plugin>/`. Legitimate, and the
  command's Output section has to name the path.
- Otherwise print and exit. Do not leave a file nobody asked for.

Anything a machine reads is JSON carrying `status`, `findings`, and
`timestamp`. Every command that produces something has an `## Output`
section saying what and where, and `make outputs` fails when one does not.
That check cannot tell whether a section is true: `OUTPUTS.md` was wrong
about five plugins, and silent about a sixth, while all of them carried a
section.

## Where things live

- Plugin folders are top level. Each has `.claude-plugin/plugin.json`.
- The catalog is `.claude-plugin/marketplace.json`.
- Per-plugin conventions are in `<plugin>/CONVENTIONS.md`, not `CLAUDE.md`.
  Claude Code does not load a plugin-root `CLAUDE.md`.
- Repo task scripts are in `scripts/`.

## Releasing a plugin

Four files move together in one commit: `plugin.json`, `CHANGELOG.md`,
`README.md`, and the plugin's entry in `.claude-plugin/marketplace.json`.
`make manifests` checks the version agrees between `plugin.json` and the
catalog entry. The two `description` fields are deliberately different and
are not compared. Full rules are in `CONTRIBUTING.md`.
