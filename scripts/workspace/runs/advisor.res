/**
 * Who holds the advisor's seat, docs/agents/advisor.md, "One holder". It guards against a slip and
 * not an impostor, as a pid and a name are all it knows.
 */
type holder = {name: string, pid: int, since: string, handingTo: option<string>}

type standing = First | Holding(holder) | Candidate(holder) | Orphan(holder) | Broken | Unknown

@module("node:fs") external rename: (string, string) => unit = "renameSync"
@module("node:fs") external link: (string, string) => unit = "linkSync"
@module("node:fs") external exclusiveDirectory: string => unit = "mkdirSync"

let home = () =>
  switch Node.env->Dict.get("ADVISOR_HOME") {
  | Some(there) if there != "" => there
  | _ => Node.dirname(Friction.expand(Delegation.threads))
  }

let currentFile = () => Node.join([home(), Delegation.advisorCurrent])
let handoverFile = () => Node.join([home(), Delegation.advisorHandover])

let parse = (text: string): option<holder> =>
  Payload.parse(text)->Option.flatMap(fields =>
    switch (fields->Payload.text("name"), Ledger.numberOf(fields, "pid")) {
    | (Some(name), Some(pid))
      if name != "" && pid > 0. && pid <= 2147483647. && Math.floor(pid) == pid =>
      Some({
        name,
        pid: Float.toInt(pid),
        since: Ledger.textOf(fields, "since"),
        handingTo: fields->Payload.text("handingTo"),
      })
    | _ => None
    }
  )

let read = () =>
  try parse(Node.readFileSync(currentFile())) catch {
  | _ => None
  }

let clean = path =>
  try Node.rmSync(path, {recursive: true, force: true}) catch {
  | _ => Console.error(`could not remove advisor temporary path ${path}`)
  }

let write = (holder: holder, ~first=false) => {
  Node.mkdirAll(home())
  let temporary = Node.mkdtempSync(Node.join([home(), ".advisor-"]))
  let staged = Node.join([temporary, "record"])
  try {
    Node.writeFileSync(
      staged,
      Ledger.line(
        [
          ("name", JSON.String(holder.name)),
          ("pid", JSON.Number(holder.pid->Int.toFloat)),
          ("since", JSON.String(holder.since)),
          ...holder.handingTo->Option.mapOr([], name => [("handingTo", JSON.String(name))]),
        ],
      ),
    )
    if first {
      link(staged, currentFile())
    } else {
      rename(staged, currentFile())
    }
  } catch {
  | error =>
    clean(temporary)
    throw(error)
  }
  clean(temporary)
}

/** Which of the cases a session stands in, from the record, its own pid and who lives. */
let standingOf = (record, ~pid, ~alive, ~present=false) =>
  switch record {
  | _ if pid <= 0 => Unknown
  | None if present => Broken
  | None => First
  | Some(holder) if holder.pid == pid => Holding(holder)
  | Some(holder) if alive(holder.pid) => Candidate(holder)
  | Some(holder) => Orphan(holder)
  }

let standing = pid =>
  standingOf(read(), ~pid, ~alive=Watchdog.alive, ~present=Node.existsSync(currentFile()))

/** Whether an order from `sender` may be acted on, or why not. */
let orderFrom = (record, ~sender) =>
  switch record {
  | None => Error(`no advisor holds the seat, so ${sender}'s order is not acted on`)
  | Some(holder) if holder.name == sender => Ok()
  | Some(holder) => Error(`${holder.name} holds the seat, so ${sender}'s order is not acted on`)
  }

let said = standing =>
  switch standing {
  | Unknown => "cannot tell: your session pid is unknown; set CLAUDE_PID to its positive pid."
  | Broken => "broken: the advisor record cannot be read; claim only on the author's word: --author-said."
  | First => "first: no record. You are the first advisor; say so to the author and claim the seat."
  | Holding(holder) => `holder: you hold the seat as ${holder.name}, since ${holder.since}.`
  | Candidate(holder) =>
    `candidate: ${holder.name} holds the seat and lives. Read only, direct nothing, and contact it to begin.`
  | Orphan(holder) =>
    `orphan: ${holder.name} held the seat and its process is gone. Read ${handoverFile()}, tell the author what you found, and claim only on the author's word.`
  }

let ownPid = () =>
  Node.env
  ->Dict.get("CLAUDE_PID")
  ->Option.flatMap(text =>
    /^\d+$/->RegExp.test(text) ? Int.fromString(text)->Option.filter(pid => pid > 0) : None
  )
  ->Option.getOr(0)

