# Tool versions

mise owns every tool, not just language runtimes. Linters, formatters, and CLIs belong in
`mise.toml` alongside the runtimes -- read that file for the current set. Do not install a tool
globally, and do not add a developer tool as a `devDependencies` entry when mise can carry it. One
manifest, one answer to "what version is this".

**mise's own `usage` is pinned in `[tools]` too**: mise reads a task's `usage` itself.

Three consequences worth knowing:

- mise activation is directory-scoped, so these versions resolve only inside this repo.
- Tools installed via mise have no `node_modules` presence, so JSON `$schema` keys must point at a
  hosted URL rather than a local path. `.oxlintrc.json` does this.
- A mise-installed tool cannot load a plugin that lives in `node_modules` -- node resolves modules
  from the requiring file's own path, so a binary under mise's install tree never reaches this
  repo's packages however it is invoked. oxfmt belongs in `package.json` with `svelte`, since its
  `svelte` option resolves `svelte/compiler` through the module graph. Enabling a plugin-shaped
  option on a mise-installed tool does not fail quietly -- it aborts the whole format run.
  `mise.toml` adds `node_modules/.bin` to the directory-scoped path so `oxfmt` is invocable.

Prefer the mise registry short name (`oxlint`) over a backend-qualified one (`npm:oxlint`); both
resolve to the same package, and the short form keeps `mise.toml` readable.

### Each layer pins only the layer directly beneath it

NixOS holds a machine and its container runtime, and never what runs inside a container, whose image
pins its own language and dependencies. For a project, Nix pins at most the version of mise, mise pins
the tools, and each tool or language's own lockfile pins its dependencies. Nix does not reach past the
next layer. Two exceptions: machine-update is built by the machine's flake as part of the
machine layer, and nixfmt, statix and deadnix come from nixpkgs, as they work on Nix alone.

### Nix is installed on the machine, and pins its own tools

Nix is a daemon and a store the whole machine shares, installed by the NixOS project's own
installer, https://github.com/NixOS/nix-installer, the upstream Nix the machines run, with flakes
on; mise cannot carry it. What Nix itself runs -- nixfmt, statix, deadnix -- comes from the nixpkgs
a project's `flake.lock` pins, `nix run --inputs-from`, so that lock is their one manifest, as
`mise.toml` is every other tool's. A task reaches Nix at `/nix/var/nix/profiles/default/bin`, which
a project's `[env]` adds to its path. **The Nix that acts for the fleet is the OS channel's, taken
from the lock**, on CI and on this Mac, and the Mac's daemon changes only by `mise run
//repos/monoflake/machine:channel mac`, never by `nix upgrade-nix` or Determinate Nix:
monoflake/machine's docs/releases.md.

