open Testing

let job = (
  ~id="a",
  ~pid=1,
  ~started=0.,
  ~ended=?,
  ~status=?,
  ~read=?,
  ~limit=?,
  ~quiet=false,
  (),
): Ledger.job => {
  id,
  by: "b",
  session: "s",
  command: "c",
  cwd: "/",
  pid,
  started,
  output: "/o",
  limit,
  quiet,
  ended,
  status,
  read,
}

let look = (~jobs=[], ~sessions=[], ~said=[], ~now, ~alive=_ => true, ~moved=_ => None) =>
  Watchdog.owed(~jobs, ~sessions, ~said, ~now, ~alive, ~moved)->Array.map(found =>
    found.says->String.split(" ")->Array.getUnsafe(0)
  )

describe("the watchdog", () => {
  test("says an advisor with no readable transcript to its superior once", () => {
    [None, Some("/missing")]->Array.forEach(
      transcript => {
        let session: Watchdog.session = {name: "advisor", role: "advisor", transcript, thread: None}
        let found = Watchdog.owed(
          ~jobs=[],
          ~sessions=[session],
          ~said=[],
          ~now=0.,
          ~alive=_ => true,
          ~moved=_ => None,
        )
        expect(found->Array.map(one => one.key))->toEqual(["unwatched:advisor"])
        expect((found->Array.getUnsafe(0)).says->String.includes("unwatched to=advisor"))->toEqual(
          true,
        )
        expect(look(~sessions=[session], ~said=["unwatched:advisor"], ~now=1000.))->toEqual([])
      },
    )
  })
  test("says an end nobody read after its limit, and only then", () => {
    let ended = job(~ended=1000., ~status=0, ())
    expect(look(~jobs=[ended], ~now=30000.))->toEqual([])
    expect(look(~jobs=[ended], ~now=62000.))->toEqual(["unread"])
    expect(look(~jobs=[{...ended, read: Some(2000.)}], ~now=62000.))->toEqual([])
  })

  test("says a job whose process is gone with no end", () => {
    expect(look(~jobs=[job()], ~now=1000., ~alive=_ => false))->toEqual(["died"])
  })

  test("says a live job's silence unless it asked to be quiet", () => {
    expect(look(~jobs=[job(~started=0., ())], ~now=61000.))->toEqual(["silent"])
    expect(look(~jobs=[job(~quiet=true, ())], ~now=61000.))->toEqual([])
    expect(look(~jobs=[job()], ~now=61000., ~moved=_ => Some(60000.)))->toEqual([])
  })

  test("says a job past its limit", () => {
    expect(look(~jobs=[job(~limit=10., ())], ~now=11000., ~moved=_ => Some(11000.)))->toEqual([
      "over",
    ])
  })

  test("says each thing once", () => {
    let found = Watchdog.owed(
      ~jobs=[job()],
      ~sessions=[],
      ~said=[],
      ~now=1000.,
      ~alive=_ => false,
      ~moved=_ => None,
    )
    let said = found->Array.map(one => one.key)
    expect(look(~jobs=[job()], ~said, ~now=2000., ~alive=_ => false))->toEqual([])
  })

  test("says a silent session to its superior, and notifies for a supervisor alone", () => {
    let session = (role): Watchdog.session => {
      name: "n",
      role,
      transcript: Some("/t"),
      thread: None,
    }
    let moved = _ => Some(0.)
    let found = role =>
      Watchdog.aboutSession(session(role), ~now=1800. *. 1000., ~moved)->Array.map(
        one => (
          one.says->String.includes(`to=${role == "integrator" ? "supervisor" : "advisor"}`),
          one.notify,
        ),
      )
    expect(found("integrator"))->toEqual([(true, false)])
    expect(found("supervisor"))->toEqual([(true, true)])
    expect(Watchdog.aboutSession(session("supervisor"), ~now=1000., ~moved))->toEqual([])
  })
})

