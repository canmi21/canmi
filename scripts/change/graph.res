/**
 * What a change reaches in one repository, its Rust crates, TypeScript packages and the edges
 * between them. Read by verify.res and deployable.res.
 */
/** Where a repository keeps its apps and packages. */
type layout = {
  /** The repository's root, absolute. */
  root: string,
  /** Where a package's manifest sits, each part a name or a star for one directory level. */
  packageDirectories: array<string>,
  /** The directories an app's own directory sits in, relative to the root. */
  appRoots: array<string>,
}

/** dependency -> its dependents, or path -> what reads it. */
type edges = Map.t<string, Set.t<string>>

let sortText = (values: array<string>) => values->Array.toSorted(String.compare)
let keysOf = map => map->Map.keys->Iterator.toArray
let setValues = set => set->Set.values->Iterator.toArray

/** The directories directly under `directory`, sorted, or none where it is not one. */
let subdirectories = directory =>
  Node.existsSync(directory)
    ? Node.entries(directory)
      ->Array.filter(Node.isDirectory)
      ->Array.map(Node.name)
      ->sortText
    : []

/** Every directory under `root` a pattern of literal names and `*` names, sorted. */
let expanded = (root, pattern) =>
  pattern
  ->String.split("/")
  ->Array.reduce([root], (found, part) =>
    found->Array.flatMap(at =>
      part == "*"
        ? subdirectories(at)->Array.map(name => Node.join([at, name]))
        : Node.existsSync(Node.join([at, part]))
        ? [Node.join([at, part])]
        : []
    )
  )

/** Each group under `apps/`, for a repository that groups its apps. */
let groupedAppRoots = root =>
  subdirectories(Node.join([root, "apps"]))->Array.map(group => `apps/${group}`)

/** Every app directory, absolute, by its name; a name is the app's wherever its layer puts it. */
let appDirectories = (layout: layout): Map.t<string, string> => {
  let found = Map.make()
  layout.appRoots->Array.forEach(appRoot =>
    subdirectories(Node.join([layout.root, appRoot]))->Array.forEach(name =>
      found->Map.set(name, Node.join([layout.root, appRoot, name]))
    )
  )
  found
}

/** The app `path` sits in, by name, or None for a path in no app. */
let appOf = (layout: layout, path: string): option<string> =>
  layout.appRoots->Array.reduce(None, (found, appRoot) =>
    switch found {
    | Some(_) => found
    | None if path->String.startsWith(`${appRoot}/`) =>
      let rest = path->String.slice(~start=appRoot->String.length + 1)->String.split("/")
      rest->Array.length > 1 ? rest[0] : None
    | None => None
    }
  )

/** Files the working copy changes, or everything after `since`. */
let changed = (root, ~since=?) => {
  let range = switch since {
  | Some(since) => ["--from", since, "--to", "@"]
  | None => ["-r", "@"]
  }
  Node.execFileSync(
    "jj",
    Array.concat(["diff", "--name-only"], range),
    {cwd: root, encoding: "utf8"},
  )
  ->String.split("\n")
  ->Array.filter(line => line != "")
}

/** The deepest of `directories` holding `path`, or None. */
let owner = (path: string, directories: array<string>): option<string> =>
  directories->Array.reduce(None, (best, directory) =>
    path->String.startsWith(`${directory}/`) &&
      best->Option.mapOr(true, best => directory->String.length > best->String.length)
      ? Some(directory)
      : best
  )

/** `affected` and everything that depends on it, through `edges` of dependency -> dependent. */
let dependents = (affected: array<string>, edges: edges): Set.t<string> => {
  let seen = Set.fromArray(affected)
  let queue = seen->setValues
  while queue->Array.length > 0 {
    let next = queue->Array.pop->Option.getOrThrow
    edges
    ->Map.get(next)
    ->Option.mapOr([], setValues)
    ->Array.forEach(dependent =>
      if !(seen->Set.has(dependent)) {
        seen->Set.add(dependent)
        queue->Array.push(dependent)
      }
    )
  }
  seen
}

let add = (edges: edges, key, value) =>
  switch edges->Map.get(key) {
  | Some(held) => held->Set.add(value)
  | None => edges->Map.set(key, Set.fromArray([value]))
  }

