/**
 * A repository's own plan, `model/plan.json` or `model/plan/plan.json`, and the total that joins
 * every repository's. RFC 8q1af. It is plain JSON because a repository's model cannot import the
 * workspace's, and any language reads it. A repository declares only what it depends on and
 * exports, in its workspace.toml's `[boundary]`, and proves only that; the total alone sees them
 * all.
 */
open Work

exception Bad(string)
let bad = why => throw(Bad(why))

let file = "model/plan.json"

/** Where a repository keeps its plan, `file` or, where model/ is full, `model/plan/plan.json`. */
let fileAt = root => {
  let nested = "model/plan/plan.json"
  !Node.existsSync(Node.join([root, file])) && Node.existsSync(Node.join([root, nested]))
    ? nested
    : file
}

/** One plan with the boundary its repository declares, its owner `workspace` or a registry path. */
type source = {
  owner: string,
  file: string,
  isPrivate: bool,
  text: string,
  items: array<item>,
  boundary: Project.boundary,
}

/** An item of the joined graph, its id the key `<repository>:<id>`, bare for the workspace's. */
type entry = {owner: string, isPrivate: bool, item: item}

let key = (~owner, id) => owner == "workspace" ? id : `${owner}:${id}`

/** The repository and the name of a `repository:name` reference. */
let split = reference =>
  switch reference->String.lastIndexOf(":") {
  | -1 => ("", reference)
  | at => (reference->String.slice(~start=0, ~end=at), reference->String.slice(~start=at + 1))
  }

/** An item's id as shown, always with its repository. */
let label = id => id->String.includes(":") ? id : `workspace:${id}`

let itemKeys = ["id", "says", "repos", "after", "holds", "why", "waits", "needs", "delivers"]

let text = (table: dict<JSON.t>, name, ~at) =>
  switch table->Dict.get(name) {
  | Some(String(found)) => found
  | _ => bad(`${at}: ${name} is no text`)
  }

let texts = (table: dict<JSON.t>, name, ~at): option<array<string>> =>
  switch table->Dict.get(name) {
  | None => None
  | Some(Array(list)) =>
    Some(
      list->Array.map(one =>
        switch one {
        | String(found) => found
        | _ => bad(`${at}: ${name} holds a value that is no text`)
        }
      ),
    )
  | Some(_) => bad(`${at}: ${name} is no list`)
  }

let holdsOf = (table: dict<JSON.t>, ~owner, ~at): holds =>
  switch table->Dict.get("holds") {
  | Some(Object(held)) =>
    switch held->Dict.toArray {
    | [("owes", String(needs))] => Owes(needs)
    | [("landing", String(part))] => Landing(part)
    | [("holds", String(part))] => Holds(part)
    | [("committed", Object(commit))] =>
      Committed({
        repo: switch commit->Dict.get("repo") {
        | Some(String(repo)) => repo
        | _ => owner
        },
        commit: text(commit, "commit", ~at),
      })
    | [("observed", Object(seen))] =>
      Observed({at: text(seen, "at", ~at), what: text(seen, "what", ~at)})
    | _ => bad(`${at}: holds is not one of owes, landing, holds, committed, observed`)
    }
  | _ => bad(`${at}: holds is missing`)
  }

let waitsOf = (table: dict<JSON.t>, ~at): option<until> =>
  switch table->Dict.get("waits") {
  | None => None
  | Some(String("author")) => Some(Author)
  | Some(Object(waiting)) => Some(Closes(text(waiting, "closes", ~at)))
  | Some(_) => bad(`${at}: waits is not "author" or {"closes": id}`)
  }

