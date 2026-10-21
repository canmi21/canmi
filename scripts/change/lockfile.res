/**
 * A pnpm lockfile's importers read as text, so a lockfile change rebuilds only the Node images
 * whose importers moved. Read by deployable.res. RFC l6r4u.
 */
let lineBreak = /\r?\n/
/** `  path:`, `  'path with spaces':`, or `  path: {}` for an importer that asks for nothing. */
let importerKey = /^ {2}(?:'([^']*)'|([^\s'][^:]*)):(?: (.+))?$/

/** Importer path -> its section's lines, every document's section of that path together. */
let importers = (lock: string): Map.t<string, string> => {
  let found: Map.t<string, array<string>> = Map.make()
  let order = []
  let inside = ref(false)
  let current = ref(None)
  lock
  ->String.splitByRegExp(lineBreak)
  ->Array.forEach(line => {
    let line = line->Option.getOr("")
    if line == "---" || (line != "" && !(line->String.startsWith(" "))) {
      inside := line == "importers:"
      current := None
    } else if inside.contents {
      switch importerKey->RegExp.exec(line) {
      | Some(result) =>
        let groups = result->RegExp.Result.matches
        let at = index => groups->Array.get(index)->Option.flatMap(group => group)
        let path = at(0)->Option.orElse(at(1))->Option.getOr("")
        let lines = switch found->Map.get(path) {
        | Some(lines) => lines
        | None =>
          let lines = []
          found->Map.set(path, lines)
          order->Array.push(path)
          lines
        }
        current := Some(lines)
        switch at(2) {
        | Some(value) => lines->Array.push(value)
        | None => ()
        }
      | None =>
        switch current.contents {
        | Some(lines) if line->String.trim != "" => lines->Array.push(line)
        | _ => ()
        }
      }
    }
  })
  order
  ->Array.map(path => (path, found->Map.get(path)->Option.getOr([])->Array.join("\n")))
  ->Map.fromArray
}

/**
 * The importer paths whose sections differ between two lockfiles, one absent in either among them.
 */
let movedImporters = (before: string, after: string): Set.t<string> => {
  let was = importers(before)
  let now = importers(after)
  Array.concat(was->Graph.keysOf, now->Graph.keysOf)
  ->Set.fromArray
  ->Graph.setValues
  ->Array.filter(path => was->Map.get(path) != now->Map.get(path))
  ->Set.fromArray
}
