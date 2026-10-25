# AGENTS.md

The workspace. This is the entry point for any agent starting with zero context, and work always
begins here. A project under `repos/` keeps its rules in `docs/` and may carry an `AGENTS.md` of
its own, read after this one: it extends this file with what is that project's alone and restates
none of it -- [docs/repos.md](docs/repos.md), "A repository's own rules extend the workspace's".

It is named `AGENTS.md` so that one file serves both harnesses without a symlink. Codex reads the
name natively; Claude Code reads it through its built-in `agents-md` plugin, whose default mode
loads a project's `AGENTS.md` exactly where a `CLAUDE.md` would be, provided the project has no
instruction file of its own -- https://github.com/anthropics/claude-code/tree/main/mods/agents-md.
That proviso is a rule: **no `CLAUDE.md` exists anywhere in this tree**, because one would stop
Claude Code reading this file.

## Start here

Read this file, then the rules covering your task: this workspace's `docs/` and `model/rules/` for
the ones that follow the author everywhere, and the project's own `AGENTS.md` and `docs/` -- `spec/`
until it is renamed -- for the ones belonging to the project you are about to touch. If none answers
a decision you are about to make, ask the user. Decisions belong to the user, not to you -- unless
their described approach already implies the answer. See
[docs/agents/agent-protocol.md](docs/agents/agent-protocol.md).

## What this repository is

Configuration, and nothing else. It holds what is true of every project the author writes --
how code is formatted, how commits are worded, how an agent behaves -- plus the list of which
projects exist and where they come from. It holds no application code, and it never will.

Each project is **its own repository**, cloned into `repos/` and ignored here. Nothing is a
submodule. The arrangement exists so an agent can work on a project with the shared rules
visible one directory up, and so a contributor can clone this repository plus the one project
they care about and have a complete environment without copying everything else.

```
AGENTS.md      this file, the only entry point
mise.toml      monorepo root, task roots, the shared toolchain, the verbs
model/         every rule a program can decide, its values and its check, in ReScript
docs/          the why behind the rules, and the rules only judgment keeps
scripts/       the tasks two repositories share, and the verbs' dispatcher, in ReScript
hooks/         the agent hook entrypoint both vendors call, and the rm guard
.mcp.json      the Tauri MCP server, pinned to its plugin, kept for the next Tauri app
repos/         one directory per project, each a separate repository, grouped as the author likes;
               registry.toml, the one file here, lists them as path = "user:repo"
```

Formatting configuration lives here and is found by walking up: `.editorconfig`, `rustfmt.toml`,
`rust-toolchain.toml` and `.oxlintrc.json` are read from a project below without being copied into
it. So is the toolchain in `mise.toml`, and so are the hooks. See [docs/repos.md](docs/repos.md).

## How rules are recorded

Every rule the user states gets written down. Never leave one in chat only.

- This file holds the most important, most universal rules, plus the index below.
- **A rule a program can decide goes in `model/rules/`, with the check that holds it**, or marked
  `Pending` with what the check would need; its why goes in `docs/`, which names the model file
  rather than repeating a value. `mise run check workspace --pending` lists what no check holds
  yet; **a pending rule is the goal, and until its check lands the present behavior holds**. See
  [docs/model.md](docs/model.md).
- Anything only judgment can keep gets a topic file in `docs/`, split by aspect, linked from the
  index.
- A rule that belongs to one project goes in that project's `docs/`, not here; one two projects
  share comes here.
- Never restate the rules here. Link to them.
- What is not done yet is an RFC, in the repository nearest it: a `draft` for an open question,
  an `accepted` one for decided work, blocked by others by id, each id unique in its repository's
  id space. **To know what is left, run `mise run plan`**; a project's `docs/` keeps its rules and at most a short
  `roadmap.md`. What is decided and only waits on a moment is a deferred item,
  `model/plan/deferred.res`, listed in red at the end of every check. See
  [docs/planning.md](docs/planning.md).
