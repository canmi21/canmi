/**
 * What a change needs built, as JSON, for the repository that calls it, as images, declarations
 * applied alone or Workers, each input read as a build reads it (fingerprint.res).
 */
/** How every image is built, so a change here is a change to all of them. */
let everyImage = [".dockerignore", ".mise/tasks/image"]
/** What every image is resolved from, read at both revisions; given files alone, every image. */
let resolution_ = ["Cargo.toml", "Cargo.lock"]
/**
 * What a Dockerfile copies from the context when its image is its crate's binary and nothing else.
 */
let workspaceInputs = ["Cargo.toml", "Cargo.lock", "apps", "libs"]
/** What every Node image installs from, read by importer; see lockfile.res. */
let lockfile = "pnpm-lock.yaml"
/** How every Worker is packaged, the same. */
let everyWorker = ["package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", ".mise/tasks/worker"]

/** Which Workers a repository packages, `only` narrowing them to those named. */
type workers = {only?: Set.t<string>}

/** A repository's Workers, none as `false` or those it packages. */
@unboxed
type packaged = | @as(false) NoWorkers | Workers(workers)

/** What a repository builds, as its own `deployable` task says. */
type config = {
  layout: Graph.layout,
  /** Whether its apps have images; one without them lists its Workers whatever it is asked. */
  images: bool,
  /** Its Workers, or false for a repository with none. */
  workers: packaged,
}

/** App name -> its crate's or its package's name, for what a run builds. */
type declared = Map.t<string, Nullable.t<string>>

let sortedKeys = (map: declared) => map->Graph.keysOf->Graph.sortText

/** App directory name -> its crate's name, for every app that declares an image. */
let apps = (layout: Graph.layout): declared => {
  let found = Map.make()
  layout
  ->Graph.appDirectories
  ->Map.forEachWithKey((directory, name) =>
    if (
      Node.existsSync(Node.join([directory, "service.toml"])) &&
      Node.existsSync(Node.join([directory, "Dockerfile"]))
    ) {
      let manifest = Node.join([directory, "Cargo.toml"])
      let line = Node.existsSync(manifest)
        ? Node.readFileSync(manifest)
          ->String.split("\n")
          ->Array.find(one => one->String.startsWith("name = "))
        : None
      found->Map.set(
        name,
        Nullable.make(
          line->Option.flatMap(line => line->String.split("\"")->Array.get(1))->Option.getOr(name),
        ),
      )
    }
  )
  found
}

/** App directory name -> its package's name, for every Workers app with a wrangler.jsonc. */
let workers = (layout: Graph.layout, ~only: option<Set.t<string>>=?): declared => {
  let found = Map.make()
  layout
  ->Graph.appDirectories
  ->Map.forEachWithKey((directory, name) => {
    let declared = Node.join([directory, "service.toml"])
    let wanted = only->Option.mapOr(true, only => only->Set.has(name))
    if (
      wanted &&
      Node.existsSync(declared) &&
      Node.existsSync(Node.join([directory, "wrangler.jsonc"]))
    ) {
      let placements = switch Toml.parse(Node.readFileSync(declared)) {
      | Object(data) =>
        switch data->Dict.get("placements") {
        | Some(Array(placements)) => placements
        | _ => []
        }
      | _ => []
      }
      if placements->Array.includes(JSON.String("workers")) {
        let manifest = Node.join([directory, "package.json"])
        let package = if Node.existsSync(manifest) {
          switch JSON.parseOrThrow(Node.readFileSync(manifest)) {
          | Object(data) =>
            switch data->Dict.get("name") {
            | Some(String(name)) => Nullable.make(name)
            | _ => Nullable.undefined
            }
          | _ => Nullable.undefined
          }
        } else {
          Nullable.null
        }
        found->Map.set(name, package)
      }
    }
  })
  found
}

/** Files changed between `base` and `head`, for CI, where there is git and no jj. */
let gitChanged = (root, base, ~head="HEAD") =>
  Node.execFileSync("git", ["diff", "--name-only", base, head], {cwd: root, encoding: "utf8"})
  ->String.split("\n")
  ->Array.filter(line => line != "")

/** A side of a comparison, as `needed` and `redeclared` read one. */
type readable = {read: string => option<string>, tree?: unit => string}

