/** The plan, model/plan/work.res, against what it names, and where each item stands. RFC 8q1af. */
open Work

type state =
  | Done
  | Under
  | Ready
  | Behind(array<string>)
  | Awaits(until)

let dated = /^\d{4}-\d{2}-\d{2}$/
let hash = /^[0-9a-f]{7,40}$/

/** Why a scan passes over a repository, none for the workspace itself. */
let skip = repo => repo == "workspace" ? None : Waiting.skipped(repo)

/** Whether a commit is on a repository's main, none where the repository is passed over. */
let onMain = (repo, commit): option<bool> =>
  switch skip(repo) {
  | Some(_) => None
  | None =>
    let root = repo == "workspace" ? Registry.root : Node.join([Registry.repos, repo])
    Some(
      Onset.read(
        ~root,
        [
          "--ignore-working-copy",
          "log",
          "--no-graph",
          "-r",
          `${commit} & ::main`,
          "-T",
          `commit_id ++ "\\n"`,
        ],
      )->Option.mapOr(false, text => text != ""),
    )
  }

/** Whether an item is done, a commit counted done where its repository is passed over. */
let isDone = (item: item, ~committed: (string, string) => option<bool>) =>
  switch item.holds {
  | Holds(_) | Observed(_) => true
  | Committed({repo, commit}) => committed(repo, commit)->Option.getOr(true)
  | Owes(_) | Landing(_) => false
  }

/** Where an item stands, derived from what it names and what is done before it. */
let stateOf = (items: array<item>, item: item, ~committed): state =>
  switch item.holds {
  | Landing(_) => Under
  | _ if isDone(item, ~committed) => Done
  | _ =>
    let undone = item.after->Array.filter(id =>
      items->Array.find(other => other.id == id)->Option.mapOr(true, other =>
        !isDone(other, ~committed)
      )
    )
    switch (undone, item.waits) {
    | ([], None) => Ready
    | ([], Some(until)) => Awaits(until)
    | (undone, _) => Behind(undone)
    }
  }

/** The items an item's `after` reaches, directly and through each other. */
let reached = (items: array<item>, item: item) => {
  let found = []
  let rec walk = ids =>
    ids->Array.forEach(id =>
      if !(found->Array.includes(id)) {
        found->Array.push(id)
        items->Array.find(other => other.id == id)->Option.forEach(other => walk(other.after))
      }
    )
  walk(item.after)
  found
}

/** The pending rules, which the plan lists as ready by name and never as items. */
let pendingRules = (rules: array<Rule.t>) =>
  rules->Array.filterMap(rule =>
    switch rule.held {
    | Pending(owed) => Some((rule.name, owed))
    | _ => None
    }
  )

/** Whatever the plan names that is not there, each one line. */
let problemsIn = (
  items: array<item>,
  ~repos: array<string>,
  ~rules: array<Rule.t>,
  ~has: string => bool,
  ~passes: string => option<bool>,
  ~rfc: (item, string) => bool,
  ~committed: (string, string) => option<bool>,
): array<string> => {
  let found = []
  let seen = []
  let registered = repo => repo == "workspace" || repos->Array.includes(repo)
  items->Array.forEach(item => {
    let say = text => found->Array.push(`plan ${item.id}: ${text}`)
    if !(/^[a-z0-9]+(-[a-z0-9]+)*$/->RegExp.test(item.id)) {
      say("its id is not lowercase words joined by hyphens")
    }
    if seen->Array.includes(item.id) {
      say("its id is taken by another item")
    }
    seen->Array.push(item.id)
    let pending = pendingRules(rules)->Array.some(((name, _)) => name == item.id)
    if pending {
      say("is a pending rule, which stays in model/rules and is listed here by name")
    }
    if item.repos == [] {
      say("names no repository")
    }
    item.repos->Array.forEach(repo =>
      if !registered(repo) {
        say(`${repo} is not in repos/registry.toml`)
      }
    )
    item.after->Array.forEach(id =>
      if id == item.id {
        say("is after itself")
      } else if !(items->Array.some(other => other.id == id)) {
        say(`is after ${id}, which is no item`)
      }
    )
    if reached(items, item)->Array.includes(item.id) && !(item.after->Array.includes(item.id)) {
      say("is after itself through the items it follows")
    }
    switch item.why {
    | Some(id) if !rfc(item, id) => say(`names ${id}, which is no RFC`)
    | _ => ()
    }
    switch item.holds {
    | Owes(needs) if needs->String.trim == "" => say("owes nothing it names")
    | Owes(_) => ()
    | Landing(name) | Holds(name) =>
      if !has(name) {
        say(`names the part ${name}, which the check does not have`)
      } else {
        switch (item.holds, passes(name)) {
        | (Landing(_), Some(true)) => say(`lands ${name}, which passes; move it to Holds`)
        | _ => ()
        }
      }
    | Committed({repo, commit}) =>
      if !registered(repo) {
        say(`names a commit in ${repo}, which is not in repos/registry.toml`)
      } else if !(hash->RegExp.test(commit)) {
        say(`names ${commit}, which is no commit hash`)
      } else if committed(repo, commit) == Some(false) {
        say(`names ${commit}, which is not on the main of ${repo}`)
      }
    | Observed({at, what}) =>
      if !(dated->RegExp.test(at)) {
        say(`is observed on ${at}, which is no date yyyy-mm-dd`)
      }
      if what->String.trim == "" {
        say("is observed with nothing said")
      }
    }
  })
  found
}

/** The commits the plan names in repositories passed over, each with why. */
let passedOver = (items: array<item>): array<string> =>
  items->Array.filterMap(item =>
    switch item.holds {
    | Committed({repo, commit}) =>
      skip(repo)->Option.map(why => `plan ${item.id}: ${commit} in ${repo} not checked, ${why}`)
    | _ => None
    }
  )
