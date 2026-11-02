/**
 * `dep add|remove <repository> <package> [--dev] [--rust] [--dry-run]`, a dependency put into or
 * taken out of a repository's package.json by pnpm or its Cargo.toml by cargo. A version is added
 * only once it has been public for a day, in the range form the repository already uses.
 * See docs/toolchain/dependencies.md.
 */
type kind = Npm | Crate
type release = {version: string, published: string, yanked: bool}
type lookup = (kind, string) => promise<option<array<release>>>
type runner = (string, array<string>, string) => int

let refuse = why => JsError.throwWithMessage(why)

let delay = 24. *. 3600. *. 1000.

let field = (value: JSON.t, name) =>
  switch value {
  | Object(entries) => entries->Dict.get(name)
  | _ => None
  }

let text = (value: option<JSON.t>) =>
  switch value {
  | Some(String(text)) => Some(text)
  | _ => None
  }

let entriesOf = (value: option<JSON.t>) =>
  switch value {
  | Some(Object(entries)) => entries->Dict.toArray
  | _ => []
  }

/** The releases an npm document lists, past what was unpublished or deprecated. */
let npmReleases = (document: JSON.t): array<release> => {
  let times = field(document, "time")->entriesOf
  let versions = field(document, "versions")
  times->Array.filterMap(((version, published)) =>
    switch (published, versions->entriesOf->Array.find(((name, _)) => name == version)) {
    | (String(published), Some((_, info))) =>
      let deprecated = field(info, "deprecated")->Option.isSome
      Some({version, published, yanked: deprecated})
    | _ => None
    }
  )
}

/** The releases a crates.io document lists. */
let crateReleases = (document: JSON.t): array<release> =>
  switch field(document, "versions") {
  | Some(Array(versions)) =>
    versions->Array.filterMap(entry =>
      switch (field(entry, "num")->text, field(entry, "created_at")->text) {
      | (Some(version), Some(published)) =>
        Some({version, published, yanked: field(entry, "yanked") == Some(Boolean(true))})
      | _ => None
      }
    )
  | _ => []
  }

/** The newest stable release public for a day, one yanked or deprecated passed over. */
let newestAged = (releases: array<release>, ~now): option<string> => {
  let aged =
    releases
    ->Array.filter(release =>
      !release.yanked &&
      !(release.version->String.includes("-")) &&
      now -. Date.fromString(release.published)->Date.getTime >= delay
    )
    ->Array.map(release => release.version)
  aged == [] ? None : Some(Outdated.newest(aged))
}

/** Each dependency a manifest declares, its section, its name and the range or "" where none. */
let declared = (manifest: JSON.t, kind): array<(string, string, string)> =>
  switch kind {
  | Npm =>
    [
      "dependencies",
      "devDependencies",
      "optionalDependencies",
      "peerDependencies",
    ]->Array.flatMap(section =>
      field(manifest, section)
      ->entriesOf
      ->Array.map(((name, range)) => (section, name, Some(range)->text->Option.getOr("")))
    )
  | Crate =>
    let sections = ["dependencies", "dev-dependencies", "build-dependencies"]
    let own = sections->Array.map(section => (section, field(manifest, section)))
    let shared = (
      "workspace.dependencies",
      field(manifest, "workspace")->Option.flatMap(workspace => field(workspace, "dependencies")),
    )
    Array.concat(own, [shared])->Array.flatMap(((section, table)) =>
      table
      ->entriesOf
      ->Array.map(((name, spec)) => (
        section,
        name,
        switch spec {
        | String(range) => range
        | _ => spec->field("version")->text->Option.getOr("")
        },
      ))
    )
  }

/** The sign a range opens with, "" for a bare or an exact version, None for any other form. */
let signOf = range =>
  switch range->String.slice(~start=0, ~end=1) {
  | ("^" | "~" | "=") as sign => Some(sign)
  | digit if /\d/->RegExp.test(digit) => Some("")
  | _ => None
  }

/** The sign most of a repository's ranges open with, `default` where none say or two tie. */
let formOf = (ranges: array<string>, ~default) => {
  let signs = ranges->Array.filterMap(signOf)
  let count = sign => signs->Array.filter(one => one == sign)->Array.length
  let best =
    ["^", "~", "=", ""]->Array.reduce((default, count(default)), ((held, most), sign) =>
      count(sign) > most ? (sign, count(sign)) : (held, most)
    )
  best->Pair.first
}

