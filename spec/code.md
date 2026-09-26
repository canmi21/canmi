# Code conventions

## Type checking is not optional

`tsconfig.json` runs `strict` plus `noUncheckedIndexedAccess`. Both are deliberate, and the
second one is the expensive one, so it needs its reason on the record.

`noUncheckedIndexedAccess` makes every array index and every destructured element
`T | undefined`. That is annoying exactly where code is doing something unproven, which is the
point. When it was first switched on here it immediately found three places where a length
check and a destructure sat next to each other with nothing connecting them, plus a narrowing
bug where `Array.isArray` left a `readonly` array unnarrowed in the false branch -- all in code
that passed its whole test suite.

The rule it implies: **guard against the values the code uses, not against a count.**
`if (parts.length >= 5)` proves nothing to a reader or a compiler about `parts[3]`. Destructure
first, then guard on the names. Never reach for `!` or a cast to silence this class of error --
the error is describing a real gap, and silencing it keeps the gap while removing the warning.

## Dependency budgets differ by destination

Where the code runs decides how much a dependency is allowed to cost.

|                                        | Optimise for            | Budget                                               |
| -------------------------------------- | ----------------------- | ---------------------------------------------------- |
| Runs locally (CLI, CMS, build tooling) | correctness, then speed | dependency count and binary size are not constraints |
| Ships to the edge or a browser         | payload                 | every dependency is argued for                       |

A local binary is never downloaded by anyone. Its compile time is paid once per change by the
one machine that builds it, and its size is paid never. Picking a weaker library there to save
megabytes trades a real correctness risk for a saving nobody experiences.

Deployed code is the opposite, and the same problem can deserve opposite answers in the two
places. The favicon resolver is the worked example: the Worker version parsed HTML with
regexes because a Worker has a bundle budget, and the local port uses a real HTML5 tokenizer
because it does not. Measured on adversarial input, the regex approach silently picked up a
commented-out `<link>`, a `<link>` inside a `<script>` string, and left `&amp;` undecoded --
three wrong icons, none of which announce themselves.

So when a dependency looks heavy, the question is not "is this too big" but **"who pays for
this size, and what does refusing it cost instead?"**

### Local code does not hand-roll a standard

The budget above is a permission. This is the obligation that goes with it: **where a format has
a de-facto standard and a known library implements it, local code uses the library**, even to
reach one small corner of what it does. Not a regex over the shape that usually appears, not a
`split_once` that covers the cases seen so far.

The cost of refusing is not a bug so much as a _disagreement_, and disagreements in a parser are
the quiet kind. `cms og` read article frontmatter with a hand-rolled split while the segment
layout read the same frontmatter with `serde_yaml_ng`, and the card looks its translation up by
the title string the first one produced. A folded scalar -- `title: >-` across two lines -- gives
the hand-rolled reader `>-`, so the card is titled with the fold marker and, worse, finds no
translation under it and falls back to the source language in every view, reporting nothing.
Quoted scalars with an escaped quote inside fail the same way. Nothing is wrong; something is
merely different, everywhere, silently.

**Two readings of one format is the shape to watch for.** Wherever a second reader appears for
something already parsed elsewhere, it is the same library or it is a defect waiting for the
first input that separates them.

This license is bounded by destination exactly as the table above is. Nothing here permits a
library into a Worker or a browser bundle to save writing twenty lines; there, the payload is the
constraint and the trade runs the other way.

### Modern browser APIs get feature-gated fallbacks

Application source keeps the standard API that expresses its intent. A browser missing a runtime
built-in does not make every call site retreat to an older spelling: the client startup boundary
detects the gap and dynamically loads the fallback before hydration. Browsers that already
implement the feature do not request that chunk.

Feature detection decides, never the user agent. A build target can lower syntax but does not
provide runtime built-ins, while a hand-written approximation can quietly disagree with the
standard on sparse arrays or generic receivers. The standards implementation belongs in one
compatibility module; business code remains modern and unaware of it.

