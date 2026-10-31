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

/** What a mise invocation was given, its operands past options, the flags and the -C directory. */
type given = {operands: array<string>, flags: array<string>, directory: option<string>}

let givenOf = (words: array<string>) => {
  let operands = []
  let flags = []
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
      } else if word->String.startsWith("-") {
        flags->Array.push(word)
      } else {
        operands->Array.push(word)
      }
      at := at.contents + 1
    }
  }
  {operands, flags, directory: directory.contents}
}

/** The task a mise invocation runs, named as `run` or as the shorthand does, scoped by -C. */
let taskOf = (given: given) => {
  let {operands, directory} = given
  let (task, after) = switch (operands[0], operands[1], operands[2]) {
  | (Some("run" | "r"), task, _) => (task, 2)
  | (Some("tasks"), Some("run"), task) => (task, 3)
  | (Some("tasks"), _, _) => (None, 0)
  | (task, _, _) => (task, 1)
  }
  task->Option.map(task => (
    task->String.includes(":") ? task : directory->Option.mapOr(task, dir => `${dir}:${task}`),
    operands->Array.slice(~start=after),
  ))
}

/** Every task a mise invocation runs, those after a `:::` judged as the first is. */
let tasksOf = (given: given) => {
  let groups = [[]]
  given.operands->Array.forEach(operand =>
    if operand == ":::" {
      groups->Array.push([])
    } else {
      groups->Array.getUnsafe(groups->Array.length - 1)->Array.push(operand)
    }
  )
  groups->Array.mapWithIndex((group, at) =>
    taskOf({...given, operands: at == 0 ? group : ["run", ...group]})
  )
}

/** What `mise exec` or `mise x` runs, a segment after `--` or a line given -c. */
type inner =
  | Segment(array<string>)
  | Line(string)
  | Bare

let execOf = (given: given, words: array<string>) =>
  switch given.operands[0] {
  | Some("exec" | "x") =>
    let dashes = words->Array.findIndex(word => word == "--")
    let command = words->Array.findIndex(word => word == "-c" || word == "--command")
    Some(
      switch (dashes, command, words[command + 1]) {
      | (-1, -1, _) | (-1, _, None) => Bare
      | (-1, _, Some(line)) => Line(line)
      | (at, _, _) => Segment(words->Array.slice(~start=at + 1))
      },
    )
  | _ => None
  }

/** The rule that holds a role's commands, named in each refusal. */
let ruleOf = role =>
  switch role {
  | Implementer => "implementer-commands"
  | Refactorer => "refactorer-commands"
  | Reviewer => Read_only.rule
  }

/** The nearest directory at or above `directory` whose mise.toml declares a check task. */
let rec checkHolder = directory => {
  let file = Node.join([directory, "mise.toml"])
  if Node.existsSync(file) && Node.readFileSync(file)->String.includes("[tasks.check]") {
    Some(directory)
  } else if Node.dirname(directory) == directory {
    None
  } else {
    checkHolder(Node.dirname(directory))
  }
}

/** Whether a check task named by `scope` from `cwd` is the workspace's own, the dispatcher. */
let workspaceCheck = (scope, ~cwd) =>
  switch scope {
  | Some(path) if path->String.startsWith("//") =>
    Node.resolve([Registry.root, path->String.slice(~start=2)]) == Registry.root
  | Some(path) => checkHolder(Node.resolve([cwd, path])) == Some(Registry.root)
  | None => checkHolder(Node.resolve([cwd])) == Some(Registry.root)
  }

/** Why a role is refused a mise task, check or verify bar one part, --pending, audit or deploy. */
let taskReason = (role, (task: string, rest: array<string>), ~flags, ~cwd) => {
  let colon = task->String.lastIndexOf(":")
  let name = colon < 0 ? task : task->String.slice(~start=colon + 1)
  let scope = colon < 0 ? None : Some(task->String.slice(~start=0, ~end=colon))
  let repo = scope->Option.map(path => path == "//" ? "" : Node.basename(path))
  let tasks = switch repo {
  | Some(repo) if Delegation.releasing->Array.some(((known, _)) => known == repo) =>
    Delegation.releasing->Array.filter(((known, _)) => known == repo)
  | _ => Delegation.releasing
  }
  // A part is one part of the workspace's own check, docs/agents/checking.md.
  let aPart =
    role == Implementer &&
    workspaceCheck(scope, ~cwd) &&
    rest[0] == Some("workspace") &&
    rest->Array.length == 2 &&
    !(flags->Array.includes("--all"))
  if name == "check" && flags->Array.includes("--pending") {
    Some(`--pending is the integrator's, ${ruleOf(role)} holds it`)
  } else if name == "check" && !aPart {
    Some(
      role == Implementer
        ? `mise run check is the integrator's, bar parts of the workspace's, ${ruleOf(
              role,
            )} holds it`
        : `mise run check is the integrator's, ${ruleOf(role)} holds it`,
    )
  } else if name == "verify" {
    Some(`mise run verify is a whole check, which is the integrator's, ${ruleOf(role)} holds it`)
  } else if name == "audit" {
    Some(`mise run audit is the integrator's, ${ruleOf(role)} holds it`)
  } else if tasks->Array.some(((_, found)) => found->Array.includes(name)) {
    Some(
      `the task ${name} deploys or releases, which is the integrator's, ${ruleOf(role)} holds it`,
    )
  } else {
    None
  }
}

