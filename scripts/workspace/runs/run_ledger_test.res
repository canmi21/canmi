open Testing

let home = Node.mkdtempSync(Node.join([Node.cwd(), ".runs-home-"]))
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
  afterEach(() => Node.rmSync(Ledger.sessions(), {recursive: true, force: true}))
  [
    ("commit message", "jj commit -m 'x; mise run //:job register seat ghost'"),
    ("search pattern", "rg 'a|mise run //:job register seat ghost' docs"),
  ]->Array.forEach(((kind, command)) => {
    test(
      `ignores registration text in a ${kind}`,
      () => {
        Run_ledger.observe(payload(command))
        // Quoted separators must not turn argument text into a registration.
        expect(Node.existsSync(Node.join([Ledger.sessions(), "ghost.json"])))->toEqual(false)
        Ledger.registerSession(~role="seat", ~name="ghost", ~transcript=Some("/original.jsonl"))
        Run_ledger.observe(payload(command))
        expect(Watchdog.registered()[0]->Option.flatMap(one => one.transcript))->toEqual(
          Some("/original.jsonl"),
        )
      },
    )
  })

  test("registers past what a shell takes for itself", () => {
    [
      "mise run //:job register seat quiet </dev/null 2>&1",
      "mise run //:job register seat quiet &>/dev/null",
      "mise run //:job register seat quiet>/dev/null",
      "mise run //:job register seat quiet > /dev/null",
      "mise run //:job register seat quiet &",
      "(mise run //:job register seat quiet)",
      "mise run //:job register seat quiet # note",
    ]->Array.forEach(
      command => {
        Run_ledger.observe(payload(command))
        expect((command, Watchdog.registered()->Array.map(one => one.name)))->toEqual((
          command,
          ["quiet"],
        ))
        Node.rmSync(Ledger.sessions(), {recursive: true, force: true})
      },
    )
    Run_ledger.observe(payload("mise run //:job register seat quiet >/dev/null --thread trial"))
    expect(Watchdog.registered()[0]->Option.flatMap(one => one.thread))->toEqual(Some("trial"))
  })

  test("registers past a leading assignment", () => {
    Run_ledger.observe(payload("FOO=1 mise run //:job register advisor assigned"))
    // An assignment does not change which program runs the registration.
    expect(Watchdog.registered()[0]->Option.map(one => one.name))->toEqual(Some("assigned"))
  })

  [
    (
      "complete thread word",
      "mise run //:job register seat scoped --thread trial_2",
      Some("trial_2"),
    ),
    (
      "thread in another segment",
      "rg --thread elsewhere docs; mise run job register seat scoped",
      None,
    ),
    (
      "transcript in another segment",
      "rg --transcript /other docs; mise run //:job register seat scoped",
      None,
    ),
    (
      "quoted transcript text",
      "mise run //:job register seat scoped; rg 'mentions --transcript' docs",
      None,
    ),
  ]->Array.forEach(((kind, command, thread)) => {
    test(
      `reads registration flags from its own words with ${kind}`,
      () => {
        Run_ledger.observe(payload(command))
        // Flags belong to the registration segment and keep their complete values.
        expect(Watchdog.registered()[0]->Option.flatMap(one => one.transcript))->toEqual(
          Some("/t.jsonl"),
        )
        expect(Watchdog.registered()[0]->Option.flatMap(one => one.thread))->toEqual(thread)
      },
    )
  })

  test("records a read of a finished job's output, and not of a running one's", () => {
    Ledger.started(job("20261102-000000-abcd"))
    Run_ledger.observe(payload(~file=Ledger.outputOf("20261102-000000-abcd"), "ls"))
    expect(Ledger.find("20261102-000000-abcd")->Option.flatMap(job => job.read))->toEqual(None)
    Ledger.ended(~id="20261102-000000-abcd", ~status=0, ~at=5.)
    Run_ledger.observe(payload(~file=Ledger.outputOf("20261102-000000-abcd"), "ls"), ~at=9.)
    expect(Ledger.find("20261102-000000-abcd")->Option.mapOr(false, Ledger.wasRead))->toEqual(true)
  })

  test("records command reads through tilde and HOME as through an absolute path", () => {
    let user = Node.env->Dict.get("HOME")->Option.getOr("")
    let relative = home->String.slice(~start=user->String.length)
    ["~" ++ relative, "$HOME" ++ relative, home]->Array.forEachWithIndex(
      (prefix, index) => {
        let id = `20261102-000000-${Int.toString(index)}`
        Ledger.started(job(id))
        Ledger.ended(~id, ~status=0, ~at=5.)
        let path = `${prefix}/outputs/${id}.log`
        expect(Run_ledger.outputsIn(`cat ${path}`))->toEqual([Ledger.outputOf(id)])
        Run_ledger.observe(payload(`cat ${path}`), ~at=9.)
        expect(Ledger.find(id)->Option.mapOr(false, Ledger.wasRead))->toEqual(true)
      },
    )
  })

  test("names a registering session's transcript, and leaves one named by hand alone", () => {
    let names = () => Node.existsSync(Ledger.sessions()) ? Node.readdir(Ledger.sessions()) : []
    Run_ledger.observe(payload("mise run //:job register seat lane-one --transcript /x"))
    Run_ledger.observe(payload("cat <<'E'\nmise run //:job register seat in-a-heredoc\nE"))
    Run_ledger.observe(payload("rg 'mise run //:job register seat in-a-quote' docs"))
    expect(names())->toEqual([])
    Run_ledger.observe(payload("mise run //:job register integrator infra"))
    expect(names())->toEqual(["infra.json"])
    expect(Watchdog.registered()[0]->Option.flatMap(one => one.transcript))->toEqual(
      Some("/t.jsonl"),
    )
    Run_ledger.observe(payload("mise run //:job register integrator infra --thread trial"))
    expect(Watchdog.registered()[0]->Option.flatMap(one => one.thread))->toEqual(Some("trial"))
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
