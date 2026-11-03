/**
 * The run ledger, one JSON line for each start, end and read, docs/agents/runs.md. A job's state is
 * folded from its lines, so a line lost costs one fact and nothing rewrites another's.
 */
type job = {
  id: string,
  by: string,
  session: string,
  command: string,
  cwd: string,
  pid: int,
  started: float,
  output: string,
  limit: option<float>,
  quiet: bool,
  ended: option<float>,
  status: option<int>,
  read: option<float>,
}

@module("node:fs") external append: (string, string) => unit = "appendFileSync"
@get external mtimeMs: Node.stats => float = "mtimeMs"

/** Where the ledger lives; `RUNS_HOME` moves it, for a test and a rehearsal. */
let home = () =>
  switch Node.env->Dict.get("RUNS_HOME") {
  | Some(there) if there != "" => there
  | _ => Friction.expand(Delegation.runs)
  }

let file = () => Node.join([home(), "ledger.jsonl"])
let outputs = () => Node.join([home(), "outputs"])
let events = () => Node.join([home(), "events.log"])
let seen = () => Node.join([home(), "seen"])
let sessions = () => Node.join([home(), "sessions"])
let outputOf = id => Node.join([outputs(), `${id}.log`])

let textOf = (fields, key) => fields->Payload.text(key)->Option.getOr("")
let numberOf = (fields: Payload.t, key) =>
  switch fields->Dict.get(key) {
  | Some(JSON.Number(value)) => Some(value)
  | _ => None
  }

/** The jobs a ledger's text holds, in the order they started, an unreadable line passed over. */
let fold = (text: string): array<job> => {
  let order = []
  let found = Dict.make()
  text
  ->String.split("\n")
  ->Array.forEach(line =>
    switch Payload.parse(line) {
    | None => ()
    | Some(fields) =>
      let id = textOf(fields, "id")
      switch (textOf(fields, "kind"), found->Dict.get(id)) {
      | ("start", _) =>
        order->Array.push(id)
        found->Dict.set(
          id,
          {
            id,
            by: textOf(fields, "by"),
            session: textOf(fields, "session"),
            command: textOf(fields, "command"),
            cwd: textOf(fields, "cwd"),
            pid: numberOf(fields, "pid")->Option.mapOr(0, Float.toInt),
            started: numberOf(fields, "at")->Option.getOr(0.),
            output: textOf(fields, "output"),
            limit: numberOf(fields, "limit"),
            quiet: fields->Payload.flag("quiet"),
            ended: None,
            status: None,
            read: None,
          },
        )
      | ("end", Some(job)) =>
        found->Dict.set(
          id,
          {
            ...job,
            ended: numberOf(fields, "at"),
            status: numberOf(fields, "status")->Option.map(Float.toInt),
          },
        )
      | ("read", Some(job)) => found->Dict.set(id, {...job, read: numberOf(fields, "at")})
      | _ => ()
      }
    }
  )
  order->Array.filterMap(id => found->Dict.get(id))
}

let line = (fields: array<(string, JSON.t)>) =>
  JSON.stringify(JSON.Object(Dict.fromArray(fields))) ++ "\n"

let write = fields => {
  Node.mkdirAll(home())
  append(file(), line(fields))
}

let jobs = () => Node.existsSync(file()) ? fold(Node.readFileSync(file())) : []

let find = id => jobs()->Array.find(job => job.id == id)

/** The job a path is the output of, by its name, or none. */
let idOfOutput = path =>
  path->String.startsWith(outputs() ++ Node.sep) && path->String.endsWith(".log")
    ? Some(Node.basename(path)->String.slice(~start=0, ~end=-4))
    : None

/** A job's start as a ledger line. */
let startLine = (job: job) =>
  line(
    [
      ("kind", JSON.String("start")),
      ("id", JSON.String(job.id)),
      ("by", JSON.String(job.by)),
      ("session", JSON.String(job.session)),
      ("command", JSON.String(job.command)),
      ("cwd", JSON.String(job.cwd)),
      ("pid", JSON.Number(job.pid->Int.toFloat)),
      ("at", JSON.Number(job.started)),
      ("output", JSON.String(job.output)),
      ("quiet", JSON.Boolean(job.quiet)),
      ...job.limit->Option.mapOr([], limit => [("limit", JSON.Number(limit))]),
    ],
  )

let started = (job: job) => {
  Node.mkdirAll(home())
  append(file(), startLine(job))
}

let ended = (~id, ~status, ~at) =>
  write([
    ("kind", JSON.String("end")),
    ("id", JSON.String(id)),
    ("status", JSON.Number(status->Int.toFloat)),
    ("at", JSON.Number(at)),
  ])