/** The items of a repository's plan, ids as written. */
let parse = (json: string, ~owner): result<array<item>, string> =>
  try {
    let top = switch JSON.parseOrThrow(json) {
    | Object(top) => top
    | _ => bad("the plan is no object")
    }
    top
    ->Dict.keysToArray
    ->Array.forEach(name =>
      if name != "items" {
        bad(`${name} is no key of a plan`)
      }
    )
    let list = switch top->Dict.get("items") {
    | Some(Array(list)) => list
    | _ => bad("items is no list")
    }
    Ok(
      list->Array.mapWithIndex((one, index) => {
        let table = switch one {
        | Object(table) => table
        | _ => bad(`item ${Int.toString(index)} is no object`)
        }
        let id = text(table, "id", ~at=`item ${Int.toString(index)}`)
        table
        ->Dict.keysToArray
        ->Array.forEach(name =>
          if !(itemKeys->Array.includes(name)) {
            bad(`${id}: ${name} is no key of an item`)
          }
        )
        let after = texts(table, "after", ~at=id)->Option.getOr([])
        after->Array.forEach(named =>
          if named->String.includes(":") {
            bad(
              `${id}: after names ${named}, another repository's, where only its own items belong`,
            )
          }
        )
        {
          id,
          says: text(table, "says", ~at=id),
          repos: texts(table, "repos", ~at=id)->Option.getOr([owner]),
          after,
          holds: holdsOf(table, ~owner, ~at=id),
          why: ?switch table->Dict.get("why") {
          | None => None
          | Some(_) => Some(text(table, "why", ~at=id))
          },
          waits: ?waitsOf(table, ~at=id),
          needs: ?texts(table, "needs", ~at=id),
          delivers: ?texts(table, "delivers", ~at=id),
        }
      }),
    )
  } catch {
  | Bad(why) => Error(why)
  | JsExn(_) => Error("the plan is not JSON")
  }

/** The workspace's own plan, which declares no boundary. */
let workspace = (): source => {
  owner: "workspace",
  file: "model/plan/work.res",
  isPrivate: false,
  text: "",
  items: Work.items,
  boundary: {exports: [], depends: []},
}

/** Every cloned, unpaused repository that declares itself, and the plans that cannot be read. */
let load = (): (array<source>, array<string>) => {
  let errors = []
  let found = Waiting.active()->Array.filterMap(path => {
    let root = Node.join([Registry.repos, path])
    let file = fileAt(root)
    let at = Node.join([root, file])
    let planned = Node.existsSync(at)
    if !Node.existsSync(Node.join([root, "workspace.toml"])) {
      if planned {
        errors->Array.push(`plan ${path}: ${file} without a workspace.toml`)
      }
      None
    } else {
      switch Project.read(root) {
      | Error(why) =>
        if planned {
          errors->Array.push(`plan ${path}: ${why}`)
        }
        None
      | Ok(declared) =>
        let json = planned ? Node.readFileSync(at) : ""
        let isPrivate = declared.push.visibility != "public"
        if !planned {
          Some({owner: path, file, isPrivate, text: json, items: [], boundary: declared.boundary})
        } else {
          switch parse(json, ~owner=path) {
          | Ok(items) =>
            Some({owner: path, file, isPrivate, text: json, items, boundary: declared.boundary})
          | Error(why) =>
            errors->Array.push(`plan ${path}: ${file}: ${why}`)
            None
          }
        }
      }
    }
  })
  (Array.concat([workspace()], found), errors)
}

/** The items of `owner` that deliver `name`, none where it is not a source. */
let deliverers = (sources: array<source>, ~owner, ~name) =>
  sources
  ->Array.find(source => source.owner == owner)
  ->Option.mapOr([], source =>
    source.items->Array.filter(item => item.delivers->Option.getOr([])->Array.includes(name))
  )

/**
 * Every item of every plan, ids made keys. An item waits on what it needs: the items that deliver
 * it, or the name itself where its exporter is not read, which nothing delivers.
 */
