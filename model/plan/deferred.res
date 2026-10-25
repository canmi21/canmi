/** What is decided and waits, `docs/planning.md`, each item listed at the end of every check. */
type until =
  /** Due once the RFC of this id is landed or declined. */
  | Closes(string)
  /** Due when the author says. */
  | Author

type item = {
  id: string,
  what: string,
  /** Repositories by their path in repos/registry.toml, or `workspace`. */
  repos: array<string>,
  until: until,
  /** The workspace's rules not held over `repos` while the item waits. */
  waives?: array<string>,
  /** `check --all` and `audit --all` pass over `repos` while the item waits. */
  pauses?: bool,
}

let items: array<item> = [
  {
    id: "inline-data-path",
    what: "driver(cloudflare)'s deploy gives a Worker bindings to what the same binding holds, as a service binding to the driver's own object Worker, as the control compiles each call's paths fewest jumps first, a machine's equivalent its loopback, so the data plane on a Cloudflare account is inlined inside Cloudflare and never crosses the control or the public network, RFCs vr5lw and 94y0d and monoflake/driver's nrs5v; its machine half, a deployment reaching the deployments of its own binding it declares, is under way since 2026-10-24 for the component test bench, and its Cloudflare half waits until the products land, or the advisor judges the moment right",
    repos: ["monoflake/platform", "monoflake/driver"],
    until: Author,
  },
  {
    id: "bench-footing",
    what: "monoflake/platform's test bench stands in for the footing, answering a bundle's read alone, RFC 9bq0y; retired once the footing and its samples land, RFC n8jq5, when the issuer's run reads the real footing and the stand-in is deleted",
    repos: ["monoflake/platform"],
    until: Author,
  },
  {
    id: "d1-per-item",
    what: "driver(cloudflare) gives each database item a D1 of its own, made for it and removed with it, replacing the one database and its clearing lease, monoflake/driver's RFC nrs5v, once database is first offered on a Cloudflare binding; it also ends install refusing over a forged `install` table in a user D1",
    repos: ["monoflake/driver"],
    until: Author,
  },
  {
    id: "release-push",
    what: "a push that releases a version of our own code is given whatever further gate it needs once the first such push comes, docs/agents/pushing.md",
    repos: ["workspace"],
    until: Author,
  },
  {
    id: "paused",
    what: "only the workspace and monoflake are worked on, so every other repository is passed over by check --all and audit --all",
    repos: [
      "canmi/web",
      "canmi/lib",
      "canmi/rfcs",
      "seam",
      "apps/rdm",
      "apps/cue",
      "apps/still",
      "console",
    ],
    until: Author,
    pauses: true,
  },
  {
    id: "ci-scripts-beside",
    what: "each paused repository's scripts read once it is worked on again, and one only its own CI runs moved under its .github/ beside the workflow, as rdm's pkgs/package.sh, docs/repos.md",
    repos: ["canmi/web", "canmi/lib", "apps/rdm", "apps/cue"],
    until: Author,
  },
  {
    id: "rdm-machine-names",
    what: "apps/rdm's release assets named by the machine as uname -m prints it, rdm-nightly-linux-x86_64 and rdm-nightly-macos-aarch64 rather than x64 and arm64, docs/naming.md's rule for a release asset, once rdm is worked on again",
    repos: ["apps/rdm"],
    until: Author,
  },
  {
    id: "machine-extlinux-board",
    what: "monoflake/machine learns a board U-Boot boots from extlinux with two disks, so the overrides in monoflake/cloud's board.nix for its one such machine move into the module: a small ext4 /boot and a btrfs /cold on its UFS, a 5 GB ext4 / and a btrfs /data with simple quotas on its NVMe, small partitions ext4 and large ones btrfs as decided by the author on 2026-10-25, its serial console named by the board",
    repos: ["monoflake/machine", "monoflake/cloud"],
    until: Author,
  },
  {
    id: "builder-lock-rest",
    what: "monoflake/machine's builder lock, after its review of 2026-10-25, leaves: callers that reuse the builder hold no lock, so `builder up` remakes a stale one under a copy; a changed entry.sh is not seen as stale; the piped tasks' freshness check covers cloud's scripts and not machine's Builder; taking over a dead holder's lock is not atomic; a holder killed before writing its pid, or a reused pid, leaves a lock nobody takes over; the keys read depend on SSH_AUTH_SOCK, so a shell without an agent sees the builder as stale; the lock lives in the user's TMPDIR; a waiter prints nothing",
    repos: ["monoflake/machine", "monoflake/cloud"],
    until: Author,
  },
  {
    id: "cache-rest",
    what: "monoflake/machine's cache, after its review of 2026-10-25, leaves: a small machine's daily garbage collection can delete a path between its builder's query and its fetch, so the fetch lacks it; two builders' sweeps can race on one bucket; R2's answer to a missing pointer, 404 or 403, is read on the first live run",
    repos: ["monoflake/machine"],
    until: Author,
  },
  {
    id: "binding-hex-rest",
    what: "after the binding hex wave of 2026-10-25: a binding made before it whose last container item goes names its next one in hex, its images left in its decimal namespace; the decimal token id is parsed four times, in conform, lose, replace and deploy, where the ids library could hold it once",
    repos: ["monoflake/driver", "monoflake/platform"],
    until: Author,
  },
  {
    id: "drawn-app-orphan",
    what: "monoflake/platform's control gains a way to remove an app whose id it drew for a deploy that failed and was never tried again, by a delete or an expiry, since releases has no delete and such a row stays for good; raised by the bare id wave's review on 2026-10-25; the first such row is the production platform's app 23f191e8, drawn on 2026-10-25 for a deploy onto binding 3 that driver(cloudflare) refused, RFC emgxf",
    repos: ["monoflake/platform"],
    until: Author,
  },
  {
    id: "objects-draw-conditional",
    what: "monoflake/platform's control on its objects state draws an app's id serialized per isolate rather than by a conditional insert across requests, against RFC b8f35, odds about one in 2^32, and its forget deletes unconditionally, so a deploy in another request can declare between its read and its deletes and run an app the control has forgotten; both retire with the production platform at RFC 8yl4b, when the footing rebuilds it",
    repos: ["monoflake/platform"],
    until: Author,
  },
  {
    id: "tool-ids-module",
    what: "monoflake/platform's deploy, conform, replace and lose each carry a near identical `Ids` module with no interface of the model's, to become one shared module or an interface each, as the author chooses",
    repos: ["monoflake/platform"],
    until: Author,
  },
  {
    id: "machine-system-review",
    what: "monoflake/machine's system reviewed whole and slimmed where it can be -- crun's Python, libkrun, what else a set carries, its criu kept while monoflake/platform's C39 is open -- once monoflake/platform's driver's abilities are built, capability first",
    repos: ["monoflake/machine"],
    until: Author,
  },
  {
    id: "envelope-operations-table",
    what: "envelope generates a table of every operation by its interface and name, its output type among it, and monoflake/platform's runner reads that in place of bindings/generated.res reading the generated module as data",
    repos: ["monoflake/platform"],
    until: Author,
  },
  {
    id: "seam-rfcs",
    what: "seam's RFCs move out of canmi/rfcs into seam's own docs/rfcs",
    repos: ["seam", "canmi/rfcs"],
    until: Author,
  },
  {
    id: "spec-to-docs",
    what: "spec/ is renamed docs/",
    repos: ["canmi/web", "canmi/lib", "apps/rdm", "apps/cue", "seam"],
    until: Author,
    waives: ["rules-in-docs"],
  },
  {
    id: "held-back",
    what: "local commits stay unpushed; a push of canmi/lib publishes packages, so it is asked first",
    repos: ["canmi/web", "canmi/lib", "apps/cue"],
    until: Author,
  },
  {
    id: "machine-platform",
    what: "the machine's option naming the platform it belongs to, one configured value, RFC y6lg7, is added by the first code that reads the name",
    repos: ["monoflake/machine"],
    until: Author,
  },
  {
    id: "console-copy",
    what: "the local copy of console and its registry entry are removed",
    repos: ["console"],
    until: Author,
    waives: ["rules-in-docs"],
  },
]
