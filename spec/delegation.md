# Delegation

How work is split between the conversation the user is having and the agents that conversation
spawns. The split is shaped for the user's hands, not for an agent's throughput, and every rule
below follows from that.

## Whether a session delegates is the user's call, and the default is no

**A session works directly until the user says it delegates.** No spawned worker, no read sent
out, no wave -- the conversation reads, edits, checks and commits on its own, under
[commits.md](commits.md), "Completion", as any agent working directly does. The user decides per
session, and says so in words: "this session dispatches", "use agents", or the like.

**Once they have, every section below applies, and it holds until they say otherwise.** It is not
re-asked each turn, and it does not lapse into a judgement about which tasks seem worth a worker
-- "When not to delegate" still governs the individual edit, but it never turns delegation back
on in a session that has not been told to, nor off in one that has.

**The agent does not propose it either.** A task that looks parallel is not a reason to ask; the
user knows this file exists and turns it on when they want it.

## The point is the user testing while the conversation builds

**The user is the fastest test this project has.** They click in two seconds what a browser
round trip costs minutes, they are already looking at the thing, and they are the only party who
knows what "feels wrong" means. So the loop is not _finish, verify, report_. It is: hand back
something clickable, and go on working while it is being clicked.

Two obligations follow, and they are what actually saves the time.

**Never end a turn without something for the user to do.** A turn that ends in "still working"
spends their attention and returns nothing to spend it on.

**Never hold a turn to confirm what they would confirm faster.** This is the existing rule in
[agent-protocol.md](agent-protocol.md), "Checking your own work", and delegation does not soften
it -- it makes it load-bearing, because the cycles saved by not confirming are the cycles the
next wave is dispatched in.

**And an honest limit, so this is not sold as more than it is.** Parallelism pays only where
there are two or more independent concerns. A request with one causal chain stays serial however
many workers exist: the table of contents indicator was one chain -- collapsed geometry, open
geometry, one element -- and no arrangement of agents would have made it two. What delegation
buys there is not wall-clock but **context**: a few hundred tokens of brief instead of twenty
thousand of reading and editing, and a conversation that can still hold the whole task at the
end of it.

The wall-clock lever is elsewhere, and half of it is the user's. **A batch of requests in one
message becomes a wave of agents; one request at a time stays a queue however it is executed.**
The other half is the overlap: wave N is being clicked while wave N+1 is being dispatched. A
conversation that goes quiet for ten minutes has failed at this even if every agent in it
succeeded.

## A returning worker is an event, not an instruction

A worker that finishes sends a notification into the conversation, and it arrives wherever the
conversation happens to be -- which is usually in the middle of something else. **It does not get
to set the topic.** The default is to park the result and finish the exchange in progress.

This is not politeness, it is the point of the whole arrangement. A conversation that stops to
report every return has spent the freedom it delegated the work to buy: the user is back to
waiting on a worker, through an intermediary, having gained nothing.

**Parked results surface at the seam between topics, never inside one.** "Right, that is
settled", "let us look at the other thing", a question that closes a thread -- those are where a
parked result comes out. Mid-idea is not.

**One turn, one topic.** Answering the idea, reporting a returned worker and dispatching the next
one in a single message is the failure this rule exists to prevent: three things arrive at once
and none of them is legible.

**Three things break the thread, and each gets one line rather than a report.**

- **A worker is blocked.** That is not a result, it is a stalled resource, and every exchange it
  waits through is the parallelism this arrangement was built for, idle.
- **What came back contradicts the premise of what is being discussed right now.** Designing on a
  fact that has just been disproved costs more than the interruption does.
- **The new idea touches a file an in-flight worker owns.** This is not a report at all, it is
  "File ownership is the whole of the concurrency control" doing its job. Say so before the idea
  is designed around a file that is being rewritten underneath it.

**Reading which of these applies is judgement, and nothing in the notification carries it.** If
the user's last message was about something else, they are on something else. If they ask how it
is going, they want the result. The signal is what they are doing, not what has arrived.

