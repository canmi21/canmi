/** What the workspace is built and checked with; the pins, settings and words parts read it. */
/** A pin names a major, a 0.x minor or a channel; one narrower carries its reason beside it. */
let pin = /^(?:\d+|0\.\d+|stable)$/

/** Where the workspace's scripts and tasks sit, their one language, and the exceptions. */
let scriptHomes = ["scripts/", "hooks/", ".mise/tasks/"]
let scripts = [".res", ".resi"]
let kept = ["hooks/bin/rm", "hooks/rm_guard.py", "hooks/test_rm_guard.py", ".mise/tasks/secret"]

/** Written before the rule and not yet moved, each one a violation the day its port lands. */
let porting = [
  "hooks/bookmark.py",
  "hooks/commit.py",
  "hooks/jj_command.py",
  "hooks/language.py",
  "hooks/run.py",
  "hooks/spec_check.py",
  "hooks/spec_diff.py",
  "hooks/test_language.py",
  "hooks/test_run.py",
  ".mise/tasks/repos",
  ".mise/tasks/tools",
  ".mise/tasks/lines",
  ".mise/tasks/refs",
  ".mise/tasks/refs_check.py",
  ".mise/tasks/self/clean",
  ".mise/tasks/self/fmt",
  ".mise/tasks/self/update",
]

/** Local development is this name; a literal loopback address never is. */
let loopback = /\b127\.0\.0\.1\b/

let indentation = [("indent_style", "tab"), ("tab_width", "2")]

let doc = "docs/toolchain.md"
let rules: array<Rule.t> = [
  {
    name: "pin-major",
    says: "A [tools] pin matches `pin`, or carries a comment naming what would lift it",
    doc,
    held: Check("pins"),
  },
  {
    name: "outside-copies",
    says: ".node-version, packageManager and rust-toolchain.toml follow the pins they mirror",
    doc,
    held: Check("tools"),
  },
  {
    name: "scripts-rescript",
    says: "A script, hook or task of the workspace's is ReScript, `kept` excepted",
    doc,
    held: Check("settings"),
  },
  {
    name: "tabs",
    says: ".editorconfig sets tabs at width 2, YAML at two spaces, and rustfmt.toml says it again",
    doc: "docs/lint-format.md",
    held: Check("settings"),
  },
  {
    name: "localhost",
    says: "Local development is localhost, never a literal loopback address",
    doc,
    held: Check("words"),
  },
  {
    name: "trash-not-rm",
    says: "An agent's rm outside the workspace, temp and caches is refused",
    doc,
    held: Hook("hooks/bin/rm"),
  },
  {
    name: "secrets-encrypted",
    says: "Every file .sops.yaml claims is encrypted",
    doc,
    held: Gate("scripts/lints/secrets.res"),
  },
  {
    name: "release-age",
    says: "pnpm-workspace.yaml holds a package version back a day before it installs",
    doc,
    held: Pending("each pnpm repository's pnpm-workspace.yaml read for minimumReleaseAge"),
  },
  {
    name: "ports-strict",
    says: "Every dev server binds a fixed port and fails when it is taken",
    doc,
    held: Pending("each repository's dev configuration read for strictPort"),
  },
  {
    name: "custom-domains",
    says: "workers_dev and preview_urls are off in every wrangler configuration",
    doc,
    held: Pending("each repository's wrangler files read; deployment is being rewritten"),
  },
]
