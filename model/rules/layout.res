/** How the workspace and the repositories under it are arranged; the repos and tools parts. */
/** What a repository below inherits by position, never copied and shown as a link where used. */
let inherited = [
  ".editorconfig",
  "rustfmt.toml",
  ".oxlintrc.json",
  ".oxfmtrc.json",
  "jujutsu.toml",
  "rust-toolchain.toml",
]

/** Of those, the one a copy may stand in for when it names the workspace's in `extends`. */
let extendable = [".oxlintrc.json"]

/** No directory but a repository's root holds more entries than this. */
let widest = 16

/** Nor lies deeper, a top-level directory's first subdirectory or a package's counted 1. */
let deepest = 5

/** A directory holding one of these is a package's root, where the depth counts from 1 again. */
let manifests = ["Cargo.toml", "package.json", "rescript.json"]

/** A root holds configuration, so a source file there belongs to a package below it. */
let sources = [".rs", ".res", ".ts", ".tsx", ".js", ".mjs", ".svelte", ".py", ".go"]
let configuration = /\.config\.[a-z]+$/

/** Where a repository keeps its rules, and the name that place had before the model. */
let rulesHome = "docs"
let retired = "spec"

/** Another project's files, kept as written, docs/vendor.md; names and shape pass them by. */
let vendor = "vendor"
let vendored = path => path->String.split("/")->Array.includes(vendor)

/** A repository kept as it was until it is pushed and deleted, which no rule over prose reads. */
let archives = ["console"]

let doc = "docs/repos.md"
let rules: array<Rule.t> = [
  {
    name: "not-copied",
    says: "No repository below carries a tracked copy of an `inherited` file",
    doc,
    held: Check("repos"),
  },
  {
    name: "linked-up",
    says: "An inherited file a repository shows is a link resolving to the workspace's, never a copy",
    doc,
    held: Check("repos"),
  },
  {
    name: "tool-once",
    says: "No repository below declares a tool the workspace's [tools] declares",
    doc,
    held: Check("tools"),
  },
  {
    name: "roots-agree",
    says: "repos/registry.toml and [monorepo].config_roots name the same repositories",
    doc,
    held: Check("repos"),
  },
  {
    name: "base-is-origin",
    says: "A workspace.toml's base is the .git address of the workspace it sits under",
    doc,
    held: Check("declared"),
  },
  {
    name: "declared-known",
    says: "A repository's workspace.toml holds only the keys the scripts read",
    doc,
    held: Check("repos"),
  },
  {
    name: "repos-ignored",
    says: ".gitignore lists repos/*/, so git never writes a gitlink",
    doc,
    held: Check("settings"),
  },
  {
    name: "rust-workspace-closed",
    says: "A Rust repository's root Cargo.toml carries a [workspace] table",
    doc,
    held: Check("settings"),
  },
  {
    name: "verb-contract",
    says: "A repository's task for a verb takes --dry-run, and a dry run writes nothing",
    doc,
    held: Pending("each repository's usage spec read for the flags its verb tasks take"),
  },
  {
    name: "tree-wide",
    says: "No directory but a repository's root holds more than `widest` entries",
    doc,
    held: Check("shape"),
    layer: Form,
  },
  {
    name: "tree-deep",
    says: "No directory lies more than `deepest` below a top-level directory or a package's root",
    doc,
    held: Check("shape"),
    layer: Form,
  },
  {
    name: "root-configuration",
    says: "A root Cargo.toml is a virtual manifest, and no source file sits at a root",
    doc,
    held: Check("shape"),
  },
  {
    name: "rules-in-docs",
    says: "A repository keeps its rules in `rulesHome`, never in `retired`",
    doc,
    held: Check("shape"),
  },
  {
    name: "agents-extend",
    says: "A repository's AGENTS.md and docs restate nothing the workspace's say; soft",
    doc,
    held: Check("drift"),
  },
  {
    name: "shared-goes-up",
    says: "What two repositories' docs both say belongs to the workspace; soft",
    doc,
    held: Check("drift"),
  },
]