describe("a session's context", () => {
  let session = (role): Watchdog.session => {
    name: "n",
    role,
    transcript: Some("/t"),
    thread: None,
  }
  let tokens = share => (Delegation.contextWindowTokens->Int.toFloat *. share)->Float.toInt
  let owedFor = (~role="advisor", ~said=[], outcome) =>
    Watchdog.owed(
      ~jobs=[],
      ~sessions=[session(role)],
      ~said,
      ~now=0.,
      ~alive=_ => true,
      ~moved=_ => Some(0.),
      ~contextOf=_ => Some(outcome),
    )->Array.filter(one => one.says->String.startsWith("context "))

  let held = share => Context.Read({tokens: tokens(share), compactions: 1})

  test("tells an advisor past the share it is due to be replaced, once", () => {
    let over = owedFor(held(Delegation.advisorReplacedFrom +. 0.01))
    expect(over->Array.length)->toEqual(1)
    expect((over->Array.getUnsafe(0)).says->String.includes("advisor-replaced"))->toEqual(true)
    let keys = over->Array.map(one => one.key)
    expect(owedFor(~said=keys, held(Delegation.advisorReplacedFrom +. 0.02)))->toEqual([])
  })

  test("names an integrator or the supervisor past its share to both, once per crossing", () => {
    let integrator = owedFor(~role="integrator", held(0.86))
    expect(integrator->Array.length)->toEqual(1)
    let says = (integrator->Array.getUnsafe(0)).says
    expect(says->String.startsWith("context to=supervisor,advisor integrator n"))->toEqual(true)
    expect(says->String.includes("context-reported"))->toEqual(true)
    let keys = integrator->Array.map(one => one.key)
    expect(owedFor(~role="integrator", ~said=keys, held(0.9)))->toEqual([])
    let compacted = Context.Read({tokens: tokens(0.86), compactions: 2})
    expect(owedFor(~role="integrator", ~said=keys, compacted)->Array.length)->toEqual(1)
    expect(owedFor(~role="integrator", held(0.84)))->toEqual([])
    expect(owedFor(~role="supervisor", held(0.76))->Array.length)->toEqual(1)
    expect(owedFor(~role="supervisor", held(0.74)))->toEqual([])
  })

  test("says nothing for an advisor under the share, another role or a failed read", () => {
    expect(owedFor(held(Delegation.advisorReplacedFrom -. 0.01)))->toEqual([])
    expect(owedFor(~role="seat", held(0.95)))->toEqual([])
    expect(owedFor(Unreadable("no transcript at the path")))->toEqual([])
  })

  test("writes a line with the figures, and a failed read as unreadable", () => {
    let line = outcome => Watchdog.contextLine(session("advisor"), outcome, ~now=0.)
    let held = line(Read({tokens: 250000, compactions: 3}))
    expect(held->String.includes("25% of the window, 3 compactions"))->toEqual(true)
    expect(line(Unreadable("why"))->String.endsWith("unreadable: why"))->toEqual(true)
  })
})

describe("a thread's figures", () => {
  let seat = (name, ~tooling=false, at): Figures.record => Seat({name, tooling, at})

  test("count seat time and landings from the last green, tooling over the whole", () => {
    let figures = Figures.figuresOf(
      [
        seat("a", 0.),
        Seated({name: "a", at: 600000.}),
        Green({step: "one", at: 600000.}),
        seat("b", ~tooling=true, 600000.),
        Landed({repository: "r", commit: "c", subject: "s", at: 700000.}),
      ],
      ~now=1200000.,
    )
    expect(figures.step)->toEqual(Some("one"))
    expect(figures.seatSeconds)->toEqual(600.)
    expect(figures.landings)->toEqual(1)
    expect(figures.toolingShare)->toEqual(0.5)
    expect(figures.flagged)->toEqual(true)
  })

  test("flag nothing at or under the share, and name no step before one is green", () => {
    let figures = Figures.figuresOf([seat("a", 0.)], ~now=1000.)
    expect(figures.step)->toEqual(None)
    expect(figures.flagged)->toEqual(false)
    expect(Figures.shown("t", figures)->String.includes("no step green yet"))->toEqual(true)
  })
})

