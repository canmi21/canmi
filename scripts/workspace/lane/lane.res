/**
 * `lane open <repository|workspace> <name> [--with <repository> ...] [--dry-run]` and
 * `lane close <name> [--dry-run]`, docs/agents/lanes.md.
 */
type step =
  | Run({cwd: string, program: string, args: array<string>})
  | Guard({cwd: string, dir: string})
  | Background({cwd: string, command: string, log: string})
  | MakeDir(string)
  | Remove(string)

type opened = {target: string, name: string, siblings: array<string>}

let namePattern = /^[a-z][a-z0-9-]*$/

/** The revset of a working copy's changes that main does not hold yet. */
let unlanded = "main..@ ~ empty()"

/** Where a lane's workspace of `target` sits, the base workspace being `workspace`. */
let destination = (~root, ~name, target) =>
  Node.join([Lane_state.lanes(root), name, target == "workspace" ? "canmi" : target])

let source = (~root, target) => target == "workspace" ? root : Node.join([root, "repos", target])

/** A path of the base workspace, or why `root` is a lane's own copy. */
let fromBase = root =>
  root->String.includes(`${Node.sep}lanes${Node.sep}`)
    ? Error("run lane from the base workspace, not from inside a lane")
    : Ok()

/** What the steps of an open are, or why they cannot be. */
let openPlan = (
  ~root,
  ~registered,
  ~cloned,
  ~exists,
  ~hasPackage,
  {target, name, siblings}: opened,
) => {
  let all = Array.concat([target], siblings)
  let unknown = all->Array.find(one => one != "workspace" && !(registered->Array.includes(one)))
  let missing = all->Array.find(one => one != "workspace" && !cloned(one))
  let nested =
    all->Array.includes("workspace") && all->Array.some(one => one->String.startsWith("canmi/"))
  switch (fromBase(root), unknown, missing) {
  | (Error(why), _, _) => Error(why)
  | _ if !(namePattern->RegExp.test(name)) =>
    Error(`${name} is no lane name, which is lowercase words joined by hyphens`)
  | _ if all->Array.length != Set.fromArray(all)->Set.size => Error("a repository is named twice")
  | _ if exists(Node.join([Lane_state.lanes(root), name])) => Error(`lanes/${name} exists already`)
  | (_, Some(one), _) => Error(`${one} is no repository of repos/registry.toml`)
  | (_, _, Some(one)) => Error(`${one} is not cloned`)
  | _ if nested =>
    Error("the workspace's lane holds canmi, which a canmi/ repository would nest in")
  | _ =>
    Ok(
      all->Array.flatMap(one => {
        let there = destination(~root, ~name, one)
        Array.concat(
          [
            MakeDir(Node.dirname(there)),
            Run({
              cwd: source(~root, one),
              program: "jj",
              args: ["workspace", "add", "--name", name, "-r", "main", there],
            }),
          ],
          hasPackage(one)
            ? [
                Background({
                  cwd: there,
                  command: "pnpm install --frozen-lockfile",
                  log: Node.join([
                    Lane_state.lanes(root),
                    name,
                    `${one->String.replaceAll("/", "-")}-install.log`,
                  ]),
                }),
              ]
            : [],
        )
      }),
    )
  }
}

/**
 * What the steps of a close are. Every working copy is snapshotted and judged first, so a lane
 * with a change not landed loses nothing.
 */
let closePlan = (~root, ~registered, ~hasCargo, ~name, workspaces: array<Lane_state.found>) => {
  let sources =
    workspaces->Array.map(one => (one, Lane_state.sourceOf(~root, ~registered, one.rel)))
  switch (fromBase(root), sources->Array.find(((_, from)) => from == None)) {
  | (Error(why), _) => Error(why)
  | _ if !(namePattern->RegExp.test(name)) =>
    Error(`${name} is no lane name, which is lowercase words joined by hyphens`)
  | _ if workspaces == [] => Error(`lanes/${name} holds no jj workspace`)
  | (_, Some((one, _))) =>
    Error(`lanes/${name}/${one.rel} is neither canmi nor a registered repository's path`)
  | _ =>
    let kept = sources->Array.filterMap(((one, from)) => from->Option.map(from => (one, from)))
    Ok(
      Array.concat(
        kept->Array.flatMap(((one, _)) => [
          Run({cwd: one.path, program: "jj", args: ["st"]}),
          Guard({cwd: one.path, dir: `lanes/${name}/${one.rel}`}),
        ]),
        Array.concat(
          kept->Array.flatMap(((one, from)) =>
            Array.flat([
              [Run({cwd: from, program: "jj", args: ["workspace", "forget", name]})],
              hasCargo(one.path) ? [Run({cwd: one.path, program: "cargo", args: ["clean"]})] : [],
              [Remove(Node.join([one.path, "node_modules"]))],
            ])
          ),
          [Remove(Node.join([Lane_state.lanes(root), name]))],
        ),
      ),
    )
  }
}

