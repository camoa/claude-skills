# What a test is

In AIDA, the implement stage is test-driven development. This page says what a test is. Every
role that writes, judges or runs a test reads it. Other pages point here and do not say it again.

## A test

- A test is written before the code, from a criterion or a done-when row.
- It proves one behaviour, at the lowest level that shows that behaviour.
- It is seen failing for the right reason: its own assertion did not hold.
- Then code is written until it passes.

A frozen test is a test after the freeze. Nobody changes it after that, so the code cannot bend
the test to pass.

## What a test is not

- An end-to-end test or a browser test.
- A visual baseline.
- A script that runs a whole flow, or the whole tool, where one call shows the behaviour.
- The project's full suite.

End to end and visual regression are the surfaces. Review runs them after the build. A criterion
that only a surface can show is proved by that surface at review. The order's tests prove the
behaviour beneath it.

## Too heavy is not proved

A test that does more than its behaviour needs is sent back, the same as a test that does not
prove its behaviour. It is too heavy when it runs a whole flow or the whole tool where one call
shows the behaviour. It is too heavy when it proves more than one behaviour. The recipe says which
level shows a behaviour. AIDA names no level.

## The light-mode exception

A light task keeps one test of another kind, by design: the one script that walks the demo path.
Its first work order owns that script, and review runs it as a surface.
