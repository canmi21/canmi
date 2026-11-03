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
