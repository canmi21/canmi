# Checking

How a wave is checked, reviewed and committed. How the work is split is
[delegation.md](delegation.md); how the lanes are merged is [lanes.md](lanes.md).

## The check has two layers

Decided by the author on 2026-10-24. Each rule in `model/rules/` carries the layer it belongs to,
`Rule.layer`, and **a rule that carries none is of the logic layer.**

**The logic layer** is type checking, tests, samples, the semantic half of lint, whether a block
agrees with its contract, the direction of dependencies and the rules of layers, file ownership --
a block changing only its own directory, and the files with one writer -- and global names. **An
implementer's work passes it for its own block before it is handed back**: the block's build, type
check, lint and tests, never a whole repository's check.

**The form layer** is a directory's width and depth, `tree-wide` and `tree-deep` of the shape part
alone; a file's length; and a comment's lines. **Once `formatted-on-write` lands, formatting is in
neither layer**: a hook formats each file as it is written, [lint-format.md](../lint-format.md), "A
file is formatted as it is written", and `accept`'s check of formatting always passes in a lane.
Until then formatting is checked as it is now, by each repository's own check.

### The form layer holds at gates, never while code is written

**Nobody checks the form layer while code is being written.** At a commit it only warns, and the
commit goes through, `form-at-commit`; **before a push it is an error, and the push stops**, by the
means `audit` already has, counting the form layer's warnings as failures, in either mode,
`push-form-clear`, [pushing.md](pushing.md). Push holds it since 2026-10-24 over the tree of the
commit each pushed bookmark points to. A warning of the form layer says the commit it first appeared
in and how many commits have passed since, worked out from the repository's history; that is a hint,
and changes no result.

**The refactorer tidies only what an implementer wrote.** A warning in a file with one writer that
the integrator wrote is tidied by the integrator itself, with no refactorer dispatched.

## A wave runs in one order

1. The implementers write the logic, each passing the logic layer alone; in parallel once
   `implementer-commands` lands, and one at a time until then.
2. The integrator merges the lanes in one merge with a parent for each, runs `mise run fmt` on the
   merge, and runs the logic layer's check.
3. The integrator commits, the form layer only warning, `form-at-commit`.
4. Where the form layer warns, the refactorer is dispatched.
5. A reviewer reads the diff.
6. The wave is accepted, as "Acceptance comes before the push" gives.
7. The push gate, where the full check runs, [pushing.md](pushing.md).

**A commit still waits until `mise run check <path>` passed at the working copy**,
[commits.md](../commits.md), unchanged.

### A wave is reviewed once, and its fixes verified once

Decided by the author on 2026-10-24.

- **A wave has one full review.**
- **The fixes made for that review are verified once**, and the verification reads only the items
  its report listed; it is no second full review.
- **What a verification finds beside them**: a defect of high severity stops the work and goes to
  the user; any other blocks no push and is written as a record of friction,
  [friction.md](friction.md).
- **What is still not fixed after the verification goes to the user.** Once the integrator has
  fixed it, the advisor or the user confirms it by reading those changes directly, and no reviewer
  is dispatched again.
- **A commit that changes the review's own procedure is approved by the procedure in force before
  it**, never by the one it brings in.

### Acceptance comes before the push

**A wave's commit is local and may come before acceptance; where acceptance fails, the fix is
squashed into that commit before the push.** What has an interface to click is accepted by the
user clicking it. What has none is accepted
by the integrator running the rehearsals on a test machine, `conform`, `lose` and `replace`.

## Testing is the user's; checking is the integrator's

They are different things and the rule differs for each.

**Testing** -- does this behave the way it should -- belongs to the user. They will say when
something is wrong, and they will say it faster than any verification loop. The evidence is
direct: a hover that revealed the mark on the first pass and never again took six browser round
trips to find, and the user would have said "it does not come back on the second hover" in two
seconds of clicking.

**Checking** -- does it type, lint and format -- belongs to the integrator, **once per wave,
before the user is asked to click.** Before rather than after, because a type error means the dev
server is serving a broken bundle: the user's click test then costs them a round trip to learn
what the checker would have said for free.

**An implementer runs its own block's build, type check, lint and tests, the logic layer, and
never a whole repository's check**, decided by the author on 2026-10-24. Checking the whole is a
question only the party that sees the whole wave can ask. The older rule, that a spawned agent ran
no tests and no type checker, came from one working copy shared by every agent, where several would
run one suite against one tree at once; it does not hold once each has a lane of its own. **Where
what it writes is one part of the check, it may run that part alone**, `mise run check <repository>
<part>`, and never the whole, decided by the author on 2026-10-24.

