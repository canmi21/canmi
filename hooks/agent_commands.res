/**
 * Holds the shell commands of a subagent, called from its definition's PreToolUse hook, and
 * formats each file it writes, called from its PostToolUse hook.
 */
type role = Implementer | Refactorer | Reviewer

let roleOf = name =>
  switch name {
  | "implementer" => Some(Implementer)
  | "refactorer" => Some(Refactorer)
  | "reviewer" => Some(Reviewer)
  | _ => None
  }

let versioning = ["git"]
let launchers = ["npx", "bunx", "pnpx", "pnpm", "yarn"]
let shells = ["sh", "bash", "zsh", "fish"]
let reading = ["diff", "log", "show"]

let firstWord = (words: array<string>) => words->Array.find(word => !(word->String.startsWith("-")))

// The mise options that take a value, global and of run.
let miseValued = [
  "-C",
  "--cd",
  "-E",
  "--env",
  "-j",
  "--jobs",
  "-o",
  "--output",
  "-s",
  "--shell",
  "-t",
  "--tool",
  "--secrets",
  "--allow-env",
  "--allow-net",
  "--allow-read",
  "--allow-write",
  "--task-cache",
  "--timeout",
  "--affected-base",
  "--affected-head",
]

/** The task a mise invocation runs, named as `run` or as the shorthand does, scoped by -C. */
let taskOf = (words: array<string>) => {
  let operands = []
  let directory = ref(None)
  let at = ref(0)
  while at.contents < words->Array.length {
    let word = words->Array.getUnsafe(at.contents)
    if miseValued->Array.includes(word) {
      if word == "-C" || word == "--cd" {
        directory := words[at.contents + 1]
      }
      at := at.contents + 2
    } else {
      if word->String.startsWith("--cd=") {
        directory := Some(word->String.slice(~start="--cd="->String.length))
      } else if !(word->String.startsWith("-")) {
        operands->Array.push(word)
      }
      at := at.contents + 1
    }
  }
  let task = switch (operands[0], operands[1], operands[2]) {
  | (Some("run" | "r"), task, _) => task
  | (Some("tasks"), Some("run"), task) => task
  | (Some("tasks"), _, _) => None
  | (task, _, _) => task
  }
  task->Option.map(task =>
    task->String.includes(":")
      ? task
      : directory.contents->Option.mapOr(task, dir => `${dir}:${task}`)
  )
}

/** Why a mise task is refused to an agent that deploys nothing and checks nothing. */
let taskReason = (task: string) => {
  let colon = task->String.lastIndexOf(":")
  let name = colon < 0 ? task : task->String.slice(~start=colon + 1)
  let scope = colon < 0 ? None : Some(task->String.slice(~start=0, ~end=colon))
  let repo = scope->Option.map(path => path == "//" ? "" : Node.basename(path))
  let tasks = switch repo {
  | Some(repo) if Delegation.releasing->Array.some(((known, _)) => known == repo) =>
    Delegation.releasing->Array.filter(((known, _)) => known == repo)
  | _ => Delegation.releasing
  }
  if name == "check" {
    Some("mise run check is the integrator's")
  } else if tasks->Array.some(((_, found)) => found->Array.includes(name)) {
    Some(`the task ${name} deploys or releases, which is the integrator's`)
  } else {
    None
  }
}

/** Why one segment is refused to a role, or none. */
let rec segmentReason = (role, segment: array<string>) =>
  switch (role, Jj_command.programOf(segment)) {
  | (_, None) => None
  | (_, Some(program, _)) if versioning->Array.includes(program) => Some("git is not typed here")
  | (Reviewer, Some("jj", _)) =>
    switch Jj_command.invocationOf(segment) {
    | Some(("file", rest)) if rest->firstWord == Some("show") => None
    | Some(subcommand, _) if reading->Array.includes(subcommand) => None
    | Some(subcommand, _) => Some(`jj ${subcommand} is not a reader's command`)
    | None => None
    }
  | (Reviewer, _) => shellReason(role, segment)
  | (_, Some("jj", _)) => Some("jj is not typed here")
  | (_, Some(program, _)) if Delegation.remote->Array.includes(program) =>
    Some(`${program} is the integrator's`)
  | (_, Some("mise", words)) => taskOf(words)->Option.flatMap(taskReason)
  | (_, Some(program, words)) if launchers->Array.includes(program) =>
    words
    ->Array.find(word => Delegation.remote->Array.includes(Node.basename(word)))
    ->Option.map(found => `${Node.basename(found)} is the integrator's`)
  | _ => shellReason(role, segment)
  }
// A shell given -c runs a command line of its own, which is judged as one.
and shellReason = (role, segment) =>
  switch Jj_command.programOf(segment) {
  | Some(program, words) if shells->Array.includes(program) =>
    switch words->Array.findIndex(word => word == "-c") {
    | -1 => None
    | at => words[at + 1]->Option.flatMap(line => reason(role, line))
    }
  | _ => None
  }
