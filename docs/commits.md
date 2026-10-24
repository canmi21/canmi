# Commit conventions

## Format

[Conventional Commits](https://www.conventionalcommits.org/):

```
<type>: <subject>

[optional body]
```

## Scope

Omit the scope in most cases. Add one only when it carries information the subject line
cannot: a large monorepo package boundary that is not already obvious from the change.
`feat: add token refresh` is preferred over `feat(auth): add token refresh` when the diff
already makes the area clear.

## Types

`Commits.types` in [model/rules/commits.res](../model/rules/commits.res) is the list, and each
means what its name says: `feat` a new capability, `fix` a bug fixed, `refactor` a restructure that
keeps behavior, `build` the build, dependencies or toolchain, `chore` everything else, including a
repository's bootstrap.

## Subject line

- Starts lowercase.
- Imperative mood: `add`, not `added` or `adds`.
- No trailing period.
- `Commits.subjectWidth` characters at most, the `type: ` prefix included.

## Body

Optional. Wrapped at the subject's width.

Plain text. No Markdown: no backticks, no asterisks, no headings, no bullet syntax, no links.
A commit message is read in terminals, logs and blame views that render none of it, where the
marks are noise around the words. Messages written before this rule are left as they are.

A body states what changed. Objectively, and briefly.

What it is not:

- Not a restatement of the subject line in longer form.
- Not a cause and its effect. "Because X, Y was changed" carries the reasoning of one moment
  into every later reading of the log, where it reads as an instruction about what to do next.
- Not self-referential. "This change", "this commit", "here we" -- the commit is the thing being
  read; it does not introduce itself.

Reasoning that is worth keeping belongs in the rules -- `docs/` here, a project's `spec/` -- or beside the code, where the next reader is
looking when they need it. The log answers what changed.

**A body is optional, and the default is not to have one.** A subject line that already says
what changed needs nothing after it. Where a trailer is owed, the body is that trailer and
nothing else; where no trailer is owed either, the message is one line. An empty body is not a
message somebody neglected to finish.

**When there is a body, three lines. `Commits.bodyLines` is the ceiling, not the target.** Longer than that and
it has stopped saying what changed and started explaining why, which is the failure the list
above describes and which no length limit alone prevents -- but a body that will not fit in
three lines is the reliable sign of it.

The rule is here because it was broken at scale. Seven commits written in one afternoon carried
bodies of fifteen to twenty-five lines each, every one of them recounting the alternatives
weighed, the measurements taken and the reasoning behind the choice -- and every one of them
duplicating a section of the rules or a code comment written in the same change, which is where a
reader goes looking for exactly that. The log was left carrying a second copy of the argument,
in the one place this file says it must not be.

### A lock a workflow moves names what moved

A commit a workflow makes when it moves a lock names the packages that changed and their new
versions, never a fixed line such as `flake.lock: Update` that every such commit repeats. Its
type is `build` and its verb `update`. The subject names as many packages as fit its width,
the rest counted as `and N more`; the body lists each as `name old -> new`, packed into its
lines and counted the same way. Decided with the author on 2026-10-21 for `monoflake/machine`,
whose `.github/update/message.nix` holds the order of the cases:

- the packages a machine holds, where any changed: `build: update linux 6.18.58 and tmux 3.8a`;
- else the versions changed below them: `build: update dependencies go 1.27.3`;
- else a count: `build: update nixpkgs and unstable, 12 rebuilt, no version changed`;
- and in each, a patch new in the tree named for a CVE adds `patch CVE-2026-1234 in libtiff`.

A lock that moved is always committed. The workflow evaluates it first and commits only where
it evaluates; the full check runs after, so a lock that breaks formatting lands and shows red.

## Language

English only, no exceptions. See [voice.md](voice.md).

## Co-authorship

An assistant that **participated in the design** gets a trailer. One that merely typed out an
instruction does not.

| The user's request                                            | Trailer |
| ------------------------------------------------------------- | ------- |
| "update the dependency", "rename this file", "change X to Y"  | no      |
| "how should we do X", "what's wrong here", a problem to solve | yes     |

The line to draw is authorship, not effort. When the user decided what to do and the assistant
executed it, the assistant wrote no part of the decision and claiming co-authorship
misattributes it. When the user brought a question and the assistant shaped the answer, leaving
the trailer off hides who did that shaping -- which matters later, when someone wants to know
how much scrutiny a change received.

```
Co-Authored-By: Claude Opus-5 <noreply@anthropic.com>
Co-Authored-By: Codex GPT-5 <codex@openai.com>
```

Each vendor and its one address is `Commits.trailers`. Fill in the actual model short name rather
than copying the example -- the point of the trailer is to record which
model, so a stale version defeats it. A new vendor needs a decision here first, which is one entry
in that list.

**The address identifies a vendor, not a mailbox.** None of the three reaches anybody, and that is
not a defect. A trailer here answers "which model wrote this" so a later reader knows how much
scrutiny the change had; it was never a way to contact the author. An argument that a model
without a reachable address should be credited in prose instead was made and is wrong -- it would
apply equally to the two that came first.

Applies going forward only. Earlier commits are not rewritten to add trailers.

## Tooling

Version control is jj, colocated with git:

```bash
jj describe -m "feat: add token refresh"   # set the message on the working copy
jj commit -m "feat: add token refresh"     # describe, then start a new change
```

In jj a message is not frozen at commit time -- `jj describe` rewrites it at any point, so
fixing a malformed message never requires an amend dance.

## Completion

When an agent finishes a task that changed repository files, it commits the completed change
and moves the `main` bookmark before handing the result back. A separate request to commit is
not required. Partial or blocked work stays uncommitted, and unrelated changes already in the
working copy are never swept into the task's commit merely to make the tree clean.

**A spawned implementer is the exception, and never commits at all.** The integrator that spawned
them commits, by path list, and the wave is accepted before it is pushed. See
[checking.md](agents/checking.md), "Commits separate concerns, not buildable states",
which also records why a commit here is not required to build on its own.

**Beside another session, a session commits its own files by path and leaves the rest.** Another
agent may be working in the same repository at the same time; its changes in the working copy are
its own, and so is a check that fails in its area. A session commits the files it changed, by path
list, once the check passes on everything it touched, and names any failure it left in its
report; it neither fixes the other's work nor waits on it, and does not ask the user first -- the
user has said that someone else is working there, and that is the answer.

### When a change is done, and when it is pushed

**A commit marks a change that is settled, and the user's intent says when that is.** Three
situations, told apart by what the user is doing rather than by how much has changed:

- **Something being built together, where a push is how it takes effect** -- a deploy, a release
  another repository has to install, a page that only exists once it is served. Each step that
  passes its checks is committed and pushed then, because the next step depends on it.
- **A run of requests the user is still shaping**, worked live in a session with no role. While
  they are adjusting how something looks or behaves and have not said it is right, every attempt is
  not a commit: a dozen commits of a dozen tries record nothing anybody will look for. When they
  move on to the next request, the one before is settled -- commit it then, and it may be pushed.
  **A wave is the other mode**: its commit is local and may come before acceptance, and a fix
  acceptance asks for is squashed into it before the push, [checking.md](agents/checking.md),
  "Acceptance comes before the push".
- **A bug with a clear sign of being fixed**: the failure it is fixed against, or the behavior
  it should have. When that holds, the fix is done, and done is the commit.

**An agent pushes, at the right moment, without asking.** Not after every commit: when a piece of
work is settled in one of the senses above, or when a push is what makes it take effect. The
exception is the user's word -- one who says, in a session, not to push, or that pushing is
theirs, has it so for that session. A push is `mise run push <repo>`, named, never the bare verb
that pushes every repository, and is said in a line.

**Which agent pushes follows the roles**, decided by the author on 2026-10-24. Where roles are
named, the integrator pushes on its own: when a wave ends, when a step of a thread is done, and
before it ends a round of work with commits still unpushed. Where none is named, the one session
holding both halves pushes its own work, as above: once the check passes and the work is done. **The
push gate**, a reviewer's read and the wave accepted, [pushing.md](agents/pushing.md), **holds for a
wave worked in roles alone.**

**A push that releases a version of our own code is asked of the user first**, in either mode,
until the deferred item `release-push` is settled; canmi/lib's `held-back` is one such push.

### Leave the working copy above `main`, not on it

The last step is `jj new`. `main` ends on the commit that was written, and the working copy ends
as an empty child above it rather than as `main` itself. Moving the bookmark and then `jj new`,
or `jj new` and then `jj bookmark move main --to @-`, come to the same place.

Ending on `main` works until the next push. jj's default `immutable_heads()` covers `trunk()`,
which is `main@origin`, so the moment a push lands, the commit the working copy is sitting in
becomes immutable. jj will not leave a working copy there -- every save after that would be a
rewrite of published history -- so it makes the empty child itself and says so:

```
Warning: The working-copy commit became immutable; a new commit has been created on top of it.
```

Nothing is broken when that appears: the push succeeded, and the shape afterwards is the shape
this rule asks for. It arrives as a warning in the middle of the user's push instead of as a step
the agent took, which is the whole of the difference and the whole of the reason for the step.

### When `main` moved meanwhile

`main` can be ahead of where the task started -- a fetch, the same repository worked on another
machine, or a wave's merge. The lanes are sibling workspaces, but none of them moves `main`: an
implementer does not commit, and the integrator joins the lanes in one merge, so the merge is the
one place they meet; see [toolchain.md](toolchain.md), "Parallel workspaces, superseded by lanes",
and [lanes.md](agents/lanes.md). When it has advanced,
`jj bookmark move` refuses to move it sideways, and that refusal is the synchronization point:
`jj rebase -d main`, run `mise run verify` again on the rebased result, then move. The order
matters. The change was verified against the tree it was written on; the rebased commit is the
first place the two changes meet, and it is what `main` is about to claim.

A conflict does not stop the rebase -- jj records it in the commit -- and it is resolved by
whoever wrote the change, because that is where the reasoning behind it still lives.

**Nothing already on `main` is rewritten.** jj's own `immutable_heads()` covers `main@origin`
and will refuse, but the rule holds one commit earlier than the refusal does: a commit the user
has seen and accepted is a claim they made, and rebasing it to tidy the history edits their
record of the afternoon.

The rebase is also where rule changes arrive: the rules move with `main` like everything else,
and [agent-protocol.md](agents/agent-protocol.md) says what to do with the delta.

## Enforcement

**What reached `main` is checked again, by the commits part of `check`**: every described commit
after the repository's own `Commits.since` against the same rules the hook applies, from one
function in `model/checks/history.res`. What came before a repository's `since` is left as it was
written; each one was set to that repository's `main` on 2026-10-20, as the author asked, and
every repository the registry lists has one. The hook sees only what an agent types with `-m`; the history sees
everything, an editor's message and a human's included, after the fact.

`hooks/commit.res` runs before any jj subcommand that can write a description and does two
things: it checks the message, then -- once the verify gate below has passed too -- it runs `jj
fix` with the workspace's `jujutsu.toml`, wherever below it the commit is made, so the content
being committed is already formatted. A malformed message is refused with the specific reason,
which the agent reads and corrects on the spot.

The guarded list is derived from which subcommands accept `-m`, not from the two that write
most of the messages. It was `commit` and `describe` alone, and `jj split -m` carried a
malformed co-author trailer straight past it -- caught only because a later `describe` in the
same session was checked and rejected the identical text. A gap of that kind is silent by
construction: the hook cannot report a command it never looked at. So when jj grows another
way to set a message, the list grows with it -- `Commits.describing`.

The hook lives at the agent-harness layer rather than in jj, because jj offers no hook point
at all: it has no commit hook, and it explicitly refuses aliases that shadow built-in
commands (verified -- `jj` prints `Cannot define an alias that overrides the built-in
command 'commit'`). The moment a message is written is inside the agent's tool call, so that
is where the check has to sit.

The behavior has one home under `hooks/`. `.claude/settings.json` and `.codex/hooks.json` are
thin adapters with the same event table, each calling the one `hooks/run.res` entrypoint. That
entrypoint owns routing, command selection, and combining output from policies that can both
apply to one event. A vendor adapter never owns policy: if the harness payloads diverge later,
the shared entrypoint normalizes their common meaning rather than growing two implementations
that only appear equivalent.

**A commit waits on a passing verify.** Agreed with the author on 2026-10-20, following
monoflake's "a commit is made only after verify passes": `hooks/verified.res` refuses a
`Commits.committing` command until the repository's `mise run check <path>` -- or `mise run check`
for the workspace -- passed at the working copy being committed. A pass writes the working copy's
commit to `.jj/verified`, and the hook compares contents with `jj diff`, so describing the change
afterwards keeps it verified and editing a file does not. A run of named parts, `check workspace
words`, verifies nothing and writes nothing. The hook reads the working copy before the command
runs, so an edit chained into it -- `printf x >> f && jj commit` -- is not seen, which was found by
trying it: a commit is a command of its own. A `cd` before it is followed, so `cd repos/seam && jj
commit` is held to seam's verify and not the workspace's.

**The escape is named on the command: `SKIP=verify jj commit ...`.** It is pre-commit's spelling --
`SKIP=<hook id>`, ids comma-separated -- since it reads at a glance and survives being copied;
`Commits.skippable` lists what it may name. A repository that cannot pass yet is no reason to stop
work in it, so the gate is passed by saying so rather than by working around it.

`hooks/decision.res` runs _after_ the commit lands and asks the question the diff
cannot: was a decision made here that nobody wrote down? It fires when a `feat`, `refactor`,
`build`, or `perf` commit touched no rules, and injects a reminder to record the reasoning
while it is still in context.

It deliberately does not block. Many commits of those types settle nothing, and a gate that
fires on false positives gets routed around instead of read. Judging whether a decision was
actually made is the agent's job; the hook only guarantees the question gets asked at the one
moment when the answer is still cheap to write -- before the conversation that produced it is
gone. Bug fixes are excluded on purpose: a fix records its cause at the regression test, not
in the rules.

`hooks/bookmark.res` runs at the end of a turn and refuses to hand the result back while `main`
does not cover what was committed. It is the only hook here bound to something other than a tool
call, and it has to be: the other two watch the Bash tool, and the moment the completion rule
above talks about is the moment the agent _stops_ calling tools. A turn that ends on its last
`jj describe` runs nothing afterwards for a tool hook to inspect, so the bookmark half of the
rule held only as long as it was remembered -- and it was not. Seventeen commits went by in one
session with the bookmark never moving.

**It refuses rather than moving the bookmark itself**, and that is the whole point of it. jj
ships the move as `experimental-advance-branches`, which [toolchain.md](toolchain.md) leaves off
so that a bookmark's position stays something somebody claimed. A hook that advanced `main`
would be that setting again under another name, and would take the claim away while looking
like enforcement.

It counts only commits that are described and non-empty. Undescribed working-copy changes are
the shape partial work is supposed to have -- the rule above says it stays uncommitted -- so
firing on those would turn a rule that protects unfinished work into one that demands it be
published.

`hooks/delta.res` runs after a `jj rebase` and hands back the diff of the rules -- `docs/`,
`model/`, a project's `spec/` -- and `AGENTS.md` between the working copy before the rebase and after it. It reads the previous
state out of jj's operation log rather than remembering anything, and prints nothing when no
rule moved. It exists because a rule written elsewhere -- another machine, an earlier session --
reaches this checkout only through `main`, and the moment it does is otherwise invisible: the
files change under an agent whose context still holds the old text. It does not block; whether a changed rule touches the task
is the agent's call, and it is asked at the one moment the answer is cheap.

What all of this does not cover, and why the rules above still have to be read rather than
merely enforced:

- Only Claude Code and Codex. Opencode and any other harness need their own adapter.
- Only the `-m` form. `jj commit` with no message opens an editor, which the hook cannot see.
- Not a human typing in a terminal.
- The bookmark check blocks once. A second stop is let through, because nothing can tell a
  refusal to move it from an inability to, and a gate with no exit is worse than a missed one.

Enforcement is a fast feedback loop, not a fence. The rules hold whether or not something is
watching.
