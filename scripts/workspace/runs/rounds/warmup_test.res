open Testing

let stamp = seconds => {
  let total = Int.toString(seconds / 60)->String.padStart(2, "0")
  let rest = Int.toString(mod(seconds, 60))->String.padStart(2, "0")
  `2026-11-03T00:${total}:${rest}Z`
}

let call = (~seconds, ~id, ~name, ~command="") =>
  `{"timestamp":"${stamp(
      seconds,
    )}","message":{"content":[{"type":"tool_use","id":"${id}","name":"${name}","input":{"command":"${command}"}}]}}`
let result = (~seconds, ~id) =>
  `{"timestamp":"${stamp(
      seconds,
    )}","message":{"content":[{"type":"tool_result","tool_use_id":"${id}"}]}}`
let join = lines => lines->Array.join("\n")

describe("seat phases", () => {
  test("a transcript with known times gives its phases", () => {
    let text = join([
      `{"timestamp":"${stamp(0)}","type":"user"}`,
      call(~seconds=10, ~id="a", ~name="Read"),
      call(~seconds=20, ~id="b", ~name="Bash", ~command="cat x"),
      call(~seconds=30, ~id="c", ~name="Bash", ~command="mise run built blk"),
      call(~seconds=60, ~id="d", ~name="Edit"),
      call(~seconds=70, ~id="e", ~name="Bash", ~command="mise run //:lane check tests"),
      result(~seconds=100, ~id="e"),
      call(~seconds=110, ~id="f", ~name="Read"),
      result(~seconds=120, ~id="f"),
    ])
    expect(Warmup.of_(text))->toEqual(
      Some({Warmup.warmup: 60., reads: 2, editing: 60., checks: 30., whole: 120.}),
    )
  })
  test("a transcript with no edit gives none", () => {
    let text = join([`{"timestamp":"${stamp(0)}"}`, call(~seconds=5, ~id="a", ~name="Read")])
    expect(Warmup.of_(text))->toEqual(None)
    expect(Warmup.of_(""))->toEqual(None)
  })
  test("reads count only before the first edit", () => {
    let text = join([
      call(~seconds=0, ~id="a", ~name="Grep"),
      call(~seconds=5, ~id="b", ~name="Write"),
      call(~seconds=10, ~id="c", ~name="Read"),
      call(~seconds=15, ~id="d", ~name="Glob"),
    ])
    expect(Warmup.of_(text)->Option.map(one => one.reads))->toEqual(Some(1))
  })
})
