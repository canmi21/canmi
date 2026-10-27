/**
 * `releases.res.mjs <manifest.toml> [--dry-run]`, each artifact a manifest names locked beside
 * it in manifest.lock at the newest version its source's releases list. See docs/toolchain.md.
 */
@module("node:fs") external appendFileSync: (string, string) => unit = "appendFileSync"

let field = (json, key) => json->JSON.Decode.object->Option.flatMap(o => o->Dict.get(key))
let text = (json, key) => json->field(key)->Option.flatMap(JSON.Decode.string)
let list = (json, key) => json->field(key)->Option.flatMap(JSON.Decode.array)->Option.getOr([])

/** The Nix system a manifest's target is, `linux-x86_64` taken as `x86_64-linux`. */
let system = target =>
  switch target->String.split("-") {
  | [os, machine] => Some(`${machine}-${os}`)
  | _ => None
  }

/** The highest version a release names an archive of for `name`, read from the archives' names,
 * an image's `.tar` or a program's `.tar.gz`. */
let newest = (names: array<string>, ~name) =>
  names
  ->Array.filterMap(file =>
    switch RegExp.fromString(
      `^${name}-(\\d[^-]*)-[a-z0-9]+-[a-z0-9_]+\\.tar(?:\\.gz)?$`,
    )->RegExp.exec(file) {
    | Some(result) => result->RegExp.Result.matches->Array.get(0)->Option.flatMap(x => x)
    | None => None
    }
  )
  ->Array.toSorted((a, b) => Outdated.order(b, a))
  ->Array.get(0)

/** A pin as the pins file holds it, its version and each system's address and SHA-256, from the
 * release that lists it and the manifest's entry for it, and its source where not the lock's. */
let pinned = (~source=?, ~version, ~release: JSON.t, entry: JSON.t) => {
  let addresses = Dict.fromArray(
    release
    ->list("assets")
    ->Array.filterMap(asset =>
      switch (asset->text("name"), asset->text("browser_download_url")) {
      | (Some(file), Some(url)) => Some((file, url))
      | _ => None
      }
    ),
  )
  let pin = dict{"version": JSON.Encode.string(version)}
  source->Option.forEach(source => pin->Dict.set("source", JSON.Encode.string(source)))
  release
  ->text("tag_name")
  ->Option.forEach(tag => pin->Dict.set("release", JSON.Encode.string(tag)))
  entry
  ->list("assets")
  ->Array.forEach(asset =>
    switch (
      asset->text("target")->Option.flatMap(system),
      asset->text("file")->Option.flatMap(file => addresses->Dict.get(file)),
      asset->text("sha256"),
    ) {
    | (Some(system), Some(url), Some(sha256)) =>
      pin->Dict.set(
        system,
        JSON.Encode.object(
          dict{"url": JSON.Encode.string(url), "sha256": JSON.Encode.string(sha256)},
        ),
      )
    | _ => ()
    }
  )
  JSON.Encode.object(pin)
}

/** The entry a release's manifest gives `name` at `version`, where it lists it, the manifest in
 * the one shape or in runtime's first, scripts/release/manifest.res telling them apart. */
let entryOf = (manifest: JSON.t, ~name, ~version) =>
  manifest
  ->Manifest.artifacts
  ->Array.find(entry =>
    entry->text("name") == Some(name) && entry->text("version") == Some(version)
  )

/** A TOML string, quoted with what it holds escaped. */
let quoted = value => JSON.stringifyAny(value)->Option.getOr(`""`)

/** The manifest as it is written, its head saying who writes it from which sources, each
 * artifact's release linked above its table, and each system's address and SHA-256 in a table of
 * its own. */
let written = (~source, ~others=[], ~manifest, pins: array<(string, JSON.t)>) => {
  let head = switch others {
  | [] => [
      `# Written by \`mise run update\` from ${manifest} and ${source}'s releases, the workspace's`,
      "# scripts/deps/releases.res; edited by hand, it is written over at the next update.",
    ]
  | others => [
      `# Written by \`mise run update\` from ${manifest} and its sources' releases, the`,
      "# workspace's scripts/deps/releases.res; edited by hand, it is written over at the next",
      `# update. Its sources are ${[source, ...others]->Array.join(" and ")}.`,
    ]
  }->Array.concat([`source = ${quoted(source)}`])
  let tables = pins->Array.flatMap(((name, pin)) => {
    let fields = pin->JSON.Decode.object->Option.getOr(Dict.make())
    let link =
      fields
      ->Dict.get("release")
      ->Option.flatMap(JSON.Decode.string)
      ->Option.mapOr([], tag => [
        `# https://github.com/${pin->text("source")->Option.getOr(source)}/releases/tag/${tag}`,
      ])
    let scalars = ["version", "release", "source"]->Array.filterMap(key =>
      fields
      ->Dict.get(key)
      ->Option.flatMap(JSON.Decode.string)
      ->Option.map(value => `${key} = ${quoted(value)}`)
    )
    let systems =
      fields
      ->Dict.toArray
      ->Array.filter(((_, value)) => value->JSON.Decode.object->Option.isSome)
      ->Array.toSorted(((a, _), (b, _)) => String.compare(b, a))
      ->Array.flatMap(((system, value)) =>
        [
          "",
          `[${name}.${system}]`,
          ...["url", "sha256"]->Array.filterMap(
            key => value->text(key)->Option.map(found => `${key} = ${quoted(found)}`),
          ),
        ]
      )
    ["", ...link, `[${name}]`, ...scalars, ...systems]
  })
  [...head, ...tables]->Array.join("\n") ++ "\n"
}

