# CLAUDE.md

The workspace. This is the entry point for any agent starting with zero context, and the only
one -- a project under `repos/` carries `spec/` and no `CLAUDE.md`, because work always begins
here. `AGENTS.md` is a symlink to this file.

## Start here

Read this file, then the `spec/` files covering your task -- this directory's for the rules that
follow the author everywhere, and `repos/<project>/spec/` for the ones belonging to the project
you are about to touch. If neither answers a decision you are about to make, ask the user.
Decisions belong to the user, not to you -- unless their described approach already implies the
answer. See [spec/agent-protocol.md](spec/agent-protocol.md).

## What this repository is

Configuration, and nothing else. It holds what is true of every project the author writes --
how code is formatted, how commits are worded, how an agent behaves -- plus the list of which
projects exist and where they come from. It holds no application code, and it never will.

Each project is **its own repository**, cloned into `repos/` and ignored here. Nothing is a
submodule. The arrangement exists so an agent can work on a project with the shared rules
visible one directory up, and so a contributor can clone this repository plus the one project
they care about and have a complete environment without copying everything else.

```
CLAUDE.md      this file, the only entry point
mise.toml      monorepo root, task roots, the shared toolchain
repos.toml     which repositories this workspace is made of, as user:repo
spec/          rules that follow the author
hooks/         the agent hook entrypoint both vendors call
.mcp.json      the MCP server that drives press's desktop window, pinned to its plugin
repos/         one directory per project, each a separate repository
```

Formatting configuration lives here and is found by walking up: `.editorconfig`, `rustfmt.toml`,
`rust-toolchain.toml` and `.oxlintrc.json` are read from a project below without being copied
into it. So is the
toolchain in `mise.toml`, and so are the hooks. See
[spec/architecture/repos.md](spec/architecture/repos.md).

## How rules are recorded

Every rule the user states gets written down. Never leave one in chat only.

- This file holds the most important, most universal rules, plus the index below.
- Anything narrower gets its own topic file in `spec/`, split by aspect, linked from the index.
- A rule that belongs to one project goes in that project's `spec/`, not here.
- Never restate spec content here. Link to it.
- When the user says "remember this" or "update yourself": do not write to agent memory. Audit
  `spec/` and this file instead, then verify a zero-memory agent could recover the arrangement
  from `CLAUDE.md` alone. See [spec/agent-protocol.md](spec/agent-protocol.md).

## Core rules

**Commits** -- Conventional Commits. Omit the scope in most cases. Subject starts lowercase,
imperative mood, 96 characters max. See [spec/commits.md](spec/commits.md).

**Language** -- Talk to the user in simplified Chinese with English technical nouns left
untranslated. Everything written into a file is English only, no exceptions: code, comments,
docs, commit messages. Only an explicit user request overrides this. "App" means a standalone
application, a deployed service, or a desktop client depending on context -- read which from
the sentence rather than asking every time. "Base", unqualified, is this workspace. See
[spec/voice.md](spec/voice.md).

**Naming** -- Files and directories are lowercase English, hyphens allowed. A language with
its own convention wins locally: Rust source files use underscores. Identifiers inside code
always follow the language's own convention. Vendor names stay at the binding edge -- name a
module for what it does, not for who supplies it. See [spec/naming.md](spec/naming.md).

**Lint vs format** -- a linter owns semantics, a formatter owns layout. Whatever the formatter
rewrites, the linter must not report; disable the overlap on the linter side. Holds for every
language. See [spec/lint-format.md](spec/lint-format.md).

## Toolchain

**The user's shell is fish.** Any command written for them to run must be fish syntax --
`set -gx X y`, not `export X=y`; `$(cmd)` is not fish. Commands an agent runs through its own
tool go through that tool's shell instead, which is usually not fish, so the two are written
differently on purpose.

Version control is jj (Jujutsu), colocated with git -- use `jj`, not `git`, in this repository
and in every one below it. Bookmarks do not advance on their own. Pushing is the user's to run;
do not offer it. mise owns every tool version. Indentation is tabs at width 2 in every language,
YAML excepted; `.editorconfig` is the source of truth.
See [spec/toolchain.md](spec/toolchain.md).

**One verb, optionally one name.** `mise run pull|push|fmt|check|update` run across every
repository; add a name from `repos.toml` -- `mise run check press` -- to run against one, and
`--dry-run` to any of them to be told what it would do. `check` dispatches to each repository's
own `verify`; `update` upgrades tools within their pinned majors and ends by naming any major it
would not cross, which is the only place that gets reported.
See [spec/toolchain.md](spec/toolchain.md).

**`publish` is the one verb that refuses to mean everything.** `mise run publish <name>` runs
that project's own publish task and a missing name is an error, because a release cannot be
taken back. See [spec/architecture/repos.md](spec/architecture/repos.md).

**A project's tasks are reached by path.** `mise tasks ls` shows only this repository's; the
projects' are `//repos/<name>:<task>` and need `mise tasks ls --all` to be listed. A project
that is not cloned is a warning, not an error, so a machine holding one project still works.

## Index

**Starting, and working with the user**

| Topic                                     | File                                             |
| ----------------------------------------- | ------------------------------------------------ |
| Cold start, decision authority, verifying | [spec/agent-protocol.md](spec/agent-protocol.md) |
| Voice and communication                   | [spec/voice.md](spec/voice.md)                   |
| Commit conventions and their enforcement  | [spec/commits.md](spec/commits.md)               |

**How the arrangement is shaped**

| Topic                                     | File                                                     |
| ----------------------------------------- | -------------------------------------------------------- |
| Separate repositories, nested and shared  | [spec/architecture/repos.md](spec/architecture/repos.md) |
| Naming conventions                        | [spec/naming.md](spec/naming.md)                         |

**Writing code**

| Topic                          | File                                       |
| ------------------------------ | ------------------------------------------ |
| Type checking, tests, comments | [spec/code.md](spec/code.md)               |
| Linting and formatting         | [spec/lint-format.md](spec/lint-format.md) |
| Shell, secrets, versions, jj   | [spec/toolchain.md](spec/toolchain.md)     |

**The projects**

| Project      | Rules                                            |
| ------------ | ------------------------------------------------ |
| `repos/press` | the site, its workers, the CMS and the corpus -- [repos/press/spec/](repos/press/spec/) |
| `repos/still` | a macOS application; no spec yet                 |
| `repos/governor` | a published crate, `canmi21:axum-governor` -- [repos/governor/spec/](repos/governor/spec/) |
