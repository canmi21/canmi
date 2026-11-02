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

let session = message =>
  message == ""
    ? None
    : Some(
        JSON.Object(
          Dict.fromArray([
            (
              "hookSpecificOutput",
              JSON.Object(
                Dict.fromArray([
                  ("hookEventName", JSON.String("SessionStart")),
                  ("additionalContext", JSON.String(message)),
                ]),
              ),
            ),
          ]),
        ),
      )

/** What a session reads again once its context is compacted, docs/agents/agent-protocol.md. */
let afterCompaction = "Your context was compacted, and a summary keeps the work but drops rules. Before acting, read again: AGENTS.md's Start here and Core rules; your role's file in docs/agents/ (advisor.md, integrator.md) or the brief you were given; docs/voice.md, whose rules a summary loses most often (simplified Chinese to the author with English nouns, AskUserQuestion fields in Chinese, every time in US Eastern with UTC beside it, never a bare id); and docs/agents/agent-protocol.md, \"A long command never holds the conversation\". Then your memory's note of work in progress, where your role keeps one. The list is kept in docs/agents/agent-protocol.md, \"After a compaction\"."

/** The context a session starts with, the compaction note first where the start is one. */
let opening = (payload: Payload.t) =>
  [payload->Payload.text("source") == Some("compact") ? afterCompaction : "", Reminder.line()]
  ->Array.filter(part => part != "")
  ->Array.join("\n\n")

let handle = (payload: Payload.t): int =>
  switch payload->Payload.text("hook_event_name") {
  | Some("SessionStart") =>
    try {session(opening(payload))->Option.forEach(say)} catch {
    | _ =>
      session(
        payload->Payload.text("source") == Some("compact") ? afterCompaction : "",
      )->Option.forEach(say)
    }
    0
  | Some("PreToolUse") =>
    // The message first, as it is cheap and the commonest refusal; jj fix only once all pass.
    switch Commit.refuse(payload) {
    | 0 =>
      switch Push.refuse(payload) {
      | 0 =>
        switch Background.refuse(payload) {
        | 0 =>
          switch Rmvar.refuse(payload) {
          | 0 =>
            switch Seat.refuse(payload) {
            | 0 =>
              switch Codex_usage.refuse(payload) {
              | 0 =>
                switch Verified.handle(payload) {
                | 0 =>
                  switch Form.handle(payload) {
                  | 0 =>
                    switch Lose.handle(payload) {
                    | 0 =>
                      switch Trash.refuse(payload) {
                      | 0 =>
                        Commit.fix(payload)
                        0
                      | refused => refused
                      }
                    | refused => refused
                    }
                  | refused => refused
                  }
                | refused => refused
                }
              | refused => refused
              }
            | refused => refused
            }
          | refused => refused
          }
        | refused => refused
        }
      | refused => refused
      }
    | refused => refused
    }
  | Some("PostToolUse") =>
    // A ledger's fault never touches the work the call did.
    try Run_ledger.observe(payload) catch {
    | _ => ()
    }
    combined([
      Decision.context(payload),
      Delta.context(payload),
      Stale_jobs.context(payload),
      Codex_trust.context(payload),
    ])->Option.forEach(message => say(post(message)))
    0
  | Some("Stop") =>
    // One hold at a time, the bookmark's first, then a silent job, and the language judged last.
    switch Bookmark.response(payload) {
    | Some(held) => say(held)
    | None =>
      switch Stale_jobs.response(payload) {
      | Some(held) => say(held)
      | None => Language.response(payload)->Option.forEach(say)
      }
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
