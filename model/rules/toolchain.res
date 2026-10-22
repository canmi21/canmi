/** What the workspace is built and checked with; the pins, settings and words parts read it. */
/** A pin names a major, a 0.x minor or a channel; one narrower carries its reason beside it. */
let pin = /^(?:\d+|0\.\d+|stable)$/

/** Where the workspace's scripts and tasks sit, their one language, and the exceptions. */
let scriptHomes = ["scripts/", "hooks/", ".mise/tasks/"]
let scripts = [".res", ".resi"]
let kept = ["hooks/bin/rm", "hooks/rm_guard.py", "hooks/test_rm_guard.py", ".mise/tasks/secret"]

/** Local development is this name; a literal loopback address never is. */
let loopback = /\b127\.0\.0\.1\b/

let indentation = [("indent_style", "tab"), ("tab_width", "2")]

/** A mise task's run, in lines; past it the task is a script and the task its one-line entry. */
let taskLines = 5

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
    name: "task-short",
    says: "Every mise task in a repository runs `taskLines` lines at most",
    doc,
    held: Check("tasks"),
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
    name: "actions-pinned",
    says: "A workflow pins each action by commit, its release a comment beside it",
    doc,
    held: Pending("each repository's .github/workflows read for a uses not pinned by commit"),
  },
  {
    name: "actions-age",
    says: "update moves an action's pin to a release a day old, within its major unless --major",
    doc,
    held: Gate("scripts/deps/actions.res"),
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
