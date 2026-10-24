# Briefs

What a spawned agent is handed when the integrator dispatches it. How the work is split is
[delegation.md](delegation.md); a reader's brief is [reading.md](reading.md).

## A spawned agent is an editing tool that can think

**A brief names an outcome, not a procedure.** If it is naming lines and characters, the edit
should have been made directly and the brief is pure overhead. If it names a goal the implementer
has to take a decision to reach, it should have been a question to the user. A brief lives between
those two: a specific command, in the project's own terms, with the how left to the implementer
because the implementer is standing in the file and the top level is not.

Briefed that way, most edits land correct with nothing checking them. Not all of them, which is
why the diff gets read; the estimate is the user's and it is not good enough to skip the net.

**The model follows the difficulty, and the integrator picks it in each brief**, decided by the
author on 2026-10-24. An implementer runs as Sonnet at low, medium or high effort, or as Opus at
medium, the cheaper first; Opus is sent only where the edit is not plain -- a change that has to be
worked out in the file, across a contract, or after a Sonnet implementer came back without it. A
reader is Sonnet at low effort, a reviewer Opus at high and a refactorer Opus at medium, each in
its role file. The integrator says which model in the one line the user is shown.

**An implementer that meets a problem reports it rather than forcing its way through.** A test
that will not pass, an error it does not understand, a second attempt at the same fix: each ends
the implementer's turn with what it saw, quoted, and the top level decides -- a new brief, a
stronger model, or a question to the user. A fix forced past a problem it did not understand is
the diff that looks finished and is not.

## What a brief holds

**An implementer's brief is what `mise run brief <name>` prints**, with its lane's path, the set of
files it owns, and the dependencies it waits on that are still waiting, decided by the author on
2026-10-24. What `brief` prints ends in the completion protocol, `built` while writing and
`accept <name> --from <base>` once, [implementer.md](implementer.md); until `accept-in-lane` lands,
`accept` still lets another block's files stand, [lanes.md](lanes.md). **A reader's brief names the four things**
[reading.md](reading.md), "Reading is delegated; the judgment on what comes back is not", gives.

**Samples come before an implementer.** The integrator writes a block's samples from the contract
the author decided, and an implementer is dispatched to build against them only once the user and
the advisor have reviewed them.

**Every brief carries these, because a spawned agent starts cold.**

- Delete with `trash`, as `AGENTS.md` has it, and there is no recursive flag -- a directory goes
  as it is. It is in [toolchain.md](../toolchain.md) with the reason, and an agent that has not
  read it reaches for `rm` and, outside the whitelist, gets a refusal it has to recover from.
  Carry the flag fact into the brief: the rule survives being paraphrased and that one detail does
  not, so an agent holding `rm -rf` habits goes looking for the switch and falls back when it
  finds none.
- **It types no version control command**, neither jj nor git: it does not commit, move a bookmark
  or push. A task it runs, as `accept --from`, may read its own lane's history.
- **Which files are its own, as an explicit list, and that every other file belongs to somebody
  else.** See [lanes.md](lanes.md), "File ownership is the whole of the concurrency control"; this
  is the line the whole arrangement rests on.
- **A short name**, because an agent that cannot be referred to cannot be parked, reported on in
  one line, or asked after by the user.
- **Which sections of the rules bind this change**, cited by name so it reads them rather than
  inferring the convention from the code around it.
- Whether the tree is expected to compile. Parts written in parallel against a contract will not
  until they are all declared, and an implementer that does not know that will try to fix it.
- **Build, type-check, lint and test its own block, the logic layer, and never run a whole
  repository's check.** The older rule against running tests or the type checker came from one
  working copy shared by every agent, and lanes ended it; [checking.md](checking.md), "Testing is
  the user's; checking is the integrator's".
- **Docker used for a test is taken down when the test is done** -- its containers, networks and
  volumes, every image built for it, and any large or once-used pulled image -- as
  [agent-protocol.md](agent-protocol.md), "A long command never holds the conversation", says.
  The report says what was removed.
- **Do not touch the rules or `AGENTS.md`**, and do not reformat or tidy code the brief did not
  name. A neighboring improvement is indistinguishable from a mistake in a diff, and it lands in
  a commit about something else.
- **A report longer than a few dozen lines is written to a file, and the message names its path.**
  The notice a finished agent sends is cut at a fixed length, not where the agent stopped, so
  asking for the report again meets the same cut; the integrator reads the file itself, or asks
  for what follows the cut, or for a report kept under the length. Learned on 2026-10-21, the
  author's observation after three reports in one session came back cut mid-sentence.
- **Stop and report rather than improvise.** A brief that turns out to be wrong, a file it needs
  and does not own, a rule it cannot satisfy and follow at once: all of these come back as a
  report. Twice in one session an implementer found a signature that disagreed with its brief and
  asked; both times the brief was the thing that was wrong, and quiet conformance would have
  broken files it did not own.

**Every decision reached in a message is written into the tree before the work is called done**
-- into a comment where the next reader meets it, a section of the rules, or a commit body. A
message is where a decision is _reached_; it is never where one _lives_. This is what answers the
objection in [agent-protocol.md](agent-protocol.md), "Working beside other agents": a decision
made in a conversation between two agents is otherwise recorded nowhere, and the arrangement here
is only legitimate because it does not stay there.
