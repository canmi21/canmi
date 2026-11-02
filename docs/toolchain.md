# Toolchain

## Shell

**Shell is fit as a workflow's entry and for an operation of one or two lines, and anything that
orchestrates is ReScript.**

The user's interactive shell is **fish**, configured in `~/.config/fish/config.fish`.

This matters in two directions, and they are opposite:

- **A command written for the user to run** must be fish syntax. `set -gx KEY value`, not `export
  KEY=value`. Command substitution is `(cmd)`, not `$(cmd)`.
- **A command an agent runs through its own tooling** goes through that tool's shell, which on this
  machine is zsh, so it must be POSIX syntax. Writing fish syntax there fails with a parse error,
  and writing bash syntax into a fish snippet fails the same way in reverse.

Three more platform facts that cost time when forgotten. This is macOS, so `sed` is BSD sed and does
not support `\b` word boundaries -- use `perl -pi -e` for word-boundary replaces. mise activation is
directory-scoped and shell-based, so a command run from a shell without mise sees none of the pinned
versions. And **there is no `timeout`**: it is GNU coreutils, `gtimeout` is not linked either, and
[agent-protocol.md](agents/agent-protocol.md) asks every command of unknown duration to carry a
ceiling. `perl -e 'alarm N; exec @ARGV' <command>` is the one that is always present.

### An agent deletes with `trash`, and a cache with its tool's clean

`/usr/bin/trash` takes files and directories alike, so every deletion an agent types goes through
it, but for three kinds, as `AGENTS.md` has it: **a cache that can be written again is cleared by
its own tool's clean**, as `cargo clean`, since `trash` frees no space; and **a cache with no clean,
as `node_modules`, and a lane's directory being closed are removed with `rm` inside the workspace**.
The reason is recovery: what `trash` removes can be put back, and what `rm` removes cannot. `rm` is
caught when an agent reaches for it anyway -- see "rm is guarded, not banned" below -- but the guard
is the net, not the method.

**Key material a program generated is the one deletion that must not be recoverable**, and is
removed with `rm` once it has been entered as a secret: `trash` keeps a copy in `~/.Trash`, and a
private key that can be put back is a private key that is still there. It is made under the
scratchpad, inside the temp directories the guard allows, so the `rm` is never one the guard
refuses.

Where the point is only to get something out of the way, moving it to a temporary directory answers
just as well and reads more honestly than a deletion.

