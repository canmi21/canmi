/**
 * Who holds the advisor's seat, docs/agents/advisor.md, "One holder". It guards against a slip and
 * not an impostor, as a pid and a name are all it knows.
 */
type holder = {name: string, pid: int, since: string, handingTo: option<string>}

type standing = First | Holding(holder) | Candidate(holder) | Orphan(holder)

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
    | (Some(name), Some(pid)) =>
      Some({
        name,
        pid: Float.toInt(pid),
        since: Ledger.textOf(fields, "since"),
        handingTo: fields->Payload.text("handingTo"),
      })
    | _ => None
    }
  )

let read = () => Node.existsSync(currentFile()) ? parse(Node.readFileSync(currentFile())) : None

let write = (holder: holder) => {
  Node.mkdirAll(home())
  Node.writeFileSync(
    currentFile(),
    Ledger.line(
      [
        ("name", JSON.String(holder.name)),
        ("pid", JSON.Number(holder.pid->Int.toFloat)),
        ("since", JSON.String(holder.since)),
        ...holder.handingTo->Option.mapOr([], name => [("handingTo", JSON.String(name))]),
      ],
    ),
  )
}

/** Which of the cases a session stands in, from the record, its own pid and who lives. */
let standingOf = (record, ~pid, ~alive) =>
  switch record {
  | None => First
  | Some(holder) if holder.pid == pid => Holding(holder)
  | Some(holder) if alive(holder.pid) => Candidate(holder)
  | Some(holder) => Orphan(holder)
  }

/** Whether an order from `sender` may be acted on, or why not. */
let orderFrom = (record, ~sender) =>
  switch record {
  | None => Error(`no advisor holds the seat, so ${sender}'s order is not acted on`)
  | Some(holder) if holder.name == sender => Ok()
  | Some(holder) => Error(`${holder.name} holds the seat, so ${sender}'s order is not acted on`)
  }

let said = standing =>
  switch standing {
  | First => "first: no record. You are the first advisor; say so to the author and claim the seat."
  | Holding(holder) => `holder: you hold the seat as ${holder.name}, since ${holder.since}.`
  | Candidate(holder) =>
    `candidate: ${holder.name} holds the seat and lives. Read only, direct nothing, and contact it to begin.`
  | Orphan(holder) =>
    `orphan: ${holder.name} held the seat and its process is gone. Read ${handoverFile()}, tell the author what you found, and claim only on the author's word.`
  }

let ownPid = () =>
  Node.env->Dict.get("CLAUDE_PID")->Option.flatMap(text => Int.fromString(text))->Option.getOr(0)

let now = () => Date.make()->Date.toISOString

let claim = (name, ~pid, ~authorSaid) =>
  switch standingOf(read(), ~pid, ~alive=Watchdog.alive) {
  | Candidate(holder) =>
    Console.error(`${holder.name} holds the seat and lives, so it passes it; nothing changed`)
    1
  | Orphan(holder) if !authorSaid =>
    Console.error(`${holder.name}'s seat is taken only on the author's word: --author-said`)
    1
  | _ =>
    write({name, pid, since: now(), handingTo: None})
    Console.log(`${name} holds the seat`)
    0
  }

/** The one point of a switch, the holder alone changing the file. */
let pass = (name, ~to, ~pid) =>
  switch standingOf(read(), ~pid, ~alive=Watchdog.alive) {
  | Holding(_) =>
    write({name, pid: to, since: now(), handingTo: None})
    Console.log(`${name} holds the seat; tell the supervisor and the author the new name`)
    0
  | _ =>
    Console.error("only the holder passes the seat; nothing changed")
    1
  }

let handing = (name, ~pid) =>
  switch standingOf(read(), ~pid, ~alive=Watchdog.alive) {
  | Holding(holder) =>
    write({...holder, handingTo: Some(name)})
    Console.log(`handing to ${name}; everything still comes here until the switch`)
    0
  | _ =>
    Console.error("only the holder names a successor; nothing changed")
    1
  }

let main = (argv: array<string>) =>
  switch argv {
  | ["case"] =>
    Console.log(said(standingOf(read(), ~pid=ownPid(), ~alive=Watchdog.alive)))
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