## What the conversation keeps

Three things, and they are the three that cannot be handed to a worker that starts cold.

**Paraphrase.** Turning what the user said into this project's terms is the whole of the top
level's value. The user says the indicator feels wrong; the brief says which function writes
which property, in which of the rail's two layouts, and which one it should have been reading. A
worker handed the first sentence goes and rediscovers the codebase, and is paid for by the token.

**Decisions, and `spec/`.** Who decides what is [agent-protocol.md](agent-protocol.md),
"Decision authority", unchanged. What delegation adds is that **a spawned agent never writes
`spec/` or `CLAUDE.md`**: the rules are the shared decision record, two workers editing them
concurrently conflict by construction, and a rule is a decision, which was never the worker's to
take. A worker that believes a rule is wrong says so in its report, which is the same thing it
does with a brief it believes is wrong.

**Sequence and commits.** Who runs when, who owns which file, and what lands in which commit.

**Judgement.** Working out _why_ something is broken, and what the fix has to be, stays here. It
is made on text a worker quoted back rather than on a worker's conclusion, which is the subject
of the next section.

## Reading is delegated; the judgement on what comes back is not

**In a delegating session, reading the code is delegated too, not only searching it.** Both halves of the cost are
worth avoiding: a file read into the conversation stays there for the rest of the session, and
the minutes spent reading it are minutes the user is waiting rather than talking. A worker reads
in the background and the thread stays free, which is the whole arrangement in one sentence.

**A read brief names four things**, and the fourth is what makes it worth sending at all.

- **The scope.** Files, a directory, or a pattern -- never "the codebase". A worker given the
  repository will give back an essay.
- **The tool, and the pattern where it is already known.** `rg` for text, `ast-grep` for
  structure -- a call shape, a hook, every implementation of one interface. Naming the pattern
  saves the worker rediscovering what the conversation already worked out.
- **The question, in one sentence.**
- **The return shape**: the exact lines, quoted, with `file:line`; the enclosing signature or
  declaration so the frame around them is visible; a line cap; and one paragraph answering the
  question, kept apart from the quotation.

**The quotation is evidence and the paragraph is not.** A report is a read somebody else took --
a quoted line is the read itself, taken through a worker instead of by hand. The two arrive in
one message and must not be weighed the same.

**A line cap is not tidiness.** A worker that returns the file has returned the problem: the
context was spent, just later and by somebody else.

**Choosing which ten lines to quote is itself a judgement, and it can be wrong.** Asking for the
enclosing structure makes a badly framed snippet visible sometimes, and not always. The reliable
signal is the other one: **an answer that surprises is read again by hand.** A finding that does
not fit what the rest of the tree implies is either a discovery or a mis-framed quotation, and
from the summary those two look identical.

**Dispatch as soon as an area is named, not when the plan is settled.** A user describing an idea
that plainly touches the rail, the CMS window, one worker -- the read goes out then, and by the
time the idea is settled the evidence is already back. This inverts the usual order, where
research follows the decision, and it is only available because reads run in the background. The
area has to be concrete enough to scope a brief; a vague mention buys a speculative read nobody
uses.

**The conversation reads for itself** when the answer surprised it, when the file is a handful of
lines whose shape it already knows, or when the question is one it cannot state without having
seen the file -- which is the honest description of some debugging.

## Research has the same brief as a read, pointed outward

A question about an upstream -- a platform limit, a runtime's behavior, what a library actually
does -- is delegated on the same terms as reading this tree, with three additions.

**Name the sources and their order.** Primary first: the vendor's own documentation, its blog,
its source. Where a documentation skill for that vendor exists, it is invoked before the open
web. And say the quiet part explicitly: **do not answer from memory without checking.** Platform
numbers change, a model's recollection of them does not, and a stale limit stated confidently is
the one outcome that makes the research worse than not having done it.

