---
name: contribution-setup
description: "Stands up and environment-matches a Drupal contribution workspace — DDEV with the workflow-matched add-on, CI gate config (new-module scaffold or existing-module discovery), the Drupal AI skills, the drupalorg CLI, and a contribution-credentials (SSH-key) check. Use when the user runs /drupal-ai-contrib:setup or asks to set up a Drupal contribution environment. Idempotent and detect-driven — does only what is missing; never a gate, never a prerequisite."
version: 0.1.1
model: inherit
user-invocable: false
---

# Contribution Setup (worker skill)

Onboarding for a Drupal contribution. **Optional, idempotent, not a gate.** Detect what
already exists and do only what is missing — a contributor who arrives with a ready
environment can skip straight to `issue`.

Backs `/drupal-ai-contrib:setup`. Load the knowledge layer via `dev-guides-navigator`:
`drupal/contributing/ddev-contribution-environment`,
`drupal/contributing/contrib-project-scaffolding`,
`drupal/contributing/three-contribution-workflows-compared`,
`drupal/contributing-with-ai/ai-toolchain-for-contribution`.

## Procedure

### 1. Detect the workflow and issue system

Determine — by inspecting the working directory and asking the contributor only what
cannot be inferred:

- **Workflow** — core / your own contrib / someone else's contrib (the three workflows
  differ in authority, CI ownership, who merges). See the workflows dev-guide.
- **Issue system** — drupal.org classic queue vs. GitLab. Detect by following the
  project's Issues link; do not assume.

### 2. Detect the environment

Check for an existing DDEV project (`.ddev/config.yaml`) and the add-on in use.
If a working contribution environment already exists, report it and stop — nothing to do.

If none exists, stand up **DDEV** with the **workflow-matched add-on**:

| Workflow | Add-on |
|----------|--------|
| Single contrib module/theme | `ddev-drupal-contrib` (module repo *is* the project root; `web/` + `vendor/` generated & gitignored) |
| Multi-module suite | `ddev-drupal-suite` |
| Drupal core | `ddev-drupal-core-dev` |

### 3. Resolve the gate config — two modes

**Existing module** — discover gates by parsing `.gitlab-ci.yml`:
- Read the `gitlab_templates` `include` and `ref`, the `variables:` block
  (`_TARGET_CORE`, `_TARGET_PHP`, `_GITLAB_TEMPLATES_REF`, `_PHPUNIT_CONCURRENT`,
  `SKIP_*`, `OPT_IN_TEST_*`).
- Record the discovered gate set; `verify` will mirror exactly these.

**New module / maintainer setup** — scaffold the correct config (writes — see §Writes).
Generate, version-resolved per the target core, from the scaffolding dev-guide:
- `.gitlab-ci.yml` — the `gitlab_templates` include + a `variables:` block
- `phpcs.xml.dist` — `Drupal` + `DrupalPractice`, scoped to `src` + `tests`
- `phpstan.neon` — `phpstan-drupal` extension, the project's level
- `phpunit.xml.dist` — the **major-version-correct schema** (D11 → PHPUnit 11 schema,
  `<source>` block, `failOnWarning`; D10 → PHPUnit 9.x schema + `DrupalListener`) —
  copy from the target core, never hand-write the version
- `.cspell-project-words.txt`
- `drupal/core-dev` (+ `drupal/coder`, `phpstan/phpstan`, `mglaman/phpstan-drupal`) in
  `require-dev`, constrained to the target major

### 4. Ensure the toolchain

**Drupal AI skills** — ensure `ai_best_practices` and `ai_skills` are installed via
`drupal_devkit` (the cross-harness skill installer). If `drupal_devkit` is absent,
report how to obtain it; do not block.

**The issue / MR CLI** — the `issue`, `submit`, and `pipeline` skills wrap
`mglaman/drupalorg-cli`. Detect it with `command -v drupalorg` (the executable is
`drupalorg`, not `drupalorg-cli`). If it is missing, surface the install instructions
from `${CLAUDE_PLUGIN_ROOT}/skills/drupal-ai-contrib/references/drupalorg-cli.md` —
that reference covers what the tool is, the recommended PHAR install, the deprecated
Composer path, and the subcommand set. Offer to install it; do not block if the
contributor declines (`issue`/`submit` re-surface the same instructions).

