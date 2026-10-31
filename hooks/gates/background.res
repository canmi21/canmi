/** Refuses a shell command that would hold the conversation, a polling wait or a long timeout. */
/** A loop that sleeps between its tests, the shape of a wait typed in the foreground. */
let pollingLoop = /\b(?:until|while)\b[\s\S]*?\bdo\b[\s\S]*?\bsleep\b[\s\S]*?\bdone\b/

/** The longest foreground timeout a call may ask for, the harness's default, in milliseconds. */
let longest = 120000.

let timeout = (payload: Payload.t) =>
  switch payload
  ->Payload.object("tool_input")
  ->Option.flatMap(input => input->Dict.get("timeout")) {
  | Some(JSON.Number(milliseconds)) => Some(milliseconds)
  | _ => None
  }

let background = (payload: Payload.t) =>
  payload
  ->Payload.object("tool_input")
  ->Option.mapOr(false, input => input->Payload.flag("run_in_background"))

/** Whether a command line waits by polling, outside the body of a quoted here-document. */
let polls = command => pollingLoop->RegExp.test(Push.withoutQuotedBodies(command))

/** Why a foreground call would hold the conversation, or nothing where it would not. */
let held = (payload: Payload.t) =>
  if background(payload) {
    None
  } else if polls(Payload.command(payload)) {
    Some("it waits in a loop that sleeps")
  } else {
    switch timeout(payload) {
    | Some(milliseconds) if milliseconds > longest =>
      Some(`it asks for a timeout of ${Float.toString(milliseconds /. 1000.)} seconds`)
    | _ => None
    }
  }

/** The exit status the harness reads, 2 refusing the command with the reason on stderr. */
let refuse = (payload: Payload.t): int =>
  switch held(payload) {
  | None => 0
  | Some(why) =>
    Console.error(
      `Command refused by hooks/gates/background.res: ${why}, which holds the conversation.\n` ++
      "Run it with run_in_background, or watch for its end with Monitor, and read its output at the job's own pace.\n" ++ "The rule: long-command-background in model/rules/delegation.res, and docs/agents/agent-protocol.md",
    )
    2
  }
