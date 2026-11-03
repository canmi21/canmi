/** Per session time between greens, read by thread rounds. */
type span = {from: float, to: float}
type activity = {
  session: Watchdog.session,
  at: float,
  jobs: array<span>,
  seats: array<span>,
  reviews: array<span>,
  turns: array<span>,
  missing: array<string>,
}
type decision = {asked: float, answered: option<float>}
type decisions = {timed: array<decision>, untimed: int, malformed: array<string>}
type bucket = Job | Review | Turn | Decision | Ready | Nothing
type totals = {
  job: float,
  review: float,
  turn: float,
  decision: float,
  ready: float,
  nothing: float,
}
type row = {session: Watchdog.session, minutes: totals}
type round = {heading: string, span: span, rows: array<row>, unattended: float}

let timeOf = text => {
  let time = Date.fromString(text)->Date.getTime
  Float.isFinite(time) ? Some(time) : None
}

let timestamps = text =>
  text
  ->String.split("\n")
  ->Array.filterMap(line =>
    // A notice queued for a session is none of its own work.
    line->String.includes("\"queue-operation\"")
      ? None
      : RegExp.exec(/"timestamp"\s*:\s*"([^"]+)"/, line)
        ->Option.flatMap(found => Charter.group(found, 0))
        ->Option.flatMap(timeOf)
  )

/** Only gaps within the model's turn gap join two timestamped events. */
let stretches = times => {
  let spans = []
  let current = ref(None)
  times
  ->Array.toSorted(Float.compare)
  ->Array.forEach(at =>
    switch current.contents {
    | Some(span) if at -. span.to <= Delegation.turnGapSeconds->Int.toFloat *. 1000. =>
      current := Some({...span, to: at})
    | previous =>
      previous->Option.forEach(span => spans->Array.push(span))
      current := Some({from: at, to: at})
    }
  )
  current.contents->Option.forEach(span => spans->Array.push(span))
  spans
}

/** A time a person wrote, its zone required and a sentence's period forgiven. */
let statedTime = text =>
  /^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})\.?$/->RegExp.test(text)
    ? timeOf(text->String.replaceRegExp(/\.$/, ""))
    : None