and reason = (role, command) =>
  Jj_command.segments(command)->Array.findMap(segment => segmentReason(role, segment))

/** The exit status the harness reads, 2 refusing the command with the reason on stderr. */
let handle = (role, payload: Payload.t): int =>
  switch reason(role, Payload.command(payload)) {
  | None => 0
  | Some(why) =>
    Console.error(`Command refused by hooks/agent_commands.res: ${why}.`)
    2
  }

/** The nearest node_modules/.bin above `directory` holding `tool`, or the bare name for PATH. */
let rec binary = (directory, tool) => {
  let local = Node.join([directory, "node_modules", ".bin", tool])
  if Node.existsSync(local) {
    local
  } else if Node.dirname(directory) == directory {
    tool
  } else {
    binary(Node.dirname(directory), tool)
  }
}

/** The nearest directory above `directory` holding a workspace.toml, the repository's root. */
let rec holder = directory =>
  if Node.existsSync(Node.join([directory, "workspace.toml"])) {
    Some(directory)
  } else if Node.dirname(directory) == directory {
    None
  } else {
    holder(Node.dirname(directory))
  }

let nix = "/nix/var/nix/profiles/default/bin"

/** Runs nixfmt on `file` from a copy of the root's flake files, nothing where it has no lock. */
let nixfmt = (root, file) => {
  let flake = Node.join([root, "flake.nix"])
  let lock = Node.join([root, "flake.lock"])
  if Node.existsSync(flake) && Node.existsSync(lock) {
    let copy = Node.mkdtempSync(Node.join([Node.tmpdir(), "nixfmt-"]))
    Node.writeFileSync(Node.join([copy, "flake.nix"]), Node.readFileSync(flake))
    Node.writeFileSync(Node.join([copy, "flake.lock"]), Node.readFileSync(lock))
    let env = Node.envCopy(Node.env)
    env->Dict.set("PATH", `${nix}:${Node.env->Dict.get("PATH")->Option.getOr("")}`)
    Node.spawnWithEnv(
      "nix",
      ["run", "--inputs-from", `path:${copy}`, "nixpkgs#nixfmt", "--", file],
      {cwd: root, env, stdio: "ignore"},
    )->ignore
    Node.rmSync(copy, {recursive: true, force: true})
  }
}

/** Formats the file an Edit or a Write left by its suffix in `Format.owners`, failing nothing. */
let format = (payload: Payload.t): int => {
  let file = payload->Payload.object("tool_input")->Option.flatMap(Payload.text(_, "file_path"))
  let owner =
    file->Option.flatMap(file =>
      Format.owners->Array.find(((suffix, _)) => suffix == Node.extname(file))
    )
  let root = file->Option.flatMap(file => holder(Node.dirname(file)))
  let declared = root->Option.mapOr(Project.noFormat, Project.formatAt)
  let passed = switch (file, root) {
  | (Some(file), Some(root)) =>
    declared.unformatted->Array.includes(Node.extname(file)) ||
      Project.inTestData(declared, Node.relative(root, file))
  | _ => false
  }
  switch (file, owner) {
  | (Some(file), Some(_, Formats(tool))) if Node.existsSync(file) && !passed =>
    let directory = Node.dirname(file)
    switch (tool, root) {
    | ("nixfmt", Some(root)) => nixfmt(root, file)
    | ("nixfmt", None) => ()
    | ("shfmt", _) =>
      // mise pins shfmt for the workspace alone, so a file elsewhere goes through the workspace.
      Node.spawnSync(
        "mise",
        ["exec", "-C", Registry.root, "--", "shfmt", "-w", file],
        {cwd: directory, stdio: "ignore", timeout: 30000},
      )->ignore
    | _ =>
      let words = tool->String.split(" ")
      Node.spawnSync(
        binary(directory, words[0]->Option.getOr(tool)),
        Array.concat(words->Array.slice(~start=1), [file]),
        {cwd: directory, stdio: "ignore", timeout: 30000},
      )->ignore
    }
  | _ => ()
  }
  0
}

if Node.isMain {
  let read = try Node.readStdin() catch {
  | _ => ""
  }
  let given = Node.args()[0]
  let payload = Payload.parse(read)
  switch (given, given->Option.flatMap(roleOf), payload) {
  | (Some("format"), _, payload) => Node.exit(payload->Option.mapOr(0, format))
  | (_, Some(role), Some(payload)) => Node.exit(handle(role, payload))
  | (_, Some(_), None) => Node.exit(0)
  | _ =>
    Console.error(
      "hooks/agent_commands.res: name the role, implementer, refactorer or reviewer, or format.",
    )
    Node.exit(2)
  }
}
