/**
 * The project's own name held to the edge of a repository's code, `own-name` in
 * model/rules/naming.res. Documents name the project as prose names any subject, so they go unread.
 */
type owner = {name: string, repositories: array<string>}

let escaped = text => text->String.replaceRegExp(/[.*+?^${}()|[\]\\\/]/g, "\\$&")

/** Prose about the project, read by people and never by the system. */
let prose = relative =>
  Node.extname(relative) == ".md" ||
  Node.basename(relative)->String.startsWith("LICENSE") ||
  [Layout.rulesHome, Layout.retired]->Array.includes(
    relative->String.split("/")->Array.getUnsafe(0),
  )

/** Where an organization's code is published, the hosts an address names it under. */
let registries = ["github.com", "githubusercontent.com", "ghcr.io", "docker.io", "crates.io"]

/**
 * A scope, an address at a registry, a bound domain, an organization named as an owner, or a
 * sibling repository named whole and never inside a path but `repos/`.
 */
let published = owner => {
  let name = escaped(owner.name)
  let siblings = owner.repositories->Array.map(escaped)->Array.join("|")
  let hosts = registries->Array.map(escaped)->Array.join("|")
  RegExp.fromString(
    [
      `@${name}\\/`,
      `github:${name}\\/`,
      `(?<![\\w.-])(?:[a-z0-9-]+\\.)*(?:${hosts})[\\/:]${name}(?![\\w.-])`,
      `\\b(?:[a-z0-9-]+\\.)*${name}\\.(?:${Naming.domains->Array.join("|")})(?![\\w.-])`,
      `\\bowner\\s*[:=]\\s*"${name}"`,
      `(?:(?<![\\w.\\/@:-])|(?<=(?:^|[^\\w.-])repos\\/))${name}\\/(?:${siblings})(?![\\w-])`,
    ]->Array.join("|"),
    ~flags="gi",
  )
}

/** A manifest's own name, and the id space and declared spellings of `workspace.toml`. */
let manifestName = /^\s*"?name"?\s*[:=]/
let declared = /^\s*(?:ids|spelled)\s*=/
let whole = (line, ~file) =>
  (Layout.manifests->Array.includes(Node.basename(file)) && manifestName->RegExp.test(line)) ||
    (file == "workspace.toml" && declared->RegExp.test(line))

/** The lines a `spelled` list wrapped across lines holds in `workspace.toml`, by number. */
let wrapped = (lines: array<string>, ~file) => {
  let inside = ref(false)
  lines->Array.map(line =>
    if file != "workspace.toml" {
      false
    } else if inside.contents {
      inside := !(line->String.includes("]"))
      true
    } else {
      inside := /^\s*spelled\s*=\s*\[[^\]]*$/->RegExp.test(line)
      false
    }
  )
}

/** Each spelling of the own name one file's text holds outside what passes, by `file:line`. */
let problems = (text, ~file, ~owner, ~spelled: array<string>): array<string> => {
  let passing = published(owner)
  let token = RegExp.fromString(`[\\w.\\/:@-]*${escaped(owner.name)}[\\w.\\/:@-]*`, ~flags="gi")
  let lines = text->String.split("\n")
  let listed = wrapped(lines, ~file)
  lines
  ->Array.mapWithIndex((line, index) => (index + 1, line))
  ->Array.filter(((number, line)) => !whole(line, ~file) && !(listed->Array.getUnsafe(number - 1)))
  ->Array.flatMap(((number, line)) => {
    let left =
      spelled
      ->Array.reduce(line, (blanked, spelling) => blanked->String.replaceAll(spelling, " "))
      ->String.replaceRegExp(passing, " ")
    References.each(token, left)->Array.map(found =>
      `${file}:${Int.toString(number)}: ${found.whole} spells ${owner.name}`
    )
  })
}

/** A declaration that passes nothing, its file gone or its spelling no longer there. */
let stale = (data: array<Project.datum>, ~owner, ~read: string => option<string>) =>
  data->Array.flatMap(({file, spelled}) =>
    switch read(file) {
    | None => [`workspace.toml: names.data names ${file}, which is not there`]
    | Some(text) =>
      spelled->Array.filterMap(spelling =>
        !(spelling->String.toLowerCase->String.includes(owner.name->String.toLowerCase))
          ? Some(`workspace.toml: names.data spells ${spelling} in ${file}, no own name`)
          : spelling->String.toLowerCase == owner.name->String.toLowerCase
          ? Some(`workspace.toml: names.data spells ${spelling} bare in ${file}, passing it all`)
          : !(text->String.includes(spelling))
          ? Some(`workspace.toml: names.data spells ${spelling}, which ${file} no longer holds`)
          : None
      )
    }
  )

/** The author's account, the owner of the workspace's origin, a person's name and no project's. */
let author = () =>
  Registry.origin()->Option.flatMap(address =>
    /github\.com[\/:]([^\/]+)\//
    ->RegExp.exec(address)
    ->Option.flatMap(result => result->RegExp.Result.matches->Array.get(0))
    ->Option.flatMap(found => found)
  )

/** The owner the registry lists for `label` and its repositories, unless the author is it. */
let ownerOf = (~label): option<owner> => {
  let listed = Registry.registry()
  switch listed->Array.find(((path, _)) => path == label) {
  | Some((_, (name, _))) if Some(name) != author() && !(Layout.archives->Array.includes(label)) =>
    Some({
      name,
      repositories: listed->Array.filterMap(((_, (user, repo))) =>
        user == name ? Some(repo) : None
      ),
    })
  | _ => None
  }
}

let main = (~root): array<string> =>
  switch ownerOf(~label=Registry.label(root)) {
  | None => []
  | Some(owner) =>
    switch Project.read(root) {
    | Error(why) if Node.existsSync(Node.join([root, "workspace.toml"])) => [why]
    | declaration =>
      let data = switch declaration {
      | Ok({names}) => names
      | Error(_) => []
      }
      let read = relative => {
        let path = Node.join([root, relative])
        Node.existsSync(path)
          ? Some(References.read(path))->Option.filter(text => !(text->String.includes("\x00")))
          : None
      }
      let files =
        References.tracked(root)
        ->Array.map(path => Node.relative(root, path))
        ->Array.filter(relative =>
          !prose(relative) &&
          !Layout.vendored(relative) &&
          !(Lines.common->Array.some(glob => Lines.matches(Node.basename(relative), glob)))
        )
      let marks = Lines.attributes(root, files)
      Array.concat(
        stale(data, ~owner, ~read),
        files
        ->Array.filter(relative => {
          let mark = marks->Dict.get(relative)->Option.getOr(Dict.make())
          mark->Dict.get("linguist-generated") != Some("true") &&
            mark->Dict.get("linguist-vendored") != Some("true")
        })
        ->Array.flatMap(relative =>
          switch read(relative) {
          | None => []
          | Some(text) =>
            problems(
              text,
              ~file=relative,
              ~owner,
              ~spelled=data
              ->Array.filter(datum => datum.file == relative)
              ->Array.flatMap(datum => datum.spelled),
            )
          }
        ),
      )
    }
  }
