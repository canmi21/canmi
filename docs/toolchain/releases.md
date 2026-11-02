# Releases

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
