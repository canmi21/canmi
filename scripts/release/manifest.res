/**
 * What a release of the author's holds, the UTC day it is named by, the one `manifest.json` that
 * lists each artifact, and the table its notes are. See docs/toolchain.md.
 */
let field = (json, key) => json->JSON.Decode.object->Option.flatMap(o => o->Dict.get(key))
let text = (json, key) => json->field(key)->Option.flatMap(JSON.Decode.string)
let list = (json, key) => json->field(key)->Option.flatMap(JSON.Decode.array)->Option.getOr([])

/** The file a release carries its manifest in, uploaded after every other asset. */
let file = "manifest.json"

/** The release a day's builds go into, named by the UTC day with each part padded, so the names
 * sort by their text as they do by date. */
let day = now => {
  let date = Date.fromTime(now)
  let pad = n => n->Int.toString->String.padStart(2, "0")
  `${date->Date.getUTCFullYear->Int.toString}.${pad(date->Date.getUTCMonth + 1)}.${pad(
      date->Date.getUTCDate,
    )}`
}

/** Each artifact a manifest lists, `artifacts` in the one shape, or runtime's first `runtimes`
 * read as it, each entry's `runtime` taken as its `name`. */
let artifacts = manifest =>
  switch manifest->field("artifacts") {
  | Some(_) => manifest->list("artifacts")
  | None =>
    manifest
    ->list("runtimes")
    ->Array.map(entry => {
      let fields = entry->JSON.Decode.object->Option.getOr(Dict.make())
      let named = dict{"name": fields->Dict.get("runtime")->Option.getOr(JSON.Encode.null)}
      fields
      ->Dict.toArray
      ->Array.forEach(((key, value)) => key == "runtime" ? () : named->Dict.set(key, value))
      JSON.Encode.object(named)
    })
  }

let same = (a, b) => a->text("name") == b->text("name") && a->text("version") == b->text("version")

/** Whether a manifest lists the artifact at the version. */
let lists = (manifest, ~name, ~version) =>
  manifest
  ->artifacts
  ->Array.some(entry =>
    entry->text("name") == Some(name) && entry->text("version") == Some(version)
  )

/** The release's manifest with each entry put in, one of the same version replaced, the rest kept
 * in their order, in the one shape whatever shape it was read in. */
let merged = (existing: option<JSON.t>, ~release, entries: array<JSON.t>) => {
  let kept =
    existing
    ->Option.mapOr([], artifacts)
    ->Array.filter(old => !(entries->Array.some(entry => same(old, entry))))
  JSON.Encode.object(
    dict{
      "release": JSON.Encode.string(release),
      "artifacts": JSON.Encode.array([...kept, ...entries]),
    },
  )->JSON.stringify(~space=2) ++ "\n"
}

/** Whether a published release carries the artifact's files at the version, so its manifest is
 * the one to read, a draft counting for nothing. */
let holds = (release: JSON.t, ~name, ~version) =>
  release->field("draft") != Some(JSON.Encode.bool(true)) &&
    release
    ->list("assets")
    ->Array.some(asset =>
      asset
      ->text("name")
      ->Option.mapOr(false, file => file->String.startsWith(`${name}-${version}-`))
    )

/** A row of the notes' table, its cells between bars. */
let row = cells => `| ${cells->Array.join(" | ")} |`

/** The head of a release's notes, the table's columns and the line under them. */
let header = columns => [row(columns), row(columns->Array.map(_ => "---"))]

/** The notes with a row added at the table's end, unless they hold it, the table's head first. */
let appended = (notes, ~columns, line) => {
  let head = header(columns)
  let rows =
    notes
    ->String.split("\n")
    ->Array.map(String.trim)
    ->Array.filter(line => line->String.startsWith("| ") && !(head->Array.includes(line)))
  [...head, ...rows->Array.includes(line) ? rows : [...rows, line]]->Array.join("\n")
}

/** A cell with the day's release put in for `{release}`, as a download's address names it. */
let filled = (cell, ~release) => cell->String.replaceAll("{release}", release)

/** One asset as the manifest lists it, its file named and measured where it was built. */
type measured = {target: string, kind: string, file: string, size: float, sha256: string}

/** An artifact as the manifest lists it, its name, version, commit and assets first, then every
 * other field but each asset's path and the row, which release.res adds with its day filled in. */
let entry = (artifact: JSON.t, assets: array<(measured, option<string>)>) => {
  let fields = artifact->JSON.Decode.object->Option.getOr(Dict.make())
  let made = Dict.make()
  ["name", "version", "commit"]->Array.forEach(key =>
    fields->Dict.get(key)->Option.forEach(value => made->Dict.set(key, value))
  )
  made->Dict.set(
    "assets",
    assets
    ->Array.map(((asset, digest)) => {
      let written = dict{
        "target": JSON.Encode.string(asset.target),
        "kind": JSON.Encode.string(asset.kind),
        "file": JSON.Encode.string(asset.file),
        "size": JSON.Encode.float(asset.size),
        "sha256": JSON.Encode.string(asset.sha256),
      }
      digest->Option.forEach(digest => written->Dict.set("digest", JSON.Encode.string(digest)))
      JSON.Encode.object(written)
    })
    ->JSON.Encode.array,
  )
  fields
  ->Dict.toArray
  ->Array.forEach(((key, value)) =>
    ["name", "version", "commit", "assets", "row"]->Array.includes(key)
      ? ()
      : made->Dict.set(key, value)
  )
  JSON.Encode.object(made)
}

/** What is wrong with one artifact of a `built.json`, against the table's columns. */
let refused = (artifact: JSON.t, ~columns: array<string>) => {
  let name = artifact->text("name")
  let version = artifact->text("version")
  let assets = artifact->list("assets")
  let cells = artifact->list("row")->Array.filterMap(JSON.Decode.string)
  switch (name, version, artifact->text("commit")) {
  | (None, _, _) => Some("an artifact names no name")
  | (Some(name), None, _) => Some(`${name} names no version`)
  | (Some(name), _, None) => Some(`${name} names no commit`)
  | (Some(name), Some(version), Some(_)) =>
    if assets == [] {
      Some(`${name} ${version} names no assets`)
    } else if cells->Array.length != columns->Array.length {
      Some(`${name} ${version}'s row has not one cell for each of the table's columns`)
    } else {
      assets->Array.findMap(asset =>
        switch (asset->text("target"), asset->text("kind"), asset->text("path")) {
        | (Some(_), Some(_), Some(path)) =>
          let base = path->String.split("/")->Array.at(-1)->Option.getOr(path)
          base->String.startsWith(`${name}-${version}-`)
            ? None
            : Some(`${path} is not named ${name}-${version}-<system>-<machine>, docs/naming.md`)
        | _ => Some(`${name} ${version} has an asset without its target, kind and path`)
        }
      )
    }
  }
}
