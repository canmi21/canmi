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

/** A job id as `//:job start` names one, so its end is read from the ledger alone. */
let jobId = /^\d{8}-\d{6}-[0-9a-f]{4}$/

/**
 * A ledger job ends by its record or its missing process alone, and its output's lines never end
 * it, since a check's own tests print nested ends; only a bare file is ended by its lines.
 */
let step = (
  state,
  ~text=?,
  ~now,
  ~stall,
  ~job: option<Ledger.job>=None,
  ~ledger=false,
  ~alive=Watchdog.alive,
) => {
  if state.ended {
    (state, [])
  } else {
    let size = text->Option.mapOr(state.size, String.length)
    let whole = text->Option.mapOr(state.offset, text => text->String.lastIndexOf("\n") + 1)
    let fresh =
      whole > state.offset
        ? text->Option.getOr("")->String.slice(~start=state.offset, ~end=whole)->String.split("\n")
        : []
    let failures = fresh->Array.filter(line => failure->RegExp.test(line))
    let count = failures->Array.length
    let next = {
      ...state,
      offset: whole > state.offset ? whole : state.offset,
      size,
      lastGrowth: size > state.size ? now : state.lastGrowth,
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
    | None if ledger => None
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
      if (
        !next.stalled &&
        !(job->Option.mapOr(false, job => job.quiet)) &&
        now -. next.lastGrowth >= stall
      ) {
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
    let job: ref<option<Ledger.job>> = ref(None)
    let foundFile = ref(false)
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
      if !state.contents.ended {
        let now = Date.now()
        job :=
          switch job.contents {
          | Some(known) => Ledger.find(known.id)->Option.orElse(Some(known))
          | None =>
            Ledger.find(named)->Option.orElse(Ledger.idOfOutput(named)->Option.flatMap(Ledger.find))
          }
        let file = job.contents->Option.mapOr(named, job => job.output)
        foundFile := foundFile.contents || Node.existsSync(file)
        let text = try Some(Node.readFileSync(file)) catch {
        | _ => None
        }
        if job.contents == None && !foundFile.contents && now -. began >= stall {
          Console.log(`missing: no job in the ledger and no file for ${named}`)
          state := {...state.contents, ended: true}
          Node.exit(1)
        } else {
          let (next, events) = step(
            state.contents,
            ~text?,
            ~now,
            ~stall,
            ~job=job.contents,
            ~ledger=jobId->RegExp.test(named) || job.contents != None,
          )
          state := next
          events->Array.forEach(Console.log)
          if next.ended {
            job.contents->Option.forEach(job => Ledger.markRead(~id=job.id, ~at=Date.now()))
            Node.exit(0)
          } else if now -. began > Int.toFloat(Delegation.watchBoundSeconds) *. 1000. {
            Console.log(
              `bound: ${file} watched for ${Int.toString(Delegation.watchBoundSeconds)} seconds`,
            )
            Node.exit(0)
          }
        }
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