/** A JSON document from GitHub, with the token where the environment holds one. */
let github = async (url): result<JSON.t, string> => {
  let headers = dict{"accept": "application/vnd.github+json", "user-agent": "workspace-releases"}
  switch Node.env->Dict.get("GITHUB_TOKEN") {
  | Some(token) => headers->Dict.set("authorization", `Bearer ${token}`)
  | None => ()
  }
  switch await Net.fetch(url, {headers: headers}) {
  | response if response->Net.ok =>
    let body = await response->Net.responseText
    try Ok(JSON.parseOrThrow(body)) catch {
    | JsExn(_) => Error(`${url} is not JSON`)
    }
  | response => Error(`${url} answered ${response->Net.status->Int.toString}`)
  | exception JsExn(e) => Error(`${url}: ${e->JsExn.message->Option.getOr("not reached")}`)
  }
}

/** The pin `name` takes now, from the newest version a published release's manifest lists. */
let resolve = async (~source=?, ~fetch=github, releases: array<JSON.t>, ~name) => {
  let published =
    releases->Array.filter(release => release->field("draft") != Some(JSON.Encode.bool(true)))
  let names =
    published->Array.flatMap(release =>
      release->list("assets")->Array.filterMap(a => a->text("name"))
    )
  switch newest(names, ~name) {
  | None => Ok(None)
  | Some(version) =>
    let holding = published->Array.find(release =>
      release
      ->list("assets")
      ->Array.some(asset =>
        asset
        ->text("name")
        ->Option.mapOr(false, file => file->String.startsWith(`${name}-${version}-`))
      )
    )
    switch holding->Option.flatMap(release =>
      release
      ->list("assets")
      ->Array.find(asset => asset->text("name") == Some("manifest.json"))
      ->Option.flatMap(asset => asset->text("browser_download_url"))
      ->Option.map(url => (release, url))
    ) {
    | None => Ok(None)
    | Some((release, url)) =>
      (await fetch(url))->Result.map(manifest =>
        entryOf(manifest, ~name, ~version)->Option.map(entry =>
          pinned(~source?, ~version, ~release, entry)
        )
      )
    }
  }
}

/** The lock a manifest is written into, its name with `.lock` for `.toml`, beside it. */
let lockOf = file =>
  file->String.endsWith(".toml") ? `${file->String.slice(~start=0, ~end=-5)}.lock` : `${file}.lock`

/** The names a manifest asks for, its one list of strings, whatever it is called there. */
let named = manifest =>
  switch manifest
  ->JSON.Decode.object
  ->Option.getOr(Dict.make())
  ->Dict.valuesToArray
  ->Array.filterMap(JSON.Decode.array)
  ->Array.map(values => values->Array.filterMap(JSON.Decode.string)) {
  | [names] => Ok(names)
  | [] => Error("names no list of what to lock")
  | _ => Error("names more than one list, so which to lock is not known")
  }

/** Where a manifest's names are released, its own source with its one list first, then each
 * table naming a source and a list of its own, whose pins carry that source. */
type source = {repository: string, names: array<string>, own: bool}

let sources = manifest =>
  [
    (true, manifest),
    ...manifest
    ->JSON.Decode.object
    ->Option.getOr(Dict.make())
    ->Dict.valuesToArray
    ->Array.filter(value => value->JSON.Decode.object->Option.isSome)
    ->Array.map(table => (false, table)),
  ]->Array.reduce(Ok([]), (found, (own, table)) =>
    found->Result.flatMap(found =>
      named(table)->Result.map(
        names => [...found, {repository: table->text("source")->Option.getOr(""), names, own}],
      )
    )
  )

/** Each name every source asks for, moved to the newest its source's releases list or kept as it
 * was, and the sources held back, whose releases or one of whose names could not be read. */