/** Every `.rs` file under `directory`, at any depth, but none under a `target` directory. */
let rustSources = directory => {
  let found = []
  let rec walk = at =>
    Node.entries(at)->Array.forEach(entry => {
      let path = Node.join([at, entry->Node.name])
      if entry->Node.isDirectory {
        if entry->Node.name != "target" {
          walk(path)
        }
      } else if entry->Node.name->String.endsWith(".rs") {
        found->Array.push(path)
      }
    })
  if Node.existsSync(directory) {
    walk(directory)
  }
  found->sortText
}

let include_ = /include_(?:str|bytes)!\(\s*"([^"]+)"/g

/** Every first group of global `pattern` in `text`, in order. */
let groups = (pattern: RegExp.t, text: string): array<string> => {
  let found = []
  pattern->RegExp.setLastIndex(0)
  let rec next = () =>
    switch pattern->RegExp.exec(text) {
    | Some(result) =>
      switch result->RegExp.Result.matches->Array.get(0) {
      | Some(Some(group)) => found->Array.push(group)
      | _ => ()
      }
      next()
    | None => ()
    }
  next()
  found
}

/** `path` with its links resolved where it exists, as Python's `Path.resolve` reads it. */
let resolved = path => {
  let absolute = Node.resolve([path])
  Node.existsSync(absolute) ? Node.realpathSync(absolute) : absolute
}

/** `target` relative to `root`, or None where it is outside it. */
let within = (root, target) => {
  let rest = Node.relative(root, target)
  rest != "" && !(rest->String.startsWith(`..${Node.sep}`)) && rest != ".."
    ? Some(rest->String.split(Node.sep)->Array.join("/"))
    : None
}

/** What each of `source`'s include literals names, relative to `root`, where it is inside it. */
let includes = (root, source, text) =>
  groups(include_, text)->Array.filterMap(path =>
    within(root, resolved(Node.join([Node.dirname(source), path])))
  )

type rustGraph = {
  /** Crate directory, relative to the root -> the crate's name. */
  directories: Map.t<string, string>,
  /** Dependency -> dependent, among the repository's own crates. */
  edges: edges,
  /** File -> the crates whose sources include it, a test's include among them. */
  included: edges,
}

let text = (dict, key) =>
  switch dict->Dict.get(key) {
  | Some(JSON.String(value)) => Some(value)
  | _ => None
  }

/** Crate directories, dependency -> dependent edges, and file -> crates that include it. */
let rustGraph = (root: string): rustGraph => {
  let metadata = Node.execFileSync(
    "cargo",
    ["metadata", "--no-deps", "--format-version", "1"],
    {cwd: root, encoding: "utf8", maxBuffer: 67108864},
  )
  let packages = switch JSON.parseOrThrow(metadata) {
  | Object(data) =>
    switch data->Dict.get("packages") {
    | Some(Array(packages)) =>
      packages->Array.filterMap(one =>
        switch one {
        | Object(one) => Some(one)
        | _ => None
        }
      )
    | _ => []
    }
  | _ => []
  }
  let real = resolved(root)
  let directories = Map.make()
  let edges = Map.make()
  let included = Map.make()
  let names = packages->Array.filterMap(one => one->text("name"))->Set.fromArray
  packages->Array.forEach(one => {
    let name = one->text("name")->Option.getOr("")
    let directory = Node.dirname(one->text("manifest_path")->Option.getOr(""))
    // The root's own crate is `.`, as a path relative to itself reads.
    directories->Map.set(within(real, resolved(directory))->Option.getOr("."), name)
    switch one->Dict.get("dependencies") {
    | Some(Array(dependencies)) =>
      dependencies->Array.forEach(dependency =>
        switch dependency {
        | Object(dependency) =>
          switch (dependency->text("path"), dependency->text("name")) {
          | (Some(_), Some(dependency)) if names->Set.has(dependency) =>
            add(edges, dependency, name)
          | _ => ()
          }
        | _ => ()
        }
      )
    | _ => ()
    }
    // A test reading another crate's file depends on it without the manifest saying so.
    rustSources(directory)->Array.forEach(source =>
      includes(real, source, Node.readFileSync(source))->Array.forEach(
        path => add(included, path, name),
      )
    )
  })
  {directories, edges, included}
}

/** The path of a module `name` declared out of line in `source`, where either file exists. */
let moduleFile = (source, name) => {
  let file = Node.basename(source)
  let base =
    ["lib.rs", "main.rs", "mod.rs"]->Array.includes(file)
      ? Node.dirname(source)
      : Node.join([
          Node.dirname(source),
          file->String.slice(~start=0, ~end=file->String.length - 3),
        ])
  [Node.join([base, `${name}.rs`]), Node.join([base, name, "mod.rs"])]->Array.find(Node.existsSync)
}