The rule covers commands an agent types. What a tool does inside itself is the tool's -- `mise run
clean` removing what a build wrote is that task's business, and nothing here reaches into it.

The cost is small and worth stating so nobody is surprised by it: the bytes go to the Finder's trash
instead of being unlinked, so the space is not returned until the trash is emptied, and what was
deleted is recoverable until then.

### rm is guarded, not banned

An agent's `rm` is `hooks/bin/rm`, put first on PATH by `mise.toml` and judging every operand after
the shell has expanded it. That is the whole reason it is a shim rather than a pattern over the
command text: `rm -rf "$DIR/"` with an empty `DIR` reaches it as `/`, which no reading of the text
could have seen.

- **Inside the whitelist it is the real `/bin/rm`, with no question asked**: the workspace and every
  repository under it, `/tmp` (where the harness scratchpad lives) and `$TMPDIR`, and the caches --
  `~/Library/Caches`, `~/.cache`, `~/.npm`, `~/.bun/install/cache`, `~/.cargo/registry`,
  `~/.cargo/git`, `~/Library/pnpm/store`, Xcode's `DerivedData`; and
  `~/.local/share/monoflake/reset`, where monoflake/cloud's reset keeps the key copies it makes for
  a machine and removes with `rm` once the machine holds them, its docs/upgrades.md.
- **Refused outright**, with a hint that a variable is probably empty: an empty operand, `/`,
  `/Users`, the home directory, another user's, a whitelisted root itself, `repos/` and each
  repository root under it, and anything inside a `.jj` or `.git` store.
- **Refused with a pointer to `trash`**: the user's own files -- `Desktop`, `Documents`,
  `Downloads`, `Movies`, `Music`, `Pictures`, `Public`, iCloud's `Mobile Documents` -- and
  everywhere else outside the whitelist.
- **One refused operand deletes nothing**, including the operands that would have passed. Paths
  compare case-insensitively, because APFS does.

Outside an agent the shim execs `/bin/rm` untouched, so the user's own shell never meets it; an
agent is recognized by `CLAUDECODE`, `AI_AGENT` or a `CODEX_` variable. Only `/bin/rm` by its
absolute path skips the shim, which is why that alone is on the harness's ask list. The policy is
`hooks/rm_guard.py` and its tests run under `check workspace hooks`.

The shim reaches an agent only through the environment mise gave the shell that launched it -- a
harness started outside mise runs the plain `rm`.

### An agent stops a background process with a signal it can catch

`kill -9` on a dev server leaves its children running for as long as the machine is up. A supervisor
written in node -- `vite dev` carrying a Cloudflare platform proxy, `wrangler dev`, anything
standing on miniflare -- registers its cleanup on `exit`, `SIGINT`, `SIGTERM` and `SIGHUP`.
`SIGKILL` runs none of those, and the child runtime does not watch for its parent's death, so it is
reparented to `init` and holds its memory until something else kills it.

So a background process is stopped with `kill -TERM` or `kill -INT`, and the agent waits for it to
be gone before moving on. `-9` is for a process still there after a grace period, and reaching for
it is the decision to leak whatever it was holding.

**The signal has to reach the process that owns the child, not a wrapper above it.** A `mise run
dev-api` is a shell running a node process running `workerd`; signaling the shell ends the shell,
and what it supervises is orphaned with its exit hook unrun.

So: signal the node process by name, or the whole process group with `kill -INT -<pgid>`, and
**count what is left afterwards** rather than assuming. `ps -eo ppid | awk '$1==1'` is the check,
and it takes a second.

The same reasoning says not to go after the children instead. A supervised runtime is restarted when
it dies -- miniflare counts the crashes and says so -- so killing a child whose parent is still
alive buys nothing and hides the leak. Stop the parent, or restart it.

This is about signals an agent sends, not about how the user leaves a server: Ctrl-C in a terminal
is already `SIGINT`, and closing the window is `SIGHUP`. Both are caught.

## Secrets

Credentials live in `secrets.json`, encrypted with [sops](https://getsops.io) to an
[age](https://age-encryption.org) key and **committed that way**. `.sops.yaml` names the recipient
public key, which is safe to commit -- it encrypts and cannot decrypt.

**Only a task that uses a credential decrypts it**: each such task loads the file by an `env = {
_.file = "secrets.json" }` of its own, and a repository's global `[env]` never names it,
`secrets-per-task` in `model/rules/toolchain.res`. The task's tools read the values from its
environment, and nothing keeps a second copy. `secrets-unprinted` refuses a command that prints
credentials only when a subagent runs it, so the file not being loaded is what guards every other
shell and tool. canmi/web still loads its file globally, the deferred item
`web-secrets-tasks`.

The private key lives at `~/.config/sops/age/keys.txt`, outside the repo, and belongs in a password
manager as well. Losing it costs a round of credential rotation, not the repo.

Committing the ciphertext rather than gitignoring a plaintext `.env` is what makes a fresh machine
reproducible: restore one key, clone, and every credential the project needs is already there. A
gitignored `.env` leaves no record of _which_ secrets exist, so setting up again means rediscovering
them one failure at a time.

Only genuinely secret values go in. Facts like `RCLONE_CONFIG_R2_TYPE = "s3"` stay in `mise.toml`,
so a diff of the encrypted file always means a credential actually changed.

**A value the browser must have cannot be a secret.** Anything compiled into a client bundle -- an
analytics token, a Sentry DSN, a publishable API key -- is readable from devtools by anyone who
loads the page. Storing it encrypted does not hide it; it only hides from the reader of this
repository that it is already public. Those go in an address package -- `@canmi/me/urls` holds every
app's Sentry DSN -- or plain config, labeled for what they are.

The same kind of credential can be secret elsewhere. A token a Worker calls another service with
never reaches a browser, so it stays a wrangler secret. What decides is exposure, not the kind of
thing it is.

**A credential is issued only for what runs on a server, in CI or in the cloud; a task that runs
only on the author's Mac uses the author's logged-in CLIs**, `cf`, `wrangler`, `gh` and `tailscale`.
What runs elsewhere holds an account-owned token in the account it acts in, never a user-owned one,
minted by that account's token manager; the author's own login is the one user-level credential
left.

### A secret is typed in, never written down

**A value goes into `secrets.json` by `mise run secret <repo> <NAME>...` and no other way.** It asks
for each name in turn, reads what is typed without echoing it, and hands it to `sops set
--value-stdin`, so the value is in no argument, no process listing, no shell history and no plain
file but the one `--from` below reads it from. A name already set is replaced only when answered
`y`, or without the question under `--replace`, which says the replacement is already decided;
nothing typed leaves it as it was. It reports each value by its length alone, and the file it
changed stays encrypted and is committed as it is. It reads one line a value.

**A machine's file and a value of several lines.** A repository path that goes on into
`machines/<m>`, as `mise run secret monoflake/cloud/machines/<m> upgrade`, writes that machine's own
`secrets.json`, its names in lowercase and hyphens as sops-nix reads them, where a repository's are
in capitals. One that goes on into `platforms/<p>` writes the file a platform's machines share, as
the test platform's bucket read token, and one into `runner` writes the self-hosted runner's, both
named as a machine's are. `--from <file>` is given once, takes one name and the whole file as its
value, its lines and its final newline kept, handed to sops without passing through the shell; a
relative path is read from where the command was typed, and a file that is not UTF-8 text is
refused. It is for a value made by a program, as a key or an environment file, and is reported by
its size alone; a value of one line is typed, so no editor's newline joins it. A key a program
generates for it is made in a 0700 directory under the scratchpad and removed with `rm` once
entered, as "An agent deletes with `trash`" has it, and only its public half is kept.

```
$ mise run secret platform BACKUP_S3_ENDPOINT BACKUP_S3_REGION
secret: /Users/canmi/workspace/repos/platform/secrets.json
  BACKUP_S3_ENDPOINT: ••••••••••••••••••••••••••••••••••••••
  BACKUP_S3_ENDPOINT set, 38 characters
  BACKUP_S3_REGION is set already; replace it? [y/N] y
  BACKUP_S3_REGION: ••••••••••••
  BACKUP_S3_REGION set, 12 characters
