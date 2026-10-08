# Three layers, and the library under them

The author's system is three layers and the author's shared library under all of them, each its
own repository: `canmi21/lib`, `monoflake/infra`, `monoflake/platform` and `canmi21/web`. They
were one repository, `canmi21/lattice`, until the split recorded in web's
`spec/todo/milestones.md`, F. This file is the picture of all four, kept in the workspace because
it is every repository's; each cites it rather than keep a copy.

## Four places, and which way they lean

**A layer depends on the ones below it and never on one above** -- except where it works without
the one above, and only leans on it when it is there. A node keeps a way in that needs nothing above it: the tailnet, by SSH and by a
task on the author's machine that speaks host's API, so the layer that brings everything back can
be reached when what it brings back is down; the console at the edge may lean on the platform's
accounts, because a node never depends on it. A dependency that cannot
fail away is a cycle, and the rule forbids it. From the bottom:

- **lib** is the author's own code that depends on nothing else of theirs: the design system,
  generic browser and server utilities, the addresses of their own sites and the world's addresses
  anyone could use. It is not a layer of the system, and it is under every layer of it.
- **infra** is what bootstraps the rest and so cannot be managed by it: host and keeper, which
  deploy each other, the meter, Caddy, the tunnel and the resolver.
- **platform** is the services infra runs for everything above: the gateway and `quota`, the CDN
  and the alias layer, storage and databases, the scheduler, the ledger, capture, probing,
  telemetry, and `apt`, the Linux machine's own capabilities offered as a service.
- **services** is what runs on the platform: the site and its API, the editor and `local`, the
  status page, and the service domains' pages, `landing`. This repository is that layer.

The status page is a service and not the platform's, though it shows the platform: it is a page
built from the site's own libraries, and the probe and the schema it reads stay in the platform.

## Managed from above, restored from below

**Every day goes through the top, and a disaster through the bottom.** A layer may be managed from
the one above it -- the platform schedules a backup, lists it, shows it in the console -- since
that leans on the layer above only while it is there. What restores a layer may not: a restore is
needed precisely when what is above is gone. So a backup is kept beside its layer or below it,
never above, and what is above holds at most a pointer to it.

- **Configuration is git.** What is declared -- the nodes, every `service.toml`, these specs -- is
  in repositories no layer of ours runs, with its history.
- **Secrets are git too**, encrypted by sops to an age key the author holds outside every machine.
- **Infra is rebuilt, not restored**: `mise run node` and what CI built bring a node back.
- **State is in databases and buckets, backed up to a provider's store directly**, never through a
  bucket of the platform's, whose index is in the database being backed up -- platform's
  `spec/architecture/databases.md`, "Backups are the data, kept off the cluster".

**So a disaster is undone from the bottom, each step needing only the ones before it**: the age
key opens the secrets; the nodes are set up from git; the platform is deployed from CI; the
database is restored from its store; the buckets' indexes come back with it, their bytes already in
their stores; every scope runs again.

**The way back is kept walkable.** Its pieces -- the age key, the secrets, SSH over the tailnet, a
provider's console when the tailnet is down, the raw backups -- are few and plain on purpose, and a
backup counts once it has been restored, not once it was uploaded.

**A copy kept above for looking at is not a backup.** An export of a layer's state, encrypted to the
author's key, may be kept anywhere -- the author's own scope included -- to read how something was
configured long after, while everything works; nothing restores from it. It is open -- platform's
`spec/issues/scheduling.md`, "Exports to look at, kept apart from backups".

Decided on 2026-10-07.

## Cloudflare is under the platform, and an app binds only the platform

**An app depends on the platform, and the platform on Cloudflare** -- never an app on Cloudflare
beside the platform, which is the diamond the site stands in today. An app is deployed through the
platform and handed its bindings by it, and **the platform exports everything a binding can be, at
one level**: every capability Workers already have -- a Durable Object, KV, R2, D1, a queue --
passed through, and its own services beside them, an IP lookup or a capture as much a binding as a
Durable Object. An app declares to the platform what it wants, both kinds alike, and never names
Cloudflare; the platform resolves each to Cloudflare's product or its own.

