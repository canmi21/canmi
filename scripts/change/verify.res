/**
 * The gates a change has to pass, chosen by what it touched, each repository calling it with its
 * own gates. See spec/architecture/repos.md, "verify runs what a change reaches".
 */
/** What a file reaches that no graph shows: packages or crates read rather than imported. */
type reach = {packages?: array<string>, crates?: array<string>}

/** A repository's gates, as its own `verify` task names them. */
type config = {
  layout: Graph.layout,
  /** Whole-tree and cheap, so they run whatever changed. */
  always: array<string>,
  /** Whole-program by nature: tsc, vitest and oxlint read everything they read. */
  node: array<string>,
  /** Gates that belong to one package, run when it or anything it imports changed. */
  packageGates: Dict.t<array<string>>,
  rust: array<string>,
  /** The tasks' own tests, run only when everything is. */
  tasks: array<string>,
  /** Rust files whose only check is a TypeScript test, as a generated mirror is. */
  nodeCheckedRust?: array<string>,
  /** Files no package owns that the whole-program gates still read. */
  nodeRead?: string => bool,
  /** What a file reaches that no graph shows. */
  reaches?: string => reach,
}

let nodeSuffixes = [
  ".ts",
  ".js",
  ".mjs",
  ".cjs",
  ".svelte",
  ".css",
  ".json",
  ".html",
  ".yaml",
  ".yml",
]
/** The gates themselves: a change to how anything is checked is checked against everything. */
let gateFile = "mise.toml"
let gateDirectory = ".mise/tasks/"
let nodeRootFiles = ["package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", "vitest.config.ts"]
let rustRootFiles = ["Cargo.toml", "Cargo.lock"]

/** Every gate the repository has, in the order they run. */
let everything = (config: config) =>
  [
    config.always,
    config.node,
    config.packageGates->Dict.valuesToArray->Array.flat,
    config.rust,
    config.tasks,
  ]->Array.flat

type plan = {
  gates: array<string>,
  /** The Rust packages to run them over, None meaning all. */
  crates: option<Set.t<string>>,
  /** Why every gate runs, where every gate does. */
  reason?: string,
}

let ownerIn = (file, map) => map->Map.get(Graph.owner(file, map->Graph.keysOf)->Option.getOr(""))

/** The gates to run for `files`, and the Rust packages to run them over. */
let plan = (config: config, files: array<string>): plan =>
  if files->Array.some(file => file == gateFile || file->String.startsWith(gateDirectory)) {
    {gates: everything(config), crates: None, reason: "the gates themselves changed"}
  } else {
    let layout = config.layout
    let {directories: crateDirs, edges: crateEdges, included} = Graph.rustGraph(layout.root)
    let built = Graph.buildInputs(layout.root, crateDirs)
    let {directories: packageDirs, edges: packageEdges} = Graph.nodeGraph(layout)
    let crates = Set.make()
    let packages = Set.make()
    let gates = config.always->Array.copy
    let allCrates = ref(false)
    let allPackages = ref(false)
    let read = ref(false)
    let addAll = (set, values) => values->Array.forEach(value => set->Set.add(value))

    files->Array.forEach(file => {
      let suffix = Node.extname(file)
      if rustRootFiles->Array.includes(file) || file == "rust-toolchain.toml" {
        allCrates := true
      }
      crates->addAll(included->Map.get(file)->Option.mapOr([], Graph.setValues))
      crates->addAll(
        built
        ->Map.get(Graph.owner(file, built->Graph.keysOf)->Option.getOr(file))
        ->Option.mapOr([], Graph.setValues),
      )
      let reach = switch config.reaches {
      | Some(reaches) => reaches(file)
      | None => {}
      }
      crates->addAll(reach.crates->Option.getOr([]))
      packages->addAll(reach.packages->Option.getOr([]))
      switch ownerIn(file, crateDirs) {
      | Some(crate) if suffix == ".rs" || file->String.endsWith("/Cargo.toml") =>
        crates->Set.add(crate)
      | _ => ()
      }
      if nodeRootFiles->Array.includes(file) || file->String.startsWith("tsconfig") {
        allPackages := true
      }
      let found = ownerIn(file, packageDirs)
      switch found {
      | Some(name)
        if nodeSuffixes->Array.includes(suffix) ||
          config.nodeCheckedRust->Option.mapOr(false, rust => rust->Array.includes(file)) =>
        packages->Set.add(name)
      | Some(_) => ()
      | None =>
        if (
          nodeSuffixes->Array.includes(suffix) &&
            config.nodeRead->Option.mapOr(false, nodeRead => nodeRead(file))
        ) {
          read := true
        }
      }
    })

    let reachedPackages = allPackages.contents
      ? packageDirs->Map.values->Iterator.toArray->Set.fromArray
      : Graph.dependents(packages->Graph.setValues, packageEdges)
    if reachedPackages->Set.size > 0 || read.contents {
      gates->Array.pushMany(config.node)
      config.packageGates
      ->Dict.toArray
      ->Array.forEach(((name, owned)) =>
        if reachedPackages->Set.has(name) {
          gates->Array.pushMany(owned)
        }
      )
    }
    let reachedCrates = allCrates.contents
      ? None
      : Some(Graph.dependents(crates->Graph.setValues, crateEdges))
    if allCrates.contents || reachedCrates->Option.mapOr(false, set => set->Set.size > 0) {
      gates->Array.pushMany(config.rust)
    }
    {gates, crates: reachedCrates}
  }

