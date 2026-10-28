# Clean up a test suite

Type `/aida:test-cleanup` when a project's test suite has grown too large. AIDA reads every test
against one rubric, reports what it found, and asks you what goes. The cleanup you approve becomes
an AIDA task, so each change goes through the stages like any other.

The skill changes no test, and it never runs the suite or a test. A test's worth is judged by
reading it. Running the suite here would cost time and prove nothing about which tests to keep.

## What happens

1. **The project.** AIDA finds the project that owns this folder. Outside a project, it names
   `/aida:project` and stops.
2. **The test files.** AIDA takes the test file globs from your framework's implement recipe, the
   same globs the build freezes tests with. When a framework gives none, AIDA asks you where its
   tests live. It never guesses a glob.
3. **The groups.** A script splits the tracked test files into groups, in folder order, up to the
   lines one reader can read. Each group costs one dispatch, so AIDA says how many there are first.
   Pass `--max-lines <n>` to change the size of a group.
4. **The reading.** One test reader per group sorts every test into one category. It proposes an
   action for each test it would change: delete, merge or shrink.
5. **The summary.** A script adds up the reports into `summary.md`, with the tests per category and
   the causes. It refuses a report whose counts do not add up.
6. **Your decisions.** AIDA shows you one group's proposals at a time. Approve all, approve some,
   change an action, or refuse all. Your answers go in `decisions.md`, as you gave them.
7. **The task.** When at least one change is approved, AIDA offers a task named `test-cleanup`,
   whose goal names your `decisions.md`. You can run it light.

The run's files stay in `test-cleanup/<run>/` in the project folder.

## The categories

| Category | A test belongs here when |
|---|---|
| `keep` | it calls one unit with logic, at the lowest level that shows the behaviour, and asserts the output |
| `trivial` | it does not prove its behaviour, or a trivial build passes it |
| `too-heavy` | it walks a whole flow, sits a level too high, or checks two behaviours |
| `text` | it reads a file's text back, or checks prose, configuration, metadata or layout |
| `pinning` | it asserts an internal detail, the wording of prose, or an exit number nothing reads |
| `duplicate` | another test already checks the same behaviour |
| `variants` | it is one of a list of tests of one rule, past the first and its boundary cases |
| `replay` | it replays the records of one live incident |

An end to end test that walks a core journey is `keep`. One that a lower test already covers is
`duplicate`.

## How the task makes the changes

The task's design follows these rules, and the design check holds it to them:

- **A merge, a shrink or a rewrite** is a `tests` order that owns only test files. Its test author
  makes the change, and each test freezes with the reason it passes.
- **Whole files to delete** are one tests-only order, proved `confirm`. It owns only files of the
  cleanup run the goal names, and a done-when row names each one. It depends on every `tests`
  order of the task, so the kept tests freeze while the old ones still exist.
- **A tests-only order deletes and never edits.** The owned-files check reads any change other
  than a deletion as unmet. A file deleted by mistake comes back through redo, not a fix round.
- **A rewritten check script is code**, so it needs tests of its own. A check script deleted whole
  is a deletion.
- **A runner entry that names a deleted file** goes to another order, which depends on the
  deletion.
- **An end to end test you approved for removal** that is a registered surface goes with
  `/aida:surfaces unregister <id>`.

The design check refuses a tests-only order, or a `tests` order whose owned files are all tests,
that owns a test another open task froze. Wait for that task to
finish, or leave that test out.

At the task's review, you confirm each done-when row, so you see every deleted file before the
task closes. Finish then runs the whole suite. A test that a runner still names after its file was
deleted fails there, and that stops the task.

## Why it works this way

- A person decides what goes, one group at a time. A model's proposal is only a proposal.
- The cleanup goes through a task, so each change is reviewed, and the suite runs at its finish.
- A deletion cannot fail first, so no test proves it. Your approval, the scripts that hold the
  build to deletions, and the suite at finish are its proof.

Source: skills/test-cleanup/SKILL.md, agents/test-reader.md, skills/design/SKILL.md, scripts/check-design.sh
