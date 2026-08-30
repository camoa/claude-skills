# prior-art-researcher output contract

**Introduced:** ai-dev-assistant v5.37.0. Schema `1.0`.

**Consumers:** `commands/research.md` (Phase 1 outward search), `commands/implement.md` (the
mechanism-challenge tier-3 cascade, via `references/mechanism-challenge.md`).

## Why this agent writes two files

Every other converted agent writes one JSON sidecar, because its deliverable is a structured verdict.
This one's deliverable is prose research a person reads. Collapsing that into a JSON string field
would make it unreadable in the place it is most useful, and returning it as a message is the defect
this contract exists to close: on a live research phase the agent returned a transitional sentence in
place of its findings, and nothing could tell that from having found nothing.

So it writes the research as markdown, and a small JSON record carrying the scalars a caller branches
on plus a pointer to the markdown. The caller reads the JSON. Nobody parses the prose.

## The two paths

Both are handed by the dispatcher. Neither is fixed, because one task researches more than one
aspect and a fixed name would collapse them.

| File | Content |
|---|---|
| `<task_folder>/research/prior-art-<aspect>.md` | The research, in the markdown shape `agents/prior-art-researcher.md` specifies |
| `<task_folder>/_prior-art-<aspect>.json` | The scalars, below |

## The JSON record

```json
{
  "schema_version": "1.0",
  "aspect": "<the capability searched for, verbatim from the dispatcher>",
  "searched": true,
  "skip_reason": null,
  "recommendation": "use | extend | build | none_found",
  "solutions_considered": 4,
  "body_path": "<task_folder>/research/prior-art-<aspect>.md",
  "sources": ["<url or path>", "..."],
  "recency_floor": "<the date bound applied, or null>",
  "researched_at": "<iso8601-Z>"
}
```

| Field | Required | Meaning |
|---|---|---|
| `aspect` | yes | Echoed from the dispatcher, so a caller can tell which of several records it is reading. |
| `searched` | yes | `false` with a non-null `skip_reason` when the search could not run at all, for example no network. A search that ran and found nothing is `true` with `recommendation: "none_found"`, which is a different fact and must not be collapsed into it. |
| `recommendation` | yes | `none_found` is a real answer, not an absence. It means the search ran and the world has nothing. |
| `solutions_considered` | yes | How many candidates were weighed. Zero with `recommendation: "none_found"` and `searched: true` is legitimate and says the search was thorough and empty. |
| `body_path` | yes | The markdown. A record whose `body_path` names a file that does not exist is malformed, not empty. |
| `sources` | yes | May be empty. What was actually read. |
| `recency_floor` | no | The date bound, where the caller set one. The mechanism-challenge cascade applies one year. |

## When the record is absent

`no_return`, the value `references/gate-audit-schema.md` defines once and three other schemas already
use: an absent sidecar after a dispatch that supplied an output path, never read as a passing result.

**The consequence is the caller's, and the two callers differ:**

- `commands/research.md` records `no_return` on the prior-art gate and proceeds. The outward search
  is advisory there and the internal search has already run.
- The **mechanism-challenge cascade** records tier 3 as `not_searched`, **not** as grounding `none`.
  Those two already mean different things to `scripts/mechanism-disposition.sh`, and only one of them
  is honest about an agent that said nothing. Folding an absent result into `none` is what let a
  build proceed on an unchallenged mechanism: no grounding resolves, the kernel returns `keep`, and
  the challenge reports that the stated mechanism stands.

## What this contract cannot do

It establishes that the agent delivered, not that what it delivered is correct. A record with
`searched: true`, four sources, and a wrong recommendation passes every check here.
