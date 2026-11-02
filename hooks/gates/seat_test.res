open Testing

let directory = Node.mkdtempSync(Node.join([Node.tmpdir(), "seat-gate-"]))
let write = (name, text) => {
  let path = Node.join([directory, name])
  Node.writeFileSync(path, text)
  path
}

let one = write("one.txt", "Intro\nResult: a gate\nVerify: its tests pass\nMore\n")
let none = write("none.txt", "Do the work\nVerify: it passes\n")
let two = write("two.txt", "Result: a\nResult: b\nVerify: both\n")
let missing = Node.join([directory, "absent.txt"])

let agent = (kind, prompt): Payload.t =>
  Dict.fromArray([
    ("tool_name", JSON.String("Agent")),
    (
      "tool_input",
      JSON.Object(
        Dict.fromArray([("subagent_type", JSON.String(kind)), ("prompt", JSON.String(prompt))]),
      ),
    ),
  ])

let bash = (command): Payload.t =>
  Dict.fromArray([
    ("tool_name", JSON.String("Bash")),
    ("cwd", JSON.String(directory)),
    ("tool_input", JSON.Object(Dict.fromArray([("command", JSON.String(command))]))),
  ])

describe("a brief", () => {
  test("holds exactly one result and one verification", () => {
    expect(Seat.faults("Result: x\nVerify: y"))->toEqual([])
    expect(Seat.faults("Verify: y")->Array.length)->toBe(1)
    expect(Seat.faults("x")->Array.length)->toBe(2)
    expect(Seat.faults("Result: a\nResult: b\nVerify: y")->Array.length)->toBe(1)
    expect(Seat.faults("Result: a\nVerify: y\nVerify: z")->Array.length)->toBe(1)
    expect(Seat.faults("Not a Result: line\nVerify: y")->Array.length)->toBe(1)
  })
})

describe("an Agent dispatch of an implementer", () => {
  test("passes with one result and one verification in the prompt", () => {
    expect(Seat.refuse(agent("implementer", "Result: a\nVerify: b")))->toBe(0)
    expect(Seat.refuse(agent("refactorer", "Result: a\nVerify: b")))->toBe(0)
  })

  test("is refused with none or several of either", () => {
    expect(Seat.refuse(agent("implementer", "Do the thing")))->toBe(2)
    expect(Seat.refuse(agent("implementer", "Result: a\nVerify: b\nVerify: c")))->toBe(2)
    expect(Seat.refuse(agent("refactorer", "Result: a\nResult: b\nVerify: c")))->toBe(2)
  })

  test("is judged by the brief file its prompt only points at", () => {
    expect(Seat.refuse(agent("implementer", `Your brief is the file ${one}. Follow it.`)))->toBe(0)
    expect(Seat.refuse(agent("implementer", `Your brief is the file ${none}`)))->toBe(2)
    expect(Seat.refuse(agent("implementer", `Your brief is the file ${two}`)))->toBe(2)
  })

  test("is refused where the brief file cannot be read", () => {
    expect(Seat.refuse(agent("implementer", `Your brief is the file ${missing}`)))->toBe(2)
  })
})

describe("an Agent dispatch of another type", () => {
  test("passes untouched", () => {
    ["reviewer", "scout", "scribe", "Explore", "general-purpose"]->Array.forEach(
      kind => expect(Seat.refuse(agent(kind, "Do the thing")))->toBe(0),
    )
  })
})

describe("a codex exec of an implementer", () => {
  test("passes with a brief file holding one result and one verification", () => {
    expect(Seat.refuse(bash(`MONOFLAKE_ROLE=implementer codex exec -C lane - < ${one}`)))->toBe(0)
    expect(Seat.refuse(bash(`MONOFLAKE_ROLE=refactorer codex exec - <${one}`)))->toBe(0)
    expect(Seat.refuse(bash(`cd lane && MONOFLAKE_ROLE=implementer codex exec - < one.txt`)))->toBe(
      0,
    )
    expect(Seat.refuse(bash(`bash -c 'MONOFLAKE_ROLE=implementer codex exec - < ${one}'`)))->toBe(0)
  })

  test("is refused for a brief with none or several of either", () => {
    expect(Seat.refuse(bash(`MONOFLAKE_ROLE=implementer codex exec - < ${none}`)))->toBe(2)
    expect(Seat.refuse(bash(`MONOFLAKE_ROLE=implementer codex exec - < ${two}`)))->toBe(2)
    expect(Seat.refuse(bash(`bash -c 'MONOFLAKE_ROLE=implementer codex exec - < ${two}'`)))->toBe(2)
  })

  test("is refused with no brief file or an unreadable one", () => {
    expect(Seat.refuse(bash("MONOFLAKE_ROLE=implementer codex exec 'do it'")))->toBe(2)
    expect(Seat.refuse(bash(`MONOFLAKE_ROLE=implementer codex exec - < ${missing}`)))->toBe(2)
    expect(Seat.refuse(bash("cat b | MONOFLAKE_ROLE=implementer codex exec -")))->toBe(2)
  })

  test("passes where the command names the escape", () => {
    expect(Seat.refuse(bash("SKIP=seat MONOFLAKE_ROLE=implementer codex exec 'do it'")))->toBe(0)
  })
})

describe("any other command", () => {
  test("passes untouched", () => {
    expect(Seat.refuse(bash("codex exec 'do it'")))->toBe(0)
    expect(Seat.refuse(bash("MONOFLAKE_ROLE=reviewer codex exec 'do it'")))->toBe(0)
    expect(Seat.refuse(bash("MONOFLAKE_ROLE=implementer codex login")))->toBe(0)
    expect(Seat.refuse(bash("echo 'MONOFLAKE_ROLE=implementer codex exec x'")))->toBe(0)
    expect(Seat.refuse(bash("ls")))->toBe(0)
  })
})

describe("a brief naming a lane", () => {
  test("is refused where the lane is stale, and an absent lane is passed over", () => {
    let base = Lane.baseOf(Registry.root)
    let there = Node.join([Lane_state.lanes(base), "stale-probe-test"])
    let exists = path => path == there
    expect(Seat.lanesIn("in lanes/stale-probe-test/monoflake/platform", ~exists))->toEqual([
      "stale-probe-test",
    ])
    expect(Seat.lanesIn("in lanes/other/monoflake/platform", ~exists))->toEqual([])
    expect(Seat.staleFaults("in lanes/other/x", ~exists, ~stale=_ => true))->toEqual([])
  })
})