let decisionsOf = text => {
  let timed = []
  let untimed = ref(0)
  let malformed = []
  text
  ->String.splitByRegExp(/^##\s+/m)
  ->Array.slice(~start=1)
  ->Array.filterMap(x => x)
  ->Array.forEach(block => {
    let lines = block->String.split("\n")
    let name = lines[0]->Option.getOr("")
    let field = label =>
      lines
      ->Array.find(line => line->String.startsWith(label))
      ->Option.map(line => line->String.slice(~start=String.length(label))->String.trim->statedTime)

    // The template's own block is no decision.
    if !(name->String.startsWith("<")) {
      switch (field("Asked:"), field("Answered:")) {
      | (None, _) => untimed := untimed.contents + 1
      | (Some(Some(asked)), None) => timed->Array.push({asked, answered: None})
      | (Some(Some(asked)), Some(Some(answered))) =>
        timed->Array.push({asked, answered: Some(answered)})
      | _ => malformed->Array.push(name)
      }
    }
  })
  {timed, untimed: untimed.contents, malformed}
}

let read = file =>
  try Some(Node.readFileSync(file)) catch {
  | _ => None
  }
let entries = directory =>
  try Node.readdir(directory) catch {
  | _ => []
  }
let withoutSuffix = file =>
  file->String.endsWith(".jsonl") ? file->String.slice(~start=0, ~end=-6) : file

let activityOf = (
  session: Watchdog.session,
  ~jobs: array<Ledger.job>,
  ~now,
  ~alive,
  ~records=[],
  ~at=0.,
) => {
  let missing = []
  let activity = file =>
    switch read(file) {
    | Some(text) => timestamps(text)->stretches
    | None =>
      missing->Array.push(file)
      []
    }
  let turns = session.transcript->Option.mapOr([], activity)
  if session.transcript == None {
    missing->Array.push(`${session.role} ${session.name} has no transcript`)
  }
  let seats = []
  let reviews = []
  session.transcript->Option.forEach(transcript => {
    let directory = Node.join([withoutSuffix(transcript), "subagents"])
    entries(directory)
    ->Array.filter(file => file->String.endsWith(".jsonl"))
    ->Array.forEach(file => {
      let path = Node.join([directory, file])
      let reviewer =
        read(withoutSuffix(path) ++ ".meta.json")
        ->Option.flatMap(Payload.parse)
        ->Option.flatMap(fields => fields->Payload.text("agentType")) == Some("reviewer")
      activity(path)->Array.forEach(span => (reviewer ? reviews : seats)->Array.push(span))
    })
  })
  let id = session.transcript->Option.map(path => Node.basename(path)->withoutSuffix)
  id->Option.forEach(id =>
    Figures.seatsOf(records, ~session=id, ~now)->Array.forEach(((from, to)) =>
      seats->Array.push({from, to})
    )
  )
  let jobs =
    jobs->Array.filterMap(job =>
      id == Some(job.session) && (job.ended != None || alive(job.pid))
        ? Some({from: job.started, to: job.ended->Option.getOr(now)})
        : None
    )
  {session, at, jobs, seats, reviews, turns, missing}
}

let atOf = (record: Figures.record) =>
  switch record {
  | Green({at}) | Seat({at}) | Seated({at}) | Landed({at}) => at
  }

/** Record order preserves repeated greens of the same step. */
let spansOf = (records: array<Figures.record>, ~now) => {
  let rounds = []
  let from = ref(records->Array.get(0)->Option.mapOr(now, atOf))
  records->Array.forEach(record =>
    switch record {
    | Green({step, at}) =>
      rounds->Array.push((step, {from: from.contents, to: at}))
      from := at
    | _ => ()
    }
  )
  rounds->Array.push(("running", {from: from.contents, to: now}))
  rounds
}

/** A point event occupies its slice and an interval excludes its ending boundary. */
let holds = (spans: array<span>, slice: span) =>
  spans->Array.some(span =>
    span.from < slice.to &&
      (span.to > slice.from || (span.from == span.to && span.from >= slice.from))
  )

let active = (activity, slice) =>
  slice.from < activity.at
    ? None
    : holds(Array.concat(activity.jobs, activity.seats), slice)
    ? Some(Job)
    : holds(activity.reviews, slice)
    ? Some(Review)
    : holds(activity.turns, slice)
    ? Some(Turn)
    : None

let zero = {job: 0., review: 0., turn: 0., decision: 0., ready: 0., nothing: 0.}
let add = (total, bucket, minutes) =>
  switch bucket {
  | Job => {...total, job: total.job +. minutes}
  | Review => {...total, review: total.review +. minutes}
  | Turn => {...total, turn: total.turn +. minutes}
  | Decision => {...total, decision: total.decision +. minutes}
  | Ready => {...total, ready: total.ready +. minutes}
  | Nothing => {...total, nothing: total.nothing +. minutes}
  }

let roundsOf = (~records, ~sessions: array<activity>, ~steps, ~decisions, ~now): array<round> => {
  let ended = Figures.lastGreen(records)->Option.mapOr(false, ((_, at)) => {
    let green = Charter.greenBy(records, ~at)
    steps != [] && steps->Array.every(step => green->Dict.get(step.Charter.id) != None)
  })
  spansOf(records, ~now)
  ->Array.filter(((heading, _)) => heading != "running" || !ended)
  ->Array.map(((heading, span)) => {
    let totals = sessions->Array.map(_ => ref(zero))
    let at = ref(span.from)
    let unattended = ref(0.)
    while at.contents < span.to {
      let slice = {
        from: at.contents,
        to: Math.min(span.to, at.contents +. Delegation.roundSliceSeconds->Int.toFloat *. 1000.),
      }
      let buckets = sessions->Array.map(activity => active(activity, slice))
      let busy =
        sessions->Array.reduceWithIndex(0, (count, activity, index) =>
          count + (
            activity.session.role == "integrator" &&
              (buckets->Array.getUnsafe(index) == Some(Job) ||
              buckets->Array.getUnsafe(index) == Some(Turn) ||
              buckets->Array.getUnsafe(index) == Some(Review))
              ? 1
              : 0
          )
        )
      let ready = Charter.ready(steps, records, ~at=slice.from)->Array.length > busy
      let decision =
        decisions->Array.some(one =>
          one.asked <= slice.from && one.answered->Option.mapOr(true, at => at > slice.from)
        )
      if ready && !decision {
        unattended := unattended.contents +. (slice.to -. slice.from) /. 60000.
      }
      buckets->Array.forEachWithIndex((bucket, index) => {
        if slice.from >= (sessions->Array.getUnsafe(index)).at {
          let bucket = bucket->Option.getOr(decision ? Decision : ready ? Ready : Nothing)
          let total = totals->Array.getUnsafe(index)
          total := add(total.contents, bucket, (slice.to -. slice.from) /. 60000.)
        }
      })
      at := slice.to
    }
    {
      heading,
      span,
      rows: sessions->Array.mapWithIndex((activity, index) => {
        let total = totals->Array.getUnsafe(index)
        {session: activity.session, minutes: total.contents}
      }),
      unattended: unattended.contents,
    }
  })
}

let minutes = value => Float.toFixed(value, ~digits=2)
let shown = (~name, ~rounds: array<round>, ~untimed, ~missing, ~malformed=[], ~problems=[]) => {
  let lines = [`untimed decision blocks: ${Int.toString(untimed)}`]
  malformed->Array.forEach(block =>
    lines->Array.push(
      `decision block not timed, a time in it has no zone or does not parse: ${block}`,
    )
  )
  problems->Array.forEach(problem => lines->Array.push(`charter: ${problem}`))
  missing
  ->Set.fromArray
  ->Set.toArray
  ->Array.forEach(file =>
    lines->Array.push(`no activity from missing or unreadable transcript: ${file}`)
  )
  rounds->Array.forEach(round => {
    lines->Array.push(
      `${round.heading}: ${Watchdog.at(round.span.from)} to ${Watchdog.at(
          round.span.to,
        )}, ${minutes((round.span.to -. round.span.from) /. 60000.)} minutes`,
    )
    round.rows->Array.forEach(({session, minutes: total}) =>
      lines->Array.push(
        `${session.role} ${session.name}: job ${minutes(total.job)}, review ${minutes(
            total.review,
          )}, turn ${minutes(total.turn)}, decision ${minutes(total.decision)}, nothing ${minutes(
            total.nothing,
          )}, ready ${minutes(total.ready)} minutes`,
      )
    )
    lines->Array.push(`thread ${name}: ready ${minutes(round.unattended)} minutes`)
  })
  lines->Array.join("\n") ++ "\n"
}

let run = (name, ~now=Date.now()) => {
  let directory = Figures.directory(name)
  if !Node.existsSync(directory) {
    Console.error(`${name} has no thread directory`)
    2
  } else {
    let jobs = Ledger.jobs()
    let sessions = Ledger.registrationsOf(name)->Array.map(registration => {
      let session: Watchdog.session = {
        name: registration.name,
        role: registration.role,
        thread: Some(registration.thread),
        transcript: registration.transcript,
      }
      activityOf(
        session,
        ~at=registration.at,
        ~jobs,
        ~now,
        ~alive=Watchdog.alive,
        ~records=Figures.records(name),
      )
    })
    let decisions = read(Node.join([directory, "decisions.md"]))->Option.getOr("")->decisionsOf
    let rounds = roundsOf(
      ~records=Figures.records(name),
      ~sessions,
      ~steps=Charter.steps(name),
      ~decisions=decisions.timed,
      ~now,
    )
    let text = shown(
      ~name,
      ~rounds,
      ~untimed=decisions.untimed,
      ~malformed=decisions.malformed,
      ~problems=Charter.problems(name, ~records=Figures.records(name)),
      ~missing=sessions->Array.flatMap(activity => activity.missing),
    )
    Node.writeFileSync(Node.join([directory, "rounds.txt"]), text)
    Node.write(text)
    0
  }
}