- Agent memory keeps only what is private and the state of work in progress; a lesson learned the
  hard way is written into [docs/lessons.md](docs/lessons.md).
- When the user says "remember this" or "update yourself": do not write to agent memory. Audit
  `docs/`, `model/rules/` and this file instead, then verify a zero-memory agent could recover the
  arrangement from `AGENTS.md` alone. See
  [docs/agents/agent-protocol.md](docs/agents/agent-protocol.md).

## Core rules

**Delegation** -- **a session works directly unless the user says it delegates.** Whether to spawn
agents is the user's call, made per session, and the default is no. The user names a session's
role at its start. **Where an advisor is named, the paraphrase, the judgment and the decisions
belong to the user and the advisor; the sequence, who owns which file, the commits and writing the
rules belong to the integrator**, which reads every implementer's diff and runs the check once per
wave. Where no role is named, one session holds both. The implementers edit, each in a lane of its
own, owning a declared set of files and touching nothing else. Testing belongs to the user -- they
are faster than any verification loop -- so a round of work ends with something the user can try
by hand, a page to click or a curl to run, and where there is nothing to try, with a rehearsal that
passed. See [docs/agents/delegation.md](docs/agents/delegation.md).

**Commits** -- Conventional Commits, the types and widths in `model/rules/commits.res`. Omit the
scope in most cases. Subject starts lowercase, imperative mood, 96 characters at most. Plain text
throughout, never Markdown. **A body is optional and usually absent**: it says what changed, in
three lines or so, and never why. The reasoning goes to the rules or beside the code, where
somebody is looking for it -- a log carrying it twice is the mistake this rule exists to stop. A
hook refuses a malformed message, and the commits part of the check reads every one since. **A
commit waits until `mise run check <path>` passed at the working copy**; `SKIP=verify jj commit
...` names the escape. See [docs/commits.md](docs/commits.md).

**Comments** -- a comment points rather than argues, **in one or two lines of plain statement, its
prose with no colon and no dash**. The settled argument lives in the rules and
the comment names the file; **a decision nobody has made yet is a draft RFC**, cited by id in one
line. Once it is made it becomes a rule plus the change that implements it, never a comment
carrying the debate. See [docs/code.md](docs/code.md), "The rules hold what is settled; an RFC
holds what is not".

**Language** -- Talk to the user in simplified Chinese with English technical nouns left
untranslated. Everything written into a file is English only: code, comments, docs, commit
messages. **The English is American** -- `color`, `behavior`, `license`, never the British
spelling; the platform is already American and half of it is identifiers, so a `color` in prose
is a second spelling of a word the reader will search for as `color`. The one exception is a value
that _is_ somebody else's name, which is recorded as its owner spells it rather than translated.
An explicit user request overrides the rest. "App" means a standalone application, a deployed
service, or a desktop client depending on context -- read which from the sentence rather than
asking every time. "Base", unqualified, is this workspace. **"Kit" is either SvelteKit or the
design package `@canmi/kit`** -- read which from the context; "shared lib" is the whole library,
the `lib` repository. See [docs/voice.md](docs/voice.md).

**Naming** -- Files and directories are lowercase English, hyphens allowed. A language with its own
convention wins locally: Rust and ReScript source files use underscores. Identifiers inside code
always follow the language's own convention. A name is written whole -- Cloudflare, never `CF`.
Vendor names stay at the binding edge -- name a module for what it does, not for who supplies it.
See [docs/naming.md](docs/naming.md).

**Shape** -- a tree grows by nesting, never by spreading: no directory but a root holds more than
`Layout.widest` entries or lies more than `Layout.deepest` deep, and a root holds configuration, not
source. It only warns at a commit and stops a push,
[docs/agents/checking.md](docs/agents/checking.md). See [docs/repos.md](docs/repos.md), "A tree
grows by nesting, never by spreading".

**Lint vs format** -- a linter owns semantics, a formatter owns layout. Whatever the formatter
rewrites, the linter must not report; disable the overlap on the linter side. Holds for every
language. See [docs/lint-format.md](docs/lint-format.md).

