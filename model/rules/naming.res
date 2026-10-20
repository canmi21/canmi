/** What a file or directory is called; the names part reads it. */
let shape = /^[a-z0-9]+(?:[-.][a-z0-9]+)*$/

/** The languages whose own convention joins a file name's words with an underscore. */
let underscored = [".rs", ".py", ".go", ".res", ".resi"]

/** Names a tool finds by spelling, so they are spelled its way. */
let assigned = [
  "AGENTS.md",
  "README.md",
  "LICENSE",
  "LICENSES",
  "REUSE.toml",
  "VENDOR.md",
  "Cargo.toml",
  "Cargo.lock",
  "Dockerfile",
]

/** Directories whose contents a tool names, as REUSE names LICENSES/ by SPDX identifier. */
let namedInside = ["LICENSES"]

/** No instruction file but AGENTS.md, since one would stop Claude Code reading it. */
let refused = ["CLAUDE.md"]

let doc = "docs/naming.md"
let rules: array<Rule.t> = [
  {
    name: "file-names",
    says: "A file or directory is lowercase English, hyphens allowed, by `shape`",
    doc,
    held: Check("names"),
  },
  {
    name: "language-names",
    says: "A source file in one of `underscored` joins words with an underscore",
    doc,
    held: Check("names"),
  },
  {
    name: "assigned-names",
    says: "A name a tool assigns, one of `assigned`, is spelled the tool's way",
    doc,
    held: Check("names"),
  },
  {
    name: "no-claude-md",
    says: "No CLAUDE.md exists anywhere in the tree",
    doc: "AGENTS.md",
    held: Check("names"),
  },
  {
    name: "data-keys",
    says: "A key in a serialized format of ours is lowercase, words joined by an underscore",
    doc,
    held: Pending("a list of which files' keys are ours rather than a tool's"),
  },
  {
    name: "no-shadow",
    says: "A local does not take the name of something already in scope",
    doc,
    held: Pending("ReScript has no shadowing warning; a scan of let bindings per scope"),
  },
  {
    name: "rebrand-kept",
    says: "Twitter is Twitter in identifiers, modules, files, commands and URLs",
    doc,
    held: Pending("a scan that tells the bare letter X as a name from every other X"),
  },
]
