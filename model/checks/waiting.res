/** The deferred items, model/plan/deferred.res, against what they name, and what each waives. */
open Deferred

/** The parts whose findings name the rule they break, so a rule of theirs can be waived. */
let waivable = ["shape"]

let finished = ["landed", "declined"]

/** The id space an item's RFC is in, the first its repositories declare, else the workspace's. */
let spaceOf = (item: item) =>
  item.repos->Array.findMap(Rfc_spaces.spaceOf)->Option.getOr(Planning.workspaceSpace)

/** Each item's statuses by id, those of its RFC's space, each space read once. */
let statuses = (): (item => Dict.t<string>) => {
  let spaces = Dict.make()
  item => {
    let space = spaceOf(item)
    switch spaces->Dict.get(space) {
    | Some(found) => found
    | None =>
      let found = Dict.make()
      Rfc_spaces.read(space).files->Array.forEach(file =>
        switch Node.readFileSync(file.path)->String.match(/\nstatus:\s*(\w+)/) {
        | Some([_, Some(status)]) => found->Dict.set(file.id, status)
        | _ => ()
        }
      )
      spaces->Dict.set(space, found)
      found
    }
  }
}

/** Whatever an item names that is not there, each one line. */
let problemsIn = (
  items: array<item>,
  ~repos: array<string>,
  ~rules: array<Rule.t>,
  ~statuses: item => Dict.t<string>,
): array<string> => {
  let found = []
  let seen = []
  items->Array.forEach(item => {
    let at = `deferred ${item.id}`
    if !(/^[a-z0-9]+(-[a-z0-9]+)*$/->RegExp.test(item.id)) {
      found->Array.push(`${at}: its id is not lowercase words joined by hyphens`)
    }
    if seen->Array.includes(item.id) {
      found->Array.push(`${at}: its id is taken by another item`)
    }
    seen->Array.push(item.id)
    if item.repos == [] {
      found->Array.push(`${at}: names no repository`)
    }
    item.repos->Array.forEach(repo =>
      if repo != "workspace" && !(repos->Array.includes(repo)) {
        found->Array.push(`${at}: ${repo} is not in repos/registry.toml`)
      }
    )
    item.waives
    ->Option.getOr([])
    ->Array.forEach(name =>
      switch rules->Array.find(rule => rule.name == name) {
      | None => found->Array.push(`${at}: waives ${name}, which is no rule`)
      | Some({held: Check(part)}) if waivable->Array.includes(part) => ()
      | Some(_) =>
        found->Array.push(
          `${at}: waives ${name}, held by no part that can waive: ${waivable->Array.join(", ")}`,
        )
      }
    )
    switch item.until {
    | Closes(id) if statuses(item)->Dict.get(id)->Option.isNone =>
      found->Array.push(`${at}: waits on ${id}, which is no RFC`)
    | _ => ()
    }
  })
  found
}

let problems = () =>
  problemsIn(items, ~repos=Registry.paths(), ~rules=Rules.all, ~statuses=statuses())

/** The item that waives `rule` over `repo`, if one does. */
let waiverIn = (items: array<item>, ~repo, ~rule) =>
  items
  ->Array.find(item =>
    item.repos->Array.includes(repo) && item.waives->Option.getOr([])->Array.includes(rule)
  )
  ->Option.map(item => item.id)

let waiver = (~repo, ~rule) => waiverIn(items, ~repo, ~rule)

/** The item that pauses `repo`, if one does. */
let pauserIn = (items: array<item>, ~repo) =>
  items
  ->Array.find(item => item.repos->Array.includes(repo) && item.pauses->Option.getOr(false))
  ->Option.map(item => item.id)

let pauser = (~repo) => pauserIn(items, ~repo)

/** The registry's repositories that no item pauses, the ones a scan across them reads. */
let active = () => Registry.paths()->Array.filter(path => pauser(~repo=path)->Option.isNone)

let red = text => Node.envOn("NO_COLOR") ? text : `\u001b[31m${text}\u001b[0m`

/** Each item, or those naming `repo`, one line each, the due first. */
let shown = (~repo: option<string>) => {
  let known = statuses()
  let due = item =>
    switch item.until {
    | Closes(id) => known(item)->Dict.get(id)->Option.mapOr(false, s => finished->Array.includes(s))
    | Author => false
    }
  items
  ->Array.filter(item => repo->Option.mapOr(true, name => item.repos->Array.includes(name)))
  ->Array.toSorted((a, b) => (due(a) ? 0. : 1.) -. (due(b) ? 0. : 1.))
  ->Array.map(item => {
    let until = switch item.until {
    | Closes(id) => `until ${id} lands`
    | Author => "until the author says"
    }
    let waives = switch item.waives {
    | Some(names) => `; waives ${names->Array.join(", ")}`
    | None => ""
    }
    let waives = item.pauses->Option.getOr(false) ? `${waives}; paused` : waives
    red(
      `deferred ${item.id}${due(item) ? " (due)" : ""}: ${item.what} -- ${item.repos->Array.join(
          ", ",
        )}; ${until}${waives}`,
    )
  })
}
