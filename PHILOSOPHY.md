# Philosophy

AI writes code fast. That was never the hard part. The hard part is everything the speed skips: understanding the problem before coding it, checking whether someone already solved it, working from current facts instead of stale training data, keeping the build consistent with what you decided, and actually testing it. This framework keeps the fast part fast and makes the skipped parts hard to skip. That is the whole idea. The rest of this page is why each piece works the way it does.

## Guided rigor, for whoever is holding it

One engine, and how hard it leans depends on who is using it. If you are experienced, it enforces your standards (TDD, SOLID, DRY, security, review) and does not go soft because you are in a hurry. If a practice is new to you, that same enforcement is how you meet it. The first time the framework has you write the test before the code, the practice shows up right where it helps, with the guide alongside it explaining why it is worth doing. You do not have to have heard of test-driven development beforehand for it to start working for you. That is the point of guided rigor: good practice comes to you, instead of waiting for you to already know to ask for it. Same engine, and the intensity scales to who is holding it. You make every decision; the structure just will not let the work be half-done.

One precise note, because it is easy to overclaim. The framework does not tutor you and it does not lecture. There are no lessons and no walls of theory. What teaches is the enforcement itself: a gate you cannot skip makes you encounter a practice you would otherwise have walked straight past, and the guide it points to holds the reasoning for when you want it. So when we say it teaches, we mean the required process puts the right way in front of you, not that the tool explains best practice at you.

## Why enforce, instead of just advising

Here is the uncomfortable thing we kept running into: **simple skills get ignored, and even CLAUDE.md gets ignored at some point in a long session.** Advice is easy for a model to drift away from. It forgets, it rationalizes, it takes the shortcut. So this is a plugin with gates, not a folder of prose. The phases are commands, the standards are gates that write a verdict you can read, and the guardrails are hooks. Advice still guides the work. Enforcement is just what keeps it honest once the session runs long and the advice has scrolled out of the model's attention. This is a claim about reliability, not about structure being smarter than you. You are smart. A gate is just harder to forget than a sentence in a markdown file.

There is a second reason, pointing the other way. An optional practice only reaches people who already know to ask for it. If you have not run into test-driven development yet, you will not turn on a switch you do not know is there, so making it optional quietly leaves out the people who would most benefit from meeting it. Making the core practices non-optional is how everyone gets them, not just the already-initiated. What you enforce is what everyone benefits from; what you leave optional, only people who already know it exists will ever find.

## You make every decision

The structure never makes a design call for you. You pick the approach, the pattern, the trade-off. What it refuses is the half-done version: research that skipped the existing-solution check, an architecture with no acceptance criteria, code with no tests, a "done" that was never reviewed. Put plainly, you own the *what*, and the framework owns the *that-it-actually-happened*. The scope contract (`/scope`) is where this is most literal: you write the goal and the success criteria, and every later phase is held to what you wrote, not to what the AI felt like doing.

## Everything the AI does gets challenged

We treat it as an assistant, not an oracle. It is fast and useful and confidently wrong often enough that nothing it produces should be trusted just because it sounds right. So challenge is built in, not bolted on. A stated mechanism gets challenged against the native pattern before it is adopted (mechanism-challenge). A built work-order gets an independent, fresh-context critic that reads the diff as hostile (wo-critic). Research can run as competing agents that debate instead of one confident pass (research-team). Validation can run in isolated teams free of the main session's bias (validate-team). The point is the same everywhere: make the AI argue with itself before you have to.

## AI is fast, we are responsible

Because you own the outcome, the machinery is deterministic exactly where a mistake is expensive. The irreversible actions (a destructive git command, a merge, bypassing a gate) are blocked or halted by scripts, not by the model's good intentions. A model can be talked into anything; a fail-closed check cannot. The guards that matter run as zero-model kernels, so they behave the same on a good day and a bad one.

## Fresh context is good; the orchestrator's memory is what holds it together

A lot of the work runs in fresh-context agents, and that is deliberate. A clean agent reviewing a diff has no stake in the story that produced it, which is exactly why the critics and validators are separate agents. But fresh context is not free. Something has to remember the *process*: the corrections you made an hour ago, the guidance you gave that is not written into any skill yet, the reason we are doing it this way and not that way. That memory lives in the orchestrator, the session driving the whole thing. So we lean toward running work through agents while keeping the orchestrator as the thread that remembers. We do not fully enforce this yet; it is the direction we are moving, not a finished guarantee.

## Why it works on any stack

You cannot write a skill for every nuance of every framework, and then a skill for every best practice on top of that. That road is combinatorially hopeless and you would spend forever maintaining it. So a *stack* is data, not engine code. The engine holds zero framework knowledge. A framework's method for each phase lives as a **process recipe**, and the domain knowledge lives in **guides**, both of them external, versioned, and growable. Supporting a new stack means writing those assets, not touching the engine. It also means the reference material the framework can reach keeps growing without the framework itself getting heavier, and there is room to point it at more references over time rather than baking every fact into a skill.

## The trace is worth keeping

The usual knock on a framework is that it hides what happened and makes debugging harder. The opposite holds here, with one honest qualification. Every run leaves a trace on disk: the phase artifacts, the gate verdicts, the loop log, the PR body. When a past *decision* looks wrong, you open the file and read what happened instead of reconstructing it from memory. That is genuinely easier. The qualification: it is a trace of the authoring process, not of your program's runtime. It tells you why the AI chose X, not why the code crashes in production. Different problem, still worth having.

## It is not finished, and that is the process

None of this is perfect. The AI still finds a way, now and then, to skip a step we thought was nailed down. We treat each one as the next thing to close: a drift we catch becomes a gate, a gap someone hits becomes a check. Most of the machinery here exists because something slipped past an earlier version of it. So the honest promise is not that the AI can never cut a corner. It is that when we find a corner being cut, we work to turn it into one that cannot be. The framework gets tighter the more it is used, and the gaps you find are welcome, because they are how it improves.

## Where this comes from

The core positioning (guided rigor for everyone; the split between gates that enforce and guides that explain the why; the pure-agnostic engine with stack-as-data) is set out in the founding design doc, *AI Dev Assistant design* (2026-06-12). The dev-guides site the framework consumes is the standing form of the guides half, and is useful on its own. The rest (responsibility, enforce-don't-just-advise, challenge-everything, the orchestrator's memory, trace-as-asset) is the framework's current design, enforced by the machinery each plugin's README describes.