/** Temporary trees written for cargo, gone when the process is. */
let temporary = []
Node.onExit(() =>
  temporary->Array.forEach(tree => Node.rmSync(tree, {recursive: true, force: true}))
)

/**
 * One side of a comparison, the commit `commit` names or the files on disk where it is None,
 * its tree written out the first time cargo is asked about it.
 */
let revision = (root: string, ~commit: option<string>=?): readable => {
  let written = ref(None)
  {
    read: path =>
      switch commit {
      | None =>
        let file = Node.join([root, path])
        Node.existsSync(file) ? Some(Node.readFileSync(file)) : None
      | Some(commit) =>
        let answer = Node.spawnSync(
          "git",
          ["show", `${commit}:${path}`],
          {cwd: root, encoding: "utf8", maxBuffer: 268435456},
        )
        answer.status == Nullable.make(0) ? answer.stdout->Nullable.toOption : None
      },
    tree: () =>
      switch (commit, written.contents) {
      | (None, _) => root
      | (Some(_), Some(tree)) => tree
      | (Some(commit), None) =>
        let tree = Node.mkdtempSync(Node.join([Node.tmpdir(), "deployable-"]))
        temporary->Array.push(tree)
        let archive = Node.execBytes("git", ["archive", commit], {cwd: root, maxBuffer: 1073741824})
        Node.execBytes("tar", ["-x", "-C", tree], {input: archive})->ignore
        written := Some(tree)
        tree
      },
  }
}

/** The git commit a jj revision is, in a colocated repository. */
let jjCommit = (root, revision) =>
  Node.execFileSync(
    "jj",
    ["log", "--no-graph", "-r", revision, "-T", "commit_id"],
    {cwd: root, encoding: "utf8"},
  )

type revisions = option<(readable, readable)>

exception NoTree

/** The tree `side` is written out as, for cargo; a side that cannot write one throws. */
let treeOf = (side: readable) =>
  switch side.tree {
  | Some(tree) => tree()
  | None => throw(NoTree)
  }

/**
 * The crates a change to Cargo.lock or the root Cargo.toml reaches, or None for every image where
 * either cannot be read. A crate the lockfile moves is asked of cargo.
 */
let resolution = (
  root,
  files: array<string>,
  declared: declared,
  crateDirs: Map.t<string, string>,
  revisions: revisions,
) => {
  let touched = files->Array.filter(file => resolution_->Array.includes(file))->Set.fromArray
  if touched->Set.size == 0 {
    Some(Set.make())
  } else {
    switch revisions {
    | None => None
    | Some((base, head)) =>
      let moved = Set.make()
      try {
        let ok = ref(true)
        if touched->Set.has("Cargo.lock") {
          switch (base.read("Cargo.lock"), head.read("Cargo.lock")) {
          | (Some(before), Some(after)) =>
            let crates =
              declared
              ->Map.values
              ->Iterator.toArray
              ->Array.filterMap(crate =>
                crate->Nullable.toOption->Option.flatMap(crate => crate == "" ? None : Some(crate))
              )
              ->Set.fromArray
            let candidates = Resolved.lockMoved(before, after, crates)
            if candidates->Set.size > 0 {
              let reached = try Resolved.treeMoved(
                treeOf(base),
                treeOf(head),
                candidates->Graph.setValues,
                root,
              ) catch {
              // Where cargo cannot be asked, the lockfile's word stands.
              | _ => candidates
              }
              reached->Set.forEach(crate => moved->Set.add(crate))
            }
          | _ => ok := false
          }
        }
        if ok.contents && touched->Set.has("Cargo.toml") {
          switch (base.read("Cargo.toml"), head.read("Cargo.toml")) {
          | (Some(before), Some(after)) =>
            let members =
              crateDirs
              ->Map.entries
              ->Iterator.toArray
              ->Array.map(((directory, crate)) => (
                crate,
                Resolved.tableOf(
                  Some(Toml.parse(Node.readFileSync(Node.join([root, directory, "Cargo.toml"])))),
                ),
              ))
              ->Map.fromArray
            switch Resolved.manifestMoved(before, after, members) {
            | Some(reached) => reached->Set.forEach(crate => moved->Set.add(crate))
            | None => ok := false
            }
          | _ => ok := false
          }
        }
        ok.contents ? Some(moved) : None
      } catch {
      | _ => None
      }
    }
  }
}

