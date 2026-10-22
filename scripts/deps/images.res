/**
 * The base images a repository's Dockerfiles pin by digest, each moved to the digest its tag names
 * now, the tag kept. See docs/toolchain.md.
 */
/** A `FROM` pinned by digest, its lead, image, tag, digest and the rest of the line. */
let from = /^(FROM\s+(?:--platform=\S+\s+)?)([^\s:@]+):([^\s@]+)@(sha256:[0-9a-f]{64})(.*)$/

/** A base image as a Dockerfile pins it, by the line it stands on. */
type base = {index: int, image: string, tag: string, digest: string}

let groups = (pattern, line) =>
  pattern
  ->RegExp.exec(line)
  ->Option.map(result => result->RegExp.Result.matches->Array.map(group => group->Option.getOr("")))

/** Every base image a Dockerfile pins by digest. */
let bases = text =>
  text
  ->String.split("\n")
  ->Array.mapWithIndex((line, index) =>
    switch groups(from, line) {
    | Some([_, image, tag, digest, _]) => Some({index, image, tag, digest})
    | _ => None
    }
  )
  ->Array.filterMap(base => base)

/** The text with each line a base stands on pinned to its tag's digest instead. */
let rebased = (text, digests: dict<string>) =>
  text
  ->String.split("\n")
  ->Array.map(line =>
    switch groups(from, line) {
    | Some([lead, image, tag, old, rest]) =>
      let digest = digests->Dict.get(`${image}:${tag}`)->Option.getOr(old)
      `${lead}${image}:${tag}@${digest}${rest}`
    | _ => line
    }
  )
  ->Array.join("\n")

/** The registry an image is served from and its repository there, Docker Hub's by default. */
let located = image =>
  switch image->String.split("/") {
  | [name] => ("registry-1.docker.io", `library/${name}`)
  | parts =>
    let first = parts->Array.getUnsafe(0)
    if first->String.includes(".") || first->String.includes(":") {
      let host = first == "docker.io" ? "registry-1.docker.io" : first
      (host, parts->Array.slice(~start=1)->Array.join("/"))
    } else {
      ("registry-1.docker.io", image)
    }
  }

/** Where a registry's challenge says its token is asked for, with its service and scope. */
let challenged = header => {
  let value = key =>
    RegExp.fromString(`${key}="([^"]*)"`)
    ->RegExp.exec(header)
    ->Option.flatMap(result => result->RegExp.Result.matches->Array.get(0)->Option.flatMap(x => x))
  if !(header->String.toLowerCase->String.startsWith("bearer ")) {
    None
  } else {
    value("realm")->Option.map(realm => {
      let query =
        ["service", "scope"]
        ->Array.filterMap(key =>
          value(key)->Option.map(found => `${key}=${encodeURIComponent(found)}`)
        )
        ->Array.join("&")
      query == "" ? realm : `${realm}?${query}`
    })
  }
}

/** The directories a search for Dockerfiles passes over, what a tool wrote or a checkout holds. */
let skipped = ["node_modules", ".git", ".jj", "dist", "target", "lib"]

/** Every Dockerfile under `root`, by Docker's own name for it alone, docs/naming.md. */
let rec dockerfiles = root =>
  Node.entries(root)
  ->Array.toSorted((a, b) => String.compare(a->Node.name, b->Node.name))
  ->Array.flatMap(entry => {
    let path = Node.join([root, entry->Node.name])
    if entry->Node.isDirectory && !(skipped->Array.includes(entry->Node.name)) {
      dockerfiles(path)
    } else if entry->Node.isFile && entry->Node.name == "Dockerfile" {
      [path]
    } else {
      []
    }
  })

/** The index and manifest types a registry is asked to answer a tag with. */
let accepted = [
  "application/vnd.oci.image.index.v1+json",
  "application/vnd.docker.distribution.manifest.list.v2+json",
  "application/vnd.oci.image.manifest.v1+json",
  "application/vnd.docker.distribution.manifest.v2+json",
]->Array.join(", ")

let reached = async (url, init) =>
  switch await Net.fetch(url, init) {
  | response => Ok(response)
  | exception JsExn(e) => Error(`${url}: ${e->JsExn.message->Option.getOr("not reached")}`)
  }

