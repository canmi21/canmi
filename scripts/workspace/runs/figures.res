/**
 * A thread's figures, which warn and never block, docs/agents/threads.md. They are seat time and
 * landings since a step last went green, and the share of its seat time that is tooling.
 */
type record =
  | Green({step: string, at: float})
  | Seat({name: string, tooling: bool, at: float, session?: string})
  | Seated({name: string, at: float})
  | Landed({repository: string, commit: string, subject: string, at: float})

let root = () =>
  switch Node.env->Dict.get("THREADS_HOME") {
  | Some(there) if there != "" => there
  | _ => Friction.expand(Delegation.threads)
  }

let directory = name => Node.join([root(), name])
let recordsFile = name => Node.join([directory(name), "figures.jsonl"])
let shownFile = name => Node.join([directory(name), "figures.txt"])

let recordOf = (line: string) =>
  Payload.parse(line)->Option.flatMap(fields => {
    let at = Ledger.numberOf(fields, "at")->Option.getOr(0.)
    let text = key => Ledger.textOf(fields, key)
    switch text("kind") {
    | "green" => Some(Green({step: text("step"), at}))
    | "seat" =>
      Some(
        Seat({
          name: text("name"),
          tooling: fields->Payload.flag("tooling"),
          at,
          session: ?(fields->Payload.text("session")),
        }),
      )
    | "seated" => Some(Seated({name: text("name"), at}))
    | "landed" =>
      Some(
        Landed({
          repository: text("repository"),
          commit: text("commit"),
          subject: text("subject"),
          at,
        }),
      )
    | _ => None
    }
  })

let recordsIn = (text: string) => text->String.split("\n")->Array.filterMap(recordOf)

let records = name =>
  Node.existsSync(recordsFile(name)) ? recordsIn(Node.readFileSync(recordsFile(name))) : []

let add = (name, fields) => Ledger.append(recordsFile(name), Ledger.line(fields))

type span = {tooling: bool, from: float, to: float}

/** Each seat's time, one still open running until `now`, at most `seatOpenSeconds`. */
let spans = (found: array<record>, ~now) =>
  found->Array.filterMap(one =>
    switch one {
    | Seat({name, tooling, at}) =>
      let closed = found->Array.findMap(other =>
        switch other {
        | Seated({name: ended, at: closedAt}) if ended == name && closedAt >= at => Some(closedAt)
        | _ => None
        }
      )
      Some({
        tooling,
        from: at,
        to: closed->Option.getOr(
          Math.min(now, at +. Delegation.seatOpenSeconds->Int.toFloat *. 1000.),
        ),
      })
    | _ => None
    }
  )

/** An unreported seat stops counting at the open seat limit. */
let seatsOf = (found: array<record>, ~session, ~now) =>
  found->Array.filterMap(one =>
    switch one {
    | Seat({name, at, session: ?Some(owner)}) if owner == session =>
      let closed = found->Array.findMap(other =>
        switch other {
        | Seated({name: ended, at: closedAt}) if ended == name && closedAt >= at => Some(closedAt)
        | _ => None
        }
      )
      Some((
        at,
        closed->Option.getOr(Math.min(now, at +. Delegation.seatOpenSeconds->Int.toFloat *. 1000.)),
      ))
    | _ => None
    }
  )

let lastGreen = found =>
  found->Array.reduce(None, (last, one) =>
    switch one {
    | Green({step, at}) => Some((step, at))
    | _ => last
    }
  )

/** A span's seconds at or after `since`. */
let after = (span, ~since) => Math.max(0., span.to -. Math.max(span.from, since)) /. 1000.

type figures = {
  step: option<string>,
  seatSeconds: float,
  landings: int,
  toolingShare: float,
  flagged: bool,
}

let figuresOf = (found: array<record>, ~now) => {
  let green = lastGreen(found)
  let since = green->Option.mapOr(0., ((_, at)) => at)
  let all = spans(found, ~now)
  let sum = (list: array<span>, ~since) =>
    list->Array.reduce(0., (total, span) => total +. after(span, ~since))
  let whole = sum(all, ~since=0.)
  let tooling = sum(all->Array.filter(span => span.tooling), ~since=0.)
  let toolingShare = whole > 0. ? tooling /. whole : 0.
  {
    step: green->Option.map(((step, _)) => step),
    seatSeconds: sum(all, ~since),
    landings: found
    ->Array.filter(one =>
      switch one {
      | Landed({at}) => at >= since
      | _ => false
      }
    )
    ->Array.length,
    toolingShare,
    flagged: toolingShare > Delegation.toolingShare,
  }
}

let shown = (name, figures) => {
  let percent = Float.toFixed(figures.toolingShare *. 100., ~digits=0)
  `figures to=advisor thread ${name}: since ${figures.step->Option.mapOr(
      "no step green yet",
      step => `step ${step} went green`,
    )}, ${Float.toFixed(figures.seatSeconds /. 60., ~digits=0)} seat minutes and ${Int.toString(
      figures.landings,
    )} landings; tooling ${percent}% of its seat time${figures.flagged
      ? ", past the share that warns"
      : ""}`
}

let threads = () =>
  Node.existsSync(root())
    ? Node.readdir(root())->Array.filter(name =>
        Node.stat(directory(name))->Option.mapOr(false, Node.statsIsDirectory)
      )
    : []

/** A thread's figures once each period, and once more on crossing the share. */
let keysOf = (name, figures, ~now) => {
  let hour = Float.toString(Math.floor(now /. (Delegation.figuresSeconds->Int.toFloat *. 1000.)))
  Array.concat([`figures:${name}:${hour}`], figures.flagged ? [`tooling:${name}`] : [])
}
