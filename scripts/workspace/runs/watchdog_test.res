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
    let session = (role): Watchdog.session => {name: "n", role, transcript: Some("/t")}
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
