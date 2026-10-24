/** How a wave's lanes are kept, merged and checked, docs/agents/lanes.md and checking.md. */
/** What only the integrator changes, a directory ending in a slash; a check program is code. */
let singleWriter = [
  "model/rules/",
  "model/plan/",
  "model/rules.res",
  "model/graph/",
  "model/contracts/",
  "model/ground/",
  "model/bootstrap/",
  "model/names/",
  "docs/",
  "AGENTS.md",
  "Cargo.toml",
  "pnpm-workspace.yaml",
  "workspace.toml",
  "model/plan/work.res",
]

/** The programs an implementer and a refactorer never run, `implementer-commands`. */
let remote = ["ssh", "rsync", "wrangler"]

/** Version control no subagent types, jj aside, which `reading` holds for a reviewer. */
let versioning = ["git"]

/** The jj subcommands a reviewer may run, `file` with `readingFile` beside them. */
let reading = ["diff", "log", "show"]
let readingFile = ["show", "list"]

/** The programs a reviewer may run beside jj's reading, every other refused. */
let inspecting = ["cat", "head", "tail", "sed", "grep", "rg", "ls", "find", "wc", "diff"]

/** sed runs for a reviewer only quiet, given -n, and never in place, -I being macOS's own. */
let sedQuiet = ["-n", "--quiet", "--silent"]
let sedInPlace = ["-i", "-I", "--in-place"]

/** What find is never given by a reviewer, each writing a file or running a program. */
let findWriting = [
  "-exec",
  "-execdir",
  "-ok",
  "-okdir",
  "-delete",
  "-fprint",
  "-fprint0",
  "-fprintf",
  "-fls",
]

/** A sed script's commands that write a file or run a program, refused a reviewer. */
let sedWriting = ["w", "W", "e"]

/** The flags that make a reviewer's rg or jj run a program or read another configuration. */
let rgRunning = ["--pre", "--hostname-bin"]
let jjRunning = ["--tool", "--config", "--config-file"]

/** What never stands before a reviewer's command, an assignment to the environment beside it. */
let wrapping = ["env", "exec", "xargs"]

/** The one place a reviewer's command may redirect its output to. */
let redirectedTo = ["/dev/null"]

/** What runs another program by its name, which the command hooks look through. */
let launchers = ["npx", "bunx", "pnpx", "pnpm", "yarn"]
let shells = ["sh", "bash", "zsh", "fish"]

/** The tasks that deploy or release, by repository, the workspace's own by no name. */
let releasing = [
  ("", ["push", "publish"]),
  ("platform", ["deploy", "conform", "lose", "replace"]),
  ("driver", ["release"]),
  ("cloud", ["switch", "tunnel", "install", "bind", "stand", "operate"]),
  ("runtime", ["publish", "release"]),
  ("machine", ["builder", "local"]),
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
    says: "An implementer is refused four kinds alone: version control, jj and git; a whole repository's check, verify or audit, one part of the workspace's check aside, and --pending always; a task that deploys; and ssh, rsync or wrangler. A task it runs may read its own lane's history",
    doc: "docs/agents/implementer.md",
    held: Hook("hooks/agent_commands"),
  },
  {
    name: "reviewer-commands",
    says: "A reviewer runs only jj's `reading` and `file` with `readingFile`, never given `jjRunning`, and the programs in `inspecting`: sed quiet, never in place and with no command in `sedWriting`, find given nothing in `findWriting`, and rg nothing in `rgRunning`; output is redirected only to `redirectedTo`; nothing in `wrapping` and no assignment stands before a command; every other command is refused, every mise task among them, and one run by `&`, a substitution or a pipe is judged as a command of its own",
    doc: "docs/agents/reviewer.md",
    held: Hook("hooks/agent_commands"),
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
    says: "A refactorer is refused the four kinds an implementer is, no part of the workspace's check aside; a task it runs may read its own lane's history",
    doc: "docs/agents/refactorer.md",
    held: Pending(
      "hooks/agent_commands.res, hung in its definition, proven to run in a refactorer; on 2026-10-24 it ran in an implementer and a reviewer, and no refactorer has run since",
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
    held: Check("shape"),
    layer: Form,
  },
]