**Ask for the mechanism, not the verdict.** A brief that asks "should we do X" gets an opinion.
A brief that asks how the thing works, with the verdict as the last line, gets something the
conversation can reason from when the next question turns out to be adjacent rather than the
same. The test to write into the brief: **enough that the reader could predict the answer to a
question that was not asked.**

**Require the line between fact and inference to be drawn every time**, and make "not documented"
an acceptable answer. A worker that cannot distinguish the two returns something worse than
nothing, because it cannot be checked without redoing the work. A load-bearing claim carries its
URL inline, or it carries the word "inferred".

**Concise but not thin** is the standard, and it is worth saying in exactly those words. Without
it a research brief comes back either as a paragraph that repeats the question, or as a survey
of everything adjacent. Bound it the way a read is bounded -- a reading time, a line cap on
quoted code -- and forbid the filler by name: no restating the question, no explaining what the
subject is, no recommendation that was not asked for.

**A research brief usually has a local half, and it belongs in the same worker.** What the
platform does in general is only half an answer; what this tree does with it is the other. One
worker holding both gives an answer already applied, and the alternative is the conversation
joining two reports that were written without reference to each other -- which is the failure
recorded in "The conversation reads the diff, not the file".

## A spawned agent is an editing tool that can think

**A brief names an outcome, not a procedure.** If it is naming lines and characters, the edit
should have been made directly and the brief is pure overhead. If it names a goal the worker has
to take a decision to reach, it should have been a question to the user. A brief lives between
those two: a specific command, in the project's own terms, with the how left to the worker
because the worker is standing in the file and the conversation is not.

Briefed that way, most edits land correct with nothing checking them. Not all of them, which is
why the diff gets read; the estimate is the user's and it is not good enough to skip the net.

**Every brief carries these, because a spawned agent starts cold.**

- Delete with `trash`, never `rm`, and there is no recursive flag -- a directory goes as it is.
  It is in [toolchain.md](toolchain.md) with the reason, and a worker that has not read it reaches
  for `rm` and hangs the turn with nobody watching. Carry the flag fact into the brief: the rule
  survives being paraphrased and that one detail does not, so a worker holding `rm -rf` habits
  goes looking for the switch and falls back when it finds none.
- `jj`, never `git`. It does not commit, does not move the bookmark, does not push.
- **Which files are its own, as an explicit list, and that every other file belongs to somebody
  else.** See "File ownership is the whole of the concurrency control"; this is the line the
  whole arrangement rests on.
- **A short name**, because a worker that cannot be referred to cannot be parked, reported on in
  one line, or asked after by the user.
- **Which `spec/` sections bind this change**, cited by name so it reads them rather than
  inferring the convention from the code around it.
- Whether the tree is expected to compile. Parts written in parallel against a contract will not
  until they are all declared, and a worker that does not know that will try to fix it.
- **Do not run the test suite, the type checker, the formatter or the linter.** The reason is in
  "Testing is the user's; checking is the conversation's" below.
- **Do not touch `spec/` or `CLAUDE.md`**, and do not reformat or tidy code the brief did not
  name. A neighbouring improvement is indistinguishable from a mistake in a diff, and it lands in
  a commit about something else.
- **Stop and report rather than improvise.** A brief that turns out to be wrong, a file it needs
  and does not own, a rule it cannot satisfy and follow at once: all of these come back as a
  report. Twice in one session a worker found a signature that disagreed with its brief and
  asked; both times the brief was the thing that was wrong, and quiet conformance would have
  broken files it did not own.

**Every decision reached in a message is written into the tree before the work is called done**
-- into a comment where the next reader meets it, a `spec/` section, or a commit body. A message
is where a decision is _reached_; it is never where one _lives_. This is what answers the
objection in [agent-protocol.md](agent-protocol.md), "Working beside other agents": a decision
made in a conversation between two agents is otherwise recorded nowhere, and the arrangement here
is only legitimate because it does not stay there.

