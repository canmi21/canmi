# CI

## A build's cache follows where it builds

Decided by the author on 2026-10-31 for this workspace and the `monoflake` repositories. The rules
are `model/rules/toolchain.res`, the `ci-` ones.

**Rust that Nix builds is built with crane**, with its dependencies as a derivation of their own.
When only the crate's own source changes, the dependencies come from the store and only the crate is
compiled again. `rustPlatform` compiles every dependency again on any change, and on a two-core Arm
runner that is minutes: `machine-update` took 343 s cold there and 54 s on x86_64. The dependencies'
derivation is needed only at build time, so it is not part of any system's closure and never goes
to a bucket. It stays in the store of the runner that built it.

**A workflow that runs cargo on a GitHub-hosted runner uses `Swatinem/rust-cache`**, whose cache
lives in the repository's GitHub cache. The free allowance is 10 GB per repository, not per account
or organization, evicted least recently used and after seven days unread. On 2026-10-31 the largest
user was monoflake/cloud with 3.4 GB, almost all of it mise's tool cache. A public repository has
GitHub-hosted runners only, since the self-hosted runners admit no public repository,
[repos/monoflake/cloud/docs/runner.md](../repos/monoflake/cloud/docs/runner.md). It has them free,
so a public Rust repository runs the four Rust steps there: `cargo fmt`, `clippy`, the tests and
`cargo deny`. monoflake/machine's check runs those four steps beside monoflake/driver's build.

**A job on a self-hosted runner keeps its caches on the runner, never in the GitHub cache.** The
runner's disk persists between jobs, so uploading a cache only to download it again on the same
machine spends time and allowance. That includes mise's tools, which already persist on the runner,
so the workspace action turns `jdx/mise-action`'s cache off there. A cache a job can write and the
next job reads is the same trust the author accepted for the runner's tools in RFC obvjb: only the
author's private repositories reach those runners.

**Every cache on a runner has a bound, so nobody clears one by hand.** The Nix store is collected
when the disk runs short, at the free space each runner's configuration names. A compiler cache or
a target directory put on a runner gets a size cap of its own, such as `SCCACHE_CACHE_SIZE`, or an
age after which systemd-tmpfiles removes it. The Arm runners' disks are 50 GB.

## CI orchestrates, the scripts do the work

Decided by the author on 2026-10-31 for every workflow of this workspace and the `monoflake`
repositories. The rules are `model/rules/toolchain.res`, `ci-native-steps`, `ci-entries` and
`ci-shell-minimal`.

**A workflow is built from native steps, one stage a step**, so GitHub times and shows each stage
apart, and a published action is taken where one fits rather than written again in a step. One step
that runs a whole pipeline hides which stage was slow or failed: monoflake/cloud's systems job ran
its plan, build and upload as one step until 2026-10-31, and a cold build looked like a hang.

**A step calls an entry the repository already has**, a mise task or a script, so the same entry
runs on the Mac. The workflow decides the order, the runners, the secrets and the conditions; what
a stage does lives in the entry, where it is tested and run locally before CI ever runs it.

**A step's shell is the call and its plumbing alone**: the entry's name, its arguments, and passing
outputs between steps. Logic, a loop, a parse, a retry, goes in the entry, in ReScript, which is
type-checked, tested, and runs the same on the Mac as on a runner.

## Scheduled updates

Every repository being worked on calls
`canmi21/canmi/.github/workflows/update-repository.yml@main` from its own
`.github/workflows/update.yml`, daily at 22:00 UTC and by hand through `workflow_dispatch`.
The reusable workflow takes `path` for the registry path, empty for the workspace, `runner` for
the runner labels as JSON, `nix` to install Nix, and `beside` for the repositories the check reads.
`prepare` runs an entry before the update, `message` replaces the shared commit message builder,
and `wake` names the workflow to dispatch on main when the preceding stages succeed. Public
repositories use hosted runners; monoflake/cloud uses its self-hosted ARM64 runners.

The update verb keeps its one-day release wait. What moves passes the repository's check before
github-actions[bot] commits it and pushes straight to main. The named check is woken explicitly
because a token's push starts no workflow. A failure before the commit pushes nothing; a release
source whose releases could not be read is held back and fails the run after the other updates
are committed, naming the held source.