### 5. Check contribution credentials — and guide, do not assume

The contribution arc needs the contributor's **drupal.org credentials** for its write
operations. Surface this now — do not let it surface mid-`issue` as a failed `git
push`. The plugin and the CLI **cannot** set credentials up; this is the contributor's
own account action. Guide them through it.

- **Read operations** (`drupalorg issue:show`, `mr:list`, `project:issues`) hit public
  APIs — no credentials needed. An empty `project:issues` result can itself be an
  auth/config gap rather than "no issues" — note that when reporting.
- **Write / push operations** — `git push` to an issue fork, and the `/do:` issue-bot
  commands — need an **SSH key registered on the contributor's drupal.org account**,
  because issue-fork git remotes use SSH URLs (`git@git.drupal.org:…`).

Detect, then guide:

```bash
ssh -T git@git.drupal.org      # a working key greets the contributor by username
```

If it does not authenticate, tell the contributor plainly: this is a ~2-minute action —
register an SSH key at *drupal.org → My account → SSH keys* (add the public key, e.g.
`~/.ssh/id_ed25519.pub`). It is the prerequisite for `git push` to issue forks; without
it, `issue` can still review and read, but cannot push a branch. Never block setup on
it — report it as the next thing to do. See
`${CLAUDE_PLUGIN_ROOT}/skills/drupal-ai-contrib/references/drupalorg-cli.md` §Authentication.

### 6. Environment-match

Install the **CI-target core version** + `drupal/core-dev` so `phpunit` / `phpstan`
resolve to the same releases CI uses (the local DDEV default usually will not match).
This is the mechanism that makes `verify`'s gates trustworthy — see `contribution-verify`.

### 7. Report

Summarize, and for each item state ready vs. needs-action so the contributor knows
their exact next step: workflow, issue system, environment status, the resolved gate
set, AI-skill status, the issue/MR CLI (`drupalorg`) status, the **credentials/SSH-key**
status, the environment-match result. Point the contributor at `issue` (or, if work is
underway, `verify`) — and if the SSH key is missing, name *that* as the first step.

## Writes — explicit confirmation only

`setup` writes files **only** with explicit user confirmation and **only** within the
target project. Show the contributor each file to be written before writing it. Never
write outside the project directory.

## Detect-driven

Every step checks first and does only what is missing. Re-running `setup` on a ready
environment is a no-op that simply reports state.

## Examples

### Example 1: existing module, environment ready
**Trigger:** `/drupal-ai-contrib:setup` in a contrib module that already has DDEV.
**Actions:**
1. Detect the workflow (someone else's contrib) and the GitLab issue system.
2. DDEV already present → report it, do not re-create.
3. Parse `.gitlab-ci.yml`, record the discovered gate set; environment-match the core.
**Result:** No files written; the contributor is told to proceed to `issue`.

### Example 2: new module, maintainer setup
**Trigger:** `/drupal-ai-contrib:setup` in a fresh contrib module with no CI config.
**Actions:**
1. Stand up DDEV with `ddev-drupal-contrib`.
2. Show each scaffold file (`.gitlab-ci.yml`, `phpcs.xml.dist`, `phpstan.neon`,
   `phpunit.xml.dist`, `.cspell-project-words.txt`) and write only on confirmation.
**Result:** A CI-ready module the maintainer owns.

## Troubleshooting

| Situation | Handling |
|-----------|----------|
| `drupal_devkit` not installed | Report how to obtain it; do not block setup. |
| `drupalorg` not on `PATH` | Surface `references/drupalorg-cli.md` (PHAR install); offer to install; do not block. If installed via Composer global, the bin dir may just be off `PATH` — see the reference's Install note. |
| No SSH key registered on the drupal.org account | Guide the contributor to add one (*drupal.org → My account → SSH keys*); report it as the next step. Read/review still works; `git push` to issue forks does not. Never block. |
| Workflow cannot be inferred | Ask the contributor — never assume core vs. contrib. |
| `.gitlab-ci.yml` exists but uses a non-`gitlab_templates` setup | Record what is there; `verify` mirrors the discovered jobs as-is. |
| Contributor declines a scaffold write | Skip that file; report which gates remain unconfigured. |
