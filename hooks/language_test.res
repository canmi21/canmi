open Testing

let english = "The sidebar divider can now be dragged, and its width is stored in localStorage under the reader record, so a reload keeps it."
let chinese = "sidebar 分割线现在可以拖动了，宽度存进 localStorage 的 reader 记录，刷新后保持。"
let asked = "拖动分割线"

let object = pairs => JSON.Object(Dict.fromArray(pairs))
let text = value => JSON.String(value)

let claude = (~extra=[], role, said) =>
  role == "tool"
    ? object([
        ("type", text("user")),
        (
          "message",
          object([
            ("role", text("user")),
            ("content", JSON.Array([object([("type", text("tool_result"))])])),
          ]),
        ),
      ])
    : object(
        Array.concat(
          [
            ("type", text(role)),
            (
              "message",
              object([
                ("role", text(role)),
                (
                  "content",
                  role == "user"
                    ? text(said)
                    : JSON.Array([object([("type", text("text")), ("text", text(said))])]),
                ),
              ]),
            ),
          ],
          extra,
        ),
      )

let codex = (role, said) =>
  object([
    ("type", text("response_item")),
    (
      "payload",
      object([
        ("type", text("message")),
        ("role", text(role)),
        (
          "content",
          JSON.Array([
            object([
              ("type", text(role == "assistant" ? "output_text" : "input_text")),
              ("text", text(said)),
            ]),
          ]),
        ),
      ]),
    ),
  ])

/** The decision for a transcript of these records, written where the hook reads it. */
let decide = records => {
  let directory = Node.mkdtempSync(Node.join([Node.tmpdir(), "language-"]))
  let path = Node.join([directory, "transcript.jsonl"])
  Node.writeFileSync(
    path,
    records->Array.map(record => JSON.stringify(record))->Array.join("\n") ++ "\n",
  )
  let found = Language.response(
    Dict.fromArray([("hook_event_name", text("Stop")), ("transcript_path", text(path))]),
  )
  Node.rmSync(directory, {recursive: true, force: true})
  found
}

let held = found =>
  switch found {
  | Some(JSON.Object(fields)) => fields->Payload.text("decision") == Some("block")
  | _ => false
  }

describe("the language a turn ends in", () => {
  test("an English reply to a Chinese message is held, citing docs/voice.md", () => {
    let found = decide([claude("user", asked), claude("assistant", english)])
    expect(held(found))->toBe(true)
    expect(JSON.stringifyAny(found)->Option.getOr(""))->toContain("docs/voice.md")
  })

  test("a Chinese reply with English nouns passes", () => {
    expect(decide([claude("user", asked), claude("assistant", chinese)]))->toEqual(None)
  })

  test("only the reply that ends the turn is judged", () => {
    // A line between tool calls is the work's own; the author reads the reply it ends with.
    let status = [claude("user", asked), claude("assistant", english), claude("tool", "")]
    expect(decide(Array.concat(status, [claude("assistant", chinese)])))->toEqual(None)
    expect(
      held(decide([claude("user", asked), claude("tool", ""), claude("assistant", english)])),
    )->toBe(true)
  })

  test("a held turn is judged on what it wrote afterwards", () => {
    let feedback = claude(
      ~extra=[("isMeta", JSON.Boolean(true))],
      "user",
      "Stop hook feedback:\nThis turn spoke to the user in English.",
    )
    let records = [claude("user", asked), claude("assistant", english), feedback]
    expect(decide(Array.concat(records, [claude("assistant", chinese)])))->toEqual(None)
    expect(held(decide(Array.concat(records, [claude("assistant", english)]))))->toBe(true)
  })

  test("a user writing English is answered in English", () => {
    expect(
      decide([claude("user", "Answer in English, please."), claude("assistant", english)]),
    )->toEqual(None)
  })

  test("injected context and another session's message are not the user speaking", () => {
    let injected = claude("user", "<system-reminder>English context</system-reminder>")
    expect(held(decide([claude("user", asked), injected, claude("assistant", english)])))->toBe(
      true,
    )
    let human = [("origin", object([("kind", text("human"))]))]
    let teammate = claude(
      "user",
      "Another Claude session sent a message:\n<teammate-message>Done.</teammate-message>",
    )
    expect(
      held(decide([claude(~extra=human, "user", asked), teammate, claude("assistant", english)])),
    )->toBe(true)
    let marked = claude(
      ~extra=[("origin", object([("kind", text("task-notification"))]))],
      "user",
      "Done.",
    )
    expect(held(decide([claude("user", asked), marked, claude("assistant", english)])))->toBe(true)
    let english_asked = claude(~extra=human, "user", "Answer in English, please.")
    expect(decide([english_asked, claude("assistant", english)]))->toEqual(None)
  })

  test("code and short lines are not prose", () => {
    let fence = "```sh\n" ++ english ++ "\n```"
    expect(decide([claude("user", asked), claude("assistant", fence)]))->toEqual(None)
    expect(
      decide([claude("user", asked), claude("assistant", "apps/cms/src/lib/sidebar.ts")]),
    )->toEqual(None)
  })

  test("the Codex transcript is read the same way", () => {
    expect(held(decide([codex("user", asked), codex("assistant", english)])))->toBe(true)
    expect(decide([codex("user", asked), codex("assistant", chinese)]))->toEqual(None)
    let injected = [
      codex("user", asked),
      codex("user", "<environment_context>x</environment_context>"),
    ]
    expect(held(decide(Array.concat(injected, [codex("assistant", english)]))))->toBe(true)
  })

  test("without a transcript the last message is judged, and a missing one is no failure", () => {
    let last = said =>
      Language.response(
        Dict.fromArray([("hook_event_name", text("Stop")), ("last_assistant_message", text(said))]),
      )
    expect(held(last(english)))->toBe(true)
    expect(last(chinese))->toEqual(None)
    expect(
      Language.response(
        Dict.fromArray([
          ("hook_event_name", text("Stop")),
          ("transcript_path", text("/nonexistent")),
        ]),
      ),
    )->toEqual(None)
  })
})
