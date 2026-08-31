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

A project cloned on its own therefore has no formatter configuration and no hooks. That is
accepted rather than worked around: the way to get a complete environment is to clone this
repository and the one project you want, nested. Two clones, not all of them.

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

`repos.toml` holds `user:repo` per project, cloned to `repos/<repo>`. The user half is carried so
an organisation's repository is one entry like any other rather than a second mechanism.

mise needs the same set as task roots and cannot read that file, so `[monorepo].config_roots`
states it a second time. Two copies of one fact, and therefore a check: `repos check` fails when
they disagree. This is the shape used wherever a fact has to cross a boundary a tool cannot see.

A listed project that is not cloned is a warning from mise and nothing more, which is what makes
the two-clone workflow work: a machine holding one project runs that project's tasks and is not
told off about the others.

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
