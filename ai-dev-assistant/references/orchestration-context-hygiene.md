# Orchestration Context Hygiene — Distill-and-Drop (v5.18.0+)

**Introduced:** ai-dev-assistant (`distill_and_drop`, epic `orchestrator_context_hygiene`, design spec §4① / §6 row 4 / §7)
**Owner:** `agents/distill-agent.md` (the check + digest); the end-of-phase seam in `commands/{scope,research,design}.md`
**Consumers:** the phase commands (dispatch the agent, read the sidecar back as scalars); a fresh agent / resumed session (carries the pointer, not the exchange)

This is the plugin-scoped doctrine for keeping AIDA's **own** prep/lifecycle context clean. The
work-order build loop already sheds its residue (fresh critics, scalar reads, verdict sidecars); this
extends the same discipline **upward** to the interactive prep phases `/scope`, `/research`, `/design`.

## 1. The rule

> After an interactive prep phase (`/scope`, `/research`, `/design`) writes its artifact, delegate a
> **self-containment check + digest** to a fresh `distill-agent` handed the artifact **path** (never the
> transcript). Carry only the returned pointer + compact digest and compact the raw exchange. In
> `autonomous` `run_mode` the same agent performs the interaction-substitute first. **Advisory — never a
> blocking gate.**

Why it works: AIDA already externalizes each phase's decisions to disk as it goes — `/scope` authors
`alignment.md` *from* the live conversation, `/research` writes the self-contained `research.md` hub +
`research/<subject>.md` + audit JSONs, `/design` writes `architecture.md`. So the "conversation tail" the
distill agent needs is **read from those artifacts**, not pasted. The genuinely-new value is narrow: a
**check** that the artifact captured everything load-bearing *before* the exchange is dropped, plus the
**autonomous interaction-substitute**. The agent does **not** re-author — the artifact already exists.

## 2. The seam (all three commands, identical shape)

At each phase tail — **after** `session-context-write.sh` has dropped the durable pointer and **after**
the phase is marked complete (so the live human interaction has already finished):

1. **Read `run_mode`** — `scripts/project-state-read.sh "<project_folder>"` → `.runMode` (project dial,
   authoritative), with an optional task override via `scripts/fm-read.sh "<task_folder>"` → `.run_mode`
   (`null` = inherit). Absent/bad → `interactive` (fail-closed; an unset mode never grants autonomy).
2. **Branch** (see the table in §4).
3. **Dispatch** `distill-agent` (Task tool) with **paths only** — `artifact_path`, `sibling_paths[]`,
   `phase`, `run_mode`, optional `bounded_brief`, `output_path` = `<task_folder>/_distill.json`. Never the
   transcript.
4. **Read the sidecar back as scalars** — `.self_contained` + `.artifact_pointer` (never the agent's
   prose). On `.self_contained == false`, print **one** advisory line naming `.gaps[]`. **Never blocks.**
5. **In `autonomous` mode**, fold any `.interaction_substitute[]` into the artifact (the agent writes only
   its sidecar; the command does the fold).

The seam is strictly additive: it sits after the live interaction, mirrors `/design`'s existing
end-of-phase work-order-compile offer, and defaults to `[n]` in interactive mode so the common path is
zero-cost.

## 3. The `_distill.json` schema

Written by `distill-agent` to `<task_folder>/_distill.json`; read back by the command as scalars.

```json
{
  "schema_version": "1.0",
  "phase": "scope | research | design",
  "artifact_pointer": "<abs path to the artifact>",
  "digest": ["<= ~5 short lines of the load-bearing decisions>"],
  "self_contained": true,
  "gaps": ["<a load-bearing decision NOT captured in the artifact>"],
  "run_mode": "interactive | autonomous",
  "interaction_substitute": null
}
```

| Field | Type | Notes |
|---|---|---|
| `schema_version` | string | Frozen at `"1.0"`. |
| `phase` | enum | `scope` \| `research` \| `design`. |
| `artifact_pointer` | abs path | the artifact the orchestrator carries forward. |
| `digest` | array | ≤ ~5 short lines naming the load-bearing decisions. |
| `self_contained` | bool | `false` **iff** `gaps[]` is non-empty. |
| `gaps` | array | load-bearing decisions not captured in the artifact; `[]` on the common path. |
| `run_mode` | enum | `interactive` \| `autonomous`. |
| `interaction_substitute` | `null` \| array | `null` in interactive mode; `{question, answer, recorded_into}[]` in autonomous mode (prep-phase Q&A only). |

**Invariant:** `self_contained == (gaps | length == 0)`. A `false` is **advisory** — the orchestrator
prints one line and proceeds; it never blocks the lifecycle, writes no `gate_type` audit, and installs no
hook.

## 4. `run_mode` branch (the whole run_mode-awareness)

| `run_mode` | Command behavior | Agent behavior |
|---|---|---|
| `interactive` (default) | offer `[y]/[n]` (default `[n]`); dispatch on `[y]` | check self-containment + emit digest; `interaction_substitute: null` |
| `autonomous` | auto-run (no human turn); fold `interaction_substitute[]` into the artifact | additionally answer the prep-phase clarifying questions the human would, record to `interaction_substitute[]` |

The autonomous interaction-substitute stays inside the **advisory** altitude — prep-phase clarifying
questions only (the 4-field / research-question class). It makes **no** irreversible/out-of-band decision
(PR / merge / infra); that is the Phase-3 `wo-mode-gate.sh` kernel's domain, a separate task. The agent
has no such tools.

## 5. Enforcement altitude (advisory only)

Per the design spec §6 row 4: *"Pure transcript hygiene; a hook cannot enforce what the model keeps in
context. SKILL/CLAUDE.md rule only."* So there is deliberately **no hook, no gate, no kernel, no new
`gate_type`**. The agent writes its own `_distill.json` sidecar directly (the `wo-critic` verdict-file
pattern) — **not** via `gate-audit-write.sh`, whose `gate_type` allowlist is closed and does not include
distill. `self_contained: false` produces a one-line nudge and nothing more. Nothing that works today
regresses: the seam runs after the live interaction, and existing artifact authoring + the session pointer
are untouched.

## 6. Recommended global `~/.claude/CLAUDE.md` snippet (copy-paste — never auto-applied)

The design spec §7 names the doctrine altitude "global CLAUDE.md". A shippable plugin **must not auto-edit
`~/.claude/CLAUDE.md`** — that file is the user's to own. The plugin ships the mechanism above and its own
plugin-scoped doctrine; the general form is offered here as an **opt-in** you add **by hand**. Copy the
block below into your `~/.claude/CLAUDE.md` if you want the discipline to apply beyond AIDA's phases:

<!-- BEGIN copy-paste into your ~/.claude/CLAUDE.md (optional; the plugin never writes this file) -->
```markdown
## Distill-and-drop after interactive phases
After a live exchange (scoping, requirements, weighing options) produces an artifact, the *conversation*
is expensive and the *artifact* is small. Delegate the write-up / self-containment check to a fresh agent
handed the artifact PATH (not the transcript), save it, and compact the raw exchange. Keep the pointer +
a compact digest, not the dialogue. In autonomous run-mode the same fresh agent performs the
interaction-substitute first. Advisory — never a blocking gate.
```
<!-- END copy-paste -->

This mirrors the bullet many orchestration setups already carry; the plugin *references* it and never
overwrites it.
