/**
 * `release.res.mjs [listed | notes] [--dry-run]`, from a repository declaring `[release]`, puts
 * what its `built.json` names into the UTC day's release, prints what is out, or renders each
 * day's notes again from its manifest. See docs/toolchain.md.
 */
let refuse = why => {
  Console.error(`release: ${why}`)
  Node.exit(1)
}

let root = Node.cwd()
let dry = Node.args()->Array.includes("--dry-run") || Node.args()->Array.includes("-n")

/** The repository released to, as the workflow names it, or its checkout's `origin` locally. */
let repository = () =>
  switch Node.env->Dict.get("GITHUB_REPOSITORY") {
  | Some(named) => Some(named)
  | None =>
    /(?:github\.com[:\/])([^\/\s]+\/[^\/\s]+?)(?:\.git)?\s*$/
    ->RegExp.exec(Node.output(~cwd=root, "git", ["remote", "get-url", "origin"]))
    ->Option.flatMap(found => found->RegExp.Result.matches->Array.get(0)->Option.flatMap(x => x))
  }

let token = switch Node.env->Dict.get("GH_TOKEN") {
| Some(token) => Some(token)
| None => Node.env->Dict.get("GITHUB_TOKEN")
}

/** A JSON document from GitHub, with the token where the environment holds one. */
let json = async url => {
  let headers = dict{"accept": "application/vnd.github+json", "user-agent": "workspace-release"}
  if url->String.startsWith("https://api.github.com/") {
    token->Option.forEach(token => headers->Dict.set("authorization", `Bearer ${token}`))
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

/** Every release of the repository, a page of a hundred at a time, drafts among them. */
let releases = async repository => {
  let rec page = async (n, found) =>
    switch await json(
      `https://api.github.com/repos/${repository}/releases?per_page=100&page=${n->Int.toString}`,
    ) {
    | Error(why) if dry && n == 1 && why->String.endsWith("answered 404") =>
      Console.error(`release: ${repository} is not on GitHub, so a dry run reads it as no releases`)
      Ok([])
    | Error(why) => Error(why)
    | Ok(listed) =>
      switch listed->JSON.Decode.array {
      | Some([]) => Ok(found)
      | Some(list) => await page(n + 1, [...found, ...list])
      | None => Error(`${repository}'s releases are not a list`)
      }
    }
  await page(1, [])
}

/** A release's manifest as it was uploaded, or none where the release carries none. */
let manifestOf = async release =>
  switch release
  ->Manifest.list("assets")
  ->Array.find(asset => asset->Manifest.text("name") == Some(Manifest.file))
  ->Option.flatMap(asset => asset->Manifest.text("browser_download_url")) {
  | None => Ok(None)
  | Some(url) => (await json(url))->Result.map(manifest => Some(manifest))
  }

let published = releases =>
  releases->Array.filter(release =>
    release->Manifest.field("draft") != Some(JSON.Encode.bool(true))
  )

/** Each artifact every published release's manifest lists, the newest release first, each with the
 * release it was read from. */
let listed = async releases => {
  let ordered =
    published(releases)->Array.toSorted((a, b) =>
      String.compare(
        b->Manifest.text("tag_name")->Option.getOr(""),
        a->Manifest.text("tag_name")->Option.getOr(""),
      )
    )
  let rec read = async (index, found) =>
    switch ordered[index] {
    | None => Ok(found)
    | Some(release) =>
      switch await manifestOf(release) {
      | Error(why) => Error(why)
      | Ok(None) => await read(index + 1, found)
      | Ok(Some(manifest)) =>
        let tag = release->Manifest.text("tag_name")->Option.getOr("")
        let entries =
          manifest
          ->Manifest.artifacts
          ->Array.map(entry => {
            let fields = entry->JSON.Decode.object->Option.getOr(Dict.make())->Dict.copy
            fields->Dict.set("release", JSON.Encode.string(tag))
            JSON.Encode.object(fields)
          })
        await read(index + 1, [...found, ...entries])
      }
    }
  await read(0, [])
}

/** Whether a published release here lists the artifact at the version, only those carrying its
 * files read. */
let releasedHere = async (releases, ~name, ~version) => {
  let rec any = async holding =>
    switch holding {
    | [] => Ok(false)
    | _ =>
      switch await manifestOf(holding->Array.getUnsafe(0)) {
      | Error(why) => Error(why)
      | Ok(Some(manifest)) if Manifest.lists(manifest, ~name, ~version) => Ok(true)
      | Ok(_) => await any(holding->Array.slice(~start=1))
      }
    }
  await any(releases->Array.filter(release => Manifest.holds(release, ~name, ~version)))
}

let shown = arg => arg->String.includes(" ") || arg->String.includes("\n") ? `'${arg}'` : arg

/** A command printed, then run unless the run is dry. */
let run = (command, args) => {
  Console.log(`  $ ${[command, ...args->Array.map(shown)]->Array.join(" ")}`)
  dry || Node.run(~cwd=root, command, args) == 0
    ? Ok()
    : Error(`${command} ${args->Array.slice(~start=0, ~end=2)->Array.join(" ")} failed`)
}

/** Each asset an artifact names, measured where it was built, its digest kept, and the path it is
 * uploaded from. */
let measured = artifact =>
  artifact
  ->Manifest.list("assets")
  ->Array.map(asset => {
    let path = asset->Manifest.text("path")->Option.getOr("")
    let at = Node.isAbsolute(path) ? path : Node.join([root, path])
    let (size, sha256) = if Node.existsSync(at) {
      (
        Net.statSync(at).size,
        Net.createHash("sha256")->Net.updateBytes(Node.readBytes(at))->Net.hexDigest,
      )
    } else {
      (0., "<not built>")
    }
    let made: Manifest.measured = {
      target: asset->Manifest.text("target")->Option.getOr(""),
      kind: asset->Manifest.text("kind")->Option.getOr(""),
      file: Node.basename(path),
      size,
      sha256,
    }
    ((made, asset->Manifest.text("digest")), at)
  })

/** A row's first two cells, the artifact and its version as the notes' table names them. */
let leading = line =>
  line
  ->String.trim
  ->String.split("|")
  ->Array.slice(~start=1, ~end=3)
  ->Array.map(String.trim)

/** The notes a release's manifest gives, its table's head, then the rows of what it listed before
 * its entries carried their rows, as the notes held them, then one row for each entry carrying its
 * own, so the table is rendered again whole from the manifest by any run. */
let notesOf = (manifest, ~body, ~columns) => {
  let head = Manifest.header(columns)
  let rows =
    manifest
    ->Manifest.artifacts
    ->Array.filterMap(entry =>
      switch entry->Manifest.list("row")->Array.filterMap(JSON.Decode.string) {
      | [] => None
      | cells => Some(Manifest.row(cells))
      }
    )
  let earlier =
    body
    ->String.split("\n")
    ->Array.map(String.trim)
    ->Array.filter(line => line->String.startsWith("| ") && !(head->Array.includes(line)))
    ->Array.filter(line => !(rows->Array.some(row => leading(row) == leading(line))))
    ->Array.reduce([], (kept, line) =>
      kept->Array.some(held => leading(held) == leading(line)) ? kept : [...kept, line]
    )
  [...head, ...earlier, ...rows]->Array.join("\n")
}

/** Text as GitHub may give it back, its line ends plain and its ends trimmed. */
let plain = text => text->String.replaceAll("\r\n", "\n")->String.trim

/** What was built released under the UTC day, a new release drafted whole and published last, or
 * the day's published one added to, its files, then its merged manifest, each entry of the same
 * version replaced whole, then its notes rendered from that manifest. */
let release = async (artifacts, ~releases, ~repository, ~columns, ~directory) => {
  let tag = Manifest.day(Date.now())
  let named = releases->Array.filter(release => release->Manifest.text("tag_name") == Some(tag))
  let standing =
    named->Array.find(release => release->Manifest.field("draft") != Some(JSON.Encode.bool(true)))
  let gh = args => run("gh", [...args, "--repo", repository])
  let measured = artifacts->Array.map(artifact => (artifact, measured(artifact)))
  let missing =
    measured->Array.flatMap(((_, assets)) =>
      assets->Array.filterMap(((_, at)) => Node.existsSync(at) ? None : Some(at))
    )
  let files = measured->Array.flatMap(((_, assets)) => assets->Array.map(((_, at)) => at))
  // Each entry keeps the row its notes take, the day filled in, so the notes are its manifest's.
  let entries = measured->Array.map(((artifact, assets)) => {
    let entry = Manifest.entry(artifact, assets->Array.map(((asset, _)) => asset))
    let fields = entry->JSON.Decode.object->Option.getOr(Dict.make())->Dict.copy
    let cells =
      artifact
      ->Manifest.list("row")
      ->Array.filterMap(JSON.Decode.string)
      ->Array.map(cell => JSON.Encode.string(Manifest.filled(cell, ~release=tag)))
    fields->Dict.set("row", JSON.Encode.array(cells))
    JSON.Encode.object(fields)
  })
  let manifest = Node.join([directory, Manifest.file])
  let write = existing => {
    let text = Manifest.merged(existing, ~release=tag, entries)
    if dry {
      Console.log(`  ${Manifest.file} would read`)
      text->String.trimEnd->String.split("\n")->Array.forEach(line => Console.log(`    ${line}`))
    } else {
      Node.mkdirAll(directory)
      Node.writeFileSync(manifest, text)
    }
    JSON.parseOrThrow(text)
  }
  measured->Array.forEach(((artifact, assets)) => {
    let name = artifact->Manifest.text("name")->Option.getOr("")
    let version = artifact->Manifest.text("version")->Option.getOr("")
    Console.log(`${name} ${version}`)
    assets->Array.forEach(((({file, size, sha256}, _), _)) =>
      Console.log(`  ${file} ${size->Float.toString} bytes, sha256 ${sha256}`)
    )
  })
  switch (missing, standing) {
  | (_, _) if !dry && missing != [] => Error(`not built: ${missing->Array.join(", ")}`)
  | (_, Some(standing)) =>
    Console.log(`release ${tag}, added to`)
    switch await manifestOf(standing) {
    | Error(why) => Error(why)
    | Ok(existing) =>
      let merged = write(existing)
      let body = standing->Manifest.text("body")->Option.getOr("")
      gh(["release", "upload", tag, ...files, "--clobber"])
      ->Result.flatMap(() => gh(["release", "upload", tag, manifest, "--clobber"]))
      ->Result.flatMap(() =>
        gh(["release", "edit", tag, "--notes", notesOf(merged, ~body, ~columns)])
      )
    }
  | (_, None) =>
    Console.log(`release ${tag}, new`)
    let merged = write(None)
    // A draft a failed run left under the day's name is put aside, so one release takes the name.
    named
    ->Array.reduce(Ok(), (done, _) =>
      done->Result.flatMap(() => gh(["release", "delete", tag, "--yes"]))
    )
    ->Result.flatMap(() =>
      gh(
        [
          "release",
          "create",
          tag,
          "--draft",
          "--title",
          tag,
          "--notes",
          notesOf(merged, ~body="", ~columns),
          ...files,
          manifest,
        ],
      )
    )
    ->Result.flatMap(() => gh(["release", "edit", tag, "--draft=false"]))
  }
}

/** Each published release whose manifest's entries carry their rows, but `except`, its notes
 * edited where they are not what that manifest renders, as a failed edit leaves them. */
let repaired = async (releases, ~repository, ~columns, ~except=[]) => {
  let rec next = async (holding, done) =>
    switch holding {
    | [] => done
    | _ =>
      let release = holding->Array.getUnsafe(0)
      let rest = holding->Array.slice(~start=1)
      let tag = release->Manifest.text("tag_name")->Option.getOr("")
      switch await manifestOf(release) {
      | Error(why) => await next(rest, Error(why))
      | Ok(None) => await next(rest, done)
      | Ok(Some(manifest)) =>
        let rowed =
          manifest->Manifest.artifacts->Array.some(entry => entry->Manifest.list("row") != [])
        let body = release->Manifest.text("body")->Option.getOr("")
        let notes = notesOf(manifest, ~body, ~columns)
        if !rowed || plain(notes) == plain(body) {
          await next(rest, done)
        } else {
          Console.log(`release ${tag}, its notes rendered again from its ${Manifest.file}`)
          let edited = run("gh", ["release", "edit", tag, "--notes", notes, "--repo", repository])
          await next(rest, done->Result.flatMap(() => edited))
        }
      }
    }
  await next(
    published(releases)->Array.filter(release =>
      !(except->Array.includes(release->Manifest.text("tag_name")->Option.getOr("")))
    ),
    Ok(),
  )
}

/** What a run releases of `artifacts`, what a published release lists passed over, and then each
 * other day's notes rendered again where a failed edit left them short. */
let releasing = async (artifacts, ~releases, ~repository, ~columns, ~directory) => {
  let rec fresh = async (index, kept) =>
    switch artifacts[index] {
    | None => Ok(kept)
    | Some(artifact) =>
      let name = artifact->Manifest.text("name")->Option.getOr("")
      let version = artifact->Manifest.text("version")->Option.getOr("")
      switch await releasedHere(releases, ~name, ~version) {
      | Error(why) => Error(why)
      | Ok(true) =>
        Console.log(`${name} ${version}, released already`)
        await fresh(index + 1, kept)
      | Ok(false) => await fresh(index + 1, [...kept, artifact])
      }
    }
  switch await fresh(0, []) {
  | Error(why) => Error(why)
  | Ok([]) =>
    Console.log("release: nothing new to release")
    await repaired(releases, ~repository, ~columns)
  | Ok(artifacts) =>
    switch await release(artifacts, ~releases, ~repository, ~columns, ~directory) {
    | Error(why) => Error(`not released: ${why}`)
    | Ok() => await repaired(releases, ~repository, ~columns, ~except=[Manifest.day(Date.now())])
    }
  }
}

let main = async () => {
  let repository = switch repository() {
  | Some(repository) => repository
  | None => refuse("no GITHUB_REPOSITORY, and no GitHub remote named origin")
  }
  switch Node.args()->Array.filter(arg => !(arg->String.startsWith("-"))) {
  | ["listed"] =>
    switch await releases(repository) {
    | Error(why) => refuse(why)
    | Ok(releases) =>
      switch await listed(releases) {
      | Error(why) => refuse(why)
      | Ok(entries) => Console.log(JSON.Encode.array(entries)->JSON.stringify(~space=2))
      }
    }
  | [] =>
    let (_, declared) = Project.here("release", declared => declared.release)
    let built = Node.join([root, declared.built])
    if !Node.existsSync(built) {
      Console.log(`release: nothing built, ${declared.built} is absent`)
      Node.exit(dry ? 0 : 1)
    }
    let artifacts = switch JSON.parseOrThrow(Node.readFileSync(built)) {
    | document => document->Manifest.list("artifacts")
    | exception JsExn(_) => refuse(`${declared.built} is not JSON`)
    }
    switch artifacts->Array.findMap(artifact =>
      Manifest.refused(artifact, ~columns=declared.columns)
    ) {
    | Some(why) => refuse(`${declared.built}: ${why}`)
    | None => ()
    }
    switch await releases(repository) {
    | Error(why) => refuse(why)
    | Ok(releases) =>
      switch await releasing(
        artifacts,
        ~releases,
        ~repository,
        ~columns=declared.columns,
        ~directory=Node.dirname(built),
      ) {
      | Error(why) => refuse(why)
      | Ok() => ()
      }
    }
  | ["notes"] =>
    let (_, declared) = Project.here("release", declared => declared.release)
    switch await releases(repository) {
    | Error(why) => refuse(why)
    | Ok(releases) =>
      switch await repaired(releases, ~repository, ~columns=declared.columns) {
      | Error(why) => refuse(why)
      | Ok() => Console.log("release: every day's notes are what its manifest renders")
      }
    }
  | _ => refuse("release.res.mjs [listed | notes] [--dry-run]")
  }
}

if Node.isMain {
  main()->ignore
}
