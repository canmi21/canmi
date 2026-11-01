open Testing

let fixture: Overlap_measure.fixture = {
  rule: "no-irregular-whitespace",
  source: "const value\u00a0= 1;\n",
}
let clean = "const value = 1;\n"
let working: Overlap_measure.tools = {
  format: _ => Ok(clean),
  lint: (_, source) => Ok(source == clean ? 0 : 1),
}

describe("measured formatter overlap", () => {
  test("requires a violation before formatting and none afterward", () => {
    expect(Overlap_measure.measured(fixture, working))->toEqual([])
    expect(Overlap_measure.measured({...fixture, source: clean}, working))->toEqual([
      "no-irregular-whitespace: fixture does not violate the rule",
    ])
    expect(Overlap_measure.measured(fixture, {...working, format: source => Ok(source)}))->toEqual([
      "no-irregular-whitespace: formatter leaves the violation",
    ])
  })

  test("refuses tool failures on both sides of formatting", () => {
    expect(
      Overlap_measure.measured(fixture, {...working, format: _ => Error("unavailable")}),
    )->toEqual(["no-irregular-whitespace: formatter failed unavailable"])
    expect(
      Overlap_measure.measured(fixture, {...working, lint: (_, _) => Error("unavailable")}),
    )->toEqual(["no-irregular-whitespace: linter failed before formatting unavailable"])
    let broken = {...working, lint: (_, source) => source == clean ? Error("unavailable") : Ok(1)}
    expect(Overlap_measure.measured(fixture, broken))->toEqual([
      "no-irregular-whitespace: linter failed after formatting unavailable",
    ])
  })

  test("requires one fixture for every declared overlapping rule", () => {
    expect(Overlap_measure.held(~rules=[fixture.rule], ~samples=[fixture], working))->toEqual([])
    expect(Overlap_measure.held(~rules=[fixture.rule], ~samples=[], working))->toEqual([
      "no-irregular-whitespace: no overlap fixture",
    ])
    expect(
      Overlap_measure.held(~rules=[fixture.rule], ~samples=[fixture, fixture], working),
    )->toEqual(["no-irregular-whitespace: more than one overlap fixture"])
    expect(Overlap_measure.held(~rules=[], ~samples=[fixture], working))->toEqual([
      "no-irregular-whitespace: fixture has no rule in Format.overlapping",
    ])
  })
})

describe("overlap linter evidence", () => {
  let read = text => Overlap_measure.diagnostics(text, ~rule=fixture.rule)

  test("reads the requested rule and a clean result", () => {
    expect(
      read(`{"number_of_files":1,"diagnostics":[{"code":"eslint(no-irregular-whitespace)"}]}`),
    )->toEqual(Ok(1))
    expect(read(`{"number_of_files":1,"diagnostics":[]}`))->toEqual(Ok(0))
  })

  test("refuses skipped files, another rule and malformed reports", () => {
    expect(read(`{"number_of_files":0,"diagnostics":[]}`))->toEqual(
      Error("expected diagnostics for exactly one file"),
    )
    expect(read(`{"number_of_files":1,"diagnostics":[{"code":"eslint(no-debugger)"}]}`))->toEqual(
      Error("unexpected diagnostic"),
    )
    expect(read(`{}`))->toEqual(Error("expected diagnostics for exactly one file"))
    expect(read(`[]`))->toEqual(Error("expected a linter report"))
    expect(read("not JSON"))->toEqual(Error("invalid linter JSON"))
  })
})

describe("installed formatter and linter", () => {
  let scratch = temporaryRoot("overlap-test-")

  test("measures every registered overlap using the installed tools", () => {
    let tools = Overlap_measure.tools(~root=Registry.root, ~scratch=scratch.contents)
    expect(Overlap_measure.held(tools))->toEqual([])
  })

  test("fails a clean fixture and a formatter that preserves the violation", () => {
    let tools = Overlap_measure.tools(~root=Registry.root, ~scratch=scratch.contents)
    expect(Overlap_measure.measured({...fixture, source: clean}, tools))->toEqual([
      "no-irregular-whitespace: fixture does not violate the rule",
    ])
    expect(Overlap_measure.measured(fixture, {...tools, format: source => Ok(source)}))->toEqual([
      "no-irregular-whitespace: formatter leaves the violation",
    ])
  })
})