let testModule = /#\[cfg\(test\)\]\s*(?:#\[[^\]]*\]\s*)*(?:pub(?:\([^)]*\))?\s+)?mod\s+(\w+)\s*;/g

/**
 * The files of `sources` that are test modules declared out of line, and all beneath one's
 * directory.
 */
let testModules = (sources: array<string>) => {
  let tests = Set.make()
  sources->Array.forEach(source =>
    groups(testModule, Node.readFileSync(source))->Array.forEach(name =>
      switch moduleFile(source, name) {
      | Some(file) =>
        tests->Set.add(file)
        let below =
          Node.basename(file) == "mod.rs"
            ? Node.dirname(file)
            : file->String.slice(~start=0, ~end=file->String.length - 3)
        sources->Array.forEach(
          one =>
            if one->String.startsWith(`${below}${Node.sep}`) {
              tests->Set.add(one)
            },
        )
      | None => ()
      }
    )
  )
  tests
}

/**
 * Path to the crates whose own code includes it with `include_str!` or `include_bytes!`, a test's
 * include aside.
 */
let embedded = (root, directories: Map.t<string, string>): edges => {
  let real = resolved(root)
  let found = Map.make()
  directories->Map.forEachWithKey((crate, directory) => {
    let top = Node.join([real, directory])
    let sources =
      rustSources(top)->Array.filter(source =>
        !(Node.relative(top, source)->String.split(Node.sep)->Array.includes("tests"))
      )
    let tests = testModules(sources)
    sources->Array.forEach(source =>
      if !(tests->Set.has(source)) {
        let text = Node.readFileSync(source)->String.split("#[cfg(test)]")->Array.getUnsafe(0)
        includes(real, source, text)->Array.forEach(path => add(found, path, crate))
      }
    )
  })
  found
}

let buildLiteral = /"(\.\.?\/[^"]+)"/g

/** Path to the crates whose build script reads it, a relative literal in `build.rs`. */
let buildInputs = (root, directories: Map.t<string, string>): edges => {
  let real = resolved(root)
  let inputs = Map.make()
  directories->Map.forEachWithKey((crate, directory) => {
    let script = Node.join([real, directory, "build.rs"])
    if Node.existsSync(script) {
      groups(buildLiteral, Node.readFileSync(script))->Array.forEach(literal => {
        let target = resolved(Node.join([real, directory, literal]))
        switch Node.existsSync(target) ? within(real, target) : None {
        | Some(path) => add(inputs, path, crate)
        | None => ()
        }
      })
    }
  })
  inputs
}

type nodeGraph = {
  /** Package directory, relative to the root -> the package's name. */
  directories: Map.t<string, string>,
  /** Dependency -> dependent, among the repository's own packages. */
  edges: edges,
}

/** Package directories and dependency -> dependent edges among the repository's packages. */
let nodeGraph = (layout: layout): nodeGraph => {
  let manifests = Set.make()
  layout.packageDirectories->Array.forEach(pattern =>
    expanded(layout.root, pattern)->Array.forEach(directory => {
      let manifest = Node.join([directory, "package.json"])
      if Node.existsSync(manifest) {
        manifests->Set.add(manifest)
      }
    })
  )
  let directories = Map.make()
  let read = []
  manifests
  ->setValues
  ->sortText
  ->Array.forEach(manifest =>
    switch JSON.parseOrThrow(Node.readFileSync(manifest)) {
    | Object(data) =>
      let name = data->text("name")->Option.getOr("")
      directories->Map.set(
        Node.relative(layout.root, Node.dirname(manifest))->String.split(Node.sep)->Array.join("/"),
        name,
      )
      read->Array.push((name, data))
    | _ => ()
    }
  )
  let known = read->Array.map(((name, _)) => name)->Set.fromArray
  let edges = Map.make()
  read->Array.forEach(((name, data)) =>
    ["dependencies", "devDependencies", "peerDependencies"]->Array.forEach(field =>
      switch data->Dict.get(field) {
      | Some(Object(dependencies)) =>
        dependencies
        ->Dict.keysToArray
        ->Array.forEach(
          dependency =>
            if known->Set.has(dependency) {
              add(edges, dependency, name)
            },
        )
      | _ => ()
      }
    )
  )
  {directories, edges}
}
