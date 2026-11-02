open Testing

let home = Node.mkdtempSync(Node.join([Node.tmpdir(), "runs-home-"]))
let threads = Node.mkdtempSync(Node.join([Node.tmpdir(), "threads-home-"]))

Node.env->Dict.set("RUNS_HOME", home)
Node.env->Dict.set("THREADS_HOME", threads)

let payload = (~transcript="/t.jsonl", ~file=?, command): Payload.t =>
  Dict.fromArray([
    ("transcript_path", JSON.String(transcript)),
    (
      "tool_input",
      JSON.Object(
        Dict.fromArray(
          Array.concat(
            [("command", JSON.String(command))],
            file->Option.mapOr([], file => [("file_path", JSON.String(file))]),
          ),
        ),
      ),
    ),
  ])

let job = (id): Ledger.job => {
  id,
  by: "b",
  session: "s",
  command: "c",
  cwd: "/",
  pid: 1,
  started: 0.,
  output: Ledger.outputOf(id),
  limit: None,
  quiet: false,
  ended: None,
  status: None,
  read: None,
}

describe("the hook's view of the ledger", () => {
  test("records a read of a finished job's output, and not of a running one's", () => {
    Ledger.started(job("20261102-000000-abcd"))
    Run_ledger.observe(payload(~file=Ledger.outputOf("20261102-000000-abcd"), "ls"))
    expect(Ledger.find("20261102-000000-abcd")->Option.flatMap(job => job.read))->toEqual(None)
    Ledger.ended(~id="20261102-000000-abcd", ~status=0, ~at=5.)
    Run_ledger.observe(payload(~file=Ledger.outputOf("20261102-000000-abcd"), "ls"), ~at=9.)
    expect(Ledger.find("20261102-000000-abcd")->Option.mapOr(false, Ledger.wasRead))->toEqual(true)
  })

  test("names a registering session's transcript, and leaves one named by hand alone", () => {
    let names = () => Node.existsSync(Ledger.sessions()) ? Node.readdir(Ledger.sessions()) : []
    Run_ledger.observe(payload("mise run //:job register seat lane-one --transcript /x"))
    expect(names())->toEqual([])
    Run_ledger.observe(payload("mise run //:job register integrator infra"))
    expect(names())->toEqual(["infra.json"])
    expect(Watchdog.registered()[0]->Option.flatMap(one => one.transcript))->toEqual(
      Some("/t.jsonl"),
    )
    Node.rmSync(Ledger.sessions(), {recursive: true, force: true})
  })
})

describe("one look of the watchdog", () => {
  test("survives a stray file among the threads, and tries a failed notice again", () => {
    Node.writeFileSync(Node.join([threads, ".DS_Store"]), "")
    Node.mkdirAll(Figures.directory("real"))
    Figures.add(
      "real",
      [("kind", JSON.String("seat")), ("name", JSON.String("a")), ("at", JSON.Number(0.))],
    )
    let transcript = Node.join([home, "transcript"])
    Node.writeFileSync(transcript, "")
    Ledger.registerSession(~role="supervisor", ~name="s", ~transcript=Some(transcript))
    let later = Date.now() +. 7200000.
    let tries = ref(0)
    let failing = _ => {
      tries := tries.contents + 1
      false
    }
    Watchdog.look(~now=later, ~notify=failing)->ignore
    Watchdog.look(~now=later, ~notify=_ => true)->ignore
    Watchdog.look(~now=later, ~notify=failing)->ignore
    expect(tries.contents)->toEqual(1)
    let events = Node.readFileSync(Ledger.events())
    expect(events->String.includes("figures to=advisor thread real"))->toEqual(true)
    expect(Node.existsSync(Figures.shownFile("real")))->toEqual(true)
    Node.rmSync(Ledger.sessions(), {recursive: true, force: true})
  })

  test("says a session it cannot watch, once", () => {
    Ledger.registerSession(~role="integrator", ~name="blind", ~transcript=None)
    Watchdog.look(~notify=_ => true)->ignore
    Watchdog.look(~notify=_ => true)->ignore
    let said =
      Node.readFileSync(Ledger.events())
      ->String.split("\n")
      ->Array.filter(line => line->String.includes("unwatched"))
    expect(said->Array.length)->toEqual(1)
    Node.rmSync(Ledger.sessions(), {recursive: true, force: true})
  })
})

describe("the temporary homes", () => {
  test("are removed", () => {
    Node.rmSync(home, {recursive: true, force: true})
    Node.rmSync(threads, {recursive: true, force: true})
    expect(Node.existsSync(home))->toEqual(false)
  })
})