**What the check loads is the whole polyfill set, not the one module named by the crash.** Naming
modules makes the fallback a list, and a list has no knowable correct length -- the entry nobody
thought of is a crash in a reader's browser. One check gating everything has no such entry. It is
affordable only because the import is dynamic and the payload is therefore reached by nobody who
does not need it, which is a property of the bundler rather than of the polyfill; a static import
of the same set is a tax on every reader. lattice measures both sides of that in
[its own spec](../repos/lattice/spec/compat.md).

## Errors are types on the way up and one message at the edge

**A fallible operation names what can go wrong as its own type**, derived with `thiserror`. Not a
`String`, and not a panic. A caller that receives a type can match on the case; a caller that
receives a string can only print it, and a caller that receives a panic cannot do either.

The distinction that decides between an error and a panic is **whose mistake it is**. A person
hand-writing frontmatter will mistype it, so unreadable frontmatter is an ordinary event and
returns `Malformed` -- lattice's `apps/cms/src/i18n/segment.rs`. A panic is for the state that cannot
arise unless this code is already wrong. `cms i18n` used to abort on a stray colon in an article,
with a message naming the fault and not the file, which left a binary search through the corpus
as the way to find out which article it was.

**Context is added by whoever has it.** The parser is handed text and does not know the path;
the caller read the file and does. So the type stays about the failure and the caller attaches
the article to it, rather than every layer carrying a path it never uses.

### At the boundary the chain becomes one message

The two shells converge differently, and both flatten only at the very end.

**The CLI** turns whatever reached it into a single message on stderr and a failing exit code.
Nothing above that point needs the distinction, because there is nobody left to act on it --
`anyhow` is the shape of that boundary, holding the chain until the moment it is printed.

**The desktop shell** keeps the chain, because it has more than one thing to do with it: an
Activity entry records what failed and where, while what a person is shown is the same flattened
sentence the CLI would print. Discarding the cause at the adapter would leave the record as
useless as the message.

So the rule is directional. Types going up, one message coming out, and the flattening happens
once, at the shell, never in the middle.

**Adoption is partial and deliberate.** The CLI boundary is in place: every command returns
`anyhow::Result<ExitCode>`, and `run` is the one place that prints. What still returns a bare
`String` is named rather than left to be found -- `licenses::npm::collect`, `i18n::parallelism`,
`i18n::selected_locales`, `runner::model_override` and the opengraph renderer. Each is bridged
with `anyhow::Error::msg` at the call, which makes the string the message and loses it as a
cause; converting them to `thiserror` is worth doing as its own work.

### `Err` is "could not run"; a failing exit code is not

A command returns `Ok(ExitCode::FAILURE)` when it ran and has something to report -- items that
failed inside a batch that finished -- and `Err` only when it could not run at all. Collapsing
the two would make `cms alt` over a library where one description failed indistinguishable from
`cms alt` in a directory that is not a repository, and the second is worth a different reaction
from whoever typed it.

## Unused is not the same as dead

A thing with no consumer today is not automatically waste. **The question is whether it completes
a set that would be incoherent without it**, and if so it stays -- reported once here rather than
rediscovered as a defect by every review that greps for callers.

Two members of the tree are there on exactly this basis:

- `--color-green-ink` and `--color-red-ink` in `libs/tokens`. Blue's is in use; the three are one
  set of hues under one naming scheme, and deleting two of them leaves the next component wanting
  a green mark either inventing an `oklch` or borrowing a name that means something else.
- The italic and bold cuts of Ioskeley Mono. Only the regular weight is reachable under the
  current highlighting themes -- see lattice's `architecture/fonts.md` for the measurement -- and
  a monospace family cut down to one weight is a family that has to be re-cut the first time
  anything wants emphasis.

**What makes this safe rather than an excuse is the cost.** Both are paid in storage nobody reads
and bytes nobody downloads: a `@font-face` is a declaration, not a request, so an unreachable cut
costs a reader nothing at all. The same argument does not license an unused dependency, an unused
export or an unreachable branch, each of which is paid on every build, every audit and every read.

So the test has two halves, and both must hold: **would the set be incoherent without it, and is
its cost paid by nobody?** Where the answer to either is no, it is dead and goes.

## Tests

Colocated with source as `src/*.test.ts`, run by vitest from the repo root.

