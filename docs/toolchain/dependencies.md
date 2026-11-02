# Dependency policy

### Dependencies move the way tools do

`mise run update` runs every repository's own `update` task, the workspace's included, and a name
narrows it to one. A dependency moves inside the range its manifest asks for, exactly as a tool
moves inside its pin; crossing a range rewrites the manifest, which is a decision with a diff and a
commit message behind it, exactly as crossing a pin is. So an `update` moves inside and names the
rest, and `--major` is what takes it -- handed on to a repository that supports it, refused by one
that does not.

**How a repository moves is the repository's own task, and the workspace knows none of it.** Each
repository's `update` is the whole of how it moves, and what it owes is the contract in
[repos.md](../repos.md), "What a repository's task owes the verb".

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
[vendor.md](../vendor.md).

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
[model/rules/toolchain.res](../../model/rules/toolchain.res) reads it in every pnpm repository.

`minimumReleaseAgeExclude` holds the exemptions. Keep the list short: every entry is an accepted
risk, justified only when the wait costs more than it protects.

### A dependency is added and removed by `mise run dep`, never by hand

`mise run dep add <repository> <package> [--dev] [--rust] [--in <member>] [--dry-run]` adds a
dependency to a repository's `package.json` through pnpm, or with `--rust` to its `Cargo.toml`
through cargo, `--dev` choosing the dev section. It writes the newest stable version that has been
public for a day, the wait above, in the form most of the repository's ranges take: `^`, `~`, an
exact pin, and for a crate bare or `=`. A package the repository already has is refused, naming
`mise run update`. Where a repository gathers several members, `--in` names the member, and one
outside the repository is refused. `dep remove` takes one out, finding its section itself, and
`--dry-run` prints the command and writes nothing. The task is `scripts/deps/dep/dep.res`.

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