**A Worker's own code holds no state; what holds it is a binding.** A stateless function, a page
rendered at the edge, static assets and the edge cache -- what can be computed again if lost -- run
on Workers, because nothing is nearer a reader. What holds state is something the app binds through
the platform: its Postgres, its buckets, its scheduler, a WebSocket service on the nodes, or one of
Cloudflare's own passed through. Where the platform has its own, the app's own data goes there --
a database is Postgres rather than D1 -- and a Worker reaches the nodes over Workers VPC, which
carries HTTP, TCP and WebSockets.

**Cloudflare's products reach an app only through the platform.** A binding is the platform's to
resolve: a bucket may keep a copy in R2, a declared Durable Object may be Cloudflare's or a service
of the platform's that answers as one. So an app does not change when the platform changes a
provider, nor the platform when an app moves. The direction is platform's `spec/roadmap.md`; what is open, its
`spec/issues/scheduling.md`.

## The directory is the layer

**Each layer is a repository, and each keeps `apps/` for what is deployed and `libs/` for what is
imported** at its top level; lib splits by registry instead, `pkgs/` and `crates/`. A layer is read
for what it does, so a deployable and a library are the split that matters there, whatever
language each is in. A dependency cannot point up any more: a layer above is another repository,
reached only through what it publishes, and nothing below installs it.

Before the split the layers were directories of one repository, `infra/`, `platform/` and
`services/`, and a `layers` task failed on a dependency that pointed up. The repository boundary
holds that rule now.

## A scope says whose it is

- **`@monoflake/*` is infra and platform**: the system that bootstraps itself, named for the
  GitHub organization and the npm scope both layers publish from.
- **`@canmi/*` is services and lib**: the author's own, on top of the system and under it.
- **A package's name is its scope and its directory's name**, unique within the scope. Where one
  concept lands in two layers of one scope, each is named for what it holds rather than given a
  layer prefix: the platform's addresses are `@monoflake/sdk`, infra's are `@monoflake/urls`.
- **A crate has no scope**, so its name is unique within its Cargo workspace.
- **Every name sits under a scope the author owns**, published or not. An unscoped name, or one in
  a scope somebody else can register, is one a stranger can publish first and a misconfigured
  install will fetch.
- **The author's facts are `@canmi/me` on npm and `canmi` on crates.io.** The bare name was the
  plan for both, and npm refused it as too near `wagmi` and `vanli`; crates.io took it. A crate
  has no scope, so a name is all the namespace it has, and `canmi` is the author's there.

## Who owns what

| Repository           | apps                                                                                                            | libs                                                               |
| -------------------- | --------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| `canmi21/lib`        | --                                                                                                              | me and canmi, ui, kit, web, response, whereabouts, axum-governor   |
| `monoflake/infra`    | host, keeper, meter, caddy, tunnel, resolver                                                                    | deploy, urls                                                       |
| `monoflake/platform` | gateway, quota, cdn, aka, hook, geo, objects, postgres, ledger, cron, apt, shot, probe, telemetry, gemini, grok | sdk, probe, ledger                                                 |
| `canmi21/web`        | site and its API, cms, local, status, landing                                                                   | prose, compile, collection, messages, social, hints, fonts, robots |

`geocode` took `geo`'s address lookup in beside the coordinate one and is published as
`whereabouts`: one crate answering where something is, each lookup behind a feature, the data
directory the caller's. Fetching the data stays in platform's `geo`, an operational choice and not
a library's, and so does the credit GeoLite2's license asks an answer to carry.

## The platform publishes the sdk and the probe's schema

What the services read of the platform is published, since they are another repository, and cut
the way the library is: where installing one changes what it brings. **The sdk is one package**:
the addresses at its root and every small part behind a subpath of its own --
`@monoflake/sdk/artifacts` (with `/artifacts/types` and `/artifacts/anchors`), `/cache`, `/imgsrc`,
`/limits`, `/store`, `/symlink`. What every host says in its robots.txt and security.txt is the
library's, `@canmi/me/robots`. Each is a client of a platform service or one of its policies, and none brings more
than valibot or `@canmi/response`, so one name says them all. **`@monoflake/probe` is the status
database's schema**, the probe's records, alone because it brings drizzle. `ledger` is Rust, and
read by nothing outside the platform. Infra publishes `@monoflake/urls` alone.

