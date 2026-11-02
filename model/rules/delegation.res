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

/**
 * What prints the environment or a decrypted secret, refused to every role by
 * `secrets-unprinted`, a program that only prints, a builtin given no name, a subcommand, and a
 * reader of a secrets file.
 */
let printing = ["printenv"]
let listingBare = ["env", "export", "set", "declare", "typeset"]
let printingSubcommands = [
  ("mise", ["env", "set"]),
  ("sops", ["-d", "--decrypt", "decrypt", "exec-env", "exec-file", "edit"]),
]
let secretsFile = "secrets.json"
let secretsReaders = ["cat", "jq"]

/** Version control no subagent types, jj aside, which `reading` holds for a reviewer. */
let versioning = ["git"]

/** The jj subcommands a reviewer may run, `file` with `readingFile` beside them. */
let reading = ["diff", "log", "show"]
let readingFile = ["show", "list"]

/** The readers a reviewer may run, decided by the author on 2026-10-24. */
let readers = ["cat", "head", "tail", "sed", "grep", "rg", "ls", "find", "wc", "diff"]

/**
 * The author's widening of 2026-10-31, both given literal words only, never one holding a `$` or a
 * backquote, printf never `-v`, and `labeling` never inside a substitution.
 */
let moving = ["cd"]
let labeling = ["echo", "printf"]

/** The programs a reviewer may run beside jj's reading, every other refused. */
let inspecting = Array.concat(readers, Array.concat(moving, labeling))

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

/** mise's own commands, which `mise <name>` runs before any task of that name. */
let miseCommands = [
  "install",
  "use",
  "ls",
  "exec",
  "x",
  "trust",
  "which",
  "where",
  "prune",
  "upgrade",
  "outdated",
  "env",
  "doctor",
  "plugins",
  "cache",
  "settings",
  "watch",
  "version",
  "self-update",
  "uninstall",
  "reshim",
  "latest",
]

/** The directory of the hooks Codex reads, whose change the author trusts by hand. */
let codexHooksDir = ".codex/"

/** A background job's description holding this word may go silent, `stale-job-looked-at`. */
let quietMark = "quiet"

/** The longest a foreground call may run or ask to run, `long-command-background`. */
let foregroundSeconds = 15

/** What always runs past `foregroundSeconds`, in the background whatever its timeout. */
let longTasks = [
  "check",
  "verify",
  "audit",
  "build",
  "test",
  "update",
  "fmt",
  "systems",
  "iterate",
  "ship",
  "install",
  "stand",
  "conform",
  "reset",
  "switch",
  "built",
  "accept",
  "blocks",
  "archive",
  "dev",
  "release",
  "publish",
  "deploy",
  "retire",
  "lose",
  "replace",
  "builder",
  "local",
  "machines",
  "nixed",
  "prepare",
  "generate",
]
let longTaskFlags = [("nudge", "--wait"), ("job", "--wait"), ("job", "run"), ("lane", "check")]
let longCommands = [
  ["vitest"],
  ["cargo", "build"],
  ["cargo", "test"],
  ["cargo", "clippy"],
  ["cargo", "nextest"],
  ["nix", "build"],
  ["nix", "flake", "check"],
  ["rescript", "build"],
  ["gh", "run", "watch"],
  ["pnpm", "install"],
  ["pnpm", "i"],
]

/** A flag that makes a long task short, the plan it prints or the list it reads. */
let shortFlags = ["--dry-run", "-n", "--pending"]

/** The watcher's stall, bound and line patterns, as regular expression sources. */
let stallSeconds = 30
let watchBoundSeconds = 1800
let watchProgress = "\\b(?:passed|ok|done|finished|built|compiling|running)\\b"
let watchFailure = "\\b(?:error|errors|failed|failure|fatal|panic|refused|timed out)\\b"
let watchEnd = "^(?:exit|status|ended)[: =]"

/** Where the run ledger, its outputs and the watchdog's event file live, in no repository. */
let runs = "~/.local/state/workspace/runs/"

/** Where a thread's private files live, one directory each, docs/agents/threads.md. */
let threads = "~/.local/share/monoflake/threads/"

/**
 * Starting values to be tuned. The watchdog ticks each minute and a report is owed within two, so
 * a job's silence and an unread end are both reported at one minute.
 */
let watchdogSeconds = 60
let runSilentSeconds = 60
let runUnreadSeconds = 60

/** A job past this many times its command's p95, once that many ended well, `runHistory`. */
let runOverP95 = 2
let runHistory = 5

