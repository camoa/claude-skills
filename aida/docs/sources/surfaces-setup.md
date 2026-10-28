# Set up the surfaces

`/aida:surfaces <kind>` installs the harness from your framework's recipe, registers the surfaces
you confirm, and takes the first baselines. Each step needs your yes.

The setup lands in the tree you run it from. Inside a task's worktree, it goes on the task's branch
and merges with it. With no task active, it goes at the project's code path.

## Install the harness

AIDA looks up the framework's setup recipe for the kind, and checks the tools it names: see
[The tools a recipe needs](tool-requirements.md). Then it shows the recipe's commands, the files
it writes and its viewports, and waits for a plain yes. An autonomous run stops here and says the
install needs a person.

The install:

- warns when the tree holds other uncommitted work, and leaves that work out of its commit;
- runs the recipe's commands in order;
- writes each file the recipe names when the file is absent, and replaces a file that holds an
  earlier version of the recipe's content;
- writes `.visual-review/surfaces.json` with the recipe's viewports, when the file is absent;
- turns the kind on in the project file, and commits all of it.

Running it again is safe. It keeps your surface file and every file that matches the recipe.

| What you see | What to do |
|---|---|
| A step failed, with its first line of output | Do not install by hand. The fix belongs in the recipe or on the machine. |
| A file is present with content no version of the recipe holds | The install stops before anything runs and names the file. Decide which version is right. |
| Two frameworks each carry a recipe | AIDA names both and stops. It cannot pick one. |
| No framework has a recipe | Nothing is installed and the kind stays off. AIDA names `templates/process-recipe-setup.md` as the shape a recipe follows. |

Scope and design offer the setup without looking the recipe up, so a yes there can end here.

## Register the surfaces

AIDA proposes a list, and you edit it. It reads the recipe's seed rows and the sources the recipe
names, on Drupal the routes, the menu, the views and the content types. It proposes one surface per
template that renders a page, and lists the templates no surface covers. It always asks for your
own list too. A version 5 `registry.yml` offers its ids and URLs as candidates.

A mask hides an element before capture, such as a date. AIDA proposes one only with the count of
elements it hides. A mask that hides everything hides the regression too.

For each surface you keep, AIDA asks these things:

- **The paths that render it**, as globs relative to the code tree. Review runs the surface only
  when a change touches one of them. A surface with no paths runs on every review.
- **Whether it is critical.** A critical surface runs on every review.
- **Why, for an end to end surface.** An end to end test is added on purpose. The reason is your
  words: the core journey it walks, or the behaviour no lower test can reach. `register` refuses
  an end to end surface with no `--reason`, and the surface file keeps it.

Only a row you confirmed is written, and nothing is enabled unattended. Each registration commits
the surface file alone, so other uncommitted work does not stop it. To add one later, run
`/aida:surfaces register` with the id, URL, kinds, paths, `--reason` for an end to end surface,
and `--enable`. Without `--enable` the surface is written disabled, and review records it as not
run. Registering the same id with different fields is refused, naming both. Registering before
the install is refused.

## Remove a surface

```
/aida:surfaces unregister <id>
```

This removes one surface from the surface file and commits the file alone. Run it only when you
decided the surface goes, such as when a lower test already covers it. A test cleanup task runs it
for an end to end test you approved for removal. The surface's baselines stay on disk. It refuses
when no surface has that id, or when there is no surface file.

## Take the first baselines

A visual regression surface has nothing to compare against until it has a baseline. AIDA plans
the baselines: every enabled visual regression surface, or the ids you name, at every viewport. It
shows the plan and takes your yes. Then it runs the recipe's accept command over those ids and
commits the baselines.

A baseline needs a running site. AIDA uses the address the task records for its worktree site.
Without one, it asks you once and stores nothing. The site is described with the task: see
[the task pages](../task/README.md).

A baseline is never written unattended and never by hand. A recipe with no accept command, or two
frameworks that each carry one, stops the step.

## Why it works this way

- The commit takes only the files the setup changed, so your uncommitted work is never swept
  into it and never stops it.
- Declaring paths is what lets review skip a surface a change cannot reach, which keeps review
  affordable on a large project.

Source: skills/surfaces/SKILL.md, skills/surfaces/references/discover.md,
skills/surfaces/scripts/surfaces-actions.sh