/** Whether `path` is an app's declaration, `service.toml` in any app's tree. */
let isDeclaration = (layout: Graph.layout, path: string): bool =>
  Graph.appOf(layout, path)->Option.isSome && path->String.endsWith("/service.toml")

/** A repository's `verify` task: the gates printed, then run, every one reporting. */
let main = (config: config, ~args=Node.args()) => {
  let root = config.layout.root

  // A library taken from the checkout beside this one is a state for trying a change, never one
  // to pass in: what it installed is nowhere a clone can reach.
  if Node.existsSync(Node.join([root, ".local", "lib"])) {
    Console.error("verify: the library is local; `mise run lib-local --off` first")
    Node.exit(1)
  }
  let dry = args->Array.includes("--dry-run") || args->Array.includes("-n")
  let after = flag => args->Array.includes(flag) ? args[args->Array.indexOf(flag) + 1] : None
  let since = after("--since")
  // `--files a b` asks what a change to exactly those files would run, without making it.
  let given =
    args->Array.includes("--files")
      ? Some(args->Array.slice(~start=args->Array.indexOf("--files") + 1))
      : None

  let chosen = if args->Array.includes("--all") || Node.envOn("AUDIT") {
    {gates: everything(config), crates: None, reason: "asked for everything"}
  } else {
    let files = switch given {
    | Some(files) => files
    | None => Graph.changed(root, ~since?)
    }
    let chosen = plan(config, files)
    let where = switch (given, since) {
    | (Some(_), _) => "given"
    | (None, Some(since)) => `since ${since}`
    | (None, None) => "in the working copy"
    }
    Console.log(`verify: ${Int.toString(files->Array.length)} file(s) ${where}`)
    chosen
  }
  switch chosen.reason {
  | Some(reason) => Console.log(`verify: every gate, because ${reason}`)
  | None => ()
  }
  let scope = switch chosen.crates {
  | None => "every crate"
  | Some(crates) =>
    switch crates->Graph.setValues->Graph.sortText->Array.join(", ") {
    | "" => "none"
    | some => some
    }
  }
  if chosen.gates->Array.includes("lint-rust") {
    Console.log(`verify: Rust over ${scope}`)
  }
  Console.log(`verify: ${chosen.gates->Array.join(" ")}`)
  if !dry {
    let environment = Dict.copy(Node.env)
    switch chosen.crates {
    | Some(crates) =>
      environment->Dict.set(
        "RUST_PACKAGES",
        crates->Graph.setValues->Graph.sortText->Array.map(crate => `-p ${crate}`)->Array.join(" "),
      )
    | None => ()
    }
    // Every gate reports, not only the first to fail: a red run is worth its whole list.
    let command = ["run", "--continue-on-error", chosen.gates->Array.getUnsafe(0)]
    chosen.gates
    ->Array.slice(~start=1)
    ->Array.forEach(gate => command->Array.pushMany([":::", gate]))
    let ran = Node.spawnWithEnv("mise", command, {cwd: root, env: environment, stdio: "inherit"})
    Node.exit(ran.status->Nullable.getOr(1))
  }
}

/** What a repository's `workspace.toml` declares, as the gates it runs. */
let fromDeclared = (layout: Graph.layout, declared: Project.verify): config => {
  layout,
  always: declared.always,
  node: declared.node,
  packageGates: declared.packages,
  rust: declared.rust,
  tasks: declared.tasks,
  nodeCheckedRust: declared.nodeCheckedRust,
  nodeRead: path => declared.nodeRead->Array.some(prefix => path->String.startsWith(prefix)),
  reaches: path => {
    let reached =
      declared.reaches->Array.filter(reach =>
        reach.under->Array.some(prefix => path->String.startsWith(prefix))
      )
    {
      packages: reached->Array.flatMap(reach => reach.packages),
      crates: reached->Array.flatMap(reach => reach.crates),
    }
  },
}

if Node.isMain {
  let (layout, declared) = Project.here("verify", declared => declared.verify)
  main(fromDeclared(layout, declared))
}
