# Application tooling

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
acceptable. `ports-strict` in [model/rules/toolchain.res](../../model/rules/toolchain.res) reads every vite config for it.

The reason is not tidiness. A tool that drifts to the next port starts a second instance silently,
and a second instance of something that writes to a project's data means two processes fetching and
overwriting in the same directory. The port collision is the cheapest mutex available -- the
operating system provides it for free, and it fails loudly at the only moment anyone can act on it.

## Cloudflare is worked through cf, Wrangler kept where a project still needs it

**An account's resources are worked through Cloudflare's `cf`, by the author's word**: a D1
database's export, query, creation and listing, an R2 bucket and its objects, a Worker's versions and
deployments read, its secrets listed, DNS, zones and tokens. `cf` signs in on its own, apart from
Wrangler's login, names a resource by its id rather than a configuration's name, and reads no
`wrangler.jsonc`, so a D1 migrations directory is passed as `--dir`. A project pins it under its
`mise.toml`'s `[tools]` as `"npm:cf"` at npm's newest, its update following npm's `latest`,
[dependencies.md](dependencies.md).

**Wrangler stays where a project still needs it, and is never removed while it does.** SvelteKit's
Cloudflare adapter reads `wrangler.jsonc` and Wrangler's platform proxy, and `cf dev`, `cf build`
and `cf deploy` read only a `cloudflare.config.ts`, so a SvelteKit project keeps Wrangler for its
development server, its local D1 in `.wrangler/state`, which `cf`'s own local state is not, its
build, its deploy with the migrations it applies, `wrangler types`, and the two commands `cf`
lacks, `secret put` and `tail`. A project moves to `cloudflare.config.ts` by `cf migrate` only once
everything it builds with reads one.

**What the local command line does to the platform is retired, not moved.** A script that installs
or deploys monoflake's driver through Wrangler stays as it is until the console operates the
platform through its online API, which replaces it.
