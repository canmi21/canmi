/**
 * The one hook entrypoint Claude Code and Codex both call, through the same line in their adapters:
 * it routes each event to its policies and combines what they answer into one response.
 */
let post = (message: string) => JSON.Object(
  Dict.fromArray([
    (
      "hookSpecificOutput",
      JSON.Object(
        Dict.fromArray([
          ("hookEventName", JSON.String("PostToolUse")),
          ("additionalContext", JSON.String(message)),
        ]),
      ),
    ),
  ]),
)

/** Every post-tool observation that applies, as one context. */
let combined = (messages: array<option<string>>) =>
  switch messages->Array.filterMap(message => message) {
  | [] => None
  | found => Some(found->Array.join("\n\n"))
  }

let say = json => Console.log(JSON.stringify(json))

let handle = (payload: Payload.t): int =>
  switch payload->Payload.text("hook_event_name") {
  | Some("PreToolUse") => Commit.handle(payload)
  | Some("PostToolUse") =>
    combined([Decision.context(payload), Delta.context(payload)])->Option.forEach(message =>
      say(post(message))
    )
    0
  | Some("Stop") =>
    // One hold at a time: work outside the bookmark costs more; the language is judged next stop.
    switch Bookmark.response(payload) {
    | Some(held) => say(held)
    | None => Language.response(payload)->Option.forEach(say)
    }
    0
  | _ => 0
  }

if Node.isMain {
  let read = try Node.readStdin() catch {
  | _ => ""
  }
  Node.exit(Payload.parse(read)->Option.mapOr(0, handle))
}