**The Mac's Nix store collects its own garbage, and the disk is watched**, so an agent runs `nix
store gc` only when asked. `/etc/nix/nix.custom.conf` sets `min-free` and `max-free`, so a build
collects garbage once free space falls under 30 GiB, until 150 GiB are free; and the launchd daemon
`local.nix-gc`, `/Library/LaunchDaemons/local.nix-gc.plist`, runs hourly and at load, collecting
garbage when `/nix`'s volume uses more than the author's 100 GiB, logging to `/var/log/nix-gc.log`.
Both are system files outside every repository, installed by the author with sudo, and neither is
edited without the author.

### A machine tool is not a mise tool, and the line is what the tool acts on

mise pins what a project is built and checked with, so every checkout of it agrees. A tool that acts
on the machine rather than on a project does not belong there: tmux, the terminal, the browser a
check drives. Pinning one would claim a version for the machine on a project's behalf, and the next
project would claim a different one.

The test is what would break if two checkouts disagreed. Two node versions build two different
bundles, so node is pinned. Two tmux versions are two people's preferences and nothing a build can
see, so tmux is installed by Homebrew and named nowhere in `[tools]`.

### A tool is pinned to its major, and update crosses it

`[tools]` names a major -- `node = "26"`, `pnpm = "11"` -- rather than `latest`; `Toolchain.pin` is
the shape, and the pins part holds this repository's `[tools]` to it. Inside that number `mise
upgrade` moves freely, and past it `mise run update` bumps the pin to the tool's newest stable
release, as `mise upgrade --bump` does, keeping its precision: `jj = "0.46"` becomes `"0.47"`, `node =
"26"` the newest major. Crossing a major still arrives as a diff in `[tools]`, kept only where the
repository's verify passes and landed with a commit of its own, as a major is where a lockfile format
or a runtime behavior changes.

Below 1.0 the minor is the breaking release, so jj is pinned at `0.46` rather than `0`. The distance
from jj 0.45 to 0.46 is the distance from node 26 to 27, and a pin that could not see it would be a
pin in name only. `rust` is a channel rather than a version and has no major to cross.

**A pin makes "am I current" two questions, and only one of them is about majors.** The publisher's
newest release answers "is a new major out". "Am I current on the line I pinned" is answered by that
line's own stable release -- npm's `latest-11`, not `latest`. `update` asks both.

**A pin narrower than its line is named as the reason a release is out of reach.** `11.24` and `11`
are the same line and not the same pin, and a report that cannot tell them apart offers an upgrade
no command here will take. A report names only versions the pin permits as available inside it.

**`update` runs `rustup update`.** rust is the one tool `mise upgrade` cannot move -- mise's rust is
a symlink to rustup's toolchain rather than an install of its own.

**A bump is taken only onto a stable release of the repository's own pin.** `mise upgrade --bump`
reads every published version, so `update` asks it first, `--dry-run`, and takes a bump only where
the pin is in the directory's own `mise.toml`, the version is newer than the one installed, and it is
no further than the publisher's stable release. A prerelease line, a prerelease with no channel to
compare, and an npm tool pinned at a prerelease, which follows npm's `latest` instead,
[dependencies.md](dependencies.md), are left and said with the reason. `--dry-run` says each bump
and writes nothing:

```
$ mise upgrade --bump jj --dry-run
workspace      jj         would bump "0.46" -> "0.47", 0.47.1
workspace      jj         would move 0.46.0 -> 0.47.1
workspace      oxlint     would move 1.90.0 -> 1.93.0

------------------------------------------------------------------------
Against each publisher's stable channel:

workspace      shfmt      3.14.1       no stable channel to compare

  a pin left here is one update does not take, its reason said above