## File ownership is the whole of the concurrency control

There is one working copy, and that is a decision with its own reasoning and its own accepted
cost -- [toolchain.md](toolchain.md), "Rejected: parallel workspaces". It leaves file ownership
as the only partition available, and being the only one, it has to be exact.

- **The file set is declared before dispatch**, not discovered during it.
- **Disjoint sets run together; overlapping sets run in sequence.** There is no third answer, and
  no locking cleverness worth inventing for a handful of workers.
- **A file two workers might both want belongs to the conversation** and to nobody else. A module
  list, a shared type, a route table, a constant two features both read.
- **One refactor is one agent.** A signature and its call sites are a single task however many
  files they span. Splitting them gives two workers one interface to guess at independently,
  which is the failure this repository has already paid for once: one interface rewritten seven
  times in an afternoon, every disagreement silent, each found by a person happening to describe
  it out loud. Parallelism is across independent concerns, never across one change.

The structural repair is worth more than the discipline. Two hand-written spellings of one
interface, in two programs that never compile together, disagree silently by construction -- and
that afternoon ended by moving the shape into a package both import, so the eighth disagreement
would have been a compile error. A rule that asks people to be careful is what gets written when
the rule that makes carelessness fail loudly is not yet available.

## File ownership partitions files, and that is all it partitions

The section above is the whole of the concurrency control for editing. Five things sit outside
editing, and each of them was found by being broken.

**Measurement intersects writing even where the file sets are disjoint.** A worker measuring a
build while other workers edit its sources measures a tree that never existed. The first CSS budget
figures of that session were already stale by the time they were read. A measurement is scheduled
between waves, never beside one.

**jj snapshots the whole tree, so every jj write waits for the writing to stop.** A `jj commit`
taken while a worker was mid-write produced `Concurrent checkout` and a divergent change id. The
recovery is to confirm the orphan's content is live in the working copy, then `jj abandon` it.

**A constraint adopted for concurrency is re-evaluated when the concurrency ends.** A rule that
exists because two workers were in flight outlives its reason unless somebody says so out loud.

**The conversation's own checking method is proven to fail before it is trusted.**
`mise run verify 2>&1 | tail` returns `tail`'s status, so every "exit 0" read that way meant
nothing. A worker comparing comment block counts read `jj file show -r @`, which returns the
working copy because jj auto-snapshots it, compared new against new, and reported a perfect green
from a comparison that had not happened. This is [code.md](code.md), "A rule is maintainable only
when breaking it fails loudly", pointed at the checker instead of at the code.

**A project's task and the workspace's can share a name, and the wrong one passes.** `mise run
refs` from the workspace runs the workspace's gate, which never reads `repos/lattice/spec`. A
worker verified a lattice edit against it twice and reported a green count line that had not looked
at the file it changed. **The path goes in the brief**: `mise run //repos/lattice:refs`.

## Testing is the user's; checking is the conversation's

They are different things and the rule differs for each.

**Testing** -- does this behave the way it should -- belongs to the user. They will say when
something is wrong, and they will say it faster than any verification loop. The evidence is
direct: a hover that revealed the mark on the first pass and never again took six browser round
trips to find, and the user would have said "it does not come back on the second hover" in two
seconds of clicking.

**Checking** -- does it type, lint and format -- belongs to the conversation, **once per wave,
before the user is asked to click.** Before rather than after, because a type error means the dev
server is serving a broken bundle: the user's click test then costs them a round trip to learn
what the checker would have said for free.

**A spawned agent runs neither.** Not because it could not, but because several of them in one
working copy would run the same suite against the same tree at the same time, and the failures
that produces are about the concurrency rather than about the code. Checking is a whole-tree
question and only the party that sees the whole wave can ask it.

**The one test a spawned agent may run is one it can isolate**: pure logic, no dev server, no
port, no process anyone else is sharing, and nothing written outside the files it owns. A
function it just wrote, with the test file it just wrote beside it. Not the suite, not a build,
not anything that needs the application up.