let continuation = /\\\n/g
let lineBreak = /\r\n|\r|\n/

/**
 * What `dockerfile` copies from the build's context, every source of a `COPY` or `ADD` without
 * `--from` but an address, or None where it cannot be told.
 */
let copied = (dockerfile: string): option<Set.t<string>> => {
  let sources = Set.make()
  let unknown = ref(false)
  dockerfile
  ->String.replaceRegExp(continuation, " ")
  ->String.splitByRegExp(lineBreak)
  ->Array.forEach(line => {
    let words = Spawn.words(line)
    switch words[0] {
    | Some(first) if ["COPY", "ADD"]->Array.includes(first->String.toUpperCase) =>
      if words->Array.some(one => one->String.startsWith("[")) {
        unknown := true
      } else if !(words->Array.some(one => one->String.startsWith("--from"))) {
        let named =
          words->Array.slice(~start=1)->Array.filter(one => !(one->String.startsWith("--")))
        named
        ->Array.slice(~start=0, ~end=named->Array.length - 1)
        ->Array.forEach(one =>
          if !(one->String.includes("://")) {
            sources->Set.add(one)
          }
        )
      }
    | _ => ()
    }
  })
  unknown.contents ? None : Some(sources)
}

/**
 * The apps whose image is their crate's binary alone, copying nothing from the context but the
 * workspace.
 */
let cargoBuilt = (layout: Graph.layout, declared: declared, crateDirs: Map.t<string, string>) => {
  let crates = crateDirs->Map.values->Iterator.toArray->Set.fromArray
  let found = Set.make()
  layout
  ->Graph.appDirectories
  ->Map.forEachWithKey((directory, app) =>
    switch declared->Map.get(app)->Option.flatMap(Nullable.toOption) {
    | Some(crate) if crate != "" && crates->Set.has(crate) =>
      switch copied(Node.readFileSync(Node.join([directory, "Dockerfile"]))) {
      | Some(sources)
        if sources->Graph.setValues->Array.every(one => workspaceInputs->Array.includes(one)) =>
        found->Set.add(app)
      | _ => ()
      }
    | _ => ()
    }
  )
  found
}

/** Those of `files` that change a build, not ignored and, given revisions, read differently. */
let changes = (files: array<string>, crateDirs: array<string>, revisions: revisions) => {
  let kept = files->Array.filter(file => !Fingerprint.ignored(file, ~crateDirectories=crateDirs))
  switch revisions {
  | None => kept
  | Some((base, head)) =>
    kept->Array.filter(file =>
      !Fingerprint.normalized(file) || !Fingerprint.same(file, base.read(file), head.read(file))
    )
  }
}

/** Whether `path` is an app's own `service.toml`, directly in its directory. */
let declaration = (layout: Graph.layout, path: string) =>
  switch Graph.appOf(layout, path) {
  | Some(app) => path->String.endsWith(`/${app}/service.toml`)
  | None => false
  }

/**
 * The apps of `declared` built from a package that imports one `moving` changed, a lockfile
 * change counting where it moved the importer or cannot tell. RFC l6r4u.
 */
let imported = (
  layout: Graph.layout,
  moving: array<string>,
  declared: declared,
  binary: Set.t<string>,
  revisions: revisions,
) => {
  let {directories, edges}: Graph.nodeGraph = Graph.nodeGraph(layout)
  let changedPackages = Set.make()
  if moving->Array.includes(lockfile) {
    let moved = switch revisions {
    | Some((base, head)) =>
      switch (base.read(lockfile), head.read(lockfile)) {
      | (Some(before), Some(after)) => Some(Lockfile.movedImporters(before, after))
      | _ => None
      }
    | None => None
    }
    directories->Map.forEachWithKey((name, directory) =>
      if moved->Option.mapOr(true, moved => moved->Set.has(directory)) {
        changedPackages->Set.add(name)
      }
    )
  }
  moving->Array.forEach(file =>
    // A declaration is host's to read, never bundled, as an app's own is.
    if !declaration(layout, file) {
      switch Verify.ownerIn(file, directories) {
      | Some(found) => changedPackages->Set.add(found)
      | None => ()
      }
    }
  )
  let chosen = Set.make()
  if changedPackages->Set.size > 0 {
    let reached = Graph.dependents(changedPackages->Graph.setValues, edges)
    directories->Map.forEachWithKey((name, directory) =>
      switch Graph.appOf(layout, `${directory}/package.json`) {
      | Some(app) if declared->Map.has(app) && !(binary->Set.has(app)) && reached->Set.has(name) =>
        chosen->Set.add(app)
      | _ => ()
      }
    )
  }
  chosen
}