/** Why a segment would print the environment or a decrypted secret, refused to every role. */
let secretReason = (segment: array<string>) => {
  // env names a program it runs, so bare it is read here, before the wrapper is passed over.
  let bare =
    segment[0]->Option.mapOr(false, first => Node.basename(first) == "env") &&
      segment
      ->Array.slice(~start=1)
      ->Array.every(word => word->String.startsWith("-") || word->String.includes("="))
  switch Jj_command.programOf(segment) {
  | _ if bare => Some("env would print a secret, secrets-unprinted holds it")
  | None => None
  | Some(program, words) =>
    let operands = words->Array.filter(word => !(word->String.startsWith("-")))
    let printed =
      Delegation.printing->Array.includes(program) ||
      switch program {
      | "env" => operands->Array.every(word => word->String.includes("="))
      | "set" => words == []
      | _ => Delegation.listingBare->Array.includes(program) && operands == []
      } ||
      Delegation.printingSubcommands->Array.some(((owner, subcommands)) =>
        owner == program && (
            owner == "mise"
              ? givenOf(words).operands[0]->Option.mapOr(false, first =>
                  subcommands->Array.includes(first)
                )
              : words->Array.some(word => subcommands->Array.includes(word))
          )
      ) ||
      (Delegation.secretsReaders->Array.includes(program) &&
        words->Array.some(word => Node.basename(word) == Delegation.secretsFile))
    printed ? Some(`${program} would print a secret, secrets-unprinted holds it`) : None
  }
}

/** Why a reviewer's cd, echo or printf is refused, a word holding a `$` or a backquote, or -v. */
let labelReason = (segment: array<string>) =>
  switch Jj_command.programOf(segment) {
  | Some(program, words)
    if Delegation.labeling->Array.includes(program) || Delegation.moving->Array.includes(program) =>
    words
    ->Array.find(word =>
      word->String.includes("$") ||
      word->String.includes("`") ||
      (program == "printf" && word->String.startsWith("-v"))
    )
    ->Option.map(found =>
      `${program} is given literal words alone, never ${found}, ${Read_only.rule} holds it`
    )
  | _ => None
  }

/** Why a reviewer's command is refused for an echo or printf inside a substitution. */
let substitutedLabel = (command: string) =>
  (command->String.includes("$(") || command->String.includes("`")) &&
    Jj_command.segments(command)->Array.some(segment =>
      switch Jj_command.programOf(segment) {
      | Some(program, _) => Delegation.labeling->Array.includes(program)
      | None => false
      }
    )
    ? Some(`echo and printf never run inside a substitution, ${Read_only.rule} holds it`)
    : None

/** Why one segment is refused to a role, or none. */
let rec segmentReason = (~directory=?, ~cwd=Registry.root, role, segment: array<string>) =>
  switch (role, Jj_command.programOf(segment)) {
  | _ if secretReason(segment) != None => secretReason(segment)
  | (_, None) => None
  | (Reviewer, _) => labelReason(segment)->Option.orElse(Read_only.segmentReason(segment))
  | (_, Some(program, _)) if Delegation.versioning->Array.includes(program) =>
    Some("git is not typed here")
  | (_, Some("mise", words)) if execOf(givenOf(words), words) != None =>
    switch execOf(givenOf(words), words) {
    | Some(Segment(inner)) =>
      segmentReason(
        ~directory=?givenOf(words).directory->Option.orElse(directory),
        ~cwd,
        role,
        inner,
      )
    | Some(Line(line)) => reason(~cwd, role, line)
    | _ => None
    }
  | (_, Some("mise", words)) =>
    let given = givenOf(words)
    let given = {...given, directory: given.directory->Option.orElse(directory)}
    tasksOf(given)->Array.findMap(found =>
      found->Option.flatMap(found => taskReason(role, found, ~flags=given.flags, ~cwd))
    )
  | (_, Some("jj", _)) => Some("jj is not typed here")
  | (_, Some(program, _)) if Delegation.remote->Array.includes(program) =>
    Some(`${program} is the integrator's`)
  | (_, Some(program, words)) if Delegation.launchers->Array.includes(program) =>
    words
    ->Array.find(word => Delegation.remote->Array.includes(Node.basename(word)))
    ->Option.map(found => `${Node.basename(found)} is the integrator's`)
  | _ => shellReason(~cwd, role, segment)
  }
// A shell given -c runs a command line of its own, which is judged as one.
and shellReason = (~cwd, role, segment) =>
  switch Jj_command.programOf(segment) {
  | Some(program, words) if Delegation.shells->Array.includes(program) =>
    switch words->Array.findIndex(word => word == "-c") {
    | -1 => None
    | at => words[at + 1]->Option.flatMap(line => reason(~cwd, role, line))
    }
  | _ => None
  }
