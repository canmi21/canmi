/**
 * A build's leftovers, each `.res.mjs` whose `.res` no longer stands beside it, as after a move,
 * under the directories rescript.json compiles. Run from the root, `node scripts/prune.res.mjs`.
 */
/** The directories a rescript.json compiles, each with whether its subdirectories are included. */
let sources = (root): array<(string, bool)> => {
  let listed = switch JSON.parseOrThrow(Node.readFileSync(Node.join([root, "rescript.json"]))) {
  | Object(config) =>
    switch config->Dict.get("sources") {
    | Some(Array(items)) => items
    | Some(item) => [item]
    | None => []
    }
  | _ => []
  }
  listed->Array.filterMap(item =>
    switch item {
    | String(dir) => Some((dir, false))
    | Object(source) =>
      switch (source->Dict.get("dir"), source->Dict.get("subdirs")) {
      | (Some(String(dir)), Some(Boolean(false)) | None) => Some((dir, false))
      | (Some(String(dir)), Some(_)) => Some((dir, true))
      | _ => None
      }
    | _ => None
    }
  )
}

/** Every `.res.mjs` below `directory`, its subdirectories read only where `deep`. */
let rec modules = (directory, ~deep) =>
  Node.entries(directory)->Array.flatMap(entry => {
    let path = Node.join([directory, entry->Node.name])
    if entry->Node.isDirectory {
      deep && entry->Node.name != "node_modules" && entry->Node.name != "lib"
        ? modules(path, ~deep)
        : []
    } else if path->String.endsWith(".res.mjs") {
      [path]
    } else {
      []
    }
  })

/** Removes each compiled module without its source and returns what it removed, from the root. */
let prune = root =>
  sources(root)
  ->Array.flatMap(((dir, deep)) =>
    Node.existsSync(Node.join([root, dir])) ? modules(Node.join([root, dir]), ~deep) : []
  )
  ->Array.filter(path => {
    let stale = !Node.existsSync(path->String.slice(~start=0, ~end=path->String.length - 4))
    if stale {
      Node.rmSync(path, {recursive: false, force: true})
    }
    stale
  })
  ->Array.map(path => Node.relative(root, path))

if Node.isMain {
  prune(Registry.root)->Array.forEach(path => Console.log(`pruned ${path}`))
}
