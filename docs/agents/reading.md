# Reading

What a reader does, and how a read and a piece of research are briefed. A reader is the built-in
Explore, [reader.md](reader.md); how the work is split is [delegation.md](delegation.md).

## Reading is delegated; the judgment on what comes back is not

**In a delegating session, reading the code is delegated too, not only searching it.** Both halves
of the cost are worth avoiding: a file read into the top level stays there for the rest of the
session, and the minutes spent reading it are minutes the user is waiting rather than talking. A
reader reads in the background and the thread stays free, which is the whole arrangement in one
sentence.

**A read brief names four things**, and the fourth is what makes it worth sending at all.

- **The scope.** Files, a directory, or a pattern -- never "the codebase". A reader given the
  repository will give back an essay.
- **The tool, and the pattern where it is already known.** `rg` for text, `ast-grep` for
  structure -- a call shape, a hook, every implementation of one interface. Naming the pattern
  saves the reader rediscovering what the top level already worked out.
- **The question, in one sentence.**
- **The return shape**: the exact lines, quoted, with `file:line`; the enclosing signature or
  declaration so the frame around them is visible; a line cap; and one paragraph answering the
  question, kept apart from the quotation.

**The quotation is evidence and the paragraph is not.** A report is a read somebody else took --
a quoted line is the read itself, taken through a reader instead of by hand. The two arrive in
one message and must not be weighed the same.

**A line cap is not tidiness.** A reader that returns the file has returned the problem: the
context was spent, just later and by somebody else.

**Choosing which ten lines to quote is itself a judgment, and it can be wrong.** Asking for the
enclosing structure makes a badly framed snippet visible sometimes, and not always. The reliable
signal is the other one: **an answer that surprises is read again by hand.** A finding that does
not fit what the rest of the tree implies is either a discovery or a mis-framed quotation, and
from the summary those two look identical.

**Dispatch as soon as an area is named, not when the plan is settled.** A user describing an idea
that plainly touches the rail, the CMS window, one reader -- the read goes out then, and by the
time the idea is settled the evidence is already back. This inverts the usual order, where
research follows the decision, and it is only available because reads run in the background. The
area has to be concrete enough to scope a brief; a vague mention buys a speculative read nobody
uses.

**The top level reads for itself** when the answer surprised it, when the file is a handful of
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
A brief that asks how the thing works, with the verdict as the last line, gets something the top
level can reason from when the next question turns out to be adjacent rather than the same. The
test to write into the brief: **enough that the reader could predict the answer to a question
that was not asked.**

**Require the line between fact and inference to be drawn every time**, and make "not documented"
an acceptable answer. A reader that cannot distinguish the two returns something worse than
nothing, because it cannot be checked without redoing the work. A load-bearing claim carries its
URL inline, or it carries the word "inferred".

**Concise but not thin** is the standard, and it is worth saying in exactly those words. Without
it a research brief comes back either as a paragraph that repeats the question, or as a survey
of everything adjacent. Bound it the way a read is bounded -- a reading time, a line cap on
quoted code -- and forbid the filler by name: no restating the question, no explaining what the
subject is, no recommendation that was not asked for.

**A research brief usually has a local half, and it belongs in the same reader.** What the
platform does in general is only half an answer; what this tree does with it is the other. One
reader holding both gives an answer already applied, and the alternative is the top level joining
two reports that were written without reference to each other -- which is the failure recorded in
[checking.md](checking.md), "The integrator reads the diff, not the file".
