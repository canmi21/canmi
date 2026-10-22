/**
 * `releases.res.mjs <pins.json> [--dry-run]`, each artifact a pins file names moved to the newest
 * version its source repository's releases list in their manifests. See docs/toolchain.md.
 */
let field = (json, key) => json->JSON.Decode.object->Option.flatMap(o => o->Dict.get(key))
let text = (json, key) => json->field(key)->Option.flatMap(JSON.Decode.string)
let list = (json, key) => json->field(key)->Option.flatMap(JSON.Decode.array)->Option.getOr([])

/** The Nix system a manifest's target is, `linux-x86_64` taken as `x86_64-linux`. */
let system = target =>
  switch target->String.split("-") {
  | [os, machine] => Some(`${machine}-${os}`)
  | _ => None
  }

/** The highest version a release names an archive of for `name`, read from the archives' names. */
let newest = (names: array<string>, ~name) =>
  names
  ->Array.filterMap(file =>
    switch RegExp.fromString(`^${name}-(\\d[^-]*)-[a-z0-9]+-[a-z0-9_]+\\.tar$`)->RegExp.exec(file) {
    | Some(result) => result->RegExp.Result.matches->Array.get(0)->Option.flatMap(x => x)
    | None => None
    }
  )
  ->Array.toSorted((a, b) => Outdated.order(b, a))
  ->Array.get(0)

/** A pin as the pins file holds it, its version and each system's address and SHA-256, from the
 * release that lists it and the manifest's entry for it. */
let pinned = (~version, ~release: JSON.t, entry: JSON.t) => {
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

/** The entry a release's manifest gives `name` at `version`, where it lists it. */
let entryOf = (manifest: JSON.t, ~name, ~version) =>
  manifest
  ->list("runtimes")
  ->Array.find(entry =>
    entry->text("runtime") == Some(name) && entry->text("version") == Some(version)
  )

/** A JSON document from GitHub, with the token where the environment holds one. */
let github = async url => {
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
let resolve = async (releases: array<JSON.t>, ~name) => {
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
      (await github(url))->Result.map(manifest =>
        entryOf(manifest, ~name, ~version)->Option.map(entry => pinned(~version, ~release, entry))
      )
    }
  }
}

let main = async () => {
  let args = Node.args()
  let dry = args->Array.includes("--dry-run") || args->Array.includes("-n")
  switch args->Array.filter(arg => !(arg->String.startsWith("-"))) {
  | [file] =>
    let pins = JSON.parseOrThrow(Node.readFileSync(file))
    let source = pins->text("source")->Option.getOr("")
    let failed = ref(false)
    switch await github(`https://api.github.com/repos/${source}/releases?per_page=100`) {
    | Error(why) =>
      Console.log(`releases: ${file}, ${source}'s releases could not be read, ${why}`)
      Node.exit(1)
    | Ok(releases) =>
      let releases = releases->JSON.Decode.array->Option.getOr([])
      let current =
        pins->field("pins")->Option.flatMap(JSON.Decode.object)->Option.getOr(Dict.make())
      let moved = Dict.make()
      let names = current->Dict.keysToArray
      for index in 0 to names->Array.length - 1 {
        let name = names->Array.getUnsafe(index)
        let was = current->Dict.getUnsafe(name)
        let version = was->text("version")->Option.getOr("none")
        switch await resolve(releases, ~name) {
        | Error(why) =>
          Console.log(`releases: ${file} ${name}, not moved, ${why}`)
          failed := true
          moved->Dict.set(name, was)
        | Ok(None) =>
          Console.log(`releases: ${file} ${name} ${version}, nothing released to move to`)
          moved->Dict.set(name, was)
        | Ok(Some(pin)) if pin->text("version") == Some(version) =>
          Console.log(`releases: ${file} ${name} ${version}, the newest released`)
          moved->Dict.set(name, was)
        | Ok(Some(pin)) =>
          Console.log(
            `releases: ${file} ${name} ${version} -> ${pin->text("version")->Option.getOr("")}`,
          )
          moved->Dict.set(name, pin)
        }
      }
      let written =
        JSON.Encode.object(
          dict{"source": JSON.Encode.string(source), "pins": JSON.Encode.object(moved)},
        )->JSON.stringify(~space=2) ++ "\n"
      if !dry && written != Node.readFileSync(file) {
        Node.writeFileSync(file, written)
      }
      Node.exit(failed.contents ? 1 : 0)
    }
  | _ =>
    Console.error("usage: releases.res.mjs <pins.json> [--dry-run]")
    Node.exit(1)
  }
}

if Node.isMain {
  main()->ignore
}