let field = (json, key) =>
  json
  ->JSON.Decode.object
  ->Option.flatMap(o => o->Dict.get(key))
  ->Option.flatMap(JSON.Decode.string)

/** The digest a tag names now, asked by HEAD so nothing is pulled, with the anonymous token a
 * registry's challenge asks for. */
let digestOf = async (image, tag) => {
  let (host, name) = located(image)
  let url = `https://${host}/v2/${name}/manifests/${tag}`
  let ask = async bearer => {
    let headers = dict{"accept": accepted}
    bearer->Option.forEach(bearer => headers->Dict.set("authorization", `Bearer ${bearer}`))
    await reached(url, {method: "HEAD", headers})
  }
  let found = response =>
    switch response->Net.responseHeaders->Net.header("docker-content-digest")->Nullable.toOption {
    | Some(digest) if response->Net.ok => Ok(digest)
    | _ => Error(`${url} answered ${response->Net.status->Int.toString} with no digest`)
    }
  switch await ask(None) {
  | Error(why) => Error(why)
  | Ok(response) if response->Net.status != 401 => found(response)
  | Ok(response) =>
    switch response
    ->Net.responseHeaders
    ->Net.header("www-authenticate")
    ->Nullable.toOption
    ->Option.flatMap(challenged) {
    | None => Error(`${url} asked for a token it did not say how to get`)
    | Some(realm) =>
      switch await reached(realm, {headers: dict{}}) {
      | Error(why) => Error(why)
      | Ok(answer) =>
        let text = await answer->Net.responseText
        switch JSON.parseOrThrow(text) {
        | json =>
          switch (json->field("token"), json->field("access_token")) {
          | (Some(bearer), _) | (None, Some(bearer)) =>
            switch await ask(Some(bearer)) {
            | Ok(response) => found(response)
            | Error(why) => Error(why)
            }
          | (None, None) => Error(`${realm} gave no token`)
          }
        | exception JsExn(_) => Error(`${realm} answered with no JSON`)
        }
      }
    }
  }
}

let main = async () => {
  let dry = Node.args()->Array.includes("--dry-run") || Node.args()->Array.includes("-n")
  let root = Node.cwd()
  let files = dockerfiles(root)
  if files == [] {
    Console.log("images: no Dockerfile here")
    Node.exit(0)
  }
  let texts = files->Array.map(file => (file, Node.readFileSync(file)))
  // Each tag asked once, though several stages and files pin it.
  let tags =
    texts
    ->Array.flatMap(((_, text)) => bases(text))
    ->Array.map(({image, tag}) => `${image}:${tag}`)
    ->Array.reduce([], (seen, key) => seen->Array.includes(key) ? seen : [...seen, key])
  let digests = Dict.make()
  let failed = ref(false)
  for index in 0 to tags->Array.length - 1 {
    let key = tags->Array.getUnsafe(index)
    let at = key->String.lastIndexOf(":")
    switch await digestOf(key->String.slice(~start=0, ~end=at), key->String.slice(~start=at + 1)) {
    | Ok(digest) => digests->Dict.set(key, digest)
    | Error(why) =>
      Console.log(`images: ${key}, its digest could not be read, ${why}`)
      failed := true
    }
  }
  texts->Array.forEach(((file, text)) => {
    let shown = Node.relative(root, file)
    bases(text)
    ->Array.reduce([], (seen: array<base>, base) =>
      seen->Array.some(other => other.image == base.image && other.tag == base.tag)
        ? seen
        : [...seen, base]
    )
    ->Array.forEach(({image, tag, digest}) =>
      switch digests->Dict.get(`${image}:${tag}`) {
      | Some(now) if now != digest =>
        Console.log(`images: ${shown} ${image}:${tag} ${digest} -> ${now}`)
      | Some(_) => Console.log(`images: ${shown} ${image}:${tag}, its tag's digest still`)
      | None => ()
      }
    )
    let moved = rebased(text, digests)
    if moved != text && !dry {
      Node.writeFileSync(file, moved)
    }
  })
  Node.exit(failed.contents ? 1 : 0)
}

if Node.isMain {
  main()->ignore
}
