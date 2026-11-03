open Testing

let assistant = (~input=2, ~read=0, ~created=0, ~output=0, ~sidechain=false, ()) =>
  `{"type":"assistant","isSidechain":${sidechain
      ? "true"
      : "false"},"message":{"role":"assistant","content":[{"type":"text","text":"x"}],"usage":{"input_tokens":${Int.toString(
      input,
    )},"cache_creation_input_tokens":${Int.toString(
      created,
    )},"cache_read_input_tokens":${Int.toString(read)},"output_tokens":${Int.toString(
      output,
    )},"service_tier":"standard"}}}`
let user = `{"type":"user","message":{"role":"user","content":"hello"}}`
let boundary = `{"type":"system","subtype":"compact_boundary","content":"Conversation compacted"}`
let quoting = `{"type":"user","message":{"role":"user","content":"a compact_boundary entry"}}`

describe("a session's last turn", () => {
  test("is its own line, and a queued notice written after it is not", () => {
    let root = Node.mkdtempSync(Node.join([Node.tmpdir(), "last-turn-"]))
    let file = Node.join([root, "t.jsonl"])
    let line = (kind, at) => `{"type":"${kind}","timestamp":"${at}"}`
    Node.writeFileSync(
      file,
      [
        line("assistant", "2026-11-03T00:00:00.000Z"),
        line("api-request", "2026-11-03T00:01:00.000Z"),
        line("queue-operation", "2026-11-03T00:09:00.000Z"),
        `{"type":"attachment","timestamp":"2026-11-03T00:09:01.000Z"}`,
      ]->Array.join("\n"),
    )
    expect(Context.lastTurn(file))->toEqual(
      Some(Date.fromString("2026-11-03T00:01:00.000Z")->Date.getTime),
    )
    expect(Context.lastTurn(Node.join([root, "none.jsonl"])))->toEqual(None)
    Node.rmSync(root, {recursive: true, force: true})
  })
})

describe("a transcript's context size", () => {
  let root = temporaryRoot("context-")
  let transcript = lines => {
    let path = Node.join([root.contents, "t.jsonl"])
    Node.writeFileSync(path, lines->Array.join("\n") ++ "\n")
    path
  }
  let cache = () => Node.join([root.contents, "cache"])

  test("is the last assistant message's four counts added", () => {
    let path = transcript([
      assistant(~read=900, ()),
      user,
      assistant(~input=2, ~read=623071, ~created=1224, ~output=159, ()),
      user,
    ])
    expect(Context.read(path, ~cache=cache(), ~now=0.))->toEqual(
      Context.Read({tokens: 624456, compactions: 0}),
    )
  })

  test("passes over a side chain and a message that states no usage", () => {
    let path = transcript([
      assistant(~read=500, ()),
      assistant(~input=0, ~read=0, ~created=0, ~output=0, ()),
      assistant(~read=9000, ~sidechain=true, ()),
    ])
    expect(Context.sizeOf(path))->toEqual(Ok(502))
  })

  test("is read from the end of a file far larger than the read", () => {
    let filler = Array.fromInitializer(~length=40000, _ => user)
    let path = transcript(
      Array.concat(Array.concat([assistant(~read=1, ())], filler), [assistant(~read=77, ())]),
    )
    expect(Context.sizeOf(path))->toEqual(Ok(79))
  })

  test("is unreadable and never zero when a file or a field is missing", () => {
    let none = Context.read(Node.join([root.contents, "absent"]), ~cache=cache(), ~now=0.)
    expect(none)->toEqual(Context.Unreadable("no transcript at the path"))
    let noUsage = transcript([user, user])
    expect(Context.sizeOf(noUsage))->toEqual(Error("no assistant message with usage in the file"))
    let broken = transcript([
      `{"type":"assistant","message":{"usage":{"input_tokens":2,"output_tokens":3}}}`,
    ])
    expect(Context.sizeOf(broken))->toEqual(Error("usage has no cache_read_input_tokens"))
    let empty = Node.join([root.contents, "empty.jsonl"])
    Node.writeFileSync(empty, "")
    expect(Context.sizeOf(empty))->toEqual(Error("no assistant message with usage in the file"))
  })

  test("counts compactions as entries, not as text quoting one, and reuses the count", () => {
    let path = transcript([user, boundary, quoting, assistant(~read=5, ()), boundary])
    expect(Context.read(path, ~cache=cache(), ~now=1000.))->toEqual(
      Context.Read({tokens: 7, compactions: 2}),
    )
    Node.writeFileSync(path, [boundary, assistant(~read=5, ())]->Array.join("\n") ++ "\n")
    let within = Context.read(path, ~cache=cache(), ~now=1000. +. 60000.)
    expect(within)->toEqual(Context.Read({tokens: 7, compactions: 2}))
    let later = Delegation.figuresSeconds->Int.toFloat *. 1000. +. 2000.
    expect(Context.read(path, ~cache=cache(), ~now=later))->toEqual(
      Context.Read({tokens: 7, compactions: 1}),
    )
  })

  test("puts an advisor due at the share and not under it", () => {
    let window = Delegation.contextWindowTokens->Int.toFloat
    let at = share => (window *. share)->Float.toInt
    expect(Context.due(at(Delegation.advisorReplacedFrom -. 0.01)))->toEqual(false)
    expect(Context.due(at(Delegation.advisorReplacedFrom +. 0.01)))->toEqual(true)
  })
})
