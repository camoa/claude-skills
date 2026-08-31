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
| Everything, the same seven CI runs | `make ci` |

## What to run before a PR

`make ci` shows you what CI will say. It is not the usual step before you push.
The workflow does not call it. `.github/workflows/ci.yml` runs the same seven
checks as seven steps. Each step fails on its own line. `make ci` groups the
same seven the same way. CI runs them for you on the PR.

`make ci` takes about seven minutes. Two checks are 99 percent of that time.
These times are from this tree, with all seven checks green:

| check | time |
|---|---|
| `test` | 366s |
| `lint` | 59s |
| `validate` | 4.1s |
| `claims` | 3.8s |
| `outputs` | 0.4s |
| `manifests` | 0.1s |
| `setup-doc-check` | 0.1s |

The two slow checks are serial. They are not large. A task in the
`camoa_skills` project will make them parallel. The task is
`repo_checks_runtime`.

On your machine, run only the checks your branch can break:

1. **Run these five on every branch.** They take 8.5 seconds together:
   `make manifests outputs setup-doc-check claims validate`. This command stops
   at the first failure. `make ci` does not. At this speed, the difference does
   not matter.
2. **Add `make lint`** if the branch changed a `.sh` file.
3. **Add `make test-<plugin>`** for each plugin you changed.
4. **Run the full `make ci`** if the branch changed the repo-root `scripts/`
   folder or `.github/workflows/ci.yml`. Those files are the checks themselves.
   Run it also when you want CI's result early.

A new version number is not a reason to run all seven. A release commit can
make `plugin.json` disagree with the catalog entry. `make manifests` and
`make validate` find that. Both are in the five cheap checks.

The short run does not do three things. Read them before you use it.

**`make test-<plugin>` saves little time on an ai-dev-assistant branch.** The
repo has 142 spec files. 134 of them are ai-dev-assistant. 6 are
code-quality-tools. 1 is plugin-creation-tools. 1 is
`scripts/tests/claim-check-spec.sh` at the repo root. So
`make test-ai-dev-assistant` is almost the same as `make test`. You save real
time only on a code-quality-tools or a plugin-creation-tools branch. The 366
seconds is a serial-execution problem. It is not a scope problem.

**The specs cross plugin borders.** ai-dev-assistant specs make assertions
about `code-quality-tools` and `plugin-creation-tools`. code-quality-tools
specs make assertions about `ai-dev-assistant` and `drupal-ai-contrib`. The
root `claim-check-spec.sh` is outside every plugin and tests
code-quality-tools. So `make test-<plugin>` can miss a spec in a different
plugin that your change broke.

**CI is not a required check on `main`.** The branch has no protection. A red
CI does not stop a merge. Nothing later finds what you skip here. A person must
look.

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
  Six rules, each deriving its authority from a file that already exists,
  all scoped to tracked files under `code-quality-tools/`:
  **R1** an install documented anywhere — a fenced block, a CI template, a
  remediation string a gate echoes — carries the constraint AND the scope
  `schema/tool-catalog.json` pins. A `*` constraint there means the catalog
  states no opinion and omitting one agrees with it. The scope half compares
  `composer require` against `composer bin <ns> require`: an `isolated` tool
  documented as a project install fails, and so does the reverse, and so does
  an isolated install into a namespace that is not the catalog's id for the
  tool, because that is not where the gates look for the binary. Both forms
  are install contexts, so an isolated line is compared on the constraint too.
  R1 reports its scope comparisons as their own number and returns UNMEASURED
  when it made none.
  **R2** no bare month-year stamp such as `(December 2025)`; dated claims
  read `checked YYYY-MM-DD`, one per row. Age is REPORTED, never failed: an
  age threshold fails a green tree with no commit behind it.
  **R3** no `deprecated` or `unmaintained` beside a package name — neither
  is a state Composer has. `abandoned` IS a Composer field, so it is allowed
  on a line that also carries the date somebody read the flag. The judgement
  matches lowercase and sentence case, never ALL CAPS, so
  `E_USER_DEPRECATED` is not read as a claim about a package. Two subjects:
  a `vendor/package` token anywhere on the line, and a BARE tool name with
  the judgement attached to it (at most four filler words apart, either
  order). The bare half exists because the four sites this rule was written
  for all wrote `drupal-check` with no vendor prefix, so a rule reading only
  slashed tokens passed every one of them. The vendor token has to look like
  a NAME rather than any two lowercase words with a slash: not preceded by
  `/`, `.` or `:`, not followed by `/`, and no dot in the second segment,
  which is what keeps file paths and URLs out of it. Recognised bare names
  are derived from `schema/tool-catalog.json` and
  `schema/upstream-versions.json`, never registered; a scoped npm name and a
  name under four characters contribute nothing, which is what keeps `react`
  and `cli` out of a rule that reads prose.
  **R4a** no `--level` on a command line the plugin ships to be run, because
  it silently overrides a placed `phpstan.neon`; **R4b** every other level
  literal equals the one `templates/drupal/phpstan.neon` ships. R4 reports
  the literals it compared and the sites reading `phpstan.level` as two
  separate numbers, because only the first kind is a comparison.
  **R5** the generated version table in `references/tool-comparison.md`
  matches `schema/tool-catalog.json` and `schema/upstream-versions.json`,
  and every catalogued Drupal package has an upstream record.
  **R6** a documented `phpcs`/`phpcbf` invocation scanning a DIRECTORY
  passes the `--extensions` list `scripts/drupal/lint-check.sh` passes,
  because phpcs otherwise reads `.php` and `.inc` only and never sees
  `.module`, `.theme`, `.install`, `.profile` or `.engine`. A short list
  fails the same way a missing one does. Extension filtering applies to
  directory arguments only, so a named file is not a subject.
  `CHANGELOG.md` and specs are exempt from all six: a changelog records
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
