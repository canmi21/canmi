/**
 * Reads the run ledger and the registered sessions and writes one event line for each thing nobody
 * is looking at, docs/agents/runs.md. Run by launchd each minute, it holds no model.
 */
type session = {name: string, role: string, transcript: option<string>, thread: option<string>}

type finding = {key: string, says: string, notify: bool}

type ciRun = {repository: string, workflow: string, id: string, sha: string, conclusion: string}

let ciOwed = (~runs: array<ciRun>, ~said: array<string>): array<finding> => {
  let latest = Dict.make()
  runs->Array.filterMap(run => {
    let workflows = latest->Dict.get(run.repository)->Option.getOr([])
    if workflows->Array.includes(run.workflow) {
      None
    } else {
      latest->Dict.set(run.repository, Array.concat(workflows, [run.workflow]))
      let key = `ci ${run.id}`
      run.conclusion == "failure" && !(said->Array.includes(key))
        ? Some({
            key,
            says: `ci to=supervisor,advisor ${run.repository} ${run.workflow} failed at ${run.sha->String.slice(
                ~start=0,
                ~end=8,
              )}, run ${run.id}`,
            notify: false,
          })
        : None
    }
  })
}

let ciLookDue = (~stamp, ~now) => {
  let last = try {
    Node.readFileSync(stamp)->Float.fromString
  } catch {
  | _ => None
  }
  if last->Option.mapOr(false, last => now -. last < 60000.) {
    false
  } else {
    Node.mkdirAll(Node.dirname(stamp))
    Node.writeFileSync(stamp, Float.toString(now))
    true
  }
}

type ciResult = {databaseId: float, workflowName: string, headSha: string, conclusion: string}

@scope("JSON") @val external parseCiRuns: string => array<ciResult> = "parse"

