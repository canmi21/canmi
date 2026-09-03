# Agent protocol

How an agent operates in this repo: how to start, who decides what, and how to keep this
ruleset trustworthy over time.

## What spec is for

`spec/` records **decisions and the reasoning behind them**. It is not documentation of the
code, and it does not restate implementation.

- **Write down**: what was decided, why, what the alternative was, and what it costs. Anything
  a future reader could not recover by reading the source.
- **Leave out**: how a function is written, what a config file currently contains, anything
  the code already states plainly. Point at the file instead of copying it.

The test for a spec sentence: if someone changed the code, would this sentence need editing?
If yes, it is describing implementation and belongs in a comment next to that code. If it
would still be true, it is a decision and belongs here.

## One fact, one home, linked from everywhere else

Nothing is written down twice. Every fact has exactly one home, and everything that needs it
links there.

| Layer         | Holds                     | Points at                        |
| ------------- | ------------------------- | -------------------------------- |
| `CLAUDE.md`   | one line per topic        | the full `spec/*.md`             |
| `spec/*.md`   | the decision and why      | the code file that implements it |
| code comments | why this line is this way | back to `spec/*.md` for the rule |

Spec and code are not two descriptions of one thing -- they are **one description with two
halves**. Spec holds the decision, code holds the implementation, and each names the other so a
reader can cross the gap in one hop. A spec file that restates what the code does will drift
away from it; a code comment that re-argues a decision makes the decision editable in two
places, and then it is editable in neither.

When you catch yourself writing something that already exists elsewhere, delete it and link
instead. The duplicate is not redundancy, it is a second thing to keep in sync, and it will
lose sync.

`mise run refs` checks that the links resolve -- markdown links in docs, and `spec/*.md`
citations in code. It is part of `mise run verify`, because a reference that points nowhere
fails silently: nothing breaks, the reader just follows a dead path. It deliberately ignores
path-shaped strings in prose, since the rules use invented names as examples on purpose.

Spec exists to be the place an argument gets settled. When code, an agent, or a later opinion
disagrees about how something should work, this is the reference that decides it -- which only
works if it carries the _why_. A rule with no recorded reason loses every argument against a
plausible-sounding alternative, because nobody can tell whether it was considered or just
inherited.

## Cold start

Starting a conversation with no context about this project:

1. Read `CLAUDE.md` at the workspace root. It is the only entry point.
2. Read the `spec/` files that cover the task: this repository's for the rules that hold
   everywhere, and `repos/<project>/spec/` for the project you are about to touch.
3. Know which repository you are in, and start from its current `main`.
4. Only then act.

Never act first and consult the rules afterwards. If a rule would have changed what you did,
reading it late is worth nothing.

Step 3 exists because a change lands in one repository and the rules governing it may live in
another. `jj workspace root` says which repository the working directory belongs to -- inside
`repos/press` it answers about press, not about this one, which is the same fact the hook
resolver depends on. A task begins with `jj new main` in whichever repository is being changed,
so the rules read in step 2 are the ones `main` currently holds rather than the ones a previous
task left the working copy on. See [architecture/repos.md](architecture/repos.md).

## Working beside other agents

**Agents do not talk to each other.** No harness messaging between sessions -- Claude Code's
cross-session messaging, or any equivalent -- and no side channel invented for the purpose.

Two reasons, each sufficient. A session list on this machine has shown sessions that were on
other machines, so a message has no reliable boundary and can land somewhere with nothing to do
with the work. And a decision made in a conversation between two agents is recorded nowhere: not
in a `spec/`, not in a commit, not where the user can see it -- which is the failure this whole
file exists to prevent.

There is no longer an arrangement for two agents inside one repository; projects are separate
repositories, so two pieces of work are two directories. What crosses between them is a commit
and nothing else. See [architecture/repos.md](architecture/repos.md).

## Decision authority

Decisions belong to the user. An agent implements them.

Ask the user when:

- The task needs a choice `spec/` does not already answer.
- The choice is structural: architecture, dependency, data model, public API, naming scope.
- The choice is expensive or awkward to reverse.

Do not ask when:

- `spec/` already answers it. Follow the spec.
- The user's described approach implies the answer. An implication carried in the user's own
  wording counts as their decision -- honour it rather than re-asking.
- The choice is local, reversible, and leaves no trace in the result.

Calibration matters in both directions. Escalating every trivial choice wastes the user's
attention; silently settling a structural one takes a decision that was never yours. When
genuinely unsure, ask one focused question instead of a list.

### Working a backlog: one item, proposed and accepted, then done

