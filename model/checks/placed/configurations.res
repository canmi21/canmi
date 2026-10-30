/** Places written as configuration values, read against `cloudflare-placed`. */
let reads = file => {
  let name = Node.basename(file)
  [".toml", ".json", ".jsonc"]->Array.includes(Node.extname(file)) &&
  !(["package.json", "package-lock.json", "pnpm-lock.yaml", "flake.lock"]->Array.includes(name)) &&
  !(name->String.endsWith(".lock"))
}

/** JSONC permits a trailing comma outside a string as well as comments. */
let uncommented = text => {
  let text = Quoting.blanked(text, ~quotes="\"")
  let rec walk = (at, out) =>
    if at >= text->String.length {
      out
    } else if text->String.charAt(at) == "\"" {
      let stop = Quoting.quoteEnd(text, at + 1, ~mark="\"") + 1
      walk(stop, `${out}${text->String.slice(~start=at, ~end=stop)}`)
    } else {
      let rest = text->String.slice(~start=at)
      let char = /^,\s*[}\]]/->RegExp.test(rest) ? " " : text->String.charAt(at)
      walk(at + 1, `${out}${char}`)
    }
  walk(0, "")
}

let found = (text, ~file, ~repo, ~exceptions=Toolchain.placedExceptions): array<string> => {
  let rec walk = (value, path) =>
    switch value {
    | JSON.Object(fields) =>
      fields
      ->Dict.toArray
      ->Array.flatMap(((key, value)) => {
        let path = path == "" ? key : `${path}.${key}`
        let here = switch value {
        | JSON.String(value)
          if ["location", "location_hint", "locationHint"]->Array.includes(key) =>
          Placing.passes(value, ~repo, ~file, ~exceptions)
            ? []
            : [`${file}: ${path} names ${value}; ${Placing.told} alone`]
        | _ => []
        }
        Array.concat(here, walk(value, path))
      })
    | JSON.Array(values) =>
      values->Array.flatMapWithIndex((value, index) =>
        walk(value, `${path}[${Int.toString(index)}]`)
      )
    | _ => []
    }
  let parsed = try {
    Some(
      file->String.endsWith(".toml")
        ? Toml.parse(text)
        : JSON.parseOrThrow(file->String.endsWith(".jsonc") ? uncommented(text) : text),
    )
  } catch {
  | _ => None
  }
  parsed->Option.mapOr([], value => walk(value, ""))
}