and reason = (~cwd=Registry.root, role, command) =>
  role == Reviewer
    ? substitutedLabel(command)
      ->Option.orElse(
        Jj_command.segments(command)->Array.findMap(segment =>
          secretReason(segment)->Option.orElse(labelReason(segment))
        ),
      )
      ->Option.orElse(Read_only.reason(command))
    : Jj_command.segments(command)->Array.findMap(segment => segmentReason(~cwd, role, segment))

/** The exit status the harness reads, 2 refusing the command with the reason on stderr. */
let handle = (role, payload: Payload.t): int =>
  switch reason(~cwd=Payload.cwd(payload), role, Payload.command(payload)) {
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

/** A patch's line naming a file it leaves written, Codex's `apply_patch`. */
let patched = /^\*\*\* (?:Add File|Update File|Move to): (.+)$/

/** The files a tool call left written: an Edit's or a Write's one, or every one a patch names. */
let written = (payload: Payload.t): array<string> => {
  let input = payload->Payload.object("tool_input")
  switch input->Option.flatMap(fields =>
    fields->Payload.text("file_path")->Option.orElse(fields->Payload.text("notebook_path"))
  ) {
  | Some(file) => [file]
  | None =>
    let cwd = Payload.cwd(payload)
    let patch =
      input
      ->Option.mapOr([], fields => fields->Dict.valuesToArray)
      ->Array.filterMap(JSON.Decode.string)
      ->Array.find(text => text->String.includes("*** Begin Patch"))
    patch
    ->Option.mapOr([], text => text->String.split("\n"))
    ->Array.filterMap(line =>
      patched
      ->RegExp.exec(line->String.trim)
      ->Option.flatMap(found => found->RegExp.Result.matches->Array.get(0)->Option.flatMap(x => x))
    )
    ->Array.map(file => file->String.startsWith("/") ? file : Node.join([cwd, file]))
  }
}

/**
 * The directory every lane sits in, `Delegation.lanes` under the workspace, found from a workspace
 * lane's own checkout as well, whose root lies two levels below it.
 */
let lanesUnder = root => {
  let parent = Node.dirname(Node.dirname(root))
  Node.basename(parent) == Delegation.lanes ? parent : Node.join([root, Delegation.lanes])
}
let lanesRoot = lanesUnder(Registry.root)

/** The lane a path lies in, the directory under `lanesRoot` it starts with, if any. */
let laneOf = path =>
  path->String.startsWith(`${lanesRoot}/`)
    ? path
      ->String.slice(~start=lanesRoot->String.length + 1)
      ->String.split("/")
      ->Array.get(0)
      ->Option.map(name => Node.join([lanesRoot, name]))
    : None

/** The temporary directories a write may go to besides the lane, as given and as resolved. */
let scratch = () => [Node.tmpdir(), `/private${Node.tmpdir()}`, "/private/tmp", "/tmp"]

/**
 * The files of `files`, resolved, an implementer may not write: outside the lane its working
 * directory lies in, or outside every lane where it works from elsewhere, temporary ones aside.
 */
let outside = (~cwd, files) => {
  let lane = laneOf(Node.resolve([cwd]))
  files->Array.filterMap(file => {
    let file = Node.resolve([cwd, file])
    let inScratch = scratch()->Array.some(directory => file->String.startsWith(`${directory}/`))
    let inLane = switch lane {
    | Some(lane) => file->String.startsWith(`${lane}/`)
    | None => laneOf(file)->Option.isSome
    }
    inScratch || inLane ? None : Some(file)
  })
}

/** The exit status the harness reads, 2 refusing a write outside the implementer's lane. */
let placed = (payload: Payload.t): int =>
  switch outside(~cwd=Payload.cwd(payload), written(payload)) {
  | [] => 0
  | files =>
    Console.error(
      `Write refused by hooks/agent_commands.res: an implementer writes inside its lane alone, ` ++
      `and ${files->Array.join(
          ", ",
        )} lies outside it. Stop and report to the integrator; a ` ++ `refusal is never worked around, docs/agents/escapes.md.`,
    )
    2
  }

/** Formats one file by its suffix in `Format.owners`, failing nothing. */
let formatted = (file: string) => {
  let file = Some(file)
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
}

/** Formats every file a tool call left written, failing nothing. */
let format = (payload: Payload.t): int => {
  written(payload)->Array.forEach(formatted)
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
  | (Some("lane"), _, payload) => Node.exit(payload->Option.mapOr(0, placed))
  | (_, Some(role), Some(payload)) => Node.exit(handle(role, payload))
  | (_, Some(_), None) => Node.exit(0)
  | _ =>
    Console.error(
      "hooks/agent_commands.res: name the role, implementer, refactorer or reviewer, or format or lane.",
    )
    Node.exit(2)
  }
}
