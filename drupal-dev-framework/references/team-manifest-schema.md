# Team Manifest Schema v1.0

**Introduced:** drupal-dev-framework v3.14.0
**Owner:** `commands/validate-team.md`
**Consumers (as of v3.14.0):** the 4 teammates spawned by `/validate:team` (`validator-code-1`, `validator-code-2`, `validator-docs`, `validator-visual`)

`team-manifest.json` is the **minimum-context package** the `/validate:team` lead writes before spawning teammates. Each teammate reads it at an absolute path named in its spawn prompt and uses it to determine:

- Which gate(s) it owns
- Where to write its result envelope (absolute paths — teammates run in worktrees)
- Where the screenshot store lives (visual teammate only)
- How to behave under interactive vs CI conditions

The manifest is write-once by the lead, read-only for teammates, and deleted by the lead during cleanup (Step 8 of the team spawn flow).

## 1. Location

```
<task_folder>/validations/tmp/team-manifest.json
```

`validations/tmp/` is a sibling of the existing `validations/latest/` and `validations/history.jsonl` established by v3.13.0 envelope persistence. `tmp/` is ephemeral — the lead creates it per-run and removes `team-manifest.json` after the team completes or fails. The `tmp/` directory itself may be left in place between runs (empty).

## 2. Shape

```json
{
  "schema_version": "1.0",
  "run_id": "2026-04-24T15:00:00Z-team-a1b2c3d4",
  "task": {
    "name": "dev_framework_isolated_validators",
    "folder": "/abs/path/to/project/implementation_process/.../dev_framework_isolated_validators",
    "project_folder": "/abs/path/to/project",
    "code_path": "/abs/path/to/code",
    "code_path_state": "set"
  },
  "gates": [
    {
      "gate": "tdd",
      "assigned_to": "validator-code-1",
      "isolation": "worktree"
    },
    {
      "gate": "solid",
      "assigned_to": "validator-code-1",
      "isolation": "worktree"
    },
    {
      "gate": "dry",
      "assigned_to": "validator-code-2",
      "isolation": "worktree"
    },
    {
      "gate": "security",
      "assigned_to": "validator-code-2",
      "isolation": "worktree"
    },
    {
      "gate": "guides",
      "assigned_to": "validator-docs",
      "isolation": "worktree"
    },
    {
      "gate": "visual-regression",
      "assigned_to": "validator-visual",
      "isolation": "none",
      "visual_fanout": [
        { "component": "article_hero", "viewport": "desktop" },
        { "component": "article_hero", "viewport": "mobile" }
      ]
    }
  ],
  "envelope": {
    "schema_version": "1.0",
    "latest_dir": "/abs/path/to/task/validations/latest",
    "history_file": "/abs/path/to/task/validations/history.jsonl"
  },
  "screenshot_store": {
    "root": "/abs/path/to/project/.screenshots",
    "schema_version": "1.0"
  },
  "fallback": {
    "interactive_visual_classification": true,
    "ci_mode": false
  }
}
```

## 3. Field contracts (top-level)

| Field | Type | Values / constraints |
|---|---|---|
| `schema_version` | string | `"1.0"` at v3.14.0. JSON string. Consumers match on major |
| `run_id` | string | ISO-8601 UTC timestamp + `-team-` + 8-char short UUID, e.g. `2026-04-24T15:00:00Z-team-a1b2c3d4`. Matches the entry appended to `history.jsonl` at Step 9 |
| `task` | object | See §4 |
| `gates` | array | Ordered list of gate assignments. See §5. Non-empty — a manifest with zero gates is invalid |
| `envelope` | object | Envelope persistence paths. See §6 |
| `screenshot_store` | object | Screenshot store location + schema version. See §7 |
| `fallback` | object | Teammate behavior hints. See §8 |

## 4. `task` — task + code context

