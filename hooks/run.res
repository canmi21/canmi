/**
 * The one hook entrypoint Claude Code and Codex both call, routing each event to its policies
 * and combining their answers into one response.
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
  | Some("PreToolUse") =>
    // The message first, as it is cheap and the commonest refusal; jj fix only once all pass.
    switch Commit.refuse(payload) {
    | 0 =>
      switch Push.refuse(payload) {
      | 0 =>
        switch Verified.handle(payload) {
        | 0 =>
          Commit.fix(payload)
          0
        | refused => refused
        }
      | refused => refused
      }
    | refused => refused
    }
  | Some("PostToolUse") =>
    combined([Decision.context(payload), Delta.context(payload)])->Option.forEach(message =>
      say(post(message))
    )
    0
  | Some("Stop") =>
    // One hold at a time, the bookmark's first and the language judged at the next stop.
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