describe("idle integrators", () => {
  let integrator: Watchdog.session = {
    name: "i",
    role: "integrator",
    transcript: Some("/sessions/s.jsonl"),
    thread: Some("t"),
  }
  let supervisor: Watchdog.session = {
    name: "v",
    role: "supervisor",
    transcript: Some("/sessions/v.jsonl"),
    thread: Some("t"),
  }
  let ready: array<(Charter.step, float)> = [({id: "1", after: []}, 0.)]
  let idle = (
    ~now=300000.,
    ~jobs=[],
    ~sessions=[integrator],
    ~ready=ready,
    ~said=[],
    ~alive=_ => true,
    ~moved=_ => Some(0.),
    ~seats=_ => [],
    ~openSeats=[],
    ~steps=[],
  ) =>
    Watchdog.aboutIdle(
      ~thread="t",
      ~ready,
      ~sessions,
      ~jobs,
      ~now,
      ~alive,
      ~moved,
      ~seats,
      ~openSeats,
      ~steps,
      ~said,
    )

  test("an integrator whose turn cannot be read is not idle, and its total leaves it out", () => {
    expect(idle(~moved=_ => None))->toEqual([])
    expect(idle(~sessions=[{...integrator, transcript: None}]))->toEqual([])
  })

  test("an open seat of its own keeps it busy, another session's does not", () => {
    let own =
      integrator.transcript->Option.mapOr(
        "",
        path => Node.basename(path)->String.replaceRegExp(/\.jsonl$/, ""),
      )
    expect(idle(~openSeats=[own]))->toEqual([])
    expect(idle(~openSeats=["another"])->Array.length)->toEqual(1)
  })

  test("waits 300 seconds and says each stretch once", () => {
    expect(idle(~now=299000.))->toEqual([])
    let found = idle()
    expect(found->Array.map(one => one.key))->toEqual(["idle:i:0"])
    expect((found->Array.getUnsafe(0)).says)->toEqual(
      "idle to=supervisor integrator i has had no job, no seat and no turn for 300 s while thread t has ready step(s) 1; 0 of 1 integrators busy",
    )
    let said = found->Array.map(one => one.key)
    expect(idle(~said, ~now=400000.))->toEqual([])
    expect(
      idle(~said, ~now=400000., ~moved=_ => Some(100000.))->Array.map(one => one.key),
    )->toEqual(["idle:i:100000"])
  })

  test("counts live jobs, seats and turns as work, but no dead pid", () => {
    expect(idle(~jobs=[job()]))->toEqual([])
    expect(idle(~jobs=[job()], ~alive=_ => false)->Array.length)->toEqual(1)
    expect(idle(~seats=_ => [1000.]))->toEqual([])
    expect(idle(~moved=_ => Some(1000.)))->toEqual([])
    expect(idle(~jobs=[job(~ended=1000., ())]))->toEqual([])
    expect(idle(~jobs=[job(~started=1000., ())], ~alive=_ => false))->toEqual([])
  })

  test("uses the earliest ready step and only this thread's integrators", () => {
    expect(idle(~ready=[]))->toEqual([])
    expect(idle(~ready=[({Charter.id: "2", after: []}, 1000.)]))->toEqual([])
    let found = idle(
      ~ready=[({Charter.id: "2", after: []}, 1000.), ...ready],
      ~sessions=[integrator, {...integrator, name: "other", thread: Some("other")}],
    )
    expect(
      (found->Array.getUnsafe(0)).says->String.endsWith("2, 1; 0 of 1 integrators busy"),
    )->toEqual(true)
    let worker = {...integrator, name: "worker", transcript: Some("/worker.jsonl")}
    let found = idle(~sessions=[integrator, worker], ~jobs=[{...job(), session: "worker"}])
    expect((found->Array.getUnsafe(0)).says->String.endsWith("1 of 2 integrators busy"))->toEqual(
      true,
    )
  })

  test(
    "escalates past the allowance, whatever a Monitor writes to the supervisor's transcript",
    () => {
      let sessions = [integrator, supervisor]
      expect(idle(~sessions, ~now=599000.)->Array.length)->toEqual(1)
      let found = idle(~sessions, ~now=600000.)
      expect(found->Array.map(one => one.key))->toEqual(["idle:i:0", "idle-supervisor:v:i:0"])
      expect((found->Array.getUnsafe(1)).says)->toEqual(
        "idle to=advisor supervisor v has left integrator i idle for 300 s past its report, while thread t has 1 ready step(s) and 0 busy integrators",
      )
      expect(idle(~sessions, ~now=600000., ~said=found->Array.map(one => one.key)))->toEqual([])
      expect(
        idle(
          ~sessions,
          ~now=600000.,
          ~moved=path => Some(path == "/sessions/v.jsonl" ? 599900. : 0.),
        )->Array.length,
      )->toEqual(2)
      expect(
        idle(~sessions=[integrator, {...supervisor, transcript: None}], ~now=600000.)->Array.length,
      )->toEqual(2)
    },
  )

  test("escalates where the other integrator only takes turns, holding no step", () => {
    let other = {...integrator, name: "j", transcript: Some("/sessions/j.jsonl")}
    let found = idle(
      ~sessions=[integrator, other, supervisor],
      ~now=600000.,
      ~moved=path => Some(path == "/sessions/j.jsonl" ? 599000. : 0.),
    )
    // j only takes turns, holding no step, so the step is free and the advisor is told.
    expect(found->Array.map(one => one.key))->toEqual(["idle:i:0", "idle-supervisor:v:i:0"])
  })

  test("writes idle to the real event file and reads seat move times", () => {
    let root = Node.mkdtempSync(Node.join([Node.tmpdir(), "watchdog-idle-"]))
    let saved = ["RUNS_HOME", "THREADS_HOME"]->Array.map(key => (key, Node.env->Dict.get(key)))
    Node.env->Dict.set("RUNS_HOME", Node.join([root, "runs"]))
    Node.env->Dict.set("THREADS_HOME", Node.join([root, "threads"]))
    let cleanup = () => {
      saved->Array.forEach(
        ((key, value)) =>
          switch value {
          | Some(value) => Node.env->Dict.set(key, value)
          | None => Node.env->Dict.delete(key)
          },
      )
      Node.rmSync(root, {recursive: true, force: true})
    }
    try {
      Node.mkdirAll(Figures.directory("t"))
      Node.mkdirAll(Node.join([Figures.directory("broken"), "charter.md"]))
      Node.mkdirAll(Figures.directory("older"))
      Node.writeFileSync(Node.join([Figures.directory("older"), "charter.md"]), "1. older step\n")
      Node.writeFileSync(
        Node.join([Figures.directory("t"), "charter.md"]),
        "1. work\n  after: none\n",
      )
      let transcript = Node.join([root, "s.jsonl"])
      Node.writeFileSync(
        transcript,
        `{"type":"assistant","timestamp":"2020-01-01T00:00:00.000Z"}\n`,
      )
      Ledger.registerSession(
        ~role="integrator",
        ~name="i",
        ~thread=Some("t"),
        ~transcript=Some(transcript),
      )
      let last = Watchdog.moved(transcript)->Option.getOrThrow
      let now = last +. 300000.
      Watchdog.look(~now, ~notify=_ => true)->ignore
      Watchdog.look(~now, ~notify=_ => true)->ignore
      let lines =
        Node.readFileSync(Ledger.events())
        ->String.split("\n")
        ->Array.filter(line => line->String.includes("idle to=supervisor integrator i"))
      expect(lines->Array.length)->toEqual(1)
      let limit = Delegation.seatOpenSeconds->Int.toFloat *. 1000.
      let owner = {...integrator, transcript: Some(transcript)}
      let seatAt = now -. limit
      let seat = at =>
        Ledger.line([
          ("kind", JSON.String("seat")),
          ("name", JSON.String("open")),
          ("session", JSON.String("s")),
          ("at", JSON.Number(at)),
        ])
      let owed = () =>
        Watchdog.idleOwed(~sessions=[owner], ~jobs=[], ~said=[], ~now)->Array.filter(
          one => one.key->String.startsWith("idle:i:"),
        )
      Node.writeFileSync(Figures.recordsFile("t"), seat(seatAt +. 1.))
      expect(owed()->Array.length)->toEqual(0)
      Node.writeFileSync(Figures.recordsFile("t"), seat(seatAt))
      expect(owed()->Array.length)->toEqual(1)
      Node.writeFileSync(Figures.recordsFile("t"), seat(seatAt -. 1.))
      expect(owed()->Array.length)->toEqual(1)
      let directory = Node.join([root, "s", "subagents"])
      Node.mkdirAll(directory)
      Node.writeFileSync(Node.join([directory, "seat.jsonl"]), "")
      Node.writeFileSync(Node.join([directory, "ignored.txt"]), "")
      Node.mkdirAll(Node.join([directory, "ignored.jsonl"]))
      expect(Watchdog.seats({...integrator, transcript: Some(transcript)})->Array.length)->toEqual(
        1,
      )
    } catch {
    | error =>
      cleanup()
      throw(error)
    }
    cleanup()
  })
})

