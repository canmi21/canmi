/**
 * `friction [--in <directory>]` sums the records of friction by rule id, docs/agents/friction.md.
 * A record is one file named for its date and its rule's id.
 */
type record = {date: string, rule: string}

let datePattern = /^(\d{4}-\d{2}-\d{2})-(.+)\.md$/
let counted = /^(.+)-\d+$/

/** `~` in a path read as the home directory. */
let expand = path =>
  path->String.startsWith("~/")
    ? Node.join([Node.env->Dict.get("HOME")->Option.getOr(""), path->String.slice(~start=2)])
    : path

/** A file name as a record of one of `known` rules, a counter after the id when a day has two. */
let parse = (file, ~known) =>
  switch datePattern->RegExp.exec(file) {
  | Some(found) =>
    switch found->RegExp.Result.matches {
    | [Some(date), Some(rest)] =>
      let id =
        known->Array.includes(rest)
          ? Some(rest)
          : counted
            ->RegExp.exec(rest)
            ->Option.flatMap(counter =>
              switch counter->RegExp.Result.matches {
              | [Some(id)] if known->Array.includes(id) => Some(id)
              | _ => None
              }
            )
      switch id {
      | Some(rule) if !Float.isNaN(Date.fromString(date)->Date.getTime) => Ok({date, rule})
      | Some(_) => Error(`${file} does not begin with a date`)
      | None => Error(`${file} names no rule of the model`)
      }
    | _ => Error(`${file} is no record`)
    }
  | None => Error(`${file} is not named for its date and a rule's id, yyyy-mm-dd-<rule>.md`)
  }

/** The rules with their records counted and dated, the most frictional first. */
let sum = (records: array<record>) => {
  let rules = records->Array.map(one => one.rule)->Set.fromArray->Set.values->Array.fromIterator
  rules
  ->Array.map(rule => {
    let mine = records->Array.filter(one => one.rule == rule)->Array.map(one => one.date)
    let sorted = mine->Array.toSorted(String.compare)
    (
      rule,
      mine->Array.length,
      sorted->Array.getUnsafe(0),
      sorted->Array.getUnsafe(mine->Array.length - 1),
    )
  })
  ->Array.toSorted(((a, n, _, _), (b, m, _, _)) =>
    n == m ? String.compare(a, b) : Int.toFloat(m - n)
  )
}

let shown = ((rule, count, first, last)) =>
  `${rule}: ${Int.toString(count)} ${count == 1 ? "record" : "records"}, ${first == last
      ? first
      : `${first} to ${last}`}`

let known = () => Rules.all->Array.map(rule => rule.name)

/** The record files of `directory`, none where it is not there. */
let files = directory => Node.existsSync(directory) ? Node.readdir(directory) : []

/** The `friction` part, a file that is no record warned of. */
let problems = (~directory) =>
  files(directory)->Array.filterMap(file =>
    switch parse(file, ~known=known()) {
    | Ok(_) => None
    | Error(why) => Some(`${expand(Delegation.friction)}: ${why}`)
    }
  )

let main = (argv: array<string>): int => {
  let directory = switch argv->Array.findIndex(arg => arg == "--in") {
  | -1 => expand(Delegation.friction)
  | at => argv[at + 1]->Option.getOr(expand(Delegation.friction))
  }
  let parsed = files(directory)->Array.map(file => parse(file, ~known=known()))
  let records = parsed->Array.filterMap(one =>
    switch one {
    | Ok(record) => Some(record)
    | Error(_) => None
    }
  )
  parsed->Array.forEach(one =>
    switch one {
    | Error(why) => Console.error(why)
    | Ok(_) => ()
    }
  )
  if records == [] {
    Console.log("no friction recorded")
  } else {
    sum(records)->Array.forEach(one => Console.log(shown(one)))
    Console.log(`${Int.toString(records->Array.length)} records`)
  }
  0
}

if Node.isMain {
  Node.exit(main(Node.args()))
}