**The browser and the desktop window open only when the acceptance criterion is a number.**
Geometry, timing, drift, a count -- things clicking cannot produce. The rail's indicator was
209px from its own label at the instant it appeared and traveled 125px up the viewport
afterwards, and no amount of looking would have turned that into a fix; the measurement was the
fix. Everything else goes to the user. This narrows [agent-protocol.md](agent-protocol.md),
"Checking your own work", rather than contradicting it: that section asks whether reading the
code could answer the question, and this one adds that even when it could not, the answer has to
be a number before the round trip is worth its cost.

## The conversation reads the diff, not the file

**Every worker that returns gets its diff read** -- `jj diff` over the paths it owned. The diff,
not the files: the cost is a fraction of authoring the change and it is what makes briefing at
four-in-five acceptable rather than reckless.

Four things are being looked for, and a worker's own report is evidence for none of them:

- it changed the files it was given, and no others;
- it did the thing, rather than something adjacent that was easier;
- it left nothing half-finished behind a plausible summary;
- it did not walk past a `spec/` rule the brief had cited.

**A read has a timestamp, and a report is a read somebody else took.** That distinction was
learned expensively: a supervisor once answered which of two landed shapes was right from two
workers' reports read against each other rather than from the file, got it backwards, retracted
it, and got the retraction backwards too -- while the workers were reading the spec it was
rewriting from those reports. Between two descriptions of one file, neither is evidence. The file
is. Checking is half of it; checking that the check is still fresh when the sentence is written
is the other half.

There is a second reason, and it is not about trust. **The conversation writes the commit message
and the `spec/` entry, and neither can be written from somebody else's summary.** A commit body
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

**Only the conversation commits.** This is a carve-out from [commits.md](commits.md),
"Completion", which has an agent commit its own completed work: that rule holds for an agent
working directly, and is suspended for a spawned worker, which never commits, never describes and
never moves the bookmark. With several workers in one working copy the alternative is a bare
`jj commit` sweeping a neighbour's half-written files into somebody else's change, silently.

**Commit after the user's verdict, not before it.** The sequence is: wave lands, diffs read,
checks run once, user clicks, then the commits are written. What the user rejects never becomes a
commit to revert.

**The trap is silent and has caught this project before.** A path list omits what it does not
name, without saying so: a rename is two paths, a bracketed path needs quoting, a file the wave
touched incidentally is simply left behind. `jj st` is read after every partial commit, and what
remains uncommitted is compared against what was meant to remain.

## What the user is shown

**Before a wave runs: one line per worker** -- what it does, and which files it owns. Not the
brief itself, which is long enough to bury the thing worth checking. The cheapest place in the
whole loop to catch a misparaphrased intent is before three workers have acted on it, and a line
is cheap enough to be read at a glance where a full brief is not.

**After a wave lands: what to click.** Named specifically -- which page, which interaction, what
should be true -- because "have a look" hands the user the job of working out what changed.

**A one-line status tail, on the turns where the state moved.** A reply that dispatched a worker,
or in which one returned, ends with a line naming what is in flight and what is parked --
`in flight: rail-fix (editing) - parked: toc-read (done, unreported)`. Turns where nothing moved
carry nothing; a status line on every message is noise, and noise is what stops it being read.

It earns its place twice. It is the insurance against the parking rule's one real risk, which is
the conversation quietly losing track of its own outstanding work. And it is where the user says
"report that one first" -- the parked order is a default, and the line is what makes it
overridable without their having to ask what is outstanding.

## When not to delegate

**If the brief would be as long as the edit, make the edit.** One line, one constant, a rename
already known, a comment. The overhead of a cold worker is real and it is not always smaller than
the work.

**A decision is never delegated**, to a worker or to the tree. It goes to the user, as one
focused question. See [agent-protocol.md](agent-protocol.md), "Decision authority".
