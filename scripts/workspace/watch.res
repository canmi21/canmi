/** `watch <file> [--stall <seconds>]` for Monitor, docs/agents/agent-protocol.md. */
type state = {offset: int, lastGrowth: float, nextStall: float, ended: bool}

let start = (~now, ~stall) => {offset: 0, lastGrowth: now, nextStall: now +. stall, ended: false}

let progress = RegExp.fromString(Delegation.watchProgress, ~flags="i")
let failure = RegExp.fromString(Delegation.watchFailure, ~flags="i")
let ending = RegExp.fromString(Delegation.watchEnd, ~flags="i")

/** The event a new line is, an end before a failure before progress, or none for a quiet one. */
let classify = line =>
  if ending->RegExp.test(line) {
    Some(`ended: ${line}`)
  } else if failure->RegExp.test(line) {
    Some(`failure: ${line}`)
  } else if progress->RegExp.test(line) {
    Some(`progress: ${line}`)
  } else {
    None
  }

/** One look at the file text at `now`, giving the next state and the lines to print. */
let step = (state, ~text, ~now, ~stall) => {
  let whole = text->String.lastIndexOf("\n") + 1
  if whole > state.offset {
    let fresh = text->String.slice(~start=state.offset, ~end=whole)->String.split("\n")
    let events = fresh->Array.filterMap(classify)
    let ended = events->Array.some(event => event->String.startsWith("ended:"))
    ({offset: whole, lastGrowth: now, nextStall: now +. stall, ended}, events)
  } else if now >= state.nextStall {
    let quiet = Float.toInt((now -. state.lastGrowth) /. 1000.)
    (
      {...state, nextStall: now +. stall},
      [`stalled: no new line for ${Int.toString(quiet)} seconds`],
    )
  } else {
    (state, [])
  }
}

@val external setInterval: (unit => unit, int) => unit = "setInterval"

let main = (argv: array<string>) =>
  switch argv[0] {
  | None =>
    Console.error("usage: mise run watch <file> [--stall <seconds>]")
    2
  | Some(file) =>
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
      let (next, events) = step(state.contents, ~text, ~now, ~stall)
      state := next
      events->Array.forEach(Console.log)
      if next.ended {
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