## The library is five packages, split by what installing one brings

The fourteen libraries that were the author's own became five npm packages, each part behind a
subpath of its own -- `@canmi/kit/motion`, `@canmi/me/urls` -- cut where a consumer's cost changes:
what a package drags in, where it can run, and whether a Rust crate has to move in step with it.

| Package           | Holds                                                               | Brings                 | Runs              | Rust       |
| ----------------- | ------------------------------------------------------------------- | ---------------------- | ----------------- | ---------- |
| `@canmi/me`       | the author's addresses, their identity, the languages they write in | nothing                | anywhere          | `canmi`    |
| `@canmi/kit`      | theme, tokens, motion, behavior, units: the design foundation       | svelte, StyleX, motion | a browser, Svelte | --         |
| `@canmi/ui`       | primitives and svg-canvas: what is composed from it                 | --                     | a browser         | --         |
| `@canmi/web`      | compat, referer and sentry: running a SvelteKit app in public       | core-js, Sentry        | a SvelteKit app   | --         |
| `@canmi/response` | the answer envelope's TypeScript half                               | nothing                | anywhere          | `response` |

`@canmi/me` is what the platform reads when it needs the author's sites, so it carries no
dependency a Worker would mind. `@canmi/kit` brings `motion`, the library that was Framer Motion,
and it is the only thing anything here animates with -- Svelte's own motion is not used; see lib's
`spec/kit/motion.md`. `@canmi/web` is the heaviest and the least shared, so a page that
only wants the design does not install Sentry. How each is built, versioned and published is lib's
`spec/repository.md`.

## Addresses are split by who owns the name

The one URL map the single repository had is three packages. An address goes with whoever owns the
name, not with whoever reads it: `canmi.net` is the author's even where the platform probes it, and
`api.monoflake.com` is the platform's even where the site calls it.

| Package           | Rust        | Holds                                                                                                                                                                     |
| ----------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `@canmi/me/urls`  | `canmi`     | the author's sites and identity; the world's addresses -- GitHub, the registries, SPDX, the social bases, analytics and fonts; the path and loopback functions            |
| `@monoflake/sdk`  | `monoflake` | the API host on both sides, the gateway's names, the CDN, the alias hosts, `canmi.app`, the ledger, cron and capture, the status page's names, the platform's own mirrors |
| `@monoflake/urls` | --          | host's door, keeper, host's own address and the private suffix                                                                                                            |

The sdk composes the three into the one map everything above infra reads, so a caller asks one
place and the Rust mirror keeps its names; infra reads `@canmi/me` and its own package directly,
since it may not read the platform's. Each owner generates its Rust half from its own TypeScript --
lib's `mise run urls` writes the `canmi` crate, the platform's writes `monoflake` -- so an address
is written once and never across a repository boundary.

## What the package graph cannot see

A dependency through an address or a name written into code is invisible to `package.json` and
`Cargo.toml`. Four pointed up before the split, and each was fixed by the declaration pattern
`service.toml` already uses -- the layer above says what it is, the one below reads the saying:

1. ~~host knows the platform's apps by name.~~ It knows roles: an app asks for one in its
   declaration and the node grants it in `GRANTS`. See infra's `spec/architecture/host.md`, "A
   role is asked for by the app and granted by the node".
2. ~~host renders Caddy's routes and the resolver from the platform's `GATEWAY_*`.~~ Neither names
   the gateway's hosts at all: the house stopped being an entrance -- platform's
   `spec/architecture/gateway.md`, "Inside a node, its own services answer locally".
3. ~~The panel reads `cron`'s and the ledger's addresses to show them.~~ The panel retired; the
   console, a layer above, shows the platform's services, since a layer above may read the one
   below and the reverse is what this list exists to end.
4. ~~The deploy crate reads `URLS.source`.~~ A node deploys from the repositories its
   `DEPLOY_SOURCES` lists, and each notice names its own. See infra's `spec/architecture/host.md`,
   "The machine pulls; nothing pushes into it".

