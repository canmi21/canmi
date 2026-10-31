open Testing

let payload = (~background=false, ~timeout=?, command): Payload.t => {
  let input = Dict.fromArray([
    ("command", JSON.String(command)),
    ("run_in_background", JSON.Boolean(background)),
  ])
  timeout->Option.forEach(ms => input->Dict.set("timeout", JSON.Number(ms)))
  Dict.fromArray([("tool_input", JSON.Object(input))])
}

describe("a command that holds the conversation", () => {
  test("is a foreground loop that sleeps, however it is written", () => {
    expect(Background.polls("until grep -q done log; do sleep 5; done"))->toEqual(true)
    expect(Background.polls("while true; do s=$(gh run view 1); sleep 20; done"))->toEqual(true)
    expect(Background.polls("f=out; until [ -s $f ]\ndo\n  sleep 3\ndone\ncat $f"))->toEqual(true)
  })

  test("is not a loop without a sleep, a lone sleep, or a loop in a quoted here-document", () => {
    expect(Background.polls("while read -r line; do echo $line; done < list"))->toEqual(false)
    expect(Background.polls("for f in a b; do cat $f; done"))->toEqual(false)
    expect(Background.polls("sleep 2; cat out"))->toEqual(false)
    expect(
      Background.polls("python3 - <<'EOF'\nwhile x: do_it(); sleep(1)\ndone = 1\nEOF"),
    )->toEqual(false)
  })

  test("is refused in the foreground and passed in the background", () => {
    expect(Background.refuse(payload("until test -e f; do sleep 2; done")))->toEqual(2)
    expect(
      Background.refuse(payload(~background=true, "until test -e f; do sleep 2; done")),
    )->toEqual(0)
    expect(Background.refuse(payload("ls")))->toEqual(0)
  })

  test("is a foreground call asking for more than the harness's default timeout", () => {
    expect(Background.refuse(payload(~timeout=600000., "mise run check")))->toEqual(2)
    expect(Background.refuse(payload(~timeout=120000., "mise run check")))->toEqual(0)
    expect(
      Background.refuse(payload(~background=true, ~timeout=600000., "mise run check")),
    )->toEqual(0)
  })
})
