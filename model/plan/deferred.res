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