describe("an integrator with no step free for it", () => {
  let integrator: Watchdog.session = {
    name: "i",
    role: "integrator",
    transcript: Some("/sessions/s.jsonl"),
    thread: Some("t"),
  }
  let other: Watchdog.session = {...integrator, name: "j", transcript: Some("/sessions/j.jsonl")}
  let steps: array<Charter.step> = [{id: "1", after: []}]
  let held: array<(Charter.step, float)> = [({id: "1", after: []}, 0.)]
  let unassigned = (
    ~now=300000.,
    ~ready=[],
    ~sessions=[integrator],
    ~steps=steps,
    ~said=[],
    ~moved=_ => Some(0.),
    ~jobs=[],
  ) =>
    Watchdog.aboutIdle(
      ~thread="t",
      ~ready,
      ~sessions,
      ~jobs,
      ~now,
      ~alive=_ => true,
      ~moved,
      ~seats=_ => [],
      ~steps,
      ~said,
    )

  test("tells the advisor at 300 seconds and not at 299, with no step ready", () => {
    expect(unassigned(~now=299000.))->toEqual([])
    let found = unassigned()
    expect(found->Array.map(one => one.key))->toEqual(["idle-unassigned:i:0"])
    expect((found->Array.getUnsafe(0)).says)->toEqual(
      "idle to=advisor integrator i has had no job, no seat and no turn for 300 s, and no step of thread t is free for it: 0 ready, 0 of 1 integrators busy",
    )
  })

  test("a turn alone holds no step, so a ready step another only chats beside is free", () => {
    let found = unassigned(
      ~ready=held,
      ~sessions=[integrator, other],
      ~moved=path => Some(path == "/sessions/j.jsonl" ? 299000. : 0.),
    )
    expect(found->Array.map(one => one.key))->toEqual(["idle:i:0"])
  })

  test("tells it where the one ready step is held by another busy integrator", () => {
    let found = unassigned(
      ~ready=held,
      ~sessions=[integrator, other],
      ~moved=path => Some(path == "/sessions/j.jsonl" ? 299000. : 0.),
      ~jobs=[{...job(), session: "j", started: 290000.}],
    )
    expect(found->Array.map(one => one.key))->toEqual(["idle:i:0", "idle-unassigned:i:0"])
    expect(
      (found->Array.getUnsafe(1)).says->String.endsWith("1 ready, 1 of 2 integrators busy"),
    )->toEqual(true)
  })

  test("is silent where ready steps outnumber busy integrators", () => {
    let found = unassigned(~ready=held)
    expect(found->Array.map(one => one.key))->toEqual(["idle:i:0"])
  })

  test("says each stretch once, from the integrator's own last activity", () => {
    let said = unassigned()->Array.map(one => one.key)
    expect(unassigned(~said, ~now=400000.))->toEqual([])
    expect(
      unassigned(~said, ~now=400000., ~moved=_ => Some(100000.))->Array.map(one => one.key),
    )->toEqual(["idle-unassigned:i:100000"])
  })

  test("says nothing for a thread with no steps", () => {
    expect(unassigned(~steps=[]))->toEqual([])
  })
})
