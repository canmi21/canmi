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
    id: "console-copy",
    what: "the local copy of console and its registry entry are removed",
    repos: ["console"],
    until: Author,
    waives: ["rules-in-docs"],
  },
]