## The split

**History is shared, not rewritten.** The three repositories continue from the same commit, each
deleting what is not its own, so every signed commit keeps its signature. GitHub counts a commit on
its author date and by repository, so the history before the split shows three times on the
contribution graph and nothing lands on the day of the split; the history was judged worth more.
web is `canmi21/lattice` renamed, so its stars stayed with the site they came for.

**The order was layers, the library, then the split.** Everything but the seven apps Cloudflare and
Vercel build moved under its layer first, beneath them: their builds named only their own
directories, so they kept deploying throughout. They moved at the split, when the repositories they
build from changed anyway and each build was pointed once. The author's account keeps two
monorepos, `lib` and `web`; a desktop application keeps a repository of its own, as rdm and still
do, and reads `canmi` and `monoflake`.

## Versions

- **A package the author mostly consumes is dated**: `@canmi/me` and `canmi`, `@canmi/kit`,
  `@canmi/ui`, `@canmi/web`, `@monoflake/sdk`, `@monoflake/probe` and `@monoflake/urls`, versioned
  `YYYY.MDD.N` and published by a push that changes one -- lib's `spec/repository.md`, "Versions and
  publishing", holds the scheme. A consumer names every package `^`, dated or semver: the lockfile
  pins the exact one and `mise run update` moves it. For a dated package `^` spans the year, so the
  first release of the next is crossed by `update --major`, once a year and on purpose.
- **A package meant for strangers is semver**: `response` in both languages, `axum-governor` and
  `whereabouts`, published by hand until each has a pipeline of its own.

## A package is named for what it is, and published once it has proved itself

**A new package is named for what it does, with no thought for which names a registry has free.**
It runs first in the repository that needs it, deployed on our own machines and used in
production, for as long as the author judges it needs to. Publishing is a decision the author
makes and not a milestone: it comes once the package has run in production long enough to be
trusted and the status page shows that to anyone. Then, and not before, a public name is chosen
against what the registries hold, the package is moved into the library's repository under it, and
published.

**A semver package's first published version is 1.0.0**, whatever it was called before. It has
been in production by then, which is what 1.0.0 says; a 0.x would only defer a judgment of when it
is stable that no rule can make, and a major number is cheap afterwards. `response`, the author's
own already, went on to 2.0.0 on its own line, the same envelope with the design it has now.

## Publishing

- **How a package is published** -- `pnpm pack` and `npm publish` of the tarball through trusted
  publishing, crates through `rust-lang/crates-io-auth-action`, each first version by hand -- is
  lib's `spec/repository.md`, "Versions and publishing"; infra and the platform publish theirs the
  same way, each from its own `release.yml`.
- **A publish is read from the run, not from the registry, for its first minutes.** npm answers
  for a new version only once its CDN has caught up, a minute or two after `npm publish` returned:
  until then `npm view` says the old version and the new one is a 404, though it is published.
  The run's own lines are the evidence -- `+ <package>@<version>` from npm and the tag the release
  pushed after it -- and a check that waits on the registry gives it a few minutes before calling
  anything lost. Twice on 2026-10-08 a successful release looked failed this way.
- **A consumer of the author's takes every package from its registry, never from git**: what a
  stranger installs is what runs here first, so a package published broken breaks here before
  anywhere else, and nothing is built in the consumer. The author's own scopes, `@canmi/*` and
  `@monoflake/*`, are exempt from the day's wait `minimumReleaseAge` imposes, which would hold back
  a change made in another repository and released there.
- **Across repositories during development** a dependency comes from Verdaccio, as a local
  prerelease `-local.N` so it never shares a version with the registry's copy, and a crate through
  `[patch]` in a `.cargo/config.toml`. The lib repository serves it, `mise run registry`, and
  publishes to it, `mise run release --local`; `mise run lib-local` in a consumer pins every
  `@canmi/*` package to its newest local version and patches each crate to `../lib`, copying each
  file it rewrites to `.local/lib/` first. `--off` puts them back, and `verify` refuses to pass
  between the two, so a local version never reaches a commit.
