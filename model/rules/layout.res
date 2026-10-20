/** How the workspace and the repositories under it are arranged; the repos and tools parts. */
/** What a repository below inherits by position and so never copies. */
let inherited = [
  ".editorconfig",
  "rustfmt.toml",
  ".oxlintrc.json",
  ".oxfmtrc.json",
  "jj.toml",
  "rust-toolchain.toml",
]

/** Of those, the one a copy may stand in for when it names the workspace's in `extends`. */
let extendable = [".oxlintrc.json"]

let doc = "docs/repos.md"
let rules: array<Rule.t> = [
  {
    name: "not-copied",
    says: "No repository below carries a tracked copy of an `inherited` file",
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
    name: "one-entry",
    says: "A project carries spec/ and no entry point of its own, monoflake excepted",
    doc,
    held: Pending("the registry naming which repositories keep an entry point of their own"),
  },
]