A list of known problems -- an audit, a review, a set of findings -- is worked one item at a
time, and each one is **proposed and explicitly accepted before anything is written**. The
proposal states the problem, the evidence for it, the options with what each costs, and a
recommendation. Then it stops. Silence is not acceptance, and neither is the user having
accepted the item before it.

The ordinary calibration above is not enough here, for two reasons a backlog has and ordinary
work does not.

**Every item on the list was already judged once, by whoever wrote the list, and that judgement
is the thing least worth trusting.** The findings that survive review are rarely the ones that
looked most obvious in it -- three separate items in the audit this rule came out of were
overturned by the user: a colour token that read as dead was a deliberate reservation, an emoji
that read as unapproved was wanted, and a fix recommended as too small to be worth a dependency
got the dependency instead. A list presents each entry with equal confidence, and the confidence
is the author's, not the reader's.

**A list also carries momentum.** Having done four items unaided makes the fifth feel
pre-approved, and nothing in the list marks which entry is the structural one. The rule removes
the judgement call rather than asking for it to be made well four times running.

Read-only investigation is exempt and needs no approval: searching, reading, type-checking,
running the test suite, taking a screenshot. That is the material a proposal is made of, and
none of it changes the tree.

## Read the source before measuring the behaviour

**What this stack depends on is open source, so its behaviour is not a black box unless you choose
to treat it as one.** Svelte, SvelteKit, Vite, the Rust crates -- all of them are on disk, in
`node_modules` or in a vendored checkout, and every question about what one of them does has an
answer written in it. Reaching for a test first to find out is choosing to rediscover, by
experiment, something the author already wrote down.

The order is: **read the code, form the rule, then measure to confirm the rule holds.** A test
written after reading is a check on your understanding and on the version installed today. A test
written instead of reading is a search, and a search stops at the first result that looks right --
which is how a rule comes to be inferred from three measurements when the upstream option that
governs it was named in the source all along.

**This is not an argument against measuring.** An upstream that changes is exactly why the
measurement stays: it is what fails the day the reading goes stale, and several checks exist for
no other reason. The rule is only about which comes first, and reversing the two costs the time
twice -- once to guess, once to find out the guess was shaped wrong.

Where a project's whole design rests on an upstream's behaviour, that project's `spec/` says so
and names the files. See [repos/seam/spec/references.md](../repos/seam/spec/references.md) for the
shape of that.

## Checking your own work

Make the change and hand it back. Do not stand up a browser to confirm that a colour is the
colour you just typed, that a radius applied, or that a class landed -- the type checker and
the build already catch the failures that class of edit can have, and the user is a faster
judge of the rest than any screenshot. They will say when something is wrong.

Chrome DevTools MCP for a page, and the `tauri` MCP server for the CMS window
([toolchain.md](toolchain.md)), are for debugging that is genuinely hard without them: a value
that renders differently from what the source says and nobody can say why, a layout that only
breaks at one size, something that misbehaves after hydration and not before. The signal is that
a question about the running application cannot be answered by reading the code -- not that a
change was made and might in principle be wrong. Reaching a desktop window is newly possible and
is not therefore newly worth doing; the restraint is the same one, and it was written for the
browser only because the browser was the only thing reachable.

The cost is not the tool call. It is the round trip: booting a browser, waiting on a dev
server, screenshotting, reading pixels back, all to restate what the diff already says. That
time is the user's, and confirming the obvious spends it to reach a conclusion the next message
would have delivered for free.

## Selfcheck

Triggered whenever the user says "remember this", "update yourself", or anything of that
shape.

Do not write to agent memory or any agent-private store. That content does not survive into
the next session's view of this project and is invisible to every other agent. Instead:

1. Decide where the rule belongs: an existing `spec/` file, or a new one named for its aspect.
2. Write it there.
3. Re-read `CLAUDE.md` and check it still holds. Are the rules it promotes still the most
   important ones? Is the index complete? Has anything drifted, duplicated, or gone stale?
4. Repair what drifted, then tell the user what moved where.

The test to apply before calling it done: a fresh agent with zero memory of this project,
starting from `CLAUDE.md` alone, must be able to recover the project's constraints and work
correctly. If it could not, the selfcheck is not finished.

## Unprompted selfcheck

The user will not keep asking for this. Adding a tool, adding a config file, or settling a
convention triggers the same review on its own:

- Does a future agent need a rule to use this correctly, or is the config file
  self-explanatory?
- Did resolving this require a judgement that is invisible in the resulting file? Judgements
  leave no trace unless written down -- a config value looks arbitrary six months later.
- Does an existing `spec/` file now contradict what was just added?

Write the rule in the same change as the tool. A tool that lands without its rule is a tool
the next agent will misuse.