/** The apps `files` need rebuilt; `revisions` reads a file before and after, as (base, head). */
let needed = (
  layout: Graph.layout,
  files: array<string>,
  declared: declared,
  ~revisions: revisions=None,
) => {
  let {directories: crateDirs, edges: crateEdges}: Graph.rustGraph = Graph.rustGraph(layout.root)
  let moving = changes(files, crateDirs->Graph.keysOf, revisions)
  if moving->Array.some(file => everyImage->Array.includes(file)) {
    declared->sortedKeys
  } else {
    let built = Graph.buildInputs(layout.root, crateDirs)
    // A file a binary includes outside its tests is in the binary byte for byte, as is what a build
    // script reads.
    let carried = Graph.embedded(layout.root, crateDirs)
    let crates = Set.make()
    let chosen = Set.make()
    let addAll = values => values->Array.forEach(value => crates->Set.add(value))
    files->Array.forEach(file => {
      addAll(
        built
        ->Map.get(Graph.owner(file, built->Graph.keysOf)->Option.getOr(file))
        ->Option.mapOr([], Graph.setValues),
      )
      addAll(carried->Map.get(file)->Option.mapOr([], Graph.setValues))
    })
    let binary = cargoBuilt(layout, declared, crateDirs)
    moving->Array.forEach(file => {
      switch Graph.appOf(layout, file) {
      | Some(app)
        if declared->Map.has(app) &&
        !declaration(layout, file) &&
        (!(binary->Set.has(app)) || file->String.endsWith("/Dockerfile")) =>
        chosen->Set.add(app)
      | _ => ()
      }
      switch Verify.ownerIn(file, crateDirs) {
      | Some(crate) if file->String.endsWith(".rs") || file->String.endsWith("/Cargo.toml") =>
        crates->Set.add(crate)
      | _ => ()
      }
    })
    imported(layout, moving, declared, binary, revisions)->Set.forEach(app => chosen->Set.add(app))
    switch resolution(layout.root, files, declared, crateDirs, revisions) {
    | None => declared->sortedKeys
    | Some(moved) =>
      let reached = Graph.dependents(
        Array.concat(crates->Graph.setValues, moved->Graph.setValues),
        crateEdges,
      )
      declared->Map.forEachWithKey((crate, app) =>
        switch crate->Nullable.toOption {
        | Some(crate) if reached->Set.has(crate) => chosen->Set.add(app)
        | _ => ()
        }
      )
      chosen->Graph.setValues->Graph.sortText
    }
  }
}

/** The apps whose own `service.toml` changed, and whose image is not among `rebuilt`. */
let redeclared = (
  layout: Graph.layout,
  files: array<string>,
  declared: declared,
  rebuilt: array<string>,
  ~revisions: revisions=None,
) => {
  let moving = revisions == None ? files : changes(files, [], revisions)
  moving
  ->Array.filterMap(file =>
    switch Graph.appOf(layout, file) {
    | Some(app) if declaration(layout, file) && declared->Map.has(app) => Some(app)
    | _ => None
    }
  )
  ->Set.fromArray
  ->Graph.setValues
  ->Array.filter(app => !(rebuilt->Array.includes(app)))
  ->Graph.sortText
}

