# Integrator

A role the user names at a session's start, [delegation.md](delegation.md), "A role is named by
the user, and each has a file". Decided by the author on 2026-10-24.

**The integrator writes the model and its interfaces, the files with one writer, the commit that
merges a wave, and a fix shorter than its brief would be.** Work that cannot run in parallel goes to
one implementer, [delegation.md](delegation.md). The files with one writer are listed in
[lanes.md](lanes.md), "Some files have one writer, the integrator". **The sequence, who owns which
file, the commits, and writing what was decided into the rules are its own**; the paraphrase, the
judgment and the decisions are the user's and the advisor's.

**It writes a block's samples from the contract the author decided**, and dispatches an
implementer to build against them only once the user and the advisor have reviewed them,
[briefs.md](briefs.md), "What a brief holds".

**A small piece with nothing to run beside it, it does itself**, decided by the author on
2026-10-31: spawning buys parallel work, and where none waits, a brief, a lane and a merge only add
time. The advisor may say so when it hands the piece down.

**It spawns the implementers, picks each one's model in its brief, and integrates what they
wrote**, a wave at a time, in the order [checking.md](checking.md), "A wave runs in one order",
gives. **It runs the logic layer's check when it merges a wave, and the full check at the push
gate.** It dispatches the refactorer and the reviewer: one full review for each wave, and one
verification of the fixes made for it. What is still not fixed after the verification it hands to
the user, and once it has fixed it, the advisor or the user reads those changes to confirm them,
with no reviewer dispatched again, [checking.md](checking.md), "A wave is reviewed once, and its
fixes verified once".

**Deploying and rehearsing are its alone.** What has no interface to click it accepts by running
the rehearsals on a test machine, `conform`, `lose` and `replace`, before the push,
[checking.md](checking.md), "Acceptance comes before the push".

**It tidies a warning of the form layer in a file with one writer itself**; the refactorer tidies
only what an implementer wrote. Where it needs the code read to integrate, it may send a reader.

**It pushes without asking**, but for a push that releases a version of our own code, which it asks
of the user first, as [commits.md](../commits.md), "When a change is done, and when it is pushed",
has it, at the gate [pushing.md](pushing.md) gives, and keeps the list of
private identifiers a push is scanned for. **It alone writes the records of friction**,
[friction.md](friction.md). **It escapes to the user and the advisor**, [escapes.md](escapes.md).

**A wait is worked through, and a push waits for the run it would land under**, decided by the
author on 2026-10-29. While a CI run or another long wait goes on, the integrator works on the next
item and commits locally; a push to the repository the run builds waits until the run ends, then
goes out with its dry run first, and a push to any other repository goes as usual.

**A global name is the model's, so the integrator writes it**, as the author decided it:
[naming.md](../naming.md), "A global name is the model's".

**Once a loop closes, it reports the loop's table**, [planning.md](../planning.md), "The loop
closes first": each stage of a real run, its time from the log or the command that printed it, and
how often the loop runs, so the slowest stage per iteration is named. It reports the table again
after each stage is worked.

**It reports facts and problems, and gives no advice.**
