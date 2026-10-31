type item = {repository: string, kind: string, name: string, from: string, to: string}
type seen = {item: item, firstSeen: string}
type summary = {items: array<seen>}

let item = (~repository=Registry.label(Node.cwd()), kind, name, from, to): item => {
  repository,
  kind,
  name,
  from,
  to,
}
let encode = items => JSON.stringifyAny(items)->Option.getOr("[]")
let decode = text => {
  let string = (fields, key) => fields->Dict.get(key)->Option.flatMap(JSON.Decode.string)
  switch JSON.parseOrThrow(text) {
  | Array(items) =>
    items->Array.filterMap(value =>
      switch value {
      | Object(fields) =>
        switch (
          string(fields, "repository"),
          string(fields, "kind"),
          string(fields, "name"),
          string(fields, "from"),
          string(fields, "to"),
        ) {
        | (Some(repository), Some(kind), Some(name), Some(from), Some(to)) =>
          Some({repository, kind, name, from, to})
        | _ => None
        }
      | _ => None
      }
    )
  | _ => throw(Registry.Refused("update summary must be an array"))
  }
}
let day = now => Date.fromTime(now)->Date.toISOString->String.slice(~start=0, ~end=10)
let due = (~now, previous) => previous != Some(day(now))
let same = (a: item, b: item) => a == b
let carry = (~today, previous: array<seen>, items) =>
  items->Array.map(item => {
    item,
    firstSeen: previous
    ->Array.find(old => same(old.item, item))
    ->Option.mapOr(today, old => old.firstSeen),
  })
let reported = (~now, entry: seen) =>
  ["action", "major", "missing"]->Array.includes(entry.item.kind) ||
    (["tool", "package", "image", "release", "flake"]->Array.includes(entry.item.kind) &&
      Date.fromString(day(now))->Date.getTime -. Date.fromString(entry.firstSeen)->Date.getTime >
        2. *. 86400000.)
let render = (~now, entries) => {
  let counts = Dict.make()
  entries
  ->Array.filter(entry => reported(~now, entry))
  ->Array.forEach(entry => {
    let kind = entry.item.kind
    counts->Dict.set(kind, counts->Dict.get(kind)->Option.getOr(0) + 1)
  })
  let parts =
    [
      "action",
      "major",
      "missing",
      "tool",
      "package",
      "image",
      "release",
      "flake",
    ]->Array.filterMap(kind =>
      counts->Dict.get(kind)->Option.map(count => `${Int.toString(count)} ${kind}`)
    )
  parts == [] ? "" : `${parts->Array.join(", ")}; mise run update --dry-run for detail`
}

@module("node:os") external homedir: unit => string = "homedir"
@module("node:fs") external openExclusive: (string, @as("wx") _) => int = "openSync"
@module("node:fs") external close: int => unit = "closeSync"
@module("node:fs") external openLog: (string, @as("a") _) => int = "openSync"
@module("node:fs") external rename: (string, string) => unit = "renameSync"
type child
type spawnOptions = {cwd: string, detached: bool, stdio: (string, int, int)}
@module("node:child_process")
external spawn: (string, array<string>, spawnOptions) => child = "spawn"
@send external unref: child => unit = "unref"
@send external onError: (child, @as("error") _, JsExn.t => unit) => unit = "on"
let directory = () =>
  Node.join([
    Node.env
    ->Dict.get("XDG_CACHE_HOME")
    ->Option.filter(value => value != "")
    ->Option.getOr(Node.join([homedir(), ".cache"])),
    "monoflake",
    "update",
  ])
let read = path =>
  try Some(Node.readFileSync(path)) catch {
  | _ => None
  }
let previous = directory =>
  try {
    let raw = Node.readFileSync(Node.join([directory, "summary.json"]))->JSON.parseOrThrow
    switch raw {
    | Object(fields) =>
      switch fields->Dict.get("items") {
      | Some(Array(entries)) =>
        entries->Array.filterMap(entry =>
          switch entry {
          | Object(fields) =>
            switch (
              fields->Dict.get("item"),
              fields->Dict.get("firstSeen")->Option.flatMap(JSON.Decode.string),
            ) {
            | (Some(item), Some(firstSeen)) =>
              decode(JSON.stringify(JSON.Array([item])))
              ->Array.get(0)
              ->Option.map(item => {item, firstSeen})
            | _ => None
            }
          | _ => None
          }
        )
      | _ => []
      }
    | _ => []
    }
  } catch {
  | _ => []
  }
let line = () =>
  try render(~now=Date.now(), previous(directory())) catch {
  | _ => ""
  }
let start = () =>
  try {
    let cache = directory()
    Node.mkdirAll(cache)
    let today = day(Date.now())
    let stamp = Node.join([cache, "started"])
    if due(~now=Date.now(), read(stamp)) {
      let lock = openExclusive(Node.join([cache, `${today}.started`]))
      close(lock)
      Node.writeFileSync(stamp, today)
      let log = openLog(Node.join([cache, "update.log"]))
      let child = spawn(
        "node",
        [Node.join([Registry.root, "scripts", "workspace", "reminder.res.mjs"]), "collect"],
        {cwd: Registry.root, detached: true, stdio: ("ignore", log, log)},
      )
      child->onError(_ => ())
      child->unref
      close(log)
    }
  } catch {
  | _ => ()
  }
let collect = () => {
  let cache = directory()
  let result = Node.spawnSync(
    "mise",
    ["run", "update", "--all", "--dry-run", "--json"],
    {cwd: Registry.root, encoding: "utf8", maxBuffer: 268435456},
  )
  Console.log(result.stderr->Nullable.getOr(""))
  Console.log(result.stdout->Nullable.getOr(""))
  if result.status == Nullable.make(0) {
    let items = decode(result.stdout->Nullable.getOr(""))
    let summary: summary = {items: carry(~today=day(Date.now()), previous(cache), items)}
    let pending = Node.join([cache, "summary.pending.json"])
    Node.writeFileSync(pending, JSON.stringifyAny(summary)->Option.getOr("{}"))
    rename(pending, Node.join([cache, "summary.json"]))
  }
}
if Node.isMain {
  try {
    switch Node.args()[0] {
    | Some("start") => start()
    | Some("line") =>
      let text = line()
      if text != "" {
        Console.log(text)
      }
    | Some("collect") => collect()
    | _ => ()
    }
  } catch {
  | _ => ()
  }
}
