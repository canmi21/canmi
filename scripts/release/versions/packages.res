/** The crates and packages of a repository, each directory one package, its root one too. */
type kind = Cargo | Node

type manifest = {path: string, kind: kind, text: string}

type t = {
  /** From the repository's root, the root itself being empty. */
  directory: string,
  name: string,
  manifests: array<manifest>,
  version: Numbers.t,
  /** What it builds from a lockfile, a binary of Cargo's or a Worker of pnpm's. */
  builds: array<kind>,
}

let cargo = /^\[package\]/m
let cargoVersion = /^version\s*=\s*"([^"]*)"/m
let cargoName = /^name\s*=\s*"([^"]*)"/m

let group = (pattern, text) =>
  pattern
  ->RegExp.exec(text)
  ->Option.flatMap(found => found->RegExp.Result.matches->Array.get(0)->Option.flatMap(x => x))

let parsed = text =>
  switch JSON.parseOrThrow(text) {
  | Object(fields) => Some(fields)
  | _ => None
  | exception JsExn(_) => None
  }

let nodeText = (text, key) =>
  switch parsed(text)->Option.flatMap(fields => fields->Dict.get(key)) {
  | Some(String(value)) => Some(value)
  | _ => None
  }

/** A manifest's written version, none at all counting as zero, or why it cannot be read. */
let versionOf = ({path, kind, text}) => {
  let written = switch kind {
  | Cargo => group(cargoVersion, text)
  | Node => nodeText(text, "version")
  }
  switch written {
  | None => Ok(Numbers.zero)
  | Some(version) =>
    switch Numbers.parse(version) {
    | Some(numbers) => Ok(numbers)
    | None => Error(`${path}: version ${version} is not major.minor.patch`)
    }
  }
}

let nameOf = ({kind, text}) =>
  switch kind {
  | Cargo => group(cargoName, text)
  | Node => nodeText(text, "name")
  }

/** A manifest's text at `version`, the rest of it untouched. */
let written = ({kind, text}, version) => {
  let shown = Numbers.show(version)
  switch kind {
  | Cargo => text->String.replaceRegExp(cargoVersion, `version = "${shown}"`)
  | Node if nodeText(text, "version")->Option.isSome =>
    text->String.replaceRegExp(/"version":\s*"[^"]*"/, `"version": "${shown}"`)
  | Node => text->String.replaceRegExp(/^(\s*)("name":[^\n]*\n)/m, `$1$2$1"version": "${shown}",\n`)
  }
}

/** A root package.json private and without a version, which holds a workspace and is no package. */
let holdsWorkspace = ({path, kind, text}) =>
  path == "package.json" &&
  kind == Node &&
  nodeText(text, "version")->Option.isNone &&
  switch parsed(text)->Option.flatMap(fields => fields->Dict.get("private")) {
  | Some(Boolean(true)) => true
  | _ => false
  }

/** Fixtures and vendored source hold a manifest that is no package of ours. */
let foreign = ["docs", "tests", "vendor", "node_modules"]

let isForeign = path => path->String.split("/")->Array.some(part => foreign->Array.includes(part))

let kindOf = path =>
  switch path->String.split("/")->Array.at(-1) {
  | Some("Cargo.toml") => Some(Cargo)
  | Some("package.json") => Some(Node)
  | _ => None
  }

/** Whether `directory` builds a binary or a Worker, a library's lock taking neither. */
let builtFrom = (~tracked, ~own, directory) => {
  let inside = name => directory == "" ? name : `${directory}/${name}`
  let holds = name => tracked->Array.includes(inside(name))
  Array.flat([
    holds("src/main.rs") ||
    tracked->Array.some(path => path->String.startsWith(inside("src/bin/"))) ||
    own->Array.some(({kind, text}) => kind == Cargo && text->String.includes("[[bin]]"))
      ? [Cargo]
      : [],
    holds("wrangler.json") || holds("wrangler.jsonc") || holds("wrangler.toml") ? [Node] : [],
  ])
}

