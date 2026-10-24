/** How a wave's lanes are kept, merged and checked, docs/agents/lanes.md and checking.md. */
/** What only the integrator changes, a directory ending in a slash. */
let singleWriter = [
  "model/",
  "docs/",
  "AGENTS.md",
  "Cargo.toml",
  "pnpm-workspace.yaml",
  "workspace.toml",
  "model/plan/work.res",
]

/** Where the lanes live, beside repos/, one `<name>/monoflake/<repository>` each. */
let lanes = "lanes"

/** The most a lane's `target` holds, in gigabytes, before `cargo clean` clears it. */
let laneTarget = 10

/** Where the records of friction live, one file each by date and rule id, in no repository. */
let friction = "~/.local/state/workspace/friction/"

let doc = "docs/agents/lanes.md"
let checking = "docs/agents/checking.md"
let rules: array<Rule.t> = [
  {
    name: "single-writer",
    says: "An implementer's diff touches no file in `singleWriter`, which the integrator alone changes",
    doc,
    held: Pending("accept reading a lane's diff against `singleWriter` in every repository"),
    layer: Logic,
  },
  {
    name: "own-directory",
    says: "An implementer's diff touches no file outside its own block's directory",
    doc,
    held: Pending("accept in every repository reading the lane's diff against its base"),
    layer: Logic,
  },
  {
    name: "lockfile-derived",
    says: "A lockfile is never merged by hand and is written again when a wave is merged",
    doc,
    held: Pending("the merge of a wave regenerating each lockfile its lanes touched"),
  },
  {
    name: "lanes-ignored",
    says: ".gitignore lists `lanes`, so git never tracks a lane",
    doc,
    held: Pending("the settings part reading .gitignore for `lanes` as it does for repos"),
  },
  {
    name: "lane-task",
    says: "A lane is opened and closed by `mise run lane`, closed once its change is in the main line",
    doc,
    held: Pending("the lane task, open and close, not written yet"),
  },
  {
    name: "lane-target",
    says: "A lane's target holds `laneTarget` gigabytes at most",
    doc,
    held: Pending("the lane task measuring each lane's target"),
  },
  {
    name: "cache-not-trashed",
    says: "A cache that can be written again is cleared by its own tool's clean, never trash, nor the pnpm global store touched",
    doc,
    held: Pending("the rm guard telling a cache from other files as trash is called"),
  },
  {
    name: "accept-in-lane",
    says: "In a lane, accept runs with --from the wave's base and passes over no other block's files",
    doc,
    held: Pending(
      "accept in every repository taking the base, and no longer passing blocks in work",
    ),
    layer: Logic,
  },
  {
    name: "implementer-commands",
    says: "An implementer types no jj, no mise run check, no task that deploys, and no ssh, rsync or wrangler; a task it runs may read its own lane's history",
    doc: "docs/agents/implementer.md",
    held: Pending(
      "a PreToolUse hook in its definition's frontmatter, in ReScript, at hooks/, beside jj_command.res",
    ),
  },
  {
    name: "reviewer-commands",
    says: "A reviewer runs jj only to read, its diff, log, show and file show",
    doc: "docs/agents/reviewer.md",
    held: Pending(
      "a PreToolUse hook in its definition's frontmatter, in ReScript, at hooks/, beside jj_command.res",
    ),
  },
  {
    name: "logic-delivered",
    says: "An implementer's work passes the logic layer before it is handed back",
    doc: checking,
    held: Pending("check running the rules of one layer alone, in a lane"),
    layer: Logic,
  },
  {
    name: "refactorer-commands",
    says: "A refactorer types no jj, no mise run check, no task that deploys, and no ssh, rsync or wrangler; a task it runs may read its own lane's history",
    doc: "docs/agents/refactorer.md",
    held: Pending(
      "a PreToolUse hook in its definition's frontmatter, in ReScript, at hooks/, beside jj_command.res",
    ),
  },
  {
    name: "exempts-read",
    says: "A check passes over what a rule's `exempts` name, and nothing else",
    doc: "docs/agents/escapes.md",
    held: Pending("every check reading the exempts of the rules it holds"),
  },
  {
    name: "friction-written",
    says: "A record of friction is one file under `friction`, named for its date and its rule's id",
    doc: "docs/agents/friction.md",
    held: Pending("the friction task, not written yet"),
  },
  {
    name: "friction-summed",
    says: "mise run friction sums the records of friction by rule id",
    doc: "docs/agents/friction.md",
    held: Pending("the friction task, not written yet"),
  },
  {
    name: "fmt-on-merge",
    says: "The merge of a wave runs mise run fmt, then the logic layer's check",
    doc: checking,
    held: Pending("the merge of a wave as a task, not written yet"),
  },
  {
    name: "form-at-commit",
    says: "At a commit the form layer only warns, saying the commit it first appeared in and how many since",
    doc: checking,
    held: Pending("check telling the form layer apart and reading each warning's history"),
    layer: Form,
  },
]
