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

let main = (~root): array<string> => {
  let read = name => References.read(Node.join([root, name]))
  let found = []
  let say = line => found->Array.push(line)
  let tracked = References.tracked(root)->Array.map(path => Node.relative(root, path))

  if !(read(".gitignore")->String.split("\n")->Array.includes("repos/*/")) {
    say(".gitignore does not list repos/*/")
  }
  Registry.paths()
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
    !(Toolchain.kept->Array.includes(path)) &&
    !(Toolchain.porting->Array.includes(path))
  )
  ->Array.forEach(path => say(`${path} is a script outside ReScript, and not one kept`))
  Toolchain.porting
  ->Array.filter(path => !(tracked->Array.includes(path)))
  ->Array.forEach(path => say(`${path} is ported; take it out of Toolchain.porting`))

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
  found
}
