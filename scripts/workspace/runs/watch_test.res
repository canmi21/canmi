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

  test("never ends a ledger job by a nested end in its output, even when a read misses it", () => {
    let output = "running tests\n[exited with code 0]\nexit: 0\nmore tests\n"
    let (last, told) = Watch.step(start(), ~text=output, ~now=1000., ~stall, ~ledger=true)
    expect(told)->toEqual([])
    expect(last.ended)->toEqual(false)
    expect(Watch.jobId->RegExp.test("20261103-052754-0184"))->toEqual(true)
    expect(Watch.jobId->RegExp.test("/tmp/out.log"))->toEqual(false)
  })

  test("a count of no failures is no failure, and any other count is", () => {
    ["12 passed, 0 failed", "0 errors"]->Array.forEach(
      line => expect((line, Watch.failure->RegExp.test(line)))->toEqual((line, false)),
    )
    ["1 failed", "10 failed", "error: x"]->Array.forEach(
      line => expect((line, Watch.failure->RegExp.test(line)))->toEqual((line, true)),
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

  test("reports a stall once per watch even after growth", () => {
    let (grown, _) = step(start(), "built a\n", 1000.)
    let (quiet, none) = step(grown, "built a\n", 30000.)
    expect(none)->toEqual([])
    let (stalled, told) = step(quiet, "built a\n", 31000.)
    expect(told)->toEqual(["stalled: no new line for 30 seconds"])
    let (_, later) = step(stalled, "built a\n", 90000.)
    expect(later)->toEqual([])
    let (partial, _) = step(stalled, "built a\nx", 91000.)
    let (_, restarted) = step(partial, "built a\nx", 121000.)
    // Growth must not rearm the notice promised once in docs/agents/runs.md.
    expect(restarted)->toEqual([])
  })

  test("exempts a quiet ledger job from stalls", () => {
    let (_, events) = Watch.step(
      start(),
      ~text="",
      ~now=30000.,
      ~stall,
      ~job=Some({...job, quiet: true}),
      ~alive=_ => true,
    )
    // Quiet is the ledger's explicit permission to go silent.
    expect(events)->toEqual([])
  })

  test("does not mistake a missed read for growth on recovery", () => {
    let (first, _) = step(start(), "built a\n", 1000.)
    let (missing, _) = Watch.step(first, ~now=20000., ~stall)
    let (_, events) = step(missing, "built a\n", 31000.)
    // An unchanged file must still stall after a transient read miss.
    expect(events)->toEqual(["stalled: no new line for 30 seconds"])
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
    let (missing, _) = Watch.step(first, ~now=2000., ~stall, ~job=Some(job), ~alive=_ => true)
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

@module("vitest") @scope("vi") external fakeTimers: unit => unit = "useFakeTimers"
@module("vitest") @scope("vi") external realTimers: unit => unit = "useRealTimers"
@module("vitest") @scope("vi") external advance: int => unit = "advanceTimersByTime"
@module("vitest") @scope("vi") external setTime: float => unit = "setSystemTime"
@module("vitest") @scope("vi") external restoreMocks: unit => unit = "restoreAllMocks"
type mock<'a>
@module("vitest") @scope("vi") external spy: ('a, string) => mock<'b> = "spyOn"
@send external implement: (mock<'a>, 'a) => unit = "mockImplementation"
type target
@val external process: target = "process"
@val external console: target = "console"

describe("the watch resolving its target", () => {
  let home = Testing.temporaryRoot("watch-")
  let oldHome = ref(None)
  let exits = ref([])
  let lines = ref([])
  beforeEach(() => {
    oldHome := Node.env->Dict.get("RUNS_HOME")
    Node.env->Dict.set("RUNS_HOME", home.contents)
    exits := []
    lines := []
    fakeTimers()
    setTime(0.)
    spy(process, "exit")->implement(code => exits.contents->Array.push(code))
    spy(console, "log")->implement(line => lines.contents->Array.push(line))
  })
  afterEach(() => {
    restoreMocks()
    realTimers()
    switch oldHome.contents {
    | Some(value) => Node.env->Dict.set("RUNS_HOME", value)
    | None => Node.env->Dict.delete("RUNS_HOME")
    }
  })

  test("finds a start written after the watch and reads the ledger end", () => {
    Watch.main(["late"])->ignore
    advance(1000)
    Ledger.started({...job, id: "late", pid: 0, output: Ledger.outputOf("late")})
    advance(1000)
    Ledger.ended(~id="late", ~status=0, ~at=2500.)
    advance(1000)
    // The supervisor writes its start after job start returns the id.
    expect(exits.contents)->toEqual([0])
    expect(lines.contents)->toEqual([
      "ended: status 0, 2.5 s, 0 failure lines; mise run //:job read late",
    ])
    expect(Ledger.find("late")->Option.mapOr(false, Ledger.wasRead))->toEqual(true)
  })

  test("resolves an output path when its ledger start arrives later", () => {
    let output = Ledger.outputOf("path")
    Node.mkdirAll(Ledger.outputs())
    Node.writeFileSync(output, "")
    Watch.main([output])->ignore
    advance(1000)
    Ledger.started({...job, id: "path", pid: 0, output, quiet: true})
    advance(30000)
    expect(lines.contents)->toEqual([])
    Ledger.ended(~id="path", ~status=2, ~at=31500.)
    advance(1000)
    expect(exits.contents)->toEqual([0])
    expect(lines.contents)->toEqual([
      "ended: status 2, 31.5 s, 0 failure lines; mise run //:job read path",
    ])
  })

  test("keeps the last readable size when a bare file disappears briefly", () => {
    let file = Node.join([home.contents, "bare.log"])
    Node.writeFileSync(file, "built a\n")
    Watch.main([file])->ignore
    advance(1000)
    Node.rmSync(file, {recursive: false, force: true})
    advance(19000)
    Node.writeFileSync(file, "built a\n")
    advance(11000)
    // The read catch must preserve the growth clock instead of supplying empty text.
    expect(lines.contents)->toEqual(["stalled: no new line for 30 seconds"])
    expect(exits.contents)->toEqual([])
    Node.writeFileSync(file, "built a\nexit: 0\n")
    advance(1000)
    expect(exits.contents)->toEqual([0])
  })

  test("allows a bare file to appear before the missing target deadline", () => {
    let file = Node.join([home.contents, "later.log"])
    Watch.main([file])->ignore
    advance(29000)
    Node.writeFileSync(file, "exit: 0\n")
    advance(1000)
    expect(lines.contents)->toEqual(["ended: exit: 0"])
    expect(exits.contents)->toEqual([0])
  })

  test("fails once at the stall deadline if neither a job nor a file appears", () => {
    Watch.main(["missing"])->ignore
    advance(30000)
    // A typo or a supervisor lost before its start cannot ever report an end.
    expect(exits.contents)->toEqual([1])
    expect(lines.contents)->toEqual(["missing: no job in the ledger and no file for missing"])
    advance(30000)
    expect(exits.contents)->toEqual([1])
  })
})