let markRead = (~id, ~at) =>
  write([("kind", JSON.String("read")), ("id", JSON.String(id)), ("at", JSON.Number(at))])

/** A registered session's file, its turn read from its transcript's growth. */
/** A session's place in a thread, kept once written, as its current record holds only the last. */
type registration = {
  name: string,
  role: string,
  thread: string,
  transcript: option<string>,
  at: float,
}

let registrationsFile = () => Node.join([home(), "registrations.jsonl"])

/** Who belonged to a thread and since when, a transcript filling in once the hook names it. */
let registrationsOf = (thread): array<registration> => {
  let found: array<registration> = []
  if Node.existsSync(registrationsFile()) {
    Node.readFileSync(registrationsFile())
    ->String.split("\n")
    ->Array.forEach(text =>
      Payload.parse(text)->Option.forEach(fields =>
        if fields->Payload.text("thread") == Some(thread) {
          let one = {
            name: textOf(fields, "name"),
            role: textOf(fields, "role"),
            thread,
            transcript: fields->Payload.text("transcript"),
            at: numberOf(fields, "at")->Option.getOr(0.),
          }
          switch found->Array.findIndex(
            known =>
              known.name == one.name &&
                (known.transcript == None ||
                one.transcript == None ||
                known.transcript == one.transcript),
          ) {
          | -1 => found->Array.push(one)
          | at =>
            let known = found->Array.getUnsafe(at)
            found->Array.setUnsafe(
              at,
              {...known, transcript: known.transcript->Option.orElse(one.transcript)},
            )
          }
        }
      )
    )
  }
  found
}

let registerSession = (~role, ~name, ~transcript, ~thread=None, ~at=Date.now()) => {
  Node.mkdirAll(sessions())
  thread->Option.forEach(thread =>
    append(
      registrationsFile(),
      line(
        [
          ("name", JSON.String(name)),
          ("role", JSON.String(role)),
          ("thread", JSON.String(thread)),
          ...transcript->Option.mapOr([], file => [("transcript", JSON.String(file))]),
          ("at", JSON.Number(at)),
        ],
      ),
    )
  )
  Node.writeFileSync(
    Node.join([sessions(), `${name}.json`]),
    line(
      [
        ("name", JSON.String(name)),
        ("role", JSON.String(role)),
        ...Array.concat(
          transcript->Option.mapOr([], file => [("transcript", JSON.String(file))]),
          thread->Option.mapOr([], name => [("thread", JSON.String(name))]),
        ),
      ],
    ),
  )
}

/** Whether a job's result was read after it ended. */
let wasRead = (job: job) =>
  switch (job.ended, job.read) {
  | (Some(ended), Some(read)) => read >= ended
  | _ => false
  }

let seconds = (job: job) => job.ended->Option.map(ended => (ended -. job.started) /. 1000.)

/** The p95 of `values`, the nearest rank, none of nothing. */
let p95 = (values: array<float>) => {
  let sorted = values->Array.toSorted(Float.compare)
  let count = sorted->Array.length
  count == 0 ? None : sorted[Float.toInt(Math.ceil(0.95 *. count->Int.toFloat)) - 1]
}

/** How long `job` may run: its own limit, else twice its command's p95 once there is history. */
let limitOf = (job: job, ~all: array<job>) =>
  switch job.limit {
  | Some(_) as given => given
  | None =>
    let past =
      all
      ->Array.filter(other => other.command == job.command && other.status == Some(0))
      ->Array.filterMap(seconds)
    past->Array.length < Delegation.runHistory
      ? None
      : p95(past)->Option.map(value => value *. Delegation.runOverP95->Int.toFloat)
  }

type row = {command: string, count: int, total: float}

/** Duration times count by command, the bottleneck first, from `since` in milliseconds. */
let table = (all: array<job>, ~since=0.) => {
  let rows = Dict.make()
  all->Array.forEach(job =>
    switch seconds(job) {
    | Some(took) if job.started >= since =>
      let row =
        rows->Dict.get(job.command)->Option.getOr({command: job.command, count: 0, total: 0.})
      rows->Dict.set(job.command, {...row, count: row.count + 1, total: row.total +. took})
    | _ => ()
    }
  )
  rows->Dict.valuesToArray->Array.toSorted((a, b) => Float.compare(b.total, a.total))
}

/** A row as a person reads it, its total, count and command, cut to the width of a line. */
let shownRow = ({command, count, total}) => {
  let seconds = total->Float.toFixed(~digits=0)->String.padStart(8, " ")
  let times = Int.toString(count)->String.padStart(4, " ")
  `${seconds} s  ${times} x  ${command->String.slice(~start=0, ~end=72)}`
}