## Toolchain

**The user's shell is fish.** Any command written for them to run must be fish syntax --
`set -gx X y`, not `export X=y`; `$(cmd)` is not fish. Commands an agent runs through its own tool
go through that tool's shell instead, which is usually not fish, so the two are written differently
on purpose.
**An agent deletes with `trash`** -- files and directories alike, because what `trash` removes can
be put back. `trash old.log`, `trash dist/`, `trash a b c` -- no recursive flag exists or is needed.
**A cache that can be written again is cleared by its own tool's clean**, as `cargo clean`; one with
no clean, as `node_modules`, and a lane's directory being closed are removed with `rm` inside the
workspace; **a key a program generated in the scratchpad is removed with `rm` once entered as a
secret**, since `trash` would keep it. An `rm` typed anyway meets a guard that allows it only inside
the workspace, temp and caches, and refuses the rest.

Local development is `localhost`, everywhere it is written down; a literal IP is only for
reaching another machine across the network. Version control is jj (Jujutsu), colocated with git
-- use `jj`, not `git`, in this repository and in every one below it. Bookmarks do not advance on
their own. An agent commits what is settled and pushes at the right moment, unless the user said
not to -- see [docs/commits.md](docs/commits.md). mise owns every tool version. **A script, a task
or a hook is ReScript**, compiled by `mise run build` and never committed; a mise task is the
entry, `Toolchain.taskLines` lines at most, and `hooks/bin/rm` with its guard the one thing left in
Python. Indentation is tabs at
width 2 in every language, YAML excepted; `.editorconfig` is the source of truth. See
[docs/toolchain.md](docs/toolchain.md).

**One verb, the workspace unless told otherwise.** `mise run pull|push|fmt|check|update|clean|audit`
alone runs on this workspace; add a path from `repos/registry.toml` -- `mise run check apps/rdm` --
to run on that repository, or `--all` to run on every one, a paused one passed over by `check`
and `audit`, and `--dry-run` to any of them to be told what it would do. A name means that repository alone, in every verb, and never with `--all`.
`pull` and `push` are jj's and live here; the rest run each repository's own task -- `verify` for
`check` and `audit`, and `update`, `clean` and `fmt` -- and pass over a repository without one,
naming it. `check` then runs the workspace's rules over the repository, and its pass is what a
commit there waits on. What such a task owes the verb, `--dry-run` first, is in [docs/repos.md](docs/repos.md).
The workspace's own half runs in the dispatcher, `scripts/workspace/repos.res`: its check is
`model/check.res`, and `mise run check workspace words names` runs only the parts named. `audit`
is `check` with every warning counted as a failure, which is not what routine work runs. `update`
moves within declared bounds and keeps a repository's move only where its own verify still passes;
crossing a range is `update --major`, crossing a tool pin is an edit to `[tools]`. `clean` removes
what a tool wrote and can write again; dependencies and local state are not caches. `mise run
repos list|clone` reads the registry against the disk, and `mise run tools` the toolchain against
its pins. See [docs/toolchain.md](docs/toolchain.md).

**`each` is every other task.** `mise run each <task> [args]` runs it in every repository that
declares it, one at a time and on past a failure; the rest are passed over. See
[docs/repos.md](docs/repos.md).

**`publish` is the one verb that refuses to mean everything.** `mise run publish <name>` runs
that project's own publish task and a missing name is an error, because a release cannot be
taken back. See [docs/repos.md](docs/repos.md).

**A project's tasks are reached by path.** `mise tasks ls` shows only this repository's; the
projects' are `//repos/<name>:<task>` and need `mise tasks ls --all` to be listed. A project
that is not cloned is a warning, not an error, so a machine holding one project still works.

## Index

**Starting, and working with the user**

