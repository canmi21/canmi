/**
 * Reads the run ledger and the registered sessions and writes one event line for each thing nobody
 * is looking at, docs/agents/runs.md. Run by launchd each minute, it holds no model.
 */
type session = {name: string, role: string, transcript: option<string>, thread: option<string>}

type finding = {key: string, says: string, notify: bool}

let at = time => Date.fromTime(time)->Date.toISOString
let short = command => command->String.slice(~start=0, ~end=72)
let whole = value => value->Float.toFixed(~digits=0)

/** What one job asks of a reader now, `moved` the time its output last grew. */
let aboutJob = (job: Ledger.job, ~all, ~now, ~alive, ~moved): array<finding> => {
  let name = `${job.id} by ${job.by}: ${short(job.command)}`
  switch job.ended {
  | Some(ended) =>
    !Ledger.wasRead(job) && now -. ended >= Delegation.runUnreadSeconds->Int.toFloat *. 1000.
      ? [
          {
            key: `ended:${job.id}`,
            says: `unread to=supervisor ended ${job.status->Option.mapOr("?", status =>
                Int.toString(status)
              )}, nobody read it: ${name}; mise run //:job read ${job.id}`,
            notify: false,
          },
        ]
      : []
  | None if !alive(job.pid) => [
      {
        key: `ended:${job.id}`,
        says: `died to=supervisor no end was written, its process is gone: ${name}`,
        notify: false,
      },
    ]
  | None =>
    let took = (now -. job.started) /. 1000.
    let last = moved(job.output)->Option.getOr(job.started)
    let silent = (now -. last) /. 1000.
    Array.concat(
      !job.quiet && silent >= Delegation.runSilentSeconds->Int.toFloat
        ? [
            {
              key: `silent:${job.id}:${Float.toString(last)}`,
              says: `silent to=supervisor no output for ${whole(silent)} s: ${name}`,
              notify: false,
            },
          ]
        : [],
      switch Ledger.limitOf(job, ~all) {
      | Some(limit) if took > limit => [
          {
            key: `over:${job.id}`,
            says: `over to=supervisor ${whole(took)} s past its limit of ${whole(
                limit,
              )} s: ${name}`,
            notify: false,
          },
        ]
      | _ => []
      },
    )
  }
}

/** What one registered session asks, its turn being when its transcript last grew. */
let aboutSession = (session: session, ~now, ~moved): array<finding> =>
  switch (
    Delegation.silentTurns->Array.find(((role, _, _)) => role == session.role),
    session.transcript->Option.flatMap(moved),
  ) {
  | (Some((_, limit, superior)), Some(last)) if (now -. last) /. 1000. >= limit->Int.toFloat =>
    let notify = session.role == Delegation.notifiesAuthor
    [
      {
        key: `turn:${session.name}:${Float.toString(last)}`,
        says: `quiet to=${superior} ${session.role} ${session.name} has taken no turn for ${whole(
            (now -. last) /. 1000.,
          )} s, its limit ${Int.toString(limit)} s${notify ? ", the author notified" : ""}`,
        notify,
      },
    ]
  | (Some(_), None) => [
      {
        key: `unwatched:${session.name}`,
        says: `unwatched to=${Delegation.silentTurns
          ->Array.find(((role, _, _)) => role == session.role)
          ->Option.mapOr("advisor", ((_, _, superior)) =>
            superior
          )} ${session.role} ${session.name} has no transcript to read, so its turn cannot be read`,
        notify: false,
      },
    ]
  | _ => []
  }

let percent = share => Float.toFixed(share *. 100., ~digits=0)

/** An advisor past the share of the window is told it is due to be replaced, once. */
let aboutContext = (session: session, outcome: option<Context.outcome>): array<finding> =>
  switch outcome {
  | Some(Read({tokens})) if session.role == "advisor" && Context.due(tokens) => [
      {
        key: `context:${session.name}:replace`,
        says: `context to=advisor advisor ${session.name} holds ${Int.toString(
            tokens,
          )} tokens, ${percent(Context.share(tokens))}% of its window, past ${percent(
            Delegation.advisorReplacedFrom,
          )}%, so it is due to be replaced (advisor-replaced)`,
        notify: false,
      },
    ]
  | _ => []
  }

/** The line a session's context figures are written as. */
let contextLine = (session: session, outcome: Context.outcome, ~now) =>
  `${at(now)} context ${session.name} ${session.role} ${switch outcome {
    | Read({tokens, compactions}) =>
      `${Int.toString(tokens)} tokens, ${percent(
          Context.share(tokens),
        )}% of the window, ${Int.toString(compactions)} compactions`
    | Unreadable(why) => `unreadable: ${why}`
    }}`