Test the decisions, not the syntax. What earns a test here: the branch that used to be wrong,
the input shape that comes from outside, the invariant that a future refactor could quietly
break. A test that restates the implementation line by line only makes the implementation
harder to change.

When a bug is found, the fix and a test that would have caught it land together, with the
cause noted at the assertion. A regression test whose reason is not written down gets deleted
by whoever next finds it confusing.

## Nothing is committed unverified

`mise run verify` -- types, lint, tests -- passes before a commit is made. The commit hook
formats automatically, so formatting is never the thing that fails; what is left are the three
checks that a human or an agent can actually get wrong.

This exists because both of the other guarantees are weaker than they look. Tests only cover
what someone thought to test, and the type checker only sees what it is pointed at. Running
them is the cheap part; the expensive part is discovering months later which commit broke
something that nothing was watching.

## A rule is maintainable only when breaking it fails loudly

Correctness first, and over any distance that stops being a matter of care. Four things have to
hold of a rule, and one missing is enough for it to decay without anybody noticing.

**Violating it makes something fail.** A rule nothing enforces is a sentence. The rule that a
configuration file's comment stays short lived in a conversation only, was then cited to a worker
as though it were on the page, and two comments were cut on that authority -- with nothing in the
tree able to say whether the citation was real.

**The failure has been demonstrated.** A gate never seen to fail is a name rather than a gate.
`mise run audit` counts every warning -- [lint-format.md](lint-format.md), "Strict mode" -- and was
driven red on all three tools before it was believed.

**The check can see everywhere the rule applies, including its own home.** A checker told which
directories to look in is blind to the next one. The reference check read only files with a known
suffix, so nine citations of a `spec/architecture.md` that does not exist survived in `.gitignore`,
`.gitattributes` and the task scripts. The comment check was handed `apps/` and `libs/`, so
`.mise/tasks/`, which held the longest blocks in the repository, was never measured.

**It does not ask a person to hold a global fact.** A threshold resting on a count nobody
recomputes is a memory. `check-css-budget` skipped any node file it could not parse, so renaming
one export dropped a third of the article route's CSS out of the measurement and the gate stayed
green. `shape` compared the fingerprint before the version and returned 0 on a match, so a constant
raised by hand was reported against the record written for the old one.

Of every failure that session found, all but one was silent; the exception failed the build and
named the article. **Silence is the default failure mode**, and these four are what turns a silent
failure into a loud one.

## A file is read whole, so it stays short

**A source file of ours aims under five hundred lines, and one over a thousand fails the gate.**
The soft limit is the warning tier -- advice until `mise run audit` -- and the hard one fails
`verify`. `.mise/tasks/lines` measures it, over a repository or over every one, and this
repository's `verify` runs it over every one: a project over the limit reddens the workspace's gate
until it is under, which was decided over the alternative of each project adopting the gate once
clean -- a gate nobody has to adopt is the one that gets adopted. A project may run the same check
from its own `verify` as well, as seam does with `lines` in its `mise.toml`, so its own gate says
so too. Measured the day the rule landed: seam under, and seventeen files over in lattice, rdm and
governor, which is where the workspace's `verify` is red until they are split.

**Why a file and not a function.** A reader, and an agent, reads a file whole: to change one
function safely they read what surrounds it, and a nine-thousand-line file is read by nobody. seam's
`walk.ts` reached 9071 lines and three other files passed a thousand before anything said so, each
one a place where a search stops at the first result that looks right because the second is four
thousand lines down. A limit on a file is the one a tool can hold objectively; where a function is
the size of a file, it is the same problem one level in, and the file limit is where it shows.

**What is measured is code of ours.** Vendored source is somebody else's and is left out, as is
whatever a tool wrote, and prose: a `spec/` file is long because the reasoning is, and a test
file's cases are code and counted -- a corpus of cases splits by topic as readily as a module
does. The extensions and the directories skipped are listed in the task, and each argues its
exemption.

