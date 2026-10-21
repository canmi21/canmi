/** A repository's tree against model/rules/layout.res, its width, depth, root and docs. */
/** Each directory of `files`, `.` the root, to the names directly inside it. */
let directories = (files: array<string>): Dict.t<array<string>> => {
  let found = Dict.make()
  files->Array.forEach(file => {
    let parts = file->String.split("/")
    parts->Array.forEachWithIndex((name, at) => {
      let parent = at == 0 ? "." : parts->Array.slice(~start=0, ~end=at)->Array.join("/")
      let inside = found->Dict.get(parent)->Option.getOr([])
      if !(inside->Array.includes(name)) {
        inside->Array.push(name)
        found->Dict.set(parent, inside)
      }
    })
  })
  found
}

let parentOf = path => {
  let parts = path->String.split("/")
  parts->Array.length == 1 ? "." : parts->Array.slice(~start=0, ~end=-1)->Array.join("/")
}

/** Every way `files` break the layout rules, each by rule; `cargo` is the root Cargo.toml. */
let ruled = (files: array<string>, ~cargo: option<string>): array<(string, string)> => {
  let tree = directories(files)
  let inside = path => tree->Dict.get(path)->Option.getOr([])
  let isPackage = path => Layout.manifests->Array.some(name => inside(path)->Array.includes(name))
  let depths = Dict.make()
  let found = []
  tree
  ->Dict.keysToArray
  ->Array.toSorted(String.compare)
  ->Array.forEach(path =>
    if path != "." {
      let count = inside(path)->Array.length
      if count > Layout.widest {
        found->Array.push((
          "tree-wide",
          `${path}/: ${Int.toString(count)} entries, past ${Int.toString(Layout.widest)}`,
        ))
      }
      let parent = parentOf(path)
      let depth = if parent == "." {
        0
      } else if isPackage(parent) {
        1
      } else {
        depths->Dict.get(parent)->Option.getOr(0) + 1
      }
      depths->Dict.set(path, depth)
      if depth == Layout.deepest + 1 {
        found->Array.push((
          "tree-deep",
          `${path}/: ${Int.toString(depth)} deep, past ${Int.toString(Layout.deepest)}`,
        ))
      }
    }
  )
  inside(".")->Array.forEach(name =>
    if (
      tree->Dict.get(name)->Option.isNone &&
      Layout.sources->Array.some(suffix => name->String.endsWith(suffix)) &&
      !(Layout.configuration->RegExp.test(name))
    ) {
      found->Array.push((
        "root-configuration",
        `${name}: a source file at the root, where configuration alone sits`,
      ))
    }
  )
  switch cargo {
  | Some(text) =>
    switch Toml.parse(text) {
    | JSON.Object(manifest) if manifest->Dict.get("package")->Option.isSome =>
      found->Array.push((
        "root-configuration",
        "Cargo.toml: a [package] at the root, where a virtual manifest alone is",
      ))
    | _ => ()
    | exception _ => found->Array.push(("root-configuration", "Cargo.toml: does not parse"))
    }
  | None => ()
  }
  if tree->Dict.get(Layout.retired)->Option.isSome {
    found->Array.push((
      "rules-in-docs",
      `${Layout.retired}/: the rules are ${Layout.rulesHome}/ now`,
    ))
  }
  found
}

let problems = (files, ~cargo) => ruled(files, ~cargo)->Array.map(((_, says)) => says)

/** A repository's findings over what version control keeps, its vendored source passed over. */
let tagged = (~root): array<(string, string)> => {
  let cargo = Node.join([root, "Cargo.toml"])
  ruled(
    Lines.tracked(root)->Array.filter(path => !Layout.vendored(path)),
    ~cargo=Node.existsSync(cargo) ? Some(Node.readFileSync(cargo)) : None,
  )
}

let main = (~root) => tagged(~root)->Array.map(((_, says)) => says)
