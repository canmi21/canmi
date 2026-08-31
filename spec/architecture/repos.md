# One repository per project, nested under one workspace

## The shape

This repository holds configuration and nothing else. Every project is its own repository,
cloned into `repos/` and ignored here. Nothing is a submodule.

```
workspace/            this repository -- rules, hooks, formatter configuration, the list
  repos/press/        a repository of its own
  repos/still/        another
```

They are nested on the filesystem so the shared rules sit one directory up, where the tools that
look for them will find them; they are separate repositories so a project's history, its
lockfile, its credentials and its issue tracker belong to it alone.

The earlier arrangement was the other way round -- one project at the root with the rest nested
inside it -- and every conflict it produced came from that inversion. Whatever sits at the root
is shared with everything below whether it should be or not, so the site's credentials reached a
macOS application that had no business seeing them, and its deploy tasks were callable from
inside it. Demoting the project to a sibling did not need a mechanism; the containment was the
whole problem.

## Configuration is inherited by position, not copied

`.editorconfig`, `rustfmt.toml`, `.oxlintrc.json`, `.oxfmtrc.json`, the `[tools]` in `mise.toml`
and the agent hooks all live here and are found by walking up. Measured, each of them: a project
below carries no copy and needs none.

That is what decides the split. **A rule that holds for everything the author writes goes here;
a rule about one project goes in that project.** The position is the mechanism, so there is no
setting to keep in step and nothing to synchronise -- which is why an earlier design that copied
these files into each project, and checked the copies, is gone.

**The rule is mechanical, not remembered.** `mise run check` fails when a project carries a
version-controlled copy of `.editorconfig`, `rustfmt.toml`, `.oxlintrc.json`, `.oxfmtrc.json` or
`jj.toml`, and when it declares a tool the workspace already declares. Both existed and neither
was visible: still carried byte-identical copies of two of them and redeclared `rust`, and
nothing said so for as long as the copies happened to agree. A rule that only holds while two
files match is not a rule, it is a coincidence with a deadline.

An identical copy and a divergent one are reported differently -- the first is dead weight, the
second is the shadowing this arrangement exists to prevent -- and both fail, because a deliberate
override has to be written down here before it is legitimate.

A project cloned on its own therefore has no formatter configuration and no hooks. That is
accepted rather than worked around: the way to get a complete environment is to clone this
repository and the one project you want, nested. Two clones, not all of them.

**What decides whether a tool can live only here: does it need the project's module graph?**
A self-contained binary can. `oxlint`, `rustfmt`, `jj`, `node` and `rust` are declared once, in
this repository's `mise.toml`, and every project resolves the same one -- a project states a tool
of its own only where it needs one this list does not carry, the way press names `rclone` for a
bucket nothing else touches. A tool that resolves its own plugins through node cannot: `oxfmt`
with `svelte: true` reaches `svelte/compiler` through the module graph of wherever it is
installed, so the copy here formats markdown and JSON and fails on a `.svelte` file, and the
project that has Svelte keeps a copy of its own. That is the test to apply before moving a tool
up: plugins mean per project, otherwise once, here.

Nothing is installed globally. A global install is a third place a version can come from, with
no file recording it and nothing upgrading it -- a globally installed oxfmt sat at 0.28 for long
enough to format this repository differently from the project beside it. What a project needs, a
project or this repository declares.

**Sharing the rules is not the same as sharing the tool that applies them.** `jj fix` is
configured once, in `jj.toml`, and `JJ_CONFIG` is set here so every repository below inherits
it -- but the formatter it invokes is whichever one that repository's `PATH` provides. This has
already gone wrong: a globally installed oxfmt formatted this repository at 0.28 while a project
formatted at 0.65, one rule set through two formatters. So the version is pinned here in
`package.json` as well, matching the projects, and that pin is the second copy to keep an eye on.

**A project may carry configuration only it can use.** `.mcp.json` is the case: one project needs
a Tauri MCP server and the others have no use for it, so it stays with that project rather than
becoming everyone's. It resolves relative to where an agent starts, so it reaches that server
when the agent starts in that project and not otherwise, which is the right shape for a tool one
project owns.

