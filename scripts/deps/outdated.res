/**
 * What waits beyond a repository's package ranges, judged by the newest version it holds anywhere:
 * a package is out of date only when that is older than the registry's latest. One on the latest
 * somewhere while another copy holds an older major is two majors at once, a warning unless
 * `versions.toml` allows it. `--names` prints only what `update --major` should move. See
 * spec/toolchain.md, "A package at two majors is a warning unless it is allowed".
 */
let entry = /^("?)([^"=\s]+)\1\s*=\s*"(.*)"$/
let brackets = /^\[+|\]+$/g
let lineBreak = /\r?\n/
let digits = /^\d+$/
let local = /^(link:|file:|workspace:)/

/** `versions.toml`'s `[several]`: package name -> why it may hold two majors. */
let allowed = (text: string): Map.t<string, string> => {
  let found = Map.make()
  let section = ref(None)
  text
  ->String.splitByRegExp(lineBreak)
  ->Array.forEach(raw => {
    let line = raw->Option.getOr("")->String.trim
    if line != "" && !(line->String.startsWith("#")) {
      if line->String.startsWith("[") {
        section := Some(line->String.replaceRegExp(brackets, ""))
      } else if section.contents == Some("several") {
        switch entry->RegExp.exec(line) {
        | Some(result) =>
          switch result->RegExp.Result.matches {
          | [_, Some(name), Some(why)] => found->Map.set(name, why->String.replaceAll("\\\"", "\""))
          | _ => ()
          }
        | None => ()
        }
      }
    }
  })
  found
}

/** A version as something to sort by: its numbers, then a release above any prerelease of it. */
let key = (version: string): array<int> => {
  let dash = version->String.indexOf("-")
  let core = dash < 0 ? version : version->String.slice(~start=0, ~end=dash)
  let numbers =
    core
    ->String.split(".")
    ->Array.map(part => digits->RegExp.test(part) ? part->Int.fromString->Option.getOr(0) : 0)
  Array.concat(numbers, [dash < 0 ? 1 : 0])
}

/** -1, 0 or 1 as `a` sorts before, with or after `b`, as Python compares two tuples. */
let compare = (a: string, b: string): int => {
  let (x, y) = (key(a), key(b))
  let shorter = Math.Int.min(x->Array.length, y->Array.length)
  let rec at = index =>
    if index == shorter {
      x->Array.length == y->Array.length ? 0 : x->Array.length < y->Array.length ? -1 : 1
    } else {
      let (p, q) = (x->Array.getUnsafe(index), y->Array.getUnsafe(index))
      p == q ? at(index + 1) : p < q ? -1 : 1
    }
  at(0)
}

let order = (a, b) => Int.toFloat(compare(a, b))

/** The part a `^` range holds: the first non-zero number, as `^0.x` does. */
let major = (version: string): string => {
  let parts = version->String.split("-")->Array.getUnsafe(0)->String.split(".")
  switch parts->Array.findIndex(part => part != "0") {
  | -1 => version
  | index => parts->Array.slice(~start=0, ~end=index + 1)->Array.join(".")
  }
}

/** The newest of `versions`, the first of equals, as Python's `max` keeps it. */
let newest = (versions: array<string>) =>
  versions
  ->Array.slice(~start=1)
  ->Array.reduce(versions->Array.getUnsafe(0), (best, one) => compare(one, best) > 0 ? one : best)

let run = (root, command, commandArgs) => Node.output(~cwd=root, command, commandArgs)

type held = Map.t<string, Map.t<string, Set.t<string>>>

let byName = (a, b) => String.compare(a, b)
let sorted = (values: array<string>) => values->Array.toSorted(byName)
let keys = map => map->Map.keys->Iterator.toArray
let byVersion = (map: Map.t<string, Set.t<string>>) => map->keys->Array.toSorted(order)

/** Package name -> version -> the repository's packages that hold it directly. */
let held = root => {
  let versions: held = Map.make()
  let listed = run(root, "pnpm", ["list", "-r", "--depth", "0", "--json"])
  let projects = switch JSON.parseOrThrow(listed == "" ? "[]" : listed) {
  | Array(projects) => projects
  | _ => []
  }
  projects->Array.forEach(project =>
    switch project {
    | Object(project) =>
      let who = switch project->Dict.get("name") {
      | Some(String(name)) => name
      | _ => "?"
      }
      ["dependencies", "devDependencies", "optionalDependencies"]->Array.forEach(group =>
        switch project->Dict.get(group) {
        | Some(Object(entries)) =>
          entries
          ->Dict.toArray
          ->Array.forEach(((name, info)) => {
            let version = switch info {
            | Object(info) =>
              switch info->Dict.get("version") {
              | Some(String(version)) => version
              | _ => ""
              }
            | _ => ""
            }
            if version != "" && !(local->RegExp.test(version)) {
              let found = versions->Map.get(name)->Option.getOr(Map.make())
              versions->Map.set(name, found)
              let holders = found->Map.get(version)->Option.getOr(Set.make())
              found->Map.set(version, holders)
              holders->Set.add(who)
            }
          })
        | _ => ()
        }
      )
    | _ => ()
    }
  )
  versions
}

