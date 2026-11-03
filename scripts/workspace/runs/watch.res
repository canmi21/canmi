/** The bounded Monitor watcher follows docs/agents/runs.md. */
type state = {
  offset: int,
  size: int,
  lastGrowth: float,
  stalled: bool,
  nextFailure: float,
  failures: int,
  pending: int,
  first: string,
  ended: bool,
}

let failureInterval = Int.toFloat(Delegation.stallSeconds) *. 1000.
let start = (~now, ~stall as _) => {
  offset: 0,
  size: 0,
  lastGrowth: now,
  stalled: false,
  nextFailure: now +. failureInterval,
  failures: 0,
  pending: 0,
  first: "",
  ended: false,
}

let failure = RegExp.fromString(Delegation.watchFailure, ~flags="i")
let ending = RegExp.fromString(Delegation.watchEnd, ~flags="i")
let exited = RegExp.fromString("^\\[exited with code -?\\d+\\]$")

let classify = line =>
  if ending->RegExp.test(line) || exited->RegExp.test(line) {
    Some(`ended: ${line}`)
  } else {
    None
  }

/** A ledger job ends by its record or its missing process alone. */
let step = (state, ~text, ~now, ~stall, ~job: option<Ledger.job>=None, ~alive=Watchdog.alive) => {
  if state.ended {
    (state, [])
  } else {
    let size = text->String.length
    let whole = text->String.lastIndexOf("\n") + 1
    let fresh =
      whole > state.offset
        ? text->String.slice(~start=state.offset, ~end=whole)->String.split("\n")
        : []
    let failures = fresh->Array.filter(line => failure->RegExp.test(line))
    let count = failures->Array.length
    let next = {
      ...state,
      offset: whole > state.offset ? whole : state.offset,
      size,
      lastGrowth: size > state.size ? now : state.lastGrowth,
      stalled: size > state.size ? false : state.stalled,
      failures: state.failures + count,
      pending: state.pending + count,
      first: state.pending == 0 ? failures[0]->Option.getOr("") : state.first,
    }
    let endEvent = switch job {
    | Some({ended: Some(_), status: Some(status)} as job) =>
      let seconds = Ledger.seconds(job)->Option.getOr(0.)->Float.toFixed(~digits=1)
      Some(
        `ended: status ${Int.toString(status)}, ${seconds} s, ${Int.toString(
            next.failures,
          )} failure lines; mise run //:job read ${job.id}`,
      )
    | Some(job) if Job.died(job, ~alive) => Some(`ended: died; mise run //:job read ${job.id}`)
    | Some(_) => None
    | None => fresh->Array.findMap(classify)
    }
    switch endEvent {
    | Some(event) => ({...next, ended: true}, [event])
    | None =>
      let events = []
      let next = if next.pending > 0 && now >= next.nextFailure {
        events->Array.push(
          `failure: ${Int.toString(next.pending)} new failure lines; ${next.first}`,
        )
        {...next, pending: 0, first: "", nextFailure: now +. failureInterval}
      } else {
        next
      }
      if !next.stalled && now -. next.lastGrowth >= stall {
        let quiet = Float.toInt((now -. next.lastGrowth) /. 1000.)
        events->Array.push(`stalled: no new line for ${Int.toString(quiet)} seconds`)
        ({...next, stalled: true}, events)
      } else {
        (next, events)
      }
    }
  }
}

@val external setInterval: (unit => unit, int) => unit = "setInterval"

let main = (argv: array<string>) =>
  switch argv[0] {
  | None =>
    Console.error("usage: mise run //:watch <job id | file> [--stall <seconds>]")
    2
  | Some(named) =>
    // A job of the ledger is named by its id, and reaching its end is reading its result.
    let job =
      Ledger.find(named)->Option.orElse(Ledger.idOfOutput(named)->Option.flatMap(Ledger.find))
    let file = job->Option.mapOr(named, job => job.output)
    let id = job->Option.map(job => job.id)->Option.orElse(Ledger.idOfOutput(file))
    let stall =
      1000. *.
      switch argv->Array.findIndex(arg => arg == "--stall") {
      | -1 => Int.toFloat(Delegation.stallSeconds)
      | at =>
        argv[at + 1]
        ->Option.flatMap(Float.fromString)
        ->Option.getOr(Int.toFloat(Delegation.stallSeconds))
      }
    let began = Date.now()
    let state = ref(start(~now=began, ~stall))
    setInterval(() => {
      let now = Date.now()
      let text = try Node.readFileSync(file) catch {
      | _ => ""
      }
      let current = id->Option.flatMap(Ledger.find)
      let (next, events) = step(state.contents, ~text, ~now, ~stall, ~job=current)
      state := next
      events->Array.forEach(Console.log)
      if next.ended {
        id->Option.forEach(id => Ledger.markRead(~id, ~at=Date.now()))
        Node.exit(0)
      } else if now -. began > Int.toFloat(Delegation.watchBoundSeconds) *. 1000. {
        Console.log(
          `bound: ${file} watched for ${Int.toString(Delegation.watchBoundSeconds)} seconds`,
        )
        Node.exit(0)
      }
    }, 1000)
    0
  }

if Node.isMain {
  switch main(Node.args()) {
  | 0 => ()
  | code => Node.exit(code)
  }
}