let now = () => Date.make()->Date.toISOString

let refused = why => {
  Console.error(`${why}; nothing changed`)
  1
}

/** Every mutation checks and publishes while holding the same exclusive directory. */
let changing = (pid, action) => {
  if pid <= 0 {
    refused("your session pid is unknown, so the seat cannot be changed")
  } else {
    Node.mkdirAll(home())
    let lock = currentFile() ++ ".lock"
    let acquired = try {
      exclusiveDirectory(lock)
      true
    } catch {
    | _ => false
    }
    if !acquired {
      refused("the advisor record is locked, so this mutation cannot proceed")
    } else {
      let result = try action() catch {
      | _ => refused("the advisor record could not be published")
      }
      clean(lock)
      result
    }
  }
}

let claim = (name, ~pid, ~authorSaid) =>
  changing(pid, () =>
    switch standing(pid) {
    | Candidate(holder) =>
      Console.error(`${holder.name} holds the seat and lives, so it passes it; nothing changed`)
      1
    | Orphan(holder) if !authorSaid =>
      Console.error(`${holder.name}'s seat is taken only on the author's word: --author-said`)
      1
    | Broken if !authorSaid => refused("the advisor record is broken; --author-said is required")
    | Unknown => refused("your session pid is unknown")
    | state =>
      write({name, pid, since: now(), handingTo: None}, ~first=state == First)
      Console.log(`${name} holds the seat`)
      0
    }
  )

/** Keep the old registration available for rollback until the new seat is published. */
let switched = (holder: holder, successor: holder) => {
  let registration = Node.join([Ledger.sessions(), `${holder.name}.json`])
  if holder.name == successor.name || !Node.existsSync(registration) {
    write(successor)
  } else {
    let temporary = Node.mkdtempSync(Node.join([Ledger.home(), ".advisor-pass-"]))
    let staged = Node.join([temporary, "registration"])
    try {
      rename(registration, staged)
      write(successor)
    } catch {
    | error =>
      if Node.existsSync(staged) {
        rename(staged, registration)
      }
      clean(temporary)
      throw(error)
    }
    clean(temporary)
  }
}

/** The one point of a switch, the holder alone changing the file. */
let pass = (name, ~to, ~pid) =>
  changing(pid, () =>
    switch standing(pid) {
    | Holding(_) if !Watchdog.alive(to) => refused("the successor pid does not live")
    | Holding(holder) if holder.handingTo->Option.mapOr(false, successor => successor != name) =>
      refused("the successor differs from the one named by handing")
    | Holding(holder) =>
      switched(holder, {name, pid: to, since: now(), handingTo: None})
      Console.log(`${name} holds the seat; tell the supervisor and the author the new name`)
      0
    | _ =>
      Console.error("only the holder passes the seat; nothing changed")
      1
    }
  )

let handing = (name, ~pid) =>
  changing(pid, () =>
    switch standing(pid) {
    | Holding(holder) =>
      write({...holder, handingTo: Some(name)})
      Console.log(`handing to ${name}; everything still comes here until the switch`)
      0
    | _ =>
      Console.error("only the holder names a successor; nothing changed")
      1
    }
  )

let main = (argv: array<string>) =>
  switch argv {
  | ["case"] =>
    Console.log(said(standing(ownPid())))
    Console.log(`your pid: ${Int.toString(ownPid())}`)
    0
  | ["claim", name] => claim(name, ~pid=ownPid(), ~authorSaid=false)
  | ["claim", name, "--author-said"] => claim(name, ~pid=ownPid(), ~authorSaid=true)
  | ["handing", name] => handing(name, ~pid=ownPid())
  | ["pass", name, to] =>
    switch Int.fromString(to) {
    | Some(to) => pass(name, ~to, ~pid=ownPid())
    | None =>
      Console.error(`${to} is no pid`)
      2
    }
  | ["order-from", sender] =>
    switch orderFrom(read(), ~sender) {
    | Ok() =>
      Console.log(`${sender} holds the seat`)
      0
    | Error(why) =>
      Console.error(why)
      1
    }
  | ["where"] =>
    Console.log(currentFile())
    Console.log(handoverFile())
    0
  | _ =>
    Console.error(
      "usage: mise run //:advisor case | where | claim <name> [--author-said] | handing <name> | pass <name> <pid> | order-from <name>",
    )
    2
  }

if Node.isMain {
  Node.exit(main(Node.args()))
}
