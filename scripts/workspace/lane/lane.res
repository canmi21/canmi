/**
 * `lane open <repository|workspace> <name> [--with <repository> ...] [--dry-run]`, which also
 * places every repository the target's workspace.toml [boundary] depends names, and
 * `lane close <name> [--dry-run]`, `lane handed <name> [--own <directory> ...]`, and `lane check`
 * and `lane take`, each in a file of its own, docs/agents/lanes.md.
 */
type step =
  | Run({cwd: string, program: string, args: array<string>})
  | Guard({cwd: string, dir: string})
  | Background({cwd: string, command: string, log: string})
  | Handed({cwd: string, dir: string, own: array<string>, all: bool, integrator: bool})
  | MakeDir(string)
  | Remove(string)
  | Say(string)

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

/** The repositories a workspace.toml's [boundary] depends names, each line cut at its colon. */
let dependsOf = (text: string): array<(string, string)> =>
  switch Toml.parse(text) {
  | Object(top) =>
    switch top->Dict.get("boundary") {
    | Some(Object(boundary)) =>
      switch boundary->Dict.get("depends") {
      | Some(Array(lines)) =>
        lines->Array.filterMap(line =>
          switch line {
          | String(line) => Some((line->String.split(":")->Array.getUnsafe(0), line))
          | _ => None
          }
        )
      | _ => []
      }
    | _ => []
    }
  | _ => []
  }

/**
 * The repositories `target` depends on, transitively, each as (repository, the one whose
 * depends names it, that line), in the order met. `depends` gives one repository's direct lines.
 */
let boundarySiblings = (~depends: string => array<(string, string)>, target) => {
  let rec go = (queue, seen, found) =>
    switch queue {
    | list{} => found
    | list{one, ...more} =>
      let (seen, fresh) =
        depends(one)->Array.reduce((seen, []), ((seen, fresh), (repo, line)) =>
          seen->Array.includes(repo)
            ? (seen, fresh)
            : (Array.concat(seen, [repo]), Array.concat(fresh, [(repo, one, line)]))
        )
      go(
        List.concat(more, fresh->Array.map(((repo, _, _)) => repo)->List.fromArray),
        seen,
        Array.concat(found, fresh),
      )
    }
  go(list{target}, [target], [])
}

/** The base workspace a root belongs to, the root itself where it is no lane's copy. */
let baseOf = root => {
  let marker = `${Node.sep}lanes${Node.sep}`
  root->String.includes(marker) ? root->String.split(marker)->Array.getUnsafe(0) : root
}