**Splitting is by the seams already there, never by count.** A long file has clusters that only
call each other, and those are the modules; a split that lands on a line number rather than a
cluster makes two files that have to be read together, which is one file with a seam in it. The
shared types come out first, so the clusters can import them without importing each other, and
a constant a cluster reads at module load sits with the cluster that owns it, since a circular
import between modules that only export functions is harmless and one that reads a constant
during load is a temporal-dead-zone error.

## Comments

A comment explains a **why** that the code cannot state: the alternative that was rejected, the
constraint from outside, the trap that looks like a bug but is not. Never restate what the
line does.

The specific comment worth writing more often than feels natural: the one next to a value that
looks arbitrary. A config number, a strictness flag, a rule turned off. Those are the ones a
future reader will "clean up" unless the reason is sitting right there. Larger decisions go in
`spec/` instead -- see [agent-protocol.md](agent-protocol.md) for which is which.

### Few, short, and only where the reason is not recoverable

Comments are rationed. Write one where a reader would otherwise get it wrong, and nowhere else.
Ordinary code carrying an ordinary intent gets none -- explaining it adds a second thing to keep
true without making the first any clearer.

Three prose paragraphs above a token, a docstring on every field of a table, a note restating
the branch below it: each is a cost paid on every future read, and paid again by whoever has to
keep it accurate. A file where everything is annotated is one where nothing stands out, which is
the same as having annotated nothing.

Write for someone scanning, not reading. Lead with the point; if the first line does not carry
it, cut down to the line that does. The full argument belongs in `spec/`, with the comment
naming the file rather than repeating it.

### How long, and where the rest of it goes

A comment block is at most **six body lines**. The block that opens a file and introduces the
whole of it gets **ten**. A body line is one carrying text: `/**`, `*/` and a blank `*` separator
are punctuation, and a JSDoc block spends about two lines on them.

Aim at one to three, and let five be the honest ceiling. Six is where a check fires, not where
the writing should land, and the gap between the two is the point of it: prose aimed at three
lands at three to five, and a limit with no slack reports that as a fault. Measured across lattice,
blocks over five body lines are 18.7% of the blocks and carry 49.8% of all comment prose -- half
the weight in a fifth of the places, which is how a tree ends up annotated everywhere and legible
nowhere. Six is also where the return falls off: five to six exempts another 3.5% of blocks, and
every line after that buys under three.

**A configuration file aims shorter still, at one or two lines.** The six holds there as it holds
everywhere, but a config file has no surrounding code to carry the context, and that absence is
exactly what tempts a comment there into explaining the whole system. The thing a reader at that
line cannot get wrong is almost always one sentence.

The pair worth keeping in mind is the one where both are right. lattice's
`apps/site/site.config.yaml` cut its IndexNow block from seven body lines to three, because every
sentence it lost was already in lattice's `indexing.md` word for word. `apps/cdn/wrangler.jsonc`
stopped at five, because one of its lines carries a measured fact nothing else records -- dev
serving `max-age=0` where production serves a year. **Length follows load, not file type.**

Every comment line stays inside **100 columns** with tabs at two, the width oxfmt's `printWidth`
and rustfmt's `max_width` already give code. Neither formatter rewraps a comment, so this one is
held by hand.

All three are counted rather than eyeballed. `mise run comments` measures every block in every
language that carries one and is part of lattice's `verify`, which is where the percentages above
come from. A file a tool generated is exempt: its comments are nobody's to fix, and a check
naming a line that may not be edited teaches its reader to skip the rest of the output. The
limits are this repository's; the check is lattice's, because lattice is the project that needed one
first and the only place it runs today.

**A link is not length.** Only the plain text counts against either limit: a URL may sit in a block
without spending a line of its budget, and a long one does not make the block too wide. Prose is
read and therefore rationed; an address is followed once and never reread, and a rule that charged
for it would push a comment into paraphrasing the page rather than pointing at it.

**What decides where a fact lives is who needs it, not how long it is.** If a second file would
have to know it, it is a rule and belongs in `spec/`. If only this file does, it stays here
however long it runs -- moving it sends the reader out for something nothing else uses. Length is
the symptom that makes the question worth asking, never the answer to it.