## `.gitattributes` is the exception: it does not inherit

Everything above inherits downward. `.gitattributes` does not, and that is deliberate rather
than a gap. git resolves attributes by walking up from a file **to the top of its own worktree
and no further**, so a separate repository below never sees this one's -- measured, in
`repos/still`, where `git check-attr -a src/main.rs` returns nothing. This repository also
ignores `repos/*/`, so GitHub's language statistics for it never reach a project's files either.

The file here exists to fix what those statistics say. Linguist counts a file only when its
language is type `programming` or `markup`; Markdown is type `prose`, so 98KB of spec documents
-- the entire point of this repository -- counted for nothing and GitHub called it 100% Python
off the hooks and the task scripts. `*.md linguist-detectable=true` overrides that type test.
Nothing is excluded to reach the result: with Markdown counted the split is about 68/32 against
the Python that really is here.

**A project sets its own, by its own logic.** A Rust application and a website have nothing to
say to each other about what language they are written in, and the non-inheritance is what makes
that work without any opt-out.

## Why not a submodule

jj has no submodule support, and the failure is quiet. Colocating over a repository that has one
prints `ignoring git submodule at ...`; jj then preserves the existing gitlink in every commit it
writes but never updates it and never checks the content out, so the pointer could only move
through hand-run git commits in a colocated repository.

Inverting the layers was considered and measured -- a plain git outer repository with jj inside
each submodule works, including `jj git init --colocate` onto a modern gitlink *file*. It is
rejected on what it buys. A submodule pointer earns its cost when the superproject builds against
the submodule, and this one builds nothing; the dependency runs the other way. Recording which
revision of a project was current at a given commit here would be a record with no consumer, paid
for by giving up jj at the level where jj does the most.

**`.gitignore` still lists `repos/*/`.** Not for jj's sake -- jj stops at a nested `.jj` or
`.git` on its own -- but for git's, which otherwise writes exactly the gitlink above the moment
`git add -A` runs:

```
warning: adding embedded git repository: repos/press
160000 31cfb453... 0	repos/press
```

## `repos.toml` lists them; `mise.toml` says it again

`repos.toml` maps a local directory to a remote:

```toml
[repos]
press = "canmi21:press"
still = "canmi21:still"
```

**The directory is the key, so uniqueness comes from the format rather than from a check.** Two
entries cannot claim one folder, and a duplicate is a parse error where it would otherwise be a
surprise on clone. The user half is carried so an organisation's repository is an entry like any
other, and so one repository name under two owners can sit side by side under different
directories -- which is the case a bare `user:repo` list could not express at all.

That key is also the name every command takes.

mise needs the same set as task roots and cannot read that file, so `[monorepo].config_roots`
states it a second time. Two copies of one fact, and therefore a check: `repos check` fails when
they disagree. This is the shape used wherever a fact has to cross a boundary a tool cannot see.

A listed project that is not cloned is a warning from mise and nothing more, which is what makes
the two-clone workflow work: a machine holding one project runs that project's tasks and is not
told off about the others.

## One verb, optionally one name

`pull`, `push`, `fmt`, `check` and `update` run across every repository, and take a name from
`repos.toml` to run against one:

```
mise run pull            every repository
mise run pull press      that one
mise run check           each repository's own verify
mise run update still    that one's tools
```

They are one-line aliases onto a single implementation, so the short form is what gets typed and
the logic lives once. A name that is not in the registry is an error that lists the names that
are, because the alternative -- doing nothing quietly, or doing everything -- are both worse than
saying so.

**This workspace is one of the repositories they act on**, under the name `workspace`. It has a
remote, a working copy and files to format like any project, and the first version of these
commands left it out: `push` reported nothing to push while this repository was a commit ahead
of its origin, which is the worst possible way for a push command to be wrong. A command that
means "all of them" has to mean all of them, and the one holding the others is the easiest to
forget.

