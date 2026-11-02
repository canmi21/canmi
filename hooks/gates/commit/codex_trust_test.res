open Testing

let payload = (command): Payload.t =>
  Dict.fromArray([("tool_input", JSON.Object(Dict.fromArray([("command", JSON.String(command))])))])

describe("the Codex trust reminder", () => {
  test("is given after a commit touching .codex/hooks.json", () => {
    let found = Codex_trust.remind(
      payload("jj commit -m 'feat: x'"),
      ~files=() => ["notes/a.md", ".codex/hooks.json"],
    )
    expect(found->Option.isSome)->toEqual(true)
    expect(found->Option.getOr("")->String.includes("trust Codex"))->toEqual(true)
  })

  test("is given when the commit sits behind another command", () => {
    let found = Codex_trust.remind(
      payload("mise run build && jj commit -m 'fix: x'"),
      ~files=() => [".codex/hooks.json"],
    )
    expect(found->Option.isSome)->toEqual(true)
  })

  test("is not given for a commit that leaves .codex/ alone", () => {
    let found = Codex_trust.remind(
      payload("jj commit -m 'fix: x'"),
      ~files=() => ["hooks/run.res", "notes/codex.md", "x.codex/y"],
    )
    expect(found)->toEqual(None)
  })

  test("is not given for a command that is no commit, and reads no files for it", () => {
    let found = Codex_trust.remind(payload("jj log"), ~files=() => failwith("read"))
    expect(found)->toEqual(None)
  })
})
