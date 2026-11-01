open Testing

let stall = 30000.

describe("the watcher", () => {
  test("names a progress line, a failure line and the end, and passes a quiet line", () => {
    expect(Watch.classify("compiling 3 crates"))->toEqual(Some("progress: compiling 3 crates"))
    expect(Watch.classify("error[E0425]: cannot find"))->toEqual(
      Some("failure: error[E0425]: cannot find"),
    )
    expect(Watch.classify("exit: 0"))->toEqual(Some("ended: exit: 0"))
    expect(Watch.classify("   some detail"))->toEqual(None)
  })

  test("reports only complete new lines, once", () => {
    let (first, events) = Watch.step(
      Watch.start(~now=0., ~stall),
      ~text="running a\nrunni",
      ~now=1000.,
      ~stall,
    )
    expect(events)->toEqual(["progress: running a"])
    let (_, again) = Watch.step(first, ~text="running a\nrunni", ~now=2000., ~stall)
    expect(again)->toEqual([])
    let (last, done) = Watch.step(
      first,
      ~text="running a\nrunning b\nexit: 1\n",
      ~now=3000.,
      ~stall,
    )
    expect(done)->toEqual(["progress: running b", "ended: exit: 1"])
    expect(last.ended)->toEqual(true)
  })

  test("names a stall once it has not grown for the stall, and again after another", () => {
    let (grown, _) = Watch.step(Watch.start(~now=0., ~stall), ~text="built a\n", ~now=1000., ~stall)
    let (quiet, none) = Watch.step(grown, ~text="built a\n", ~now=30000., ~stall)
    expect(none)->toEqual([])
    let (stalled, told) = Watch.step(quiet, ~text="built a\n", ~now=31000., ~stall)
    expect(told)->toEqual(["stalled: no new line for 30 seconds"])
    let (_, again) = Watch.step(stalled, ~text="built a\n", ~now=60000., ~stall)
    expect(again)->toEqual([])
    let (_, later) = Watch.step(stalled, ~text="built a\n", ~now=61000., ~stall)
    expect(later)->toEqual(["stalled: no new line for 60 seconds"])
  })

  test("stalls on a file that never appears", () => {
    let (_, told) = Watch.step(Watch.start(~now=0., ~stall), ~text="", ~now=30000., ~stall)
    expect(told)->toEqual(["stalled: no new line for 30 seconds"])
  })
})