/** What the steps of an open are, or why they cannot be. */
let openPlan = (
  ~root,
  ~registered,
  ~cloned,
  ~exists,
  ~hasPackage,
  ~depends=_ => [],
  {target, name, siblings}: opened,
) => {
  let named = Array.concat([target], siblings)
  let beside =
    boundarySiblings(~depends, target)->Array.filter(((repo, _, _)) =>
      !(named->Array.includes(repo))
    )
  let reason = repo =>
    beside->Array.findMap(((one, from, line)) => one == repo ? Some((from, line)) : None)
  let all = Array.concat(named, beside->Array.map(((repo, _, _)) => repo))
  let unknown = all->Array.find(one => one != "workspace" && !(registered->Array.includes(one)))
  let missing = all->Array.find(one => one != "workspace" && !cloned(one))
  let nested =
    all->Array.includes("workspace") && all->Array.some(one => one->String.startsWith("canmi/"))
  switch (fromBase(root), unknown, missing) {
  | (Error(why), _, _) => Error(why)
  | _ if !(namePattern->RegExp.test(name)) =>
    Error(`${name} is no lane name, which is lowercase words joined by hyphens`)
  | _ if named->Array.length != Set.fromArray(named)->Set.size =>
    Error("a repository is named twice")
  | _ if exists(Node.join([Lane_state.lanes(root), name])) => Error(`lanes/${name} exists already`)
  | (_, Some(one), _) => Error(`${one} is no repository of repos/registry.toml`)
  | (_, _, Some(one)) => Error(`${one} is not cloned`)
  | _ if nested =>
    Error("the workspace's lane holds canmi, which a canmi/ repository would nest in")
  | _ =>
    Ok(
      all->Array.flatMap(one => {
        let there = destination(~root, ~name, one)
        // Platform's libraries are generated before the lane is handed over, target or beside.
        let generated = one == "monoflake/platform"
        let log = Node.join([
          Lane_state.lanes(root),
          name,
          `${one->String.replaceAll("/", "-")}-install.log`,
        ])
        Array.flat([
          switch reason(one) {
          | Some((from, line)) => [
              Say(`${one} beside, as ${from}'s boundary depends names ${line}`),
            ]
          | None => []
          },
          [
            MakeDir(Node.dirname(there)),
            Run({
              cwd: source(~root, one),
              program: "jj",
              args: ["workspace", "add", "--name", name, "-r", "main", there],
            }),
          ],
          switch (hasPackage(one), generated) {
          | (false, _) => []
          | (true, true) => [
              Run({
                cwd: there,
                program: "sh",
                args: [
                  "-c",
                  `(pnpm install --frozen-lockfile && rescript build && mise run generate) > '${log}' 2>&1`,
                ],
              }),
            ]
          | (true, false) => [
              Background({cwd: there, command: "pnpm install --frozen-lockfile", log}),
            ]
          },
        ])
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
          Handed({
            cwd: one.path,
            dir: `lanes/${name}/${one.rel}`,
            own: [],
            all: false,
            integrator: false,
          }),
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

/** What the steps of a handing in are, every workspace of the lane judged by every rule. */
let handedPlan = (
  ~root,
  ~registered,
  ~own,
  ~name,
  ~integrator=false,
  workspaces: array<Lane_state.found>,
) =>
  switch (fromBase(root), workspaces) {
  | (Error(why), _) => Error(why)
  | _ if !(namePattern->RegExp.test(name)) =>
    Error(`${name} is no lane name, which is lowercase words joined by hyphens`)
  | (_, []) => Error(`lanes/${name} holds no jj workspace`)
  | _ if workspaces->Array.some(one => Lane_state.sourceOf(~root, ~registered, one.rel) == None) =>
    Error(`lanes/${name} holds a path that is neither canmi nor a registered repository's`)
  | _ =>
    Ok(
      workspaces->Array.map(one => Handed({
        cwd: one.path,
        dir: `lanes/${name}/${one.rel}`,
        own,
        all: true,
        integrator,
      })),
    )
  }

let shown = step =>
  switch step {
  | Run({cwd, program, args}) => `(in ${cwd}) ${program} ${args->Array.join(" ")}`
  | Guard({cwd, dir}) => `(in ${cwd}) refuse if jj log -r '${unlanded}' lists a change, ${dir}`
  | Background({cwd, command, log}) => `(in ${cwd}) ${command} in the background, log ${log}`
  | Handed({cwd, all}) =>
    `(in ${cwd}) judge the files changed from main, ${all ? "every rule" : "lengths"}`
  | MakeDir(dir) => `mkdir -p ${dir}`
  | Remove(path) => `remove ${path}`
  | Say(text) => `note: ${text}`
  }

/** The stdout lines of a jj command run in `cwd`, or why it failed. */
let jjLines = (cwd, args) => {
  let answer = Node.spawnSync("jj", args, {cwd, encoding: "utf8", maxBuffer: 268435456})
  answer.status->Nullable.toOption == Some(0)
    ? Ok(
        answer.stdout
        ->Nullable.getOr("")
        ->String.split("\n")
        ->Array.map(String.trim)
        ->Array.filter(line => line != ""),
      )
    : Error(answer.stderr->Nullable.getOr("jj failed")->String.trim)
}

/** Paths the lane's own change touches that main neither equals nor has moved on since the fork. */
let notHeld = (~touched, ~differ, ~moved) =>
  touched->Array.filter(path => differ->Array.includes(path) && !(moved->Array.includes(path)))

let fileset = path =>
  `root-file:"${path->String.replaceAll("\\", "\\\\")->String.replaceAll("\"", "\\\"")}"`

/**
 * The changes of a working copy that main lacks, one per line, or the failure to read them. A
 * change counts as held when each path the lane touched equals main's or main changed it after the
 * fork. That misses a path main changed for another reason without taking the lane's edit.
 */
let unlandedIn = cwd =>
  switch jjLines(
    cwd,
    [
      "log",
      "-r",
      unlanded,
      "--no-graph",
      "-T",
      `change_id.short() ++ " " ++ description.first_line() ++ "\\n"`,
    ],
  ) {
  | Error(why) => Error(why)
  | Ok([]) => Ok("")
  | Ok(changes) =>
    let fork = "fork_point(main | @)"
    switch jjLines(cwd, ["diff", "--from", fork, "--to", "@", "--name-only"]) {
    | Error(why) => Error(why)
    | Ok([]) => Ok("")
    | Ok(touched) =>
      let only = touched->Array.map(fileset)
      switch (
        jjLines(cwd, Array.concat(["diff", "--from", "main", "--to", "@", "--name-only"], only)),
        jjLines(cwd, Array.concat(["diff", "--from", fork, "--to", "main", "--name-only"], only)),
      ) {
      | (Ok(differ), Ok(moved)) =>
        notHeld(~touched, ~differ, ~moved) == [] ? Ok("") : Ok(changes->Array.join("\n"))
      | (Error(why), _) | (_, Error(why)) => Error(why)
      }
    }
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
  | Handed({cwd, dir, own, all, integrator}) =>
    Handed.report(~cwd, ~dir, ~own, ~all, ~integrator) == 0
      ? Ok()
      : Error(`${dir} holds a change that is refused above, so it stays open`)
  | Background({cwd, command, log}) =>
    Node.run(
      "sh",
      ["-c", `cd '${cwd}' && nohup sh -c '${command}; echo "exit: $?"' > '${log}' 2>&1 &`],
    ) == 0
      ? Ok()
      : Error(`${command} did not start`)
  | Say(text) => Ok(Console.log(text))
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

/** The `--with` repositories, `--own` directories and the words of an argument list. */
let parse = (argv: array<string>) => {
  let dry = argv->Array.some(arg => arg == "-n" || arg == "--dry-run")
  let rec go = (rest: list<string>, words, siblings, own) =>
    switch rest {
    | list{"--with", one, ...more} => go(more, words, Array.concat(siblings, [one]), own)
    | list{"--own" | "--in", one, ...more} => go(more, words, siblings, Array.concat(own, [one]))
    | list{"-n" | "--dry-run" | "--integrator", ...more} => go(more, words, siblings, own)
    | list{word, ...more} => go(more, Array.concat(words, [word]), siblings, own)
    | list{} => (words, siblings, own)
    }
  let (words, siblings, own) = go(argv->List.fromArray, [], [], [])
  (words, siblings, own, dry)
}

let usage =
  "usage: mise run lane open <repository|workspace> <name> " ++
  "[--with <repository> ...] [--dry-run]\n" ++
  "       mise run lane close <name> [--dry-run]\n" ++
  "       mise run //:lane handed <name> [--own <directory> ...] [--dry-run]\n" ++
  "       mise run //:lane check <part> ... [--dry-run], from inside the lane\n" ++ "       mise run //:lane take <name> [--in <repository>] [--dry-run]"

let main = (argv: array<string>): int => {
  let root = Registry.root
  let (words, siblings, own, dry) = parse(argv)
  let integrator = argv->Array.includes("--integrator")
  let registered = Registry.paths()
  switch words {
  | _ if words[0] == Some("check") => Lane_check.main(words->Array.slice(~start=1), ~dry)
  | ["open", target, name] =>
    openPlan(
      ~root,
      ~registered,
      ~cloned=one => Node.existsSync(Node.join([root, "repos", one])),
      ~exists=Node.existsSync,
      ~hasPackage=one => Node.existsSync(Node.join([source(~root, one), "package.json"])),
      ~depends=one => {
        let file = Node.join([source(~root, one), "workspace.toml"])
        Node.existsSync(file) ? dependsOf(Node.readFileSync(file)) : []
      },
      {target, name, siblings},
    )->finish(~root, ~dry)
  | ["take", name] if siblings == [] && fromBase(root) != Ok() =>
    Console.error(`run lane take ${name} from the base workspace, not from inside a lane`)
    1
  | ["take", name] if siblings == [] =>
    Lane_state.workspacesOf(
      ~root,
      ~subdirs=Lane_state.realSubdirs,
      ~isWorkspace=Lane_state.realIsWorkspace,
      name,
    )
    ->Array.filter(one => own == [] || own->Array.includes(one.rel))
    ->Lane_take.main(~root, ~registered, ~name, ~dry, ~handed=one =>
      Handed_pass.held(~root, ~name, one)
    )
  | ["handed", name] if siblings == [] =>
    let root = baseOf(root)
    let workspaces = Lane_state.workspacesOf(
      ~root,
      ~subdirs=Lane_state.realSubdirs,
      ~isWorkspace=Lane_state.realIsWorkspace,
      name,
    )
    let plan = handedPlan(~root, ~registered, ~own, ~name, ~integrator, workspaces)
    // A pass is recorded for take to read, docs/agents/lanes.md, so a dry run records none.
    switch plan {
    | Ok(_) if !dry =>
      Handed_pass.judged(~root, ~name, ~integrator, workspaces, () => finish(~root, ~dry, plan))
    | _ => finish(~root, ~dry, plan)
    }
  | ["close", name] if siblings == [] && own == [] =>
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