/**
 * A role's turn silent this long goes to its superior. An integrator works in minutes, so ten; a
 * supervisor waits on integrators, so three times that, and past it the author is notified.
 */
let silentTurns = [
  ("seat", 600, "integrator"),
  ("integrator", 600, "supervisor"),
  ("supervisor", 1800, "advisor"),
]
let notifiesAuthor = "supervisor"

/**
 * The share of a thread's seat time that is tooling past which its figures warn, about a fifth by
 * the author's word, and how often the figures are said. They warn and never block.
 */
let toolingShare = 0.2
let figuresSeconds = 3600

/** The launchd label the watchdog runs under. */
let watchdogLabel = "icu.canmi.workspace-watchdog"

/**
 * The fast parts of a repository's check a seat runs in its lane, `lane check`, each by what it
 * catches; the whole check stays the landing's.
 */
let seatParts = [
  ("format", "a file its formatter would change"),
  ("names", "a file or directory misnamed, and the repository's own name misused"),
  ("wire", "the wire's names: the model's check, its Contracts and Names among it"),
  ("compile", "what does not compile, ReScript and Rust"),
  ("tests", "a failing test: the block's `built`, or the repository's `test`"),
]

/** Where `check` is the model's alone, so `wire` runs it; elsewhere it is the whole check. */
let wireRepositories = ["platform", "driver", "cloud"]

/** A lane's, a launchd job's or a step's verbs a seat never runs, `implementer-commands`. */
let notSeats = [("lane", ["open", "close", "take"]), ("job", ["install"]), ("thread", ["green"])]

/** The file a check's blocks in work are listed to, read at the end of `check`, `in-work-shown`. */
let inWorkFile = "IN_WORK_FILE"

/** The models and efforts of a subagent of ours, each from the least to the most. */
let models = ["haiku", "sonnet", "opus"]
let efforts = ["low", "medium", "high", "xhigh", "max"]

/** The floor of every subagent of ours, `subagent-floor`, an absent field inheriting. */
let floorModel = "sonnet"
let floorEffort = "low"

/** Where the subagents are defined, one Markdown file each. */
let definitions = ".claude/agents"

/** What a scout answers within, and the longest answer it gives, in lines. */
let scoutAnswer = 40

/** Where a scribe may write, only a file with this suffix, and in its lane. */
let scribeSuffix = ".md"

/** The docs directory is named once, so no citation reads the map's paths as workspace docs. */
let docs = "docs"

/** An area of the map a scout is pointed at, each with its entry paths under repos/. */
let areas = [
  ("update", ["monoflake/machine/system/nix/update", "monoflake/machine/" ++ docs ++ "/update.md"]),
  ("control", ["monoflake/platform/code/products/control"]),
  ("gateway", ["monoflake/platform/code/products/gateway"]),
  ("driver", ["monoflake/driver/machine"]),
  (
    "fleet",
    [
      "monoflake/cloud/platforms",
      "monoflake/cloud/organizations",
      "monoflake/cloud/" ++ docs ++ "/fleet.md",
    ],
  ),
  (
    "ci",
    [
      "monoflake/cloud/.github/workflows",
      "monoflake/machine/.github/workflows",
      "monoflake/cloud/runner",
    ],
  ),
  ("reset", ["monoflake/cloud/scripts/systems/reset"]),
  ("network", ["monoflake/machine/system/network", "monoflake/machine/" ++ docs ++ "/network.md"]),
]

/** Where the lanes live, beside repos/, one `<name>/monoflake/<repository>` each. */
let lanes = "lanes"

/**
 * How many implementers run at once, each in a lane of its own owning files no other lane touches,
 * docs/agents/delegation.md.
 */
let implementersAtOnce = 10

/** The most a lane's `target` holds, in gigabytes, before `cargo clean` clears it. */
let laneTarget = 10

/** The caches a tool writes again by path, each with the clean `cache-not-trashed` names. */
let caches = [
  ("target", "cargo clean"),
  ("node_modules", "rm inside the workspace, as it has no clean"),
  ("lib/bs", "pnpm exec rescript clean"),
  (".rescript", "pnpm exec rescript clean"),
  ("dist", "the repository's own `mise run clean`"),
]

/** Where the pnpm global store sits, which nothing touches. */
let stores = ["Library/pnpm/store", ".pnpm-store"]

/** Where the records of friction live, one file each by date and rule id, in no repository. */
let friction = "~/.local/state/workspace/friction/"

