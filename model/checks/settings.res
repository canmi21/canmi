/** The workspace's own configuration files against the rules that name them. */
type package = {devDependencies?: Dict.t<string>, dependencies?: Dict.t<string>}
@scope("JSON") @val external parsePackage: string => package = "parse"
@scope("JSON") @val external parseLint: string => {"rules": Nullable.t<Dict.t<JSON.t>>} = "parse"

/** The value `key` takes in `section` of an INI-shaped file such as .editorconfig, if any. */
let iniValue = (text, ~section, ~key) => {
  let current = ref("")
  text
  ->String.split("\n")
  ->Array.filterMap(line => {
    let line = line->String.trim
    if line->String.startsWith("[") {
      current := line
      None
    } else if current.contents == section {
      switch line->String.split("=")->Array.map(String.trim) {
      | [found, value] if found == key => Some(value)
      | _ => None
      }
    } else {
      None
    }
  })
  ->Array.get(0)
}

/** A whole-line comment in JSONC, which is all .oxlintrc.json carries. */
let jsonComment = RegExp.fromString("^\\s*//.*$", ~flags="gm")

let scriptLike = [".py", ".ts", ".js", ".mjs", ".sh", ".fish", ""]

/** The value `key` takes in a definition's frontmatter, if any. */
let field = (text, key) => {
  let lines = text->String.split("\n")
  let close = lines->Array.slice(~start=1)->Array.findIndex(line => line->String.trim == "---")
  let head = lines->Array.get(0)->Option.map(String.trim) == Some("---") ? close : -1
  lines
  ->Array.slice(~start=1, ~end=head + 1)
  ->Array.findMap(line =>
    line->String.startsWith(`${key}:`)
      ? Some(line->String.slice(~start=key->String.length + 1)->String.trim)
      : None
  )
}

/** Where a name stands in a ranking, if the value holds one of its names. */
let rank = (ranking: array<string>, value, ~whole) => {
  let value = value->String.toLowerCase
  ranking
  ->Array.findIndex(name => whole ? value == name : value->String.includes(name))
  ->(at => at < 0 ? None : Some(at))
}

/** What a definition's frontmatter breaks of the floor, an absent field inheriting. */
let floor = (text, ~file) => {
  let below = (key, ranking, least, ~whole) =>
    switch field(text, key)->Option.map(value => (value, rank(ranking, value, ~whole))) {
    | Some(value, Some(at)) if at < ranking->Array.indexOf(least) => [
        `${file}: ${key} ${value} is below ${least}, the floor of every subagent of ours`,
      ]
    | _ => []
    }
  let unknown = switch field(text, "effort") {
  | Some(value) if rank(Delegation.efforts, value, ~whole=true) == None => [
      `${file}: effort ${value} is no effort of ${Delegation.efforts->Array.join(", ")}`,
    ]
  | _ => []
  }
  [
    below("model", Delegation.models, Delegation.floorModel, ~whole=false),
    below("effort", Delegation.efforts, Delegation.floorEffort, ~whole=true),
    unknown,
  ]->Array.flat
}

/** The repository of a path under repos/, the longest registered path it starts with. */
let repositoryOf = path =>
  Registry.paths()
  ->Array.filter(repo => path == repo || path->String.startsWith(`${repo}/`))
  ->Array.toSorted((a, b) => Float.fromInt(b->String.length - a->String.length))
  ->Array.get(0)

/** Each entry path of the map that is no file or directory, a repository passed over aside. */
let missing = (~repos, ~skipped) =>
  Delegation.areas->Array.flatMap(((area, paths)) =>
    paths->Array.filterMap(path =>
      switch repositoryOf(path) {
      | None => Some(`area ${area}: ${path} lies in no repository of the registry`)
      | Some(repo) if skipped(repo)->Option.isSome => None
      | Some(_) if Node.existsSync(Node.join([repos, path])) => None
      | Some(_) => Some(`area ${area}: ${path} does not exist under repos/`)
      }
    )
  )

