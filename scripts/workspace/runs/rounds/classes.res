type activity = {kind: string, who: string, description: string, spans: array<Rounds.span>}
type thread = {sessions: array<string>, records: array<Figures.record>}
type landing = {repository: string, result: result<array<string>, string>}
type timing = {
  kind: string,
  who: string,
  description: string,
  seconds: float,
  recurring: option<bool>,
}
type push = {thread: string, step: string, seconds: option<float>}
type row = {kind: string, values: array<float>, recurring: option<int>, count: int}

let names = () =>
  Array.concat(
    Delegation.jobClasses->Array.map(((name, _)) => name),
    ["other", "Claude seat", "review", "landing"],
  )
let classOf = command =>
  Delegation.jobClasses
  ->Array.find(((_, pattern)) => RegExp.fromString(pattern)->RegExp.test(command))
  ->Option.mapOr("other", ((name, _)) => name)

let normalized = (~lanes=[], command) => {
  command
  ->String.splitByRegExp(/\s+/)
  ->Array.filterMap(word => word)
  ->Array.map(word => {
    let bare = word->String.replaceRegExp(/['"]/g, "")
    lanes->Array.includes(bare) || (bare->String.includes("/") && !(bare->String.startsWith("//:")))
      ? ""
      : word->String.replaceRegExp(
          /\b(?:0x[0-9a-f]+|[0-9a-f]{7,}|\d+(?:\.\d+)?|[a-z]*[0-9][\w-]*|[\w]+-[\w]+-[\w-]+)\b/gi,
          "",
        )
  })
  ->Array.join(" ")
  ->String.replaceRegExp(/\s+/g, " ")
  ->String.trim
}

let recurring = (same: array<Ledger.job>, threads: array<thread>) => {
  let days =
    same
    ->Array.map(job =>
      Date.fromTime(job.started)->Date.toISOString->String.slice(~start=0, ~end=10)
    )
    ->Set.fromArray
  days->Set.size > 1 ||
    threads->Array.some(thread =>
      thread.records->Array.some(record =>
        switch record {
        | Green({at}) =>
          same->Array.some(
            job =>
              thread.sessions->Array.includes(job.session) &&
                job.ended->Option.mapOr(false, ended => ended <= at),
          ) &&
            same->Array.some(
              job => thread.sessions->Array.includes(job.session) && job.started > at,
            )
        | _ => false
        }
      )
    )
}

let timings = (
  ~jobs: array<Ledger.job>,
  ~activity: array<activity>,
  ~records: array<thread>,
  ~since,
) => {
  let jobs = jobs->Array.filter(job => job.started >= since && job.ended != None)
  let lanes = jobs->Array.map(job => job.by)->Set.fromArray->Set.toArray
  let groups = Dict.make()
  let keyed = jobs->Array.map(job => (job, normalized(~lanes, job.command)))
  keyed->Array.forEach(((job, key)) => {
    let group = groups->Dict.get(key)->Option.getOr([])
    group->Array.push(job)
    groups->Dict.set(key, group)
  })
  let recurrences =
    groups
    ->Dict.toArray
    ->Array.map(((key, group)) => (key, recurring(group, records)))
    ->Dict.fromArray
  Array.concat(
    keyed->Array.map(((job, key)) => {
      kind: classOf(job.command),
      who: job.by,
      description: job.command->Node.codePoints->Array.slice(~start=0, ~end=72)->Array.join(""),
      seconds: Ledger.seconds(job)->Option.getOr(0.),
      recurring: recurrences->Dict.get(key),
    }),
    activity->Array.filterMap(one => {
      let spans = one.spans->Array.filter(span => span.to >= since)
      spans == []
        ? None
        : Some({
            kind: one.kind,
            who: one.who,
            description: one.description,
            seconds: spans->Array.reduce(0., (sum, span) =>
              sum +. Math.max(0., span.to -. Math.max(since, span.from)) /. 1000.
            ),
            recurring: None,
          })
    }),
  )
}

let total = row => row.values->Array.reduce(0., (sum, value) => sum +. value)
let median = values => {
  let sorted = values->Array.toSorted(Float.compare)
  let size = sorted->Array.length
  size == 0
    ? None
    : Some((sorted->Array.getUnsafe((size - 1) / 2) +. sorted->Array.getUnsafe(size / 2)) /. 2.)
}
let rows = (timings: array<timing>, landings: array<landing>) =>
  names()
  ->Array.map(kind => {
    let matching = timings->Array.filter(one => one.kind == kind)
    {
      kind,
      values: matching->Array.map(one => one.seconds),
      recurring: ["Claude seat", "review", "landing"]->Array.includes(kind)
        ? None
        : Some(matching->Array.filter(one => one.recurring == Some(true))->Array.length),
      count: kind == "landing"
        ? landings->Array.reduce(0, (sum, one) =>
            sum +
            switch one.result {
            | Ok(subjects) => subjects->Array.length
            | Error(_) => 0
            }
          )
        : matching->Array.length,
    }
  })
  ->Array.toSorted((a, b) => {
    let empty = Int.compare(a.count == 0 ? 1 : 0, b.count == 0 ? 1 : 0)
    empty == 0. ? Float.compare(total(b), total(a)) : empty
  })

/** Each green at or after `since` with its seconds to the next landing recorded. */
let pushesOf = (named: array<(string, array<Figures.record>)>, ~since) =>
  named->Array.flatMap(((thread, found)) =>
    Figures.greenToPush(found)->Array.filterMap(((step, at, seconds)) =>
      at >= since ? Some({thread, step, seconds}) : None
    )
  )

/** Why green to push prints no figure, plan item green-to-push-measured. */
let greenToPushUnmeasured = "green to push: not measured, as a step's green is recorded after its own landing and nothing records when it went green locally or which landing is its own"

type seat = {who: string, name: string, text: string}

let shown = (~timings, ~landings, ~pushes=[], ~seats=[]) => {
  let number = value => value->Float.toFixed(~digits=1)
  let lines = ["class | runs | total seconds | median | longest | recurring | one-off"]
  rows(timings, landings)->Array.forEach(row => {
    let count = row.count == 0 ? "-" : Int.toString(row.count)
    let times =
      row.values == []
        ? "- | - | -"
        : `${number(total(row))} | ${number(median(row.values)->Option.getOr(0.))} | ${number(
              row.values->Array.reduce(0., Math.max),
            )}`
    let recurrence = switch row.recurring {
    | Some(value) if row.count > 0 => `${Int.toString(value)} | ${Int.toString(row.count - value)}`
    | _ => "- | -"
    }
    lines->Array.push(`${row.kind} | ${count} | ${times} | ${recurrence}`)
    if row.kind == "landing" {
      landings->Array.forEach(one =>
        lines->Array.push(
          `  ${one.repository}: ${switch one.result {
            | Ok(subjects) => Int.toString(subjects->Array.length)
            | Error(why) => `jj failed: ${why}`
            }}`,
        )
      )
    }
  })
  lines->Array.push(
    "recurring against one-off is a first read, by a normalized command, a retry of one fault reading as recurring",
  )

  // A step's green follows its own landing, so the next landing is another's, and none is printed.
  if pushes != [] {
    lines->Array.push(greenToPushUnmeasured)
  }
  lines->Array.push(
    `pieces past ${Int.toString(
        Delegation.pieceMinutes,
      )} minutes, allowed while starting, warning and never blocking`,
  )
  timings
  ->Array.filter(one => one.seconds > Delegation.pieceMinutes->Int.toFloat *. 60.)
  ->Array.forEach(one =>
    lines->Array.push(
      `${one.kind} | ${one.who} | ${number(one.seconds /. 60.)} minutes | ${one.description}`,
    )
  )
  let minutes = seconds => number(seconds /. 60.)
  lines->Array.push("seat | who | warm-up | reads | editing | checks | whole")
  seats->Array.forEach(seat =>
    switch Warmup.of_(seat.text) {
    | Some(one) =>
      let slow = one.warmup > 120. ? " (past 2 minutes)" : ""
      let many = one.reads > 15 ? " (past 15)" : ""
      lines->Array.push(
        `${seat.name} | ${seat.who} | ${minutes(one.warmup)}${slow} | ${Int.toString(
            one.reads,
          )}${many} | ${minutes(one.editing)} | ${minutes(one.checks)} | ${minutes(one.whole)}`,
      )
    | None => lines->Array.push(`${seat.name} | ${seat.who} | - | - | - | - | -`)
    }
  )
  lines->Array.join("\n") ++ "\n"
}

let activityOf = (sessions: array<Watchdog.session>) => {
  let seen = Set.make()
  sessions->Array.flatMap(session =>
    session.transcript->Option.mapOr([], transcript => {
      let directory = Node.join([Rounds.withoutSuffix(transcript), "subagents"])
      Rounds.entries(directory)
      ->Array.filter(file => file->String.endsWith(".jsonl"))
      ->Array.filterMap(
        file => {
          let path = Node.join([directory, file])
          if seen->Set.has(path) {
            None
          } else {
            seen->Set.add(path)->ignore
            let kind =
              Rounds.read(Rounds.withoutSuffix(path) ++ ".meta.json")
              ->Option.flatMap(Payload.parse)
              ->Option.flatMap(fields => fields->Payload.text("agentType")) == Some("reviewer")
                ? "review"
                : "Claude seat"
            Some({
              kind,
              who: session.name,
              description: file,
              spans: Rounds.read(path)->Option.mapOr([], Rounds.whole),
            })
          }
        },
      )
    })
  )
}

let seatsOf = (sessions: array<Watchdog.session>) =>
  activityOf(sessions)
  ->Array.filter(one => one.kind == "Claude seat")
  ->Array.filterMap(one =>
    sessions
    ->Array.find(session => session.name == one.who)
    ->Option.flatMap(session => session.transcript)
    ->Option.flatMap(transcript =>
      Rounds.read(Node.join([Rounds.withoutSuffix(transcript), "subagents", one.description]))
    )
    ->Option.map(text => {who: one.who, name: one.description, text})
  )

let landingOf = (~repository, result: Node.spawned): landing => {
  repository,
  result: result.status->Nullable.toOption == Some(0) && result.error->Nullable.toOption == None
    ? Ok(result.stdout->Nullable.getOr("")->String.split("\n")->Array.filter(line => line != ""))
    : Error(
        result.stderr->Nullable.getOr("")->String.trim == ""
          ? "no successful result or timeout"
          : result.stderr->Nullable.getOr("")->String.trim,
      ),
}

let run = argv => {
  let day = switch argv {
  | [] =>
    Some(
      Date.fromTime(Date.now() -. 7. *. 86400000.)
      ->Date.toISOString
      ->String.slice(~start=0, ~end=10),
    )
  | ["--since", day] => Some(day)
  | _ => None
  }
  switch day {
  | Some(day) if /^\d{4}-\d{2}-\d{2}$/->RegExp.test(day) && Rounds.timeOf(day) != None =>
    let threads = Figures.threads()
    let historical: array<Watchdog.session> = threads->Array.flatMap(thread =>
      Ledger.registrationsOf(thread)->Array.map(one => {
        Watchdog.name: one.name,
        role: one.role,
        transcript: one.transcript,
        thread: Some(thread),
      })
    )
    let sessions = Array.concat(historical, Watchdog.registered())
    let records = threads->Array.map(thread => {
      sessions: sessions
      ->Array.filter(session => session.thread == Some(thread))
      ->Array.filterMap(session =>
        session.transcript->Option.map(path => Node.basename(path)->Rounds.withoutSuffix)
      ),
      records: Figures.records(thread),
    })
    let landings =
      Array.concat(
        [("workspace", Registry.root)],
        Registry.paths()->Array.map(name => (name, Node.join([Registry.repos, name]))),
      )
      ->Array.filter(((name, directory)) =>
        Node.existsSync(Node.join([directory, ".jj"])) && Waiting.pauser(~repo=name) == None
      )
      ->Array.map(((repository, directory)) =>
        landingOf(
          ~repository,
          Node.spawnSync(
            "jj",
            [
              "log",
              "--no-graph",
              "-R",
              directory,
              "-r",
              `::main & committer_date(after:"${day}T00:00:00-00:00")`,
              "-T",
              "description.first_line() ++ \"\\n\"",
            ],
            {encoding: "utf8", timeout: 10000, maxBuffer: 268435456},
          ),
        )
      )
    Node.write(
      shown(
        ~timings=timings(
          ~jobs=Ledger.jobs(),
          ~activity=activityOf(sessions),
          ~records,
          ~since=Rounds.timeOf(day)->Option.getOr(0.),
        ),
        ~landings,
        ~pushes=pushesOf(
          threads->Array.map(thread => (thread, Figures.records(thread))),
          ~since=Rounds.timeOf(day)->Option.getOr(0.),
        ),
        ~seats=seatsOf(sessions),
      ),
    )
    0
  | _ =>
    Console.error("usage: mise run //:job table --by-class [--since <yyyy-mm-dd>]")
    2
  }
}
