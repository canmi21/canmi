/** GitHub requests belong to scripts/bindings/github.res. */
let maxBuffer = 67108864
let token = () =>
  switch Node.env->Dict.get("GH_TOKEN") {
  | Some(token) => Some(token)
  | None => Node.env->Dict.get("GITHUB_TOKEN")
  }

/** A JSON document from GitHub, with the token where the environment holds one. */
let json = async url => {
  let headers = dict{"accept": "application/vnd.github+json", "user-agent": "workspace-release"}
  if url->String.startsWith("https://api.github.com/") {
    token()->Option.forEach(token => headers->Dict.set("authorization", `Bearer ${token}`))
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

/** Every release from GitHub in pages of one hundred. */
let releases = async (~fetch=json, repository) => {
  let rec page = async (n, found) =>
    switch await fetch(
      `https://api.github.com/repos/${repository}/releases?per_page=100&page=${n->Int.toString}`,
    ) {
    | Error(why) => Error(why)
    | Ok(document) =>
      switch document->JSON.Decode.array {
      | Some([]) => Ok(found)
      | Some(list) => await page(n + 1, [...found, ...list])
      | None => Error(`${repository}'s releases are not a list`)
      }
    }
  await page(1, [])
}

if Node.isMain {
  let result = switch Node.args() {
  | ["json", url] => await json(url)
  | ["releases", repository] => (await releases(repository))->Result.map(JSON.Encode.array)
  | _ => Error("github.res.mjs json <url> | releases <repository>")
  }
  switch result {
  | Ok(document) => Console.log(JSON.stringify(document))
  | Error(why) =>
    Console.error(why)
    Node.exit(1)
  }
}