| Topic                                                                                                   | File                                                           |
| ------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| Cold start, decision authority, citing a section or a count, reading upstream, long commands, verifying | [docs/agents/agent-protocol.md](docs/agents/agent-protocol.md) |
| When the user names a role at a session's start, read that role's file first                            | [docs/agents/](docs/agents/)                                   |
| Lessons learned the hard way: commits, other sessions, shells, remotes, reading                         | [docs/lessons.md](docs/lessons.md)                             |
| The model: what a program decides, what holds each rule, what is pending                                | [docs/model.md](docs/model.md)                                 |
| Spawning implementers: briefs, lanes, who tests, who checks, who commits                                | [docs/agents/delegation.md](docs/agents/delegation.md)         |
| Voice and communication                                                                                 | [docs/voice.md](docs/voice.md)                                 |
| Planning: a short roadmap here, every open question and piece of decided work an RFC                    | [docs/planning.md](docs/planning.md)                           |
| READMEs, repository descriptions and license years                                                      | [docs/readme.md](docs/readme.md)                               |
| Why a decision was made: RFCs, drafts, and a rule citing one by id                                      | [docs/rfcs.md](docs/rfcs.md)                                   |
| Commit conventions, when to commit and push, and their enforcement                                      | [docs/commits.md](docs/commits.md)                             |

**How the arrangement is shaped**

| Topic                                          | File                             |
| ---------------------------------------------- | -------------------------------- |
| Separate repositories, nested and shared       | [docs/repos.md](docs/repos.md)   |
| Naming conventions                             | [docs/naming.md](docs/naming.md) |
| Vendored source: where, how taken, how treated | [docs/vendor.md](docs/vendor.md) |

**Writing code**

| Topic                                                | File                                       |
| ---------------------------------------------------- | ------------------------------------------ |
| Type checking, tests, comments, a UI that only draws | [docs/code.md](docs/code.md)               |
| Linting and formatting                               | [docs/lint-format.md](docs/lint-format.md) |
| Shell, addresses, secrets, versions, jj, hooks       | [docs/toolchain.md](docs/toolchain.md)     |

**The projects**

| Project                    | Rules                                                                                                                                                                               |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `repos/canmi/web`          | the site, its API, the status page, the service domains' pages, the CMS, `local` and the corpus -- [repos/canmi/web/spec/](repos/canmi/web/spec/)                                   |
| `repos/monoflake/platform` | the platform's design and every component a user runs, MIT OR Apache-2.0 -- its own [AGENTS.md](repos/monoflake/platform/AGENTS.md) and [docs/](repos/monoflake/platform/docs/)     |
| `repos/monoflake/driver`   | the drivers, what each vendor gives the platform through a kind's contract, MIT OR Apache-2.0 -- its own [AGENTS.md](repos/monoflake/driver/AGENTS.md)                              |
| `repos/monoflake/cloud`    | private: what runs the platform as the hosted one -- its control, anchor, console and the two deployments' configuration                                                            |
| `repos/apps/still`         | a macOS application; no spec yet                                                                                                                                                    |
| `repos/canmi/lib`          | the author's own library, every package and crate they publish that depends on nothing else of theirs, `axum-governor` among them -- [repos/canmi/lib/spec/](repos/canmi/lib/spec/) |
| `repos/apps/rdm`           | a GPUI download manager for macOS -- [repos/apps/rdm/spec/](repos/apps/rdm/spec/)                                                                                                   |
| `repos/apps/cue`           | one bot behind many chat clients: a stateful hub, and a thin bridge per client, QQ first -- [repos/apps/cue/spec/](repos/apps/cue/spec/)                                            |
| `repos/canmi/rfcs`         | why each decision was made, one file per decision; documents only, no spec -- [docs/rfcs.md](docs/rfcs.md)                                                                          |
| `repos/seam`               | compile-time rendering for Svelte, and the framework around it -- [repos/seam/spec/](repos/seam/spec/)                                                                              |
| `repos/console`            | an archive of what was web's console, pushed to `monoflake/console` and archived there; nothing in it builds, and this copy may go                                                  |
