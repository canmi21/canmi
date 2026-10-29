/** What a file or directory is called; the names part reads it. */
let shape = /^[a-z0-9]+(?:[-.][a-z0-9]+)*$/

/** The languages whose own convention joins a file name's words with an underscore. */
let underscored = [".rs", ".py", ".go", ".res", ".resi"]

/** Names a tool finds by spelling, so they are spelled its way. */
let assigned = [
  "AGENTS.md",
  "README.md",
  "LICENSE",
  "LICENSE-MIT",
  "LICENSE-APACHE",
  "VENDOR.md",
  "Cargo.toml",
  "Cargo.lock",
  "Dockerfile",
]

/** No instruction file but AGENTS.md, since one would stop Claude Code reading it. */
let refused = ["CLAUDE.md"]

/** The top-level domains a domain bound to the platform sits under, a published address. */
let domains = ["com", "net", "org", "dev", "io", "app"]

/** The vendors' names held to the edge, each unmistakably a vendor's and no plain English word. */
let vendors = ["cloudflare", "cloudflared", "r2", "d1", "aws"]

/** What the author named by hand in a vendor account, each its account, kind and name. */
let handNamed = [
  ("monoflake", "worker", "control"),
  ("monoflake", "d1", "control"),
  ("monoflake", "r2", "artifacts"),
  ("monoflake", "worker", "gateway"),
  ("monoflake", "r2", "caches"),
]

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
    name: "own-name",
    says: "The project's own name appears only where a datum leaves the system and meets others'",
    doc,
    held: Check("names"),
  },
  {
    name: "vendor-name",
    says: "A name in `vendors` appears only in a file the vendor defines, a dependency's package name, a declared adapter module, where a model declares its ground and drivers, or a rule's list of words",
    doc,
    held: Pending(
      "own-name's scan over `vendors`, and each repository's adapters declared in workspace.toml",
    ),
  },
  {
    name: "account-name",
    says: "The author's account name, canmi21, appears in no identifier and no code that decides by it, only as data and in comments",
    doc,
    held: Pending("a scan of identifiers in every repository's code for the account name"),
  },
  {
    name: "vendor-resources-drawn",
    says: "Every resource a platform or an organization makes in a vendor account is named by an id drawn as monoflake/platform's RFC b8f35 draws one, 8 lowercase hex digits and bare, but for `handNamed`",
    doc,
    held: Pending(
      "each control's and CI's resource names in monoflake/cloud's controls.toml and systems.toml read against b8f35's form, `handNamed` excepted",
    ),
  },
  {
    name: "qualified-meanings",
    says: "A module or a contract using both meanings of one word writes each by its qualified name",
    doc,
    held: Pending("a scan for two opened modules whose bare names one module uses alike"),
  },
  {
    name: "global-names-modeled",
    says: "A contract's, a component's and a role's name is declared in the model alone",
    doc,
    held: Pending("each repository's declarations of those names read against its model"),
    layer: Logic,
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
