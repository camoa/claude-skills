# When a framework has no recipe

A stage that plans goes on without a recipe. A stage that builds or measures stops, because code
that nothing measured is worse than no code.

The lookup first asks your folders, then the catalog. An empty folder is not an answer, so the
catalog always gets asked. Each stage records which of the three answers it got: see
[Where content comes from](where-content-comes-from.md#a-failed-lookup-has-three-answers). Where a
stage treats a failed lookup differently from `no-recipe`, the table says so.

## What each point does

| Point | With no recipe |
|---|---|
| `research` | Goes on, the same way after a failed lookup; only the recorded finding differs. Outside prior art is judged by three tests: maintained, used, supported. The search inside the project runs from the project root and says the bound on custom code was not enforced. |
| `design` | Goes on. Every work order's reasoning says `written without framework input`. Design invents no kind of unit and guesses no convention. |
| `test-execution` | `no-recipe` records the framework `undeclared`, and the build goes on. An unreachable catalog or a failed fetch records `unknown` and stops: a person decides, and an autonomous run halts. |
| `implement` | No test patterns, so every order proved by tests is blocked at the freeze. A `record` or `observe` order still builds. A `gate` order builds, but its own check reads `unknown`. The build's first step names each blocked order before any order is built. |
| `test-authoring` | The test author gets no recipe path. |
| `review` | `no-recipe` reads `undeclared`, which passes and is reported in that word. An unreachable catalog reads `unknown`, which fails the review. |
| `e2e-setup`, `visual-regression` | Installs nothing, and the kind stays off. The surfaces skill names `templates/process-recipe-setup.md` as the shape a recipe follows. |
| `worktree-environment` | The worktree has the branch's files and no site. The task says so once and goes on. |

A tool with no recipe stops too. See [Install and run a tool](tools.md#no-recipe).

## The offer to write a recipe

With a person present, research asks whether to write the recipe before it moves on. It names the
framework and gives three answers:

- **Write one now.** The shape is in `templates/process-recipe-research.md`.
- **Not now.** Research goes on. Design may ask again.
- **Not for this framework.** Research runs `task decline-recipe`, which records the answer on
  this task. Research and design skip the ask for that framework for the rest of the task. The
  next task asks again.

Design asks the same question when the navigator found no recipe, before it drafts anything. It
skips the ask when research already recorded "not for this framework". The design shape is in
`templates/process-recipe-design.md`.

Implementation never asks. It records the missing recipe and goes on, or stops, as the table says.
On an autonomous run, no stage asks. Research records the missing recipe in its finding and goes
on.

Until a recipe exists for a point that builds or measures, that framework cannot build under AIDA.
A recipe in a folder you declare is enough: see
[Use your own folders before the catalog](your-own-sources.md).

## Why it works this way

- A plan made without framework input is still work a person can read and correct. A build with
  no way to run a test is not.
- "Not for this framework" holds for one task only. A second framework that needs no recipe on
  this task may need one on the next.

Source: skills/research/SKILL.md, skills/design/SKILL.md, skills/implement/references/preconditions.md,
skills/review/references/checks.md, skills/surfaces/SKILL.md, skills/task/SKILL.md, templates/
