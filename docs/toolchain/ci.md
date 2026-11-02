# CI dependencies

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
[model/rules/toolchain.res](../../model/rules/toolchain.res) refuses a `FROM` with no tag and digest.
