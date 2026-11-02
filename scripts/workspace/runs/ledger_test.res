open Testing

let start = (id, ~at=0., ~command="c") =>
  `{"kind":"start","id":"${id}","by":"b","command":"${command}","cwd":"/","pid":1,"at":${Float.toString(
      at,
    )},"output":"/o","quiet":false}`
let end_ = (id, ~at, ~status=0) =>
  `{"kind":"end","id":"${id}","status":${Int.toString(status)},"at":${Float.toString(at)}}`

describe("the ledger", () => {
  test("folds a start, an end and a read, passing over an unreadable line", () => {
    let jobs = Ledger.fold(
      [
        start("a"),
        "not json",
        end_("a", ~at=5000.),
        `{"kind":"read","id":"a","at":6000}`,
      ]->Array.join("\n"),
    )
    expect(jobs->Array.length)->toEqual(1)
    let job = jobs->Array.getUnsafe(0)
    expect(job.status)->toEqual(Some(0))
    expect(Ledger.seconds(job))->toEqual(Some(5.))
    expect(Ledger.wasRead(job))->toEqual(true)
  })

  test("a read before the end is not a read of the result", () => {
    let job =
      Ledger.fold(
        [start("a"), `{"kind":"read","id":"a","at":1}`, end_("a", ~at=5.)]->Array.join("\n"),
      )->Array.getUnsafe(0)
    expect(Ledger.wasRead(job))->toEqual(false)
  })

  test("takes the limit from the job, else twice the p95 once there is history", () => {
    let runs = n =>
      Array.fromInitializer(
        ~length=n,
        at => [start(`r${Int.toString(at)}`), end_(`r${Int.toString(at)}`, ~at=10000.)],
      )
      ->Array.flat
      ->Array.join("\n")
    let live = Ledger.fold(start("live"))->Array.getUnsafe(0)
    expect(Ledger.limitOf(live, ~all=Ledger.fold(runs(4))))->toEqual(None)
    expect(Ledger.limitOf(live, ~all=Ledger.fold(runs(5))))->toEqual(Some(20.))
    expect(Ledger.limitOf({...live, limit: Some(3.)}, ~all=[]))->toEqual(Some(3.))
  })

  test("sums the table by command, the bottleneck first", () => {
    let rows = Ledger.table(
      Ledger.fold(
        [
          start("a", ~command="x"),
          end_("a", ~at=1000.),
          start("b", ~command="y"),
          end_("b", ~at=9000.),
          start("c", ~command="x"),
          end_("c", ~at=1000.),
        ]->Array.join("\n"),
      ),
    )
    expect(rows->Array.map(row => (row.command, row.count, row.total)))->toEqual([
      ("y", 1, 9.),
      ("x", 2, 2.),
    ])
  })
})

describe("the job's command", () => {
  test("is one word as written and several quoted", () => {
    expect(Job.lineOf(["a && b"]))->toEqual("a && b")
    expect(Job.lineOf(["mise", "run", "x y"]))->toEqual("mise run 'x y'")
  })

  test("takes the flags before it, with or without the dashes", () => {
    let given = Job.parseGiven(
      ["--by", "me", "--limit", "9", "--quiet", "--", "ls", "--by"],
      ~defaultBy="d",
    )
    expect((given.by, given.limit, given.quiet, given.command))->toEqual((
      "me",
      Some(9.),
      true,
      ["ls", "--by"],
    ))
    expect(Job.parseGiven(["ls", "-a"], ~defaultBy="d").command)->toEqual(["ls", "-a"])
  })

  test("reads its id from the output path alone", () => {
    expect(Ledger.idOfOutput(Ledger.outputOf("20261102-000000-abcd")))->toEqual(
      Some("20261102-000000-abcd"),
    )
    expect(Ledger.idOfOutput("/elsewhere/a.log"))->toEqual(None)
  })
})

describe("stopping a job", () => {
  let job: Ledger.job = {
    id: "a",
    by: "seat-a",
    session: "one",
    command: "c",
    cwd: "/",
    pid: 1,
    started: 0.,
    output: "/o",
    limit: None,
    quiet: false,
    ended: None,
    status: None,
    read: None,
  }

  test("is its starter's alone, and the refusal says whose it is", () => {
    expect(Job.notOwn(job, ~session="one", ~by="seat-a"))->toEqual(None)
    expect(Job.notOwn(job, ~session="one", ~by="seat-b"))->toEqual(Some("seat-a in session one"))
    expect(Job.notOwn(job, ~session="two", ~by="seat-a"))->toEqual(Some("seat-a in session one"))
    expect(Job.notOwn({...job, session: ""}, ~session="", ~by="other"))->toEqual(Some("seat-a"))
  })
})
