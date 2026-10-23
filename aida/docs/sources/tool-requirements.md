# The tools a recipe needs

A process recipe can name the tools its commands need. `/aida:tool require` checks that each one is
present. The build, review and the surfaces skill run it for you, so you mostly meet its answer.

## What you type

```
/aida:tool require [--advisory] [--only <tool>] <recipe path>
```

It reads two lists in the recipe's frontmatter:

```yaml
requires_tooling:
  - phpcs
requires_tooling_with_tests:
  - phpunit
```

A tool under `requires_tooling` is always needed. A tool under `requires_tooling_with_tests` is
needed unless the task's contract says it has no automated tests. A recipe with neither list
prints `REQUIRES: none`.

`require` runs each tool once, as `/aida:tool run` does, and prints one `TOOLING:` line per tool.
It installs nothing. A tool reads absent only when its command is not found. Any other result
means the tool ran, so it reads present.

| Answer | What to do |
|---|---|
| Every tool present | Nothing. The stage goes on. |
| A tool absent | Install it with `/aida:tool install <tool>`, then run `require` again. |
| A tool unknown | No recipe answered for it, or its check could not run. AIDA asks the catalog for a recipe. If none answers, it names the tool and stops. |

Read every `TOOLING:` line. An unknown tool and an absent tool can appear in the same run, and the
absent one still needs its install. `--advisory` prints the same lines and never stops.
`--only <tool>` checks that one tool.

## Where a stage runs it for you

- **The build's first step** checks the tools the `test-execution` recipe names. It also checks
  the tools that the build's own checks run on each order. An absent tool stops the build before
  the first order, with the install as the advice. See [Implementation](../stages/implement/README.md).
- **A tool that only end-of-task rows run**, such as a mutation tool, does not stop the build.
  The `endOfTaskAbsent:` line names it, and review reads those rows as known since the start.
- **A task that needs no test harness** records the suite as `not-needed` and runs none. That is
  a task whose orders are all proved by their records, or a task with no automated tests. The
  check tools still run.
- **Review** runs `require --advisory` on the `review` recipe and reads the lines to you. A missing
  tool makes its own check read `unknown`.
- **The surfaces skill** runs `require` on each recipe before an install or a baseline, and goes on
  only when every tool is present.

Only `install` needs you. On an autonomous run, the install refuses, so the stage halts at the
absent tool. See [When a stage stops](../when-it-stops/README.md).

## Why it works this way

- The first order is paid for before its checks run. Checking the tools first stops a build that
  could not be measured before it costs anything.
- A tool that ran and failed is present. Treating that as absent would hide the real failure.

Source: skills/tool/SKILL.md, skills/implement/references/preconditions.md,
skills/review/references/checks.md, skills/surfaces/SKILL.md