let shown = step =>
  switch step {
  | Run({cwd, program, args}) => `(in ${cwd}) ${program} ${args->Array.join(" ")}`
  | Guard({cwd, dir}) => `(in ${cwd}) refuse if jj log -r '${unlanded}' lists a change, ${dir}`
  | Background({cwd, command, log}) => `(in ${cwd}) ${command} in the background, log ${log}`
  | MakeDir(dir) => `mkdir -p ${dir}`
  | Remove(path) => `remove ${path}`
  }

/** The changes of a working copy that main lacks, one per line, or the failure to read them. */
let unlandedIn = cwd => {
  let answer = Node.spawnSync(
    "jj",
    [
      "log",
      "-r",
      unlanded,
      "--no-graph",
      "-T",
      `change_id.short() ++ " " ++ description.first_line() ++ "\\n"`,
    ],
    {cwd, encoding: "utf8", maxBuffer: 268435456},
  )
  answer.status->Nullable.toOption == Some(0)
    ? Ok(answer.stdout->Nullable.getOr("")->String.trim)
    : Error(answer.stderr->Nullable.getOr("jj log failed")->String.trim)
}

let nothingElse = (~root, path) => path->String.startsWith(Lane_state.lanes(root) ++ Node.sep)

/** One step done, the reason it failed otherwise. */
let perform = (~root, step) =>
  switch step {
  | Run({cwd, program, args}) =>
    Node.run(~cwd, program, args) == 0 ? Ok() : Error(`${program} ${args->Array.join(" ")} failed`)
  | Guard({cwd, dir}) =>
    switch unlandedIn(cwd) {
    | Ok("") => Ok()
    | Ok(changes) => Error(`${dir} holds changes not in main, so it stays open:\n${changes}`)
    | Error(why) => Error(`${dir} could not be judged: ${why}`)
    }
  | Background({cwd, command, log}) =>
    Node.run("sh", ["-c", `cd '${cwd}' && nohup ${command} > '${log}' 2>&1 &`]) == 0
      ? Ok()
      : Error(`${command} did not start`)
  | MakeDir(dir) => nothingElse(~root, dir ++ Node.sep) ? Ok(Node.mkdirAll(dir)) : Error(dir)
  | Remove(path) =>
    nothingElse(~root, path)
      ? Ok(Node.rmSync(path, {recursive: true, force: true}))
      : Error(`${path} is outside lanes/, so it is not removed`)
  }

/** Every step in turn, stopping at the first that fails. */
let execute = (~root, steps) =>
  steps->Array.reduce(Ok(), (done, step) =>
    switch done {
    | Error(_) as failed => failed
    | Ok() => perform(~root, step)
    }
  )

let finish = (~root, ~dry, plan) =>
  switch plan {
  | Error(why) =>
    Console.error(why)
    1
  | Ok(steps) if dry =>
    steps->Array.forEach(step => Console.log(shown(step)))
    0
  | Ok(steps) =>
    switch execute(~root, steps) {
    | Ok() => 0
    | Error(why) =>
      Console.error(why)
      1
    }
  }

/** The `--with` repositories of an argument list and the words that are not flags. */
let parse = (argv: array<string>) => {
  let dry = argv->Array.some(arg => arg == "-n" || arg == "--dry-run")
  let rec go = (rest: list<string>, words, siblings) =>
    switch rest {
    | list{"--with", one, ...more} => go(more, words, Array.concat(siblings, [one]))
    | list{"-n" | "--dry-run", ...more} => go(more, words, siblings)
    | list{word, ...more} => go(more, Array.concat(words, [word]), siblings)
    | list{} => (words, siblings)
    }
  let (words, siblings) = go(argv->List.fromArray, [], [])
  (words, siblings, dry)
}

let usage =
  "usage: mise run lane open <repository|workspace> <name> " ++
  "[--with <repository> ...] [--dry-run]\n" ++ "       mise run lane close <name> [--dry-run]"

let main = (argv: array<string>): int => {
  let root = Registry.root
  let (words, siblings, dry) = parse(argv)
  let registered = Registry.paths()
  switch words {
  | ["open", target, name] =>
    openPlan(
      ~root,
      ~registered,
      ~cloned=one => Node.existsSync(Node.join([root, "repos", one])),
      ~exists=Node.existsSync,
      ~hasPackage=one => Node.existsSync(Node.join([source(~root, one), "package.json"])),
      {target, name, siblings},
    )->finish(~root, ~dry)
  | ["close", name] if siblings == [] =>
    let workspaces = Lane_state.workspacesOf(
      ~root,
      ~subdirs=Lane_state.realSubdirs,
      ~isWorkspace=Lane_state.realIsWorkspace,
      name,
    )
    closePlan(
      ~root,
      ~registered,
      ~hasCargo=dir => Node.existsSync(Node.join([dir, "Cargo.toml"])),
      ~name,
      workspaces,
    )->finish(~root, ~dry)
  | _ =>
    Console.error(usage)
    2
  }
}

if Node.isMain {
  Node.exit(main(Node.args()))
}
