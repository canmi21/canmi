open Testing

let payload = (command): Payload.t =>
  Dict.fromArray([("tool_input", JSON.Object(Dict.fromArray([("command", JSON.String(command))])))])

let reading = (~five, ~seven) =>
  `{"claude":{"fiveHourPercent":1},"codex":{"fiveHourPercent":${Int.toString(
      five,
    )},"sevenDayPercent":${Int.toString(
      seven,
    )},"fiveHourReset":"2026-11-02T03:15:05.000Z","sevenDayReset":"2026-11-04T14:17:08.000Z"}}`

describe("a codex exec", () => {
  test("is found however it is run", () => {
    [
      "codex exec --full-auto 'do it'",
      "codex e x",
      "codex review",
      "codex -m gpt exec x",
      "cd lane && codex exec x",
      "env A=1 nohup codex exec x",
      "bash -c 'codex exec x'",
      "bash --norc -c 'codex exec x'",
      "bash -lc \"codex review\"",
      "(codex exec x)",
      "(cd a && codex exec y) &",
      "{ codex exec x; }",
      "if true; then codex exec x; fi",
      "for i in 1 2; do codex e x; done",
      "codex exec x &",
      "mise exec -- codex exec x",
      "echo $(codex exec x)",
      "cat <<EOF\nplan\nEOF\ncodex exec x",
    ]->Array.forEach(
      command => expect((command, Codex_usage.runs(command)))->toEqual((command, true)),
    )
  })

  test("is not found in a word, a quote, a body, a help request or another subcommand", () => {
    [
      "codex login",
      "codex --help exec",
      "codex mcp add exec",
      "codex --version",
      "echo 'codex exec x'",
      "grep codex exec.log",
      "cat <<EOF\ncodex exec x\nEOF",
      "cat <<'EOF'\n(codex exec x)\nEOF",
      "bash --norc -c 'ls'",
      "ls > codex.log 2>&1 &",
      "mise exec -- ls",
    ]->Array.forEach(
      command => expect((command, Codex_usage.runs(command)))->toEqual((command, false)),
    )
  })

  test("is refused where a window reads 100, saying when it resets", () => {
    expect(Codex_usage.read(reading(~five=100, ~seven=81)))->toEqual(
      Codex_usage.Limited("2026-11-02T03:15:05.000Z"),
    )
    expect(Codex_usage.read(reading(~five=10, ~seven=100)))->toEqual(
      Codex_usage.Limited("2026-11-04T14:17:08.000Z"),
    )
    expect(Codex_usage.read(reading(~five=100, ~seven=100)))->toEqual(
      Codex_usage.Limited("2026-11-04T14:17:08.000Z"),
    )
    // Dates, not strings: a later date with an earlier-sorting text.
    let zones = `{"codex":{"fiveHourPercent":100,"sevenDayPercent":100,"fiveHourReset":"2026-11-02T12:00:00+09:00","sevenDayReset":"2026-11-02T05:00:00-05:00"}}`
    expect(Codex_usage.read(zones))->toEqual(Codex_usage.Limited("2026-11-02T05:00:00-05:00"))
    expect(
      Codex_usage.refuse(payload("codex exec x"), ~measure=() => reading(~five=100, ~seven=1)),
    )->toBe(2)
  })

  test("is let through with quota, with another command, and with an unreadable reading", () => {
    expect(Codex_usage.read(reading(~five=99, ~seven=81)))->toEqual(Codex_usage.Free)
    expect(
      Codex_usage.refuse(payload("codex exec x"), ~measure=() => reading(~five=99, ~seven=1)),
    )->toBe(0)
    expect(Codex_usage.refuse(payload("ls"), ~measure=() => reading(~five=100, ~seven=100)))->toBe(
      0,
    )
    expect(Codex_usage.read(""))->toEqual(Codex_usage.Unknown)
    expect(Codex_usage.read("{\"codex\":null}"))->toEqual(Codex_usage.Unknown)
    expect(Codex_usage.refuse(payload("codex exec x"), ~measure=() => "not json"))->toBe(0)
  })
})