let existsWorkspace = root => Node.existsSync(Node.join([root, "pnpm-workspace.yaml"]))

let fileOf = kind => kind == Npm ? "package.json" : "Cargo.toml"

let manifestOf = (root, kind): JSON.t => {
  let path = Node.join([root, fileOf(kind)])
  if !Node.existsSync(path) {
    refuse(`${path} does not exist`)
  }
  switch kind {
  | Npm => JSON.parseOrThrow(Node.readFileSync(path))
  | Crate => Toml.parse(Node.readFileSync(path))
  }
}

/** The directory a command works in, a member of the repository where `--in` names one. */
let placeOf = (root, member) =>
  switch member {
  | None => root
  | Some(path) =>
    let dir = Node.resolve([root, path])
    let within = Node.relative(root, dir)
    if within == "" || within == ".." || within->String.startsWith(`..${Node.sep}`) {
      refuse(`--in ${path} is no directory inside the repository`)
    }
    if !Node.existsSync(dir) {
      refuse(`--in ${path} does not exist`)
    }
    dir
  }

/** A root that only gathers members holds no dependency of its own to add to. */
let gathers = (root, kind, manifest, present) =>
  switch kind {
  | Npm => present == [] && existsWorkspace(root)
  | Crate => field(manifest, "workspace")->Option.isSome && field(manifest, "package") == None
  }

let show = (command, args) => `$ ${command} ${args->Array.join(" ")}`

/** Adds `name` at the newest version a day old, or says why it cannot, and returns the status. */
let add = async (
  ~root,
  ~repository,
  ~name,
  ~kind,
  ~member=?,
  ~dev,
  ~dry,
  ~lookup: lookup,
  ~run: runner,
  ~now,
  ~log,
) => {
  let file = fileOf(kind)
  let dir = placeOf(root, member)
  let manifest = manifestOf(dir, kind)
  let present = declared(manifest, kind)
  if member == None && gathers(root, kind, manifest, present) {
    refuse(
      `${repository} is a workspace root with no dependencies of its own; name a member with --in`,
    )
  }
  switch present->Array.find(((_, own, _)) => own == name) {
  | Some((section, _, _)) =>
    refuse(
      `${name} is already in ${file} under ${section}; \`mise run update ${repository}\` moves it`,
    )
  | None => ()
  }
  let releases = switch await lookup(kind, name) {
  | Some(releases) => releases
  | None =>
    refuse(`${name} could not be read from the ${kind == Npm ? "npm" : "crates.io"} registry`)
  }
  let version = switch newestAged(releases, ~now) {
  | Some(version) => version
  | None => refuse(`${name} has no stable release that has been public for a day`)
  }
  // A member of a Cargo workspace often says `workspace = true`, so the root's ranges speak too.
  let shared = member != None && kind == Crate ? declared(manifestOf(root, kind), kind) : []
  let ranges = Array.concat(present, shared)->Array.map(((_, _, range)) => range)
  let published = releases->Array.find(release => release.version == version)
  log(`${name} ${version} published ${published->Option.mapOr("?", release => release.published)}`)
  releases
  ->Array.filter(release => !release.yanked && Outdated.compare(release.version, version) > 0)
  ->Array.forEach(release =>
    log(`${name} ${release.version} published ${release.published}, passed over`)
  )
  let (command, args) = switch kind {
  | Npm =>
    let sign = formOf(ranges, ~default="^")
    let pin = sign == "" ? ["--save-exact"] : [`--save-prefix=${sign}`]
    let place = member == None && existsWorkspace(root) ? ["-w"] : []
    ("pnpm", Array.flat([["add", `${name}@${version}`], dev ? ["--save-dev"] : [], pin, place]))
  | Crate =>
    let sign = formOf(ranges, ~default="")
    ("cargo", Array.flat([["add", `${name}@${sign}${version}`], dev ? ["--dev"] : []]))
  }
  log(show(command, args))
  dry ? 0 : run(command, args, dir)
}