/** The Workers `files` need packaged. */
let neededWorkers = (layout: Graph.layout, files: array<string>, declared: declared) =>
  if files->Array.some(file => everyWorker->Array.includes(file)) {
    declared->sortedKeys
  } else {
    let {directories: packageDirs, edges: packageEdges}: Graph.nodeGraph = Graph.nodeGraph(layout)
    let packages = Set.make()
    let chosen = Set.make()
    files->Array.forEach(file => {
      switch Graph.appOf(layout, file) {
      | Some(app) if declared->Map.has(app) => chosen->Set.add(app)
      | _ => ()
      }
      switch Verify.ownerIn(file, packageDirs) {
      | Some(found) => packages->Set.add(found)
      | None => ()
      }
    })
    let reached = Graph.dependents(packages->Graph.setValues, packageEdges)
    declared->Map.forEachWithKey((name, app) =>
      switch name->Nullable.toOption {
      | Some(name) if reached->Set.has(name) => chosen->Set.add(app)
      | _ => ()
      }
    )
    chosen->Graph.setValues->Graph.sortText
  }

/**
 * The files a change touched and the revisions to read them at, `--files` with none, `--git`
 * between two commits, and otherwise the working copy against `--since` or its parent.
 */
let inputs = (root, args: array<string>): (array<string>, revisions) => {
  let after = flag => args[args->Array.indexOf(flag) + 1]
  if args->Array.includes("--files") {
    (args->Array.slice(~start=args->Array.indexOf("--files") + 1), None)
  } else if args->Array.includes("--git") {
    let base = after("--git")->Option.getOr("")
    let head = args->Array.includes("--head") ? after("--head")->Option.getOr("HEAD") : "HEAD"
    // HEAD is what CI checked out, so its tree is the one on disk.
    let later = head == "HEAD" ? revision(root) : revision(root, ~commit=head)
    (gitChanged(root, base, ~head), Some((revision(root, ~commit=base), later)))
  } else {
    let since = args->Array.includes("--since") ? after("--since") : None
    let files = Graph.changed(root, ~since?)
    try {
      (
        files,
        Some((revision(root, ~commit=jjCommit(root, since->Option.getOr("@-"))), revision(root))),
      )
    } catch {
    | _ => (files, None)
    }
  }
}

exception Refused(string)

/** The list a repository's `deployable` prints for `args`. */
let deployable = (config: config, args: array<string>): array<string> => {
  let layout = config.layout
  if args->Array.includes("--declared") {
    if !config.images {
      throw(Refused("--declared lists images, and this repository builds none"))
    }

    // Everything rebuilt leaves no declaration to apply alone.
    if args->Array.includes("--all") {
      []
    } else {
      let declared = apps(layout)
      let (files, revisions) = inputs(layout.root, args)
      redeclared(layout, files, declared, needed(layout, files, declared, ~revisions), ~revisions)
    }
  } else {
    let worker = !config.images || args->Array.includes("--workers")
    let packaged = switch config.workers {
    | NoWorkers => None
    | Workers(workers) => Some(workers.only)
    }
    if worker && packaged == None {
      throw(Refused("--workers lists Workers, and this repository packages none"))
    }
    let declared = switch (worker, packaged) {
    | (true, Some(only)) => workers(layout, ~only?)
    | _ => apps(layout)
    }
    if args->Array.includes("--all") {
      declared->sortedKeys
    } else {
      let (files, revisions) = inputs(layout.root, args)
      worker ? neededWorkers(layout, files, declared) : needed(layout, files, declared, ~revisions)
    }
  }
}

/** A repository's `deployable` task, the list as JSON on stdout or the reason on stderr. */
let main = (config: config, ~args=Node.args()) =>
  try {
    Console.log(JSON.stringifyAny(deployable(config, args))->Option.getOr("[]"))
  } catch {
  | Refused(why) =>
    Console.error(`deployable: ${why}`)
    Node.exit(1)
  | JsExn(error) =>
    Console.error(`deployable: ${error->JsExn.message->Option.getOr("")}`)
    Node.exit(1)
  }

/** What a repository's `workspace.toml` declares, as what it builds. */
let fromDeclared = (layout: Graph.layout, declared: Project.deployable): config => {
  layout,
  images: declared.images,
  workers: switch declared.workers {
  | None => NoWorkers
  | All => Workers({})
  | Only(names) => Workers({only: Set.fromArray(names)})
  },
}

if Node.isMain {
  let (layout, declared) = Project.here("deployable", declared => declared.deployable)
  main(fromDeclared(layout, declared))
}