let merge = (sources: array<source>): array<entry> =>
  sources->Array.flatMap(({owner, isPrivate, items}) =>
    items->Array.map(item => {
      owner,
      isPrivate,
      item: {
        ...item,
        id: key(~owner, item.id),
        after: Array.concat(
          item.after->Array.map(named => key(~owner, named)),
          item.needs
          ->Option.getOr([])
          ->Array.flatMap(
            need => {
              let (exporter, name) = split(need)
              switch sources->Array.find(other => other.owner == exporter) {
              | Some(_) =>
                deliverers(sources, ~owner=exporter, ~name)->Array.map(
                  one => key(~owner=exporter, one.id),
                )
              | None => [need]
              }
            },
          ),
        ),
      },
    })
  )

/** The dependencies of the repositories that are passed over, each with why, said by the plan. */
let passedOver = (sources: array<source>, ~skipped: string => option<string>): array<string> => {
  let said = []
  sources->Array.forEach(source =>
    source.boundary.depends->Array.forEach(dependency => {
      let (named, _) = split(dependency)
      switch skipped(named) {
      | Some(why) =>
        let line = `plan ${source.owner}: depends on ${dependency} not joined, ${named} ${why}`
        if !(said->Array.includes(line)) {
          said->Array.push(line)
        }
      | None => ()
      }
    })
  )
  said
}

/** A line of a public plan that holds a private identifier, by its number alone. */
let leaks = (source: source, ~listed): array<string> =>
  switch (source.isPrivate || source.owner == "workspace", listed) {
  | (false, Some(patterns)) =>
    source.text
    ->String.split("\n")
    ->Array.mapWithIndex((line, index) => (Scan.found(line, patterns), index + 1))
    ->Array.filterMap(((hits, number)) =>
      hits == []
        ? None
        : Some(
            `plan ${source.owner}: ${source.file}:${Int.toString(
                number,
              )}: a public plan holds a private identifier`,
          )
    )
  | _ => []
  }

/**
 * What one repository's own files show, and nothing of any other: its needs within its depends,
 * its deliveries within its exports, and its own graph. A workspace's is `Plan.problemsIn`.
 */
let ownProblems = (
  source: source,
  ~repos: array<string>,
  ~rules: array<Rule.t>,
  ~has: string => bool,
  ~passes: string => option<bool>,
  ~rfc: (item, string) => bool,
  ~committed: (string, string) => option<bool>,
  ~listed,
): array<string> => {
  let found = Plan.problemsIn(source.items, ~repos, ~rules, ~has, ~passes, ~rfc, ~committed)
  source.items->Array.forEach(item => {
    let say = why => found->Array.push(`plan ${item.id}: ${why}`)
    item.needs
    ->Option.getOr([])
    ->Array.forEach(need =>
      if !(source.boundary.depends->Array.includes(need)) {
        say(`needs ${need}, which is not in [boundary] depends`)
      }
    )
    item.delivers
    ->Option.getOr([])
    ->Array.forEach(name =>
      if !(source.boundary.exports->Array.includes(name)) {
        say(`delivers ${name}, which is not in [boundary] exports`)
      }
    )
  })
  Array.concat(found, leaks(source, ~listed))->Array.map(line => `${source.owner}: ${line}`)
}

/** What the joined plans show that no repository's own files do. */
let joinProblems = (
  sources: array<source>,
  ~repos: array<string>,
  ~skipped: string => option<string>,
): array<string> => {
  let found = []
  sources->Array.forEach(source =>
    source.boundary.depends->Array.forEach(dependency => {
      let (named, name) = split(dependency)
      let say = why => found->Array.push(`plan ${source.owner}: depends on ${dependency}, ${why}`)
      if !(repos->Array.includes(named)) {
        say(`${named} is not in repos/registry.toml`)
      } else {
        switch sources->Array.find(other => other.owner == named) {
        | Some(exporter) =>
          if !(exporter.boundary.exports->Array.includes(name)) {
            say(`which ${named} does not export`)
          }
        | None =>
          if skipped(named)->Option.isNone {
            say(`${named} declares no workspace.toml to export it`)
          }
        }
      }
    })
  )
  let merged = merge(sources)
  let items = merged->Array.map(({item}) => item)
  merged->Array.forEach(({owner, item}) =>
    Plan.reached(items, item)->Array.forEach(id =>
      switch merged->Array.find(other => other.item.id == id) {
      | Some({owner: other, item: back})
        if other != owner && item.id < id && Plan.reached(items, back)->Array.includes(item.id) =>
        found->Array.push(
          `plan ${label(item.id)}: is after itself through ${label(id)}, across repositories`,
        )
      | _ => ()
      }
    )
  )
  found
}