| Field | Type | Values / constraints |
|---|---|---|
| `name` | string | Task folder name (e.g., `dev_framework_isolated_validators`). Matches the `task` field teammates will write into each envelope |
| `folder` | string | Absolute path to the task folder. Teammates use this to read `alignment.md`, `research.md`, `architecture.md` if needed |
| `project_folder` | string | Absolute path to the memory project folder (parent of `implementation_process/`). Used to locate `.screenshots/` and `project_state.md` |
| `code_path` | string \| null | Absolute path to the user's code base, or `null` for `docs-only` / `unknown` projects. Code-validator teammates skip with `verdict: "skipped"` + reason when null |
| `code_path_state` | enum | `"set"` \| `"docs-only"` \| `"unset"`. From `project-state-reader`. Consumers distinguish states explicitly rather than inferring from null |

## 5. `gates[]` — gate assignments

Each entry is one gate run. A teammate owning multiple gates appears in multiple entries (see `validator-code-1` in the §2 example — one entry for `tdd`, one for `solid`).

| Field | Type | Values / constraints |
|---|---|---|
| `gate` | enum | `"tdd"` \| `"solid"` \| `"dry"` \| `"security"` \| `"guides"` \| `"visual-regression"`. Matches `/validate:<gate>` command names. **`visual-parity` is NOT allowed** — it requires an explicit `<reference>` arg and inherits `/validate:all`'s limitation (deferred to v2 Set B5) |
| `assigned_to` | enum | `"validator-code-1"` \| `"validator-code-2"` \| `"validator-docs"` \| `"validator-visual"`. Suggestion only — file-lock task claiming (agent-teams runtime) decides actual ownership. The field exists so the lead can report "expected owner vs actual claimer" mismatches during debugging |
| `isolation` | enum | `"worktree"` \| `"none"`. Per teammate role from architecture §7. Worktree isolation is git-state only — filesystem writes use `envelope.*` absolute paths regardless (§10) |
| `visual_fanout` | array? | **Present only when `gate == "visual-regression"`.** Enumerates the components × viewports to capture. Each element is `{ component: string, viewport: string }`. Empty array means the task has no baselines in the store — teammate emits `verdict: "skipped"` with reason. Omit the field entirely for non-visual gates — do not write `visual_fanout: []` for a code gate |

## 6. `envelope` — where teammates write results

| Field | Type | Values / constraints |
|---|---|---|
| `schema_version` | string | `"1.0"` — the envelope schema version teammates MUST emit. Matches `references/validation-gate-result.md`. If the lead and teammates disagree on this, the aggregate step fails loudly |
| `latest_dir` | string | Absolute path to `<task>/validations/latest/`. Teammates write `<gate>.json` into this directory. Absolute-path invariant (§10) applies |
| `history_file` | string | Absolute path to `<task>/validations/history.jsonl`. Teammates append one JSON-line entry per gate run |

## 7. `screenshot_store` — visual teammate only

| Field | Type | Values / constraints |
|---|---|---|
| `root` | string | Absolute path to `<project>/.screenshots/` (per `references/screenshot-store-schema.md` §1). Visual teammate reads baselines and writes `.previous.*` rotation from here |
| `schema_version` | string | `"1.0"` — the screenshot store schema version at manifest-write time. Visual teammate refuses if it reads a different version from a `<component>/<viewport>.meta.json` |

Non-visual teammates MUST NOT read this block. It is populated unconditionally by the lead (even on docs-only tasks) to keep the manifest shape invariant across runs.

## 8. `fallback` — teammate behavior hints

| Field | Type | Values / constraints |
|---|---|---|
| `interactive_visual_classification` | boolean | `true` → visual teammate prompts user via mailbox-to-lead when a diff is detected (regression/intentional/cancel). `false` → skip-with-reason. Mirrors `/validate:all`'s CI-mode guard |
| `ci_mode` | boolean | `true` → teammates suppress interactive prompts across all gates (visual classification, user confirmations). `false` → interactive prompts allowed where the corresponding per-gate command would prompt |

Redundancy between `interactive_visual_classification` and `ci_mode` is intentional: `ci_mode` is the global posture, `interactive_visual_classification` is the per-concern override. A lead could set `ci_mode: false, interactive_visual_classification: false` to run interactive code gates while auto-skipping visual diffs that would block.