```

What is left says why: a pin narrower than its line to widen, a release past stable not to take, or a tool with no channel to compare. **The
notice goes last, after the upgrade output, and nowhere else.** It is the only part a person has to
act on, and an install log is long enough to bury it. `verify` stays offline and does not carry this
check.

**mise's `latest` is not the publisher's stable channel either.** It can sit ahead of the channel,
so `latest` is never reported as the stable release.

### What CI cannot update reaches the author as one line

**What the scheduled update cannot take is reported locally, and nothing else**, `update-reminder`
in [model/rules/toolchain.res](../../model/rules/toolchain.res). `mise run pull` and `mise run check`
start, at most once a day and detached, `mise run update --all --dry-run --json`, keeping its
summary under `$XDG_CACHE_HOME/monoflake/update/` with the day each item was first seen. Reported
are an action pin, which the bot does not move ([ci.md](../ci.md), "Scheduled updates"), a dependency's move only `--major` takes, a tool's pin being crossed by update itself, a tool the Mac has not installed at its pinned version, and any move within the
bounds still waiting two days after it first appeared, which means the scheduled update keeps
failing. A move within the bounds younger than that is not reported, since tonight's run takes it.
The line comes at the end of `pull` and `check`, counts per kind and `mise run update --dry-run` for
the detail, and the agent's session start adds the same line to its context so the agent tells the
author; there is nothing at all when nothing is reported. Not a mise `[hooks] enter`, which would be
noisy in fish and reach the network on every directory change.

### Stable means the publisher's channel, not the highest version that exists

mise resolves a pin against every release a tool has published, including prereleases.

**The version tracked is the one an outside build resolves.** Cloudflare and Vercel have never heard
of mise; they read npm's dist-tags, a GitHub release marked not-prerelease, nodejs.org's index. So
`mise run tools outdated` asks those, per tool, and reports a version **ahead** of stable as loudly
as one behind it. A tool whose channel cannot be read is named as such rather than guessed at from
the highest tag.

**`update` drops mise's own upgrade advice rather than passing it on.** After upgrading within the
pins, mise prints that newer versions exist outside the configured ranges and to run `mise upgrade
--bump`. Never follow that here: mise resolves against every published version and cannot read a
dist-tag, so it installs a prerelease. The line is filtered out of the output and replaced with one
that names the version, the file that pins it, and which channel it is actually on.

**A narrow pin's note names the fact that would let it go, and somebody has to check that fact.**

**`rust-toolchain.toml` is generated too, and rustup is what reads it.** mise's rust is a symlink to
the rustup toolchain rather than one mise installs, so the file at the workspace root is the thing
that actually decides which compiler every crate below builds with. It names the `stable` channel,
mirroring `rust = "stable"` in `mise.toml`, rather than the release that channel holds today.

A concrete version is a toolchain of its own to rustup: `1.99.0` installs a second full compiler
beside `stable` even when the two are the same release, and every later release adds another that
nothing removes. The author's crates outside this workspace build on `stable` too. `tools outdated`
reports channel drift, and `update` closes it with `rustup update stable`. Two machines can still
build with different releases from the same file; that is the trade `rust = "stable"` accepts below,
and `verify` catches a release that breaks something.

`update` writes it from the pin and `verify` checks it, the same as `.node-version`. The release the
channel holds is read with `rustup run stable rustc --version`, which asks the channel by name
rather than whatever a nearby `rust-toolchain.toml` resolves to.

**An image pins the release, since the channel names none.** A rust image is tagged by release, and
infra's is held by its digest too, so a tag pushed again cannot change what a node runs. So the
`image` task of infra and of the platform each names the release, moved with the channel only when
somebody moves it.

**Node follows the current release line, never LTS.** `node = "26"` is the Current line, and 26 is
not an LTS -- that is the intended state and not something to correct. Cloudflare serves both lines,
so the safety an LTS buys is availability this does not need, and what it costs is running a runtime
a year behind the one being written against. Nothing here is a commercial deployment with a support
contract to honor. `nodejs.org`'s index is read newest-first for the same reason, so "stable" for
node means released, not blessed.

### The files an outside build reads are generated, not maintained

`.node-version` and `packageManager` restate a version whose home is a `mise.toml`. They exist
because an outside build reads them and does not know about mise.

`mise run update` rewrites each from the pin it mirrors, and **`mise run verify` rewrites one that
something else has moved**, rather than failing: a pin inside a major floats, so the copies follow
on the next verify, to be committed with the change it ran for. A mirror of a hand-written source,
as the generated Rust URL mirrors in the platform and the lib repository, fails its check instead.

### Inside the major, a version number is a bug report

Within a pinned major nothing is written down: `node = "26"` takes whatever 26.x is current, and
`tools up` moves it. Naming an exact release there is a claim that _this_ one is what the repository
works with, and for a linter or a CLI that claim is almost never true -- it is the release that
happened to be current on the day somebody typed it. What the number then buys is a tool that stops
improving until a person remembers to raise it, and a diff every few months that says nothing except
that time passed.

So a version narrower than the major is written when a specific release actually breaks something,
and it carries the reason beside it: which version, what it broke, and what would let it be lifted.
A narrow pin with no such note is indistinguishable from one nobody has revisited, and the next
reader cannot tell whether it is still needed.

`rust = "stable"` is the same rule wearing a channel name.

What this accepts is that a patch release can change under a build nobody touched. That is
survivable because `verify` runs: the change surfaces as a failing check rather than as behavior
nobody notices. Freezing an exact version defers the same discovery indefinitely instead, which is
the worse side of the same trade -- and it is why the boundary sits at the major, where the change
is large enough to be worth stopping for, rather than at every release.

### The JavaScript toolchain lives in package.json

`typescript`, `vite`, and `vitest` are root `devDependencies`, not mise tools. mise's registry
carries none of them, and that is the right outcome rather than a gap:

- `vitest` is imported by the test files themselves (`import { it } from 'vitest'`), so it has to be
  resolvable from `node_modules`. A binary on `$PATH` cannot satisfy an import.
- `typescript` is looked up out of `node_modules` by editors, language servers, and vite.
- `vite` is what vitest runs on, and every web app will depend on it directly.

The general rule behind the exception: **a tool belongs to the package manager whose resolution
model it participates in.** oxlint reads files and writes files, so mise carries it. oxfmt resolves
`svelte/compiler` through node's module graph with its `svelte` option, so it belongs here with
`svelte` beside it to satisfy that peer dependency. Anything the code itself imports, or that
another JS tool resolves by module name, belongs in `package.json`.

Task entry points stay in mise regardless of where the tool lives, so there is one place to look for
"how do I run this" whichever ecosystem the binary came from. `mise tasks` lists them; `mise run
verify` is the one a change has to pass. Tasks are defined in `mise.toml`, except where a task needs
real logic, which is a script under `scripts/` the task runs.