**Everything that changes something takes `--dry-run`, or `-n`.** The flag may go anywhere after
the verb, because mise appends it last: `mise run push press --dry-run`. `push` and `update` pass
it to the tool underneath, which has a real one; `pull` skips the fetch and says the divergence
it reports is as of the last one; `verify` prints the task paths it would run.

`fmt` is the interesting case. `jj fix` has no dry run, and predicting what a formatter will do
means reimplementing the formatter, so the dry run **runs it and puts the repository back** --
the operation log records every state the repository has been in, and `jj op restore` returns it
to the one from before the fix. What it reports is what the formatters actually did.

`check` dispatches to each repository's own `verify` rather than reimplementing it: what a
project has to pass is the project's to decide, and this only decides where to look. `fmt` is
`jj fix` with the formatters `jj.toml` names, which is why formatting is identical everywhere
without any project configuring it.

## Tasks are reached by path

Each project's `mise.toml` is a task root, so its tasks are `//repos/<name>:<task>` and this
repository's own are `//:<task>`. Two projects may both have `check` without collision, and no
project's `deploy` is reachable by typing a bare task name from inside another.

`mise tasks ls` shows only this repository's; `--all` is needed for the projects'. That is worth
knowing before concluding a project has no tasks.

## Nothing is written down inside a project except its own spec

`CLAUDE.md` says every rule the user states gets written down and never left in chat only.
**Inside a project that rule is narrower.** A project carries `spec/` and no `CLAUDE.md`, because
work always begins at this repository and a second entry point would be a second thing to keep
current.

The default in a project is still to write nothing beyond what the user asks for: the design of a
separate application is that application's, and dragging it here would defeat the separation.
When something does belong to this repository -- the entry below is one -- the user says so.

A project's `spec/` may cite this repository's rules in prose but does not link to them. A
relative link across the boundary resolves only while nested and is fragile about depth; a
citation by name reads correctly either way. Code citations are different: `refs` resolves a
cited `spec/*.md` by walking up, so it finds this repository's rules when nested and reports them
dead when the project stands alone, which is the truth in both cases.

## Cargo does not honour `.gitignore`

git and jj stop at `repos/*/`. Cargo does not -- it walks the filesystem looking for a workspace:

```
error: current package believes it's in a workspace when it's not:
current:   .../repos/still/Cargo.toml
workspace: .../Cargo.toml
```

A Rust project therefore carries an empty `[workspace]` table, which ends the walk. Adding it to
another repository's `members` is the other thing cargo suggests and is exactly wrong: a missing
directory in that list is a hard error, so a checkout without the project cloned would lose every
cargo command.

Membership would also cost what it silently changes. A member's `[profile]` is ignored with only
a warning, and a member has no `Cargo.lock` of its own -- so the project would build differently
inside and outside, and a lone clone would resolve dependencies unpinned. Unlike pnpm, cargo has
no `--ignore-workspace` to write an outward lockfile with.

## The agent hooks resolve upwards

The hooks are found through `jj workspace root`, which answers about the nearest repository -- so
inside a project it answers about the project. The command in
[`.claude/settings.json`](../../.claude/settings.json) walks up from there until it finds a
checkout that has `hooks/`. A fixed path was the alternative and is wrong: the walk is what lets
one entrypoint serve every project.

This is why the commit conventions reach a project without anything being installed in it: a
commit written inside `repos/press` is held to them, and a contributor's own clone is not, which
is the right split.

**The walk starts from `pwd` when jj answers nothing.** Outside any repository `jj workspace
root` fails, and the empty string it leaves is a fixed point of `dirname` -- it returns `.`
forever, so the loop never reaches `/` and never ends. A hook that hangs blocks every command in
the session, including the one that would leave the directory, so this is unrecoverable from
inside the shell. Moving a repository is exactly such a moment, which is when it was found.

## One checkout per repository

There is no arrangement for running several checkouts of one repository side by side, and the one
that existed is gone. It solved a problem that only exists in a monorepo: two pieces of work
colliding in one tree. Two projects in two repositories do not share a tree, so changing the CMS
and changing a standalone application are simply two directories, and the dev servers, port
arithmetic and coordination rules that arrangement needed went with it.