**A pointer names the question, not the answer.** "See spec/search.md for why it is one and not
nine" survives that file being rewritten; "the index is one because ..." does not, and nothing
links the two, so nobody finds out. The exception is a value this file's own code uses: a
constant states its own number here and points at `spec/` for why that number.

### `spec/` holds what is settled; an issue holds what is not

The rule above sends the full argument to `spec/` and leaves the comment naming the file. This is
that rule in the other state: **where a comment would otherwise have to argue a decision nobody has
made, it links to an issue instead.** An issue is where an open question lives, and the link is the
whole comment -- the argument is had there, by the people having it, and not in a file that merely
happens to be where somebody noticed.

The link is a waypoint, not an end state. Once the decision is made it stops being an issue and
becomes a rule in `spec/` plus the change that implements it. What it never becomes is a comment
carrying the argument, which is how a file ends up holding a debate that was settled elsewhere.

Spelling follows what is here already: a bare URL after "See" in a comment, as
`apps/site/src/lib/documents/llms.ts` has it, and a markdown link labeled `owner/repo#number` in a
document, as lattice's `architecture/css/extraction.md` cites `facebook/stylex#1825`.

### A comment that moves takes its coordinates with it

"Above", "below", "here", "this file", "the rule before it": a positional word is true of where the
comment was, and a comment that moves keeps it. On arrival it stays grammatical and stops being
true, which is the worst of the two pairs available. **Re-read every positional word against the new
position, and name the thing rather than where it used to sit.**

Nothing catches these. The reference check validates citations into `spec/` and the section names
quoted beside them, and "the rule above" is neither -- it is a pointer, not a citation. A rule
lifted out of lattice's `apps/site/src/styles/utilities.css` into a component's `<style>` block
carried a comment ending "The rule above would then only answer to hover over the text", and the
rule it meant stayed behind. It was caught by eye, in a diff, because somebody happened to read
that paragraph.

The audit is a grep over five words; the failure is not cheap at all. A reader who follows a
dangling "above" into an empty `<style>` block concludes the comment is stale and stops trusting
the rest of it.

**A phrase describing the rendered page is not a coordinate.** In that same comment "the box's
bottom", "2.5px below the anchor's", "in the same sentence" and "measured on the error page" all
travelled intact, and one of them reads better after the move than before. The rule is about
positions in a file, never about the word "below".

### `FIXME` is a problem; `TODO` is a plan

Two markers, and the line between them is whether anything is **wrong**.

|         | Means                                                    | Deleted when                            |
| ------- | -------------------------------------------------------- | --------------------------------------- |
| `FIXME` | Something is wrong here and is waiting on something else | the code is fixed, or `spec/` adopts it |
| `TODO`  | Nothing is wrong; something is planned and not built yet | it is built, or the plan is dropped     |

**`FIXME` is a debt.** The code knowingly departs from a rule in `spec/`, or behaves in a way
somebody would call a bug if they met it cold. It says which rule, why it stands, and what has to
happen first. `cms tn` and `cms embed` carry one because their operations live inside the CLI
adapter, which lattice's `architecture/cms.md` does not allow.

**`TODO` is not a debt**, which is why it needs its own word rather than a softer `FIXME`. It
marks something deliberately unfinished with no bad consequence while it waits -- a value
captured for a component nobody has written, a hook left where an extension will go. Nothing
misbehaves; there is simply less than there will be. `VITE_COMMIT_HASH` is the standing example:
the build captures it because only the build can, and the footer meant to show it is planned.

Both say what they are waiting for. A marker that does not is indistinguishable from one nobody
has revisited, which makes every marker in the tree worth a little less.

**Why mark at all, rather than fix or forget.** An unmarked departure gets rediscovered by every
review as though it were new, and each rediscovery costs the same conversation about whether it
was a decision or an oversight. The other way out -- writing an exemption into `spec/` -- is
worse for a `FIXME`: an exemption reads as settled, so the thing stops being a departure and the
code quietly becomes the rule. The debt stays where the code is, visible to a plain search.

Keeping them apart is what keeps either useful. A tree where both words mean "look at this
sometime" has one marker wearing two spellings, and a search for real problems returns a list
nobody finishes reading.
