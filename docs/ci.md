# CI

## Writing a workflow

A workflow follows these, each a rule in `model/rules/toolchain.res`.

- A workflow is native steps, one stage a step, and a published action where one fits:
  `ci-native-steps`.
- A step calls only a mise task a person also runs, or a CI-only entry under `.github/<purpose>/`
  in ReScript: `ci-entries`.
- `pnpm install` and `pnpm exec` are plumbing, and `sudo`, `mise exec --` and `nix shell --command`
  are judged by what they wrap: `ci-entries`.
- A step never calls a script in `scripts/` by path, and never `npx` or `sh -c`: `ci-entries`.
- A step is one shot, with its orchestration in the entry: `ci-shell-minimal`.
- A step's `name:` capitalizes its first word only: `step-name-capital`.
- A schedule is nominal, and `workflow_dispatch` is how to run now: `schedule-nominal`.
- Caches go by runner kind, crane for Nix builds, `Swatinem/rust-cache` on a hosted runner and the
  runner's own disk on a self-hosted one: `ci-crane`, `ci-rust-cache`, `ci-runner-local`.

`ci-native-steps` is held by the `ci-steps` part, a warning until the workflows that break it are
rewritten. `ci-entries` and `ci-shell-minimal` are held by the `ci-shell` part and are of the form
layer, so they warn in a lane and refuse a commit onto a main line,
[agents/checking.md](agents/checking.md). The commands an entry or its plumbing may be are
`Toolchain.entryCommands` and `Toolchain.plumbingCommands`, and a step excused from
`ci-shell-minimal` is named, with why, in `Toolchain.shellExempt`.

## CI orchestrates, the scripts do the work

These rules apply to every workflow and composite action of this workspace and the `monoflake`
repositories and are named in `model/rules/toolchain.res`, `ci-native-steps`, `ci-entries` and
`ci-shell-minimal`.

**A workflow is built from native steps, one stage a step**, so GitHub times and shows each stage
apart, and a published action is taken where one fits rather than written again in a step.

**A step calls an entry the repository already has**, one of two kinds: a mise task a person also
runs, as `mise run verify`, or a CI-only entry under the repository's `.github/`, in a directory
named for what the workflow does, as `node .github/update/stage.res.mjs`. `pnpm install` and
`pnpm exec` are plumbing, and `sudo`, `mise exec --` and `nix shell --command` pass when the command
they wrap does. Any other program, `npx` among them, is a finding, and a step never calls a script
in `scripts/` by path. The same entry runs on the Mac. The workflow decides the order, the runners,
the secrets and the conditions; what a stage does lives in the entry, where it is tested and run
locally before CI ever runs it.

**A step is one shot**: one command, however many lines its flags take, after plain preparation
such as `mkdir -p` or an `export`, and passing outputs between steps. An order of commands that
depend on each other, a conditional, a loop, a retry, a parse of output, or a value carried from one
command to the next is orchestration and goes in the entry, in ReScript, which is type-checked,
tested, and runs the same on the Mac as on a runner.

## Step names

**A step's `name:` starts with a capital letter**, as "List the machines" and "Install cloud's
packages": only the first letter, never title case. Job names, workflow names and inputs stay
lowercase. The `step-name-capital` rule holds it,
[model/rules/toolchain.res](../model/rules/toolchain.res). A test or script matching a step by its
name changes with it.

## A schedule's time is nominal

The rule is `schedule-nominal` in `model/rules/toolchain.res`. **GitHub runs a scheduled workflow
hours late, or drops it**, and moving a cron off the hour does not help. monoflake/cloud's systems
run every 12 hours, and a dropped run is made up within about a day. Anything that depends on a
schedule tolerates a late or a missing run, and urgent work is dispatched by hand: the systems
bucket's lifecycle, `expire_days` times 24 hours, is at least twice systems.yml's interval, so one
dropped run is survived within R2's one-to-two-day deletion window. The schedule holds monoflake/cloud's C
alone; B and A build only when a roll asks, so their objects expire between rolls.

**A held object is renewed only from an age T**, `renewAfterHours` in monoflake/cloud's
`model/pipeline.res`, T being the lifecycle less the interval, the worst delay and a job's time, its
queue behind one whole job and its own run. An object left is younger than T, so through a late run
its age stays under the lifecycle. **That covers a late run alone**: a dropped or failed run takes a
left object to about 36 h, past the lifecycle, so surviving it rests on R2's deletion window and not
on this inequality. A nar or narinfo within a job's time of the lifecycle is uploaded rather than
copied, since a copy of what R2 deleted matches nothing and exits 0.
`scripts/tests/systems/bucket/renewal_test.res` there holds T positive, the lifecycle at least twice
the interval, a left object's worst age under the lifecycle, and systems.yml's crons and each job's
`timeout-minutes` against the model; the worst delay is the seven-hour measurement used by
`scheduleLateHours`, which no test reads.

