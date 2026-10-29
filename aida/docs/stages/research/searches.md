# Where research looks

Research runs one small search per subject, each by its own agent. The criteria decide how many
searches run. Three criteria that rest on the same library may need one search.

## The searches

- **This project's own code and configuration.** The searcher looks for names close to the work:
  classes, services, files, folders. It reads only the top of each candidate, its docblock. A file
  with no docblock is reported as having none. Configuration counts too: an existing view or
  content type can solve a problem with no code. The project's own task records are searched the
  same way. This searcher has no web tools. It runs on every task that changes code.
- **Prior art outside the project.** A library, module or package that already does this.
  Anything found is judged on three things: is it maintained, is it used, is it supported.
- **The catalog.** Research asks which guides and recipes cover each criterion. It records each
  name, and whether it is a guide, a tooling recipe or an agentic recipe. It never opens them;
  design reads them. A catalog it could not reach is recorded as not reached, not as empty.
- **What reputable sources recommend.** A current, dated source. Research also records the command
  those sources run to verify the result, word for word, with its source. Design turns that
  command into the work order's proof.
- **An assumption that needs checking.** A mechanism the task leans on might have changed. The
  answer is true, false or could not be settled, and all three are recorded.

Prior art that exists only on another branch is extracted into `inputs/prior-art/` first, and the
searcher is told where. A page an outside searcher could not fetch is recorded as a snippet,
marked so. Research may then fetch that one page itself and save it in `inputs/`.

A candidate inside the project is ranked by how close it is: same name, same folder, same layer.
Design decides whether to reuse, extend, supersede or decline it.

## A spike, rarely

Some questions no document answers. Only when the searches come back empty, research writes a
small experiment under `.aida-spike/` in the task's worktree and runs it. That folder must already
be in the project's `.gitignore`, or research writes nothing and says so. The answer becomes a
finding. Research deletes the folder before it closes, and design writes the real code fresh. A
folder left behind is a warning at the close.

## What a finding holds

Each search writes `research/<search>.json` in the task folder, and a page `research/<search>.md`
rendered from it. Nothing reads the page back. At the top of the page are the words the search
searched for. A search keeps one set of words. A search that broadens takes a new name.

Each finding holds what was found, where it came from, the date it was looked at, and the
criteria it serves. Research never records a claim from memory. A memory is only a lead for one
search.

"Looked and found nothing" is recorded too, once. It tells design that it can decide without
looking again.

When a search shows a criterion is too vague to check, research does not invent a bound. It says
so, names `/aida:scope`, and goes on with what it can check.

## Why it works this way

- Each agent sees only its own message, and the conversation sees only what the agent reports.
  That keeps the cost of each search small.
- The words a search used bound what it proves. A search that found nothing proves nothing outside
  those words.
- Research names a guide and does not read it, because reading is where the cost is.

Source: skills/research/SKILL.md, agents/internal-searcher.md, agents/outward-searcher.md, agents/catalog-identifier.md