/** Removes `name` where the repository has it, or says it has none, and returns the status. */
let remove = (~root, ~member=?, ~name, ~kind, ~dry, ~run: runner, ~log) => {
  let file = fileOf(kind)
  let dir = placeOf(root, member)
  let present = declared(manifestOf(dir, kind), kind)
  switch present->Array.find(((_, own, _)) => own == name) {
  | None => refuse(`${name} is not in ${file}`)
  | Some((section, _, _)) =>
    let (command, args) = switch kind {
    | Npm => (
        "pnpm",
        Array.flat([["remove", name], member == None && existsWorkspace(root) ? ["-w"] : []]),
      )
    | Crate =>
      let flag = switch section {
      | "dev-dependencies" => ["--dev"]
      | "build-dependencies" => ["--build"]
      | _ => []
      }
      ("cargo", Array.flat([["remove", name], flag]))
    }
    log(show(command, args))
    dry ? 0 : run(command, args, dir)
  }
}

let fetchJson = async url =>
  try {
    let headers = Dict.fromArray([("User-Agent", "workspace-dep")])
    let response = await Net.fetch(url, {headers: headers})
    Net.ok(response) ? Some(JSON.parseOrThrow(await Net.responseText(response))) : None
  } catch {
  | _ => None
  }

/** The registry's own answer, npm's or crates.io's. */
let registryLookup: lookup = async (kind, name) =>
  switch kind {
  | Npm =>
    (await fetchJson(`https://registry.npmjs.org/${name->String.replace("/", "%2F")}`))->Option.map(
      npmReleases,
    )
  | Crate => (await fetchJson(`https://crates.io/api/v1/crates/${name}`))->Option.map(crateReleases)
  }

let systemRun: runner = (command, args, root) => Node.run(~cwd=root, command, args)

/** The flags, the member `--in` names and the words of a command line, an unknown flag refused. */
let parse = (args: array<string>) => {
  let flags = ["--dev", "--rust", "--dry-run"]
  let at = args->Array.indexOf("--in")
  let member = at < 0 ? None : args[at + 1]
  if at >= 0 && member->Option.mapOr(true, path => path->String.startsWith("--")) {
    refuse("--in names a member directory")
  }
  let words =
    args->Array.filterWithIndex((arg, index) =>
      !(arg->String.startsWith("--")) && (at < 0 || index != at + 1)
    )
  args->Array.forEach(arg =>
    if arg->String.startsWith("--") && arg != "--in" && !(flags->Array.includes(arg)) {
      refuse(
        `${arg} is no flag of dep; they are ${flags
          ->Array.concat(["--in <path>"])
          ->Array.join(", ")}`,
      )
    }
  )
  (words, member, flag => args->Array.includes(flag))
}

let usage = "usage: mise run dep add|remove <repository> <package> [--in <path>] [--dev] [--rust] [--dry-run]"

let main = async () => {
  let (words, member, has) = parse(Node.args())
  let (verb, repository, name) = switch words {
  | [verb, repository, name] if verb == "add" || verb == "remove" => (verb, repository, name)
  | _ => refuse(usage)
  }
  let kind = has("--rust") ? Crate : Npm
  let dry = has("--dry-run")
  if verb == "remove" && has("--dev") {
    refuse("remove finds the section itself; --dev is for add")
  }
  let root = switch Registry.selected(Some(repository)) {
  | [root] => root
  | _ => refuse(usage)
  }
  let log = Console.log
  let status = if verb == "add" {
    await add(
      ~root,
      ~repository,
      ~member?,
      ~name,
      ~kind,
      ~dev=has("--dev"),
      ~dry,
      ~lookup=registryLookup,
      ~run=systemRun,
      ~now=Date.now(),
      ~log,
    )
  } else {
    remove(~root, ~member?, ~name, ~kind, ~dry, ~run=systemRun, ~log)
  }
  Node.exit(status)
}

if Node.isMain {
  main()
  ->Promise.catch(error => {
    switch error {
    | Registry.Refused(why) => Console.error(why)
    | JsExn(error) => Console.error(error->JsExn.message->Option.getOr("dep failed"))
    | other => Console.error(other)
    }
    Node.exit(1)
  })
  ->ignore
}