## A build's cache follows where it builds

These rules apply to this workspace and the `monoflake` repositories and are named in
`model/rules/toolchain.res`, the `ci-` ones. The `ci` part of the check holds `ci-crane`,
`ci-rust-cache` and `ci-runner-local`, reading each repository's workflows, composite actions and
Nix files.

**Rust that Nix builds is built with crane**, with its dependencies as a derivation of their own.
When only the crate's own source changes, the dependencies come from the store and only the crate is
compiled again. The dependencies' derivation is needed only at build time, so it is not part of any
system's closure and never goes to a bucket. It stays in the store of the runner that built it.

**A workflow that runs cargo on a GitHub-hosted runner uses `Swatinem/rust-cache`**, whose cache
lives in the repository's GitHub cache. The free allowance is 10 GB per repository, not per account
or organization, evicted least recently used and after seven days unread. A public repository has
GitHub-hosted runners only, since the self-hosted runners admit no public repository,
[repos/monoflake/cloud/docs/runner.md](../repos/monoflake/cloud/docs/runner.md). It has them free,
so a public Rust repository runs the four Rust steps there: `cargo fmt`, `clippy`, the tests and
`cargo deny`. monoflake/machine's check runs those four steps beside monoflake/driver's build.

**A job on a self-hosted runner keeps its caches on the runner, never in the GitHub cache.** The
runner's disk persists between jobs, so uploading a cache only to download it again on the same
machine spends time and allowance. That includes mise's tools, which already persist on the runner,
so the workspace action turns `jdx/mise-action`'s cache off there. A cache a job can write and the
next job reads shares the trust of the runner's tools, RFC obvjb: only the author's private
repositories reach those runners.

**Every cache on a runner has a bound, so nobody clears one by hand.** The Nix store is collected
when the disk runs short, at the free space each runner's configuration names. A compiler cache or a
target directory put on a runner gets a size cap of its own, such as `SCCACHE_CACHE_SIZE`, or an age
after which systemd-tmpfiles removes it. The Arm runners' disks are 50 GB.

## Scheduled updates

The workspace action owns `nix` for installing Nix and `beside` for cloning space separated
`owner/repo` repositories at the commit the caller's `[versions] pin` names, or else at main, and
installing their packages. **The action prepares only what a job asks for**: the workspace's
packages and compiled scripts come with `scripts`, which a job asks only when it runs one, and where
a caller declares a pin, which is read by them. Its `history`
checks the calling repository and the workspace out whole, which the reusable update workflow asks
because the workspace's check reads the commits a repository's RFCs name in either.

The workspace and monoflake's platform, driver, machine and runtime call
`canmi21/canmi/.github/workflows/update-repository.yml@main` from their own
`.github/workflows/update.yml`, daily at 22:00 UTC and by hand through `workflow_dispatch`;
monoflake/cloud's entry follows once the fleet's watched switches of 2026-10-31 are done, as its
update moves every machine's lock. A paused repository has none.
The reusable workflow takes `path` for the registry path, empty for the workspace, `runner` for
the runner labels as JSON, `nix` to install Nix, and `beside` for the repositories the check reads.
`prepare` runs an entry before the update, `message` replaces the shared commit message builder,
and `wake` names the workflow to dispatch on main when the preceding stages succeed. Public
repositories use hosted runners; monoflake/cloud uses its self-hosted ARM64 runners.

The update verb keeps its one-day release wait. The workflow runs in this order: update, the
message naming what moved, `mise run bump` rolling the versions as a landing on main does,
[commits.md](commits.md), "A package's version rolls at landing", then the check, then the commit.
What moves passes the repository's check before github-actions[bot] commits it and pushes straight
to main. The named check is woken explicitly
because a token's push starts no workflow. A failure before the commit pushes nothing; a release
source whose releases could not be read is held back and fails the run after the other updates are
committed, naming the held source.

**The scheduled update moves no action pin**: in CI the actions mover reads and reports alone, and
writes nothing under `.github/`, because GitHub refuses a push from the job's own `GITHUB_TOKEN`
that changes a workflow file, and that token cannot be given the `workflows` permission. A pin in a
workflow or a composite action moves by a local `mise run update`, committed and pushed by an agent
or the author through the verb.