/** Everything owed now and not said before, each once. */
let owed = (~jobs, ~sessions, ~said: array<string>, ~now, ~alive, ~moved, ~contextOf=_ => None) =>
  Array.concat(
    Array.concat(
      jobs->Array.flatMap(job => aboutJob(job, ~all=jobs, ~now, ~alive, ~moved)),
      sessions->Array.flatMap(session => aboutSession(session, ~now, ~moved)),
    ),
    sessions->Array.flatMap(session => aboutContext(session, contextOf(session))),
  )->Array.filter(found => !(said->Array.includes(found.key)))

@module("node:process") external kill: (int, int) => unit = "kill"

/** Whether a process lives, as signal 0 asks. */
let alive = pid =>
  pid > 0 && try {
      kill(pid, 0)
      true
    } catch {
    | _ => false
    }

let moved = path => Node.stat(path)->Option.map(Ledger.mtimeMs)

let sessionFrom = (text: string): option<session> =>
  Payload.parse(text)->Option.map(fields => {
    name: Ledger.textOf(fields, "name"),
    role: Ledger.textOf(fields, "role"),
    transcript: fields->Payload.text("transcript"),
    thread: fields->Payload.text("thread"),
  })

/** The registered sessions, one file each, an unreadable one passed over. */
let registered = () =>
  Node.existsSync(Ledger.sessions())
    ? Node.readdir(Ledger.sessions())->Array.filterMap(name =>
        try sessionFrom(Node.readFileSync(Node.join([Ledger.sessions(), name]))) catch {
        | _ => None
        }
      )
    : []

/** A notification on the author's Mac, its text an argument so nothing in it is read as script. */
let notified = text =>
  Node.spawnSync(
    "osascript",
    [
      "-e",
      "on run argv",
      "-e",
      "display notification (item 1 of argv) with title \"workspace watchdog\" sound name \"Basso\"",
      "-e",
      "end run",
      "--",
      text,
    ],
    {stdio: "ignore", timeout: 10000},
  ).status->Nullable.toOption == Some(0)

/** Each thread's figures, written where the advisor reads them and said when a key is new. */
let figuresOwed = (~said: array<string>, ~now) =>
  Figures.threads()->Array.flatMap(name => {
    let figures = Figures.figuresOf(Figures.records(name), ~now)
    let says = Figures.shown(name, figures)
    Node.writeFileSync(Figures.shownFile(name), `${at(now)} ${says}\n`)
    let fresh =
      Figures.keysOf(name, figures, ~now)->Array.filter(key => !(said->Array.includes(key)))
    // One line for a look, each key marked by it.
    fresh->Array.mapWithIndex((key, index) => {key, says: index == 0 ? says : "", notify: false})
  })

/** What one session's transcript says, a fault in the read being a value and never a stop. */
let contextRead = (session: session, ~now) =>
  session.transcript->Option.map(path =>
    try Context.read(path, ~cache=Node.join([Ledger.home(), "compactions"]), ~now) catch {
    | _ => Context.Unreadable("the read failed unexpectedly")
    }
  )

/** Each session's figures, on its thread's figures.txt after its own line, else contexts.txt. */
let contextsWritten = (reads: array<(session, Context.outcome)>, ~now) => {
  let loose = []
  reads->Array.forEach(((session, outcome)) => {
    let line = `${contextLine(session, outcome, ~now)}\n`
    let placed = switch session.thread {
    | Some(thread) if Node.existsSync(Figures.directory(thread)) =>
      try {
        Ledger.append(Figures.shownFile(thread), line)
        true
      } catch {
      | _ => false
      }
    | _ => false
    }
    if !placed {
      loose->Array.push(line)
    }
  })
  try Node.writeFileSync(Node.join([Ledger.home(), "contexts.txt"]), loose->Array.join("")) catch {
  | _ => ()
  }
}

/** One look, its events written and each marked said, how many it wrote returned. */
let look = (~now=Date.now(), ~notify=notified) => {
  Node.mkdirAll(Ledger.home())
  let said = Node.existsSync(Ledger.seen())
    ? Node.readFileSync(Ledger.seen())->String.split("\n")
    : []
  let sessions = registered()
  let reads =
    sessions->Array.filterMap(session =>
      contextRead(session, ~now)->Option.map(outcome => (session, outcome))
    )
  let outcomes = Dict.make()
  reads->Array.forEach(((session, outcome)) => outcomes->Dict.set(session.name, outcome))
  let found = Array.concat(
    owed(~jobs=Ledger.jobs(), ~sessions, ~said, ~now, ~alive, ~moved, ~contextOf=session =>
      outcomes->Dict.get(session.name)
    ),
    figuresOwed(~said, ~now),
  )
  contextsWritten(reads, ~now)
  found->Array.forEach(one => {
    if one.says != "" {
      Ledger.append(Ledger.events(), `${at(now)} ${one.says}\n`)
    }

    // An author not reached is tried again at the next look.
    if !one.notify || notify(one.says) {
      Ledger.append(Ledger.seen(), `${one.key}\n`)
    }
  })
  found->Array.length
}

if Node.isMain {
  look()->ignore
}