**A block a project's model holds alone is the case it is made for**: where each block builds, lints
and tests apart from every other, as `monoflake/platform`'s `docs/code.md` makes them, its
implementer runs the block's `built` and `accept --from <base>`, which touch nothing a neighbor
shares, each sibling it builds against being a jj workspace of that sibling's own in its lane,
[lanes.md](lanes.md), "A lane is a directory beside `repos/`". **It types no jj command**; a task it
runs, as `accept --from`, may read its own lane's history. Such a task snapshots its own lane's
working copy first, as every jj read does to see the latest edits; that touches its own lane's
working-copy commit alone, and records one operation in the shared store, where jj merges the
operations several workspaces make at once by itself. The integrator reads what changed.

**The browser and the desktop window open only when the acceptance criterion is a number.**
Geometry, timing, drift, a count -- things clicking cannot produce. The rail's indicator was
209px from its own label at the instant it appeared and traveled 125px up the viewport
afterwards, and no amount of looking would have turned that into a fix; the measurement was the
fix. Everything else goes to the user. This narrows [agent-protocol.md](agent-protocol.md),
"Checking your own work", rather than contradicting it: that section asks whether reading the
code could answer the question, and this one adds that even when it could not, the answer has to
be a number before the round trip is worth its cost.

## The integrator reads the diff, not the file

**Every implementer that returns gets its diff read** -- `jj diff` over the paths it owned. The
diff, not the files: the cost is a fraction of authoring the change and it is what makes briefing
at four-in-five acceptable rather than reckless.

Four things are being looked for, and an implementer's own report is evidence for none of them:

- it changed the files it was given, and no others;
- it did the thing, rather than something adjacent that was easier;
- it left nothing half-finished behind a plausible summary;
- it did not walk past a rule the brief had cited.

**A read has a timestamp, and a report is a read somebody else took.** That distinction was
learned expensively: a supervisor once answered which of two landed shapes was right from two
implementers' reports read against each other rather than from the file, got it backwards,
retracted it, and got the retraction backwards too -- while the implementers were reading the spec
it was rewriting from those reports. Between two descriptions of one file, neither is evidence.
The file is. Checking is half of it; checking that the check is still fresh when the sentence is
written is the other half.

There is a second reason, and it is not about trust. **The integrator writes the commit message
and the rule's entry, and neither can be written from somebody else's summary.** A commit body
says what changed; a rule says what was decided and why. Both are claims about a tree that has to
have been read.

## Commits separate concerns, not buildable states

**Commit by path list.** Ten changed files landing as three commits is three `jj commit` calls
naming their paths -- not three rounds of restoring the tree to a state it never passed through.
The staging dance buys a history that looks like the work was done in order, and the work was not
done in order.

**A commit here is not required to build on its own.** This is the author's workspace, not a
library with bisect discipline and strangers depending on its history. A commit's job is to keep
one concern legible; where two timelines cross inside one, that is the honest record of an
afternoon in which two things were being done at once.

**Only the integrator commits.** This is a carve-out from [commits.md](../commits.md),
"Completion", which has an agent commit its own completed work: that rule holds for an agent
working directly, and is suspended for a spawned agent, which never commits, never describes and
never moves the bookmark. The alternative is a bare `jj commit` sweeping a neighbor's half-written
files into somebody else's change, silently.

**The integrator pushes at the gate.** When to push is [commits.md](../commits.md), "When a change
is done, and when it is pushed", and the gate is [pushing.md](pushing.md); the integrator says
each push in one line.

**Accept before the push, not before the commit**, decided by the author on 2026-10-24, in a wave.
The sequence is "A wave runs in one order": the wave is committed locally, reviewed and accepted,
and only what was accepted is pushed. A run of requests worked live with the user, in a session with
no role, commits instead when the user moves on to the next request, the one before then being
settled, [commits.md](../commits.md), "When a change is done, and when it is pushed".

**The trap is silent and has caught this project before.** A path list omits what it does not
name, without saying so: a rename is two paths, a bracketed path needs quoting, a file the wave
touched incidentally is simply left behind. `jj st` is read after every partial commit, and what
remains uncommitted is compared against what was meant to remain.
