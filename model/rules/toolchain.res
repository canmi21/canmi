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

/** What a test and its fixtures may write out, docs/agents/pushing.md, RFCs 5737, 3849 and 2606. */
let documentation = {
  "addresses": ["192.0.2.0/24", "198.51.100.0/24", "203.0.113.0/24", "2001:db8::/32"],
  "domains": [
    "example.com",
    "example.net",
    "example.org",
    ".test",
    ".example",
    ".invalid",
    ".localhost",
  ],
  "allowed": ["10.200.0.0/16"],
}

/** The private identifiers a push is scanned for, kept local and in no repository. */
let privateIdentifiers = "~/.config/workspace/private-identifiers"

let doc = "docs/toolchain.md"
let pushing = "docs/agents/pushing.md"
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
    escape: ByTool,
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
    says: "A workflow pins an outside action by commit, its release beside it, and takes the author's own at main",
    doc,
    held: Check("workflows"),
  },
  {
    name: "workflows-linted",
    says: "Every repository's workflows pass actionlint, with shellcheck over each step's shell",
    doc,
    held: Check("workflows"),
  },
  {
    name: "actions-age",
    says: "update moves an action's pin to a release a day old, within its major unless --major",
    doc,
    held: Gate("scripts/deps/actions.res"),
  },
  {
    name: "images-pinned",
    says: "A Dockerfile pins each base image by its tag and a digest",
    doc,
    held: Pending("each repository's Dockerfiles read for a FROM with no digest"),
  },
  {
    name: "images-current",
    says: "update moves a base image's pin to the digest its tag names now, the tag kept",
    doc,
    held: Gate("scripts/deps/images.res"),
  },
  {
    name: "releases-pinned",
    says: "update moves what a repository takes from another's releases to the newest version a manifest lists",
    doc,
    held: Gate("scripts/deps/releases.res"),
  },
  {
    name: "ports-strict",
    says: "Every dev server binds a fixed port and fails when it is taken",
    doc,
    held: Pending("each repository's dev configuration read for strictPort"),
  },
  {
    name: "test-port-zero",
    says: "A test binds port 0 and is handed a free one, never a fixed port",
    doc: "docs/code.md",
    held: Pending("each repository's tests read for a listen on a literal port"),
  },
  {
    name: "test-documentation-values",
    says: "A test and its fixtures write out only the addresses, domains and placeholders `documentation` holds",
    doc: pushing,
    held: Pending("each repository's tests and fixtures read for literals outside `documentation`"),
  },
  {
    name: "push-declared",
    says: "A repository's workspace.toml declares under [push] its visibility, the CI a push starts and any release",
    doc: pushing,
    held: Pending("a [push] key read by a script, which declared-known then admits"),
  },
  {
    name: "push-workflows-declared",
    says: "A workflow under .github/workflows/ that runs on a push is declared under [push]",
    doc: pushing,
    held: Pending("each repository's workflows read against its [push]"),
  },
  {
    name: "push-scanned",
    says: "A public repository's push carries no private identifier, credential, high-entropy string, or address or domain outside `documentation`",
    doc: pushing,
    held: Pending("a scan of the diff a push sends, reading `privateIdentifiers`"),
  },
  {
    name: "push-form-clear",
    says: "Every push waits on the form layer holding nothing in the commit each pushed bookmark points to, read from the repository; a commit may carry form warnings, only the state pushed must be clean",
    doc: pushing,
    held: Gate("push"),
    layer: Form,
  },
  {
    name: "gate-named",
    says: "A rule held by a Gate names a file, or a gate in `Rule.gates`",
    doc: "docs/model.md",
    held: Check("rules"),
  },
  {
    name: "push-gated",
    says: "A wave's push in roles also waits on the full check, a reviewer's read and the wave accepted",
    doc: pushing,
    held: Pending(
      "push running the full check and reading that a reviewer read the wave and the wave was accepted",
    ),
  },
  {
    name: "custom-domains",
    says: "workers_dev and preview_urls are off in every wrangler configuration",
    doc,
    held: Pending("each repository's wrangler files read; deployment is being rewritten"),
  },
]