/** Each subagent definition against the floor, and the area map against the tree. */
let subagents = (~root): array<string> => {
  let directory = Node.join([root, Delegation.definitions])
  let defined = Node.existsSync(directory)
    ? Node.readdir(directory)->Array.filter(name => name->String.endsWith(".md"))
    : []
  Array.concat(
    defined->Array.flatMap(name =>
      floor(
        Node.readFileSync(Node.join([directory, name])),
        ~file=`${Delegation.definitions}/${name}`,
      )
    ),
    missing(~repos=Registry.repos, ~skipped=Waiting.skipped),
  )
}

let main = (~root): array<string> => {
  let read = name => References.read(Node.join([root, name]))
  let found = []
  let say = line => found->Array.push(line)
  let tracked = References.tracked(root)->Array.map(path => Node.relative(root, path))

  if !(read(".gitignore")->String.split("\n")->Array.includes("repos/*/")) {
    say(".gitignore does not list repos/*/")
  }
  Waiting.active()
  ->Array.map(path => (path, Node.join([Registry.repos, path, "Cargo.toml"])))
  ->Array.forEach(((path, manifest)) =>
    if Node.existsSync(manifest) && !(References.read(manifest)->String.includes("[workspace]")) {
      say(`repos/${path}/Cargo.toml carries no [workspace] table, so cargo walks up into this one`)
    }
  )
  tracked
  ->Array.filter(path =>
    Toolchain.scriptHomes->Array.some(home => path->String.startsWith(home)) &&
    scriptLike->Array.includes(Node.extname(path)) &&
    !(Toolchain.kept->Array.includes(path))
  )
  ->Array.forEach(path => say(`${path} is a script outside ReScript, and not one kept`))

  let editorconfig = read(".editorconfig")
  Toolchain.indentation->Array.forEach(((key, value)) =>
    if iniValue(editorconfig, ~section="[*]", ~key) != Some(value) {
      say(`.editorconfig [*] does not set ${key} = ${value}`)
    }
  )
  if iniValue(editorconfig, ~section="[*.{yml,yaml}]", ~key="indent_style") != Some("space") {
    say(".editorconfig does not indent YAML with spaces")
  }
  let rustfmt = read("rustfmt.toml")
  ["hard_tabs = true", "tab_spaces = 2"]->Array.forEach(line =>
    if !(rustfmt->String.split("\n")->Array.includes(line)) {
      say(`rustfmt.toml does not say ${line}`)
    }
  )

  let lint =
    parseLint(read(".oxlintrc.json")->String.replaceRegExp(jsonComment, ""))["rules"]
    ->Nullable.toOption
    ->Option.getOr(Dict.make())
  Format.overlapping->Array.forEach(rule =>
    if lint->Dict.get(rule) != Some(JSON.String("off")) {
      say(`.oxlintrc.json leaves ${rule} on, which the formatter already rewrites`)
    }
  )
  let declared = (manifest: package, name) =>
    [manifest.dependencies, manifest.devDependencies]->Array.some(table =>
      table->Option.mapOr(false, table => table->Dict.get(name)->Option.isSome)
    )
  tracked
  ->Array.filter(path => Node.basename(path) == "package.json")
  ->Array.forEach(path => {
    let manifest = parsePackage(read(path))
    if declared(manifest, "oxfmt") && !declared(manifest, "svelte") {
      say(`${path} declares oxfmt without svelte, so oxfmt formats no Markdown`)
    }
  })

  if !(tracked->Array.includes("LICENSE")) {
    say("the workspace keeps no LICENSE at its root")
  }
  tracked
  ->Array.filter(path => path != "LICENSE" && Node.basename(path)->String.startsWith("LICENSE"))
  ->Array.forEach(path => say(`${path} is a second license`))
  Array.concat(found, subagents(~root))
}