/** The patterns of the private identifiers, none where the machine's list cannot be read. */
let patterns = () => Scan.identifiers()->Option.map(Scan.patterns)

/** One repository's own findings from its files alone, as its own check reads them. */
let ownAt = (~root): array<string> => {
  let path = Registry.label(root)
  let file = fileAt(root)
  let at = Node.join([root, file])
  if !Node.existsSync(at) {
    []
  } else {
    switch Project.read(root) {
    | Error(why) => [why]
    | Ok(declared) =>
      let json = Node.readFileSync(at)
      switch parse(json, ~owner=path) {
      | Error(why) => [`${file}: ${why}`]
      | Ok(items) =>
        ownProblems(
          {
            owner: path,
            file,
            isPrivate: declared.push.visibility != "public",
            text: json,
            items,
            boundary: declared.boundary,
          },
          ~repos=Registry.paths(),
          ~rules=Rules.all,
          ~has=_ => false,
          ~passes=_ => None,
          ~rfc=(_, _) => true,
          ~committed=(_, _) => None,
          ~listed=patterns(),
        )
      }
    }
  }
}

/** The total over every cloned repository, as `Plan.problemsIn` is over the workspace's. */
let found = (~repos, ~rules, ~has, ~passes, ~rfc, ~committed) => {
  let (sources, errors) = load()
  let listed = patterns()
  Array.flat([
    errors,
    sources
    ->Array.filter(source => source.owner != "workspace")
    ->Array.flatMap(source =>
      ownProblems(source, ~repos, ~rules, ~has, ~passes, ~rfc, ~committed, ~listed)
    ),
    joinProblems(sources, ~repos, ~skipped=Waiting.skipped),
  ])
}

/**
 * Whether the check's output can leave this machine, which a CI log does and a terminal does not.
 * A private repository's waiting item is then named by id and repository alone.
 */
let leaves = () => Node.envOn("CI")

/** The waiting items of the repositories' plans in red, those naming `repo` where one is given. */
let waitingIn = (
  sources: array<source>,
  ~repo: option<string>,
  ~hidden: bool,
  ~due: item => bool,
): array<string> =>
  sources
  ->Array.filter(source => source.owner != "workspace")
  ->Array.flatMap(source =>
    source.items
    ->Array.filter(item => item.waits->Option.isSome)
    ->Array.filter(item => repo->Option.mapOr(true, name => item.repos->Array.includes(name)))
    ->Array.map(item => (source, item))
  )
  ->Array.toSorted(((_, a), (_, b)) => (due(a) ? 0. : 1.) -. (due(b) ? 0. : 1.))
  ->Array.map(((source, item)) => {
    let id = label(key(~owner=source.owner, item.id))
    if hidden && source.isPrivate {
      Waiting.red(`deferred ${id}: private, withheld -- ${source.owner}`)
    } else {
      let until = switch item.waits {
      | Some(Closes(rfc)) => `until ${rfc} lands`
      | Some(Author) | None => "until the author says"
      }
      Waiting.red(
        `deferred ${id}${due(item) ? " (due)" : ""}: ${item.says} -- ${item.repos->Array.join(
            ", ",
          )}; ${until}`,
      )
    }
  })

let waiting = (~repo: option<string>) => {
  let (sources, _) = load()
  let known = Waiting.statuses()
  waitingIn(sources, ~repo, ~hidden=leaves(), ~due=item =>
    switch item.waits {
    | Some(Closes(id)) =>
      known(item)->Dict.get(id)->Option.mapOr(false, s => Waiting.finished->Array.includes(s))
    | _ => false
    }
  )
}