## 9. Invariants

The manifest is a contract. Breaking any of these invariants invalidates a run:

- **All paths are absolute.** No relative paths, no `~`, no env var references. Teammates in worktrees cannot resolve relative paths back to the main working directory.
- **`visual_fanout[]` only on visual gates.** Omit the field entirely on code/docs gates. Do NOT write `visual_fanout: []` for a non-visual gate.
- **`gates[]` non-empty.** A manifest with zero gates is invalid — the lead refuses to spawn the team.
- **`assigned_to` is a suggestion.** File-lock task claiming (agent-teams runtime) decides actual ownership. Teammates MUST NOT refuse a task because its `assigned_to` names a different teammate — they claim what they can and leave the rest.
- **Schema versions match.** `schema_version` (manifest), `envelope.schema_version`, and `screenshot_store.schema_version` are each independent. If a teammate reads a mismatch against the version it expects, it emits `verdict: "fail"` with an explicit mismatch message rather than silently continuing.
- **Write-once.** The lead writes the manifest before spawn and never updates it mid-run. Teammates treat the file as read-only. Any mid-run state (per-gate progress, mailbox messages) flows through the envelope + mailbox primitives, not the manifest.

## 10. Absolute-path invariant — why it matters

Teammates with `isolation: "worktree"` run with `cwd` inside a temporary worktree. Relative-path writes from that `cwd` land inside the worktree's copy of the task folder — NOT the main working directory the lead reads from at aggregation time (Step 7 of the team spawn flow).

Every teammate spawn prompt includes the reminder:

> When you write `<gate>.json` or append to `history.jsonl`, use the absolute paths in `manifest.envelope.*`. Do NOT use relative paths — you are in a worktree and relative writes will not reach the lead.

This applies uniformly regardless of `isolation`, because even `isolation: "none"` teammates have their own `cwd` in the agent-teams runtime.

## 11. Lifecycle

```
lead                                            teammates
────                                            ─────────
1. compose manifest in memory
2. write <task>/validations/tmp/team-manifest.json
3. TeamCreate + spawn 4 teammates
                                                4. read manifest from absolute path
                                                5. claim gate via file-lock
                                                6. run gate logic
                                                7. write <latest>/<gate>.json
                                                8. append <history> line
                                                9. mailbox: "<gate> complete, verdict: <v>"
10. receive progress messages (§4 Step 6)
11. wait for all gates (or timeout)
12. aggregate → _all.json
13. rm <tmp>/team-manifest.json                 (teammates already exited)
14. clean up team
```

## 12. Versioning policy

- **Major bumps** (`2.0`) are breaking: any change to field names, types, enums, or invariants. Consumers gate on major.
- **Minor bumps** (`1.1`) are additive: new optional fields, new enum values, clarifications that don't break existing readers.
- **Patch bumps** do not exist for schema versioning — if the change is editorial only, do not bump. If it's a contract change of any kind, use minor or major.

v1.0 is the committed shape for v3.14.0. No pre-release iterations were needed — the design is a direct lift of research §6 decisions.

## 13. Non-goals (what this schema deliberately omits)

- **No credentials.** The manifest MUST NOT contain environment variables, API keys, or secrets. Teammates inherit credentials from the project CLAUDE.md + MCP configs (agent-teams §"Context and communication") — not from the manifest.
- **No per-teammate model/turns config.** Model routing and MaxTurns are set in teammate spawn prompt headers (architecture §7), not the manifest. This keeps the manifest stable when a user overrides model choice for a specific run.
- **No streaming output specification.** Mailbox messages use a fixed format string (`"<gate> complete, verdict: <verdict>"`) documented in architecture §4 Step 6. Changing that format is a spawn-prompt change, not a schema change.
- **No `--json` flag output shape.** `/validate:team` does not emit JSON directly — `_all.json` already is JSON. (Deferred to v2 Set B3 if a direct JSON output mode ships.)
- **No cleanup/resume subcommand shape.** Manual recovery steps live in the command body. (Deferred to v2 Set B4.)