type moves = {pins: array<(string, JSON.t)>, held: array<string>}

let moves = async (sources: array<source>, ~locked, ~file, ~lock, ~fetch=github) => {
  let pins = []
  let held = []
  for index in 0 to sources->Array.length - 1 {
    let {repository, names, own} = sources->Array.getUnsafe(index)
    // A name nothing has locked yet is left out rather than written as a table with no version.
    let kept = name => locked->field(name)->Option.forEach(was => pins->Array.push((name, was)))
    let hold = () =>
      if !(held->Array.includes(repository)) {
        held->Array.push(repository)
      }
    switch await fetch(`https://api.github.com/repos/${repository}/releases?per_page=100`) {
    | Error(why) =>
      Console.log(`releases: ${file}, ${repository}'s releases could not be read, ${why}`)
      hold()
      names->Array.forEach(kept)
    | Ok(releases) =>
      let releases = releases->JSON.Decode.array->Option.getOr([])
      for index in 0 to names->Array.length - 1 {
        let name = names->Array.getUnsafe(index)
        let version =
          locked->field(name)->Option.flatMap(was => was->text("version"))->Option.getOr("none")
        switch await resolve(~source=?own ? None : Some(repository), ~fetch, releases, ~name) {
        | Error(why) =>
          Console.log(`releases: ${lock} ${name}, not moved, ${why}`)
          hold()
          kept(name)
        | Ok(None) =>
          Console.log(`releases: ${lock} ${name} ${version}, nothing released to move to`)
          kept(name)
        | Ok(Some(pin)) if pin->text("version") == Some(version) =>
          Console.log(`releases: ${lock} ${name} ${version}, the newest released`)
          pins->Array.push((name, pin))
        | Ok(Some(pin)) =>
          Console.log(
            `releases: ${file} ${name} ${version} -> ${pin->text("version")->Option.getOr("")}`,
          )
          pins->Array.push((name, pin))
        }
      }
    }
  }
  {pins, held}
}

/** The exit where some sources were written and others held back, the lock kept as written. */
let partly = 2

/** The line a run held back in part ends with, naming each source, and the sources it names. */
let heldLine = (file, held) =>
  `releases: ${file}, held back ${held->Array.join(" ")}, the rest written`

let heldIn = output =>
  output
  ->String.split("\n")
  ->Array.findMap(line =>
    switch /^releases: .*, held back (.+), the rest written$/->RegExp.exec(line) {
    | Some(found) => found->RegExp.Result.matches->Array.get(0)->Option.flatMap(x => x)
    | None => None
    }
  )
  ->Option.mapOr([], held => held->String.split(" "))

/**
 * The manifest `file` locked, every source read apart, and the exit it ends with, 0 where all
 * moved, `partly` where some sources were written and others held back with their pins kept, and
 * 1 where nothing is to be kept, no source read in whole.
 */
let update = async (file, ~dry, ~fetch=github) => {
  let manifest = Toml.parse(Node.readFileSync(file))
  let source = manifest->text("source")->Option.getOr("")
  let lock = lockOf(file)
  let locked = Node.existsSync(lock)
    ? Toml.parse(Node.readFileSync(lock))
    : JSON.Encode.object(dict{})
  switch sources(manifest) {
  | Error(why) =>
    Console.log(`releases: ${file} ${why}`)
    1
  | Ok(sources) =>
    let {pins, held} = await moves(sources, ~locked, ~file, ~lock, ~fetch)
    let others = sources->Array.filterMap(found => found.own ? None : Some(found.repository))
    let written = written(~source, ~others, ~manifest=Node.basename(file), pins)
    let code = switch held {
    | [] => 0
    | held if held->Array.length < sources->Array.length => partly
    | _ => 1
    }

    // A source held back keeps each of its pins, so the rest is written, and on 1 nothing is.
    if !dry && code != 1 && (!Node.existsSync(lock) || written != Node.readFileSync(lock)) {
      Node.writeFileSync(lock, written)
    }
    if code == partly {
      Console.log(heldLine(file, held))
      Node.env
      ->Dict.get("GITHUB_OUTPUT")
      ->Option.forEach(output => appendFileSync(output, `held=${held->Array.join(" ")}\n`))
    }
    code
  }
}

let main = async () => {
  let args = Node.args()
  let dry = args->Array.includes("--dry-run") || args->Array.includes("-n")
  switch args->Array.filter(arg => !(arg->String.startsWith("-"))) {
  | [file] => Node.exit(await update(file, ~dry))
  | _ =>
    Console.error("usage: releases.res.mjs <manifest.toml> [--dry-run]")
    Node.exit(1)
  }
}

if Node.isMain {
  main()->ignore
}
