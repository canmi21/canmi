open Testing

let stall = 30000.
let job = Ledger.fold(`{"kind":"start","id":"a","pid":7,"at":0,"output":"/o"}`)->Array.getUnsafe(0)
let step = (state, text, now) => Watch.step(state, ~text, ~now, ~stall)
let start = () => Watch.start(~now=0., ~stall)

describe("the watcher", () => {
  test("leaves progress and quiet lines in the file", () => {
    expect(Watch.classify("compiling 3 crates"))->toEqual(None)
    let (first, events) = step(start(), "running a\nrunni", 1000.)
    expect(events)->toEqual([])
    expect(first.offset)->toEqual(10)
    let (_, again) = step(first, "running a\nrunning b\n", 2000.)
    expect(again)->toEqual([])
  })

  test("keeps the end patterns for a bare file and reports the end once", () => {
    ["exit: 0", "status=1", "ended: done", "[exited with code 0]"]->Array.forEach(
      line => {
        let (last, told) = step(start(), `built a\n${line}\n`, 1000.)
        expect(told)->toEqual([`ended: ${line}`])
        expect(last.ended)->toEqual(true)
        let (_, again) = step(last, `built a\n${line}\n`, 2000.)
        expect(again)->toEqual([])
      },
    )
  })

  test("waits for complete lines and gathers failures at the model interval", () => {
    let text = "error: first\nfailed second\nfatal third"
    let (first, early) = step(start(), text, 1000.)
    expect(early)->toEqual([])
    let (batch, told) = step(first, text, 30000.)
    expect(told)->toEqual(["failure: 2 new failure lines; error: first"])
    let (more, quiet) = step(batch, text ++ "\n", 31000.)
    expect(quiet)->toEqual([])
    let (waiting, none) = step(more, text ++ "\n", 59000.)
    expect(none)->toEqual([])
    let (last, next) = step(waiting, text ++ "\n", 60000.)
    expect(next)->toEqual(["failure: 1 new failure lines; fatal third"])
    expect(last.failures)->toEqual(3)
    let (_, again) = step(last, text ++ "\n", 90000.)
    expect(again)->toEqual(["stalled: no new line for 59 seconds"])
  })

  test("does not use a custom stall interval as the failure interval", () => {
    let (first, _) = Watch.step(start(), ~text="error: a\n", ~now=1000., ~stall=1000.)
    let (_, events) = Watch.step(first, ~text="error: a\n", ~now=2000., ~stall=1000.)
    expect(events)->toEqual(["stalled: no new line for 1 seconds"])
  })

  test("reports a stall once until the file grows, even by a partial line", () => {
    let (grown, _) = step(start(), "built a\n", 1000.)
    let (quiet, none) = step(grown, "built a\n", 30000.)
    expect(none)->toEqual([])
    let (stalled, told) = step(quiet, "built a\n", 31000.)
    expect(told)->toEqual(["stalled: no new line for 30 seconds"])
    let (_, later) = step(stalled, "built a\n", 90000.)
    expect(later)->toEqual([])
    let (partial, _) = step(stalled, "built a\nx", 91000.)
    let (_, restarted) = step(partial, "built a\nx", 121000.)
    expect(restarted)->toEqual(["stalled: no new line for 30 seconds"])
  })

  test("stalls once on a file that never appears", () => {
    let (quiet, told) = step(start(), "", 30000.)
    expect(told)->toEqual(["stalled: no new line for 30 seconds"])
    let (_, again) = step(quiet, "", 90000.)
    expect(again)->toEqual([])
  })

  test("ignores another job's quoted end and reports the ledger end with totals", () => {
    let text = "[exited with code 1]\nexit: 1\nstatus: 2\nerror: real failure\n"
    let (running, events) = Watch.step(
      start(),
      ~text,
      ~now=1000.,
      ~stall,
      ~job=Some(job),
      ~alive=_ => true,
    )
    expect(events)->toEqual([])
    expect(running.ended)->toEqual(false)
    let done = {...job, ended: Some(2500.), status: Some(3)}
    let (last, told) = Watch.step(
      running,
      ~text,
      ~now=3000.,
      ~stall,
      ~job=Some(done),
      ~alive=_ => false,
    )
    expect(told)->toEqual(["ended: status 3, 2.5 s, 1 failure lines; mise run //:job read a"])
    let (_, again) = Watch.step(last, ~text, ~now=4000., ~stall, ~job=Some(done))
    expect(again)->toEqual([])
  })

  test("keeps failure totals across a missing read and ends without an output marker", () => {
    let (first, _) = Watch.step(
      start(),
      ~text="error: first\n",
      ~now=1000.,
      ~stall,
      ~job=Some(job),
      ~alive=_ => true,
    )
    let (missing, _) = Watch.step(
      first,
      ~text="",
      ~now=2000.,
      ~stall,
      ~job=Some(job),
      ~alive=_ => true,
    )
    let (_, told) = Watch.step(
      missing,
      ~text="error: first\n",
      ~now=3000.,
      ~stall,
      ~job=Some({...job, ended: Some(3000.), status: Some(0)}),
    )
    expect(told)->toEqual(["ended: status 0, 3.0 s, 1 failure lines; mise run //:job read a"])
  })

  test("ends on a missing process but leaves pid zero running", () => {
    let (last, told) = Watch.step(
      start(),
      ~text="",
      ~now=1000.,
      ~stall,
      ~job=Some(job),
      ~alive=_ => false,
    )
    expect(last.ended)->toEqual(true)
    expect(told)->toEqual(["ended: died; mise run //:job read a"])
    let (waiting, none) = Watch.step(
      start(),
      ~text="",
      ~now=1000.,
      ~stall,
      ~job=Some({...job, pid: 0}),
      ~alive=_ => false,
    )
    expect(waiting.ended)->toEqual(false)
    expect(none)->toEqual([])
  })
})