type outdated = {current: string, latest: string, dependents: array<string>}

/** `pnpm outdated`'s answer, by package. */
let outdatedOf = root => {
  let answer = run(root, "pnpm", ["outdated", "-r", "--format", "json"])
  switch JSON.parseOrThrow(answer == "" ? "{}" : answer) {
  | Object(entries) =>
    entries
    ->Dict.toArray
    ->Array.filterMap(((name, entry)) =>
      switch entry {
      | Object(entry) =>
        let text = field =>
          switch entry->Dict.get(field) {
          | Some(String(value)) => value
          | _ => ""
          }
        let dependents = switch entry->Dict.get("dependentPackages") {
        | Some(Array(packages)) =>
          packages->Array.filterMap(one =>
            switch one {
            | Object(one) =>
              switch one->Dict.get("name") {
              | Some(String(name)) => Some(name)
              | _ => None
              }
            | _ => None
            }
          )
        | _ => []
        }
        Some((name, {current: text("current"), latest: text("latest"), dependents}))
      | _ => None
      }
    )
    ->Map.fromArray
  | _ => Map.make()
  }
}

/** The report, as lines, or with `names` only the names `update --major` should move. */
let report = (root: string, names: bool): array<string> => {
  let versions = held(root)
  let path = Node.join([root, "versions.toml"])
  let several = allowed(Node.existsSync(path) ? Node.readFileSync(path) : "")
  let outdated = outdatedOf(root)
  let behind = []
  let split = []
  outdated
  ->keys
  ->sorted
  ->Array.forEach(name => {
    let entry = outdated->Map.get(name)->Option.getOrThrow
    let present =
      versions
      ->Map.get(name)
      ->Option.getOr(Map.fromArray([(entry.current, Set.fromArray(entry.dependents))]))
    if compare(newest(present->keys), entry.latest) >= 0 {
      split->Array.push((name, present))
    } else {
      let who =
        present
        ->Map.values
        ->Iterator.toArray
        ->Array.flatMap(one => one->Set.values->Iterator.toArray)
        ->Set.fromArray
        ->Set.values
        ->Iterator.toArray
        ->sorted
      behind->Array.push((name, present->byVersion->Array.join(", "), entry.latest, who))
    }
  })
  // A package at two majors that nothing calls out of date: every copy is on its own latest line.
  versions
  ->keys
  ->sorted
  ->Array.forEach(name => {
    let present = versions->Map.get(name)->Option.getOrThrow
    if !(outdated->Map.has(name)) && present->keys->Array.map(major)->Set.fromArray->Set.size > 1 {
      split->Array.push((name, present))
    }
  })
  if names {
    behind->Array.filterMap(((name, _, _, _)) => several->Map.has(name) ? None : Some(name))
  } else {
    let lines = []
    if behind->Array.length > 0 {
      lines->Array.pushMany([
        "Out of date -- the newest the workspace holds is behind the registry:",
        "",
      ])
      let width = behind->Array.reduce(0, (widest, (name, _, _, _)) =>
        Math.Int.max(widest, name->String.length)
      )
      behind->Array.forEach(((name, have, latest, who)) =>
        lines->Array.push(
          `  ${name->String.padEnd(width, " ")}  ${have} -> ${latest}   (${who->Array.join(", ")})`,
        )
      )
    } else {
      lines->Array.push(
        "Nothing is out of date: every package's newest copy here is the registry's latest.",
      )
    }
    let warned = ref(0)
    split->Array.forEach(((name, present)) => {
      let copies =
        present
        ->byVersion
        ->Array.map(one =>
          `${one} in ${present
            ->Map.get(one)
            ->Option.mapOr([], holders => holders->Set.values->Iterator.toArray)
            ->sorted
            ->Array.join(", ")}`
        )
      switch several->Map.get(name) {
      | Some(why) =>
        lines->Array.pushMany([
          "",
          `allowed at several majors: ${name}\n    ${copies->Array.join("\n    ")}\n    because ${why}`,
        ])
      | None =>
        warned := warned.contents + 1
        lines->Array.pushMany([
          "",
          `warning: ${name} is held at several majors\n    ${copies->Array.join("\n    ")}`,
        ])
      }
    })
    if warned.contents > 0 {
      lines->Array.pushMany([
        "",
        "Move every copy to one major, or allow the pair in versions.toml with the reason.",
      ])
    }
    let splitNames = split->Array.map(((name, _)) => name)->Set.fromArray
    several
    ->keys
    ->sorted
    ->Array.forEach(name =>
      if !(splitNames->Set.has(name)) {
        lines->Array.pushMany([
          "",
          `versions.toml allows ${name} at several majors, and the workspace holds one: drop the line.`,
        ])
      }
    )
    lines
  }
}

/** The task: `outdated [--names]`, from the repository's root. */
let main = (~root=Node.cwd(), ~args=Node.args()) => {
  let names = args->Array.includes("--names") || Node.envIs("usage_names", "true")
  let lines = report(root, names)
  if lines->Array.length > 0 {
    Console.log(lines->Array.join("\n"))
  }
}

if Node.isMain {
  main()
}
