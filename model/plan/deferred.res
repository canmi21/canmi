/** What is decided and waits, `docs/planning.md`: each item listed at the end of every check. */
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
}

let items: array<item> = [
  {
    id: "machine-system-review",
    what: "monoflake/platform's machine system reviewed whole and slimmed where it can be -- crun's criu and Python, libkrun, what else a set carries -- once the driver's abilities are built, capability first",
    repos: ["monoflake/platform"],
    until: Author,
  },
  {
    id: "image-bases-pinned",
    what: "the pins tool also moves the base images monoflake/platform's machine images pin by digest, distroless and busybox, as it moves workerd",
    repos: ["monoflake/platform"],
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
