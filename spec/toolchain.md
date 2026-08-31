# Toolchain

## Shell

The user's interactive shell is **fish**, configured in `~/.config/fish/config.fish`.

This matters in two directions, and they are opposite:

- **A command written for the user to run** must be fish syntax. `set -gx KEY value`, not
  `export KEY=value`. Command substitution is `(cmd)`, not `$(cmd)`.
- **A command an agent runs through its own tooling** goes through that tool's shell, which
  on this machine is zsh, so it must be POSIX syntax. Writing fish syntax there fails with a
  parse error, and writing bash syntax into a fish snippet fails the same way in reverse.

Two more platform facts that cost time when forgotten: this is macOS, so `sed` is BSD sed
and does not support `\b` word boundaries -- use `perl -pi -e` for word-boundary replaces.
And mise activation is directory-scoped and shell-based, so a command run from a shell
without mise sees none of the pinned versions.

## Secrets

Credentials live in `secrets.json`, encrypted with [sops](https://getsops.io) to an
[age](https://age-encryption.org) key and **committed that way**. mise decrypts it on entering
the directory, so every tool reads the values from the environment and nothing keeps a second
copy. `.sops.yaml` names the recipient public key, which is safe to commit -- it encrypts and
cannot decrypt.

The private key lives at `~/.config/sops/age/keys.txt`, outside the repo, and belongs in a
password manager as well. Losing it costs a round of credential rotation, not the repo.

Committing the ciphertext rather than gitignoring a plaintext `.env` is what makes a fresh
machine reproducible: restore one key, clone, and every credential the project needs is
already there. A gitignored `.env` leaves no record of _which_ secrets exist, so setting up
again means rediscovering them one failure at a time.

Only genuinely secret values go in. Facts like `RCLONE_CONFIG_R2_TYPE = "s3"` stay in
`mise.toml`, so a diff of the encrypted file always means a credential actually changed.

**A value the browser must have cannot be a secret.** Anything compiled into a client bundle
-- an analytics token, a Sentry DSN, a publishable API key -- is readable from devtools by
anyone who loads the page. Storing it encrypted does not hide it; it only hides from the
reader of this repository that it is already public. Those go in `libs/urls` or plain config,
labelled for what they are.

The same credential can be secret elsewhere. The API worker's Sentry DSN is a different
project that never reaches a browser, so it stays a wrangler secret. What decides is exposure,
not the kind of thing it is.

### Three things that will bite

**JSON, not dotenv.** mise parses a `.env` as plain dotenv before looking for sops metadata
and fails on the age block. JSON puts that metadata under a `sops` key it recognises.

**No empty placeholders.** sops leaves `""` untouched, and mise then rejects the whole file
because a value lacks the `ENC[` prefix. Write `"unset"` instead of `""`.

**The circular trap.** A broken `secrets.json` makes `mise exec` fail in this directory --
including for the sops you would use to repair it. Call sops by absolute path when fixing it.

`mise run secrets` refuses any file `.sops.yaml` claims that is not actually encrypted, and
runs first in `verify` because it is the only check there guarding something irreversible: a
plaintext credential reaching the remote is not undone by deleting the file.

## Version control

jj (Jujutsu), colocated with git -- `.jj` and `.git` sit side by side in the repo root. Use
`jj` for everyday work; reach for `git` only where jj has no equivalent.

The remote is `origin` and the default branch is `main`; the URL lives in git's own config,
not here, because a URL written into a spec document is a second place for it to go stale.

jj has no branches, only bookmarks, and **bookmarks do not advance on their own**. `jj commit`
leaves `main` where it was, so moving it is a separate, deliberate step (`jj bookmark move`).
Auto-advance is available as an opt-in jj config -- `experimental-advance-branches`, still named
for branches from before the rename -- and is deliberately not enabled. A bookmark that only
moves when told to is a bookmark whose position means something.

Pushing is the user's to run. Do not offer it at the end of a task and do not ask whether to
push. Commit and move the bookmark; stop there.

One checkout per repository, and one agent in it. The arrangement that ran several checkouts
of one repository side by side is gone: projects are separate repositories now, so two pieces of
work that used to collide inside one tree no longer share a tree at all. See
[architecture/repos.md](architecture/repos.md).

## Tool versions

mise owns every tool, not just language runtimes. Linters, formatters, and CLIs belong in
`mise.toml` alongside the runtimes -- read that file for the current set. Do not install a tool
globally, and do not add a developer tool as a `devDependencies` entry when mise can carry it.
One manifest, one answer to "what version is this".

Three consequences worth knowing:

- mise activation is directory-scoped, so these versions resolve only inside this repo.
- Tools installed via mise have no `node_modules` presence, so JSON `$schema` keys must point
  at a hosted URL rather than a local path. `.oxlintrc.json` does this.
- A mise-installed tool cannot load a plugin that lives in `node_modules` -- node resolves
  modules from the requiring file's own path, so a binary under mise's install tree never
  reaches this repo's packages however it is invoked. That is why oxfmt moved to
  `package.json` when its `svelte` option (which resolves `svelte/compiler`) was switched on:
  the option is not gated on an app depending on svelte, it is structurally unreachable from a
  mise install. Enabling a plugin-shaped option on a mise-installed tool does not fail
  quietly -- it aborts the whole format run. `mise.toml` adds `node_modules/.bin` to the
  directory-scoped path so `oxfmt` stays invocable exactly as before.

Prefer the mise registry short name (`oxlint`) over a backend-qualified one (`npm:oxlint`);
both resolve to the same package, and the short form keeps `mise.toml` readable.

### A tool is pinned to its major, and crossing one is a decision

`[tools]` names a major -- `node = "26"`, `pnpm = "11"` -- rather than `latest`. Inside that
number `mise run tools up` moves freely; outside it nothing moves until the number is edited, so
crossing a major arrives as a diff with a commit message rather than as a surprise on a machine.
A major is where a lockfile format or a runtime behaviour changes, which is exactly the class of
change worth stopping for.

Below 1.0 the minor is the breaking release, so jj is pinned at `0.44` rather than `0`. The
distance from jj 0.44 to 0.45 is the distance from node 26 to 27, and a pin that could not see
it would be a pin in name only. `rust` is a channel rather than a version and has no major to
cross.

**mise will not tell you a new major exists.** With a pin in place `mise outdated` reports
nothing outside it -- it answers "are you current within what you asked for", which is a
different question. So `mise run update` asks the other one itself, against `mise ls-remote`, and
prints what is waiting without taking it:

```
workspace      oxlint     1.79.0 upgraded

------------------------------------------------------------------------
Held back at a pin. Nothing above crossed a major; these are waiting:

  pnpm       11.25.0  ->  12.1.0
             edit [tools] in mise.toml to take one
```

**The notice goes last, after the upgrade output, and nowhere else.** It is the only part a
person has to act on, and an install log is long enough to bury it. Putting the same check into
`verify` was the alternative and is worse: `verify` runs constantly and is offline, so it would
either gain a network dependency or report a cached answer that is stale exactly when it
matters. Asking at the moment somebody has decided to update costs nothing extra and reaches
them while the subject is already in mind.

This replaced `latest` everywhere, and the reason is worth keeping. `latest` is resolved once,
when a tool is first installed, and never advances on its own -- so it reads as "always current"
while meaning "whatever the day of installation happened to offer". Two machines set up a month
apart get different toolchains from the same file and neither says so. A major that has to be
typed is a version the repository actually records.

**mise's `latest` is not the publisher's stable channel either.** It offered pnpm 11.25.0 while
npm's `latest` tag pointed at 11.24.0, so `latest` had already put this workspace on a
prerelease line without saying so. Another reason the number is written down.

### Stable means the publisher's channel, not the highest version that exists

mise resolves a pin against every release a tool has published, and a published release is not
the same as a released one. pnpm publishes its `next` line to npm, so `pnpm = "11"` reached
11.25.0 while npm's `latest` tag was 11.24.0 -- the workspace was on a prerelease line and
nothing said so. The same mistake was then made twice over in the tooling written to prevent it,
which reported pnpm 12.1.0 as available because the version existed, when npm has no `latest-12`
at all.

**The version tracked is the one an outside build resolves.** Cloudflare and Vercel have never
heard of mise; they read npm's dist-tags, a GitHub release marked not-prerelease, nodejs.org's
index. So `mise run tools outdated` asks those, per tool, and reports a version **ahead** of
stable as loudly as one behind it. A tool whose channel cannot be read is named as such rather
than guessed at from the highest tag.

**`update` drops mise's own upgrade advice rather than passing it on.** After upgrading within
the pins, mise prints that newer versions exist outside the configured ranges and to run `mise
upgrade --bump`. Following that here installs a prerelease: mise resolves against every published
version and cannot read a dist-tag, so its bump target for pnpm was 11.25.0 while npm's stable
tag was 11.24.0. The line is filtered out of the output and replaced with one that names the
version, the file that pins it, and which channel it is actually on.

This is not tidying. The line was read, believed and acted on -- the pin in `mise.toml` was
edited to `11.25` because the command said to, one line below the command saying everything was
already current. A tool that reports a rule and repeats advice contrary to it has not reported
the rule.

`pnpm = "11.24"` carries a minor for exactly this reason, which is the kind of reason the rule
below asks a narrow pin to have. The digit comes off when the two lines converge.

**`rust-toolchain.toml` is generated too, and rustup is what reads it.** mise's rust is a
symlink to the rustup toolchain rather than one mise installs, so the file at the workspace root
is the thing that actually decides which compiler every crate below builds with. It carries a
concrete version rather than the word `stable`, for the reason every pin here does: a channel
name records nothing, and two machines set up a month apart would build with different compilers
from the same file and neither would say so.

`update` writes it and `verify` checks it, the same as `.node-version`. The version is read with
`rustup run stable rustc --version` rather than plain `rustc --version`, which would return the
version the file itself pins -- comparing the file against itself, a check that could never fail.

**Node follows the current release line, never LTS.** `node = "26"` is the Current line, and
26 is not an LTS -- that is the intended state and not something to correct. Cloudflare serves
both lines, so the safety an LTS buys is availability this does not need, and what it costs is
running a runtime a year behind the one being written against. Nothing here is a commercial
deployment with a support contract to honour. `nodejs.org`'s index is read newest-first for the
same reason, so "stable" for node means released, not blessed.

### The files an outside build reads are generated, not maintained

`.node-version` and `packageManager` restate a version whose home is a `mise.toml`. They exist
because an outside build reads them and nothing out there knows about mise -- and a restated
fact drifts, which it had: `.node-version` said 26.5.0 while mise resolved 26.8.1, so Cloudflare
was building on a node three patches from the one every local check ran against.

So they are written rather than edited. `mise run update` rewrites each from the pin it mirrors,
and `mise run verify` fails when something else has moved one. That is the same arrangement as
the generated Rust URL mirror in press: a copy across a boundary a tool cannot see, plus a check
that fails the moment it stops agreeing.

### Inside the major, a version number is a bug report

Within a pinned major nothing is written down: `node = "26"` takes whatever 26.x is current,
and `tools up` moves it. Naming an exact release there is a claim that *this* one is what the
repository works with, and for a linter or a CLI that claim is almost never true -- it is the
release that happened to be current on the day somebody typed it. What the number then buys is a
tool that stops improving until a person remembers to raise it, and a diff every few months that
says nothing except that time passed.

So a version narrower than the major is written when a specific release actually breaks
something, and it carries the reason beside it: which version, what it broke, and what would let
it be lifted. A narrow pin with no such note is indistinguishable from one nobody has revisited,
and the next reader cannot tell whether it is still needed.

`rust = "stable"` is the same rule wearing a channel name.

What this accepts is that a patch release can change under a build nobody touched. That is
survivable because `verify` runs: the change surfaces as a failing check rather than as
behaviour nobody notices. Freezing an exact version defers the same discovery indefinitely
instead, which is the worse side of the same trade -- and it is why the boundary sits at the
major, where the change is large enough to be worth stopping for, rather than at every release.

### The JavaScript toolchain lives in package.json

`typescript`, `vite`, and `vitest` are root `devDependencies`, not mise tools. mise's registry
carries none of them, and that is the right outcome rather than a gap:

- `vitest` is imported by the test files themselves (`import { it } from 'vitest'`), so it has
  to be resolvable from `node_modules`. A binary on `$PATH` cannot satisfy an import.
- `typescript` is looked up out of `node_modules` by editors, language servers, and vite.
- `vite` is what vitest runs on, and every web app will depend on it directly.

The general rule behind the exception: **a tool belongs to the package manager whose
resolution model it participates in.** oxlint reads files and writes files, so mise carries
it. oxfmt did too until its `svelte` option made it resolve `svelte/compiler` through node's
module graph -- participation that moved it here, with `svelte` beside it to satisfy that
peer dependency. Anything the code itself imports, or that another JS tool resolves by module
name, belongs in `package.json`.

Task entry points stay in mise regardless of where the tool lives, so there is one place to
look for "how do I run this" whichever ecosystem the binary came from. `mise tasks` lists them;
`mise run verify` is the one a change has to pass. Tasks are defined in `mise.toml`, except
where a task needs real logic, which goes in `.mise/tasks/` as an executable file.

### The other exception: hook scripts

`hooks/` is deliberately outside mise's reach. The real policies live there once and use
`#!/usr/bin/env python3` with nothing beyond the standard library. Both vendor directories
bind the same `hooks/run.py` entrypoint; `.claude/settings.json` and `.codex/hooks.json` are
only the glue that exposes it to each harness.

The reason is the failure mode. mise activation is shell-scoped, and a hook is launched by
the agent harness rather than by an interactive shell. If a hook's interpreter came from
mise and mise were not active, the hook would fail to start -- and a hook that fails to
start enforces nothing while looking exactly like a hook that passed. Silent
non-enforcement is worse than no enforcement, because it is believed.

Compatibility is a check, not a claim made once. `mise run verify` invokes the exact shared
entrypoint with representative Claude Code and Codex payloads under `/usr/bin/python3`, the
interpreter both adapters run. This catches syntax and annotation features newer than the
macOS system Python before either harness has to discover them one failed hook at a time.
Version pinning would buy nothing here and would cost the guarantee that the hook starts
outside an activated shell.

This exception covers hook scripts only. Everything a human or an agent invokes on purpose
still belongs in `mise.toml`.

## Dependency policy

`pnpm-workspace.yaml` sets `minimumReleaseAge: 1440` -- a package version must have been
public for 24 hours before it can be installed, transitive dependencies included. Most npm
compromises are found and yanked inside that window.

`minimumReleaseAgeExclude` holds the exemptions. Keep the list short: every entry is an
accepted risk, justified only when the wait costs more than it protects.

### An advisory in a development-only dependency is not a production one

Where a vulnerable package runs decides how much it costs. A deployed Worker uses workerd's own
fetch and never loads the HTTP client its build tooling depends on; a bundler plugin's glob
matcher never sees a request. Fixing those clears an alert list, which is worth something --
a list nobody can read is a list that hides the next real one -- but it is not the same work as
patching something on the request path, and a security fix that says which of the two it is
saves the next reader from having to re-derive it.

That ranking decides how much risk a fix may carry. Forcing a patch across an exact upstream pin
is reasonable for a clean list and unreasonable if it can break a build; where an override does
that, its comment says what was verified afterwards.

## Default stacks

| Area                      | Stack                      |
| ------------------------- | -------------------------- |
| Binaries and applications | Rust + Cargo               |
| Web                       | TypeScript + pnpm + Svelte |

These are defaults, not a whitelist. Reaching outside them is a structural decision and
belongs to the user -- see [agent-protocol.md](agent-protocol.md).

### A Rust CLI parses with clap, and wears cargo's colours

Arguments are declared as types with clap's derive API rather than read out of `std::env::args`
by hand. The property being bought is refusal: a hand-rolled loop matches the flags it knows and
ignores the rest, so a typo is silence. `cms` had five commands where that silence spent money --
`--limit` was read with `.parse().ok()`, and an unparsed limit is no limit, so `--limit 2x` and
`--lmit 2` both bought the whole library. Derive fixes both at once because the flag set _is_ the
type; there is no second list of known names to keep in step.

This was argued against on dependency grounds and the argument was wrong: `cms` runs locally, and
[code.md](code.md) already says dependency count is not a constraint there. A local binary's
compile time is paid by the one machine that builds it and its size is paid by nobody, so
refusing a parser to save megabytes trades a correctness property for a saving no one
experiences. The rule was already written; it just was not read.

Help is clap's own, styled with `anstyle` to cargo's palette -- green headings, cyan literals.
Not clap's defaults: this stands next to `cargo` in the same terminal, and one constant saves its
reader a second colour language. The hand-written usage text it replaced had drifted anyway, with
one command's description printed under another's name.