secret: 2 set in /Users/canmi/workspace/repos/platform/secrets.json,
  still encrypted; it is committed as it is
```

**So an agent that needs a secret asks for this command, never for the value.** It names the
repository and the names, the author runs it in their own terminal, and the agent reads only that
the names now exist. A value pasted into a chat is in a transcript, and that is not undone.

### Three things that will bite

**JSON, not dotenv.** mise parses a `.env` as plain dotenv before looking for sops metadata and
fails on the age block. JSON puts that metadata under a `sops` key it recognizes.

**No empty placeholders.** sops leaves `""` untouched, and mise then rejects the whole file because
a value lacks the `ENC[` prefix. Write `"unset"` instead of `""`.

**The circular trap.** A broken `secrets.json` makes every task that loads it fail, and `mise exec`
too where a repository still loads it globally -- including for the sops you would use to repair it.
Call sops by absolute path when fixing it.

`mise run secrets` refuses any file `.sops.yaml` claims that is not actually encrypted, and runs
first in `verify` because it is the only check there guarding something irreversible: a plaintext
credential reaching the remote is not undone by deleting the file.

## Addresses

Local development is `localhost`. Every URL typed, configured or written down for a service running
on this machine uses that name, at every layer: the browser, the config file, the health check, the
test fixture. The words part refuses a literal loopback address in this repository.

A literal IP is what a machine on the local network is reached by, and only that. `localhost` on
another device is that device, so an address handed across the network has to name a host rather
than a role. Whichever form the network offers -- the address itself or a name that resolves to it
-- is the one to use.

Public addresses are decided case by case. There is no default worth writing down for them.

A listen address is not an address in this sense. What a server binds to answers which interfaces it
accepts on, and `0.0.0.0` or `::` there is a different question with a different answer.

## Version control

jj (Jujutsu), colocated with git -- `.jj` and `.git` sit side by side in the repo root. Use `jj` for
everyday work; reach for `git` only where jj has no equivalent.

The remote is `origin` and the default branch is `main`; the URL lives in git's own config, not
here, because a URL written into a spec document is a second place for it to go stale.

jj has no branches, only bookmarks, and **bookmarks do not advance on their own**. `jj commit`
leaves `main` where it was, so moving it is a separate, deliberate step (`jj bookmark move`).
Auto-advance is available as an opt-in jj config, `experimental-advance-branches`, and is
deliberately not enabled. A bookmark that only moves when told to is a bookmark whose position means
something.

Commit and move the bookmark; when to push is [commits.md](commits.md), "When a change is done, and
when it is pushed".

### Parallel workspaces, superseded by lanes

**A lane is a working copy of its own, one jj workspace for each implementer**.

- The file sets are disjoint, a shared file is written by the integrator alone, and a lockfile is
  derived; the diff `accept --from <base>` reads holds all three by machine.
- A lane starts no dev server and does no deploy or rehearsal; those are done by the integrator in
  the main checkout alone, and a test binds port 0.
- What every lane abides by is the model and the contracts, frozen in the base commit; they exist
  already, and are no structure made for the concurrency.

How a lane is opened, merged and closed is [lanes.md](agents/lanes.md).

**The cost is real and is accepted rather than hidden: a commit here is not guaranteed to build on
its own.** Several pieces of work land in one sequence, so checking out a commit in the middle may
find a change half of whose tree arrived in the next one. That is the price, and against it is a
mental overhead that is lower by a wide margin -- one tree, one set of servers, one place the
current state of anything is read. This is not a library with strangers bisecting its history. See
[commits.md](commits.md), "Completion", for what a commit is therefore for.

Projects are separate repositories, so this is a question about concurrency inside one project and
never about two. Two projects are two directories. See [repos.md](repos.md).

## Tool versions

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

### A machine tool is not a mise tool, and the line is what the tool acts on

mise pins what a project is built and checked with, so every checkout of it agrees. A tool that acts
on the machine rather than on a project does not belong there: tmux, the terminal, the browser a
check drives. Pinning one would claim a version for the machine on a project's behalf, and the next
project would claim a different one.

The test is what would break if two checkouts disagreed. Two node versions build two different
bundles, so node is pinned. Two tmux versions are two people's preferences and nothing a build can
see, so tmux is installed by Homebrew and named nowhere in `[tools]`.

### A tool is pinned to its major, and crossing one is a decision

`[tools]` names a major -- `node = "26"`, `pnpm = "11"` -- rather than `latest`; `Toolchain.pin` is
the shape, and the pins part holds this repository's `[tools]` to it. Inside that number `mise run
tools up` moves freely; outside it nothing moves until the number is edited, so crossing a major
arrives as a diff with a commit message rather than as a surprise on a machine. A major is where a
lockfile format or a runtime behavior changes, which is exactly the class of change worth stopping
for.

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

**mise will not tell you a new major exists.** With a pin in place `mise outdated` reports nothing
outside it -- it answers "are you current within what you asked for", which is a different question.
So `mise run update` asks the other one itself, against `mise ls-remote`, and prints what is waiting
without taking it:

```
workspace      oxlint     1.81.0 -> 1.82.0

Beyond the pins, and what channel each is actually on:

mise.toml                jj         0.45.1       stable; edit [tools] to cross the pin

------------------------------------------------------------------------
Against each publisher's stable channel:

workspace      jj         0.44.0       -> 0.45.1 across a pin
workspace      pnpm       11.24.0      -> 11.26.0 held back by the pin "11.24"
workspace      rust       stable       holds 1.98.0, the channel is 1.98.1

  a pin is crossed by editing [tools]; nothing here does it for you
```

Three verdicts and three different actions: cross a pin, widen one, or let `update` run again. **The
notice goes last, after the upgrade output, and nowhere else.** It is the only part a person has to
act on, and an install log is long enough to bury it. `verify` stays offline and does not carry this
check.

**mise's `latest` is not the publisher's stable channel either.** It can sit ahead of the channel,
so `latest` is never reported as the stable release.

### What CI cannot update reaches the author as one line

**What the scheduled update cannot take is reported locally, and nothing else**, `update-reminder`
in [model/rules/toolchain.res](../model/rules/toolchain.res). `mise run pull` and `mise run check`
start, at most once a day and detached, `mise run update --all --dry-run --json`, keeping its
summary under `$XDG_CACHE_HOME/monoflake/update/` with the day each item was first seen. Reported
are an action pin, which the bot does not move ([ci.md](ci.md), "Scheduled updates"), a move only
`--major` takes, a tool the Mac has not installed at its pinned version, and any move within the
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

### Hooks are ReScript too, and a hook that cannot start says so

`hooks/` holds the policies once, in ReScript like every script here, and both vendor directories
bind the same `hooks/run.res` entrypoint; `.claude/settings.json` and `.codex/hooks.json` are only
the glue that exposes it to each harness.

**The failure mode is what the adapter is written against.** A hook is launched by the harness
rather than by an interactive shell, and one that fails to start enforces nothing while looking
exactly like one that passed -- silent non-enforcement is worse than none, because it is believed.
So the adapter line builds the entrypoint when its compiled output is missing, cleans and builds
again when an incremental build leaves it missing, and otherwise exits 1 with the reason on stderr:
never a quiet 0 over a hook that did not run. It runs `node` from the harness's PATH and `rescript`
from the workspace's `node_modules`, so a fresh clone needs `pnpm install` first.

Compatibility is a check, not a claim made once: `check workspace scripts` runs the entrypoint with
representative Claude Code and Codex payloads, and the adapter line itself through `sh`, from a
subdirectory, from inside a nested repository and from outside any.

**`hooks/bin/rm` and its guard stay Python, under `/usr/bin/python3`.** It is a command an agent
types, first on PATH, not a hook: it has to answer before anything is built, in whatever shell the
agent has, and macOS's own Python is the one interpreter always there. `Toolchain.kept` names it,
and `check workspace hooks` runs its tests.

## A Tauri app is inspected through an MCP server pinned to its plugin

`.mcp.json` at the root of this workspace declares one server, `tauri`, for inspecting a running
Tauri app through screenshots, a DOM snapshot, computed styles, JavaScript in the webview and any
Tauri command the app exposes. Chrome DevTools MCP reaches a browser tab instead. The configuration
belongs to the workspace for any Tauri project.

**Its version is not free.** The server speaks to `tauri-plugin-mcp-bridge`, a Rust dependency of
the app, over a WebSocket the plugin opens on port 9223; the two ship from one repository and are
released together. So the pin in `.mcp.json` is exact and equals the crate's version, and moving one
without the other is how a protocol change becomes a connection that opens and then answers nothing.
It is fetched with `npx` rather than added to this repository's `package.json`, because a repository
that holds configuration and nothing else should not carry a package it has no build to verify it
against -- and the exact version is already the whole claim.

It reaches an app that is already running and nothing else. A server that starts cleanly and finds
no window is the ordinary shape of a mistake here, and it reads as the server being broken rather
than as the app being absent.

A project-scoped server is approved once, by the user, in an interactive session. An agent cannot
approve one and should not try; `claude mcp list` says which state it is in.

## Workers answer on custom domains only

`workers_dev` and `preview_urls` are off everywhere, as `custom-domains` in
`model/rules/toolchain.res` holds in its `domains` part, a warning until monoflake/driver's three
Workers are bound to names. Every generated hostname is another route to
the same worker, reached without whatever sits in front of the custom domain, and nobody watches
those addresses. A route under a custom domain of our own is not a generated address, and is
allowed, but none is left. A more specific route wins over the domain's Worker only for a request
from outside: another Worker's `fetch` passing through a route does not run that route's Worker. A
scope of the API host is reached by binding.

How the platform's gateway declares its hosts and zones is platform's
`spec/architecture/gateway.md`, "The gateway declares its hosts in its `wrangler.jsonc`".

The cost is real and accepted: there is no URL to open between uploading a version and promoting it,
so a deploy is the first time the code meets production. What replaces that check is `wrangler dev`,
which runs the same code against the same bindings, plus the fact that a worker with no route
configured serves nothing until a domain is pointed at it by hand.

That last point is what makes replacing a worker safe. A first deploy under a new name is inert --
it creates the worker and attracts no traffic. Deploying over an existing worker of the same name
replaces it in place and keeps its routes and custom domains attached, so replacing one never
requires deleting it first. Nothing is deleted until whatever supersedes it has been seen serving
real traffic.

## Dev ports are pinned

Every dev server binds a fixed port and **fails when that port is taken**. Vite gets `strictPort:
true`; anything else refuses to fall back. Auto-incrementing to the next free port is never
acceptable. `ports-strict` in [model/rules/toolchain.res](../model/rules/toolchain.res) reads every vite config for it.

The reason is not tidiness. A tool that drifts to the next port starts a second instance silently,
and a second instance of something that writes to a project's data means two processes fetching and
overwriting in the same directory. The port collision is the cheapest mutex available -- the
operating system provides it for free, and it fails loudly at the only moment anyone can act on it.

## Dependency policy

### Dependencies move the way tools do

`mise run update` runs every repository's own `update` task, the workspace's included, and a name
narrows it to one. A dependency moves inside the range its manifest asks for, exactly as a tool
moves inside its pin; crossing a range rewrites the manifest, which is a decision with a diff and a
commit message behind it, exactly as crossing a pin is. So an `update` moves inside and names the
rest, and `--major` is what takes it -- handed on to a repository that supports it, refused by one
that does not.

**How a repository moves is the repository's own task, and the workspace knows none of it.** Each
repository's `update` is the whole of how it moves, and what it owes is the contract in
[repos.md](repos.md), "What a repository's task owes the verb".

**What the workspace moves alike in many repositories is declared, not called.** A repository's
`workspace.toml` names under `[update]` the workspace's movers it takes -- `packages` for its own
tools, crates and npm packages, `scripts/deps/update.res`; `actions` for its workflows' actions;
`images` for its Dockerfiles' base images; `releases`, a list of the `manifest.toml` files whose
locks are moved -- and the dispatcher runs each from the repository's root after its own `update`
task, `--dry-run` and `--major` handed on, the whole kept only where its verify passes. The
repository's own task keeps what is its alone, a flake's inputs or a Dockerfile's runtime version,
and a repository whose movers are all declared has none. A new repository takes a mover with one
line rather than a copy of the call.

**A name means that repository and nothing else.** `update rdm` runs rdm's `update` and writes
nothing outside `repos/rdm`. The workspace's `[tools]` is the one set of pins every repository reads
by walking up, so raising it is `update workspace`, the dispatcher's own half, or `update` with no
name, never a side effect of naming a project. A repository's own `update` moves the tools its own
`mise.toml` declares and nothing it inherits.

**What waits across a range is measured, not predicted.** Each resolver is asked what is still out
of date _after_ the in-range pass has run, because whatever survives that is across a boundary by
construction. For cargo that is `cargo upgrade --incompatible --dry-run`, which is cargo-edit: cargo
does not ship it and mise's registry does not carry it, so a repository uses it when present and
**names it when absent** rather than reporting a clean list that was never checked.

Vendored source is filtered out of all of this, by the repository that holds it. See
[vendor.md](vendor.md).

### A dependency is added with `pnpm add`, and a new workspace package checked in the lockfile

**`pnpm add -D <name>@<range> --filter <package>` adds a dependency**, never an edit to a
`package.json` followed by `pnpm install`. `add` resolves the dependency every time.

**A new workspace package is confirmed in `pnpm-lock.yaml` before it is pushed**: an importer under
its path, `pkgs/<name>: {}` for one with no dependencies. `pnpm install --lockfile-only` does not
write it, and a local `--frozen-lockfile` install passing does not confirm it, as CI's still
refuses. With none written, the entry goes in by hand, beside its neighbors.

### A dependency that moved while you were working is the user's upgrade

Manifests and lockfiles that changed under an agent mid-task were not changed by the task. The user
raises dependencies whenever they have time, from whichever terminal they happen to be in, and that
is the only thing that routinely rewrites those files here. So there is nothing to investigate and
nothing to attribute: carry on, and keep the change out of whatever commit the task was making,
which is what a path-scoped `jj commit` is for.

What the agent owes the change is one thing, and it is not an opinion about the versions. **Run
`verify` and say whether it still passes.** That is the whole review. A dependency diff nobody has
checked is the only failure mode available here, and checking it costs one command.

### An upgrade that breaks is reverted in the lockfile, never pinned in the manifest

The preference is plainly for the newest version of everything, and it is a preference about debt
rather than about features: a repository that stays current is never more than one release behind
the ecosystem it is written against, while one that defers is eventually a migration.

So when a raised dependency breaks something, the repair is to **put the lockfile back** and leave
every declared range alone. The range is a statement about what the code can work with, and
narrowing it to route around one bad release is a claim that outlives the release: the next reader
finds a bound with no reason attached even after the excluded version is fixed.

**`update` makes that repair itself, and it is the one half that stays in the workspace.** Before a
repository's `update` runs, the workspace records its working copy through jj; afterwards it reads
which files changed, runs that repository's `verify`, and on a failure puts exactly those files back
with `jj restore` and names the repository and the lines that failed under the summary. A failed
`update` is put back the same way, since it may have stopped halfway through a rewrite. None of that
needs to know what a resolver is, which is why it is not a repository's to repeat. By path rather
than `jj op restore`, so an edit somebody made elsewhere in the working copy while it ran survives.
What it does not restore is an installed tree: a pnpm repository's `node_modules` follows the
restored lockfile at its next install. The whole lockfile goes back rather than one family, because
which family broke is a question only a bisection answers.

A reverted lockfile makes the same repair and forgets it on purpose. The next `mise run update`
tries the range again from the top, and if the upstream has been fixed in the meantime the
repository simply moves. Nobody has to remember to lift anything, which is the part a manifest pin
gets wrong. For Cargo that is a lockfile pin at the version that worked, no manifest constraint and
no `[patch]`; the rule is the same in every ecosystem here.

What carries across the gap is the user's own memory of what broke, and the retry is theirs: they
come back to it after a few days and run the same flow again. An agent's part is to say what failed
and how, not to build a record of it.

### A cache is what a tool can write again, and nothing else is

`mise run clean` runs every repository's own `clean`, or one named repository's. What each removes
is the repository's to say, because a cache belongs to the tool that writes it and a repository is
what chose its tools. The line every one of them draws is the same, and it is what makes `clean`
safe to run without thinking first:

- **Dependencies are not caches.** `node_modules` stays exactly as installed and only what tools
  dropped inside it goes -- `.vite`, `.vite-temp`, `.cache`, `.vitest`. A clean that ends in a
  reinstall is not a clean, it is a network bill. The same holds for `~/.cargo/registry` and
  `~/.cargo/git`, and pnpm's store is the machine's rather than any repository's, so no `clean`
  prunes it.
- **Local state is not a cache.** `.wrangler/state` is a local D1, KV and R2 emulation -- rows
  somebody typed, not output somebody built -- so only `.wrangler/tmp` goes.
- **cargo owns its own output.** `cargo clean` is what empties the target directory. `[build]
  target-dir` can move it anywhere, so a sweep matching the word `target` would miss the real one
  and find somebody else's. A test may leave a directory read-only under `CARGO_TARGET_TMPDIR`, as
  the platform's container driver does for a secret's, which stops `cargo clean`, so `clean` makes
  that directory writable first.
- **ReScript's output goes as well.** Each `lib/` beside a `rescript.json` and every `*.res.mjs`
  compiled in place is removed, since every task builds them again before it runs. The workspace's
  own `clean` takes its own and leaves `repos/` to each repository's.

**What gets removed is decided twice, by a name and by version control.** A path a `clean` sweeps
has to be one its tools write _and_ be ignored by the repository _and_ have nothing tracked
underneath it. Neither half is enough on its own: web ignores `build/` and tracks four records under
`data/build/` that a site-only CI job cannot regenerate, so a name alone would delete them -- while
"everything git ignores" is `node_modules`, `.env`, a photograph library and that local database.
**A sweep stops at every repository boundary that is not its own**: a directory carrying a `.git` or
a `.jj` is somebody else's to clean.

### A package at two majors is a warning unless it is allowed

**Out of date is judged by the newest copy the workspace holds, not by each package's.** `update
--dry-run` asks pnpm what is outdated and what every package holds directly, and calls a package
behind only when its newest copy anywhere here is older than the registry's latest. One already on
the latest somewhere while another package keeps an older major is not behind: it is two majors at
once, which is reported apart, as a warning.

**`versions.toml` allows a pair, with the reason.** Its `[several]` names each package that may hold
two majors and why, as a transition somebody chose; the report then lists it without the warning,
and `update --major` crosses only what the report calls behind, so an allowed pair is never
collapsed by it. A line the workspace no longer needs -- one major left -- is reported for removal.
The report is each repository's `outdated` task, run from the workspace's
`scripts/deps/outdated.res`.

### A package version waits a day before it can be installed

`pnpm-workspace.yaml` sets `minimumReleaseAge: 1440` -- a package version must have been public for
24 hours before it can be installed, transitive dependencies included. Most npm compromises are
found and yanked inside that window. `release-age` in
[model/rules/toolchain.res](../model/rules/toolchain.res) reads it in every pnpm repository.

`minimumReleaseAgeExclude` holds the exemptions. Keep the list short: every entry is an accepted
risk, justified only when the wait costs more than it protects.

### An outside action is pinned by commit, the author's own taken at `main`

A workflow names each action from outside by the commit a release tag points at, with the release
beside it as a comment: `uses: actions/checkout@3d3c42e5... # v7.0.1`. A tag can be moved to other
code after the fact; a commit cannot. An action of the author's own, any owner `repos/registry.toml`
lists, is inside the boundary and trusted, so it is taken at `main`, as the workspace's
`canmi21/canmi/.github/actions/workspace@main` is, and a change to it reaches every repository's
next run with no pin to move. The workflows part of check holds both, and runs actionlint, with
shellcheck over each step's shell, on every repository's workflows. A value a workflow passes that
is itself a release of some repository, such as the Nix an installer action installs, carries that
repository as its comment, `installer-version: 2.35.3 # NixOS/nix-installer`, so it is moved the
same way.

A repository with workflows declares `actions = true` under `[update]`, and the workspace's own
action is moved by the workspace's `update`. `scripts/deps/actions.res`, reading each workflow and
each composite action at `.github/actions/<name>/action.yml`, moves each pin to the newest release
that has been public for a day -- the same wait as `minimumReleaseAge` -- within its major, or
across it with `--major`, following an annotated tag to its commit. A release still inside its first
day, or past the major, is named and left. A repository of the author's own that a workflow checks
out is pinned by the commit, the branch it follows beside it, `ref: 0ae9cea1... #
monoflake/platform@main`, and moved to the branch's head with no wait, as the author's own is
trusted; RFC x6hf9. The move is local: it is reviewed and pushed by hand, as every `update` is, and
no workflow moves its own actions. A repository with `.github/release/bump.res` has its `bump` run
after a workflow is written, so a moved pin of what it builds from raises its version, RFC 8c0rg.

### A task in CI says what it is doing

A task that runs in CI for more than a minute prints each stage as it starts and as it ends, with
its counts and its elapsed time, in plain lines, never a spinner and never a silent stretch: a log
that sits still for ten minutes cannot be told from one that hangs. `ci-progress` is `Pending`,
since only a run's log shows how long a step said nothing.

### A Dockerfile's base images are pinned by digest and moved by `update`

A Dockerfile names each base image by its tag and the digest the tag named when it was pinned, `FROM
busybox:1.37.0-glibc@sha256:42a9...`, so a build takes the same base until somebody moves it, and a
tag republished with a security fix is taken by a move rather than by chance. A repository with
Dockerfiles declares `images = true` under `[update]`, and `scripts/deps/images.res` finds every
file named `Dockerfile` below the repository, passing over what a tool wrote or a checkout holds,
asks each tag's registry for the digest it names now, by `HEAD` with the anonymous token the
registry's challenge asks for, and moves the pin where it changed, the tag kept. A tag moved to
another version, as busybox from 1.37 to 1.38, is an edit by hand. No day is waited out, since a
registry records no time a digest was published. `images-pinned` in
[model/rules/toolchain.res](../model/rules/toolchain.res) refuses a `FROM` with no tag and digest.

### What one repository takes from another's releases is locked beside a manifest by `update`

Where a repository takes an artifact another of the author's repositories releases, as
`monoflake/machine` takes `monoflake/runtime`'s images, it pairs the two files a package manager
does, `Cargo.toml` and `Cargo.lock`. A `manifest.toml`, written by hand, names the source repository
and lists what is taken from it. A `manifest.lock` beside it, written by `update` alone, holds for
each artifact its version, the release it came from, and each system's address and SHA-256, the
system named as Nix names it, `x86_64-linux`. Both are TOML, since Nix reads TOML itself,
`builtins.fromTOML`, and TOML takes comments: the lock opens saying who writes it, and each
artifact's release is linked above its table. The repository names the manifest under `[update]`'s
`releases`, and `scripts/deps/releases.res` is run with it; a scheduled workflow may run it too. It
reads the source's published releases, takes the highest version an archive is named by, and locks
it only once that release's `manifest.json` lists it, each address the release's own download and
each hash the manifest's. The source holds the delay already, a runtime released a day after
upstream, so none is waited out again. A table in the manifest naming its own `source` and one list
takes that list from that repository, as `monoflake/machine`'s `[driver]` takes `driver-machine`
from `monoflake/driver`, and each pin it locks records its `source`. A source with any name whose
releases cannot be read keeps all its pins as they were, moving none of its names, while the others
are written, and the run exits 2 naming it, which `update` keeps and warns of; it exits 1 and writes
nothing when no source was read.

### A release is the workspace's script, each repository building what it releases

A repository that releases on GitHub declares `[release]` in its `workspace.toml`, read by
`scripts/change/project.res`: `built`, the path of the `built.json` its own build writes, and
`columns`, the head of the notes' table. Its build stays its own, runtime's images or the driver's
archives, and names each artifact in `built.json` with its `name`, `version`, `commit`, each asset's
`target`, `kind` and `path`, an image's `digest`, the fields that are its alone, and its `row` in
the table, where `{release}` stands for the day's tag. `scripts/release/release.res`, run as the
repository's `release` task, does the rest: a UTC day's release, `2026.10.22`, drafted whole and
published last when new, or added to when it stands, each file uploaded with `--clobber`, then one
`manifest.json` merged and uploaded, each entry carrying its row, and the notes' table, newest row first, rendered from
it last, on every run that touches the day, one with nothing new among them, so notes a failed edit
left short are made whole by the next run and none is doubled. A failed read of another day's
manifest skips that day's notes with a warning and leaves the released run green. An artifact counts
as released only once a published release's manifest lists its version, and `release listed` prints
every one so a build can skip what is out. Every manifest has one shape, `{release, artifacts}`,
`scripts/release/manifest.res`; the compatible shape `{release, runtimes}`, with each entry's
`runtime` for its `name`, is read and rewritten in the one shape the next time its day is added to.
RFC 8c0rg.

### An advisory in a development-only dependency is not a production one

Where a vulnerable package runs decides how much it costs. A deployed Worker uses workerd's own
fetch and never loads the HTTP client its build tooling depends on; a bundler plugin's glob matcher
never sees a request. Fixing those clears an alert list, which is worth something -- a list nobody
can read is a list that hides the next real one -- but it is not the same work as patching something
on the request path, and a security fix that says which of the two it is saves the next reader from
having to re-derive it.

That ranking decides how much risk a fix may carry. Forcing a patch across an exact upstream pin is
reasonable for a clean list and unreasonable if it can break a build; where an override does that,
its comment says what was verified afterwards.

## Default stacks

| Area                      | Stack                      |
| ------------------------- | -------------------------- |
| Binaries and applications | Rust + Cargo               |
| Web                       | TypeScript + pnpm + Svelte |
| Scripts and tasks         | ReScript                   |

These are defaults, not a whitelist. Reaching outside them is a structural decision and belongs to
the user -- see [agent-protocol.md](agents/agent-protocol.md).

### A script is ReScript, compiled before it runs

**A task, a tool or a hook of the workspace's is ReScript**, under `scripts/`, `hooks/` and
`model/`, compiled to `.res.mjs` beside its source by `mise run build`, which every task running one
depends on, and never committed -- RFC 17b3o. A mise task is the entry, and the script behind it
decides the order: **a task runs `Toolchain.taskLines` lines at most**, and past that it is a script
with the task its one line. `each` runs from `scripts/workspace/each.res`.
**No script is written in Python**, and the settings part holds the tree to it: `Toolchain.kept`
names the exceptions, `hooks/bin/rm` and its guard among them, which is a
command an agent types rather than a script, and stays as it is.

**A task is named by one word, and nested by spaces**: an action is the task's first argument, as
`mise run lane open`, `mise run repos list` and `mise run check workspace words`, never a name
joined by a hyphen. A command so read is declarative, a tree of nouns and the actions on them, and
one task holds every action of its noun. `task-nested` in `model/rules/toolchain.res`; canmi/web's
and seam's tasks wait for their repositories, the deferred `task-names-nested-rest`.

**A Cloudflare resource made with a place asks the author where**: an R2 bucket's location hint or
jurisdiction, a D1 database's location, a Durable Object's location hint, a Worker's placement, and
whatever else Cloudflare places by region. Where the author cannot be asked, Western North America
(R2's `wnam`, or its equal) or Asia-Pacific (`apac`) alone is chosen, by where the resource's
readers and writers are at the time. A place is never left unset: Cloudflare then places the
resource near the caller, and R2 never moves a bucket after, monoflake/platform's
docs/lessons/cloudflare.md, "Where R2 places a bucket". `cloudflare-placed` in
`model/rules/toolchain.res` holds the D1 databases and R2 buckets a script or task makes;
`cloudflare-placed-rest` waits for the rest, a create by the API, a jurisdiction, a Durable Object's
hint and a Worker's placement.

### A Rust CLI parses with clap, and wears cargo's colors

Arguments are declared as types with clap's derive API rather than read out of `std::env::args` by
hand. Unknown flags and invalid values are refused. Dependency count is not a constraint for a local
binary, [code.md](code.md).

Help is clap's own, styled with `anstyle` to cargo's palette -- green headings, cyan literals. Not
clap's defaults: this stands next to `cargo` in the same terminal, and one constant saves its reader
a second color language.