/** Every package `tracked` holds, read by `read`, or each manifest that cannot be read. */
let found = (~fallback, ~read, tracked) => {
  let problems = []
  let manifests =
    tracked
    ->Array.filter(path => !isForeign(path))
    ->Array.filterMap(path =>
      kindOf(path)->Option.flatMap(kind =>
        read(path)->Option.flatMap(
          text => kind == Cargo && !RegExp.test(cargo, text) ? None : Some({path, kind, text}),
        )
      )
    )
    ->Array.filter(manifest => !holdsWorkspace(manifest))
  let directoryOf = path =>
    path->String.includes("/")
      ? path->String.split("/")->Array.slice(~start=0, ~end=-1)->Array.join("/")
      : ""
  let directories = manifests->Array.reduce([], (kept, {path}) => {
    let directory = directoryOf(path)
    kept->Array.includes(directory) ? kept : [...kept, directory]
  })
  let packages = directories->Array.filterMap(directory => {
    let own = manifests->Array.filter(({path}) => directoryOf(path) == directory)
    let read = own->Array.map(versionOf)
    read->Array.forEach(result =>
      switch result {
      | Error(why) => problems->Array.push(why)
      | Ok(_) => ()
      }
    )
    let versions = read->Array.filterMap(result => result->Result.mapOr(None, v => Some(v)))
    // A directory holding both manifests holds one version, the higher where they disagree.
    versions == []
      ? None
      : Some({
          directory,
          name: own
          ->Array.findMap(nameOf)
          ->Option.getOr(directory == "" ? fallback : directory),
          manifests: own,
          builds: builtFrom(~tracked, ~own, directory),
          version: versions->Array.reduce(Numbers.zero, (best, version) =>
            Numbers.later(version, best) ? version : best
          ),
        })
  })
  (packages, problems)
}

let cargoPath = /path\s*=\s*"([^"]+)"/g

/** The directories `package` reaches by a path dependency, those in this repository alone. */
let uses = (packages: array<t>, package: t) =>
  package.manifests->Array.flatMap(({kind, text}) =>
    switch kind {
    | Cargo =>
      let paths = []
      let rec next = () =>
        switch cargoPath->RegExp.exec(text) {
        | None => ()
        | Some(found) =>
          found
          ->RegExp.Result.matches
          ->Array.get(0)
          ->Option.flatMap(x => x)
          ->Option.forEach(path => paths->Array.push(path))
          next()
        }
      next()
      paths->Array.filterMap(path => {
        let directory = Node.join([package.directory == "" ? "." : package.directory, path])
        packages->Array.find(other => other.directory == directory)->Option.map(o => o.directory)
      })
    | Node =>
      switch parsed(text)->Option.flatMap(fields => fields->Dict.get("dependencies")) {
      | Some(Object(dependencies)) =>
        dependencies
        ->Dict.toArray
        ->Array.filterMap(((name, range)) =>
          switch range {
          | String(range) if range->String.startsWith("workspace:") =>
            packages->Array.find(other => other.name == name)->Option.map(o => o.directory)
          | _ => None
          }
        )
      | _ => []
      }
    }
  )

/** A Cargo.lock with each local crate of `moved` at its new version. */
let lockFollowed = (lock, moved: array<(string, Numbers.t)>) =>
  lock
  ->String.split("[[package]]")
  ->Array.map(block => {
    let name = group(cargoName, block)
    switch moved->Array.find(((crate, _)) => Some(crate) == name) {
    | Some((_, version)) if !(block->String.includes("\nsource = ")) =>
      block->String.replaceRegExp(cargoVersion, `version = "${Numbers.show(version)}"`)
    | _ => block
    }
  })
  ->Array.join("[[package]]")

/** Each crate of `crates` the lock holds at another version than its manifest's. */
let lockStale = (lock, crates: array<(string, Numbers.t)>) =>
  lock
  ->String.split("[[package]]")
  ->Array.filterMap(block =>
    switch (group(cargoName, block), group(cargoVersion, block)) {
    | (Some(name), Some(written)) if !(block->String.includes("\nsource = ")) =>
      crates
      ->Array.find(((crate, _)) => crate == name)
      ->Option.flatMap(((_, version)) =>
        Numbers.show(version) == written
          ? None
          : Some(`Cargo.lock holds ${name} ${written}, its manifest ${Numbers.show(version)}`)
      )
    | _ => None
    }
  )

/** The crates `directories` reach in a sibling, its own directories, a sibling's manifests read. */
let siblingCrates = (
  ~root,
  ~sibling,
  ~read=path => Node.existsSync(path) ? Some(Node.readFileSync(path)) : None,
  directories,
) => {
  let seen = []
  let rec visit = directory => {
    let manifest = Node.join([directory, "Cargo.toml"])
    if !(seen->Array.includes(directory)) {
      seen->Array.push(directory)
      read(manifest)->Option.forEach(text => {
        let rec next = () =>
          switch cargoPath->RegExp.exec(text) {
          | None => ()
          | Some(found) =>
            let path = found->RegExp.Result.matches->Array.get(0)->Option.flatMap(x => x)
            next()
            path->Option.forEach(path => visit(Node.resolve([directory, path])))
          }
        next()
      })
    }
  }
  directories->Array.forEach(directory => visit(Node.join([root, directory])))
  seen
  ->Array.filter(directory => directory->String.startsWith(sibling ++ "/"))
  ->Array.map(directory => Node.relative(sibling, directory))
}