let doc = "docs/agents/lanes.md"
let checking = "docs/agents/checking.md"
let rules: array<Rule.t> = [
  {
    name: "single-writer",
    says: "An implementer's diff touches no file in `singleWriter`, which the integrator alone changes",
    doc,
    held: Check("lanes"),
    layer: Logic,
  },
  {
    name: "own-directory",
    says: "An implementer's diff touches no file outside its own block's directory",
    doc,
    held: Check("lanes"),
    layer: Logic,
  },
  {
    name: "lockfile-derived",
    says: "An implementer's diff touches no lockfile, which the merge of a wave writes again",
    doc,
    held: Check("lanes"),
  },
  {
    name: "lanes-ignored",
    says: ".gitignore lists `lanes`, so git never tracks a lane",
    doc,
    held: Check("settings"),
  },
  {
    name: "lane-task",
    says: "A lane is opened and closed by `mise run lane`, closed once its change is in the main line",
    doc,
    held: Check("lanes"),
  },
  {
    name: "lane-target",
    says: "A lane's target holds `laneTarget` gigabytes at most",
    doc,
    held: Check("lane-state"),
  },
  {
    name: "cache-not-trashed",
    says: "A cache that can be written again is cleared by its own tool's clean, never trash, nor the pnpm global store touched",
    doc,
    held: Hook("hooks/cache/trash"),
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
    says: "An implementer is refused these kinds alone: version control, jj and git; a whole repository's check, verify or audit, a `verify:<part>` among them, one part of the workspace's check and `lane check` of `seatParts` aside, and --pending always; a task that deploys; ssh, rsync or wrangler, a command given to `job` judged as its own; and `notSeats`. A task it runs may read its own lane's history",
    doc: "docs/agents/seats/implementer.md",
    held: Hook("hooks/agent_commands"),
  },
  {
    name: "stale-job-looked-at",
    says: "A job silent for `stallSeconds` is said at most every five minutes for one hour of silence and held once at a stop per job and silence, a TaskStop ending it as a notice does, a description holding `quietMark` exempt, an unreadable transcript letting the stop through, named",
    doc: "docs/agents/agent-protocol.md",
    held: Hook("hooks/gates/stale_jobs"),
  },
  {
    name: "seat-parts",
    says: "A seat checks its lane by `mise run //:lane check` of `seatParts` and the `built` of its own block, naming a part that is not one refused and a stale lane refused",
    doc: "docs/agents/checking.md",
    held: Check("scripts"),
  },
  {
    name: "lane-not-stale",
    says: "A seat is never dispatched into a lane whose working copy is stale, by the Agent tool's prompt or a `codex exec`, and `lane check` and `lane take` refuse one",
    doc,
    held: Hook("hooks/gates/seat"),
  },
  {
    name: "lane-taken-snapshotted",
    says: "`lane take` snapshots the lane first and restores its changed paths alone, refusing a path main moved since the fork or the main checkout holds an edit to",
    doc,
    held: Check("scripts"),
  },
  {
    name: "in-work-shown",
    says: "A check of a repository ends naming what its blocks in work fail, `inWorkFile` carrying it from whichever process listed it, so an exit 0 cannot hide it",
    doc: checking,
    held: Check("scripts"),
  },
  {
    name: "run-ledger",
    says: "`mise run //:job` records who started a long command, its pid, start, output and at its end its status and duration under `runs`; a read after the end is recorded, by `job read`, `watch`, or a hook seeing its output read",
    doc: "docs/agents/runs.md",
    held: Check("scripts"),
  },
  {
    name: "watchdog-reports",
    says: "The watchdog, run by launchd each `watchdogSeconds` with no model in it, writes one event line for a job ended and unread past `runUnreadSeconds`, one died, one silent past `runSilentSeconds`, one past its limit or `runOverP95` times its command's p95 after `runHistory` runs, and a registered role silent past `silentTurns`, each once, and notifies the author of `notifiesAuthor` silent",
    doc: "docs/agents/runs.md",
    held: Check("scripts"),
  },
  {
    name: "job-stop-own",
    says: "`job stop` stops only a job of the session and the `--by` name that started it, refusing any other and saying whose it is, as `kill-by-recorded-pid` has it",
    doc: "docs/agents/runs.md",
    held: Check("scripts"),
  },
  {
    name: "thread-figures",
    says: "The watchdog says each thread's seat time and landings since a step last went green and the share of its seat time that is tooling, flagged past `toolingShare`, each `figuresSeconds`, which warn and fail nothing",
    doc: "docs/agents/threads.md",
    held: Check("scripts"),
  },
  {
    name: "codex-quota",
    says: "`codex exec` is refused while a window reads 100, naming the reset, an unreadable reading passing with a warning",
    doc: "docs/agents/delegation.md",
    held: Hook("hooks/gates/codex_usage"),
  },
  {
    name: "seat-one-result",
    says: "An implementer or refactorer is dispatched only with a brief holding exactly one line starting `Result:` and exactly one starting `Verify:`, by the Agent tool's prompt or the file it points at, or the file a `codex exec` of `MONOFLAKE_ROLE` is given on stdin; none, several or an unreadable file is refused, because two results are two seats",
    doc: "docs/agents/delegation.md",
    held: Hook("hooks/gates/seat"),
  },
  {
    name: "codex-trust-reminded",
    says: "A landing that changes the hooks under `.codex/` is followed at once by a reminder to the author to trust Codex by hand",
    doc: "docs/agents/delegation.md",
    held: Hook("hooks/gates/commit/codex_trust"),
  },
  {
    name: "long-command-background",
    says: "A foreground shell command never runs past `foregroundSeconds`: one that waits in a loop that sleeps, asks for a timeout past it, or runs a task of `longTasks`, a task given a flag of `longTaskFlags` or a command of `longCommands`, the plan a flag of `shortFlags` asks aside, is refused; it runs in the background or under Monitor and is looked at again every few seconds to a few tens, the watcher's stall of `stallSeconds` naming a hang",
    doc: "docs/agents/agent-protocol.md",
    held: Hook("hooks/gates/background"),
  },
  {
    name: "implementer-lane",
    says: "An implementer writes inside its own lane alone, a temporary directory aside, by an Edit, a Write or a Codex patch; a write elsewhere is refused and reported, never worked around",
    doc: "docs/agents/seats/implementer.md",
    held: Hook("hooks/agent_commands"),
  },
  {
    name: "secrets-unprinted",
    says: "No subagent prints a secret: `printing`, a builtin of `listingBare` given no name or only -p, a subcommand of `printingSubcommands`, and `secretsReaders` given a `secretsFile` are refused to every role, wherever the command is nested",
    doc: "docs/agents/seats/implementer.md",
    held: Hook("hooks/agent_commands"),
  },
  {
    name: "reviewer-commands",
    says: "A reviewer runs only jj's `reading` and `file` with `readingFile`, never given `jjRunning`, and the programs in `inspecting`, `readers` with `moving` and `labeling` beside them, `moving` and `labeling` given no word holding a `$` or a backquote, printf no `-v`, and `labeling` never inside a substitution: sed quiet, never in place and with no command in `sedWriting`, find given nothing in `findWriting`, and rg nothing in `rgRunning`; output is redirected only to `redirectedTo`; each segment's first word is its program, no wrapper and no assignment before it; every other command is refused, every mise task among them, and one run by `&`, a substitution or a pipe is judged as a command of its own",
    doc: "docs/agents/seats/reviewer.md",
    held: Hook("hooks/agent_commands"),
  },
  {
    name: "subagent-floor",
    says: "Every subagent of ours runs as `floorModel` at `floorEffort` or above, nothing of ours is Haiku; a definition naming no model or no effort inherits and passes",
    doc: "docs/agents/delegation.md",
    held: Check("settings"),
  },
  {
    name: "areas-exist",
    says: "Each entry path of `areas` exists under repos/, one in a repository not cloned passed over",
    doc: "docs/agents/seats/reader.md",
    held: Check("settings"),
  },
  {
    name: "scribe-writes-markdown",
    says: "A scribe writes inside its own lane alone, and only a file ending in `scribeSuffix`; any other write is refused and reported",
    doc: "docs/agents/seats/scribe.md",
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
    says: "A refactorer is refused the kinds an implementer is, no part of the workspace's check aside; a task it runs may read its own lane's history",
    doc: "docs/agents/seats/refactorer.md",
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
    held: Check("friction"),
  },
  {
    name: "friction-summed",
    says: "mise run friction sums the records of friction by rule id",
    doc: "docs/agents/friction.md",
    held: Check("scripts"),
  },
  {
    name: "fmt-on-merge",
    says: "The merge of a wave runs mise run fmt, then the logic layer's check",
    doc: checking,
    held: Pending("the merge of a wave as a task, not written yet"),
  },
  {
    name: "form-at-commit",
    says: "A commit in a lane only warns of the form layer; a commit onto a repository's main line, made in its main checkout, is refused on any form finding in the tree it would leave, each repository alone, a paused one passed over, and `SKIP=form` the escape",
    doc: checking,
    held: Hook("hooks/gates/commit/form"),
    layer: Form,
  },
]