let ciRuns = (~now: float): array<ciRun> => {
  let stamp = Node.join([Node.dirname(Ledger.seen()), "ci-looked"])
  if !ciLookDue(~stamp, ~now) {
    []
  } else {
    Array.concat(
      ["canmi21/canmi"],
      Registry.registry()->Array.map(((_, (owner, repository))) => `${owner}/${repository}`),
    )->Array.flatMap(repository => {
      try {
        let result = Node.spawnSync(
          "gh",
          [
            "run",
            "list",
            "-R",
            repository,
            "--branch",
            "main",
            "-L",
            "10",
            "--json",
            "databaseId,workflowName,headSha,conclusion",
          ],
          {encoding: "utf8"},
        )
        if result.status->Nullable.toOption == Some(0) {
          parseCiRuns(result.stdout->Nullable.toOption->Option.getOr("[]"))->Array.map(run => {
            repository,
            workflow: run.workflowName,
            id: Float.toString(run.databaseId),
            sha: run.headSha,
            conclusion: run.conclusion,
          })
        } else {
          []
        }
      } catch {
      | _ => []
      }
    })
  }
}

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
  | (_, None) => [
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

/** The share past which a session of this role is reported, `contextReported`. */
let reportedAt = role =>
  Delegation.contextReported->Array.find(((one, _)) => one == role)->Option.map(((_, at)) => at)

/**
 * A session past its role's share is named to the supervisor and the advisor once per crossing,
 * a compaction starting a new one, and an advisor told it is due to be replaced.
 */
let aboutContext = (session: session, outcome: option<Context.outcome>): array<finding> =>
  switch (outcome, reportedAt(session.role)) {
  | (Some(Read({tokens, compactions})), Some(at)) if Context.share(tokens) >= at =>
    let held = `${Int.toString(tokens)} tokens, ${percent(Context.share(tokens))}% of its window`
    session.role == "advisor"
      ? [
          {
            key: `context:${session.name}:replace:${Int.toString(compactions)}`,
            says: `context to=advisor advisor ${session.name} holds ${held}, past ${percent(
                at,
              )}%, so it is due to be replaced (advisor-replaced)`,
            notify: false,
          },
        ]
      : [
          {
            key: `context:${session.name}:${Int.toString(compactions)}`,
            says: `context to=supervisor,advisor ${session.role} ${session.name} holds ${held}, past ${percent(
                at,
              )}%: it stops at a clean point, writes a savepoint, and the author compacts it (context-reported)`,
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

/** Idle integrators and their supervisors, with all activity supplied by the caller. */
let aboutIdle = (
  ~thread,
  ~ready: array<(Charter.step, float)>,
  ~sessions: array<session>,
  ~jobs: array<Ledger.job>,
  ~now,
  ~alive,
  ~moved,
  ~seats,
  ~openSeats=[],
  ~steps: array<Charter.step>=[],
  ~said: array<string>,
) => {
  let limit = Delegation.idleSeconds->Int.toFloat *. 1000.
  let sessionId = path => Node.basename(path)->String.replaceRegExp(/\.jsonl$/, "")
  // One whose turn cannot be read is `unwatched`, never idle.
  let integrators =
    sessions->Array.filter(one =>
      one.role == "integrator" &&
      one.thread == Some(thread) &&
      one.transcript->Option.flatMap(moved) != None
    )
  let activity = integrators->Array.map(one => {
    let own = one.transcript->Option.mapOr([], path => {
      jobs->Array.filter(job => job.session == sessionId(path))
    })
    let times = Array.concat(
      seats(one),
      one.transcript->Option.flatMap(moved)->Option.mapOr([], last => [last]),
    )
    // Holding a step is a live job or a seat; a turn alone keeps it from idle and holds no step.
    let holding =
      own->Array.some(job =>
        job.ended == None && alive(job.pid) && Ledger.runsUntil(job, ~now) >= now
      ) ||
      one.transcript->Option.mapOr(false, path => openSeats->Array.includes(sessionId(path))) ||
      seats(one)->Array.some(last => now -. last < limit)
    let busy = holding || times->Array.some(last => now -. last < limit)
    let last =
      own->Array.reduce(0., (last, job) =>
        Math.max(last, Math.max(job.started, job.ended->Option.getOr(0.)))
      )
    (one, busy, times->Array.reduce(last, Math.max), holding)
  })
  let holdingNumber = activity->Array.filter(((_, _, _, holding)) => holding)->Array.length
  let busyNumber = activity->Array.filter(((_, busy, _, _)) => busy)->Array.length
  let busyCount = busyNumber->Int.toString
  let total = integrators->Array.length->Int.toString
  let existing =
    ready == []
      ? []
      : {
          let first = ready->Array.reduce(now, (first, (_, since)) => Math.min(first, since))
          let ids = ready->Array.map(((step, _)) => step.id)->Array.join(", ")
          activity
          ->Array.flatMap(((one, busy, last, _)) => {
            let idleFrom = Math.max(first, last)
            let since = Float.toString(idleFrom)
            let waiting = now -. idleFrom
            busy || waiting < limit
              ? []
              : Array.concat(
                  [
                    {
                      key: `idle:${one.name}:${since}`,
                      says: `idle to=supervisor integrator ${one.name} has had no job, no seat and no turn for ${whole(
                          waiting /. 1000.,
                        )} s while thread ${thread} has ready step(s) ${ids}; ${busyCount} of ${total} integrators busy`,
                      notify: false,
                    },
                  ],
                  // Its transcript says nothing, as each Monitor notice writes there and wakes it.
                  sessions->Array.filterMap(supervisor => {
                    let deadline = idleFrom +. limit
                    supervisor.role == "supervisor" &&
                    supervisor.thread == Some(thread) &&
                    ready->Array.length > holdingNumber &&
                    now -. deadline >= Delegation.idleSupervisorSeconds->Int.toFloat *. 1000.
                      ? Some({
                          key: `idle-supervisor:${supervisor.name}:${one.name}:${since}`,
                          says: `idle to=advisor supervisor ${supervisor.name} has left integrator ${one.name} idle for ${whole(
                              (now -. deadline) /. 1000.,
                            )} s past its report, while thread ${thread} has ${ready
                            ->Array.length
                            ->Int.toString} ready step(s) and ${busyCount} busy integrators`,
                          notify: false,
                        })
                      : None
                  }),
                )
          })
          ->Array.filter(one => !(said->Array.includes(one.key)))
        }
  // No step is free for an integrator idle this long, so only the advisor can act.
  let unassigned =
    (steps != [] || ready != []) && ready->Array.length <= holdingNumber
      ? activity->Array.filterMap(((one, busy, last, _)) => {
          let waiting = now -. last
          busy || waiting < limit
            ? None
            : Some({
                key: `idle-unassigned:${one.name}:${Float.toString(last)}`,
                says: `idle to=advisor integrator ${one.name} has had no job, no seat and no turn for ${whole(
                    waiting /. 1000.,
                  )} s, and no step of thread ${thread} is free for it: ${ready
                  ->Array.length
                  ->Int.toString} ready, ${busyCount} of ${total} integrators busy`,
                notify: false,
              })
        })
      : []
  Array.concat(existing, unassigned)->Array.filter(one => !(said->Array.includes(one.key)))
}

/** The move times of a session's Claude seats, ignoring other files. */
let seats = (session: session) =>
  session.transcript->Option.mapOr([], path => {
    let directory = Node.join([path->String.replaceRegExp(/\.jsonl$/, ""), "subagents"])
    Node.existsSync(directory)
      ? Node.readdir(directory)
        ->Array.filter(name => name->String.endsWith(".jsonl"))
        ->Array.filterMap(name => {
          let path = Node.join([directory, name])
          Node.stat(path)->Option.flatMap(
            stat => Node.statsIsFile(stat) ? Some(Ledger.mtimeMs(stat)) : None,
          )
        })
      : []
  })

/** A failed thread read leaves every other thread available to this look. */
let idleOwed = (~sessions, ~jobs, ~said, ~now) =>
  Figures.threads()->Array.flatMap(thread => {
    let charter = why => {
      key: `charter:${thread}:${why}`,
      says: `charter to=supervisor thread ${thread}: ${why}, so its ready steps may be wrong`,
      notify: false,
    }
    try {
      let records = Figures.records(thread)
      let steps = Charter.steps(thread)
      let open_ = records->Array.filterMap(one =>
        switch one {
        | Seat({name, at, session: ?Some(session)})
          if now >= at && now -. at < Delegation.seatOpenSeconds->Int.toFloat *. 1000. =>
          records->Array.some(
            other =>
              switch other {
              | Seated({name: ended, at: closed}) => ended == name && closed >= at
              | _ => false
              },
          )
            ? None
            : Some(session)
        | _ => None
        }
      )
      Array.concat(
        Charter.problems(thread, ~records)->Array.map(charter),
        aboutIdle(
          ~thread,
          ~ready=Charter.ready(steps, records, ~at=now),
          ~sessions,
          ~jobs,
          ~said,
          ~now,
          ~alive,
          ~moved=Context.lastTurn,
          ~seats,
          ~openSeats=open_,
          ~steps,
        ),
      )
    } catch {
    | _ => [charter("its files cannot be read")]
    }->Array.filter(one => !(said->Array.includes(one.key)))
  })

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
let look = (~now=Date.now(), ~notify=notified, ~ci=ciRuns) => {
  Node.mkdirAll(Ledger.home())
  let said = Node.existsSync(Ledger.seen())
    ? Node.readFileSync(Ledger.seen())->String.split("\n")
    : []
  let sessions = registered()
  let jobs = Ledger.jobs()
  let reads =
    sessions->Array.filterMap(session =>
      contextRead(session, ~now)->Option.map(outcome => (session, outcome))
    )
  let outcomes = Dict.make()
  reads->Array.forEach(((session, outcome)) => outcomes->Dict.set(session.name, outcome))
  let found = Array.flat([
    owed(~jobs, ~sessions, ~said, ~now, ~alive, ~moved, ~contextOf=session =>
      outcomes->Dict.get(session.name)
    ),
    figuresOwed(~said, ~now),
    idleOwed(~sessions, ~jobs, ~said, ~now),
    ciOwed(~runs=ci(~now), ~said),
  ])
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
